// Shared macros and constants. Everything here must be iOS 6.0 safe.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Any API newer than the iOS 6.0 deployment target is a hard error in files that include this header.
#pragma clang diagnostic error "-Wunguarded-availability"

#define L(key) NSLocalizedString((key), nil)
#define TBIsPad() (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
#define TBLog(fmt, ...) NSLog((@"[Tubie] " fmt), ##__VA_ARGS__)

// Runs a block on the main thread (immediately if already there).
static inline void TBMain(dispatch_block_t block)
{
    if ([NSThread isMainThread]) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

extern NSString * const TBErrorDomain;
extern NSString * const TBThemeDidChangeNotification;
extern NSString * const TBSettingsDidChangeNotification;
extern NSString * const TBLibraryDidChangeNotification;     // subscriptions, history or watch later changed

// NSError codes in TBErrorDomain (HTTP errors use the HTTP status as code)
enum {
    TBErrorNetwork        = -1,
    TBErrorTLS            = -2,
    TBErrorCertificate    = -3,
    TBErrorTimeout        = -4,
    TBErrorCancelled      = -5,
    TBErrorBadResponse    = -6,
    TBErrorDNS            = -7,
    TBErrorConnect        = -8,
    TBErrorConnectionLost = -9,
    TBErrorAPI            = -10,   // YouTube answered, but with an error
    TBErrorOffline        = -11,   // the live stream has not started
    TBErrorAuth           = -12,   // a signed-in viewer is required (age restriction)
    TBErrorRestricted     = -13,   // private, blocked in this country...
};

NSError *TBMakeError(NSInteger code, NSString *message);

// JSON values as the type the caller expects, nil/0 for anything else (NSNull, wrong type)
NSString *TBStr(id value);         // numbers become their decimal string
NSDictionary *TBDict(id value);
NSArray *TBArr(id value);
NSInteger TBInt(id value);
double TBDbl(id value);
BOOL TBBool(id value);

// "2026-10-02T17:31:00Z" and "2026-10-02T17:31:05.042684Z"
NSDate *TBDateFromISO(NSString *string);
