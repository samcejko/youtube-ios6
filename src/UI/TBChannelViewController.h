#import <UIKit/UIKit.h>
#import "TBGridViewController.h"
#import "TBModels.h"

// A channel: banner, avatar, name, subscribers and the Subscribe button on top, then the videos / shorts / live
// streams / playlists of the tab chosen with the segmented control
@interface TBChannelViewController : TBGridViewController
- (instancetype)initWithChannel:(TBChannel *)channel;
@end
