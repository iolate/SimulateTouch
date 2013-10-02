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
    if (FTLoopIsRunning == FALSE) {
        return;
    }
    int touchCount = [ATouchEvents count];
    
    if (touchCount == 0) {
        FTLoopIsRunning = FALSE;
        return;
    }
    
    NSMutableArray* willRemoveObjects = [NSMutableArray array];
    
    for (int i = 0; i < touchCount; i++)
    {
        STTouchA* touch = [ATouchEvents objectAtIndex:i];
        
        int touchType = touch->type;
        //0: move/stay 1: down 2: up
        
        if (touchType == 1) {
            //Already simulate_touch_event is called
            
            touch->type = 0;
            
            touch->point.x = touch->point.x+touch->dx;
            touch->point.y = touch->point.y+touch->dy;
            touch->times = 1;
            
        }else if (touchType == 0) {
            CGPoint point = CGPointMake(roundf(touch->point.x), roundf(touch->point.y));
            int r = simulate_touch_event(touch->pathIndex, touchType, point);
            if (r == 0) {
                NSLog(@"ST Error: touchLoop type:0 index:%d, point:(%d,%d) pathIndex:0", touch->pathIndex, (int)touch->point.x, (int)touch->point.y);
                continue;
            }
            
            touch->point.x = touch->point.x+touch->dx;
            touch->point.y = touch->point.y+touch->dy;
            
            touch->times++;

            if (touch->times == touch->stime-1) {
                touch->type = 2;
            }
        }else { // == 2
            CGPoint point = CGPointMake(roundf(touch->point.x), roundf(touch->point.y));
            int r = simulate_touch_event(touch->pathIndex, touchType, point);
            if (r == 0) {
                NSLog(@"ST Error: touchLoop type:2 index:%d, point:(%d,%d) pathIndex:0", touch->pathIndex, (int)touch->point.x, (int)touch->point.y);
                continue;
            }
            
            [willRemoveObjects addObject:touch];
        }
    }
    
    for (STTouchA* touch in willRemoveObjects) {
        [ATouchEvents removeObject:touch];
        [touch release];
    }
    
    willRemoveObjects = nil;
    
    //recursive
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / LOOP_TIMES_IN_SECOND); // 1초에 50번 실행되는 듯..?
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
    
    int stime = roundf(duration/0.022); //코드 자체에 시간이 걸리는지 이렇게 해야 얼추 맞음
    float dx = (toPoint.x - fromPoint.x)/stime;
    float dy = (toPoint.y - fromPoint.y)/stime;
    
    touch->type = 1;
    touch->point = fromPoint;
    touch->dx = dx;
    touch->dy = dy;
    touch->times = 0;
    touch->stime = stime;
    
    [ATouchEvents addObject:touch];
    
    int r = simulate_touch_event(0, 1, fromPoint);
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