// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.os.Build;
import android.os.Build.VERSION_CODES;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.List;
import java.util.Locale;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

class FlutterCookieManager implements MethodCallHandler {
  private final MethodChannel methodChannel;

  FlutterCookieManager(BinaryMessenger messenger) {
    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/cookie_manager");
    methodChannel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(MethodCall methodCall, Result result) {
    switch (methodCall.method) {
      case "clearCookies":
        clearCookies(result);
        break;
      case "clearCookiesForDomains":
        clearCookiesForDomains(methodCall.arguments, result);
        break;
      default:
        result.notImplemented();
    }
  }

  void dispose() {
    methodChannel.setMethodCallHandler(null);
  }

  private static void clearCookies(final Result result) {
    CookieManager cookieManager = CookieManager.getInstance();
    final boolean hasCookies = cookieManager.hasCookies();
    if (Build.VERSION.SDK_INT >= VERSION_CODES.LOLLIPOP) {
      cookieManager.removeAllCookies(
          new ValueCallback<Boolean>() {
            @Override
            public void onReceiveValue(Boolean value) {
              result.success(hasCookies);
            }
          });
    } else {
      cookieManager.removeAllCookie();
      result.success(hasCookies);
    }
  }

  private static void clearCookiesForDomains(final Object arguments, final Result result) {
    if (!(arguments instanceof List)) {
      result.error("invalid_arguments", "Expected a list of domains", null);
      return;
    }

    CookieManager cookieManager = CookieManager.getInstance();
    final List<?> domains = (List<?>) arguments;
    boolean hadCookies = false;
    for (Object domain : domains) {
      if (domain == null) {
        continue;
      }
      String host = normalizeHost(domain.toString());
      if (host == null || host.isEmpty()) {
        continue;
      }
      hadCookies |= clearCookiesForHost(cookieManager, host);
    }

    result.success(hadCookies);
  }

  private static boolean clearCookiesForHost(CookieManager cookieManager, String host) {
    boolean hadCookies = false;
    String[] schemes = new String[] {"https", "http"};
    for (String scheme : schemes) {
      String url = scheme + "://" + host + "/";
      String cookieHeader = cookieManager.getCookie(url);
      if (cookieHeader == null || cookieHeader.isEmpty()) {
        continue;
      }
      hadCookies = true;
      String[] cookies = cookieHeader.split(";");
      for (String rawCookie : cookies) {
        String cookie = rawCookie.trim();
        if (cookie.isEmpty()) {
          continue;
        }
        int equalsIndex = cookie.indexOf('=');
        if (equalsIndex <= 0) {
          continue;
        }
        String name = cookie.substring(0, equalsIndex);
        String expiredCookie = String.format(
            Locale.US,
            "%s=; Max-Age=0; Path=/; Domain=%s",
            name,
            host);
        cookieManager.setCookie(url, expiredCookie);
      }
    }
    return hadCookies;
  }

  private static String normalizeHost(String domain) {
    try {
      URI uri = new URI(domain);
      if (uri.getHost() != null) {
        return uri.getHost();
      }
    } catch (URISyntaxException ignored) {
      // Fall through and treat the input as a host name.
    }
    return domain;
  }
}
