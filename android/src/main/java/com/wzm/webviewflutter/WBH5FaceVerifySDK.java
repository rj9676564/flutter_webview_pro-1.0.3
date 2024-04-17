package com.wzm.webviewflutter;

import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.text.TextUtils;
import android.util.Log;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;

import static android.app.Activity.RESULT_OK;

public class WBH5FaceVerifySDK {
    private static final String TAG = "WBH5FaceVerifySDK";
    public static final int VIDEO_REQUEST = 0x11;
    private ValueCallback<Uri> mUploadMessage;
    private ValueCallback<Uri[]> mUploadCallbackAboveL;
    private static WBH5FaceVerifySDK instance;


    public static synchronized WBH5FaceVerifySDK getInstance() {
        if (null == instance) {
            instance = new WBH5FaceVerifySDK();
        }
        return instance;
    }

    private WBH5FaceVerifySDK() {
    }


    /**
     * webView的websetting设置，ua配置一定不能少
     * @param mWebView
     * @param context
     */
    public void setWebViewSettings(WebView mWebView, Context context) {
        if (null == mWebView)
            return;
        WebSettings webSetting = mWebView.getSettings();
        webSetting.setJavaScriptEnabled(true);
        webSetting.setTextZoom(100);
        webSetting.setAllowFileAccess(true);
        webSetting.setLayoutAlgorithm(WebSettings.LayoutAlgorithm.NARROW_COLUMNS);
        webSetting.setSupportZoom(true);
        webSetting.setBuiltInZoomControls(true);
        webSetting.setUseWideViewPort(true);
        webSetting.setSupportMultipleWindows(false);
        webSetting.setLoadWithOverviewMode(true);
        webSetting.setAppCacheEnabled(true);
        webSetting.setDatabaseEnabled(true);
        webSetting.setDomStorageEnabled(true);
        webSetting.setAppCacheMaxSize(Long.MAX_VALUE);
        webSetting.setAppCachePath(context.getDir("appcache", 0).getPath());
        webSetting.setDatabasePath(context.getDir("databases", 0).getPath());
        webSetting.setPluginState(WebSettings.PluginState.ON_DEMAND);
        webSetting.setRenderPriority(WebSettings.RenderPriority.HIGH);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.HONEYCOMB) {
            mWebView.removeJavascriptInterface("searchBoxJavaBridge_");
        }
        String ua = webSetting.getUserAgentString();
        webSetting.setUserAgentString(ua + ";kyc/h5face;kyc/2.0");//这个设置ua包含;kyc/h5face;kyc/2.0一定不能少
        webSetting.setMediaPlaybackRequiresUserGesture(false);
    }


    /**
     * 传统录制模式，将录制的视频送给h5端
     * @param requestCode
     * @param resultCode
     * @param data
     * @return
     */
    public boolean receiveH5FaceVerifyResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == VIDEO_REQUEST) { //根据请求码判断返回的是否是h5刷脸结果
            if (null == mUploadMessage && null == mUploadCallbackAboveL) {
                return true;
            }
            Uri result = data == null || resultCode != RESULT_OK ? null : data.getData();
            Uri[] uris = result == null ? null : new Uri[]{result};
            if (mUploadCallbackAboveL != null) {
                mUploadCallbackAboveL.onReceiveValue(uris);
                setmUploadCallbackAboveL(null);
            } else {
                mUploadMessage.onReceiveValue(result);
                setmUploadMessage(null);
            }
            return true;
        }
        return false;
    }

    /**
     * 传统录制模式，针对5.0以下设备
     */
    public boolean recordVideoForApiBelow21(ValueCallback<Uri> uploadMsg, String acceptType, Activity activity) {
        if (isTencentH5FaceVerify(null,null,acceptType)) { //是腾讯的H5刷脸
            setmUploadMessage(uploadMsg);
            recordVideo(activity);
            return true;
        }
        return false;
    }


    /**
     * 传统录制模式，针对5.0以上设备
     */
    @TargetApi(21)
    public boolean recordVideoForApi21(WebView webView, ValueCallback<Uri[]> filePathCallback, Activity activity, WebChromeClient.FileChooserParams fileChooserParams) {
        Log.d(TAG, "recordVideoForApi21 url=" + webView.getUrl());
        if (isTencentH5FaceVerify(webView,fileChooserParams,null)){  //是腾讯的H5刷脸
            setmUploadCallbackAboveL(filePathCallback);
            recordVideo(activity);
            return true;
        }
        return  false;
    }


    /**
     * 传统录制模式，调用系统前置摄像头进行视频录制
     */
    private void recordVideo(Activity activity) {
        try {
            Intent intent = new Intent(MediaStore.ACTION_VIDEO_CAPTURE);
            intent.putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.putExtra("android.intent.extras.CAMERA_FACING", 1); // 调用前置摄像头
            activity.startActivityForResult(intent, VIDEO_REQUEST);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public void setmUploadMessage(ValueCallback<Uri> uploadMessage) {
        mUploadMessage = uploadMessage;
    }

    public void setmUploadCallbackAboveL(ValueCallback<Uri[]> uploadCallbackAboveL) {
        mUploadCallbackAboveL = uploadCallbackAboveL;
    }
    /**
     * 判断是否腾讯的h5刷脸，根据acceptType参数值或者url判断
     */
    public boolean isTencentH5FaceVerify(WebView webView, WebChromeClient.FileChooserParams fileChooserParams, String acceptType) {
        if ("video/kyc".equals(acceptType)) {
            return true;
        } else if (fileChooserParams != null && fileChooserParams.getAcceptTypes() != null && fileChooserParams.getAcceptTypes().length > 0 && "video/kyc".equals(fileChooserParams.getAcceptTypes()[0])) {
                return true;
        }else if (webView!=null&& !TextUtils.isEmpty(webView.getUrl())){
            String h5Url=webView.getUrl();
            try{
                String thirdName=h5Url.split("//")[1].split("\\.")[0];
                Log.d(TAG,"thirdUrlName "+thirdName);
                if (thirdName.contains("kyc")||thirdName.contains("ida")){
                    return true;
                }else {
                    return false;
                }
            }catch (Exception e){
                e.printStackTrace();
                return false;
            }
        }else {
            return false;
        }
    }

    /**
     * 判断是否腾讯域名
     * @param h5Url
     * @return
     */
    public boolean isTencentH5FaceVerify(String h5Url) {
        try{
            String thirdName=h5Url.split("//")[1].split("\\.")[0];
            Log.d(TAG,"isTencentH5FaceVerify thirdUrlName="+thirdName);
            if (thirdName.contains("kyc")||thirdName.contains("ida")){
                return true;
            }else {
                return false;
            }
        }catch (Exception e){
            e.printStackTrace();
            return false;
        }
    }

    /**
     * 录制模式中， 给ValueCallback接口的onReceiveValue抽象方法传入nul。尤其拒绝权限后，要记得调用这个方法，否则再次点击【开始录制】按钮会没有响应
     * 回调onShowFileChooser这个方法，在这个重写的方法里面打开系统相机进行拍照或者录制，点击一次回调一次的前提是
     * 请求被取消，而取消该请求回调的方法: 给ValueCallback接口的onReceiveValue抽象方法传入nul，同时onShowFileChooser方法返回true;
     * 详情参考 https://www.teachcourse.cn/2224.html
     */
    public void resetReceive(){
        if (mUploadCallbackAboveL!=null){
            mUploadCallbackAboveL.onReceiveValue(null);
        }
        if (mUploadMessage!=null){
            mUploadMessage.onReceiveValue(null);
        }
    }
}
