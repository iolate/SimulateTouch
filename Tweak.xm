#import <CoreGraphics/CoreGraphics.h>

typedef enum {
    STTouchMove = 0,
    STTouchDown,
    STTouchUp
} STTouchType;

typedef enum {
    UIInterfaceOrientationPortrait           = 1,//UIDeviceOrientationPortrait,
    UIInterfaceOrientationPortraitUpsideDown = 2,//UIDeviceOrientationPortraitUpsideDown,
    UIInterfaceOrientationLandscapeLeft      = 4,//UIDeviceOrientationLandscapeRight,
    UIInterfaceOrientationLandscapeRight     = 3,//UIDeviceOrientationLandscapeLeft
} UIInterfaceOrientation;

@interface UIApplication
+(id)sharedApplication;
-(UIInterfaceOrientation)statusBarOrientation;

+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;

+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;
-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(STTouchType)type;
@end

@interface UIScreen
+(id)mainScreen;
-(CGRect)bounds;
@end

@interface SimulateTouch
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;
@end

#pragma mark -

%hook UIApplication

%new
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    return [SimulateTouch STScreenToWindowPoint:point withOrientation:orientation];
}

%new
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    return [SimulateTouch STWindowToScreenPoint:point withOrientation:orientation];
}

%new
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type
{
    return [SimulateTouch simulateTouch:pathIndex atPoint:point withType:type];
}

%new
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration
{
    return [SimulateTouch simulateSwipeFromPoint:fromPoint toPoint:toPoint duration:duration];
}

%new
-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type
{
    UIInterfaceOrientation orientation = [[%c(UIApplication) sharedApplication] statusBarOrientation];
    CGPoint nPoint = [SimulateTouch STWindowToScreenPoint:point withOrientation:orientation];
    
    return [SimulateTouch simulateTouch:pathIndex atPoint:nPoint withType:type];
}

%new
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(STTouchType)type
{
    UIInterfaceOrientation orientation = [[%c(UIApplication) sharedApplication] statusBarOrientation];
    CGPoint nFPoint = [SimulateTouch STWindowToScreenPoint:fromPoint withOrientation:orientation];
    CGPoint nTPoint = [SimulateTouch STWindowToScreenPoint:toPoint withOrientation:orientation];
    
    return [SimulateTouch simulateSwipeFromPoint:nFPoint toPoint:nTPoint duration:0.3f];
}

%end