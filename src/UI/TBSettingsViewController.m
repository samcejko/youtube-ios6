#import "TBSettingsViewController.h"
#import "TBChoiceViewController.h"
#import "TBGoogleLoginViewController.h"
#import "TBAccount.h"
#import "TBExtras.h"
#import "TBLibrary.h"
#import "TBSettings.h"
#import "TBTheme.h"
#import "TBTLSSocket.h"
#import "TBHTTP.h"
#import "TBImageLoader.h"
#import "TBUtils.h"
#import "TBCommon.h"

typedef NS_ENUM(NSInteger, TBSettingsSection) {
    TBSectionAccount = 0,
    TBSectionAppearance,
    TBSectionPlayback,
    TBSectionSponsorBlock,
    TBSectionCaptions,
    TBSectionContent,
    TBSectionPrivacy,
    TBSectionAdvanced,
    TBSectionAbout,
    TBSectionCount,
};

// Several options with checkmarks (the SponsorBlock categories)
@interface TBMultiChoiceViewController : UITableViewController
@property (nonatomic, strong) NSArray *keys;
@property (nonatomic, strong) NSArray *titles;
@property (nonatomic, strong) NSMutableSet *selected;
@property (nonatomic, copy) void (^completion)(NSArray *selectedKeys);
@end

@implementation TBMultiChoiceViewController
- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToTableView:self.tableView];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *key in self.keys) if ([self.selected containsObject:key]) [result addObject:key];
    if (self.completion) self.completion(result);
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.keys.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    [[TBTheme shared] styleCell:cell];
    cell.textLabel.text = self.titles[(NSUInteger)indexPath.row];
    cell.accessoryType = [self.selected containsObject:self.keys[(NSUInteger)indexPath.row]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *key = self.keys[(NSUInteger)indexPath.row];
    if ([self.selected containsObject:key]) [self.selected removeObject:key]; else [self.selected addObject:key];
    [tableView reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
}
@end

@interface TBSettingsViewController () <UIAlertViewDelegate>
@property (nonatomic, copy) NSString *cacheSizeText;
@property (nonatomic, copy) NSString *connectionTestText;
@property (nonatomic, strong) TBHTTPTask *testTask;
@property (nonatomic) BOOL signInAfterSecret;   // the secret was asked for on the way to signing in
@end

@implementation TBSettingsViewController

- (instancetype)init
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) self.title = L(@"Settings");
    return self;
}

- (void)dealloc
{
    [_testTask cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TBThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(accountChanged) name:TBAccountDidChangeNotification object:nil];
}

- (void)accountChanged
{
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self applyTheme];
    __weak TBSettingsViewController *weakSelf = self;
    [[TBImageLoader shared] diskUsage:^(unsigned long long bytes) {
        weakSelf.cacheSizeText = [TBUtils formatFileSize:bytes];
        [weakSelf.tableView reloadData];
    }];
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    [t applyToTableView:self.tableView];
    [t applyToNavigationBar:self.navigationController.navigationBar];
    [self.tableView reloadData];
}

#pragma mark - Helpers

- (NSInteger)tagForSection:(NSInteger)section row:(NSInteger)row { return section * 100 + row; }

- (UISwitch *)switchOn:(BOOL)on tag:(NSInteger)tag
{
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.on = on;
    sw.tag = tag;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    return sw;
}

+ (NSArray *)qualityKeys { return @[ TBQualityAuto, @"1080", @"720", @"480", @"360", @"240", @"144" ]; }

+ (NSString *)qualityTitle:(NSString *)key
{
    if ([key isEqualToString:TBQualityAuto]) return L(@"Automatic");
    return [NSString stringWithFormat:@"%@p", key];
}

+ (NSArray *)languages
{
    return @[ @[@"cs", @"Čeština"], @[@"sk", @"Slovenčina"], @[@"en", @"English"], @[@"de", @"Deutsch"], @[@"pl", @"Polski"], @[@"es", @"Español"],
              @[@"fr", @"Français"], @[@"it", @"Italiano"], @[@"pt", @"Português"], @[@"ru", @"Русский"], @[@"uk", @"Українська"], @[@"tr", @"Türkçe"],
              @[@"ja", @"日本語"], @[@"ko", @"한국어"] ];
}

+ (NSArray *)regions
{
    return @[ @[@"CZ", @"Česko"], @[@"SK", @"Slovensko"], @[@"US", @"United States"], @[@"GB", @"United Kingdom"], @[@"DE", @"Deutschland"], @[@"AT", @"Österreich"],
              @[@"PL", @"Polska"], @[@"FR", @"France"], @[@"ES", @"España"], @[@"IT", @"Italia"], @[@"NL", @"Nederland"], @[@"SE", @"Sverige"],
              @[@"UA", @"Україна"], @[@"JP", @"日本"], @[@"KR", @"한국"], @[@"BR", @"Brasil"], @[@"CA", @"Canada"], @[@"AU", @"Australia"] ];
}

+ (NSString *)nameForCode:(NSString *)code in:(NSArray *)list
{
    for (NSArray *entry in list) if ([entry[0] caseInsensitiveCompare:code] == NSOrderedSame) return entry[1];
    return code;
}

#pragma mark - Table structure

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return TBSectionCount; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch ((TBSettingsSection)section) {
        case TBSectionAccount: return [[TBAccount shared] isSignedIn] ? 2 : 3;   // (signed out: sign in, client id, client secret)
        case TBSectionPlayback: return 5;
        case TBSectionSponsorBlock: return 2;
        case TBSectionCaptions: return 2;
        case TBSectionContent: return 2;
        case TBSectionPrivacy: return 3;
        case TBSectionAppearance: return 1;
        case TBSectionAdvanced: return 3;
        case TBSectionAbout: return 4;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch ((TBSettingsSection)section) {
        case TBSectionAccount: return L(@"Account");
        case TBSectionPlayback: return L(@"Playback");
        case TBSectionSponsorBlock: return @"SponsorBlock";
        case TBSectionCaptions: return L(@"Captions");
        case TBSectionContent: return L(@"Content");
        case TBSectionPrivacy: return L(@"Privacy");
        case TBSectionAppearance: return L(@"Appearance");
        case TBSectionAdvanced: return L(@"Advanced");
        case TBSectionAbout: return L(@"About");
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch ((TBSettingsSection)section) {
        case TBSectionAccount: return [[TBAccount shared] isSignedIn]
            ? L(@"Subscriptions and likes are linked to the account. The watch history and \"watch later\" stay on this device: YouTube's API does not offer them.")
            : L(@"Sign in with a code at google.com/device, as a TV does. Create your own Google OAuth client (a 5-minute setup; see the README) and enter its ID and secret, or sign in with the built-in client if you are one of its test users.");
        case TBSectionPlayback: return L(@"This device decodes H.264 up to 1080p at 30 frames per second; renditions beyond that are left out of \"Automatic\". \"MP4 only\" plays the plain 360p file instead of the adaptive stream.");
        case TBSectionSponsorBlock: return L(@"Skips the parts of videos the SponsorBlock community marked (sponsor.ajay.app).");
        case TBSectionContent: return L(@"The language of titles and the region of the explore pages, as YouTube offers them.");
        case TBSectionPrivacy: return L(@"Nothing is sent to Google beyond the requests of a visitor without an account. The history stays on this device. Dislike counts come from returnyoutubedislike.com.");
        case TBSectionAdvanced: return L(@"Turn certificate verification off only if the device clock is wrong or the certificate bundle is outdated.");
        default: return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == TBSectionAdvanced && indexPath.row == 2) return 56;
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TBTheme *t = [TBTheme shared];
    NSInteger sec = indexPath.section, row = indexPath.row;
    NSInteger tag = [self tagForSection:sec row:row];
    BOOL subtitle = sec == TBSectionAdvanced && row == 2;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:subtitle ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:subtitle ? 12 : 15];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    switch ((TBSettingsSection)sec) {
        case TBSectionAccount: {
            TBAccount *account = [TBAccount shared];
            if (account.isSignedIn) {
                if (row == 0) {
                    cell.textLabel.text = account.channelTitle.length ? account.channelTitle : L(@"Google account");
                    cell.detailTextLabel.text = account.handle ?: @"";
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                } else {
                    cell.textLabel.text = L(@"Sign out");
                    cell.textLabel.textColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:1];
                }
            } else if (row == 0) {
                cell.textLabel.text = L(@"Sign in with Google");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Google client ID");
                cell.detailTextLabel.text = [account usesOwnClientId] ? L(@"Set") : L(@"Default");
            } else {
                cell.textLabel.text = L(@"Google client secret");
                cell.detailTextLabel.text = [TBAccount isConfigured] ? L(@"Set") : L(@"Not set");
            }
            break;
        }
        case TBSectionPlayback:
            if (row == 0) {
                cell.textLabel.text = L(@"Quality");
                cell.detailTextLabel.text = [TBSettingsViewController qualityTitle:[TBSettings preferredQuality]];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Autoplay next video");
                cell.accessoryView = [self switchOn:[TBSettings autoplayNext] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 2) {
                cell.textLabel.text = L(@"Sound in background");
                cell.accessoryView = [self switchOn:[TBSettings backgroundAudio] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 3) {
                cell.textLabel.text = L(@"Keep screen on");
                cell.accessoryView = [self switchOn:[TBSettings keepScreenOn] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"MP4 only (360p)");
                cell.accessoryView = [self switchOn:[TBSettings progressiveOnly] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            break;
        case TBSectionSponsorBlock:
            if (row == 0) {
                cell.textLabel.text = L(@"Skip marked parts");
                cell.accessoryView = [self switchOn:[TBSettings sponsorBlock] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"Categories");
                NSArray *cats = [[NSUserDefaults standardUserDefaults] arrayForKey:@"sponsorBlockCategories"] ?: @[];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)cats.count];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        case TBSectionCaptions:
            if (row == 0) {
                cell.textLabel.text = L(@"Show captions");
                cell.accessoryView = [self switchOn:[TBSettings captionsEnabled] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"Caption language");
                NSString *lang = [TBSettings captionsLanguage];
                cell.detailTextLabel.text = lang.length ? [TBSettingsViewController nameForCode:lang in:[TBSettingsViewController languages]] : L(@"Device language");
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        case TBSectionContent:
            if (row == 0) {
                cell.textLabel.text = L(@"Language");
                cell.detailTextLabel.text = [TBSettingsViewController nameForCode:[TBSettings contentLanguage] in:[TBSettingsViewController languages]];
            } else {
                cell.textLabel.text = L(@"Region");
                cell.detailTextLabel.text = [TBSettingsViewController nameForCode:[TBSettings contentRegion] in:[TBSettingsViewController regions]];
            }
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case TBSectionPrivacy:
            if (row == 0) {
                cell.textLabel.text = L(@"Keep watch history");
                cell.accessoryView = [self switchOn:[TBSettings keepHistory] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Show dislikes");
                cell.accessoryView = [self switchOn:[TBSettings showDislikes] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = L(@"Clear history and searches");
                cell.textLabel.textColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:1];
            }
            break;
        case TBSectionAppearance: {
            cell.textLabel.text = L(@"Theme");
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[ L(@"Light"), L(@"Dark") ]];
            seg.segmentedControlStyle = UISegmentedControlStyleBar;
            seg.frame = CGRectMake(0, 0, TBIsPad() ? 200 : 150, 30);
            seg.selectedSegmentIndex = t.isDark ? 1 : 0;
            seg.tag = tag;
            [seg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case TBSectionAdvanced:
            if (row == 0) {
                cell.textLabel.text = L(@"Verify certificates");
                cell.accessoryView = [self switchOn:[TBSettings verifyTLS] tag:tag];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else if (row == 1) {
                cell.textLabel.text = L(@"Clear image cache");
                cell.detailTextLabel.text = self.cacheSizeText ?: @"";
            } else {
                cell.textLabel.text = L(@"Connection test");
                cell.detailTextLabel.text = self.connectionTestText ?: L(@"Tap to test the connection to YouTube");
            }
            break;
        case TBSectionAbout:
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            if (row == 0) { cell.textLabel.text = L(@"Version"); cell.detailTextLabel.text = [TBUtils appVersion]; }
            else if (row == 1) { cell.textLabel.text = L(@"Author"); cell.detailTextLabel.text = @"samcejko"; }
            else if (row == 2) { cell.textLabel.text = L(@"Root certificates"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)[TBTLSSocket caCertificateCount]]; }
            else { cell.textLabel.text = L(@"Device"); cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · iOS %@", [TBUtils deviceModel], [UIDevice currentDevice].systemVersion]; }
            break;
        default: break;
    }
    UIColor *keep = ((sec == TBSectionPrivacy && row == 2) || (sec == TBSectionAccount && row == 1 && [[TBAccount shared] isSignedIn])) ? cell.textLabel.textColor : nil;
    [t styleCell:cell];
    if (keep) cell.textLabel.textColor = keep;
    return cell;
}

#pragma mark - Account

- (void)askForClientSecret
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"Google client secret") message:L(@"Paste the client secret (GOCSPX-…)") delegate:self
                                          cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"OK"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.secureTextEntry = YES;
    alert.tag = 71;
    [alert show];
}

- (void)askForClientId
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"Google client ID") message:L(@"Paste the client ID (…apps.googleusercontent.com). Leave empty for the built-in one.") delegate:self
                                          cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"OK"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *field = [alert textFieldAtIndex:0];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.text = [[TBAccount shared] usesOwnClientId] ? [TBAccount shared].clientId : @"";
    alert.tag = 73;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag == 71) {
        if (buttonIndex == alertView.cancelButtonIndex) { self.signInAfterSecret = NO; return; }
        [TBAccount shared].clientSecret = [alertView textFieldAtIndex:0].text;
        [self.tableView reloadData];
        if (self.signInAfterSecret && [TBAccount isConfigured]) {
            self.signInAfterSecret = NO;
            [self.navigationController pushViewController:[[TBGoogleLoginViewController alloc] init] animated:YES];
        }
    } else if (alertView.tag == 73) {
        if (buttonIndex == alertView.cancelButtonIndex) return;
        [TBAccount shared].clientId = [alertView textFieldAtIndex:0].text;
        [self.tableView reloadData];
    } else if (alertView.tag == 72) {
        if (buttonIndex != alertView.cancelButtonIndex) [[TBAccount shared] signOut];
    }
}

#pragma mark - Controls

- (void)switchChanged:(UISwitch *)sw
{
    NSInteger sec = sw.tag / 100, row = sw.tag % 100;
    if (sec == TBSectionPlayback && row == 1) [TBSettings setAutoplayNext:sw.on];
    else if (sec == TBSectionPlayback && row == 2) [TBSettings setBackgroundAudio:sw.on];
    else if (sec == TBSectionPlayback && row == 3) [TBSettings setKeepScreenOn:sw.on];
    else if (sec == TBSectionPlayback && row == 4) [TBSettings setProgressiveOnly:sw.on];
    else if (sec == TBSectionSponsorBlock && row == 0) [TBSettings setSponsorBlock:sw.on];
    else if (sec == TBSectionCaptions && row == 0) [TBSettings setCaptionsEnabled:sw.on];
    else if (sec == TBSectionPrivacy && row == 0) [TBSettings setKeepHistory:sw.on];
    else if (sec == TBSectionPrivacy && row == 1) [TBSettings setShowDislikes:sw.on];
    else if (sec == TBSectionAdvanced && row == 0) [TBSettings setVerifyTLS:sw.on];
    [TBSettings save];
}

- (void)segmentChanged:(UISegmentedControl *)seg
{
    if (seg.tag / 100 == TBSectionAppearance) [[TBTheme shared] setDark:seg.selectedSegmentIndex == 1];
    [TBSettings save];
}

#pragma mark - Selection

- (void)pushChoiceWithTitle:(NSString *)title keys:(NSArray *)keys titles:(NSArray *)titles selected:(NSString *)selected completion:(void (^)(NSString *key))completion
{
    TBChoiceViewController *vc = [[TBChoiceViewController alloc] init];
    vc.title = title;
    vc.titles = titles;
    NSUInteger idx = NSNotFound;
    for (NSUInteger i = 0; i < keys.count; i++) if ([keys[i] caseInsensitiveCompare:selected ?: @""] == NSOrderedSame) { idx = i; break; }
    vc.selectedIndex = idx == NSNotFound ? 0 : (NSInteger)idx;
    vc.completion = ^(NSInteger index) {
        if (index >= 0 && index < (NSInteger)keys.count) completion(keys[(NSUInteger)index]);
        [TBSettings save];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger sec = indexPath.section, row = indexPath.row;
    if (sec == TBSectionAccount) {
        TBAccount *account = [TBAccount shared];
        if (account.isSignedIn) {
            if (row == 1) {
                UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"Sign out of the Google account?") message:nil delegate:self
                                                      cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Sign out"), nil];
                alert.tag = 72;
                [alert show];
            }
        } else if (row == 0) {
            if ([TBAccount isConfigured]) [self.navigationController pushViewController:[[TBGoogleLoginViewController alloc] init] animated:YES];
            else { self.signInAfterSecret = YES; [self askForClientSecret]; }
        } else if (row == 1) {
            [self askForClientId];
        } else {
            self.signInAfterSecret = NO;
            [self askForClientSecret];
        }
        return;
    }
    if (sec == TBSectionPlayback && row == 0) {
        NSArray *keys = [TBSettingsViewController qualityKeys];
        NSMutableArray *titles = [NSMutableArray array];
        for (NSString *k in keys) [titles addObject:[TBSettingsViewController qualityTitle:k]];
        [self pushChoiceWithTitle:L(@"Quality") keys:keys titles:titles selected:[TBSettings preferredQuality] completion:^(NSString *key) { [TBSettings setPreferredQuality:key]; }];
    } else if (sec == TBSectionSponsorBlock && row == 1) {
        TBMultiChoiceViewController *vc = [[TBMultiChoiceViewController alloc] init];
        vc.title = L(@"Categories");
        vc.keys = [TBSponsorBlock allCategories];
        NSMutableArray *titles = [NSMutableArray array];
        for (NSString *k in vc.keys) [titles addObject:[TBSponsorBlock titleForCategory:k]];
        vc.titles = titles;
        vc.selected = [NSMutableSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"sponsorBlockCategories"] ?: @[]];
        vc.completion = ^(NSArray *selectedKeys) { [TBSettings setSponsorBlockCategories:selectedKeys]; [TBSettings save]; };
        [self.navigationController pushViewController:vc animated:YES];
    } else if (sec == TBSectionCaptions && row == 1) {
        NSMutableArray *keys = [NSMutableArray arrayWithObject:@""];
        NSMutableArray *titles = [NSMutableArray arrayWithObject:L(@"Device language")];
        for (NSArray *l in [TBSettingsViewController languages]) { [keys addObject:l[0]]; [titles addObject:l[1]]; }
        [self pushChoiceWithTitle:L(@"Caption language") keys:keys titles:titles selected:[TBSettings captionsLanguage] completion:^(NSString *key) { [TBSettings setCaptionsLanguage:key]; }];
    } else if (sec == TBSectionContent) {
        NSArray *list = row == 0 ? [TBSettingsViewController languages] : [TBSettingsViewController regions];
        NSMutableArray *keys = [NSMutableArray array], *titles = [NSMutableArray array];
        for (NSArray *l in list) { [keys addObject:l[0]]; [titles addObject:l[1]]; }
        if (row == 0) [self pushChoiceWithTitle:L(@"Language") keys:keys titles:titles selected:[TBSettings contentLanguage] completion:^(NSString *key) { [TBSettings setContentLanguage:key]; }];
        else [self pushChoiceWithTitle:L(@"Region") keys:keys titles:titles selected:[TBSettings contentRegion] completion:^(NSString *key) { [TBSettings setContentRegion:key]; }];
    } else if (sec == TBSectionPrivacy && row == 2) {
        [[TBLibrary shared] clearHistory];
        [TBSettings clearRecentSearches];
        [TBUtils alertWithTitle:L(@"Cleared") message:L(@"The watch history and the recent searches are gone.")];
    } else if (sec == TBSectionAdvanced && row == 1) {
        __weak TBSettingsViewController *weakSelf = self;
        [[TBImageLoader shared] clearMemory];
        [[TBImageLoader shared] clearDiskWithCompletion:^{
            [[TBImageLoader shared] diskUsage:^(unsigned long long bytes) {
                weakSelf.cacheSizeText = [TBUtils formatFileSize:bytes];
                [weakSelf.tableView reloadData];
            }];
        }];
        self.cacheSizeText = L(@"Clearing…");
        [tableView reloadData];
    } else if (sec == TBSectionAdvanced && row == 2) {
        [self runConnectionTest];
    }
}

- (void)runConnectionTest
{
    if (self.testTask) return;
    self.connectionTestText = L(@"Testing…");
    [self.tableView reloadData];
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    __weak TBSettingsViewController *weakSelf = self;
    self.testTask = [TBHTTP get:@"https://www.youtube.com/generate_204" headers:nil completion:^(NSInteger status, NSData *body, NSDictionary *headers, NSError *error) {
        TBSettingsViewController *s = weakSelf;
        if (!s) return;
        s.testTask = nil;
        NSTimeInterval dt = [NSDate timeIntervalSinceReferenceDate] - started;
        s.connectionTestText = error ? error.localizedDescription : [NSString stringWithFormat:L(@"YouTube answered (HTTP %ld) in %.1f s"), (long)status, dt];
        [s.tableView reloadData];
    }];
}

@end
