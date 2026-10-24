#import "TBResolver.h"
#import <math.h>

static NSString *TBResolverString(id value) { return [value isKindOfClass:[NSString class]] ? value : nil; }
static double TBResolverNumber(id value) {
    double number=[value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    return isfinite(number) && number > 0 ? MIN(number,1.0e12) : 0;
}

static NSInteger TBResolverInteger(id value) { return (NSInteger)MIN((double)NSIntegerMax,TBResolverNumber(value)); }

@implementation TBResolver
+ (NSString *)streamURL:(id)value
{
    NSString *text=TBResolverString(value);
    NSURL *url=text.length ? [NSURL URLWithString:text] : nil;
    NSString *scheme=[url.scheme lowercaseString];
    return url.host.length && !url.user.length && !url.password.length && ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]) ? text : nil;
}
+ (NSDictionary *)mediaHeaders:(id)value
{
    if (![value isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    for (id key in value) {
        NSString *name=TBResolverString(key), *text=TBResolverString(value[key]);
        if (!name || !text || [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) continue;
        // Media requests never inherit the account's Authorization or Cookie headers.
        if ([@[@"user-agent",@"referer",@"origin",@"accept-language"] containsObject:[name lowercaseString]]) result[name]=text;
    }
    return result;
}
+ (TBPlayerInfo *)playerInfoFromResponse:(NSDictionary *)response videoId:(NSString *)videoId
{
    if (![response isKindOfClass:[NSDictionary class]]) return nil;
    NSString *returnedId=TBResolverString(response[@"id"]);
    if (returnedId.length && ![returnedId isEqualToString:videoId]) return nil;
    TBPlayerInfo *info=[[TBPlayerInfo alloc] init];
    info.videoId=videoId; info.title=TBResolverString(response[@"title"]); info.author=TBResolverString(response[@"author"]);
    info.channelId=TBResolverString(response[@"channelId"]); info.lengthSeconds=TBResolverNumber(response[@"duration"]);
    info.isLive=[response[@"isLive"] respondsToSelector:@selector(boolValue)] && [response[@"isLive"] boolValue];
    info.progressiveURL=[self streamURL:response[@"playUrl"]];
    info.progressiveHeight=TBResolverInteger(response[@"playHeight"]);
    info.hlsManifestURL=[self streamURL:response[@"hlsUrl"]];
    NSArray *raw=[response[@"adaptiveFormats"] isKindOfClass:[NSArray class]] ? response[@"adaptiveFormats"] : @[];
    NSMutableArray *videos=[NSMutableArray array]; TBDashFormat *audio=nil;
    for (id object in raw) {
        if (![object isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *value=object;
        NSString *url=[self streamURL:value[@"url"]], *codec=TBResolverString(value[@"codecs"]);
        BOOL isAudio=[codec hasPrefix:@"mp4a.40.2"], isVideo=[codec hasPrefix:@"avc1"] || [codec hasPrefix:@"avc3"];
        if (!url || (!isAudio && !isVideo)) continue;
        TBDashFormat *format=[[TBDashFormat alloc] init];
        format.itag=TBResolverInteger(value[@"itag"]); if (format.itag <= 0) continue;
        format.url=url;format.codecs=codec;format.isAudio=isAudio;
        format.width=TBResolverInteger(value[@"width"]);format.height=TBResolverInteger(value[@"height"]);
        format.frameRate=TBResolverNumber(value[@"fps"]);format.bitrate=TBResolverInteger(value[@"bitrate"]);
        format.contentLength=(long long)TBResolverNumber(value[@"contentLength"]);format.duration=info.lengthSeconds;
        format.indexEnd=(long long)MIN(1048575.0,TBResolverNumber(value[@"indexEnd"]));
        format.audioSampleRate=TBResolverInteger(value[@"audioSampleRate"]);format.audioChannels=TBResolverInteger(value[@"audioChannels"]);
        format.isDefaultAudio=[value[@"isDefaultAudio"] respondsToSelector:@selector(boolValue)] && [value[@"isDefaultAudio"] boolValue];
        format.httpHeaders=[self mediaHeaders:value[@"httpHeaders"]];
        if (isAudio) {
            if (!audio || (format.isDefaultAudio && !audio.isDefaultAudio) || (format.isDefaultAudio==audio.isDefaultAudio && format.bitrate>audio.bitrate)) audio=format;
        } else if (format.width>0 && format.height>0) [videos addObject:format];
    }
    [videos sortUsingComparator:^NSComparisonResult(TBDashFormat *a,TBDashFormat *b) {
        NSInteger ah=MIN(a.width,a.height), bh=MIN(b.width,b.height);
        if (ah != bh) return ah>bh ? NSOrderedAscending : NSOrderedDescending;
        return a.bitrate>b.bitrate ? NSOrderedAscending : (a.bitrate<b.bitrate ? NSOrderedDescending : NSOrderedSame);
    }];
    info.dashAudio=audio;info.dashVideo=videos;
    if (!info.progressiveURL.length && !info.hlsManifestURL.length && !(audio && videos.count)) return nil;
    info.status=@"OK";return info;
}
@end
