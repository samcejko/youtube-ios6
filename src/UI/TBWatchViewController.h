#import <UIKit/UIKit.h>
#import "TBModels.h"

@class TBPlaybackSession;

// Watching a video: the player on top, below it the title, the channel, the actions, the description, the comments
// and the related videos. Presented full screen; a tapped related video loads into the same screen.
@interface TBWatchViewController : UIViewController

- (instancetype)initWithVideo:(TBVideo *)video;
// Re-opening a video whose player is still running in the mini player: the live AVPlayer is adopted, nothing reloads
- (instancetype)initWithSession:(TBPlaybackSession *)session;

// The videos that follow this one (a playlist): "next" takes the following entry
@property (nonatomic, strong) NSArray *queue;
@property (nonatomic) NSUInteger queueIndex;

- (void)loadVideo:(TBVideo *)video;
- (void)seekToSeconds:(NSTimeInterval)seconds;
// The speed menu's choice (0.5-2): applied now and kept for the next videos
- (void)choosePlaybackRate:(float)rate;
// What a finger held on the picture does (2x while held), for the debug "hold" command
- (void)debugHoldFastForward:(BOOL)holding;
// The player's state in one line (rate, position, tracks, buffered ranges) for the debug "stats" command
- (NSString *)playbackDebugDescription;

@end
