#import "TBGoogleLoginViewController.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"

@interface TBGoogleLoginViewController ()
@property (nonatomic, strong) UILabel *stepLabel;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIButton *retryButton;
@property (nonatomic, strong) TBHTTPTask *task;
@end

@implementation TBGoogleLoginViewController

- (instancetype)init
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) self.title = L(@"Sign in with Google");
    return self;
}

- (void)dealloc
{
    [_task cancel];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    TBTheme *t = [TBTheme shared];
    self.view.backgroundColor = [t backgroundColor];

    self.stepLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.stepLabel.backgroundColor = [UIColor clearColor];
    self.stepLabel.font = [UIFont systemFontOfSize:TBIsPad() ? 18 : 15];
    self.stepLabel.textColor = [t primaryTextColor];
    self.stepLabel.textAlignment = NSTextAlignmentCenter;
    self.stepLabel.numberOfLines = 0;
    self.stepLabel.text = L(@"On a computer or phone, open this address and enter the code:");
    [self.view addSubview:self.stepLabel];

    self.urlLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.urlLabel.backgroundColor = [UIColor clearColor];
    self.urlLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 26 : 20];
    self.urlLabel.textColor = [t linkColor];
    self.urlLabel.textAlignment = NSTextAlignmentCenter;
    self.urlLabel.text = @"google.com/device";
    [self.view addSubview:self.urlLabel];

    self.codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.codeLabel.backgroundColor = [UIColor clearColor];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 52 : 36];
    self.codeLabel.textColor = [t primaryTextColor];
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:self.codeLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.font = [UIFont systemFontOfSize:TBIsPad() ? 16 : 14];
    self.statusLabel.textColor = [t secondaryTextColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self.view addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[t spinnerStyle]];
    self.spinner.hidesWhenStopped = YES;
    [self.view addSubview:self.spinner];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.retryButton setTitle:L(@"Try Again") forState:UIControlStateNormal];
    [self.retryButton setTitleColor:[t primaryTextColor] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:NO] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [self.retryButton addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.view addSubview:self.retryButton];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(cancelTapped)];
    [self start];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat w = MIN(b.size.width - 40, 560), x = floor((b.size.width - w) / 2);
    CGFloat y = floor(b.size.height * 0.12);
    self.stepLabel.frame = CGRectMake(x, y, w, 60);
    self.urlLabel.frame = CGRectMake(x, y + 66, w, 36);
    self.codeLabel.frame = CGRectMake(x, y + 120, w, 70);
    self.spinner.center = CGPointMake(b.size.width / 2, y + 215);
    self.statusLabel.frame = CGRectMake(x, y + 236, w, 60);
    self.retryButton.frame = CGRectMake(floor((b.size.width - 140) / 2), y + 306, 140, 36);
}

- (void)start
{
    [self.task cancel];
    self.retryButton.hidden = YES;
    self.codeLabel.text = @"";
    self.statusLabel.text = L(@"Asking Google for a code…");
    [self.spinner startAnimating];
    __weak TBGoogleLoginViewController *weakSelf = self;
    self.task = [[TBAccount shared] signInWithCodeHandler:^(NSString *userCode, NSString *verificationURL) {
        TBGoogleLoginViewController *s = weakSelf;
        s.codeLabel.text = userCode;
        NSString *shown = [verificationURL stringByReplacingOccurrencesOfString:@"https://www." withString:@""];
        s.urlLabel.text = [shown stringByReplacingOccurrencesOfString:@"https://" withString:@""];
        s.statusLabel.text = L(@"Waiting for the confirmation… The code is good for a few minutes.");
    } completion:^(NSError *error) {
        TBGoogleLoginViewController *s = weakSelf;
        if (!s) return;
        s.task = nil;
        [s.spinner stopAnimating];
        if (error) {
            s.statusLabel.text = error.localizedDescription;
            s.retryButton.hidden = NO;
            return;
        }
        s.statusLabel.text = L(@"Signed in. Your subscriptions are being fetched.");
        s.codeLabel.text = @"✓";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
    }];
}

- (void)cancelTapped
{
    [self.task cancel];
    self.task = nil;
    [self.navigationController popViewControllerAnimated:YES];
}

@end
