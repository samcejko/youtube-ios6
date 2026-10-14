// TBModern.h - the iOS 6 app on iOS 7 and newer: the arm64 build for iOS 14-17 (rootless jailbreaks, TrollStore)
// and the armv7 build on 32-bit devices with iOS 7-10. It keeps the layout clear of the notch and the home indicator,
// draws the glossy iOS 6 bars that UIKit stopped drawing in iOS 7, presents modal screens full screen as iOS 6 did and
// keeps dark mode off. Every function here is a no-op on iOS 6, where UIKit does all of this itself.
//
// Shared by all of samcejko's iOS 6 apps (only the prefix differs): change it in every copy or in none.
#import <UIKit/UIKit.h>

// YES on iOS 7 or newer.
BOOL TBModernIOS(void);

// The first thing application:didFinishLaunchingWithOptions: does, before the window is made: the iOS 6 look of
// the bars (UIAppearance; the bars of defaultBarStyle, black or default blue), bordered bar buttons, the iOS 6 blue
// of switches, rounded grouped tables, full-screen modal presentation. Nothing happens on iOS 6.
void TBModernSetUp(UIBarStyle defaultBarStyle);
// The same without the bars' artwork, for an app that draws its bars itself (full-screen modals, rounded grouped
// tables, full-width separators only).
void TBModernSetUpWithoutSkin(void);

// An app's own bar artwork, set the way each iOS wants it (with the appearance objects iOS 13-15 need, or else the
// bar turns transparent at the top of a list). titleAttributes may be nil. No-ops on iOS 6.
void TBModernApplyNavigationBarBackground(UINavigationBar *bar, UIImage *image, NSDictionary *titleAttributes);
void TBModernApplyTabBarBackground(UITabBar *bar, UIImage *image);

// A scroll view that pages over the whole screen (a feed, a gallery): keeps iOS 11+ from adding the safe area
// to its insets, which would throw the paging off.
void TBModernKeepScrollViewInsets(UIScrollView *scrollView);

// A navigation controller whose Back button has logic of its own: turns the swipe-back gesture of iOS 7+ off.
void TBModernDisableSwipeBack(UINavigationController *nav);

// iOS 7 and newer ignore [UIApplication setStatusBarHidden:] / setStatusBarStyle: and ask the view controller
// (prefersStatusBarHidden, preferredStatusBarStyle) instead: tells it to ask again after a change.
void TBModernStatusBarChanged(UIViewController *vc);

// The part of a view covered by the notch, the home indicator or the rounded corners (iOS 11 and newer; zero
// before that and on iOS 6). Valid once the view is in a window and laid out, i.e. in layoutSubviews and
// viewDidLayoutSubviews - add .bottom to anything that sits on the bottom edge, .left/.right to anything that
// reaches the side edges in landscape, .top to views that start at the top of the screen without a navigation bar.
UIEdgeInsets TBSafeAreaInsets(UIView *view);
// The same for the whole screen (the key window), for code that runs before a view is laid out.
UIEdgeInsets TBScreenSafeAreaInsets(void);

// How far from the top of a full-screen view (one that lies under the status bar) the content starts: the iOS 6
// value given (20 for a status bar the app shows, 0 for a hidden one), the height of the status bar on iOS 7-10,
// the safe area (notch) on iOS 11 and newer.
CGFloat TBModernTopInset(UIView *view, CGFloat ios6Value);

// The horizontal space grouped table cells lose to their margins: the iOS 6 value given (20 on iPhone, 90 on iPad
// for both sides together), 0 on iOS 7-12 (full-width cells), 40 on iOS 13 and newer (the inset groups).
CGFloat TBModernGroupedCellMargins(CGFloat ios6Margins);

// The glossy iOS 6 look of one bar, on iOS 7 and newer (the bar's barStyle decides between blue and black).
// Call after the app's own styling (barStyle, translucent, tintColor); no-ops on iOS 6.
void TBModernStyleNavigationBar(UINavigationBar *bar);
void TBModernStyleToolbar(UIToolbar *bar);
void TBModernStyleSearchBar(UISearchBar *bar);
void TBModernStyleTabBar(UITabBar *bar);

// The status bar style to ask for: on iOS 7 and newer the status bar lies over the (always dark) bar, so its text
// has to be light whatever the iOS 6 style would have been; on iOS 6 the given style is returned unchanged.
UIStatusBarStyle TBModernStatusBarStyle(UIStatusBarStyle ios6Style);

// iOS 8 and newer show local notifications only after the user allowed them: asks once (iOS 6 and 7 need nothing).
void TBModernRequestNotificationPermission(void);
