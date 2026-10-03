#import <UIKit/UIKit.h>

// The shorts player: one short fills the screen, a swipe up brings the next, a swipe down the previous, a tap pauses.
// Presented full screen.
@interface TBShortsViewController : UIViewController
- (instancetype)initWithVideos:(NSArray *)videos startingAt:(NSUInteger)index;
- (void)showVideos:(NSArray *)videos startingAt:(NSUInteger)index;
@end
