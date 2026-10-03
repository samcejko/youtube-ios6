#import <Foundation/Foundation.h>
#import "TBModels.h"

// YouTube keeps every video as adaptive MP4 files - one track per file, fragmented, with a "sidx" index - which a 2012
// player cannot use: it knows MPEG-TS over HLS. These routines read such a file's index and turn its fragments into
// what the player eats: the pictures as MPEG-TS packets (H.264 Annex B in PES), the sound as packed AAC (ADTS frames
// behind an ID3 timestamp tag), the very format YouTube's own HLS sound renditions use.

// One fragment of the file (a moof + mdat pair)
@interface TBDashFragment : NSObject
@property (nonatomic) long long offset;             // in the file
@property (nonatomic) long long size;
@property (nonatomic) long long startTime;          // in the track's timescale
@property (nonatomic) long long duration;
@end

// The parsed init segment and sidx index of a TBDashFormat
@interface TBDashIndex : NSObject
@property (nonatomic, strong) TBDashFormat *format;
@property (nonatomic) uint32_t timescale;
@property (nonatomic) long long editOffset;         // elst media_time: composition time of presentation time 0
@property (nonatomic) uint32_t defaultSampleDuration, defaultSampleSize, defaultSampleFlags;   // trex
@property (nonatomic, strong) NSArray *fragments;   // TBDashFragment
// video
@property (nonatomic, strong) NSData *sps;
@property (nonatomic, strong) NSData *pps;
@property (nonatomic) NSInteger nalLengthSize;
// audio
@property (nonatomic) NSInteger audioObjectType;    // 2 = AAC-LC
@property (nonatomic) NSInteger audioFrequencyIndex;
@property (nonatomic) NSInteger audioChannelConfig;

// Parses the bytes 0...indexEnd of the file (ftyp, moov, sidx); nil when they are not what was expected
+ (instancetype)indexWithData:(NSData *)data format:(TBDashFormat *)format error:(NSString **)error;

// An HLS media playlist listing the fragments as segments named "<n>.ts" / "<n>.aac"
- (NSString *)mediaPlaylist;
- (NSTimeInterval)durationOfFragment:(NSUInteger)index;

// One fragment, converted. Timestamps come out as the track's own time (plus a second of lead so nothing is negative).
- (NSData *)transportStreamForFragment:(NSUInteger)index data:(NSData *)fragment error:(NSString **)error;
- (NSData *)packedAudioForFragment:(NSUInteger)index data:(NSData *)fragment error:(NSString **)error;

@end
