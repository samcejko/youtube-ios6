#import <UIKit/UIKit.h>
#import "TBModels.h"

// A block of text whose web addresses and channel mentions are tappable links, drawn in the link colour: the
// description of a video, a comment, a channel's description. The text is laid out and drawn with Core Text (iOS 6
// has no TextKit), so a tap is matched to the link under the finger exactly; a touch anywhere else never reaches
// this view (hitTest says so), so the table row underneath keeps selecting and expanding as before.
//
// The links are those YouTube marked (TBTextLink, carrying the real targets behind shortened addresses and
// "@handle" mentions) plus the addresses written in the text itself (NSDataDetector).
@interface TBLinkLabel : UIView

@property (nonatomic, strong) UIFont *font;                 // default: the system font, 14 pt
@property (nonatomic, strong) UIColor *textColor;           // default: black
@property (nonatomic, strong) UIColor *linkColor;           // default: the iOS 6 link blue
@property (nonatomic) NSInteger numberOfLines;              // 0 = every line (default); else the last one ends with …
@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, strong, readonly) NSArray *links;     // TBTextLink, in the text's coordinates
// A tapped link; the label is handed over as the anchor for a sheet
@property (nonatomic, copy) void (^onLink)(NSString *url, TBLinkLabel *label);

// The text and the links YouTube marked in it (may be nil: addresses written in the text are found anyway)
- (void)setText:(NSString *)text knownLinks:(NSArray *)knownLinks;

// The height the text takes at this width (maxLines 0 = every line): the very layout the label draws
+ (CGFloat)heightForText:(NSString *)text font:(UIFont *)font width:(CGFloat)width maxLines:(NSInteger)maxLines;
// The links of a text (TBTextLink, sorted): YouTube's marks, then the addresses written where they do not overlap
+ (NSArray *)linksInText:(NSString *)text knownLinks:(NSArray *)knownLinks;

@end
