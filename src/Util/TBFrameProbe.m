#import "TBFrameProbe.h"
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>
#import <math.h>
@interface TBFrameProbe ()
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *item;
@property(nonatomic,strong) AVPlayerItemVideoOutput *output;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) void (^completion)(NSDictionary *);
@property(nonatomic) NSInteger attempts;
@end
@implementation TBFrameProbe
+ (void)capturePlayer:(AVPlayer *)player completion:(void (^)(NSDictionary *))completion {
    if (!player.currentItem) { completion(@{@"frameAvailable":@NO});return; }
    TBFrameProbe *probe=[[self alloc] init];probe.player=player;probe.item=player.currentItem;probe.completion=completion;
    probe.output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    [probe.item addOutput:probe.output];
    probe.timer=[NSTimer scheduledTimerWithTimeInterval:.1 target:probe selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)tick:(NSTimer *)timer {
    CMTime presented=kCMTimeInvalid;
    CVPixelBufferRef buffer=[self.output copyPixelBufferForItemTime:self.player.currentTime itemTimeForDisplay:&presented];
    if (!buffer && ++self.attempts<20 && self.player.currentItem==self.item) return;
    TBFrameProbe *keepAlive=self;
    [self.timer invalidate];self.timer=nil;[self.item removeOutput:self.output];
    NSMutableDictionary *result=[@{@"frameAvailable":@(buffer!=NULL)} mutableCopy];
    if (buffer) {
        CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
        size_t width=CVPixelBufferGetWidth(buffer),height=CVPixelBufferGetHeight(buffer);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGContextRef context=CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer),width,height,8,CVPixelBufferGetBytesPerRow(buffer),space,kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst);
        CGImageRef image=context ? CGBitmapContextCreateImage(context) : NULL;
        BOOL saved=image && [UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"video-frame.png"] atomically:YES];
        result[@"saved"]=@(saved);result[@"width"]=@(width);result[@"height"]=@(height);
        double seconds=CMTimeGetSeconds(presented);result[@"frameTime"]=@(isfinite(seconds)?seconds:0);
        if(image)CGImageRelease(image);if(context)CGContextRelease(context);CGColorSpaceRelease(space);
        CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);CVPixelBufferRelease(buffer);
    }
    if(keepAlive.completion)keepAlive.completion(result);keepAlive.completion=nil;
}
@end
