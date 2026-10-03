#import <Foundation/Foundation.h>

@class TBDashFormat;

// What the app shows: videos (also shorts and live streams), channels, playlists, comments - as YouTube's
// InnerTube API describes them, reduced to what the screens need.

@interface TBVideo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic, copy) NSString *channelName;
@property (nonatomic, copy) NSString *channelAvatarURL;
@property (nonatomic, copy) NSString *thumbnailURL;         // as the API gave it; -thumbnailURLForWidth: derives others
@property (nonatomic) NSTimeInterval lengthSeconds;         // 0 when unknown (live)
@property (nonatomic, copy) NSString *lengthText;           // "19:00"
@property (nonatomic) long long viewCount;                  // 0 when unknown
@property (nonatomic, copy) NSString *viewsText;            // "67K views", "1,234 watching"
@property (nonatomic, copy) NSString *publishedText;        // "1 day ago"
@property (nonatomic, strong) NSDate *publishedAt;          // exact (RSS feeds, history)
@property (nonatomic, copy) NSString *descriptionSnippet;
@property (nonatomic) BOOL isLive;
@property (nonatomic) BOOL isUpcoming;
@property (nonatomic) BOOL isShort;
// history / watch later
@property (nonatomic, strong) NSDate *watchedAt;
@property (nonatomic) NSTimeInterval position;
+ (instancetype)videoWithId:(NSString *)videoId;
- (NSString *)thumbnailURLForWidth:(NSInteger)width;        // i.ytimg.com: 320, 480, 640 or 1280 px wide
- (NSString *)metaText;                                     // "channel · views · age" for lists
- (NSDictionary *)dictionary;                               // for the library files
+ (instancetype)videoFromDictionary:(NSDictionary *)d;
@end

@interface TBChannelTab : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *params;
@property (nonatomic) BOOL selected;
@end

@interface TBChannel : NSObject
@property (nonatomic, copy) NSString *channelId;            // "UC..."
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *handle;               // "@name"
@property (nonatomic, copy) NSString *avatarURL;
@property (nonatomic, copy) NSString *bannerURL;
@property (nonatomic, copy) NSString *subscribersText;      // "519M subscribers"
@property (nonatomic, copy) NSString *videoCountText;       // "1K videos"
@property (nonatomic, copy) NSString *descriptionText;
@property (nonatomic, strong) NSArray *tabs;                // TBChannelTab (channel pages only)
@property (nonatomic, strong) NSDate *subscribedAt;
- (NSDictionary *)dictionary;
+ (instancetype)channelFromDictionary:(NSDictionary *)d;
@end

@interface TBPlaylist : NSObject
@property (nonatomic, copy) NSString *playlistId;           // "PL..." (without the "VL" browse prefix)
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, copy) NSString *videoCountText;       // "25 videos"
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *ownerId;
@property (nonatomic, copy) NSString *descriptionText;
@end

@interface TBComment : NSObject
@property (nonatomic, copy) NSString *commentId;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *authorChannelId;
@property (nonatomic, copy) NSString *authorAvatarURL;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *likesText;            // "1.2K"
@property (nonatomic, copy) NSString *publishedText;        // "3 days ago"
@property (nonatomic) NSInteger replyCount;
@property (nonatomic, copy) NSString *repliesToken;         // continuation that loads the replies
@property (nonatomic) BOOL isPinned;
@property (nonatomic) BOOL isHearted;
@property (nonatomic) BOOL isCreator;
@property (nonatomic) BOOL isReply;
@end

@interface TBCaptionTrack : NSObject
@property (nonatomic, copy) NSString *languageCode;         // "en", "cs"
@property (nonatomic, copy) NSString *name;                 // "English (auto-generated)"
@property (nonatomic, copy) NSString *url;                  // timedtext URL (format added when fetched)
@property (nonatomic) BOOL isAuto;
@end

// One rendition of an HLS master playlist
@interface TBVariant : NSObject
@property (nonatomic, copy) NSString *url;                  // the media playlist
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) double frameRate;
@property (nonatomic) NSInteger bandwidth;
@property (nonatomic, copy) NSString *codecs;
@property (nonatomic, copy) NSString *audioGroup;           // the AUDIO group the picture goes with (nil = sound inside)
@property (nonatomic, strong) TBDashFormat *dash;           // set when the rendition is remuxed from a DASH file
- (BOOL)isH264;
- (NSInteger)qualityLines;                                  // the "720" of 720p: the shorter side (upright shorts are 720x1280)
- (NSString *)title;                                        // "720p", "1080p60"
- (NSString *)qualityKey;                                   // "720"
@end

// One of YouTube's adaptive ("DASH") MP4 files: a single track in a fragmented MP4 with a sidx index, fetched by
// byte ranges. The media proxy turns its fragments into MPEG-TS (video) or packed AAC (audio) for the player.
@interface TBDashFormat : NSObject
@property (nonatomic) NSInteger itag;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *codecs;               // "avc1.64001F", "mp4a.40.2"
@property (nonatomic) BOOL isAudio;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) double frameRate;
@property (nonatomic) NSInteger bitrate;                    // bits per second
@property (nonatomic) long long initStart, initEnd;         // the init segment (ftyp + moov)
@property (nonatomic) long long indexStart, indexEnd;       // the sidx box
@property (nonatomic) long long contentLength;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) NSInteger audioSampleRate;
@property (nonatomic) NSInteger audioChannels;
@property (nonatomic) BOOL isDefaultAudio;                  // the original sound track (not an automatic dub)
@property (nonatomic, copy) NSString *audioTrackName;
@end

// An alternate audio rendition (#EXT-X-MEDIA:TYPE=AUDIO)
@interface TBAudioRendition : NSObject
@property (nonatomic, copy) NSString *groupId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, strong) TBDashFormat *dash;           // set when the rendition is remuxed from a DASH file
@end

// The player response of a video, reduced
@interface TBPlayerInfo : NSObject
@property (nonatomic, copy) NSString *videoId;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic) NSTimeInterval lengthSeconds;
@property (nonatomic) long long viewCount;
@property (nonatomic) BOOL isLive;
@property (nonatomic) BOOL isLiveContent;
@property (nonatomic, copy) NSString *status;               // playabilityStatus.status ("OK")
@property (nonatomic, copy) NSString *statusReason;
@property (nonatomic, copy) NSString *hlsManifestURL;
@property (nonatomic, copy) NSString *progressiveURL;       // the best MP4 with sound, 720p at most
@property (nonatomic) NSInteger progressiveHeight;
@property (nonatomic, strong) NSArray *dashVideo;           // TBDashFormat, H.264 only, highest first
@property (nonatomic, strong) TBDashFormat *dashAudio;      // the AAC-LC sound track to go with them
@property (nonatomic, strong) NSArray *captionTracks;       // TBCaptionTrack
@property (nonatomic, copy) NSString *shortDescription;
@property (nonatomic, copy) NSString *thumbnailURL;
@property (nonatomic, copy) NSString *publishDate;          // "2009-10-25"
@property (nonatomic, copy) NSString *category;
- (BOOL)isPlayable;
@end

// A row of items with a title (the explore page)
@interface TBShelf : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, copy) NSString *browseId;            // where "more" leads (optional)
@property (nonatomic, copy) NSString *params;
@end

// The watch page's information about a video (from the "next" response)
@interface TBWatchInfo : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *viewsText;            // "1,822,575,369 views"
@property (nonatomic, copy) NSString *dateText;             // "Oct 25, 2009"
@property (nonatomic, copy) NSString *likesText;            // "19M"
@property (nonatomic, strong) TBChannel *channel;           // id, title, avatar, subscribers
@property (nonatomic, copy) NSString *descriptionText;
@property (nonatomic, strong) NSArray *related;             // TBVideo / TBPlaylist
@property (nonatomic, copy) NSString *relatedContinuation;
@property (nonatomic, copy) NSString *commentsToken;
@property (nonatomic, copy) NSString *commentCountText;     // "1.2K"
@end

// Text helpers for InnerTube JSON (also used by the parsers of other classes)
NSString *TBText(id node);                                  // {"simpleText"}, {"runs":[{"text"}]}, {"content"} or a string
NSString *TBThumbnailURL(id node);                          // the largest of {"thumbnails":[{url,width}]} or {"sources":[...]}
long long TBNumberFromText(NSString *text);                 // "67,046 views" -> 67046, "1.2M" -> 1200000
NSString *TBAbsoluteURL(NSString *url);                     // "//yt3..." -> "https://yt3..."
NSString *TBImageURL(NSString *url);                        // a picture URL this system can decode (YouTube's WebP variants turned into JPEG ones)
