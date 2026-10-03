#import "TBLibrary.h"
#import "TBSettings.h"
#import "TBUtils.h"
#import "TBCommon.h"

static const NSUInteger TBHistoryLimit = 500;
static const NSTimeInterval TBFeedCacheSeconds = 300;

#pragma mark - RSS

// Parses YouTube's Atom feed: <entry> with <yt:videoId>, <title>, <published>, <author><name>, <media:group>
// (<media:thumbnail url>, <media:community><media:statistics views>)
@interface TBFeedParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *videos;
@property (nonatomic, strong) TBVideo *current;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, copy) NSString *channelId;
@property (nonatomic, copy) NSString *channelName;
@property (nonatomic) BOOL inEntry, inAuthor;
+ (NSDate *)dateWithOffset:(NSString *)s;
@end

@implementation TBFeedParser

- (NSArray *)parse:(NSData *)data
{
    self.videos = [NSMutableArray array];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    [parser parse];
    return self.videos;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributes
{
    self.text = [NSMutableString string];
    if ([name isEqualToString:@"entry"]) { self.inEntry = YES; self.current = [[TBVideo alloc] init]; }
    else if ([name isEqualToString:@"author"]) self.inAuthor = YES;
    else if (self.inEntry && [name isEqualToString:@"media:thumbnail"]) self.current.thumbnailURL = attributes[@"url"];
    else if (self.inEntry && [name isEqualToString:@"media:statistics"]) {
        self.current.viewCount = [attributes[@"views"] longLongValue];
        if (self.current.viewCount > 0) self.current.viewsText = [NSString stringWithFormat:L(@"%@ views"), [TBUtils formatCount:(NSInteger)MIN(self.current.viewCount, (long long)NSIntegerMax)]];
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    [self.text appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)qName
{
    NSString *value = [self.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([name isEqualToString:@"entry"]) {
        if (self.current.videoId.length) {
            if (!self.current.channelId.length) self.current.channelId = self.channelId;
            if (!self.current.channelName.length) self.current.channelName = self.channelName;
            [self.videos addObject:self.current];
        }
        self.inEntry = NO;
        self.current = nil;
        return;
    }
    if ([name isEqualToString:@"author"]) { self.inAuthor = NO; return; }
    if (!self.inEntry) {
        if ([name isEqualToString:@"yt:channelId"]) self.channelId = value;
        else if ([name isEqualToString:@"name"] && self.inAuthor) self.channelName = value;
        return;
    }
    if ([name isEqualToString:@"yt:videoId"]) self.current.videoId = value;
    else if ([name isEqualToString:@"title"]) self.current.title = value;
    else if ([name isEqualToString:@"yt:channelId"]) self.current.channelId = value;
    else if ([name isEqualToString:@"name"] && self.inAuthor) self.current.channelName = value;
    else if ([name isEqualToString:@"published"]) self.current.publishedAt = TBDateFromISO(value) ?: [TBFeedParser dateWithOffset:value];
}

// "2026-09-27T16:00:14+00:00" (TBDateFromISO knows the "Z" form only)
+ (NSDate *)dateWithOffset:(NSString *)s
{
    if (s.length < 25) return nil;
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZ";
    });
    // "+00:00" -> "+0000"
    NSString *fixed = [[s substringToIndex:s.length - 3] stringByAppendingString:[s substringFromIndex:s.length - 2]];
    @synchronized (f) { return [f dateFromString:fixed]; }
}

@end

@implementation TBFeed

+ (TBHTTPTask *)videosOfChannel:(NSString *)channelId completion:(void (^)(NSArray *videos, NSError *error))completion
{
    NSString *url = [NSString stringWithFormat:@"https://www.youtube.com/feeds/videos.xml?channel_id=%@", [TBUtils urlEncode:channelId ?: @""]];
    return [TBHTTP get:url headers:@{ @"Accept": @"application/atom+xml, application/xml, */*" } completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        if (error) { completion(nil, error); return; }
        if (status != 200) { completion(nil, TBMakeError(TBErrorAPI, [NSString stringWithFormat:L(@"The feed could not be loaded (HTTP %ld)."), (long)status])); return; }
        NSArray *videos = [[[TBFeedParser alloc] init] parse:body];
        completion(videos, nil);
    }];
}

@end

#pragma mark - Library

@interface TBLibrary ()
@property (nonatomic, strong) NSMutableArray *subscriptionList;    // TBChannel
@property (nonatomic, strong) NSMutableArray *historyList;         // TBVideo
@property (nonatomic, strong) NSMutableArray *laterList;           // TBVideo
@property (nonatomic, strong) NSArray *feed;
@property (nonatomic, strong) NSDate *feedLoadedAt;
@property (nonatomic, strong) NSArray *feedLogins;                 // the subscriptions the feed was built from
@end

@implementation TBLibrary

+ (instancetype)shared
{
    static TBLibrary *library;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ library = [[TBLibrary alloc] init]; });
    return library;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _subscriptionList = [NSMutableArray array];
        _historyList = [NSMutableArray array];
        _laterList = [NSMutableArray array];
        for (id d in [NSArray arrayWithContentsOfFile:[self pathFor:@"subscriptions"]]) { TBChannel *c = [TBChannel channelFromDictionary:d]; if (c) [_subscriptionList addObject:c]; }
        for (id d in [NSArray arrayWithContentsOfFile:[self pathFor:@"history"]]) { TBVideo *v = [TBVideo videoFromDictionary:d]; if (v) [_historyList addObject:v]; }
        for (id d in [NSArray arrayWithContentsOfFile:[self pathFor:@"watchlater"]]) { TBVideo *v = [TBVideo videoFromDictionary:d]; if (v) [_laterList addObject:v]; }
    }
    return self;
}

- (NSString *)pathFor:(NSString *)name
{
    return [[TBUtils documentsPath] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
}

- (void)saveList:(NSArray *)list as:(NSString *)name
{
    NSMutableArray *dicts = [NSMutableArray array];
    for (id item in list) [dicts addObject:[item dictionary]];
    NSString *path = [self pathFor:name];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [dicts writeToFile:path atomically:YES];
    });
}

- (void)notify
{
    TBMain(^{ [[NSNotificationCenter defaultCenter] postNotificationName:TBLibraryDidChangeNotification object:self]; });
}

#pragma mark Subscriptions

- (NSArray *)subscriptions { return [self.subscriptionList copy]; }

- (BOOL)isSubscribed:(NSString *)channelId
{
    for (TBChannel *c in self.subscriptionList) if ([c.channelId isEqualToString:channelId]) return YES;
    return NO;
}

- (void)subscribe:(TBChannel *)channel
{
    if (!channel.channelId.length || [self isSubscribed:channel.channelId]) return;
    TBChannel *copy = [TBChannel channelFromDictionary:[channel dictionary]];
    copy.subscribedAt = [NSDate date];
    [self.subscriptionList insertObject:copy atIndex:0];
    [self saveList:self.subscriptionList as:@"subscriptions"];
    self.feedLoadedAt = nil;   // (the feed is out of date now)
    [self notify];
}

- (void)unsubscribe:(NSString *)channelId
{
    NSUInteger before = self.subscriptionList.count;
    for (NSInteger i = (NSInteger)self.subscriptionList.count - 1; i >= 0; i--) {
        if ([[self.subscriptionList[(NSUInteger)i] channelId] isEqualToString:channelId]) [self.subscriptionList removeObjectAtIndex:(NSUInteger)i];
    }
    if (self.subscriptionList.count == before) return;
    [self saveList:self.subscriptionList as:@"subscriptions"];
    NSMutableArray *feed = [NSMutableArray array];
    for (TBVideo *v in self.feed) if (![v.channelId isEqualToString:channelId]) [feed addObject:v];
    self.feed = feed;
    [self notify];
}

#pragma mark Feed

- (NSArray *)cachedFeed { return self.feed; }

- (TBHTTPTask *)feedForce:(BOOL)force completion:(void (^)(NSArray *videos, NSError *error))completion
{
    NSArray *channels = [self subscriptions];
    if (!channels.count) { TBMain(^{ completion(@[], nil); }); return nil; }
    if (!force && self.feed && self.feedLoadedAt && -[self.feedLoadedAt timeIntervalSinceNow] < TBFeedCacheSeconds) {
        NSArray *feed = self.feed;
        TBMain(^{ completion(feed, nil); });
        return nil;
    }
    TBHTTPTask *outer = [[TBHTTPTask alloc] init];
    NSMutableArray *tasks = [NSMutableArray array];
    outer.cancelBlock = ^{ for (TBHTTPTask *t in tasks) [t cancel]; };
    NSMutableArray *all = [NSMutableArray array];
    __block NSUInteger pending = channels.count;
    __block NSError *lastError = nil;
    __block NSUInteger failures = 0;
    __weak TBLibrary *weakSelf = self;
    for (TBChannel *c in channels) {
        TBHTTPTask *t = [TBFeed videosOfChannel:c.channelId completion:^(NSArray *videos, NSError *error) {
            if (outer.isCancelled) return;
            if (error) { lastError = error; failures++; }
            for (TBVideo *v in videos) {
                if (!v.channelAvatarURL.length) v.channelAvatarURL = c.avatarURL;
                if (!v.channelName.length) v.channelName = c.title;
                [all addObject:v];
            }
            if (--pending > 0) return;
            TBLibrary *s = weakSelf;
            if (failures == channels.count && lastError) { completion(nil, lastError); return; }
            [all sortUsingComparator:^NSComparisonResult(TBVideo *a, TBVideo *b) {
                return [(b.publishedAt ?: [NSDate distantPast]) compare:(a.publishedAt ?: [NSDate distantPast])];
            }];
            s.feed = all;
            s.feedLoadedAt = [NSDate date];
            completion(all, nil);
        }];
        if (t) [tasks addObject:t];
    }
    return outer;
}

#pragma mark History

- (NSArray *)history { return [self.historyList copy]; }

- (void)addToHistory:(TBVideo *)video
{
    if (!video.videoId.length || ![TBSettings keepHistory]) return;
    TBVideo *copy = [TBVideo videoFromDictionary:[video dictionary]];
    NSTimeInterval position = 0;
    for (NSInteger i = (NSInteger)self.historyList.count - 1; i >= 0; i--) {
        TBVideo *old = self.historyList[(NSUInteger)i];
        if ([old.videoId isEqualToString:video.videoId]) { position = old.position; [self.historyList removeObjectAtIndex:(NSUInteger)i]; }
    }
    copy.watchedAt = [NSDate date];
    copy.position = video.position > 0 ? video.position : position;
    [self.historyList insertObject:copy atIndex:0];
    while (self.historyList.count > TBHistoryLimit) [self.historyList removeLastObject];
    [self saveList:self.historyList as:@"history"];
    [self notify];
}

- (void)updateDetailsOf:(TBVideo *)video
{
    if (!video.videoId.length) return;
    BOOL changed = NO;
    for (NSMutableArray *list in @[ self.historyList, self.laterList ]) {
        for (TBVideo *v in list) {
            if (![v.videoId isEqualToString:video.videoId]) continue;
            if (video.title.length && ![video.title isEqualToString:v.title]) { v.title = video.title; changed = YES; }
            if (video.channelName.length && ![video.channelName isEqualToString:v.channelName]) { v.channelName = video.channelName; changed = YES; }
            if (video.channelId.length && !v.channelId.length) { v.channelId = video.channelId; changed = YES; }
            if (video.lengthSeconds > 0 && v.lengthSeconds <= 0) { v.lengthSeconds = video.lengthSeconds; v.lengthText = [TBUtils formatDuration:video.lengthSeconds]; changed = YES; }
            if (video.isLive != v.isLive) { v.isLive = video.isLive; changed = YES; }
        }
    }
    if (!changed) return;
    [self saveList:self.historyList as:@"history"];
    [self saveList:self.laterList as:@"watchlater"];
    [self notify];
}

- (void)updatePosition:(NSTimeInterval)position forVideo:(NSString *)videoId
{
    for (TBVideo *v in self.historyList) {
        if ([v.videoId isEqualToString:videoId]) {
            v.position = position;
            [self saveList:self.historyList as:@"history"];
            return;
        }
    }
}

- (void)removeFromHistory:(NSString *)videoId
{
    for (NSInteger i = (NSInteger)self.historyList.count - 1; i >= 0; i--) {
        if ([[self.historyList[(NSUInteger)i] videoId] isEqualToString:videoId]) [self.historyList removeObjectAtIndex:(NSUInteger)i];
    }
    [self saveList:self.historyList as:@"history"];
    [self notify];
}

- (void)clearHistory
{
    [self.historyList removeAllObjects];
    [self saveList:self.historyList as:@"history"];
    [self notify];
}

#pragma mark Watch later

- (NSArray *)watchLater { return [self.laterList copy]; }

- (BOOL)isInWatchLater:(NSString *)videoId
{
    for (TBVideo *v in self.laterList) if ([v.videoId isEqualToString:videoId]) return YES;
    return NO;
}

- (void)toggleWatchLater:(TBVideo *)video
{
    if (!video.videoId.length) return;
    if ([self isInWatchLater:video.videoId]) { [self removeFromWatchLater:video.videoId]; return; }
    TBVideo *copy = [TBVideo videoFromDictionary:[video dictionary]];
    copy.watchedAt = [NSDate date];
    [self.laterList insertObject:copy atIndex:0];
    [self saveList:self.laterList as:@"watchlater"];
    [self notify];
}

- (void)removeFromWatchLater:(NSString *)videoId
{
    for (NSInteger i = (NSInteger)self.laterList.count - 1; i >= 0; i--) {
        if ([[self.laterList[(NSUInteger)i] videoId] isEqualToString:videoId]) [self.laterList removeObjectAtIndex:(NSUInteger)i];
    }
    [self saveList:self.laterList as:@"watchlater"];
    [self notify];
}

@end
