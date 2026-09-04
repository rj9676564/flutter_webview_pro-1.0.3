# flutter_webview_pro

一个用于 Android 和 iOS 的 Flutter WebView 插件。

本包基于 Flutter WebView 行为，并补充了文件上传、地理位置、Cookie 管理和 WebView 会话隔离等能力。

## 功能

- 使用 Flutter `WebView` 展示网页内容。
- 支持导航控制、页面加载回调、JavaScript 执行和 JavaScript Channel。
- 清理全部 WebView Cookie。
- 使用 `CookieManager.clearCookiesForDomains` 按域名清理 WebView Cookie。
- 使用 `SessionWebViewManager` 管理按 session 隔离的 WebView 会话。
- 使用 `WebViewProxy` 为 Android WebView 配置 HTTP/SOCKS 代理。

## WebView 代理

在创建或加载 WebView 之前配置代理：

```dart
import 'package:flutter_webview_pro/webview_flutter.dart';

await WebViewProxy.setProxy('192.168.1.152:9090');
// 显式指定 HTTP 代理协议：
// await WebViewProxy.setProxy('http://192.168.1.152:9090');
// SOCKS 代理：
// await WebViewProxy.setProxy('socks5://127.0.0.1:1080');
```

支持 `host:port`、`http://host:port` 和 `socks5://host:port` 格式。传入
`null` 或空字符串可以清除代理覆盖，恢复默认网络连接：

```dart
await WebViewProxy.clearProxy();
```

Android 使用 AndroidX WebKit 的 `ProxyController`，代理会作用于当前 App
进程中的 WebView。代理配置是异步应用的，因此创建或加载 WebView 前需要
等待 `setProxy` 完成。设备上的 Android System WebView/Chrome 需要支持代理
覆盖功能，过旧的 WebView 可能会忽略该请求。

iOS 的 `WKWebView` 没有应用级代理覆盖能力。为了保持跨平台 API 一致，iOS
仍然提供该方法，但 `setProxy` 在 iOS 上是空操作。开发环境抓包时，需要在
iPhone 当前 Wi-Fi 的代理设置中，填写开发机 IP 和代理端口。

如果代理工具需要解密 HTTPS 流量，需要把代理工具导出的根 CA 安装到测试
设备，并在代理工具中开启 HTTPS/SSL 解密。iOS 手动安装证书后，还需要在
**设置 → 通用 → 关于本机 → 证书信任设置**中开启信任。Android debug App
需要通过 App 自己的 Network Security Configuration 明确信任用户证书；本
插件不会自动安装或信任代理 CA。代理 CA 信任配置只应在开发环境使用。

## 使用方式

在 `pubspec.yaml` 中添加依赖后，引入：

```dart
import 'package:flutter_webview_pro/webview_flutter.dart';
```

创建 WebView：

```dart
WebView(
  initialUrl: 'https://flutter.dev',
  javascriptMode: JavascriptMode.unrestricted,
)
```

按域名清理 Cookie：

```dart
final CookieManager cookieManager = CookieManager();

await cookieManager.clearCookiesForDomains(<String>[
  'flutter.dev',
  'https://example.com',
]);
```

使用常驻 WebView 池保持隔离会话：

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  sessionStore: FileSessionWebViewSessionStore(),
);

await sessionManager.switchToSession(
  'tenant-a',
  initialUrl: 'https://tenant-a.example.com',
);

Widget build(BuildContext context) {
  return SessionWebViewSwitcher(
    manager: sessionManager,
    javascriptMode: JavascriptMode.unrestricted,
  );
}
```

进入 WebView 页面时调用 `switchToSession`，传入当前页面要绑定的 session 标识。切换店铺或账号时，在构建 `SessionWebViewSwitcher` 前传入新的 session key。

首次打开的 session 会接管平台 WebView 已有状态，而不是先清理。重新打开相同 session key 时，如果平台 WebView 中仍有 Cookie 和 origin storage，也会继续复用。切换到不同 session key 时，manager 会先捕获上一个 session，再清理共享 WebView 状态，并恢复目标 session snapshot。

`FileSessionWebViewSessionStore()` 默认会把 snapshot JSON 文件写到系统临时/缓存目录，调用方不需要自己传路径。这样 App 正常进程重启后，仍可以按 session key 恢复 Cookie 和 Web Storage。如果不需要进程重启恢复，可以不传 `sessionStore`，继续使用默认内存 store。

应用级退出登录时，清理全部 WebView session 和平台 WebView 数据：

```dart
await sessionManager.clearAllSessions();
```

调用后会删除全部已保存 snapshot、Cookie、storage 和 cache。下一次打开任意 session key 时，网页都应该重新登录。

如果需要校验恢复后的页面仍绑定到预期 session，可以提供可选的 binding capture 和 validator：

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  sessionBindingCapture: (String sessionKey, WebViewController controller) {
    return controller.evaluateJavascript('window.__CURRENT_SESSION_ID__');
  },
  sessionBindingValidator: (String sessionKey, String? binding) {
    return binding == sessionKey;
  },
);
```

`SessionWebViewManager` 会从 session 访问过的 URL 中自动学习 Cookie host。如果登录流程依赖 WebView 正常导航中不会出现的额外域名，可以全局补充：

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  additionalCookieDomains: <String>[
    'sso.example.com',
    'static-login.example.com',
  ],
);
```

## 平台

- Android
- iOS

## 说明

`clearCookiesForDomains` 支持传入 host 或 URL。只要清理前任意匹配域名存在 Cookie，就返回 `true`，否则返回 `false`。

`SessionWebViewManager` 默认最多保持 3 个常驻 WebView。池满时会淘汰最近最少使用的实例，并捕获它的 Cookie 和 Web Storage；再次打开相同 session key 时，会用 snapshot 恢复该 session。

默认情况下，`SessionWebViewManager` 会先记录 `initialUrl` 解析出的 host，后续随着页面导航到新域名继续扩展 Cookie host 集合。只有当登录依赖正常导航中不会出现的域名时，才需要使用 `additionalCookieDomains`。

`SessionWebViewManager` 可恢复的状态包括 Cookie、`localStorage`、`sessionStorage` 和最后访问 URL。如果 session 仍常驻，也能保留实时页面状态。实例被淘汰后，内存中的 JavaScript 变量、未提交表单、临时 DOM 状态不保证恢复。

默认的 `MemorySessionWebViewSessionStore` 只在内存中保存 snapshot。如果 App 进程被杀，manager 无法判断平台 WebView 磁盘中残留的 Cookie 属于哪个 session。若需要进程重启后仍恢复 session snapshot，请使用 `FileSessionWebViewSessionStore()`。它的默认路径是 `FileSessionWebViewSessionStore.defaultFilePath`，位于 `Directory.systemTemp` 下；系统执行缓存或临时文件清理时，仍可能删除该文件。
