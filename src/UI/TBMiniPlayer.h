#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TBModels.h"
#import "TBPlayback.h"

// A snapshot of a playing video handed between the full watch screen and the floating mini player. It carries the live
// AVPlayer itself, so the sound and picture never stop as the two trade it back and forth.
@interface TBPlaybackSession : NSObject
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) TBVideo *video;
@property (nonatomic, strong) TBPlaybackSource *source;
@property (nonatomic, strong) NSArray *queue;
@property (nonatomic) NSUInteger queueIndex;
@property (nonatomic, copy) NSString *quality;
@property (nonatomic, strong) TBVariant *currentVariant;
@property (nonatomic) double position;
@property (nonatomic) BOOL wantsToPlay;
@property (nonatomic) NSUInteger proxyGeneration;
@end

// A small floating bar (its own window above the app) that keeps a video playing after the watch screen is minimised.
// Tapping the picture or the title opens the watch screen again with the very same player; the X stops it.
@interface TBMiniPlayer : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL active;
// Called when the bar is tapped to expand; it receives the session (already detached) and should open a watch screen.
@property (nonatomic, copy) void (^onExpand)(TBPlaybackSession *session);

- (void)showSession:(TBPlaybackSession *)session;   // adopt a session and float the bar
- (TBPlaybackSession *)detachSession;               // hand the session back (for expand): hide the bar, keep playing
- (void)dismiss;                                     // stop and clear

@end
