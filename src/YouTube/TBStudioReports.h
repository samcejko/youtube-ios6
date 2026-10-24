#import <Foundation/Foundation.h>
@interface TBStudioReports : NSObject
+ (NSArray *)records:(id)report;
+ (NSArray *)dimensions;
+ (NSDictionary *)queryForDimension:(NSString *)dimension days:(NSInteger)days video:(NSString *)videoId now:(NSDate *)now;
+ (NSDictionary *)previousQueryForDashboard:(NSDictionary *)dashboard;
+ (NSNumber *)number:(id)value;
+ (NSArray *)comparisonRows:(NSDictionary *)dashboard;
+ (NSString *)CSVForRows:(NSArray *)rows columns:(NSArray *)columns;
@end
