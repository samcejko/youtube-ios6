#import <UIKit/UIKit.h>
#import "TBInnertube.h"

typedef NS_ENUM(NSInteger, TBGridStyle) {
    TBGridStyleVideos = 0,     // videos, playlists and channels mixed: cards on wide screens, rows on narrow ones
    TBGridStyleShorts,         // tall thumbnails, several per row
};

// Loads one page: continuation nil = the first page. Returns the task so that it can be cancelled.
typedef TBHTTPTask *(^TBGridLoader)(NSString *continuation, TBItemsCompletion completion);

// A paged grid of videos, shorts, playlists and channels with pull-to-refresh, "load more" at the bottom, an
// empty/error state, optional sections with titles (shelves) and an optional header view that scrolls with the
// content (channel pages).
@interface TBGridViewController : UIViewController

- (instancetype)initWithStyle:(TBGridStyle)style loader:(TBGridLoader)loader;

@property (nonatomic) TBGridStyle style;
@property (nonatomic, copy) TBGridLoader loader;
@property (nonatomic, readonly, strong) UICollectionView *collectionView;
@property (nonatomic, readonly, strong) NSArray *items;         // every item, in order
@property (nonatomic, copy) NSString *emptyText;               // shown when the first page is empty
@property (nonatomic) BOOL refreshesOnAppear;                  // reload when the view appears after a while (default YES)
@property (nonatomic) NSTimeInterval staleAfter;               // seconds (default 300)
@property (nonatomic) BOOL shortsOpenAsFeed;                   // a tapped short starts the shorts player with its neighbours (default YES)

// A view above the grid, scrolling with it (its height is taken from its frame)
@property (nonatomic, strong) UIView *headerView;
- (void)setHeaderHeight:(CGFloat)height;

- (void)reload;                                                // from the first page
- (void)replaceItems:(NSArray *)items;                         // a fixed list (no paging)
- (void)replaceShelves:(NSArray *)shelves;                     // TBShelf: sections with titles (no paging)
- (void)setLoader:(TBGridLoader)loader andReload:(BOOL)reload;
- (void)applyTheme;

// Taps: the default opens the item (video, short, playlist, channel); a block replaces it
@property (nonatomic, copy) void (^onSelectItem)(id item);
// A long press offers to remove the item (history, watch later) when this is set
@property (nonatomic, copy) void (^onRemoveItem)(id item);
// "More" of a shelf header
@property (nonatomic, copy) void (^onSelectShelf)(TBShelf *shelf);

@end
