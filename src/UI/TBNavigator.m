#import "TBNavigator.h"
#import "TBWatchViewController.h"
#import "TBShortsViewController.h"
#import "TBChannelViewController.h"
#import "TBPlaylistViewController.h"
#import "TBGridViewController.h"
#import "TBRootViewController.h"
#import "TBInnertube.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

@implementation TBNavigator

+ (UIViewController *)presenterFrom:(UIViewController *)controller
{
    UIViewController *top = controller ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

+ (UINavigationController *)navigationControllerFrom:(UIViewController *)controller
{
    UIViewController *presenter = [self presenterFrom:controller];
    if ([presenter isKindOfClass:[UINavigationController class]]) return (UINavigationController *)presenter;
    if (presenter.navigationController) return presenter.navigationController;
    if ([presenter isKindOfClass:[UITabBarController class]]) {
        UIViewController *selected = [(UITabBarController *)presenter selectedViewController];
        if ([selected isKindOfClass:[UINavigationController class]]) return (UINavigationController *)selected;
    }
    return nil;
}

+ (BOOL)isPlayer:(UIViewController *)controller
{
    return [controller isKindOfClass:[TBWatchViewController class]] || [controller isKindOfClass:[TBShortsViewController class]];
}

+ (void)showPage:(UIViewController *)page from:(UIViewController *)controller
{
    UIViewController *presenter = [self presenterFrom:controller];
    if ([self isPlayer:presenter]) {
        // from a player: the page opens in its own stack over the video
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
        page.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissPresented:)];
        nav.modalPresentationStyle = TBIsPad() ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
        [[TBTheme shared] applyToNavigationBar:nav.navigationBar];
        [presenter presentViewController:nav animated:YES completion:nil];
        return;
    }
    UINavigationController *nav = [self navigationControllerFrom:controller];
    if (nav) [nav pushViewController:page animated:YES];
}

+ (void)dismissPresented:(id)sender
{
    UIViewController *top = [self presenterFrom:nil];
    [top.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Videos

+ (void)presentPlayer:(UIViewController *)player from:(UIViewController *)controller
{
    UIViewController *presenter = [self presenterFrom:controller];
    player.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [presenter presentViewController:player animated:YES completion:nil];
}

// A player on top of a player: the one underneath goes first (the pages presented over it with it)
+ (void)replacePlayerWith:(UIViewController *)player
{
    UIViewController *top = [self presenterFrom:nil];
    UIViewController *player0 = top;
    while (player0 && ![self isPlayer:player0]) player0 = player0.presentingViewController;
    UIViewController *under = player0.presentingViewController ?: top.presentingViewController;
    [under dismissViewControllerAnimated:NO completion:^{ [self presentPlayer:player from:under]; }];
}

+ (void)openVideo:(TBVideo *)video from:(UIViewController *)controller
{
    if (!video.videoId.length) return;
    UIViewController *presenter = [self presenterFrom:controller];
    if ([presenter isKindOfClass:[TBWatchViewController class]]) {
        [(TBWatchViewController *)presenter loadVideo:video];
        return;
    }
    TBWatchViewController *watch = [[TBWatchViewController alloc] initWithVideo:video];
    UIViewController *walker = presenter;
    while (walker && ![self isPlayer:walker]) walker = walker.presentingViewController;
    if (walker) { [self replacePlayerWith:watch]; return; }
    [self presentPlayer:watch from:controller];
}

+ (void)openVideoId:(NSString *)videoId from:(UIViewController *)controller
{
    if (!videoId.length) return;
    [self openVideo:[TBVideo videoWithId:videoId] from:controller];
}

+ (void)openShorts:(NSArray *)videos startingAt:(NSUInteger)index from:(UIViewController *)controller
{
    if (!videos.count) return;
    UIViewController *presenter = [self presenterFrom:controller];
    if ([presenter isKindOfClass:[TBShortsViewController class]]) {
        [(TBShortsViewController *)presenter showVideos:videos startingAt:index];
        return;
    }
    TBShortsViewController *shorts = [[TBShortsViewController alloc] initWithVideos:videos startingAt:index];
    UIViewController *walker = presenter;
    while (walker && ![self isPlayer:walker]) walker = walker.presentingViewController;
    if (walker) { [self replacePlayerWith:shorts]; return; }
    [self presentPlayer:shorts from:controller];
}

#pragma mark - Pages

+ (void)openChannel:(TBChannel *)channel from:(UIViewController *)controller
{
    if (!channel.channelId.length) return;
    [self showPage:[[TBChannelViewController alloc] initWithChannel:channel] from:controller];
}

+ (void)openChannelId:(NSString *)channelId from:(UIViewController *)controller
{
    if (!channelId.length) return;
    TBChannel *c = [[TBChannel alloc] init];
    c.channelId = channelId;
    [self openChannel:c from:controller];
}

+ (void)openPlaylist:(TBPlaylist *)playlist from:(UIViewController *)controller
{
    if (!playlist.playlistId.length) return;
    [self showPage:[[TBPlaylistViewController alloc] initWithPlaylist:playlist] from:controller];
}

+ (void)openPlaylistId:(NSString *)playlistId from:(UIViewController *)controller
{
    if (!playlistId.length) return;
    TBPlaylist *p = [[TBPlaylist alloc] init];
    p.playlistId = playlistId;
    [self openPlaylist:p from:controller];
}

+ (void)openShelf:(TBShelf *)shelf from:(UIViewController *)controller
{
    if (!shelf) return;
    TBGridViewController *grid;
    if (shelf.browseId.length) {
        NSString *browseId = shelf.browseId, *params = shelf.params;
        grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:^TBHTTPTask *(NSString *continuation, TBItemsCompletion completion) {
            return [TBInnertube browse:browseId params:params continuation:continuation completion:^(NSDictionary *response, NSArray *items, NSString *next, NSError *error) {
                completion(items, next, error);
            }];
        }];
    } else {
        grid = [[TBGridViewController alloc] initWithStyle:TBGridStyleVideos loader:nil];
        [grid replaceItems:shelf.items];
    }
    grid.title = shelf.title;
    [self showPage:grid from:controller];
}

+ (void)openItem:(id)item from:(UIViewController *)controller
{
    if ([item isKindOfClass:[TBVideo class]]) {
        TBVideo *v = item;
        if (v.isShort) [self openShorts:@[ v ] startingAt:0 from:controller];
        else [self openVideo:v from:controller];
    } else if ([item isKindOfClass:[TBChannel class]]) {
        [self openChannel:item from:controller];
    } else if ([item isKindOfClass:[TBPlaylist class]]) {
        [self openPlaylist:item from:controller];
    } else if ([item isKindOfClass:[TBShelf class]]) {
        [self openShelf:item from:controller];
    }
}

+ (void)openSearch:(NSString *)query from:(UIViewController *)controller
{
    TBRootViewController *root = (TBRootViewController *)[UIApplication sharedApplication].keyWindow.rootViewController;
    if ([root isKindOfClass:[TBRootViewController class]]) [root searchFor:query];
}

#pragma mark - URLs

+ (BOOL)openURL:(NSURL *)url from:(UIViewController *)controller
{
    NSString *host = [url.host lowercaseString] ?: @"";
    NSString *path = url.path ?: @"";
    NSDictionary *query = [TBUtils parseQuery:url.query ?: @""];
    if ([host isEqualToString:@"youtu.be"]) {
        NSString *videoId = [path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        if (videoId.length) { [self openVideoId:videoId from:controller]; return YES; }
        return NO;
    }
    if ([host rangeOfString:@"youtube.com"].location == NSNotFound && [host rangeOfString:@"youtube-nocookie.com"].location == NSNotFound) return NO;
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *p in [path componentsSeparatedByString:@"/"]) if (p.length) [parts addObject:p];
    NSString *first = parts.count ? [parts[0] lowercaseString] : @"";
    if ([first isEqualToString:@"watch"] && [query[@"v"] length]) { [self openVideoId:query[@"v"] from:controller]; return YES; }
    if (([first isEqualToString:@"shorts"] || [first isEqualToString:@"embed"] || [first isEqualToString:@"v"] || [first isEqualToString:@"live"]) && parts.count > 1) {
        if ([first isEqualToString:@"shorts"]) {
            TBVideo *v = [TBVideo videoWithId:parts[1]];
            v.isShort = YES;
            [self openShorts:@[ v ] startingAt:0 from:controller];
        } else {
            [self openVideoId:parts[1] from:controller];
        }
        return YES;
    }
    if ([first isEqualToString:@"playlist"] && [query[@"list"] length]) { [self openPlaylistId:query[@"list"] from:controller]; return YES; }
    if ([first isEqualToString:@"channel"] && parts.count > 1) { [self openChannelId:parts[1] from:controller]; return YES; }
    if ([first isEqualToString:@"results"] && [query[@"search_query"] length]) { [self openSearch:query[@"search_query"] from:controller]; return YES; }
    if ([first hasPrefix:@"@"] || [first isEqualToString:@"c"] || [first isEqualToString:@"user"]) {
        // handles and legacy names: YouTube resolves them
        [TBInnertube resolveURL:url.absoluteString completion:^(NSString *channelId, NSString *videoId, NSString *playlistId, NSError *error) {
            if (channelId.length) [self openChannelId:channelId from:controller];
            else if (videoId.length) [self openVideoId:videoId from:controller];
            else if (playlistId.length) [self openPlaylistId:playlistId from:controller];
            else if (error) [TBUtils alertWithTitle:L(@"Not found") message:error.localizedDescription];
        }];
        return YES;
    }
    return NO;
}

@end
