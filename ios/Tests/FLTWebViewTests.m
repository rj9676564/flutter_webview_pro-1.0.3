// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

@import Flutter;
@import XCTest;
@import webview_flutter;

// OCMock library doesn't generate a valid modulemap.
#import <OCMock/OCMock.h>

static bool feq(CGFloat a, CGFloat b) { return fabs(b - a) < FLT_EPSILON; }

@interface FLTWebViewTests : XCTestCase

@property(strong, nonatomic) NSObject<FlutterBinaryMessenger> *mockBinaryMessenger;

@end

@implementation FLTWebViewTests

- (void)setUp {
  [super setUp];
  self.mockBinaryMessenger = OCMProtocolMock(@protocol(FlutterBinaryMessenger));
}

- (void)testCanInitFLWebViewController {
  FLWebViewController *controller =
      [[FLWebViewController alloc] initWithFrame:CGRectMake(0, 0, 300, 400)
                                   viewIdentifier:1
                                        arguments:nil
                                  binaryMessenger:self.mockBinaryMessenger];
  XCTAssertNotNil(controller);
}

- (void)testCanInitFLWebViewFactory {
  FLWebViewFactory *factory =
      [[FLWebViewFactory alloc] initWithMessenger:self.mockBinaryMessenger];
  XCTAssertNotNil(factory);
}

- (void)testWebViewWithoutSessionKeyUsesDefaultDataStore {
  FLWebViewController *controller =
      [[FLWebViewController alloc] initWithFrame:CGRectMake(0, 0, 300, 400)
                                  viewIdentifier:1
                                       arguments:nil
                                 binaryMessenger:self.mockBinaryMessenger];
  WKWebView *webView = (WKWebView *)controller.view;
  XCTAssertEqual(webView.configuration.websiteDataStore, [WKWebsiteDataStore defaultDataStore]);
}

- (void)testClearingAllWebsiteDataKeepsExistingSessionDataStore {
  if (@available(iOS 11.0, *)) {
    NSString *sessionKey = @"test-all-clear-keeps-store";
    [FLCookieManager removeWebsiteDataStoreForSessionKey:sessionKey];
    WKWebsiteDataStore *storeBefore = [FLCookieManager websiteDataStoreForSessionKey:sessionKey];
    FLCookieManager *cookieManager = [[FLCookieManager alloc] init];
    FlutterMethodCall *call = [FlutterMethodCall
        methodCallWithMethodName:@"clearWebsiteData"
                       arguments:@{
                         @"includeCookies" : @YES,
                         @"includeLocalStorage" : @YES,
                         @"includeCache" : @NO,
                       }];
    XCTestExpectation *expectation =
        [self expectationWithDescription:@"clearWebsiteData completes"];

    [cookieManager handleMethodCall:call
                              result:^(id _Nullable result) {
                                WKWebsiteDataStore *storeAfter =
                                    [FLCookieManager websiteDataStoreForSessionKey:sessionKey];
                                XCTAssertEqual(storeBefore, storeAfter);
                                [FLCookieManager removeWebsiteDataStoreForSessionKey:sessionKey];
                                [expectation fulfill];
                              }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
  }
}

- (void)testClearingSessionWebsiteDataKeepsExistingDataStore {
  if (@available(iOS 11.0, *)) {
    NSString *sessionKey = @"test-session-clear-keeps-store";
    [FLCookieManager removeWebsiteDataStoreForSessionKey:sessionKey];
    WKWebsiteDataStore *storeBefore = [FLCookieManager websiteDataStoreForSessionKey:sessionKey];
    FLCookieManager *cookieManager = [[FLCookieManager alloc] init];
    FlutterMethodCall *call = [FlutterMethodCall
        methodCallWithMethodName:@"clearWebsiteDataForSession"
                       arguments:@{
                         @"sessionKey" : sessionKey,
                         @"includeCookies" : @YES,
                         @"includeLocalStorage" : @YES,
                         @"includeCache" : @NO,
                       }];
    XCTestExpectation *expectation =
        [self expectationWithDescription:@"clearWebsiteDataForSession completes"];

    [cookieManager handleMethodCall:call
                              result:^(id _Nullable result) {
                                WKWebsiteDataStore *storeAfter =
                                    [FLCookieManager websiteDataStoreForSessionKey:sessionKey];
                                XCTAssertEqual(storeBefore, storeAfter);
                                [FLCookieManager removeWebsiteDataStoreForSessionKey:sessionKey];
                                [expectation fulfill];
                              }];

    [self waitForExpectationsWithTimeout:5 handler:nil];
  }
}

- (void)webViewContentInsetBehaviorShouldBeNeverOnIOS11 {
  if (@available(iOS 11, *)) {
    FLWebViewController *controller =
        [[FLWebViewController alloc] initWithFrame:CGRectMake(0, 0, 300, 400)
                                     viewIdentifier:1
                                          arguments:nil
                                    binaryMessenger:self.mockBinaryMessenger];
    UIView *view = controller.view;
    XCTAssertTrue([view isKindOfClass:WKWebView.class]);
    WKWebView *webView = (WKWebView *)view;
    XCTAssertEqual(webView.scrollView.contentInsetAdjustmentBehavior,
                   UIScrollViewContentInsetAdjustmentNever);
  }
}

- (void)testWebViewScrollIndicatorAticautomaticallyAdjustsScrollIndicatorInsetsShouldbeNoOnIOS13 {
  if (@available(iOS 13, *)) {
    FLWebViewController *controller =
        [[FLWebViewController alloc] initWithFrame:CGRectMake(0, 0, 300, 400)
                                     viewIdentifier:1
                                          arguments:nil
                                    binaryMessenger:self.mockBinaryMessenger];
    UIView *view = controller.view;
    XCTAssertTrue([view isKindOfClass:WKWebView.class]);
    WKWebView *webView = (WKWebView *)view;
    XCTAssertFalse(webView.scrollView.automaticallyAdjustsScrollIndicatorInsets);
  }
}

- (void)testContentInsetsSumAlwaysZeroAfterSetFrame {
  FLWKWebView *webView = [[FLWKWebView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
  webView.scrollView.contentInset = UIEdgeInsetsMake(0, 0, 300, 0);
  XCTAssertFalse(UIEdgeInsetsEqualToEdgeInsets(webView.scrollView.contentInset, UIEdgeInsetsZero));
  webView.frame = CGRectMake(0, 0, 300, 200);
  XCTAssertTrue(UIEdgeInsetsEqualToEdgeInsets(webView.scrollView.contentInset, UIEdgeInsetsZero));
  XCTAssertTrue(CGRectEqualToRect(webView.frame, CGRectMake(0, 0, 300, 200)));

  if (@available(iOS 11, *)) {
    // After iOS 11, we need to make sure the contentInset compensates the adjustedContentInset.
    UIScrollView *partialMockScrollView = OCMPartialMock(webView.scrollView);
    UIEdgeInsets insetToAdjust = UIEdgeInsetsMake(0, 0, 300, 0);
    OCMStub(partialMockScrollView.adjustedContentInset).andReturn(insetToAdjust);
    XCTAssertTrue(UIEdgeInsetsEqualToEdgeInsets(webView.scrollView.contentInset, UIEdgeInsetsZero));
    webView.frame = CGRectMake(0, 0, 300, 100);
    XCTAssertTrue(feq(webView.scrollView.contentInset.bottom, -insetToAdjust.bottom));
    XCTAssertTrue(CGRectEqualToRect(webView.frame, CGRectMake(0, 0, 300, 100)));
  }
}

@end
