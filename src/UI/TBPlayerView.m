#import "TBPlayerView.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <MediaPlayer/MediaPlayer.h>

static const NSTimeInterval TBControlsHideDelay = 4.0;
static const CGFloat TBBarHeight = 44;

// A view whose layer shows the video
@interface TBVideoLayerView : UIView
@end

@implementation TBVideoLayerView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

@interface TBPlayerView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) TBVideoLayerView *videoView;
@property (nonatomic, strong) UIView *controls;
@property (nonatomic, strong) UIImageView *topGradient;
@property (nonatomic, strong) UIImageView *bottomGradient;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *subtitleButton;
@property (nonatomic, strong) UIButton *qualityButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *forwardButton;
@property (nonatomic, strong) UIButton *liveButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *chatButton;
@property (nonatomic, strong) UIButton *fullscreenButton;
@property (nonatomic, strong) UILabel *adLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic) BOOL controlsVisible;
@property (nonatomic) BOOL scrubbing;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic, strong) NSTimer *hideTimer;
// chapters, gestures, the floating-player button and the brightness/volume HUD
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UILabel *chapterLabel;
@property (nonatomic, strong) UILabel *hudLabel;
@property (nonatomic, strong) UITapGestureRecognizer *singleTap;
@property (nonatomic, strong) UITapGestureRecognizer *doubleTap;
@property (nonatomic, strong) UIPanGestureRecognizer *pan;
@property (nonatomic, strong) NSArray *chapterFractions;
@property (nonatomic, strong) NSArray *chapterTitles;
@property (nonatomic, strong) NSMutableArray *chapterMarkViews;
@property (nonatomic, strong) NSMutableArray *chapterMarkFractions;
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic, strong) UISlider *systemVolumeSlider;
@property (nonatomic) BOOL panActive;
@property (nonatomic) BOOL panIgnore;
@property (nonatomic) BOOL panIsVolume;
@property (nonatomic) CGFloat panStartValue;
@property (nonatomic, strong) NSTimer *hudTimer;
@end

@implementation TBPlayerView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor blackColor];
        self.clipsToBounds = YES;
        TBTheme *t = [TBTheme shared];

        _videoView = [[TBVideoLayerView alloc] initWithFrame:self.bounds];
        _videoView.backgroundColor = [UIColor blackColor];
        ((AVPlayerLayer *)_videoView.layer).videoGravity = AVLayerVideoGravityResizeAspect;
        [self addSubview:_videoView];

        _controls = [[UIView alloc] initWithFrame:self.bounds];
        _controls.backgroundColor = [UIColor clearColor];
        [self addSubview:_controls];

        _topGradient = [[UIImageView alloc] initWithImage:[t controlsGradientImageTop:YES]];
        [_controls addSubview:_topGradient];
        _bottomGradient = [[UIImageView alloc] initWithImage:[t controlsGradientImageTop:NO]];
        [_controls addSubview:_bottomGradient];

        // (the icon buttons carry labels for VoiceOver; they also let the debug URL commands find them by name)
        _closeButton = [self iconButtonWithImage:[t closeIconWhite] action:@selector(closeTapped)];
        _closeButton.accessibilityLabel = L(@"Close");
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:15];
        _titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        _titleLabel.shadowOffset = CGSizeMake(0, 1);
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [_controls addSubview:_titleLabel];
        _subtitleButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _subtitleButton.titleLabel.font = [UIFont systemFontOfSize:12];
        _subtitleButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _subtitleButton.titleLabel.shadowOffset = CGSizeMake(0, 1);
        _subtitleButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_subtitleButton setTitleColor:[UIColor colorWithWhite:0.85 alpha:1] forState:UIControlStateNormal];
        [_subtitleButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.7] forState:UIControlStateNormal];
        [_subtitleButton addTarget:self action:@selector(channelTapped) forControlEvents:UIControlEventTouchUpInside];
        _subtitleButton.accessibilityLabel = L(@"Channel");
        [_controls addSubview:_subtitleButton];
        _qualityButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _qualityButton.accessibilityLabel = L(@"Quality");
        _qualityButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [_qualityButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_qualityButton setBackgroundImage:[t darkPillImage] forState:UIControlStateNormal];
        [_qualityButton addTarget:self action:@selector(qualityTapped) forControlEvents:UIControlEventTouchUpInside];
        [_controls addSubview:_qualityButton];

        _playButton = [self iconButtonWithImage:[t playIcon] action:@selector(playTapped)];
        _playButton.accessibilityLabel = L(@"Play");
        _backButton = [self iconButtonWithImage:[t skipIconForward:NO] action:@selector(backTapped)];
        _backButton.accessibilityLabel = L(@"Back 10 seconds");
        _forwardButton = [self iconButtonWithImage:[t skipIconForward:YES] action:@selector(forwardTapped)];
        _forwardButton.accessibilityLabel = L(@"Forward 10 seconds");
        _liveButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _liveButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [_liveButton setTitle:L(@"LIVE") forState:UIControlStateNormal];
        [_liveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_liveButton setBackgroundImage:[t pillImageWithColor:[t liveColor]] forState:UIControlStateNormal];
        [_liveButton addTarget:self action:@selector(liveTapped) forControlEvents:UIControlEventTouchUpInside];
        [_controls addSubview:_liveButton];
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _statusLabel.backgroundColor = [UIColor clearColor];
        _statusLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        _statusLabel.font = [UIFont systemFontOfSize:12];
        _statusLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        _statusLabel.shadowOffset = CGSizeMake(0, 1);
        [_controls addSubview:_statusLabel];
        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.minimumValue = 0;
        _slider.maximumValue = 1;
        _slider.continuous = YES;
        [_slider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
        [_slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
        [_slider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [_controls addSubview:_slider];
        _timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _timeLabel.backgroundColor = [UIColor clearColor];
        _timeLabel.textColor = [UIColor whiteColor];
        _timeLabel.font = [UIFont boldSystemFontOfSize:11];
        _timeLabel.textAlignment = NSTextAlignmentRight;
        [_controls addSubview:_timeLabel];
        _chatButton = [self iconButtonWithImage:[t chatIconOn:YES] action:@selector(chatTapped)];
        _chatButton.accessibilityLabel = L(@"Chat");
        _fullscreenButton = [self iconButtonWithImage:[t fullscreenIconEnter:YES] action:@selector(fullscreenTapped)];
        _fullscreenButton.accessibilityLabel = L(@"Full screen");
        _adLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _adLabel.backgroundColor = [UIColor colorWithRed:0.85 green:0.65 blue:0.1 alpha:0.9];
        _adLabel.textColor = [UIColor blackColor];
        _adLabel.font = [UIFont boldSystemFontOfSize:11];
        _adLabel.textAlignment = NSTextAlignmentCenter;
        _adLabel.text = L(@"Ad");
        _adLabel.hidden = YES;
        [self addSubview:_adLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.hidesWhenStopped = YES;
        [self addSubview:_spinner];
        _messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _messageLabel.backgroundColor = [UIColor clearColor];
        _messageLabel.textColor = [UIColor whiteColor];
        _messageLabel.font = [UIFont systemFontOfSize:15];
        _messageLabel.numberOfLines = 0;
        _messageLabel.textAlignment = NSTextAlignmentCenter;
        _messageLabel.hidden = YES;
        [self addSubview:_messageLabel];
        _retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [_retryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_retryButton setBackgroundImage:[t accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
        [_retryButton setBackgroundImage:[t accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
        [_retryButton addTarget:self action:@selector(retryTapped) forControlEvents:UIControlEventTouchUpInside];
        _retryButton.hidden = YES;
        [self addSubview:_retryButton];

        _minimizeButton = [self iconButtonWithImage:[t minimizeChevronWhite] action:@selector(minimizeTapped)];
        _minimizeButton.accessibilityLabel = L(@"Minimize");
        _minimizeButton.hidden = YES;

        _chapterLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _chapterLabel.backgroundColor = [UIColor clearColor];
        _chapterLabel.textColor = [UIColor whiteColor];
        _chapterLabel.font = [UIFont boldSystemFontOfSize:11];
        _chapterLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
        _chapterLabel.shadowOffset = CGSizeMake(0, 1);
        _chapterLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _chapterLabel.hidden = YES;
        [_controls addSubview:_chapterLabel];
        _chapterMarkViews = [NSMutableArray array];
        _chapterMarkFractions = [NSMutableArray array];

        _hudLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _hudLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
        _hudLabel.textColor = [UIColor whiteColor];
        _hudLabel.font = [UIFont boldSystemFontOfSize:15];
        _hudLabel.textAlignment = NSTextAlignmentCenter;
        _hudLabel.layer.cornerRadius = 6;
        _hudLabel.clipsToBounds = YES;
        _hudLabel.hidden = YES;
        [self addSubview:_hudLabel];

        // an off-screen system volume control: setting its slider moves the volume without the system HUD appearing
        _volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        _volumeView.alpha = 0.02;
        _volumeView.userInteractionEnabled = NO;
        [self insertSubview:_volumeView atIndex:0];

        _singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
        [self addGestureRecognizer:_singleTap];
        _doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
        _doubleTap.numberOfTapsRequired = 2;
        _doubleTap.enabled = NO;
        [self addGestureRecognizer:_doubleTap];
        [_singleTap requireGestureRecognizerToFail:_doubleTap];
        _pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        _pan.delegate = self;
        _pan.enabled = NO;
        _pan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:_pan];

        _controlsVisible = YES;
        _isLive = YES;
        [self updateModeViews];
    }
    return self;
}

- (void)dealloc
{
    [_hideTimer invalidate];
    [_hudTimer invalidate];
}

- (UIButton *)iconButtonWithImage:(UIImage *)image action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setImage:image forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    b.showsTouchWhenHighlighted = YES;
    [self.controls addSubview:b];
    return b;
}

- (AVPlayerLayer *)playerLayer
{
    return (AVPlayerLayer *)self.videoView.layer;
}

- (void)setPlayer:(AVPlayer *)player
{
    _player = player;
    self.playerLayer.player = player;
}

#pragma mark - State

- (void)setIsLive:(BOOL)isLive { _isLive = isLive; [self updateModeViews]; }
- (void)setChatButtonHidden:(BOOL)hidden { _chatButtonHidden = hidden; [self updateModeViews]; }
- (void)setPlaying:(BOOL)playing
{
    _playing = playing;
    [self.playButton setImage:playing ? [[TBTheme shared] pauseIcon] : [[TBTheme shared] playIcon] forState:UIControlStateNormal];
    self.playButton.accessibilityLabel = playing ? L(@"Pause") : L(@"Play");
}

- (void)setFullscreen:(BOOL)fullscreen
{
    _fullscreen = fullscreen;
    [self.fullscreenButton setImage:[[TBTheme shared] fullscreenIconEnter:!fullscreen] forState:UIControlStateNormal];
    self.fullscreenButton.accessibilityLabel = fullscreen ? L(@"Exit full screen") : L(@"Full screen");
}

- (void)setChatVisible:(BOOL)chatVisible
{
    _chatVisible = chatVisible;
    [self.chatButton setImage:[[TBTheme shared] chatIconOn:chatVisible] forState:UIControlStateNormal];
    self.chatButton.accessibilityLabel = chatVisible ? L(@"Hide chat") : L(@"Show chat");
}

- (void)setCloseIsBack:(BOOL)closeIsBack
{
    _closeIsBack = closeIsBack;
    [self.closeButton setImage:closeIsBack ? [[TBTheme shared] backChevronWhite] : [[TBTheme shared] closeIconWhite] forState:UIControlStateNormal];
    self.closeButton.accessibilityLabel = closeIsBack ? L(@"Back") : L(@"Close");
}
- (void)setTitle:(NSString *)title { _title = [title copy]; self.titleLabel.text = title; }
- (void)setSubtitle:(NSString *)subtitle { _subtitle = [subtitle copy]; [self.subtitleButton setTitle:subtitle forState:UIControlStateNormal]; }
- (void)setStatusText:(NSString *)statusText { _statusText = [statusText copy]; self.statusLabel.text = statusText; }
- (void)setAdBreak:(BOOL)adBreak { _adBreak = adBreak; self.adLabel.hidden = !adBreak; }
- (void)setTopInset:(CGFloat)topInset { _topInset = topInset; [self setNeedsLayout]; }

- (void)setQualityTitle:(NSString *)qualityTitle
{
    _qualityTitle = [qualityTitle copy];
    [self.qualityButton setTitle:qualityTitle.length ? [qualityTitle stringByAppendingString:@" ▾"] : @"" forState:UIControlStateNormal];
    self.qualityButton.hidden = qualityTitle.length == 0;
    [self setNeedsLayout];
}

- (void)updateModeViews
{
    self.liveButton.hidden = !self.isLive;
    self.slider.hidden = self.isLive;
    self.timeLabel.hidden = self.isLive;
    self.backButton.hidden = self.isLive;
    self.forwardButton.hidden = self.isLive;
    self.chatButton.hidden = self.chatButtonHidden;
    [self setNeedsLayout];
}

- (void)setBuffering:(BOOL)buffering
{
    if (buffering) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

- (void)showMessage:(NSString *)text retryTitle:(NSString *)retry
{
    self.messageLabel.text = text;
    self.messageLabel.hidden = text.length == 0;
    self.retryButton.hidden = retry.length == 0;
    [self.retryButton setTitle:retry forState:UIControlStateNormal];
    if (text.length) {
        [self.spinner stopAnimating];
        self.controlsLocked = YES;
        [self showControls:YES animated:YES];
    }
    [self setNeedsLayout];
}

- (void)setProgress:(double)fraction duration:(NSTimeInterval)duration position:(NSTimeInterval)position
{
    self.duration = duration;
    if (!self.scrubbing) {
        self.slider.value = (float)MAX(0, MIN(1, fraction));
        self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [TBUtils formatDuration:position], [TBUtils formatDuration:duration]];
        [self updateChapterLabelForFraction:fraction];
    }
}

#pragma mark - Controls visibility

- (void)showControls:(BOOL)show animated:(BOOL)animated
{
    [self.hideTimer invalidate];
    self.hideTimer = nil;
    self.controlsVisible = show;
    void (^change)(void) = ^{ self.controls.alpha = show ? 1.0 : 0.0; };
    if (animated) [UIView animateWithDuration:0.25 animations:change];
    else change();
    if (show && !self.controlsLocked) {
        self.hideTimer = [NSTimer scheduledTimerWithTimeInterval:TBControlsHideDelay target:self selector:@selector(hideTimerFired) userInfo:nil repeats:NO];
    }
}

- (void)showControlsBriefly
{
    [self showControls:YES animated:YES];
}

- (void)hideTimerFired
{
    if (self.controlsLocked || self.scrubbing) { [self showControls:YES animated:NO]; return; }
    [self showControls:NO animated:YES];
}

- (void)setControlsLocked:(BOOL)controlsLocked
{
    _controlsLocked = controlsLocked;
    if (controlsLocked) [self showControls:YES animated:YES];
    else if (self.controlsVisible) [self showControls:YES animated:NO];   // (starts the timer)
}

- (void)tapped:(UITapGestureRecognizer *)gesture
{
    CGPoint p = [gesture locationInView:self];
    if (self.controlsVisible && !self.controlsLocked) {
        // a tap on the bars is for the buttons (they handle it themselves); one on the picture hides the controls
        if (p.y > self.topInset + TBBarHeight && p.y < self.bounds.size.height - TBBarHeight) [self showControls:NO animated:YES];
        else [self showControls:YES animated:NO];
    } else {
        [self showControls:YES animated:YES];
    }
}

#pragma mark - Actions

- (void)closeTapped { [self.delegate playerViewDidTapClose:self]; }
- (void)playTapped { [self.delegate playerViewDidTapPlayPause:self]; [self showControls:YES animated:NO]; }
- (void)qualityTapped { [self.delegate playerViewDidTapQuality:self fromView:self.qualityButton]; }
- (void)chatTapped { [self.delegate playerViewDidTapChat:self]; [self showControls:YES animated:NO]; }
- (void)fullscreenTapped { [self.delegate playerViewDidTapFullscreen:self]; [self showControls:YES animated:NO]; }
- (void)channelTapped { [self.delegate playerViewDidTapChannel:self]; }
- (void)liveTapped { [self.delegate playerViewDidTapGoLive:self]; [self showControls:YES animated:NO]; }
- (void)backTapped { [self.delegate playerView:self didSkipSeconds:-10]; [self showControls:YES animated:NO]; }
- (void)forwardTapped { [self.delegate playerView:self didSkipSeconds:10]; [self showControls:YES animated:NO]; }
- (void)retryTapped { if (self.retryHandler) self.retryHandler(); }

- (void)sliderTouchDown
{
    self.scrubbing = YES;
    [self showControls:YES animated:NO];
}

- (void)sliderChanged
{
    if (self.duration > 0) {
        self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", [TBUtils formatDuration:self.slider.value * self.duration], [TBUtils formatDuration:self.duration]];
    }
    [self updateChapterLabelForFraction:self.slider.value];
}

- (void)sliderTouchUp
{
    self.scrubbing = NO;
    [self.delegate playerView:self didSeekToFraction:self.slider.value];
    [self showControls:YES animated:NO];
}

- (void)minimizeTapped
{
    if ([self.delegate respondsToSelector:@selector(playerViewDidTapMinimize:)]) [self.delegate playerViewDidTapMinimize:self];
}

#pragma mark - Minimize button visibility

- (void)setDelegate:(id<TBPlayerViewDelegate>)delegate
{
    _delegate = delegate;
    [self updateMinimizeVisibility];
}

- (void)setMinimizeButtonHidden:(BOOL)minimizeButtonHidden
{
    _minimizeButtonHidden = minimizeButtonHidden;
    [self updateMinimizeVisibility];
}

- (void)updateMinimizeVisibility
{
    BOOL responds = [self.delegate respondsToSelector:@selector(playerViewDidTapMinimize:)];
    self.minimizeButton.hidden = !(responds && !self.minimizeButtonHidden);
    [self setNeedsLayout];
}

#pragma mark - Chapters

- (void)setChapterFractions:(NSArray *)fractions titles:(NSArray *)titles
{
    self.chapterFractions = fractions;
    self.chapterTitles = titles;
    for (UIView *v in self.chapterMarkViews) [v removeFromSuperview];
    [self.chapterMarkViews removeAllObjects];
    [self.chapterMarkFractions removeAllObjects];
    for (NSUInteger i = 0; i < fractions.count; i++) {
        double f = [fractions[i] doubleValue];
        if (f <= 0.001 || f >= 0.999) continue;   // the 0:00 start and anything at the very end need no mark
        UIView *tick = [[UIView alloc] initWithFrame:CGRectZero];
        tick.backgroundColor = [UIColor colorWithWhite:1 alpha:0.85];
        tick.userInteractionEnabled = NO;
        [self.controls addSubview:tick];
        [self.chapterMarkViews addObject:tick];
        [self.chapterMarkFractions addObject:@(f)];
    }
    self.chapterLabel.hidden = (titles.count == 0) || self.isLive;
    [self updateChapterLabelForFraction:self.slider.value];
    [self setNeedsLayout];
}

- (void)updateChapterLabelForFraction:(double)fraction
{
    if (!self.chapterTitles.count || self.isLive) { self.chapterLabel.text = @""; return; }
    NSInteger idx = 0;
    for (NSUInteger i = 0; i < self.chapterFractions.count; i++) {
        if (fraction + 1e-6 >= [self.chapterFractions[i] doubleValue]) idx = (NSInteger)i; else break;
    }
    NSString *title = self.chapterTitles[(NSUInteger)idx];
    if (![title isEqualToString:self.chapterLabel.text]) self.chapterLabel.text = title;
}

#pragma mark - Gestures

- (void)setAdvancedGesturesEnabled:(BOOL)advancedGesturesEnabled
{
    _advancedGesturesEnabled = advancedGesturesEnabled;
    self.doubleTap.enabled = advancedGesturesEnabled;
    self.pan.enabled = advancedGesturesEnabled;
}

- (void)doubleTapped:(UITapGestureRecognizer *)gesture
{
    if (!self.advancedGesturesEnabled || self.isLive) return;
    CGPoint p = [gesture locationInView:self];
    if (p.y < self.topInset + TBBarHeight || p.y > self.bounds.size.height - TBBarHeight) return;  // the bars own their taps
    BOOL forward = p.x > self.bounds.size.width / 2;
    [self.delegate playerView:self didSkipSeconds:forward ? 10 : -10];
    [self showHUD:forward ? @"+10 s" : @"-10 s"];
    [self hideHUDAfterDelay];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture
{
    if (!self.advancedGesturesEnabled) return;
    CGPoint t = [gesture translationInView:self];
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
            self.panActive = NO;
            self.panIgnore = NO;
            break;
        case UIGestureRecognizerStateChanged: {
            if (self.panIgnore) return;
            if (!self.panActive) {
                if (fabs(t.y) > 10 && fabs(t.y) > fabs(t.x)) {
                    self.panActive = YES;
                    CGPoint start = [gesture locationInView:self];
                    self.panIsVolume = start.x > self.bounds.size.width / 2;
                    self.panStartValue = self.panIsVolume ? [self systemVolume] : [UIScreen mainScreen].brightness;
                } else if (fabs(t.x) > 10) {
                    self.panIgnore = YES;   // a horizontal drag is not ours
                    return;
                } else {
                    return;
                }
            }
            CGFloat range = MAX(120.0, self.bounds.size.height * 0.75);
            CGFloat value = MAX(0, MIN(1, self.panStartValue + (-t.y / range)));   // drag up raises
            if (self.panIsVolume) [self setSystemVolume:value];
            else [UIScreen mainScreen].brightness = value;
            [self showHUD:[NSString stringWithFormat:@"%@ %d%%", self.panIsVolume ? @"\U0001F50A" : @"☀", (int)round(value * 100)]];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            self.panActive = NO;
            self.panIgnore = NO;
            [self hideHUDAfterDelay];
            break;
        default:
            break;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (gestureRecognizer == self.pan) {
        if (!self.advancedGesturesEnabled) return NO;
        if ([touch.view isKindOfClass:[UIControl class]]) return NO;   // the slider and the buttons keep their touches
        CGPoint p = [touch locationInView:self];
        if (p.y > self.bounds.size.height - TBBarHeight) return NO;    // the scrubber row
        if (p.y < self.topInset + TBBarHeight) return NO;              // the top bar
    }
    return YES;
}

#pragma mark - Brightness / volume HUD

- (UISlider *)findVolumeSlider
{
    if (self.systemVolumeSlider) return self.systemVolumeSlider;
    for (UIView *v in self.volumeView.subviews) if ([v isKindOfClass:[UISlider class]]) { self.systemVolumeSlider = (UISlider *)v; break; }
    return self.systemVolumeSlider;
}

- (CGFloat)systemVolume
{
    UISlider *slider = [self findVolumeSlider];
    if (slider) return slider.value;
    return [AVAudioSession sharedInstance].outputVolume;
}

- (void)setSystemVolume:(CGFloat)volume
{
    UISlider *slider = [self findVolumeSlider];
    if (!slider) return;
    [slider setValue:(float)volume animated:NO];
    [slider sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)showHUD:(NSString *)text
{
    [self.hudTimer invalidate];
    self.hudTimer = nil;
    self.hudLabel.text = text;
    [self.hudLabel sizeToFit];
    CGFloat w = self.hudLabel.bounds.size.width + 28, h = 34;
    self.hudLabel.frame = CGRectMake(floor((self.bounds.size.width - w) / 2), floor((self.bounds.size.height - h) / 2), w, h);
    self.hudLabel.hidden = NO;
    self.hudLabel.alpha = 1;
}

- (void)hideHUDAfterDelay
{
    [self.hudTimer invalidate];
    self.hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 target:self selector:@selector(fadeHUD) userInfo:nil repeats:NO];
}

- (void)fadeHUD
{
    [UIView animateWithDuration:0.25 animations:^{ self.hudLabel.alpha = 0; } completion:^(BOOL finished) { self.hudLabel.hidden = YES; }];
}

#pragma mark - Layout

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.videoView.frame = b;
    self.controls.frame = b;
    CGFloat top = self.topInset;
    BOOL narrow = b.size.width < 400;
    self.topGradient.frame = CGRectMake(0, 0, b.size.width, top + TBBarHeight + 20);
    self.bottomGradient.frame = CGRectMake(0, b.size.height - TBBarHeight - 20, b.size.width, TBBarHeight + 20);

    // top bar
    self.closeButton.frame = CGRectMake(4, top + 2, 40, 40);
    CGFloat textX = 48;
    if (!self.minimizeButton.hidden) {
        self.minimizeButton.frame = CGRectMake(48, top + 2, 40, 40);
        textX = 92;
    }
    CGFloat qualityW = self.qualityButton.hidden ? 0 : ceil([self.qualityButton.currentTitle sizeWithFont:self.qualityButton.titleLabel.font].width) + 16;
    self.qualityButton.frame = CGRectMake(b.size.width - 8 - qualityW, top + 11, qualityW, 22);
    CGFloat textW = CGRectGetMinX(self.qualityButton.frame) - 8 - textX;
    self.titleLabel.frame = CGRectMake(textX, top + 4, textW, 20);
    self.subtitleButton.frame = CGRectMake(textX, top + 24, textW, 16);

    // bottom bar
    CGFloat y = b.size.height - TBBarHeight;
    CGFloat x = 4;
    self.playButton.frame = CGRectMake(x, y + 2, 40, 40);
    x += 44;
    if (!self.isLive) {
        self.backButton.frame = CGRectMake(x, y + 2, 40, 40);
        x += 40;
        self.forwardButton.frame = CGRectMake(x, y + 2, 40, 40);
        x += 44;
    }
    CGFloat rightX = b.size.width - 4;
    self.fullscreenButton.frame = CGRectMake(rightX - 40, y + 2, 40, 40);
    rightX -= 44;
    if (!self.chatButton.hidden) {
        self.chatButton.frame = CGRectMake(rightX - 40, y + 2, 40, 40);
        rightX -= 44;
    }
    if (self.isLive) {
        self.liveButton.frame = CGRectMake(x, y + 12, 44, 20);
        x += 50;
        self.statusLabel.frame = CGRectMake(x, y + 13, MAX(0, rightX - x - 4), 18);
    } else {
        CGFloat timeW = narrow ? 80 : 110;
        self.timeLabel.frame = CGRectMake(rightX - timeW, y + 13, timeW, 18);
        rightX -= timeW + 6;
        self.slider.frame = CGRectMake(x, y + 7, MAX(0, rightX - x), 30);
        self.statusLabel.frame = CGRectZero;
    }
    // chapters drawn over the scrubber (videos only)
    if (!self.isLive) {
        CGRect sf = self.slider.frame;
        CGFloat trackX = sf.origin.x + 2, trackW = MAX(1, sf.size.width - 4);
        CGFloat cy = sf.origin.y + sf.size.height / 2;
        for (NSUInteger i = 0; i < self.chapterMarkViews.count; i++) {
            UIView *tick = self.chapterMarkViews[i];
            tick.frame = CGRectMake(floor(trackX + trackW * [self.chapterMarkFractions[i] doubleValue]) - 1, cy - 4, 2, 8);
            tick.hidden = NO;
        }
        self.chapterLabel.frame = CGRectMake(sf.origin.x, sf.origin.y - 16, sf.size.width, 14);
    } else {
        for (UIView *tick in self.chapterMarkViews) tick.hidden = YES;
    }
    self.adLabel.frame = CGRectMake(b.size.width - 50, top + TBBarHeight + 8, 40, 18);
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height / 2);
    CGFloat messageW = MIN(b.size.width - 40, 420);
    self.messageLabel.frame = CGRectMake(floor((b.size.width - messageW) / 2), b.size.height / 2 - 50, messageW, 70);
    self.retryButton.frame = CGRectMake(floor((b.size.width - 140) / 2), b.size.height / 2 + 26, 140, 34);
}

@end
