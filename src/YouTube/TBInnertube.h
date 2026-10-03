#import <Foundation/Foundation.h>
#import "TBHTTP.h"
#import "TBModels.h"

// Which of YouTube's own clients a request pretends to be. Browsing uses the web client (rich, readable JSON);
// playback uses the phone clients: they get stream URLs that need no deciphering (see TBPlayback).
typedef NS_ENUM(NSInteger, TBClient) {
    TBClientWeb = 0,
    TBClientIOS,
    TBClientAndroid,
};

// A page of items (TBVideo, TBChannel, TBPlaylist, TBShelf) and the token of the next page (nil = the last one)
typedef void (^TBItemsCompletion)(NSArray *items, NSString *continuation, NSError *error);

// Search filters (the "sp" parameter)
extern NSString * const TBSearchFilterVideos;
extern NSString * const TBSearchFilterChannels;
extern NSString * const TBSearchFilterPlaylists;
extern NSString * const TBSearchFilterLive;

// Topic pages that work without an account (the "explore" tab)
extern NSString * const TBBrowseMusic;
extern NSString * const TBBrowseGaming;
extern NSString * const TBBrowseNews;
extern NSString * const TBBrowseSports;
extern NSString * const TBBrowseLive;

// YouTube's InnerTube API (youtubei/v1), as an anonymous visitor. Completion blocks run on the main thread;
// a cancelled task never calls back.
@interface TBInnertube : NSObject

+ (TBHTTPTask *)call:(NSString *)endpoint body:(NSDictionary *)body client:(TBClient)client
          completion:(void (^)(NSDictionary *response, NSError *error))completion;

// Search: videos, channels, playlists and shorts shelves; `filter` is one of the constants above or nil
+ (TBHTTPTask *)search:(NSString *)query filter:(NSString *)filter continuation:(NSString *)continuation completion:(TBItemsCompletion)completion;
+ (TBHTTPTask *)searchSuggestions:(NSString *)query completion:(void (^)(NSArray *suggestions, NSError *error))completion;

// Browsing. `browseId` is a channel ("UC..."), a playlist ("VLPL...") or a page ("FE..."); `params` picks a tab.
+ (TBHTTPTask *)browse:(NSString *)browseId params:(NSString *)params continuation:(NSString *)continuation
            completion:(void (^)(NSDictionary *response, NSArray *items, NSString *continuation, NSError *error))completion;
// A channel page: the channel (with its tabs) and the items of the selected tab (the home tab unless params say otherwise)
+ (TBHTTPTask *)channel:(NSString *)channelId params:(NSString *)params
             completion:(void (^)(TBChannel *channel, NSArray *items, NSString *continuation, NSError *error))completion;
// A playlist: its details and the first videos
+ (TBHTTPTask *)playlist:(NSString *)playlistId
              completion:(void (^)(TBPlaylist *playlist, NSArray *items, NSString *continuation, NSError *error))completion;
// The shelves of a topic page (Music, Gaming...), each with its first items
+ (TBHTTPTask *)shelvesOfPage:(NSString *)browseId completion:(void (^)(NSArray *shelves, NSError *error))completion;
// A channel id for a handle or a URL (youtube.com/@name, /c/name, /user/name)
+ (TBHTTPTask *)resolveURL:(NSString *)url completion:(void (^)(NSString *channelId, NSString *videoId, NSString *playlistId, NSError *error))completion;

// The watch page: details, related videos, the comments token
+ (TBHTTPTask *)watchInfo:(NSString *)videoId completion:(void (^)(TBWatchInfo *info, NSError *error))completion;
// Comments (and replies) by continuation token
+ (TBHTTPTask *)comments:(NSString *)token completion:(void (^)(NSArray *comments, NSString *continuation, NSString *countText, NSError *error))completion;

// The player response: playability, stream URLs, captions
+ (TBHTTPTask *)player:(NSString *)videoId client:(TBClient)client completion:(void (^)(TBPlayerInfo *info, NSError *error))completion;

// The User-Agent header the given client sends (media requests send the same one)
+ (NSString *)userAgentForClient:(TBClient)client;

// Items out of any piece of InnerTube JSON (renderers and view models the app understands); continuation tokens found on the way
+ (NSArray *)itemsInNode:(id)node continuation:(NSString **)continuation;

@end
