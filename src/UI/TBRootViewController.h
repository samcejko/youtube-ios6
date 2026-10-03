#import <UIKit/UIKit.h>

// The tab bar: Home, Subscriptions, Shorts, Search, Library
@interface TBRootViewController : UITabBarController
- (void)applyTheme;
- (void)searchFor:(NSString *)query;        // the tubie:search?q= link
- (void)selectTab:(NSInteger)index;
@end
