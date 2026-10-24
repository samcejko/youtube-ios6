#import <UIKit/UIKit.h>

// Only instantiated where UIKit has no UIRefreshControl (iOS 5).
@interface TBRefreshControl : UIControl
@property(nonatomic, readonly, getter=isRefreshing) BOOL refreshing;
@property(nonatomic, strong) UIColor *tintColor;
- (void)endRefreshing;
- (void)trackScrollView:(UIScrollView *)scrollView released:(BOOL)released;
@end
