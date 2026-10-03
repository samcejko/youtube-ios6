#import "TBShortsViewController.h"
#import "TBNavigator.h"
#import "TBPlayback.h"
#import "TBLibrary.h"
#import "TBMediaProxy.h"
#import "TBImageLoader.h"
#import "TBSettings.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

static void *TBShortStatusContext = &TBShortStatusContext;

@interface TBShortLayerView : UIView
@end
@implementation TBShortLayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface TBShortsViewController ()
@property (nonatomic, strong) NSArray *videos;
@property (nonatomic) NSUInteger index;
@property (nonatomic, strong) TBShortLayerView *videoView;
@property (nonatomic, strong) UIImageView *poster;
@property (nonatomic, strong) UIImageView *shade;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *channelButton;
@property (nonatomic, strong) UILabel *viewsLabel;
@property (nonatomic, strong) UILabel *counterLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressBar;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIImageView *pausedBadge;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) TBHTTPTask *loadTask;
@property (nonatomic, strong) TBHTTPTask *preloadTask;
@property (nonatomic, strong) TBPlaybackSource *nextSource;
@property (nonatomic, copy) NSString *nextSourceId;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic) BOOL paused;
@property (nonatomic) NSUInteger loadGeneration;
@end

@implementation TBShortsViewController

- (instancetype)initWithVideos:(NSArray *)videos startingAt:(NSUInteger)index
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videos = videos ?: @[];
        _index = MIN(index, videos.count ? videos.count - 1 : 0);
        self.wantsFullScreenLayout = YES;
    }
    return self;
}

- (void)dealloc
{
    [self teardown];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    TBTheme *t = [TBTheme shared];

    self.poster = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.poster.contentMode = UIViewContentModeScaleAspectFit;
    self.poster.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.poster];

    self.videoView = [[TBShortLayerView alloc] initWithFrame:self.view.bounds];
    self.videoView.backgroundColor = [UIColor clearColor];
    self.videoView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    ((AVPlayerLayer *)self.videoView.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    [self.view addSubview:self.videoView];

    self.shade = [[UIImageView alloc] initWithImage:[t controlsGradientImageTop:NO]];
    [self.view addSubview:self.shade];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.closeButton setImage:[t closeIconWhite] forState:UIControlStateNormal];
    self.closeButton.accessibilityLabel = L(@"Close");
    self.closeButton.showsTouchWhenHighlighted = YES;
    [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.closeButton];

    self.counterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.counterLabel.backgroundColor = [UIColor clearColor];
    self.counterLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    self.counterLabel.font = [UIFont boldSystemFontOfSize:13];
    self.counterLabel.textAlignment = NSTextAlignmentRight;
    self.counterLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
    self.counterLabel.shadowOffset = CGSizeMake(0, 1);
    [self.view addSubview:self.counterLabel];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.backgroundColor = [UIColor clearColor];
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.titleLabel.numberOfLines = 3;
    self.titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
    self.titleLabel.shadowOffset = CGSizeMake(0, 1);
    [self.view addSubview:self.titleLabel];

    self.channelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.channelButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.channelButton.titleLabel.shadowOffset = CGSizeMake(0, 1);
    self.channelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.channelButton setTitleColor:[UIColor colorWithWhite:0.92 alpha:1] forState:UIControlStateNormal];
    [self.channelButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.8] forState:UIControlStateNormal];
    [self.channelButton addTarget:self action:@selector(channelTapped) forControlEvents:UIControlEventTouchUpInside];
    self.channelButton.accessibilityLabel = L(@"Channel");
    [self.view addSubview:self.channelButton];

    self.viewsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.viewsLabel.backgroundColor = [UIColor clearColor];
    self.viewsLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.viewsLabel.font = [UIFont systemFontOfSize:12];
    self.viewsLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
    self.viewsLabel.shadowOffset = CGSizeMake(0, 1);
    [self.view addSubview:self.viewsLabel];

    self.progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
    [self.view addSubview:self.progressTrack];
    self.progressBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressBar.backgroundColor = [t liveColor];
    [self.progressTrack addSubview:self.progressBar];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.pausedBadge = [[UIImageView alloc] initWithImage:[t playIcon]];
    self.pausedBadge.hidden = YES;
    self.pausedBadge.alpha = 0.85;
    [self.view addSubview:self.pausedBadge];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.textColor = [UIColor whiteColor];
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    [self.view addGestureRecognizer:tap];
    UISwipeGestureRecognizer *up = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedUp)];
    up.direction = UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:up];
    UISwipeGestureRecognizer *down = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipedDown)];
    down.direction = UISwipeGestureRecognizerDirectionDown;
    [self.view addGestureRecognizer:down];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:NULL];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self showCurrent];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = [TBSettings keepScreenOn];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
}

- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return TBIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown; }

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    // on the wide iPad screen the picture stays a phone-shaped column in the middle
    CGFloat w = MIN(b.size.width, floor(b.size.height * 9.0 / 16.0) + 40);
    CGFloat x = floor((b.size.width - w) / 2);
    self.shade.frame = CGRectMake(x, b.size.height - 180, w, 180);
    self.closeButton.frame = CGRectMake(x + 6, 10, 44, 44);
    self.counterLabel.frame = CGRectMake(x + w - 110, 22, 100, 20);
    self.viewsLabel.frame = CGRectMake(x + 12, b.size.height - 28, w - 24, 16);
    self.channelButton.frame = CGRectMake(x + 12, b.size.height - 50, w - 24, 20);
    CGSize ts = [self.titleLabel.text sizeWithFont:self.titleLabel.font constrainedToSize:CGSizeMake(w - 24, 60) lineBreakMode:NSLineBreakByWordWrapping];
    self.titleLabel.frame = CGRectMake(x + 12, b.size.height - 56 - ts.height, w - 24, ts.height);
    self.progressTrack.frame = CGRectMake(x, b.size.height - 3, w, 3);
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    self.pausedBadge.frame = CGRectMake(floor(b.size.width / 2 - 30), floor(b.size.height / 2 - 30), 60, 60);
    self.messageLabel.frame = CGRectMake(x + 20, b.size.height / 2 - 40, w - 40, 80);
}

#pragma mark - Showing

- (void)showVideos:(NSArray *)videos startingAt:(NSUInteger)index
{
    self.videos = videos ?: @[];
    self.index = MIN(index, videos.count ? videos.count - 1 : 0);
    [self showCurrent];
}

- (TBVideo *)current
{
    return self.index < self.videos.count ? self.videos[self.index] : nil;
}

- (void)showCurrent
{
    TBVideo *video = [self current];
    if (!video) return;
    self.loadGeneration++;
    NSUInteger generation = self.loadGeneration;
    [self.loadTask cancel];
    [self detachItem];
    self.paused = NO;
    self.pausedBadge.hidden = YES;
    self.messageLabel.hidden = YES;
    self.progressBar.frame = CGRectMake(0, 0, 0, 3);
    self.titleLabel.text = video.title ?: @"";
    [self.channelButton setTitle:video.channelName.length ? [@"@ " stringByAppendingString:video.channelName] : @"" forState:UIControlStateNormal];
    self.viewsLabel.text = video.viewsText ?: @"";
    self.counterLabel.text = self.videos.count > 1 ? [NSString stringWithFormat:@"%lu / %lu", (unsigned long)self.index + 1, (unsigned long)self.videos.count] : @"";
    [self.view setNeedsLayout];
    // the poster while the video loads
    NSString *posterURL = video.thumbnailURL.length ? video.thumbnailURL : [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/oar2.jpg", video.videoId];
    self.poster.image = nil;
    __weak TBShortsViewController *weakSelf = self;
    [[TBImageLoader shared] loadImage:posterURL maxPixels:720 completion:^(UIImage *image) {
        TBShortsViewController *s = weakSelf;
        if (s && s.loadGeneration == generation && !s.item) s.poster.image = image;
    }];
    [self.spinner startAnimating];
    [[TBLibrary shared] addToHistory:video];

    void (^play)(TBPlaybackSource *) = ^(TBPlaybackSource *source) {
        TBShortsViewController *s = weakSelf;
        if (!s || s.loadGeneration != generation) return;
        if (source.info.title.length) { video.title = source.info.title; s.titleLabel.text = video.title; }
        if (source.info.author.length) { video.channelName = source.info.author; [s.channelButton setTitle:[@"@ " stringByAppendingString:video.channelName] forState:UIControlStateNormal]; }
        if (source.info.channelId.length) video.channelId = source.info.channelId;
        if (!video.viewsText.length && source.info.viewCount > 0) { video.viewsText = [NSString stringWithFormat:L(@"%@ views"), [TBUtils formatCount:(NSInteger)MIN(source.info.viewCount, (long long)NSIntegerMax)]]; s.viewsLabel.text = video.viewsText; }
        [s.view setNeedsLayout];
        NSString *title = nil;
        NSURL *url = [TBPlayback playerURLForSource:source quality:@"720" chosen:NULL title:&title];
        if (!url) { [s showMessage:L(@"This short cannot be played.")]; return; }
        TBLog(@"Short %@: %@", video.videoId, title);
        [s loadItemWithURL:url];
        [s preloadNext];
    };
    if (self.nextSource && [self.nextSourceId isEqualToString:video.videoId]) {
        TBPlaybackSource *ready = self.nextSource;
        self.nextSource = nil;
        self.nextSourceId = nil;
        play(ready);
        return;
    }
    self.loadTask = [TBPlayback sourceForVideo:video.videoId preferProgressive:YES completion:^(TBPlaybackSource *source, NSError *error) {
        TBShortsViewController *s = weakSelf;
        if (!s || s.loadGeneration != generation) return;
        s.loadTask = nil;
        if (error) { [s showMessage:error.localizedDescription]; return; }
        play(source);
    }];
}

- (void)preloadNext
{
    if (self.index + 1 >= self.videos.count) return;
    TBVideo *next = self.videos[self.index + 1];
    if ([self.nextSourceId isEqualToString:next.videoId]) return;
    [self.preloadTask cancel];
    self.nextSource = nil;
    self.nextSourceId = nil;
    __weak TBShortsViewController *weakSelf = self;
    self.preloadTask = [TBPlayback sourceForVideo:next.videoId preferProgressive:YES completion:^(TBPlaybackSource *source, NSError *error) {
        TBShortsViewController *s = weakSelf;
        if (!s) return;
        s.preloadTask = nil;
        if (source) { s.nextSource = source; s.nextSourceId = next.videoId; }
    }];
}

- (void)showMessage:(NSString *)text
{
    [self.spinner stopAnimating];
    self.messageLabel.text = text;
    self.messageLabel.hidden = NO;
    // on to the next one after a moment
    NSUInteger generation = self.loadGeneration;
    __weak TBShortsViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        TBShortsViewController *s = weakSelf;
        if (s && s.loadGeneration == generation && s.index + 1 < s.videos.count) [s swipedUp];
    });
}

#pragma mark - Player

- (void)loadItemWithURL:(NSURL *)url
{
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.item = item;
    [item addObserver:self forKeyPath:@"status" options:0 context:TBShortStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
        self.player.allowsExternalPlayback = NO;
        ((AVPlayerLayer *)self.videoView.layer).player = self.player;
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
    }
    [self.player play];
}

- (void)detachItem
{
    if (!self.item) return;
    @try { [self.item removeObserver:self forKeyPath:@"status" context:TBShortStatusContext]; } @catch (NSException *e) {}
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [self.player pause];
    self.item = nil;
}

- (void)teardown
{
    [self.loadTask cancel]; self.loadTask = nil;
    [self.preloadTask cancel]; self.preloadTask = nil;
    [self.tickTimer invalidate]; self.tickTimer = nil;
    [self detachItem];
    ((AVPlayerLayer *)self.videoView.layer).player = nil;
    self.player = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != TBShortStatusContext) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self observeValueForKeyPath:keyPath ofObject:object change:change context:context]; }); return; }
    if (object != self.item) return;
    if (self.item.status == AVPlayerItemStatusReadyToPlay) {
        [self.spinner stopAnimating];
        self.poster.image = nil;
        if (!self.paused) [self.player play];
    } else if (self.item.status == AVPlayerItemStatusFailed) {
        TBLog(@"Short failed: %@", self.item.error);
        [self showMessage:L(@"This short cannot be played.")];
    }
}

- (void)itemEnded:(NSNotification *)note
{
    // shorts loop
    [self.player seekToTime:kCMTimeZero];
    if (!self.paused) [self.player play];
}

- (void)itemFailed:(NSNotification *)note
{
    [self showMessage:L(@"This short cannot be played.")];
}

- (void)tick
{
    if (!self.item) return;
    double duration = CMTimeGetSeconds(self.item.duration), position = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(duration) || duration <= 0 || isnan(position)) return;
    CGFloat w = self.progressTrack.bounds.size.width;
    self.progressBar.frame = CGRectMake(0, 0, floor(w * MIN(1, position / duration)), 3);
}

#pragma mark - Gestures

- (void)tapped
{
    if (!self.item) return;
    self.paused = !self.paused;
    if (self.paused) [self.player pause]; else [self.player play];
    self.pausedBadge.hidden = !self.paused;
}

- (void)swipedUp
{
    if (self.index + 1 >= self.videos.count) return;
    self.index++;
    [self showCurrent];
}

- (void)swipedDown
{
    if (self.index == 0) return;
    self.index--;
    [self showCurrent];
}

- (void)closeTapped
{
    [self teardown];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)channelTapped
{
    TBVideo *video = [self current];
    if (video.channelId.length) [TBNavigator openChannelId:video.channelId from:self];
}

#pragma mark - Background

- (void)didEnterBackground
{
    [self.player pause];
}

- (void)willEnterForeground
{
    [[TBMediaProxy shared] ensureRunning];
    if (self.item && !self.paused) [self showCurrent];   // (the proxy may have moved: a fresh start is the simplest)
}

@end
