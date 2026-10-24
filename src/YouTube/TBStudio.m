#import "TBStudio.h"
#import "TBAccount.h"
#import "TBUtils.h"
#import "TBCommon.h"

@implementation TBStudio
+ (NSArray *)recordsFromReport:(id)report
{
    if (![report isKindOfClass:[NSDictionary class]]) return @[];
    NSArray *columns=TBArr(report[@"columnHeaders"]),*rows=TBArr(report[@"rows"]);
    NSMutableArray *records=[NSMutableArray array];
    for (id row in rows) {
        if (![row isKindOfClass:[NSArray class]] || [row count]!=columns.count) continue;
        NSMutableDictionary *record=[NSMutableDictionary dictionary];
        for (NSUInteger i=0;i<columns.count;i++) {
            NSString *name=TBStr(TBDict(columns[i])[@"name"]);id value=row[i];
            if (name.length && ([value isKindOfClass:[NSNumber class]] || [value isKindOfClass:[NSString class]])) record[name]=value;
        }
        if (record.count) [records addObject:record];
    }
    return records;
}
+ (NSString *)errorText:(NSDictionary *)json status:(NSInteger)status analytics:(BOOL)analytics
{
    NSDictionary *error=TBDict(json[@"error"]);NSString *reason=TBStr(TBDict([TBArr(error[@"errors"]) firstObject])[@"reason"]);
    if (status==401) return L(@"Your Google sign-in has expired. Sign in again in Account settings.");
    if ([reason isEqualToString:@"accessNotConfigured"] || [reason isEqualToString:@"serviceDisabled"]) return analytics ? L(@"Enable YouTube Analytics API in the Google Cloud project used for this sign-in.") : L(@"Enable YouTube Data API v3 in the Google Cloud project used for this sign-in.");
    if (status==403) return analytics ? L(@"This sign-in cannot read channel analytics. Connect a Google client authorized for YouTube Analytics.") : L(@"This sign-in cannot read your channel. Check the Google client's YouTube access.");
    return TBStr(error[@"message"]) ?: L(@"The report could not be loaded. Try again.");
}
+ (void)completeDashboard:(NSMutableDictionary *)result token:(NSString *)token outer:(TBHTTPTask *)outer children:(NSMutableArray *)children completion:(void (^)(NSDictionary *))completion
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
        result[@"videoTitles"]=titles;finish();
    }];
    @synchronized(children){[children addObject:task];}
}
+ (TBHTTPTask *)dashboardForDays:(NSInteger)days completion:(void (^)(NSDictionary *))completion
{
    if (days!=7 && days!=28 && days!=90) days=28;
    TBHTTPTask *outer=[[TBHTTPTask alloc] init];
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
        NSString *metrics=@"views,estimatedMinutesWatched,averageViewDuration,likes,comments,subscribersGained,subscribersLost";
        NSDictionary *base=@{@"ids":@"channel==MINE",@"startDate":result[@"startDate"],@"endDate":result[@"endDate"]};
        NSMutableDictionary *summary=[base mutableCopy];summary[@"metrics"]=metrics;
        NSMutableDictionary *daily=[base mutableCopy];daily[@"metrics"]=@"views,estimatedMinutesWatched,subscribersGained,subscribersLost";daily[@"dimensions"]=@"day";daily[@"sort"]=@"day";
        NSMutableDictionary *top=[base mutableCopy];top[@"metrics"]=@"views,estimatedMinutesWatched,averageViewDuration";top[@"dimensions"]=@"video";top[@"sort"]=@"-views";top[@"maxResults"]=@"10";
        NSArray *requests=@[
            @{@"key":@"channel",@"url":@"https://www.googleapis.com/youtube/v3/channels",@"query":@{@"part":@"snippet,statistics,contentDetails",@"mine":@"true"}},
            @{@"key":@"summary",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":summary},
            @{@"key":@"daily",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":daily},
            @{@"key":@"topVideos",@"url":@"https://youtubeanalytics.googleapis.com/v2/reports",@"query":top}];
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
