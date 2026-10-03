#import "TBShortsTabViewController.h"
#import "TBInnertube.h"
#import "TBLibrary.h"
#import "TBTheme.h"
#import "TBCommon.h"

static NSString * const TBChannelShortsParams = @"EgZzaG9ydHPyBgUKA5oBAA%3D%3D";

@interface TBShortsTabViewController ()
@property (nonatomic, strong) UISegmentedControl *segments;
@end

@implementation TBShortsTabViewController

- (instancetype)init
{
    self = [super initWithStyle:TBGridStyleShorts loader:nil];
    if (self) {
        self.title = L(@"Shorts");
        self.emptyText = L(@"No shorts found.");
        [self useSource:0];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.segments = [[UISegmentedControl alloc] initWithItems:@[ L(@"Popular"), L(@"Subscriptions") ]];
    self.segments.segmentedControlStyle = UISegmentedControlStyleBar;
    self.segments.selectedSegmentIndex = 0;
    self.segments.frame = CGRectMake(0, 0, 220, 30);
    [self.segments addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.segments;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryChanged) name:TBLibraryDidChangeNotification object:nil];
}

- (void)segmentChanged
{
    [self useSource:self.segments.selectedSegmentIndex];
    [self reload];
}

- (void)libraryChanged
{
    if (self.segments.selectedSegmentIndex == 1) [self setLoader:self.loader andReload:self.isViewLoaded && self.view.window != nil];
}

- (void)useSource:(NSInteger)source
{
    if (source == 0) {
        // the search for "shorts" in the user's language returns shelves of them
        [self setLoader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            return [TBInnertube search:@"#shorts" filter:nil continuation:continuation completion:^(NSArray *items, NSString *next, NSError *error) {
                if (error) { completion(nil, nil, error); return; }
                NSMutableArray *shorts = [NSMutableArray array];
                for (id item in items) if ([item isKindOfClass:[TBVideo class]] && ([(TBVideo *)item isShort] || [(TBVideo *)item lengthSeconds] <= 60)) { [(TBVideo *)item setIsShort:YES]; [shorts addObject:item]; }
                completion(shorts, next, nil);
            }];
        } andReload:NO];
        self.emptyText = L(@"No shorts found.");
        return;
    }
    // the shorts of the subscribed channels (the first dozen of them), newest first per channel
    [self setLoader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
        NSArray *channels = [[TBLibrary shared] subscriptions];
        if (!channels.count || continuation.length) { TBMain(^{ completion(@[], nil, nil); }); return nil; }
        if (channels.count > 12) channels = [channels subarrayWithRange:NSMakeRange(0, 12)];
        TBHTTPTask *outer = [[TBHTTPTask alloc] init];
        NSMutableArray *tasks = [NSMutableArray array];
        outer.cancelBlock = ^{ for (TBHTTPTask *t in tasks) [t cancel]; };
        NSMutableArray *perChannel = [NSMutableArray array];
        for (NSUInteger i = 0; i < channels.count; i++) [perChannel addObject:@[]];
        __block NSUInteger pending = channels.count;
        for (NSUInteger i = 0; i < channels.count; i++) {
            TBChannel *c = channels[i];
            TBHTTPTask *t = [TBInnertube browse:c.channelId params:TBChannelShortsParams continuation:nil completion:^(NSDictionary *response, NSArray *items, NSString *next, NSError *error) {
                if (outer.isCancelled) return;
                NSMutableArray *shorts = [NSMutableArray array];
                for (id item in items) {
                    if (![item isKindOfClass:[TBVideo class]]) continue;
                    TBVideo *v = item;
                    v.isShort = YES;
                    if (!v.channelName.length) { v.channelName = c.title; v.channelId = c.channelId; }
                    [shorts addObject:v];
                    if (shorts.count >= 6) break;
                }
                perChannel[i] = shorts;
                if (--pending > 0) return;
                // interleaved: the newest of every channel first
                NSMutableArray *merged = [NSMutableArray array];
                for (NSUInteger round = 0; round < 6; round++) {
                    for (NSArray *list in perChannel) if (round < list.count) [merged addObject:list[round]];
                }
                completion(merged, nil, nil);
            }];
            if (t) [tasks addObject:t];
        }
        return outer;
    } andReload:NO];
    self.emptyText = [[TBLibrary shared] subscriptions].count ? L(@"The channels you follow have no shorts.") : L(@"Subscribe to channels and their shorts show up here.");
}

@end
