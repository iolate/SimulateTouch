/*
 * Name: libSimulateTouch
 * Author: iolate <iolate@me.com>
 *
 */

#import <mach/mach_time.h>

#import <CoreGraphics/CoreGraphics.h>

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

@interface UIScreen
+(id)mainScreen;
-(CGRect)bounds;
@end

@interface STTouchA : NSObject
{
@public
    int type; //터치 종류 0: move/stay| 1: down| 2: up
    int pathIndex;
    CGPoint startPoint;
    CGPoint endPoint;
    uint64_t startTime;
    float requestedTime;
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

double MachTimeToSecs(uint64_t time)
{
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    return (double)time * (double)timebase.numer / (double)timebase.denom / 1e9;
}


static void _simulateTouchLoop()
{
    if (FTLoopIsRunning == FALSE) {
        return;
    }
    int touchCount = [ATouchEvents count];
    
    if (touchCount == 0) {
        FTLoopIsRunning = FALSE;
        return;
    }
    
    NSMutableArray* willRemoveObjects = [NSMutableArray array];
    uint64_t curTime = mach_absolute_time();
    
    for (int i = 0; i < touchCount; i++)
    {
        STTouchA* touch = [ATouchEvents objectAtIndex:i];
        
        int touchType = touch->type;
        //0: move/stay 1: down 2: up
        
        if (touchType == 1) {
            //Already simulate_touch_event is called
            touch->type = STTouchMove;
        }else {
            double dif = MachTimeToSecs(curTime - touch->startTime);
            
            float req = touch->requestedTime;
            if (dif >= 0 && dif < req) {
                //Move
                
                float dx = touch->endPoint.x - touch->startPoint.x;
                float dy = touch->endPoint.y - touch->startPoint.y;
                
                double per = dif / (double)req;
                CGPoint point = CGPointMake(touch->startPoint.x + (float)(dx * per), touch->startPoint.y + (float)(dy * per));
                
                int r = simulate_touch_event(touch->pathIndex, STTouchMove, point);
                if (r == 0) {
                    NSLog(@"ST Error: touchLoop type:0 index:%d, point:(%d,%d) pathIndex:0", touch->pathIndex, (int)point.x, (int)point.y);
                    continue;
                }
                
            }else {
                //Up
                
                int r = simulate_touch_event(touch->pathIndex, STTouchUp, touch->endPoint);
                if (r == 0) {
                    NSLog(@"ST Error: touchLoop type:2 index:%d, point:(%d,%d) pathIndex:0", touch->pathIndex, (int)touch->endPoint.x, (int)touch->endPoint.y);
                    continue;
                }
                
                [willRemoveObjects addObject:touch];
            }
        }
    }
    
    for (STTouchA* touch in willRemoveObjects) {
        [ATouchEvents removeObject:touch];
        [touch release];
    }
    
    willRemoveObjects = nil;
    
    //recursive
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / LOOP_TIMES_IN_SECOND);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        _simulateTouchLoop();
    });
}

#pragma mark -

@interface SimulateTouch : NSObject
@end

@implementation SimulateTouch

+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    CGSize screen = [[UIScreen mainScreen] bounds].size;
    
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

+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation {
    CGSize screen = [[UIScreen mainScreen] bounds].size;
    
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

+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type
{
    int r = simulate_touch_event(pathIndex, type, point);
    if (r == 0) {
        NSLog(@"ST Error: simulateTouch:atPoint:withType: index:%d type:%d pathIndex:0", pathIndex, type);
        return 0;
    }
    return r;
}

+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration
{
    if (ATouchEvents == nil) {
        ATouchEvents = [[NSMutableArray alloc] init];
    }
    
    STTouchA* touch = [[STTouchA alloc] init];
    
    touch->type = STTouchMove;
    touch->startPoint = fromPoint;
    touch->endPoint = toPoint;
    touch->requestedTime = duration;
    touch->startTime = mach_absolute_time();
    
    [ATouchEvents addObject:touch];
    
    int r = simulate_touch_event(0, STTouchDown, fromPoint);
    if (r == 0) {
        NSLog(@"ST Error: simulateSwipeFromPoint:toPoint:duration: pathIndex:0");
        return 0;
    }
    touch->pathIndex = r;
    
    if (!FTLoopIsRunning) {
        FTLoopIsRunning = TRUE;
        _simulateTouchLoop();
    }
    
    return r;
}

@end