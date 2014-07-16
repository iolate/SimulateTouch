/*
 * Name: libSimulateTouch ( kr.iolate.simulatetouch )
 * Author: iolate <iolate@me.com>
 *
 */

#include <substrate.h>
#include <mach/mach.h>
#import <mach/mach_time.h>
#import <CoreGraphics/CoreGraphics.h>

#import <IOKit/hid/IOHIDEvent.h>
#import <IOKit/hid/IOHIDEventSystem.h>
#import <IOKit/hid/IOHIDEventSystemClient.h>

//https://github.com/iolate/iOS-Private-Headers/tree/master/IOKit/hid
#import "private-headers/IOKit/hid/IOHIDEvent7.h"
#import "private-headers/IOKit/hid/IOHIDEventTypes7.h"
#import "private-headers/IOKit/hid/IOHIDEventSystemConnection.h"

#import <rocketbootstrap.h>

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

-(unsigned)clientPortAtPosition:(CGPoint)position;
-(unsigned)contextIdAtPosition:(CGPoint)position;
- (unsigned int)clientPortOfContextId:(unsigned int)arg1;
-(CGRect)bounds;

//iOS7
- (unsigned int)taskPortOfContextId:(unsigned int)arg1; //New!
@end

@interface BKUserEventTimer
+ (id)sharedInstance;
- (void)userEventOccurred; //iOS6
- (void)userEventOccurredOnDisplay:(id)arg1; //iOS7

-(BOOL)respondsToSelector:(SEL)selector;
@end

@interface BKHIDSystemInterface
+ (id)sharedInstance;
- (void)injectHIDEvent:(IOHIDEventRef)arg1;
@end

@interface BKAccessibility
//IOHIDEventSystemConnectionRef
+ (id)_eventRoutingClientConnectionManager;
@end

@interface BKHIDClientConnectionManager
- (IOHIDEventSystemConnectionRef)clientForTaskPort:(unsigned int)arg1;
- (IOHIDEventSystemConnectionRef)clientForBundleID:(id)arg1;
@end

#define Int2String(i) [NSString stringWithFormat:@"%d", i]

#pragma mark - Implementation
/*
MSHook(IOHIDEventRef, IOHIDEventCreateDigitizerEvent, CFAllocatorRef allocator, AbsoluteTime timeStamp, IOHIDDigitizerTransducerType type,
       uint32_t index, uint32_t identity, uint32_t eventMask, uint32_t buttonMask,
       IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat barrelPressure,
       Boolean range, Boolean touch, IOOptionBits options) {
    
    //NSLog(@"##### Event %d", type);
    //NSLog(@"##### Event %d %d %d %d %d (%f, %f, %f) %f %f %d %d %d", type, index, identity, eventMask, buttonMask, x, y, z, tipPressure, barrelPressure, range, touch, (unsigned int)options);
    return _IOHIDEventCreateDigitizerEvent(allocator, timeStamp, type, index, identity, eventMask, buttonMask, x, y, z, tipPressure, barrelPressure, range, touch, options);
}
MSHook(IOHIDEventRef, IOHIDEventCreateDigitizerFingerEventWithQuality, CFAllocatorRef allocator, AbsoluteTime timeStamp,
       uint32_t index, uint32_t identity, uint32_t eventMask,
       IOHIDFloat x, IOHIDFloat y, IOHIDFloat z, IOHIDFloat tipPressure, IOHIDFloat twist,
       IOHIDFloat minorRadius, IOHIDFloat majorRadius, IOHIDFloat quality, IOHIDFloat density, IOHIDFloat irregularity,
       Boolean range, Boolean touch, IOOptionBits options) {
    
    //NSLog(@"##### Quality %d %d %d %f %f", index, identity, eventMask, x, y);
    
    return _IOHIDEventCreateDigitizerFingerEventWithQuality(allocator, timeStamp, index, identity, eventMask, x, y, z, tipPressure, twist, minorRadius, majorRadius, quality, density, irregularity, range, touch, options);
}*/


static IOHIDEventSystemCallback original_callback;
static void iohid_event_callback (void* target, void* refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    if (IOHIDEventGetType(event) == kIOHIDEventTypeDigitizer) {
        [STTouches removeAllObjects];
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

// ============= from veency http://gitweb.saurik.com/veency.git
extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
    void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
}
static void SendHIDEvent(IOHIDEventRef event) {
    static IOHIDEventSystemClientRef client_(NULL);
    if (client_ == NULL)
        client_ = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    
    IOHIDEventSetSenderID(event, 0xDEFACEDBEEFFECE5);
    IOHIDEventSystemClientDispatchEvent(client_, event);
    CFRelease(event);
}
// =============

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
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldDigitizerDisplayIntegrated, 1, -268435456); //-268435456
    IOHIDEventSetIntegerValueWithOptions(handEvent, kIOHIDEventFieldBuiltIn, 1, -268435456); //-268435456
    
    //It looks changing each time, but it doens't care. just don't use 0
    #define kIOHIDEventDigitizerSenderID 0x000000010000027F
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
        
        int eventM = (touchType == 0) ? kIOHIDDigitizerEventPosition : (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch); //Originally, 0, 1 and 2 are used too...
        int touch_ = (touchType == 2) ? 0 : 1;
        
        float x = touch->point.x;
        float y = touch->point.y;
        
        float rX, rY;
        
        //=========================
        
        //0~1 point
        id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
        CGSize screen = [(CAWindowServerDisplay *)display bounds].size;
        
        //I don't know why, but iPad Air's screen size is {width:2048,height:1536}
        float width = MIN(screen.width, screen.height);
        float height = MAX(screen.width, screen.height);
        
        float factor = 1.0f;
        if (width == 640 || width == 1536) factor = 2.0f;
        
        rX = x/width*factor;
        rY = y/height*factor;
        
        //=========================

        IOHIDEventRef fingerEvent = IOHIDEventCreateDigitizerFingerEventWithQuality(kCFAllocatorDefault, timeStamp,
                                                                                    [pIndex intValue], i + 2, eventM, rX, rY, 0, 0, 0, 0, 0, 0, 0, 0, touch_, touch_, 0);
        IOHIDEventAppendEvent(handEvent, fingerEvent);
        i++;
        
        handEventTouch |= touch_;
        if (touchType == 0) {
            handEventMask |= kIOHIDDigitizerEventPosition; //4
        }else{
            handEventMask |= (kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch | kIOHIDDigitizerEventIdentity); //1 + 2 + 32 = 35
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
    
    BKUserEventTimer* etimer = [NSClassFromString(@"BKUserEventTimer") sharedInstance];
    
    if ([etimer respondsToSelector:@selector(userEventOccurred)]) {
        [etimer userEventOccurred];
    }else if ([etimer respondsToSelector:@selector(userEventOccurredOnDisplay:)]) {
        [etimer userEventOccurredOnDisplay:nil];
    }
    
    if (iOS7) {
       SendHIDEvent(handEvent);
    }else {
        original_callback(NULL, NULL, NULL, handEvent);
    }
}

#pragma mark - Communicate with Library

typedef struct {
    int type;
    int index;
    float point_x;
    float point_y;
} STEvent;
#define POINT(a) CGPointMake(a->point_x, a->point_y)

static CFDataRef messageCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef cfData, void *info)
{
    DLog(@"### ST: Receive Message Id: %d", (int)msgid);
    if (msgid == 1) {
        if (CFDataGetLength(cfData) == sizeof(STEvent)) {
            STEvent* touch = (STEvent *)[(NSData *)cfData bytes];
            if (touch != NULL) {
                
                unsigned int port = 0;
                if (iOS7) {
                    id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
                    unsigned int contextId = [display contextIdAtPosition:POINT(touch)];
                    port = [display taskPortOfContextId:contextId];
                    
                    if (lastPort && lastPort != port) {
                        [STTouches removeAllObjects];
                    }
                    lastPort = port;
                }
                
                int pathIndex = touch->index;
                DLog(@"### ST: Received Path Index: %d", pathIndex);
                if (pathIndex == 0) {
                    pathIndex = getExtraIndexNumber();
                }
                
                SimulateTouchEvent(port, pathIndex, touch->type, POINT(touch));
                
                return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
            }else{
                DLog(@"### ST: Received STEvent is nil");
                return NULL;
            }
        }
        DLog(@"### ST: Received data is not STEvent. event size: %lu received size: %lu", sizeof(STEvent), CFDataGetLength(cfData));
    } else {
        NSLog(@"### ST: Unknown message type: %d", (int)msgid); //%x
    }
    
    return NULL;
}

#pragma mark - MSInitialize

#define MACH_PORT_NAME "kr.iolate.simulatetouch"

#ifdef __cplusplus
extern "C" {
#endif
    //Cydia Substrate
    typedef const void *MSImageRef;
    
    MSImageRef MSGetImageByName(const char *file);
    void *MSFindSymbol(MSImageRef image, const char *name);
#ifdef __cplusplus
}
#endif

MSInitialize {
    STTouches = [[NSMutableDictionary alloc] init];
    
    if (objc_getClass("BKHIDSystemInterface")) {
        iOS7 = YES;
    }else{
        //iOS6
        MSHookFunction(IOHIDEventSystemOpen, MSHake(IOHIDEventSystemOpen));
        iOS7 = NO;
    }
    //MSHookFunction(&IOHIDEventCreateDigitizerEvent, MSHake(IOHIDEventCreateDigitizerEvent));
    //MSHookFunction(&IOHIDEventCreateDigitizerFingerEventWithQuality, MSHake(IOHIDEventCreateDigitizerFingerEventWithQuality));
    
    CFMessagePortRef local = CFMessagePortCreateLocal(NULL, CFSTR(MACH_PORT_NAME), messageCallBack, NULL, NULL);
    if (rocketbootstrap_cfmessageportexposelocal(local) != 0) {
        NSLog(@"### ST: RocketBootstrap failed");
        return;
    }
    
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, local, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
}
