#import "TBExternalOpen.h"
#import "TBUtils.h"
#import "TBCommon.h"

@interface TBExternalOpen () <UIActionSheetDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic) BOOL hasCopy;
@property (nonatomic) BOOL hasSurfari;
@end

// The live sheets' delegates, so ARC does not free them while the sheet is on screen
static NSMutableArray *g_live;

@implementation TBExternalOpen

+ (BOOL)surfariAvailable
{
    return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"surfari://open?url=https://youtube.com/"]];
}

+ (NSURL *)surfariURLForURL:(NSURL *)url
{
    NSString *encoded = [TBUtils urlEncode:url.absoluteString ?: @""];
    return [NSURL URLWithString:[@"surfari://open?url=" stringByAppendingString:encoded]];
}

+ (void)presentShareSheetForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url copy:YES from:controller anchor:anchor];
}

+ (void)presentOpenInForURL:(NSURL *)url from:(UIViewController *)controller anchor:(UIView *)anchor
{
    [self present:url copy:NO from:controller anchor:anchor];
}

+ (void)present:(NSURL *)url copy:(BOOL)copy from:(UIViewController *)controller anchor:(UIView *)anchor
{
    if (!url || ![[url.scheme lowercaseString] hasPrefix:@"http"]) return;
    TBExternalOpen *open = [[TBExternalOpen alloc] init];
    open.url = url;
    open.hasCopy = copy;
    open.hasSurfari = [self surfariAvailable];
    if (!g_live) g_live = [NSMutableArray array];
    [g_live addObject:open];

    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:url.absoluteString delegate:open cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (copy) [sheet addButtonWithTitle:L(@"Copy link")];
    [sheet addButtonWithTitle:L(@"Open in Safari")];
    if (open.hasSurfari) [sheet addButtonWithTitle:L(@"Open in Surfari")];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:L(@"Cancel")];
    UIView *host = controller.view;
    if (TBIsPad() && anchor) [sheet showFromRect:anchor.bounds inView:anchor animated:YES];
    else [sheet showInView:host];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != actionSheet.cancelButtonIndex && buttonIndex >= 0) {
        NSInteger index = buttonIndex;
        if (self.hasCopy) {
            if (index == 0) { [UIPasteboard generalPasteboard].string = self.url.absoluteString; index = -100; }
            else index -= 1;   // (shift past "Copy link")
        }
        if (index == 0) {
            [[UIApplication sharedApplication] openURL:self.url];
        } else if (index == 1 && self.hasSurfari) {
            [[UIApplication sharedApplication] openURL:[TBExternalOpen surfariURLForURL:self.url]];
        }
    }
    [g_live removeObject:self];
}

@end
