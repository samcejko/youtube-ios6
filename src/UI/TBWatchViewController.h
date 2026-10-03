#import <UIKit/UIKit.h>
#import "TBModels.h"

// Watching a video: the player on top, below it the title, the channel, the actions, the description, the comments
// and the related videos. Presented full screen; a tapped related video loads into the same screen.
@interface TBWatchViewController : UIViewController

- (instancetype)initWithVideo:(TBVideo *)video;

// The videos that follow this one (a playlist): "next" takes the following entry
@property (nonatomic, strong) NSArray *queue;
@property (nonatomic) NSUInteger queueIndex;

- (void)loadVideo:(TBVideo *)video;
- (void)seekToSeconds:(NSTimeInterval)seconds;

@end
