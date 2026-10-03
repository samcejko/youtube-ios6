#import <Foundation/Foundation.h>
#import "TBHTTP.h"
#import "TBModels.h"
#import "TBInnertube.h"

// Posted on the main thread when the account signs in or out, when its profile arrives and when its subscriptions
// were brought into the library
extern NSString * const TBAccountDidChangeNotification;

// The Google account, signed in the way a TV does: the app shows a code, the user types it at google.com/device on
// any other device, and Google hands the app OAuth tokens (kept in the keychain). With them the YouTube Data API
// serves the account's subscriptions, likes and playlists; the watch history and "watch later" are not in that API,
// so those stay on the device. The OAuth client is the author's; Google's device flow also asks for the client's
// secret, which the user enters in Settings (it lives in the keychain, never in the repository or the binary).
@interface TBAccount : NSObject

+ (instancetype)shared;
+ (BOOL)isConfigured;                                       // a client secret is set (built-in or entered)

@property (nonatomic, copy) NSString *clientId;             // the OAuth client id; the built-in default unless Settings set one
@property (nonatomic, copy) NSString *clientSecret;         // setting either posts the notification
- (BOOL)usesOwnClientId;                                    // a client id other than the built-in default was entered
- (BOOL)isSignedIn;
@property (nonatomic, readonly, copy) NSString *channelTitle;   // the account's channel (after fetchProfile)
@property (nonatomic, readonly, copy) NSString *channelId;
@property (nonatomic, readonly, copy) NSString *handle;         // "@name"
@property (nonatomic, readonly, copy) NSString *avatarURL;

// The device flow: `codeHandler` gets the code to show (main thread), then the app polls until the user confirmed,
// refused, or the code expired (completion on the main thread). Cancelling the task stops the polling.
- (TBHTTPTask *)signInWithCodeHandler:(void (^)(NSString *userCode, NSString *verificationURL))codeHandler
                           completion:(void (^)(NSError *error))completion;
- (void)signOut;

// YouTube Data API v3 (the token is refreshed when it ran out). Completions run on the main thread.
- (TBHTTPTask *)fetchProfile:(void (^)(NSError *error))completion;
// Every subscribed channel (TBChannel), newest first - and the library's subscriptions become these
- (TBHTTPTask *)syncSubscriptions:(void (^)(NSArray *channels, NSError *error))completion;
- (TBHTTPTask *)subscribeTo:(TBChannel *)channel completion:(void (^)(NSError *error))completion;
- (TBHTTPTask *)unsubscribeFrom:(NSString *)channelId completion:(void (^)(NSError *error))completion;
// "like", "dislike" or "none"
- (TBHTTPTask *)rateVideo:(NSString *)videoId rating:(NSString *)rating completion:(void (^)(NSError *error))completion;
- (TBHTTPTask *)ratingOfVideo:(NSString *)videoId completion:(void (^)(NSString *rating, NSError *error))completion;
// The liked videos (playlist "LL") and the account's own playlists, a page at a time
- (TBHTTPTask *)likedVideosPage:(NSString *)pageToken completion:(TBItemsCompletion)completion;
- (TBHTTPTask *)playlistsPage:(NSString *)pageToken completion:(TBItemsCompletion)completion;
- (TBHTTPTask *)addVideo:(NSString *)videoId toPlaylist:(NSString *)playlistId completion:(void (^)(NSError *error))completion;

@end
