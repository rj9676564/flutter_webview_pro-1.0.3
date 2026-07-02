// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/basic_types.dart';
import 'package:flutter/src/gestures/recognizer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webview_pro/platform_interface.dart';
import 'package:flutter_webview_pro/webview_flutter.dart';

typedef void VoidCallback();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final _FakePlatformViewsController fakePlatformViewsController =
      _FakePlatformViewsController();

  final _FakeCookieManager _fakeCookieManager = _FakeCookieManager();

  setUpAll(() {
    SystemChannels.platform_views.setMockMethodCallHandler(
        fakePlatformViewsController.fakePlatformViewsMethodHandler);
    SystemChannels.platform
        .setMockMethodCallHandler(_fakeCookieManager.onMethodCall);
  });

  setUp(() {
    fakePlatformViewsController.reset();
    _fakeCookieManager.reset();
  });

  testWidgets('Create WebView', (WidgetTester tester) async {
    await tester.pumpWidget(const WebView());
  });

  testWidgets('Initial url', (WidgetTester tester) async {
    late WebViewController controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(await controller.currentUrl(), 'https://youtube.com');
  });

  testWidgets('Javascript mode', (WidgetTester tester) async {
    await tester.pumpWidget(const WebView(
      initialUrl: 'https://youtube.com',
      javascriptMode: JavascriptMode.unrestricted,
    ));

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.javascriptMode, JavascriptMode.unrestricted);

    await tester.pumpWidget(const WebView(
      initialUrl: 'https://youtube.com',
      javascriptMode: JavascriptMode.disabled,
    ));
    expect(platformWebView.javascriptMode, JavascriptMode.disabled);
  });

  testWidgets('Load url', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    await controller!.loadUrl('https://flutter.io');

    expect(await controller!.currentUrl(), 'https://flutter.io');
  });

  testWidgets('Invalid urls', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    expect(await controller!.currentUrl(), isNull);

    expect(() => controller!.loadUrl(''), throwsA(anything));
    expect(await controller!.currentUrl(), isNull);

    // Missing schema.
    expect(() => controller!.loadUrl('flutter.io'), throwsA(anything));
    expect(await controller!.currentUrl(), isNull);
  });

  testWidgets('Headers in loadUrl', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    final Map<String, String> headers = <String, String>{
      'CACHE-CONTROL': 'ABC'
    };
    await controller!.loadUrl('https://flutter.io', headers: headers);
    expect(await controller!.currentUrl(), equals('https://flutter.io'));
  });

  testWidgets("Can't go back before loading a page",
      (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    final bool canGoBackNoPageLoaded = await controller!.canGoBack();

    expect(canGoBackNoPageLoaded, false);
  });

  testWidgets("Clear Cache", (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);
    expect(fakePlatformViewsController.lastCreatedView!.hasCache, true);

    await controller!.clearCache();

    expect(fakePlatformViewsController.lastCreatedView!.hasCache, false);
  });

  testWidgets("Can't go back with no history", (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);
    final bool canGoBackFirstPageLoaded = await controller!.canGoBack();

    expect(canGoBackFirstPageLoaded, false);
  });

  testWidgets('Can go back', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    await controller!.loadUrl('https://www.google.com');
    final bool canGoBackSecondPageLoaded = await controller!.canGoBack();

    expect(canGoBackSecondPageLoaded, true);
  });

  testWidgets("Can't go forward before loading a page",
      (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    final bool canGoForwardNoPageLoaded = await controller!.canGoForward();

    expect(canGoForwardNoPageLoaded, false);
  });

  testWidgets("Can't go forward with no history", (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);
    final bool canGoForwardFirstPageLoaded = await controller!.canGoForward();

    expect(canGoForwardFirstPageLoaded, false);
  });

  testWidgets('Can go forward', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    await controller!.loadUrl('https://youtube.com');
    await controller!.goBack();
    final bool canGoForwardFirstPageBacked = await controller!.canGoForward();

    expect(canGoForwardFirstPageBacked, true);
  });

  testWidgets('Go back', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    expect(await controller!.currentUrl(), 'https://youtube.com');

    await controller!.loadUrl('https://flutter.io');

    expect(await controller!.currentUrl(), 'https://flutter.io');

    await controller!.goBack();

    expect(await controller!.currentUrl(), 'https://youtube.com');
  });

  testWidgets('Go forward', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    expect(await controller!.currentUrl(), 'https://youtube.com');

    await controller!.loadUrl('https://flutter.io');

    expect(await controller!.currentUrl(), 'https://flutter.io');

    await controller!.goBack();

    expect(await controller!.currentUrl(), 'https://youtube.com');

    await controller!.goForward();

    expect(await controller!.currentUrl(), 'https://flutter.io');
  });

  testWidgets('Current URL', (WidgetTester tester) async {
    WebViewController? controller;
    await tester.pumpWidget(
      WebView(
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    expect(controller, isNotNull);

    // Test a WebView without an explicitly set first URL.
    expect(await controller!.currentUrl(), isNull);

    await controller!.loadUrl('https://youtube.com');
    expect(await controller!.currentUrl(), 'https://youtube.com');

    await controller!.loadUrl('https://flutter.io');
    expect(await controller!.currentUrl(), 'https://flutter.io');

    await controller!.goBack();
    expect(await controller!.currentUrl(), 'https://youtube.com');
  });

  testWidgets('Reload url', (WidgetTester tester) async {
    late WebViewController controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.currentUrl, 'https://flutter.io');
    expect(platformWebView.amountOfReloadsOnCurrentUrl, 0);

    await controller.reload();

    expect(platformWebView.currentUrl, 'https://flutter.io');
    expect(platformWebView.amountOfReloadsOnCurrentUrl, 1);

    await controller.loadUrl('https://youtube.com');

    expect(platformWebView.amountOfReloadsOnCurrentUrl, 0);
  });

  testWidgets('evaluate Javascript', (WidgetTester tester) async {
    late WebViewController controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        javascriptMode: JavascriptMode.unrestricted,
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );
    expect(
        await controller.evaluateJavascript("fake js string"), "fake js string",
        reason: 'should get the argument');
  });

  testWidgets('evaluate Javascript with JavascriptMode disabled',
      (WidgetTester tester) async {
    late WebViewController controller;
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://flutter.io',
        javascriptMode: JavascriptMode.disabled,
        onWebViewCreated: (WebViewController webViewController) {
          controller = webViewController;
        },
      ),
    );
    expect(
      () => controller.evaluateJavascript('fake js string'),
      throwsA(anything),
    );
  });

  testWidgets('Cookies can be cleared once', (WidgetTester tester) async {
    await tester.pumpWidget(
      const WebView(
        initialUrl: 'https://flutter.io',
      ),
    );
    final CookieManager cookieManager = CookieManager();
    final bool hasCookies = await cookieManager.clearCookies();
    expect(hasCookies, true);
  });

  testWidgets('Second cookie clear does not have cookies',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const WebView(
        initialUrl: 'https://flutter.io',
      ),
    );
    final CookieManager cookieManager = CookieManager();
    final bool hasCookies = await cookieManager.clearCookies();
    expect(hasCookies, true);
    final bool hasCookiesSecond = await cookieManager.clearCookies();
    expect(hasCookiesSecond, false);
  });

  testWidgets('Cookies can be cleared for domains',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const WebView(
        initialUrl: 'https://flutter.io',
      ),
    );
    final CookieManager cookieManager = CookieManager();
    final bool hasCookies = await cookieManager.clearCookiesForDomains(
      <String>['https://flutter.io'],
    );
    expect(hasCookies, true);
  });

  testWidgets('Cookies can be stored per session', (WidgetTester tester) async {
    final WebViewPlatform previousPlatform = WebView.platform;
    WebView.platform = _SessionCookiePlatform(_fakeCookieManager);
    final CookieManager cookieManager = CookieManager();

    try {
      await cookieManager.setCookiesForSession(
        'user:1|shop:a',
        const <WebViewCookie>[
          WebViewCookie(
            name: 'sid',
            value: 'A',
            domain: 'merchant.example.com',
          ),
        ],
      );
      await cookieManager.setCookiesForSession(
        'user:1|shop:b',
        const <WebViewCookie>[
          WebViewCookie(
            name: 'sid',
            value: 'B',
            domain: 'merchant.example.com',
          ),
        ],
      );

      expect(
        (await cookieManager.getCookiesForSession('user:1|shop:a'))
            .single
            .value,
        'A',
      );
      expect(
        (await cookieManager.getCookiesForSession('user:1|shop:b'))
            .single
            .value,
        'B',
      );
    } finally {
      WebView.platform = previousPlatform;
    }
  });

  testWidgets('Android rejects per-session cookie APIs',
      (WidgetTester tester) async {
    final WebViewPlatform previousPlatform = WebView.platform;
    WebView.platform = SurfaceAndroidWebView();
    final CookieManager cookieManager = CookieManager();

    try {
      expect(
        () => cookieManager.getCookiesForSession('user:1|shop:a'),
        throwsUnsupportedError,
      );
      expect(
        () => cookieManager.setCookiesForSession(
          'user:1|shop:a',
          const <WebViewCookie>[],
        ),
        throwsUnsupportedError,
      );
      expect(
        () => cookieManager.clearWebsiteDataForSession('user:1|shop:a'),
        throwsUnsupportedError,
      );
    } finally {
      WebView.platform = previousPlatform;
    }
  });

  testWidgets('SessionWebViewManager reuses resident instances',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(
      platformSupportsMultipleResidentWebViews: true,
    );

    await manager.switchToSession('tenant-a',
        initialUrl: 'https://tenant-a.example.com');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView firstView =
        fakePlatformViewsController.createdViews.last;
    await manager.switchToSession('tenant-b',
        initialUrl: 'https://tenant-b.example.com');
    await tester.pump();
    await tester.pump();

    await manager.switchToSession('tenant-a',
        initialUrl: 'https://tenant-a.example.com');
    await tester.pump();

    expect(fakePlatformViewsController.createdViews.length, 2);
    expect(fakePlatformViewsController.createdViews.first, same(firstView));
    expect(
      manager.residentSessionKeys,
      containsAll(<String>['tenant-a', 'tenant-b']),
    );
  });

  testWidgets('SessionWebViewManager keeps a single resident view on Android',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(
      capacity: 3,
      platformSupportsMultipleResidentWebViews: false,
    );

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView viewA =
        fakePlatformViewsController.createdViews.last;
    viewA.fakeOnPageFinishedCallback();
    await tester.pump();
    viewA.storage['localStorage']!['token'] = 'A-TOKEN';
    viewA.storage['sessionStorage']!['tenant'] = 'tenant-a';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'merchant.example.com',
        ),
      ],
    );

    await manager.switchToSession(
      'tenant-b',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView viewB =
        fakePlatformViewsController.createdViews.last;
    expect(viewB, isNot(same(viewA)));
    expect(manager.residentSessionKeys, <String>['tenant-b']);
    viewB.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(viewB.storage['localStorage'], isEmpty);
    expect(viewB.storage['sessionStorage'], isEmpty);
    expect(
      _fakeCookieManager.getCookiesForDomain('merchant.example.com'),
      isEmpty,
    );

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView restoredViewA =
        fakePlatformViewsController.createdViews.last;
    expect(restoredViewA, isNot(same(viewA)));
    expect(manager.residentSessionKeys, <String>['tenant-a']);
    restoredViewA.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredViewA.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(restoredViewA.storage['localStorage']!['token'], 'A-TOKEN');
    expect(restoredViewA.storage['sessionStorage']!['tenant'], 'tenant-a');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('merchant.example.com')
          .single
          .value,
      'cookie-a',
    );
  });

  testWidgets('SessionWebViewManager restores snapshot after LRU eviction',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(
      capacity: 2,
      sessionBindingCapture:
          (String sessionKey, WebViewController controller) async {
        return controller.evaluateJavascript('window.__sessionBinding');
      },
      sessionBindingValidator: (String sessionKey, String? binding) =>
          binding == sessionKey,
    );

    await manager.switchToSession('tenant-a',
        initialUrl: 'https://tenant-a.example.com');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();
    FakePlatformWebView viewA = fakePlatformViewsController.createdViews.last;
    viewA.fakeOnPageFinishedCallback();
    viewA.storage['localStorage']!['token'] = 'A-TOKEN';
    viewA.storage['sessionStorage']!['tenant'] = 'tenant-a';
    viewA.binding = 'tenant-a';
    _fakeCookieManager.setCookiesForDomain(
      'tenant-a.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'tenant-a.example.com',
        ),
      ],
    );

    await manager.switchToSession('tenant-b',
        initialUrl: 'https://tenant-b.example.com');
    await tester.pump();
    await tester.pump();
    FakePlatformWebView viewB = fakePlatformViewsController.createdViews.last;
    viewB.fakeOnPageFinishedCallback();
    viewB.binding = 'tenant-b';

    await manager.switchToSession('tenant-c',
        initialUrl: 'https://tenant-c.example.com');
    await tester.pump();
    await tester.pump();

    expect(manager.residentSessionKeys, isNot(contains('tenant-a')));

    await manager.switchToSession('tenant-a',
        initialUrl: 'https://tenant-a.example.com');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView restoredView =
        fakePlatformViewsController.createdViews.last;
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(restoredView, isNot(same(viewA)));
    expect(restoredView.currentUrl, 'https://tenant-a.example.com');
    expect(restoredView.storage['localStorage']!['token'], 'A-TOKEN');
    expect(restoredView.storage['sessionStorage']!['tenant'], 'tenant-a');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('tenant-a.example.com')
          .single
          .value,
      'cookie-a',
    );
  });

  testWidgets('SessionWebViewManager learns cookie domains from navigation',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(
      capacity: 2,
      restoreLastUrlOnReopen: true,
    );

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://landing.a.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView viewA =
        fakePlatformViewsController.createdViews.last;
    viewA.fakeNavigate('https://merchant.b.com');
    await tester.pump();
    viewA.fakeOnPageFinishedCallback();
    viewA.storage['localStorage']!['token'] = 'B-TOKEN';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.b.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-b',
          domain: 'merchant.b.com',
        ),
      ],
    );

    await manager.switchToSession(
      'tenant-b',
      initialUrl: 'https://tenant-b.example.com',
    );
    await tester.pump();
    await tester.pump();
    fakePlatformViewsController.createdViews.last.fakeOnPageFinishedCallback();

    await manager.switchToSession(
      'tenant-c',
      initialUrl: 'https://tenant-c.example.com',
    );
    await tester.pump();
    await tester.pump();
    fakePlatformViewsController.createdViews.last.fakeOnPageFinishedCallback();

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://landing.a.com',
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView restoredView =
        fakePlatformViewsController.createdViews.last;
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(
      _fakeCookieManager.getCookiesForDomain('merchant.b.com').single.value,
      'cookie-b',
    );
    expect(restoredView.storage['localStorage']!['token'], 'B-TOKEN');
  });

  testWidgets(
      'SessionWebViewManager clears shared session state for a new session key',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView viewA =
        fakePlatformViewsController.createdViews.last;
    viewA.fakeOnPageFinishedCallback();
    await tester.pump();
    viewA.storage['localStorage']!['token'] = 'A-TOKEN';
    viewA.storage['sessionStorage']!['tenant'] = 'tenant-a';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'merchant.example.com',
        ),
      ],
    );

    await manager.switchToSession(
      'tenant-b',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView viewB =
        fakePlatformViewsController.createdViews.last;
    viewB.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(viewB.storage['localStorage'], isEmpty);
    expect(viewB.storage['sessionStorage'], isEmpty);
    expect(
      _fakeCookieManager.getCookiesForDomain('merchant.example.com'),
      isEmpty,
    );
  });

  testWidgets('SessionWebViewManager restores after dispose capture failure',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView viewA =
        fakePlatformViewsController.createdViews.last;
    viewA.fakeOnPageFinishedCallback();
    viewA.storage['localStorage']!['token'] = 'A-TOKEN';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'merchant.example.com',
        ),
      ],
    );
    await manager.captureSession('tenant-a');

    viewA.throwOnEvaluateJavascript = true;
    await manager.disposeSession('tenant-a');

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView restoredView =
        fakePlatformViewsController.createdViews.last;
    expect(restoredView, isNot(same(viewA)));
    expect(restoredView.currentUrl, 'https://merchant.example.com');
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(restoredView.storage['localStorage']!['token'], 'A-TOKEN');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('merchant.example.com')
          .single
          .value,
      'cookie-a',
    );
  });

  testWidgets('SessionWebViewManager preserves same session platform state',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView firstView =
        fakePlatformViewsController.createdViews.last;
    firstView.fakeOnPageFinishedCallback();
    await tester.pump();
    firstView.storage['localStorage']!['token'] = 'A-TOKEN';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'merchant.example.com',
        ),
      ],
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView secondView =
        fakePlatformViewsController.createdViews.last;
    expect(secondView, isNot(same(firstView)));
    expect(secondView.storage['localStorage']!['token'], 'A-TOKEN');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('merchant.example.com')
          .single
          .value,
      'cookie-a',
    );
  });

  testWidgets('SessionWebViewManager adopts first untracked platform state',
      (WidgetTester tester) async {
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'existing-cookie',
          domain: 'merchant.example.com',
        ),
      ],
    );
    FakePlatformWebView.seedLocalStorage(
      'https://merchant.example.com/',
      <String, String>{'token': 'EXISTING-TOKEN'},
    );
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView view =
        fakePlatformViewsController.createdViews.last;
    expect(view.storage['localStorage']!['token'], 'EXISTING-TOKEN');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('merchant.example.com')
          .single
          .value,
      'existing-cookie',
    );
  });

  testWidgets('SessionWebViewManager clears all sessions on logout',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView view =
        fakePlatformViewsController.createdViews.last;
    view.fakeOnPageFinishedCallback();
    await tester.pump();
    view.storage['localStorage']!['token'] = 'A-TOKEN';
    _fakeCookieManager.setCookiesForDomain(
      'merchant.example.com',
      <WebViewCookie>[
        const WebViewCookie(
          name: 'sid',
          value: 'cookie-a',
          domain: 'merchant.example.com',
        ),
      ],
    );
    await manager.captureSession('tenant-a');

    await manager.clearAllSessions();

    expect(manager.currentSessionKey, isNull);
    expect(manager.residentSessionKeys, isEmpty);
    expect(view.storage['localStorage'], isEmpty);
    expect(
      _fakeCookieManager.getCookiesForDomain('merchant.example.com'),
      isEmpty,
    );
    expect(await manager.restoreSession('tenant-a'), isNull);
  });

  testWidgets('SessionWebViewManager restores from session store after restart',
      (WidgetTester tester) async {
    final MemorySessionWebViewSessionStore store =
        MemorySessionWebViewSessionStore();
    await store.write(
      SessionSnapshot(
        sessionKey: 'tenant-a',
        cookies: const <WebViewCookie>[
          WebViewCookie(
            name: 'sid',
            value: 'cookie-a',
            domain: 'merchant.example.com',
          ),
        ],
        cookieDomains: const <String>['merchant.example.com'],
        localStorage: const <String, String>{'token': 'A-TOKEN'},
        sessionStorage: const <String, String>{'tenant': 'tenant-a'},
        lastUrl: 'https://merchant.example.com',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );

    FakePlatformWebView.resetSharedStorage();
    _fakeCookieManager.reset();

    final SessionWebViewManager restartedManager = SessionWebViewManager(
      capacity: 2,
      sessionStore: store,
    );
    await restartedManager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: restartedManager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView restoredView =
        fakePlatformViewsController.createdViews.last;
    expect(restoredView.currentUrl, 'https://merchant.example.com');
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(restoredView.storage['localStorage']!['token'], 'A-TOKEN');
    expect(restoredView.storage['sessionStorage']!['tenant'], 'tenant-a');
    expect(
      _fakeCookieManager
          .getCookiesForDomain('merchant.example.com')
          .single
          .value,
      'cookie-a',
    );
  });

  testWidgets(
      'SessionWebViewManager reopens disposed session from initialUrl by default',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com/a',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView firstView =
        fakePlatformViewsController.createdViews.last;
    firstView.fakeOnPageFinishedCallback();
    await tester.pump();

    firstView.fakeNavigate('https://merchant.example.com/b');
    firstView.fakeOnPageStartedCallback();
    firstView.fakeOnPageFinishedCallback();
    await tester.pump();

    firstView.fakeNavigate('https://merchant.example.com/c');
    firstView.fakeOnPageStartedCallback();
    firstView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(firstView.currentUrl, 'https://merchant.example.com/c');

    await manager.captureSession('tenant-a');
    await manager.disposeSession('tenant-a');

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://merchant.example.com/a',
    );
    await tester.pump();
    await tester.pump();

    final FakePlatformWebView reopenedView =
        fakePlatformViewsController.createdViews.last;
    expect(reopenedView, isNot(same(firstView)));
    expect(reopenedView.currentUrl, 'https://merchant.example.com/a');
  });

  test('FileSessionWebViewSessionStore persists snapshots across instances',
      () async {
    final String filePath =
        '${Directory.systemTemp.path}/flutter_webview_pro_session_test.json';
    final File file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }

    await FileSessionWebViewSessionStore(filePath).write(
      SessionSnapshot(
        sessionKey: 'tenant-a',
        cookies: const <WebViewCookie>[
          WebViewCookie(
            name: 'sid',
            value: 'cookie-a',
            domain: 'merchant.example.com',
          ),
        ],
        cookieDomains: const <String>['merchant.example.com'],
        localStorage: const <String, String>{'token': 'A-TOKEN'},
        sessionStorage: const <String, String>{'tenant': 'tenant-a'},
        storageByOrigin: const <String, OriginStorageSnapshot>{
          'https://merchant.example.com': OriginStorageSnapshot(
            localStorage: <String, String>{'token': 'A-TOKEN'},
            sessionStorage: <String, String>{'tenant': 'tenant-a'},
          ),
        },
        lastUrl: 'https://merchant.example.com',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );

    final SessionSnapshot? restored =
        await FileSessionWebViewSessionStore(filePath).read('tenant-a');

    expect(restored, isNotNull);
    expect(restored!.cookies.single.value, 'cookie-a');
    expect(restored.localStorage['token'], 'A-TOKEN');
    expect(restored.sessionStorage['tenant'], 'tenant-a');
    expect(
      restored.storageByOrigin['https://merchant.example.com']!
          .localStorage['token'],
      'A-TOKEN',
    );

    if (await file.exists()) {
      await file.delete();
    }
  });

  testWidgets('SessionWebViewManager captures storage for multiple origins',
      (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(capacity: 2);

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://h5.example.com/home',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
          navigationDelegate: (_) async => NavigationDecision.navigate,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView view =
        fakePlatformViewsController.createdViews.last;
    view.storage['localStorage']!['h5Token'] = 'H5';
    view.fakeOnPageFinishedCallback();
    await manager.captureSession('tenant-a');

    view.fakeNavigate('https://login.example.com/oauth');
    await tester.pump();
    view.storage['localStorage']!['loginToken'] = 'LOGIN';
    view.fakeOnPageStartedCallback();
    view.fakeOnPageFinishedCallback();
    await manager.captureSession('tenant-a');

    final SessionSnapshot snapshot =
        (await manager.restoreSession('tenant-a'))!;

    expect(
      snapshot
          .storageByOrigin['https://h5.example.com']!.localStorage['h5Token'],
      'H5',
    );
    expect(
      snapshot.storageByOrigin['https://login.example.com']!
          .localStorage['loginToken'],
      'LOGIN',
    );
  });

  testWidgets(
      'SessionWebViewManager retry does not inject fallback storage '
      'into a different origin', (WidgetTester tester) async {
    final SessionWebViewManager manager = SessionWebViewManager(
      capacity: 1,
      restoreLastUrlOnReopen: false,
      sessionStore: MemorySessionWebViewSessionStore(),
      sessionBindingValidator: (String sessionKey, String? binding) => false,
    );
    await manager.sessionStore.write(
      SessionSnapshot(
        sessionKey: 'tenant-a',
        cookies: const <WebViewCookie>[],
        cookieDomains: const <String>['shop.example.com'],
        localStorage: const <String, String>{'token': 'SHOP_TOKEN'},
        sessionStorage: const <String, String>{'tenant': 'shop'},
        lastUrl: 'https://shop.example.com/home',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );
    await manager.restoreSession('tenant-a');

    await manager.switchToSession(
      'tenant-a',
      initialUrl: 'https://auth.example.com/callback',
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SessionWebViewSwitcher(
          manager: manager,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    );
    await tester.pump();

    final FakePlatformWebView restoredView =
        fakePlatformViewsController.createdViews.last;
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();
    restoredView.fakeOnPageFinishedCallback();
    await tester.pump();

    expect(restoredView.currentUrl, 'https://auth.example.com/callback');
    expect(restoredView.storage['localStorage'], isEmpty);
    expect(restoredView.storage['sessionStorage'], isEmpty);
  });

  test('FileSessionWebViewSessionStore has a default cache file path', () {
    final FileSessionWebViewSessionStore store =
        FileSessionWebViewSessionStore();

    expect(store.filePath, FileSessionWebViewSessionStore.defaultFilePath);
    expect(
      store.filePath,
      contains('${Directory.systemTemp.path}${Platform.pathSeparator}'),
    );
    expect(store.filePath, endsWith('session_webview_sessions.json'));
  });

  testWidgets('Initial JavaScript channels', (WidgetTester tester) async {
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts', onMessageReceived: (JavascriptMessage msg) {}),
          JavascriptChannel(
              name: 'Alarm', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.javascriptChannelNames,
        unorderedEquals(<String>['Tts', 'Alarm']));
  });

  test('Only valid JavaScript channel names are allowed', () {
    final JavascriptMessageHandler noOp = (JavascriptMessage msg) {};
    JavascriptChannel(name: 'Tts1', onMessageReceived: noOp);
    JavascriptChannel(name: '_Alarm', onMessageReceived: noOp);
    JavascriptChannel(name: 'foo_bar_', onMessageReceived: noOp);

    VoidCallback createChannel(String name) {
      return () {
        JavascriptChannel(name: name, onMessageReceived: noOp);
      };
    }

    expect(createChannel('1Alarm'), throwsAssertionError);
    expect(createChannel('foo.bar'), throwsAssertionError);
    expect(createChannel(''), throwsAssertionError);
  });

  testWidgets('Unique JavaScript channel names are required',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Alarm', onMessageReceived: (JavascriptMessage msg) {}),
          JavascriptChannel(
              name: 'Alarm', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );
    expect(tester.takeException(), isNot(null));
  });

  testWidgets('JavaScript channels update', (WidgetTester tester) async {
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts', onMessageReceived: (JavascriptMessage msg) {}),
          JavascriptChannel(
              name: 'Alarm', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );

    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts', onMessageReceived: (JavascriptMessage msg) {}),
          JavascriptChannel(
              name: 'Alarm2', onMessageReceived: (JavascriptMessage msg) {}),
          JavascriptChannel(
              name: 'Alarm3', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.javascriptChannelNames,
        unorderedEquals(<String>['Tts', 'Alarm2', 'Alarm3']));
  });

  testWidgets('Remove all JavaScript channels and then add',
      (WidgetTester tester) async {
    // This covers a specific bug we had where after updating javascriptChannels to null,
    // updating it again with a subset of the previously registered channels fails as the
    // widget's cache of current channel wasn't properly updated when updating javascriptChannels to
    // null.
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );

    await tester.pumpWidget(
      const WebView(
        initialUrl: 'https://youtube.com',
      ),
    );

    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts', onMessageReceived: (JavascriptMessage msg) {}),
        },
      ),
    );

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.javascriptChannelNames,
        unorderedEquals(<String>['Tts']));
  });

  testWidgets('JavaScript channel messages', (WidgetTester tester) async {
    final List<String> ttsMessagesReceived = <String>[];
    final List<String> alarmMessagesReceived = <String>[];
    await tester.pumpWidget(
      WebView(
        initialUrl: 'https://youtube.com',
        javascriptChannels: <JavascriptChannel>{
          JavascriptChannel(
              name: 'Tts',
              onMessageReceived: (JavascriptMessage msg) {
                ttsMessagesReceived.add(msg.message);
              }),
          JavascriptChannel(
              name: 'Alarm',
              onMessageReceived: (JavascriptMessage msg) {
                alarmMessagesReceived.add(msg.message);
              }),
        },
      ),
    );

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(ttsMessagesReceived, isEmpty);
    expect(alarmMessagesReceived, isEmpty);

    platformWebView.fakeJavascriptPostMessage('Tts', 'Hello');
    platformWebView.fakeJavascriptPostMessage('Tts', 'World');

    expect(ttsMessagesReceived, <String>['Hello', 'World']);
  });

  group('$PageStartedCallback', () {
    testWidgets('onPageStarted is not null', (WidgetTester tester) async {
      String? returnedUrl;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageStarted: (String url) {
          returnedUrl = url;
        },
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      platformWebView.fakeOnPageStartedCallback();

      expect(platformWebView.currentUrl, returnedUrl);
    });

    testWidgets('onPageStarted is null', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView(
        initialUrl: 'https://youtube.com',
        onPageStarted: null,
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      // The platform side will always invoke a call for onPageStarted. This is
      // to test that it does not crash on a null callback.
      platformWebView.fakeOnPageStartedCallback();
    });

    testWidgets('onPageStarted changed', (WidgetTester tester) async {
      String? returnedUrl;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageStarted: (String url) {},
      ));

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageStarted: (String url) {
          returnedUrl = url;
        },
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      platformWebView.fakeOnPageStartedCallback();

      expect(platformWebView.currentUrl, returnedUrl);
    });
  });

  group('$PageFinishedCallback', () {
    testWidgets('onPageFinished is not null', (WidgetTester tester) async {
      String? returnedUrl;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageFinished: (String url) {
          returnedUrl = url;
        },
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      platformWebView.fakeOnPageFinishedCallback();

      expect(platformWebView.currentUrl, returnedUrl);
    });

    testWidgets('onPageFinished is null', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView(
        initialUrl: 'https://youtube.com',
        onPageFinished: null,
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      // The platform side will always invoke a call for onPageFinished. This is
      // to test that it does not crash on a null callback.
      platformWebView.fakeOnPageFinishedCallback();
    });

    testWidgets('onPageFinished changed', (WidgetTester tester) async {
      String? returnedUrl;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageFinished: (String url) {},
      ));

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onPageFinished: (String url) {
          returnedUrl = url;
        },
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      platformWebView.fakeOnPageFinishedCallback();

      expect(platformWebView.currentUrl, returnedUrl);
    });
  });

  group('$PageLoadingCallback', () {
    testWidgets('onLoadingProgress is not null', (WidgetTester tester) async {
      int? loadingProgress;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onProgress: (int progress) {
          loadingProgress = progress;
        },
      ));

      final FakePlatformWebView? platformWebView =
          fakePlatformViewsController.lastCreatedView;

      platformWebView?.fakeOnProgressCallback(50);

      expect(loadingProgress, 50);
    });

    testWidgets('onLoadingProgress is null', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView(
        initialUrl: 'https://youtube.com',
        onProgress: null,
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      // This is to test that it does not crash on a null callback.
      platformWebView.fakeOnProgressCallback(50);
    });

    testWidgets('onLoadingProgress changed', (WidgetTester tester) async {
      int? loadingProgress;

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onProgress: (int progress) {},
      ));

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        onProgress: (int progress) {
          loadingProgress = progress;
        },
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      platformWebView.fakeOnProgressCallback(50);

      expect(loadingProgress, 50);
    });
  });

  group('navigationDelegate', () {
    testWidgets('hasNavigationDelegate', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView(
        initialUrl: 'https://youtube.com',
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      expect(platformWebView.hasNavigationDelegate, false);

      await tester.pumpWidget(WebView(
        initialUrl: 'https://youtube.com',
        navigationDelegate: (NavigationRequest r) =>
            NavigationDecision.navigate,
      ));

      expect(platformWebView.hasNavigationDelegate, true);
    });

    testWidgets('Block navigation', (WidgetTester tester) async {
      final List<NavigationRequest> navigationRequests = <NavigationRequest>[];

      await tester.pumpWidget(WebView(
          initialUrl: 'https://youtube.com',
          navigationDelegate: (NavigationRequest request) {
            navigationRequests.add(request);
            // Only allow navigating to https://flutter.dev
            return request.url == 'https://flutter.dev'
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          }));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      expect(platformWebView.hasNavigationDelegate, true);

      platformWebView.fakeNavigate('https://www.google.com');
      // The navigation delegate only allows navigation to https://flutter.dev
      // so we should still be in https://youtube.com.
      expect(platformWebView.currentUrl, 'https://youtube.com');
      expect(navigationRequests.length, 1);
      expect(navigationRequests[0].url, 'https://www.google.com');
      expect(navigationRequests[0].isForMainFrame, true);

      platformWebView.fakeNavigate('https://flutter.dev');
      await tester.pump();
      expect(platformWebView.currentUrl, 'https://flutter.dev');
    });
  });

  group('debuggingEnabled', () {
    testWidgets('enable debugging', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView(
        debuggingEnabled: true,
      ));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      expect(platformWebView.debuggingEnabled, true);
    });

    testWidgets('defaults to false', (WidgetTester tester) async {
      await tester.pumpWidget(const WebView());

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      expect(platformWebView.debuggingEnabled, false);
    });

    testWidgets('can be changed', (WidgetTester tester) async {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(WebView(key: key));

      final FakePlatformWebView platformWebView =
          fakePlatformViewsController.lastCreatedView!;

      await tester.pumpWidget(WebView(
        key: key,
        debuggingEnabled: true,
      ));

      expect(platformWebView.debuggingEnabled, true);

      await tester.pumpWidget(WebView(
        key: key,
        debuggingEnabled: false,
      ));

      expect(platformWebView.debuggingEnabled, false);
    });
  });

  group('Custom platform implementation', () {
    setUpAll(() {
      WebView.platform = MyWebViewPlatform();
    });
    tearDownAll(() {
      WebView.platform = null;
    });

    testWidgets('creation', (WidgetTester tester) async {
      await tester.pumpWidget(
        const WebView(
          initialUrl: 'https://youtube.com',
          gestureNavigationEnabled: true,
        ),
      );

      final MyWebViewPlatform builder = WebView.platform as MyWebViewPlatform;
      final MyWebViewPlatformController platform = builder.lastPlatformBuilt!;

      expect(
          platform.creationParams,
          MatchesCreationParams(CreationParams(
            initialUrl: 'https://youtube.com',
            webSettings: WebSettings(
              javascriptMode: JavascriptMode.disabled,
              hasNavigationDelegate: false,
              debuggingEnabled: false,
              userAgent: WebSetting<String?>.of(null),
              gestureNavigationEnabled: true,
            ),
          )));
    });

    testWidgets('loadUrl', (WidgetTester tester) async {
      late WebViewController controller;
      await tester.pumpWidget(
        WebView(
          initialUrl: 'https://youtube.com',
          onWebViewCreated: (WebViewController webViewController) {
            controller = webViewController;
          },
        ),
      );

      final MyWebViewPlatform builder = WebView.platform as MyWebViewPlatform;
      final MyWebViewPlatformController platform = builder.lastPlatformBuilt!;

      final Map<String, String> headers = <String, String>{
        'header': 'value',
      };

      await controller.loadUrl('https://google.com', headers: headers);

      expect(platform.lastUrlLoaded, 'https://google.com');
      expect(platform.lastRequestHeaders, headers);
    });
  });
  testWidgets('Set UserAgent', (WidgetTester tester) async {
    await tester.pumpWidget(const WebView(
      initialUrl: 'https://youtube.com',
      javascriptMode: JavascriptMode.unrestricted,
    ));

    final FakePlatformWebView platformWebView =
        fakePlatformViewsController.lastCreatedView!;

    expect(platformWebView.userAgent, isNull);

    await tester.pumpWidget(const WebView(
      initialUrl: 'https://youtube.com',
      javascriptMode: JavascriptMode.unrestricted,
      userAgent: 'UA',
    ));

    expect(platformWebView.userAgent, 'UA');
  });
}

class FakePlatformWebView {
  static final Map<String, Map<String, String>> _localStorageByOrigin =
      <String, Map<String, String>>{};

  FakePlatformWebView(int? id, Map<dynamic, dynamic> params) {
    if (params.containsKey('initialUrl')) {
      final String? initialUrl = params['initialUrl'];
      if (initialUrl != null) {
        history.add(initialUrl);
        currentPosition++;
      }
    }
    if (params.containsKey('javascriptChannelNames')) {
      javascriptChannelNames =
          List<String>.from(params['javascriptChannelNames']);
    }
    javascriptMode = JavascriptMode.values[params['settings']['jsMode']];
    hasNavigationDelegate =
        params['settings']['hasNavigationDelegate'] ?? false;
    debuggingEnabled = params['settings']['debuggingEnabled'];
    userAgent = params['settings']['userAgent'];
    channel = MethodChannel(
        'plugins.flutter.io/webview_$id', const StandardMethodCodec());
    channel.setMockMethodCallHandler(onMethodCall);
  }

  late MethodChannel channel;

  List<String?> history = <String?>[];
  int currentPosition = -1;
  int amountOfReloadsOnCurrentUrl = 0;
  bool hasCache = true;
  bool throwOnEvaluateJavascript = false;
  String? binding;
  final Map<String, String> _sessionStorage = <String, String>{};
  Map<String, Map<String, String>> get storage => <String, Map<String, String>>{
        'localStorage': _localStorage,
        'sessionStorage': _sessionStorage,
      };

  Map<String, String> get _localStorage {
    final String origin = _originForUrl(currentUrl);
    return _localStorageByOrigin.putIfAbsent(
      origin,
      () => <String, String>{},
    );
  }

  String? get currentUrl => history.isEmpty ? null : history[currentPosition];
  JavascriptMode? javascriptMode;
  List<String>? javascriptChannelNames;

  bool? hasNavigationDelegate;
  bool? debuggingEnabled;
  String? userAgent;

  Future<dynamic> onMethodCall(MethodCall call) {
    switch (call.method) {
      case 'loadUrl':
        final Map<dynamic, dynamic> request = call.arguments;
        _loadUrl(request['url']);
        return Future<void>.sync(() {});
      case 'updateSettings':
        if (call.arguments['jsMode'] != null) {
          javascriptMode = JavascriptMode.values[call.arguments['jsMode']];
        }
        if (call.arguments['hasNavigationDelegate'] != null) {
          hasNavigationDelegate = call.arguments['hasNavigationDelegate'];
        }
        if (call.arguments['debuggingEnabled'] != null) {
          debuggingEnabled = call.arguments['debuggingEnabled'];
        }
        userAgent = call.arguments['userAgent'];
        break;
      case 'canGoBack':
        return Future<bool>.sync(() => currentPosition > 0);
      case 'canGoForward':
        return Future<bool>.sync(() => currentPosition < history.length - 1);
      case 'goBack':
        currentPosition = max(-1, currentPosition - 1);
        return Future<void>.sync(() {});
      case 'goForward':
        currentPosition = min(history.length - 1, currentPosition + 1);
        return Future<void>.sync(() {});
      case 'reload':
        amountOfReloadsOnCurrentUrl++;
        return Future<void>.sync(() {});
      case 'currentUrl':
        return Future<String?>.value(currentUrl);
      case 'evaluateJavascript':
        return Future<dynamic>.value(
            _evaluateJavascript(call.arguments as String));
      case 'addJavascriptChannels':
        final List<String> channelNames = List<String>.from(call.arguments);
        javascriptChannelNames!.addAll(channelNames);
        break;
      case 'removeJavascriptChannels':
        final List<String> channelNames = List<String>.from(call.arguments);
        javascriptChannelNames!
            .removeWhere((String channel) => channelNames.contains(channel));
        break;
      case 'clearCache':
        hasCache = false;
        return Future<void>.sync(() {});
    }
    return Future<void>.sync(() {});
  }

  void fakeJavascriptPostMessage(String jsChannel, String message) {
    final StandardMethodCodec codec = const StandardMethodCodec();
    final Map<String, dynamic> arguments = <String, dynamic>{
      'channel': jsChannel,
      'message': message
    };
    final ByteData data = codec
        .encodeMethodCall(MethodCall('javascriptChannelMessage', arguments));
    ServicesBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (ByteData? data) {});
  }

  // Fakes a main frame navigation that was initiated by the webview, e.g when
  // the user clicks a link in the currently loaded page.
  void fakeNavigate(String url) {
    if (!hasNavigationDelegate!) {
      print('no navigation delegate');
      _loadUrl(url);
      return;
    }
    final StandardMethodCodec codec = const StandardMethodCodec();
    final Map<String, dynamic> arguments = <String, dynamic>{
      'url': url,
      'isForMainFrame': true
    };
    final ByteData data =
        codec.encodeMethodCall(MethodCall('navigationRequest', arguments));
    ServicesBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (ByteData? data) {
      final bool allow = codec.decodeEnvelope(data!);
      if (allow) {
        _loadUrl(url);
      }
    });
  }

  void fakeOnPageStartedCallback() {
    final StandardMethodCodec codec = const StandardMethodCodec();

    final ByteData data = codec.encodeMethodCall(MethodCall(
      'onPageStarted',
      <dynamic, dynamic>{'url': currentUrl},
    ));

    ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      data,
      (ByteData? data) {},
    );
  }

  void fakeOnPageFinishedCallback() {
    final StandardMethodCodec codec = const StandardMethodCodec();

    final ByteData data = codec.encodeMethodCall(MethodCall(
      'onPageFinished',
      <dynamic, dynamic>{'url': currentUrl},
    ));

    ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      data,
      (ByteData? data) {},
    );
  }

  void fakeOnProgressCallback(int progress) {
    final StandardMethodCodec codec = const StandardMethodCodec();

    final ByteData data = codec.encodeMethodCall(MethodCall(
      'onProgress',
      <dynamic, dynamic>{'progress': progress},
    ));

    ServicesBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, data, (ByteData? data) {});
  }

  void _loadUrl(String? url) {
    history = history.sublist(0, currentPosition + 1);
    history.add(url);
    currentPosition++;
    amountOfReloadsOnCurrentUrl = 0;
  }

  static void clearLocalStorageForDomain(String domain) {
    _localStorageByOrigin.remove(_originForUrl('https://$domain/'));
    _localStorageByOrigin.remove(_originForUrl('http://$domain/'));
  }

  static void seedLocalStorage(String url, Map<String, String> values) {
    _localStorageByOrigin[_originForUrl(url)] = Map<String, String>.from(
      values,
    );
  }

  static void resetSharedStorage() {
    _localStorageByOrigin.clear();
  }

  static String _originForUrl(String? url) {
    final Uri? uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return 'about:blank';
    }
    final int? port = uri.hasPort ? uri.port : null;
    return '${uri.scheme}://${uri.host}${port == null ? '' : ':$port'}';
  }

  String _evaluateJavascript(String script) {
    if (throwOnEvaluateJavascript) {
      throw StateError('WebView is disposed');
    }
    if (script.contains('window.__sessionBinding')) {
      return binding ?? '';
    }
    final String storageName =
        script.contains('"sessionStorage"') ? 'sessionStorage' : 'localStorage';
    if (script.contains('JSON.stringify(data)')) {
      return jsonEncode(storage[storageName]);
    }
    if (script.contains('storage.clear()')) {
      final RegExp valuesPattern =
          RegExp(r'var values = (\{.*\});', dotAll: true);
      final Match? match = valuesPattern.firstMatch(script);
      final Map<String, String> target = storage[storageName]!;
      target.clear();
      if (match != null) {
        target.addAll(
          Map<String, String>.from(
            (jsonDecode(match.group(1)!) as Map<dynamic, dynamic>)
                .map((dynamic key, dynamic value) => MapEntry<String, String>(
                      key.toString(),
                      value.toString(),
                    )),
          ),
        );
      }
      return 'true';
    }
    return script;
  }
}

class _FakePlatformViewsController {
  FakePlatformWebView? lastCreatedView;
  final List<FakePlatformWebView> createdViews = <FakePlatformWebView>[];

  Future<dynamic> fakePlatformViewsMethodHandler(MethodCall call) {
    switch (call.method) {
      case 'create':
        final Map<dynamic, dynamic> args = call.arguments;
        final Map<dynamic, dynamic> params = _decodeParams(args['params'])!;
        lastCreatedView = FakePlatformWebView(
          args['id'],
          params,
        );
        createdViews.add(lastCreatedView!);
        return Future<int>.sync(() => 1);
      default:
        return Future<void>.sync(() {});
    }
  }

  void reset() {
    lastCreatedView = null;
    createdViews.clear();
    FakePlatformWebView.resetSharedStorage();
  }
}

Map<dynamic, dynamic>? _decodeParams(Uint8List paramsMessage) {
  final ByteBuffer buffer = paramsMessage.buffer;
  final ByteData messageBytes = buffer.asByteData(
    paramsMessage.offsetInBytes,
    paramsMessage.lengthInBytes,
  );
  return const StandardMessageCodec().decodeMessage(messageBytes);
}

class _FakeCookieManager {
  _FakeCookieManager() {
    final MethodChannel channel = const MethodChannel(
      'plugins.flutter.io/cookie_manager',
      StandardMethodCodec(),
    );
    channel.setMockMethodCallHandler(onMethodCall);
  }

  bool hasCookies = true;
  final Map<String, List<WebViewCookie>> cookiesByDomain =
      <String, List<WebViewCookie>>{};
  final Map<String, List<WebViewCookie>> cookiesBySession =
      <String, List<WebViewCookie>>{};

  Future<dynamic> onMethodCall(MethodCall call) {
    switch (call.method) {
      case 'clearCookies':
        bool hadCookies = false;
        if (hasCookies) {
          hadCookies = true;
          hasCookies = false;
        }
        return Future<bool>.sync(() {
          return hadCookies;
        });
      case 'clearCookiesForDomains':
        bool hadCookies = false;
        if (hasCookies) {
          hadCookies = true;
          hasCookies = false;
        }
        return Future<bool>.sync(() {
          return hadCookies;
        });
      case 'getCookiesForDomains':
        final List<String> domains =
            List<String>.from(call.arguments as List<dynamic>);
        return Future<List<Map<String, dynamic>>>.sync(() {
          return domains
              .expand((String domain) =>
                  cookiesByDomain[domain] ?? <WebViewCookie>[])
              .map((WebViewCookie cookie) => cookie.toMap())
              .toList();
        });
      case 'getCookiesForSession':
        final Map<dynamic, dynamic> values =
            call.arguments as Map<dynamic, dynamic>;
        final String sessionKey = values['sessionKey'] as String? ?? '';
        return Future<List<Map<String, dynamic>>>.sync(() {
          return (cookiesBySession[sessionKey] ?? <WebViewCookie>[])
              .map((WebViewCookie cookie) => cookie.toMap())
              .toList();
        });
      case 'setCookies':
        final List<dynamic> values =
            List<dynamic>.from(call.arguments as List<dynamic>);
        for (final dynamic value in values) {
          final WebViewCookie cookie =
              WebViewCookie.fromMap(value as Map<dynamic, dynamic>);
          final List<WebViewCookie> cookies = cookiesByDomain.putIfAbsent(
              cookie.domain, () => <WebViewCookie>[]);
          cookies.removeWhere((WebViewCookie item) => item.name == cookie.name);
          cookies.add(cookie);
        }
        return Future<bool>.sync(() => true);
      case 'setCookiesForSession':
        final Map<dynamic, dynamic> values =
            call.arguments as Map<dynamic, dynamic>;
        final String sessionKey = values['sessionKey'] as String? ?? '';
        final List<dynamic> cookieValues =
            List<dynamic>.from(values['cookies'] as List<dynamic>);
        final List<WebViewCookie> cookies =
            cookiesBySession.putIfAbsent(sessionKey, () => <WebViewCookie>[]);
        for (final dynamic value in cookieValues) {
          final WebViewCookie cookie =
              WebViewCookie.fromMap(value as Map<dynamic, dynamic>);
          cookies.removeWhere((WebViewCookie item) =>
              item.name == cookie.name &&
              item.domain == cookie.domain &&
              item.path == cookie.path);
          cookies.add(cookie);
        }
        return Future<bool>.sync(() => true);
      case 'clearWebsiteDataForDomains':
        final Map<dynamic, dynamic> values =
            call.arguments as Map<dynamic, dynamic>;
        final List<String> domains =
            List<String>.from(values['domains'] as List<dynamic>);
        final bool includeCookies = values['includeCookies'] as bool? ?? true;
        final bool includeLocalStorage =
            values['includeLocalStorage'] as bool? ?? true;
        if (includeCookies) {
          for (final String domain in domains) {
            cookiesByDomain.remove(domain);
          }
        }
        if (includeLocalStorage) {
          for (final String domain in domains) {
            FakePlatformWebView.clearLocalStorageForDomain(domain);
          }
        }
        return Future<bool>.sync(() => true);
      case 'clearWebsiteDataForSession':
        final Map<dynamic, dynamic> values =
            call.arguments as Map<dynamic, dynamic>;
        final String sessionKey = values['sessionKey'] as String? ?? '';
        final bool includeCookies = values['includeCookies'] as bool? ?? true;
        final bool includeLocalStorage =
            values['includeLocalStorage'] as bool? ?? true;
        if (includeCookies) {
          cookiesBySession.remove(sessionKey);
        }
        if (includeLocalStorage) {
          FakePlatformWebView.resetSharedStorage();
        }
        return Future<bool>.sync(() => true);
      case 'clearWebsiteData':
        final Map<dynamic, dynamic> values =
            call.arguments as Map<dynamic, dynamic>;
        final bool includeCookies = values['includeCookies'] as bool? ?? true;
        final bool includeLocalStorage =
            values['includeLocalStorage'] as bool? ?? true;
        if (includeCookies) {
          cookiesByDomain.clear();
          cookiesBySession.clear();
          hasCookies = false;
        }
        if (includeLocalStorage) {
          FakePlatformWebView.resetSharedStorage();
        }
        return Future<bool>.sync(() => true);
    }
    return Future<bool>.sync(() => true);
  }

  void reset() {
    hasCookies = true;
    cookiesByDomain.clear();
    cookiesBySession.clear();
  }

  void setCookiesForDomain(String domain, List<WebViewCookie> cookies) {
    cookiesByDomain[domain] = List<WebViewCookie>.from(cookies);
  }

  List<WebViewCookie> getCookiesForDomain(String domain) {
    return cookiesByDomain[domain] ?? <WebViewCookie>[];
  }

  void setCookiesForSession(String sessionKey, List<WebViewCookie> cookies) {
    cookiesBySession[sessionKey] = List<WebViewCookie>.from(cookies);
  }

  List<WebViewCookie> getCookiesForSession(String sessionKey) {
    return cookiesBySession[sessionKey] ?? <WebViewCookie>[];
  }
}

class MyWebViewPlatform implements WebViewPlatform {
  MyWebViewPlatformController? lastPlatformBuilt;

  @override
  Widget build({
    BuildContext? context,
    CreationParams? creationParams,
    required WebViewPlatformCallbacksHandler webViewPlatformCallbacksHandler,
    WebViewPlatformCreatedCallback? onWebViewPlatformCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    assert(onWebViewPlatformCreated != null);
    lastPlatformBuilt = MyWebViewPlatformController(
        creationParams, gestureRecognizers, webViewPlatformCallbacksHandler);
    onWebViewPlatformCreated!(lastPlatformBuilt);
    return Container();
  }

  @override
  Future<bool> clearCookies() {
    return Future<bool>.sync(() => true);
  }

  @override
  Future<bool> clearCookiesForDomains(List<String> domains) {
    return Future<bool>.sync(() => true);
  }

  @override
  Future<bool> clearWebsiteDataForDomains(
    List<String> domains, {
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) {
    return Future<bool>.sync(() => true);
  }

  @override
  Future<List<WebViewCookie>> getCookiesForDomains(List<String> domains) {
    return Future<List<WebViewCookie>>.sync(() => <WebViewCookie>[]);
  }

  @override
  Future<List<WebViewCookie>> getCookiesForSession(String sessionKey) {
    return Future<List<WebViewCookie>>.sync(() => <WebViewCookie>[]);
  }

  @override
  Future<void> setCookies(List<WebViewCookie> cookies) {
    return Future<void>.sync(() {});
  }

  @override
  Future<void> setCookiesForSession(
    String sessionKey,
    List<WebViewCookie> cookies,
  ) {
    return Future<void>.sync(() {});
  }

  @override
  Future<bool> clearWebsiteDataForSession(
    String sessionKey, {
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) {
    return Future<bool>.sync(() => true);
  }

  @override
  Future<bool> clearWebsiteData({
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) {
    return Future<bool>.sync(() => true);
  }
}

class _SessionCookiePlatform extends MyWebViewPlatform {
  _SessionCookiePlatform(this.cookieManager);

  final _FakeCookieManager cookieManager;

  @override
  Future<List<WebViewCookie>> getCookiesForSession(String sessionKey) {
    return Future<List<WebViewCookie>>.sync(
      () => cookieManager.getCookiesForSession(sessionKey),
    );
  }

  @override
  Future<void> setCookiesForSession(
    String sessionKey,
    List<WebViewCookie> cookies,
  ) {
    return Future<void>.sync(
      () => cookieManager.setCookiesForSession(sessionKey, cookies),
    );
  }
}

class MyWebViewPlatformController extends WebViewPlatformController {
  MyWebViewPlatformController(this.creationParams, this.gestureRecognizers,
      WebViewPlatformCallbacksHandler platformHandler)
      : super(platformHandler);

  CreationParams? creationParams;
  Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  String? lastUrlLoaded;
  Map<String, String>? lastRequestHeaders;

  @override
  Future<void> loadUrl(String url, Map<String, String>? headers) async {
    equals(1, 1);
    lastUrlLoaded = url;
    lastRequestHeaders = headers;
  }
}

class MatchesWebSettings extends Matcher {
  MatchesWebSettings(this._webSettings);

  final WebSettings? _webSettings;

  @override
  Description describe(Description description) =>
      description.add('$_webSettings');

  @override
  bool matches(
      covariant WebSettings webSettings, Map<dynamic, dynamic> matchState) {
    return _webSettings!.javascriptMode == webSettings.javascriptMode &&
        _webSettings!.hasNavigationDelegate ==
            webSettings.hasNavigationDelegate &&
        _webSettings!.debuggingEnabled == webSettings.debuggingEnabled &&
        _webSettings!.gestureNavigationEnabled ==
            webSettings.gestureNavigationEnabled &&
        _webSettings!.userAgent == webSettings.userAgent;
  }
}

class MatchesCreationParams extends Matcher {
  MatchesCreationParams(this._creationParams);

  final CreationParams _creationParams;

  @override
  Description describe(Description description) =>
      description.add('$_creationParams');

  @override
  bool matches(covariant CreationParams creationParams,
      Map<dynamic, dynamic> matchState) {
    return _creationParams.initialUrl == creationParams.initialUrl &&
        MatchesWebSettings(_creationParams.webSettings)
            .matches(creationParams.webSettings!, matchState) &&
        orderedEquals(_creationParams.javascriptChannelNames)
            .matches(creationParams.javascriptChannelNames, matchState);
  }
}
