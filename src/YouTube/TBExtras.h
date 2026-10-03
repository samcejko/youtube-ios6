#import <Foundation/Foundation.h>
#import "TBHTTP.h"
#import "TBModels.h"

// SponsorBlock: the community's list of parts worth skipping (sponsor.ajay.app)
@interface TBSponsorSegment : NSObject
@property (nonatomic) NSTimeInterval start;
@property (nonatomic) NSTimeInterval end;
@property (nonatomic, copy) NSString *category;   // sponsor, selfpromo, interaction, intro, outro, preview, music_offtopic, filler
- (NSString *)title;                              // for the "skipped" note
@end

@interface TBSponsorBlock : NSObject
+ (NSArray *)allCategories;                       // the category keys the settings offer
+ (NSString *)titleForCategory:(NSString *)category;
// The segments of the categories the user chose (empty when none, or when the video has none)
+ (TBHTTPTask *)segmentsForVideo:(NSString *)videoId completion:(void (^)(NSArray *segments, NSError *error))completion;
@end

// Return YouTube Dislike (returnyoutubedislikeapi.com): likes, dislikes and views as the community counts them
@interface TBVotes : NSObject
@property (nonatomic) long long likes;
@property (nonatomic) long long dislikes;
@property (nonatomic) long long viewCount;
@end

@interface TBReturnDislike : NSObject
+ (TBHTTPTask *)votesForVideo:(NSString *)videoId completion:(void (^)(TBVotes *votes, NSError *error))completion;
@end

// Captions: a track fetched as WebVTT and parsed into cues
@interface TBCaptionCue : NSObject
@property (nonatomic) NSTimeInterval start;
@property (nonatomic) NSTimeInterval end;
@property (nonatomic, copy) NSString *text;
@end

@interface TBCaptions : NSObject
// The track to show by default for the settings (nil = none): the chosen language, else the device's, else nothing
+ (TBCaptionTrack *)preferredTrackIn:(NSArray *)tracks;
+ (TBHTTPTask *)loadTrack:(TBCaptionTrack *)track completion:(void (^)(NSArray *cues, NSError *error))completion;
// The cue at a moment (nil = none), cues sorted by start
+ (TBCaptionCue *)cueAtTime:(NSTimeInterval)time inCues:(NSArray *)cues;
@end
