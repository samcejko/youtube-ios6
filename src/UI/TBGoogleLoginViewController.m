#import "TBGoogleLoginViewController.h"
#import "TBAccount.h"
#import "TBTheme.h"
#import "TBUtils.h"
#import "TBCommon.h"
#import <QuartzCore/QuartzCore.h>

@interface TBGoogleLoginViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *qrContainer;
@property (nonatomic, strong) UIImageView *qrImageView;
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

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.scrollView];

    self.stepLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.stepLabel.backgroundColor = [UIColor clearColor];
    self.stepLabel.font = [UIFont systemFontOfSize:TBIsPad() ? 17 : 14];
    self.stepLabel.textColor = [t primaryTextColor];
    self.stepLabel.textAlignment = NSTextAlignmentCenter;
    self.stepLabel.numberOfLines = 0;
    self.stepLabel.text = L(@"Asking Google for a code…");
    [self.scrollView addSubview:self.stepLabel];

    self.qrContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.qrContainer.backgroundColor = [UIColor whiteColor];
    self.qrContainer.layer.cornerRadius = 8.0;
    self.qrContainer.layer.masksToBounds = YES;
    self.qrContainer.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
    self.qrContainer.layer.borderWidth = 1.0;
    self.qrContainer.hidden = YES;
    [self.scrollView addSubview:self.qrContainer];

    self.qrImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.qrImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.qrImageView.backgroundColor = [UIColor whiteColor];
    [self.qrContainer addSubview:self.qrImageView];

    self.urlLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.urlLabel.backgroundColor = [UIColor clearColor];
    self.urlLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 22 : 17];
    self.urlLabel.textColor = [t linkColor];
    self.urlLabel.textAlignment = NSTextAlignmentCenter;
    self.urlLabel.text = @"youtube.com/activate";
    [self.scrollView addSubview:self.urlLabel];

    self.codeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.codeLabel.backgroundColor = [UIColor clearColor];
    self.codeLabel.font = [UIFont boldSystemFontOfSize:TBIsPad() ? 44 : 30];
    self.codeLabel.textColor = [t primaryTextColor];
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.adjustsFontSizeToFitWidth = YES;
    [self.scrollView addSubview:self.codeLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.font = [UIFont systemFontOfSize:TBIsPad() ? 15 : 13];
    self.statusLabel.textColor = [t secondaryTextColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [self.scrollView addSubview:self.statusLabel];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[t spinnerStyle]];
    self.spinner.hidesWhenStopped = YES;
    [self.scrollView addSubview:self.spinner];

    self.retryButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.retryButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.retryButton setTitle:L(@"Try Again") forState:UIControlStateNormal];
    [self.retryButton setTitleColor:[t primaryTextColor] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:NO] forState:UIControlStateNormal];
    [self.retryButton setBackgroundImage:[t buttonImageHighlighted:YES] forState:UIControlStateHighlighted];
    [self.retryButton addTarget:self action:@selector(start) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton.hidden = YES;
    [self.scrollView addSubview:self.retryButton];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(cancelTapped)];
    [self start];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.task cancel];
    self.task = nil;
}

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    CGRect b = self.view.bounds;
    self.scrollView.frame = b;

    CGFloat w = MIN(b.size.width - 32, TBIsPad() ? 520 : 300);
    CGFloat x = floor((b.size.width - w) / 2);

    BOOL hasQR = (!self.qrContainer.hidden && self.qrImageView.image != nil);
    CGFloat qrSize = TBIsPad() ? 200 : (b.size.height >= 500 ? 150 : 120);

    CGFloat y = TBIsPad() ? 24 : 12;

    // 1. stepLabel
    CGFloat stepH = [self.stepLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height;
    if (stepH < 20) stepH = 20;
    self.stepLabel.frame = CGRectMake(x, y, w, stepH);
    y += stepH + (TBIsPad() ? 14 : 8);

    // 2. qrContainer
    if (hasQR) {
        CGFloat qx = floor((b.size.width - qrSize) / 2);
        self.qrContainer.frame = CGRectMake(qx, y, qrSize, qrSize);
        self.qrImageView.frame = CGRectInset(self.qrContainer.bounds, 6, 6);
        y += qrSize + (TBIsPad() ? 14 : 8);
    } else {
        self.qrContainer.frame = CGRectZero;
        self.qrImageView.frame = CGRectZero;
    }

    // 3. urlLabel
    self.urlLabel.frame = CGRectMake(x, y, w, TBIsPad() ? 28 : 22);
    y += self.urlLabel.frame.size.height + (TBIsPad() ? 6 : 4);

    // 4. codeLabel
    self.codeLabel.frame = CGRectMake(x, y, w, TBIsPad() ? 50 : 36);
    y += self.codeLabel.frame.size.height + (TBIsPad() ? 10 : 6);

    // 5. spinner
    self.spinner.center = CGPointMake(floor(b.size.width / 2), y + 12);
    y += 24;

    // 6. statusLabel
    CGFloat statusH = [self.statusLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height;
    if (statusH < 20) statusH = 20;
    self.statusLabel.frame = CGRectMake(x, y, w, statusH);
    y += statusH + (TBIsPad() ? 14 : 8);

    // 7. retryButton
    self.retryButton.frame = CGRectMake(floor((b.size.width - 150) / 2), y, 150, 36);
    if (!self.retryButton.hidden) {
        y += 36 + 16;
    } else {
        y += 16;
    }

    self.scrollView.contentSize = CGSizeMake(b.size.width, y);
}

- (void)start
{
    [self.task cancel];
    self.retryButton.hidden = YES;
    self.qrContainer.hidden = YES;
    self.qrImageView.image = nil;
    self.codeLabel.text = @"";
    self.urlLabel.text = @"";
    self.stepLabel.text = L(@"Asking Google for a code…");
    self.statusLabel.text = @"";
    [self.spinner startAnimating];
    [self.view setNeedsLayout];

    __weak TBGoogleLoginViewController *weakSelf = self;
    self.task = [[TBAccount shared] signInWithCodeHandler:^(NSString *userCode, NSString *verificationURL, UIImage *qrImage) {
        TBGoogleLoginViewController *s = weakSelf;
        if (!s) return;
        s.codeLabel.text = userCode;
        NSString *shown = [verificationURL stringByReplacingOccurrencesOfString:@"https://www." withString:@""];
        s.urlLabel.text = [shown stringByReplacingOccurrencesOfString:@"https://" withString:@""];
        if (qrImage) {
            s.qrImageView.image = qrImage;
            s.qrContainer.hidden = NO;
            s.stepLabel.text = L(@"Scan the QR code with your phone, or open this address and enter the code:");
        } else {
            s.qrContainer.hidden = YES;
            s.qrImageView.image = nil;
            s.stepLabel.text = L(@"On a computer or phone, open this address and enter the code:");
        }
        s.statusLabel.text = L(@"Waiting for the confirmation… The code is good for a few minutes.");
        [s.view setNeedsLayout];
    } completion:^(NSError *error) {
        TBGoogleLoginViewController *s = weakSelf;
        if (!s) return;
        s.task = nil;
        [s.spinner stopAnimating];
        if (error) {
            s.statusLabel.text = error.localizedDescription;
            s.retryButton.hidden = NO;
            [s.view setNeedsLayout];
            return;
        }
        s.qrContainer.hidden = YES;
        s.statusLabel.text = L(@"Signed in. Your subscriptions are being fetched.");
        s.codeLabel.text = @"✓";
        [s.view setNeedsLayout];
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
