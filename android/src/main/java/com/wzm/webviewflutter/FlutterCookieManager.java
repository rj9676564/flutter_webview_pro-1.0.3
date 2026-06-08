// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.content.Context;
import android.os.Build;
import android.os.Build.VERSION_CODES;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebStorage;
import android.webkit.WebView;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

class FlutterCookieManager implements MethodCallHandler {
  private final MethodChannel methodChannel;
  private final Context context;

  FlutterCookieManager(BinaryMessenger messenger, Context context) {
    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/cookie_manager");
    methodChannel.setMethodCallHandler(this);
    this.context = context;
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
      case "clearWebsiteDataForDomains":
        clearWebsiteDataForDomains(methodCall.arguments, result);
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

  private void clearWebsiteDataForDomains(final Object arguments, final Result result) {
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "Expected a map of website data options", null);
      return;
    }

    final Map<?, ?> options = (Map<?, ?>) arguments;
    final Object domainsValue = options.get("domains");
    if (!(domainsValue instanceof List)) {
      result.error("invalid_arguments", "Expected a list of domains", null);
      return;
    }

    final boolean includeCookies = readBoolean(options, "includeCookies", true);
    final boolean includeLocalStorage = readBoolean(options, "includeLocalStorage", true);
    final boolean includeCache = readBoolean(options, "includeCache", true);
    final List<?> domains = (List<?>) domainsValue;
    final Set<String> hosts = normalizedHosts(domains);
    if (hosts.isEmpty()) {
      result.success(false);
      return;
    }

    final boolean hadData = clearWebsiteDataForHosts(
        hosts,
        includeCookies,
        includeCache);
    if (!includeLocalStorage) {
      result.success(hadData);
      return;
    }

    clearLocalStorageForHosts(
        hosts,
        new ValueCallback<Boolean>() {
          @Override
          public void onReceiveValue(Boolean hadLocalStorage) {
            result.success(hadData || Boolean.TRUE.equals(hadLocalStorage));
          }
        });
  }

  private boolean clearWebsiteDataForHosts(
      Set<String> hosts,
      boolean includeCookies,
      boolean includeCache) {
    boolean hadData = false;
    if (includeCookies) {
      CookieManager cookieManager = CookieManager.getInstance();
      for (String host : hosts) {
        hadData |= clearCookiesForHost(cookieManager, host);
      }
    }
    if (includeCache) {
      hadData |= clearHttpCache();
    }
    return hadData;
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
        return uri.getHost().toLowerCase(Locale.US);
      }
    } catch (URISyntaxException ignored) {
      // Fall through and treat the input as a host name.
    }
    return domain.toLowerCase(Locale.US);
  }

  private static Set<String> normalizedHosts(List<?> domains) {
    Set<String> hosts = new HashSet<>();
    for (Object domain : domains) {
      if (domain == null) {
        continue;
      }
      String host = normalizeHost(domain.toString().trim());
      if (host != null && !host.isEmpty()) {
        hosts.add(host);
      }
    }
    return hosts;
  }

  private static boolean readBoolean(Map<?, ?> options, String key, boolean defaultValue) {
    Object value = options.get(key);
    return value instanceof Boolean ? (Boolean) value : defaultValue;
  }

  private static void clearLocalStorageForHosts(
      final Set<String> hosts,
      final ValueCallback<Boolean> callback) {
    final WebStorage webStorage = WebStorage.getInstance();
    webStorage.getOrigins(
        new ValueCallback<Map>() {
          @Override
          public void onReceiveValue(Map origins) {
            boolean hadData = false;
            if (origins != null) {
              for (Object key : origins.keySet()) {
                if (key == null) {
                  continue;
                }
                String origin = key.toString();
                String originHost = normalizeHost(origin);
                if (hostMatchesAnyDomain(originHost, hosts)) {
                  webStorage.deleteOrigin(origin);
                  hadData = true;
                }
              }
            }
            callback.onReceiveValue(hadData);
          }
        });
  }

  private static boolean hostMatchesAnyDomain(String host, Set<String> domains) {
    if (host == null || host.isEmpty()) {
      return false;
    }
    for (String domain : domains) {
      if (host.equals(domain) || host.endsWith("." + domain)) {
        return true;
      }
    }
    return false;
  }

  private boolean clearHttpCache() {
    if (context == null) {
      return false;
    }
    WebView webView = new WebView(context);
    webView.clearCache(true);
    webView.destroy();
    return true;
  }
}
