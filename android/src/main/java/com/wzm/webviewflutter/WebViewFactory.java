// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.content.Context;
import android.view.View;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

public final class WebViewFactory extends PlatformViewFactory {
  private final BinaryMessenger messenger;
  private final View containerView;
  private FlutterWebView flutterWebView;
  // 多会话下会同时存在多个 WebView，activity/权限结果需要分发给所有存活的实例
  private final List<FlutterWebView> webViews = new CopyOnWriteArrayList<>();

  WebViewFactory(BinaryMessenger messenger, View containerView) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
    this.containerView = containerView;
  }

  @SuppressWarnings("unchecked")
  @Override
  public PlatformView create(Context context, int id, Object args) {
    Map<String, Object> params = (Map<String, Object>) args;
    flutterWebView = new FlutterWebView(context, messenger, id, params, containerView);
    webViews.add(flutterWebView);
    return flutterWebView;
  }

  /** 返回所有未销毁的 WebView，并顺带清理已销毁的。 */
  public List<FlutterWebView> getActiveWebViews() {
    List<FlutterWebView> active = new ArrayList<>();
    for (FlutterWebView webView : webViews) {
      if (webView.isDisposed()) {
        webViews.remove(webView);
      } else {
        active.add(webView);
      }
    }
    return active;
  }

  public FlutterWebView getFlutterWebView() {
    return flutterWebView;
  }
}
