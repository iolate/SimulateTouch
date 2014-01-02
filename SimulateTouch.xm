/*
 * Name: libSimulateTouch ( kr.iolate.simulatetouch )
 * Author: iolate <iolate@me.com>
 *
 */

#include <substrate.h>
#include <mach/mach.h>
#import <mach/mach_time.h>

//#import <GraphicsServices/GSEvent.h>
#import <IOKit/hid/IOHIDEvent.h>
#import "../wavemessaging/WaveMessaging.h"
#import <CoreGraphics/CoreGraphics.h>

//https://github.com/iolate/iOS-Private-Headers/tree/master/IOKit/hid
#import "private-headers/IOKit/hid/IOHIDEvent7.h"
#import "private-headers/IOKit/hid/IOHIDEventTypes7.h"

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

static void SendTouchesEvent();

static NSMutableDictionary* STTouches = nil; //Dictionary{index:STTouch}

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
- (void)userEventOccurred;
@end

#define Int2String(i) [NSString stringWithFormat:@"%d", i]
#define kIOHIDEventDigitizerSenderID 0x000000010000027F

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
    
    SendTouchesEvent();
}

static void SendTouchesEvent() {
    
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
        
        float factor = 1.0f;
        
        if (screen.width == 640 || screen.width == 1546) {
            factor = 2.0f;
        }
        
        float rX = x/screen.width*factor;
        float rY = y/screen.height*factor;
        
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
}

#pragma mark - Communicate with Library

typedef struct {
    int type;
    int index;
    CGPoint point;
} STEvent;

NSDictionary* waveMessagingCallBack(NSString* serviceName, NSDictionary* contents, BOOL reply) {
    int msgid = [[contents objectForKey:@"type"] intValue];
    
    DLog(@"### ST: Receive Message Id: %d", (int)msgid);
    if (msgid == 1) {
        NSData* cfData = [contents objectForKey:@"stevent"];
        if ([cfData length] == sizeof(STEvent)) {
            STEvent* touch = (STEvent *)[cfData bytes];
            if (touch != NULL) {
                
                int pathIndex = touch->index;
                DLog(@"### ST: Received Path Index: %d", pathIndex);
                if (pathIndex == 0) {
                    pathIndex = getExtraIndexNumber();
                }
                
                SimulateTouchEvent(0, pathIndex, touch->type, touch->point);
                
                return @{@"pathIndex": [NSNumber numberWithInt:pathIndex]};
                
            }else{
                return nil;
            }
        }
    }else {
          NSLog(@"SimulateTouchServer: Unknown message type: %d", (int)msgid); //%x
      }
    
    // Do not return a reply to the caller
    return nil;
}

#pragma mark - MSInitialize

#define MACH_PORT_NAME "kr.iolate.simulatetouch"

MSInitialize {
    STTouches = [[NSMutableDictionary alloc] init];
    MSHookFunction(IOHIDEventSystemOpen, MSHake(IOHIDEventSystemOpen));
    
    if (objc_getClass("BKHIDSystemInterface")) {
        iOS7 = YES;
    }else{
        //iOS6
        iOS7 = NO;
    }
    //MSHookFunction(&IOHIDEventCreateDigitizerEvent, MSHake(IOHIDEventCreateDigitizerEvent));
    //MSHookFunction(&IOHIDEventCreateDigitizerFingerEventWithQuality, MSHake(IOHIDEventCreateDigitizerFingerEventWithQuality));
    
    WaveMessagingStartService(@MACH_PORT_NAME, waveMessagingCallBack);
}