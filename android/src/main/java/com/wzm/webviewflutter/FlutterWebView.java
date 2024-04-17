// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.wzm.webviewflutter;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Context;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Message;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.webkit.GeolocationPermissions;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import android.webkit.JsPromptResult;

import java.io.File;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import androidx.annotation.NonNull;
import androidx.annotation.Size;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.platform.PlatformView;
import util.FileUtil;

import android.content.pm.PackageManager;

public class FlutterWebView implements PlatformView, MethodCallHandler {
    private static final String TAG = "FlutterWebView";

    private static final String JS_CHANNEL_NAMES_FIELD = "javascriptChannelNames";
    private final WebView webView;
    private final MethodChannel methodChannel;
    private final FlutterWebViewClient flutterWebViewClient;
    private final Handler platformThreadHandler;

    private ValueCallback<Uri> uploadMessage;
    private ValueCallback<Uri[]> uploadMessageAboveL;
    private WebChromeClient.FileChooserParams fileChooserParams;
    private String acceptType;
    private final static int FILE_CHOOSER_RESULT_CODE = 10000;
    public static final int RESULT_OK = -1;

    private String[] perms = {Manifest.permission.CAMERA};
    private static final int REQUEST_CAMERA = 1;
    private static final int REQUEST_LOCATION = 100;
    private Uri cameraUri;
    private static final int PERMISSION_QUEST_TRTC_CAMERA_VERIFY = 12;//trtc模式的权限申请
    private static final int PERMISSION_QUEST_OLD_CAMERA_VERIFY = 11;//录制模式的权限申请
    // Verifies that a url opened by `Window.open` has a secure url.
    private class FlutterWebChromeClient extends WebChromeClient {
        private PermissionRequest request;
        private boolean belowApi21;// android 5.0以下系统

        private int checkSdkPermission(String permission) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                int permissionResult = ContextCompat.checkSelfPermission(WebViewFlutterPlugin.activity, permission);
                Log.d(TAG, "checkSdkPermission >=23 " + permissionResult + " permission=" + permission);
                return permissionResult;
            } else {
                int permissionResult = WebViewFlutterPlugin.activity.getPackageManager().checkPermission(permission, WebViewFlutterPlugin.activity.getPackageName());
                Log.d(TAG, "checkSdkPermission <23 =" + permissionResult + " permission=" + permission);
                return permissionResult;
            }
        }
        /**
         * 针对trtc录制模式，申请相机权限
         */
        public void requestCameraPermission(boolean trtc,boolean belowApi21) {
            this.belowApi21=belowApi21;
            if (checkSdkPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "checkSelfPermission false");
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {  //23+的情况
                    if (ActivityCompat.shouldShowRequestPermissionRationale(WebViewFlutterPlugin.activity, Manifest.permission.CAMERA)) {
                        //用户之前拒绝过，这里返回true
                        Log.d(TAG, "shouldShowRequestPermissionRationale true");
                        if (trtc){
                            ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity,
                                    new String[]{Manifest.permission.CAMERA},
                                    PERMISSION_QUEST_TRTC_CAMERA_VERIFY);
                        }else {
                            ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity,
                                    new String[]{Manifest.permission.CAMERA},
                                    PERMISSION_QUEST_OLD_CAMERA_VERIFY);
                        }
                    } else {
                        Log.d(TAG, "shouldShowRequestPermissionRationale false");
                        if (trtc){
                            ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity,
                                    new String[]{Manifest.permission.CAMERA},
                                    PERMISSION_QUEST_TRTC_CAMERA_VERIFY);
                        }else {
                            ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity,
                                    new String[]{Manifest.permission.CAMERA},
                                    PERMISSION_QUEST_OLD_CAMERA_VERIFY);
                        }

                    }
                } else {
                    if (trtc){
                        //23以下没法系统弹窗动态申请权限，只能用户跳转设置页面，自己打开
                        openAppDetail(PERMISSION_QUEST_TRTC_CAMERA_VERIFY);
                    }else {
                        //23以下没法系统弹窗动态申请权限，只能用户跳转设置页面，自己打开
                        openAppDetail(PERMISSION_QUEST_OLD_CAMERA_VERIFY);
                    }
                }

            } else {
                Log.d(TAG, "checkSelfPermission true");
                if (trtc){
                    enterTrtcFaceVerify();
                }else {
                    enterOldModeFaceVerify(belowApi21);
                }

            }
        }
        private void openAppDetail(int requestCode) {
            showWarningDialog(requestCode);
        }
        AlertDialog dialog = null;
        private void showWarningDialog(final int requestCode) {
            dialog = new AlertDialog.Builder( WebViewFlutterPlugin.activity)
                    .setTitle("权限申请提示")
                    .setMessage("请前往设置->应用->权限中打开相关权限，否则功能无法正常运行！")
                    .setPositiveButton("确定", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialogInterface, int which) {
                            // 一般情况下如果用户不授权的话，功能是无法运行的，做退出处理,合作方自己根据自身产品决定是退出还是停留
                            if (dialog != null && dialog.isShowing()) {
                                dialog.dismiss();
                            }
                            dialog = null;
                            enterSettingActivity(requestCode);

                        }
                    }).setNegativeButton("取消", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialogInterface, int which) {
                            if (dialog != null && dialog.isShowing()) {
                                dialog.dismiss();
                            }
                            dialog = null;
                            WBH5FaceVerifySDK.getInstance().resetReceive();

                        }
                    }).setCancelable(false).show();
        }
        //老的录制模式中，拉起系统相机进行录制视频
        public boolean enterOldModeFaceVerify(boolean belowApi21){
            Log.d(TAG,"enterOldFaceVerify");
            if (belowApi21){ // For Android < 5.0
                if (WBH5FaceVerifySDK.getInstance().recordVideoForApiBelow21(uploadMessage, acceptType, WebViewFlutterPlugin.activity)) { //腾讯的h5刷脸
                    return true;
                }else {
                    // todo 合作方如果其他的h5页面处理，则再次补充其他页面逻辑
                }
            }else { // For Android >= 5.0
                if (WBH5FaceVerifySDK.getInstance().recordVideoForApi21(webView, uploadMessageAboveL, WebViewFlutterPlugin.activity,fileChooserParams)) {  //腾讯的h5刷脸
                    return true;
                }else {
                    // todo 合作方如果其他的h5页面处理，则再次补充其他页面逻辑

                }
            }
            return false;
        }

        private void enterSettingActivity(int requestCode) {
            //部分插件化框架中用Activity.getPackageName拿到的不一定是宿主的包名，所以改用applicationContext获取
            String packageName = WebViewFlutterPlugin.activity.getApplicationContext().getPackageName();
            Uri uri = Uri.fromParts("package", packageName, null);
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri);
            ResolveInfo resolveInfo = WebViewFlutterPlugin.activity.getPackageManager().resolveActivity(intent, 0);
            if (resolveInfo != null) {
                WebViewFlutterPlugin.activity.startActivityForResult(intent, requestCode);
            }
        }

        /**
         * H5_TRTC 刷脸配置，这里负责处理来自H5页面发出的相机权限申请：先申请终端的相机权限，再授权h5请求
         *
         * @param request 来自H5页面的权限请求
         */
        @Override
        public void onPermissionRequest(PermissionRequest request) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                if (request != null && request.getOrigin() != null && WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(request.getOrigin().toString())) { //腾讯意愿性h5刷脸的域名
                    Log.d(TAG, "onPermissionRequest 发起腾讯h5刷脸的相机授权");
                    this.request = request;
                    enterTrtcFaceVerify();
                }
            }

        }

        @Override
        public boolean onCreateWindow(
                final WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
            final WebViewClient webViewClient =
                    new WebViewClient() {
                        @TargetApi(Build.VERSION_CODES.LOLLIPOP)
                        @Override
                        public boolean shouldOverrideUrlLoading(
                                @NonNull WebView view, @NonNull WebResourceRequest request) {
                            final String url = request.getUrl().toString();
                            if (!flutterWebViewClient.shouldOverrideUrlLoading(
                                    FlutterWebView.this.webView, request)) {
                                webView.loadUrl(url);
                            }
                            return true;
                        }

                        @Override
                        public boolean shouldOverrideUrlLoading(WebView view, String url) {
                            if (!flutterWebViewClient.shouldOverrideUrlLoading(
                                    FlutterWebView.this.webView, url)) {
                                webView.loadUrl(url);
                            }
                            return true;
                        }

                    };

            final WebView newWebView = new WebView(view.getContext());
            newWebView.setWebViewClient(webViewClient);

            final WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
            transport.setWebView(newWebView);
            resultMsg.sendToTarget();

            return true;
        }

        public void enterTrtcFaceVerify() {
            Log.d(TAG, "enterTrtcFaceVerify");
            if (Build.VERSION.SDK_INT > Build.VERSION_CODES.LOLLIPOP) { // android sdk 21以上
                if (request != null && request.getOrigin() != null) {
                    //根据腾讯域名授权，如果合作方对授权域名无限制的话，这个if条件判断可以去掉，直接进行授权即可。
                    Log.d(TAG, "enterTrtcFaceVerify getOrigin()!=null");
                    if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(request.getOrigin().toString())) {
                        Log.d(TAG, "enterTrtcFaceVerify 授权成功");
                        //授权
                        request.grant(request.getResources());
                        request.getOrigin();
                    } else {
                        Log.d(TAG, "enterTrtcFaceVerify 授权成识别");
                    }
                } else {
                    if (request == null) {
                        Log.d(TAG, "enterTrtcFaceVerify request==null");
                        if (webView != null && webView.canGoBack()) {
                            webView.goBack();
                        }
                    }
                }
            }
        }

        @Override
        public void onProgressChanged(WebView view, int progress) {
            flutterWebViewClient.onLoadingProgress(progress);
        }

        // For Android < 3.0
        public void openFileChooser(ValueCallback<Uri> valueCallback) {
            Log.v(TAG, "openFileChooser Android < 3.0");


            if (uploadMessage != null) {
                uploadMessage.onReceiveValue(null);
            }
            uploadMessage = valueCallback;
            takePhotoOrOpenGallery();
        }

        // For Android  >= 3.0
        public void openFileChooser(ValueCallback valueCallback, String acceptType) {
            Log.v(TAG, "openFileChooser Android  >= 3.0");

            FlutterWebView.this.uploadMessage = valueCallback;
            takePhotoOrOpenGallery();
        }

        //For Android  >= 4.1
        public void openFileChooser(ValueCallback<Uri> valueCallback, String acceptType, String capture) {
            Log.v(TAG, "openFileChooser Android  >= 4.1");
            if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(null, null, acceptType)) { //true 说明是腾讯的h5刷脸页面
                uploadMessage = valueCallback;
                FlutterWebView.this.acceptType = acceptType;

                WBH5FaceVerifySDK.getInstance().setmUploadMessage(uploadMessage);
                enterTrtcFaceVerify();
            }
            uploadMessage = valueCallback;
            takePhotoOrOpenGallery();
        }

        // For Android >= 5.0
        @Override
        public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
            Log.v(TAG, "openFileChooser Android >= 5.0");
            uploadMessageAboveL = filePathCallback;
            FlutterWebView.this.fileChooserParams = fileChooserParams;
            if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(webView, fileChooserParams, null)) { //true说 明是腾讯的h5刷脸页面

                WBH5FaceVerifySDK.getInstance().setmUploadCallbackAboveL(filePathCallback);
//                activity.requestCameraPermission(false,false);
                    enterTrtcFaceVerify();
                return true;
            }
            takePhotoOrOpenGallery();
            return true;
        }

        @Override
        public void onGeolocationPermissionsShowPrompt(final String origin, final GeolocationPermissions.Callback callback) {
            callback.invoke(origin, true, false);
            super.onGeolocationPermissionsShowPrompt(origin, callback);
        }
    }

    @TargetApi(Build.VERSION_CODES.JELLY_BEAN_MR1)
    @SuppressWarnings("unchecked")
    FlutterWebView(
            final Context context,
            BinaryMessenger messenger,
            int id,
            Map<String, Object> params,
            View containerView) {

        DisplayListenerProxy displayListenerProxy = new DisplayListenerProxy();
        DisplayManager displayManager =
                (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
        displayListenerProxy.onPreWebViewInitialization(displayManager);

        Boolean usesHybridComposition = (Boolean) params.get("usesHybridComposition");
        webView =
                (usesHybridComposition)
                        ? new WebView(context)
                        : new InputAwareWebView(context, containerView);

        displayListenerProxy.onPostWebViewInitialization(displayManager);

        platformThreadHandler = new Handler(context.getMainLooper());
        // Allow local storage.
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(true);

        // Multi windows is set with FlutterWebChromeClient by default to handle internal bug: b/159892679.
        webView.getSettings().setSupportMultipleWindows(true);
        webView.setWebChromeClient(new FlutterWebChromeClient());

        methodChannel = new MethodChannel(messenger, "plugins.flutter.io/webview_" + id);
        methodChannel.setMethodCallHandler(this);

        flutterWebViewClient = new FlutterWebViewClient(methodChannel);
        Map<String, Object> settings = (Map<String, Object>) params.get("settings");
        if (settings != null) applySettings(settings);

        if (params.containsKey(JS_CHANNEL_NAMES_FIELD)) {
            List<String> names = (List<String>) params.get(JS_CHANNEL_NAMES_FIELD);
            if (names != null) registerJavaScriptChannelNames(names);
        }

        Integer autoMediaPlaybackPolicy = (Integer) params.get("autoMediaPlaybackPolicy");
        if (autoMediaPlaybackPolicy != null) updateAutoMediaPlaybackPolicy(autoMediaPlaybackPolicy);
        if (params.containsKey("userAgent")) {
            String userAgent = (String) params.get("userAgent");
            updateUserAgent(userAgent);
        }
        if (params.containsKey("initialUrl")) {
            String url = (String) params.get("initialUrl");
            webView.loadUrl(url);
        }
    }

    @Override
    public View getView() {
        return webView;
    }

    // @Override
    // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
    // annotation would cause compile time failures in versions of Flutter too old to include the new
    // method. However leaving it raw like this means that the method will be ignored in old versions
    // of Flutter but used as an override anyway wherever it's actually defined.
    // TODO(mklim): Add the @Override annotation once flutter/engine#9727 rolls to stable.
    public void onInputConnectionUnlocked() {
        if (webView instanceof InputAwareWebView) {
            ((InputAwareWebView) webView).unlockInputConnection();
        }
    }

    // @Override
    // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
    // annotation would cause compile time failures in versions of Flutter too old to include the new
    // method. However leaving it raw like this means that the method will be ignored in old versions
    // of Flutter but used as an override anyway wherever it's actually defined.
    // TODO(mklim): Add the @Override annotation once flutter/engine#9727 rolls to stable.
    public void onInputConnectionLocked() {
        if (webView instanceof InputAwareWebView) {
            ((InputAwareWebView) webView).lockInputConnection();
        }
    }

    // @Override
    // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
    // annotation would cause compile time failures in versions of Flutter too old to include the new
    // method. However leaving it raw like this means that the method will be ignored in old versions
    // of Flutter but used as an override anyway wherever it's actually defined.
    // TODO(mklim): Add the @Override annotation once stable passes v1.10.9.
    public void onFlutterViewAttached(View flutterView) {
        if (webView instanceof InputAwareWebView) {
            ((InputAwareWebView) webView).setContainerView(flutterView);
        }
    }

    // @Override
    // This is overriding a method that hasn't rolled into stable Flutter yet. Including the
    // annotation would cause compile time failures in versions of Flutter too old to include the new
    // method. However leaving it raw like this means that the method will be ignored in old versions
    // of Flutter but used as an override anyway wherever it's actually defined.
    // TODO(mklim): Add the @Override annotation once stable passes v1.10.9.
    public void onFlutterViewDetached() {
        if (webView instanceof InputAwareWebView) {
            ((InputAwareWebView) webView).setContainerView(null);
        }
    }

    @Override
    public void onMethodCall(MethodCall methodCall, Result result) {
        switch (methodCall.method) {
            case "loadUrl":
                loadUrl(methodCall, result);
                break;
            case "updateSettings":
                updateSettings(methodCall, result);
                break;
            case "canGoBack":
                canGoBack(result);
                break;
            case "canGoForward":
                canGoForward(result);
                break;
            case "goBack":
                goBack(result);
                break;
            case "goForward":
                goForward(result);
                break;
            case "reload":
                reload(result);
                break;
            case "currentUrl":
                currentUrl(result);
                break;
            case "evaluateJavascript":
                evaluateJavaScript(methodCall, result);
                break;
            case "addJavascriptChannels":
                addJavaScriptChannels(methodCall, result);
                break;
            case "removeJavascriptChannels":
                removeJavaScriptChannels(methodCall, result);
                break;
            case "clearCache":
                clearCache(result);
                break;
            case "getTitle":
                getTitle(result);
                break;
            case "scrollTo":
                scrollTo(methodCall, result);
                break;
            case "scrollBy":
                scrollBy(methodCall, result);
                break;
            case "getScrollX":
                getScrollX(result);
                break;
            case "getScrollY":
                getScrollY(result);
                break;
            default:
                result.notImplemented();
        }
    }

    @SuppressWarnings("unchecked")
    private void loadUrl(MethodCall methodCall, Result result) {
        Map<String, Object> request = (Map<String, Object>) methodCall.arguments;
        String url = (String) request.get("url");
        Map<String, String> headers = (Map<String, String>) request.get("headers");
        if (headers == null) {
            headers = Collections.emptyMap();
        }
        webView.loadUrl(url, headers);
        result.success(null);
    }

    private void canGoBack(Result result) {
        result.success(webView.canGoBack());
    }

    private void canGoForward(Result result) {
        result.success(webView.canGoForward());
    }

    private void goBack(Result result) {
        if (webView.canGoBack()) {
            webView.goBack();
        }
        result.success(null);
    }

    private void goForward(Result result) {
        if (webView.canGoForward()) {
            webView.goForward();
        }
        result.success(null);
    }

    private void reload(Result result) {
        webView.reload();
        result.success(null);
    }

    private void currentUrl(Result result) {
        result.success(webView.getUrl());
    }

    @SuppressWarnings("unchecked")
    private void updateSettings(MethodCall methodCall, Result result) {
        applySettings((Map<String, Object>) methodCall.arguments);
        result.success(null);
    }

    @TargetApi(Build.VERSION_CODES.KITKAT)
    private void evaluateJavaScript(MethodCall methodCall, final Result result) {
        String jsString = (String) methodCall.arguments;
        if (jsString == null) {
            throw new UnsupportedOperationException("JavaScript string cannot be null");
        }
        webView.evaluateJavascript(
                jsString,
                new android.webkit.ValueCallback<String>() {
                    @Override
                    public void onReceiveValue(String value) {
                        result.success(value);
                    }
                });
    }

    @SuppressWarnings("unchecked")
    private void addJavaScriptChannels(MethodCall methodCall, Result result) {
        List<String> channelNames = (List<String>) methodCall.arguments;
        registerJavaScriptChannelNames(channelNames);
        result.success(null);
    }

    @SuppressWarnings("unchecked")
    private void removeJavaScriptChannels(MethodCall methodCall, Result result) {
        List<String> channelNames = (List<String>) methodCall.arguments;
        for (String channelName : channelNames) {
            webView.removeJavascriptInterface(channelName);
        }
        result.success(null);
    }

    private void clearCache(Result result) {
        webView.clearCache(true);
        WebStorage.getInstance().deleteAllData();
        result.success(null);
    }

    private void getTitle(Result result) {
        result.success(webView.getTitle());
    }

    private void scrollTo(MethodCall methodCall, Result result) {
        Map<String, Object> request = methodCall.arguments();
        int x = (int) request.get("x");
        int y = (int) request.get("y");

        webView.scrollTo(x, y);

        result.success(null);
    }

    private void scrollBy(MethodCall methodCall, Result result) {
        Map<String, Object> request = methodCall.arguments();
        int x = (int) request.get("x");
        int y = (int) request.get("y");

        webView.scrollBy(x, y);
        result.success(null);
    }

    private void getScrollX(Result result) {
        result.success(webView.getScrollX());
    }

    private void getScrollY(Result result) {
        result.success(webView.getScrollY());
    }

    private void applySettings(Map<String, Object> settings) {
        for (String key : settings.keySet()) {
            switch (key) {
                case "jsMode":
                    Integer mode = (Integer) settings.get(key);
                    if (mode != null) updateJsMode(mode);
                    break;
                case "hasNavigationDelegate":
                    final boolean hasNavigationDelegate = (boolean) settings.get(key);

                    final WebViewClient webViewClient =
                            flutterWebViewClient.createWebViewClient(hasNavigationDelegate, webView.getContext());

                    webView.setWebViewClient(webViewClient);
                    break;
                case "debuggingEnabled":
                    final boolean debuggingEnabled = (boolean) settings.get(key);

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        webView.setWebContentsDebuggingEnabled(debuggingEnabled);
                    }
                    break;
                case "hasProgressTracking":
                    flutterWebViewClient.hasProgressTracking = (boolean) settings.get(key);
                    break;
                case "gestureNavigationEnabled":
                    break;
                case "geolocationEnabled":
                    final boolean geolocationEnabled = (boolean) settings.get(key);
                    webView.getSettings().setGeolocationEnabled(geolocationEnabled);
                    if (geolocationEnabled && Build.VERSION.SDK_INT >= 23) {
                        int checkPermission = ContextCompat.checkSelfPermission(WebViewFlutterPlugin.activity, Manifest.permission.ACCESS_COARSE_LOCATION);
                        if (checkPermission != PackageManager.PERMISSION_GRANTED) {
                            ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity,
                                    new String[]{Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION},
                                    REQUEST_LOCATION);
                        }
                    }
                    break;
                case "userAgent":
                    updateUserAgent((String) settings.get(key));
                    break;
                case "allowsInlineMediaPlayback":
                    // no-op inline media playback is always allowed on Android.
                    break;
                default:
                    throw new IllegalArgumentException("Unknown WebView setting: " + key);
            }
        }
    }

    private void updateJsMode(int mode) {
        switch (mode) {
            case 0: // disabled
                webView.getSettings().setJavaScriptEnabled(false);
                break;
            case 1: // unrestricted
                webView.getSettings().setJavaScriptEnabled(true);
                break;
            default:
                throw new IllegalArgumentException("Trying to set unknown JavaScript mode: " + mode);
        }
    }

    private void updateAutoMediaPlaybackPolicy(int mode) {
        // This is the index of the AutoMediaPlaybackPolicy enum, index 1 is always_allow, for all
        // other values we require a user gesture.
        boolean requireUserGesture = mode != 1;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            webView.getSettings().setMediaPlaybackRequiresUserGesture(requireUserGesture);
        }
    }

    private void registerJavaScriptChannelNames(List<String> channelNames) {
        for (String channelName : channelNames) {
            webView.addJavascriptInterface(
                    new JavaScriptChannel(methodChannel, channelName, platformThreadHandler), channelName);
        }
    }

    private void updateUserAgent(String userAgent) {
        webView.getSettings().setUserAgentString(userAgent);
    }

    @Override
    public void dispose() {
        methodChannel.setMethodCallHandler(null);
        if (webView instanceof InputAwareWebView) {
            ((InputAwareWebView) webView).dispose();
        }
        webView.destroy();
    }


    private void openImageChooserActivity() {
        Log.v(TAG, "openImageChooserActivity");
        Intent intent1 = new Intent(Intent.ACTION_GET_CONTENT);
        intent1.addCategory(Intent.CATEGORY_OPENABLE);
        intent1.setType("*/*");

        Intent chooser = new Intent(Intent.ACTION_CHOOSER);
        chooser.putExtra(Intent.EXTRA_TITLE, WebViewFlutterPlugin.activity.getString(R.string.select_picture));
        chooser.putExtra(Intent.EXTRA_INTENT, intent1);
        if (WebViewFlutterPlugin.activity != null) {
            WebViewFlutterPlugin.activity.startActivityForResult(chooser, FILE_CHOOSER_RESULT_CODE);
        } else {
            Log.v(TAG, "activity is null");
        }
    }

    private void takePhotoOrOpenGallery() {
        if (WebViewFlutterPlugin.activity == null || !FileUtil.checkSDcard(WebViewFlutterPlugin.activity)) {
            return;
        }
        String[] selectPicTypeStr = {WebViewFlutterPlugin.activity.getString(R.string.take_photo),
                WebViewFlutterPlugin.activity.getString(R.string.photo_library)};
        new AlertDialog.Builder(WebViewFlutterPlugin.activity)
                .setOnCancelListener(new ReOnCancelListener())
                .setItems(selectPicTypeStr,
                        new DialogInterface.OnClickListener() {
                            @Override
                            public void onClick(DialogInterface dialog, int which) {
                                switch (which) {
                                    // 相机拍摄
                                    case 0:
                                        openCamera();
                                        break;
                                    // 手机相册
                                    case 1:
                                        openImageChooserActivity();
                                        break;
                                    default:
                                        break;
                                }
                            }
                        }).show();
    }

    /**
     * Check if the calling context has a set of permissions.
     *
     * @param context the calling context.
     * @param perms   one ore more permissions, such as {@link Manifest.permission#CAMERA}.
     * @return true if all permissions are already granted, false if at least one permission is not
     * yet granted.
     * @see Manifest.permission
     */
    public static boolean hasPermissions(@NonNull Context context,
                                         @Size(min = 1) @NonNull String... perms) {
        // Always return true for SDK < M, let the system deal with the permissions
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            Log.w(TAG, "hasPermissions: API version < M, returning true by default");

            // DANGER ZONE!!! Changing this will break the library.
            return true;
        }

        // Null context may be passed if we have detected Low API (less than M) so getting
        // to this point with a null context should not be possible.
        if (context == null) {
            throw new IllegalArgumentException("Can't check permissions for null context");
        }

        for (String perm : perms) {
            if (ContextCompat.checkSelfPermission(context, perm)
                    != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
        }

        return true;
    }

    /**
     * 打开照相机
     */
    private void openCamera() {
        if (hasPermissions(WebViewFlutterPlugin.activity, perms)) {
            try {
                //创建File对象，用于存储拍照后的照片
                File outputImage = FileUtil.createImageFile(WebViewFlutterPlugin.activity);
                if (outputImage.exists()) {
                    outputImage.delete();
                }
                outputImage.createNewFile();
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    cameraUri = FileProvider.getUriForFile(WebViewFlutterPlugin.activity, WebViewFlutterPlugin.activity.getPackageName() + ".fileprovider", outputImage);
                } else {
                    Uri.fromFile(outputImage);
                }
                //启动相机程序
                Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
                intent.putExtra(MediaStore.EXTRA_OUTPUT, cameraUri);
                WebViewFlutterPlugin.activity.startActivityForResult(intent, REQUEST_CAMERA);
            } catch (Exception e) {
                Toast.makeText(WebViewFlutterPlugin.activity, e.getMessage(), Toast.LENGTH_SHORT).show();
                if (uploadMessageAboveL != null) {
                    uploadMessageAboveL.onReceiveValue(null);
                    uploadMessageAboveL = null;
                }
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                ActivityCompat.requestPermissions(WebViewFlutterPlugin.activity, perms, REQUEST_CAMERA);
            }
        }

    }

    /**
     * dialog监听类
     */
    private class ReOnCancelListener implements DialogInterface.OnCancelListener {
        @Override
        public void onCancel(DialogInterface dialogInterface) {
            if (uploadMessage != null) {
                uploadMessage.onReceiveValue(null);
                uploadMessage = null;
            }

            if (uploadMessageAboveL != null) {
                uploadMessageAboveL.onReceiveValue(null);
                uploadMessageAboveL = null;
            }
        }
    }

    public boolean requestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == REQUEST_CAMERA) {
            if (grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                openCamera();
            } else {
                Toast.makeText(WebViewFlutterPlugin.activity, WebViewFlutterPlugin.activity.getString(R.string.take_pic_need_permission), Toast.LENGTH_SHORT).show();
                if (uploadMessage != null) {
                    uploadMessage.onReceiveValue(null);
                    uploadMessage = null;
                }
                if (uploadMessageAboveL != null) {
                    uploadMessageAboveL.onReceiveValue(null);
                    uploadMessageAboveL = null;
                }
            }
        }
        return false;
    }

    public boolean activityResult(int requestCode, int resultCode, Intent data) {
        Log.v(TAG, "activityResult: ");
        if (null == uploadMessage && null == uploadMessageAboveL) {
            return false;
        }
        Uri result = null;
        if (requestCode == REQUEST_CAMERA && resultCode == RESULT_OK) {
            result = cameraUri;
        }
        if (requestCode == FILE_CHOOSER_RESULT_CODE) {
            result = data == null || resultCode != RESULT_OK ? null : data.getData();
        }
        if (uploadMessageAboveL != null) {
            onActivityResultAboveL(requestCode, resultCode, data);
        } else if (uploadMessage != null && result != null) {
            uploadMessage.onReceiveValue(result);
            uploadMessage = null;
        }
        return false;
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private void onActivityResultAboveL(int requestCode, int resultCode, Intent intent) {
        if (requestCode != FILE_CHOOSER_RESULT_CODE && requestCode != REQUEST_CAMERA || uploadMessageAboveL == null) {
            return;
        }
        Uri[] results = null;
        if (requestCode == REQUEST_CAMERA && resultCode == RESULT_OK) {
            results = new Uri[]{cameraUri};
        }

        if (requestCode == FILE_CHOOSER_RESULT_CODE && resultCode == Activity.RESULT_OK) {
            if (intent != null) {
                String dataString = intent.getDataString();
                ClipData clipData = intent.getClipData();
                if (clipData != null) {
                    results = new Uri[clipData.getItemCount()];
                    for (int i = 0; i < clipData.getItemCount(); i++) {
                        ClipData.Item item = clipData.getItemAt(i);
                        results[i] = item.getUri();
                    }
                }
                if (dataString != null) {
                    results = new Uri[]{Uri.parse(dataString)};
                }
            }
        }
        uploadMessageAboveL.onReceiveValue(results);
        uploadMessageAboveL = null;
    }

}

