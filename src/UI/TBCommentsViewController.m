#import "TBCommentsViewController.h"
#import "TBCells.h"
#import "TBInnertube.h"
#import "TBAccount.h"
#import "TBNavigator.h"
#import "TBUtils.h"
#import "TBTheme.h"
#import "TBCommon.h"

@interface TBCommentsViewController () <UIAlertViewDelegate>
@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *nextToken;
@property (nonatomic, strong) NSMutableArray *comments;
@property (nonatomic, strong) TBHTTPTask *task;
@property (nonatomic, strong) TBHTTPTask *postTask;
@property (nonatomic) BOOL loading;
@property (nonatomic) BOOL loadedOnce;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIActivityIndicatorView *footerSpinner;
@end

@implementation TBCommentsViewController

- (instancetype)initWithToken:(NSString *)token title:(NSString *)title
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _token = [token copy];
        _comments = [NSMutableArray array];
        self.title = title ?: L(@"Comments");
    }
    return self;
}

- (void)dealloc
{
    [_task cancel];
    [_postTask cancel];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The account can write here: a top-level comment when this is a video's comments, a reply on a replies screen
- (BOOL)canPost
{
    return [[TBAccount shared] isSignedIn] && (self.videoId.length || self.replyParentId.length);
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.tableView registerClass:[TBCommentCell class] forCellReuseIdentifier:[TBCommentCell reuseIdentifier]];
    if ([self canPost]) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:(self.replyParentId.length ? L(@"Reply") : L(@"Add")) style:UIBarButtonItemStyleBordered target:self action:@selector(composeTapped)];
    }
    self.messageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.messageLabel.backgroundColor = [UIColor clearColor];
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.hidden = YES;
    [self.tableView addSubview:self.messageLabel];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.spinner.hidesWhenStopped = YES;
    [self.tableView addSubview:self.spinner];
    self.footerSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    self.footerSpinner.frame = CGRectMake(0, 0, 44, 44);
    self.footerSpinner.hidesWhenStopped = YES;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    [self.tableView.tableFooterView addSubview:self.footerSpinner];
    [self applyTheme];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:TBThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[TBTheme shared] applyToNavigationBar:self.navigationController.navigationBar];
    if (!self.loadedOnce && !self.loading) [self load];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect b = self.tableView.bounds;
    self.messageLabel.frame = CGRectMake(30, 60, b.size.width - 60, 80);
    self.spinner.center = CGPointMake(b.size.width / 2, 70);
    self.footerSpinner.center = CGPointMake(b.size.width / 2, 22);
}

- (void)applyTheme
{
    TBTheme *t = [TBTheme shared];
    [t applyToTableView:self.tableView];
    self.tableView.backgroundColor = [t cardColor];
    self.messageLabel.textColor = [t secondaryTextColor];
    self.spinner.activityIndicatorViewStyle = [t spinnerStyle];
    self.footerSpinner.activityIndicatorViewStyle = [t spinnerStyle];
    [self.tableView reloadData];
}

- (void)load
{
    if (!self.token.length) { self.messageLabel.text = L(@"Comments are turned off for this video."); self.messageLabel.hidden = NO; return; }
    self.loading = YES;
    [self.spinner startAnimating];
    __weak TBCommentsViewController *weakSelf = self;
    self.task = [TBInnertube comments:self.token completion:^(NSArray *comments, NSString *continuation, NSString *countText, NSError *error) {
        TBCommentsViewController *s = weakSelf;
        if (!s) return;
        s.loading = NO;
        s.loadedOnce = YES;
        s.task = nil;
        [s.spinner stopAnimating];
        if (error) { s.messageLabel.text = error.localizedDescription; s.messageLabel.hidden = NO; return; }
        [s.comments setArray:comments ?: @[]];
        s.nextToken = continuation;
        if (countText.length) s.title = [NSString stringWithFormat:@"%@ (%@)", L(@"Comments"), countText];
        [s.tableView reloadData];
        if (!s.comments.count) { s.messageLabel.text = L(@"No comments yet."); s.messageLabel.hidden = NO; }
    }];
}

- (void)loadMore
{
    if (self.loading || !self.nextToken.length) return;
    self.loading = YES;
    [self.footerSpinner startAnimating];
    __weak TBCommentsViewController *weakSelf = self;
    self.task = [TBInnertube comments:self.nextToken completion:^(NSArray *comments, NSString *continuation, NSString *countText, NSError *error) {
        TBCommentsViewController *s = weakSelf;
        if (!s) return;
        s.loading = NO;
        s.task = nil;
        [s.footerSpinner stopAnimating];
        if (error) { s.nextToken = nil; return; }
        NSMutableSet *known = [NSMutableSet set];
        for (id c in s.comments) [known addObject:[c valueForKey:@"commentId"] ?: @""];
        for (id c in comments) if (![known containsObject:[c valueForKey:@"commentId"] ?: @""]) [s.comments addObject:c];
        s.nextToken = comments.count ? continuation : nil;
        [s.tableView reloadData];
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.comments.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [TBCommentCell heightForComment:self.comments[(NSUInteger)indexPath.row] width:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    TBCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:[TBCommentCell reuseIdentifier] forIndexPath:indexPath];
    [cell configureWithComment:self.comments[(NSUInteger)indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    TBComment *comment = self.comments[(NSUInteger)indexPath.row];
    if (comment.repliesToken.length) {
        TBCommentsViewController *replies = [[TBCommentsViewController alloc] initWithToken:comment.repliesToken title:L(@"Replies")];
        replies.replyParentId = comment.commentId;   // (a signed-in account can reply here)
        [self.navigationController pushViewController:replies animated:YES];
    } else if (comment.authorChannelId.length) {
        [TBNavigator openChannelId:comment.authorChannelId from:self];
    }
}

#pragma mark - Posting

- (void)composeTapped
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:(self.replyParentId.length ? L(@"Reply") : L(@"Add a comment"))
                                                   message:nil delegate:self cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Post"), nil];
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    alert.tag = 90;
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (alertView.tag != 90 || buttonIndex == alertView.cancelButtonIndex) return;
    NSString *text = [[alertView textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    __weak TBCommentsViewController *weakSelf = self;
    void (^done)(TBComment *, NSError *) = ^(TBComment *comment, NSError *error) {
        TBCommentsViewController *s = weakSelf;
        if (!s) return;
        s.postTask = nil;
        if (error || !comment) { [TBUtils alertWithTitle:L(@"Comment") message:error.localizedDescription ?: L(@"The comment could not be posted.")]; return; }
        [s.comments insertObject:comment atIndex:0];
        s.messageLabel.hidden = YES;
        [s.tableView reloadData];
        [s.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:YES];
    };
    [self.postTask cancel];
    if (self.replyParentId.length) self.postTask = [[TBAccount shared] replyWithText:text toComment:self.replyParentId completion:done];
    else self.postTask = [[TBAccount shared] postComment:text onVideo:self.videoId completion:done];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.nextToken.length && !self.loading && indexPath.row >= (NSInteger)self.comments.count - 5) [self loadMore];
}

@end
