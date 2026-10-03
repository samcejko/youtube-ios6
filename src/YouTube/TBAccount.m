#import "TBAccount.h"
#import "TBLibrary.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <Security/Security.h>

NSString * const TBAccountDidChangeNotification = @"TBAccountDidChangeNotification";

// The YouTube Smart TV OAuth client credentials (Samsung SmartTV / Tizen) as used by YouTube UWP.
// Enables seamless device code + QR code login without needing custom Google Cloud projects.
static NSString * const TBGoogleDefaultClientID = @"861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com";
static NSString * const TBGoogleDefaultClientSecret = @"SboVhoG9s0rNafixCSGGKXAT";
static NSString * const TBGoogleScope = @"http://gdata.youtube.com https://www.googleapis.com/auth/youtube-paid-content";
static NSString * const TBGoogleDeviceCodeURL = @"https://www.youtube.com/o/oauth2/device/code";
static NSString * const TBGoogleTokenURL = @"https://www.youtube.com/o/oauth2/token";
static NSString * const TBGoogleRefreshURL = @"https://oauth2.googleapis.com/token";
static NSString * const TBGoogleRevokeURL = @"https://oauth2.googleapis.com/revoke";
static NSString * const TBDataAPIBase = @"https://www.googleapis.com/youtube/v3/";
static NSString * const TBInnertubeApiKey = @"AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8";
static NSString * const TBInnertubeBase = @"https://www.youtube.com/youtubei/v1/";
static NSString * const TBTvUserAgent = @"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0)";
static NSString * const TBTvDeviceModel = @"ytlr:samsung:smarttv";

static NSString * const TBKeychainService = @"com.samcejko.tubie.google";
static NSString * const TBKeychainAccount = @"oauth";

#pragma mark - Keychain

static NSMutableDictionary *TBKeychainQuery(void)
{
    return [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
               (__bridge id)kSecAttrService: TBKeychainService,
               (__bridge id)kSecAttrAccount: TBKeychainAccount } mutableCopy];
}

static NSDictionary *TBKeychainRead(void)
{
    NSMutableDictionary *query = TBKeychainQuery();
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

static void TBKeychainWrite(NSDictionary *tokens)
{
    NSMutableDictionary *query = TBKeychainQuery();
    SecItemDelete((__bridge CFDictionaryRef)query);
    if (!tokens) return;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:tokens format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) return;
    query[(__bridge id)kSecValueData] = data;
    query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if (status != errSecSuccess) TBLog(@"Keychain: the tokens could not be kept (%d)", (int)status);
}

#pragma mark - Account

@interface TBAccount ()
@property (nonatomic, strong) TBHTTPTask *signInRequest;     // the device-code or token request under way (cancelled with the sign-in task)
@property (nonatomic, strong) TBHTTPTask *syncRequest;       // the subscriptions page under way (cancelled with the sync task)
@property (nonatomic, copy) NSString *storedClientId;       // the client id typed into Settings (nil = the built-in default)
@property (nonatomic, copy) NSString *storedClientSecret;   // the client secret typed into Settings (nil = the built-in default)
@property (nonatomic, copy) NSString *accessToken;
- (void)pollDeviceCode:(NSString *)deviceCode secret:(NSString *)secret interval:(NSTimeInterval)interval deadline:(NSDate *)deadline
                 after:(NSTimeInterval)wait task:(TBHTTPTask *)outer completion:(void (^)(NSError *error))completion;
- (void)fetchSubscriptionsPage:(NSString *)token into:(NSMutableArray *)channels ids:(NSMutableDictionary *)ids task:(TBHTTPTask *)outer
                    completion:(void (^)(NSArray *channels, NSError *error))completion;
- (void)fetchTvQrCode:(NSString *)userCode completion:(void (^)(UIImage *qrImage))completion;
@property (nonatomic, copy) NSString *refreshToken;
@property (nonatomic, strong) NSDate *tokenExpiry;
@property (nonatomic, copy, readwrite) NSString *channelTitle;
@property (nonatomic, copy, readwrite) NSString *channelId;
@property (nonatomic, copy, readwrite) NSString *handle;
@property (nonatomic, copy, readwrite) NSString *avatarURL;
@property (nonatomic, strong) NSMutableDictionary *subscriptionIds;   // channel id -> subscription id (the API deletes by the latter)
@end

@implementation TBAccount

+ (instancetype)shared
{
    static TBAccount *account;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ account = [[TBAccount alloc] init]; });
    return account;
}

+ (BOOL)isConfigured
{
    return [TBAccount shared].clientSecret.length > 0;
}

- (NSString *)clientId
{
    return self.storedClientId.length ? self.storedClientId : TBGoogleDefaultClientID;
}

- (void)setClientId:(NSString *)clientId
{
    NSString *trimmed = [clientId stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // (the built-in default typed back in is treated as "use the default")
    self.storedClientId = (trimmed.length && ![trimmed isEqualToString:TBGoogleDefaultClientID]) ? trimmed : nil;
    [self writeKeychain];
    [self notify];
}

- (BOOL)usesOwnClientId
{
    return self.storedClientId.length > 0;
}

- (NSString *)clientSecret
{
    return self.storedClientSecret.length ? self.storedClientSecret : TBGoogleDefaultClientSecret;
}

- (void)setClientSecret:(NSString *)secret
{
    NSString *trimmed = [secret stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.storedClientSecret = (trimmed.length && ![trimmed isEqualToString:TBGoogleDefaultClientSecret]) ? trimmed : nil;
    [self writeKeychain];
    [self notify];
}

- (BOOL)usesOwnClientSecret
{
    return self.storedClientSecret.length > 0;
}

- (BOOL)usesCustomOAuthClient
{
    return [self usesOwnClientId] || [self usesOwnClientSecret];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _subscriptionIds = [NSMutableDictionary dictionary];
        NSDictionary *kept = TBKeychainRead();
        _storedClientSecret = kept[@"secret"];
        _storedClientId = kept[@"clientId"];
#ifdef TB_GOOGLE_CLIENT_SECRET
        // the secret the build was given (a repository secret of the CI); one typed into Settings wins
        if (!_storedClientSecret.length && strlen(TB_GOOGLE_CLIENT_SECRET) > 0) _storedClientSecret = @TB_GOOGLE_CLIENT_SECRET;
#endif
        _accessToken = kept[@"access"];
        _refreshToken = kept[@"refresh"];
        _tokenExpiry = [kept[@"expiry"] isKindOfClass:[NSDate class]] ? kept[@"expiry"] : nil;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        _channelTitle = [d stringForKey:@"accountChannelTitle"];
        _channelId = [d stringForKey:@"accountChannelId"];
        _handle = [d stringForKey:@"accountHandle"];
        _avatarURL = [d stringForKey:@"accountAvatar"];
    }
    return self;
}

- (BOOL)isSignedIn
{
    return self.refreshToken.length > 0;
}

- (void)notify
{
    TBMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TBAccountDidChangeNotification object:self]; });
}

- (void)writeKeychain
{
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    if (self.storedClientSecret) kept[@"secret"] = self.storedClientSecret;
    if (self.storedClientId) kept[@"clientId"] = self.storedClientId;
    if (self.accessToken) kept[@"access"] = self.accessToken;
    if (self.refreshToken) kept[@"refresh"] = self.refreshToken;
    if (self.tokenExpiry) kept[@"expiry"] = self.tokenExpiry;
    TBKeychainWrite(kept.count ? kept : nil);
}

- (void)keepTokensFrom:(NSDictionary *)json
{
    NSString *access = TBStr(json[@"access_token"]);
    if (access.length) self.accessToken = access;
    NSString *refresh = TBStr(json[@"refresh_token"]);
    if (refresh.length) self.refreshToken = refresh;
    double expires = TBDbl(json[@"expires_in"]);
    self.tokenExpiry = [NSDate dateWithTimeIntervalSinceNow:expires > 0 ? expires - 60 : 3000];
    [self writeKeychain];
}

+ (NSError *)errorFromOAuth:(id)json status:(NSInteger)status fallback:(NSError *)error
{
    NSDictionary *d = TBDict(json);
    NSString *code = TBStr(d[@"error"]);
    NSString *description = TBStr(d[@"error_description"]);
    if ([code isEqualToString:@"access_denied"]) return TBMakeError(TBErrorAuth, L(@"The sign-in was refused."));
    if ([code isEqualToString:@"expired_token"]) return TBMakeError(TBErrorAuth, L(@"The code expired. Try again."));
    if ([code isEqualToString:@"invalid_grant"]) return TBMakeError(TBErrorAuth, L(@"The sign-in is no longer valid. Sign in again."));
    if ([code isEqualToString:@"invalid_client"]) return TBMakeError(TBErrorAuth, L(@"The app's Google client is not set up correctly."));
    if (description.length) return TBMakeError(TBErrorAuth, description);
    return error ?: TBMakeError(TBErrorAuth, [NSString stringWithFormat:L(@"Google answered with an error (HTTP %ld)."), (long)status]);
}

#pragma mark - Device flow

- (TBHTTPTask *)signInWithCodeHandler:(void (^)(NSString *userCode, NSString *verificationURL, UIImage *qrImage))codeHandler
                           completion:(void (^)(NSError *error))completion
{
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    __weak TBAccount *weakSelf = self;
    outer.cancelBlock = ^{ [weakSelf.signInRequest cancel]; weakSelf.signInRequest = nil; };
    if (![TBAccount isConfigured]) {
        TBMain(^{ completion(TBMakeError(TBErrorAuth, L(@"Enter the Google client secret in Settings first."))); });
        return outer;
    }
    NSString *secret = self.clientSecret;
    NSString *clientId = self.clientId;
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    NSString *deviceId = uuid ? [(__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) lowercaseString] : @"ios-tubie";
    if (uuid) CFRelease(uuid);

    BOOL customClient = [self usesCustomOAuthClient];
    NSString *deviceCodeURL = customClient ? @"https://oauth2.googleapis.com/device/code" : TBGoogleDeviceCodeURL;
    NSString *scope = customClient ? @"https://www.googleapis.com/auth/youtube.force-ssl" : TBGoogleScope;
    NSMutableDictionary *fields = [@{ @"client_id": clientId, @"scope": scope } mutableCopy];
    NSDictionary *headers = nil;
    if (!customClient) {
        fields[@"device_id"] = deviceId;
        fields[@"device_model"] = TBTvDeviceModel;
        headers = @{ @"User-Agent": TBTvUserAgent };
    }

    self.signInRequest = [TBHTTP postForm:deviceCodeURL headers:headers fields:fields completion:^(id json, NSInteger status, NSError *error) {
        TBAccount *s = weakSelf;
        if (!s || outer.isCancelled) return;
        s.signInRequest = nil;
        NSDictionary *d = TBDict(json);
        NSString *deviceCode = TBStr(d[@"device_code"]), *userCode = TBStr(d[@"user_code"]);
        if (error || !deviceCode.length || !userCode.length) { completion([TBAccount errorFromOAuth:json status:status fallback:error]); return; }
        NSString *url = TBStr(d[@"verification_url"]) ?: (customClient ? @"https://www.google.com/device" : @"https://www.youtube.com/activate");
        NSTimeInterval interval = MAX(3, TBDbl(d[@"interval"]) > 0 ? TBDbl(d[@"interval"]) : 5);
        NSTimeInterval expires = TBDbl(d[@"expires_in"]) > 0 ? TBDbl(d[@"expires_in"]) : 1800;
        codeHandler(userCode, url, nil);
        if (!customClient) {
            [s fetchTvQrCode:userCode completion:^(UIImage *qrImage) {
                if (qrImage && !outer.isCancelled) {
                    codeHandler(userCode, url, qrImage);
                }
            }];
        }
        TBLog(@"Google sign-in: code %@ shown, polling every %.0f s", userCode, interval);
        [s pollDeviceCode:deviceCode secret:secret interval:interval deadline:[NSDate dateWithTimeIntervalSinceNow:expires] after:interval task:outer completion:completion];
    }];
    return outer;
}

- (void)fetchTvQrCode:(NSString *)userCode completion:(void (^)(UIImage *qrImage))completion
{
    if (!userCode.length) { TBMain(^{ completion(nil); }); return; }
    NSString *url = [NSString stringWithFormat:@"%@mdx/handoff?key=%@&prettyPrint=false", TBInnertubeBase, TBInnertubeApiKey];
    NSDictionary *headers = @{ @"User-Agent": TBTvUserAgent,
                               @"Content-Type": @"application/json",
                               @"Accept": @"application/json" };
    NSDictionary *body = @{
        @"context": @{
            @"client": @{
                @"clientName": @"TVHTML5",
                @"clientVersion": @"7.20251217.19.00",
                @"deviceMake": @"Samsung",
                @"deviceModel": @"SmartTV",
                @"platform": @"TV",
                @"hl": [TBSettings contentLanguage] ?: @"en",
                @"gl": [TBSettings contentRegion] ?: @"US"
            }
        },
        @"handoffQrParams": @{
            @"rapidQrParams": @{
                @"qrPresetStyle": @"HANDOFF_QR_LIMITED_PRESET_STYLE_MODERN_BIG_DOTS_INVERT_WITH_YT_LOGO",
                @"userCode": userCode,
                @"rapidQrFeature": @"RAPID_QR_FEATURE_DEFAULT"
            }
        }
    };
    [TBHTTP postJSON:url headers:headers object:body retries:1 completion:^(id json, NSInteger status, NSError *error) {
        if (error || !json) { completion(nil); return; }
        NSDictionary *rapid = TBDict(TBDict(json)[@"rapidQrRenderer"]);
        NSDictionary *renderer = TBDict(rapid[@"qrCodeRenderer"]);
        NSDictionary *img = TBDict(renderer[@"qrCodeImage"]);
        NSArray *thumbs = TBArr(img[@"thumbnails"]);
        NSString *qrUrl = TBStr(TBDict([thumbs firstObject])[@"url"]);
        if (!qrUrl.length) { completion(nil); return; }
        if ([qrUrl rangeOfString:@"base64," options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSData *data = [TBUtils base64Decode:qrUrl];
            UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
            completion(image);
            return;
        }
        [TBHTTP request:@"GET" url:qrUrl headers:nil body:nil retries:1 completion:^(NSInteger s, NSData *bodyData, NSDictionary *h, NSError *e) {
            UIImage *image = bodyData.length ? [UIImage imageWithData:bodyData] : nil;
            completion(image);
        }];
    }];
}

// One token request after `wait` seconds; while Google says the user has not confirmed yet, the next one follows
- (void)pollDeviceCode:(NSString *)deviceCode secret:(NSString *)secret interval:(NSTimeInterval)interval deadline:(NSDate *)deadline
                 after:(NSTimeInterval)wait task:(TBHTTPTask *)outer completion:(void (^)(NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TBAccount *s = weakSelf;
        if (!s || outer.isCancelled) return;
        if ([deadline timeIntervalSinceNow] < 0) { completion(TBMakeError(TBErrorAuth, L(@"The code expired. Try again."))); return; }
        BOOL customClient = [s usesCustomOAuthClient];
        NSString *tokenURL = customClient ? @"https://oauth2.googleapis.com/token" : TBGoogleTokenURL;
        NSString *grantType = customClient ? @"urn:ietf:params:oauth:grant-type:device_code" : @"http://oauth.net/grant_type/device/1.0";
        NSDictionary *fields = @{ @"client_id": s.clientId,
                                  @"client_secret": secret,
                                  @"code": deviceCode,
                                  @"grant_type": grantType };
        NSDictionary *headers = customClient ? nil : @{ @"User-Agent": TBTvUserAgent };
        s.signInRequest = [TBHTTP postForm:tokenURL headers:headers fields:fields completion:^(id json, NSInteger status, NSError *error) {
            TBAccount *account = weakSelf;
            if (!account || outer.isCancelled) return;
            account.signInRequest = nil;
            NSDictionary *t = TBDict(json);
            NSString *code = TBStr(t[@"error"]);
            if (TBStr(t[@"access_token"]).length) {
                [account keepTokensFrom:t];
                TBLog(@"Google sign-in: signed in");
                [account notify];
                completion(nil);
                [account fetchProfile:^(NSError *e) { if (e) TBLog(@"Profile: %@", e.localizedDescription); }];
                [account syncSubscriptions:^(NSArray *channels, NSError *e) { if (e) TBLog(@"Subscriptions: %@", e.localizedDescription); }];
                return;
            }
            BOOL hiccup = !code.length && (error.code == TBErrorNetwork || error.code == TBErrorTimeout || error.code == TBErrorConnectionLost);
            if ([code isEqualToString:@"authorization_pending"] || [code isEqualToString:@"slow_down"] || hiccup) {
                NSTimeInterval next = [code isEqualToString:@"authorization_pending"] ? interval : interval + 5;
                [account pollDeviceCode:deviceCode secret:secret interval:interval deadline:deadline after:next task:outer completion:completion];
                return;
            }
            completion([TBAccount errorFromOAuth:json status:status fallback:error]);
        }];
    });
}

- (void)signOut
{
    NSString *token = self.refreshToken ?: self.accessToken;
    if (token.length) {
        [TBHTTP postForm:TBGoogleRevokeURL fields:@{ @"token": token } completion:^(id json, NSInteger status, NSError *error) {}];
    }
    self.accessToken = nil;
    self.refreshToken = nil;
    self.tokenExpiry = nil;
    [self writeKeychain];
    self.channelTitle = nil;
    self.channelId = nil;
    self.handle = nil;
    self.avatarURL = nil;
    [self.subscriptionIds removeAllObjects];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[ @"accountChannelTitle", @"accountChannelId", @"accountHandle", @"accountAvatar" ]) [d removeObjectForKey:key];
    [d synchronize];
    TBLog(@"Google sign-in: signed out");
    [self notify];
}

#pragma mark - Tokens

// A valid access token (refreshed when it ran out), on the main thread
- (TBHTTPTask *)withAccessToken:(void (^)(NSString *token, NSError *error))completion
{
    if (!self.isSignedIn) { TBMain(^{ completion(nil, TBMakeError(TBErrorAuth, L(@"Not signed in."))); }); return nil; }
    if (self.accessToken.length && self.tokenExpiry && [self.tokenExpiry timeIntervalSinceNow] > 0) {
        NSString *token = self.accessToken;
        TBMain(^{ completion(token, nil); });
        return nil;
    }
    if (!self.clientSecret.length) { TBMain(^{ completion(nil, TBMakeError(TBErrorAuth, L(@"Enter the Google client secret in Settings first."))); }); return nil; }
    __weak TBAccount *weakSelf = self;
    NSDictionary *fields = @{ @"client_id": self.clientId, @"client_secret": self.clientSecret, @"refresh_token": self.refreshToken, @"grant_type": @"refresh_token" };
    return [TBHTTP postForm:TBGoogleRefreshURL fields:fields completion:^(id json, NSInteger status, NSError *error) {
        TBAccount *s = weakSelf;
        NSDictionary *t = TBDict(json);
        if (TBStr(t[@"access_token"]).length) { [s keepTokensFrom:t]; completion(s.accessToken, nil); return; }
        NSError *failure = [TBAccount errorFromOAuth:json status:status fallback:error];
        if ([TBStr(t[@"error"]) isEqualToString:@"invalid_grant"]) {
            TBLog(@"Google sign-in: the refresh token was rejected, signing out");
            [s signOut];
        }
        completion(nil, failure);
    }];
}

#pragma mark - Data API

+ (NSError *)errorFromAPI:(id)json status:(NSInteger)status fallback:(NSError *)error
{
    NSDictionary *e = TBDict(TBDict(json)[@"error"]);
    NSString *reason = nil;
    for (id item in TBArr(e[@"errors"])) { reason = TBStr(TBDict(item)[@"reason"]); if (reason) break; }
    if ([reason isEqualToString:@"quotaExceeded"] || [reason isEqualToString:@"dailyLimitExceeded"]) return TBMakeError(TBErrorAPI, L(@"The daily limit of YouTube's API is used up; it starts over at 9:00 (Pacific midnight)."));
    if (status == 401) return TBMakeError(TBErrorAuth, L(@"The sign-in is no longer valid. Sign in again."));
    NSString *message = TBStr(e[@"message"]);
    if (message.length) return TBMakeError(TBErrorAPI, message);
    return error ?: TBMakeError(TBErrorAPI, [NSString stringWithFormat:L(@"YouTube's API answered with an error (HTTP %ld)."), (long)status]);
}

// One call of the Data API with the account's token; `query` are URL parameters, `body` a JSON object for POST/PUT
- (TBHTTPTask *)api:(NSString *)method path:(NSString *)path query:(NSDictionary *)query body:(id)body
         completion:(void (^)(NSDictionary *json, NSError *error))completion
{
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    __block TBHTTPTask *inner = nil;
    outer.cancelBlock = ^{ [inner cancel]; };
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in [[query allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, [TBUtils urlEncode:[query[key] description]]]];
    }
    NSString *url = [NSString stringWithFormat:@"%@%@%@%@", TBDataAPIBase, path, pairs.count ? @"?" : @"", [pairs componentsJoinedByString:@"&"]];
    inner = [self withAccessToken:^(NSString *token, NSError *error) {
        if (outer.isCancelled) return;
        if (!token) { completion(nil, error); return; }
        NSDictionary *headers = @{ @"Authorization": [@"Bearer " stringByAppendingString:token], @"Accept": @"application/json",
                                   @"Content-Type": @"application/json" };
        NSData *data = body ? [TBUtils JSONDataFromObject:body] : nil;
        inner = [TBHTTP request:method url:url headers:headers body:data retries:0 completion:^(NSInteger status, NSData *responseBody, NSDictionary *responseHeaders, NSError *requestError) {
            if (outer.isCancelled) return;
            id json = responseBody.length ? [TBUtils JSONObjectFromData:responseBody] : nil;
            if (requestError || status >= 400) { completion(nil, [TBAccount errorFromAPI:json status:status fallback:requestError]); return; }
            completion(TBDict(json) ?: @{}, nil);
        }];
    }];
    return outer;
}

- (TBHTTPTask *)fetchProfile:(void (^)(NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    return [self api:@"GET" path:@"channels" query:@{ @"part": @"snippet", @"mine": @"true" } body:nil completion:^(NSDictionary *json, NSError *error) {
        TBAccount *s = weakSelf;
        if (error) { completion(error); return; }
        NSDictionary *item = TBDict([TBArr(json[@"items"]) firstObject]);
        NSDictionary *snippet = TBDict(item[@"snippet"]);
        if (item) {
            s.channelId = TBStr(item[@"id"]);
            s.channelTitle = TBStr(snippet[@"title"]);
            s.handle = TBStr(snippet[@"customUrl"]);
            s.avatarURL = TBImageURL(TBThumbnailURL(snippet[@"thumbnails"]) ?: TBStr(TBDict(TBDict(snippet[@"thumbnails"])[@"default"])[@"url"]));
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setObject:s.channelTitle ?: @"" forKey:@"accountChannelTitle"];
            [d setObject:s.channelId ?: @"" forKey:@"accountChannelId"];
            [d setObject:s.handle ?: @"" forKey:@"accountHandle"];
            [d setObject:s.avatarURL ?: @"" forKey:@"accountAvatar"];
            [s notify];
        }
        completion(nil);
    }];
}

// The thumbnails object of the Data API: {"default": {"url"}, "medium": {...}, "high": {...}} - the largest
static NSString *TBAPIThumbnail(NSDictionary *thumbnails)
{
    for (NSString *key in @[ @"maxres", @"standard", @"high", @"medium", @"default" ]) {
        NSString *url = TBStr(TBDict(thumbnails[key])[@"url"]);
        if (url.length) return TBImageURL(url);
    }
    return nil;
}

- (TBHTTPTask *)syncSubscriptions:(void (^)(NSArray *channels, NSError *error))completion
{
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    __weak TBAccount *weakSelf = self;
    outer.cancelBlock = ^{ [weakSelf.syncRequest cancel]; weakSelf.syncRequest = nil; };
    [self fetchSubscriptionsPage:nil into:[NSMutableArray array] ids:[NSMutableDictionary dictionary] task:outer completion:completion];
    return outer;
}

// One page of the account's subscriptions; the next page follows until there is none (or a thousand channels)
- (void)fetchSubscriptionsPage:(NSString *)token into:(NSMutableArray *)channels ids:(NSMutableDictionary *)ids task:(TBHTTPTask *)outer
                    completion:(void (^)(NSArray *channels, NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    NSMutableDictionary *query = [@{ @"part": @"snippet", @"mine": @"true", @"maxResults": @"50", @"order": @"alphabetical" } mutableCopy];
    if (token.length) query[@"pageToken"] = token;
    self.syncRequest = [self api:@"GET" path:@"subscriptions" query:query body:nil completion:^(NSDictionary *json, NSError *error) {
        TBAccount *s = weakSelf;
        if (!s || outer.isCancelled) return;
        s.syncRequest = nil;
        if (error) { completion(nil, error); return; }
        for (id item in TBArr(json[@"items"])) {
            NSDictionary *d = TBDict(item), *snippet = TBDict(d[@"snippet"]);
            TBChannel *c = [[TBChannel alloc] init];
            c.channelId = TBStr(TBDict(snippet[@"resourceId"])[@"channelId"]);
            if (!c.channelId.length) continue;
            c.title = TBStr(snippet[@"title"]);
            c.descriptionText = TBStr(snippet[@"description"]);
            c.avatarURL = TBAPIThumbnail(TBDict(snippet[@"thumbnails"]));
            c.subscribedAt = TBDateFromISO(TBStr(snippet[@"publishedAt"])) ?: [NSDate date];
            [channels addObject:c];
            NSString *subscriptionId = TBStr(d[@"id"]);
            if (subscriptionId) ids[c.channelId] = subscriptionId;
        }
        NSString *next = TBStr(json[@"nextPageToken"]);
        if (next.length && channels.count < 1000) { [s fetchSubscriptionsPage:next into:channels ids:ids task:outer completion:completion]; return; }
        [s.subscriptionIds addEntriesFromDictionary:ids];
        [channels sortUsingComparator:^NSComparisonResult(TBChannel *a, TBChannel *b) { return [b.subscribedAt compare:a.subscribedAt]; }];
        [[TBLibrary shared] replaceSubscriptions:channels];
        TBLog(@"Google account: %lu subscriptions", (unsigned long)channels.count);
        [s notify];
        completion(channels, nil);
    }];
}

- (TBHTTPTask *)subscribeTo:(TBChannel *)channel completion:(void (^)(NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    id body = @{ @"snippet": @{ @"resourceId": @{ @"kind": @"youtube#channel", @"channelId": channel.channelId ?: @"" } } };
    return [self api:@"POST" path:@"subscriptions" query:@{ @"part": @"snippet" } body:body completion:^(NSDictionary *json, NSError *error) {
        if (!error) {
            NSString *subscriptionId = TBStr(json[@"id"]);
            if (subscriptionId && channel.channelId) weakSelf.subscriptionIds[channel.channelId] = subscriptionId;
        }
        completion(error);
    }];
}

- (TBHTTPTask *)unsubscribeFrom:(NSString *)channelId completion:(void (^)(NSError *error))completion
{
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    __block TBHTTPTask *inner = nil;
    outer.cancelBlock = ^{ [inner cancel]; };
    __weak TBAccount *weakSelf = self;
    void (^remove)(NSString *) = ^(NSString *subscriptionId) {
        inner = [weakSelf api:@"DELETE" path:@"subscriptions" query:@{ @"id": subscriptionId } body:nil completion:^(NSDictionary *json, NSError *error) {
            if (outer.isCancelled) return;
            if (!error) [weakSelf.subscriptionIds removeObjectForKey:channelId];
            completion(error);
        }];
    };
    NSString *known = self.subscriptionIds[channelId ?: @""];
    if (known.length) { remove(known); return outer; }
    // (the subscription's own id is needed: looked up by the channel)
    inner = [self api:@"GET" path:@"subscriptions" query:@{ @"part": @"id", @"mine": @"true", @"forChannelId": channelId ?: @"" } body:nil completion:^(NSDictionary *json, NSError *error) {
        if (outer.isCancelled) return;
        if (error) { completion(error); return; }
        NSString *subscriptionId = TBStr(TBDict([TBArr(json[@"items"]) firstObject])[@"id"]);
        if (!subscriptionId.length) { completion(nil); return; }   // (not subscribed there anyway)
        remove(subscriptionId);
    }];
    return outer;
}

- (TBHTTPTask *)rateVideo:(NSString *)videoId rating:(NSString *)rating completion:(void (^)(NSError *error))completion
{
    return [self api:@"POST" path:@"videos/rate" query:@{ @"id": videoId ?: @"", @"rating": rating ?: @"none" } body:nil completion:^(NSDictionary *json, NSError *error) {
        completion(error);
    }];
}

- (TBHTTPTask *)ratingOfVideo:(NSString *)videoId completion:(void (^)(NSString *rating, NSError *error))completion
{
    return [self api:@"GET" path:@"videos/getRating" query:@{ @"id": videoId ?: @"" } body:nil completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        completion(TBStr(TBDict([TBArr(json[@"items"]) firstObject])[@"rating"]) ?: @"none", nil);
    }];
}

#pragma mark - Comments

// A TBComment from a Data API comment resource's snippet (the account's just-posted comment or reply)
- (TBComment *)commentFromSnippet:(NSDictionary *)snippet commentId:(NSString *)commentId
{
    TBComment *c = [[TBComment alloc] init];
    c.commentId = commentId;
    c.text = TBStr(snippet[@"textDisplay"]) ?: TBStr(snippet[@"textOriginal"]);
    c.authorName = TBStr(snippet[@"authorDisplayName"]) ?: self.channelTitle;
    c.authorChannelId = TBStr(TBDict(snippet[@"authorChannelId"])[@"value"]) ?: self.channelId;
    c.authorAvatarURL = TBImageURL(TBStr(snippet[@"authorProfileImageUrl"])) ?: self.avatarURL;
    c.publishedText = L(@"just now");
    c.likesText = nil;
    return c;
}

- (TBHTTPTask *)postComment:(NSString *)text onVideo:(NSString *)videoId completion:(void (^)(TBComment *comment, NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    id body = @{ @"snippet": @{ @"videoId": videoId ?: @"", @"topLevelComment": @{ @"snippet": @{ @"textOriginal": text ?: @"" } } } };
    return [self api:@"POST" path:@"commentThreads" query:@{ @"part": @"snippet" } body:body completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *top = TBDict(TBDict(TBDict(json[@"snippet"])[@"topLevelComment"]));
        TBComment *c = [weakSelf commentFromSnippet:TBDict(top[@"snippet"]) commentId:TBStr(top[@"id"]) ?: TBStr(json[@"id"])];
        completion(c, nil);
    }];
}

- (TBHTTPTask *)replyWithText:(NSString *)text toComment:(NSString *)parentId completion:(void (^)(TBComment *comment, NSError *error))completion
{
    __weak TBAccount *weakSelf = self;
    id body = @{ @"snippet": @{ @"parentId": parentId ?: @"", @"textOriginal": text ?: @"" } };
    return [self api:@"POST" path:@"comments" query:@{ @"part": @"snippet" } body:body completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, error); return; }
        TBComment *c = [weakSelf commentFromSnippet:TBDict(json[@"snippet"]) commentId:TBStr(json[@"id"])];
        c.isReply = YES;
        completion(c, nil);
    }];
}

- (TBHTTPTask *)likedVideosPage:(NSString *)pageToken completion:(TBItemsCompletion)completion
{
    NSMutableDictionary *query = [@{ @"part": @"snippet,contentDetails", @"playlistId": @"LL", @"maxResults": @"50" } mutableCopy];
    if (pageToken.length) query[@"pageToken"] = pageToken;
    return [self api:@"GET" path:@"playlistItems" query:query body:nil completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        for (id item in TBArr(json[@"items"])) {
            NSDictionary *snippet = TBDict(TBDict(item)[@"snippet"]);
            NSString *videoId = TBStr(TBDict(snippet[@"resourceId"])[@"videoId"]) ?: TBStr(TBDict(TBDict(item)[@"contentDetails"])[@"videoId"]);
            if (videoId.length != 11) continue;
            TBVideo *v = [TBVideo videoWithId:videoId];
            v.title = TBStr(snippet[@"title"]);
            if ([v.title isEqualToString:@"Private video"] || [v.title isEqualToString:@"Deleted video"]) continue;
            v.channelName = TBStr(snippet[@"videoOwnerChannelTitle"]);
            v.channelId = TBStr(snippet[@"videoOwnerChannelId"]);
            v.thumbnailURL = TBAPIThumbnail(TBDict(snippet[@"thumbnails"]));
            v.publishedAt = TBDateFromISO(TBStr(TBDict(TBDict(item)[@"contentDetails"])[@"videoPublishedAt"]) ?: TBStr(snippet[@"publishedAt"]));
            [videos addObject:v];
        }
        completion(videos, TBStr(json[@"nextPageToken"]), nil);
    }];
}

- (TBHTTPTask *)playlistsPage:(NSString *)pageToken completion:(TBItemsCompletion)completion
{
    NSMutableDictionary *query = [@{ @"part": @"snippet,contentDetails", @"mine": @"true", @"maxResults": @"50" } mutableCopy];
    if (pageToken.length) query[@"pageToken"] = pageToken;
    return [self api:@"GET" path:@"playlists" query:query body:nil completion:^(NSDictionary *json, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSMutableArray *playlists = [NSMutableArray array];
        for (id item in TBArr(json[@"items"])) {
            NSDictionary *d = TBDict(item), *snippet = TBDict(d[@"snippet"]);
            TBPlaylist *p = [[TBPlaylist alloc] init];
            p.playlistId = TBStr(d[@"id"]);
            if (!p.playlistId.length) continue;
            p.title = TBStr(snippet[@"title"]);
            p.descriptionText = TBStr(snippet[@"description"]);
            p.thumbnailURL = TBAPIThumbnail(TBDict(snippet[@"thumbnails"]));
            p.ownerName = TBStr(snippet[@"channelTitle"]);
            p.ownerId = TBStr(snippet[@"channelId"]);
            NSInteger count = TBInt(TBDict(d[@"contentDetails"])[@"itemCount"]);
            p.videoCountText = [NSString stringWithFormat:L(@"%@ videos"), [NSString stringWithFormat:@"%ld", (long)count]];
            [playlists addObject:p];
        }
        completion(playlists, TBStr(json[@"nextPageToken"]), nil);
    }];
}

- (TBHTTPTask *)addVideo:(NSString *)videoId toPlaylist:(NSString *)playlistId completion:(void (^)(NSError *error))completion
{
    id body = @{ @"snippet": @{ @"playlistId": playlistId ?: @"", @"resourceId": @{ @"kind": @"youtube#video", @"videoId": videoId ?: @"" } } };
    return [self api:@"POST" path:@"playlistItems" query:@{ @"part": @"snippet" } body:body completion:^(NSDictionary *json, NSError *error) {
        completion(error);
    }];
}

@end
