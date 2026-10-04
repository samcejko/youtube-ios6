#import <UIKit/UIKit.h>
#import "TBModels.h"

// Opening things from anywhere in the app: the watch page (full screen), the shorts player, channel and playlist
// pages (pushed, or presented over the watch page).
@interface TBNavigator : NSObject

+ (void)openVideo:(TBVideo *)video from:(UIViewController *)controller;
+ (void)openVideoId:(NSString *)videoId from:(UIViewController *)controller;
// Presents an already-built player screen (e.g. the watch screen that adopts the mini player's live session)
+ (void)presentPlayer:(UIViewController *)player from:(UIViewController *)controller;
+ (void)openShorts:(NSArray *)videos startingAt:(NSUInteger)index from:(UIViewController *)controller;
+ (void)openChannel:(TBChannel *)channel from:(UIViewController *)controller;
+ (void)openChannelId:(NSString *)channelId from:(UIViewController *)controller;
+ (void)openPlaylist:(TBPlaylist *)playlist from:(UIViewController *)controller;
+ (void)openPlaylistId:(NSString *)playlistId from:(UIViewController *)controller;
+ (void)openShelf:(TBShelf *)shelf from:(UIViewController *)controller;      // its items as a grid
+ (void)openItem:(id)item from:(UIViewController *)controller;               // a video, short, channel or playlist
+ (void)openSearch:(NSString *)query from:(UIViewController *)controller;

// youtube.com / youtu.be links; NO when the address means nothing to the app
+ (BOOL)openURL:(NSURL *)url from:(UIViewController *)controller;

// The controller to present modal screens from (the top of the current stack)
+ (UIViewController *)presenterFrom:(UIViewController *)controller;
+ (UINavigationController *)navigationControllerFrom:(UIViewController *)controller;
// Pushes onto the current stack; over a player (which has no stack) a new stack with a Done button is presented
+ (void)showPage:(UIViewController *)page from:(UIViewController *)controller;

@end
