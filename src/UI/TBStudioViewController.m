#import "TBStudioViewController.h"
#import "TBStudio.h"
#import "TBStudioReports.h"
#import "TBStudioReportViewController.h"
#import "TBAccount.h"
#import "TBSettingsViewController.h"
#import "TBGoogleLoginViewController.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBNavigator.h"
#import "TBCommon.h"

@interface TBStudioChart : UIView
@property(nonatomic,copy) NSArray *rows;
@property(nonatomic) NSInteger metric;
@property(nonatomic,copy) void (^selected)(NSDictionary *);
@end
static double ChartValue(NSDictionary *row,NSInteger metric){if(metric==1)return [row[@"estimatedMinutesWatched"] doubleValue];if(metric==2)return [row[@"subscribersGained"] doubleValue]-[row[@"subscribersLost"] doubleValue];return [row[@"views"] doubleValue];}
@implementation TBStudioChart
- (instancetype)initWithFrame:(CGRect)frame {self=[super initWithFrame:frame];if(self)[self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];return self;}
- (void)tapped:(UITapGestureRecognizer *)gesture {CGFloat x=[gesture locationInView:self].x-36,width=MAX(1,self.bounds.size.width-48);if(x<0 || x>width || !self.rows.count)return;NSUInteger i=MIN(self.rows.count-1,(NSUInteger)(x/width*self.rows.count));if(self.selected)self.selected(self.rows[i]);}
- (void)setMetric:(NSInteger)metric {_metric=metric;[self setNeedsDisplay];}
- (void)setRows:(NSArray *)rows { _rows=[rows copy];[self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    TBTheme *theme=[TBTheme shared];[[theme cardColor] setFill];UIRectFill(self.bounds);
    CGRect plot=CGRectMake(36,16,MAX(1,self.bounds.size.width-48),108);
    [[theme secondaryTextColor] setStroke];UIBezierPath *grid=[UIBezierPath bezierPath];
    for(int i=0;i<3;i++){CGFloat y=plot.origin.y+plot.size.height*i/2;[grid moveToPoint:CGPointMake(plot.origin.x,y)];[grid addLineToPoint:CGPointMake(CGRectGetMaxX(plot),y)];}
    grid.lineWidth=.25;[grid stroke];
    double maximum=1,minimum=0;for(NSDictionary *row in self.rows){double value=ChartValue(row,self.metric);maximum=MAX(maximum,value);minimum=MIN(minimum,value);}
    CGFloat zero=plot.origin.y+plot.size.height*maximum/(maximum-minimum);
    CGFloat step=plot.size.width/MAX((NSUInteger)1,self.rows.count);
    CGContextRef context=UIGraphicsGetCurrentContext();
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)@[(id)[UIColor colorWithRed:.95 green:.36 blue:.32 alpha:1].CGColor,(id)[UIColor colorWithRed:.58 green:.04 blue:.03 alpha:1].CGColor],NULL);
    for(NSUInteger i=0;i<self.rows.count;i++) {
        double value=ChartValue(self.rows[i],self.metric);CGFloat height=plot.size.height*fabs(value)/(maximum-minimum);
        CGRect bar=CGRectMake(plot.origin.x+i*step+1,value>=0?zero-height:zero,MAX(1,step-2),height);
        CGContextSaveGState(context);CGContextClipToRect(context,bar);
        CGContextDrawLinearGradient(context,gradient,bar.origin,CGPointMake(bar.origin.x,CGRectGetMaxY(bar)),0);CGContextRestoreGState(context);
    }
    CGGradientRelease(gradient);CGColorSpaceRelease(space);
    [[theme secondaryTextColor] setFill];UIFont *font=[UIFont systemFontOfSize:10];
    [[TBUtils formatCount:(NSInteger)MIN((double)NSIntegerMax,maximum)] drawInRect:CGRectMake(1,8,33,16) withFont:font];if(minimum<0)[[NSString stringWithFormat:@"%.0f",minimum] drawInRect:CGRectMake(1,112,33,16) withFont:font];
    NSString *first=TBStr(TBDict([self.rows firstObject])[@"day"]) ?: @"",*last=TBStr(TBDict([self.rows lastObject])[@"day"]) ?: @"";
    [first drawInRect:CGRectMake(12,130,110,18) withFont:font];
    [last drawInRect:CGRectMake(self.bounds.size.width-122,130,110,18) withFont:font lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentRight];
}
@end

@interface TBStudioViewController ()
@property(nonatomic,strong) TBHTTPTask *task;
@property(nonatomic,strong) NSDictionary *dashboard;
@property(nonatomic,strong) UISegmentedControl *period;
@property(nonatomic) NSInteger days;
@property(nonatomic) NSInteger chartMetric;
@property(nonatomic,copy) NSString *videoId;
@property(nonatomic,copy) NSString *videoTitle;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@end
@implementation TBStudioViewController
- (instancetype)init { self=[super initWithStyle:UITableViewStyleGrouped];if(self){self.title=L(@"Studio");self.days=28;}return self; }
- (instancetype)initWithVideo:(NSString *)videoId title:(NSString *)title days:(NSInteger)days {self=[self init];if(self){self.videoId=videoId;self.videoTitle=title;self.title=L(@"Video analytics");self.days=days;}return self;}
- (void)dealloc { [_task cancel];[[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)accountChanged {[self reload];}
- (void)chartChanged:(UISegmentedControl *)sender {self.chartMetric=sender.selectedSegmentIndex;[self.tableView reloadData];}
- (NSArray *)reportTitles {return @[L(@"Countries"),L(@"Devices"),L(@"Operating systems"),L(@"Traffic sources"),L(@"Subscribed and other viewers"),L(@"Videos, Shorts and live"),L(@"Playback locations")];}
- (void)openComparison {if(![TBStudioReports comparisonRows:self.dashboard].count){[TBUtils alertWithTitle:L(@"Compare periods") message:self.dashboard[@"previousSummaryError"] ?: L(@"No report data available.")];return;}[self.navigationController pushViewController:[[TBStudioReportViewController alloc] initWithComparison:self.dashboard] animated:YES];}
- (void)viewDidLoad {
    [super viewDidLoad];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TBAccountDidChangeNotification object:nil];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,58)];
    self.period=[[UISegmentedControl alloc] initWithItems:@[L(@"7 days"),L(@"28 days"),L(@"90 days")]];
    self.period.frame=CGRectMake(14,12,header.bounds.size.width-28,32);self.period.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.period.selectedSegmentIndex=self.days==7?0:(self.days==90?2:1);self.period.segmentedControlStyle=UISegmentedControlStyleBar;
    [self.period addTarget:self action:@selector(periodChanged) forControlEvents:UIControlEventValueChanged];[header addSubview:self.period];self.tableView.tableHeaderView=header;
    [self reload];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];TBTheme *theme=[TBTheme shared];[theme applyToTableView:self.tableView];[theme applyToNavigationBar:self.navigationController.navigationBar];

}
- (void)periodChanged { self.days=self.period.selectedSegmentIndex==0?7:(self.period.selectedSegmentIndex==2?90:28);[self reload]; }
- (void)reload {
    [self.task cancel];NSUInteger generation=++self.generation;self.loading=YES;self.dashboard=nil;[self.tableView reloadData];
    __weak TBStudioViewController *weakSelf=self;
    self.task=[TBStudio dashboardForDays:self.days video:self.videoId completion:^(NSDictionary *dashboard){TBStudioViewController *s=weakSelf;if(!s || s.generation!=generation)return;s.task=nil;s.loading=NO;s.dashboard=dashboard;[s.tableView reloadData];}];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [[TBAccount shared] isSignedIn]?6:1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section==0)return self.videoId.length?1:(self.dashboard[@"channel"]?4:1);
    if(section==1)return [TBArr(self.dashboard[@"summary"]) count]?8:1;
    if(section==2)return 1;
    if(section==3)return self.videoId.length?1:MAX((NSUInteger)1,[TBArr(self.dashboard[@"topVideos"]) count]);
    if(section==4)return [TBStudioReports dimensions].count+1;
    return 1;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view=RetroSectionHeader([self tableView:tableView titleForHeaderInSection:section],tableView.bounds.size.width);
    if([TBTheme shared].isDark)for(UILabel *label in view.subviews){label.textColor=[[TBTheme shared] secondaryTextColor];label.shadowColor=[UIColor blackColor];}
    if(section==2){CGRect frame=view.frame;frame.size.height=74;view.frame=frame;UISegmentedControl *choice=[[UISegmentedControl alloc] initWithItems:@[L(@"Views"),L(@"Minutes"),L(@"Subscribers")]];choice.frame=CGRectMake(14,34,tableView.bounds.size.width-28,30);choice.autoresizingMask=UIViewAutoresizingFlexibleWidth;choice.segmentedControlStyle=UISegmentedControlStyleBar;choice.selectedSegmentIndex=self.chartMetric;[choice addTarget:self action:@selector(chartChanged:) forControlEvents:UIControlEventValueChanged];[view addSubview:choice];}
    return view;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section==2?74:32; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[self.videoId.length?L(@"Video"):L(@"Your channel"),L(@"Selected period"),L(@"Daily report"),self.videoId.length?L(@"Comparison"):L(@"Top videos"),L(@"More reports"),L(@"Account")][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0)return self.videoId.length?self.videoTitle:(self.dashboard[@"accountError"] ?: (self.dashboard[@"channelError"]?L(@"Channel details are unavailable for this sign-in. Available analytics are shown below."):nil));
    if(section==1)return self.dashboard[@"summaryError"];
    if(section==2)return self.dashboard[@"dailyError"] ?: L(@"Tap a bar for that day's numbers. Subscribers shows gained minus lost. Recent reports can be delayed.");
    if(section==3)return self.videoId.length?self.dashboard[@"previousSummaryError"]:self.dashboard[@"topVideosError"];
    if(section==4)return L(@"Reports load when opened. YouTube may withhold small audiences or restrict individual reports.");
    if(section==5)return L(@"These reports use your existing sign-in. No additional server or Google Cloud setup is required.");
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return path.section==2 && [TBArr(self.dashboard[@"daily"]) count]?156:48; }
- (NSString *)number:(id)value { if(![value respondsToSelector:@selector(doubleValue)])return @"—";NSNumberFormatter *f=[[NSNumberFormatter alloc] init];f.numberStyle=NSNumberFormatterDecimalStyle;f.maximumFractionDigits=1;return [f stringFromNumber:@([value doubleValue])]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:path.section==3 && !self.videoId.length?UITableViewCellStyleSubtitle:UITableViewCellStyleValue1 reuseIdentifier:nil];[[TBTheme shared] styleCell:cell];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    NSDictionary *channel=TBDict(self.dashboard[@"channel"]),*statistics=TBDict(channel[@"statistics"]),*summary=TBDict([TBArr(self.dashboard[@"summary"]) firstObject]);
    if(path.section==0 && self.videoId.length){cell.textLabel.text=L(@"Watch video");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;}
    else if(path.section==0 && channel) {
        if(path.row==0){cell.textLabel.text=TBStr(TBDict(channel[@"snippet"])[@"title"]) ?: L(@"Your channel");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;}
        if(path.row==1){cell.textLabel.text=L(@"Subscribers");cell.detailTextLabel.text=[statistics[@"hiddenSubscriberCount"] boolValue]?L(@"Hidden"):[self number:statistics[@"subscriberCount"]];}
        if(path.row==2){cell.textLabel.text=L(@"Total views");cell.detailTextLabel.text=[self number:statistics[@"viewCount"]];}
        if(path.row==3){cell.textLabel.text=L(@"Videos");cell.detailTextLabel.text=[self number:statistics[@"videoCount"]];}
    } else if(path.section==1 && summary) {
        NSArray *names=@[L(@"Views"),L(@"Watch time"),L(@"Average view duration"),L(@"Average viewed"),L(@"Likes"),L(@"Comments"),L(@"Shares"),L(@"Subscribers gained / lost")];cell.textLabel.text=names[path.row];
        if(path.row==0)cell.detailTextLabel.text=[self number:summary[@"views"]];
        if(path.row==1)cell.detailTextLabel.text=[NSString stringWithFormat:L(@"%@ minutes"),[self number:summary[@"estimatedMinutesWatched"]]];
        if(path.row==2)cell.detailTextLabel.text=[TBUtils formatDuration:[summary[@"averageViewDuration"] doubleValue]];
        if(path.row==3)cell.detailTextLabel.text=[[self number:summary[@"averageViewPercentage"]] stringByAppendingString:@"%"];
        if(path.row==4)cell.detailTextLabel.text=[self number:summary[@"likes"]];
        if(path.row==5)cell.detailTextLabel.text=[self number:summary[@"comments"]];
        if(path.row==6)cell.detailTextLabel.text=[self number:summary[@"shares"]];
        if(path.row==7)cell.detailTextLabel.text=[NSString stringWithFormat:@"+%@ / −%@",[self number:summary[@"subscribersGained"]],[self number:summary[@"subscribersLost"]]];
    } else if(path.section==2 && [TBArr(self.dashboard[@"daily"]) count]) {
        TBStudioChart *chart=[[TBStudioChart alloc] initWithFrame:cell.contentView.bounds];chart.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;chart.rows=self.dashboard[@"daily"];chart.metric=self.chartMetric;__weak TBStudioViewController *owner=self;chart.selected=^(NSDictionary *row){[TBUtils alertWithTitle:TBStr(row[@"day"]) message:[NSString stringWithFormat:L(@"%@ views\n%@ minutes watched\nSubscribers: +%@ / −%@"),[owner number:row[@"views"]],[owner number:row[@"estimatedMinutesWatched"]],[owner number:row[@"subscribersGained"]],[owner number:row[@"subscribersLost"]]]];};[cell.contentView addSubview:chart];
    } else if(path.section==3 && self.videoId.length){cell.textLabel.text=L(@"Compare periods");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else if(path.section==3 && [TBArr(self.dashboard[@"topVideos"]) count]) {
        NSDictionary *video=self.dashboard[@"topVideos"][path.row];NSString *videoId=TBStr(video[@"video"]);
        cell.textLabel.text=TBStr(TBDict(self.dashboard[@"videoTitles"])[videoId]) ?: videoId ?: L(@"Video");
        cell.detailTextLabel.text=[NSString stringWithFormat:L(@"%@ views"),[self number:video[@"views"]]];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else if(path.section==4){cell.textLabel.text=path.row==0?L(@"Compare periods"):[self reportTitles][path.row-1];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else if(path.section==5) {
        cell.textLabel.text=L(@"Account settings");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else {
        cell.textLabel.text=self.loading?L(@"Loading…"):([[TBAccount shared] isSignedIn]?(path.section==0?L(@"Channel details unavailable"):L(@"No report data available.")):L(@"Sign in with Google"));
        if(![[TBAccount shared] isSignedIn]){cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;}
        cell.textLabel.textColor=[[TBTheme shared] secondaryTextColor];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(![[TBAccount shared] isSignedIn]){[self.navigationController pushViewController:[[TBGoogleLoginViewController alloc] init] animated:YES];return;}
    if(path.section==5){[self.navigationController pushViewController:[[TBSettingsViewController alloc] init] animated:YES];return;}
    if(path.section==0 && self.videoId.length){[TBNavigator openVideoId:self.videoId from:self];return;}
    if(path.section==0 && path.row==0 && self.dashboard[@"channel"]){NSString *channel=TBStr(self.dashboard[@"channel"][@"id"]);if(channel.length)[TBNavigator openChannelId:channel from:self];}
    if(path.section==3){if(self.videoId.length){[self openComparison];return;}if(path.row<[TBArr(self.dashboard[@"topVideos"]) count]){NSString *video=TBStr(self.dashboard[@"topVideos"][path.row][@"video"]);if(video.length)[self.navigationController pushViewController:[[TBStudioViewController alloc] initWithVideo:video title:TBStr(TBDict(self.dashboard[@"videoTitles"])[video]) days:self.days] animated:YES];}}
    if(path.section==4){if(path.row==0){[self openComparison];return;}[self.navigationController pushViewController:[[TBStudioReportViewController alloc] initWithDimension:[TBStudioReports dimensions][path.row-1] title:[self reportTitles][path.row-1] days:self.days video:self.videoId] animated:YES];}
}
@end
