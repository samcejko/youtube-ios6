#import "TBWatchViewController.h"
#import "TBPlayerView.h"
#import "TBCells.h"
#import "TBCommentsViewController.h"
#import "TBNavigator.h"
#import "TBInnertube.h"
#import "TBPlayback.h"
#import "TBExtras.h"
#import "TBLibrary.h"
#import "TBMediaProxy.h"
#import "TBImageLoader.h"
#import "TBSettings.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

static void *TBStatusContext = &TBStatusContext;
static void *TBBufferEmptyContext = &TBBufferEmptyContext;
static void *TBKeepUpContext = &TBKeepUpContext;

static const NSTimeInterval TBStallReloadAfter = 25;
static const NSInteger TBMaxAutomaticReloads = 3;

typedef NS_ENUM(NSInteger, TBWatchSection) {
    TBWatchSectionInfo = 0,       // title + meta, actions
    TBWatchSectionChannel,
    TBWatchSectionDescription,
    TBWatchSectionComments,
    TBWatchSectionRelated,
    TBWatchSectionCount,
};

// The row with the title and the numbers
@interface TBWatchTitleCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLabel2;
@property (nonatomic, strong) UILabel *metaLabel;
+ (CGFloat)heightForTitle:(NSString *)title width:(CGFloat)width;
@end

@implementation TBWatchTitleCell
+ (CGFloat)heightForTitle:(NSString *)title width:(CGFloat)width
{
    CGSize s = [title sizeWithFont:[UIFont boldSystemFontOfSize:16] constrainedToSize:CGSizeMake(width - 24, 200) lineBreakMode:NSLineBreakByWordWrapping];
    return 10 + ceil(s.height) + 4 + 16 + 10;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _titleLabel2 = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel2.backgroundColor = [UIColor clearColor];
        _titleLabel2.font = [UIFont boldSystemFontOfSize:16];
        _titleLabel2.numberOfLines = 0;
        [self.contentView addSubview:_titleLabel2];
        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.font = [UIFont systemFontOfSize:12];
        [self.contentView addSubview:_metaLabel];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGSize s = [self.titleLabel2.text sizeWithFont:self.titleLabel2.font constrainedToSize:CGSizeMake(b.size.width - 24, 200) lineBreakMode:NSLineBreakByWordWrapping];
    self.titleLabel2.frame = CGRectMake(12, 10, b.size.width - 24, ceil(s.height));
    self.metaLabel.frame = CGRectMake(12, CGRectGetMaxY(self.titleLabel2.frame) + 4, b.size.width - 24, 16);
}
@end

// The row of buttons: like/dislike counts, watch later, quality, share
@interface TBWatchActionsCell : UITableViewCell
@property (nonatomic, strong) NSArray *buttons;
@end

@implementation TBWatchActionsCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        NSMutableArray *buttons = [NSMutableArray array];
        for (int i = 0; i < 4; i++) {
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
            b.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            b.tag = i;
            [self.contentView addSubview:b];
            [buttons addObject:b];
        }
        _buttons = buttons;
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat gap = 6, w = floor((b.size.width - 24 - gap * 3) / 4);
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        [self.buttons[i] setFrame:CGRectMake(12 + i * (w + gap), 7, w, 32)];
    }
}
@end

@interface TBWatchViewController () <TBPlayerViewDelegate, UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) TBVideo *video;
@property (nonatomic, strong) TBPlayerView *playerView;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *skipLabel;

@property (nonatomic, strong) TBPlaybackSource *source;
@property (nonatomic, strong) TBWatchInfo *info;
@property (nonatomic, strong) TBVotes *votes;
@property (nonatomic, strong) NSArray *sponsorSegments;
@property (nonatomic, strong) NSArray *captionCues;
@property (nonatomic, strong) TBCaptionTrack *captionTrack;
@property (nonatomic, strong) TBHTTPTask *loadTask, *infoTask, *votesTask, *sponsorTask, *captionsTask;

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *item;
@property (nonatomic, strong) TBVariant *currentVariant;
@property (nonatomic, copy) NSString *quality;
@property (nonatomic) NSUInteger proxyGeneration;
@property (nonatomic) BOOL wantsToPlay;
@property (nonatomic) BOOL itemReady;
@property (nonatomic) BOOL ended;
@property (nonatomic) BOOL fullscreen;
@property (nonatomic) BOOL inBackground;
@property (nonatomic) BOOL descriptionExpanded;
@property (nonatomic) double pendingSeek;
@property (nonatomic) NSInteger automaticReloads;
@property (nonatomic) NSTimeInterval lastProgressTime;
@property (nonatomic) double lastPosition;
@property (nonatomic) NSTimeInterval pausedAt;
@property (nonatomic) NSTimeInterval skipNoteUntil;
@property (nonatomic) double lastSkippedEnd;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic) float playbackRate;
@property (nonatomic) NSInteger pendingSheet;    // 1 quality, 2 share, 3 rate
@end

@implementation TBWatchViewController

- (instancetype)initWithVideo:(TBVideo *)video
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _video = video;
        _quality = [TBSettings preferredQuality];
        _pendingSeek = -1;
        _playbackRate = 1;
        _wantsToPlay = YES;
        self.wantsFullScreenLayout = YES;
    }
    return self;
}

- (void)dealloc
{
    [self teardownPlayback];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - View

- (void)viewDidLoad
{
    [super viewDidLoad];
    TBTheme *t = [TBTheme shared];
    self.view.backgroundColor = [t backgroundColor];

    self.playerView = [[TBPlayerView alloc] initWithFrame:CGRectZero];
    self.playerView.delegate = self;
    self.playerView.chatButtonHidden = YES;
    self.playerView.isLive = NO;
    self.playerView.playing = YES;
    [self.view addSubview:self.playerView];

    self.captionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.captionLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    self.captionLabel.textColor = [UIColor whiteColor];
    self.captionLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 18 : 14];
    self.captionLabel.textAlignment = NSTextAlignmentCenter;
    self.captionLabel.numberOfLines = 3;
    self.captionLabel.layer.cornerRadius = 4;
    self.captionLabel.hidden = YES;
    self.captionLabel.userInteractionEnabled = NO;
    [self.view addSubview:self.captionLabel];

    self.skipLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.skipLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    self.skipLabel.textColor = [UIColor whiteColor];
    self.skipLabel.font = [UIFont boldSystemFontOfSize:12];
    self.skipLabel.textAlignment = NSTextAlignmentCenter;
    self.skipLabel.layer.cornerRadius = 4;
    self.skipLabel.hidden = YES;
    self.skipLabel.userInteractionEnabled = NO;
    [self.view addSubview:self.skipLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.tableView registerClass:[TBVideoTableCell class] forCellReuseIdentifier:[TBVideoTableCell reuseIdentifier]];
    [self.view addSubview:self.tableView];
    [self applyTheme];

    NSError *audioError = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&audioError];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(didEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(willEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [nc addObserver:self selector:@selector(themeChanged) name:TBThemeDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(imageLoaded:) name:TBImageDidLoadNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged) name:TBSettingsDidChangeNotification object:nil];

    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self startWithVideo:self.video];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:animated];
    [self updateStatusBar];
    [self updateIdleTimer];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationNone];
    [[UIApplication sharedApplication] setStatusBarStyle:[[TBTheme shared] statusBarStyle] animated:animated];
    [UIApplication sharedApplication].idleTimerDisabled = NO;
    [self resignFirstResponder];
}

- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return TBIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown; }

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)orientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:orientation duration:duration];
    [self.view setNeedsLayout];
}

- (BOOL)videoFillsScreen
{
    // full screen by choice, or a phone turned on its side
    return self.fullscreen || (!TBIsPad() && UIInterfaceOrientationIsLandscape(self.interfaceOrientation));
}

- (void)updateStatusBar
{
    [[UIApplication sharedApplication] setStatusBarHidden:[self videoFillsScreen] withAnimation:UIStatusBarAnimationFade];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    BOOL fills = [self videoFillsScreen];
    CGFloat statusBar = fills ? 0 : 20;
    CGRect playerFrame;
    if (fills) {
        playerFrame = b;
    } else {
        CGFloat h = floor(b.size.width * 9.0 / 16.0);
        CGFloat maxH = floor(b.size.height * 0.56);
        if (h > maxH) h = maxH;
        playerFrame = CGRectMake(0, 0, b.size.width, h + statusBar);
    }
    self.playerView.frame = playerFrame;
    self.playerView.topInset = statusBar;
    self.tableView.frame = CGRectMake(0, CGRectGetMaxY(playerFrame), b.size.width, b.size.height - CGRectGetMaxY(playerFrame));
    self.tableView.hidden = fills;
    [self layoutOverlays];
}

- (void)layoutOverlays
{
    CGRect pf = self.playerView.frame;
    CGFloat w = MIN(pf.size.width - 40, 640);
    CGSize s = [self.captionLabel.text sizeWithFont:self.captionLabel.font constrainedToSize:CGSizeMake(w - 16, 120) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat lift = self.playerView.controlsVisible ? 54 : 14;
    self.captionLabel.frame = CGRectMake(floor((pf.size.width - s.width - 16) / 2), CGRectGetMaxY(pf) - lift - s.height - 8, ceil(s.width) + 16, ceil(s.height) + 8);
    self.skipLabel.frame = CGRectMake(pf.size.width - 12 - 190, pf.origin.y + self.playerView.topInset + 50, 190, 24);
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.view.backgroundColor = [t cardColor];
    [t applyToTableView:self.tableView];
    self.tableView.backgroundColor = [t cardColor];
    [self.tableView reloadData];
}

- (void)themeChanged { [self applyTheme]; }
- (void)libraryChanged { [self.tableView reloadData]; }
- (void)settingsChanged { [self.tableView reloadData]; }

- (void)imageLoaded:(NSNotification *)note
{
    // (avatars arrive after the rows were drawn)
}

- (void)updateIdleTimer
{
    [UIApplication sharedApplication].idleTimerDisabled = self.wantsToPlay && !self.ended && [TBSettings keepScreenOn];
}

#pragma mark - Loading

- (void)startWithVideo:(TBVideo *)video
{
    self.video = video;
    self.playerView.title = video.title ?: @"";
    self.playerView.subtitle = video.channelName ?: @"";
    self.playerView.isLive = video.isLive;
    self.playerView.qualityTitle = @"";
    self.playerView.statusText = @"";
    self.info = nil;
    self.votes = nil;
    self.sponsorSegments = nil;
    self.captionCues = nil;
    self.captionTrack = nil;
    self.captionLabel.hidden = YES;
    self.descriptionExpanded = NO;
    self.lastSkippedEnd = -1;
    [self.tableView reloadData];
    [self.tableView setContentOffset:CGPointZero animated:NO];
    [self startPlayback];
    [self loadInfo];
    [[TBLibrary shared] addToHistory:video];
}

- (void)loadVideo:(TBVideo *)video
{
    if (!video.videoId.length) return;
    [self teardownPlayback];
    self.wantsToPlay = YES;
    self.ended = NO;
    self.pendingSeek = -1;
    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self startWithVideo:video];
}

- (void)loadInfo
{
    NSString *videoId = self.video.videoId;
    __weak TBWatchViewController *weakSelf = self;
    [self.infoTask cancel];
    self.infoTask = [TBInnertube watchInfo:videoId completion:^(TBWatchInfo *info, NSError *error) {
        TBWatchViewController *s = weakSelf;
        if (!s || ![s.video.videoId isEqualToString:videoId]) return;
        s.infoTask = nil;
        if (!info) return;
        s.info = info;
        if (info.title.length && !s.video.title.length) { s.video.title = info.title; s.playerView.title = info.title; }
        if (info.channel.title.length) {
            s.video.channelName = info.channel.title;
            s.video.channelId = info.channel.channelId ?: s.video.channelId;
            s.video.channelAvatarURL = info.channel.avatarURL ?: s.video.channelAvatarURL;
            s.playerView.subtitle = info.channel.title;
        }
        [[TBLibrary shared] updateDetailsOf:s.video];
        [s.tableView reloadData];
        [s updateNowPlaying];
    }];
    [self.votesTask cancel];
    if ([TBSettings showDislikes]) {
        self.votesTask = [TBReturnDislike votesForVideo:videoId completion:^(TBVotes *votes, NSError *error) {
            TBWatchViewController *s = weakSelf;
            if (!s || ![s.video.videoId isEqualToString:videoId]) return;
            s.votesTask = nil;
            s.votes = votes;
            [s.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:1 inSection:TBWatchSectionInfo] ] withRowAnimation:UITableViewRowAnimationNone];
        }];
    }
    [self.sponsorTask cancel];
    self.sponsorTask = [TBSponsorBlock segmentsForVideo:videoId completion:^(NSArray *segments, NSError *error) {
        TBWatchViewController *s = weakSelf;
        if (!s || ![s.video.videoId isEqualToString:videoId]) return;
        s.sponsorTask = nil;
        s.sponsorSegments = segments;
        if (segments.count) TBLog(@"SponsorBlock: %lu segments", (unsigned long)segments.count);
    }];
}

#pragma mark - Playback

- (void)startPlayback
{
    [self.loadTask cancel];
    self.ended = NO;
    self.itemReady = NO;
    [self.playerView showMessage:nil retryTitle:nil];
    self.playerView.controlsLocked = NO;
    [self.playerView setBuffering:YES];
    NSString *videoId = self.video.videoId;
    __weak TBWatchViewController *weakSelf = self;
    self.loadTask = [TBPlayback sourceForVideo:videoId preferProgressive:[TBSettings progressiveOnly] completion:^(TBPlaybackSource *source, NSError *error) {
        TBWatchViewController *s = weakSelf;
        if (!s || ![s.video.videoId isEqualToString:videoId]) return;
        s.loadTask = nil;
        if (error) { [s failWithError:error]; return; }
        s.source = source;
        TBPlayerInfo *info = source.info;
        if (info.title.length) { s.video.title = info.title; s.playerView.title = info.title; }
        if (info.author.length && !s.video.channelName.length) { s.video.channelName = info.author; s.playerView.subtitle = info.author; }
        if (info.channelId.length && !s.video.channelId.length) s.video.channelId = info.channelId;
        if (info.lengthSeconds > 0) s.video.lengthSeconds = info.lengthSeconds;
        s.video.isLive = source.isLive;
        s.playerView.isLive = source.isLive;
        [[TBLibrary shared] updateDetailsOf:s.video];
        [s.tableView reloadData];
        if (!source.isLive && s.pendingSeek < 0) {
            NSTimeInterval resume = [TBSettings resumePositionForVideo:videoId];
            if (resume > 10 && (info.lengthSeconds <= 0 || resume < info.lengthSeconds - 20)) s.pendingSeek = resume;
        }
        [s playSource];
        [s loadCaptions];
    }];
}

- (void)playSource
{
    TBVariant *chosen = nil;
    NSString *title = nil;
    NSURL *url = [TBPlayback playerURLForSource:self.source quality:self.quality chosen:&chosen title:&title];
    if (!url) { [self failWithError:TBMakeError(TBErrorNetwork, L(@"The local video proxy could not start."))]; return; }
    self.currentVariant = chosen;
    self.proxyGeneration = [TBMediaProxy shared].generation;
    self.playerView.qualityTitle = title ?: @"";
    NSMutableArray *names = [NSMutableArray array];
    for (TBVariant *v in self.source.variants) [names addObject:[v title]];
    TBLog(@"Playing %@: %@ (%@) renditions: %@ audio: %lu", self.video.videoId, title, self.source.hasHLS ? @"HLS" : @"MP4",
          names.count ? [names componentsJoinedByString:@", "] : @"-", (unsigned long)self.source.audioRenditions.count);
    [self loadItemWithURL:url];
}

- (void)loadItemWithURL:(NSURL *)url
{
    [self detachItem];
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    self.item = item;
    [item addObserver:self forKeyPath:@"status" options:0 context:TBStatusContext];
    [item addObserver:self forKeyPath:@"playbackBufferEmpty" options:0 context:TBBufferEmptyContext];
    [item addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:0 context:TBKeepUpContext];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(itemDidPlayToEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [nc addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [nc addObserver:self selector:@selector(itemStalled:) name:AVPlayerItemPlaybackStalledNotification object:item];
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:item];
        self.player.allowsExternalPlayback = NO;   // (the proxy lives on this device only)
        self.playerView.player = self.player;
    } else {
        [self.player replaceCurrentItemWithPlayerItem:item];
        if (!self.inBackground) self.playerView.player = self.player;
    }
    self.lastProgressTime = [NSDate timeIntervalSinceReferenceDate];
    self.lastPosition = -1;
    [self.playerView setBuffering:YES];
    if (self.wantsToPlay) {
        [self.player play];
        self.playerView.playing = YES;
    }
}

- (void)detachItem
{
    if (!self.item) return;
    @try {
        [self.item removeObserver:self forKeyPath:@"status" context:TBStatusContext];
        [self.item removeObserver:self forKeyPath:@"playbackBufferEmpty" context:TBBufferEmptyContext];
        [self.item removeObserver:self forKeyPath:@"playbackLikelyToKeepUp" context:TBKeepUpContext];
    } @catch (NSException *e) {}
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.item];
    [nc removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.item];
    [nc removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:self.item];
    self.item = nil;
}

- (void)teardownPlayback
{
    [self.loadTask cancel]; self.loadTask = nil;
    [self.infoTask cancel]; self.infoTask = nil;
    [self.votesTask cancel]; self.votesTask = nil;
    [self.sponsorTask cancel]; self.sponsorTask = nil;
    [self.captionsTask cancel]; self.captionsTask = nil;
    [self.tickTimer invalidate]; self.tickTimer = nil;
    [self rememberPosition];
    [self.player pause];
    [self detachItem];
    self.playerView.player = nil;
    self.player = nil;
    self.source = nil;
    Class center = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (center) [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context != TBStatusContext && context != TBBufferEmptyContext && context != TBKeepUpContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self observeValueForKeyPath:keyPath ofObject:object change:change context:context]; });
        return;
    }
    if (object != self.item) return;
    if (context == TBStatusContext) {
        if (self.item.status == AVPlayerItemStatusFailed) {
            TBLog(@"Item failed: %@", self.item.error);
            [self handlePlaybackFailure:self.item.error];
        } else if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            self.itemReady = YES;
            self.automaticReloads = 0;
            [self.playerView setBuffering:NO];
            if (self.pendingSeek >= 0) {
                double seek = self.pendingSeek;
                self.pendingSeek = -1;
                [self.player seekToTime:CMTimeMakeWithSeconds(seek, 600)];
            }
            if (self.wantsToPlay) [self.player play];
            if (self.playbackRate != 1 && !self.source.isLive) self.player.rate = self.playbackRate;
            [self updateNowPlaying];
        }
    } else if (context == TBBufferEmptyContext) {
        if (self.item.playbackBufferEmpty && self.wantsToPlay) [self.playerView setBuffering:YES];
    } else if (context == TBKeepUpContext) {
        if (self.item.playbackLikelyToKeepUp) {
            [self.playerView setBuffering:NO];
            if (self.wantsToPlay && self.player.rate == 0 && !self.ended) [self.player play];
        }
    }
}

- (void)itemDidPlayToEnd:(NSNotification *)note
{
    if (self.source.isLive) {
        [self failWithError:TBMakeError(TBErrorOffline, L(@"The live stream has ended."))];
        return;
    }
    self.ended = YES;
    self.wantsToPlay = NO;
    self.playerView.playing = NO;
    [TBSettings setResumePosition:0 forVideo:self.video.videoId];
    [[TBLibrary shared] updatePosition:0 forVideo:self.video.videoId];
    self.playerView.controlsLocked = YES;
    [self updateIdleTimer];
    TBVideo *next = [self nextVideo];
    if (next) {
        __weak TBWatchViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TBWatchViewController *s = weakSelf;
            if (s && s.ended) [s loadVideo:next];
        });
    }
}

- (TBVideo *)nextVideo
{
    if (self.queue.count && self.queueIndex + 1 < self.queue.count) {
        for (NSUInteger i = self.queueIndex + 1; i < self.queue.count; i++) {
            if ([self.queue[i] isKindOfClass:[TBVideo class]]) { self.queueIndex = i; return self.queue[i]; }
        }
    }
    if (![TBSettings autoplayNext]) return nil;
    for (id item in self.info.related) if ([item isKindOfClass:[TBVideo class]] && ![(TBVideo *)item isLive]) return item;
    return nil;
}

- (void)itemFailed:(NSNotification *)note
{
    TBLog(@"Failed to play to end: %@", note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]);
    [self handlePlaybackFailure:note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]];
}

- (void)itemStalled:(NSNotification *)note
{
    TBLog(@"Playback stalled");
    if (self.wantsToPlay) [self.playerView setBuffering:YES];
}

- (void)handlePlaybackFailure:(NSError *)error
{
    if (self.ended) return;
    if (self.source.hasHLS && self.source.progressiveURL.length && self.automaticReloads >= 1) {
        // HLS keeps failing: the plain MP4 is the way out
        TBLog(@"Falling back to the MP4");
        self.source.variants = nil;
        self.source.audioRenditions = nil;
        self.automaticReloads++;
        [self playSource];
        return;
    }
    if (self.automaticReloads < TBMaxAutomaticReloads) {
        self.automaticReloads++;
        TBLog(@"Reloading the stream (%ld)", (long)self.automaticReloads);
        [self.playerView setBuffering:YES];
        __weak TBWatchViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TBWatchViewController *s = weakSelf;
            if (!s || s.ended || !s.wantsToPlay) return;
            if (s.source) { if (!s.source.isLive && s.item) s.pendingSeek = MAX(0, CMTimeGetSeconds(s.player.currentTime)); [s playSource]; }
            else [s startPlayback];
        });
        return;
    }
    NSString *message = error.localizedDescription;
    if (self.source.isLive) message = L(@"The stream could not be played. It may have ended, or the connection is too slow.");
    else if (!message.length) message = L(@"The video could not be played.");
    [self failWithError:TBMakeError(TBErrorNetwork, message)];
}

- (void)failWithError:(NSError *)error
{
    [self.playerView setBuffering:NO];
    self.playerView.playing = NO;
    [self.playerView showMessage:error.localizedDescription ?: L(@"Playback failed.") retryTitle:L(@"Try Again")];
    __weak TBWatchViewController *weakSelf = self;
    self.playerView.retryHandler = ^{ [weakSelf retryTapped]; };
    [self updateIdleTimer];
}

- (void)retryTapped
{
    self.automaticReloads = 0;
    self.wantsToPlay = YES;
    self.ended = NO;
    [self startPlayback];
    [self updateIdleTimer];
}

- (void)rememberPosition
{
    if (self.source.isLive || !self.item || !self.itemReady) return;
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (position > 0 && !isnan(position)) {
        [TBSettings setResumePosition:position forVideo:self.video.videoId];
        [[TBLibrary shared] updatePosition:position forVideo:self.video.videoId];
    }
}

- (void)seekToSeconds:(NSTimeInterval)seconds
{
    if (!self.item) { self.pendingSeek = seconds; return; }
    [self.player seekToTime:CMTimeMakeWithSeconds(MAX(0, seconds), 600)];
}

- (NSString *)playbackDebugDescription
{
    if (!self.item) return @"no item";
    NSMutableArray *tracks = [NSMutableArray array];
    for (AVPlayerItemTrack *t in self.item.tracks) {
        [tracks addObject:[NSString stringWithFormat:@"%@%@", t.assetTrack.mediaType ?: @"?", t.enabled ? @"" : @"(off)"]];
    }
    NSMutableArray *ranges = [NSMutableArray array];
    for (NSValue *v in self.item.loadedTimeRanges) {
        CMTimeRange r = [v CMTimeRangeValue];
        [ranges addObject:[NSString stringWithFormat:@"%.1f-%.1f", CMTimeGetSeconds(r.start), CMTimeGetSeconds(CMTimeRangeGetEnd(r))]];
    }
    static NSString * const statusNames[] = { @"unknown", @"ready", @"failed" };
    NSInteger status = self.item.status;
    return [NSString stringWithFormat:@"rate %.2f at %.1f/%.1f s, item %@%@, tracks [%@], buffered [%@], size %.0fx%.0f, empty %d keepUp %d, variant %@",
            self.player.rate, CMTimeGetSeconds(self.player.currentTime), CMTimeGetSeconds(self.item.duration),
            status >= 0 && status <= 2 ? statusNames[status] : @"?", self.item.error ? [NSString stringWithFormat:@" (%@)", self.item.error.localizedDescription] : @"",
            [tracks componentsJoinedByString:@", "], [ranges componentsJoinedByString:@", "],
            self.item.presentationSize.width, self.item.presentationSize.height,
            self.item.playbackBufferEmpty, self.item.playbackLikelyToKeepUp, self.currentVariant ? [self.currentVariant title] : @"auto"];
}

#pragma mark - Captions

- (void)loadCaptions
{
    self.captionCues = nil;
    self.captionLabel.hidden = YES;
    TBCaptionTrack *track = [TBCaptions preferredTrackIn:self.source.info.captionTracks];
    self.captionTrack = track;
    if (!track) return;
    NSString *videoId = self.video.videoId;
    __weak TBWatchViewController *weakSelf = self;
    [self.captionsTask cancel];
    self.captionsTask = [TBCaptions loadTrack:track completion:^(NSArray *cues, NSError *error) {
        TBWatchViewController *s = weakSelf;
        if (!s || ![s.video.videoId isEqualToString:videoId]) return;
        s.captionsTask = nil;
        s.captionCues = cues;
        if (error) TBLog(@"Captions: %@", error.localizedDescription);
    }];
}

- (void)selectCaptionTrack:(TBCaptionTrack *)track
{
    self.captionTrack = track;
    self.captionCues = nil;
    self.captionLabel.hidden = YES;
    if (!track) return;
    NSString *videoId = self.video.videoId;
    __weak TBWatchViewController *weakSelf = self;
    [self.captionsTask cancel];
    self.captionsTask = [TBCaptions loadTrack:track completion:^(NSArray *cues, NSError *error) {
        TBWatchViewController *s = weakSelf;
        if (!s || ![s.video.videoId isEqualToString:videoId]) return;
        s.captionsTask = nil;
        s.captionCues = cues;
    }];
}

#pragma mark - Tick

- (void)tick
{
    if (!self.item) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(position)) position = 0;
    if (!self.source.isLive) {
        double duration = CMTimeGetSeconds(self.item.duration);
        if (isnan(duration) || duration <= 0) duration = self.video.lengthSeconds;
        if (duration > 0) [self.playerView setProgress:position / duration duration:duration position:position];
        // SponsorBlock: a segment that starts here is jumped over
        if (self.wantsToPlay && self.itemReady) {
            for (TBSponsorSegment *seg in self.sponsorSegments) {
                if (position >= seg.start && position < seg.end - 0.5 && fabs(seg.end - self.lastSkippedEnd) > 0.1) {
                    self.lastSkippedEnd = seg.end;
                    [self.player seekToTime:CMTimeMakeWithSeconds(seg.end, 600)];
                    self.skipLabel.text = [NSString stringWithFormat:L(@"Skipped: %@"), [seg title]];
                    self.skipLabel.hidden = NO;
                    self.skipNoteUntil = now + 3;
                    TBLog(@"SponsorBlock: skipped %@ %.0f-%.0f", seg.category, seg.start, seg.end);
                    break;
                }
            }
        }
        // captions
        if (self.captionCues.count) {
            TBCaptionCue *cue = [TBCaptions cueAtTime:position inCues:self.captionCues];
            if (cue && ![cue.text isEqualToString:self.captionLabel.text]) { self.captionLabel.text = cue.text; [self layoutOverlays]; }
            self.captionLabel.hidden = !cue || self.inBackground;
        } else {
            self.captionLabel.hidden = YES;
        }
    }
    if (!self.skipLabel.hidden && now > self.skipNoteUntil) self.skipLabel.hidden = YES;
    // progress watch: a playing video whose position does not move for a long time is started again
    if (fabs(position - self.lastPosition) > 0.01) {
        self.lastPosition = position;
        self.lastProgressTime = now;
    } else if (self.wantsToPlay && self.itemReady && !self.ended && now - self.lastProgressTime > TBStallReloadAfter) {
        TBLog(@"No progress for %.0f s, reloading", now - self.lastProgressTime);
        self.lastProgressTime = now;
        if (self.source.isLive) [self playSource];
        else { [self.player pause]; [self.player play]; }
    }
    if (self.source.isLive) self.playerView.statusText = self.info.viewsText ?: @"";
    if (!self.source.isLive && ((NSInteger)now % 15 == 0)) [self rememberPosition];
}

#pragma mark - Now playing

- (void)updateNowPlaying
{
    Class center = NSClassFromString(@"MPNowPlayingInfoCenter");
    if (!center) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if (self.video.title.length) info[MPMediaItemPropertyTitle] = self.video.title;
    if (self.video.channelName.length) info[MPMediaItemPropertyArtist] = self.video.channelName;
    if (self.video.lengthSeconds > 0) info[MPMediaItemPropertyPlaybackDuration] = @(self.video.lengthSeconds);
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event
{
    if (event.type != UIEventTypeRemoteControl) return;
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlTogglePlayPause: [self playerViewDidTapPlayPause:self.playerView]; break;
        case UIEventSubtypeRemoteControlPlay: if (!self.wantsToPlay) [self playerViewDidTapPlayPause:self.playerView]; break;
        case UIEventSubtypeRemoteControlPause: if (self.wantsToPlay) [self playerViewDidTapPlayPause:self.playerView]; break;
        case UIEventSubtypeRemoteControlNextTrack: { TBVideo *next = [self nextVideo]; if (next) [self loadVideo:next]; break; }
        default: break;
    }
}

#pragma mark - Background

- (void)didEnterBackground
{
    self.inBackground = YES;
    if (self.wantsToPlay && [TBSettings backgroundAudio] && !self.ended) {
        // without a picture to draw the sound goes on; with the layer attached iOS pauses the player
        self.playerView.player = nil;
        __weak TBWatchViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TBWatchViewController *s = weakSelf;
            if (s && s.inBackground && s.wantsToPlay) [s.player play];
        });
    } else if (self.wantsToPlay) {
        [self.player pause];
        self.pausedAt = [NSDate timeIntervalSinceReferenceDate];
    }
    [self rememberPosition];
}

- (void)willEnterForeground
{
    self.inBackground = NO;
    self.playerView.player = self.player;
    TBMediaProxy *proxy = [TBMediaProxy shared];
    [proxy ensureRunning];
    if (proxy.generation != self.proxyGeneration && !self.ended && self.source) {
        if (!self.source.isLive && self.item) self.pendingSeek = MAX(0, CMTimeGetSeconds(self.player.currentTime));
        [self playSource];
        return;
    }
    if (self.wantsToPlay && !self.ended) {
        if (self.source.isLive && ![TBSettings backgroundAudio] && [NSDate timeIntervalSinceReferenceDate] - self.pausedAt > 60) [self playSource];
        else [self.player play];
    }
    [self updateStatusBar];
}

#pragma mark - Player view delegate

- (void)playerViewDidTapPlayPause:(TBPlayerView *)view
{
    if (self.ended) {
        self.ended = NO;
        self.wantsToPlay = YES;
        if (self.source.isLive) { [self retryTapped]; return; }
        [self.player seekToTime:kCMTimeZero];
        [self.player play];
        self.playerView.playing = YES;
        self.playerView.controlsLocked = NO;
        [self updateIdleTimer];
        return;
    }
    if (self.wantsToPlay) {
        self.wantsToPlay = NO;
        [self.player pause];
        self.pausedAt = [NSDate timeIntervalSinceReferenceDate];
        self.playerView.playing = NO;
        self.playerView.controlsLocked = YES;
        [self rememberPosition];
    } else {
        self.wantsToPlay = YES;
        self.playerView.playing = YES;
        self.playerView.controlsLocked = NO;
        if (self.source.isLive && [NSDate timeIntervalSinceReferenceDate] - self.pausedAt > 60) [self playSource];
        else [self.player play];
    }
    [self updateIdleTimer];
}

- (void)playerViewDidTapClose:(TBPlayerView *)view
{
    if (self.fullscreen) { [self playerViewDidTapFullscreen:view]; return; }
    [self teardownPlayback];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)playerViewDidTapQuality:(TBPlayerView *)view fromView:(UIView *)anchor
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Quality") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (self.source.hasHLS) {
        [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@%@", L(@"Auto"), self.currentVariant ? @"" : @" ✓"]];
        for (TBVariant *v in self.source.variants) {
            [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@%@", [v title], v == self.currentVariant ? @" ✓" : @""]];
        }
    } else {
        [sheet addButtonWithTitle:self.playerView.qualityTitle.length ? self.playerView.qualityTitle : L(@"Video")];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    self.pendingSheet = 1;
    if (TBIsPad()) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:self.view];
}

- (void)playerViewDidTapChat:(TBPlayerView *)view
{
}

- (void)playerViewDidTapFullscreen:(TBPlayerView *)view
{
    self.fullscreen = !self.fullscreen;
    self.playerView.fullscreen = self.fullscreen;
    [self updateStatusBar];
    [UIView animateWithDuration:0.25 animations:^{ [self.view setNeedsLayout]; [self.view layoutIfNeeded]; }];
}

- (void)playerViewDidTapChannel:(TBPlayerView *)view
{
    if (self.video.channelId.length) [TBNavigator openChannelId:self.video.channelId from:self];
}

- (void)playerView:(TBPlayerView *)view didSeekToFraction:(double)fraction
{
    double duration = CMTimeGetSeconds(self.item.duration);
    if (isnan(duration) || duration <= 0) duration = self.video.lengthSeconds;
    if (duration <= 0) return;
    self.lastSkippedEnd = -1;
    [self.player seekToTime:CMTimeMakeWithSeconds(fraction * duration, 600)];
}

- (void)playerView:(TBPlayerView *)view didSkipSeconds:(double)seconds
{
    double position = CMTimeGetSeconds(self.player.currentTime);
    if (isnan(position)) position = 0;
    self.lastSkippedEnd = -1;
    [self.player seekToTime:CMTimeMakeWithSeconds(MAX(0, position + seconds), 600)];
}

- (void)playerViewDidTapGoLive:(TBPlayerView *)view
{
    if (self.source.isLive) [self playSource];
}

#pragma mark - Sheets

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSInteger kind = self.pendingSheet;
    self.pendingSheet = 0;
    if (buttonIndex == actionSheet.cancelButtonIndex || buttonIndex < 0) return;
    if (kind == 1) {
        if (!self.source.hasHLS) return;
        NSString *quality = buttonIndex == 0 ? TBQualityAuto : [self.source.variants[(NSUInteger)(buttonIndex - 1)] qualityKey];
        if ([quality isEqualToString:self.quality]) return;
        self.quality = quality;
        [TBSettings setPreferredQuality:quality];
        [TBSettings save];
        if (!self.source.isLive && self.item) self.pendingSeek = MAX(0, CMTimeGetSeconds(self.player.currentTime));
        [self playSource];
    } else if (kind == 3) {
        // playback rate
        float rates[] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
        if (buttonIndex < 6) {
            self.playbackRate = rates[buttonIndex];
            if (self.wantsToPlay && self.itemReady) self.player.rate = self.playbackRate;
            [self.tableView reloadData];
        }
    } else if (kind == 4) {
        // captions
        if (buttonIndex == 0) { [TBSettings setCaptionsEnabled:NO]; [self selectCaptionTrack:nil]; return; }
        NSArray *tracks = self.source.info.captionTracks;
        if (buttonIndex - 1 < (NSInteger)tracks.count) {
            TBCaptionTrack *track = tracks[(NSUInteger)(buttonIndex - 1)];
            [TBSettings setCaptionsEnabled:YES];
            [TBSettings setCaptionsLanguage:track.languageCode ?: @""];
            [self selectCaptionTrack:track];
        }
    }
}

#pragma mark - Actions

- (void)actionTapped:(UIButton *)button
{
    switch (button.tag) {
        case 0: {   // like / dislike counts: nothing to do without an account
            NSString *text = self.votes ? [NSString stringWithFormat:L(@"%@ likes, %@ dislikes (Return YouTube Dislike)"), [TBUtils formatCount:(NSInteger)MIN(self.votes.likes, (long long)NSIntegerMax)], [TBUtils formatCount:(NSInteger)MIN(self.votes.dislikes, (long long)NSIntegerMax)]]
                                          : L(@"Liking needs a Google account, which the app does not use.");
            [TBUtils alertWithTitle:L(@"Rating") message:text];
            break;
        }
        case 1: {   // watch later
            [[TBLibrary shared] toggleWatchLater:self.video];
            [self.tableView reloadData];
            break;
        }
        case 2: {   // captions
            NSArray *tracks = self.source.info.captionTracks;
            if (!tracks.count) { [TBUtils alertWithTitle:L(@"Captions") message:L(@"This video has no captions.")]; break; }
            UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Captions") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
            [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@%@", L(@"Off"), self.captionTrack ? @"" : @" ✓"]];
            for (TBCaptionTrack *t in tracks) [sheet addButtonWithTitle:[NSString stringWithFormat:@"%@%@", t.name ?: t.languageCode, t == self.captionTrack ? @" ✓" : @""]];
            sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
            self.pendingSheet = 4;
            if (TBIsPad()) [sheet showFromRect:button.bounds inView:button animated:YES];
            else [sheet showInView:self.view];
            break;
        }
        case 3: {   // speed
            if (self.source.isLive) break;
            UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:L(@"Speed") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
            float rates[] = { 0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f };
            for (int i = 0; i < 6; i++) [sheet addButtonWithTitle:[NSString stringWithFormat:@"%g×%@", rates[i], fabs(rates[i] - self.playbackRate) < 0.01 ? @" ✓" : @""]];
            sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
            self.pendingSheet = 3;
            if (TBIsPad()) [sheet showFromRect:button.bounds inView:button animated:YES];
            else [sheet showInView:self.view];
            break;
        }
        default: break;
    }
}

- (void)shareTapped
{
    NSString *link = [NSString stringWithFormat:@"https://youtu.be/%@", self.video.videoId ?: @""];
    [UIPasteboard generalPasteboard].string = link;
    self.skipLabel.text = L(@"Link copied");
    self.skipLabel.hidden = NO;
    self.skipNoteUntil = [NSDate timeIntervalSinceReferenceDate] + 2;
}

- (void)subscribeTapped
{
    TBChannel *channel = self.info.channel;
    if (!channel) {
        channel = [[TBChannel alloc] init];
        channel.channelId = self.video.channelId;
        channel.title = self.video.channelName;
        channel.avatarURL = self.video.channelAvatarURL;
    }
    if (!channel.channelId.length) return;
    TBLibrary *library = [TBLibrary shared];
    if ([library isSubscribed:channel.channelId]) [library unsubscribe:channel.channelId];
    else [library subscribe:channel];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return TBWatchSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ((TBWatchSection)section) {
        case TBWatchSectionInfo: return 2;
        case TBWatchSectionChannel: return 1;
        case TBWatchSectionDescription: return [self descriptionText].length ? 1 : 0;
        case TBWatchSectionComments: return self.info.commentsToken.length ? 1 : 0;
        case TBWatchSectionRelated: return (NSInteger)self.info.related.count;
        default: return 0;
    }
}

- (NSString *)descriptionText
{
    return self.info.descriptionText.length ? self.info.descriptionText : self.source.info.shortDescription;
}

- (NSString *)metaText
{
    NSMutableArray *parts = [NSMutableArray array];
    NSString *views = self.info.viewsText;
    if (!views.length && self.source.info.viewCount > 0) views = [NSString stringWithFormat:L(@"%@ views"), [TBUtils formatCount:(NSInteger)MIN(self.source.info.viewCount, (long long)NSIntegerMax)]];
    if (views.length) [parts addObject:views];
    if (self.info.dateText.length) [parts addObject:self.info.dateText];
    else if (self.source.info.publishDate.length) [parts addObject:self.source.info.publishDate];
    return [parts componentsJoinedByString:@" · "];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat width = tableView.bounds.size.width;
    switch ((TBWatchSection)indexPath.section) {
        case TBWatchSectionInfo: return indexPath.row == 0 ? [TBWatchTitleCell heightForTitle:self.video.title ?: @"" width:width] : 46;
        case TBWatchSectionChannel: return 60;
        case TBWatchSectionDescription: {
            NSString *text = [self descriptionText];
            CGSize s = [text sizeWithFont:[UIFont systemFontOfSize:13] constrainedToSize:CGSizeMake(width - 24, self.descriptionExpanded ? 20000 : 72) lineBreakMode:NSLineBreakByWordWrapping];
            return MIN(self.descriptionExpanded ? 20000 : 72, ceil(s.height)) + 20;
        }
        case TBWatchSectionComments: return 44;
        case TBWatchSectionRelated: return [TBVideoTableCell height];
        default: return 44;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return section == TBWatchSectionRelated && self.info.related.count ? 28 : 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section != TBWatchSectionRelated || !self.info.related.count) return nil;
    TBTheme *t = [TBTheme shared];
    UIImageView *header = [[UIImageView alloc] initWithImage:[t sectionHeaderBackgroundImage]];
    header.frame = CGRectMake(0, 0, tableView.bounds.size.width, 28);
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 0, tableView.bounds.size.width - 24, 28)];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:14];
    label.textColor = [UIColor whiteColor];
    label.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
    label.shadowOffset = CGSizeMake(0, 1);
    label.text = L(@"Up next");
    [header addSubview:label];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TBTheme *t = [TBTheme shared];
    switch ((TBWatchSection)indexPath.section) {
        case TBWatchSectionInfo: {
            if (indexPath.row == 0) {
                TBWatchTitleCell *cell = [[TBWatchTitleCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                [t styleCell:cell];
                cell.titleLabel2.text = self.video.title ?: @"";
                cell.titleLabel2.textColor = [t primaryTextColor];
                cell.metaLabel.text = [self metaText];
                cell.metaLabel.textColor = [t secondaryTextColor];
                return cell;
            }
            TBWatchActionsCell *cell = [[TBWatchActionsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            [t styleCell:cell];
            NSString *likes = self.votes ? [TBUtils formatCount:(NSInteger)MIN(self.votes.likes, (long long)NSIntegerMax)] : (self.info.likesText ?: @"–");
            NSString *dislikes = self.votes && [TBSettings showDislikes] ? [TBUtils formatCount:(NSInteger)MIN(self.votes.dislikes, (long long)NSIntegerMax)] : nil;
            NSString *rating = dislikes ? [NSString stringWithFormat:@"👍 %@  👎 %@", likes, dislikes] : [NSString stringWithFormat:@"👍 %@", likes];
            BOOL later = [[TBLibrary shared] isInWatchLater:self.video.videoId];
            NSArray *titles = @[ rating, later ? L(@"✓ Later") : L(@"Watch later"), self.captionTrack ? L(@"CC ✓") : L(@"CC"),
                                 self.source.isLive ? L(@"Live") : [NSString stringWithFormat:@"%g×", self.playbackRate] ];
            for (NSUInteger i = 0; i < titles.count; i++) {
                UIButton *b = cell.buttons[i];
                [b setTitle:titles[i] forState:UIControlStateNormal];
                [b setTitleColor:[t primaryTextColor] forState:UIControlStateNormal];
                [b setBackgroundImage:[t buttonImageHighlighted:NO] forState:UIControlStateNormal];
                [b setBackgroundImage:[t buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
                [b removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
                [b addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            }
            return cell;
        }
        case TBWatchSectionChannel: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            [t styleCell:cell];
            cell.textLabel.text = self.video.channelName ?: L(@"Channel");
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.text = self.info.channel.subscribersText ?: @"";
            cell.detailTextLabel.textColor = [t secondaryTextColor];
            cell.detailTextLabel.backgroundColor = [UIColor clearColor];
            TBImageView *avatar = [[TBImageView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
            avatar.contentMode = UIViewContentModeScaleAspectFill;
            avatar.clipsToBounds = YES;
            avatar.layer.cornerRadius = 20;
            avatar.maxPixels = 120;
            [avatar setImageURL:self.info.channel.avatarURL ?: self.video.channelAvatarURL placeholder:[t avatarPlaceholderWithSize:40]];
            cell.imageView.image = [t avatarPlaceholderWithSize:40];   // (reserves the room; the real picture sits on top)
            [cell.contentView addSubview:avatar];
            avatar.frame = CGRectMake(10, 10, 40, 40);
            cell.imageView.hidden = YES;
            cell.indentationLevel = 0;
            UIButton *subscribe = [UIButton buttonWithType:UIButtonTypeCustom];
            BOOL subscribed = [[TBLibrary shared] isSubscribed:self.video.channelId];
            subscribe.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [subscribe setTitle:subscribed ? L(@"Subscribed ✓") : L(@"Subscribe") forState:UIControlStateNormal];
            [subscribe setTitleColor:subscribed ? [t primaryTextColor] : [UIColor whiteColor] forState:UIControlStateNormal];
            [subscribe setBackgroundImage:subscribed ? [t buttonImageHighlighted:NO] : [t accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
            [subscribe setBackgroundImage:subscribed ? [t buttonImageHighlighted:YES] : [t accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
            [subscribe addTarget:self action:@selector(subscribeTapped) forControlEvents:UIControlEventTouchUpInside];
            subscribe.frame = CGRectMake(0, 0, 120, 30);
            cell.accessoryView = subscribe;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            return cell;
        }
        case TBWatchSectionDescription: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            [t styleCell:cell];
            cell.textLabel.text = [self descriptionText];
            cell.textLabel.font = [UIFont systemFontOfSize:13];
            cell.textLabel.numberOfLines = self.descriptionExpanded ? 0 : 4;
            cell.textLabel.lineBreakMode = self.descriptionExpanded ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail;
            cell.textLabel.textColor = [t secondaryTextColor];
            return cell;
        }
        case TBWatchSectionComments: {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
            [t styleCell:cell];
            cell.textLabel.text = L(@"Comments");
            cell.detailTextLabel.text = self.info.commentCountText ?: @"";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        case TBWatchSectionRelated: {
            TBVideoTableCell *cell = [tableView dequeueReusableCellWithIdentifier:[TBVideoTableCell reuseIdentifier] forIndexPath:indexPath];
            id item = self.info.related[(NSUInteger)indexPath.row];
            if ([item isKindOfClass:[TBPlaylist class]]) [cell configureWithPlaylist:item];
            else [cell configureWithVideo:item];
            return cell;
        }
        default: return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    switch ((TBWatchSection)indexPath.section) {
        case TBWatchSectionInfo:
            if (indexPath.row == 0) [self shareTapped];
            break;
        case TBWatchSectionChannel:
            if (self.video.channelId.length) [TBNavigator openChannelId:self.video.channelId from:self];
            break;
        case TBWatchSectionDescription:
            self.descriptionExpanded = !self.descriptionExpanded;
            [tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationFade];
            break;
        case TBWatchSectionComments: {
            TBCommentsViewController *comments = [[TBCommentsViewController alloc] initWithToken:self.info.commentsToken title:L(@"Comments")];
            [TBNavigator showPage:comments from:self];
            break;
        }
        case TBWatchSectionRelated: {
            id item = self.info.related[(NSUInteger)indexPath.row];
            if ([item isKindOfClass:[TBVideo class]]) { self.queue = nil; [self loadVideo:item]; }
            else [TBNavigator openItem:item from:self];
            break;
        }
        default: break;
    }
}

@end
