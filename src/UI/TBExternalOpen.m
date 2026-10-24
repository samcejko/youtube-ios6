#import "TBExternalOpen.h"
#import "TBNavigator.h"
#import "TBUtils.h"
#import "TBModern.h"
#import "TBCommon.h"

// What the buttons of a sheet do, in their order
static NSString * const TBActionCopy    = @"copy";
static NSString * const TBActionSister  = @"sister";
static NSString * const TBActionSafari  = @"safari";
static NSString * const TBActionSurfari = @"surfari";

// A sister app of this family: the sites it shows, its URL scheme(s) and its name on the button
@interface TBSisterApp : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, strong) NSArray *hosts;       // domains (also every subdomain of them)
@property (nonatomic, strong) NSArray *schemes;     // the first one that answers canOpenURL: is used
@property (nonatomic, copy) NSString *scheme;       // the one installed (set when found)
@end

@implementation TBSisterApp
@end

@interface TBExternalOpen () <UIActionSheetDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSArray *actions;     // TBAction* per button index
@property (nonatomic, strong) TBSisterApp *sister;
@end

// The live sheets' delegates, so ARC does not free them while the sheet is on screen
static NSMutableArray *g_live;

static NSInteger TBMajorIOSVersion(void)
{
    static NSInteger major = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        major = [[[[UIDevice currentDevice] systemVersion] componentsSeparatedByString:@"."][0] integerValue];
        if (major < 1) major = 6;
    });
    return major;
}

@implementation TBExternalOpen

#pragma mark - The browsers and the sister apps

+ (BOOL)surfariAvailable
{
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"surfari://open?url=https://youtube.com/"]];
}

+ (NSURL *)surfariURLForURL:(NSURL *)url
{
    NSString *encoded = [TBUtils urlEncode:url.absoluteString ?: @""];
    return [NSURL URLWithString:[@"surfari://open?url=" stringByAppendingString:encoded]];
}

+ (NSArray *)sisterApps
{
    static NSArray *apps = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        TBSisterApp *twitcher = [[TBSisterApp alloc] init];
        twitcher.name = @"Twitcher";
        twitcher.buttonTitle = L(@"Open in Twitcher");
        twitcher.hosts = @[ @"twitch.tv" ];
        twitcher.schemes = @[ @"twitcher" ];
        TBSisterApp *kicker = [[TBSisterApp alloc] init];
        kicker.name = @"Kicker";
        kicker.buttonTitle = L(@"Open in Kicker");
        kicker.hosts = @[ @"kick.com" ];
        kicker.schemes = @[ @"kicker" ];
        TBSisterApp *tiktak = [[TBSisterApp alloc] init];
        tiktak.name = @"TikTak";
        tiktak.buttonTitle = L(@"Open in TikTak");
        tiktak.hosts = @[ @"tiktok.com" ];                 // (vm.tiktok.com and vt.tiktok.com are subdomains)
        tiktak.schemes = @[ @"tiktak", @"tikie" ];         // (the app's older scheme as a fallback)
        apps = @[ twitcher, kicker, tiktak ];
    });
    return apps;
}

// The installed sister app for this address, or nil
+ (TBSisterApp *)installedSisterAppForURL:(NSURL *)url
{
    NSString *host = [url.host lowercaseString];
    if (!host.length) return nil;
    for (TBSisterApp *app in [self sisterApps]) {
        BOOL matches = NO;
        for (NSString *domain in app.hosts) {
            if ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]) { matches = YES; break; }
        }
        if (!matches) continue;
        for (NSString *scheme in app.schemes) {
            NSURL *probe = [NSURL URLWithString:[scheme stringByAppendingString:@":open?url=https%3A%2F%2Fexample.com%2F"]];
            if (probe && [[UIApplication sharedApplication] canOpenURL:probe]) {
                TBSisterApp *found = [[TBSisterApp alloc] init];
                found.name = app.name;
                found.buttonTitle = app.buttonTitle;
                found.hosts = app.hosts;
                found.schemes = app.schemes;
                found.scheme = scheme;
                return found;
            }
        }
        return nil;
    }
    return nil;
}

+ (NSString *)sisterAppNameForURL:(NSURL *)url
{
    return [self installedSisterAppForURL:url].name;
}

+ (NSURL *)sisterURL:(TBSisterApp *)app forURL:(NSURL *)url
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:open?url=%@", app.scheme, [TBUtils urlEncode:url.absoluteString ?: @""]]];
}

+ (BOOL)isWebURL:(NSURL *)url
{
    NSString *scheme = [url.scheme lowercaseString];
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

#pragma mark - Opening

+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (![self isWebURL:url]) return;
    TBSisterApp *sister = [self installedSisterAppForURL:url];
    if (TBModernIOS() && !sister) {
        // iOS 7 and newer: Safari, no questions asked
        [[UIApplication sharedApplication] openURL:url];
        return;
    }
    [self presentSheetForURL:url copy:NO sister:sister from:controller anchor:anchor];
}

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (![self isWebURL:url]) return;
    if ([self presentSystemShareSheetForURL:url from:controller anchor:anchor]) return;
    [self presentSheetForURL:url copy:YES sister:[self installedSisterAppForURL:url] from:controller anchor:anchor];
}

// iOS 7 and newer: the system's share sheet (a popover from the anchor on the iPad, iOS 8+). NO on iOS 6 (and on
// an iPad with iOS 7, which has no popover presentation controller yet): the app's own sheet then.
+ (BOOL)presentSystemShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!TBModernIOS() || !controller) return NO;
    if (TBIsPad() && TBMajorIOSVersion() < 8) return NO;
    UIViewController *presenter = [TBNavigator presenterFrom:controller];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
    if (TBIsPad() && TBMajorIOSVersion() >= 8) {
        activity.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController *popover = activity.popoverPresentationController;
        UIView *source = anchor ?: presenter.view;
        popover.sourceView = source;
        if (anchor) {
            popover.sourceRect = anchor.bounds;
        } else {
            CGRect b = source.bounds;
            popover.sourceRect = CGRectMake(floor(CGRectGetMidX(b)), floor(CGRectGetMidY(b)), 1, 1);
            popover.permittedArrowDirections = 0;
        }
    }
#pragma clang diagnostic pop
#endif
    [presenter presentViewController:activity animated:YES completion:nil];
    return YES;
}

+ (void)presentSheetForURL:(NSURL *)url copy:(BOOL)copy sister:(TBSisterApp *)sister from:(UIViewController *)controller anchor:(UIView *)anchor
{
    TBExternalOpen *open = [[TBExternalOpen alloc] init];
    open.url = url;
    open.sister = sister;
    if (!g_live) g_live = [NSMutableArray array];
    [g_live addObject:open];

    NSMutableArray *actions = [NSMutableArray array];
    UIActionSheet *sheet = [[RetroActionSheet alloc] initWithTitle:url.absoluteString delegate:open cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (copy) { [sheet addButtonWithTitle:L(@"Copy link")]; [actions addObject:TBActionCopy]; }
    if (sister) { [sheet addButtonWithTitle:sister.buttonTitle]; [actions addObject:TBActionSister]; }
    [sheet addButtonWithTitle:L(@"Open in Safari")];
    [actions addObject:TBActionSafari];
    if (!TBModernIOS() && [self surfariAvailable]) { [sheet addButtonWithTitle:L(@"Open in Surfari")]; [actions addObject:TBActionSurfari]; }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    open.actions = actions;
    UIView *host = [TBNavigator presenterFrom:controller].view ?: [UIApplication sharedApplication].keyWindow;
    if (TBIsPad() && anchor && anchor.window) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:host];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.cancelButtonIndex && buttonIndex >= 0 && buttonIndex < (NSInteger)self.actions.count) {
        NSString *action = self.actions[(NSUInteger)buttonIndex];
        UIApplication *app = [UIApplication sharedApplication];
        if ([action isEqualToString:TBActionCopy]) [UIPasteboard generalPasteboard].string = self.url.absoluteString;
        else if ([action isEqualToString:TBActionSister]) [app openURL:[TBExternalOpen sisterURL:self.sister forURL:self.url]];
        else if ([action isEqualToString:TBActionSafari]) [app openURL:self.url];
        else if ([action isEqualToString:TBActionSurfari]) [app openURL:[TBExternalOpen surfariURLForURL:self.url]];
    }
    [g_live removeObject:self];
}

@end
