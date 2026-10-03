#import "TBHTTP.h"
#import "TBHTTPRequest.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"

static const NSInteger TBMaxRedirects = 5;

@interface TBHTTPTask ()
@property (atomic, strong) TBHTTPRequest *request;
@property (atomic) BOOL isCancelled;
@end

@implementation TBHTTPTask

- (void)cancel
{
    if (self.isCancelled) return;
    self.isCancelled = YES;
    [self.request cancel];
    dispatch_block_t block = self.cancelBlock;
    self.cancelBlock = nil;
    if (block) block();
}

@end

@implementation TBHTTP

+ (void)run:(TBHTTPTask *)task method:(NSString *)method url:(NSURL *)url headers:(NSDictionary *)headers body:(NSData *)body
       hops:(NSInteger)hops retries:(NSInteger)retries completion:(TBHTTPCompletion)completion
{
    TBHTTPRequest *r = [[TBHTTPRequest alloc] initWithMethod:method URL:url];
    r.headers = headers;
    r.body = body;
    r.connectTimeout = 15;
    r.readTimeout = 30;
    r.verifyTLS = [TBSettings verifyTLS];
    __weak TBHTTPRequest *weakRequest = r;
    r.onComplete = ^(NSError *error) {
        TBHTTPRequest *request = weakRequest;
        if (task.isCancelled) return;
        NSInteger status = request.statusCode;
        NSDictionary *responseHeaders = request.responseHeaders;
        if (!error && status >= 300 && status < 400 && status != 304 && hops < TBMaxRedirects) {
            NSString *location = responseHeaders[@"location"];
            NSURL *next = location.length ? [[NSURL URLWithString:location relativeToURL:url] absoluteURL] : nil;
            if (next.host.length) {
                BOOL safe = [method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"];
                BOOL toGet = status == 303 || ((status == 301 || status == 302) && !safe);
                NSDictionary *nextHeaders = headers;
                if (![[next.host lowercaseString] isEqualToString:[url.host lowercaseString]]) {
                    // credentials stay with the host they were meant for
                    NSMutableDictionary *trimmed = [NSMutableDictionary dictionary];
                    for (NSString *key in headers) {
                        NSString *lower = [key lowercaseString];
                        if ([lower isEqualToString:@"authorization"] || [lower isEqualToString:@"client-id"]) continue;
                        trimmed[key] = headers[key];
                    }
                    nextHeaders = trimmed;
                }
                [self run:task method:toGet ? @"GET" : method url:next headers:nextHeaders body:toGet ? nil : body
                     hops:hops + 1 retries:retries completion:completion];
                return;
            }
        }
        if (error && retries > 0 && error.code != TBErrorCancelled && error.code != TBErrorCertificate) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (task.isCancelled) return;
                [self run:task method:method url:url headers:headers body:body hops:hops retries:retries - 1 completion:completion];
            });
            return;
        }
        NSData *responseBody = request.responseBody;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(error ? 0 : status, responseBody, responseHeaders, error);
        });
    };
    task.request = r;
    if (task.isCancelled) return;
    [r start];
}

+ (TBHTTPTask *)request:(NSString *)method url:(NSString *)url headers:(NSDictionary *)headers body:(NSData *)body
                retries:(NSInteger)retries completion:(TBHTTPCompletion)completion
{
    TBHTTPTask *task = [[TBHTTPTask alloc] init];
    NSURL *u = url.length ? [NSURL URLWithString:url] : nil;
    if (!u.host.length) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (task.isCancelled) return;
            if (completion) completion(0, nil, nil, TBMakeError(TBErrorNetwork, [NSString stringWithFormat:@"Bad address: %@", url ?: @""]));
        });
        return task;
    }
    [self run:task method:method.length ? [method uppercaseString] : @"GET" url:u headers:headers body:body hops:0 retries:retries completion:completion];
    return task;
}

+ (TBHTTPTask *)get:(NSString *)url headers:(NSDictionary *)headers completion:(TBHTTPCompletion)completion
{
    return [self request:@"GET" url:url headers:headers body:nil retries:1 completion:completion];
}

// What an error body says: {"message": ...}, {"error": ..., "message": ...}, {"error_description": ...}, {"errors": [{"message": ...}]}
+ (NSString *)messageFromErrorJSON:(id)json
{
    NSDictionary *d = TBDict(json);
    if (!d) {
        NSDictionary *first = TBDict([TBArr(json) firstObject]);
        return TBStr(first[@"error"]) ?: TBStr(first[@"message"]);
    }
    NSString *message = TBStr(d[@"message"]);
    if (!message.length) message = TBStr(d[@"error_description"]);
    if (!message.length) message = TBStr(TBDict([TBArr(d[@"errors"]) firstObject])[@"message"]);
    if (!message.length && [d[@"error"] isKindOfClass:[NSString class]]) message = d[@"error"];
    return message.length ? message : nil;
}

+ (TBHTTPCompletion)jsonHandler:(TBJSONCompletion)completion
{
    return ^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (!completion) return;
        if (error) { completion(nil, 0, error); return; }
        id json = [TBUtils JSONObjectFromData:body];
        if (status >= 400) {
            NSString *message = [self messageFromErrorJSON:json] ?: [NSString stringWithFormat:L(@"Request failed (HTTP %ld)."), (long)status];
            completion(json, status, TBMakeError(status, message));
            return;
        }
        if (!json && body.length) {
            completion(nil, status, TBMakeError(TBErrorBadResponse, L(@"Unexpected response format.")));
            return;
        }
        completion(json, status, nil);
    };
}

+ (TBHTTPTask *)getJSON:(NSString *)url headers:(NSDictionary *)headers completion:(TBJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (!h[@"Accept"]) h[@"Accept"] = @"application/json";
    return [self request:@"GET" url:url headers:h body:nil retries:1 completion:[self jsonHandler:completion]];
}

+ (TBHTTPTask *)postJSON:(NSString *)url headers:(NSDictionary *)headers object:(id)object retries:(NSInteger)retries
              completion:(TBJSONCompletion)completion
{
    NSMutableDictionary *h = [NSMutableDictionary dictionaryWithDictionary:headers ?: @{}];
    if (!h[@"Accept"]) h[@"Accept"] = @"application/json";
    if (!h[@"Content-Type"]) h[@"Content-Type"] = @"application/json";
    NSData *body = [TBUtils JSONDataFromObject:object] ?: [NSData data];
    return [self request:@"POST" url:url headers:h body:body retries:retries completion:[self jsonHandler:completion]];
}

+ (TBHTTPTask *)postForm:(NSString *)url fields:(NSDictionary *)fields completion:(TBJSONCompletion)completion
{
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in fields) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [TBUtils urlEncode:key], [TBUtils urlEncode:[fields[key] description]]]];
    }
    NSData *body = [[pairs componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *h = @{ @"Content-Type": @"application/x-www-form-urlencoded", @"Accept": @"application/json" };
    return [self request:@"POST" url:url headers:h body:body retries:0 completion:[self jsonHandler:completion]];
}

@end
