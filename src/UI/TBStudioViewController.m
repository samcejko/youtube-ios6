#import "TBStudioViewController.h"
#import "TBStudio.h"
#import "TBAccount.h"
#import "TBSettingsViewController.h"
#import "TBGoogleLoginViewController.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBNavigator.h"
#import "TBCommon.h"

@interface TBStudioChart : UIView
@property(nonatomic,copy) NSArray *rows;
@end
@implementation TBStudioChart
- (void)setRows:(NSArray *)rows { _rows=[rows copy];[self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    TBTheme *theme=[TBTheme shared];[[theme cardColor] setFill];UIRectFill(self.bounds);
    CGRect plot=CGRectMake(12,12,MAX(1,self.bounds.size.width-24),112);
    [[theme secondaryTextColor] setStroke];UIBezierPath *grid=[UIBezierPath bezierPath];
    for(int i=0;i<3;i++){CGFloat y=plot.origin.y+plot.size.height*i/2;[grid moveToPoint:CGPointMake(plot.origin.x,y)];[grid addLineToPoint:CGPointMake(CGRectGetMaxX(plot),y)];}
    grid.lineWidth=.25;[grid stroke];
    double maximum=1;for(NSDictionary *row in self.rows)maximum=MAX(maximum,[row[@"views"] doubleValue]);
    CGFloat step=plot.size.width/MAX((NSUInteger)1,self.rows.count);
    CGContextRef context=UIGraphicsGetCurrentContext();
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)@[(id)[UIColor colorWithRed:.95 green:.36 blue:.32 alpha:1].CGColor,(id)[UIColor colorWithRed:.58 green:.04 blue:.03 alpha:1].CGColor],NULL);
    for(NSUInteger i=0;i<self.rows.count;i++) {
        CGFloat height=plot.size.height*MAX(0,[self.rows[i][@"views"] doubleValue])/maximum;
        CGRect bar=CGRectMake(plot.origin.x+i*step+1,CGRectGetMaxY(plot)-height,MAX(1,step-2),height);
        CGContextSaveGState(context);CGContextClipToRect(context,bar);
        CGContextDrawLinearGradient(context,gradient,bar.origin,CGPointMake(bar.origin.x,CGRectGetMaxY(bar)),0);CGContextRestoreGState(context);
    }
    CGGradientRelease(gradient);CGColorSpaceRelease(space);
    [[theme secondaryTextColor] setFill];UIFont *font=[UIFont systemFontOfSize:11];
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
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL loading;
@end
@implementation TBStudioViewController
- (instancetype)init { self=[super initWithStyle:UITableViewStyleGrouped];if(self){self.title=L(@"Studio");self.days=28;}return self; }
- (void)dealloc { [_task cancel]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    UIView *header=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,58)];
    self.period=[[UISegmentedControl alloc] initWithItems:@[L(@"7 days"),L(@"28 days"),L(@"90 days")]];
    self.period.frame=CGRectMake(14,12,header.bounds.size.width-28,32);self.period.autoresizingMask=UIViewAutoresizingFlexibleWidth;
    self.period.selectedSegmentIndex=1;self.period.segmentedControlStyle=UISegmentedControlStyleBar;
    [self.period addTarget:self action:@selector(periodChanged) forControlEvents:UIControlEventValueChanged];[header addSubview:self.period];self.tableView.tableHeaderView=header;
    [self reload];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];TBTheme *theme=[TBTheme shared];[theme applyToTableView:self.tableView];[theme applyToNavigationBar:self.navigationController.navigationBar];
    if(!self.loading && !self.dashboard[@"channel"] && [[TBAccount shared] isSignedIn])[self reload];
}
- (void)periodChanged { self.days=self.period.selectedSegmentIndex==0?7:(self.period.selectedSegmentIndex==2?90:28);[self reload]; }
- (void)reload {
    [self.task cancel];NSUInteger generation=++self.generation;self.loading=YES;self.dashboard=nil;[self.tableView reloadData];
    __weak TBStudioViewController *weakSelf=self;
    self.task=[TBStudio dashboardForDays:self.days completion:^(NSDictionary *dashboard){TBStudioViewController *s=weakSelf;if(!s || s.generation!=generation)return;s.task=nil;s.loading=NO;s.dashboard=dashboard;[s.tableView reloadData];}];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return [[TBAccount shared] isSignedIn]?5:1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section==0)return self.dashboard[@"channel"]?4:1;
    if(section==1)return [TBArr(self.dashboard[@"summary"]) count]?6:1;
    if(section==2)return 1;
    if(section==3)return MAX((NSUInteger)1,[TBArr(self.dashboard[@"topVideos"]) count]);
    return 1;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *view=RetroSectionHeader([self tableView:tableView titleForHeaderInSection:section],tableView.bounds.size.width);
    if([TBTheme shared].isDark)for(UILabel *label in view.subviews){label.textColor=[[TBTheme shared] secondaryTextColor];label.shadowColor=[UIColor blackColor];}
    return view;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 32; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[(L(@"Your channel")),L(@"Selected period"),L(@"Daily views"),L(@"Top videos"),L(@"Account")][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if(section==0)return self.dashboard[@"channelError"] ?: self.dashboard[@"accountError"];
    if(section==1)return self.dashboard[@"summaryError"];
    if(section==2)return self.dashboard[@"dailyError"] ?: L(@"Reports can be delayed. Dates follow YouTube's reporting time zone.");
    if(section==3)return self.dashboard[@"topVideosError"];
    if(section==4)return L(@"Studio reads your channel and reports. Analytics requires access granted by your Google account and an enabled YouTube Analytics API.");
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { return path.section==2 && [TBArr(self.dashboard[@"daily"]) count]?156:48; }
- (NSString *)number:(id)value { if(![value respondsToSelector:@selector(doubleValue)])return @"—";NSNumberFormatter *f=[[NSNumberFormatter alloc] init];f.numberStyle=NSNumberFormatterDecimalStyle;f.maximumFractionDigits=0;return [f stringFromNumber:@([value doubleValue])]; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:path.section==3?UITableViewCellStyleSubtitle:UITableViewCellStyleValue1 reuseIdentifier:nil];[[TBTheme shared] styleCell:cell];
    cell.selectionStyle=UITableViewCellSelectionStyleNone;
    NSDictionary *channel=TBDict(self.dashboard[@"channel"]),*statistics=TBDict(channel[@"statistics"]),*summary=TBDict([TBArr(self.dashboard[@"summary"]) firstObject]);
    if(path.section==0 && channel) {
        if(path.row==0){cell.textLabel.text=TBStr(TBDict(channel[@"snippet"])[@"title"]) ?: L(@"Your channel");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;}
        if(path.row==1){cell.textLabel.text=L(@"Subscribers");cell.detailTextLabel.text=[statistics[@"hiddenSubscriberCount"] boolValue]?L(@"Hidden"):[self number:statistics[@"subscriberCount"]];}
        if(path.row==2){cell.textLabel.text=L(@"Total views");cell.detailTextLabel.text=[self number:statistics[@"viewCount"]];}
        if(path.row==3){cell.textLabel.text=L(@"Videos");cell.detailTextLabel.text=[self number:statistics[@"videoCount"]];}
    } else if(path.section==1 && summary) {
        NSArray *names=@[L(@"Views"),L(@"Watch time"),L(@"Average view duration"),L(@"Likes"),L(@"Comments"),L(@"Subscribers gained / lost")];cell.textLabel.text=names[path.row];
        if(path.row==0)cell.detailTextLabel.text=[self number:summary[@"views"]];
        if(path.row==1)cell.detailTextLabel.text=[NSString stringWithFormat:L(@"%@ minutes"),[self number:summary[@"estimatedMinutesWatched"]]];
        if(path.row==2)cell.detailTextLabel.text=[TBUtils formatDuration:[summary[@"averageViewDuration"] doubleValue]];
        if(path.row==3)cell.detailTextLabel.text=[self number:summary[@"likes"]];
        if(path.row==4)cell.detailTextLabel.text=[self number:summary[@"comments"]];
        if(path.row==5)cell.detailTextLabel.text=[NSString stringWithFormat:@"+%@ / −%@",[self number:summary[@"subscribersGained"]],[self number:summary[@"subscribersLost"]]];
    } else if(path.section==2 && [TBArr(self.dashboard[@"daily"]) count]) {
        TBStudioChart *chart=[[TBStudioChart alloc] initWithFrame:cell.contentView.bounds];chart.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;chart.rows=self.dashboard[@"daily"];[cell.contentView addSubview:chart];
    } else if(path.section==3 && [TBArr(self.dashboard[@"topVideos"]) count]) {
        NSDictionary *video=self.dashboard[@"topVideos"][path.row];NSString *videoId=TBStr(video[@"video"]);
        cell.textLabel.text=TBStr(TBDict(self.dashboard[@"videoTitles"])[videoId]) ?: videoId ?: L(@"Video");
        cell.detailTextLabel.text=[NSString stringWithFormat:L(@"%@ views"),[self number:video[@"views"]]];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else if(path.section==4) {
        cell.textLabel.text=L(@"Account settings");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;
    } else {
        cell.textLabel.text=self.loading?L(@"Loading…"):([[TBAccount shared] isSignedIn]?L(@"No report data available."):L(@"Sign in with Google"));
        if(![[TBAccount shared] isSignedIn]){cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.selectionStyle=UITableViewCellSelectionStyleBlue;}
        cell.textLabel.textColor=[[TBTheme shared] secondaryTextColor];
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(![[TBAccount shared] isSignedIn]){[self.navigationController pushViewController:[[TBGoogleLoginViewController alloc] init] animated:YES];return;}
    if(path.section==4){[self.navigationController pushViewController:[[TBSettingsViewController alloc] init] animated:YES];return;}
    if(path.section==0 && path.row==0 && self.dashboard[@"channel"]){NSString *channel=TBStr(self.dashboard[@"channel"][@"id"]);if(channel.length)[TBNavigator openChannelId:channel from:self];}
    if(path.section==3 && path.row<[TBArr(self.dashboard[@"topVideos"]) count]){NSString *video=TBStr(self.dashboard[@"topVideos"][path.row][@"video"]);if(video.length)[TBNavigator openVideoId:video from:self];}
}
@end
