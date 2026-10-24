#import <Foundation/Foundation.h>
#import "TBHTTP.h"

// Read-only owner reports. Tokens stay in TBAccount/Keychain and go only to Google's API endpoints.
@interface TBStudio : NSObject
+ (TBHTTPTask *)dashboardForDays:(NSInteger)days completion:(void (^)(NSDictionary *dashboard))completion;
+ (NSArray *)recordsFromReport:(id)report;
@end
