#import <UIKit/UIKit.h>
#import "TBModels.h"

// A label on a dark capsule, placed over a thumbnail (the length, LIVE)
@interface TBPillLabel : UIView
- (void)setText:(NSString *)text image:(UIImage *)image;
@end

// A video or a playlist in a grid: a "card" (thumbnail on top, texts below) on wide screens, a row (thumbnail on
// the left) on narrow ones. A red bar on the thumbnail shows how far a video was watched.
@interface TBVideoCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)cardHeightForWidth:(CGFloat)width;
+ (CGFloat)rowHeight;
- (void)configureWithVideo:(TBVideo *)video asCard:(BOOL)card;
- (void)configureWithPlaylist:(TBPlaylist *)playlist asCard:(BOOL)card;
- (void)applyTheme;
@end

// A short: a tall thumbnail with the title and the views over its lower part
@interface TBShortCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)heightForWidth:(CGFloat)width;
- (void)configureWithVideo:(TBVideo *)video;
- (void)applyTheme;
@end

// A channel in a grid (a full-width row): round avatar, name, handle and subscribers
@interface TBChannelCell : UICollectionViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)height;
- (void)configureWithChannel:(TBChannel *)channel;
- (void)applyTheme;
@end

// The title of a section of the grid, with an optional "More" on the right
@interface TBGridHeaderView : UICollectionReusableView
+ (NSString *)reuseIdentifier;
+ (CGFloat)height;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UIButton *moreButton;
- (void)applyTheme;
@end

// A video in a table (the related videos of the watch page, the videos of a playlist): thumbnail with the length,
// title, channel · views · age
@interface TBVideoTableCell : UITableViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)height;
- (void)configureWithVideo:(TBVideo *)video;
- (void)configureWithPlaylist:(TBPlaylist *)playlist;
@end

// A comment: round avatar, author and age, the text, likes and the number of replies
@interface TBCommentCell : UITableViewCell
+ (NSString *)reuseIdentifier;
+ (CGFloat)heightForComment:(id)comment width:(CGFloat)width;
- (void)configureWithComment:(id)comment;
@end
