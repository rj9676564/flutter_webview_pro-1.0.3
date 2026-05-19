# flutter_webview_pro

A Flutter plugin that provides a WebView widget on Android and iOS.

This package is based on Flutter WebView behavior and includes additional native capabilities such as file upload support, geolocation support, and cookie management helpers.

## Features

- Display web content with a Flutter `WebView` widget.
- Control navigation, page loading callbacks, JavaScript execution, and JavaScript channels.
- Clear all WebView cookies.
- Clear WebView cookies for specified domains with `CookieManager.clearCookiesForDomains`.

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

## Platforms

- Android
- iOS

## Notes

`clearCookiesForDomains` accepts host names or URLs. It returns `true` when matching cookies were found before deletion, otherwise `false`.
