# WebView Session 隔离实现记录

本文记录本次为 `flutter_webview_pro` 增加 WebView session 隔离能力时做过的改动、调试过程、踩过的坑，以及当前方案的边界。

## 背景

业务场景是一个主账号可以切换多个店铺，每个店铺在第三方 H5/开放平台中都是独立业务主体。如果直接复用默认 WebView 全局 Cookie 和缓存，切换店铺时容易出现数据串线：

- 切到 B 店铺后，H5 仍展示 A 店铺数据。
- 同域 Cookie 被覆盖后，第三方后台登录态异常。
- 关闭 WebView 后重新进入，同店铺登录态可能被误清。
- 用户退出登录时，只清 Cookie 不够，localStorage/sessionStorage/snapshot 仍可能残留。

核心目标是：按业务传入的 `sessionKey` 隔离 WebView 登录态，同时同一个 `sessionKey` 重新进入时尽量保持登录状态。

## 主要改动

### 新增通用 session 管理层

新增 `lib/src/session_webview_manager.dart`，提供：

- `SessionWebViewManager`：按 `sessionKey` 管理 WebView session。
- `SessionWebViewSwitcher`：展示当前 session 的 WebView，并让 resident WebView 保持在 widget tree 中。
- `SessionSnapshot`：保存可恢复状态，包括 Cookie、`localStorage`、`sessionStorage`、最后访问 URL、可选业务 binding。
- `MemorySessionWebViewSessionStore`：默认内存 snapshot store。
- `FileSessionWebViewSessionStore`：文件 snapshot store，用于 App 进程重启后恢复 session。无参构造时使用系统临时/缓存目录下的默认 JSON 文件路径。
- `SessionWebViewClearableSessionStore`：可选清空能力，用于持久化 store 在退出登录时删除全部 snapshot。

API 已通过 `lib/webview_flutter.dart` export，对外保持通用开源命名，不绑定店铺、租户等业务概念。

### Cookie 和 Web Storage 捕获/恢复

在 Dart 层补充：

- `WebViewCookie`
- `CookieManager.getCookiesForDomains`
- `CookieManager.setCookies`
- `CookieManager.clearWebsiteData`
- `WebViewController.captureLocalStorage`
- `WebViewController.captureSessionStorage`
- `WebViewController.restoreLocalStorage`
- `WebViewController.restoreSessionStorage`

在 Android/iOS 原生层补充：

- Android `FlutterCookieManager.getCookiesForDomains`
- Android `FlutterCookieManager.setCookies`
- Android `FlutterCookieManager.clearWebsiteDataForDomains`
- Android `FlutterCookieManager.clearWebsiteData`
- iOS `FLCookieManager.getCookiesForDomains`
- iOS `FLCookieManager.setCookies`
- iOS `FLCookieManager.clearWebsiteDataForDomains`
- iOS `FLCookieManager.clearWebsiteData`

`clearWebsiteData` 用于退出登录，清理全局 WebView Cookie、storage 和 cache。

### 自动学习 Cookie 域名

最初讨论过让调用方提供 `sessionCookieDomainsResolver`，但这对业务不现实，因为业务常常只知道入口 URL，不知道后续跳转到哪些域名。

最终方案：

- 从 `initialUrl` 中记录 host。
- 在 `onPageStarted` 和 `onPageFinished` 中继续记录导航到的新 host。
- snapshot 中保存已学习到的 `cookieDomains`。
- 提供 `additionalCookieDomains` 作为兜底，只在登录依赖未经过 WebView 主导航的域名时使用。

这样支持入口是 `a.com`，后续跳到 `b.com` 的场景。

### 同 session 重进不主动清理

Android/iOS 默认 WebView 的 Cookie 和 origin storage 是平台级共享的，不是每个 WebView 实例独立。早期实现中，重建同一个 session 时也会先执行 `_resetSharedSessionState()`，这会把平台 WebView 已经持久化的登录态先清掉，然后再依赖 snapshot 恢复。

这个策略导致一个实际问题：只要 snapshot 不完整，用户不切店铺、只是关闭 WebView 再进入，也会丢登录态。

最终改成：

- 首次打开 session 时采用 `adopting existing shared state`，不主动清平台状态。
- 同一个 `sessionKey` 关闭后重进，如果平台 WebView 状态还在，则复用它。
- 只有切到不同 `sessionKey` 时，才清理共享状态并恢复目标 session snapshot。

这解决了“同店铺重新进入也要重新登录”的问题。

### 退出登录全清

退出登录不能只调用 `CookieManager().clearCookies()`，因为它只清 Cookie，不清：

- `SessionWebViewManager` 内存 snapshot
- resident WebView entry
- `localStorage`
- `sessionStorage`
- WebView cache

新增：

```dart
await sessionManager.clearAllSessions();
```

它会：

- 清空 manager 中全部 entries 和 LRU 状态。
- 清空内存 store 中全部 snapshot。
- 如果自定义 store 实现 `SessionWebViewClearableSessionStore`，调用其 `clear()`。
- 调用 `CookieManager.clearWebsiteData()` 清全局 WebView cookies、storage、cache。

业务侧也将退出登录逻辑从：

```dart
await CookieManager().clearCookies();
```

替换为：

```dart
await sharedSessionWebViewManager.clearAllSessions();
```

这样用户退出登录后，下次进入任意 WebView session 都需要重新登录。

### 宿主集成调整

在宿主 App 中做了配套调整：

- 新增公共 holder：`lib/common/webview/session_webview_manager_holder.dart`
- `web_page_view.dart` 使用同一个 `sharedSessionWebViewManager`
- `global_config.dart` 退出登录时调用 `sharedSessionWebViewManager.clearAllSessions()`
- `web_page_view.dart` 进入页面时只调用一次 `switchToSession`
- 页面退出前显式 `captureSession`
- `PopScope`、原生返回、H5 `myapp://back` 都统一走 `_closePage()`，避免绕过保存

## 踩过的坑

### 1. 业务命名不应该进入开源库

早期命名里出现过 `ShopManager` 一类业务语义。用户指出这是开源 WebView 库，不应该绑定业务逻辑。

最终统一改成：

- `sessionKey`
- `SessionWebViewManager`
- `SessionWebViewSwitcher`
- `SessionSnapshot`

业务上的 shopId、tenantId 只由宿主传入为 `sessionKey`。

### 2. 不应该强制要求调用方知道所有 Cookie 域名

最初设计过 `sessionCookieDomainsResolver`，但业务只知道入口 URL，后续可能跳转到第三方域名。强制传 resolver 会让 API 难用且容易配置错误。

最终取消 resolver，改为自动学习导航域名，并保留 `additionalCookieDomains` 作为兜底。

### 3. dispose 阶段不能再调用 WebView JS

用户日志中出现：

```text
MissingPluginException(No implementation found for method evaluateJavascript on channel plugins.flutter.io/webview_2)
```

根因是 WebView platform view 已销毁后，`disposeSession()` 或退出流程仍尝试 `evaluateJavascript` 捕获 storage。

修复：

- `disposeSession()` 不再调用 `_captureSnapshot()`。
- snapshot 主要依赖 `onPageFinished` 和退出前显式 `captureSession()`。
- `_captureSnapshot()` 分段容错，Cookie、localStorage、sessionStorage、currentUrl 任一失败时回退已有 snapshot，不让整个保存流程失败。

### 4. 同 session 重建时先清理会把登录态清掉

早期恢复逻辑统一 `resetBeforeRestore: true`。这在跨 session 恢复时合理，但同 session 重建时会把平台 WebView 原本存在的 Cookie/localStorage 清掉。

最终增加 `_sharedSessionStateKey`：

- 相同 session：`reset=false`，不重写 Cookie/localStorage。
- 首次 session：adopt 现有平台状态。
- 不同 session：`starting clean`，清理后恢复目标 snapshot。

### 5. offstage resident WebView 在页面销毁后会变成假 resident

`SessionWebViewSwitcher` 被页面销毁后，manager 中的 entry 仍可能标记为 resident。下一次进入页面时，旧 offstage WebView 可能被重新构建，干扰当前 session。

修复：

- `SessionWebViewSwitcher` 从 `StatelessWidget` 改为 `StatefulWidget`。
- 在 `dispose()` 中调用 `detachResidentWebViews()`。
- manager 只保留 snapshot，不认为旧 platform view 仍存活。

### 6. Android Cookie API 读不到完整 Cookie 属性

Android `CookieManager.getCookie(url)` 只能读到 `name=value`，拿不到完整的原始 Domain、Path、HttpOnly、SameSite 等属性。当前实现只能近似保存：

- name
- value
- domain 使用已学习 host
- path 默认 `/`
- secure 根据 `http/https` 读取结果推断

这意味着跨 session 恢复 Cookie 能覆盖常见场景，但无法做到浏览器级别的完整 Cookie jar 导出导入。

### 7. WebView 实例常驻不等于 Cookie 隔离

Android/iOS 默认 WebView 的 Cookie jar 是全局共享的。即使多个 WebView offstage 常驻，它们也不是独立 Cookie 容器。

当前方案的隔离核心不是“每个 WebView 实例天然隔离”，而是：

- 切换前捕获当前 session。
- 切换时清理共享 WebView 状态。
- 恢复目标 session snapshot。

这适合“店铺数量少、切换频率低”的业务场景。高频切换或强隔离场景，需要平台侧支持真正独立 cookie store，或改成不同 WebView data directory/profile 的方案。

### 8. 进程重启后的恢复需要持久化 store

默认 `MemorySessionWebViewSessionStore` 只保存在内存里。App 进程被杀后，manager 不知道平台 WebView 磁盘上残留的 Cookie 属于哪个 session。

已新增 `FileSessionWebViewSessionStore()`：

```dart
final SessionWebViewManager sessionManager = SessionWebViewManager(
  sessionStore: FileSessionWebViewSessionStore(),
);
```

无参构造会使用默认路径：

```dart
FileSessionWebViewSessionStore.defaultFilePath
```

该路径位于 `Directory.systemTemp` 下的 `flutter_webview_pro/session_webview_sessions.json`，属于系统临时/缓存目录。它可以覆盖正常 App 进程重启后的 snapshot 恢复，但系统执行缓存或临时文件清理时仍可能删除。

因此：

- 默认首次打开 session 会 adopt 平台已有状态，避免误清同店铺登录态。
- 如果要求进程重启后仍恢复 session snapshot，使用 `FileSessionWebViewSessionStore()` 或自定义持久化 `SessionWebViewSessionStore`。
- 持久化 store 如需支持退出登录全清，应实现 `SessionWebViewClearableSessionStore`。

### 9. Android 编译验证受本地 JDK/Gradle 限制

插件 Dart 单测已通过，但 Android Java 编译曾失败：

```text
Unsupported class file major version 61
```

原因是 example 使用 Gradle 7.0.2，而当前环境是 JDK 17。这个错误是环境兼容问题，不是本次 Java 源码语法问题。需要切 JDK 11 或升级 Gradle 后再跑 Android 编译。

## 测试覆盖

新增和调整了 `test/webview_flutter_test.dart` 中的 session 相关测试，覆盖：

- resident WebView 复用。
- LRU 淘汰后恢复 snapshot。
- 从导航自动学习 Cookie 域名。
- 新 session key 清理共享状态，避免串线。
- dispose/capture 失败时仍可回退已有 snapshot。
- 同 session 页面销毁后重建，保留平台状态。
- 首次打开未跟踪 session 时 adopt 平台已有状态。
- 退出登录 `clearAllSessions()` 清空全部 session 和平台状态。

执行结果：

```bash
fvm flutter test test/webview_flutter_test.dart
```

结果：全部通过。

## 当前方案总结

当前实现满足以下目标：

- 只需要调用方传入 `sessionKey` 和 `initialUrl`。
- 支持入口域名和后续实际业务域名不同。
- 同 session 重进尽量保留登录态。
- 不同 session 切换时做清理和恢复，降低串线风险。
- 退出登录时全量清理，下次进入必须重新登录。
- API 命名保持通用，不绑定店铺业务。

当前仍需注意：

- 默认 snapshot store 是内存级，进程重启后不保证严格隔离。
- Android Cookie 捕获不是完整浏览器 Cookie 导出。
- WebView 常驻池不能天然隔离同域 Cookie。
- 如果第三方登录还依赖未经过 WebView 主导航的隐藏域名，需要通过 `additionalCookieDomains` 补充。
