#include <substrate.h>
#include <mach/mach.h>

#import <GraphicsServices/GSEvent.h>
#import <UIKit/UIApplication.h>
#import <UIKit/UIScreen.h>

#define GSEventTypeMouse 0x0bb9
#define GSMouseEventTypeDown    0x1
#define GSMouseEventTypeDragged 0x2
#define GSMouseEventTypeCountChanged      0x5
#define GSMouseEventTypeUp      0x6
#define GSMouseEventTypeCancel  0x8

#define PATHINFO_SIZE 11
#define LOOP_TIMES_IN_SECOND 60
/*
typedef struct GSEventRecord2 {
    GSEventType type; // 0x8
    GSEventSubType subtype;	// 0xC
    float a;
    CGPoint location; 	// 0x10
    CGPoint windowLocation;	// 0x18
    int windowContextId;	// 0x20
    uint64_t timestamp;	// 0x24, from mach_absolute_time
    GSWindowRef window;	// 0x2C
    GSEventFlags flags;	// 0x30
    unsigned senderPID;	// 0x34
    CFIndex infoSize; // 0x38
} GSEventRecord2;
*/
@interface GSEventTouchProxy : NSObject
{
@public
/*
    typedef struct GSEventRecord {
		GSEventType type; // 0x8
		GSEventSubType subtype;	// 0xC
		CGPoint location; 	// 0x10
		CGPoint windowLocation;	// 0x18
		int windowContextId;	// 0x20
		uint64_t timestamp;	// 0x24, from mach_absolute_time
		GSWindowRef window;	// 0x2C
		GSEventFlags flags;	// 0x30
		unsigned senderPID;	// 0x34
		CFIndex infoSize; // 0x38
	} GSEventRecord;
    typedef struct GSPathInfo {
		uint8_t pathIndex;
		uint8_t pathIdentity;
		uint8_t pathProximity;
		uint8_t x03;
		uint32_t x04;
		uint32_t x08;
        CGPoint pathLocation;
		uint32_t x14; // 0x14
	} GSPathInfo; // sizeof = 0x18.
*/
    uint32_t ignored;
    struct GSEventRecord record;
    //--GSEventRecordInfo
    //----GSEventHandInfo
    uint32_t type;
    uint16_t x34; //1
    uint16_t x38; ////touching count
    CGPoint x3a;
    uint32_t x40;
    //---- sizeof: 0x14
    uint32_t x44;
    uint32_t x48;
    uint32_t x4c;
    uint8_t x50; //iOS6 touch count?
    uint8_t pathPositions; //touch count ( < iOS5) //0
    uint16_t x52; //touch count ( >= iOS5) iOS6, type?
    //struct GSPathInfo pathInfo[];
    //-- sizeof: 0x24
    struct GSPathInfo path[PATHINFO_SIZE]; // sizeof = 0x18
}
@end

@implementation GSEventTouchProxy
@end

static NSMutableDictionary* GSTouchEvents = nil;
static BOOL FTLoopIsRunning = FALSE;

static CGPoint STPointForCurrentScreen(CGPoint point)
{
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
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

static void _simulateTouchLoop()
{
    FTLoopIsRunning = TRUE;
    int touchCount = [[GSTouchEvents allKeys] count];
    
    if (touchCount == 0) {
        FTLoopIsRunning = FALSE;
        return;
    }
    BOOL iOS5 = YES;
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 6.0) {
        iOS5 = NO;
    }
    
    
    GSEventTouchProxy* gevent = [[GSEventTouchProxy alloc] init];
    
    if (iOS5) {
        gevent->record.type = (GSEventType)GSEventTypeMouse;
    }else{
        gevent->record.type = (GSEventType)GSEventTypeMouse;
        //gevent->ignored = 33620352;
        //locationInWindow top-left:(0,0) left:y+ down:x+, middle point of touches
        //gevent->record.flags = (GSEventFlags)500864448;
    }
    
    gevent->record.timestamp = GSCurrentEventTimestamp();
    gevent->record.infoSize = 0x24 + 0x18 * touchCount;
    //sizeof(struct GSEventRecordInfo) + sizeof(struct GSPathInfo) * touchCount;
    
    int tDown = 0;
    int tUp = 0;
    int tMove = 0;
    
    int i = 0;
    
    float sumx = 0.0f;
    float sumy = 0.0f;
    for (NSString* pIndex in [GSTouchEvents allKeys])
    {
        if (i > PATHINFO_SIZE - 1) break;
        
        NSDictionary* touch = [GSTouchEvents objectForKey:pIndex];
        int touchType = [[touch objectForKey:@"type"] intValue];
        //0: move/stay 1: down 2: up
        
        float touchX = [[touch objectForKey:@"x"] floatValue] ?: 0.0f;
        float touchY = [[touch objectForKey:@"y"] floatValue] ?: 0.0f;
        
        if (touchType == 0) {
            tMove++;
            
            if ([[touch allKeys] containsObject:@"dx"] || [[touch allKeys] containsObject:@"dy"]) {
                NSMutableDictionary* nTouch = [NSMutableDictionary dictionaryWithDictionary:touch];
                
                float dX = [[touch objectForKey:@"dx"] floatValue] ?: 0.0f;
                float dY = [[touch objectForKey:@"dy"] floatValue] ?: 0.0f;
                
                float newX = roundf(touchX+dX);
                float newY = roundf(touchY+dY);
                
                [nTouch setObject:[NSNumber numberWithFloat:newX] forKey:@"x"];
                [nTouch setObject:[NSNumber numberWithFloat:newY] forKey:@"y"];
                
                int times = [[touch objectForKey:@"times"] intValue];
                int stime = [[touch objectForKey:@"stime"] intValue] ?: 18;
                
                times++;
                
                [nTouch setObject:[NSNumber numberWithInt:times] forKey:@"times"];
                
                if (times == stime) {
                    [nTouch setObject:[NSNumber numberWithInt:2] forKey:@"type"];
                }
                
                [GSTouchEvents setObject:nTouch forKey:pIndex];
            
            }
        }else if (touchType == 1) {
            tDown++;
            
             NSMutableDictionary* nTouch = [NSMutableDictionary dictionaryWithDictionary:touch];
            [nTouch setObject:[NSNumber numberWithInt:0] forKey:@"type"];
            
            if ([[touch allKeys] containsObject:@"times"]) {
               
                
                float dX = [[touch objectForKey:@"dx"] floatValue] ?: 0.0f;
                float dY = [[touch objectForKey:@"dy"] floatValue] ?: 0.0f;
                
                [nTouch setObject:[NSNumber numberWithFloat:roundf(touchX+dX)] forKey:@"x"];
                [nTouch setObject:[NSNumber numberWithFloat:roundf(touchY+dY)] forKey:@"y"];
                
                [nTouch setObject:[NSNumber numberWithInt:1] forKey:@"times"];
            }
            [GSTouchEvents setObject:nTouch forKey:pIndex];
            
        }else {
            tUp++;
            
            [GSTouchEvents removeObjectForKey:pIndex];
            
        }
        
        gevent->path[i].pathIndex = [pIndex intValue];
        gevent->path[i].pathIdentity = 0x02;
        gevent->path[i].pathProximity = touchType != 2 ? 0x03 : 0x00;
        gevent->path[i].pathLocation = STPointForCurrentScreen(CGPointMake(touchX, touchY));
        
        sumx += touchX;
        sumy += touchY;
        
        i++;
    }
    
    int tType = (tMove ? 1 : 0) + (tDown ? 2 : 0) + (tUp ? 4 : 0);
    
    int touchEventType = 1;
    
    if (tType == 1) {
        touchEventType = GSMouseEventTypeDragged;
    }else if (tType == 2) {
        touchEventType = GSMouseEventTypeDown;
    }else if (tType == 4) {
        touchEventType = GSMouseEventTypeUp;
    }else if (tType == 3 || tType == 5 || tType == 7) {
        touchEventType = GSMouseEventTypeCountChanged;
    }else if (tType == 6) {
        // ????
        touchEventType = GSMouseEventTypeDown;
    }
    
    if (iOS5) {
        gevent->type = touchEventType;
        gevent->x34 = 0x1;
        
        gevent->x38 = tMove + tDown;
        gevent->x52 = touchCount;
    }else{
        gevent->type = touchEventType;
        gevent->x34 = 0x1;
        
        gevent->x38 = tMove + tDown;
        //gevent->record.windowLocation = CGPointMake(sumx/(i+1), sumy/(i+1));
        gevent->x52 = touchCount; //MUST NEED
    }
    
    mach_port_t appPort = GSCopyPurpleNamedPort([[[NSBundle mainBundle] bundleIdentifier] UTF8String]);
    GSSendEvent(&gevent->record, appPort);
    mach_port_deallocate(mach_task_self(), appPort);
    
    //recursive
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / LOOP_TIMES_IN_SECOND);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        _simulateTouchLoop();
    });
}

static int getExtraIndexNumber()
{
    int r = arc4random()%14;
    r += 2; //except 0 and 1 (MouseSupport)
    
    NSString* pin = [NSString stringWithFormat:@"%d", r];
    if ([[GSTouchEvents allKeys] containsObject:pin]) {
        return getExtraIndexNumber();
    }else{
        return r;
    }
}

%hook UIApplication
%new
-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(int)type
{
    if (pathIndex == 0) {
       pathIndex = getExtraIndexNumber(); 
    }else {
        if (type == 1) {
            NSString* pin = [NSString stringWithFormat:@"%d", pathIndex];
            if ([[GSTouchEvents allKeys] containsObject:pin]) {
                return 0;
            }
        }
    }
    
    if (type > 2) {
        return 0;
    }
    
    NSDictionary* touch = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:type], @"type",
                           [NSNumber numberWithFloat:point.x], @"x",
                           [NSNumber numberWithFloat:point.y], @"y", nil];
    
    [GSTouchEvents setObject:touch forKey:[NSString stringWithFormat:@"%d", pathIndex]];
    
    
    if (FTLoopIsRunning == FALSE) {
        _simulateTouchLoop();
    }
    
    return pathIndex;
}

%new
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(int)type
{
    if (pathIndex == 0) {
        pathIndex = getExtraIndexNumber();
    }else{
        if (type == 1) {
            NSString* pin = [NSString stringWithFormat:@"%d", pathIndex];
            if ([[GSTouchEvents allKeys] containsObject:pin]) {
                return 0;
            }
        }
        
    }

    if (type > 2) {
        return 0;
    }
    
    float duration = 0.3f;
    
    int splitTime = LOOP_TIMES_IN_SECOND * duration;
    
    float dX = toPoint.x - fromPoint.x;
    float dY = toPoint.y - fromPoint.y;
    
    float dxt = dX / (float)splitTime;
    float dyt = dY / (float)splitTime;
    
    NSDictionary* touch = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:1], @"type",
                           [NSNumber numberWithFloat:fromPoint.x], @"x",
                           [NSNumber numberWithFloat:fromPoint.y], @"y",
                           [NSNumber numberWithFloat:dxt], @"dx",
                           [NSNumber numberWithFloat:dyt], @"dy",
                           [NSNumber numberWithInt:0], @"times",
                           [NSNumber numberWithInt:splitTime], @"stime", nil];
    
    
    [GSTouchEvents setObject:touch forKey:[NSString stringWithFormat:@"%d", pathIndex]];
    
    if (FTLoopIsRunning == FALSE) {
        _simulateTouchLoop();
    }
    
    return pathIndex;
}

%end

%ctor{
    GSTouchEvents = [[NSMutableDictionary alloc] init];
}