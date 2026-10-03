#import "TBConnectionPool.h"
#import "TBTLSSocket.h"
#import "TBCommon.h"

static const NSTimeInterval TBIdleTimeout = 25;     // most servers drop idle connections after 5 to 60 s
static const NSUInteger TBMaxIdlePerKey = 6;
static const NSUInteger TBMaxIdleTotal = 24;

@interface TBPooledConnection : NSObject
@property (nonatomic, strong) TBTLSSocket *socket;
@property (nonatomic) NSTimeInterval lastUsed;
@end

@implementation TBPooledConnection
@end

@implementation TBConnectionPool {
    NSMutableDictionary *_idle;     // key -> NSMutableArray<TBPooledConnection>
    NSUInteger _count;
    NSUInteger _reuses;
}

+ (instancetype)shared
{
    static TBConnectionPool *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ pool = [[TBConnectionPool alloc] init]; });
    return pool;
}

- (instancetype)init
{
    self = [super init];
    if (self) _idle = [NSMutableDictionary dictionary];
    return self;
}

// Must be called with the lock held. Moves expired connections into `dead`.
- (void)pruneLocked:(NSMutableArray *)dead
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSMutableArray *emptyKeys = [NSMutableArray array];
    for (NSString *key in _idle) {
        NSMutableArray *list = _idle[key];
        for (NSInteger i = (NSInteger)list.count - 1; i >= 0; i--) {
            TBPooledConnection *c = list[(NSUInteger)i];
            if (now - c.lastUsed > TBIdleTimeout) {
                [dead addObject:c.socket];
                [list removeObjectAtIndex:(NSUInteger)i];
                _count--;
            }
        }
        if (!list.count) [emptyKeys addObject:key];
    }
    [_idle removeObjectsForKeys:emptyKeys];
}

- (TBTLSSocket *)checkoutSocketForKey:(NSString *)key
{
    if (!key) return nil;
    NSMutableArray *dead = [NSMutableArray array];
    TBTLSSocket *result = nil;
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        while (list.count && !result) {
            TBPooledConnection *c = [list lastObject];
            [list removeLastObject];
            _count--;
            if ([c.socket isLikelyAlive]) result = c.socket;
            else [dead addObject:c.socket];
        }
        if (result) _reuses++;
    }
    for (TBTLSSocket *s in dead) [s close];
    return result;
}

- (void)checkinSocket:(TBTLSSocket *)socket forKey:(NSString *)key
{
    if (!socket || !key) return;
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        [self pruneLocked:dead];
        NSMutableArray *list = _idle[key];
        if (!list) {
            list = [NSMutableArray array];
            _idle[key] = list;
        }
        if (list.count >= TBMaxIdlePerKey || _count >= TBMaxIdleTotal) {
            [dead addObject:socket];
        } else {
            TBPooledConnection *c = [[TBPooledConnection alloc] init];
            c.socket = socket;
            c.lastUsed = [NSDate timeIntervalSinceReferenceDate];
            [list addObject:c];
            _count++;
        }
    }
    for (TBTLSSocket *s in dead) [s close];
}

- (void)drain
{
    NSMutableArray *dead = [NSMutableArray array];
    @synchronized (self) {
        for (NSString *key in _idle) {
            for (TBPooledConnection *c in _idle[key]) [dead addObject:c.socket];
        }
        [_idle removeAllObjects];
        _count = 0;
    }
    for (TBTLSSocket *s in dead) [s close];
    if (dead.count) TBLog(@"Connection pool drained (%lu closed)", (unsigned long)dead.count);
}

- (NSUInteger)idleCount
{
    @synchronized (self) { return _count; }
}

- (NSUInteger)reuseCount
{
    @synchronized (self) { return _reuses; }
}

@end
