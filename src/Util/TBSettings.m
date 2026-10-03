#import "TBSettings.h"
#import "TBCommon.h"

NSString * const TBQualityAuto = @"auto";

#define DEF [NSUserDefaults standardUserDefaults]

@implementation TBSettings

+ (NSString *)deviceLanguage
{
    NSString *code = [[[NSLocale preferredLanguages] firstObject] componentsSeparatedByString:@"-"].firstObject;
    return code.length ? code : @"en";
}

+ (NSString *)deviceRegion
{
    NSString *region = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    return region.length ? [region uppercaseString] : @"US";
}

+ (void)registerDefaults
{
    [DEF registerDefaults:@{
        @"darkTheme": @NO,
        @"preferredQuality": TBQualityAuto,
        @"backgroundAudio": @YES,
        @"keepScreenOn": @YES,
        @"autoplayNext": @NO,
        @"progressiveOnly": @NO,
        @"sponsorBlock": @YES,
        @"sponsorBlockCategories": @[ @"sponsor", @"selfpromo", @"interaction", @"music_offtopic" ],   // (what the SponsorBlock extension skips by itself)
        @"captionsEnabled": @NO,
        @"captionsLanguage": @"",
        @"contentLanguage": [self deviceLanguage],
        @"contentRegion": [self deviceRegion],
        @"keepHistory": @YES,
        @"showDislikes": @YES,
        @"verifyTLS": @YES,
    }];
}

+ (void)save
{
    [DEF synchronize];
}

+ (void)notify
{
    TBMain(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:TBSettingsDidChangeNotification object:nil];
    });
}

#pragma mark - Appearance

+ (BOOL)darkTheme { return [DEF boolForKey:@"darkTheme"]; }
+ (void)setDarkTheme:(BOOL)value { [DEF setBool:value forKey:@"darkTheme"]; }

#pragma mark - Playback

+ (NSString *)preferredQuality { return [DEF stringForKey:@"preferredQuality"] ?: TBQualityAuto; }
+ (void)setPreferredQuality:(NSString *)value { [DEF setObject:value ?: TBQualityAuto forKey:@"preferredQuality"]; [self notify]; }

+ (BOOL)backgroundAudio { return [DEF boolForKey:@"backgroundAudio"]; }
+ (void)setBackgroundAudio:(BOOL)value { [DEF setBool:value forKey:@"backgroundAudio"]; [self notify]; }

+ (BOOL)keepScreenOn { return [DEF boolForKey:@"keepScreenOn"]; }
+ (void)setKeepScreenOn:(BOOL)value { [DEF setBool:value forKey:@"keepScreenOn"]; [self notify]; }

+ (BOOL)autoplayNext { return [DEF boolForKey:@"autoplayNext"]; }
+ (void)setAutoplayNext:(BOOL)value { [DEF setBool:value forKey:@"autoplayNext"]; [self notify]; }

+ (BOOL)progressiveOnly { return [DEF boolForKey:@"progressiveOnly"]; }
+ (void)setProgressiveOnly:(BOOL)value { [DEF setBool:value forKey:@"progressiveOnly"]; [self notify]; }

#pragma mark - SponsorBlock

+ (BOOL)sponsorBlock { return [DEF boolForKey:@"sponsorBlock"]; }
+ (void)setSponsorBlock:(BOOL)value { [DEF setBool:value forKey:@"sponsorBlock"]; [self notify]; }

+ (NSArray *)sponsorBlockCategories
{
    if (![self sponsorBlock]) return @[];
    return [DEF arrayForKey:@"sponsorBlockCategories"] ?: @[];
}

+ (void)setSponsorBlockCategories:(NSArray *)value { [DEF setObject:value ?: @[] forKey:@"sponsorBlockCategories"]; [self notify]; }

#pragma mark - Captions

+ (BOOL)captionsEnabled { return [DEF boolForKey:@"captionsEnabled"]; }
+ (void)setCaptionsEnabled:(BOOL)value { [DEF setBool:value forKey:@"captionsEnabled"]; [self notify]; }

+ (NSString *)captionsLanguage { return [DEF stringForKey:@"captionsLanguage"] ?: @""; }
+ (void)setCaptionsLanguage:(NSString *)value { [DEF setObject:value ?: @"" forKey:@"captionsLanguage"]; [self notify]; }

#pragma mark - Content

+ (NSString *)contentLanguage { return [DEF stringForKey:@"contentLanguage"] ?: [self deviceLanguage]; }
+ (void)setContentLanguage:(NSString *)value { [DEF setObject:value ?: [self deviceLanguage] forKey:@"contentLanguage"]; [self notify]; }

+ (NSString *)contentRegion { return [DEF stringForKey:@"contentRegion"] ?: [self deviceRegion]; }
+ (void)setContentRegion:(NSString *)value { [DEF setObject:value ?: [self deviceRegion] forKey:@"contentRegion"]; [self notify]; }

+ (BOOL)keepHistory { return [DEF boolForKey:@"keepHistory"]; }
+ (void)setKeepHistory:(BOOL)value { [DEF setBool:value forKey:@"keepHistory"]; [self notify]; }

+ (BOOL)showDislikes { return [DEF boolForKey:@"showDislikes"]; }
+ (void)setShowDislikes:(BOOL)value { [DEF setBool:value forKey:@"showDislikes"]; [self notify]; }

#pragma mark - Network

+ (BOOL)verifyTLS { return [DEF boolForKey:@"verifyTLS"]; }
+ (void)setVerifyTLS:(BOOL)value { [DEF setBool:value forKey:@"verifyTLS"]; }

#pragma mark - Resume positions

+ (NSTimeInterval)resumePositionForVideo:(NSString *)videoId
{
    if (!videoId.length) return 0;
    NSDictionary *all = [DEF dictionaryForKey:@"resumePositions"];
    return TBDbl(all[videoId]);
}

+ (void)setResumePosition:(NSTimeInterval)seconds forVideo:(NSString *)videoId
{
    if (!videoId.length) return;
    NSMutableDictionary *all = [[DEF dictionaryForKey:@"resumePositions"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *order = [[DEF arrayForKey:@"resumeOrder"] mutableCopy] ?: [NSMutableArray array];
    [order removeObject:videoId];
    if (seconds > 5) {
        all[videoId] = @(floor(seconds));
        [order addObject:videoId];
    } else {
        [all removeObjectForKey:videoId];
    }
    while (order.count > 300) {
        [all removeObjectForKey:order[0]];
        [order removeObjectAtIndex:0];
    }
    [DEF setObject:all forKey:@"resumePositions"];
    [DEF setObject:order forKey:@"resumeOrder"];
}

#pragma mark - Search history

+ (NSArray *)recentSearches
{
    return [DEF arrayForKey:@"recentSearches"] ?: @[];
}

+ (void)addRecentSearch:(NSString *)query
{
    NSString *q = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!q.length) return;
    NSMutableArray *list = [[self recentSearches] mutableCopy];
    for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
        if ([list[(NSUInteger)i] caseInsensitiveCompare:q] == NSOrderedSame) [list removeObjectAtIndex:(NSUInteger)i];
    }
    [list insertObject:q atIndex:0];
    while (list.count > 15) [list removeLastObject];
    [DEF setObject:list forKey:@"recentSearches"];
}

+ (void)clearRecentSearches
{
    [DEF removeObjectForKey:@"recentSearches"];
}

@end
