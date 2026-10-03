#import <Foundation/Foundation.h>
#import "TBHTTP.h"
#import "TBModels.h"

// Everything the player needs for one video: how YouTube serves it and what this device can decode.
// Videos: the iOS client's HLS (H.264 up to 1080p in MPEG-TS, the sound as a separate AAC rendition);
// live streams: the Android client's HLS (sound inside); shorts and anything without HLS: a progressive MP4.
@interface TBPlaybackSource : NSObject
@property (nonatomic, strong) TBPlayerInfo *info;
@property (nonatomic, strong) NSArray *variants;            // TBVariant, H.264 only, the device's limits applied, highest first
@property (nonatomic, strong) NSArray *audioRenditions;     // TBAudioRendition (empty when the sound is inside the pictures)
@property (nonatomic, copy) NSString *progressiveURL;       // fallback / shorts
@property (nonatomic) NSInteger progressiveHeight;
@property (nonatomic) BOOL isLive;
- (BOOL)hasHLS;
- (BOOL)isRemuxed;                                          // the renditions are adaptive MP4 files converted by the proxy
@end

@interface TBPlayback : NSObject

// The source of a video (two or three requests in one cancellable task)
+ (TBHTTPTask *)sourceForVideo:(NSString *)videoId preferProgressive:(BOOL)preferProgressive completion:(void (^)(TBPlaybackSource *source, NSError *error))completion;

// A URL for AVPlayer through the media proxy. quality: TBQualityAuto or a height ("720"); `chosen` receives the
// rendition when one was picked (nil = the player switches by itself), `title` what the quality button shows.
+ (NSURL *)playerURLForSource:(TBPlaybackSource *)source quality:(NSString *)quality chosen:(TBVariant **)chosen title:(NSString **)title;

// Device limits: the iPad 2 / iPhone 4S decode 1080p30 (and 720p60); the iPhone 4 and older 720p30
+ (BOOL)deviceCanPlay:(TBVariant *)variant;
+ (NSArray *)variantsFromMaster:(NSString *)text baseURL:(NSURL *)base audioRenditions:(NSArray **)renditions;

@end
