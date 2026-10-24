#import "TBModels.h"

@implementation TBDashFormat
@end

@implementation TBAudioRendition
@end

@implementation TBPlayerInfo

- (BOOL)isPlayable
{
    return [self.status isEqualToString:@"OK"] && (self.hlsManifestURL.length || self.progressiveURL.length || (self.dashVideo.count && self.dashAudio));
}

@end
