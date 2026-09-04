// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "WebViewProFlutterPlugin.h"
#import "FLCookieManager.h"
#import "FlutterWebView.h"

@implementation WebViewProFlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* proxyChannel = [FlutterMethodChannel
      methodChannelWithName:@"plugins.flutter.io/webview_proxy"
            binaryMessenger:registrar.messenger];
  [proxyChannel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
    if ([call.method isEqualToString:@"setProxy"]) {
      // WKWebView does not expose an app-level proxy override. It follows the
      // system proxy configuration instead.
      result(nil);
    } else {
      result(FlutterMethodNotImplemented);
    }
  }];

  FLWebViewFactory* mywebviewFactory =
      [[FLWebViewFactory alloc] initWithMessenger:registrar.messenger];
  [registrar registerViewFactory:mywebviewFactory withId:@"plugins.flutter.io/webview"];
  [FLCookieManager registerWithRegistrar:registrar];
}

@end
