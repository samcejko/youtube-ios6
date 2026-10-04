#import "TBMiniPlayer.h"
#import "TBMediaProxy.h"
#import "TBSettings.h"
#import "TBLibrary.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import "TBInnertube.h"
#import <AVFoundation/AVFoundation.h>

@implementation TBPlaybackSession
@end

#pragma mark - Views

// A view whose layer shows the video
@interface TBMiniVideoView : UIView
@end
@implementation TBMiniVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

// The floating window: taps on empty space fall through to the app underneath
@interface TBMiniWindow : UIWindow
@end
@implementation TBMiniWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}
@end

#pragma mark - Mini player

@interface TBMiniPlayer ()
@property (nonatomic, strong) TBMiniWindow *window;
@property (nonatomic, strong) UIView *container;   // rotated by hand so the bar follows the device
@property (nonatomic, strong) UIView *bar;
@property (nonatomic, strong) UIView *hairline;
@property (nonatomic, strong) TBMiniVideoView *videoHost;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) TBPlaybackSession *session;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) NSInteger ticks;
@end

@implementation TBMiniPlayer

+ (instancetype)shared
{
    static TBMiniPlayer *mini;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mini = [[TBMiniPlayer alloc] init]; });
    return mini;
}

- (AVPlayerLayer *)videoLayer { return (AVPlayerLayer *)self.videoHost.layer; }

- (void)buildIfNeeded
{
    if (self.window) return;
    self.window = [[TBMiniWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.windowLevel = UIWindowLevelNormal + 1;
    self.window.backgroundColor = [UIColor clearColor];

    self.container = [[UIView alloc] initWithFrame:self.window.bounds];
    self.container.backgroundColor = [UIColor clearColor];
    [self.window addSubview:self.container];

    self.bar = [[UIView alloc] initWithFrame:CGRectZero];
    self.bar.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.bar.clipsToBounds = YES;
    [self.container addSubview:self.bar];

    self.hairline = [[UIView alloc] initWithFrame:CGRectZero];
    self.hairline.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [self.bar addSubview:self.hairline];

    self.videoHost = [[TBMiniVideoView alloc] initWithFrame:CGRectZero];
    self.videoHost.backgroundColor = [UIColor blackColor];
    [self videoLayer].videoGravity = AVLayerVideoGravityResizeAspect;
    self.videoHost.userInteractionEnabled = YES;
    [self.bar addSubview:self.videoHost];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.titleLabel.numberOfLines = 2;
    self.titleLabel.userInteractionEnabled = YES;
    [self.bar addSubview:self.titleLabel];

    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[[TBTheme shared] playIcon] forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playPauseTapped) forControlEvents:UIControlEventTouchUpInside];
    self.playButton.showsTouchWhenHighlighted = YES;
    self.playButton.accessibilityLabel = L(@"Play");
    [self.bar addSubview:self.playButton];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeButton setImage:[[TBTheme shared] closeIconWhite] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    self.closeButton.showsTouchWhenHighlighted = YES;
    self.closeButton.accessibilityLabel = L(@"Close");
    [self.bar addSubview:self.closeButton];

    for (UIView *v in @[ self.videoHost, self.titleLabel ]) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(expandTapped)];
        [v addGestureRecognizer:tap];
    }
}

// The window stays in fixed (portrait) coordinates; the container is rotated to match the interface
- (void)layoutForOrientation
{
    if (!self.container) return;
    UIInterfaceOrientation o = [UIApplication sharedApplication].statusBarOrientation;
    CGFloat angle = 0;
    if (o == UIInterfaceOrientationLandscapeLeft) angle = -M_PI_2;
    else if (o == UIInterfaceOrientationLandscapeRight) angle = M_PI_2;
    else if (o == UIInterfaceOrientationPortraitUpsideDown) angle = M_PI;
    CGSize screen = [UIScreen mainScreen].bounds.size;   // portrait: width < height
    BOOL landscape = UIInterfaceOrientationIsLandscape(o);
    CGSize size = landscape ? CGSizeMake(screen.height, screen.width) : screen;
    self.container.bounds = CGRectMake(0, 0, size.width, size.height);
    self.container.transform = CGAffineTransformMakeRotation(angle);
    self.container.center = CGPointMake(screen.width / 2, screen.height / 2);
    [self layoutBar];
}

- (void)layoutBar
{
    CGFloat W = self.container.bounds.size.width, H = self.container.bounds.size.height;
    CGFloat barH = 62, tabBar = 49;
    self.bar.frame = CGRectMake(0, H - tabBar - barH, W, barH);
    self.hairline.frame = CGRectMake(0, 0, W, 0.5);
    CGFloat videoW = floor(barH * 16.0 / 9.0);
    self.videoHost.frame = CGRectMake(0, 0, videoW, barH);
    CGFloat rightX = W;
    self.closeButton.frame = CGRectMake(rightX - 46, (barH - 44) / 2, 44, 44); rightX -= 46;
    self.playButton.frame = CGRectMake(rightX - 46, (barH - 44) / 2, 44, 44); rightX -= 46;
    self.titleLabel.frame = CGRectMake(videoW + 10, 0, MAX(0, rightX - videoW - 18), barH);
}

#pragma mark - Show / detach / dismiss

- (void)showSession:(TBPlaybackSession *)session
{
    if (!session.player) return;
    if (_active) [self dismiss];
    self.session = session;
    [self buildIfNeeded];
    [self videoLayer].player = session.player;
    self.titleLabel.text = session.video.title ?: @"";
    self.window.hidden = NO;
    [self layoutForOrientation];
    [self updatePlayPauseIcon];
    [self startTimer];
    [self observe];
    _active = YES;
    if (session.wantsToPlay && session.player.rate < 0.01) [session.player play];
}

- (TBPlaybackSession *)detachSession
{
    TBPlaybackSession *s = self.session;
    if (s.player) {
        double pos = CMTimeGetSeconds(s.player.currentTime);
        if (!isnan(pos)) s.position = pos;
        s.wantsToPlay = s.player.rate > 0.01;
    }
    [self savePosition];
    [self stopTimer];
    [self unobserve];
    [self videoLayer].player = nil;
    self.window.hidden = YES;
    self.session = nil;
    _active = NO;
    return s;   // the player keeps running; the caller reattaches it to a new screen
}

- (void)dismiss
{
    if (self.session) {
        [self savePosition];
        [self.session.player pause];
    }
    [self stopTimer];
    [self unobserve];
    [self videoLayer].player = nil;
    self.window.hidden = YES;
    self.session = nil;
    _active = NO;
}

#pragma mark - Controls

- (void)playPauseTapped
{
    AVPlayer *p = self.session.player;
    if (!p) return;
    if (p.rate > 0.01) { [p pause]; self.session.wantsToPlay = NO; }
    else { [p play]; self.session.wantsToPlay = YES; }
    [self updatePlayPauseIcon];
}

- (void)closeTapped { [self dismiss]; }

- (void)expandTapped
{
    if (!self.session) return;
    void (^expand)(TBPlaybackSession *) = self.onExpand;
    TBPlaybackSession *s = [self detachSession];
    if (expand) expand(s);
    else [s.player pause];
}

- (void)updatePlayPauseIcon
{
    BOOL playing = self.session.player.rate > 0.01;
    [self.playButton setImage:playing ? [[TBTheme shared] pauseIcon] : [[TBTheme shared] playIcon] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = playing ? L(@"Pause") : L(@"Play");
}

#pragma mark - Timer

- (void)startTimer
{
    [self stopTimer];
    self.ticks = 0;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)stopTimer { [self.timer invalidate]; self.timer = nil; }

- (void)tick
{
    [self updatePlayPauseIcon];
    self.ticks++;
    if (self.ticks % 30 == 0) [self savePosition];   // ~15 s
}

- (void)savePosition
{
    AVPlayer *p = self.session.player;
    NSString *videoId = self.session.video.videoId;
    if (!p || !videoId.length || self.session.source.isLive) return;
    double pos = CMTimeGetSeconds(p.currentTime);
    if (pos > 0 && !isnan(pos)) {
        [TBSettings setResumePosition:pos forVideo:videoId];
        [[TBLibrary shared] updatePosition:pos forVideo:videoId];
        if (self.session.source.info) {
            [TBInnertube reportWatchtime:self.session.source.info position:pos isPaused:(p.rate < 0.01) isFinished:NO];
        }
    }
}

#pragma mark - Notifications

- (void)observe
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.session.player.currentItem];
    [nc addObserver:self selector:@selector(didBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(willForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(orientationChanged) name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
}

- (void)unobserve { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)orientationChanged { [self layoutForOrientation]; }

- (void)itemEnded:(NSNotification *)note
{
    NSString *videoId = self.session.video.videoId;
    if (videoId.length) {
        [TBSettings setResumePosition:0 forVideo:videoId];
        [[TBLibrary shared] updatePosition:0 forVideo:videoId];
        if (self.session.source.info) {
            NSTimeInterval dur = self.session.source.info.lengthSeconds > 0 ? self.session.source.info.lengthSeconds : CMTimeGetSeconds(self.session.player.currentTime);
            [TBInnertube reportWatchtime:self.session.source.info position:dur isPaused:YES isFinished:YES];
        }
    }
    [self dismiss];
}

- (void)didBackground
{
    AVPlayer *p = self.session.player;
    if (!p) return;
    if (p.rate > 0.01 && [TBSettings backgroundAudio]) {
        [self videoLayer].player = nil;   // without a layer iOS lets the sound carry on
        __weak TBMiniPlayer *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TBMiniPlayer *s = weakSelf;
            if (s.session.wantsToPlay && s.session.player.rate < 0.01) [s.session.player play];
        });
    } else if (p.rate > 0.01) {
        [p pause];
    }
    [self savePosition];
}

- (void)willForeground
{
    if (!self.session.player) return;
    [self videoLayer].player = self.session.player;
    [[TBMediaProxy shared] ensureRunning];
    if (self.session.wantsToPlay && self.session.player.rate < 0.01) [self.session.player play];
}

@end
