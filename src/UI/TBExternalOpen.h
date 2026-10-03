#import <UIKit/UIKit.h>

// A share / "Open in…" action sheet for a web link: copy it, or open it in Safari or (when installed) Surfari, the
// iOS 6 browser of this family. Retains itself until the sheet is gone.
@interface TBExternalOpen : NSObject

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Just the browser chooser (no "copy"); used where a link is being opened rather than shared
+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Whether Surfari is installed (its URL scheme answers)
+ (BOOL)surfariAvailable;

@end
