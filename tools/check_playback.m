#import <Foundation/Foundation.h>
#import "TBResolver.h"
#import "TBRemux.h"
#import <math.h>
#import <float.h>

static NSData *Box(NSString *type,NSData *payload) {
    uint32_t length=CFSwapInt32HostToBig((uint32_t)payload.length+8);
    NSMutableData *result=[NSMutableData dataWithBytes:&length length:4];
    [result appendData:[type dataUsingEncoding:NSASCIIStringEncoding]];[result appendData:payload];return result;
}
int main(void) { @autoreleasepool {
    NSDictionary *video=@{@"itag":@134,@"url":@"https://media.example/video",@"codecs":@"avc1.4d401e",@"width":@640,@"height":@360,@"bitrate":@500000};
    NSDictionary *audio=@{@"itag":@140,@"url":@"https://media.example/audio",@"codecs":@"mp4a.40.2",@"bitrate":@128000,@"isDefaultAudio":@YES};
    // A bot-blocked/missing InnerTube response must not be needed to interpret independent resolver media.
    TBPlayerInfo *info=[TBResolver playerInfoFromResponse:@{@"id":@"jNQXAC9IVRw",@"duration":@240,@"adaptiveFormats":@[video,audio]} videoId:@"jNQXAC9IVRw"];
    NSCAssert((info.isPlayable && info.dashVideo.count==1 && info.dashAudio.itag==140),@"DASH-only source must be playable without HLS or progressive MP4");
    NSCAssert((info.dashAudio.indexEnd==0),@"Missing InnerTube byte ranges require bounded MP4 probing");
    NSCAssert((![TBResolver playerInfoFromResponse:@{@"id":@"wrong",@"playUrl":@"https://media.example/movie"} videoId:@"jNQXAC9IVRw"]),@"Response must belong to the requested video");
    NSCAssert((![TBResolver playerInfoFromResponse:@{@"adaptiveFormats":@[video]} videoId:@"jNQXAC9IVRw"]),@"Silent video cannot replace an audio/video source");
    NSCAssert((![TBResolver streamURL:@"file:///etc/passwd"] && ![TBResolver streamURL:@"https://user:password@media.example/movie"]),@"Reject nonmedia URLs and embedded credentials");
    NSDictionary *headers=[TBResolver mediaHeaders:@{@"Authorization":@"secret",@"Cookie":@"secret",@"User-Agent":@"media-client",@"Referer":@"bad\r\nheader"}];
    NSCAssert((headers.count==1 && [headers[@"User-Agent"] isEqualToString:@"media-client"]),@"Keep only safe media headers");
    NSMutableDictionary *huge=[video mutableCopy];huge[@"width"]=@(DBL_MAX);huge[@"bitrate"]=@(INFINITY);huge[@"indexEnd"]=@(DBL_MAX);
    info=[TBResolver playerInfoFromResponse:@{@"adaptiveFormats":@[huge,audio]} videoId:@"jNQXAC9IVRw"];
    NSCAssert((info.dashVideo.count==1 && ((TBDashFormat *)info.dashVideo[0]).indexEnd<=1048575),@"Malformed numeric metadata must not overflow or request an unlimited index");
    // Actual MP4 parser: a truncated version-1 sidx must fail before its 64-bit fields are read.
    NSMutableData *sidx=[NSMutableData dataWithLength:24];((uint8_t *)sidx.mutableBytes)[0]=1;
    NSString *error=nil;TBDashFormat *format=[[TBDashFormat alloc] init];format.isAudio=YES;
    NSCAssert((![TBDashIndex indexWithData:Box(@"sidx",sidx) format:format error:&error]),@"Truncated sidx must be rejected");
    for (NSUInteger length=0;length<64;length++) {
        NSMutableData *malformed=[NSMutableData dataWithLength:length];
        [TBDashIndex indexWithData:Box(@"sidx",malformed) format:format error:NULL];
    }
    NSLog(@"Playback resolver, DASH-only selection, header isolation and truncated-index checks passed");
} return 0; }
