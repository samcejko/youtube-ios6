#import <UIKit/UIKit.h>

// Opening and sharing a web link outside the app.
//
// iOS 6: an action sheet - "Open in Safari", "Open in Surfari" when that browser of this family is installed, and
// for sharing "Copy link" first. iOS 7 and newer (the arm64 build on iOS 14-17, the armv7 one on iOS 7-10): a link
// opens in Safari straight away and sharing is the system's share sheet (UIActivityViewController).
//
// On every iOS a link to twitch.tv, kick.com or tiktok.com offers "Open in Twitcher / Kicker / TikTak" first when
// that sister app is installed (their URL schemes answer canOpenURL:); on iOS 7+ that is the one case with a sheet.
// Retains itself until the sheet is gone.
@interface TBExternalOpen : NSObject

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Just opening (no "copy"); used where a link is being opened rather than shared
+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor;
// Whether Surfari is installed (its URL scheme answers)
+ (BOOL)surfariAvailable;
// The installed sister app a link belongs to ("Twitcher", "Kicker", "TikTak"), or nil
+ (NSString *)sisterAppNameForURL:(NSURL *)url;

@end
