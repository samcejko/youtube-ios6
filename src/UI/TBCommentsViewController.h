#import <UIKit/UIKit.h>

// The comments of a video (or the replies to one comment): a paged table, a tap on a comment with replies opens them
@interface TBCommentsViewController : UITableViewController
- (instancetype)initWithToken:(NSString *)token title:(NSString *)title;
@end
