#import "TBSearchViewController.h"
#import "TBGridViewController.h"
#import "TBInnertube.h"
#import "TBSettings.h"
#import "TBTheme.h"
#import "TBCommon.h"

@interface TBSearchViewController () <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UISegmentedControl *filter;
@property (nonatomic, strong) UIView *filterBar;
@property (nonatomic, strong) TBGridViewController *grid;
@property (nonatomic, strong) UITableView *suggestionTable;
@property (nonatomic, strong) NSArray *suggestions;
@property (nonatomic, strong) TBHTTPTask *suggestionTask;
@property (nonatomic, copy) NSString *query;
@property (nonatomic) BOOL showsSuggestions;
@end

@implementation TBSearchViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) self.title = L(@"Search");
    return self;
}

- (void)dealloc
{
    [_suggestionTask cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = L(@"Search YouTube");
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchBar.showsCancelButton = NO;
    self.navigationItem.titleView = self.searchBar;

    self.filterBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 40)];
    self.filterBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.filter = [[UISegmentedControl alloc] initWithItems:@[ L(@"All"), L(@"Videos"), L(@"Channels"), L(@"Playlists"), L(@"Live") ]];
    self.filter.segmentedControlStyle = UISegmentedControlStyleBar;
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.filterBar addSubview:self.filter];
    [self.view addSubview:self.filterBar];

    __weak TBSearchViewController *weakSelf = self;
    self.grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
        TBSearchViewController *s = weakSelf;
        if (!s.query.length) { TBMain(^{ completion(@[], nil, nil); }); return nil; }
        return [TBInnertube search:s.query filter:[s currentFilter] continuation:continuation completion:completion];
    }];
    self.grid.emptyText = L(@"Nothing found.");
    self.grid.refreshesOnAppear = NO;
    [self addChildViewController:self.grid];
    [self.view addSubview:self.grid.view];
    [self.grid didMoveToParentViewController:self];

    self.suggestionTable = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.suggestionTable.dataSource = self;
    self.suggestionTable.delegate = self;
    self.suggestionTable.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.suggestionTable];

    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TBThemeDidChangeNotification object:nil];
    [self showSuggestions:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    [self.suggestionTable reloadData];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    self.filterBar.frame = CGRectMake(0, 0, b.size.width, 40);
    CGFloat fw = MIN(b.size.width - 16, 520);
    self.filter.frame = CGRectMake(floor((b.size.width - fw) / 2), 5, fw, 30);
    self.grid.view.frame = CGRectMake(0, 40, b.size.width, b.size.height - 40);
    self.suggestionTable.frame = b;
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    self.view.backgroundColor = [t backgroundColor];
    self.filterBar.backgroundColor = [t backgroundColor];
    [t applyToSearchBar:self.searchBar];
    [t applyToTableView:self.suggestionTable];
    self.suggestionTable.backgroundColor = [t cardColor];
    [self.suggestionTable reloadData];
}

- (void)showSuggestions:(BOOL)show
{
    self.showsSuggestions = show;
    self.suggestionTable.hidden = !show;
    self.grid.view.hidden = show;
    self.filterBar.hidden = show;
    if (show) [self.suggestionTable reloadData];
}

#pragma mark - Searching

- (NSString *)currentFilter
{
    switch (self.filter.selectedSegmentIndex) {
        case 1: return TBSearchFilterVideos;
        case 2: return TBSearchFilterChannels;
        case 3: return TBSearchFilterPlaylists;
        case 4: return TBSearchFilterLive;
        default: return nil;
    }
}

- (void)filterChanged
{
    if (self.query.length) [self.grid reload];
}

- (void)searchFor:(NSString *)text
{
    [self view];
    self.searchBar.text = text;
    [self.searchBar resignFirstResponder];
    [self runSearch];
}

- (void)runSearch
{
    NSString *text = [self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (!text.length) return;
    self.query = text;
    [TBSettings addRecentSearch:text];
    [self showSuggestions:NO];
    [self.grid reload];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:YES animated:YES];
    [self showSuggestions:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
    if (![searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) {
        self.suggestions = nil;
        [self.suggestionTable reloadData];
        return;
    }
    [self performSelector:@selector(fetchSuggestions) withObject:nil afterDelay:0.35];
}

- (void)fetchSuggestions
{
    NSString *text = self.searchBar.text;
    [self.suggestionTask cancel];
    __weak TBSearchViewController *weakSelf = self;
    self.suggestionTask = [TBInnertube searchSuggestions:text completion:^(NSArray *suggestions, NSError *error) {
        TBSearchViewController *s = weakSelf;
        if (!s || ![s.searchBar.text isEqualToString:text]) return;
        s.suggestionTask = nil;
        s.suggestions = suggestions;
        [s.suggestionTable reloadData];
    }];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
    [searchBar resignFirstResponder];
    [self runSearch];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    if (self.query.length) { searchBar.text = self.query; [self showSuggestions:NO]; }
}

#pragma mark - Suggestions table

- (BOOL)showsRecent
{
    return ![self.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if ([self showsRecent]) {
        NSUInteger count = [TBSettings recentSearches].count;
        return (NSInteger)(count ? count + 1 : 0);
    }
    return (NSInteger)self.suggestions.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if ([self showsRecent]) return [TBSettings recentSearches].count ? L(@"Recent searches") : nil;
    return self.suggestions.count ? L(@"Suggestions") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TBTheme *t = [TBTheme shared];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"s"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"s"];
    [t styleCell:cell];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.textColor = [t primaryTextColor];
    if ([self showsRecent]) {
        NSArray *recent = [TBSettings recentSearches];
        if ((NSUInteger)indexPath.row < recent.count) {
            cell.textLabel.text = recent[(NSUInteger)indexPath.row];
        } else {
            cell.textLabel.text = L(@"Clear recent searches");
            cell.textLabel.font = [UIFont systemFontOfSize:15];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [t secondaryTextColor];
        }
    } else {
        cell.textLabel.text = self.suggestions[(NSUInteger)indexPath.row];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self showsRecent]) {
        NSArray *recent = [TBSettings recentSearches];
        if ((NSUInteger)indexPath.row < recent.count) {
            self.searchBar.text = recent[(NSUInteger)indexPath.row];
        } else {
            [TBSettings clearRecentSearches];
            [tableView reloadData];
            return;
        }
    } else {
        self.searchBar.text = self.suggestions[(NSUInteger)indexPath.row];
    }
    [self.searchBar resignFirstResponder];
    [self runSearch];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.searchBar resignFirstResponder];
}

@end
