#import "TBLibraryViewController.h"
#import "TBGridViewController.h"
#import "TBSettingsViewController.h"
#import "TBLibrary.h"
#import "TBInnertube.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

@implementation TBLibraryViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = L(@"Library");
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:TBLibraryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:TBThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:TBAccountDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if ([[TBAccount shared] isSignedIn]) {
        [[TBAccount shared] syncSubscriptions:nil];
    }
    [self refresh];
}

- (void)refresh
{
    TBTheme *t = [TBTheme shared];
    [t applyToTableView:self.tableView];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // (with the account signed in: its liked videos and playlists as well)
    return section == 0 ? ([[TBAccount shared] isSignedIn] ? 5 : 3) : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TBTheme *t = [TBTheme shared];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    [t styleCell:cell];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    TBLibrary *library = [TBLibrary shared];
    if (indexPath.section == 1) {
        cell.textLabel.text = L(@"Settings");
        return cell;
    }
    switch (indexPath.row) {
        case 0: cell.textLabel.text = L(@"History"); cell.detailTextLabel.text = [[TBAccount shared] isSignedIn] ? @"" : [NSString stringWithFormat:@"%lu", (unsigned long)[library history].count]; break;
        case 1: cell.textLabel.text = L(@"Watch later"); cell.detailTextLabel.text = [[TBAccount shared] isSignedIn] ? @"" : [NSString stringWithFormat:@"%lu", (unsigned long)[library watchLater].count]; break;
        case 2: cell.textLabel.text = L(@"Subscriptions"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[library subscriptions].count]; break;
        case 3: cell.textLabel.text = L(@"Liked videos"); cell.detailTextLabel.text = @""; break;
        default: cell.textLabel.text = L(@"My playlists"); cell.detailTextLabel.text = @""; break;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        [self.navigationController pushViewController:[[TBSettingsViewController alloc] init] animated:YES];
        return;
    }
    TBLibrary *library = [TBLibrary shared];
    if (indexPath.row == 0 && [[TBAccount shared] isSignedIn]) {
        TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            return [TBInnertube authenticatedBrowse:@"FEhistory" params:nil continuation:continuation completion:^(NSDictionary *resp, NSArray *items, NSString *nextContinuation, NSError *error) {
                if (error && !continuation) {
                    NSArray *local = [[TBLibrary shared] history];
                    if (local.count > 0) {
                        if (completion) completion(local, nil, nil);
                        return;
                    }
                }
                if (completion) completion(items, nextContinuation, error);
            }];
        }];
        grid.title = L(@"History");
        grid.emptyText = L(@"Nothing watched yet.");
        __weak TBGridViewController *weakGrid = grid;
        grid.onRemoveItem = ^(id item) {
            if (![item isKindOfClass:[TBVideo class]]) return;
            NSString *vid = [(TBVideo *)item videoId];
            [[TBLibrary shared] removeFromHistory:vid];
            [[TBAccount shared] removeFromHistory:vid completion:nil];
            NSMutableArray *curr = [weakGrid.items mutableCopy];
            [curr removeObject:item];
            [weakGrid replaceItems:curr];
        };
        [self.navigationController pushViewController:grid animated:YES];
        return;
    }
    if (indexPath.row == 1 && [[TBAccount shared] isSignedIn]) {
        TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            return [TBInnertube authenticatedBrowse:@"VLWL" params:nil continuation:continuation completion:^(NSDictionary *resp, NSArray *items, NSString *nextContinuation, NSError *error) {
                if (error && !continuation) {
                    NSArray *local = [[TBLibrary shared] watchLater];
                    if (local.count > 0) {
                        if (completion) completion(local, nil, nil);
                        return;
                    }
                }
                if (completion) completion(items, nextContinuation, error);
            }];
        }];
        grid.title = L(@"Watch later");
        grid.emptyText = L(@"Nothing saved for later. The button is on every video's page.");
        __weak TBGridViewController *weakGrid = grid;
        grid.onRemoveItem = ^(id item) {
            if (![item isKindOfClass:[TBVideo class]]) return;
            NSString *vid = [(TBVideo *)item videoId];
            [[TBLibrary shared] removeFromWatchLater:vid];
            [[TBAccount shared] removeFromWatchLater:vid completion:nil];
            NSMutableArray *curr = [weakGrid.items mutableCopy];
            [curr removeObject:item];
            [weakGrid replaceItems:curr];
        };
        [self.navigationController pushViewController:grid animated:YES];
        return;
    }
    if (indexPath.row == 2 && [[TBAccount shared] isSignedIn]) {
        TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            return [[TBAccount shared] syncSubscriptions:^(NSArray *channels, NSError *error) {
                if (completion) completion(channels ?: [[TBLibrary shared] subscriptions], nil, error);
            }];
        }];
        grid.title = L(@"Subscriptions");
        grid.emptyText = L(@"No subscriptions yet.");
        [grid replaceItems:[library subscriptions]];
        __weak TBGridViewController *weakGrid = grid;
        grid.onRemoveItem = ^(id item) {
            if (![item isKindOfClass:[TBChannel class]]) return;
            NSString *channelId = [(TBChannel *)item channelId];
            [[TBAccount shared] unsubscribeFrom:channelId completion:^(NSError *error) {
                if (error) { [TBUtils alertWithTitle:L(@"Subscriptions") message:error.localizedDescription]; return; }
                [[TBLibrary shared] unsubscribe:channelId];
                [weakGrid replaceItems:[[TBLibrary shared] subscriptions]];
            }];
        };
        [self.navigationController pushViewController:grid animated:YES];
        return;
    }
    if (indexPath.row >= 3) {
        // the account's lists, a page at a time
        BOOL liked = indexPath.row == 3;
        TBGridViewController *paged = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            if (liked && ![[TBAccount shared] usesCustomOAuthClient]) {
                return [TBInnertube authenticatedBrowse:@"VLLL" params:nil continuation:continuation completion:^(NSDictionary *resp, NSArray *items, NSString *nextContinuation, NSError *error) {
                    if (completion) completion(items, nextContinuation, error);
                }];
            }
            if (!liked && ![[TBAccount shared] usesCustomOAuthClient]) {
                return [TBInnertube authenticatedBrowse:@"FEplaylist_aggregation" params:nil continuation:continuation completion:^(NSDictionary *resp, NSArray *items, NSString *nextContinuation, NSError *error) {
                    if (items.count > 0 || !error) {
                        if (completion) completion(items, nextContinuation, error);
                    } else {
                        [[TBAccount shared] playlistsPage:continuation completion:completion];
                    }
                }];
            }
            return liked ? [[TBAccount shared] likedVideosPage:continuation completion:completion] : [[TBAccount shared] playlistsPage:continuation completion:completion];
        }];
        paged.title = liked ? L(@"Liked videos") : L(@"My playlists");
        paged.emptyText = liked ? L(@"No liked videos.") : L(@"No playlists.");
        [self.navigationController pushViewController:paged animated:YES];
        return;
    }
    TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:nil];
    __weak TBGridViewController *weakGrid = grid;
    // (each case in braces: a block literal is a declaration the compiler will not let a later case jump over)
    switch (indexPath.row) {
        case 0: {
            grid.title = L(@"History");
            grid.emptyText = L(@"Nothing watched yet.");
            [grid replaceItems:[library history]];
            grid.onRemoveItem = ^(id item) {
                NSString *vid = [(TBVideo *)item videoId];
                [library removeFromHistory:vid];
                if ([[TBAccount shared] isSignedIn]) [[TBAccount shared] removeFromHistory:vid completion:nil];
                [weakGrid replaceItems:[library history]];
            };
            grid.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Clear") style:UIBarButtonItemStyleBordered target:self action:@selector(clearHistoryTapped)];
            break;
        }
        case 1: {
            grid.title = L(@"Watch later");
            grid.emptyText = L(@"Nothing saved for later. The button is on every video's page.");
            [grid replaceItems:[library watchLater]];
            grid.onRemoveItem = ^(id item) {
                NSString *vid = [(TBVideo *)item videoId];
                [library removeFromWatchLater:vid];
                if ([[TBAccount shared] isSignedIn]) [[TBAccount shared] removeFromWatchLater:vid completion:nil];
                [weakGrid replaceItems:[library watchLater]];
            };
            break;
        }
        default: {
            grid.title = L(@"Subscriptions");
            grid.emptyText = L(@"No subscriptions yet.");
            [grid replaceItems:[library subscriptions]];
            grid.onRemoveItem = ^(id item) { [library unsubscribe:[(TBChannel *)item channelId]]; [weakGrid replaceItems:[library subscriptions]]; };
            break;
        }
    }
    [self.navigationController pushViewController:grid animated:YES];
}

- (void)clearHistoryTapped
{
    [[TBLibrary shared] clearHistory];
    UIViewController *top = self.navigationController.topViewController;
    if ([top isKindOfClass:[TBGridViewController class]]) [(TBGridViewController *)top replaceItems:@[]];
}

@end
