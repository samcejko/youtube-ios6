#import "TBRefreshControl.h"

@interface TBRefreshControl ()
@property(nonatomic, readwrite, getter=isRefreshing) BOOL refreshing;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, weak) UIScrollView *scrollView;
@property(nonatomic) CGFloat addedInset;
@end

@implementation TBRefreshControl
- (instancetype)init
{
    self = [super initWithFrame:CGRectMake(0, -54, 320, 54)];
    if (self) {
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.userInteractionEnabled = NO;
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        _spinner.hidesWhenStopped = NO;
        _spinner.alpha = 0;
        [self addSubview:_spinner];
    }
    return self;
}
- (void)setTintColor:(UIColor *)tintColor
{
    _tintColor = tintColor;
    self.spinner.activityIndicatorViewStyle = tintColor ? UIActivityIndicatorViewStyleWhite : UIActivityIndicatorViewStyleGray;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    self.spinner.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}
- (void)trackScrollView:(UIScrollView *)scrollView released:(BOOL)released
{
    self.scrollView = scrollView;
    CGFloat originalTop = scrollView.contentInset.top - self.addedInset;
    self.frame = CGRectMake(0, -originalTop - 54, scrollView.bounds.size.width, 54);
    if (self.refreshing) return;
    CGFloat pull = -scrollView.contentOffset.y - originalTop;
    self.spinner.alpha = MIN(1, MAX(0, pull / 60));
    if (released && pull >= 60) {
        self.refreshing = YES;
        self.addedInset = 54;
        [self.spinner startAnimating];
        UIEdgeInsets inset = scrollView.contentInset;
        inset.top += self.addedInset;
        scrollView.contentInset = inset;
        [self sendActionsForControlEvents:UIControlEventValueChanged];
    }
}
- (void)endRefreshing
{
    if (self.addedInset) {
        UIEdgeInsets inset = self.scrollView.contentInset;
        inset.top -= self.addedInset;
        self.addedInset = 0;
        self.scrollView.contentInset = inset;
    }
    self.refreshing = NO;
    [self.spinner stopAnimating];
    self.spinner.alpha = 0;
}
@end
