#include <substrate.h>
#include <mach/mach.h>

#import <GraphicsServices/GSEvent.h>

#define GSEventTypeMouse 0x0bb9 //kGSEventHand = 3001
#define GSMouseEventTypeDown    0x1
#define GSMouseEventTypeDragged 0x2
#define GSMouseEventTypeCountChanged      0x5
#define GSMouseEventTypeUp      0x6
#define GSMouseEventTypeCancel  0x8

#define PATHINFO_SIZE 11

#define Int2String(i) [NSString stringWithFormat:@"%d", i]

#define DEBUG
#ifdef DEBUG
#   define RLog(...) NSLog(__VA_ARGS__)
#else
#   define RLog(...)
#endif


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

@interface CAWindowServer //in QuartzCore
+(id)serverIfRunning;
-(id)displayWithName:(id)name;
-(NSArray *)displays; //@property(readonly, assign) NSArray* displays;
@end

@interface CAWindowServerDisplay
-(id)contextIdsWithClientPort:(unsigned)clientPort;
-(unsigned)contextIdAtPosition:(CGPoint)position;
-(unsigned)clientPortAtPosition:(CGPoint)position;
@end

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

@interface STTouch : NSObject
{
    @public
    int type; //터치 종류 0: move/stay 1: down 2: up
    CGPoint point;
}
@end
@implementation STTouch
@end

static NSMutableDictionary* STTouches = nil; //key: client port - Dictionary{index:STTouch

static void SendTouchesEvent(mach_port_t port);

#pragma mark -

MSHook(void, GSSendEvent, const GSEventRecord* record, mach_port_t port) {
    GSEventType type = record->type;
    
    if (type == kGSEventHand) {
        [STTouches removeObjectForKey:Int2String(port)];
    }
    
    _GSSendEvent(record, port);
}

static void PrepareNextEvent(NSString* port) {
    NSMutableDictionary* touches = [STTouches objectForKey:port];

    for (NSString* p in [touches allKeys]) {
        STTouch* touch = [touches objectForKey:p];
        if (touch->type == 2) {
            [touches removeObjectForKey:p];
            [touch release];
        }
        
    }
    
    [STTouches setObject:touches forKey:Int2String((int)port)];
}
static int getExtraIndexNumber(NSString* port)
{
    int r = arc4random()%14;
    r += 2; //except 0 and 1 (MouseSupport)
    
    NSString* pin = Int2String(r);
    
    NSDictionary* sTouches = [STTouches objectForKey:port];
    
    if ([[sTouches allKeys] containsObject:pin]) {
        return getExtraIndexNumber(port);
    }else{
        return r;
    }
}

static void SimulateTouchEvent(mach_port_t _port, int pathIndex, int type, CGPoint touchPoint) {
    if (pathIndex == 0) return;
    
    NSString* port = Int2String(_port);
    
    NSMutableDictionary* touches = [STTouches objectForKey:port] ?: [NSMutableDictionary dictionary];
    
    STTouch* touch = [touches objectForKey:Int2String(pathIndex)] ?: [[STTouch alloc] init];
    
    touch->type = type;
    touch->point = touchPoint;
    
    [touches setObject:touch forKey:Int2String(pathIndex)];
    [STTouches setObject:touches forKey:port];
    
    SendTouchesEvent(_port);
    PrepareNextEvent(port);
}

static void SendTouchesEvent(mach_port_t port) {
    NSDictionary* sTouches = [STTouches objectForKey:Int2String(port)];
    
    int touchCount = [[sTouches allKeys] count];
    
    if (touchCount == 0) {
        return;
    }
    
    GSEventTouchProxyiOS6* gevent6;
    
    gevent6 = [[GSEventTouchProxyiOS6 alloc] init];
    gevent6->record.type = (GSEventType)GSEventTypeMouse;
    gevent6->record.timestamp = GSCurrentEventTimestamp();
    
    int tDown = 0, tUp = 0, tMove = 0;
    int i = 0;
    
    for (NSString* pIndex in [sTouches allKeys])
    {
        if (i > PATHINFO_SIZE - 1) break;
        
        STTouch* touch = [sTouches objectForKey:pIndex];
        int touchType = touch->type;
        
        if (touchType == 0) tMove++;
        else if (touchType == 1) tDown++;
        else tUp++;
        
        gevent6->path[i].pathIndex = [pIndex intValue];
        gevent6->path[i].pathIdentity = 0x02;
        gevent6->path[i].pathProximity = touchType != 2 ? 0x03 : 0x00;
        gevent6->path[i].pathLocation = touch->point;
        
        i++;
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
    
    //mach_port_deallocate(mach_task_self(), appPort);
}

#pragma mark -

typedef struct {
    int type;
    int index;
    CGPoint point;
} STEvent;

static CFDataRef messageCallBack(CFMessagePortRef local, SInt32 msgid, CFDataRef cfData, void *info)
{
    RLog(@"Receive Message Id: %d", (int)msgid);
    if (msgid == 1) {
        if (CFDataGetLength(cfData) == sizeof(STEvent)) {
            STEvent* touch = (STEvent *)[(NSData *)cfData bytes];
            if (touch != NULL) {
                id display = [[objc_getClass("CAWindowServer") serverIfRunning] displayWithName:@"LCD"];
                unsigned port = [display clientPortAtPosition:touch->point];
                
                int pathIndex = touch->index;
                RLog(@"Received Path Index: %d", pathIndex);
                if (pathIndex == 0) {
                    pathIndex = getExtraIndexNumber(Int2String(port));
                }
                
                SimulateTouchEvent(port, pathIndex, touch->type, touch->point);
                
                return (CFDataRef)[[NSData alloc] initWithBytes:&pathIndex length:sizeof(pathIndex)];
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

#define MACH_PORT_NAME "kr.iolate.simulatetouch"


MSInitialize {
    MSHookFunction(&GSSendEvent, MSHake(GSSendEvent));
    STTouches = [[NSMutableDictionary alloc] init];
    
    CFMessagePortRef local = CFMessagePortCreateLocal(NULL, CFSTR(MACH_PORT_NAME), messageCallBack, NULL, NULL);
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, local, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode); 
}