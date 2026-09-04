// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.app.Activity;
import android.content.Intent;

import android.util.Log;
import androidx.webkit.ProxyConfig;
import androidx.webkit.ProxyController;
import androidx.webkit.WebViewFeature;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Java platform implementation of the webview_flutter plugin.
 *
 * <p>Register this in an add to app scenario to gracefully handle activity and context changes.
 */
public class WebViewFlutterPlugin implements FlutterPlugin , PluginRegistry.ActivityResultListener,PluginRegistry.RequestPermissionsResultListener, ActivityAware{
  private static final String TAG = "WebViewFlutterPlugin";
  private FlutterCookieManager flutterCookieManager;
  private MethodChannel webViewProxyChannel;
  public static Activity activity;
  private WebViewFactory factory;

  /**
   * Add an instance of this to {@link io.flutter.embedding.engine.plugins.PluginRegistry} to
   * register it.
   *
   * <p>Registration should eventually be handled automatically by v2 of the
   * GeneratedPluginRegistrant. https://github.com/flutter/flutter/issues/42694
   */
  public WebViewFlutterPlugin() {}

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    BinaryMessenger messenger = binding.getBinaryMessenger();
    factory = new WebViewFactory(messenger, null);
    binding
        .getPlatformViewRegistry()
        .registerViewFactory(
            "plugins.flutter.io/webview", factory);
    flutterCookieManager = new FlutterCookieManager(messenger, binding.getApplicationContext());
    webViewProxyChannel = new MethodChannel(messenger, "plugins.flutter.io/webview_proxy");
    webViewProxyChannel.setMethodCallHandler((call, result) -> {
      if (!"setProxy".equals(call.method)) {
        result.notImplemented();
        return;
      }

      if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
        Log.w(TAG, "WebViewFeature.PROXY_OVERRIDE is not supported on this device.");
        result.success(null);
        return;
      }

      try {
        String proxy = call.argument("proxy");
        if (proxy == null || proxy.trim().isEmpty()) {
          Log.i(TAG, "Clearing WebView proxy override.");
          ProxyController.getInstance().clearProxyOverride(
              Runnable::run,
              () -> {
                Log.i(TAG, "WebView proxy override cleared.");
                result.success(null);
              });
        } else {
          proxy = proxy.trim();
          String proxyUrl = proxy.contains("://") ? proxy : "http://" + proxy;
          Log.i(TAG, "Setting WebView proxy override to " + proxyUrl);
          ProxyConfig proxyConfig = new ProxyConfig.Builder()
              .addProxyRule(proxyUrl)
              .addDirect()
              .build();
          ProxyController.getInstance().setProxyOverride(
              proxyConfig,
              Runnable::run,
              () -> {
                Log.i(TAG, "WebView proxy override applied.");
                result.success(null);
              });
        }
      } catch (Exception e) {
        Log.e(TAG, "Failed to set webview proxy", e);
        result.error("PROXY_ERROR", e.getMessage(), null);
      }
    });
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (flutterCookieManager == null) {
      return;
    }
    activity = null;
    flutterCookieManager.dispose();
    flutterCookieManager = null;
    if (webViewProxyChannel != null) {
      webViewProxyChannel.setMethodCallHandler(null);
      webViewProxyChannel = null;
    }
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    Log.v(TAG,"onActivityResult");
    if (factory != null && factory.getFlutterWebView() != null){
      return factory.getFlutterWebView().activityResult(requestCode, resultCode, data);
    }

    return false;
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    Log.v(TAG,"onAttachedToActivity");
    activity = binding.getActivity();
    binding.addActivityResultListener(this);
    binding.addRequestPermissionsResultListener(this);
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    Log.v(TAG,"onDetachedFromActivityForConfigChanges");
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    Log.v(TAG,"onReattachedToActivityForConfigChanges");
  }

  @Override
  public void onDetachedFromActivity() {
    Log.v(TAG,"onDetachedFromActivity");
  }

  @Override
  public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
    Log.v(TAG,"onRequestPermissionsResult");
    if (factory != null && factory.getFlutterWebView() != null){
      return factory.getFlutterWebView().requestPermissionsResult(requestCode, permissions, grantResults);
    }

    return false;
  }
}
