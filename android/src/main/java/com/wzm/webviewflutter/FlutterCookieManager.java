// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.content.Context;
import android.os.Build;
import android.os.Build.VERSION_CODES;
import android.webkit.CookieManager;
import android.webkit.CookieSyncManager;
import android.webkit.ValueCallback;
import android.webkit.WebStorage;
import android.webkit.WebView;
import java.text.SimpleDateFormat;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.LinkedHashSet;
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

  private static class CookieWrite {
    final String url;
    final String header;

    CookieWrite(String url, String header) {
      this.url = url;
      this.header = header;
    }
  }

  FlutterCookieManager(BinaryMessenger messenger, Context context) {
    methodChannel = new MethodChannel(messenger, "plugins.flutter.io/cookie_manager");
    methodChannel.setMethodCallHandler(this);
    this.context = context;
    if (Build.VERSION.SDK_INT < VERSION_CODES.LOLLIPOP && context != null) {
      CookieSyncManager.createInstance(context);
    }
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
      case "getCookiesForDomains":
        getCookiesForDomains(methodCall.arguments, result);
        break;
      case "getCookiesForSession":
        getCookiesForSession(methodCall.arguments, result);
        break;
      case "setCookies":
        setCookies(methodCall.arguments, result);
        break;
      case "setCookiesForSession":
        setCookiesForSession(methodCall.arguments, result);
        break;
      case "clearWebsiteDataForDomains":
        clearWebsiteDataForDomains(methodCall.arguments, result);
        break;
      case "clearWebsiteDataForSession":
        clearWebsiteDataForSession(methodCall.arguments, result);
        break;
      case "clearWebsiteData":
        clearWebsiteData(methodCall.arguments, result);
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
    flushCookies(cookieManager);

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

  private void clearWebsiteData(final Object arguments, final Result result) {
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "Expected a map of website data options", null);
      return;
    }

    final Map<?, ?> options = (Map<?, ?>) arguments;
    final boolean includeCookies = readBoolean(options, "includeCookies", true);
    final boolean includeLocalStorage = readBoolean(options, "includeLocalStorage", true);
    final boolean includeCache = readBoolean(options, "includeCache", true);

    boolean hadData = false;
    if (includeCookies) {
      CookieManager cookieManager = CookieManager.getInstance();
      hadData |= cookieManager.hasCookies();
      if (Build.VERSION.SDK_INT >= VERSION_CODES.LOLLIPOP) {
        cookieManager.removeAllCookies(null);
      } else {
        cookieManager.removeAllCookie();
      }
      flushCookies(cookieManager);
    }
    if (includeLocalStorage) {
      WebStorage.getInstance().deleteAllData();
      hadData = true;
    }
    if (includeCache) {
      hadData |= clearHttpCache();
    }
    result.success(hadData);
  }

  private static void getCookiesForDomains(final Object arguments, final Result result) {
    if (!(arguments instanceof List)) {
      result.error("invalid_arguments", "Expected a list of domains", null);
      return;
    }

    CookieManager cookieManager = CookieManager.getInstance();
    final Set<String> hosts = normalizedHosts((List<?>) arguments);
    List<Map<String, Object>> cookies = new ArrayList<>();
    for (String host : hosts) {
      cookies.addAll(readCookiesForHost(cookieManager, host));
    }
    result.success(cookies);
  }

  private static void getCookiesForSession(final Object arguments, final Result result) {
    result.error(
        "unsupported_operation",
        "Android WebView exposes one process-wide CookieManager; per-session cookies are not supported.",
        null);
  }

  private static void setCookies(final Object arguments, final Result result) {
    if (!(arguments instanceof List)) {
      result.error("invalid_arguments", "Expected a list of cookies", null);
      return;
    }

    CookieManager cookieManager = CookieManager.getInstance();
    final List<CookieWrite> writes = cookieWritesFromList((List<?>) arguments);
    writeCookies(cookieManager, writes, result);
  }

  private static void setCookiesForSession(final Object arguments, final Result result) {
    result.error(
        "unsupported_operation",
        "Android WebView exposes one process-wide CookieManager; per-session cookies are not supported.",
        null);
  }

  private void clearWebsiteDataForSession(final Object arguments, final Result result) {
    result.error(
        "unsupported_operation",
        "Android WebView data is process-global in this plugin; per-session clearing is not supported.",
        null);
  }

  private static List<CookieWrite> cookieWritesFromList(final List<?> cookieList) {
    final List<CookieWrite> writes = new ArrayList<>();
    for (Object cookieValue : cookieList) {
      if (!(cookieValue instanceof Map)) {
        continue;
      }
      @SuppressWarnings("unchecked")
      Map<String, Object> cookie = (Map<String, Object>) cookieValue;
      String domain = stringValue(cookie.get("domain"));
      String name = stringValue(cookie.get("name"));
      if (domain == null || domain.isEmpty() || name == null || name.isEmpty()) {
        continue;
      }
      String host = normalizeHost(domain);
      if (host == null || host.isEmpty()) {
        continue;
      }
      String scheme = Boolean.TRUE.equals(cookie.get("isSecure")) ? "https" : "http";
      String url = scheme + "://" + host + "/";
      writes.add(new CookieWrite(url, buildCookieHeader(cookie, host)));
    }
    return writes;
  }

  private static void writeCookies(
      final CookieManager cookieManager,
      final List<CookieWrite> writes,
      final Result result) {
    if (writes.isEmpty()) {
      flushCookies(cookieManager);
      result.success(null);
      return;
    }
    if (Build.VERSION.SDK_INT < VERSION_CODES.LOLLIPOP) {
      for (CookieWrite write : writes) {
        cookieManager.setCookie(write.url, write.header);
      }
      flushCookies(cookieManager);
      result.success(null);
      return;
    }

    final int[] pending = new int[] {writes.size()};
    final boolean[] completed = new boolean[] {false};
    final ValueCallback<Boolean> callback =
        new ValueCallback<Boolean>() {
          @Override
          public void onReceiveValue(Boolean value) {
            pending[0] -= 1;
            if (pending[0] == 0 && !completed[0]) {
              completed[0] = true;
              flushCookies(cookieManager);
              result.success(null);
            }
          }
        };
    for (CookieWrite write : writes) {
      cookieManager.setCookie(write.url, write.header, callback);
    }
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
      flushCookies(cookieManager);
    }
    if (includeCache) {
      hadData |= clearHttpCache();
    }
    return hadData;
  }

  private static boolean clearCookiesForHost(CookieManager cookieManager, String host) {
    boolean hadCookies = false;
    String[] schemes = new String[] {"https", "http"};
    final Set<String> domainsToExpire = cookieDomainVariants(host);
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
        cookieManager.setCookie(
            url,
            String.format(
                Locale.US,
                "%s=; Max-Age=0; Path=/",
                name));
        for (String domain : domainsToExpire) {
          String expiredCookie = String.format(
              Locale.US,
              "%s=; Max-Age=0; Path=/; Domain=%s",
              name,
              domain);
          cookieManager.setCookie(url, expiredCookie);
          cookieManager.setCookie(
              url,
              String.format(
                  Locale.US,
                  "%s=; Max-Age=0; Path=/; Domain=.%s",
                  name,
                  domain));
        }
      }
    }
    return hadCookies;
  }

  private static Set<String> cookieDomainVariants(String host) {
    final LinkedHashSet<String> domains = new LinkedHashSet<>();
    if (host == null || host.isEmpty()) {
      return domains;
    }
    final String[] parts = host.split("\\.");
    for (int index = 0; index < parts.length - 1; index++) {
      final StringBuilder builder = new StringBuilder();
      for (int partIndex = index; partIndex < parts.length; partIndex++) {
        if (builder.length() > 0) {
          builder.append('.');
        }
        builder.append(parts[partIndex]);
      }
      final String domain = builder.toString();
      if (!domain.isEmpty()) {
        domains.add(domain);
      }
    }
    return domains;
  }

  private static List<Map<String, Object>> readCookiesForHost(
      CookieManager cookieManager, String host) {
    List<Map<String, Object>> cookies = new ArrayList<>();
    Set<String> seenNames = new HashSet<>();
    String[] schemes = new String[] {"https", "http"};
    for (String scheme : schemes) {
      String url = scheme + "://" + host + "/";
      String cookieHeader = cookieManager.getCookie(url);
      if (cookieHeader == null || cookieHeader.isEmpty()) {
        continue;
      }
      String[] cookieEntries = cookieHeader.split(";");
      for (String rawCookie : cookieEntries) {
        String cookie = rawCookie.trim();
        if (cookie.isEmpty()) {
          continue;
        }
        int equalsIndex = cookie.indexOf('=');
        if (equalsIndex <= 0) {
          continue;
        }
        String name = cookie.substring(0, equalsIndex);
        if (seenNames.contains(name)) {
          continue;
        }
        seenNames.add(name);
        Map<String, Object> cookieMap = new java.util.HashMap<>();
        cookieMap.put("name", name);
        cookieMap.put("value", cookie.substring(equalsIndex + 1));
        cookieMap.put("domain", host);
        cookieMap.put("path", "/");
        cookieMap.put("isSecure", scheme.equals("https"));
        cookieMap.put("isHttpOnly", false);
        cookieMap.put("expiresDate", null);
        cookies.add(cookieMap);
      }
    }
    return cookies;
  }

  private static void flushCookies(CookieManager cookieManager) {
    if (Build.VERSION.SDK_INT >= VERSION_CODES.LOLLIPOP) {
      cookieManager.flush();
    } else {
      try {
        CookieSyncManager.getInstance().sync();
      } catch (IllegalStateException ignored) {
        // CookieSyncManager requires createInstance(context) before getInstance().
      }
    }
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

  private static String stringValue(Object value) {
    return value == null ? null : value.toString();
  }

  private static String buildCookieHeader(Map<String, Object> cookie, String host) {
    StringBuilder builder = new StringBuilder();
    builder.append(stringValue(cookie.get("name")))
        .append("=")
        .append(stringValue(cookie.get("value")));

    if (host != null && !host.isEmpty()) {
      builder.append("; Domain=").append(host);
    }

    String path = stringValue(cookie.get("path"));
    builder.append("; Path=").append(path == null || path.isEmpty() ? "/" : path);

    if (Boolean.TRUE.equals(cookie.get("isSecure"))) {
      builder.append("; Secure");
    }
    if (Boolean.TRUE.equals(cookie.get("isHttpOnly"))) {
      builder.append("; HttpOnly");
    }

    Object expiresDate = cookie.get("expiresDate");
    if (expiresDate instanceof Number) {
      builder.append("; Expires=").append(formatExpires(((Number) expiresDate).longValue()));
    }
    return builder.toString();
  }

  private static String formatExpires(long timestampMillis) {
    SimpleDateFormat format =
        new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US);
    format.setTimeZone(java.util.TimeZone.getTimeZone("GMT"));
    return format.format(new Date(timestampMillis));
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
