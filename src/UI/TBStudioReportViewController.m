#import "TBStudioReportViewController.h"
#import "TBStudio.h"
#import "TBStudioReports.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

static NSString *Number(id value){NSNumber *n=[TBStudioReports number:value];if(!n)return @"—";NSNumberFormatter *f=[[NSNumberFormatter alloc] init];f.numberStyle=NSNumberFormatterDecimalStyle;f.maximumFractionDigits=1;return [f stringFromNumber:n];}
static NSString *Metric(NSString *key){NSDictionary *names=@{@"views":L(@"Views"),@"estimatedMinutesWatched":L(@"Watch time"),@"averageViewDuration":L(@"Average view duration"),@"averageViewPercentage":L(@"Average viewed"),@"likes":L(@"Likes"),@"comments":L(@"Comments"),@"shares":L(@"Shares"),@"subscribersGained":L(@"Subscribers gained"),@"subscribersLost":L(@"Subscribers lost")};return names[key] ?: key;}
static NSString *Value(NSString *key,id value){if([key isEqualToString:@"averageViewDuration"])return [TBUtils formatDuration:[[TBStudioReports number:value] doubleValue]];if([key isEqualToString:@"estimatedMinutesWatched"])return [NSString stringWithFormat:L(@"%@ minutes"),Number(value)];if([key isEqualToString:@"averageViewPercentage"])return [Number(value) stringByAppendingString:@"%"] ;return Number(value);}

@interface TBStudioReportViewController ()
@property(nonatomic,copy) NSString *dimension;
@property(nonatomic,copy) NSString *videoId;
@property(nonatomic) NSInteger days;
@property(nonatomic,strong) NSDictionary *report;
@property(nonatomic,strong) NSDictionary *comparison;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) TBHTTPTask *task;
@property(nonatomic,strong) UIDocumentInteractionController *document;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@end
@implementation TBStudioReportViewController
- (instancetype)initWithDimension:(NSString *)dimension title:(NSString *)title days:(NSInteger)days video:(NSString *)videoId {self=[super initWithStyle:UITableViewStyleGrouped];if(self){self.dimension=dimension;self.title=title;self.days=days;self.videoId=videoId;}return self;}
- (instancetype)initWithComparison:(NSDictionary *)dashboard {self=[super initWithStyle:UITableViewStyleGrouped];if(self){self.title=L(@"Compare periods");self.comparison=dashboard;self.rows=[TBStudioReports comparisonRows:dashboard];}return self;}
- (void)dealloc {[_task cancel];[[NSNotificationCenter defaultCenter] removeObserver:self];}
- (void)viewDidLoad {[super viewDidLoad];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TBAccountDidChangeNotification object:nil];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:L(@"Export CSV") style:UIBarButtonItemStyleBordered target:self action:@selector(exportCSV)];if(!self.comparison)self.navigationItem.rightBarButtonItems=@[self.navigationItem.rightBarButtonItem,[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)]];if(!self.comparison)[self reload];else [self.tableView reloadData];}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[[TBTheme shared] applyToTableView:self.tableView];[[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];}
- (void)accountChanged {if(self.comparison){self.rows=@[];self.comparison=nil;self.report=@{@"error":L(@"Reopen this report after changing accounts.")};[self.tableView reloadData];}else [self reload];}
- (void)reload {[_task cancel];self.rows=nil;self.report=nil;self.loading=YES;NSUInteger generation=++self.generation;[self.tableView reloadData];__weak TBStudioReportViewController *weakSelf=self;self.task=[TBStudio reportForDimension:self.dimension days:self.days video:self.videoId completion:^(NSDictionary *report){TBStudioReportViewController *s=weakSelf;if(!s || s.generation!=generation)return;s.task=nil;s.loading=NO;s.report=report;s.rows=TBArr(report[@"rows"]);[s.tableView reloadData];}];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return MAX((NSUInteger)1,self.rows.count);}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(self.loading)return L(@"Loading…");if(self.report[@"error"])return self.report[@"error"];
    if(self.comparison){NSString *last=TBStr(TBDict([TBArr(self.comparison[@"daily"]) lastObject])[@"day"]) ?: @"—";return [NSString stringWithFormat:L(@"Current: %@ – %@\nPrevious: %@ – %@\nMatching available days are compared; recent reports can be delayed."),self.comparison[@"startDate"] ?: @"—",last,self.comparison[@"previousStartDate"] ?: @"—",self.comparison[@"previousEndDate"] ?: @"—"];}
    return [NSString stringWithFormat:L(@"%@ – %@\nUp to 25 rows. YouTube may withhold small audiences for privacy. Percentages refer to the listed views."),self.report[@"startDate"] ?: @"—",self.report[@"endDate"] ?: @"—"];
}
- (NSString *)label:(NSString *)code {
    if([self.dimension isEqualToString:@"country"]){if([code isEqualToString:@"ZZ"])return L(@"Unknown");return [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:code] ?: code;}
    NSDictionary *names=@{@"ANDROID":@"Android",@"IOS":@"iOS",@"WINDOWS":@"Windows",@"LINUX":@"Linux",@"MACINTOSH":@"macOS",@"MOBILE":L(@"Mobile"),@"TABLET":L(@"Tablet"),@"DESKTOP":L(@"Computer"),@"TV":L(@"TV"),@"GAME_CONSOLE":L(@"Game console"),@"UNKNOWN_PLATFORM":L(@"Unknown"),@"SUBSCRIBED":L(@"Subscribed viewers"),@"UNSUBSCRIBED":L(@"Other viewers"),@"VIDEO_ON_DEMAND":L(@"Videos"),@"LIVE_STREAM":L(@"Live streams"),@"SHORTS":L(@"Shorts"),@"STORY":L(@"Stories"),@"UNSPECIFIED":L(@"Unknown"),@"YT_SEARCH":L(@"YouTube search"),@"EXT_URL":L(@"External links"),@"RELATED_VIDEO":L(@"Suggested videos"),@"SUBSCRIBER":L(@"Home and subscriptions"),@"NO_LINK_OTHER":L(@"Direct or unknown"),@"YT_CHANNEL":L(@"Channel pages"),@"PLAYLIST":L(@"Playlists"),@"NOTIFICATION":L(@"Notifications"),@"END_SCREEN":L(@"End screens"),@"YT_OTHER_PAGE":L(@"Other YouTube pages"),@"WATCH":L(@"Watch page"),@"EMBEDDED":L(@"Embedded players"),@"BROWSE":L(@"Browse"),@"EXTERNAL_APP":L(@"External apps")};return names[code] ?: code;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path {return self.comparison?76:64;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];[[TBTheme shared] styleCell:cell];cell.selectionStyle=self.rows.count?UITableViewCellSelectionStyleBlue:UITableViewCellSelectionStyleNone;cell.detailTextLabel.numberOfLines=2;
    if(!self.rows.count){cell.textLabel.text=self.loading?L(@"Loading…"):L(@"No report data available.");return cell;}
    NSDictionary *row=self.rows[path.row];
    if(self.comparison){NSString *key=TBStr(row[@"metric"]);cell.textLabel.text=[NSString stringWithFormat:@"%@: %@",Metric(key),Value(key,row[@"current"])];NSString *change=row[@"percentage"]?[NSString stringWithFormat:@"%+.1f%%",[row[@"percentage"] doubleValue]]:L(@"No percentage baseline");cell.detailTextLabel.text=[NSString stringWithFormat:L(@"Previous: %@ · change %@ (%@)"),Value(key,row[@"previous"]),[NSString stringWithFormat:@"%+.1f",[row[@"change"] doubleValue]],change];}
    else {double total=0;for(NSDictionary *r in self.rows)total+=[[TBStudioReports number:r[@"views"]] doubleValue];double count=[[TBStudioReports number:row[@"views"]] doubleValue];cell.textLabel.text=[self label:TBStr(row[self.dimension]) ?: L(@"Unknown")];NSString *share=total>0?[NSString stringWithFormat:@"%.1f%%",count/total*100]:@"—";cell.detailTextLabel.text=[NSString stringWithFormat:L(@"%@ views · %@ minutes · %@"),Number(row[@"views"]),Number(row[@"estimatedMinutesWatched"]),share];}return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {[tableView deselectRowAtIndexPath:path animated:YES];if(!self.rows.count)return;UITableViewCell *cell=[tableView cellForRowAtIndexPath:path];[TBUtils alertWithTitle:cell.textLabel.text message:cell.detailTextLabel.text];}
- (void)exportCSV {
    if(!self.rows.count){[TBUtils alertWithTitle:L(@"Studio") message:L(@"No report data available.")];return;}
    NSArray *columns=self.comparison?@[@"metric",@"current",@"previous",@"change",@"percentage"]:@[self.dimension,@"views",@"estimatedMinutesWatched"];
    NSString *csv=[TBStudioReports CSVForRows:self.rows columns:columns];NSString *file=[NSTemporaryDirectory() stringByAppendingPathComponent:self.comparison?@"Studio-comparison.csv":[@"Studio-" stringByAppendingFormat:@"%@.csv",self.dimension]];
    if(![csv writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]){[TBUtils alertWithTitle:L(@"Studio") message:L(@"The report could not be saved.")];return;}
    self.document=[UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:file]];self.document.UTI=@"public.comma-separated-values-text";
    if(![self.document presentOptionsMenuFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES]){[UIPasteboard generalPasteboard].string=csv;[TBUtils alertWithTitle:L(@"Studio") message:L(@"CSV copied to the clipboard.")];}
}
@end
