#import "TBPlaylistViewController.h"
#import "TBWatchViewController.h"
#import "TBNavigator.h"
#import "TBInnertube.h"
#import "TBImageLoader.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

@interface TBPlaylistViewController ()
@property (nonatomic, strong) TBPlaylist *playlist;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) TBImageView *thumbnail;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIButton *playButton;
@end

@implementation TBPlaylistViewController

- (instancetype)initWithPlaylist:(TBPlaylist *)playlist
{
    self = [super initWithStyle:TBGridStyleVideos loader:nil];
    if (self) {
        _playlist = playlist;
        self.title = playlist.title.length ? playlist.title : L(@"Playlist");
        self.emptyText = L(@"This playlist is empty.");
        __weak TBPlaylistViewController *weakSelf = self;
        NSString *playlistId = playlist.playlistId;
        self.loader = ^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            if (continuation.length) {
                return [TBInnertube browse:nil params:nil continuation:continuation completion:^(NSDictionary *response, NSArray *items, NSString *next, NSError *error) {
                    completion(items, next, error);
                }];
            }
            return [TBInnertube playlist:playlistId completion:^(TBPlaylist *loaded, NSArray *items, NSString *next, NSError *error) {
                TBPlaylistViewController *s = weakSelf;
                if (s && loaded) {
                    if (!loaded.thumbnailURL.length) loaded.thumbnailURL = s.playlist.thumbnailURL;
                    s.playlist = loaded;
                    [s fillHeader];
                    [s layoutHeader];
                }
                completion(items, next, error);
            }];
        };
        self.onSelectItem = ^(id item) {
            TBPlaylistViewController *s = weakSelf;
            if (!s) return;
            if (![item isKindOfClass:[TBVideo class]]) { [TBNavigator openItem:item from:s]; return; }
            [s playFrom:item];
        };
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 120)];
    self.thumbnail = [[TBImageView alloc] initWithFrame:CGRectZero];
    self.thumbnail.contentMode = UIViewContentModeScaleAspectFill;
    self.thumbnail.clipsToBounds = YES;
    self.thumbnail.maxPixels = 480;
    [self.header addSubview:self.thumbnail];
    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.backgroundColor = [UIColor clearColor];
    self.nameLabel.font = [UIFont boldSystemFontOfSize:17];
    self.nameLabel.numberOfLines = 2;
    [self.header addSubview:self.nameLabel];
    self.detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.detailLabel.backgroundColor = [UIColor clearColor];
    self.detailLabel.font = [UIFont systemFontOfSize:13];
    self.detailLabel.numberOfLines = 2;
    [self.header addSubview:self.detailLabel];
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.playButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.playButton.titleLabel.shadowOffset = CGSizeMake(0, -1);
    [self.playButton setTitle:L(@"Play all") forState:UIControlStateNormal];
    [self.playButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.playButton setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.4] forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playAllTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.header addSubview:self.playButton];
    self.headerView = self.header;
    [self applyHeaderTheme];
    [self fillHeader];
    [self layoutHeader];
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
    self.nameLabel.textColor = [t primaryTextColor];
    self.detailLabel.textColor = [t secondaryTextColor];
    [self.playButton setBackgroundImage:[t accentButtonImageHighlighted:NO disabled:NO] forState:UIControlStateNormal];
    [self.playButton setBackgroundImage:[t accentButtonImageHighlighted:YES disabled:NO] forState:UIControlStateHighlighted];
}

- (void)fillHeader
{
    TBPlaylist *p = self.playlist;
    self.nameLabel.text = p.title ?: @"";
    NSMutableArray *parts = [NSMutableArray array];
    if (p.ownerName.length) [parts addObject:p.ownerName];
    if (p.videoCountText.length) [parts addObject:p.videoCountText];
    self.detailLabel.text = [parts componentsJoinedByString:@" · "];
    [self.thumbnail setImageURL:p.thumbnailURL placeholder:[[TBTheme shared] thumbnailPlaceholder]];
    self.title = p.title.length ? p.title : self.title;
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
    CGFloat pad = 12, thumbW = w >= 500 ? 200 : 128, thumbH = floor(thumbW * 9.0 / 16.0);
    self.thumbnail.frame = CGRectMake(pad, pad, thumbW, thumbH);
    CGFloat x = pad + thumbW + 12, tw = w - x - pad;
    self.nameLabel.frame = CGRectMake(x, pad, tw, 42);
    self.detailLabel.frame = CGRectMake(x, pad + 44, tw, 32);
    self.playButton.frame = CGRectMake(x, pad + 80, 120, 32);
    CGFloat h = MAX(pad + thumbH, pad + 112) + pad;
    if (fabs(self.header.frame.size.height - h) > 0.5 || fabs(self.header.frame.size.width - w) > 0.5) {
        self.header.frame = CGRectMake(0, 0, w, h);
        [self setHeaderHeight:h];
    }
}

- (void)playFrom:(TBVideo *)video
{
    NSArray *items = self.items;
    NSUInteger index = [items indexOfObject:video];
    TBWatchViewController *watch = [[TBWatchViewController alloc] initWithVideo:video];
    watch.queue = items;
    watch.queueIndex = index == NSNotFound ? 0 : index;
    watch.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [[TBNavigator presenterFrom:self] presentViewController:watch animated:YES completion:nil];
}

- (void)playAllTapped
{
    for (id item in self.items) if ([item isKindOfClass:[TBVideo class]]) { [self playFrom:item]; return; }
}

@end
