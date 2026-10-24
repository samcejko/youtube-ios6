#import <UIKit/UIKit.h>
@interface TBStudioReportViewController : UITableViewController
- (instancetype)initWithDimension:(NSString *)dimension title:(NSString *)title days:(NSInteger)days video:(NSString *)videoId;
- (instancetype)initWithComparison:(NSDictionary *)dashboard;
@end
