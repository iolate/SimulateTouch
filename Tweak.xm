#import <CoreGraphics/CoreGraphics.h>

%group GRP_UIApp

#define LOOP_TIMES_IN_SECOND 60
#define MACH_PORT_NAME "kr.iolate.simulatetouch"

typedef enum {
    STTouchMove = 0,
    STTouchDown,
    STTouchUp
} STTouchType;

typedef struct {
    int type;
    int index;
    CGPoint point;
} STEvent;

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

@interface STTouchA : NSObject
{
@public
    int type; //터치 종류 0: move/stay 1: down 2: up
    int pathIndex;
    CGPoint point;
    float dx;
    float dy;
    int times; //현재 횟수
    int stime; //횟수
}
@end
@implementation STTouchA
@end

static CFMessagePortRef messagePort = NULL;
static NSMutableArray* ATouchEvents = nil;
static BOOL FTLoopIsRunning = FALSE;

#pragma mark -

static int simulate_touch_event(int index, int type, CGPoint point) {
    
    if (messagePort && !CFMessagePortIsValid(messagePort)){
        CFRelease(messagePort);
        messagePort = NULL;
    }
    if (!messagePort) {
        messagePort = CFMessagePortCreateRemote(NULL, CFSTR(MACH_PORT_NAME));
    }
    if (!messagePort || !CFMessagePortIsValid(messagePort)) {
        return 0; //kCFMessagePortIsInvalid;
    }
    
    STEvent event;
    event.type = type;
    event.index = index;
    event.point = point;
    
    CFDataRef cfData = CFDataCreate(NULL, (uint8_t*)&event, sizeof(event));
    CFDataRef rData = NULL;
    
    CFMessagePortSendRequest(messagePort, 1/*type*/, cfData, 1, 1, kCFRunLoopDefaultMode, &rData);
    
    if (cfData) {
        CFRelease(cfData);
    }
    
    int pathIndex;
    [(NSData *)rData getBytes:&pathIndex length:sizeof(pathIndex)];
    
    if (rData) {
        CFRelease(rData);
    }
    
    return pathIndex;
}

static void _simulateTouchLoop()
{
    FTLoopIsRunning = TRUE;
    int touchCount = [ATouchEvents count];
    
    if (touchCount == 0) {
        FTLoopIsRunning = FALSE;
        return;
    }
    
    for (int i = 0; i < touchCount; i++)
    {
        STTouchA* touch = [ATouchEvents objectAtIndex:i];
        
        int touchType = touch->type;
        //0: move/stay 1: down 2: up
        
        
        
        if (touchType == 1) {
            //Already call simulate_touch_event
            
            touch->type = 0;
            
            touch->point.x = roundf(touch->point.x+touch->dx);
            touch->point.y = roundf(touch->point.y+touch->dy);
            touch->times = 1;
            
        }else{
            int r = simulate_touch_event(touch->pathIndex, touchType, touch->point);
            touch->pathIndex = r;
            
            if (touchType == 0) {
                
                touch->point.x = roundf(touch->point.x+touch->dx);
                touch->point.y = roundf(touch->point.y+touch->dy);
                //touch->point = point;
                
                touch->times++;
                
                if (touch->times == touch->stime-1) {
                    touch->type = 2;
                }
            }else { //touchType == 2
                [ATouchEvents removeObjectAtIndex:i];
                [touch release];
            }
        }
    }
    
    //recursive
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / LOOP_TIMES_IN_SECOND);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        _simulateTouchLoop();
    });
}

#pragma mark -

%hook UIApplication

%new
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    CGSize screen = [[%c(UIScreen) mainScreen] bounds].size;
    
    if (orientation == UIInterfaceOrientationPortrait) {
        return point;
    }else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        return CGPointMake(screen.width - point.x, screen.height - point.y);
    }else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        //Homebutton is left
        return CGPointMake(screen.height - point.y, point.x);
    }else if (orientation == UIInterfaceOrientationLandscapeRight) {
        return CGPointMake(point.y, screen.width - point.x);
    }else return point;
}

%new
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    //UIInterfaceOrientation orientation = [&c(UIApplication) sharedApplication].statusBarOrientation;
    
    CGSize screen = [[%c(UIScreen) mainScreen] bounds].size;
    
    if (orientation == UIInterfaceOrientationPortrait) {
        return point;
    }else if (orientation == UIInterfaceOrientationPortraitUpsideDown) {
        return CGPointMake(screen.width - point.x, screen.height - point.y);
    }else if (orientation == UIInterfaceOrientationLandscapeLeft) {
        //Homebutton is left
        return CGPointMake(point.y, screen.height - point.x);
    }else if (orientation == UIInterfaceOrientationLandscapeRight) {
        return CGPointMake(screen.width - point.y, point.x);
    }else return point;
}

%new
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type
{
    int r = simulate_touch_event(pathIndex, type, point);
    return r;
}

%new
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration
{
    if (ATouchEvents == nil) {
        ATouchEvents = [[NSMutableArray alloc] init];
    }
    
    STTouchA* touch = [[STTouchA alloc] init];
    
    int stime = roundf((float)LOOP_TIMES_IN_SECOND*duration);
    
    float dx = roundf((toPoint.x - fromPoint.x)/stime);
    float dy = roundf((toPoint.y - fromPoint.y)/stime);
    
    touch->type = 1;
    touch->point = fromPoint;
    touch->dx = dx;
    touch->dy = dy;
    touch->times = 0;
    touch->stime = stime;
    
    [ATouchEvents addObject:touch];
    
    int r = simulate_touch_event(0, 1, fromPoint);
    touch->pathIndex = r;
    
    _simulateTouchLoop();
    
    return r;
}

%new
-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type
{
    NSLog(@"touch %d", pathIndex);
    UIInterfaceOrientation orientation = [[%c(UIApplication) sharedApplication] statusBarOrientation];
    CGPoint nPoint = [%c(UIApplication) STWindowToScreenPoint:point withOrientation:orientation];
    
    return [%c(UIApplication) simulateTouch:pathIndex atPoint:nPoint withType:type];
}

%new
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(STTouchType)type
{
    UIInterfaceOrientation orientation = [[%c(UIApplication) sharedApplication] statusBarOrientation];
    CGPoint nFPoint = [%c(UIApplication) STWindowToScreenPoint:fromPoint withOrientation:orientation];
    CGPoint nTPoint = [%c(UIApplication) STWindowToScreenPoint:toPoint withOrientation:orientation];
    
    return [%c(UIApplication) simulateSwipeFromPoint:nFPoint toPoint:nTPoint duration:0.3f];
}

%end

%end

%ctor {
    Class uiapp = %c(UIApplication);
    if (uiapp != nil) {
        %init(GRP_UIApp);
    }
}