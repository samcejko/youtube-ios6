#import "TBSubscriptionsViewController.h"
#import "TBNavigator.h"
#import "TBLibrary.h"
#import "TBInnertube.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBUtils.h"
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
            if ([[TBAccount shared] isSignedIn] && ![[TBAccount shared] usesCustomOAuthClient]) {
                return [TBInnertube authenticatedBrowse:@"FEsubscriptions" params:nil continuation:continuation completion:^(NSDictionary *resp, NSArray *items, NSString *nextContinuation, NSError *error) {
                    if (error && !continuation) {
                        BOOL force = s.forceNext;
                        s.forceNext = NO;
                        [[TBLibrary shared] feedForce:force completion:^(NSArray *videos, NSError *feedError) {
                            completion(videos, nil, feedError);
                        }];
                        return;
                    }
                    completion(items, nextContinuation, error);
                }];
            }
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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Channels") style:UIBarButtonItemStyleBordered target:self action:@selector(channelsTapped)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TBAccountDidChangeNotification object:nil];
}

- (void)accountChanged
{
    if (self.isViewLoaded && self.view.window) [self reload];
}

- (void)updateEmptyText
{
    if ([[TBLibrary shared] subscriptions].count) self.emptyText = L(@"The channels you follow have not published anything.");
    else self.emptyText = [[TBAccount shared] isSignedIn] ? L(@"Your account follows no channels yet.") : L(@"Open a channel and tap Subscribe: its new videos gather here, without any account.");
}

- (void)reload
{
    self.forceNext = YES;
    [self updateEmptyText];
    if ([[TBAccount shared] isSignedIn]) {
        // a pull brings the account's subscriptions up to date first, the feed follows
        __weak TBSubscriptionsViewController *weakSelf = self;
        [[TBAccount shared] syncSubscriptions:^(NSArray *channels, NSError *error) {
            if (error) TBLog(@"Subscriptions: %@", error.localizedDescription);
            [weakSelf reloadFeed];
        }];
        return;
    }
    [super reload];
}

- (void)reloadFeed
{
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
    TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
        if ([[TBAccount shared] isSignedIn]) {
            return [[TBAccount shared] syncSubscriptions:^(NSArray *channels, NSError *error) {
                if (completion) completion(channels ?: [[TBLibrary shared] subscriptions], nil, error);
            }];
        }
        if (completion) completion([[TBLibrary shared] subscriptions], nil, nil);
        return nil;
    }];
    grid.title = L(@"Channels");
    grid.emptyText = L(@"No subscriptions yet.");
    [grid replaceItems:[[TBLibrary shared] subscriptions]];
    __weak TBGridViewController *weakGrid = grid;
    grid.onRemoveItem = ^(id item) {
        if (![item isKindOfClass:[TBChannel class]]) return;
        NSString *channelId = [(TBChannel *)item channelId];
        if ([[TBAccount shared] isSignedIn]) {
            [[TBAccount shared] unsubscribeFrom:channelId completion:^(NSError *error) {
                if (error) { [TBUtils alertWithTitle:L(@"Subscriptions") message:error.localizedDescription]; return; }
                [[TBLibrary shared] unsubscribe:channelId];
                [weakGrid replaceItems:[[TBLibrary shared] subscriptions]];
            }];
            return;
        }
        [[TBLibrary shared] unsubscribe:channelId];
        [weakGrid replaceItems:[[TBLibrary shared] subscriptions]];
    };
    [self.navigationController pushViewController:grid animated:YES];
}

@end
