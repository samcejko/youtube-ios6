#import "TBGridViewController.h"
#import "TBCells.h"
#import "TBNavigator.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

static NSString * const kFooterId = @"footer";

@interface TBGridFooterView : UICollectionReusableView
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation TBGridFooterView
- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[[TBTheme shared] spinnerStyle]];
        _spinner.hidesWhenStopped = YES;
        _spinner.center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
        _spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self addSubview:_spinner];
    }
    return self;
}
@end

@interface TBGridViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIActionSheetDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *layout;
@property (nonatomic, strong) NSMutableArray *sections;        // TBShelf; a plain list is one shelf without a title
@property (nonatomic, copy) NSString *nextContinuation;
@property (nonatomic) BOOL hasMore;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL fixedList;
@property (nonatomic, strong) TBHTTPTask *task;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSDate *loadedAt;
@property (nonatomic) CGFloat headerHeight;
@property (nonatomic) BOOL firstPageFailed;
@property (nonatomic, strong) id pressedItem;
@end

@implementation TBGridViewController

- (instancetype)initWithStyle:(TBGridStyle)style loader:(TBGridLoader)loader
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _style = style;
        _loader = [loader copy];
        _sections = [NSMutableArray array];
        _refreshesOnAppear = YES;
        _staleAfter = 300;
        _shortsOpenAsFeed = YES;
        _emptyText = L(@"Nothing here right now.");
    }
    return self;
}

- (void)dealloc
{
    [_task cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray *)items
{
    NSMutableArray *all = [NSMutableArray array];
    for (TBShelf *s in self.sections) [all addObjectsFromArray:s.items];
    return all;
}

- (TBShelf *)plainShelf
{
    if (!self.sections.count) {
        TBShelf *s = [[TBShelf alloc] init];
        s.items = @[];
        [self.sections addObject:s];
    }
    return self.sections[0];
}

#pragma mark - View

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.layout = [[UICollectionViewFlowLayout alloc] init];
    self.layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[TBVideoCell class] forCellWithReuseIdentifier:[TBVideoCell reuseIdentifier]];
    [self.collectionView registerClass:[TBShortCell class] forCellWithReuseIdentifier:[TBShortCell reuseIdentifier]];
    [self.collectionView registerClass:[TBChannelCell class] forCellWithReuseIdentifier:[TBChannelCell reuseIdentifier]];
    [self.collectionView registerClass:[TBGridFooterView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:kFooterId];
    [self.collectionView registerClass:[TBGridHeaderView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:[TBGridHeaderView reuseIdentifier]];
    [self.view addSubview:self.collectionView];

    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(pulled) forControlEvents:UIControlEventValueChanged];
    [self.collectionView addSubview:self.refreshControl];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    press.minimumPressDuration = 0.6;
    [self.collectionView addGestureRecognizer:press];

    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.retryButton setTitle:L(@"Try Again") forState:UIControlStateNormal];
    [self.retryButton addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    if (self.headerView) [self installHeader];
    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:TBThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.navigationController) [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    if (!self.fixedList && !self.items.count && !self.loading && !self.firstPageFailed && self.loader) {
        [self reload];
    } else if (self.refreshesOnAppear && !self.fixedList && self.loadedAt && -[self.loadedAt timeIntervalSinceNow] > self.staleAfter && !self.loading) {
        [self reload];
    } else {
        // (a video watched meanwhile: its progress bar)
        [self.collectionView reloadData];
    }
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self layoutChrome];
}

- (void)layoutChrome
{
    CGRect b = self.view.bounds;
    self.messageLabel.frame = CGRectMake(30, b.size.height * 0.35 + self.headerHeight / 2, b.size.width - 60, 80);
    self.retryButton.frame = CGRectMake(floor((b.size.width - 120) / 2), CGRectGetMaxY(self.messageLabel.frame) + 8, 120, 34);
    self.spinner.center = CGPointMake(b.size.width / 2, b.size.height * 0.4 + self.headerHeight / 2);
    if (self.headerView) self.headerView.frame = CGRectMake(0, -self.headerHeight, b.size.width, self.headerHeight);
    [self.layout invalidateLayout];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.layout invalidateLayout];
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.view.backgroundColor = [t backgroundColor];
    self.collectionView.backgroundColor = [t backgroundColor];
    self.collectionView.indicatorStyle = t.isDark ? UIScrollViewIndicatorStyleWhite : UIScrollViewIndicatorStyleDefault;
    self.messageLabel.textColor = [t secondaryTextColor];
    [self.retryButton setTitleColor:[t primaryTextColor] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:NO] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
    self.spinner.activityIndicatorViewStyle = t.isDark ? UIActivityIndicatorViewStyleWhiteLarge : UIActivityIndicatorViewStyleGray;
    self.refreshControl.tintColor = t.isDark ? [UIColor whiteColor] : nil;
    [self.collectionView reloadData];
}

- (void)themeChanged
{
    [self applyTheme];
}

#pragma mark - Header

- (void)setHeaderView:(UIView *)headerView
{
    [_headerView removeFromSuperview];
    _headerView = headerView;
    _headerHeight = headerView.frame.size.height;
    if (self.isViewLoaded) [self installHeader];
}

- (void)installHeader
{
    if (!self.headerView) return;
    [self.collectionView addSubview:self.headerView];
    [self setHeaderHeight:self.headerHeight];
}

- (void)setHeaderHeight:(CGFloat)height
{
    _headerHeight = height;
    UIEdgeInsets insets = self.collectionView.contentInset;
    insets.top = height;
    self.collectionView.contentInset = insets;
    self.collectionView.scrollIndicatorInsets = UIEdgeInsetsMake(height, 0, 0, 0);
    if (self.headerView) self.headerView.frame = CGRectMake(0, -height, self.view.bounds.size.width, height);
    [self layoutChrome];
}

#pragma mark - Loading

- (void)pulled
{
    if (self.fixedList) { [self.refreshControl endRefreshing]; return; }
    [self reload];
}

- (void)showMessage:(NSString *)text retry:(BOOL)retry
{
    self.messageLabel.text = text;
    self.messageLabel.hidden = text.length == 0;
    self.retryButton.hidden = !retry;
}

- (void)setLoader:(TBGridLoader)loader andReload:(BOOL)reload
{
    _loader = [loader copy];
    [self.task cancel];
    self.task = nil;
    self.loading = NO;
    self.firstPageFailed = NO;
    self.loadedAt = nil;
    [self.sections removeAllObjects];
    self.hasMore = NO;
    self.fixedList = NO;
    if (self.isViewLoaded) {
        [self.collectionView reloadData];
        [self showMessage:nil retry:NO];
        if (reload) [self reload];
    }
}

- (void)reload
{
    if (!self.loader) return;
    [self.task cancel];
    self.fixedList = NO;
    self.loading = YES;
    self.firstPageFailed = NO;
    [self showMessage:nil retry:NO];
    if (!self.items.count && !self.refreshControl.isRefreshing) [self.spinner startAnimating];
    __weak TBGridViewController *weakSelf = self;
    self.task = self.loader(nil, ^(NSArray *items, NSString *continuation, NSError *error) {
        TBGridViewController *s = weakSelf;
        if (!s) return;
        s.loading = NO;
        s.task = nil;
        [s.spinner stopAnimating];
        [s.refreshControl endRefreshing];
        if (error) {
            s.firstPageFailed = YES;
            if (!s.items.count) [s showMessage:error.localizedDescription retry:YES];
            else [TBUtils alertWithTitle:L(@"Could not refresh") message:error.localizedDescription];
            return;
        }
        s.loadedAt = [NSDate date];
        [s.sections removeAllObjects];
        [s plainShelf].items = [s uniqueItems:items ?: @[] known:nil];
        s.nextContinuation = continuation;
        s.hasMore = continuation.length > 0;
        [s.collectionView reloadData];
        if (!s.items.count) [s showMessage:s.emptyText retry:NO];
    });
}

- (void)loadMore
{
    if (self.loading || !self.hasMore || self.fixedList || !self.loader) return;
    self.loading = YES;
    __weak TBGridViewController *weakSelf = self;
    self.task = self.loader(self.nextContinuation, ^(NSArray *items, NSString *continuation, NSError *error) {
        TBGridViewController *s = weakSelf;
        if (!s) return;
        s.loading = NO;
        s.task = nil;
        if (error) {
            s.hasMore = NO;   // (the end of the list is shown; a pull loads again)
            [s.collectionView reloadData];
            return;
        }
        TBShelf *shelf = [s plainShelf];
        NSArray *fresh = [s uniqueItems:items known:shelf.items];
        shelf.items = [shelf.items arrayByAddingObjectsFromArray:fresh];
        s.nextContinuation = continuation;
        s.hasMore = continuation.length > 0 && items.count > 0;
        [s.collectionView reloadData];
    });
}

// (the API repeats items across pages now and then)
- (NSArray *)uniqueItems:(NSArray *)items known:(NSArray *)known
{
    NSMutableSet *seen = [NSMutableSet set];
    for (id item in known) [seen addObject:[self identityOf:item]];
    NSMutableArray *fresh = [NSMutableArray array];
    for (id item in items) {
        if ([item isKindOfClass:[TBShelf class]]) continue;
        NSString *key = [self identityOf:item];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [fresh addObject:item];
    }
    return fresh;
}

- (NSString *)identityOf:(id)item
{
    if ([item isKindOfClass:[TBVideo class]]) return [@"v:" stringByAppendingString:[(TBVideo *)item videoId] ?: @""];
    if ([item isKindOfClass:[TBChannel class]]) return [@"c:" stringByAppendingString:[(TBChannel *)item channelId] ?: @""];
    if ([item isKindOfClass:[TBPlaylist class]]) return [@"p:" stringByAppendingString:[(TBPlaylist *)item playlistId] ?: @""];
    return [NSString stringWithFormat:@"%p", item];
}

- (void)replaceItems:(NSArray *)items
{
    [self.task cancel];
    self.task = nil;
    self.loading = NO;
    self.fixedList = YES;
    self.hasMore = NO;
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    [self.sections removeAllObjects];
    [self plainShelf].items = items ?: @[];
    [self.collectionView reloadData];
    [self showMessage:self.items.count ? nil : self.emptyText retry:NO];
}

- (void)replaceShelves:(NSArray *)shelves
{
    [self.task cancel];
    self.task = nil;
    self.loading = NO;
    self.fixedList = YES;
    self.hasMore = NO;
    [self.spinner stopAnimating];
    [self.refreshControl endRefreshing];
    [self.sections setArray:shelves ?: @[]];
    [self.collectionView reloadData];
    [self showMessage:self.items.count ? nil : self.emptyText retry:NO];
}

#pragma mark - Layout metrics

- (BOOL)usesCards
{
    return self.view.bounds.size.width >= 500;
}

- (BOOL)shortsSection:(NSInteger)section
{
    if (self.style == TBGridStyleShorts) return YES;
    TBShelf *shelf = section < (NSInteger)self.sections.count ? self.sections[(NSUInteger)section] : nil;
    if (!shelf.items.count) return NO;
    for (id item in shelf.items) if (![item isKindOfClass:[TBVideo class]] || ![(TBVideo *)item isShort]) return NO;
    return YES;
}

- (NSInteger)columnsInSection:(NSInteger)section
{
    CGFloat width = self.view.bounds.size.width;
    if ([self shortsSection:section]) return MAX(3, (NSInteger)floor(width / (TBIsPad() ? 170 : 112)));
    if (![self usesCards]) return 1;
    return MAX(2, MIN(4, (NSInteger)floor(width / 300)));
}

- (CGFloat)itemWidthInSection:(NSInteger)section
{
    NSInteger columns = [self columnsInSection:section];
    CGFloat width = self.view.bounds.size.width;
    BOOL shorts = [self shortsSection:section];
    CGFloat inset = shorts ? 8 : ([self usesCards] ? 8 : 0);
    CGFloat spacing = shorts ? 6 : ([self usesCards] ? 8 : 0);
    return floor((width - 2 * inset - (columns - 1) * spacing) / columns);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat w = [self itemWidthInSection:indexPath.section];
    id item = [self itemAt:indexPath];
    if ([self shortsSection:indexPath.section]) return CGSizeMake(w, [TBShortCell heightForWidth:w]);
    if ([item isKindOfClass:[TBChannel class]]) return CGSizeMake([self usesCards] ? self.view.bounds.size.width - 16 : self.view.bounds.size.width, [TBChannelCell height]);
    if ([self usesCards]) return CGSizeMake(w, [TBVideoCell cardHeightForWidth:w]);
    return CGSizeMake(w, [TBVideoCell rowHeight]);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section
{
    if ([self shortsSection:section]) return UIEdgeInsetsMake(6, 8, 10, 8);
    return [self usesCards] ? UIEdgeInsetsMake(8, 8, 8, 8) : UIEdgeInsetsMake(0, 0, 0, 0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section
{
    if ([self shortsSection:section]) return 6;
    return [self usesCards] ? 8 : 0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section
{
    if ([self shortsSection:section]) return 8;
    return [self usesCards] ? 8 : 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForFooterInSection:(NSInteger)section
{
    BOOL last = section == (NSInteger)self.sections.count - 1;
    return CGSizeMake(self.view.bounds.size.width, (last && self.hasMore) ? 44 : 4);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section
{
    TBShelf *shelf = self.sections[(NSUInteger)section];
    return CGSizeMake(self.view.bounds.size.width, shelf.title.length ? [TBGridHeaderView height] : 0);
}

#pragma mark - Data source

- (id)itemAt:(NSIndexPath *)indexPath
{
    if (indexPath.section >= (NSInteger)self.sections.count) return nil;
    TBShelf *shelf = self.sections[(NSUInteger)indexPath.section];
    if (indexPath.item >= (NSInteger)shelf.items.count) return nil;
    return shelf.items[(NSUInteger)indexPath.item];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return (NSInteger)[self.sections[(NSUInteger)section] items].count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id item = [self itemAt:indexPath];
    if ([self shortsSection:indexPath.section]) {
        TBShortCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[TBShortCell reuseIdentifier] forIndexPath:indexPath];
        [cell applyTheme];
        [cell configureWithVideo:item];
        return cell;
    }
    if ([item isKindOfClass:[TBChannel class]]) {
        TBChannelCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[TBChannelCell reuseIdentifier] forIndexPath:indexPath];
        [cell applyTheme];
        [cell configureWithChannel:item];
        return cell;
    }
    TBVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:[TBVideoCell reuseIdentifier] forIndexPath:indexPath];
    [cell applyTheme];
    if ([item isKindOfClass:[TBPlaylist class]]) [cell configureWithPlaylist:item asCard:[self usesCards]];
    else [cell configureWithVideo:item asCard:[self usesCards]];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        TBGridHeaderView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:[TBGridHeaderView reuseIdentifier] forIndexPath:indexPath];
        TBShelf *shelf = self.sections[(NSUInteger)indexPath.section];
        [header applyTheme];
        header.titleLabel.text = shelf.title ?: @"";
        header.moreButton.hidden = !(self.onSelectShelf && (shelf.browseId.length || shelf.items.count > 6));
        header.moreButton.tag = indexPath.section;
        [header.moreButton removeTarget:self action:NULL forControlEvents:UIControlEventTouchUpInside];
        [header.moreButton addTarget:self action:@selector(moreTapped:) forControlEvents:UIControlEventTouchUpInside];
        return header;
    }
    TBGridFooterView *footer = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:kFooterId forIndexPath:indexPath];
    footer.spinner.activityIndicatorViewStyle = [[TBTheme shared] spinnerStyle];
    BOOL last = indexPath.section == (NSInteger)self.sections.count - 1;
    if (last && self.hasMore) [footer.spinner startAnimating];
    else [footer.spinner stopAnimating];
    return footer;
}

- (void)moreTapped:(UIButton *)button
{
    if (button.tag < (NSInteger)self.sections.count && self.onSelectShelf) self.onSelectShelf(self.sections[(NSUInteger)button.tag]);
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    id item = [self itemAt:indexPath];
    if (!item) return;
    if (self.onSelectItem) { self.onSelectItem(item); return; }
    if ([item isKindOfClass:[TBVideo class]] && [(TBVideo *)item isShort] && self.shortsOpenAsFeed) {
        // the shorts of this section, starting with the tapped one
        TBShelf *shelf = self.sections[(NSUInteger)indexPath.section];
        NSMutableArray *shorts = [NSMutableArray array];
        NSUInteger start = 0;
        for (id other in shelf.items) {
            if ([other isKindOfClass:[TBVideo class]] && [(TBVideo *)other isShort]) {
                if (other == item) start = shorts.count;
                [shorts addObject:other];
            }
        }
        [TBNavigator openShorts:shorts startingAt:start from:self];
        return;
    }
    [TBNavigator openItem:item from:self];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!self.hasMore || self.loading) return;
    CGFloat bottom = scrollView.contentOffset.y + scrollView.bounds.size.height;
    if (bottom > scrollView.contentSize.height - scrollView.bounds.size.height) [self loadMore];
}

#pragma mark - Long press

- (void)longPressed:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan || !self.onRemoveItem) return;
    NSIndexPath *ip = [self.collectionView indexPathForItemAtPoint:[gesture locationInView:self.collectionView]];
    id item = ip ? [self itemAt:ip] : nil;
    if (!item) return;
    self.pressedItem = item;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:L(@"Cancel") destructiveButtonTitle:L(@"Remove") otherButtonTitles:nil];
    UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:ip];
    if (TBIsPad() && cell) [sheet showFromRect:cell.bounds inView:cell animated:YES];
    else [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.destructiveButtonIndex && self.pressedItem && self.onRemoveItem) self.onRemoveItem(self.pressedItem);
    self.pressedItem = nil;
}

@end
