#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@class TBPlayerView;

@protocol TBPlayerViewDelegate <NSObject>
- (void)playerViewDidTapPlayPause:(TBPlayerView *)view;
- (void)playerViewDidTapClose:(TBPlayerView *)view;
- (void)playerViewDidTapQuality:(TBPlayerView *)view fromView:(UIView *)anchor;
- (void)playerViewDidTapChat:(TBPlayerView *)view;
- (void)playerViewDidTapFullscreen:(TBPlayerView *)view;
- (void)playerViewDidTapChannel:(TBPlayerView *)view;
- (void)playerView:(TBPlayerView *)view didSeekToFraction:(double)fraction;    // videos and clips
- (void)playerView:(TBPlayerView *)view didSkipSeconds:(double)seconds;        // -10 / +10
- (void)playerViewDidTapGoLive:(TBPlayerView *)view;                            // live: back to the live edge
@optional
- (void)playerViewDidTapMinimize:(TBPlayerView *)view;                          // shrink to the floating mini player
@end

// The video (AVPlayerLayer) with the controls drawn over it: a top bar with the title and the quality, a bottom bar
// with play/pause, LIVE or the time slider, chat and full screen buttons, a spinner and messages in the middle.
// The controls hide by themselves after a few seconds; a tap shows them again.
@interface TBPlayerView : UIView

@property (nonatomic, weak) id<TBPlayerViewDelegate> delegate;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, readonly) AVPlayerLayer *playerLayer;

@property (nonatomic) BOOL isLive;                   // LIVE badge instead of the slider
@property (nonatomic) BOOL playing;                  // the play/pause button's state
@property (nonatomic) BOOL fullscreen;               // the button's state
@property (nonatomic) BOOL chatVisible;
@property (nonatomic) BOOL chatButtonHidden;         // (no chat for clips)
@property (nonatomic) BOOL closeIsBack;              // a chevron instead of an X (a stack behind this screen)
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;      // channel · game
@property (nonatomic, copy) NSString *qualityTitle;
@property (nonatomic, copy) NSString *statusText;    // viewers · uptime, or the position in a video
@property (nonatomic) BOOL adBreak;                  // shows a small "Ad" note

- (void)setBuffering:(BOOL)buffering;                // spinner in the middle
- (void)showMessage:(NSString *)text retryTitle:(NSString *)retry;   // an error with a button; nil hides it
@property (nonatomic, copy) dispatch_block_t retryHandler;
- (void)setProgress:(double)fraction duration:(NSTimeInterval)duration position:(NSTimeInterval)position;   // videos
- (void)showControls:(BOOL)show animated:(BOOL)animated;
- (void)showControlsBriefly;
@property (nonatomic, readonly) BOOL controlsVisible;
@property (nonatomic) BOOL controlsLocked;           // stay visible (while paused, while an error shows)
@property (nonatomic) CGFloat topInset;              // room for the status bar

// Double-tap to skip, a vertical drag for brightness (left) / volume (right). Off by default (shorts keep their own
// swipe); the watch screen turns it on.
@property (nonatomic) BOOL advancedGesturesEnabled;
@property (nonatomic) BOOL minimizeButtonHidden;     // the watch screen hides it for live streams

// The chapters' boundaries as fractions of the duration (0..1) and their titles; nil clears them
- (void)setChapterFractions:(NSArray *)fractions titles:(NSArray *)titles;

@end
