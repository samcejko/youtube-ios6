#import <UIKit/UIKit.h>
#import "TBGridViewController.h"
#import "TBModels.h"

// A playlist: its picture, name, owner and count on top, the videos below; a tapped video plays on through the list
@interface TBPlaylistViewController : TBGridViewController
- (instancetype)initWithPlaylist:(TBPlaylist *)playlist;
@end
