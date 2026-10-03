#import "TBChoiceViewController.h"
#import "TBTheme.h"
#import "TBCommon.h"

@implementation TBChoiceViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToTableView:self.tableView];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.titles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL subtitle = (NSUInteger)indexPath.row < self.subtitles.count && [self.subtitles[(NSUInteger)indexPath.row] length];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:subtitle ? UITableViewCellStyleSubtitle : UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.titles[(NSUInteger)indexPath.row];
    if (subtitle) {
        cell.detailTextLabel.text = self.subtitles[(NSUInteger)indexPath.row];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
        cell.detailTextLabel.numberOfLines = 2;
    }
    cell.accessoryType = indexPath.row == self.selectedIndex ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    [[TBTheme shared] styleCell:cell];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL subtitle = (NSUInteger)indexPath.row < self.subtitles.count && [self.subtitles[(NSUInteger)indexPath.row] length];
    return subtitle ? 56 : 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.selectedIndex = indexPath.row;
    [tableView reloadData];
    if (self.completion) self.completion(indexPath.row);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
