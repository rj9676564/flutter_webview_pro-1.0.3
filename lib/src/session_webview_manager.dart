import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../platform_interface.dart';
import '../webview_flutter.dart';

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
    implements SessionWebViewClearableSessionStore {
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

  @override
  Future<void> clear() async {
    final File file = await _file;
    if (await file.exists()) {
      await file.delete();
    }
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
  SessionSnapshot? snapshot;
  final LinkedHashSet<String> cookieDomains = LinkedHashSet<String>();
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
    this.additionalCookieDomains,
    SessionWebViewSessionStore? sessionStore,
    this.sessionBindingCapture,
    this.sessionBindingValidator,
  }) : sessionStore = sessionStore ?? MemorySessionWebViewSessionStore();

  /// Maximum number of resident WebView instances.
  ///
  /// When the pool is full, the least recently used non-active session is evicted.
  final int capacity;

  /// Additional cookie domains that should be captured/restored for every
  /// session in addition to the host parsed from `initialUrl`.
  ///
  /// Most integrations can leave this unset and rely on the `initialUrl` host.
  final List<String>? additionalCookieDomains;

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

  final CookieManager _cookieManager = CookieManager();
  final Map<String, _SessionWebViewEntry> _entries =
      <String, _SessionWebViewEntry>{};
  final LinkedHashSet<String> _lru = LinkedHashSet<String>();
  Future<void> _serial = Future<void>.value();
  String? _currentSessionKey;
  String? _sharedSessionStateKey;

  /// Current active session key.
  String? get currentSessionKey => _currentSessionKey;

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

  /// Switches the active view to [sessionKey].
  ///
  /// If the session is already resident its existing instance is reused.
  /// Otherwise the manager creates a new instance and restores the most recent
  /// [SessionSnapshot], if one exists.
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
  Future<void> warmUpSession(
    String sessionKey, {
    required String initialUrl,
  }) {
    return _enqueue(() => _ensureResident(sessionKey, initialUrl: initialUrl));
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
        _sharedSessionStateKey = null;
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
      _sharedSessionStateKey = null;
      notifyListeners();
      return null;
    });
  }

  /// Disposes the resident instance while keeping the persisted snapshot.
  ///
  /// This intentionally drops the live page state but retains the recoverable
  /// session layer already captured by [captureSession] or page-finished hooks.
  Future<void> disposeSession(String sessionKey) {
    return _enqueue(() async {
      final _SessionWebViewEntry? entry = _entries[sessionKey];
      if (entry == null) {
        return;
      }
      entry.resident = false;
      entry.controller = null;
      entry.restoreState = null;
      entry.widgetKey = UniqueKey();
      _lru.remove(sessionKey);
      if (_currentSessionKey == sessionKey) {
        _currentSessionKey = null;
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
      entry.resident = false;
      entry.controller = null;
      entry.restoreState = null;
      entry.widgetKey = UniqueKey();
      _lru.remove(sessionKey);
      if (_currentSessionKey == sessionKey) {
        _currentSessionKey = null;
      }
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
        onPageStarted?.call(url);
      },
      onPageFinished: (String url) {
        entry.lastUrl = url;
        _recordCookieDomain(entry, url);
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
    final _SessionWebViewEntry entry = _entryFor(sessionKey, initialUrl);
    entry.initialUrl = initialUrl;
    if (entry.snapshot == null) {
      entry.snapshot = await sessionStore.read(sessionKey);
      if (entry.snapshot != null) {
        entry.cookieDomains
          ..clear()
          ..addAll(entry.snapshot!.cookieDomains);
      }
    }
    if (entry.resident && entry.controller != null) {
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
        targetUrl: entry.snapshot!.lastUrl ?? initialUrl,
        resetBeforeRestore: !sharedStateMatches,
        restoreCookies: !sharedStateMatches,
        restoreLocalStorage: !sharedStateMatches,
        restoreSessionStorage:
            !sharedStateMatches || entry.snapshot!.sessionStorage.isNotEmpty,
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
      entry.resident = false;
      entry.controller = null;
      entry.restoreState = null;
      entry.widgetKey = UniqueKey();
      _lru.remove(candidate);
    }
  }

  Future<SessionSnapshot?> _captureSnapshot(String sessionKey) async {
    final _SessionWebViewEntry? entry = _entries[sessionKey];
    final WebViewController? controller = entry?.controller;
    if (entry == null || controller == null) {
      debugPrint(
        '[SessionWebViewManager] skip capture, no live controller for '
        'sessionKey=$sessionKey hasSnapshot=${entry?.snapshot != null}',
      );
      return entry?.snapshot ?? await sessionStore.read(sessionKey);
    }

    final SessionSnapshot? previousSnapshot =
        entry.snapshot ?? await sessionStore.read(sessionKey);
    final List<String> cookieDomains = _cookieDomainsForEntry(entry);
    final List<WebViewCookie> cookies = await _capturePart<List<WebViewCookie>>(
      sessionKey: sessionKey,
      label: 'cookies',
      fallback: previousSnapshot?.cookies ?? <WebViewCookie>[],
      action: () => _cookieManager.getCookiesForDomains(cookieDomains),
    );
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
    final String? binding = sessionBindingCapture == null
        ? previousSnapshot?.sessionBinding
        : await _capturePart<String?>(
            sessionKey: sessionKey,
            label: 'sessionBinding',
            fallback: previousSnapshot?.sessionBinding,
            action: () => sessionBindingCapture!(sessionKey, controller),
          );

    final SessionSnapshot snapshot = SessionSnapshot(
      sessionKey: sessionKey,
      cookies: cookies,
      cookieDomains: cookieDomains,
      localStorage: localStorage,
      sessionStorage: sessionStorage,
      lastUrl: currentUrl ??
          entry.lastUrl ??
          previousSnapshot?.lastUrl ??
          entry.initialUrl,
      sessionBinding: binding,
      updatedAt: DateTime.now(),
    );
    entry.snapshot = snapshot;
    await sessionStore.write(snapshot);
    debugPrint(
      '[SessionWebViewManager] captured sessionKey=$sessionKey '
      'cookies=${cookies.length} local=${localStorage.length} '
      'session=${sessionStorage.length} lastUrl=${snapshot.lastUrl}',
    );
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
    final WebViewController? controller = entry.controller;
    if (controller == null) {
      return;
    }
    final _SessionRestoreState? restoreState = entry.restoreState;
    if (restoreState != null) {
      debugPrint(
        '[SessionWebViewManager] restoring sessionKey=${entry.sessionKey} '
        'cookies=${restoreState.snapshot.cookies.length} '
        'local=${restoreState.snapshot.localStorage.length} '
        'session=${restoreState.snapshot.sessionStorage.length} '
        'targetUrl=${restoreState.targetUrl} '
        'reset=${restoreState.resetBeforeRestore} '
        'restoreCookies=${restoreState.restoreCookies} '
        'restoreLocal=${restoreState.restoreLocalStorage} '
        'restoreSession=${restoreState.restoreSessionStorage}',
      );
      if (restoreState.resetBeforeRestore) {
        await _resetSharedSessionState(entry, controller);
      }
      if (restoreState.restoreCookies) {
        // Cookies are restored before the initial navigation so server-side auth
        // can see the recovered session on the first request.
        await _cookieManager.setCookies(restoreState.snapshot.cookies);
      }
      _sharedSessionStateKey = entry.sessionKey;
      await controller.loadUrl(restoreState.targetUrl);
      return;
    }
    if (_sharedSessionStateKey == entry.sessionKey) {
      debugPrint(
        '[SessionWebViewManager] reusing shared state '
        'sessionKey=${entry.sessionKey} initialUrl=${entry.initialUrl}',
      );
    } else if (_sharedSessionStateKey == null) {
      debugPrint(
        '[SessionWebViewManager] adopting existing shared state '
        'sessionKey=${entry.sessionKey} initialUrl=${entry.initialUrl}',
      );
    } else {
      debugPrint(
        '[SessionWebViewManager] starting clean '
        'sessionKey=${entry.sessionKey} initialUrl=${entry.initialUrl}',
      );
      await _resetSharedSessionState(entry, controller);
    }
    _sharedSessionStateKey = entry.sessionKey;
    await controller.loadUrl(entry.initialUrl);
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
    if (!restoreState.storageRestored) {
      // Storage is written after the first load, then the page is reloaded once
      // so client-side bootstrap logic can observe the restored values.
      final bool shouldRestoreStorage = restoreState.restoreLocalStorage ||
          restoreState.restoreSessionStorage;
      if (restoreState.restoreLocalStorage) {
        await controller.restoreLocalStorage(
          restoreState.snapshot.localStorage,
        );
      }
      if (restoreState.restoreSessionStorage) {
        await controller.restoreSessionStorage(
          restoreState.snapshot.sessionStorage,
        );
      }
      restoreState.storageRestored = true;
      if (shouldRestoreStorage && !restoreState.reloadedAfterRestore) {
        restoreState.reloadedAfterRestore = true;
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
        await _cookieManager.setCookies(restoreState.snapshot.cookies);
        await controller
            .restoreLocalStorage(restoreState.snapshot.localStorage);
        await controller.restoreSessionStorage(
          restoreState.snapshot.sessionStorage,
        );
        await controller.loadUrl(restoreState.targetUrl);
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
    return entry;
  }

  void _touch(String sessionKey) {
    _lru.remove(sessionKey);
    _lru.add(sessionKey);
  }

  Future<void> _resetSharedSessionState(
    _SessionWebViewEntry entry,
    WebViewController controller,
  ) async {
    final List<String> domains = _cookieDomainsForEntry(entry);
    if (domains.isNotEmpty) {
      await _cookieManager.clearWebsiteDataForDomains(
        domains,
        includeCookies: true,
        includeLocalStorage: true,
        includeCache: false,
      );
    }
    // Domain-scoped localStorage cleanup is handled natively above. Running a
    // JS localStorage.clear() before the target page has loaded can clear the
    // wrong origin or fail on a blank document.
    await controller.restoreSessionStorage(<String, String>{});
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

  void _recordCookieDomain(_SessionWebViewEntry entry, String? url) {
    if (url == null || url.isEmpty) {
      return;
    }
    final Uri? uri = Uri.tryParse(url);
    final String host = uri?.host ?? '';
    if (host.isNotEmpty) {
      entry.cookieDomains.add(host);
    }
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
