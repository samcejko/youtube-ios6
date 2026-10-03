#import "TBRootViewController.h"
#import "TBHomeViewController.h"
#import "TBSubscriptionsViewController.h"
#import "TBShortsTabViewController.h"
#import "TBSearchViewController.h"
#import "TBLibraryViewController.h"
#import "TBTheme.h"
#import "TBCommon.h"

@interface TBRootViewController () <UITabBarControllerDelegate>
@property (nonatomic, strong) UINavigationController *homeNav;
@property (nonatomic, strong) UINavigationController *subscriptionsNav;
@property (nonatomic, strong) UINavigationController *shortsNav;
@property (nonatomic, strong) UINavigationController *searchNav;
@property (nonatomic, strong) UINavigationController *libraryNav;
@end

@implementation TBRootViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        TBTheme *t = [TBTheme shared];
        TBHomeViewController *home = [[TBHomeViewController alloc] init];
        home.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Home") image:[t tabIconHome] tag:0];
        _homeNav = [[UINavigationController alloc] initWithRootViewController:home];

        TBSubscriptionsViewController *subscriptions = [[TBSubscriptionsViewController alloc] init];
        subscriptions.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Subscriptions") image:[t tabIconSubscriptions] tag:1];
        _subscriptionsNav = [[UINavigationController alloc] initWithRootViewController:subscriptions];

        TBShortsTabViewController *shorts = [[TBShortsTabViewController alloc] init];
        shorts.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Shorts") image:[t tabIconShorts] tag:2];
        _shortsNav = [[UINavigationController alloc] initWithRootViewController:shorts];

        TBSearchViewController *search = [[TBSearchViewController alloc] init];
        search.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Search") image:[t tabIconSearch] tag:3];
        _searchNav = [[UINavigationController alloc] initWithRootViewController:search];

        TBLibraryViewController *library = [[TBLibraryViewController alloc] init];
        library.tabBarItem = [[UITabBarItem alloc] initWithTitle:L(@"Library") image:[t tabIconLibrary] tag:4];
        _libraryNav = [[UINavigationController alloc] initWithRootViewController:library];

        self.viewControllers = @[ _homeNav, _subscriptionsNav, _shortsNav, _searchNav, _libraryNav ];
        NSInteger last = [[NSUserDefaults standardUserDefaults] integerForKey:@"lastTab"];
        self.selectedIndex = (NSUInteger)((last >= 0 && last <= 4) ? last : 0);
        self.delegate = self;
        [self applyTheme];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TBThemeDidChangeNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    for (UINavigationController *nav in self.viewControllers) [t applyToNavigationBar:nav.navigationBar];
    [t applyToTabBar:self.tabBar];
    [[UIApplication sharedApplication] setStatusBarStyle:[t statusBarStyle] animated:NO];
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)self.selectedIndex forKey:@"lastTab"];
}

- (void)selectTab:(NSInteger)index
{
    if (index >= 0 && index < (NSInteger)self.viewControllers.count) self.selectedViewController = self.viewControllers[(NSUInteger)index];
}

- (void)searchFor:(NSString *)query
{
    [self.presentedViewController dismissViewControllerAnimated:NO completion:nil];
    self.selectedViewController = self.searchNav;
    [self.searchNav popToRootViewControllerAnimated:NO];
    TBSearchViewController *search = (TBSearchViewController *)self.searchNav.viewControllers[0];
    [search searchFor:query];
}

#pragma mark - Rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return TBIsPad() ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
