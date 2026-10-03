#import <UIKit/UIKit.h>

// The comments of a video (or the replies to one comment): a paged table, a tap on a comment with replies opens them
@interface TBCommentsViewController : UITableViewController
- (instancetype)initWithToken:(NSString *)token title:(NSString *)title;
// The video the comments belong to (lets a signed-in account post a top-level comment)
@property (nonatomic, copy) NSString *videoId;
// Set on a replies screen: the parent comment's id (lets a signed-in account post a reply)
@property (nonatomic, copy) NSString *replyParentId;
@end
