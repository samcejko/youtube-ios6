#import "TBModels.h"
#import "TBUtils.h"
#import "TBCommon.h"

#pragma mark - Text helpers

NSString *TBText(id node)
{
    if ([node isKindOfClass:[NSString class]]) return node;
    NSDictionary *d = TBDict(node);
    if (!d) return nil;
    NSString *simple = TBStr(d[@"simpleText"]);
    if (simple) return simple;
    NSString *content = TBStr(d[@"content"]);
    if (content) return content;
    NSArray *runs = TBArr(d[@"runs"]);
    if (runs.count) {
        NSMutableString *s = [NSMutableString string];
        for (id run in runs) {
            NSString *t = TBStr(TBDict(run)[@"text"]);
            if (t) [s appendString:t];
        }
        return s;
    }
    // accessibility labels carry the text of some badges
    NSString *label = TBStr(TBDict(TBDict(d[@"accessibility"])[@"accessibilityData"])[@"label"]);
    if (label) return label;
    return nil;
}

NSString *TBAbsoluteURL(NSString *url)
{
    if (!url.length) return url;
    if ([url hasPrefix:@"//"]) return [@"https:" stringByAppendingString:url];
    return url;
}

NSString *TBThumbnailURL(id node)
{
    NSDictionary *d = TBDict(node);
    if (!d) return nil;
    NSArray *list = TBArr(d[@"thumbnails"]) ?: TBArr(d[@"sources"]);
    if (!list) {
        // one level down: {"thumbnail": {"thumbnails": [...]}}, {"image": {"sources": [...]}}
        for (NSString *key in @[ @"thumbnail", @"image", @"primaryThumbnail", @"thumbnailViewModel", @"avatar", @"avatarViewModel", @"decoratedAvatarViewModel" ]) {
            NSString *found = TBThumbnailURL(d[key]);
            if (found) return found;
        }
        return nil;
    }
    NSDictionary *best = nil;
    for (id item in list) {
        NSDictionary *t = TBDict(item);
        if (!TBStr(t[@"url"]).length) continue;
        if (!best || TBInt(t[@"width"]) > TBInt(best[@"width"])) best = t;
    }
    return TBAbsoluteURL(TBStr(best[@"url"]));
}

long long TBNumberFromText(NSString *text)
{
    if (!text.length) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    [scanner scanUpToCharactersFromSet:digits intoString:NULL];
    NSMutableString *number = [NSMutableString string];
    double multiplier = 1;
    BOOL seenDot = NO;
    for (NSUInteger i = (NSUInteger)scanner.scanLocation; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if ([digits characterIsMember:c]) { [number appendFormat:@"%C", c]; continue; }
        if ((c == '.' || c == ',') && !seenDot && i + 1 < text.length && [digits characterIsMember:[text characterAtIndex:i + 1]]) {
            // "1.2M" has a decimal point; "67,046" has a thousands separator (three digits follow)
            BOOL thousands = (i + 3 < text.length) && [digits characterIsMember:[text characterAtIndex:i + 2]] && [digits characterIsMember:[text characterAtIndex:i + 3]]
                             && (i + 4 >= text.length || ![digits characterIsMember:[text characterAtIndex:i + 4]]);
            if (thousands) continue;
            [number appendString:@"."];
            seenDot = YES;
            continue;
        }
        if (c == ' ' || c == 0xA0) continue;
        if (c == 'K' || c == 'k') multiplier = 1000;
        else if (c == 'M' || c == 'm') multiplier = 1000000;
        else if (c == 'B' || c == 'b') multiplier = 1000000000;
        // Czech: "tis." / "mil." / "mld."
        else if (c == 't' && [text rangeOfString:@"tis" options:0 range:NSMakeRange(i, text.length - i)].location == i) multiplier = 1000;
        break;
    }
    if (!number.length) return 0;
    return (long long)([number doubleValue] * multiplier);
}

#pragma mark - Video

@implementation TBVideo

+ (instancetype)videoWithId:(NSString *)videoId
{
    TBVideo *v = [[TBVideo alloc] init];
    v.videoId = videoId;
    return v;
}

- (NSString *)thumbnailURLForWidth:(NSInteger)width
{
    if (!self.videoId.length) return self.thumbnailURL;
    NSString *name = width <= 320 ? @"mqdefault" : (width <= 480 ? @"hqdefault" : (width <= 640 ? @"sddefault" : @"hq720"));
    return [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/%@.jpg", self.videoId, name];
}

- (NSString *)metaText
{
    NSMutableArray *parts = [NSMutableArray array];
    if (self.channelName.length) [parts addObject:self.channelName];
    if (self.isLive) [parts addObject:self.viewsText.length ? self.viewsText : L(@"Live")];
    else {
        if (self.viewsText.length) [parts addObject:self.viewsText];
        else if (self.viewCount > 0) [parts addObject:[NSString stringWithFormat:L(@"%@ views"), [TBUtils formatCount:(NSInteger)MIN(self.viewCount, (long long)NSIntegerMax)]]];
        if (self.publishedText.length) [parts addObject:self.publishedText];
        else if (self.publishedAt) [parts addObject:[TBUtils formatRelativeDate:self.publishedAt]];
    }
    return [parts componentsJoinedByString:@" · "];
}

- (NSDictionary *)dictionary
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.videoId) d[@"id"] = self.videoId;
    if (self.title) d[@"title"] = self.title;
    if (self.channelId) d[@"channelId"] = self.channelId;
    if (self.channelName) d[@"channelName"] = self.channelName;
    if (self.thumbnailURL) d[@"thumbnail"] = self.thumbnailURL;
    if (self.lengthSeconds > 0) d[@"length"] = @(self.lengthSeconds);
    if (self.lengthText) d[@"lengthText"] = self.lengthText;
    if (self.viewsText) d[@"viewsText"] = self.viewsText;
    if (self.publishedText) d[@"publishedText"] = self.publishedText;
    if (self.publishedAt) d[@"publishedAt"] = self.publishedAt;
    if (self.watchedAt) d[@"watchedAt"] = self.watchedAt;
    if (self.position > 0) d[@"position"] = @(self.position);
    if (self.isLive) d[@"live"] = @YES;
    if (self.isShort) d[@"short"] = @YES;
    return d;
}

+ (instancetype)videoFromDictionary:(NSDictionary *)d
{
    d = TBDict(d);
    NSString *videoId = TBStr(d[@"id"]);
    if (!videoId.length) return nil;
    TBVideo *v = [TBVideo videoWithId:videoId];
    v.title = TBStr(d[@"title"]);
    v.channelId = TBStr(d[@"channelId"]);
    v.channelName = TBStr(d[@"channelName"]);
    v.thumbnailURL = TBStr(d[@"thumbnail"]);
    v.lengthSeconds = TBDbl(d[@"length"]);
    v.lengthText = TBStr(d[@"lengthText"]);
    v.viewsText = TBStr(d[@"viewsText"]);
    v.publishedText = TBStr(d[@"publishedText"]);
    v.publishedAt = [d[@"publishedAt"] isKindOfClass:[NSDate class]] ? d[@"publishedAt"] : nil;
    v.watchedAt = [d[@"watchedAt"] isKindOfClass:[NSDate class]] ? d[@"watchedAt"] : nil;
    v.position = TBDbl(d[@"position"]);
    v.isLive = TBBool(d[@"live"]);
    v.isShort = TBBool(d[@"short"]);
    return v;
}

@end

#pragma mark - Channel

@implementation TBChannelTab
@end

@implementation TBChannel

- (NSDictionary *)dictionary
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.channelId) d[@"id"] = self.channelId;
    if (self.title) d[@"title"] = self.title;
    if (self.handle) d[@"handle"] = self.handle;
    if (self.avatarURL) d[@"avatar"] = self.avatarURL;
    if (self.subscribersText) d[@"subscribers"] = self.subscribersText;
    if (self.subscribedAt) d[@"subscribedAt"] = self.subscribedAt;
    return d;
}

+ (instancetype)channelFromDictionary:(NSDictionary *)d
{
    d = TBDict(d);
    NSString *channelId = TBStr(d[@"id"]);
    if (!channelId.length) return nil;
    TBChannel *c = [[TBChannel alloc] init];
    c.channelId = channelId;
    c.title = TBStr(d[@"title"]);
    c.handle = TBStr(d[@"handle"]);
    c.avatarURL = TBStr(d[@"avatar"]);
    c.subscribersText = TBStr(d[@"subscribers"]);
    c.subscribedAt = [d[@"subscribedAt"] isKindOfClass:[NSDate class]] ? d[@"subscribedAt"] : nil;
    return c;
}

@end

@implementation TBPlaylist
@end

@implementation TBComment
@end

@implementation TBCaptionTrack
@end

#pragma mark - Streams

@implementation TBVariant

- (BOOL)isH264
{
    return [self.codecs rangeOfString:@"avc1" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

- (NSString *)title
{
    if (self.height <= 0) return L(@"Video");
    if (self.frameRate > 30.5) return [NSString stringWithFormat:@"%ldp%.0f", (long)self.height, self.frameRate];
    return [NSString stringWithFormat:@"%ldp", (long)self.height];
}

- (NSString *)qualityKey
{
    return [NSString stringWithFormat:@"%ld", (long)self.height];
}

@end

@implementation TBAudioRendition
@end

@implementation TBPlayerInfo

- (BOOL)isPlayable
{
    return [self.status isEqualToString:@"OK"] && (self.hlsManifestURL.length || self.progressiveURL.length);
}

@end

@implementation TBShelf
@end

@implementation TBWatchInfo
@end
