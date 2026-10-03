#import "TBChannelViewController.h"
#import "TBInnertube.h"
#import "TBLibrary.h"
#import "TBAccount.h"
#import "TBImageLoader.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface TBChannelViewController ()
@property (nonatomic, strong) TBChannel *channel;
@property (nonatomic, strong) TBHTTPTask *channelTask;
@property (nonatomic, strong) TBHTTPTask *accountTask;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) TBImageView *banner;
@property (nonatomic, strong) TBImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIButton *subscribeButton;
@property (nonatomic, strong) UISegmentedControl *segments;
@property (nonatomic, strong) NSArray *shownTabs;        // TBChannelTab behind the segments
@end

@implementation TBChannelViewController

- (instancetype)initWithChannel:(TBChannel *)channel
{
    self = [super initWithStyle:TBGridStyleVideos loader:nil];
    if (self) {
        _channel = channel;
        self.title = channel.title.length ? channel.title : L(@"Channel");
        self.emptyText = L(@"Nothing here.");
        self.refreshesOnAppear = NO;
    }
    return self;
}

- (void)dealloc
{
    [_channelTask cancel];
    [_accountTask cancel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self buildHeader];
    [self applyHeaderTheme];
    [self fillHeader];
    [self layoutHeader];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
    [self loadChannel];
}

- (void)buildHeader
{
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 200)];
    self.banner = [[TBImageView alloc] initWithFrame:CGRectZero];
    self.banner.contentMode = UIViewContentModeScaleAspectFill;
    self.banner.clipsToBounds = YES;
    self.banner.maxPixels = 1024;
    [self.header addSubview:self.banner];
    self.avatar = [[TBImageView alloc] initWithFrame:CGRectZero];
    self.avatar.contentMode = UIViewContentModeScaleAspectFill;
    self.avatar.clipsToBounds = YES;
    self.avatar.maxPixels = 200;
    self.avatar.layer.borderWidth = 3;
    [self.header addSubview:self.avatar];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:20];
    self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.header addSubview:self.nameLabel];
    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.detailLabel.backgroundColor = [UIColor clearColor];
    self.detailLabel.font = [UIFont systemFontOfSize:13];
    self.detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.header addSubview:self.detailLabel];
    self.descriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.descriptionLabel.backgroundColor = [UIColor clearColor];
    self.descriptionLabel.font = [UIFont systemFontOfSize:13];
    self.descriptionLabel.numberOfLines = 2;
    [self.header addSubview:self.descriptionLabel];
    self.subscribeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.subscribeButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.subscribeButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.subscribeButton addTarget:self action:@selector(subscribeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.subscribeButton];
    self.segments = [[UISegmentedControl alloc] initWithItems:@[ L(@"Videos") ]];
    self.segments.segmentedControlStyle = UISegmentedControlStyleBar;
    self.segments.selectedSegmentIndex = 0;
    [self.segments addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    [self.header addSubview:self.segments];
    self.headerView = self.header;
}

- (void)applyTheme
{
    [super applyTheme];
    if (self.header) [self applyHeaderTheme];
}

- (void)applyHeaderTheme
{
    TBTheme *t = [TBTheme shared];
    self.header.backgroundColor = [t cardColor];
    self.banner.backgroundColor = t.isDark ? [UIColor colorWithWhite:0.15 alpha:1] : [UIColor colorWithWhite:0.82 alpha:1];
    self.nameLabel.textColor = [t primaryTextColor];
    self.detailLabel.textColor = [t secondaryTextColor];
    self.descriptionLabel.textColor = [t secondaryTextColor];
    self.avatar.layer.borderColor = [t cardColor].CGColor;
    [self updateSubscribeButton];
}

- (void)fillHeader
{
    TBChannel *c = self.channel;
    self.nameLabel.text = c.title ?: @"";
    NSMutableArray *parts = [NSMutableArray array];
    if (c.handle.length) [parts addObject:c.handle];
    if (c.subscribersText.length) [parts addObject:c.subscribersText];
    if (c.videoCountText.length) [parts addObject:c.videoCountText];
    self.detailLabel.text = [parts componentsJoinedByString:@" · "];
    self.descriptionLabel.text = c.descriptionText ?: @"";
    [self.avatar setImageURL:c.avatarURL placeholder:[[TBTheme shared] avatarPlaceholderWithSize:80]];
    [self.banner setImageURL:c.bannerURL placeholder:nil];
    self.banner.hidden = !c.bannerURL.length;
    self.title = c.title.length ? c.title : self.title;
    [self updateSubscribeButton];
}

- (void)updateSubscribeButton
{
    TBTheme *t = [TBTheme shared];
    BOOL subscribed = [[TBLibrary shared] isSubscribed:self.channel.channelId];
    [self.subscribeButton setTitle:subscribed ? L(@"Subscribed ✓") : L(@"Subscribe") forState:UIControlStateNormal];
    [self.subscribeButton setTitleColor:subscribed ? [t primaryTextColor] : [UIColor whiteColor] forState:UIControlStateNormal];
    [self.subscribeButton setTitleShadowColor:subscribed ? [UIColor clearColor] : [UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    [self.subscribeButton setBackgroundImage:subscribed ? [t buttonImageHighlighted:NO] : [t accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
    [self.subscribeButton setBackgroundImage:subscribed ? [t buttonImageHighlighted:YES] : [t accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self layoutHeader];
}

- (void)layoutHeader
{
    CGFloat w = self.view.bounds.size.width;
    if (w <= 0) return;
    BOOL wide = w >= 500;
    CGFloat bannerH = self.banner.hidden ? 0 : floor(w / 6.2);
    CGFloat avatarSize = wide ? 88 : 64;
    CGFloat pad = 12;
    self.banner.frame = CGRectMake(0, 0, w, bannerH);
    CGFloat y = bannerH + 10;
    self.avatar.frame = CGRectMake(pad, bannerH ? bannerH - avatarSize / 2 : y, avatarSize, avatarSize);
    self.avatar.layer.cornerRadius = avatarSize / 2;
    CGFloat textX = pad + avatarSize + 12;
    CGFloat buttonW = wide ? 130 : 110;
    self.subscribeButton.frame = CGRectMake(w - pad - buttonW, bannerH ? bannerH + 8 : y + 4, buttonW, 32);
    CGFloat textW = CGRectGetMinX(self.subscribeButton.frame) - 10 - textX;
    CGFloat textY = bannerH ? bannerH + 6 : y;
    self.nameLabel.frame = CGRectMake(textX, textY, textW, 24);
    self.detailLabel.frame = CGRectMake(textX, textY + 26, textW, 16);
    y = MAX(CGRectGetMaxY(self.avatar.frame), textY + 44) + 8;
    NSString *desc = self.descriptionLabel.text ?: @"";
    CGFloat descH = desc.length ? MIN(34, ceil([desc sizeWithFont:self.descriptionLabel.font constrainedToSize:CGSizeMake(w - 2 * pad, 34) lineBreakMode:NSLineBreakByWordWrapping].height)) : 0;
    self.descriptionLabel.frame = CGRectMake(pad, y, w - 2 * pad, descH);
    y += descH ? descH + 8 : 0;
    CGFloat segW = MIN(w - 2 * pad, 420);
    self.segments.frame = CGRectMake(pad, y, segW, 30);
    y += 40;
    if (fabs(self.header.frame.size.height - y) > 0.5 || fabs(self.header.frame.size.width - w) > 0.5) {
        self.header.frame = CGRectMake(0, 0, w, y);
        [self setHeaderHeight:y];
    }
}

#pragma mark - Data

- (void)loadChannel
{
    __weak TBChannelViewController *weakSelf = self;
    [self.channelTask cancel];
    self.channelTask = [TBInnertube channel:self.channel.channelId params:nil completion:^(TBChannel *channel, NSArray *items, NSString *continuation, NSError *error) {
        TBChannelViewController *s = weakSelf;
        if (!s) return;
        s.channelTask = nil;
        if (error) { [TBUtils alertWithTitle:L(@"Channel") message:error.localizedDescription]; return; }
        channel.subscribedAt = s.channel.subscribedAt;
        s.channel = channel;
        [s fillHeader];
        [s setupTabs];
        [s layoutHeader];
        // a subscribed channel keeps its details fresh
        if ([[TBLibrary shared] isSubscribed:channel.channelId]) { [[TBLibrary shared] unsubscribe:channel.channelId]; [[TBLibrary shared] subscribe:channel]; }
    }];
}

- (void)setupTabs
{
    NSMutableArray *tabs = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    for (TBChannelTab *tab in self.channel.tabs) {
        NSString *lower = [tab.title lowercaseString];
        if (!tab.params.length) continue;
        if ([lower rangeOfString:@"home"].location != NSNotFound || [lower isEqualToString:@"domů"] || [lower rangeOfString:@"post"].location != NSNotFound
            || [lower rangeOfString:@"příspěv"].location != NSNotFound || [lower rangeOfString:@"store"].location != NSNotFound || [lower rangeOfString:@"obchod"].location != NSNotFound
            || [lower rangeOfString:@"search"].location != NSNotFound || [lower rangeOfString:@"hledat"].location != NSNotFound || [lower rangeOfString:@"about"].location != NSNotFound) continue;
        [tabs addObject:tab];
        [titles addObject:tab.title];
        if (tabs.count >= 4) break;
    }
    if (!tabs.count) {
        // (an unusual channel: whatever the home tab had)
        TBChannelTab *home = [[TBChannelTab alloc] init];
        home.title = L(@"Videos");
        home.params = @"";
        [tabs addObject:home];
        [titles addObject:home.title];
    }
    self.shownTabs = tabs;
    [self.segments removeAllSegments];
    for (NSUInteger i = 0; i < titles.count; i++) [self.segments insertSegmentWithTitle:titles[i] atIndex:i animated:NO];
    self.segments.selectedSegmentIndex = 0;
    [self segmentChanged];
}

- (void)segmentChanged
{
    NSInteger index = self.segments.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)self.shownTabs.count) return;
    TBChannelTab *tab = self.shownTabs[(NSUInteger)index];
    NSString *channelId = self.channel.channelId, *params = tab.params;
    NSString *lower = [tab.title lowercaseString];
    self.style = ([lower rangeOfString:@"short"].location != NSNotFound) ? TBGridStyleShorts : TBGridStyleVideos;
    TBChannel *channel = self.channel;
    [self setLoader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
        return [TBInnertube browse:channelId params:params.length ? params : nil continuation:continuation completion:^(NSDictionary *response, NSArray *items, NSString *next, NSError *error) {
            for (id item in items) {
                if ([item isKindOfClass:[TBVideo class]]) {
                    TBVideo *v = item;
                    if (!v.channelName.length) { v.channelName = channel.title; v.channelId = channel.channelId; }
                    if (!v.channelAvatarURL.length) v.channelAvatarURL = channel.avatarURL;
                }
            }
            completion(items, next, error);
        }];
    } andReload:YES];
}

- (void)subscribeTapped
{
    TBLibrary *library = [TBLibrary shared];
    TBChannel *channel = self.channel;
    BOOL subscribed = [library isSubscribed:channel.channelId];
    if ([[TBAccount shared] isSignedIn]) {
        __weak TBChannelViewController *weakSelf = self;
        self.subscribeButton.enabled = NO;
        void (^done)(NSError *) = ^(NSError *error) {
            TBChannelViewController *s = weakSelf;
            s.subscribeButton.enabled = YES;
            if (error) { [TBUtils alertWithTitle:L(@"Subscriptions") message:error.localizedDescription]; return; }
            if (subscribed) [library unsubscribe:channel.channelId]; else [library subscribe:channel];
            [s updateSubscribeButton];
        };
        [self.accountTask cancel];
        self.accountTask = subscribed ? [[TBAccount shared] unsubscribeFrom:channel.channelId completion:done] : [[TBAccount shared] subscribeTo:channel completion:done];
        return;
    }
    if (subscribed) [library unsubscribe:channel.channelId];
    else [library subscribe:channel];
    [self updateSubscribeButton];
}

- (void)libraryChanged
{
    [self updateSubscribeButton];
}

@end
