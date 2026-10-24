#import <Foundation/Foundation.h>
#import "TBModels.h"

// The resolver's response is independent of an InnerTube player response. Only supported media is accepted.
@interface TBResolver : NSObject
+ (TBPlayerInfo *)playerInfoFromResponse:(NSDictionary *)response videoId:(NSString *)videoId;
+ (NSDictionary *)mediaHeaders:(id)value;
+ (NSString *)streamURL:(id)value;
@end
