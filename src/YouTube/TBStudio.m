#import "TBStudio.h"
#import "TBStudioReports.h"
#import "TBAccount.h"
#import "TBUtils.h"
#import "TBCommon.h"

@implementation TBStudio
+ (NSArray *)recordsFromReport:(id)report
{
    return [TBStudioReports records:report];
}
+ (NSString *)errorText:(NSDictionary *)json status:(NSInteger)status analytics:(BOOL)analytics
{
    NSDictionary *error=TBDict(json[@"error"]);NSString *reason=TBStr(TBDict([TBArr(error[@"errors"]) firstObject])[@"reason"]);
    if (status>=500) return L(@"YouTube could not load this report. Try again later.");
    if (status==401) return L(@"Your Google sign-in has expired. Sign in again in Account settings.");
    if ([reason isEqualToString:@"accessNotConfigured"] || [reason isEqualToString:@"serviceDisabled"]) return analytics ? L(@"This report is unavailable for the current sign-in. Other reports may still work.") : L(@"Enable YouTube Data API v3 in the Google Cloud project used for this sign-in.");
    if (status==403) return analytics ? L(@"YouTube does not allow this report for the current sign-in.") : L(@"This sign-in cannot read your channel. Check the Google client's YouTube access.");
    return TBStr(error[@"message"]) ?: L(@"The report could not be loaded. Try again.");
}
+ (void)completeMetadata:(NSMutableDictionary *)result token:(NSString *)token outer:(TBHTTPTask *)outer children:(NSMutableArray *)children completion:(void (^)(NSDictionary *))completion
{
    NSMutableArray *ids=[NSMutableArray array];
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet];
    for (NSDictionary *row in TBArr(result[@"topVideos"])) {
        NSString *video=TBStr(row[@"video"]);
        if(video.length==11 && [video rangeOfCharacterFromSet:invalid].location==NSNotFound)[ids addObject:video];
    }
    void (^finish)(void)=^{ if(outer.isCancelled)return;outer.cancelBlock=nil;@synchronized(children){[children removeAllObjects];}completion(result); };
    if(!ids.count){finish();return;}
    NSString *url=[@"https://www.googleapis.com/youtube/v3/videos?part=snippet&id=" stringByAppendingString:[TBUtils urlEncode:[ids componentsJoinedByString:@","]]];
    TBHTTPTask *task=[TBHTTP getJSON:url headers:@{@"Authorization":[@"Bearer " stringByAppendingString:token]} completion:^(id json,NSInteger status,NSError *error){
        if(outer.isCancelled)return;
        NSMutableDictionary *titles=[NSMutableDictionary dictionary];
        for(NSDictionary *item in TBArr(TBDict(json)[@"items"])) { NSString *identifier=TBStr(item[@"id"]),*title=TBStr(TBDict(item[@"snippet"])[@"title"]);if(identifier.length && title.length)titles[identifier]=title; }
        result[@"videoTitles"]=titles;
        NSMutableArray *missing=[NSMutableArray array];for(NSString *identifier in ids)if(!titles[identifier])[missing addObject:identifier];
        if(!missing.count){finish();return;}
        __block NSUInteger pending=missing.count;
        // Public metadata still works when this OAuth project's Data API is disabled.
        // Never send the account token to the public oEmbed request.
        for(NSString *identifier in missing){
            NSString *watch=[@"https://www.youtube.com/watch?v=" stringByAppendingString:identifier];
            NSString *embed=[@"https://www.youtube.com/oembed?format=json&url=" stringByAppendingString:[TBUtils urlEncode:watch]];
            TBHTTPTask *metadata=[TBHTTP getJSON:embed headers:nil completion:^(id body,NSInteger code,NSError *failure){
                if(outer.isCancelled)return;NSString *title=TBStr(TBDict(body)[@"title"]);if(code==200 && title.length)titles[identifier]=title;
                if(--pending==0)finish();
            }];
            @synchronized(children){[children addObject:metadata];}
        }
    }];
    @synchronized(children){[children addObject:task];}
}
 + (void)completeDashboard:(NSMutableDictionary *)result token:(NSString *)token outer:(TBHTTPTask *)outer children:(NSMutableArray *)children completion:(void (^)(NSDictionary *))completion
{
    NSDictionary *query=[TBStudioReports previousQueryForDashboard:result];
    if(!query){[self completeMetadata:result token:token outer:outer children:children completion:completion];return;}
    result[@"previousStartDate"]=query[@"startDate"];result[@"previousEndDate"]=query[@"endDate"];
    NSMutableArray *pairs=[NSMutableArray array];for(NSString *key in [[query allKeys] sortedArrayUsingSelector:@selector(compare:)])[pairs addObject:[NSString stringWithFormat:@"%@=%@",key,[TBUtils urlEncode:query[key]]]];
    TBHTTPTask *task=[TBHTTP getJSON:[@"https://youtubeanalytics.googleapis.com/v2/reports?" stringByAppendingString:[pairs componentsJoinedByString:@"&"]] headers:@{@"Authorization":[@"Bearer " stringByAppendingString:token]} completion:^(id json,NSInteger status,NSError *error){
        if(outer.isCancelled)return;if(status==200 && !error)result[@"previousSummary"]=[self recordsFromReport:json];else {result[@"previousSummaryError"]=status>0?[self errorText:TBDict(json) status:status analytics:YES]:(error.localizedDescription ?: L(@"The report could not be loaded. Try again."));result[@"previousSummaryHTTP"]=@(status);}
        [self completeMetadata:result token:token outer:outer children:children completion:completion];
    }];if(task)@synchronized(children){[children addObject:task];}
}
+ (TBHTTPTask *)reportForDimension:(NSString *)dimension days:(NSInteger)days video:(NSString *)videoId completion:(void (^)(NSDictionary *))completion
{
    TBHTTPTask *outer=[[TBHTTPTask alloc] init];NSMutableArray *children=[NSMutableArray array];outer.cancelBlock=^{for(TBHTTPTask *task in children)[task cancel];[children removeAllObjects];};
    NSDictionary *query=[TBStudioReports queryForDimension:dimension days:days video:videoId now:nil];
    if(!query){outer.cancelBlock=nil;completion(@{@"error":L(@"The report could not be loaded. Try again.")});return outer;}
    NSMutableDictionary *result=[@{@"dimension":dimension,@"startDate":query[@"startDate"],@"endDate":query[@"endDate"]} mutableCopy];
    TBHTTPTask *auth=[[TBAccount shared] withAccessToken:^(NSString *token,NSError *error){if(outer.isCancelled)return;if(!token.length){result[@"error"]=error.localizedDescription ?: L(@"Not signed in.");outer.cancelBlock=nil;completion(result);return;}
        NSMutableArray *pairs=[NSMutableArray array];for(NSString *key in [[query allKeys] sortedArrayUsingSelector:@selector(compare:)])[pairs addObject:[NSString stringWithFormat:@"%@=%@",key,[TBUtils urlEncode:query[key]]]];
        TBHTTPTask *task=[TBHTTP getJSON:[@"https://youtubeanalytics.googleapis.com/v2/reports?" stringByAppendingString:[pairs componentsJoinedByString:@"&"]] headers:@{@"Authorization":[@"Bearer " stringByAppendingString:token]} completion:^(id json,NSInteger status,NSError *failure){if(outer.isCancelled)return;if(status==200 && !failure)result[@"rows"]=[self recordsFromReport:json];else {result[@"error"]=status>0?[self errorText:TBDict(json) status:status analytics:YES]:(failure.localizedDescription ?: L(@"The report could not be loaded. Try again."));result[@"HTTP"]=@(status);}outer.cancelBlock=nil;[children removeAllObjects];completion(result);}];if(task)[children addObject:task];
    }];if(auth)[children addObject:auth];return outer;
}
+ (TBHTTPTask *)dashboardForDays:(NSInteger)days completion:(void (^)(NSDictionary *))completion {return [self dashboardForDays:days video:nil completion:completion];}
+ (TBHTTPTask *)dashboardForDays:(NSInteger)days video:(NSString *)videoId completion:(void (^)(NSDictionary *))completion
{
    if (days!=7 && days!=28 && days!=90) days=28;
    TBHTTPTask *outer=[[TBHTTPTask alloc] init];
    if(videoId.length && ![TBStudioReports queryForDimension:@"country" days:days video:videoId now:nil]){completion(@{@"accountError":L(@"This report is unavailable for the current sign-in. Other reports may still work.")});return outer;}
    NSMutableArray *children=[NSMutableArray array];
    outer.cancelBlock=^{ @synchronized(children) { for(TBHTTPTask *task in children)[task cancel];[children removeAllObjects]; } };
    NSCalendar *calendar=[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];calendar.timeZone=[NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    NSDateComponents *offset=[[NSDateComponents alloc] init];offset.day=1-days;
    NSDate *today=[NSDate date],*start=[calendar dateByAddingComponents:offset toDate:today options:0];
    NSDateFormatter *format=[[NSDateFormatter alloc] init];format.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];format.timeZone=calendar.timeZone;format.dateFormat=@"yyyy-MM-dd";
    NSMutableDictionary *result=[@{@"days":@(days),@"startDate":[format stringFromDate:start],@"endDate":[format stringFromDate:today]} mutableCopy];
    TBHTTPTask *auth=[[TBAccount shared] withAccessToken:^(NSString *token,NSError *error) {
        if (outer.isCancelled) return;
        if (!token.length) { result[@"accountError"]=error.localizedDescription ?: L(@"Sign in with Google to see your channel and reports.");outer.cancelBlock=nil;completion(result);return; }
        NSString *metrics=@"views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage,likes,comments,shares,subscribersGained,subscribersLost";
        NSMutableDictionary *base=[@{@"ids":@"channel==MINE",@"startDate":result[@"startDate"],@"endDate":result[@"endDate"]} mutableCopy];
        if(videoId.length){base[@"filters"]=[@"video==" stringByAppendingString:videoId];result[@"videoId"]=videoId;}
        NSMutableDictionary *summary=[base mutableCopy];summary[@"metrics"]=metrics;
        NSMutableDictionary *daily=[base mutableCopy];daily[@"metrics"]=metrics;daily[@"dimensions"]=@"day";daily[@"sort"]=@"day";
        NSMutableDictionary *top=[base mutableCopy];top[@"metrics"]=@"views,estimatedMinutesWatched,averageViewDuration";top[@"dimensions"]=@"video";top[@"sort"]=@"-views";top[@"maxResults"]=@"10";
        NSMutableArray *requests=[@[
            @{@"key":@"channel",@"url":@"https://www.googleapis.com/youtube/v3/channels",@"query":@{@"part":@"snippet,statistics,contentDetails",@"mine":@"true"}},
            @{@"key":@"summary",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":summary},
            @{@"key":@"daily",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":daily},
            @{@"key":@"topVideos",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":top}] mutableCopy];
        if(videoId.length){[requests removeObjectAtIndex:3];[requests removeObjectAtIndex:0];}
        __block NSUInteger pending=requests.count;
        for (NSDictionary *spec in requests) {
            NSMutableArray *pairs=[NSMutableArray array];NSDictionary *query=spec[@"query"];
            for (NSString *key in [[query allKeys] sortedArrayUsingSelector:@selector(compare:)]) [pairs addObject:[NSString stringWithFormat:@"%@=%@",key,[TBUtils urlEncode:[query[key] description]]]];
            NSString *url=[spec[@"url"] stringByAppendingFormat:@"?%@",[pairs componentsJoinedByString:@"&"]];
            TBHTTPTask *task=[TBHTTP getJSON:url headers:@{@"Authorization":[@"Bearer " stringByAppendingString:token],@"Accept":@"application/json"} completion:^(id json,NSInteger status,NSError *requestError) {
                if (outer.isCancelled) return;
                NSString *key=spec[@"key"];
                if (requestError || status!=200) {
                    result[[key stringByAppendingString:@"Error"]]=status>0 ? [self errorText:TBDict(json) status:status analytics:![key isEqualToString:@"channel"]] : (requestError.localizedDescription ?: L(@"The report could not be loaded. Try again."));
                    result[[key stringByAppendingString:@"HTTP"]]=@(status);
                    if([key isEqualToString:@"channel"] && [TBAccount shared].channelId.length)result[@"channel"]=@{@"id":[TBAccount shared].channelId,@"snippet":@{@"title":[TBAccount shared].channelTitle ?: L(@"Your channel")}};
                } else if ([key isEqualToString:@"channel"]) {
                    NSDictionary *channel=TBDict([TBArr(TBDict(json)[@"items"]) firstObject]);
                    if (channel) result[key]=channel;else result[@"channelError"]=L(@"This Google account has no YouTube channel.");
                } else result[key]=[self recordsFromReport:json];
                if (--pending==0) [self completeDashboard:result token:token outer:outer children:children completion:completion];
            }];
            @synchronized(children){[children addObject:task];}
        }
    }];
    if(auth)@synchronized(children){[children addObject:auth];}
    return outer;
}
@end
