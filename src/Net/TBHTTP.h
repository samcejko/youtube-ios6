#import <Foundation/Foundation.h>

typedef void (^TBHTTPCompletion)(NSInteger status, NSData *body, NSDictionary *headers, NSError *error);
typedef void (^TBJSONCompletion)(id json, NSInteger status, NSError *error);

// A running request of TBHTTP. After -cancel the completion block is never called.
@interface TBHTTPTask : NSObject
@property (atomic, readonly) BOOL isCancelled;
@property (atomic, copy) dispatch_block_t cancelBlock;   // for chained requests: called by -cancel (once)
- (void)cancel;
@end

// Convenience layer over TBHTTPRequest for API calls: redirects are followed, GET requests are tried a second
// time after a network error, completion blocks run on the main thread.
@interface TBHTTP : NSObject

+ (TBHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(TBHTTPCompletion)completion;

+ (TBHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(TBHTTPCompletion)completion;

// JSON answers. `error` is set for network errors, for statuses >= 400 (code = the status, message from the body
// when it has one) and for bodies that are not JSON; `json` is passed even with an error when the body parsed.
+ (TBHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(TBJSONCompletion)completion;
+ (TBHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(TBJSONCompletion)completion;
+ (TBHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(TBJSONCompletion)completion;

@end
