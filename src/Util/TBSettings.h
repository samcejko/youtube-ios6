#import <Foundation/Foundation.h>

// Quality preference values (also what the quality menu of the player stores)
extern NSString * const TBQualityAuto;      // the player switches between what the device can decode
// ...and "1080", "720", "480", "360", "240", "144": the highest rendition that is not above this height

// User preferences, kept in NSUserDefaults. Setters post TBSettingsDidChangeNotification.
@interface TBSettings : NSObject

+ (void)registerDefaults;
+ (void)save;

// Appearance
+ (BOOL)darkTheme;
+ (void)setDarkTheme:(BOOL)value;

// Playback
+ (NSString *)preferredQuality;
+ (void)setPreferredQuality:(NSString *)value;
+ (BOOL)backgroundAudio;            // keep the sound playing when the app goes to the background
+ (void)setBackgroundAudio:(BOOL)value;
+ (BOOL)keepScreenOn;               // no auto-lock while a video plays
+ (void)setKeepScreenOn:(BOOL)value;
+ (BOOL)autoplayNext;               // the first related video follows when one ends
+ (void)setAutoplayNext:(BOOL)value;
+ (BOOL)progressiveOnly;            // 360p MP4 instead of HLS (a way out should HLS fail on a device)
+ (void)setProgressiveOnly:(BOOL)value;

// SponsorBlock
+ (BOOL)sponsorBlock;
+ (void)setSponsorBlock:(BOOL)value;
+ (NSArray *)sponsorBlockCategories;    // the categories skipped (empty when SponsorBlock is off)
+ (void)setSponsorBlockCategories:(NSArray *)value;

// Captions
+ (BOOL)captionsEnabled;
+ (void)setCaptionsEnabled:(BOOL)value;
+ (NSString *)captionsLanguage;     // "" = the device's language
+ (void)setCaptionsLanguage:(NSString *)value;

// Content
+ (NSString *)contentLanguage;      // "hl": "cs", "en"...
+ (void)setContentLanguage:(NSString *)value;
+ (NSString *)contentRegion;        // "gl": "CZ", "US"...
+ (void)setContentRegion:(NSString *)value;
+ (BOOL)keepHistory;
+ (void)setKeepHistory:(BOOL)value;
+ (BOOL)showDislikes;               // Return YouTube Dislike
+ (void)setShowDislikes:(BOOL)value;

// Network
+ (BOOL)verifyTLS;
+ (void)setVerifyTLS:(BOOL)value;

// YouTube resolver (yt-dlp) that hands the app fresh, fully playable streams for videos that would otherwise be stuck
// at 360p. Defaults to the author's Pi (https://ytdlp.samcejko.eu/yt); "" turns it off. Base URL only; the app appends
// "/resolve". The request carries only the video id - no account, nothing personal.
+ (NSString *)resolverBase;
+ (void)setResolverBase:(NSString *)value;

// Resume positions of videos: seconds by video id (the last 300 are kept)
+ (NSTimeInterval)resumePositionForVideo:(NSString *)videoId;
+ (void)setResumePosition:(NSTimeInterval)seconds forVideo:(NSString *)videoId;

// Search history (most recent first, 15 kept)
+ (NSArray *)recentSearches;
+ (void)addRecentSearch:(NSString *)query;
+ (void)clearRecentSearches;

@end
