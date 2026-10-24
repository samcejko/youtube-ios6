#import "PSTCollectionView.h"
#import "TBAppDelegate.h"
#import "TBRootViewController.h"
#import "TBWatchViewController.h"
#import "TBShortsViewController.h"
#import "TBPlayback.h"
#import "TBNavigator.h"
#import "TBTLSSocket.h"
#import "TBMediaProxy.h"
#import "TBImageLoader.h"
#import "TBSettings.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBModern.h"
#import "TBCommon.h"
#import "TBInnertube.h"
#import "MusicHandoff.h"
#import "TBAccount.h"
#import "TBStudio.h"
#import "TBStudioReports.h"
#import "TBStudioViewController.h"
#import "TBFrameProbe.h"
#import <AVFoundation/AVFoundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <mach/mach.h>

// A button "named" text: by its title or by its accessibility label (icon buttons have no title), case does not matter
static BOOL TBButtonMatches(UIButton *button, NSString *text)
{
    for (NSString *name in @[ button.currentTitle ?: @"", button.accessibilityLabel ?: @"" ]) {
        if (name.length && [name rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// Is the text in a label of this view? (Controls' own labels excepted: a segment title is not its table row's text.)
static BOOL TBViewContainsText(UIView *view, NSString *text)
{
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *s = ((UILabel *)view).text;
        return s.length && [s rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound;
    }
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:[UIControl class]]) continue;
        if (TBViewContainsText(sub, text)) return YES;
    }
    return NO;
}

// Acts on a view "named" text the way a finger would: a button is pressed, a segment selected, the switch of a table
// row flipped, a table or grid row selected. YES when this view was the one.
static BOOL TBPressView(UIView *v, NSString *text)
{
    if ([v isKindOfClass:[UIButton class]]) {
        if (!TBButtonMatches((UIButton *)v, text)) return NO;
        [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
        return YES;
    }
    if ([v isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *segments = (UISegmentedControl *)v;
        for (NSUInteger i = 0; i < segments.numberOfSegments; i++) {
            NSString *title = [segments titleForSegmentAtIndex:i];
            if (title.length && [title rangeOfString:text options:NSCaseInsensitiveSearch].location != NSNotFound) {
                segments.selectedSegmentIndex = (NSInteger)i;
                [segments sendActionsForControlEvents:UIControlEventValueChanged];
                return YES;
            }
        }
        return NO;
    }
    if ([v isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)v;
        if (!TBViewContainsText(cell, text)) return NO;
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
            UISwitch *sw = (UISwitch *)cell.accessoryView;
            [sw setOn:!sw.on animated:NO];
            [sw sendActionsForControlEvents:UIControlEventValueChanged];
            return YES;
        }
        UIView *table = cell.superview;
        while (table && ![table isKindOfClass:[UITableView class]]) table = table.superview;
        NSIndexPath *ip = [(UITableView *)table indexPathForCell:cell];
        id<UITableViewDelegate> delegate = [(UITableView *)table delegate];
        if (!ip || ![delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) return NO;
        [delegate tableView:(UITableView *)table didSelectRowAtIndexPath:ip];
        return YES;
    }
    if ([v isKindOfClass:[PSUICollectionViewCell class]]) {
        PSUICollectionViewCell *cell = (PSUICollectionViewCell *)v;
        if (!TBViewContainsText(cell, text)) return NO;
        UIView *grid = cell.superview;
        while (grid && ![grid isKindOfClass:[PSUICollectionView class]]) grid = grid.superview;
        NSIndexPath *ip = [(PSUICollectionView *)grid indexPathForCell:cell];
        id<PSUICollectionViewDelegate> delegate = [(PSUICollectionView *)grid delegate];
        if (!ip || ![delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) return NO;
        [delegate collectionView:(PSUICollectionView *)grid didSelectItemAtIndexPath:ip];
        return YES;
    }
    return NO;
}

@implementation TBAppDelegate

static NSUInteger TBHandoffGeneration;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // (a peer that went away must not kill the process while a socket is written to)
    signal(SIGPIPE, SIG_IGN);
    [TBSettings registerDefaults];
    TBLog(@"Tubie %@ starting on %@ (iOS %@)", [TBUtils appVersion], [TBUtils deviceModel], [UIDevice currentDevice].systemVersion);
    // iOS 7 and newer (the arm64 build): the iOS 6 look of the bars, full-screen modals; nothing on iOS 6
    TBModernSetUp([[TBTheme shared] barStyle]);
    [TBTLSSocket warmUp];
    [[TBImageLoader shared] pruneDisk];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.rootViewController = [[TBRootViewController alloc] init];
    self.window.rootViewController = self.rootViewController;
    self.window.backgroundColor = [[TBTheme shared] backgroundColor];
    [self.window makeKeyAndVisible];
    [application setStatusBarStyle:[[TBTheme shared] statusBarStyle] animated:NO];
    return YES;
}

// tubie:watch/<id>, tubie:short/<id>, tubie:channel/<id or @handle>, tubie:playlist/<id>, tubie:search?q=<text> and
// tubie:open?url=<youtube link> open content. Over SSH (uiopen) a few commands help checking the app: snapshot and
// screen write tmp/screen.png, press?n=1 presses a button of the alert on screen, press?title=X a button, segment,
// switch row or list row with that text, tab?n=1 switches the tab, back pops the navigation stack, seek?t=120 moves
// the open video, link?url=<percent-encoded address> does what a tap on that link in a description would and stats
// logs the memory in use. The commands need a file named "debug" in the app's Documents.
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    TBHandoffGeneration++;
    NSString *s = url.absoluteString ?: @"";
    if ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]) return [TBNavigator openURL:url from:self.rootViewController];
    if (![s hasPrefix:@"tubie:"]) return NO;
    NSString *target = [s substringFromIndex:@"tubie:".length];
    while ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
    NSString *query = nil;
    NSRange q = [target rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        query = [target substringFromIndex:q.location + 1];
        target = [target substringToIndex:q.location];
    }
    NSDictionary *params = query.length ? [TBUtils parseQuery:query] : @{};
    if (([target isEqualToString:@"play"] || ([target isEqualToString:@"search"] && [params[@"autoplay"] isEqualToString:@"1"])) && [params[@"title"] length]) {
        NSUInteger generation = TBHandoffGeneration;
        NSString *videoId = MHYouTubeID(params[@"url"]);
        if (videoId.length) {
            [TBNavigator openVideoId:videoId from:self.rootViewController];
            return YES;
        }
        NSString *title = params[@"title"], *artist = params[@"artist"] ?: @"";
        NSString *query = [NSString stringWithFormat:@"%@ %@ audio", title, artist];
        double duration = MHDuration(params[@"duration"]);
        // Show useful results immediately while checking for a confident playable match.
        [self.rootViewController searchFor:query];
        UIViewController *searchTab = self.rootViewController.selectedViewController;
        [TBInnertube search:query filter:TBSearchFilterVideos continuation:nil completion:^(NSArray *items, NSString *continuation, NSError *error) {
            if (generation != TBHandoffGeneration || self.rootViewController.selectedViewController != searchTab || self.rootViewController.presentedViewController) return;
            TBVideo *best = nil;
            double bestDifference = HUGE_VAL;
            for (id item in items) {
                if (![item isKindOfClass:[TBVideo class]]) continue;
                TBVideo *video = item;
                if (!video.videoId.length || video.isLive || video.isUpcoming) continue;
                if (!MHMatches(title, artist, duration, video.title, video.channelName, video.lengthSeconds, YES)) continue;
                double difference = duration > 0 ? fabs(duration - video.lengthSeconds) : 0;
                if (!best || difference < bestDifference) { best = video; bestDifference = difference; }
            }
            if (best) [TBNavigator openVideo:best from:self.rootViewController];
            // An uncertain match leaves the results visible for the user's choice.
        }];
        return YES;
    }
    if ([target hasPrefix:@"watch/"]) {
        [TBNavigator openVideoId:[target substringFromIndex:@"watch/".length] from:self.rootViewController];
        return YES;
    }
    if ([target hasPrefix:@"short/"]) {
        TBVideo *v = [TBVideo videoWithId:[target substringFromIndex:@"short/".length]];
        v.isShort = YES;
        [TBNavigator openShorts:@[ v ] startingAt:0 from:self.rootViewController];
        return YES;
    }
    if ([target hasPrefix:@"channel/"]) {
        NSString *who = [[target substringFromIndex:@"channel/".length] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if ([who hasPrefix:@"@"]) [TBNavigator openURL:[NSURL URLWithString:[@"https://www.youtube.com/" stringByAppendingString:who]] from:self.rootViewController];
        else [TBNavigator openChannelId:who from:self.rootViewController];
        return YES;
    }
    if ([target hasPrefix:@"playlist/"]) {
        [TBNavigator openPlaylistId:[target substringFromIndex:@"playlist/".length] from:self.rootViewController];
        return YES;
    }
    if ([target isEqualToString:@"search"] && [params[@"q"] length]) {
        [self.rootViewController searchFor:params[@"q"]];
        return YES;
    }
    if ([target isEqualToString:@"open"] && [params[@"url"] length]) {
        return [TBNavigator openURL:[NSURL URLWithString:params[@"url"]] from:self.rootViewController];
    }
    if ([target isEqualToString:@"studio"]) {
        if(self.rootViewController.presentedViewController)[self.rootViewController dismissViewControllerAnimated:NO completion:nil];
        [self.rootViewController selectTab:4];
        UIViewController *selected=self.rootViewController.selectedViewController;
        if([selected isKindOfClass:[UINavigationController class]]) { UINavigationController *nav=(UINavigationController *)selected;[nav popToRootViewControllerAnimated:NO];[nav pushViewController:[[TBStudioViewController alloc] init] animated:NO]; }
        return YES;
    }
    BOOL debug = [[NSFileManager defaultManager] fileExistsAtPath:[[TBUtils documentsPath] stringByAppendingPathComponent:@"debug"]];
    if (!debug) return YES;
    if ([target isEqualToString:@"rotate"]) {
        BOOL landscape=![params[@"landscape"] isEqualToString:@"0"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
        if([UIDevice currentDevice].systemVersion.integerValue>=16) {
            UIWindowScene *scene=self.window.windowScene;
            UIWindowSceneGeometryPreferencesIOS *preferences=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:landscape?UIInterfaceOrientationMaskLandscapeRight:UIInterfaceOrientationMaskPortrait];
            [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error){TBLog(@"Device rotation check: %@",error.localizedDescription);}];
        } else
#endif
        { @try { [[UIDevice currentDevice] setValue:@(landscape?UIInterfaceOrientationLandscapeRight:UIInterfaceOrientationPortrait) forKey:@"orientation"];[UIViewController attemptRotationToDeviceOrientation]; } @catch(NSException *exception){TBLog(@"Device rotation check: %@",exception.reason);} }
#pragma clang diagnostic pop
        return YES;
    }
    if ([target isEqualToString:@"studioprobe"]) {
        NSString *file=[NSTemporaryDirectory() stringByAppendingPathComponent:@"studio-probe.json"];
        [@"{\"running\":true}" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        void (^save)(NSDictionary *)=^(NSDictionary *result){[[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] writeToFile:file atomically:YES];};
        NSInteger days=[params[@"days"] integerValue];if(days!=7 && days!=90)days=28;
        NSString *dimension=params[@"dimension"],*video=params[@"video"];
        if([dimension isEqualToString:@"all"]){NSMutableDictionary *all=[NSMutableDictionary dictionary];__block NSUInteger pending=[TBStudioReports dimensions].count;for(NSString *name in [TBStudioReports dimensions])[TBStudio reportForDimension:name days:days video:video completion:^(NSDictionary *result){all[name]=result;if(--pending==0)save(all);}];}
        else if(dimension.length)[TBStudio reportForDimension:dimension days:days video:video completion:save];
        else [TBStudio dashboardForDays:days video:video completion:save];return YES;
    }
    if ([target isEqualToString:@"frame"]) {
        UIViewController *top=[TBNavigator presenterFrom:nil];
        if ([top isKindOfClass:[TBWatchViewController class]] || [top isKindOfClass:[TBShortsViewController class]]) [TBFrameProbe capturePlayer:[top valueForKey:@"player"] completion:^(NSDictionary *result) {
            [[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"frame-probe.json"] atomically:YES];
        }];return YES;
    }
    if ([target isEqualToString:@"diagnostics"]) {
        UIViewController *top=[TBNavigator presenterFrom:nil];
        NSMutableDictionary *result=[@{@"screen":NSStringFromClass([top class]),@"signedIn":@([[TBAccount shared] isSignedIn]),@"customClient":@([[TBAccount shared] usesCustomOAuthClient]),@"idleDisabled":@([UIApplication sharedApplication].idleTimerDisabled),@"keepScreenOn":@([TBSettings keepScreenOn])} mutableCopy];
        result[@"appVersion"]=[TBUtils appVersion];
        result[@"collectionBackend"]=NSStringFromClass(class_getSuperclass([PSUICollectionView class]));
        result[@"collectionCellBackend"]=NSStringFromClass(class_getSuperclass([PSUICollectionViewCell class]));
        NSMutableArray *views=[NSMutableArray arrayWithArray:top.view.subviews],*labels=[NSMutableArray array];
        for (NSUInteger i=0;i<views.count;i++) { UIView *v=views[i];[views addObjectsFromArray:v.subviews];if(!v.hidden && [v isKindOfClass:[UILabel class]] && ((UILabel *)v).text.length)[labels addObject:((UILabel *)v).text]; }
        result[@"labels"]=labels;
        result[@"landscape"]=@(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation));
        if ([top isKindOfClass:[TBWatchViewController class]] || [top isKindOfClass:[TBShortsViewController class]]) {
            BOOL watch=[top isKindOfClass:[TBWatchViewController class]];
            AVPlayer *player=[top valueForKey:@"player"];AVPlayerItem *item=player.currentItem;
            double position=CMTimeGetSeconds(player.currentTime);
            result[@"rate"]=@(player.rate);result[@"position"]=@(isfinite(position)?position:0);result[@"itemStatus"]=@(item.status);
            if(watch){result[@"playerDescription"]=[(TBWatchViewController *)top playbackDebugDescription] ?: @"";TBPlaybackSource *source=[top valueForKey:@"source"];result[@"remuxed"]=@(source.isRemuxed);}
            UIView *playerView=[top valueForKey:watch?@"playerView":@"videoView"];
            AVPlayerLayer *layer=watch?[playerView valueForKey:@"playerLayer"]:(AVPlayerLayer *)playerView.layer;
            result[@"layerAttached"]=@(player && layer.player==player);result[@"readyForDisplay"]=@(layer.readyForDisplay);
        }
        [[NSJSONSerialization dataWithJSONObject:result options:0 error:NULL] writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tubie-diagnostics.json"] atomically:YES];return YES;
    }
    if ([target isEqualToString:@"proxylog"]) {
        // every request the player makes to the media proxy goes to the log (proxylog?on=0 stops it)
        [TBMediaProxy shared].logRequests = ![params[@"on"] isEqualToString:@"0"];
        TBLog(@"Proxy request log %@", [TBMediaProxy shared].logRequests ? @"on" : @"off");
        return YES;
    }
    if ([target isEqualToString:@"resolver"]) {
        // point the app at a yt-dlp resolver on your computer (resolver?url=http://192.168.1.50:8740); empty url turns it off
        NSString *url = params[@"url"];
        if (url != nil) { [TBSettings setResolverBase:url]; [TBSettings save]; }
        NSString *base = [TBSettings resolverBase];
        TBLog(@"Resolver base: %@", base.length ? base : @"(off)");
        return YES;
    }
    if ([target isEqualToString:@"stats"]) {
        struct task_basic_info info;
        mach_msg_type_number_t count = TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
            TBLog(@"Memory: %.1f MB resident, %.1f MB virtual", info.resident_size / 1048576.0, info.virtual_size / 1048576.0);
        }
        UIViewController *top = [TBNavigator presenterFrom:nil];
        TBLog(@"Windows: %lu, top controller: %@, proxy generation %ld, dark theme %d", (unsigned long)[UIApplication sharedApplication].windows.count,
              NSStringFromClass([top class]), (long)[TBMediaProxy shared].generation, [TBTheme shared].isDark);
        TBLog(@"Proxy served: %@", [[TBMediaProxy shared] statsDescription]);
        if ([top isKindOfClass:[TBWatchViewController class]]) TBLog(@"Player: %@", [(TBWatchViewController *)top playbackDebugDescription]);
        return YES;
    }
    if ([target isEqualToString:@"snapshot"]) {
        // every visible window drawn into one picture (alerts and sheets have windows of their own)
        CGSize size = [UIScreen mainScreen].bounds.size;
        UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.hidden || w.alpha <= 0) continue;
            CGContextSaveGState(ctx);
            CGContextTranslateCTM(ctx, w.frame.origin.x, w.frame.origin.y);
            [w.layer renderInContext:ctx];
            CGContextRestoreGState(ctx);
        }
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = [UIImagePNGRepresentation(image) writeToFile:path atomically:YES];
        TBLog(@"Snapshot %@: %@", ok ? @"written to" : @"failed for", path);
        return YES;
    }
    if ([target isEqualToString:@"screen"]) {
        // what the screen really shows, video included (the system's own screen grab, resolved at run time)
        CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
        CGImageRef shot = grab ? grab() : NULL;
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"screen.png"];
        BOOL ok = NO;
        if (shot) {
            ok = [UIImagePNGRepresentation([UIImage imageWithCGImage:shot]) writeToFile:path atomically:YES];
            CGImageRelease(shot);
        }
        TBLog(@"Screen grab %@: %@", ok ? @"written to" : @"failed for", path);
        return YES;
    }
    if ([target isEqualToString:@"press"]) {
        NSString *byTitle = params[@"title"];
        NSInteger n = [params[@"n"] integerValue];
        NSMutableArray *views = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) [views addObject:w];
        BOOL pressed = NO;
        for (NSUInteger i = 0; i < views.count && !pressed; i++) {
            UIView *v = views[i];
            BOOL classicButton=NO;
            if(!byTitle.length && [v isKindOfClass:[UIButton class]] && v.tag==n)for(UIView *ancestor=v.superview;ancestor;ancestor=ancestor.superview)if([ancestor.accessibilityIdentifier isEqualToString:@"TubieClassicPopup"]){classicButton=YES;break;}
            if(classicButton){[(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];pressed=YES;}
            else if (!byTitle.length && [v isKindOfClass:[UIAlertView class]] && ((UIAlertView *)v).visible) {
                UIAlertView *alert = (UIAlertView *)v;
                if ([alert.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [alert.delegate alertView:alert clickedButtonAtIndex:n];
                [alert dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (!byTitle.length && [v isKindOfClass:[UIActionSheet class]] && ((UIActionSheet *)v).visible) {
                UIActionSheet *sheet = (UIActionSheet *)v;
                if ([sheet.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [sheet.delegate actionSheet:sheet clickedButtonAtIndex:n];
                [sheet dismissWithClickedButtonIndex:n animated:NO];
                pressed = YES;
            } else if (byTitle.length && !v.hidden && TBPressView(v, byTitle)) {
                pressed = YES;
            } else {
                [views addObjectsFromArray:v.subviews];
            }
        }
        TBLog(@"Press %@: %@", query ?: @"", pressed ? @"done" : @"nothing found");
        return YES;
    }
    if ([target isEqualToString:@"tab"]) {
        [self.rootViewController selectTab:[params[@"n"] integerValue]];
        return YES;
    }
    if ([target isEqualToString:@"scroll"]) {
        // scroll?y=400 (or y=end) moves the largest scroll view on screen, so that rows further down can be pressed
        UIScrollView *largest = nil;
        NSMutableArray *views = [NSMutableArray array];
        for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.hidden) [views addObject:w];
        for (NSUInteger i = 0; i < views.count; i++) {
            UIView *v = views[i];
            if ([v isKindOfClass:[UIScrollView class]] && !v.hidden && v.window) {
                CGFloat area = v.bounds.size.width * v.bounds.size.height;
                if (!largest || area > largest.bounds.size.width * largest.bounds.size.height) largest = (UIScrollView *)v;
            }
            [views addObjectsFromArray:v.subviews];
        }
        if (largest) {
            CGFloat maxY = MAX(0, largest.contentSize.height + largest.contentInset.bottom - largest.bounds.size.height);
            BOOL pull = [params[@"pull"] isEqualToString:@"1"];
            CGFloat y = pull ? -largest.contentInset.top - 75 : ([params[@"y"] isEqualToString:@"end"] ? maxY : MIN(maxY, MAX(-largest.contentInset.top, [params[@"y"] doubleValue])));
            [largest setContentOffset:CGPointMake(largest.contentOffset.x, y) animated:NO];
            if (pull && [largest.delegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)]) [largest.delegate scrollViewDidEndDragging:largest willDecelerate:NO];
        }
        TBLog(@"Scroll: %@", largest ? NSStringFromClass([largest class]) : @"no scroll view");
        return YES;
    }
    if ([target isEqualToString:@"back"]) {
        UIViewController *top = [TBNavigator presenterFrom:nil];
        if ([top isKindOfClass:[UITabBarController class]]) top = [(UITabBarController *)top selectedViewController];
        UINavigationController *nav = [top isKindOfClass:[UINavigationController class]] ? (UINavigationController *)top : top.navigationController;
        TBLog(@"Back: %@", [nav popViewControllerAnimated:YES] ? @"popped" : @"nothing to pop");
        return YES;
    }
    if ([target isEqualToString:@"seek"]) {
        UIViewController *top = [TBNavigator presenterFrom:nil];
        if ([top isKindOfClass:[TBWatchViewController class]]) [(TBWatchViewController *)top seekToSeconds:[params[@"t"] doubleValue]];
        TBLog(@"Seek: %@", [top isKindOfClass:[TBWatchViewController class]] ? @"done" : @"no player open");
        return YES;
    }
    // speed?r=1.5: what picking a speed in the menu does; hold?on=1 / hold?on=0: a finger held on the picture (2x)
    if ([target isEqualToString:@"speed"] || [target isEqualToString:@"hold"]) {
        UIViewController *top = [TBNavigator presenterFrom:nil];
        if (![top isKindOfClass:[TBWatchViewController class]]) { TBLog(@"%@: no player open", target); return YES; }
        TBWatchViewController *watch = (TBWatchViewController *)top;
        if ([target isEqualToString:@"speed"]) [watch choosePlaybackRate:[params[@"r"] floatValue]];
        else [watch debugHoldFastForward:![params[@"on"] isEqualToString:@"0"]];
        return YES;
    }
    if ([target isEqualToString:@"link"]) {
        // link?url=https%3A%2F%2Fexample.com%2F: exactly the path a tapped link in a description or comment takes
        // (YouTube's addresses open inside, the rest goes to the chooser or Safari) from the screen on top
        UIViewController *top = [TBNavigator presenterFrom:nil];
        NSURL *link = [params[@"url"] length] ? [NSURL URLWithString:params[@"url"]] : nil;
        if (link) [TBNavigator openLink:link from:top anchor:nil];
        TBLog(@"Link %@: %@", params[@"url"] ?: @"(none)", link ? NSStringFromClass([top class]) : @"not a valid address");
        return YES;
    }
    return YES;
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[TBMediaProxy shared] ensureRunning];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [TBSettings save];
}

@end
