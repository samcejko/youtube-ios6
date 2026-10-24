#import <Foundation/Foundation.h>
#import "TBStudioReports.h"
#import <math.h>
int main(void){@autoreleasepool{
    NSArray *columns=@[@{@"name":@"country",@"columnType":@"DIMENSION"},@{@"name":@"views",@"columnType":@"METRIC"}];
    NSArray *rows=[TBStudioReports records:@{@"columnHeaders":columns,@"rows":@[@[@"CZ",@12],@[@"US",@"bad"],@[@"DE",[NSNull null]],@[@"FR"]]}];
    NSCAssert((rows.count==1 && [rows[0][@"views"] integerValue]==12),@"Malformed/missing metric rows cannot become zero-valued data");
    NSCAssert((![TBStudioReports number:@(INFINITY)] && ![TBStudioReports number:@"not-a-number"] && [TBStudioReports number:@"0"]),@"Only finite metrics, including real zero, are accepted");
    NSDictionary *dashboard=@{@"days":@28,@"startDate":@"2026-10-01",@"endDate":@"2026-10-28",@"daily":@[@{@"day":@"2026-10-25"}],@"videoId":@"jNQXAC9IVRw"};
    NSDictionary *query=[TBStudioReports previousQueryForDashboard:dashboard];
    NSCAssert(([query[@"startDate"] isEqualToString:@"2026-09-03"] && [query[@"endDate"] isEqualToString:@"2026-09-27"] && [query[@"filters"] isEqualToString:@"video==jNQXAC9IVRw"]),@"Compare matching available days, not a full earlier period against incomplete current data");
    NSCAssert((![TBStudioReports previousQueryForDashboard:@{@"days":@7,@"startDate":@"2026-10-01",@"endDate":@"2026-10-07",@"daily":@[]}]),@"Unknown reporting cutoff cannot produce a fabricated comparison");
    NSArray *comparison=[TBStudioReports comparisonRows:@{@"summary":@[@{@"views":@7,@"shares":@0}],@"previousSummary":@[@{@"views":@0,@"shares":@2}]}];
    NSCAssert((comparison.count==2 && !comparison[0][@"percentage"] && [comparison[1][@"percentage"] doubleValue]==-100),@"Zero baseline cannot produce infinite percentages");
    NSString *csv=[TBStudioReports CSVForRows:@[@{@"name":@"=unsafe,\"text\"\nnext",@"value":@(-3)}] columns:@[@"name",@"value"]];
    NSCAssert(([csv rangeOfString:@"\"'=unsafe,\"\"text\"\"\nnext\""].location!=NSNotFound && [csv rangeOfString:@"\"-3\""].location!=NSNotFound),@"CSV must quote line breaks and quotes, protect string formulas and preserve numeric negatives");
    for(NSString *dimension in [TBStudioReports dimensions])NSCAssert(([TBStudioReports queryForDimension:dimension days:28 video:nil now:nil]),@"Known report must have a request");
    NSCAssert((![TBStudioReports queryForDimension:@"arbitrary" days:28 video:nil now:nil] && ![TBStudioReports queryForDimension:@"country" days:28 video:@"bad;other==filter" now:nil]),@"Report and video filters are bounded to supported inputs");
    NSLog(@"Studio report validation, matching-day comparison, zero baselines and CSV checks passed");
}return 0;}
