#import "TBInnertube.h"
#import "TBAccount.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"

NSString * const TBSearchFilterVideos    = @"EgIQAQ%3D%3D";
NSString * const TBSearchFilterChannels  = @"EgIQAg%3D%3D";
NSString * const TBSearchFilterPlaylists = @"EgIQAw%3D%3D";
NSString * const TBSearchFilterLive      = @"EgJAAQ%3D%3D";

NSString * const TBBrowseMusic  = @"UC-9-kyTW8ZkZNDHQJ6FgpwQ";
NSString * const TBBrowseGaming = @"UCOpNcN46UbXVtpKMrmU4Abg";
NSString * const TBBrowseNews   = @"UCYfdidRxbB8Qhf0Nx7ioOYw";
NSString * const TBBrowseSports = @"UCEgdi0XIXXZ-qJOFPf4JSKw";
NSString * const TBBrowseLive   = @"UC4R8DWoMoI7CAwX8_LjQHig";

static NSString * const TBInnertubeBase = @"https://www.youtube.com/youtubei/v1/";

// (the versions the clients had in spring 2025; YouTube keeps serving older versions for years)
static NSString * const TBWebVersion     = @"2.20250312.04.00";
static NSString * const TBIOSVersion     = @"20.10.4";
static NSString * const TBAndroidVersion = @"20.10.38";
static NSString * const TBTVVersion      = @"7.20250209.19.00";

#pragma mark - JSON helpers

// The first dictionary under a property of this name, anywhere below `node` (breadth first: the shallowest wins)
static NSDictionary *TBFindFirst(id node, NSString *key)
{
    NSMutableArray *queue = [NSMutableArray arrayWithObject:node ?: [NSNull null]];
    NSUInteger visited = 0;
    while (queue.count && visited < 20000) {
        id current = queue[0];
        [queue removeObjectAtIndex:0];
        visited++;
        if ([current isKindOfClass:[NSDictionary class]]) {
            id direct = current[key];
            if ([direct isKindOfClass:[NSDictionary class]]) return direct;
            for (id value in [current allValues]) {
                if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) [queue addObject:value];
            }
        } else if ([current isKindOfClass:[NSArray class]]) {
            for (id value in current) {
                if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) [queue addObject:value];
            }
        }
    }
    return nil;
}

// Every dictionary under a property of this name, in document order
static void TBFindAll(id node, NSString *key, NSMutableArray *into, NSInteger depth)
{
    if (depth > 80) return;
    if ([node isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in node) {
            id value = node[k];
            if ([k isEqualToString:key] && [value isKindOfClass:[NSDictionary class]]) [into addObject:value];
            TBFindAll(value, key, into, depth + 1);
        }
    } else if ([node isKindOfClass:[NSArray class]]) {
        for (id value in node) TBFindAll(value, key, into, depth + 1);
    }
}

static NSString *TBBrowseIdIn(id node)
{
    // navigationEndpoint / onTap / innertubeCommand -> browseEndpoint.browseId
    NSDictionary *endpoint = TBFindFirst(node, @"browseEndpoint");
    return TBStr(endpoint[@"browseId"]);
}

static NSString *TBVideoIdIn(id node)
{
    NSDictionary *watch = TBFindFirst(node, @"watchEndpoint") ?: TBFindFirst(node, @"reelWatchEndpoint");
    return TBStr(watch[@"videoId"]);
}

static NSTimeInterval TBSecondsFromLengthText(NSString *text)
{
    // "1:02:03", "19:00", "0:45"
    if (!text.length) return 0;
    NSArray *parts = [text componentsSeparatedByString:@":"];
    if (parts.count < 2 || parts.count > 3) return 0;
    NSTimeInterval seconds = 0;
    for (NSString *p in parts) {
        NSString *digits = [p stringByTrimmingCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        if (!digits.length) return 0;
        seconds = seconds * 60 + [digits integerValue];
    }
    return seconds;
}

#pragma mark - Item parsers

// YouTube video ids are 11 characters; anything else is some other kind of item
static BOOL TBLooksLikeVideoId(NSString *s)
{
    return s.length == 11;
}

static TBVideo *TBVideoFromRenderer(NSDictionary *r)
{
    NSString *videoId = TBStr(r[@"videoId"]);
    if (!TBLooksLikeVideoId(videoId)) return nil;
    TBVideo *v = [TBVideo videoWithId:videoId];
    v.title = TBText(r[@"title"]) ?: TBText(r[@"headline"]);
    v.thumbnailURL = TBThumbnailURL(r[@"thumbnail"]);
    v.lengthText = TBText(r[@"lengthText"]);
    if (!v.lengthText.length) {
        NSInteger secs = TBInt(r[@"lengthSeconds"]);
        if (secs > 0) v.lengthText = [TBUtils formatDuration:secs];
    }
    v.lengthSeconds = TBInt(r[@"lengthSeconds"]) > 0 ? TBInt(r[@"lengthSeconds"]) : TBSecondsFromLengthText(v.lengthText);
    v.viewsText = TBText(r[@"shortViewCountText"]) ?: TBText(r[@"viewCountText"]);
    v.viewCount = TBNumberFromText(TBText(r[@"viewCountText"]) ?: v.viewsText);
    v.publishedText = TBText(r[@"publishedTimeText"]);
    NSDictionary *owner = TBDict(r[@"ownerText"]) ?: (TBDict(r[@"shortBylineText"]) ?: TBDict(r[@"longBylineText"]));
    v.channelName = TBText(owner);
    v.channelId = TBBrowseIdIn(owner);
    v.channelAvatarURL = TBThumbnailURL(TBFindFirst(r[@"channelThumbnailSupportedRenderers"], @"thumbnail") ?: r[@"channelThumbnail"]);
    v.descriptionSnippet = TBText(r[@"descriptionSnippet"]);
    if (!v.descriptionSnippet.length) {
        NSArray *snippets = TBArr(r[@"detailedMetadataSnippets"]);
        if (snippets.count) v.descriptionSnippet = TBText(TBDict(snippets[0])[@"snippetText"]);
    }
    // "videoInfo" of playlist rows: "1.2M views · 3 years ago"
    if (!v.viewsText.length && r[@"videoInfo"]) {
        NSArray *runs = TBArr(TBDict(r[@"videoInfo"])[@"runs"]);
        NSMutableArray *texts = [NSMutableArray array];
        for (id run in runs) { NSString *t = [TBStr(TBDict(run)[@"text"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]; if (t.length && ![t isEqualToString:@"·"]) [texts addObject:t]; }
        if (texts.count) v.viewsText = texts[0];
        if (texts.count > 1) v.publishedText = texts[1];
    }
    for (id b in TBArr(r[@"badges"])) {
        NSString *style = TBStr(TBDict(TBDict(b)[@"metadataBadgeRenderer"])[@"style"]);
        NSString *label = TBStr(TBDict(TBDict(b)[@"metadataBadgeRenderer"])[@"label"]);
        if ([style rangeOfString:@"LIVE"].location != NSNotFound || [label isEqualToString:@"LIVE"]) v.isLive = YES;
    }
    for (id o in TBArr(r[@"thumbnailOverlays"])) {
        NSDictionary *status = TBDict(TBDict(o)[@"thumbnailOverlayTimeStatusRenderer"]);
        NSString *style = TBStr(status[@"style"]);
        if ([style isEqualToString:@"LIVE"]) v.isLive = YES;
        else if ([style isEqualToString:@"UPCOMING"]) v.isUpcoming = YES;
        else if ([style isEqualToString:@"SHORTS"]) v.isShort = YES;
    }
    if (v.isLive) { v.lengthText = nil; v.lengthSeconds = 0; }
    return v;
}

static TBVideo *TBVideoFromLockup(NSDictionary *lockup)
{
    TBVideo *v = [TBVideo videoWithId:TBStr(lockup[@"contentId"]) ?: TBVideoIdIn(lockup[@"rendererContext"])];
    if (!TBLooksLikeVideoId(v.videoId)) return nil;
    NSDictionary *meta = TBDict(TBDict(lockup[@"metadata"])[@"lockupMetadataViewModel"]);
    v.title = TBText(meta[@"title"]);
    NSDictionary *image = TBDict(lockup[@"contentImage"]);
    v.thumbnailURL = TBThumbnailURL(TBDict(image[@"thumbnailViewModel"]) ?: image);
    // badges over the picture: the length, or LIVE
    NSMutableArray *badges = [NSMutableArray array];
    TBFindAll(image, @"thumbnailBadgeViewModel", badges, 0);
    for (NSDictionary *badge in badges) {
        NSString *text = TBText(badge[@"text"]);
        if (!text.length) continue;
        if ([text isEqualToString:@"LIVE"] || [TBStr(badge[@"badgeStyle"]) rangeOfString:@"LIVE"].location != NSNotFound) { v.isLive = YES; continue; }
        if ([text rangeOfString:@":"].location != NSNotFound && !v.lengthText) { v.lengthText = text; v.lengthSeconds = TBSecondsFromLengthText(text); }
    }
    // metadata rows: [channel] [views · age]
    NSArray *rows = TBArr(TBDict(TBDict(meta[@"metadata"])[@"contentMetadataViewModel"])[@"metadataRows"]);
    NSMutableArray *texts = [NSMutableArray array];
    NSInteger rowIndex = 0;
    for (id row in rows) {
        for (id part in TBArr(TBDict(row)[@"metadataParts"])) {
            NSDictionary *p = TBDict(part);
            NSString *text = TBText(p[@"text"]);
            if (!text.length) continue;
            if (rowIndex == 0 && !v.channelName.length) {
                v.channelName = text;
                v.channelId = TBBrowseIdIn(p);
            } else {
                [texts addObject:text];
            }
        }
        rowIndex++;
    }
    for (NSString *t in texts) {
        if ([t rangeOfString:@"watching" options:NSCaseInsensitiveSearch].location != NSNotFound || [t rangeOfString:@"sleduj" options:NSCaseInsensitiveSearch].location != NSNotFound) { v.viewsText = t; v.isLive = YES; }
        else if (!v.viewsText.length && ([t rangeOfString:@"view" options:NSCaseInsensitiveSearch].location != NSNotFound || [t rangeOfString:@"zhlédnut" options:NSCaseInsensitiveSearch].location != NSNotFound)) v.viewsText = t;
        else if (!v.publishedText.length) v.publishedText = t;
    }
    v.viewCount = TBNumberFromText(v.viewsText);
    NSDictionary *avatar = TBFindFirst(meta[@"image"], @"avatarViewModel");
    v.channelAvatarURL = TBThumbnailURL(avatar[@"image"]);
    if (!v.channelId.length) v.channelId = TBBrowseIdIn(meta[@"image"]);
    return v;
}

static TBPlaylist *TBPlaylistFromLockup(NSDictionary *lockup)
{
    TBPlaylist *p = [[TBPlaylist alloc] init];
    NSString *contentId = TBStr(lockup[@"contentId"]);
    if ([contentId hasPrefix:@"VL"]) contentId = [contentId substringFromIndex:2];
    p.playlistId = contentId;
    if (!p.playlistId.length) return nil;
    NSDictionary *meta = TBDict(TBDict(lockup[@"metadata"])[@"lockupMetadataViewModel"]);
    p.title = TBText(meta[@"title"]);
    p.thumbnailURL = TBThumbnailURL(lockup[@"contentImage"]);
    NSMutableArray *badges = [NSMutableArray array];
    TBFindAll(lockup[@"contentImage"], @"thumbnailBadgeViewModel", badges, 0);
    for (NSDictionary *badge in badges) { NSString *t = TBText(badge[@"text"]); if (t.length) { p.videoCountText = t; break; } }
    NSArray *rows = TBArr(TBDict(TBDict(meta[@"metadata"])[@"contentMetadataViewModel"])[@"metadataRows"]);
    for (id row in rows) {
        for (id part in TBArr(TBDict(row)[@"metadataParts"])) {
            NSString *text = TBText(TBDict(part)[@"text"]);
            if (!text.length) continue;
            NSString *owner = TBBrowseIdIn(part);
            if (owner.length && !p.ownerId.length) { p.ownerId = owner; p.ownerName = text; }
            else if (!p.ownerName.length && [text rangeOfString:@"video" options:NSCaseInsensitiveSearch].location == NSNotFound && [text rangeOfString:@"Playlist"].location == NSNotFound) p.ownerName = text;
        }
    }
    return p;
}

static TBChannel *TBChannelFromLockup(NSDictionary *lockup)
{
    TBChannel *c = [[TBChannel alloc] init];
    c.channelId = TBStr(lockup[@"contentId"]) ?: TBBrowseIdIn(lockup[@"rendererContext"]);
    if (![c.channelId hasPrefix:@"UC"]) return nil;
    NSDictionary *meta = TBDict(TBDict(lockup[@"metadata"])[@"lockupMetadataViewModel"]);
    c.title = TBText(meta[@"title"]);
    c.avatarURL = TBThumbnailURL(lockup[@"contentImage"]) ?: TBThumbnailURL(meta[@"image"]);
    NSArray *rows = TBArr(TBDict(TBDict(meta[@"metadata"])[@"contentMetadataViewModel"])[@"metadataRows"]);
    for (id row in rows) {
        for (id part in TBArr(TBDict(row)[@"metadataParts"])) {
            NSString *text = TBText(TBDict(part)[@"text"]);
            if (!text.length) continue;
            if ([text hasPrefix:@"@"]) c.handle = text;
            else if (!c.subscribersText.length && [text rangeOfString:@"subscriber" options:NSCaseInsensitiveSearch].location != NSNotFound) c.subscribersText = text;
            else if (!c.videoCountText.length && [text rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound) c.videoCountText = text;
        }
    }
    return c;
}

static TBVideo *TBShortFromLockup(NSDictionary *lockup)
{
    TBVideo *v = [TBVideo videoWithId:TBVideoIdIn(lockup[@"onTap"])];
    if (!TBLooksLikeVideoId(v.videoId)) return nil;
    NSDictionary *overlay = TBDict(lockup[@"overlayMetadata"]);
    v.title = TBText(overlay[@"primaryText"]) ?: TBStr(lockup[@"accessibilityText"]);
    v.viewsText = TBText(overlay[@"secondaryText"]);
    v.viewCount = TBNumberFromText(v.viewsText);
    v.thumbnailURL = TBThumbnailURL(lockup[@"thumbnailViewModel"]) ?: TBThumbnailURL(lockup[@"thumbnail"]);
    v.isShort = YES;
    return v;
}

static TBChannel *TBChannelFromRenderer(NSDictionary *r)
{
    TBChannel *c = [[TBChannel alloc] init];
    c.channelId = TBStr(r[@"channelId"]) ?: TBBrowseIdIn(r[@"navigationEndpoint"]);
    if (!c.channelId.length) return nil;
    c.title = TBText(r[@"title"]);
    c.avatarURL = TBThumbnailURL(r[@"thumbnail"]);
    c.descriptionText = TBText(r[@"descriptionSnippet"]);
    // (YouTube swaps these two fields on the web: the one with "@" is the handle)
    for (NSString *text in @[ TBText(r[@"subscriberCountText"]) ?: @"", TBText(r[@"videoCountText"]) ?: @"" ]) {
        if (!text.length) continue;
        if ([text hasPrefix:@"@"]) c.handle = text;
        else if ([text rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound && c.subscribersText.length) c.videoCountText = text;
        else c.subscribersText = text;
    }
    return c;
}

static TBPlaylist *TBPlaylistFromRenderer(NSDictionary *r)
{
    TBPlaylist *p = [[TBPlaylist alloc] init];
    p.playlistId = TBStr(r[@"playlistId"]);
    if (!p.playlistId.length) return nil;
    p.title = TBText(r[@"title"]);
    NSArray *thumbs = TBArr(r[@"thumbnails"]);
    p.thumbnailURL = TBThumbnailURL(thumbs.count ? thumbs[0] : r[@"thumbnail"]) ?: TBThumbnailURL(TBFindFirst(r[@"thumbnailRenderer"], @"thumbnail"));
    NSString *count = TBText(r[@"videoCountText"]) ?: (TBText(r[@"videoCountShortText"]) ?: TBStr(r[@"videoCount"]));
    if (count.length && [count rangeOfString:@"video" options:NSCaseInsensitiveSearch].location == NSNotFound) count = [NSString stringWithFormat:L(@"%@ videos"), count];
    p.videoCountText = count;
    NSDictionary *owner = TBDict(r[@"shortBylineText"]) ?: TBDict(r[@"longBylineText"]);
    p.ownerName = TBText(owner);
    p.ownerId = TBBrowseIdIn(owner);
    return p;
}

static TBVideo *TBVideoFromTile(NSDictionary *tile)
{
    NSDictionary *onSelect = TBDict(tile[@"onSelectCommand"]);
    NSDictionary *watch = TBDict(onSelect[@"watchEndpoint"]) ?: TBDict(onSelect[@"watchPlaylistEndpoint"]);
    NSString *videoId = TBStr(watch[@"videoId"]) ?: TBVideoIdIn(tile);
    if (!TBLooksLikeVideoId(videoId)) return nil;
    TBVideo *v = [TBVideo videoWithId:videoId];

    NSDictionary *metadata = TBDict(TBDict(tile[@"metadata"])[@"tileMetadataRenderer"]);
    v.title = TBText(metadata[@"title"]) ?: TBText(tile[@"title"]);

    v.thumbnailURL = TBThumbnailURL(tile[@"thumbnailRenderer"] ?: tile[@"thumbnail"]);
    if (!v.thumbnailURL.length) {
        NSDictionary *thumbVM = TBFindFirst(tile, @"thumbnailViewModel");
        v.thumbnailURL = TBThumbnailURL(thumbVM);
    }
    if (!v.thumbnailURL.length) {
        v.thumbnailURL = [v thumbnailURLForWidth:480];
    }

    NSDictionary *header = TBDict(TBDict(tile[@"header"])[@"tileHeaderRenderer"]);
    if (header) {
        NSString *dur = TBText(header[@"durationText"]) ?: TBText(header[@"thumbnailOverlays"]);
        if (!dur.length) {
            NSDictionary *status = TBFindFirst(header, @"thumbnailOverlayTimeStatusRenderer");
            dur = TBText(status[@"text"]);
        }
        if (dur.length) {
            v.lengthText = dur;
            v.lengthSeconds = TBSecondsFromLengthText(dur);
        }
    }

    NSArray *lines = TBArr(metadata[@"lines"]);
    if (lines.count > 0) {
        NSDictionary *line0 = TBDict(lines[0]);
        NSDictionary *lr0 = TBDict(line0[@"lineRenderer"]);
        NSArray *items0 = TBArr(lr0[@"items"]);
        if (items0.count > 0) {
            NSDictionary *item0 = TBDict(items0[0]);
            NSDictionary *lineItem0 = TBDict(item0[@"lineItemRenderer"]);
            v.channelName = TBText(lineItem0[@"text"]);
            v.channelId = TBBrowseIdIn(lineItem0);
            if (!v.channelId.length) v.channelId = TBBrowseIdIn(line0);
            if (!v.channelId.length) v.channelId = TBBrowseIdIn(metadata);
            if (!v.channelId.length) v.channelId = TBBrowseIdIn(tile);
        }
    }
    if (!v.channelAvatarURL.length) {
        v.channelAvatarURL = TBThumbnailURL(TBFindFirst(tile, @"channelThumbnail") ?: TBFindFirst(tile, @"avatar"));
    }
    if (lines.count > 1) {
        NSDictionary *line1 = TBDict(lines[1]);
        NSDictionary *lr1 = TBDict(line1[@"lineRenderer"]);
        NSArray *items1 = TBArr(lr1[@"items"]);
        for (id it in items1) {
            NSDictionary *lineItem = TBDict(TBDict(it)[@"lineItemRenderer"]);
            NSString *t = TBText(lineItem[@"text"]);
            if (!t.length) continue;
            if ([t rangeOfString:@"view" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [t rangeOfString:@"zhlédnutí" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                v.viewsText = t;
            } else if ([t rangeOfString:@":"].location != NSNotFound && !v.lengthText.length) {
                v.lengthText = t;
                v.lengthSeconds = TBSecondsFromLengthText(t);
            } else if (!v.publishedText.length) {
                v.publishedText = t;
            }
        }
    }
    v.viewCount = TBNumberFromText(v.viewsText);
    return v;
}

// Renderers that are items themselves; the walk does not descend into them
static NSSet *TBItemKeys(void)
{
    static NSSet *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[ @"videoRenderer", @"compactVideoRenderer", @"gridVideoRenderer", @"playlistVideoRenderer", @"playlistPanelVideoRenderer",
                                      @"videoWithContextRenderer", @"reelItemRenderer", @"shortsLockupViewModel", @"lockupViewModel", @"tileRenderer",
                                      @"channelRenderer", @"gridChannelRenderer", @"playlistRenderer", @"gridPlaylistRenderer", @"compactPlaylistRenderer",
                                      @"continuationItemRenderer" ]];
    });
    return keys;
}

// Renderers nothing good comes out of (ads, movies to rent, radios); not descended into either
static NSSet *TBSkipKeys(void)
{
    static NSSet *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = [NSSet setWithArray:@[ @"adSlotRenderer", @"promotedSparklesWebRenderer", @"promotedVideoRenderer", @"movieRenderer", @"compactMovieRenderer",
                                      @"radioRenderer", @"compactRadioRenderer", @"showRenderer", @"searchRefinementCardRenderer", @"horizontalCardListRenderer",
                                      @"backgroundPromoRenderer", @"messageRenderer", @"didYouMeanRenderer", @"showingResultsForRenderer", @"infoPanelContainerRenderer",
                                      @"topbar", @"header", @"engagementPanels", @"playerOverlays", @"frameworkUpdates", @"responseContext",
                                      @"menu", @"menuRenderer", @"trackingParams", @"accessibility", @"searchFilterRenderer", @"sortFilterSubMenuRenderer", @"chipCloudRenderer",
                                      @"inlinePlaybackEndpoint", @"richThumbnail", @"channelThumbnailSupportedRenderers" ]];
    });
    return keys;
}

static void TBWalk(id node, NSMutableArray *items, NSMutableArray *continuations, NSInteger depth)
{
    if (depth > 60) return;
    if ([node isKindOfClass:[NSArray class]]) {
        for (id value in node) TBWalk(value, items, continuations, depth + 1);
        return;
    }
    if (![node isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = node;
    for (NSString *key in d) {
        id value = d[key];
        if ([TBSkipKeys() containsObject:key]) continue;
        if ([TBItemKeys() containsObject:key] && [value isKindOfClass:[NSDictionary class]]) {
            NSDictionary *r = value;
            id item = nil;
            if ([key isEqualToString:@"continuationItemRenderer"]) {
                NSString *token = TBStr(TBDict(TBDict(r[@"continuationEndpoint"])[@"continuationCommand"])[@"token"]);
                if (!token.length) token = TBStr(TBDict(r[@"continuationCommand"])[@"token"]);
                if (!token.length) token = TBStr(TBDict(r[@"continuationEndpoint"])[@"token"]);
                if (token.length) [continuations addObject:token];
                continue;
            }
            if ([key isEqualToString:@"lockupViewModel"]) {
                NSString *type = TBStr(r[@"contentType"]) ?: @"";
                if ([type rangeOfString:@"PLAYLIST"].location != NSNotFound || [type rangeOfString:@"PODCAST"].location != NSNotFound || [type rangeOfString:@"ALBUM"].location != NSNotFound) item = TBPlaylistFromLockup(r);
                else if ([type rangeOfString:@"CHANNEL"].location != NSNotFound) item = TBChannelFromLockup(r);
                else item = TBVideoFromLockup(r);
            } else if ([key isEqualToString:@"shortsLockupViewModel"]) {
                item = TBShortFromLockup(r);
            } else if ([key isEqualToString:@"reelItemRenderer"]) {
                TBVideo *v = TBVideoFromRenderer(r);
                v.isShort = YES;
                item = v;
            } else if ([key isEqualToString:@"tileRenderer"]) {
                item = TBVideoFromTile(r);
            } else if ([key isEqualToString:@"videoRenderer"] || [key hasSuffix:@"VideoRenderer"] || [key isEqualToString:@"videoWithContextRenderer"]) {
                // (plain "videoRenderer" - the search results - has a small v, which the suffix test alone missed)
                item = TBVideoFromRenderer(r);
            } else if ([key isEqualToString:@"channelRenderer"] || [key isEqualToString:@"gridChannelRenderer"]) {
                item = TBChannelFromRenderer(r);
            } else {
                item = TBPlaylistFromRenderer(r);
            }
            if (item) [items addObject:item];
            continue;
        }
        if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) TBWalk(value, items, continuations, depth + 1);
    }
}

#pragma mark - Requests

@implementation TBInnertube

+ (NSString *)userAgentForClient:(TBClient)client
{
    switch (client) {
        case TBClientIOS: return [NSString stringWithFormat:@"com.google.ios.youtube/%@ (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)", TBIOSVersion];
        case TBClientAndroid: return [NSString stringWithFormat:@"com.google.android.youtube/%@ (Linux; U; Android 11) gzip", TBAndroidVersion];
        case TBClientTV: return @"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36";
        default: return @"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36";
    }
}

+ (NSDictionary *)contextForClient:(TBClient)client
{
    NSMutableDictionary *c = [NSMutableDictionary dictionary];
    c[@"hl"] = [TBSettings contentLanguage];
    c[@"gl"] = [TBSettings contentRegion];
    switch (client) {
        case TBClientIOS:
            c[@"clientName"] = @"IOS";
            c[@"clientVersion"] = TBIOSVersion;
            c[@"deviceMake"] = @"Apple";
            c[@"deviceModel"] = @"iPhone16,2";
            c[@"osName"] = @"iPhone";
            c[@"osVersion"] = @"18.3.2.22D82";
            break;
        case TBClientAndroid:
            c[@"clientName"] = @"ANDROID";
            c[@"clientVersion"] = TBAndroidVersion;
            c[@"androidSdkVersion"] = @30;
            c[@"osName"] = @"Android";
            c[@"osVersion"] = @"11";
            break;
        case TBClientTV:
            c[@"clientName"] = @"TVHTML5";
            c[@"clientVersion"] = TBTVVersion;
            c[@"platform"] = @"TV";
            c[@"deviceMake"] = @"Samsung";
            c[@"deviceModel"] = @"SmartTV";
            c[@"osName"] = @"Tizen";
            c[@"osVersion"] = @"6.0";
            break;
        default:
            c[@"clientName"] = @"WEB";
            c[@"clientVersion"] = TBWebVersion;
            break;
    }
    return @{ @"client": c };
}

+ (NSString *)clientNumber:(TBClient)client
{
    switch (client) {
        case TBClientIOS: return @"5";
        case TBClientAndroid: return @"3";
        case TBClientTV: return @"85";
        default: return @"1";
    }
}

+ (TBHTTPTask *)call:(NSString *)endpoint body:(NSDictionary *)body client:(TBClient)client
          completion:(void (^)(NSDictionary *response, NSError *error))completion
{
    return [self call:endpoint body:body client:client token:nil completion:completion];
}

+ (TBHTTPTask *)call:(NSString *)endpoint body:(NSDictionary *)body client:(TBClient)client token:(NSString *)token
          completion:(void (^)(NSDictionary *response, NSError *error))completion
{
    NSMutableDictionary *full = [body mutableCopy] ?: [NSMutableDictionary dictionary];
    full[@"context"] = [self contextForClient:client];
    NSString *version = [[self contextForClient:client][@"client"] objectForKey:@"clientVersion"];
    NSMutableDictionary *headers = [@{ @"User-Agent": [self userAgentForClient:client],
                                       @"X-YouTube-Client-Name": [self clientNumber:client],
                                       @"X-YouTube-Client-Version": version,
                                       @"Origin": @"https://www.youtube.com",
                                       @"Accept-Language": [TBSettings contentLanguage] } mutableCopy];
    if (token.length) {
        headers[@"Authorization"] = [NSString stringWithFormat:@"Bearer %@", token];
    }
    NSString *url = [NSString stringWithFormat:@"%@%@?prettyPrint=false", TBInnertubeBase, endpoint];
    return [TBHTTP postJSON:url headers:headers object:full retries:1 completion:^(id json, NSInteger status, NSError *error) {
        NSDictionary *response = TBDict(json);
        if (error && !response) {
            if (status >= 500) error = TBMakeError(TBErrorAPI, L(@"YouTube is not answering right now. Try again in a moment."));
            else if (status == 400 || status == 404) error = TBMakeError(TBErrorAPI, L(@"YouTube did not understand the request (it may have changed its API)."));
            completion(nil, error);
            return;
        }
        NSDictionary *apiError = TBDict(response[@"error"]);
        if (apiError) {
            completion(nil, TBMakeError(TBErrorAPI, TBStr(apiError[@"message"]) ?: L(@"YouTube returned an error.")));
            return;
        }
        completion(response, nil);
    }];
}

+ (NSArray *)itemsInNode:(id)node continuation:(NSString **)continuation
{
    NSMutableArray *items = [NSMutableArray array];
    NSMutableArray *tokens = [NSMutableArray array];
    TBWalk(node, items, tokens, 0);
    if (continuation) *continuation = tokens.lastObject;
    return items;
}

#pragma mark - Search

+ (TBHTTPTask *)search:(NSString *)query filter:(NSString *)filter continuation:(NSString *)continuation completion:(TBItemsCompletion)completion
{
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if (continuation.length) body[@"continuation"] = continuation;
    else {
        body[@"query"] = query ?: @"";
        if (filter.length) body[@"params"] = filter;
    }
    return [self call:@"search" body:body client:TBClientWeb completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, nil, error); return; }
        NSString *next = nil;
        NSArray *items = [self itemsInNode:response continuation:&next];
        // YouTube pushes a shelf of two dozen shorts into the first page; here the videos, channels and playlists
        // come first and a handful of shorts follow (the Shorts tab is the place for them)
        NSMutableArray *regular = [NSMutableArray array], *shorts = [NSMutableArray array];
        for (id item in items) {
            if ([item isKindOfClass:[TBVideo class]] && [(TBVideo *)item isShort]) { if (shorts.count < 6) [shorts addObject:item]; }
            else [regular addObject:item];
        }
        if (regular.count) [regular addObjectsFromArray:shorts]; else regular = shorts;
        TBLog(@"Search '%@': %lu items (%lu shorts)%@", query ?: @"", (unsigned long)regular.count, (unsigned long)shorts.count, next.length ? @", more" : @"");
        completion(regular, next, nil);
    }];
}

+ (TBHTTPTask *)searchSuggestions:(NSString *)query completion:(void (^)(NSArray *suggestions, NSError *error))completion
{
    NSString *url = [NSString stringWithFormat:@"https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&hl=%@&gl=%@&q=%@",
                     [TBSettings contentLanguage], [TBSettings contentRegion], [TBUtils urlEncode:query ?: @""]];
    return [TBHTTP get:url headers:@{ @"User-Agent": [self userAgentForClient:TBClientWeb] } completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (error) { completion(nil, error); return; }
        // window.google.ac.h(["query",[["suggestion",0,[...]],...],{...}])
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] ?: @"";
        NSRange open = [text rangeOfString:@"("];
        NSRange close = [text rangeOfString:@")" options:NSBackwardsSearch];
        NSMutableArray *result = [NSMutableArray array];
        if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
            id json = [TBUtils JSONObjectFromData:[[text substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)] dataUsingEncoding:NSUTF8StringEncoding]];
            NSArray *list = TBArr(TBArr(json).count > 1 ? TBArr(json)[1] : nil);
            for (id entry in list) {
                NSString *s = TBStr(TBArr(entry).count ? TBArr(entry)[0] : entry);
                if (s.length) [result addObject:s];
            }
        }
        completion(result, nil);
    }];
}

#pragma mark - Browse

+ (TBHTTPTask *)browse:(NSString *)browseId params:(NSString *)params continuation:(NSString *)continuation
            completion:(void (^)(NSDictionary *response, NSArray *items, NSString *continuation, NSError *error))completion
{
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    if (continuation.length) body[@"continuation"] = continuation;
    else {
        body[@"browseId"] = browseId ?: @"";
        if (params.length) body[@"params"] = params;
    }
    return [self call:@"browse" body:body client:TBClientWeb completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, nil, nil, error); return; }
        NSString *next = nil;
        id scope = response;
        // a channel page: only the selected tab's content, not the links of the other tabs
        NSArray *tabs = TBArr(TBDict(TBDict(response[@"contents"])[@"twoColumnBrowseResultsRenderer"])[@"tabs"]);
        for (id tab in tabs) {
            NSDictionary *t = TBDict(TBDict(tab)[@"tabRenderer"]);
            if (TBBool(t[@"selected"]) && t[@"content"]) { scope = t[@"content"]; break; }
        }
        if (continuation.length) scope = response[@"onResponseReceivedActions"] ?: (response[@"onResponseReceivedEndpoints"] ?: response);
        NSArray *items = [self itemsInNode:scope continuation:&next];
        completion(response, items, next, nil);
    }];
}

+ (TBHTTPTask *)authenticatedBrowse:(NSString *)browseId params:(NSString *)params continuation:(NSString *)continuation
                         completion:(void (^)(NSDictionary *response, NSArray *items, NSString *continuation, NSError *error))completion
{
    if (![[TBAccount shared] isSignedIn]) {
        return [self browse:browseId params:params continuation:continuation completion:completion];
    }
    return [[TBAccount shared] withAccessToken:^(NSString *token, NSError *authError) {
        if (!token.length) {
            [self browse:browseId params:params continuation:continuation completion:completion];
            return;
        }
        NSMutableDictionary *body = [NSMutableDictionary dictionary];
        if (continuation.length) body[@"continuation"] = continuation;
        else {
            body[@"browseId"] = browseId ?: @"";
            if (params.length) body[@"params"] = params;
        }
        TBClient client = [[TBAccount shared] usesCustomOAuthClient] ? TBClientWeb : TBClientTV;
        [self call:@"browse" body:body client:client token:token completion:^(NSDictionary *response, NSError *error) {
            if (error) { completion(nil, nil, nil, error); return; }
            NSString *next = nil;
            id scope = response;
            NSArray *tabs = TBArr(TBDict(TBDict(response[@"contents"])[@"twoColumnBrowseResultsRenderer"])[@"tabs"]);
            for (id tab in tabs) {
                NSDictionary *t = TBDict(TBDict(tab)[@"tabRenderer"]);
                if (TBBool(t[@"selected"]) && t[@"content"]) { scope = t[@"content"]; break; }
            }
            if (continuation.length) scope = response[@"onResponseReceivedActions"] ?: (response[@"onResponseReceivedEndpoints"] ?: response);
            NSArray *items = [self itemsInNode:scope continuation:&next];
            completion(response, items, next, nil);
        }];
    }];
}

+ (TBChannel *)channelFromBrowseResponse:(NSDictionary *)response
{
    TBChannel *c = [[TBChannel alloc] init];
    NSDictionary *meta = TBDict(TBDict(response[@"metadata"])[@"channelMetadataRenderer"]);
    c.channelId = TBStr(meta[@"externalId"]);
    c.title = TBStr(meta[@"title"]);
    c.descriptionText = TBStr(meta[@"description"]);
    c.avatarURL = TBThumbnailURL(meta[@"avatar"]);
    NSString *vanity = TBStr(meta[@"vanityChannelUrl"]);
    NSRange at = [vanity rangeOfString:@"@"];
    if (at.location != NSNotFound) c.handle = [vanity substringFromIndex:at.location];
    // the header: banner, subscriber count, the handle when the metadata has none
    NSDictionary *header = TBDict(response[@"header"]);
    NSDictionary *old = TBDict(header[@"c4TabbedHeaderRenderer"]);
    if (old) {
        if (!c.channelId.length) c.channelId = TBStr(old[@"channelId"]);
        if (!c.title.length) c.title = TBText(old[@"title"]);
        if (!c.avatarURL.length) c.avatarURL = TBThumbnailURL(old[@"avatar"]);
        c.bannerURL = TBThumbnailURL(old[@"banner"]);
        c.subscribersText = TBText(old[@"subscriberCountText"]);
        c.videoCountText = TBText(old[@"videosCountText"]);
        if (!c.handle.length) c.handle = TBText(old[@"channelHandleText"]);
    }
    NSDictionary *page = TBDict(TBDict(TBDict(header[@"pageHeaderRenderer"])[@"content"])[@"pageHeaderViewModel"]);
    if (page) {
        if (!c.title.length) c.title = TBStr(TBDict(header[@"pageHeaderRenderer"])[@"pageTitle"]);
        if (!c.avatarURL.length) c.avatarURL = TBThumbnailURL(TBFindFirst(page[@"image"], @"avatarViewModel"));
        c.bannerURL = TBThumbnailURL(TBFindFirst(page[@"banner"], @"image")) ?: c.bannerURL;
        NSArray *rows = TBArr(TBDict(TBDict(page[@"metadata"])[@"contentMetadataViewModel"])[@"metadataRows"]);
        for (id row in rows) {
            for (id part in TBArr(TBDict(row)[@"metadataParts"])) {
                NSString *text = TBText(TBDict(part)[@"text"]);
                if (!text.length) continue;
                if ([text hasPrefix:@"@"]) { if (!c.handle.length) c.handle = text; }
                else if ([text rangeOfString:@"subscriber" options:NSCaseInsensitiveSearch].location != NSNotFound || [text rangeOfString:@"odběratel" options:NSCaseInsensitiveSearch].location != NSNotFound) c.subscribersText = text;
                else if ([text rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound) c.videoCountText = text;
            }
        }
        if (!c.descriptionText.length) c.descriptionText = TBText(TBFindFirst(page[@"description"], @"description"));
    }
    // tabs
    NSMutableArray *tabs = [NSMutableArray array];
    for (id tab in TBArr(TBDict(TBDict(response[@"contents"])[@"twoColumnBrowseResultsRenderer"])[@"tabs"])) {
        NSDictionary *t = TBDict(TBDict(tab)[@"tabRenderer"]);
        NSString *title = TBStr(t[@"title"]);
        if (!title.length) continue;
        TBChannelTab *ct = [[TBChannelTab alloc] init];
        ct.title = title;
        ct.params = TBStr(TBDict(TBDict(t[@"endpoint"])[@"browseEndpoint"])[@"params"]);
        ct.selected = TBBool(t[@"selected"]);
        [tabs addObject:ct];
    }
    c.tabs = tabs;
    return c.channelId.length ? c : nil;
}

+ (TBHTTPTask *)channel:(NSString *)channelId params:(NSString *)params
             completion:(void (^)(TBChannel *channel, NSArray *items, NSString *continuation, NSError *error))completion
{
    return [self browse:channelId params:params continuation:nil completion:^(NSDictionary *response, NSArray *items, NSString *continuation, NSError *error) {
        if (error) { completion(nil, nil, nil, error); return; }
        TBChannel *channel = [self channelFromBrowseResponse:response];
        if (!channel) { completion(nil, nil, nil, TBMakeError(TBErrorAPI, L(@"This channel does not exist."))); return; }
        // items of the channel's own tab carry the channel's name when the API left it out
        for (id item in items) {
            if ([item isKindOfClass:[TBVideo class]]) {
                TBVideo *v = item;
                if (!v.channelName.length) { v.channelName = channel.title; v.channelId = channel.channelId; }
                if (!v.channelAvatarURL.length) v.channelAvatarURL = channel.avatarURL;
            }
        }
        completion(channel, items, continuation, nil);
    }];
}

+ (TBHTTPTask *)playlist:(NSString *)playlistId
              completion:(void (^)(TBPlaylist *playlist, NSArray *items, NSString *continuation, NSError *error))completion
{
    NSString *browseId = [playlistId hasPrefix:@"VL"] ? playlistId : [@"VL" stringByAppendingString:playlistId ?: @""];
    return [self browse:browseId params:nil continuation:nil completion:^(NSDictionary *response, NSArray *items, NSString *continuation, NSError *error) {
        if (error) { completion(nil, nil, nil, error); return; }
        TBPlaylist *p = [[TBPlaylist alloc] init];
        p.playlistId = [browseId substringFromIndex:2];
        NSDictionary *meta = TBDict(TBDict(response[@"metadata"])[@"playlistMetadataRenderer"]);
        p.title = TBStr(meta[@"title"]);
        p.descriptionText = TBStr(meta[@"description"]);
        NSDictionary *header = TBDict(TBDict(response[@"header"])[@"playlistHeaderRenderer"]);
        if (header) {
            if (!p.title.length) p.title = TBText(header[@"title"]);
            p.videoCountText = TBText(header[@"numVideosText"]);
            p.ownerName = TBText(header[@"ownerText"]);
            p.ownerId = TBBrowseIdIn(header[@"ownerText"]);
            p.thumbnailURL = TBThumbnailURL(TBFindFirst(header[@"playlistHeaderBanner"], @"thumbnail"));
        } else {
            NSDictionary *page = TBDict(TBDict(TBDict(TBDict(response[@"header"])[@"pageHeaderRenderer"])[@"content"])[@"pageHeaderViewModel"]);
            if (!p.title.length) p.title = TBStr(TBDict(TBDict(response[@"header"])[@"pageHeaderRenderer"])[@"pageTitle"]);
            NSArray *rows = TBArr(TBDict(TBDict(page[@"metadata"])[@"contentMetadataViewModel"])[@"metadataRows"]);
            for (id row in rows) {
                for (id part in TBArr(TBDict(row)[@"metadataParts"])) {
                    NSString *text = TBText(TBDict(part)[@"text"]);
                    NSString *owner = TBBrowseIdIn(part);
                    if (owner.length) { p.ownerId = owner; p.ownerName = text; }
                    else if ([text rangeOfString:@"video" options:NSCaseInsensitiveSearch].location != NSNotFound) p.videoCountText = text;
                }
            }
            p.thumbnailURL = TBThumbnailURL(TBFindFirst(page[@"heroImage"], @"image")) ?: TBThumbnailURL(TBFindFirst(response[@"sidebar"], @"thumbnail"));
        }
        if (!p.thumbnailURL.length) {
            for (id item in items) if ([item isKindOfClass:[TBVideo class]]) { p.thumbnailURL = [(TBVideo *)item thumbnailURLForWidth:480]; break; }
        }
        if (!p.title.length && !items.count) { completion(nil, nil, nil, TBMakeError(TBErrorAPI, L(@"This playlist does not exist or is private."))); return; }
        completion(p, items, continuation, nil);
    }];
}

+ (TBHTTPTask *)shelvesOfPage:(NSString *)browseId completion:(void (^)(NSArray *shelves, NSError *error))completion
{
    return [self browse:browseId params:nil continuation:nil completion:^(NSDictionary *response, NSArray *allItems, NSString *continuation, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSMutableArray *shelves = [NSMutableArray array];
        NSMutableArray *renderers = [NSMutableArray array];
        TBFindAll(response, @"shelfRenderer", renderers, 0);
        TBFindAll(response, @"richShelfRenderer", renderers, 0);
        TBFindAll(response, @"reelShelfRenderer", renderers, 0);
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *r in renderers) {
            NSString *title = TBText(r[@"title"]) ?: TBText(r[@"headerRenderer"]);
            NSArray *items = [self itemsInNode:r[@"content"] ?: (r[@"contents"] ?: r[@"items"]) continuation:NULL];
            NSMutableArray *fresh = [NSMutableArray array];
            for (id item in items) {
                NSString *key = [item isKindOfClass:[TBVideo class]] ? [(TBVideo *)item videoId] : ([item isKindOfClass:[TBPlaylist class]] ? [(TBPlaylist *)item playlistId] : [(TBChannel *)item channelId]);
                if (!key.length || [seen containsObject:key]) continue;
                [seen addObject:key];
                [fresh addObject:item];
            }
            if (!fresh.count) continue;
            TBShelf *shelf = [[TBShelf alloc] init];
            shelf.title = title.length ? title : L(@"Videos");
            shelf.items = fresh;
            NSDictionary *endpoint = TBFindFirst(r[@"endpoint"] ?: r[@"title"], @"browseEndpoint");
            shelf.browseId = TBStr(endpoint[@"browseId"]);
            shelf.params = TBStr(endpoint[@"params"]);
            [shelves addObject:shelf];
        }
        if (!shelves.count && allItems.count) {
            // no shelves, just a grid: one shelf with everything
            NSMutableArray *videos = [NSMutableArray array];
            for (id item in allItems) if ([item isKindOfClass:[TBVideo class]]) [videos addObject:item];
            if (videos.count) {
                TBShelf *shelf = [[TBShelf alloc] init];
                shelf.title = TBStr(TBDict(TBDict(response[@"metadata"])[@"channelMetadataRenderer"])[@"title"]) ?: L(@"Videos");
                shelf.items = videos;
                [shelves addObject:shelf];
            }
        }
        completion(shelves, nil);
    }];
}

+ (TBHTTPTask *)authenticatedShelvesOfPage:(NSString *)browseId completion:(void (^)(NSArray *shelves, NSError *error))completion
{
    if (![[TBAccount shared] isSignedIn]) {
        return [self shelvesOfPage:browseId completion:completion];
    }
    return [self authenticatedBrowse:browseId params:nil continuation:nil completion:^(NSDictionary *response, NSArray *allItems, NSString *continuation, NSError *error) {
        if (error) {
            [self shelvesOfPage:browseId completion:completion];
            return;
        }
        NSMutableArray *shelves = [NSMutableArray array];
        NSMutableArray *renderers = [NSMutableArray array];
        TBFindAll(response, @"shelfRenderer", renderers, 0);
        TBFindAll(response, @"richShelfRenderer", renderers, 0);
        TBFindAll(response, @"reelShelfRenderer", renderers, 0);
        TBFindAll(response, @"horizontalListRenderer", renderers, 0);
        TBFindAll(response, @"itemSectionRenderer", renderers, 0);
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *r in renderers) {
            NSString *title = TBText(r[@"title"]) ?: TBText(r[@"headerRenderer"]);
            if (!title.length) title = TBText(TBDict(r[@"header"])[@"shelfHeaderRenderer"][@"title"]);
            NSArray *items = [self itemsInNode:r[@"content"] ?: (r[@"contents"] ?: r[@"items"]) continuation:NULL];
            NSMutableArray *fresh = [NSMutableArray array];
            for (id item in items) {
                NSString *key = [item isKindOfClass:[TBVideo class]] ? [(TBVideo *)item videoId] : ([item isKindOfClass:[TBPlaylist class]] ? [(TBPlaylist *)item playlistId] : [(TBChannel *)item channelId]);
                if (!key.length || [seen containsObject:key]) continue;
                [seen addObject:key];
                [fresh addObject:item];
            }
            if (!fresh.count) continue;
            TBShelf *shelf = [[TBShelf alloc] init];
            shelf.title = title.length ? title : L(@"Recommended");
            shelf.items = fresh;
            NSDictionary *endpoint = TBFindFirst(r[@"endpoint"] ?: r[@"title"], @"browseEndpoint");
            shelf.browseId = TBStr(endpoint[@"browseId"]);
            shelf.params = TBStr(endpoint[@"params"]);
            [shelves addObject:shelf];
        }
        if (!shelves.count && allItems.count) {
            NSMutableArray *videos = [NSMutableArray array];
            for (id item in allItems) if ([item isKindOfClass:[TBVideo class]]) [videos addObject:item];
            if (videos.count) {
                TBShelf *shelf = [[TBShelf alloc] init];
                shelf.title = TBStr(TBDict(TBDict(response[@"metadata"])[@"channelMetadataRenderer"])[@"title"]) ?: L(@"Recommended");
                shelf.items = videos;
                [shelves addObject:shelf];
            }
        }
        completion(shelves, nil);
    }];
}

+ (TBHTTPTask *)authenticatedGuide:(void (^)(NSDictionary *response, NSArray *channels, NSError *error))completion
{
    if (![[TBAccount shared] isSignedIn]) {
        if (completion) completion(nil, @[], nil);
        return nil;
    }
    return [[TBAccount shared] withAccessToken:^(NSString *token, NSError *authError) {
        if (!token.length) {
            if (completion) completion(nil, @[], authError);
            return;
        }
        TBClient client = [[TBAccount shared] usesCustomOAuthClient] ? TBClientWeb : TBClientTV;
        [self call:@"guide" body:@{} client:client token:token completion:^(NSDictionary *response, NSError *error) {
            if (error) { if (completion) completion(nil, nil, error); return; }
            NSMutableArray *channels = [NSMutableArray array];
            NSMutableArray *entries = [NSMutableArray array];
            TBFindAll(response, @"guideEntryRenderer", entries, 0);
            TBFindAll(response, @"guideItemRenderer", entries, 0);
            TBFindAll(response, @"compactLinkRenderer", entries, 0);
            TBFindAll(response, @"guideAccountRenderer", entries, 0);
            if (!entries.count) {
                TBFindAll(response, @"browseEndpoint", entries, 0);
            }
            NSMutableSet *seen = [NSMutableSet set];
            for (NSDictionary *entry in entries) {
                NSString *browseId = TBBrowseIdIn(entry);
                if (![browseId hasPrefix:@"UC"] || [seen containsObject:browseId]) continue;
                [seen addObject:browseId];
                TBChannel *c = [[TBChannel alloc] init];
                c.channelId = browseId;
                c.title = TBText(entry[@"formattedTitle"]) ?: (TBText(entry[@"title"]) ?: (TBText(entry[@"text"]) ?: TBText(entry[@"accessibility"])));
                if (!c.title.length) c.title = TBText(TBFindFirst(entry, @"text"));
                c.avatarURL = TBThumbnailURL(entry[@"thumbnail"] ?: TBFindFirst(entry, @"thumbnail"));
                [channels addObject:c];
            }
            if (channels.count > 0 || [[TBAccount shared] usesCustomOAuthClient]) {
                TBLog(@"authenticatedGuide: found %lu channels", (unsigned long)channels.count);
                if (completion) completion(response, channels, nil);
                return;
            }
            TBLog(@"authenticatedGuide (TV): 0 channels from guide, trying Web client guide...");
            [self call:@"guide" body:@{} client:TBClientWeb token:token completion:^(NSDictionary *webResp, NSError *webErr) {
                NSMutableArray *webEntries = [NSMutableArray array];
                TBFindAll(webResp, @"guideEntryRenderer", webEntries, 0);
                TBFindAll(webResp, @"guideItemRenderer", webEntries, 0);
                for (NSDictionary *entry in webEntries) {
                    NSString *browseId = TBBrowseIdIn(entry);
                    if (![browseId hasPrefix:@"UC"] || [seen containsObject:browseId]) continue;
                    [seen addObject:browseId];
                    TBChannel *c = [[TBChannel alloc] init];
                    c.channelId = browseId;
                    c.title = TBText(entry[@"formattedTitle"]) ?: (TBText(entry[@"title"]) ?: TBText(entry[@"text"]));
                    c.avatarURL = TBThumbnailURL(entry[@"thumbnail"] ?: TBFindFirst(entry, @"thumbnail"));
                    [channels addObject:c];
                }
                if (channels.count > 0) {
                    TBLog(@"authenticatedGuide (Web client guide): found %lu channels", (unsigned long)channels.count);
                    if (completion) completion(webResp, channels, nil);
                    return;
                }
                TBLog(@"authenticatedGuide (Web guide): 0 channels, trying FEsubscriptions extract...");
                [self authenticatedBrowse:@"FEsubscriptions" params:nil continuation:nil completion:^(NSDictionary *subResp, NSArray *subItems, NSString *subCont, NSError *subErr) {
                    for (id it in subItems) {
                        if ([it isKindOfClass:[TBChannel class]]) {
                            TBChannel *c = (TBChannel *)it;
                            if (c.channelId.length && ![seen containsObject:c.channelId]) {
                                [seen addObject:c.channelId];
                                [channels addObject:c];
                            }
                        } else if ([it isKindOfClass:[TBVideo class]]) {
                            TBVideo *v = (TBVideo *)it;
                            NSString *cid = v.channelId.length ? v.channelId : v.channelName;
                            if (cid.length && ![seen containsObject:cid]) {
                                [seen addObject:cid];
                                TBChannel *c = [[TBChannel alloc] init];
                                c.channelId = v.channelId.length ? v.channelId : [NSString stringWithFormat:@"channel:%@", v.channelName];
                                c.title = v.channelName.length ? v.channelName : @"Channel";
                                c.avatarURL = v.channelAvatarURL;
                                [channels addObject:c];
                            }
                        }
                    }
                    TBLog(@"authenticatedGuide (FEsubscriptions extract): found %lu channels", (unsigned long)channels.count);
                    if (completion) completion(subResp ?: response, channels, subErr ?: error);
                }];
            }];
        }];
    }];
}

+ (TBHTTPTask *)resolveURL:(NSString *)url completion:(void (^)(NSString *channelId, NSString *videoId, NSString *playlistId, NSError *error))completion
{
    return [self call:@"navigation/resolve_url" body:@{ @"url": url ?: @"" } client:TBClientWeb completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, nil, nil, error); return; }
        NSDictionary *endpoint = TBDict(response[@"endpoint"]);
        NSString *channelId = TBStr(TBDict(endpoint[@"browseEndpoint"])[@"browseId"]);
        NSString *videoId = TBStr(TBDict(endpoint[@"watchEndpoint"])[@"videoId"]);
        NSString *playlistId = TBStr(TBDict(endpoint[@"watchEndpoint"])[@"playlistId"]);
        if ([channelId hasPrefix:@"VL"]) { playlistId = [channelId substringFromIndex:2]; channelId = nil; }
        if (!channelId.length && !videoId.length && !playlistId.length) { completion(nil, nil, nil, TBMakeError(TBErrorAPI, L(@"Nothing was found at this address."))); return; }
        completion(channelId, videoId, playlistId, nil);
    }];
}

#pragma mark - Watch page

+ (TBHTTPTask *)watchInfo:(NSString *)videoId completion:(void (^)(TBWatchInfo *info, NSError *error))completion
{
    return [self call:@"next" body:@{ @"videoId": videoId ?: @"" } client:TBClientWeb completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        TBWatchInfo *info = [[TBWatchInfo alloc] init];
        NSDictionary *results = TBDict(TBDict(response[@"contents"])[@"twoColumnWatchNextResults"]);
        NSDictionary *primary = TBFindFirst(results[@"results"], @"videoPrimaryInfoRenderer");
        NSDictionary *secondary = TBFindFirst(results[@"results"], @"videoSecondaryInfoRenderer");
        info.title = TBText(primary[@"title"]);
        NSDictionary *viewCount = TBDict(TBDict(primary[@"viewCount"])[@"videoViewCountRenderer"]);
        info.viewsText = TBText(viewCount[@"viewCount"]) ?: TBText(viewCount[@"shortViewCount"]);
        info.dateText = TBText(primary[@"dateText"]) ?: TBText(primary[@"relativeDateText"]);
        NSDictionary *like = TBFindFirst(primary[@"videoActions"], @"likeButtonViewModel");
        if (like) {
            NSDictionary *inner = TBDict(like[@"likeButtonViewModel"]) ?: like;
            NSDictionary *button = TBFindFirst(inner, @"buttonViewModel");
            info.likesText = TBStr(button[@"title"]);
        }
        if (!info.likesText.length) {
            NSDictionary *toggle = TBFindFirst(primary[@"videoActions"], @"toggleButtonRenderer");
            info.likesText = TBText(TBDict(toggle[@"defaultText"]));
        }
        NSDictionary *owner = TBDict(TBDict(secondary[@"owner"])[@"videoOwnerRenderer"]);
        if (owner) {
            TBChannel *c = [[TBChannel alloc] init];
            c.title = TBText(owner[@"title"]);
            c.channelId = TBBrowseIdIn(owner[@"title"]) ?: TBBrowseIdIn(owner[@"navigationEndpoint"]);
            c.avatarURL = TBThumbnailURL(owner[@"thumbnail"]);
            c.subscribersText = TBText(owner[@"subscriberCountText"]);
            info.channel = c;
        }
        info.descriptionText = TBText(secondary[@"attributedDescription"]) ?: TBText(secondary[@"description"]);
        // comments: the continuation of the comments section, and the count shown at its entry point
        for (id content in TBArr(TBDict(TBDict(results[@"results"])[@"results"])[@"contents"])) {
            NSDictionary *section = TBDict(TBDict(content)[@"itemSectionRenderer"]);
            if (!section) continue;
            NSString *identifier = TBStr(section[@"sectionIdentifier"]);
            if ([identifier isEqualToString:@"comment-item-section"]) {
                NSString *token = nil;
                [self itemsInNode:section continuation:&token];
                info.commentsToken = token;
            } else if ([identifier isEqualToString:@"comments-entry-point"]) {
                NSDictionary *entry = TBFindFirst(section, @"commentsEntryPointHeaderRenderer");
                info.commentCountText = TBText(entry[@"commentCount"]);
            }
        }
        if (!info.commentsToken.length) {
            // the engagement panel carries the same continuation
            for (id panel in TBArr(response[@"engagementPanels"])) {
                NSDictionary *p = TBDict(TBDict(panel)[@"engagementPanelSectionListRenderer"]);
                if ([TBStr(p[@"panelIdentifier"]) isEqualToString:@"engagement-panel-comments-section"]) {
                    NSString *token = nil;
                    [self itemsInNode:p[@"content"] continuation:&token];
                    if (token.length) info.commentsToken = token;
                }
            }
        }
        NSString *relatedNext = nil;
        info.related = [self itemsInNode:results[@"secondaryResults"] continuation:&relatedNext];
        info.relatedContinuation = relatedNext;
        if (!info.title.length && !info.related.count) { completion(nil, TBMakeError(TBErrorAPI, L(@"This video is not available."))); return; }
        completion(info, nil);
    }];
}

+ (TBHTTPTask *)comments:(NSString *)token completion:(void (^)(NSArray *comments, NSString *continuation, NSString *countText, NSError *error))completion
{
    return [self call:@"next" body:@{ @"continuation": token ?: @"" } client:TBClientWeb completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, nil, nil, error); return; }
        // the texts: entity payloads keyed by comment id
        NSMutableDictionary *payloads = [NSMutableDictionary dictionary];
        NSMutableDictionary *toolbars = [NSMutableDictionary dictionary];   // toolbar state key -> state (hearted)
        for (id m in TBArr(TBDict(TBDict(response[@"frameworkUpdates"])[@"entityBatchUpdate"])[@"mutations"])) {
            NSDictionary *payload = TBDict(TBDict(m)[@"payload"]);
            NSDictionary *comment = TBDict(payload[@"commentEntityPayload"]);
            if (comment) {
                NSString *commentId = TBStr(TBDict(comment[@"properties"])[@"commentId"]);
                if (commentId) payloads[commentId] = comment;
            }
            NSDictionary *toolbar = TBDict(payload[@"engagementToolbarStateEntityPayload"]);
            if (toolbar) {
                NSString *key = TBStr(toolbar[@"key"]);
                if (key) toolbars[key] = toolbar;
            }
        }
        // the order: the thread renderers of the continuation items
        NSMutableArray *threads = [NSMutableArray array];
        TBFindAll(response[@"onResponseReceivedEndpoints"] ?: response, @"commentThreadRenderer", threads, 0);
        NSMutableArray *viewModels = [NSMutableArray array];
        if (!threads.count) TBFindAll(response[@"onResponseReceivedEndpoints"] ?: response, @"commentViewModel", viewModels, 0);   // (replies have no thread)
        NSMutableArray *comments = [NSMutableArray array];
        NSArray *sources = threads.count ? threads : viewModels;
        for (NSDictionary *source in sources) {
            NSDictionary *vm = threads.count ? (TBDict(TBDict(source[@"commentViewModel"])[@"commentViewModel"]) ?: TBDict(source[@"commentViewModel"])) : (TBDict(source[@"commentViewModel"]) ?: source);
            NSString *commentId = TBStr(vm[@"commentId"]);
            NSDictionary *payload = payloads[commentId ?: @""];
            if (!payload) continue;
            TBComment *c = [[TBComment alloc] init];
            c.commentId = commentId;
            NSDictionary *props = TBDict(payload[@"properties"]);
            c.text = TBText(props[@"content"]);
            c.publishedText = TBStr(props[@"publishedTime"]);
            c.isReply = TBInt(props[@"replyLevel"]) > 0;
            NSDictionary *author = TBDict(payload[@"author"]);
            c.authorName = TBStr(author[@"displayName"]);
            c.authorChannelId = TBStr(author[@"channelId"]);
            c.authorAvatarURL = TBImageURL(TBStr(author[@"avatarThumbnailUrl"]));
            c.isCreator = TBBool(author[@"isCreator"]);
            NSDictionary *toolbar = TBDict(payload[@"toolbar"]);
            c.likesText = TBStr(toolbar[@"likeCountNotliked"]) ?: TBStr(toolbar[@"likeCountLiked"]);
            if ([c.likesText isEqualToString:@"0"]) c.likesText = nil;
            c.replyCount = (NSInteger)TBNumberFromText(TBStr(toolbar[@"replyCount"]));
            NSDictionary *state = toolbars[TBStr(props[@"toolbarStateKey"]) ?: @""];
            c.isHearted = [TBStr(state[@"heartState"]) isEqualToString:@"TOOLBAR_HEART_STATE_HEARTED"];
            c.isPinned = TBDict(vm[@"pinnedText"]) != nil || TBFindFirst(source, @"pinnedCommentBadge") != nil;
            if (threads.count) {
                NSString *repliesToken = nil;
                [self itemsInNode:source[@"replies"] continuation:&repliesToken];
                c.repliesToken = repliesToken;
            }
            [comments addObject:c];
        }
        // the next page: the last continuation item outside the threads
        NSString *next = nil;
        NSMutableArray *tokens = [NSMutableArray array];
        for (id endpoint in TBArr(response[@"onResponseReceivedEndpoints"])) {
            NSDictionary *e = TBDict(endpoint);
            NSArray *items = TBArr(TBDict(e[@"appendContinuationItemsAction"])[@"continuationItems"]) ?: TBArr(TBDict(e[@"reloadContinuationItemsCommand"])[@"continuationItems"]);
            for (id item in items) {
                NSDictionary *cont = TBDict(TBDict(item)[@"continuationItemRenderer"]);
                NSString *t = TBStr(TBDict(TBDict(cont[@"continuationEndpoint"])[@"continuationCommand"])[@"token"])
                              ?: TBStr(TBDict(TBDict(TBDict(TBDict(cont[@"button"])[@"buttonRenderer"])[@"command"])[@"continuationCommand"])[@"token"]);
                if (t.length) [tokens addObject:t];
            }
        }
        next = tokens.lastObject;
        NSDictionary *header = TBFindFirst(response, @"commentsHeaderRenderer");
        NSString *countText = TBText(header[@"countText"]) ?: TBText(header[@"commentsCount"]);
        completion(comments, next, countText, nil);
    }];
}

#pragma mark - Player

+ (TBHTTPTask *)player:(NSString *)videoId client:(TBClient)client completion:(void (^)(TBPlayerInfo *info, NSError *error))completion
{
    NSDictionary *body = @{ @"videoId": videoId ?: @"", @"contentCheckOk": @YES, @"racyCheckOk": @YES };
    return [self call:@"player" body:body client:client completion:^(NSDictionary *response, NSError *error) {
        if (error) { completion(nil, error); return; }
        TBPlayerInfo *info = [[TBPlayerInfo alloc] init];
        NSDictionary *status = TBDict(response[@"playabilityStatus"]);
        info.status = TBStr(status[@"status"]) ?: @"";
        info.statusReason = TBStr(status[@"reason"]) ?: TBText(TBFindFirst(status[@"errorScreen"], @"subreason"));
        NSDictionary *details = TBDict(response[@"videoDetails"]);
        info.videoId = TBStr(details[@"videoId"]) ?: videoId;
        info.title = TBStr(details[@"title"]);
        info.author = TBStr(details[@"author"]);
        info.channelId = TBStr(details[@"channelId"]);
        info.lengthSeconds = TBDbl(details[@"lengthSeconds"]);
        info.viewCount = (long long)TBDbl(details[@"viewCount"]);
        info.isLive = TBBool(details[@"isLive"]);
        info.isLiveContent = TBBool(details[@"isLiveContent"]);
        info.shortDescription = TBStr(details[@"shortDescription"]);
        info.thumbnailURL = TBThumbnailURL(details[@"thumbnail"]);
        NSDictionary *streaming = TBDict(response[@"streamingData"]);
        info.hlsManifestURL = TBStr(streaming[@"hlsManifestUrl"]);
        // progressive MP4 with sound: the tallest up to 720p
        NSInteger bestHeight = 0;
        for (id f in TBArr(streaming[@"formats"])) {
            NSDictionary *format = TBDict(f);
            NSString *url = TBStr(format[@"url"]);
            NSString *mime = TBStr(format[@"mimeType"]) ?: @"";
            NSInteger height = TBInt(format[@"height"]);
            if (!url.length || ![mime hasPrefix:@"video/mp4"] || [mime rangeOfString:@"avc1"].location == NSNotFound) continue;
            if (height > 720 || height <= bestHeight) continue;
            bestHeight = height;
            info.progressiveURL = url;
            info.progressiveHeight = height;
        }
        // adaptive MP4 files (DASH): H.264 pictures, AAC-LC sound - the media proxy remuxes them when there is no HLS
        NSMutableArray *dashVideo = [NSMutableArray array];
        NSMutableArray *dashAudio = [NSMutableArray array];
        for (id f in TBArr(streaming[@"adaptiveFormats"])) {
            NSDictionary *format = TBDict(f);
            NSString *url = TBStr(format[@"url"]);
            NSString *mime = TBStr(format[@"mimeType"]) ?: @"";
            NSDictionary *initRange = TBDict(format[@"initRange"]), *indexRange = TBDict(format[@"indexRange"]);
            if (!url.length || !initRange || !indexRange) continue;
            BOOL video = [mime hasPrefix:@"video/mp4"] && [mime rangeOfString:@"avc1"].location != NSNotFound;
            BOOL audio = [mime hasPrefix:@"audio/mp4"] && [mime rangeOfString:@"mp4a.40.2"].location != NSNotFound;
            if (!video && !audio) continue;
            TBDashFormat *d = [[TBDashFormat alloc] init];
            d.itag = TBInt(format[@"itag"]);
            d.url = url;
            d.isAudio = audio;
            NSRange codecs = [mime rangeOfString:@"codecs=\""];
            if (codecs.location != NSNotFound) {
                NSString *rest = [mime substringFromIndex:NSMaxRange(codecs)];
                NSRange quote = [rest rangeOfString:@"\""];
                d.codecs = quote.location != NSNotFound ? [rest substringToIndex:quote.location] : rest;
            }
            d.width = TBInt(format[@"width"]);
            d.height = TBInt(format[@"height"]);
            d.frameRate = TBDbl(format[@"fps"]);
            d.bitrate = TBInt(format[@"bitrate"]);
            d.initStart = (long long)TBDbl(initRange[@"start"]);
            d.initEnd = (long long)TBDbl(initRange[@"end"]);
            d.indexStart = (long long)TBDbl(indexRange[@"start"]);
            d.indexEnd = (long long)TBDbl(indexRange[@"end"]);
            d.contentLength = (long long)TBDbl(format[@"contentLength"]);
            d.duration = TBDbl(format[@"approxDurationMs"]) / 1000.0;
            d.audioSampleRate = TBInt(format[@"audioSampleRate"]);
            d.audioChannels = TBInt(format[@"audioChannels"]);
            NSDictionary *track = TBDict(format[@"audioTrack"]);
            d.isDefaultAudio = !track || TBBool(track[@"audioIsDefault"]);
            d.audioTrackName = TBStr(track[@"displayName"]);
            if (d.indexEnd <= d.indexStart || d.indexEnd > 2000000) continue;   // (an index of megabytes: not this kind of file)
            [video ? dashVideo : dashAudio addObject:d];
        }
        [dashVideo sortUsingComparator:^NSComparisonResult(TBDashFormat *a, TBDashFormat *b) {
            if (a.height != b.height) return a.height > b.height ? NSOrderedAscending : NSOrderedDescending;
            if (a.frameRate != b.frameRate) return a.frameRate > b.frameRate ? NSOrderedAscending : NSOrderedDescending;
            return a.bitrate < b.bitrate ? NSOrderedAscending : (a.bitrate > b.bitrate ? NSOrderedDescending : NSOrderedSame);
        }];
        info.dashVideo = dashVideo;
        // the sound: the original track (dubbed ones carry an audioTrack that is not the default), the best bitrate
        TBDashFormat *bestAudio = nil;
        for (TBDashFormat *a in dashAudio) {
            if (!bestAudio || (a.isDefaultAudio && !bestAudio.isDefaultAudio) || (a.isDefaultAudio == bestAudio.isDefaultAudio && a.bitrate > bestAudio.bitrate)) bestAudio = a;
        }
        info.dashAudio = bestAudio;
        NSMutableArray *tracks = [NSMutableArray array];
        for (id t in TBArr(TBDict(TBDict(response[@"captions"])[@"playerCaptionsTracklistRenderer"])[@"captionTracks"])) {
            NSDictionary *track = TBDict(t);
            TBCaptionTrack *ct = [[TBCaptionTrack alloc] init];
            ct.url = TBStr(track[@"baseUrl"]);
            ct.languageCode = TBStr(track[@"languageCode"]);
            ct.name = TBText(track[@"name"]);
            ct.isAuto = [TBStr(track[@"kind"]) isEqualToString:@"asr"];
            if (ct.url.length) [tracks addObject:ct];
        }
        info.captionTracks = tracks;
        NSDictionary *micro = TBDict(TBDict(response[@"microformat"])[@"playerMicroformatRenderer"]);
        info.publishDate = TBStr(micro[@"publishDate"]) ?: TBStr(micro[@"uploadDate"]);
        info.category = TBStr(micro[@"category"]);
        completion(info, nil);
    }];
}

@end
