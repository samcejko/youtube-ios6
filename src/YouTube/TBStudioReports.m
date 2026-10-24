#import "TBStudioReports.h"
#import <math.h>
static NSString *String(id v){return [v isKindOfClass:[NSString class]]?v:nil;}
static NSDateFormatter *Format(void){NSDateFormatter *f=[[NSDateFormatter alloc] init];f.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];f.timeZone=[NSTimeZone timeZoneWithName:@"America/Los_Angeles"];f.dateFormat=@"yyyy-MM-dd";f.lenient=NO;return f;}
static NSDate *Shift(NSDate *date,NSInteger days){NSCalendar *c=[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];c.timeZone=[NSTimeZone timeZoneWithName:@"America/Los_Angeles"];NSDateComponents *d=[[NSDateComponents alloc] init];d.day=days;return [c dateByAddingComponents:d toDate:date options:0];}
@implementation TBStudioReports
+ (NSNumber *)number:(id)value {
    if(![value isKindOfClass:[NSNumber class]] && ![value isKindOfClass:[NSString class]])return nil;
    double n=0;if([value isKindOfClass:[NSString class]]){NSScanner *scan=[NSScanner scannerWithString:value];scan.locale=@{@"NSDecimalSeparator":@"."};if(![scan scanDouble:&n] || !scan.isAtEnd)return nil;}else n=[value doubleValue];return isfinite(n)?@(n):nil;
}
+ (NSArray *)records:(id)report {
    if(![report isKindOfClass:[NSDictionary class]] || ![report[@"columnHeaders"] isKindOfClass:[NSArray class]] || ![report[@"rows"] isKindOfClass:[NSArray class]])return @[];
    NSArray *columns=report[@"columnHeaders"];NSMutableArray *rows=[NSMutableArray array];
    for(id row in report[@"rows"]){if(![row isKindOfClass:[NSArray class]] || [row count]!=columns.count)continue;NSMutableDictionary *record=[NSMutableDictionary dictionary];BOOL valid=YES;
        for(NSUInteger i=0;i<columns.count;i++){NSDictionary *column=[columns[i] isKindOfClass:[NSDictionary class]]?columns[i]:nil;NSString *key=String(column[@"name"]);id value=row[i];if(!key.length || record[key] || (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]])){valid=NO;break;}if([column[@"columnType"] isEqualToString:@"METRIC"] && ![self number:value]){valid=NO;break;}record[key]=value;}
        if(valid && record.count)[rows addObject:record];
    }return rows;
}
+ (NSArray *)dimensions {return @[@"country",@"deviceType",@"operatingSystem",@"insightTrafficSourceType",@"subscribedStatus",@"creatorContentType",@"insightPlaybackLocationType"];}
+ (NSDictionary *)queryForDimension:(NSString *)dimension days:(NSInteger)days video:(NSString *)videoId now:(NSDate *)now {
    if(![[self dimensions] containsObject:dimension])return nil;if(days!=7 && days!=28 && days!=90)days=28;
    if(videoId.length && (videoId.length!=11 || [videoId rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"] invertedSet]].location!=NSNotFound))return nil;
    NSDateFormatter *f=Format();NSDate *today=now ?: [NSDate date];NSMutableDictionary *q=[@{@"ids":@"channel==MINE",@"startDate":[f stringFromDate:Shift(today,1-days)],@"endDate":[f stringFromDate:today],@"dimensions":dimension,@"metrics":@"views,estimatedMinutesWatched",@"sort":@"-views",@"maxResults":@"25"} mutableCopy];if(videoId.length)q[@"filters"]=[@"video==" stringByAppendingString:videoId];return q;
}
+ (NSArray *)queriesForDimension:(NSString *)dimension days:(NSInteger)days video:(NSString *)videoId now:(NSDate *)now {
    NSDictionary *base=[self queryForDimension:dimension days:days video:videoId now:now];if(!base)return @[];
    if(![dimension isEqualToString:@"subscribedStatus"])return @[base];
    // Filtered aggregates avoid a server error returned by some channels for the grouped report.
    NSMutableArray *queries=[NSMutableArray array];for(NSString *status in @[@"SUBSCRIBED",@"UNSUBSCRIBED"]){NSMutableDictionary *q=[base mutableCopy];[q removeObjectsForKeys:@[@"dimensions",@"sort",@"maxResults"]];NSString *filter=[@"subscribedStatus==" stringByAppendingString:status];q[@"filters"]=q[@"filters"]?[q[@"filters"] stringByAppendingFormat:@";%@",filter]:filter;[queries addObject:@{@"query":q,@"status":status}];}return queries;
}
+ (NSDictionary *)previousQueryForDashboard:(NSDictionary *)dashboard {
    NSArray *daily=[dashboard[@"daily"] isKindOfClass:[NSArray class]]?dashboard[@"daily"]:nil;NSString *last=nil;
    for(id row in daily)if([row isKindOfClass:[NSDictionary class]]){NSString *day=String(row[@"day"]);if(day.length==10 && (!last || [day compare:last]==NSOrderedDescending))last=day;}
    NSDateFormatter *f=Format();NSString *start=String(dashboard[@"startDate"]),*end=String(dashboard[@"endDate"]);NSDate *begin=[f dateFromString:start ?: @""],*finish=[f dateFromString:last ?: @""];
    NSInteger days=[dashboard[@"days"] integerValue];if(!begin || !finish || !end || (days!=7 && days!=28 && days!=90) || [last compare:start]==NSOrderedAscending || [last compare:end]==NSOrderedDescending)return nil;
    NSMutableDictionary *q=[@{@"ids":@"channel==MINE",@"startDate":[f stringFromDate:Shift(begin,-days)],@"endDate":[f stringFromDate:Shift(finish,-days)],@"metrics":@"views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage,likes,comments,shares,subscribersGained,subscribersLost"} mutableCopy];NSString *video=String(dashboard[@"videoId"]);if(video.length)q[@"filters"]=[@"video==" stringByAppendingString:video];return q;
}
+ (NSArray *)comparisonRows:(NSDictionary *)dashboard {
    NSArray *a=[dashboard[@"summary"] isKindOfClass:[NSArray class]]?dashboard[@"summary"]:nil,*b=[dashboard[@"previousSummary"] isKindOfClass:[NSArray class]]?dashboard[@"previousSummary"]:nil;
    NSDictionary *current=[a.firstObject isKindOfClass:[NSDictionary class]]?a.firstObject:nil,*previous=[b.firstObject isKindOfClass:[NSDictionary class]]?b.firstObject:nil;NSMutableArray *result=[NSMutableArray array];
    for(NSString *key in @[@"views",@"estimatedMinutesWatched",@"averageViewDuration",@"averageViewPercentage",@"likes",@"comments",@"shares",@"subscribersGained",@"subscribersLost"]){NSNumber *now=[self number:current[key]],*old=[self number:previous[key]];if(!now || !old)continue;NSMutableDictionary *row=[@{@"metric":key,@"current":now,@"previous":old,@"change":@(now.doubleValue-old.doubleValue)} mutableCopy];if(old.doubleValue!=0)row[@"percentage"]=@((now.doubleValue-old.doubleValue)/fabs(old.doubleValue)*100);[result addObject:row];}return result;
}
+ (NSString *)CSVForRows:(NSArray *)rows columns:(NSArray *)columns {
    NSMutableArray *lines=[NSMutableArray array];NSMutableArray *all=[NSMutableArray arrayWithObject:columns];for(NSDictionary *row in rows){NSMutableArray *values=[NSMutableArray array];for(NSString *key in columns)[values addObject:row[key] ?: @""];[all addObject:values];}
    for(NSArray *values in all){NSMutableArray *quoted=[NSMutableArray array];for(id value in values){NSString *text=[value description];if([value isKindOfClass:[NSString class]]){NSString *trim=[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];if(trim.length && [@"=+-@" rangeOfString:[trim substringToIndex:1]].location!=NSNotFound)text=[@"'" stringByAppendingString:text];}[quoted addObject:[NSString stringWithFormat:@"\"%@\"",[text stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]]];}[lines addObject:[quoted componentsJoinedByString:@","]];}return [[lines componentsJoinedByString:@"\r\n"] stringByAppendingString:@"\r\n"];
}
@end
