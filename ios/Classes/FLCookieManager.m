// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FLCookieManager.h"

@implementation FLCookieManager {
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FLCookieManager *instance = [[FLCookieManager alloc] init];

  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"plugins.flutter.io/cookie_manager"
                                  binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([[call method] isEqualToString:@"clearCookies"]) {
    [self clearCookies:result];
  } else if ([[call method] isEqualToString:@"clearCookiesForDomains"]) {
    [self clearCookiesForDomains:[call arguments] result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)clearCookies:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    NSSet<NSString *> *websiteDataTypes = [NSSet setWithObject:WKWebsiteDataTypeCookies];
    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];

    void (^deleteAndNotify)(NSArray<WKWebsiteDataRecord *> *) =
        ^(NSArray<WKWebsiteDataRecord *> *cookies) {
          BOOL hasCookies = cookies.count > 0;
          [dataStore removeDataOfTypes:websiteDataTypes
                        forDataRecords:cookies
                     completionHandler:^{
                       result(@(hasCookies));
                     }];
        };

    [dataStore fetchDataRecordsOfTypes:websiteDataTypes completionHandler:deleteAndNotify];
  } else {
    // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
    NSLog(@"Clearing cookies is not supported for Flutter WebViews prior to iOS 9.");
  }
}

- (void)clearCookiesForDomains:(NSArray *)domains result:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
    WKHTTPCookieStore *cookieStore = dataStore.httpCookieStore;
    __block BOOL hadCookies = NO;
    dispatch_group_t group = dispatch_group_create();

    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
      for (NSHTTPCookie *cookie in cookies) {
        for (id domainValue in domains) {
          if (![domainValue isKindOfClass:[NSString class]]) {
            continue;
          }
          NSString *domain = [self normalizedHost:domainValue];
          if (domain.length == 0) {
            continue;
          }
          if ([self cookie:cookie matchesDomain:domain]) {
            hadCookies = YES;
            dispatch_group_enter(group);
            [cookieStore deleteCookie:cookie completionHandler:^{
              dispatch_group_leave(group);
            }];
            break;
          }
        }
      }
      dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        result(@(hadCookies));
      });
    }];
  } else {
    NSLog(@"Clearing cookies is not supported for Flutter WebViews prior to iOS 9.");
    result(@(NO));
  }
}

- (NSString *)normalizedHost:(NSString *)domain {
  NSURLComponents *components = [NSURLComponents componentsWithString:domain];
  if (components.host.length > 0) {
    return components.host.lowercaseString;
  }
  return domain.lowercaseString;
}

- (BOOL)cookie:(NSHTTPCookie *)cookie matchesDomain:(NSString *)domain {
  NSString *cookieDomain = cookie.domain.lowercaseString;
  if ([cookieDomain hasPrefix:@"."]) {
    cookieDomain = [cookieDomain substringFromIndex:1];
  }
  return [cookieDomain isEqualToString:domain] ||
         [cookieDomain hasSuffix:[NSString stringWithFormat:@".%@", domain]];
}

@end
