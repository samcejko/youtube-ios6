#import "TBSubscriptionsViewController.h"
#import "TBNavigator.h"
#import "TBLibrary.h"
#import "TBTheme.h"
#import "TBCommon.h"

@interface TBSubscriptionsViewController ()
@property (nonatomic) BOOL forceNext;
@end

@implementation TBSubscriptionsViewController

- (instancetype)init
{
    self = [super initWithStyle:TBGridStyleVideos loader:nil];
    if (self) {
        self.title = L(@"Subscriptions");
        self.staleAfter = 300;
        __weak TBSubscriptionsViewController *weakSelf = self;
        self.loader = ^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            TBSubscriptionsViewController *s = weakSelf;
            if (continuation.length) { TBMain(^{ completion(@[], nil, nil); }); return nil; }
            BOOL force = s.forceNext;
            s.forceNext = NO;
            return [[TBLibrary shared] feedForce:force completion:^(NSArray *videos, NSError *error) {
                completion(videos, nil, error);
            }];
        };
        [self updateEmptyText];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Channels") style:UIBarButtonItemStyleBordered target:self action:@selector(channelsTapped)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
}

- (void)updateEmptyText
{
    self.emptyText = [[TBLibrary shared] subscriptions].count ? L(@"The channels you follow have not published anything.") : L(@"Open a channel and tap Subscribe: its new videos gather here, without any account.");
}

- (void)reload
{
    self.forceNext = YES;
    [self updateEmptyText];
    [super reload];
}

- (void)libraryChanged
{
    [self updateEmptyText];
    if (self.isViewLoaded && self.view.window) [super reload];   // (a cached feed answers at once; a new channel triggers a fresh one)
}

- (void)channelsTapped
{
    TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:nil];
    grid.title = L(@"Channels");
    grid.emptyText = L(@"No subscriptions yet.");
    [grid replaceItems:[[TBLibrary shared] subscriptions]];
    __weak TBGridViewController *weakGrid = grid;
    grid.onRemoveItem = ^(id item) {
        if ([item isKindOfClass:[TBChannel class]]) [[TBLibrary shared] unsubscribe:[(TBChannel *)item channelId]];
        [weakGrid replaceItems:[[TBLibrary shared] subscriptions]];
    };
    [self.navigationController pushViewController:grid animated:YES];
}

@end
