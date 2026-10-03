#import "TBExtras.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"

#pragma mark - SponsorBlock

@implementation TBSponsorSegment

- (NSString *)title
{
    return [TBSponsorBlock titleForCategory:self.category];
}

@end

@implementation TBSponsorBlock

+ (NSArray *)allCategories
{
    return @[ @"sponsor", @"selfpromo", @"interaction", @"intro", @"outro", @"preview", @"music_offtopic", @"filler" ];
}

+ (NSString *)titleForCategory:(NSString *)category
{
    if ([category isEqualToString:@"sponsor"]) return L(@"Sponsor");
    if ([category isEqualToString:@"selfpromo"]) return L(@"Self-promotion");
    if ([category isEqualToString:@"interaction"]) return L(@"Reminder to subscribe");
    if ([category isEqualToString:@"intro"]) return L(@"Intro");
    if ([category isEqualToString:@"outro"]) return L(@"Outro");
    if ([category isEqualToString:@"preview"]) return L(@"Preview / recap");
    if ([category isEqualToString:@"music_offtopic"]) return L(@"Non-music part");
    if ([category isEqualToString:@"filler"]) return L(@"Filler");
    return category ?: @"";
}

+ (TBHTTPTask *)segmentsForVideo:(NSString *)videoId completion:(void (^)(NSArray *segments, NSError *error))completion
{
    NSArray *categories = [TBSettings sponsorBlockCategories];
    if (!videoId.length || !categories.count) { TBMain(^{ completion(@[], nil); }); return nil; }
    NSData *json = [TBUtils JSONDataFromObject:categories];
    NSString *url = [NSString stringWithFormat:@"https://sponsor.ajay.app/api/skipSegments?videoID=%@&categories=%@",
                     [TBUtils urlEncode:videoId], [TBUtils urlEncode:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"[]"]];
    return [TBHTTP getJSON:url headers:nil completion:^(id response, NSInteger status, NSError *error) {
        if (status == 404) { completion(@[], nil); return; }   // (no segments for this video)
        if (error) { completion(nil, error); return; }
        NSMutableArray *segments = [NSMutableArray array];
        for (id item in TBArr(response)) {
            NSDictionary *d = TBDict(item);
            NSArray *range = TBArr(d[@"segment"]);
            if (range.count != 2) continue;
            TBSponsorSegment *s = [[TBSponsorSegment alloc] init];
            s.start = TBDbl(range[0]);
            s.end = TBDbl(range[1]);
            s.category = TBStr(d[@"category"]);
            if (s.end > s.start + 0.5) [segments addObject:s];
        }
        [segments sortUsingComparator:^NSComparisonResult(TBSponsorSegment *a, TBSponsorSegment *b) {
            return a.start < b.start ? NSOrderedAscending : (a.start > b.start ? NSOrderedDescending : NSOrderedSame);
        }];
        completion(segments, nil);
    }];
}

@end

#pragma mark - Return YouTube Dislike

@implementation TBVotes
@end

@implementation TBReturnDislike

+ (TBHTTPTask *)votesForVideo:(NSString *)videoId completion:(void (^)(TBVotes *votes, NSError *error))completion
{
    NSString *url = [NSString stringWithFormat:@"https://returnyoutubedislikeapi.com/votes?videoId=%@", [TBUtils urlEncode:videoId ?: @""]];
    return [TBHTTP getJSON:url headers:nil completion:^(id response, NSInteger status, NSError *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *d = TBDict(response);
        TBVotes *v = [[TBVotes alloc] init];
        v.likes = (long long)TBDbl(d[@"likes"]);
        v.dislikes = (long long)TBDbl(d[@"dislikes"]);
        v.viewCount = (long long)TBDbl(d[@"viewCount"]);
        completion(v, nil);
    }];
}

@end

#pragma mark - Captions

@implementation TBCaptionCue
@end

@implementation TBCaptions

+ (TBCaptionTrack *)preferredTrackIn:(NSArray *)tracks
{
    if (!tracks.count || ![TBSettings captionsEnabled]) return nil;
    NSString *wanted = [TBSettings captionsLanguage];
    if (!wanted.length) wanted = [[NSLocale preferredLanguages] firstObject] ?: @"en";
    NSString *base = [[wanted componentsSeparatedByString:@"-"] firstObject];
    TBCaptionTrack *exact = nil, *automatic = nil, *english = nil;
    for (TBCaptionTrack *t in tracks) {
        NSString *code = [[t.languageCode componentsSeparatedByString:@"-"] firstObject];
        if ([code isEqualToString:base]) {
            if (!t.isAuto && !exact) exact = t;
            if (t.isAuto && !automatic) automatic = t;
        }
        if ([code isEqualToString:@"en"] && !t.isAuto && !english) english = t;
    }
    return exact ?: (automatic ?: english);
}

static NSTimeInterval TBVTTTime(NSString *s)
{
    // "00:00:01.360" or "01.360" or "00:01.360"
    NSArray *parts = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsSeparatedByString:@":"];
    NSTimeInterval t = 0;
    for (NSString *p in parts) t = t * 60 + [p doubleValue];
    return t;
}

+ (TBHTTPTask *)loadTrack:(TBCaptionTrack *)track completion:(void (^)(NSArray *cues, NSError *error))completion
{
    NSString *url = track.url;
    if (!url.length) { TBMain(^{ completion(nil, TBMakeError(TBErrorAPI, L(@"No captions."))); }); return nil; }
    url = [url stringByAppendingString:[url rangeOfString:@"?"].location == NSNotFound ? @"?fmt=vtt" : @"&fmt=vtt"];
    return [TBHTTP get:url headers:nil completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (status != 200) { completion(nil, TBMakeError(TBErrorAPI, L(@"The captions could not be loaded."))); return; }
        NSString *text = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] ?: @"";
        NSMutableArray *cues = [NSMutableArray array];
        TBCaptionCue *cue = nil;
        NSMutableString *cueText = nil;
        for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange arrow = [line rangeOfString:@"-->"];
            if (arrow.location != NSNotFound) {
                if (cue && cueText.length) { cue.text = cueText; [cues addObject:cue]; }
                cue = [[TBCaptionCue alloc] init];
                cue.start = TBVTTTime([line substringToIndex:arrow.location]);
                NSString *rest = [[line substringFromIndex:arrow.location + 3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                NSRange space = [rest rangeOfString:@" "];   // ("00:00:03.000 align:start position:0%": the settings follow the time)
                cue.end = TBVTTTime(space.location != NSNotFound ? [rest substringToIndex:space.location] : rest);
                cueText = [NSMutableString string];
                continue;
            }
            if (!cue) continue;
            if (!line.length) {
                if (cueText.length) { cue.text = cueText; [cues addObject:cue]; }
                cue = nil;
                cueText = nil;
                continue;
            }
            // tags (<c>, <b>, timestamps) out, entities in
            NSMutableString *clean = [NSMutableString string];
            BOOL inTag = NO;
            for (NSUInteger i = 0; i < line.length; i++) {
                unichar c = [line characterAtIndex:i];
                if (c == '<') { inTag = YES; continue; }
                if (c == '>') { inTag = NO; continue; }
                if (!inTag) [clean appendFormat:@"%C", c];
            }
            NSString *decoded = [[[[clean stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"] stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"]
                                   stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"] stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
            decoded = [[decoded stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"] stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
            if (!decoded.length) continue;
            if (cueText.length) [cueText appendString:@"\n"];
            [cueText appendString:decoded];
        }
        if (cue && cueText.length) { cue.text = cueText; [cues addObject:cue]; }
        completion(cues, nil);
    }];
}

+ (TBCaptionCue *)cueAtTime:(NSTimeInterval)time inCues:(NSArray *)cues
{
    // binary search for the last cue starting at or before `time`
    NSInteger lo = 0, hi = (NSInteger)cues.count - 1, found = -1;
    while (lo <= hi) {
        NSInteger mid = (lo + hi) / 2;
        TBCaptionCue *c = cues[(NSUInteger)mid];
        if (c.start <= time) { found = mid; lo = mid + 1; } else hi = mid - 1;
    }
    // (auto captions overlap: the latest cue that has started wins)
    for (NSInteger i = found; i >= 0 && i > found - 3; i--) {
        TBCaptionCue *c = cues[(NSUInteger)i];
        if (c.start <= time && time < c.end) return c;
    }
    return nil;
}

@end
