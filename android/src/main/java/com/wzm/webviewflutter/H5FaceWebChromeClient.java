package com.wzm.webviewflutter;

import android.annotation.TargetApi;
import android.app.Activity;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.webkit.JsPromptResult;
import android.webkit.JsResult;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;


public class H5FaceWebChromeClient extends WebChromeClient {
    private static final String TAG = "H5FaceWebChromeClient";
    private Activity activity;
    private PermissionRequest request;
    private WebView webView;

    private ValueCallback<Uri> uploadMsg;
    private String acceptType;
    private ValueCallback<Uri[]> filePathCallback;
    private FileChooserParams fileChooserParams;

    public H5FaceWebChromeClient(Activity mActivity) {
        this.activity = mActivity;
    }

    @Override
    public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, JsPromptResult result) {
        return super.onJsPrompt(view, url, message, defaultValue, result);
    }

    @Override
    public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
        result.confirm();
        return true;
    }


    /**
     * H5_TRTC 刷脸配置，这里负责处理来自H5页面发出的相机权限申请：先申请终端的相机权限，再授权h5请求
     * @param request 来自H5页面的权限请求
     */
    @Override
    public void onPermissionRequest(PermissionRequest request) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (request!=null&&request.getOrigin()!=null&&WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(request.getOrigin().toString())){ //腾讯意愿性h5刷脸的域名
                Log.d(TAG,"onPermissionRequest 发起腾讯h5刷脸的相机授权");
                this.request=request;
                if (activity!=null){ //申请相机权限，申请权限的代码demo仅供参考，合作方可根据自身业务定制
                    enterTrtcFaceVerify();
    //                activity.requestCameraPermission(true,false);//申请终端的相机权限
                }
            }
        }

    }

    /**
     * 相机权限申请成功后，拉起TRTC刷脸界面进行实时刷脸验证
     */
    public void enterTrtcFaceVerify(){
        Log.d(TAG,"enterTrtcFaceVerify");
        if (Build.VERSION.SDK_INT>Build.VERSION_CODES.LOLLIPOP){ // android sdk 21以上
            if (request!=null&&request.getOrigin()!=null){
                //根据腾讯域名授权，如果合作方对授权域名无限制的话，这个if条件判断可以去掉，直接进行授权即可。
                Log.d(TAG,"enterTrtcFaceVerify getOrigin()!=null");
                if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(request.getOrigin().toString())){
                    Log.d(TAG,"enterTrtcFaceVerify 授权成功");
                    //授权
                    request.grant(request.getResources());
                    request.getOrigin();
                }else {
                    Log.d(TAG,"enterTrtcFaceVerify 授权成识别");
                }
            }else {
                if (request==null){
                    Log.d(TAG,"enterTrtcFaceVerify request==null");
                    if (webView!=null&&webView.canGoBack()){
                        webView.goBack();
                    }
                }
            }
        }
    }


    // For Android >= 4.1  老的录制模式中，收到h5页面发送的录制请求
    public void openFileChooser(ValueCallback<Uri> uploadMsg, String acceptType, String capture) {
        Log.d(TAG,"openFileChooser-------acceptType="+acceptType);
        if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(null,null,acceptType)){ //true 说明是腾讯的h5刷脸页面
            this.uploadMsg=uploadMsg;
            this.acceptType=acceptType;
            WBH5FaceVerifySDK.getInstance().setmUploadMessage(uploadMsg);
            if (activity!=null){ //申请系统的相机、录制、sd卡等权限
//                activity.requestCameraPermission(false,true);
                enterTrtcFaceVerify();

            }
        }

    }

    // For Lollipop 5.0+ Devices  老的录制模式中，收到h5页面发送的录制请求
    @TargetApi(21)
    @Override
    public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback, FileChooserParams fileChooserParams) {
        if (fileChooserParams!=null&&fileChooserParams.getAcceptTypes()!=null&&fileChooserParams.getAcceptTypes().length>0){
            Log.d(TAG,"onShowFileChooser-------acceptType="+fileChooserParams.getAcceptTypes()[0]);
        }else {
            Log.d(TAG,"onShowFileChooser-------acceptType=null");
        }
        if (WBH5FaceVerifySDK.getInstance().isTencentH5FaceVerify(webView,fileChooserParams,null)){ //true说 明是腾讯的h5刷脸页面
            this.webView=webView;
            this.filePathCallback=filePathCallback;
            this.fileChooserParams=fileChooserParams;
            WBH5FaceVerifySDK.getInstance().setmUploadCallbackAboveL(filePathCallback);
            if (activity!=null){ //申请系统的相机、录制、sd卡等权限
//                activity.requestCameraPermission(false,false);
                enterTrtcFaceVerify();
            }

        }
        return true;

    }

    //老的录制模式中，拉起系统相机进行录制视频
    public boolean enterOldModeFaceVerify(boolean belowApi21){
        Log.d(TAG,"enterOldFaceVerify");
        if (belowApi21){ // For Android < 5.0
            if (WBH5FaceVerifySDK.getInstance().recordVideoForApiBelow21(uploadMsg, acceptType, activity)) { //腾讯的h5刷脸
                return true;
            }else {
                // todo 合作方如果其他的h5页面处理，则再次补充其他页面逻辑
            }
        }else { // For Android >= 5.0
            if (WBH5FaceVerifySDK.getInstance().recordVideoForApi21(webView, filePathCallback, activity,fileChooserParams)) {  //腾讯的h5刷脸
                return true;
            }else {
                // todo 合作方如果其他的h5页面处理，则再次补充其他页面逻辑

            }
        }
        return false;
    }


}
