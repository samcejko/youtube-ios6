#import "TBPlayback.h"
#import "TBInnertube.h"
#import "TBMediaProxy.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"

// YouTube's adaptive files answer range requests for roughly the first 60 seconds of media when the client has no
// PO token (measured 2026-10: ~3.8% of a 27-minute file for every itag, the whole of a 7-second short). Videos up
// to this length are remuxed in full; longer ones would stop after a minute, so they play as the 360p MP4.
static const NSTimeInterval TBRemuxMaxSeconds = 55;

@implementation TBPlaybackSource

- (BOOL)hasHLS
{
    return self.variants.count > 0;
}

- (BOOL)isRemuxed
{
    return self.variants.count > 0 && [(TBVariant *)self.variants[0] dash] != nil;
}

@end

// The attribute list of an HLS tag: NAME=value,NAME="quoted, value"
static NSDictionary *TBParseAttributes(NSString *list)
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSUInteger i = 0, n = list.length;
    while (i < n) {
        while (i < n && ([list characterAtIndex:i] == ',' || [list characterAtIndex:i] == ' ')) i++;
        NSUInteger nameStart = i;
        while (i < n && [list characterAtIndex:i] != '=' && [list characterAtIndex:i] != ',') i++;
        if (i >= n || [list characterAtIndex:i] != '=') break;
        NSString *name = [[list substringWithRange:NSMakeRange(nameStart, i - nameStart)] uppercaseString];
        i++;
        NSString *value;
        if (i < n && [list characterAtIndex:i] == '"') {
            NSUInteger end = [list rangeOfString:@"\"" options:0 range:NSMakeRange(i + 1, n - i - 1)].location;
            if (end == NSNotFound) end = n;
            value = [list substringWithRange:NSMakeRange(i + 1, end - i - 1)];
            i = MIN(end + 1, n);
        } else {
            NSUInteger end = [list rangeOfString:@"," options:0 range:NSMakeRange(i, n - i)].location;
            if (end == NSNotFound) end = n;
            value = [list substringWithRange:NSMakeRange(i, end - i)];
            i = end;
        }
        if (name.length) result[name] = value;
    }
    return result;
}

@implementation TBPlayback

#pragma mark - Master playlists

+ (NSArray *)variantsFromMaster:(NSString *)text baseURL:(NSURL *)base audioRenditions:(NSArray **)renditions
{
    NSMutableArray *variants = [NSMutableArray array];
    NSMutableArray *audio = [NSMutableArray array];
    NSDictionary *pending = nil;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!line.length) continue;
        if ([line hasPrefix:@"#EXT-X-MEDIA:"]) {
            NSDictionary *a = TBParseAttributes([line substringFromIndex:@"#EXT-X-MEDIA:".length]);
            if ([a[@"TYPE"] isEqualToString:@"AUDIO"] && [a[@"URI"] length]) {
                NSURL *url = [[NSURL URLWithString:a[@"URI"] relativeToURL:base] absoluteURL];
                if (url.host.length) {
                    TBAudioRendition *r = [[TBAudioRendition alloc] init];
                    r.groupId = a[@"GROUP-ID"] ?: @"";
                    r.name = a[@"NAME"] ?: @"Default";
                    r.url = url.absoluteString;
                    [audio addObject:r];
                }
            }
            continue;
        }
        if ([line hasPrefix:@"#EXT-X-STREAM-INF:"]) {
            pending = TBParseAttributes([line substringFromIndex:@"#EXT-X-STREAM-INF:".length]);
            continue;
        }
        if ([line hasPrefix:@"#"]) continue;
        if (!pending) continue;
        NSURL *url = [[NSURL URLWithString:line relativeToURL:base] absoluteURL];
        if (url.host.length) {
            TBVariant *v = [[TBVariant alloc] init];
            v.url = url.absoluteString;
            v.codecs = pending[@"CODECS"] ?: @"";
            v.bandwidth = [pending[@"BANDWIDTH"] integerValue];
            v.frameRate = [pending[@"FRAME-RATE"] doubleValue];
            v.audioGroup = pending[@"AUDIO"];
            NSArray *res = [pending[@"RESOLUTION"] componentsSeparatedByString:@"x"];
            if (res.count == 2) { v.width = [res[0] integerValue]; v.height = [res[1] integerValue]; }
            if (v.frameRate <= 0) v.frameRate = 30;
            if ([v isH264]) [variants addObject:v];   // (VP9 and AV1 renditions mean nothing to this hardware)
        }
        pending = nil;
    }
    // highest first; of two with the same height the one with the better frame rate, then the lower bandwidth
    [variants sortUsingComparator:^NSComparisonResult(TBVariant *a, TBVariant *b) {
        if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
        if (a.frameRate != b.frameRate) return a.frameRate > b.frameRate ? NSOrderedAscending : NSOrderedDescending;
        if (a.bandwidth != b.bandwidth) return a.bandwidth < b.bandwidth ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    // one rendition per height and frame rate
    NSMutableArray *unique = [NSMutableArray array];
    for (TBVariant *v in variants) {
        TBVariant *last = unique.lastObject;
        if (last && last.height == v.height && fabs(last.frameRate - v.frameRate) < 1) continue;
        [unique addObject:v];
    }
    if (renditions) *renditions = audio;
    return unique;
}

+ (BOOL)deviceCanPlay:(TBVariant *)variant
{
    BOOL old = [TBUtils deviceIsOldGeneration];
    NSInteger height = [variant qualityLines];   // (an upright 720x1280 short takes the decoder what a 1280x720 picture does)
    double fps = variant.frameRate > 0 ? variant.frameRate : 30;
    if (old) return height <= 720 && (height < 720 || fps <= 30.5);
    // A5 and A6: H.264 High Profile up to level 4.1, 1080p30. 1080p60 (level 4.2) is beyond them; 720p60 fits.
    if (height > 1080) return NO;
    if (height >= 1080 && fps > 30.5) return NO;
    return YES;
}

+ (TBHTTPTask *)fetchMaster:(NSString *)url client:(TBClient)client completion:(void (^)(NSArray *variants, NSArray *audio, NSError *error))completion
{
    NSDictionary *headers = @{ @"Accept": @"application/vnd.apple.mpegurl, application/x-mpegURL, */*", @"User-Agent": [TBInnertube userAgentForClient:client] };
    return [TBHTTP get:url headers:headers completion:^(NSInteger status, NSData *body, NSDictionary *responseHeaders, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        if (status != 200) { completion(nil, nil, TBMakeError(TBErrorAPI, [NSString stringWithFormat:L(@"The stream list could not be loaded (HTTP %ld)."), (long)status])); return; }
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] ?: @"";
        NSArray *audio = nil;
        NSArray *variants = [self variantsFromMaster:text baseURL:[NSURL URLWithString:url] audioRenditions:&audio];
        NSMutableArray *playable = [NSMutableArray array];
        for (TBVariant *v in variants) if ([self deviceCanPlay:v]) [playable addObject:v];
        if (!playable.count && variants.count) [playable addObject:variants.lastObject];   // (better than nothing: the smallest)
        completion(playable, audio, nil);
    }];
}

#pragma mark - Sources

+ (NSError *)errorForInfo:(TBPlayerInfo *)info
{
    NSString *status = info.status ?: @"";
    if ([status isEqualToString:@"LOGIN_REQUIRED"]) return TBMakeError(TBErrorAuth, L(@"This video asks for a signed-in viewer (age restriction), which the app cannot do."));
    if ([status isEqualToString:@"LIVE_STREAM_OFFLINE"]) return TBMakeError(TBErrorOffline, info.statusReason.length ? info.statusReason : L(@"This live stream has not started yet."));
    if (info.statusReason.length) return TBMakeError(TBErrorRestricted, info.statusReason);
    return TBMakeError(TBErrorAPI, L(@"This video cannot be played."));
}

+ (TBHTTPTask *)sourceForVideo:(NSString *)videoId preferProgressive:(BOOL)preferProgressive completion:(void (^)(TBPlaybackSource *source, NSError *error))completion
{
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    __block TBHTTPTask *inner = nil;
    outer.cancelBlock = ^{ [inner cancel]; };
    TBPlaybackSource *source = [[TBPlaybackSource alloc] init];

    // step 3: the master playlist of whatever client gave one
    void (^finishWithHLS)(NSString *, TBClient) = ^(NSString *hls, TBClient client) {
        inner = [self fetchMaster:hls client:client completion:^(NSArray *variants, NSArray *audio, NSError *error) {
            if (outer.isCancelled) return;
            if (error || !variants.count) {
                if (source.progressiveURL.length) { completion(source, nil); return; }   // (the MP4 will do)
                completion(nil, error ?: TBMakeError(TBErrorBadResponse, L(@"The stream list could not be read.")));
                return;
            }
            source.variants = variants;
            source.audioRenditions = audio;
            completion(source, nil);
        }];
    };

    // step 2: the Android client (live streams get their HLS here, everything gets a progressive MP4)
    void (^askAndroid)(void) = ^{
        inner = [TBInnertube player:videoId client:TBClientAndroid completion:^(TBPlayerInfo *info, NSError *error) {
            if (outer.isCancelled) return;
            if (error && !source.info) { completion(nil, error); return; }
            if (info && (!source.info || ![source.info isPlayable])) source.info = info;
            if (info.progressiveURL.length && !source.progressiveURL.length) {
                source.progressiveURL = info.progressiveURL;
                source.progressiveHeight = info.progressiveHeight;
            }
            if (info.isLive) source.isLive = YES;
            if (!preferProgressive && info.hlsManifestURL.length && !source.variants.count) { finishWithHLS(info.hlsManifestURL, TBClientAndroid); return; }
            if (source.progressiveURL.length) { completion(source, nil); return; }
            completion(nil, [self errorForInfo:source.info ?: info]);
        }];
    };

    // step 1: the iOS client (videos get their HLS here; most of them only the adaptive MP4 files, which the proxy
    // can remux into the same kind of stream)
    inner = [TBInnertube player:videoId client:TBClientIOS completion:^(TBPlayerInfo *info, NSError *error) {
        if (outer.isCancelled) return;
        if (error) { completion(nil, error); return; }
        source.info = info;
        source.isLive = info.isLive;
        if (info.progressiveURL.length) { source.progressiveURL = info.progressiveURL; source.progressiveHeight = info.progressiveHeight; }
        if (![info.status isEqualToString:@"OK"]) { askAndroid(); return; }   // (the other client may be luckier)
        if (info.isLive || preferProgressive) { askAndroid(); return; }
        if (info.hlsManifestURL.length) { finishWithHLS(info.hlsManifestURL, TBClientIOS); return; }
        // (without a PO token YouTube serves only the first minute or so of an adaptive file: the remux is for
        // shorts and clips; longer videos get the plain MP4 - see TBRemuxMaxSeconds)
        NSArray *variants = info.lengthSeconds > 0 && info.lengthSeconds <= TBRemuxMaxSeconds ? [self remuxVariantsForInfo:info] : @[];
        if (variants.count) {
            source.variants = variants;
            TBAudioRendition *sound = [[TBAudioRendition alloc] init];
            sound.groupId = @"dash";
            sound.name = info.dashAudio.audioTrackName.length ? info.dashAudio.audioTrackName : @"Default";
            sound.url = info.dashAudio.url;
            sound.dash = info.dashAudio;
            source.audioRenditions = @[ sound ];
            completion(source, nil);
            return;
        }
        askAndroid();
    }];
    return outer;
}

// The adaptive MP4 files as renditions (the proxy converts them), the device's limits applied, highest first
+ (NSArray *)remuxVariantsForInfo:(TBPlayerInfo *)info
{
    if (!info.dashVideo.count || !info.dashAudio) return @[];
    NSMutableArray *variants = [NSMutableArray array];
    for (TBDashFormat *d in info.dashVideo) {
        TBVariant *v = [[TBVariant alloc] init];
        v.url = d.url;
        v.width = d.width;
        v.height = d.height;
        v.frameRate = d.frameRate > 0 ? d.frameRate : 30;
        v.bandwidth = d.bitrate + info.dashAudio.bitrate;
        v.codecs = [NSString stringWithFormat:@"%@,%@", d.codecs ?: @"avc1.4d401f", info.dashAudio.codecs ?: @"mp4a.40.2"];
        v.audioGroup = @"dash";
        v.dash = d;
        if (![self deviceCanPlay:v]) continue;
        TBVariant *last = variants.lastObject;
        if (last && [last qualityLines] == [v qualityLines] && fabs(last.frameRate - v.frameRate) < 1) continue;   // (one per size and frame rate)
        [variants addObject:v];
    }
    return variants;
}

#pragma mark - Player URLs

+ (TBVariant *)variantFrom:(NSArray *)variants forQuality:(NSString *)quality
{
    if (!variants.count || !quality.length || [quality isEqualToString:TBQualityAuto]) return nil;
    NSInteger wanted = [quality integerValue];
    if (wanted <= 0) return nil;
    for (TBVariant *v in variants) if ([v qualityLines] <= wanted) return v;   // (highest first)
    return variants.lastObject;
}

+ (NSString *)masterPlaylistForVariants:(NSArray *)variants audio:(NSArray *)audio startingWith:(TBVariant *)first
{
    TBMediaProxy *proxy = [TBMediaProxy shared];
    NSMutableArray *ordered = [NSMutableArray array];
    if (first && [variants containsObject:first]) [ordered addObject:first];
    for (TBVariant *v in variants) if (![ordered containsObject:v]) [ordered addObject:v];
    NSMutableString *text = [NSMutableString stringWithString:@"#EXTM3U\n#EXT-X-VERSION:4\n"];
    NSMutableSet *groupsUsed = [NSMutableSet set];
    for (TBVariant *v in ordered) if (v.audioGroup.length) [groupsUsed addObject:v.audioGroup];
    for (TBAudioRendition *r in audio) {
        if (![groupsUsed containsObject:r.groupId]) continue;
        NSString *proxied = r.dash ? [proxy proxyURLForDashFormat:r.dash] : [proxy proxyURLForURL:[NSURL URLWithString:r.url]];
        if (!proxied) continue;
        [text appendFormat:@"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"%@\",NAME=\"%@\",DEFAULT=YES,AUTOSELECT=YES,URI=\"%@\"\n", r.groupId, r.name ?: @"Default", proxied];
    }
    for (TBVariant *v in ordered) {
        NSString *proxied = v.dash ? [proxy proxyURLForDashFormat:v.dash] : [proxy proxyURLForURL:[NSURL URLWithString:v.url]];
        if (!proxied) continue;
        [text appendFormat:@"#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=%ld", (long)MAX(v.bandwidth, (NSInteger)100000)];
        if (v.width > 0 && v.height > 0) [text appendFormat:@",RESOLUTION=%ldx%ld", (long)v.width, (long)v.height];
        if (v.codecs.length) [text appendFormat:@",CODECS=\"%@\"", v.codecs];
        if (v.audioGroup.length) [text appendFormat:@",AUDIO=\"%@\"", v.audioGroup];
        [text appendFormat:@"\n%@\n", proxied];
    }
    return text;
}

+ (NSURL *)playerURLForSource:(TBPlaybackSource *)source quality:(NSString *)quality chosen:(TBVariant **)chosen title:(NSString **)title
{
    TBMediaProxy *proxy = [TBMediaProxy shared];
    [proxy ensureRunning];
    [proxy resetPlaybackState];
    if (chosen) *chosen = nil;
    if (source.variants.count) {
        TBVariant *v = [self variantFrom:source.variants forQuality:quality];
        NSString *master;
        if (v) {
            // one rendition only (the sound rendition still has to come along)
            master = [self masterPlaylistForVariants:@[ v ] audio:source.audioRenditions startingWith:v];
            if (chosen) *chosen = v;
            if (title) *title = [v title];
        } else {
            // "Auto": start on the highest the device allows and let the player drop if the connection cannot keep up.
            // (iOS 6's adaptive switching barely climbs once it starts low, so it must begin high - starting at 480
            // left every video stuck at 480p.) 1080p30 on the iPad 2 is heavy, so Auto tops out at 720p; the ladder
            // still carries 1080p for the quality menu.
            TBVariant *start = [self variantFrom:source.variants forQuality:@"720"] ?: source.variants.firstObject;
            master = [self masterPlaylistForVariants:source.variants audio:source.audioRenditions startingWith:start];
            if (title) *title = L(@"Auto");
        }
        NSString *url = [proxy proxyURLForPlaylistText:master];
        return url ? [NSURL URLWithString:url] : nil;
    }
    if (source.progressiveURL.length) {
        if (title) *title = source.progressiveHeight > 0 ? [NSString stringWithFormat:@"%ldp", (long)source.progressiveHeight] : L(@"Video");
        NSString *url = [proxy proxyURLForURL:[NSURL URLWithString:source.progressiveURL]];
        return url ? [NSURL URLWithString:url] : nil;
    }
    return nil;
}

@end
