#import "TBHomeViewController.h"
#import "TBNavigator.h"
#import "TBInnertube.h"
#import "TBLibrary.h"
#import "TBTheme.h"
#import "TBCommon.h"

static const NSUInteger TBHomeShelfLimit = 8;

@interface TBHomeViewController ()
@property (nonatomic, strong) NSMutableArray *tasks;
@property (nonatomic, strong) NSMutableDictionary *fullShelves;   // title -> TBShelf with every item
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
    for (TBHTTPTask *t in _tasks) [t cancel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"Tubie";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
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

#pragma mark - Loading

// (the base class pulls through here)
- (void)reload
{
    if (self.loading) return;
    for (TBHTTPTask *t in self.tasks) [t cancel];
    [self.tasks removeAllObjects];
    self.loading = YES;
    NSArray *pages = @[ @[ L(@"Music"), TBBrowseMusic ], @[ L(@"News"), TBBrowseNews ], @[ L(@"Sports"), TBBrowseSports ],
                        @[ L(@"Live"), TBBrowseLive ], @[ L(@"Gaming"), TBBrowseGaming ] ];
    NSMutableArray *results = [NSMutableArray array];
    for (NSUInteger i = 0; i < pages.count; i++) [results addObject:[NSNull null]];
    __block NSUInteger pending = pages.count + 1;
    __weak TBHomeViewController *weakSelf = self;
    void (^finish)(void) = ^{
        TBHomeViewController *s = weakSelf;
        if (!s || --pending > 0) return;
        s.loading = NO;
        s.loadedAt = [NSDate date];
        NSMutableArray *shelves = [NSMutableArray array];
        [shelves addObjectsFromArray:[s localShelves]];
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
            TBShelf *display = [[TBShelf alloc] init];
            display.title = pageTitle;
            display.items = all.count > TBHomeShelfLimit ? [all subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : all;
            [shelves addObject:display];
        }
        [s replaceShelves:shelves];
    };
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

// Continue watching and the subscriptions feed, from what is on the device
- (NSArray *)localShelves
{
    NSMutableArray *shelves = [NSMutableArray array];
    NSMutableArray *unfinished = [NSMutableArray array];
    for (TBVideo *v in [[TBLibrary shared] history]) {
        if (v.position > 30 && (v.lengthSeconds <= 0 || v.position < v.lengthSeconds - 30) && !v.isShort) [unfinished addObject:v];
        if (unfinished.count >= 6) break;
    }
    if (unfinished.count) {
        TBShelf *shelf = [[TBShelf alloc] init];
        shelf.title = L(@"Continue watching");
        shelf.items = unfinished;
        [shelves addObject:shelf];
    }
    NSArray *feed = [[TBLibrary shared] cachedFeed];
    if (feed.count) {
        TBShelf *shelf = [[TBShelf alloc] init];
        shelf.title = L(@"Subscriptions");
        shelf.items = feed.count > TBHomeShelfLimit ? [feed subarrayWithRange:NSMakeRange(0, TBHomeShelfLimit)] : feed;
        TBShelf *full = [[TBShelf alloc] init];
        full.title = shelf.title;
        full.items = feed;
        self.fullShelves[shelf.title] = full;
        [shelves addObject:shelf];
    }
    return shelves;
}

- (void)refreshLocalShelves
{
    if (self.loading || !self.loadedAt) return;
    NSMutableArray *shelves = [NSMutableArray arrayWithArray:[self localShelves]];
    for (TBShelf *shelf in [self currentRemoteShelves]) [shelves addObject:shelf];
    [self replaceShelves:shelves];
}

- (NSArray *)currentRemoteShelves
{
    // the shelves shown now minus the local ones (by title)
    NSMutableArray *remote = [NSMutableArray array];
    NSSet *local = [NSSet setWithObjects:L(@"Continue watching"), L(@"Subscriptions"), nil];
    for (NSString *title in @[ L(@"Music"), L(@"News"), L(@"Sports"), L(@"Live"), L(@"Gaming") ]) {
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
