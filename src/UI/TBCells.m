#import "TBCells.h"
#import "TBImageLoader.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kCardPad = 8;
static const CGFloat kCardTextHeight = 64;
static const CGFloat kRowHeight = 92;
static const CGFloat kRowThumbWidth = 136;

#pragma mark - Pill

@interface TBPillLabel ()
@property (nonatomic, strong) UIImageView *background;
@property (nonatomic, strong) UILabel *label;
@end

@implementation TBPillLabel

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _background = [[UIImageView alloc] initWithFrame:self.bounds];
        _background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_background];
        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.backgroundColor = [UIColor clearColor];
        _label.textColor = [UIColor whiteColor];
        _label.font = [UIFont boldSystemFontOfSize:11];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.shadowColor = [UIColor colorWithWhite:0 alpha:0.5];
        _label.shadowOffset = CGSizeMake(0, -1);
        [self addSubview:_label];
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setText:(NSString *)text image:(UIImage *)image
{
    self.label.text = text;
    self.background.image = image;
    CGSize size = [text sizeWithFont:self.label.font];
    CGRect f = self.frame;
    f.size = CGSizeMake(ceil(size.width) + 12, 18);
    self.frame = f;
    self.label.frame = self.bounds;
    self.hidden = text.length == 0;
}

@end

#pragma mark - Video cell

@interface TBVideoCell ()
@property (nonatomic, strong) UIImageView *cardBackground;
@property (nonatomic, strong) TBImageView *thumbnail;
@property (nonatomic, strong) TBImageView *avatar;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) TBPillLabel *lengthPill;
@property (nonatomic, strong) TBPillLabel *livePill;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressBar;
@property (nonatomic, strong) UIImageView *stackImage;      // the "list" sign of playlists
@property (nonatomic) BOOL card;
@property (nonatomic) BOOL showsAvatar;
@property (nonatomic) double progress;
@end

@implementation TBVideoCell

+ (NSString *)reuseIdentifier { return @"video"; }
+ (CGFloat)rowHeight { return kRowHeight; }

+ (CGFloat)cardHeightForWidth:(CGFloat)width
{
    return floor((width - 2 * kCardPad) * 9.0 / 16.0) + kCardTextHeight + kCardPad * 2;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _cardBackground = [[UIImageView alloc] initWithFrame:self.bounds];
        [self.contentView addSubview:_cardBackground];
        _thumbnail = [[TBImageView alloc] initWithFrame:CGRectZero];
        _thumbnail.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnail.clipsToBounds = YES;
        _thumbnail.maxPixels = 640;
        [self.contentView addSubview:_thumbnail];
        _avatar = [[TBImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.maxPixels = 120;
        [self.contentView addSubview:_avatar];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_titleLabel];
        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.numberOfLines = 2;
        _metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_metaLabel];
        _lengthPill = [[TBPillLabel alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_lengthPill];
        _livePill = [[TBPillLabel alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_livePill];
        _progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
        _progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        _progressTrack.hidden = YES;
        [self.contentView addSubview:_progressTrack];
        _progressBar = [[UIView alloc] initWithFrame:CGRectZero];
        [_progressTrack addSubview:_progressBar];
        _stackImage = [[UIImageView alloc] initWithFrame:CGRectZero];
        _stackImage.hidden = YES;
        [self.contentView addSubview:_stackImage];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.cardBackground.image = [t cardBackgroundImage];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 14 : 13];
    self.titleLabel.textColor = [t primaryTextColor];
    self.metaLabel.font = [UIFont systemFontOfSize:TBIsPad() ? 12 : 11];
    self.metaLabel.textColor = [t secondaryTextColor];
    self.thumbnail.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.progressBar.backgroundColor = [t liveColor];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    TBTheme *t = [TBTheme shared];
    self.cardBackground.image = highlighted ? [t cardBackgroundImageHighlighted] : [t cardBackgroundImage];
}

- (void)configureWithVideo:(TBVideo *)video asCard:(BOOL)card
{
    TBTheme *t = [TBTheme shared];
    self.card = card;
    self.titleLabel.text = video.title.length ? video.title : L(@"Untitled");
    self.metaLabel.text = [video metaText];
    self.showsAvatar = card && video.channelAvatarURL.length > 0;
    self.avatar.hidden = !self.showsAvatar;
    if (self.showsAvatar) [self.avatar setImageURL:video.channelAvatarURL placeholder:[t avatarPlaceholderWithSize:24]];
    NSString *thumb = card ? [video thumbnailURLForWidth:[TBUtils screenScale] > 1.5 ? 640 : 480] : [video thumbnailURLForWidth:320];
    if (!video.videoId.length) thumb = video.thumbnailURL;
    [self.thumbnail setImageURL:thumb placeholder:[t thumbnailPlaceholder]];
    // (a short among ordinary videos says so where the length would be)
    [self.lengthPill setText:video.isLive ? nil : (video.lengthText.length ? video.lengthText : (video.isShort ? L(@"Shorts") : nil)) image:[t darkPillImage]];
    [self.livePill setText:video.isLive ? L(@"LIVE") : (video.isUpcoming ? L(@"UPCOMING") : nil) image:video.isLive ? [t pillImageWithColor:[t liveColor]] : [t darkPillImage]];
    self.progress = (video.position > 5 && video.lengthSeconds > 0) ? MIN(1.0, video.position / video.lengthSeconds) : 0;
    self.progressTrack.hidden = self.progress <= 0;
    self.stackImage.hidden = YES;
    [self setNeedsLayout];
}

- (void)configureWithPlaylist:(TBPlaylist *)playlist asCard:(BOOL)card
{
    TBTheme *t = [TBTheme shared];
    self.card = card;
    self.titleLabel.text = playlist.title.length ? playlist.title : L(@"Playlist");
    NSMutableArray *parts = [NSMutableArray array];
    if (playlist.ownerName.length) [parts addObject:playlist.ownerName];
    [parts addObject:L(@"Playlist")];
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    self.showsAvatar = NO;
    self.avatar.hidden = YES;
    [self.thumbnail setImageURL:playlist.thumbnailURL placeholder:[t thumbnailPlaceholder]];
    [self.lengthPill setText:playlist.videoCountText.length ? playlist.videoCountText : L(@"Playlist") image:[t darkPillImage]];
    [self.livePill setText:nil image:nil];
    self.progress = 0;
    self.progressTrack.hidden = YES;
    self.stackImage.hidden = YES;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    self.cardBackground.frame = b;
    if (self.card) {
        CGFloat w = b.size.width - 2 * kCardPad;
        CGFloat h = floor(w * 9.0 / 16.0);
        self.thumbnail.frame = CGRectMake(kCardPad, kCardPad, w, h);
        CGFloat y = kCardPad + h + 7;
        CGFloat x = kCardPad;
        if (self.showsAvatar) {
            self.avatar.frame = CGRectMake(kCardPad, y + 2, 28, 28);
            self.avatar.layer.cornerRadius = 14;
            x = kCardPad + 36;
        }
        CGFloat tw = b.size.width - x - kCardPad;
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.frame = CGRectMake(x, y, tw, 34);
        self.metaLabel.numberOfLines = 1;
        self.metaLabel.frame = CGRectMake(x, y + 36, tw, 16);
    } else {
        CGFloat th = floor(kRowThumbWidth * 9.0 / 16.0);
        self.thumbnail.frame = CGRectMake(kCardPad, floor((b.size.height - th) / 2), kRowThumbWidth, th);
        CGFloat x = kCardPad + kRowThumbWidth + 10;
        CGFloat tw = b.size.width - x - kCardPad;
        self.titleLabel.numberOfLines = 2;
        self.titleLabel.frame = CGRectMake(x, 9, tw, 36);
        self.metaLabel.numberOfLines = 2;
        self.metaLabel.frame = CGRectMake(x, 47, tw, 32);
    }
    CGRect tf = self.thumbnail.frame;
    CGRect lp = self.lengthPill.frame;
    self.lengthPill.frame = CGRectMake(CGRectGetMaxX(tf) - 5 - lp.size.width, CGRectGetMaxY(tf) - 23, lp.size.width, lp.size.height);
    CGRect lv = self.livePill.frame;
    self.livePill.frame = CGRectMake(tf.origin.x + 5, tf.origin.y + 5, lv.size.width, lv.size.height);
    self.progressTrack.frame = CGRectMake(tf.origin.x, CGRectGetMaxY(tf) - 3, tf.size.width, 3);
    self.progressBar.frame = CGRectMake(0, 0, floor(tf.size.width * self.progress), 3);
}

@end

#pragma mark - Short cell

@interface TBShortCell ()
@property (nonatomic, strong) TBImageView *thumbnail;
@property (nonatomic, strong) UIImageView *shade;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *viewsLabel;
@end

@implementation TBShortCell

+ (NSString *)reuseIdentifier { return @"short"; }

+ (CGFloat)heightForWidth:(CGFloat)width
{
    return floor(width * 16.0 / 9.0);
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _thumbnail = [[TBImageView alloc] initWithFrame:self.bounds];
        _thumbnail.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnail.clipsToBounds = YES;
        _thumbnail.maxPixels = 480;
        _thumbnail.layer.cornerRadius = 6;
        _thumbnail.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
        [self.contentView addSubview:_thumbnail];
        _shade = [[UIImageView alloc] initWithFrame:CGRectZero];
        _shade.layer.cornerRadius = 6;
        _shade.clipsToBounds = YES;
        [self.contentView addSubview:_shade];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.textColor = [UIColor whiteColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:12];
        _titleLabel.numberOfLines = 2;
        _titleLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
        _titleLabel.shadowOffset = CGSizeMake(0, 1);
        [self.contentView addSubview:_titleLabel];
        _viewsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _viewsLabel.backgroundColor = [UIColor clearColor];
        _viewsLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        _viewsLabel.font = [UIFont systemFontOfSize:11];
        _viewsLabel.shadowColor = [UIColor colorWithWhite:0 alpha:0.8];
        _viewsLabel.shadowOffset = CGSizeMake(0, 1);
        [self.contentView addSubview:_viewsLabel];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme
{
    self.shade.image = [[TBTheme shared] controlsGradientImageTop:NO];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    self.thumbnail.alpha = highlighted ? 0.7 : 1.0;
}

- (void)configureWithVideo:(TBVideo *)video
{
    // hqdefault (16 KB) has the upright picture in its middle, between black bars that the aspect-fill crops away;
    // the upright "oar2" picture itself is ten times the size - too much for a grid of them on this hardware
    NSString *url = video.videoId.length ? [video thumbnailURLForWidth:480] : video.thumbnailURL;
    [self.thumbnail setImageURL:url fallback:video.thumbnailURL placeholder:[[TBTheme shared] thumbnailPlaceholder]];
    self.titleLabel.text = video.title ?: @"";
    self.viewsLabel.text = video.viewsText ?: @"";
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    self.thumbnail.frame = b;
    self.shade.frame = CGRectMake(0, b.size.height - 70, b.size.width, 70);
    self.titleLabel.frame = CGRectMake(6, b.size.height - 50, b.size.width - 12, 30);
    self.viewsLabel.frame = CGRectMake(6, b.size.height - 19, b.size.width - 12, 14);
}

@end

#pragma mark - Channel cell

@interface TBChannelCell ()
@property (nonatomic, strong) UIImageView *cardBackground;
@property (nonatomic, strong) TBImageView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIImageView *chevron;
@end

@implementation TBChannelCell

+ (NSString *)reuseIdentifier { return @"channel"; }
+ (CGFloat)height { return 64; }

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        _cardBackground = [[UIImageView alloc] initWithFrame:self.bounds];
        [self.contentView addSubview:_cardBackground];
        _avatar = [[TBImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.maxPixels = 150;
        [self.contentView addSubview:_avatar];
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.backgroundColor = [UIColor clearColor];
        _nameLabel.font = [UIFont boldSystemFontOfSize:15];
        [self.contentView addSubview:_nameLabel];
        _detailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _detailLabel.backgroundColor = [UIColor clearColor];
        _detailLabel.font = [UIFont systemFontOfSize:12];
        _detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_detailLabel];
        _chevron = [[UIImageView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_chevron];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.cardBackground.image = [t cardBackgroundImage];
    self.nameLabel.textColor = [t primaryTextColor];
    self.detailLabel.textColor = [t secondaryTextColor];
    self.chevron.image = [t disclosureChevronImage];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    TBTheme *t = [TBTheme shared];
    self.cardBackground.image = highlighted ? [t cardBackgroundImageHighlighted] : [t cardBackgroundImage];
}

- (void)configureWithChannel:(TBChannel *)channel
{
    [self.avatar setImageURL:channel.avatarURL placeholder:[[TBTheme shared] avatarPlaceholderWithSize:44]];
    self.nameLabel.text = channel.title ?: channel.handle;
    NSMutableArray *parts = [NSMutableArray array];
    if (channel.handle.length) [parts addObject:channel.handle];
    if (channel.subscribersText.length) [parts addObject:channel.subscribersText];
    if (channel.videoCountText.length) [parts addObject:channel.videoCountText];
    self.detailLabel.text = [parts componentsJoinedByString:@" · "];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    self.cardBackground.frame = CGRectMake(0, 0, b.size.width, b.size.height);
    self.avatar.frame = CGRectMake(12, 10, 44, 44);
    self.avatar.layer.cornerRadius = 22;
    CGFloat x = 68, w = b.size.width - x - 30;
    self.nameLabel.frame = CGRectMake(x, 13, w, 20);
    self.detailLabel.frame = CGRectMake(x, 35, w, 16);
    CGSize cs = self.chevron.image.size;
    self.chevron.frame = CGRectMake(b.size.width - 12 - cs.width, floor((b.size.height - cs.height) / 2), cs.width, cs.height);
}

@end

#pragma mark - Header

@interface TBGridHeaderView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *moreButton;
@end

@implementation TBGridHeaderView

+ (NSString *)reuseIdentifier { return @"header"; }
+ (CGFloat)height { return 34; }

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16];
        _titleLabel.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_titleLabel];
        _moreButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _moreButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [_moreButton setTitle:L(@"More") forState:UIControlStateNormal];
        _moreButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
        [self addSubview:_moreButton];
        [self applyTheme];
    }
    return self;
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.titleLabel.textColor = [t primaryTextColor];
    self.titleLabel.shadowColor = t.isDark ? [UIColor colorWithWhite:0 alpha:0.6] : [UIColor colorWithWhite:1 alpha:0.8];
    [self.moreButton setTitleColor:[t accentColor] forState:UIControlStateNormal];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.bounds;
    self.titleLabel.frame = CGRectMake(12, 8, b.size.width - 100, 22);
    self.moreButton.frame = CGRectMake(b.size.width - 92, 6, 80, 26);
}

@end

#pragma mark - Video table cell

@interface TBVideoTableCell ()
@property (nonatomic, strong) TBImageView *thumbnail;
@property (nonatomic, strong) TBPillLabel *lengthPill;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressBar;
@property (nonatomic) double progress;
@end

@implementation TBVideoTableCell

+ (NSString *)reuseIdentifier { return @"videoRow"; }
+ (CGFloat)height { return 84; }

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        _thumbnail = [[TBImageView alloc] initWithFrame:CGRectZero];
        _thumbnail.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnail.clipsToBounds = YES;
        _thumbnail.maxPixels = 320;
        _thumbnail.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
        [self.contentView addSubview:_thumbnail];
        _lengthPill = [[TBPillLabel alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_lengthPill];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.font = [UIFont boldSystemFontOfSize:13];
        [self.contentView addSubview:_titleLabel];
        _metaLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _metaLabel.backgroundColor = [UIColor clearColor];
        _metaLabel.numberOfLines = 2;
        _metaLabel.font = [UIFont systemFontOfSize:11];
        [self.contentView addSubview:_metaLabel];
        _progressTrack = [[UIView alloc] initWithFrame:CGRectZero];
        _progressTrack.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        _progressTrack.hidden = YES;
        [self.contentView addSubview:_progressTrack];
        _progressBar = [[UIView alloc] initWithFrame:CGRectZero];
        [_progressTrack addSubview:_progressBar];
        self.accessoryType = UITableViewCellAccessoryNone;
    }
    return self;
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    [t styleCell:self];
    self.titleLabel.textColor = [t primaryTextColor];
    self.metaLabel.textColor = [t secondaryTextColor];
    self.progressBar.backgroundColor = [t liveColor];
}

- (void)configureWithVideo:(TBVideo *)video
{
    [self applyTheme];
    TBTheme *t = [TBTheme shared];
    [self.thumbnail setImageURL:(video.videoId.length ? [video thumbnailURLForWidth:320] : video.thumbnailURL) placeholder:[t thumbnailPlaceholder]];
    [self.lengthPill setText:video.isLive ? L(@"LIVE") : video.lengthText image:video.isLive ? [t pillImageWithColor:[t liveColor]] : [t darkPillImage]];
    self.titleLabel.text = video.title.length ? video.title : L(@"Untitled");
    self.metaLabel.text = [video metaText];
    self.progress = (video.position > 5 && video.lengthSeconds > 0) ? MIN(1.0, video.position / video.lengthSeconds) : 0;
    self.progressTrack.hidden = self.progress <= 0;
    [self setNeedsLayout];
}

- (void)configureWithPlaylist:(TBPlaylist *)playlist
{
    [self applyTheme];
    TBTheme *t = [TBTheme shared];
    [self.thumbnail setImageURL:playlist.thumbnailURL placeholder:[t thumbnailPlaceholder]];
    [self.lengthPill setText:playlist.videoCountText.length ? playlist.videoCountText : L(@"Playlist") image:[t darkPillImage]];
    self.titleLabel.text = playlist.title.length ? playlist.title : L(@"Playlist");
    self.metaLabel.text = playlist.ownerName.length ? [NSString stringWithFormat:@"%@ · %@", playlist.ownerName, L(@"Playlist")] : L(@"Playlist");
    self.progress = 0;
    self.progressTrack.hidden = YES;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat tw = 128, th = 72;
    self.thumbnail.frame = CGRectMake(8, floor((b.size.height - th) / 2), tw, th);
    CGRect lp = self.lengthPill.frame;
    self.lengthPill.frame = CGRectMake(CGRectGetMaxX(self.thumbnail.frame) - 5 - lp.size.width, CGRectGetMaxY(self.thumbnail.frame) - 23, lp.size.width, lp.size.height);
    CGRect tf = self.thumbnail.frame;
    self.progressTrack.frame = CGRectMake(tf.origin.x, CGRectGetMaxY(tf) - 3, tf.size.width, 3);
    self.progressBar.frame = CGRectMake(0, 0, floor(tf.size.width * self.progress), 3);
    CGFloat x = 8 + tw + 10;
    CGFloat w = b.size.width - x - 10;
    self.titleLabel.frame = CGRectMake(x, 7, w, 34);
    self.metaLabel.frame = CGRectMake(x, 43, w, 30);
}

@end

#pragma mark - Comment cell

@interface TBCommentCell ()
@property (nonatomic, strong) TBImageView *avatar;
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *textLabel2;
@property (nonatomic, strong) UILabel *footerLabel;
@end

@implementation TBCommentCell

+ (NSString *)reuseIdentifier { return @"comment"; }

+ (UIFont *)textFont { return [UIFont systemFontOfSize:14]; }

+ (CGFloat)heightForComment:(id)comment width:(CGFloat)width
{
    NSString *text = [comment valueForKey:@"text"] ?: @"";
    BOOL reply = [[comment valueForKey:@"isReply"] boolValue];
    CGFloat textWidth = width - (reply ? 86 : 62) - 12;
    CGSize size = [text sizeWithFont:[self textFont] constrainedToSize:CGSizeMake(textWidth, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(66, 10 + 18 + 2 + ceil(size.height) + 4 + 16 + 10);
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _avatar = [[TBImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.maxPixels = 100;
        [self.contentView addSubview:_avatar];
        _authorLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _authorLabel.backgroundColor = [UIColor clearColor];
        _authorLabel.font = [UIFont boldSystemFontOfSize:12];
        _authorLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_authorLabel];
        _textLabel2 = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel2.backgroundColor = [UIColor clearColor];
        _textLabel2.font = [TBCommentCell textFont];
        _textLabel2.numberOfLines = 0;
        _textLabel2.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:_textLabel2];
        _footerLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _footerLabel.backgroundColor = [UIColor clearColor];
        _footerLabel.font = [UIFont systemFontOfSize:11];
        [self.contentView addSubview:_footerLabel];
    }
    return self;
}

- (void)configureWithComment:(id)comment
{
    TBTheme *t = [TBTheme shared];
    [t styleCell:self];
    NSString *author = [comment valueForKey:@"authorName"] ?: @"";
    NSString *published = [comment valueForKey:@"publishedText"] ?: @"";
    BOOL creator = [[comment valueForKey:@"isCreator"] boolValue];
    BOOL pinned = [[comment valueForKey:@"isPinned"] boolValue];
    NSMutableString *head = [NSMutableString stringWithString:author];
    if (published.length) [head appendFormat:@" · %@", published];
    if (pinned) [head appendFormat:@" · %@", L(@"Pinned")];
    self.authorLabel.text = head;
    self.authorLabel.textColor = creator ? [t accentColor] : [t secondaryTextColor];
    self.textLabel2.text = [comment valueForKey:@"text"] ?: @"";
    self.textLabel2.textColor = [t primaryTextColor];
    NSMutableArray *footer = [NSMutableArray array];
    NSString *likes = [comment valueForKey:@"likesText"];
    if (likes.length) [footer addObject:[NSString stringWithFormat:@"👍 %@", likes]];
    NSInteger replies = [[comment valueForKey:@"replyCount"] integerValue];
    if (replies > 0) [footer addObject:[NSString stringWithFormat:L(@"%ld replies"), (long)replies]];
    if ([[comment valueForKey:@"isHearted"] boolValue]) [footer addObject:@"❤"];
    self.footerLabel.text = [footer componentsJoinedByString:@"   "];
    self.footerLabel.textColor = [t secondaryTextColor];
    [self.avatar setImageURL:[comment valueForKey:@"authorAvatarURL"] placeholder:[t avatarPlaceholderWithSize:36]];
    self.accessoryType = replies > 0 && ![[comment valueForKey:@"isReply"] boolValue] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    self.selectionStyle = replies > 0 ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
    self.indentationLevel = [[comment valueForKey:@"isReply"] boolValue] ? 1 : 0;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat indent = self.indentationLevel > 0 ? 24 : 0;
    CGFloat size = self.indentationLevel > 0 ? 28 : 36;
    self.avatar.frame = CGRectMake(12 + indent, 10, size, size);
    self.avatar.layer.cornerRadius = size / 2;
    CGFloat x = 12 + indent + size + 10;
    CGFloat w = b.size.width - x - 12;
    self.authorLabel.frame = CGRectMake(x, 10, w, 16);
    CGSize textSize = [self.textLabel2.text sizeWithFont:self.textLabel2.font constrainedToSize:CGSizeMake(w, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    self.textLabel2.frame = CGRectMake(x, 28, w, ceil(textSize.height));
    self.footerLabel.frame = CGRectMake(x, CGRectGetMaxY(self.textLabel2.frame) + 4, w, 16);
}

@end
