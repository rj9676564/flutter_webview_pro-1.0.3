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
  } else if ([[call method] isEqualToString:@"getCookiesForDomains"]) {
    [self getCookiesForDomains:[call arguments] result:result];
  } else if ([[call method] isEqualToString:@"setCookies"]) {
    [self setCookies:[call arguments] result:result];
  } else if ([[call method] isEqualToString:@"clearWebsiteDataForDomains"]) {
    [self clearWebsiteDataForDomains:[call arguments] result:result];
  } else if ([[call method] isEqualToString:@"clearWebsiteData"]) {
    [self clearWebsiteData:[call arguments] result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)getCookiesForDomains:(NSArray *)domains result:(FlutterResult)result {
  if (@available(iOS 11.0, *)) {
    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
    WKHTTPCookieStore *cookieStore = dataStore.httpCookieStore;

    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
      NSMutableArray<NSDictionary *> *matchedCookies = [NSMutableArray array];
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
            [matchedCookies addObject:[self serializeCookie:cookie]];
            break;
          }
        }
      }
      result(matchedCookies);
    }];
  } else {
    result(@[]);
  }
}

- (void)setCookies:(NSArray *)cookies result:(FlutterResult)result {
  if (@available(iOS 11.0, *)) {
    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
    WKHTTPCookieStore *cookieStore = dataStore.httpCookieStore;
    dispatch_group_t group = dispatch_group_create();

    for (id value in cookies) {
      if (![value isKindOfClass:[NSDictionary class]]) {
        continue;
      }
      NSHTTPCookie *cookie = [self deserializeCookie:value];
      if (cookie == nil) {
        continue;
      }
      dispatch_group_enter(group);
      [cookieStore setCookie:cookie completionHandler:^{
        dispatch_group_leave(group);
      }];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
      result(nil);
    });
  } else {
    result(nil);
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

- (void)clearWebsiteDataForDomains:(NSDictionary *)options result:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    if (![options isKindOfClass:[NSDictionary class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Expected a map of website data options"
                                 details:nil]);
      return;
    }

    NSArray *domains = options[@"domains"];
    if (![domains isKindOfClass:[NSArray class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Expected a list of domains"
                                 details:nil]);
      return;
    }

    BOOL includeCookies = [self boolValue:options[@"includeCookies"] defaultValue:YES];
    BOOL includeLocalStorage = [self boolValue:options[@"includeLocalStorage"] defaultValue:YES];
    BOOL includeCache = [self boolValue:options[@"includeCache"] defaultValue:YES];

    NSMutableSet<NSString *> *dataTypes = [NSMutableSet set];
    if (includeCookies) {
      [dataTypes addObject:WKWebsiteDataTypeCookies];
    }
    if (includeLocalStorage) {
      [dataTypes addObject:WKWebsiteDataTypeLocalStorage];
      [dataTypes addObject:WKWebsiteDataTypeSessionStorage];
      [dataTypes addObject:WKWebsiteDataTypeIndexedDBDatabases];
      [dataTypes addObject:WKWebsiteDataTypeWebSQLDatabases];
    }
    if (includeCache) {
      [dataTypes addObject:WKWebsiteDataTypeDiskCache];
      [dataTypes addObject:WKWebsiteDataTypeMemoryCache];
    }
    if (dataTypes.count == 0 || domains.count == 0) {
      result(@(NO));
      return;
    }

    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
    [dataStore fetchDataRecordsOfTypes:dataTypes completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
      NSMutableArray<WKWebsiteDataRecord *> *matchedRecords = [NSMutableArray array];
      for (WKWebsiteDataRecord *record in records) {
        NSString *recordDomain = record.displayName.lowercaseString;
        for (id domainValue in domains) {
          if (![domainValue isKindOfClass:[NSString class]]) {
            continue;
          }
          NSString *domain = [self normalizedHost:domainValue];
          if (domain.length == 0) {
            continue;
          }
          if ([self host:recordDomain matchesDomain:domain]) {
            [matchedRecords addObject:record];
            break;
          }
        }
      }

      BOOL hadData = matchedRecords.count > 0;
      if (!hadData) {
        result(@(NO));
        return;
      }
      [dataStore removeDataOfTypes:dataTypes
                    forDataRecords:matchedRecords
                 completionHandler:^{
                   result(@(YES));
                 }];
    }];
  } else {
    NSLog(@"Clearing website data is not supported for Flutter WebViews prior to iOS 9.");
    result(@(NO));
  }
}

- (void)clearWebsiteData:(NSDictionary *)options result:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    if (![options isKindOfClass:[NSDictionary class]]) {
      result([FlutterError errorWithCode:@"invalid_arguments"
                                 message:@"Expected a map of website data options"
                                 details:nil]);
      return;
    }

    BOOL includeCookies = [self boolValue:options[@"includeCookies"] defaultValue:YES];
    BOOL includeLocalStorage = [self boolValue:options[@"includeLocalStorage"] defaultValue:YES];
    BOOL includeCache = [self boolValue:options[@"includeCache"] defaultValue:YES];
    NSMutableSet<NSString *> *dataTypes = [NSMutableSet set];
    if (includeCookies) {
      [dataTypes addObject:WKWebsiteDataTypeCookies];
    }
    if (includeLocalStorage) {
      [dataTypes addObject:WKWebsiteDataTypeLocalStorage];
      [dataTypes addObject:WKWebsiteDataTypeSessionStorage];
      [dataTypes addObject:WKWebsiteDataTypeIndexedDBDatabases];
      [dataTypes addObject:WKWebsiteDataTypeWebSQLDatabases];
    }
    if (includeCache) {
      [dataTypes addObject:WKWebsiteDataTypeDiskCache];
      [dataTypes addObject:WKWebsiteDataTypeMemoryCache];
    }
    if (dataTypes.count == 0) {
      result(@(NO));
      return;
    }

    WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];
    [dataStore fetchDataRecordsOfTypes:dataTypes completionHandler:^(NSArray<WKWebsiteDataRecord *> *records) {
      BOOL hadData = records.count > 0;
      if (!hadData) {
        result(@(NO));
        return;
      }
      [dataStore removeDataOfTypes:dataTypes
                    forDataRecords:records
                 completionHandler:^{
                   result(@(YES));
                 }];
    }];
  } else {
    NSLog(@"Clearing website data is not supported for Flutter WebViews prior to iOS 9.");
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

- (BOOL)host:(NSString *)host matchesDomain:(NSString *)domain {
  if (host.length == 0 || domain.length == 0) {
    return NO;
  }
  return [host isEqualToString:domain] ||
         [host hasSuffix:[NSString stringWithFormat:@".%@", domain]];
}

- (BOOL)boolValue:(id)value defaultValue:(BOOL)defaultValue {
  if ([value isKindOfClass:[NSNumber class]]) {
    return [value boolValue];
  }
  return defaultValue;
}

- (NSDictionary *)serializeCookie:(NSHTTPCookie *)cookie {
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  map[@"name"] = cookie.name ?: @"";
  map[@"value"] = cookie.value ?: @"";
  map[@"domain"] = cookie.domain ?: @"";
  map[@"path"] = cookie.path ?: @"/";
  map[@"isSecure"] = @(cookie.secure);
  map[@"isHttpOnly"] = @([self cookieIsHttpOnly:cookie]);
  if (cookie.expiresDate != nil) {
    map[@"expiresDate"] = @((long long)(cookie.expiresDate.timeIntervalSince1970 * 1000));
  } else {
    map[@"expiresDate"] = [NSNull null];
  }
  return map;
}

- (NSHTTPCookie *)deserializeCookie:(NSDictionary *)value {
  NSString *name = value[@"name"];
  NSString *domain = value[@"domain"];
  if (name.length == 0 || domain.length == 0) {
    return nil;
  }

  NSMutableDictionary<NSHTTPCookiePropertyKey, id> *properties =
      [NSMutableDictionary dictionary];
  properties[NSHTTPCookieName] = name;
  properties[NSHTTPCookieValue] = value[@"value"] ?: @"";
  properties[NSHTTPCookieDomain] = [self normalizedHost:domain];
  properties[NSHTTPCookiePath] = value[@"path"] ?: @"/";

  if ([value[@"isSecure"] boolValue]) {
    properties[NSHTTPCookieSecure] = @"TRUE";
  }
  if ([value[@"isHttpOnly"] boolValue]) {
    properties[@"HttpOnly"] = @"TRUE";
  }
  id expiresDate = value[@"expiresDate"];
  if ([expiresDate isKindOfClass:[NSNumber class]]) {
    NSTimeInterval interval = [expiresDate doubleValue] / 1000.0;
    properties[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSince1970:interval];
  }
  return [NSHTTPCookie cookieWithProperties:properties];
}

- (BOOL)cookieIsHttpOnly:(NSHTTPCookie *)cookie {
  NSString *sameSitePolicy = cookie.properties[@"HttpOnly"];
  if ([sameSitePolicy isKindOfClass:[NSString class]]) {
    return [sameSitePolicy caseInsensitiveCompare:@"TRUE"] == NSOrderedSame;
  }
  return NO;
}

@end
