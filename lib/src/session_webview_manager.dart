import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../platform_interface.dart';
import '../webview_flutter.dart';

/// Captured web storage for one origin.
class OriginStorageSnapshot {
  /// Creates a new [OriginStorageSnapshot].
  const OriginStorageSnapshot({
    required this.localStorage,
    required this.sessionStorage,
  });

  /// Persisted localStorage key-value pairs.
  final Map<String, String> localStorage;

  /// Persisted sessionStorage key-value pairs.
  final Map<String, String> sessionStorage;

  /// Serializes this origin storage snapshot.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'localStorage': localStorage,
      'sessionStorage': sessionStorage,
    };
  }

  /// Deserializes this origin storage snapshot.
  factory OriginStorageSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return OriginStorageSnapshot(
      localStorage: SessionSnapshot._stringMap(map['localStorage']),
      sessionStorage: SessionSnapshot._stringMap(map['sessionStorage']),
    );
  }
}

/// Captures the current session binding from the active page.
typedef SessionBindingCapture = Future<String?> Function(
  String sessionKey,
  WebViewController controller,
);

/// Validates whether the restored page is bound to the expected session.
typedef SessionBindingValidator = bool Function(
  String sessionKey,
  String? restoredBinding,
);

/// Persists [SessionSnapshot] objects for later recovery.
///
/// The store keeps the recoverable session layer only: cookies, storage,
/// lastUrl, and an optional business-side session binding marker.
/// It does not persist an in-memory WebView instance.
abstract class SessionWebViewSessionStore {
  /// Reads a snapshot by [sessionKey].
  Future<SessionSnapshot?> read(String sessionKey);

  /// Writes a snapshot.
  Future<void> write(SessionSnapshot snapshot);

  /// Deletes a snapshot.
  Future<void> delete(String sessionKey);
}

/// Optional store capability for remembering which session owns the shared
/// platform WebView state across process restarts.
///
/// Android keeps cookies and DOM storage process-wide *and* on disk, so after a
/// process kill the platform store still holds the last session's data — it is
/// more current than any snapshot, because a kill skips the capture that would
/// have written one. Without this capability the manager cannot tell "fresh
/// process, same session as before" from "someone else's leftovers", so it
/// conservatively resets, destroying exactly the state that survived.
///
/// Implement this and the two cases become distinguishable: reopening the owning
/// session after a kill reuses the platform store untouched, which is also what
/// a normal exit does. Ownership is recorded when a session *acquires* the
/// store, never on release, so a kill cannot skip the write.
abstract class SessionWebViewSharedStateOwnerStore
    implements SessionWebViewSessionStore {
  /// Reads the session key that last owned the shared platform state.
  Future<String?> readSharedStateOwner();

  /// Records [sessionKey] as the owner of the shared platform state.
  Future<void> writeSharedStateOwner(String? sessionKey);
}

/// Optional store capability for clearing every persisted snapshot.
///
/// Implement this when using a persistent store and logout should remove all
/// recoverable WebView sessions, including keys that are not currently resident
/// in [SessionWebViewManager].
abstract class SessionWebViewClearableSessionStore
    implements SessionWebViewSessionStore {
  /// Deletes every snapshot in the store.
  Future<void> clear();
}

/// In-memory [SessionWebViewSessionStore] implementation.
class MemorySessionWebViewSessionStore
    implements SessionWebViewClearableSessionStore {
  final Map<String, SessionSnapshot> _snapshots = <String, SessionSnapshot>{};

  @override
  Future<void> clear() async {
    _snapshots.clear();
  }

  @override
  Future<void> delete(String sessionKey) async {
    _snapshots.remove(sessionKey);
  }

  @override
  Future<SessionSnapshot?> read(String sessionKey) async {
    return _snapshots[sessionKey];
  }

  @override
  Future<void> write(SessionSnapshot snapshot) async {
    _snapshots[snapshot.sessionKey] = snapshot;
  }
}

/// File-backed [SessionWebViewSessionStore] implementation.
///
/// Use this when session snapshots need to survive app process restarts.
/// The store writes one JSON file containing snapshots keyed by session key.
class FileSessionWebViewSessionStore
    implements
        SessionWebViewClearableSessionStore,
        SessionWebViewSharedStateOwnerStore {
  /// Creates a file-backed store.
  ///
  /// When [filePath] is omitted, snapshots are stored under
  /// [Directory.systemTemp], which maps to the app-writable temporary/cache area
  /// on mobile platforms.
  FileSessionWebViewSessionStore([String? filePath])
      : filePath = filePath ?? defaultFilePath;

  /// Default JSON snapshot file path.
  static String get defaultFilePath => <String>[
        Directory.systemTemp.path,
        'flutter_webview_pro',
        'session_webview_sessions.json',
      ].join(Platform.pathSeparator);

  /// Absolute path of the JSON snapshot file.
  final String filePath;

  Future<File> get _file async {
    final File file = File(filePath);
    final Directory parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    return file;
  }

  // Kept beside the snapshot file rather than inside it: that JSON is a flat
  // sessionKey -> snapshot map, and a reserved key there could collide with a
  // real session key.
  Future<File> get _ownerFile async {
    await _file;
    return File('$filePath.owner');
  }

  @override
  Future<String?> readSharedStateOwner() async {
    try {
      final File file = await _ownerFile;
      if (!await file.exists()) {
        return null;
      }
      final String content = (await file.readAsString()).trim();
      return content.isEmpty ? null : content;
    } catch (error) {
      debugPrint(
        '[FileSessionWebViewSessionStore] read owner failed error=$error',
      );
      return null;
    }
  }

  @override
  Future<void> writeSharedStateOwner(String? sessionKey) async {
    try {
      final File file = await _ownerFile;
      if (sessionKey == null || sessionKey.isEmpty) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      await file.writeAsString(sessionKey, flush: true);
    } catch (error) {
      debugPrint(
        '[FileSessionWebViewSessionStore] write owner failed error=$error',
      );
    }
  }

  @override
  Future<void> clear() async {
    final File file = await _file;
    if (await file.exists()) {
      await file.delete();
    }
    await writeSharedStateOwner(null);
  }

  @override
  Future<void> delete(String sessionKey) async {
    final Map<String, SessionSnapshot> snapshots = await _readAll();
    snapshots.remove(sessionKey);
    await _writeAll(snapshots);
  }

  @override
  Future<SessionSnapshot?> read(String sessionKey) async {
    return (await _readAll())[sessionKey];
  }

  @override
  Future<void> write(SessionSnapshot snapshot) async {
    final Map<String, SessionSnapshot> snapshots = await _readAll();
    snapshots[snapshot.sessionKey] = snapshot;
    await _writeAll(snapshots);
  }

  Future<Map<String, SessionSnapshot>> _readAll() async {
    final File file = await _file;
    if (!await file.exists()) {
      return <String, SessionSnapshot>{};
    }
    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) {
        return <String, SessionSnapshot>{};
      }
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) {
        return <String, SessionSnapshot>{};
      }
      return decoded.map<String, SessionSnapshot>((dynamic key, dynamic value) {
        return MapEntry<String, SessionSnapshot>(
          key.toString(),
          SessionSnapshot.fromMap(value as Map<dynamic, dynamic>),
        );
      });
    } catch (error) {
      debugPrint(
        '[FileSessionWebViewSessionStore] read failed filePath=$filePath '
        'error=$error',
      );
      return <String, SessionSnapshot>{};
    }
  }

  Future<void> _writeAll(Map<String, SessionSnapshot> snapshots) async {
    final File file = await _file;
    final String content = jsonEncode(
      snapshots.map<String, Map<String, dynamic>>(
        (String key, SessionSnapshot value) =>
            MapEntry<String, Map<String, dynamic>>(key, value.toMap()),
      ),
    );
    await file.writeAsString(content, flush: true);
  }
}

/// Serialized isolated session state.
///
/// A snapshot is sufficient to rebuild a session after the resident
/// WebView has been evicted, but it does not preserve volatile page memory such
/// as live JavaScript variables, pending forms, or transient DOM state.
class SessionSnapshot {
  /// Creates a new [SessionSnapshot].
  const SessionSnapshot({
    required this.sessionKey,
    required this.cookies,
    required this.cookieDomains,
    required this.localStorage,
    required this.sessionStorage,
    this.storageByOrigin = const <String, OriginStorageSnapshot>{},
    this.lastUrl,
    this.sessionBinding,
    required this.updatedAt,
  });

  /// Session identifier.
  final String sessionKey;

  /// Persisted cookies.
  final List<WebViewCookie> cookies;

  /// Cookie domains observed while this session was active.
  final List<String> cookieDomains;

  /// Persisted localStorage key-value pairs.
  final Map<String, String> localStorage;

  /// Persisted sessionStorage key-value pairs.
  final Map<String, String> sessionStorage;

  /// Persisted storage grouped by web origin.
  final Map<String, OriginStorageSnapshot> storageByOrigin;

  /// Last loaded main-frame URL.
  final String? lastUrl;

  /// Business-side binding marker used to validate the restored session.
  final String? sessionBinding;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Serializes this snapshot.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'sessionKey': sessionKey,
      'cookies': cookies.map((WebViewCookie cookie) => cookie.toMap()).toList(),
      'cookieDomains': cookieDomains,
      'localStorage': localStorage,
      'sessionStorage': sessionStorage,
      'storageByOrigin': storageByOrigin.map<String, Map<String, dynamic>>(
        (String origin, OriginStorageSnapshot value) =>
            MapEntry<String, Map<String, dynamic>>(origin, value.toMap()),
      ),
      'lastUrl': lastUrl,
      'sessionBinding': sessionBinding,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  /// Deserializes a snapshot.
  factory SessionSnapshot.fromMap(Map<dynamic, dynamic> map) {
    return SessionSnapshot(
      sessionKey: map['sessionKey'] as String? ?? '',
      cookies: ((map['cookies'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic item) =>
              WebViewCookie.fromMap(item as Map<dynamic, dynamic>))
          .toList(),
      cookieDomains: ((map['cookieDomains'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic item) => item.toString())
          .toList(),
      localStorage: _stringMap(map['localStorage']),
      sessionStorage: _stringMap(map['sessionStorage']),
      storageByOrigin: _storageByOriginMap(map['storageByOrigin']),
      lastUrl: map['lastUrl'] as String?,
      sessionBinding: map['sessionBinding'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] as int? ?? 0,
      ),
    );
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) {
      return <String, String>{};
    }
    return value.map<String, String>((dynamic key, dynamic val) {
      return MapEntry<String, String>(key.toString(), val?.toString() ?? '');
    });
  }

  static Map<String, OriginStorageSnapshot> _storageByOriginMap(
    dynamic value,
  ) {
    if (value is! Map) {
      return <String, OriginStorageSnapshot>{};
    }
    return value.map<String, OriginStorageSnapshot>(
      (dynamic key, dynamic val) {
        if (val is Map) {
          return MapEntry<String, OriginStorageSnapshot>(
            key.toString(),
            OriginStorageSnapshot.fromMap(val),
          );
        }
        return MapEntry<String, OriginStorageSnapshot>(
          key.toString(),
          const OriginStorageSnapshot(
            localStorage: <String, String>{},
            sessionStorage: <String, String>{},
          ),
        );
      },
    );
  }
}

class _SessionRestoreState {
  _SessionRestoreState({
    required this.snapshot,
    required this.targetUrl,
    this.resetBeforeRestore = false,
    this.restoreCookies = true,
    this.restoreLocalStorage = true,
    this.restoreSessionStorage = true,
  });

  final SessionSnapshot snapshot;
  final String targetUrl;
  final bool resetBeforeRestore;
  final bool restoreCookies;
  final bool restoreLocalStorage;
  final bool restoreSessionStorage;
  bool storageRestored = false;
  bool reloadedAfterRestore = false;
  bool validationRetried = false;
  final Set<String> restoredOrigins = <String>{};
}

class _SessionWebViewEntry {
  _SessionWebViewEntry({
    required this.sessionKey,
    required this.initialUrl,
  });

  final String sessionKey;
  String initialUrl;
  WebViewController? controller;
  Key widgetKey = UniqueKey();
  String? lastUrl;
  String? lastOrigin;
  SessionSnapshot? snapshot;
  final LinkedHashSet<String> cookieDomains = LinkedHashSet<String>();
  final LinkedHashSet<String> origins = LinkedHashSet<String>();
  bool resident = false;
  _SessionRestoreState? restoreState;
}

/// Manages a resident pool of session-specific WebView instances.
///
/// The manager keeps recently used sessions resident in memory and evicts the
/// least-recently-used instance once [capacity] is exceeded. Before eviction it
/// captures a [SessionSnapshot], so reopening that session restores cookies,
/// storage, and the last visited URL instead of starting from a blank session.
///
/// Recovery is intentionally two-layered:
/// - Resident instance present: preserves the live page state.
/// - Resident instance evicted: restores the recoverable session state only.
class SessionWebViewManager extends ChangeNotifier {
  /// Creates a new [SessionWebViewManager].
  SessionWebViewManager({
    this.capacity = 3,
    this.restoreLastUrlOnReopen = false,
    this.additionalCookieDomains,
    this.preservedLocalStorageDomains,
    this.ephemeralCookieDomains,
    SessionWebViewSessionStore? sessionStore,
    this.sessionBindingCapture,
    this.sessionBindingValidator,
    @visibleForTesting bool? platformSupportsMultipleResidentWebViews,
  })  : _platformSupportsMultipleResidentWebViews =
            platformSupportsMultipleResidentWebViews,
        sessionStore = sessionStore ?? MemorySessionWebViewSessionStore();

  /// Maximum number of resident WebView instances.
  ///
  /// When the pool is full, the least recently used non-active session is evicted.
  final int capacity;

  /// Whether reopening a disposed session should navigate to the last captured
  /// URL instead of the newly provided `initialUrl`.
  ///
  /// When false, cookies and web storage are still restored, but the reopened
  /// WebView starts from the caller-provided entry URL.
  final bool restoreLastUrlOnReopen;

  /// Additional cookie domains that should be captured/restored for every
  /// session in addition to the host parsed from `initialUrl`.
  ///
  /// Most integrations can leave this unset and rely on the `initialUrl` host.
  final List<String>? additionalCookieDomains;

  /// Domains whose origin-scoped local storage must survive shared-state resets.
  ///
  /// Cookies are still cleared for these domains. This is useful when several
  /// hosts share a registrable-domain cookie, while only one host's local storage
  /// belongs to a persistent session.
  final List<String>? preservedLocalStorageDomains;

  /// Domains whose cookies and web storage must never enter a [SessionSnapshot].
  ///
  /// Use this for third-party auth relays (OAuth hand-off hosts and the like):
  /// their state is short-lived and process-wide, so persisting it would silently
  /// re-authenticate the next visit — even after [disposeSession] cleared the
  /// platform WebView store — and would resurrect a stale binding after the app
  /// process is killed mid-flow.
  ///
  /// Domains listed here are also stripped from any snapshot already on disk when
  /// [disposeSession] clears them from the platform store.
  final List<String>? ephemeralCookieDomains;

  /// Snapshot persistence store.
  final SessionWebViewSessionStore sessionStore;

  /// Optional callback that reads the current business-side session binding.
  ///
  /// Use this to record a session identifier from JavaScript, URL state, or other
  /// page-level signals so restoration can be validated after reload.
  final SessionBindingCapture? sessionBindingCapture;

  /// Optional callback that validates the restored page binding for [sessionKey].
  ///
  /// When validation fails the manager retries one restore pass before giving
  /// up and leaving the caller to handle re-authentication or custom fallback.
  final SessionBindingValidator? sessionBindingValidator;

  final bool? _platformSupportsMultipleResidentWebViews;

  final CookieManager _cookieManager = CookieManager();
  final Map<String, _SessionWebViewEntry> _entries =
      <String, _SessionWebViewEntry>{};
  final LinkedHashSet<String> _lru = LinkedHashSet<String>();
  Future<void> _serial = Future<void>.value();
  String? _currentSessionKey;
  String? _sharedSessionStateKey;
  bool _sharedStateOwnerLoaded = false;

  /// Current active session key.
  String? get currentSessionKey => _currentSessionKey;

  /// Records who owns the shared platform state, on disk as well as in memory.
  ///
  /// Called when a session *acquires* the store, so a process kill cannot skip
  /// it. Restoring the value on the next launch is what lets the manager tell
  /// "fresh process, same session" from "another session's leftovers".
  void _setSharedStateOwner(String? sessionKey) {
    _sharedSessionStateKey = sessionKey;
    _sharedStateOwnerLoaded = true;
    final SessionWebViewSessionStore store = sessionStore;
    if (store is SessionWebViewSharedStateOwnerStore) {
      _ignore(store.writeSharedStateOwner(sessionKey));
    }
  }

  /// Loads the persisted owner once per process, before the first reset decision.
  Future<void> _ensureSharedStateOwnerLoaded() async {
    if (_sharedStateOwnerLoaded) {
      return;
    }
    _sharedStateOwnerLoaded = true;
    final SessionWebViewSessionStore store = sessionStore;
    if (store is! SessionWebViewSharedStateOwnerStore) {
      return;
    }
    try {
      _sharedSessionStateKey ??= await store.readSharedStateOwner();
    } catch (e) {
      debugPrint('[SessionWebViewManager] read shared state owner failed: $e');
    }
  }

  /// Resident session keys in the pool.
  ///
  /// Resident entries still have a live WebView instance and can preserve
  /// transient in-page state across session switches.
  List<String> get residentSessionKeys => _entries.values
      .where((_SessionWebViewEntry entry) => entry.resident)
      .map((_SessionWebViewEntry entry) => entry.sessionKey)
      .toList(growable: false);

  Iterable<_SessionWebViewEntry> get _residentEntries =>
      _entries.values.where((_SessionWebViewEntry entry) => entry.resident);

  bool get _supportsMultipleResidentWebViews =>
      _platformSupportsMultipleResidentWebViews ?? Platform.isIOS;

  /// Switches the active view to [sessionKey].
  ///
  /// If the session is already resident its existing instance is reused.
  /// Otherwise the manager creates a new instance and restores the most recent
  /// [SessionSnapshot], if one exists.
  ///
  /// Android WebView keeps cookies and web storage in process-wide stores, so
  /// switching to another session drops the previous resident instance after
  /// capturing a snapshot. iOS keeps per-session website data stores and can
  /// keep multiple resident instances alive. On Android, a first session with no
  /// snapshot starts from a clean shared WebView store instead of adopting
  /// untracked process state left by a previous manager instance.
  Future<void> switchToSession(
    String sessionKey, {
    required String initialUrl,
  }) {
    return _enqueue(() => _switchToSession(sessionKey, initialUrl: initialUrl));
  }

  /// Prepares a session WebView without making it active.
  ///
  /// This reserves a resident slot and primes restoration for [sessionKey], but it
  /// does not update [currentSessionKey].
  ///
  /// On Android this is a no-op for non-current sessions because background
  /// WebViews would mutate the same process-wide cookie and storage state used
  /// by the visible session.
  Future<void> warmUpSession(
    String sessionKey, {
    required String initialUrl,
  }) {
    return _enqueue(() async {
      if (!_supportsMultipleResidentWebViews &&
          _currentSessionKey != sessionKey) {
        return null;
      }
      await _ensureResident(sessionKey, initialUrl: initialUrl);
      return null;
    });
  }

  /// Captures and persists a session snapshot.
  ///
  /// The snapshot can later be used to rebuild the session after LRU eviction
  /// or process death.
  Future<SessionSnapshot?> captureSession(String sessionKey) {
    return _enqueue<SessionSnapshot?>(() => _captureSnapshot(sessionKey));
  }

  /// Clears the persisted snapshot and evicts the resident entry if present.
  Future<void> clearSession(String sessionKey) {
    return _enqueue(() async {
      _entries.remove(sessionKey);
      _lru.remove(sessionKey);
      if (_currentSessionKey == sessionKey) {
        _currentSessionKey = null;
      }
      if (_sharedSessionStateKey == sessionKey) {
        _setSharedStateOwner(null);
      }
      await sessionStore.delete(sessionKey);
      notifyListeners();
      return null;
    });
  }

  /// Clears every session known to the manager.
  ///
  /// Use this on app-level logout. It removes resident entries, persisted
  /// snapshots, and optionally clears global platform WebView data so the next
  /// entry must authenticate again.
  ///
  /// If [sessionStore] does not implement [SessionWebViewClearableSessionStore],
  /// only snapshots for currently known entries can be deleted.
  Future<void> clearAllSessions({
    bool clearPlatformData = true,
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) {
    return _enqueue(() async {
      final List<String> sessionKeys = _entries.keys.toList(growable: false);

      if (clearPlatformData) {
        await _cookieManager.clearWebsiteData(
          includeCookies: includeCookies,
          includeLocalStorage: includeLocalStorage,
          includeCache: includeCache,
        );
      }

      final SessionWebViewSessionStore store = sessionStore;
      if (store is SessionWebViewClearableSessionStore) {
        await store.clear();
      } else {
        for (final String sessionKey in sessionKeys) {
          await store.delete(sessionKey);
        }
      }

      _entries.clear();
      _lru.clear();
      _currentSessionKey = null;
      _setSharedStateOwner(null);
      notifyListeners();
      return null;
    });
  }

  /// Disposes the resident instance while keeping the persisted snapshot.
  ///
  /// This intentionally drops the live page state but retains the recoverable
  /// session layer already captured by [captureSession] or page-finished hooks.
  ///
  /// When [clearCookieDomainsOnClose] is non-empty, cookies, local storage, and
  /// cache for those domains are cleared from the shared platform WebView store
  /// on close. This is opt-in per call: callers should pass domains that are
  /// typically third-party auth relays whose data is not session-scoped (e.g.
  /// process-wide on Android), so leaving it behind risks leaking into the next
  /// session that touches the same domain.
  Future<void> disposeSession(
    String sessionKey, {
    List<String>? clearCookieDomainsOnClose,
  }) {
    return _enqueue(() async {
      final _SessionWebViewEntry? entry = _entries[sessionKey];
      if (entry == null) {
        return;
      }
      _dropResidentEntry(sessionKey, clearCurrent: true);
      final List<String>? domains = clearCookieDomainsOnClose
          ?.where((String value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (domains != null && domains.isNotEmpty) {
        try {
          await _clearWebsiteDataForDomains(domains);
        } catch (e) {
          debugPrint(
              '[SessionWebViewManager] clearWebsiteDataForDomains failed: $e');
        }
      }
      // Clearing the platform store is not enough: a snapshot written earlier in
      // this page's life (or by a previous app version) would restore the very
      // cookies that were just cleared.
      await _purgeEphemeralStateFromStore(sessionKey);
      notifyListeners();
      return null;
    });
  }

  /// Disposes [sessionKey] and forgets it entirely: the resident instance, the
  /// in-memory entry, and the persisted snapshot.
  ///
  /// Use this for caller-keyed one-shot sessions — a fresh, never-repeating key
  /// per visit. [disposeSession] deliberately keeps the snapshot, so a unique
  /// key would leave one unreachable snapshot behind on every visit and grow the
  /// session store without bound.
  Future<void> forgetSession(
    String sessionKey, {
    List<String>? clearCookieDomainsOnClose,
  }) {
    return _enqueue(() async {
      final _SessionWebViewEntry? entry = _entries[sessionKey];
      // Whatever this session actually visited must go too. A one-shot session
      // exists precisely so its third-party login does not outlive it, and the
      // hosts it touched are known only from its own navigation — a caller-side
      // static list cannot name them.
      final Set<String> targets = <String>{...?entry?.cookieDomains};
      _dropResidentEntry(sessionKey, clearCurrent: true);
      _entries.remove(sessionKey);
      if (_sharedSessionStateKey == sessionKey) {
        // The platform store no longer belongs to anyone; force the next session
        // to reset it instead of inheriting this one's leftovers.
        _setSharedStateOwner(null);
      }
      targets.addAll(clearCookieDomainsOnClose ?? const <String>[]);
      final List<String> domains = targets
          .where((String value) => value.trim().isNotEmpty)
          .toList(growable: false);
      if (domains.isNotEmpty) {
        try {
          await _clearWebsiteDataForDomains(domains);
        } catch (e) {
          debugPrint(
              '[SessionWebViewManager] clearWebsiteDataForDomains failed: $e');
        }
      }
      try {
        await sessionStore.delete(sessionKey);
      } catch (e) {
        debugPrint('[SessionWebViewManager] delete snapshot failed: $e');
      }
      notifyListeners();
      return null;
    });
  }

  /// Marks resident WebView instances as detached without deleting snapshots.
  ///
  /// This is used when the widget tree containing the platform views is
  /// disposed. At that point the live WebViews are gone, but cookies and
  /// origin-scoped storage may still exist in the platform WebView store.
  void detachResidentWebViews(
    Iterable<String> sessionKeys, {
    bool notify = true,
  }) {
    bool changed = false;
    for (final String sessionKey in sessionKeys) {
      final _SessionWebViewEntry? entry = _entries[sessionKey];
      if (entry == null || !entry.resident) {
        continue;
      }
      _dropResidentEntry(sessionKey, clearCurrent: true);
      changed = true;
    }
    if (changed && notify) {
      notifyListeners();
    }
  }

  /// Loads the latest snapshot from the backing store.
  ///
  /// This does not create or attach a resident WebView instance by itself.
  Future<SessionSnapshot?> restoreSession(String sessionKey) async {
    final SessionSnapshot? snapshot = await sessionStore.read(sessionKey);
    if (snapshot != null) {
      final _SessionWebViewEntry entry =
          _entryFor(sessionKey, snapshot.lastUrl ?? '');
      entry.snapshot = snapshot;
    }
    return snapshot;
  }

  /// Builds the WebView widget for a resident session entry.
  ///
  /// Call this through [SessionWebViewSwitcher] in normal usage so only the
  /// active resident instance is visible while inactive resident instances stay
  /// alive offstage.
  WebView buildWebView({
    required String sessionKey,
    required JavascriptMode javascriptMode,
    WebViewCreatedCallback? onWebViewCreated,
    Set<JavascriptChannel>? javascriptChannels,
    NavigationDelegate? navigationDelegate,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
    PageStartedCallback? onPageStarted,
    PageFinishedCallback? onPageFinished,
    PageLoadingCallback? onProgress,
    WebResourceErrorCallback? onWebResourceError,
    bool debuggingEnabled = false,
    bool gestureNavigationEnabled = false,
    bool geolocationEnabled = false,
    String? userAgent,
    AutoMediaPlaybackPolicy initialMediaPlaybackPolicy =
        AutoMediaPlaybackPolicy.require_user_action_for_all_media_types,
    bool allowsInlineMediaPlayback = false,
  }) {
    final _SessionWebViewEntry entry = _entries[sessionKey]!;
    return WebView(
      key: entry.widgetKey,
      sessionKey: sessionKey,
      javascriptMode: javascriptMode,
      javascriptChannels: javascriptChannels,
      navigationDelegate: navigationDelegate,
      gestureRecognizers: gestureRecognizers,
      onWebViewCreated: (WebViewController controller) {
        entry.controller = controller;
        onWebViewCreated?.call(controller);
        _ignore(_restoreIfNeeded(entry));
      },
      onPageStarted: (String url) {
        entry.lastUrl = url;
        _recordCookieDomain(entry, url);
        _recordOrigin(entry, url);
        onPageStarted?.call(url);
      },
      onPageFinished: (String url) {
        entry.lastUrl = url;
        _recordCookieDomain(entry, url);
        _recordOrigin(entry, url);
        onPageFinished?.call(url);
        _ignore(_onPageFinished(entry));
      },
      onProgress: onProgress,
      onWebResourceError: onWebResourceError,
      debuggingEnabled: debuggingEnabled,
      gestureNavigationEnabled: gestureNavigationEnabled,
      geolocationEnabled: geolocationEnabled,
      userAgent: userAgent,
      initialMediaPlaybackPolicy: initialMediaPlaybackPolicy,
      allowsInlineMediaPlayback: allowsInlineMediaPlayback,
    );
  }

  /// Returns true when [sessionKey] currently has a live resident WebView.
  bool isResident(String sessionKey) => _entries[sessionKey]?.resident ?? false;

  Future<void> _switchToSession(
    String sessionKey, {
    required String initialUrl,
  }) async {
    final String? previousSessionKey = _currentSessionKey;
    if (previousSessionKey != null && previousSessionKey != sessionKey) {
      await _captureSnapshot(previousSessionKey);
      if (!_supportsMultipleResidentWebViews) {
        _dropResidentEntry(previousSessionKey);
      }
    }
    await _ensureResident(sessionKey, initialUrl: initialUrl);
    _currentSessionKey = sessionKey;
    _touch(sessionKey);
    notifyListeners();
  }

  Future<void> _ensureResident(
    String sessionKey, {
    required String initialUrl,
  }) async {
    // Must happen before any resetBeforeRestore decision: on a fresh process the
    // in-memory owner is null, which would read as "someone else's leftovers"
    // and wipe the platform state that survived a process kill.
    await _ensureSharedStateOwnerLoaded();
    final _SessionWebViewEntry entry = _entryFor(sessionKey, initialUrl);
    entry.initialUrl = initialUrl;
    if (entry.snapshot == null) {
      entry.snapshot = await sessionStore.read(sessionKey);
      if (entry.snapshot != null) {
        entry.cookieDomains
          ..clear()
          ..addAll(entry.snapshot!.cookieDomains);
        entry.origins
          ..clear()
          ..addAll(entry.snapshot!.storageByOrigin.keys);
      }
    }
    // Reusing the live instance is only safe when the shared platform store is
    // still ours. On Android cookies and DOM storage are process-wide, so another
    // session closing underneath us can clear the domains this page depends on
    // while its WebView stays perfectly alive — resident does not imply intact.
    // Falling through rebuilds the instance and arms the reset/restore path.
    if (entry.resident &&
        entry.controller != null &&
        (_supportsMultipleResidentWebViews ||
            _sharedSessionStateKey == sessionKey)) {
      return;
    }
    await _evictIfNeeded(protectedSessionKey: sessionKey);
    entry.resident = true;
    entry.controller = null;
    entry.widgetKey = UniqueKey();
    if (entry.snapshot != null) {
      final bool sharedStateMatches = _sharedSessionStateKey == sessionKey;
      entry.restoreState = _SessionRestoreState(
        snapshot: entry.snapshot!,
        targetUrl: restoreLastUrlOnReopen
            ? (entry.snapshot!.lastUrl ?? initialUrl)
            : initialUrl,
        resetBeforeRestore: !sharedStateMatches,
        restoreCookies: !sharedStateMatches || Platform.isIOS,
        restoreLocalStorage: true,
        restoreSessionStorage: true,
      );
    } else {
      entry.restoreState = null;
    }
  }

  Future<void> _evictIfNeeded({String? protectedSessionKey}) async {
    while (_residentEntries.length >= capacity) {
      final String? candidate = _lru.firstWhere(
        (String sessionKey) =>
            sessionKey != protectedSessionKey &&
            sessionKey != _currentSessionKey,
        orElse: () => '',
      );
      if (candidate == null || candidate.isEmpty) {
        return;
      }
      await _captureSnapshot(candidate);
      final _SessionWebViewEntry? entry = _entries[candidate];
      if (entry == null) {
        _lru.remove(candidate);
        continue;
      }
      _dropResidentEntry(candidate);
    }
  }

  void _dropResidentEntry(String sessionKey, {bool clearCurrent = false}) {
    final _SessionWebViewEntry? entry = _entries[sessionKey];
    if (entry == null) {
      _lru.remove(sessionKey);
      return;
    }
    entry.resident = false;
    entry.controller = null;
    entry.restoreState = null;
    entry.widgetKey = UniqueKey();
    _lru.remove(sessionKey);
    if (clearCurrent && _currentSessionKey == sessionKey) {
      _currentSessionKey = null;
    }
  }

  Future<SessionSnapshot?> _captureSnapshot(String sessionKey) async {
    final _SessionWebViewEntry? entry = _entries[sessionKey];
    final WebViewController? controller = entry?.controller;
    if (entry == null || controller == null) {
      return entry?.snapshot ?? await sessionStore.read(sessionKey);
    }

    final SessionSnapshot? previousSnapshot =
        entry.snapshot ?? await sessionStore.read(sessionKey);
    final List<String> cookieDomains = _cookieDomainsForEntry(entry);
    final List<WebViewCookie> capturedCookies =
        await _capturePart<List<WebViewCookie>>(
      sessionKey: sessionKey,
      label: 'cookies',
      fallback: previousSnapshot?.cookies ?? <WebViewCookie>[],
      action: () => Platform.isIOS
          ? _cookieManager.getCookiesForSession(sessionKey)
          : _cookieManager.getCookiesForDomains(cookieDomains),
    );
    // Auth-relay cookies are cleared from the platform store on close; keeping
    // them in the snapshot would restore the login the next time round.
    final List<WebViewCookie> cookies = capturedCookies
        .where((WebViewCookie cookie) => !_isEphemeralHost(cookie.domain))
        .toList(growable: false);
    final Map<String, String> localStorage =
        await _capturePart<Map<String, String>>(
      sessionKey: sessionKey,
      label: 'localStorage',
      fallback: previousSnapshot?.localStorage ?? <String, String>{},
      action: controller.captureLocalStorage,
    );
    final Map<String, String> sessionStorage =
        await _capturePart<Map<String, String>>(
      sessionKey: sessionKey,
      label: 'sessionStorage',
      fallback: previousSnapshot?.sessionStorage ?? <String, String>{},
      action: controller.captureSessionStorage,
    );
    final String? currentUrl = await _capturePart<String?>(
      sessionKey: sessionKey,
      label: 'currentUrl',
      fallback: null,
      action: controller.currentUrl,
    );
    final String? currentOrigin =
        _originForUrl(currentUrl ?? entry.lastUrl ?? entry.initialUrl);
    final bool currentOriginIsEphemeral = _isEphemeralOrigin(currentOrigin);
    final Map<String, OriginStorageSnapshot> storageByOrigin =
        <String, OriginStorageSnapshot>{
      if (previousSnapshot != null)
        for (final MapEntry<String, OriginStorageSnapshot> origin
            in previousSnapshot.storageByOrigin.entries)
          if (!_isEphemeralOrigin(origin.key)) origin.key: origin.value,
    };
    if (storageByOrigin.isEmpty &&
        previousSnapshot != null &&
        (previousSnapshot.localStorage.isNotEmpty ||
            previousSnapshot.sessionStorage.isNotEmpty)) {
      final String? previousOrigin = _originForUrl(previousSnapshot.lastUrl);
      if (previousOrigin != null) {
        storageByOrigin[previousOrigin] = OriginStorageSnapshot(
          localStorage: previousSnapshot.localStorage,
          sessionStorage: previousSnapshot.sessionStorage,
        );
      }
    }
    if (currentOrigin != null && !currentOriginIsEphemeral) {
      storageByOrigin[currentOrigin] = OriginStorageSnapshot(
        localStorage: localStorage,
        sessionStorage: sessionStorage,
      );
      entry.origins.add(currentOrigin);
    }
    final String? binding = sessionBindingCapture == null
        ? previousSnapshot?.sessionBinding
        : await _capturePart<String?>(
            sessionKey: sessionKey,
            label: 'sessionBinding',
            fallback: previousSnapshot?.sessionBinding,
            action: () => sessionBindingCapture!(sessionKey, controller),
          );

    // Capturing while the auth relay is on screen must not leave the relay as
    // the snapshot's origin, or reopening would resume the hand-off half-done.
    final String? resolvedLastUrl = currentUrl ??
        entry.lastUrl ??
        previousSnapshot?.lastUrl ??
        entry.initialUrl;
    final SessionSnapshot snapshot = SessionSnapshot(
      sessionKey: sessionKey,
      cookies: cookies,
      cookieDomains: cookieDomains
          .where((String domain) => !_isEphemeralHost(domain))
          .toList(growable: false),
      localStorage:
          currentOriginIsEphemeral ? <String, String>{} : localStorage,
      sessionStorage:
          currentOriginIsEphemeral ? <String, String>{} : sessionStorage,
      storageByOrigin: storageByOrigin,
      lastUrl: _isEphemeralOrigin(resolvedLastUrl)
          ? entry.initialUrl
          : resolvedLastUrl,
      sessionBinding: binding,
      updatedAt: DateTime.now(),
    );
    entry.snapshot = snapshot;
    await sessionStore.write(snapshot);
    return snapshot;
  }

  Future<T> _capturePart<T>({
    required String sessionKey,
    required String label,
    required T fallback,
    required Future<T> Function() action,
  }) async {
    try {
      return await action();
    } catch (error) {
      debugPrint(
        '[SessionWebViewManager] capture $label failed '
        'sessionKey=$sessionKey error=$error',
      );
      return fallback;
    }
  }

  void _ignore(Future<void> future) {}

  Future<void> _restoreIfNeeded(_SessionWebViewEntry entry) async {
    try {
      final WebViewController? controller = entry.controller;
      if (controller == null) {
        return;
      }
      final _SessionRestoreState? restoreState = entry.restoreState;
      if (restoreState != null) {
        if (restoreState.resetBeforeRestore) {
          // Only wipe DOM storage when the snapshot can put it back. A fresh
          // process always takes this branch, and after a process kill the
          // snapshot on disk predates the login — no capture ever ran. Clearing
          // then would discard the only surviving copy of the H5 token, and the
          // first page load would fail auth. Cookies are cleared either way,
          // since the snapshot always carries those.
          await _resetSharedSessionState(
            entry,
            controller,
            includeLocalStorage:
                _snapshotHasStoredStorage(restoreState.snapshot),
          );
        }
        if (restoreState.restoreCookies) {
          // Cookies are restored before the initial navigation so server-side auth
          // can see the recovered session on the first request.
          if (Platform.isIOS) {
            await _cookieManager.setCookiesForSession(
              entry.sessionKey,
              restoreState.snapshot.cookies,
            );
          } else {
            await _cookieManager.setCookies(restoreState.snapshot.cookies);
          }
        }
        _setSharedStateOwner(entry.sessionKey);
        await controller.loadUrl(restoreState.targetUrl);
        return;
      }
      final bool shouldResetSharedState =
          _sharedSessionStateKey != entry.sessionKey &&
              (_sharedSessionStateKey != null ||
                  !_supportsMultipleResidentWebViews);
      if (shouldResetSharedState) {
        await _resetSharedSessionState(
          entry,
          controller,
          clearAllPlatformData: _sharedSessionStateKey == null &&
              !_supportsMultipleResidentWebViews,
        );
      }
      _setSharedStateOwner(entry.sessionKey);
      await controller.loadUrl(entry.initialUrl);
    } catch (e) {
      debugPrint('[SessionWebViewManager] _restoreIfNeeded error: $e');
    }
  }

  Future<void> _onPageFinished(_SessionWebViewEntry entry) async {
    final WebViewController? controller = entry.controller;
    final _SessionRestoreState? restoreState = entry.restoreState;
    if (controller == null) {
      return;
    }
    if (restoreState == null) {
      await _captureSnapshot(entry.sessionKey);
      return;
    }
    final String? currentOrigin = _originForUrl(entry.lastUrl);
    final OriginStorageSnapshot? originStorage =
        _storageForOrigin(restoreState.snapshot, currentOrigin);
    if (currentOrigin != null &&
        !restoreState.restoredOrigins.contains(currentOrigin)) {
      final bool shouldRestoreStorage = restoreState.restoreLocalStorage ||
          restoreState.restoreSessionStorage;
      // A snapshot holding nothing for this origin means "nothing was ever
      // captured here", not "this origin must end up empty". restoreLocalStorage
      // clears before writing, so restoring an empty map would destroy state the
      // platform legitimately kept — most visibly the login token that survives a
      // process kill, where no capture ever ran and the snapshot on disk predates
      // the login. Deliberate clearing is the reset path's job, not this one's.
      if (restoreState.restoreLocalStorage &&
          (originStorage?.localStorage.isNotEmpty ?? false)) {
        try {
          await controller.restoreLocalStorage(originStorage!.localStorage);
        } catch (e) {
          debugPrint('[SessionWebViewManager] restoreLocalStorage failed: $e');
        }
      }
      if (restoreState.restoreSessionStorage &&
          (originStorage?.sessionStorage.isNotEmpty ?? false)) {
        try {
          await controller.restoreSessionStorage(originStorage!.sessionStorage);
        } catch (e) {
          debugPrint(
              '[SessionWebViewManager] restoreSessionStorage failed: $e');
        }
      }
      restoreState.restoredOrigins.add(currentOrigin);
      restoreState.storageRestored = true;
      final bool restoredAnyStorage =
          (originStorage?.localStorage.isNotEmpty ?? false) ||
              (originStorage?.sessionStorage.isNotEmpty ?? false);
      if (shouldRestoreStorage &&
          restoredAnyStorage &&
          !restoreState.reloadedAfterRestore) {
        restoreState.reloadedAfterRestore = true;
        // The first navigation runs before origin-scoped storage can be
        // restored. Loading the same URL again is not guaranteed to restart a
        // SPA, so force a real reload after the storage rewrite.
        await controller.reload();
        return;
      }
    }
    if (sessionBindingValidator != null && !restoreState.validationRetried) {
      final String? binding = sessionBindingCapture == null
          ? restoreState.snapshot.sessionBinding
          : await sessionBindingCapture!(entry.sessionKey, controller);
      if (!sessionBindingValidator!(entry.sessionKey, binding)) {
        restoreState.validationRetried = true;
        // Retry exactly once with a full cookie/storage rewrite to recover from
        // pages that read state too early during bootstrap.
        if (Platform.isIOS) {
          await _cookieManager.setCookiesForSession(
            entry.sessionKey,
            restoreState.snapshot.cookies,
          );
        } else {
          await _cookieManager.setCookies(restoreState.snapshot.cookies);
        }
        final OriginStorageSnapshot? retryStorage =
            _storageForOrigin(restoreState.snapshot, currentOrigin);
        // Same rule as above: an empty snapshot must not wipe live storage.
        if (retryStorage?.localStorage.isNotEmpty ?? false) {
          try {
            await controller.restoreLocalStorage(retryStorage!.localStorage);
          } catch (e) {
            debugPrint(
                '[SessionWebViewManager] retry restoreLocalStorage failed: $e');
          }
        }
        if (retryStorage?.sessionStorage.isNotEmpty ?? false) {
          try {
            await controller
                .restoreSessionStorage(retryStorage!.sessionStorage);
          } catch (e) {
            debugPrint(
                '[SessionWebViewManager] retry restoreSessionStorage failed: $e');
          }
        }
        await controller.reload();
        return;
      }
    }
    entry.restoreState = null;
    await _captureSnapshot(entry.sessionKey);
  }

  _SessionWebViewEntry _entryFor(String sessionKey, String initialUrl) {
    final _SessionWebViewEntry entry = _entries.putIfAbsent(
      sessionKey,
      () =>
          _SessionWebViewEntry(sessionKey: sessionKey, initialUrl: initialUrl),
    );
    _recordCookieDomain(entry, initialUrl);
    _recordOrigin(entry, initialUrl);
    return entry;
  }

  void _touch(String sessionKey) {
    _lru.remove(sessionKey);
    _lru.add(sessionKey);
  }

  /// Whether [snapshot] carries any DOM storage that a restore could write back.
  bool _snapshotHasStoredStorage(SessionSnapshot snapshot) {
    if (snapshot.localStorage.isNotEmpty ||
        snapshot.sessionStorage.isNotEmpty) {
      return true;
    }
    return snapshot.storageByOrigin.values.any(
      (OriginStorageSnapshot storage) =>
          storage.localStorage.isNotEmpty || storage.sessionStorage.isNotEmpty,
    );
  }

  Future<void> _resetSharedSessionState(
    _SessionWebViewEntry entry,
    WebViewController controller, {
    bool clearAllPlatformData = false,
    bool includeLocalStorage = true,
  }) async {
    final List<String> domains = _cookieDomainsForSharedStateReset(entry);
    if (Platform.isIOS) {
      try {
        await _cookieManager.clearWebsiteDataForSession(
          entry.sessionKey,
          includeCookies: true,
          includeLocalStorage: includeLocalStorage,
          includeCache: false,
        );
      } catch (e) {
        debugPrint(
            '[SessionWebViewManager] clearWebsiteDataForSession failed: $e');
      }
    } else if (clearAllPlatformData &&
        (preservedLocalStorageDomains == null ||
            preservedLocalStorageDomains!.isEmpty)) {
      try {
        await _cookieManager.clearWebsiteData(
          includeCookies: true,
          includeLocalStorage: includeLocalStorage,
          includeCache: false,
        );
      } catch (e) {
        debugPrint('[SessionWebViewManager] clearWebsiteData failed: $e');
      }
    } else if (clearAllPlatformData) {
      try {
        await _cookieManager.clearWebsiteData(
          includeCookies: true,
          includeLocalStorage: false,
          includeCache: false,
        );
        if (includeLocalStorage) {
          await _clearWebsiteDataForDomains(
            domains,
            includeCookies: false,
            includeLocalStorage: true,
            includeCache: false,
          );
        }
      } catch (e) {
        debugPrint('[SessionWebViewManager] clearWebsiteData failed: $e');
      }
    } else if (domains.isNotEmpty) {
      try {
        await _clearWebsiteDataForDomains(
          domains,
          includeLocalStorage: includeLocalStorage,
          includeCache: false,
        );
      } catch (e) {
        debugPrint(
            '[SessionWebViewManager] clearWebsiteDataForDomains failed: $e');
      }
    }
    // Domain-scoped localStorage cleanup is handled natively above. Running a
    // JS localStorage.clear() before the target page has loaded can clear the
    // wrong origin or fail on a blank document.
    try {
      final String? currentUrl = await controller.currentUrl();
      if (currentUrl != null &&
          (currentUrl.startsWith('http://') ||
              currentUrl.startsWith('https://'))) {
        await controller.restoreSessionStorage(<String, String>{});
      }
    } catch (e) {
      debugPrint('[SessionWebViewManager] reset sessionStorage failed: $e');
    }
  }

  Future<void> _clearWebsiteDataForDomains(
    List<String> domains, {
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) async {
    final List<String> normalizedDomains = domains
        .where((String value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (normalizedDomains.isEmpty) {
      return;
    }
    final List<String> localStorageDomains = Platform.isIOS
        ? normalizedDomains
        : normalizedDomains
            .where((String domain) => !_isPreservedLocalStorageHost(domain))
            .toList(growable: false);
    final bool mustSplit = includeLocalStorage &&
        localStorageDomains.length != normalizedDomains.length;
    if (!mustSplit) {
      await _cookieManager.clearWebsiteDataForDomains(
        normalizedDomains,
        includeCookies: includeCookies,
        includeLocalStorage: includeLocalStorage,
        includeCache: includeCache,
      );
      return;
    }

    if (includeCookies || includeCache) {
      await _cookieManager.clearWebsiteDataForDomains(
        normalizedDomains,
        includeCookies: includeCookies,
        includeLocalStorage: false,
        includeCache: includeCache,
      );
    }
    if (localStorageDomains.isNotEmpty) {
      await _cookieManager.clearWebsiteDataForDomains(
        localStorageDomains,
        includeCookies: false,
        includeLocalStorage: true,
        includeCache: false,
      );
    }
  }

  bool _isPreservedLocalStorageHost(String? host) {
    final List<String>? domains = preservedLocalStorageDomains;
    if (host == null || host.isEmpty || domains == null || domains.isEmpty) {
      return false;
    }
    final String normalized = host.trim().toLowerCase();
    for (final String domain in domains) {
      final String candidate = domain.trim().toLowerCase();
      if (candidate.isNotEmpty &&
          (normalized == candidate || normalized.endsWith('.$candidate'))) {
        return true;
      }
    }
    return false;
  }

  /// Rewrites the stored snapshot for [sessionKey] without ephemeral state.
  Future<void> _purgeEphemeralStateFromStore(String sessionKey) async {
    final List<String>? domains = ephemeralCookieDomains;
    if (domains == null || domains.isEmpty) {
      return;
    }
    try {
      final SessionSnapshot? stored = await sessionStore.read(sessionKey);
      if (stored == null) {
        return;
      }
      final SessionSnapshot? purged = _stripEphemeralState(stored);
      if (purged == null) {
        return;
      }
      await sessionStore.write(purged);
      final _SessionWebViewEntry? entry = _entries[sessionKey];
      if (entry != null) {
        entry.snapshot = purged;
        entry.cookieDomains.removeWhere(_isEphemeralHost);
        entry.origins.removeWhere(_isEphemeralOrigin);
      }
    } catch (e) {
      debugPrint('[SessionWebViewManager] purge ephemeral state failed: $e');
    }
  }

  /// Whether [host] belongs to a domain that must never be persisted.
  bool _isEphemeralHost(String? host) {
    final List<String>? domains = ephemeralCookieDomains;
    if (host == null || host.isEmpty || domains == null || domains.isEmpty) {
      return false;
    }
    final String normalized = host.toLowerCase();
    for (final String domain in domains) {
      final String candidate = domain.trim().toLowerCase();
      if (candidate.isEmpty) {
        continue;
      }
      if (normalized == candidate || normalized.endsWith('.$candidate')) {
        return true;
      }
    }
    return false;
  }

  /// Whether the origin string [origin] resolves to an ephemeral host.
  bool _isEphemeralOrigin(String? origin) {
    if (origin == null || origin.isEmpty) {
      return false;
    }
    return _isEphemeralHost(_uriForWebUrl(origin)?.host);
  }

  /// Drops every ephemeral cookie/origin from [snapshot].
  ///
  /// Returns null when nothing had to be stripped.
  SessionSnapshot? _stripEphemeralState(SessionSnapshot snapshot) {
    final List<WebViewCookie> cookies = snapshot.cookies
        .where((WebViewCookie cookie) => !_isEphemeralHost(cookie.domain))
        .toList(growable: false);
    final List<String> cookieDomains = snapshot.cookieDomains
        .where((String domain) => !_isEphemeralHost(domain))
        .toList(growable: false);
    final Map<String, OriginStorageSnapshot> storageByOrigin =
        <String, OriginStorageSnapshot>{
      for (final MapEntry<String, OriginStorageSnapshot> entry
          in snapshot.storageByOrigin.entries)
        if (!_isEphemeralOrigin(entry.key)) entry.key: entry.value,
    };
    final bool lastUrlIsEphemeral = _isEphemeralOrigin(snapshot.lastUrl);
    if (cookies.length == snapshot.cookies.length &&
        cookieDomains.length == snapshot.cookieDomains.length &&
        storageByOrigin.length == snapshot.storageByOrigin.length &&
        !lastUrlIsEphemeral) {
      return null;
    }
    return SessionSnapshot(
      sessionKey: snapshot.sessionKey,
      cookies: cookies,
      cookieDomains: cookieDomains,
      // The flat maps mirror lastUrl's origin; drop them with it.
      localStorage:
          lastUrlIsEphemeral ? <String, String>{} : snapshot.localStorage,
      sessionStorage:
          lastUrlIsEphemeral ? <String, String>{} : snapshot.sessionStorage,
      storageByOrigin: storageByOrigin,
      lastUrl: lastUrlIsEphemeral ? null : snapshot.lastUrl,
      sessionBinding: snapshot.sessionBinding,
      updatedAt: snapshot.updatedAt,
    );
  }

  List<String> _cookieDomainsForEntry(_SessionWebViewEntry entry) {
    final Set<String> domains = <String>{}..addAll(entry.cookieDomains);
    if (additionalCookieDomains != null) {
      domains.addAll(
        additionalCookieDomains!
            .where((String value) => value.trim().isNotEmpty),
      );
    }
    return domains.toList(growable: false);
  }

  List<String> _cookieDomainsForSharedStateReset(_SessionWebViewEntry entry) {
    final Set<String> domains = <String>{}..addAll(entry.cookieDomains);
    final String? sharedSessionStateKey = _sharedSessionStateKey;
    if (sharedSessionStateKey != null) {
      final _SessionWebViewEntry? sharedEntry = _entries[sharedSessionStateKey];
      if (sharedEntry != null) {
        domains.addAll(sharedEntry.cookieDomains);
      }
    }
    if (additionalCookieDomains != null) {
      domains.addAll(
        additionalCookieDomains!
            .where((String value) => value.trim().isNotEmpty),
      );
    }
    return domains.toList(growable: false);
  }

  void _recordCookieDomain(_SessionWebViewEntry entry, String? url) {
    if (url == null || url.isEmpty) {
      return;
    }
    final Uri? uri = _uriForWebUrl(url);
    final String host = uri?.host ?? '';
    if (host.isNotEmpty) {
      entry.cookieDomains.add(host);
    }
  }

  void _recordOrigin(_SessionWebViewEntry entry, String? url) {
    final String? origin = _originForUrl(url);
    if (origin == null) {
      return;
    }
    entry.origins.add(origin);
    entry.lastOrigin = origin;
  }

  OriginStorageSnapshot? _storageForOrigin(
    SessionSnapshot snapshot,
    String? origin,
  ) {
    if (origin != null && snapshot.storageByOrigin.containsKey(origin)) {
      return snapshot.storageByOrigin[origin];
    }
    if (snapshot.localStorage.isNotEmpty ||
        snapshot.sessionStorage.isNotEmpty) {
      final String? snapshotOrigin = _originForUrl(snapshot.lastUrl);
      if (origin == null || snapshotOrigin == origin) {
        return OriginStorageSnapshot(
          localStorage: snapshot.localStorage,
          sessionStorage: snapshot.sessionStorage,
        );
      }
    }
    return null;
  }

  String? _originForUrl(String? url) {
    if (url == null || url.isEmpty) {
      return null;
    }
    final Uri? uri = _uriForWebUrl(url);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final bool hasDefaultPort = (uri.scheme == 'http' && uri.port == 80) ||
        (uri.scheme == 'https' && uri.port == 443);
    final String port = uri.hasPort && !hasDefaultPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Uri? _uriForWebUrl(String url) {
    final Uri? parsed = Uri.tryParse(url);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed;
    }
    if (!url.contains('://')) {
      final Uri? withScheme = Uri.tryParse('http://$url');
      if (withScheme != null && withScheme.host.isNotEmpty) {
        return withScheme;
      }
    }
    return parsed;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

/// Builds the currently resident WebViews and shows the active one.
///
/// Inactive resident sessions are kept offstage so their WebView instances
/// remain alive and can be switched back to without losing transient page
/// state.
class SessionWebViewSwitcher extends StatefulWidget {
  /// Creates a new [SessionWebViewSwitcher].
  const SessionWebViewSwitcher({
    Key? key,
    required this.manager,
    required this.javascriptMode,
    this.javascriptChannels,
    this.navigationDelegate,
    this.gestureRecognizers,
    this.onWebViewCreated,
    this.onPageStarted,
    this.onPageFinished,
    this.onProgress,
    this.onWebResourceError,
    this.debuggingEnabled = false,
    this.gestureNavigationEnabled = false,
    this.geolocationEnabled = false,
    this.userAgent,
    this.initialMediaPlaybackPolicy =
        AutoMediaPlaybackPolicy.require_user_action_for_all_media_types,
    this.allowsInlineMediaPlayback = false,
  }) : super(key: key);

  /// Manager instance.
  final SessionWebViewManager manager;

  /// Shared JavaScript mode.
  final JavascriptMode javascriptMode;

  /// Shared JavaScript channels.
  final Set<JavascriptChannel>? javascriptChannels;

  /// Shared navigation delegate.
  final NavigationDelegate? navigationDelegate;

  /// Shared gesture recognizers.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Shared created callback.
  final WebViewCreatedCallback? onWebViewCreated;

  /// Shared page started callback.
  final PageStartedCallback? onPageStarted;

  /// Shared page finished callback.
  final PageFinishedCallback? onPageFinished;

  /// Shared loading progress callback.
  final PageLoadingCallback? onProgress;

  /// Shared resource error callback.
  final WebResourceErrorCallback? onWebResourceError;

  /// Shared debugging flag.
  final bool debuggingEnabled;

  /// Shared gesture navigation flag.
  final bool gestureNavigationEnabled;

  /// Shared geolocation flag.
  final bool geolocationEnabled;

  /// Shared user agent.
  final String? userAgent;

  /// Shared media playback policy.
  final AutoMediaPlaybackPolicy initialMediaPlaybackPolicy;

  /// Shared inline media playback flag.
  final bool allowsInlineMediaPlayback;

  @override
  State<SessionWebViewSwitcher> createState() => _SessionWebViewSwitcherState();
}

class _SessionWebViewSwitcherState extends State<SessionWebViewSwitcher> {
  Set<String> _attachedSessionKeys = <String>{};

  @override
  void didUpdateWidget(SessionWebViewSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      oldWidget.manager.detachResidentWebViews(
        _attachedSessionKeys,
        notify: false,
      );
      _attachedSessionKeys = <String>{};
    }
  }

  @override
  void dispose() {
    widget.manager.detachResidentWebViews(_attachedSessionKeys, notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (BuildContext context, Widget? child) {
        final List<String> residentSessionKeys =
            widget.manager.residentSessionKeys;
        _attachedSessionKeys = residentSessionKeys.toSet();
        final List<Widget> children = <Widget>[];
        for (final String sessionKey in residentSessionKeys) {
          final bool visible = widget.manager.currentSessionKey == sessionKey;
          children.add(
            Offstage(
              offstage: !visible,
              child: TickerMode(
                enabled: visible,
                child: widget.manager.buildWebView(
                  sessionKey: sessionKey,
                  javascriptMode: widget.javascriptMode,
                  onWebViewCreated: widget.onWebViewCreated,
                  javascriptChannels: widget.javascriptChannels,
                  navigationDelegate: widget.navigationDelegate,
                  gestureRecognizers: widget.gestureRecognizers,
                  onPageStarted: widget.onPageStarted,
                  onPageFinished: widget.onPageFinished,
                  onProgress: widget.onProgress,
                  onWebResourceError: widget.onWebResourceError,
                  debuggingEnabled: widget.debuggingEnabled,
                  gestureNavigationEnabled: widget.gestureNavigationEnabled,
                  geolocationEnabled: widget.geolocationEnabled,
                  userAgent: widget.userAgent,
                  initialMediaPlaybackPolicy: widget.initialMediaPlaybackPolicy,
                  allowsInlineMediaPlayback: widget.allowsInlineMediaPlayback,
                ),
              ),
            ),
          );
        }
        if (children.isEmpty) {
          return const SizedBox.shrink();
        }
        return Stack(children: children);
      },
    );
  }
}
