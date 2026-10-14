#import "TBLinkLabel.h"
#import "TBUtils.h"
#import "TBModern.h"
#import "TBCommon.h"
#import <CoreText/CoreText.h>

#pragma mark - Layout

// One drawn line: the CTLine, the characters of the text it stands for and the offset its own string indices have
// against the text (0 for a line of the frame; the start of the paragraph for the truncated last line)
@interface TBLinkLine : NSObject
@property (nonatomic) CTLineRef line;           // owned
@property (nonatomic) NSRange range;            // in the text
@property (nonatomic) NSUInteger base;
@end

@implementation TBLinkLine
- (void)dealloc { if (_line) CFRelease(_line); }
@end

// The lines of one text at one width, with a limit on their number; shared through a cache, because a table asks
// for the height of every row at once and draws each of them right after
@interface TBLinkLayout : NSObject
@property (nonatomic, strong) NSArray *lines;   // TBLinkLine
@property (nonatomic) CGFloat lineHeight;       // the step from one line to the next (the font's)
@property (nonatomic) CGFloat ascent;           // the baseline below the top of a line
@property (nonatomic) CGFloat width;
@property (nonatomic) CGFloat height;
@end

@implementation TBLinkLayout
@end

// The Core Text font of a UIFont: toll-free bridged since iOS 7; iOS 6 finds it by its name (the system font's
// private name is known to Core Text; an unknown name would give Helvetica, which is what the system font is)
static CTFontRef TBCreateCTFont(UIFont *font)
{
    if (TBModernIOS()) return (CTFontRef)CFRetain((__bridge CFTypeRef)font);
    return CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);
}

// The text with the font only: the colours come from the graphics context when the lines are drawn (so one layout
// serves the row heights, the drawing and both themes)
static NSAttributedString *TBLayoutString(NSString *text, UIFont *font)
{
    CTFontRef ctFont = TBCreateCTFont(font);
    NSDictionary *attributes = @{ (__bridge id)kCTFontAttributeName: (__bridge id)ctFont,
                                  (__bridge id)kCTForegroundColorFromContextAttributeName: (__bridge id)kCFBooleanTrue };
    NSAttributedString *s = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CFRelease(ctFont);
    return s;
}

static NSString *TBTrimmedText(NSString *text)
{
    if (!text) return @"";
    // trailing blank lines would add empty rows; everything before stays where it is (the links' offsets hold)
    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSUInteger end = text.length;
    while (end > 0 && [blank characterIsMember:[text characterAtIndex:end - 1]]) end--;
    return end == text.length ? text : [text substringToIndex:end];
}

static NSCache *TBLayoutCache(void)
{
    static NSCache *cache = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; cache.countLimit = 160; });
    return cache;
}

static TBLinkLayout *TBMakeLayout(NSString *text, UIFont *font, CGFloat width, NSInteger maxLines)
{
    TBLinkLayout *layout = [[TBLinkLayout alloc] init];
    layout.width = width;
    layout.lineHeight = ceil(font.lineHeight);
    layout.ascent = ceil(font.ascender);
    if (!text.length || width < 1) { layout.lines = @[]; return layout; }

    NSAttributedString *attributed = TBLayoutString(text, font);
    CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, CGRectMake(0, 0, width, 200000));
    CTFrameRef frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, NULL);
    CFArrayRef frameLines = CTFrameGetLines(frame);
    CFIndex count = CFArrayGetCount(frameLines);
    CFIndex shown = (maxLines > 0 && count > maxLines) ? maxLines : count;
    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:(NSUInteger)shown];
    for (CFIndex i = 0; i < shown; i++) {
        CTLineRef line = (CTLineRef)CFArrayGetValueAtIndex(frameLines, i);
        CFRange r = CTLineGetStringRange(line);
        TBLinkLine *entry = [[TBLinkLine alloc] init];
        if (i == shown - 1 && shown < count) {
            // the last line shown stands for the rest of its paragraph (and "…" says that more follows)
            NSUInteger start = (NSUInteger)r.location;
            NSRange paragraph = [text rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet] options:0 range:NSMakeRange(start, text.length - start)];
            NSUInteger length = paragraph.location == NSNotFound ? text.length - start : paragraph.location - start;
            NSMutableAttributedString *rest = [[attributed attributedSubstringFromRange:NSMakeRange(start, length)] mutableCopy];
            NSDictionary *attributes = [attributed attributesAtIndex:start effectiveRange:NULL];
            [rest appendAttributedString:[[NSAttributedString alloc] initWithString:@"…" attributes:attributes]];
            CTLineRef restLine = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)rest);
            CTLineRef token = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)[[NSAttributedString alloc] initWithString:@"…" attributes:attributes]);
            CTLineRef truncated = CTLineCreateTruncatedLine(restLine, width, kCTLineTruncationEnd, token);
            entry.line = truncated ?: (CTLineRef)CFRetain(restLine);
            entry.range = NSMakeRange(start, length);
            entry.base = start;
            CFRelease(restLine);
            CFRelease(token);
        } else {
            entry.line = (CTLineRef)CFRetain(line);
            entry.range = NSMakeRange((NSUInteger)r.location, (NSUInteger)r.length);
            entry.base = 0;
        }
        [lines addObject:entry];
    }
    layout.lines = lines;
    layout.height = shown * layout.lineHeight;
    CFRelease(frame);
    CGPathRelease(path);
    CFRelease(framesetter);
    return layout;
}

static TBLinkLayout *TBLayoutFor(NSString *text, UIFont *font, CGFloat width, NSInteger maxLines)
{
    width = floor(width);
    NSString *key = [NSString stringWithFormat:@"%@|%g|%g|%ld|%@", font.fontName, font.pointSize, width, (long)maxLines, text];
    TBLinkLayout *layout = [TBLayoutCache() objectForKey:key];
    if (!layout) {
        layout = TBMakeLayout(text, font, width, maxLines);
        [TBLayoutCache() setObject:layout forKey:key];
    }
    return layout;
}

#pragma mark - Finding the links

static NSDataDetector *TBLinkDetector(void)
{
    static NSDataDetector *detector = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL]; });
    return detector;
}

// The detector also takes "readme.md" or "node.sh" for addresses: without a scheme or "www." the text has to
// carry a path, or name one of the sites the app has pages for
static BOOL TBLooksLikeAddress(NSString *shown, NSURL *url)
{
    NSString *lower = [shown lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"www."]) return YES;
    if ([lower rangeOfString:@"/"].location != NSNotFound) return YES;
    NSString *host = [url.host lowercaseString] ?: @"";
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    for (NSString *site in @[ @"youtube.com", @"youtu.be", @"twitch.tv", @"kick.com", @"tiktok.com" ]) {
        if ([host isEqualToString:site] || [host hasSuffix:[@"." stringByAppendingString:site]]) return YES;
    }
    return NO;
}

@interface TBLinkLabel ()
@property (nonatomic, copy, readwrite) NSString *text;
@property (nonatomic, strong, readwrite) NSArray *links;
@property (nonatomic, strong) TBLinkLayout *layout;
@property (nonatomic, strong) TBTextLink *pressedLink;
@end

@implementation TBLinkLabel

+ (NSArray *)linksInText:(NSString *)text knownLinks:(NSArray *)knownLinks
{
    NSMutableArray *links = [NSMutableArray array];
    for (TBTextLink *known in knownLinks) {
        if ([known isKindOfClass:[TBTextLink class]] && known.range.length && NSMaxRange(known.range) <= text.length && known.url.length) [links addObject:known];
    }
    if (text.length) {
        NSArray *matches = [TBLinkDetector() matchesInString:text options:0 range:NSMakeRange(0, text.length)];
        for (NSTextCheckingResult *match in matches) {
            NSURL *url = match.URL;
            NSString *scheme = [url.scheme lowercaseString];
            if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) continue;   // (mailto: and the like)
            if (!TBLooksLikeAddress([text substringWithRange:match.range], url)) continue;
            BOOL overlaps = NO;
            for (TBTextLink *known in links) if (NSIntersectionRange(known.range, match.range).length) { overlaps = YES; break; }
            if (!overlaps) [links addObject:[TBTextLink linkWithRange:match.range url:url.absoluteString]];
        }
    }
    [links sortUsingComparator:^NSComparisonResult(TBTextLink *a, TBTextLink *b) {
        return a.range.location < b.range.location ? NSOrderedAscending : (a.range.location > b.range.location ? NSOrderedDescending : NSOrderedSame);
    }];
    return links;
}

+ (CGFloat)heightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)width maxLines:(NSInteger)maxLines
{
    return TBLayoutFor(TBTrimmedText(text), font ?: [UIFont systemFontOfSize:14], width, maxLines).height;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.contentMode = UIViewContentModeRedraw;
        _font = [UIFont systemFontOfSize:14];
        _textColor = [UIColor blackColor];
        _linkColor = [UIColor colorWithRed:30 / 255.0 green:90 / 255.0 blue:200 / 255.0 alpha:1];
        _text = @"";
        _links = @[];
    }
    return self;
}

- (void)setText:(NSString *)text knownLinks:(NSArray *)knownLinks
{
    self.text = TBTrimmedText(text);
    self.links = [TBLinkLabel linksInText:self.text knownLinks:knownLinks];
    [self invalidate];
}

- (void)invalidate
{
    self.layout = nil;
    self.pressedLink = nil;
    [self setNeedsDisplay];
}

- (void)setFont:(UIFont *)font { _font = font ?: [UIFont systemFontOfSize:14]; [self invalidate]; }
- (void)setTextColor:(UIColor *)textColor { _textColor = textColor ?: [UIColor blackColor]; [self setNeedsDisplay]; }
- (void)setLinkColor:(UIColor *)linkColor { _linkColor = linkColor ?: _linkColor; [self setNeedsDisplay]; }
- (void)setNumberOfLines:(NSInteger)numberOfLines { _numberOfLines = numberOfLines; [self invalidate]; }

- (void)setFrame:(CGRect)frame
{
    BOOL widthChanged = fabs(frame.size.width - self.frame.size.width) > 0.5;
    [super setFrame:frame];
    if (widthChanged) [self invalidate];
}

- (void)setBounds:(CGRect)bounds
{
    BOOL widthChanged = fabs(bounds.size.width - self.bounds.size.width) > 0.5;
    [super setBounds:bounds];
    if (widthChanged) [self invalidate];
}

- (TBLinkLayout *)currentLayout
{
    CGFloat width = floor(self.bounds.size.width);
    if (!self.layout || fabs(self.layout.width - width) > 0.5) self.layout = TBLayoutFor(self.text, self.font, width, self.numberOfLines);
    return self.layout;
}

#pragma mark - Where the links are

// The rectangles a link covers (one per line it runs over), in the view's coordinates
- (NSArray *)rectsForLink:(TBTextLink *)link
{
    TBLinkLayout *layout = [self currentLayout];
    NSMutableArray *rects = [NSMutableArray array];
    for (NSUInteger i = 0; i < layout.lines.count; i++) {
        TBLinkLine *line = layout.lines[i];
        NSRange part = NSIntersectionRange(line.range, link.range);
        if (!part.length) continue;
        CGFloat x0 = CTLineGetOffsetForStringIndex(line.line, (CFIndex)(part.location - line.base), NULL);
        CGFloat x1 = CTLineGetOffsetForStringIndex(line.line, (CFIndex)(NSMaxRange(part) - line.base), NULL);
        CGFloat w = fabs(x1 - x0);
        if (w < 1) continue;
        [rects addObject:[NSValue valueWithCGRect:CGRectMake(MIN(x0, x1), i * layout.lineHeight, w, layout.lineHeight)]];
    }
    return rects;
}

- (TBTextLink *)linkAtPoint:(CGPoint)point
{
    for (TBTextLink *link in self.links) {
        for (NSValue *v in [self rectsForLink:link]) {
            if (CGRectContainsPoint(CGRectInset([v CGRectValue], -4, -3), point)) return link;
        }
    }
    return nil;
}

// Only a link is this view's business; a touch on plain text goes to whatever lies below (the row, the header)
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.hidden || !self.userInteractionEnabled || self.alpha < 0.01 || !self.onLink || !self.links.count) return nil;
    return [self linkAtPoint:point] ? self : nil;
}

#pragma mark - Touches (not passed on: the row below must not select when a link is tapped)

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.pressedLink = [self linkAtPoint:[[touches anyObject] locationInView:self]];
    [self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (self.pressedLink && [self linkAtPoint:[[touches anyObject] locationInView:self]] != self.pressedLink) {
        self.pressedLink = nil;
        [self setNeedsDisplay];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    TBTextLink *link = self.pressedLink;
    self.pressedLink = nil;
    [self setNeedsDisplay];
    if (link && self.onLink && [self linkAtPoint:[[touches anyObject] locationInView:self]] == link) self.onLink(link.url, self);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    self.pressedLink = nil;
    [self setNeedsDisplay];
}

#pragma mark - Drawing

// Glyphs of a run drawn in the text colour, those of a link in the link colour
- (void)drawLine:(TBLinkLine *)line inContext:(CGContextRef)ctx
{
    CGColorRef textColor = self.textColor.CGColor, linkColor = self.linkColor.CGColor;
    NSArray *links = self.links;
    CFArrayRef runs = CTLineGetGlyphRuns(line.line);
    for (CFIndex r = 0; r < CFArrayGetCount(runs); r++) {
        CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
        CFIndex glyphs = CTRunGetGlyphCount(run);
        if (glyphs <= 0) continue;
        if (!links.count) {
            CGContextSetFillColorWithColor(ctx, textColor);
            CTRunDraw(run, ctx, CFRangeMake(0, 0));
            continue;
        }
        const CFIndex *indices = CTRunGetStringIndicesPtr(run);
        CFIndex *copy = NULL;
        if (!indices) {
            copy = malloc(sizeof(CFIndex) * (size_t)glyphs);
            CTRunGetStringIndices(run, CFRangeMake(0, 0), copy);
            indices = copy;
        }
        CFIndex start = 0;
        BOOL inLink = NO;
        for (CFIndex g = 0; g <= glyphs; g++) {
            BOOL isLink = NO;
            if (g < glyphs) {
                NSUInteger index = (NSUInteger)indices[g] + line.base;
                for (TBTextLink *link in links) if (NSLocationInRange(index, link.range)) { isLink = YES; break; }
            }
            if (g == glyphs || isLink != inLink) {
                if (g > start) {
                    CGContextSetFillColorWithColor(ctx, inLink ? linkColor : textColor);
                    CTRunDraw(run, ctx, CFRangeMake(start, g - start));
                }
                start = g;
                inLink = isLink;
            }
        }
        if (copy) free(copy);
    }
}

- (void)drawRect:(CGRect)rect
{
    TBLinkLayout *layout = [self currentLayout];
    if (!layout.lines.count) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (self.pressedLink) {
        [[self.linkColor colorWithAlphaComponent:0.22] setFill];
        for (NSValue *v in [self rectsForLink:self.pressedLink]) {
            [[UIBezierPath bezierPathWithRoundedRect:CGRectInset([v CGRectValue], -2, 0) cornerRadius:3] fill];
        }
    }
    CGContextSaveGState(ctx);
    CGFloat height = self.bounds.size.height;
    CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1, -1);
    for (NSUInteger i = 0; i < layout.lines.count; i++) {
        CGFloat baseline = i * layout.lineHeight + layout.ascent;   // measured from the top of the view
        CGContextSetTextPosition(ctx, 0, height - baseline);
        [self drawLine:layout.lines[i] inContext:ctx];
    }
    CGContextRestoreGState(ctx);
}

@end
