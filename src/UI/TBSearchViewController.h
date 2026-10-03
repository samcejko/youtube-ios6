#import <UIKit/UIKit.h>

// The search tab: a search bar with suggestions and recent searches, the results as a grid with a filter
// (everything, videos, channels, playlists, live)
@interface TBSearchViewController : UIViewController
- (void)searchFor:(NSString *)text;   // (the tubie:search?q= link)
@end
