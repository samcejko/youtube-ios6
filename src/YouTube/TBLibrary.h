#import <Foundation/Foundation.h>
#import "TBHTTP.h"
#import "TBModels.h"

// What the user keeps on the device: subscriptions, the watch history and the "watch later" list - plain property
// lists in Documents (no account is involved). Posts TBLibraryDidChangeNotification on every change (main thread).
@interface TBLibrary : NSObject

+ (instancetype)shared;

// Subscriptions (TBChannel, newest first)
- (NSArray *)subscriptions;
- (BOOL)isSubscribed:(NSString *)channelId;
- (void)subscribe:(TBChannel *)channel;
- (void)unsubscribe:(NSString *)channelId;

// The subscriptions feed: the latest videos of every subscribed channel (YouTube's RSS feeds), newest first.
// Cached for a few minutes; `force` asks again.
- (TBHTTPTask *)feedForce:(BOOL)force completion:(void (^)(NSArray *videos, NSError *error))completion;
- (NSArray *)cachedFeed;

// History (TBVideo with watchedAt and position, newest first; 500 kept)
- (NSArray *)history;
- (void)addToHistory:(TBVideo *)video;
// A video opened by its id alone gets its title and channel later: the entries in history and watch later follow
- (void)updateDetailsOf:(TBVideo *)video;
- (void)updatePosition:(NSTimeInterval)position forVideo:(NSString *)videoId;
- (void)removeFromHistory:(NSString *)videoId;
- (void)clearHistory;

// Watch later (TBVideo, newest first)
- (NSArray *)watchLater;
- (BOOL)isInWatchLater:(NSString *)videoId;
- (void)toggleWatchLater:(TBVideo *)video;
- (void)removeFromWatchLater:(NSString *)videoId;

@end

// One channel's RSS feed (15 latest videos)
@interface TBFeed : NSObject
+ (TBHTTPTask *)videosOfChannel:(NSString *)channelId completion:(void (^)(NSArray *videos, NSError *error))completion;
@end
