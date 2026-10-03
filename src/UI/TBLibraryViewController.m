#import "TBLibraryViewController.h"
#import "TBGridViewController.h"
#import "TBSettingsViewController.h"
#import "TBLibrary.h"
#import "TBTheme.h"
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
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
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
    return section == 0 ? 3 : 1;
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
        case 0: cell.textLabel.text = L(@"History"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[library history].count]; break;
        case 1: cell.textLabel.text = L(@"Watch later"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[library watchLater].count]; break;
        default: cell.textLabel.text = L(@"Subscriptions"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[library subscriptions].count]; break;
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
    TBGridViewController *grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:nil];
    __weak TBGridViewController *weakGrid = grid;
    // (each case in braces: a block literal is a declaration the compiler will not let a later case jump over)
    switch (indexPath.row) {
        case 0: {
            grid.title = L(@"History");
            grid.emptyText = L(@"Nothing watched yet.");
            [grid replaceItems:[library history]];
            grid.onRemoveItem = ^(id item) { [library removeFromHistory:[(TBVideo *)item videoId]]; [weakGrid replaceItems:[library history]]; };
            grid.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Clear") style:UIBarButtonItemStyleBordered target:self action:@selector(clearHistoryTapped)];
            break;
        }
        case 1: {
            grid.title = L(@"Watch later");
            grid.emptyText = L(@"Nothing saved for later. The button is on every video's page.");
            [grid replaceItems:[library watchLater]];
            grid.onRemoveItem = ^(id item) { [library removeFromWatchLater:[(TBVideo *)item videoId]]; [weakGrid replaceItems:[library watchLater]]; };
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
