#import <AVFoundation/AVFoundation.h>
// One-shot device check. Called only by the opt-in local debug URL bridge.
@interface TBFrameProbe : NSObject
+ (void)capturePlayer:(AVPlayer *)player completion:(void (^)(NSDictionary *result))completion;
@end
