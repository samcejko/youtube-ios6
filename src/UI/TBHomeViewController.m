#import "TBHomeViewController.h"
#import "TBNavigator.h"
#import "TBInnertube.h"
#import "TBLibrary.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBCommon.h"

static const NSUInteger TBHomeShelfLimit = 8;

@interface TBHomeViewController ()
@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, strong) NSMutableDictionary *fullShelves;   // title -> TBShelf with every item
@property (nonatomic, strong) NSMutableArray *remoteShelfTitles;  // ordered list of remote shelf titles
@property (nonatomic, strong) NSDate *loadedAt;
@property (nonatomic) BOOL loading;
@end

@implementation TBHomeViewController

- (instancetype)init
{
    self = [super initWithStyle:TBGridStyleVideos loader:nil];
    if (self) {
        self.title = L(@"Home");
        self.emptyText = L(@"Nothing could be loaded. Pull down to try again.");
        _tasks = [NSMutableArray array];
        _fullShelves = [NSMutableDictionary dictionary];
        _remoteShelfTitles = [NSMutableArray array];
        __weak TBHomeViewController *weakSelf = self;
        self.onSelectShelf = ^(TBShelf *shelf) {
            TBHomeViewController *s = weakSelf;
            TBShelf *full = s.fullShelves[shelf.title ?: @""] ?: shelf;
            [TBNavigator openShelf:full from:s];
        };
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (TBHTTPTask *t in _tasks) [t cancel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"Tubie";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TBAccountDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!self.loading && (!self.loadedAt || -[self.loadedAt timeIntervalSinceNow] > 900)) [self reload];
    else [self refreshLocalShelves];
}

- (void)libraryChanged
{
    if (self.isViewLoaded && self.view.window) [self refreshLocalShelves];
}

- (void)accountChanged
{
    self.loadedAt = nil;
    [self.fullShelves removeAllObjects];
    [self.remoteShelfTitles removeAllObjects];
    if (self.isViewLoaded && self.view.window) [self reload];
}

#pragma mark - Loading

// (the base class pulls through here)
- (void)reload
{
    if (self.loading) return;
    for (TBHTTPTask *t in self.tasks) [t cancel];
    [self.tasks removeAllObjects];
    self.loading = YES;
    BOOL signedIn = [[TBAccount shared] isSignedIn];
    NSArray *pages = @[ @[ L(@"Music"), TBBrowseMusic ], @[ L(@"News"), TBBrowseNews ], @[ L(@"Sports"), TBBrowseSports ],
                        @[ L(@"Live"), TBBrowseLive ], @[ L(@"Gaming"), TBBrowseGaming ] ];
    NSMutableArray *results = [NSMutableArray array];
    for (NSUInteger i = 0; i < pages.count; i++) [results addObject:[NSNull null]];
    __block NSArray *recommendedShelves = nil;
    __block NSUInteger pending = pages.count + (signedIn ? 2 : 1);
    __weak TBHomeViewController *weakSelf = self;
    void (^finish)(void) = ^{
        TBHomeViewController *s = weakSelf;
        if (!s || --pending > 0) return;
        s.loading = NO;
        s.loadedAt = [NSDate date];
        [s.remoteShelfTitles removeAllObjects];
        NSMutableArray *shelves = [NSMutableArray array];

        // 1. Continue watching
        [shelves addObjectsFromArray:[s localContinueWatchingShelves]];

        // 2. Recommended shelves (when signed in)
        if (recommendedShelves.count) {
            for (TBShelf *recShelf in recommendedShelves) {
                if (!recShelf.items.count) continue;
                NSString *title = recShelf.title.length ? recShelf.title : L(@"Recommended");
                s.fullShelves[title] = recShelf;
                [s.remoteShelfTitles addObject:title];
                TBShelf *display = [[TBShelf alloc] init];
                display.title = title;
                display.items = recShelf.items.count > TBHomeShelfLimit ? [recShelf.items subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : recShelf.items;
                [shelves addObject:display];
            }
        }

        // 3. Subscriptions feed
        [shelves addObjectsFromArray:[s localSubscriptionsShelves]];

        // 4. Topic shelves (Music, News, Sports, Live, Gaming)
        for (NSUInteger i = 0; i < pages.count; i++) {
            if (results[i] == [NSNull null]) continue;
            NSArray *pageShelves = results[i];
            NSString *pageTitle = pages[i][0];
            NSMutableArray *all = [NSMutableArray array];
            for (TBShelf *shelf in pageShelves) [all addObjectsFromArray:shelf.items];
            if (!all.count) continue;
            TBShelf *full = [[TBShelf alloc] init];
            full.title = pageTitle;
            full.items = all;
            s.fullShelves[pageTitle] = full;
            [s.remoteShelfTitles addObject:pageTitle];
            TBShelf *display = [[TBShelf alloc] init];
            display.title = pageTitle;
            display.items = all.count > TBHomeShelfLimit ? [all subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : all;
            [shelves addObject:display];
        }
        [s replaceShelves:shelves];
    };
    if (signedIn) {
        TBHTTPTask *recTask = [TBInnertube authenticatedShelvesOfPage:@"FEwhat_to_watch" completion:^(NSArray *recShelves, NSError *error) {
            if (recShelves.count) recommendedShelves = recShelves;
            if (error) TBLog(@"Home: FEwhat_to_watch failed: %@", error.localizedDescription);
            finish();
        }];
        if (recTask) [self.tasks addObject:recTask];
    }
    for (NSUInteger i = 0; i < pages.count; i++) {
        NSString *browseId = pages[i][1];
        TBHTTPTask *t = [TBInnertube shelvesOfPage:browseId completion:^(NSArray *pageShelves, NSError *error) {
            if (pageShelves) results[i] = pageShelves;
            if (error) TBLog(@"Home: %@ failed: %@", browseId, error.localizedDescription);
            finish();
        }];
        if (t) [self.tasks addObject:t];
    }
    TBHTTPTask *feed = [[TBLibrary shared] feedForce:NO completion:^(NSArray *videos, NSError *error) { finish(); }];
    if (feed) [self.tasks addObject:feed];
}

- (NSArray *)localContinueWatchingShelves
{
    NSMutableArray *unfinished = [NSMutableArray array];
    for (TBVideo *v in [[TBLibrary shared] history]) {
        if (v.position > 30 && (v.lengthSeconds <= 0 || v.position < v.lengthSeconds - 30) && !v.isShort) [unfinished addObject:v];
        if (unfinished.count >= 6) break;
    }
    if (unfinished.count) {
        TBShelf *shelf = [[TBShelf alloc] init];
        shelf.title = L(@"Continue watching");
        shelf.items = unfinished;
        return @[ shelf ];
    }
    return @[];
}

- (NSArray *)localSubscriptionsShelves
{
    NSArray *feed = [[TBLibrary shared] cachedFeed];
    if (feed.count) {
        TBShelf *shelf = [[TBShelf alloc] init];
        shelf.title = L(@"Subscriptions");
        shelf.items = feed.count > TBHomeShelfLimit ? [feed subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : feed;
        TBShelf *full = [[TBShelf alloc] init];
        full.title = shelf.title;
        full.items = feed;
        self.fullShelves[shelf.title] = full;
        return @[ shelf ];
    }
    return @[];
}

// Continue watching and the subscriptions feed, from what is on the device
- (NSArray *)localShelves
{
    NSMutableArray *shelves = [NSMutableArray arrayWithArray:[self localContinueWatchingShelves]];
    [shelves addObjectsFromArray:[self localSubscriptionsShelves]];
    return shelves;
}

- (void)refreshLocalShelves
{
    if (self.loading || !self.loadedAt) return;
    NSMutableArray *shelves = [NSMutableArray arrayWithArray:[self localContinueWatchingShelves]];
    NSSet *topicTitles = [NSSet setWithObjects:L(@"Music"), L(@"News"), L(@"Sports"), L(@"Live"), L(@"Gaming"), nil];
    NSSet *localTitles = [NSSet setWithObjects:L(@"Continue watching"), L(@"Subscriptions"), nil];
    for (NSString *title in self.remoteShelfTitles) {
        if ([topicTitles containsObject:title] || [localTitles containsObject:title]) continue;
        TBShelf *full = self.fullShelves[title];
        if (!full) continue;
        TBShelf *display = [[TBShelf alloc] init];
        display.title = title;
        display.items = full.items.count > TBHomeShelfLimit ? [full.items subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : full.items;
        [shelves addObject:display];
    }
    [shelves addObjectsFromArray:[self localSubscriptionsShelves]];
    for (NSString *title in self.remoteShelfTitles) {
        if (![topicTitles containsObject:title]) continue;
        TBShelf *full = self.fullShelves[title];
        if (!full) continue;
        TBShelf *display = [[TBShelf alloc] init];
        display.title = title;
        display.items = full.items.count > TBHomeShelfLimit ? [full.items subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : full.items;
        [shelves addObject:display];
    }
    [self replaceShelves:shelves];
}

- (NSArray *)currentRemoteShelves
{
    NSMutableArray *remote = [NSMutableArray array];
    NSSet *local = [NSSet setWithObjects:L(@"Continue watching"), L(@"Subscriptions"), nil];
    for (NSString *title in self.remoteShelfTitles) {
        TBShelf *full = self.fullShelves[title];
        if (!full || [local containsObject:title]) continue;
        TBShelf *display = [[TBShelf alloc] init];
        display.title = title;
        display.items = full.items.count > TBHomeShelfLimit ? [full.items subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : full.items;
        [remote addObject:display];
    }
    return remote;
}

@end
