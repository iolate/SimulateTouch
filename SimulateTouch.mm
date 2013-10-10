/*
 * Name: libSimulateTouch
 * Author: iolate <iolate@me.com>
 *
 */

#include <substrate.h>
#include <mach/mach.h>
#import <mach/mach_time.h>

#import <GraphicsServices/GSEvent.h>

#import <IOKit/hid/IOHIDEvent.h>

//https://github.com/iolate/iOS-Private-Headers/tree/master/IOKit/hid
#import "private-headers/IOKit/hid/IOHIDEvent7.h"
#import "private-headers/IOKit/hid/IOHIDEventTypes7.h"
#import "private-headers/IOKit/hid/IOHIDEventSystemConnection.h"


#pragma mark - Common declaration

//#define DEBUG
#ifdef DEBUG
#   define DLog(...) NSLog(__VA_ARGS__)
#else
#   define DLog(...)
#endif

@interface STTouch : NSObject
{
@public
    int type; //터치 종류 0: move/stay 1: down 2: up
    CGPoint point;
}
@end
@implementation STTouch
@end

static void SendTouchesEvent(mach_port_t port);

static NSMutableDictionary* STTouches = nil; //Dictionary{index:STTouch}
static unsigned int lastPort = 0;

static BOOL iOS7 = NO;

@interface CAWindowServer //in QuartzCore
+(id)serverIfRunning;
-(id)displayWithName:(id)name;
-(NSArray *)displays; //@property(readonly, assign) NSArray* displays;
@end

@interface CAWindowServerDisplay
-(id)contextIdsWithClientPort:(unsigned)clientPort;
-(unsigned)clientPortAtPosition:(CGPoint)position;

//iOS7
-(unsigned)contextIdAtPosition:(CGPoint)position;
- (unsigned int)taskPortOfContextId:(unsigned int)arg1; //New!
@end


#pragma mark - iOS6 declaration

//Symbol not found error because this was added on iOS7
void IOHIDEventSystemConnectionDispatchEvent(IOHIDEventSystemConnectionRef systemConnection, IOHIDEventRef event) __attribute__((weak));

#define GSEventTypeMouse 0x0bb9 //kGSEventHand = 3001
#define GSMouseEventTypeDown    0x1
#define GSMouseEventTypeDragged 0x2
#define GSMouseEventTypeCountChanged      0x5
#define GSMouseEventTypeUp      0x6
#define GSMouseEventTypeCancel  0x8

#define PATHINFO_SIZE 11

#define Int2String(i) [NSString stringWithFormat:@"%d", i]

typedef struct GSPathInfoiOS6 {
    uint8_t pathIndex;		// 0x0 = 0x5C
    uint8_t pathIdentity;		// 0x1 = 0x5D
    uint8_t pathProximity;	// 0x2 = 0x5E
    uint8_t pathPressure;				// 0x4 = 0x60
    uint32_t x04;		// 0x8 = 0x64
    uint32_t x08;
    CGPoint pathLocation;
    uint32_t x14;
    uint16_t ignored;
} GSPathInfoiOS6;

@interface GSEventTouchProxyiOS6 : NSObject
{
@public
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
    uint16_t x52; //touch count ( >= iOS5) iOS6
    //struct GSPathInfo pathInfo[];
    //-- sizeof: 0x24
    struct GSPathInfoiOS6 path[PATHINFO_SIZE]; // sizeof = 0x1C
}
@end
@implementation GSEventTouchProxyiOS6
@end

#pragma mark - iOS7 declaration

#define kIOHIDEventDigitizerSenderID 0x000000010000027F

@interface BKAccessibility
//IOHIDEventSystemConnectionRef
+ (id)_eventRoutingClientConnectionManager;
@end

@interface BKHIDClientConnectionManager
- (IOHIDEventSystemConnectionRef)clientForTaskPort:(unsigned int)arg1;
- (IOHIDEventSystemConnectionRef)clientForBundleID:(id)arg1;
@end

#pragma mark - Implementation

#ifdef DEBUG
static NSString* prevString = nil;
static int count = 0;
static void LogTouchEvent(IOHIDEventRef event) {
    
    if (IOHIDEventGetType(event) != 11) return;
    
    NSString* logString = nil;
    
    logString = [NSString stringWithFormat:@"\nST\t%d %d (%d %d)",
                 IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerEventMask), IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerIndex), IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerRange), IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerTouch)];
    
	CFArrayRef children = IOHIDEventGetChildren(event);
    
    for (int i = 0; i < CFArrayGetCount(children); i++) {
		IOHIDEventRef e = (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
		logString = [logString stringByAppendingFormat:@"\nST\t\t%d %d (%d %d)", IOHIDEventGetIntegerValue(e, kIOHIDEventFieldDigitizerEventMask), IOHIDEventGetIntegerValue(e, kIOHIDEventFieldDigitizerIdentity), IOHIDEventGetIntegerValue(e, kIOHIDEventFieldDigitizerRange), IOHIDEventGetIntegerValue(e, kIOHIDEventFieldDigitizerTouch)];
	}
	
	if (prevString != nil && [prevString isEqualToString:logString]){
		count++;
	}else{
		if (count != 0) {
			NSLog(@"ST Last repeated %d times", count);
			count  = 0;
		}
		NSLog(@"%@", logString);
	}
    
	prevString = [logString retain];
    
}
#endif

MSHook(void, IOHIDEventSystemConnectionDispatchEvent, IOHIDEventSystemConnectionRef systemConnection, IOHIDEventRef event) {
    //Only for iOS7
    if (IOHIDEventSystemConnectionGetType(systemConnection) == 3 && IOHIDEventGetType(event) == 11) {
        [STTouches removeAllObjects];
        lastPort = 0;
        
#ifdef DEBUG
        static IOHIDEventSystemConnectionRef sc;
        
        if (sc == nil) sc = systemConnection;
        if (sc == systemConnection) LogTouchEvent(event);
#endif
        
    }
    
    _IOHIDEventSystemConnectionDispatchEvent(systemConnection, event);
}

MSHook(void, GSSendEvent, const GSEventRecord* record, mach_port_t port) {
    //Only for iOS6
    GSEventType type = record->type;
    
    if (type == kGSEventHand) {
        [STTouches removeAllObjects];
        lastPort = 0;
    }
    
    _GSSendEvent(record, port);
}


static int getExtraIndexNumber()
{
    int r = arc4random()%14;
    r += 1; //except 0
    
    NSString* pin = Int2String(r);
    
    if ([[STTouches allKeys] containsObject:pin]) {
        return getExtraIndexNumber();
    }else{
        return r;
    }
}

static void SimulateTouchEvent(mach_port_t port, int pathIndex, int type, CGPoint touchPoint) {
    if (pathIndex == 0) return;
    
    STTouch* touch = [STTouches objectForKey:Int2String(pathIndex)] ?: [[STTouch alloc] init];
    
    touch->type = type;
    touch->point = touchPoint;
    
    [STTouches setObject:touch forKey:Int2String(pathIndex)];
    
    SendTouchesEvent(port);
}

static void SendTouchesEvent(mach_port_t port) {
    
    int touchCount = [[STTouches allKeys] count];
    
    if (touchCount == 0) {
        return;
    }
    
    if (iOS7) {
        uint64_t abTime = mach_absolute_time();
        AbsoluteTime timeStamp = *(AbsoluteTime *) &abTime;
        
        IOHIDEventRef handEvent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, timeStamp, kIOHIDTransducerTypeHand, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerDisplayIntegrated, 1, -268435456);
        IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldBuiltIn, 1, -268435456);
        IOHIDEventSetSenderID(handEvent, kIOHIDEventDigitizerSenderID);
        
        int handEventMask = 0;
        int handEventTouch = 0;
        int touchingCount = 0; //except Up touch
        
        int i = 0;
        for (NSString* pIndex in [STTouches allKeys])
        {
            STTouch* touch = [STTouches objectForKey:pIndex];
            int touchType = touch->type;
            
            int eventM = (touchType == 0) ? 4 : 3;
            int touch_ = (touchType == 2) ? 0 : 1;
            
            float x = touch->point.x;
            float y = touch->point.y;

            IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(kCFAllocatorDefault, timeStamp,
                                                        [pIndex intValue], i + 2, eventM, x, y, 0, 0, 0, 0, 0, 0, 0, 0, touch_, touch_, 0);
            IOHIDEventAppendEvent(handEvent, fingerEvent);
            i++;
            
            handEventTouch |= touch_;
            if (touchType == 0) {
                handEventMask |= kIOHIDDigitizerEventPosition;
            }else{
                handEventMask |= (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity);
            }
            
            if (touchType == 2) {
                handEventMask |= kIOHIDDigitizerEventPosition;
                [STTouches removeObjectForKey:pIndex];
                [touch release];
            }else{
                touchingCount++;
            }
        }
        
        IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerEventMask, handEventMask, -268435456);
        IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerRange, handEventTouch, -268435456);
        IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerTouch, handEventTouch, -268435456);
        //IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerIndex, (1<<22) + (int)pow(2.0, (double)(touchingCount+1)) - 2, -268435456);
        
#ifdef DEBUG
        LogTouchEvent(handEvent);
#endif
        id manager = [objc_getClass("BKAccessibility") _eventRoutingClientConnectionManager];
        IOHIDEventSystemConnectionRef systemConnection = [manager clientForTaskPort:port];
        _IOHIDEventSystemConnectionDispatchEvent(systemConnection, handEvent);
        
    }else{
        GSEventTouchProxyiOS6* gevent6;
        
        gevent6 = [[GSEventTouchProxyiOS6 alloc] init];
        gevent6->record.type = (GSEventType)GSEventTypeMouse;
        gevent6->record.timestamp = GSCurrentEventTimestamp();
        
        int tDown = 0, tUp = 0, tMove = 0;
        int i = 0;
        
        for (NSString* pIndex in [STTouches allKeys])
        {
            if (i > PATHINFO_SIZE - 1) break;
            
            STTouch* touch = [STTouches objectForKey:pIndex];
            int touchType = touch->type;
            
            gevent6->path[i].pathIndex = [pIndex intValue];
            gevent6->path[i].pathIdentity = 0x02;
            gevent6->path[i].pathProximity = touchType != 2 ? 0x03 : 0x00;
            gevent6->path[i].pathLocation = touch->point;
            
            i++;
            
            if (touchType == 0) tMove++;
            else if (touchType == 1) tDown++;
            else {
                tUp++;
                [STTouches removeObjectForKey:pIndex];
                [touch release];
            }
        }
        
        int touchEvent = 1;
        
        int tType = (tMove ? 1 : 0) + (tDown ? 2 : 0) + (tUp ? 4 : 0);
        if (tType == 1) {
            touchEvent = GSMouseEventTypeDragged;
        }else if (tType == 2) {
            touchEvent = GSMouseEventTypeDown;
        }else if (tType == 4) {
            touchEvent = GSMouseEventTypeUp;
        }else {
            touchEvent = GSMouseEventTypeCountChanged;
        }
        
        gevent6->type = touchEvent;
        gevent6->x34 = 0x1;
        gevent6->x38 = tMove + tDown;
        gevent6->x52 = touchCount;
        
        _GSSendEvent(&gevent6->record, port);
    }
}

#pragma mark - Communicate with Library

typedef struct {
    int type;
    int index;
    CGPoint point;
} STEvent;

static CFDataRef messageCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef cfData, void *info)
{
    DLog(@"Receive Message Id: %d", (int)msgid);
    if (msgid == 1) {
        if (CFDataGetLength(cfData) == sizeof(STEvent)) {
            STEvent* touch = (STEvent *)[(NSData *)cfData bytes];
            if (touch != NULL) {
                
                if (iOS7) {
                    
                    id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
                    unsigned int contextId = [display contextIdAtPosition:touch->point];
                    unsigned int port = [display taskPortOfContextId:contextId];
                    
                    if (lastPort && lastPort != port) {
                        [STTouches removeAllObjects];
                    }
                    lastPort = port;
                    
                    int pathIndex = touch->index;
                    DLog(@"Received Path Index: %d", pathIndex);
                    if (pathIndex == 0) {
                        pathIndex = getExtraIndexNumber();
                    }
                    
                    SimulateTouchEvent(port, pathIndex, touch->type, touch->point);
                    
                    return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
                    
                }else{
                    
                    id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
                    unsigned port = [display clientPortAtPosition:touch->point];
                    
                    if (lastPort && lastPort != port) {
                        [STTouches removeAllObjects];
                    }
                    lastPort = port;
                    
                    int pathIndex = touch->index;
                    DLog(@"Received Path Index: %d", pathIndex);
                    if (pathIndex == 0) {
                        pathIndex = getExtraIndexNumber();
                    }
                    
                    SimulateTouchEvent(port, pathIndex, touch->type, touch->point);
                    
                    return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
                    
                }
                
            }else{
                return 0;
            }
        }
    } else {
        NSLog(@"SimulateTouchServer: Unknown message type: %d", (int)msgid); //%x
    }
    
    // Do not return a reply to the caller
    return NULL;
}

#pragma mark - MSInitialize

#define MACH_PORT_NAME "kr.iolate.simulatetouch"

MSInitialize {
    //MSHookFunction(&, MSHake());
    
    STTouches = [[NSMutableDictionary alloc] init];
    
    if (objc_getClass("BKHIDSystemInterface")) {
        iOS7 = YES;
        MSHookFunction(&IOHIDEventSystemConnectionDispatchEvent, MSHake(IOHIDEventSystemConnectionDispatchEvent));
    }else{
        //iOS6
        iOS7 = NO;
        MSHookFunction(&GSSendEvent, MSHake(GSSendEvent));
    }
    
    CFMessagePortRef local = CFMessagePortCreateLocal(NULL, CFSTR(MACH_PORT_NAME), messageCallBack, NULL, NULL);
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, local, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode); 
}