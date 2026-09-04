# flutter_webview_pro

A Flutter plugin that provides a WebView widget on Android and iOS.

This package is based on Flutter WebView behavior and includes additional native capabilities such as file upload support, geolocation support, and cookie management helpers.

## Features

- Display web content with a Flutter `WebView` widget.
- Control navigation, page loading callbacks, JavaScript execution, and JavaScript channels.
- Clear all WebView cookies.
- Clear WebView cookies for specified domains with `CookieManager.clearCookiesForDomains`.
- Keep session-specific WebView instances resident with `SessionWebViewManager`.
- Configure an Android WebView HTTP/SOCKS proxy with `WebViewProxy`.

## WebView proxy

Configure the proxy before creating or loading a WebView:

```dart
import 'package:flutter_webview_pro/webview_flutter.dart';

await WebViewProxy.setProxy('192.168.1.152:9090');
// HTTP proxy with an explicit scheme:
// await WebViewProxy.setProxy('http://192.168.1.152:9090');
// SOCKS proxy:
// await WebViewProxy.setProxy('socks5://127.0.0.1:1080');
```

Supported proxy formats are `host:port`, `http://host:port`, and
`socks5://host:port`. Passing `null` or an empty string clears the override and
restores the default connection:

```dart
await WebViewProxy.clearProxy();
```

On Android, this feature uses AndroidX WebKit `ProxyController` and applies to
WebViews in the current application process. The proxy configuration is
applied asynchronously, so await `setProxy` before creating or loading the
WebView. The device's Android System WebView/Chrome must support the proxy
override feature; old WebView implementations may ignore the request.

On iOS, `WKWebView` does not provide an app-level proxy override. The same API
is kept for cross-platform compatibility, but `setProxy` is a no-op on iOS. For
development traffic capture, configure the proxy in the iPhone's current Wi-Fi
network settings, using the development computer's IP address and proxy port.

If the proxy tool decrypts HTTPS traffic, install its root CA on the test
device and enable HTTPS/SSL interception in the proxy tool. On iOS, manually
installed certificates also need to be enabled in **Settings > General > About
> Certificate Trust Settings**. On Android, a debug app should explicitly
trust user-installed CAs through its app-level Network Security Configuration;
this package does not install or trust a proxy CA automatically. Use proxy CA
trust settings only in development builds.

## Usage

Add the package to your `pubspec.yaml`, then import it:

```dart
import 'package:flutter_webview_pro/webview_flutter.dart';
```

Create a WebView:

```dart
WebView(
  initialUrl: 'https://flutter.dev',
  javascriptMode: JavascriptMode.unrestricted,
)
```

Clear cookies for specific domains:

```dart
final CookieManager cookieManager = CookieManager();

await cookieManager.clearCookiesForDomains(<String>[
  'flutter.dev',
  'https://example.com',
]);
```

Keep isolated web sessions with a resident WebView pool:

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  sessionStore: FileSessionWebViewSessionStore(),
);

await sessionManager.switchToSession(
  'tenant-a',
  initialUrl: 'https://tenant-a.example.com',
);

Widget build(BuildContext context) {
  return SessionWebViewSwitcher(
    manager: sessionManager,
    javascriptMode: JavascriptMode.unrestricted,
  );
}
```

Call `switchToSession` when the WebView page is entered with the session
identifier you want to bind to that page. For a store/account switch, pass the
new session key before building `SessionWebViewSwitcher`.

The first opened session adopts existing platform WebView state instead of
clearing it. Reopening the same session key also reuses platform cookies and
origin storage when they are still available. When switching to a different
session key, the manager captures the previous session, clears shared WebView
state for the learned domains, and restores the target session snapshot.

`FileSessionWebViewSessionStore()` uses a default JSON file under the system
temporary/cache directory, so snapshots can be restored after a normal app
process restart without requiring the caller to provide a custom path. If you do
not need process-restart recovery, you can omit `sessionStore` and use the
default in-memory store.

On app-level logout, clear all WebView sessions and platform WebView data:

```dart
await sessionManager.clearAllSessions();
```

After this call, all saved snapshots, cookies, storage, and cache data are
removed. The next time any session key is opened, the web page should require
login again.

To validate that a restored page is still bound to the expected session, provide
an optional binding capture and validator:

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  sessionBindingCapture: (String sessionKey, WebViewController controller) {
    return controller.evaluateJavascript('window.__CURRENT_SESSION_ID__');
  },
  sessionBindingValidator: (String sessionKey, String? binding) {
    return binding == sessionKey;
  },
);
```

`SessionWebViewManager` learns cookie hosts from the URLs visited during a
session. If the web session also relies on login domains that are not visited
through normal WebView navigation, you can add them globally:

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  additionalCookieDomains: <String>[
    'sso.example.com',
    'static-login.example.com',
  ],
);
```

## Platforms

- Android
- iOS

## Notes

`clearCookiesForDomains` accepts host names or URLs. It returns `true` when matching cookies were found before deletion, otherwise `false`.

`SessionWebViewManager` keeps up to 3 WebViews resident by default. When the
pool is full it evicts the least recently used instance, captures its cookies
and web storage, and restores that session when the same session key is opened
again.

By default `SessionWebViewManager` starts with the host parsed from
`initialUrl`, then keeps expanding the session's cookie host set as navigation
reaches new domains. Use `additionalCookieDomains` only when the login flow
depends on extra domains that are not visible through navigation.

`SessionWebViewManager` restores the recoverable session layer: cookies,
`localStorage`, `sessionStorage`, and the last URL. If a session stays resident it
also preserves transient live page state. Once evicted, in-memory JavaScript
variables, pending form edits, and temporary DOM state are not guaranteed to be
restored.

The default `MemorySessionWebViewSessionStore` only keeps snapshots in memory.
If the app process is killed, the manager cannot know which session owns the
platform WebView cookies that remain on disk. Use
`FileSessionWebViewSessionStore()` when session snapshots must survive normal
app restarts. Its default path is
`FileSessionWebViewSessionStore.defaultFilePath`, which points to a JSON file
under `Directory.systemTemp`; the OS may still remove this file during cache or
temporary-file cleanup.
