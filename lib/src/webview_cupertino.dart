// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../platform_interface.dart';
import 'webview_method_channel.dart';

/// Builds an iOS webview.
///
/// This is used as the default implementation for [WebView.platform] on iOS. It uses
/// a [UiKitView] to embed the webview in the widget hierarchy, and uses a method channel to
/// communicate with the platform code.
class CupertinoWebView implements WebViewPlatform {
  @override
  Widget build({
    required BuildContext context,
    required CreationParams creationParams,
    required WebViewPlatformCallbacksHandler webViewPlatformCallbacksHandler,
    WebViewPlatformCreatedCallback? onWebViewPlatformCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  }) {
    return UiKitView(
      viewType: 'plugins.flutter.io/webview',
      onPlatformViewCreated: (int id) {
        if (onWebViewPlatformCreated == null) {
          return;
        }
        onWebViewPlatformCreated(
            MethodChannelWebViewPlatform(id, webViewPlatformCallbacksHandler));
      },
      gestureRecognizers: gestureRecognizers,
      creationParams:
          MethodChannelWebViewPlatform.creationParamsToMap(creationParams),
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  @override
  Future<bool> clearCookies() => MethodChannelWebViewPlatform.clearCookies();

  @override
  Future<bool> clearCookiesForDomains(List<String> domains) =>
      MethodChannelWebViewPlatform.clearCookiesForDomains(domains);

  @override
  Future<List<WebViewCookie>> getCookiesForDomains(List<String> domains) =>
      MethodChannelWebViewPlatform.getCookiesForDomains(domains);

  @override
  Future<List<WebViewCookie>> getCookiesForSession(String sessionKey) =>
      MethodChannelWebViewPlatform.getCookiesForSession(sessionKey);

  @override
  Future<void> setCookies(List<WebViewCookie> cookies) =>
      MethodChannelWebViewPlatform.setCookies(cookies);

  @override
  Future<void> setCookiesForSession(
    String sessionKey,
    List<WebViewCookie> cookies,
  ) =>
      MethodChannelWebViewPlatform.setCookiesForSession(sessionKey, cookies);

  @override
  Future<bool> clearWebsiteDataForDomains(
    List<String> domains, {
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) =>
      MethodChannelWebViewPlatform.clearWebsiteDataForDomains(
        domains,
        includeCookies: includeCookies,
        includeLocalStorage: includeLocalStorage,
        includeCache: includeCache,
      );

  @override
  Future<bool> clearWebsiteDataForSession(
    String sessionKey, {
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) =>
      MethodChannelWebViewPlatform.clearWebsiteDataForSession(
        sessionKey,
        includeCookies: includeCookies,
        includeLocalStorage: includeLocalStorage,
        includeCache: includeCache,
      );

  @override
  Future<bool> clearWebsiteData({
    bool includeCookies = true,
    bool includeLocalStorage = true,
    bool includeCache = true,
  }) =>
      MethodChannelWebViewPlatform.clearWebsiteData(
        includeCookies: includeCookies,
        includeLocalStorage: includeLocalStorage,
        includeCache: includeCache,
      );
}
