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

#import <IOKit/hid/IOHIDEventSystem.h>

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
{
    @public
    void *_impl;
}
-(unsigned)clientPortAtPosition:(CGPoint)position;
-(unsigned)contextIdAtPosition:(CGPoint)position;
- (unsigned int)clientPortOfContextId:(unsigned int)arg1;
-(CGRect)bounds;
//iOS7
- (unsigned int)taskPortOfContextId:(unsigned int)arg1; //New!
@end

@interface BKUserEventTimer
+ (id)sharedInstance;
- (void)userEventOccurred;
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
    //uint32_t x08;
    uint8_t test1;
    uint8_t test2;
    uint8_t test3;
    uint8_t test4;
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

/*
MSHook(IOHIDEventRef, IOHIDEventCreateDigitizerEvent, CFAllocatorRef allocator, AbsoluteTime timeStamp, IOHIDDigitizerTransducerType type,
       uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
       IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat barrelPressure,
       Boolean range, Boolean touch, IOOptionBits options) {
    
    NSLog(@"##### Event %d", type);
    //NSLog(@"##### Event %d %d %d %d %d (%f, %f, %f) %f %f %d %d %d", type, index, identity, eventMask, buttonMask, x, y, z, tipPressure, barrelPressure, range, touch, (unsigned int)options);
    
    return _IOHIDEventCreateDigitizerEvent(allocator, timeStamp, type, index, identity, eventMask, buttonMask, x, y, z, tipPressure, barrelPressure, range, touch, options);
}
MSHook(IOHIDEventRef, IOHIDEventCreateDigitizerFingerEventWithQuality, CFAllocatorRef allocator, AbsoluteTime timeStamp,
       uint32_t index, uint32_t identity, uint32_t eventMask,
       IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat twist,
       IOHIDFloat minorRadius, IOHIDFloat majorRadius, IOHIDFloat quality, IOHIDFloat density, IOHIDFloat irregularity,
       Boolean range, Boolean touch, IOOptionBits options) {
    
    NSLog(@"##### Quality %d %d %d %f %f", index, identity, eventMask, x, y);
    
    return _IOHIDEventCreateDigitizerFingerEventWithQuality(allocator, timeStamp, index, identity, eventMask, x, y, z, tipPressure, twist, minorRadius, majorRadius, quality, density, irregularity, range, touch, options);
}*/

static IOHIDEventSystemCallback original_callback;
static void iohid_event_callback (void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
        [STTouches removeAllObjects];
        lastPort = 0;
    }
    
    original_callback(target, refcon, service, event);
}

MSHook(Boolean, IOHIDEventSystemOpen, IOHIDEventSystemRef system, IOHIDEventSystemCallback callback, void* target, void* refcon, void* unused) {
    original_callback = callback;
    return _IOHIDEventSystemOpen(system, iohid_event_callback, target, refcon, unused);
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
    
    uint64_t abTime = mach_absolute_time();
    AbsoluteTime timeStamp = *(AbsoluteTime *) &abTime;
    
    //iOS6 kIOHIDDigitizerTransducerTypeHand == 35
    //iOS7 kIOHIDTransducerTypeHand == 3
    IOHIDEventRef handEvent = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, timeStamp, iOS7 ? kIOHIDTransducerTypeHand : kIOHIDDigitizerTransducerTypeHand, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    
    //Got on iOS7.
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerDisplayIntegrated, 1, -268435456);
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldBuiltIn, 1, -268435456);
    IOHIDEventSetSenderID(handEvent, kIOHIDEventDigitizerSenderID);
    //
    
    int handEventMask = 0;
    int handEventTouch = 0;
    int touchingCount = 0; //except Up touch
    
    int i = 0;
    for (NSString* pIndex in [STTouches allKeys])
    {
        STTouch* touch = [STTouches objectForKey:pIndex];
        int touchType = touch->type;
        
        int eventM = (touchType == 0) ? 4 : 3; //Originally, 0, 1 and 2 are used too...
        int touch_ = (touchType == 2) ? 0 : 1;
        
        float x = touch->point.x;
        float y = touch->point.y;
        
        //Use 0~1 for point. Miraculously, iOS7 works anyway :p
        id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
        CGSize screen = [(CAWindowServerDisplay *)display bounds].size;
        //NSLog(@"### %@", display);
        float rX = x/screen.width;
        float rY = y/screen.height;
        //
        
        IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(kCFAllocatorDefault, timeStamp,
                                                                                    [pIndex intValue], i + 2, eventM, rX, rY, 0, 0, 0, 0, 0, 0, 0, 0, touch_, touch_, 0);
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
    
    //Got on iOS7.
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerEventMask, handEventMask, -268435456);
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerRange, handEventTouch, -268435456);
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerTouch, handEventTouch, -268435456);
    //IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerIndex, (1<<22) + (int)pow(2.0, (double)(touchingCount+1)) - 2, -268435456);
    //
    
    original_callback(NULL, NULL, NULL, handEvent);
    
    //id manager = [objc_getClass("BKAccessibility") _eventRoutingClientConnectionManager];
    //IOHIDEventSystemConnectionRef systemConnection = [manager clientForTaskPort:port];
    //_IOHIDEventSystemConnectionDispatchEvent(systemConnection, handEvent);
}
/*
#define SB_SERVICES  "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
mach_port_t getFrontMostAppPort()
{
    //bool locked;
    //bool passcode;
    mach_port_t *port;
    void *lib = dlopen(SB_SERVICES, RTLD_LAZY);
    int (*SBSSpringBoardServerPort)() = (int (*)())dlsym(lib, "SBSSpringBoardServerPort");
    //void* (*SBGetScreenLockStatus)(mach_port_t* port, bool *lockStatus, bool *passcodeEnabled) = (void *(*)(mach_port_t *, bool *, bool *))dlsym(lib, "SBGetScreenLockStatus");
    port = (mach_port_t *)SBSSpringBoardServerPort();
    dlclose(lib);
    //SBGetScreenLockStatus(port, &locked, &passcode);
    void *(*SBFrontmostApplicationDisplayIdentifier)(mach_port_t *port, char *result) = (void
                                                                                         *(*)(mach_port_t *, char *))dlsym(lib, "SBFrontmostApplicationDisplayIdentifier");
    char appId[256];
    memset(appId, 0, sizeof(appId));
    SBFrontmostApplicationDisplayIdentifier(port, appId);
    NSString * frontmostApp=[NSString stringWithFormat:@"%s",appId];
    //GSGetPurpleSystemEventPort()
    if([frontmostApp length] == 0) return GSCopyPurpleNamedPort("com.apple.springboard");
    else return GSCopyPurpleNamedPort(appId);
}

static unsigned int poseWindowContext = -1;
%hook CAWindowServerDisplay

- (unsigned int)clientPortOfContextId:(unsigned int)arg1 {
    //iOS6 use this
    if (arg1 == poseWindowContext) {
        return getFrontMostAppPort();
    }
    
    return %orig;
}
-(unsigned)clientPortAtPosition:(CGPoint)position {
    unsigned contextId = [self contextIdAtPosition:position];
    return [self clientPortOfContextId:contextId];
}
%end
*/
#pragma mark - Communicate with Library

@interface CAContextImpl : NSObject

@end

typedef struct {
    int type;
    int index;
    CGPoint point;
} STEvent;

static CFDataRef messageCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef cfData, void *info)
{
    DLog(@"### ST: Receive Message Id: %d", (int)msgid);
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
                    DLog(@"### ST: Received Path Index: %d", pathIndex);
                    if (pathIndex == 0) {
                        pathIndex = getExtraIndexNumber();
                    }
                    
                    SimulateTouchEvent(port, pathIndex, touch->type, touch->point);
                    
                    return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
                    
                }else{
                    id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
                    void* _impl = ((CAWindowServerDisplay *)display)->_impl;
                    //NSLog(@"### impl %lu", sizeof(_impl));
                    
                    NSLog(@"### impl %lu", sizeof(*_impl));
                    unsigned port = [display clientPortAtPosition:touch->point];
                    
                    if (port == 0) {
                        //screen is dim.
                        NSLog(@"### ST: Screen is dim.");
                        int pathIndex = 0;
                        return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
                    }
                    
                    if (lastPort && lastPort != port) {
                        [STTouches removeAllObjects];
                    }
                    lastPort = port;
                    
                    int pathIndex = touch->index;
                    DLog(@"### ST: Received Path Index: %d", pathIndex);
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
    }/*else if (msgid == 2) {
        unsigned int contextId;
        [(NSData *)cfData getBytes:&contextId length:sizeof(contextId)];
        
        poseWindowContext = contextId;
        
        return NULL;
    }*/else {
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
    MSHookFunction(IOHIDEventSystemOpen, MSHake(IOHIDEventSystemOpen));
    
    if (objc_getClass("BKHIDSystemInterface")) {
        iOS7 = YES;
        //MSHookFunction(&IOHIDEventSystemConnectionDispatchEvent, MSHake(IOHIDEventSystemConnectionDispatchEvent));
    }else{
        //iOS6
        iOS7 = NO;
        //MSHookFunction(&GSSendEvent, MSHake(GSSendEvent));
    }
    
    //MSHookFunction(&IOHIDEventCreateDigitizerEvent, MSHake(IOHIDEventCreateDigitizerEvent));
    //MSHookFunction(&IOHIDEventCreateDigitizerFingerEventWithQuality, MSHake(IOHIDEventCreateDigitizerFingerEventWithQuality));
    
    
    CFMessagePortRef local = CFMessagePortCreateLocal(NULL, CFSTR(MACH_PORT_NAME), messageCallBack, NULL, NULL);
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, local, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
}