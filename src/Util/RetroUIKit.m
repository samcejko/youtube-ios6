#import "RetroUIKit.h"
#import <QuartzCore/QuartzCore.h>

static BOOL RetroModern(void) { return [[[UIDevice currentDevice] systemVersion] integerValue] >= 7; }
static NSMutableArray *RetroPresented;
static void RetroHold(id object) { if (!RetroPresented) RetroPresented = [NSMutableArray array]; [RetroPresented addObject:object]; }
static void RetroRelease(id object) { [RetroPresented removeObject:object]; }
static void RetroGradient(CGRect rect, UIColor *top, UIColor *bottom) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)@[(id)top.CGColor,(id)bottom.CGColor], NULL);
    CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(),gradient,rect.origin,CGPointMake(rect.origin.x,CGRectGetMaxY(rect)),0);
    CGGradientRelease(gradient); CGColorSpaceRelease(space);
}
static UIImage *RetroGloss(UIColor *top, UIColor *bottom, CGFloat height) {
    CGSize size = CGSizeMake(25,height); UIGraphicsBeginImageContextWithOptions(size,NO,0);
    CGRect rect = CGRectInset((CGRect){CGPointZero,size},.5,.5);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:5];
    [path addClip]; RetroGradient(rect,top,bottom);
    [[UIColor colorWithWhite:1 alpha:.25] setFill]; CGContextFillRect(UIGraphicsGetCurrentContext(),CGRectMake(0,0,size.width,height*.46));
    [[UIColor colorWithWhite:0 alpha:.55] setStroke]; path.lineWidth=1; [path stroke];
    UIImage *result=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return [result stretchableImageWithLeftCapWidth:12 topCapHeight:(NSInteger)(height*.5)];
}
void RetroStyleButton(UIButton *button) {
    button.backgroundColor=[UIColor clearColor];
    [button setBackgroundImage:RetroGloss([UIColor colorWithRed:.29 green:.56 blue:.88 alpha:1],[UIColor colorWithRed:.05 green:.27 blue:.58 alpha:1],26) forState:UIControlStateNormal];
    button.titleLabel.shadowColor=[UIColor colorWithWhite:0 alpha:.55]; button.titleLabel.shadowOffset=CGSizeMake(0,-1);
}
UIColor *RetroGroupedBackground(void) {
    if (!RetroModern()) return [UIColor groupTableViewBackgroundColor];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(6,6),YES,1);
    [[UIColor colorWithRed:197./255 green:204./255 blue:212./255 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,6,6));
    [[UIColor colorWithRed:202./255 green:209./255 blue:217./255 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,1,6));
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return [UIColor colorWithPatternImage:image];
}
UIView *RetroSectionHeader(NSString *title, CGFloat width) {
    if (!title.length) return nil;
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(16,0,width-32,30)];
    label.font=[UIFont boldSystemFontOfSize:17]; label.textColor=[UIColor colorWithRed:.30 green:.34 blue:.42 alpha:1];
    label.shadowColor=[UIColor whiteColor]; label.shadowOffset=CGSizeMake(0,1); label.backgroundColor=[UIColor clearColor];label.text=title;
    UIView *view=[[UIView alloc] initWithFrame:CGRectMake(0,0,width,30)]; [view addSubview:label]; return view;
}

@interface RetroSwitch : UISwitch { UIImageView *_skin; }
@end
@implementation RetroSwitch
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:CGRectMake(frame.origin.x,frame.origin.y,79,27)];
    if (self) { self.bounds=CGRectMake(0,0,79,27); _skin=[[UIImageView alloc] initWithFrame:self.bounds];_skin.userInteractionEnabled=NO;[self addSubview:_skin];for (UIGestureRecognizer *gesture in self.gestureRecognizers) gesture.enabled=NO;[self setNeedsLayout]; }
    return self;
}
- (CGSize)sizeThatFits:(CGSize)size { return CGSizeMake(79,27); }
- (CGSize)intrinsicContentSize { return CGSizeMake(79,27); }
- (void)layoutSubviews {
    [super layoutSubviews];
    for (UIView *view in self.subviews) if (view!=_skin) view.hidden=YES;
    _skin.frame=self.bounds;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(79,27),NO,0);
    UIBezierPath *track=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(.5,.5,78,26) cornerRadius:13];[track addClip];
    RetroGradient(CGRectMake(0,0,79,27),self.on?[UIColor colorWithRed:.02 green:.26 blue:.60 alpha:1]:[UIColor colorWithWhite:.56 alpha:1],self.on?[UIColor colorWithRed:.25 green:.64 blue:1 alpha:1]:[UIColor colorWithWhite:.94 alpha:1]);
    [[UIColor colorWithWhite:0 alpha:.4] setStroke];track.lineWidth=1;[track stroke];
    NSString *text=self.on?@"I":@"O";
    UIColor *foreground=self.on?[UIColor whiteColor]:[UIColor colorWithWhite:.45 alpha:1]; [foreground setFill];
    [text drawInRect:CGRectMake(self.on?14:45,4,22,21) withFont:[UIFont boldSystemFontOfSize:17] lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentCenter];
    CGRect knob=CGRectMake(self.on?53:1,1,25,25);
    CGContextSaveGState(UIGraphicsGetCurrentContext()); UIBezierPath *handle=[UIBezierPath bezierPathWithRoundedRect:knob cornerRadius:12.5];[handle addClip];
    RetroGradient(knob,[UIColor whiteColor],[UIColor colorWithWhite:.78 alpha:1]);CGContextRestoreGState(UIGraphicsGetCurrentContext());
    [[UIColor colorWithWhite:.35 alpha:1] setStroke];handle.lineWidth=.6;[handle stroke];
    _skin.image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();
}
- (void)setOn:(BOOL)on { [super setOn:on animated:NO];[self setNeedsLayout]; }
- (void)setOn:(BOOL)on animated:(BOOL)animated { [super setOn:on animated:NO];[self setNeedsLayout]; }
- (BOOL)accessibilityActivate {
    if (!self.enabled) return NO;
    [self setOn:!self.on animated:YES]; [self sendActionsForControlEvents:UIControlEventValueChanged]; return YES;
}
// UISwitch's private gesture recognizers otherwise intercept the old control tracking callbacks.
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (self.enabled && CGRectContainsPoint(self.bounds,[touch locationInView:self])) [self accessibilityActivate];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (CGRectContainsPoint(self.bounds,[touch locationInView:self])) { [self setOn:!self.on animated:YES];[self sendActionsForControlEvents:UIControlEventValueChanged]; }
}
@end
UISwitch *RetroMakeSwitch(void) { return RetroModern()?[[RetroSwitch alloc] initWithFrame:CGRectZero]:[[UISwitch alloc] init]; }

static UIButton *RetroButton(NSString *title, NSInteger index, BOOL destructive, id target, SEL action) {
    UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.tag=index;
    [button setTitle:title forState:UIControlStateNormal];[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font=[UIFont boldSystemFontOfSize:17];button.titleLabel.shadowColor=[UIColor colorWithWhite:0 alpha:.65];button.titleLabel.shadowOffset=CGSizeMake(0,-1);
    UIColor *top=destructive?[UIColor colorWithRed:.85 green:.2 blue:.2 alpha:1]:[UIColor colorWithRed:.46 green:.57 blue:.72 alpha:1];
    UIColor *bottom=destructive?[UIColor colorWithRed:.55 green:.02 blue:.02 alpha:1]:[UIColor colorWithRed:.22 green:.34 blue:.52 alpha:1];
    [button setBackgroundImage:RetroGloss(top,bottom,42) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
static UILabel *RetroTitle(NSString *text, CGFloat width, CGFloat height) {
    UILabel *label=[[UILabel alloc] initWithFrame:CGRectMake(12,10,width-24,height)];label.text=text;label.font=[UIFont boldSystemFontOfSize:18];
    label.textAlignment=UITextAlignmentCenter;label.numberOfLines=2;label.textColor=[UIColor whiteColor];label.backgroundColor=[UIColor clearColor];label.shadowColor=[UIColor blackColor];label.shadowOffset=CGSizeMake(0,-1);return label;
}
static UIView *RetroOverlay(void) {
    UIWindow *window=[UIApplication sharedApplication].keyWindow;
    UIView *overlay=[[UIView alloc] initWithFrame:window.bounds];overlay.accessibilityIdentifier=@"TubieClassicPopup";overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;overlay.backgroundColor=[UIColor colorWithWhite:0 alpha:.45];[window addSubview:overlay];return overlay;
}
@interface RetroAlertView () { UIView *_retroOverlay; }
@end
@implementation RetroAlertView
- (BOOL)isVisible { return RetroModern()?(_retroOverlay!=nil):[super isVisible]; }
- (void)show {
    if (!RetroModern()) { [super show];return; }
    if (_retroOverlay) return;RetroHold(self);_retroOverlay=RetroOverlay();
    CGFloat width=MIN(320,_retroOverlay.bounds.size.width-40);
    CGFloat textHeight=[self.message sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(width-28,CGFLOAT_MAX) lineBreakMode:UILineBreakModeWordWrap].height+12;
    CGFloat messageHeight=MIN(180,textHeight);
    CGFloat height=58+messageHeight+MAX(1,self.numberOfButtons)*48;
    UIView *panel=[[UIView alloc] initWithFrame:CGRectMake((_retroOverlay.bounds.size.width-width)*.5,(_retroOverlay.bounds.size.height-height)*.5,width,height)];
    panel.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    panel.backgroundColor=[UIColor colorWithRed:.23 green:.29 blue:.40 alpha:1];panel.layer.cornerRadius=11;panel.layer.borderWidth=2;panel.layer.borderColor=[UIColor colorWithWhite:.8 alpha:1].CGColor;[_retroOverlay addSubview:panel];
    [panel addSubview:RetroTitle(self.title,width,36)];
    UIScrollView *messageScroll=[[UIScrollView alloc] initWithFrame:CGRectMake(14,48,width-28,messageHeight)];
    messageScroll.contentSize=CGSizeMake(width-28,textHeight);[panel addSubview:messageScroll];
    UILabel *message=RetroTitle(self.message,width,textHeight);message.frame=CGRectMake(0,0,width-28,textHeight);message.font=[UIFont systemFontOfSize:15];message.numberOfLines=0;[messageScroll addSubview:message];
    for (NSInteger i=0;i<self.numberOfButtons;i++) { UIButton *button=RetroButton([self buttonTitleAtIndex:i],i,NO,self,@selector(retroPressed:));button.frame=CGRectMake(10,52+messageHeight+i*48,width-20,42);[panel addSubview:button]; }
    if ([self.delegate respondsToSelector:@selector(didPresentAlertView:)]) [self.delegate didPresentAlertView:self];
}
- (void)retroPressed:(UIButton *)button {
    if ([self.delegate respondsToSelector:@selector(alertView:clickedButtonAtIndex:)]) [self.delegate alertView:self clickedButtonAtIndex:button.tag];
    [self dismissWithClickedButtonIndex:button.tag animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    if (!RetroModern()) { [super dismissWithClickedButtonIndex:index animated:animated];return; }
    if (!_retroOverlay)return;
    if ([self.delegate respondsToSelector:@selector(alertView:willDismissWithButtonIndex:)]) [self.delegate alertView:self willDismissWithButtonIndex:index];
    [_retroOverlay removeFromSuperview];_retroOverlay=nil;
    if ([self.delegate respondsToSelector:@selector(alertView:didDismissWithButtonIndex:)]) [self.delegate alertView:self didDismissWithButtonIndex:index];
    RetroRelease(self);
}
@end
@interface RetroActionSheet () { UIView *_retroOverlay; }
@end
@implementation RetroActionSheet
- (BOOL)isVisible { return RetroModern()?(_retroOverlay!=nil):[super isVisible]; }
- (void)retroShow {
    if (_retroOverlay)return;RetroHold(self);_retroOverlay=RetroOverlay();
    CGFloat width=MIN(460,_retroOverlay.bounds.size.width-20), height=MIN(_retroOverlay.bounds.size.height-80,64+self.numberOfButtons*49);
    CGFloat bottom=20;
    UIScrollView *panel=[[UIScrollView alloc] initWithFrame:CGRectMake((_retroOverlay.bounds.size.width-width)*.5,_retroOverlay.bounds.size.height-height-bottom,width,height)];
    panel.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin;
    panel.backgroundColor=[UIColor colorWithWhite:.28 alpha:1];panel.layer.cornerRadius=9;panel.layer.borderWidth=1;panel.layer.borderColor=[UIColor colorWithWhite:.75 alpha:1].CGColor;panel.contentSize=CGSizeMake(width,54+self.numberOfButtons*49);[_retroOverlay addSubview:panel];
    [panel addSubview:RetroTitle(self.title,width,32)];
    for (NSInteger i=0;i<self.numberOfButtons;i++) { UIButton *button=RetroButton([self buttonTitleAtIndex:i],i,i==self.destructiveButtonIndex,self,@selector(retroPressed:));button.frame=CGRectMake(9,48+i*49,width-18,42);[panel addSubview:button]; }
    if ([self.delegate respondsToSelector:@selector(didPresentActionSheet:)]) [self.delegate didPresentActionSheet:self];
}
- (void)showInView:(UIView *)view { if (!RetroModern()) [super showInView:view];else [self retroShow]; }
- (void)showFromBarButtonItem:(UIBarButtonItem *)item animated:(BOOL)animated { if (!RetroModern()) [super showFromBarButtonItem:item animated:animated];else [self retroShow]; }
- (void)showFromRect:(CGRect)rect inView:(UIView *)view animated:(BOOL)animated { if (!RetroModern()) [super showFromRect:rect inView:view animated:animated];else [self retroShow]; }
- (void)showFromToolbar:(UIToolbar *)toolbar { if (!RetroModern()) [super showFromToolbar:toolbar];else [self retroShow]; }
- (void)showFromTabBar:(UITabBar *)tabBar { if (!RetroModern()) [super showFromTabBar:tabBar];else [self retroShow]; }
- (void)retroPressed:(UIButton *)button {
    if ([self.delegate respondsToSelector:@selector(actionSheet:clickedButtonAtIndex:)]) [self.delegate actionSheet:self clickedButtonAtIndex:button.tag];
    [self dismissWithClickedButtonIndex:button.tag animated:YES];
}
- (void)dismissWithClickedButtonIndex:(NSInteger)index animated:(BOOL)animated {
    if (!RetroModern()) { [super dismissWithClickedButtonIndex:index animated:animated];return; }
    if (!_retroOverlay)return;
    if ([self.delegate respondsToSelector:@selector(actionSheet:willDismissWithButtonIndex:)]) [self.delegate actionSheet:self willDismissWithButtonIndex:index];
    [_retroOverlay removeFromSuperview];_retroOverlay=nil;
    if ([self.delegate respondsToSelector:@selector(actionSheet:didDismissWithButtonIndex:)]) [self.delegate actionSheet:self didDismissWithButtonIndex:index];
    RetroRelease(self);
}
@end
