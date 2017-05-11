/*
 * Name: libSimulateTouch (kr.iolate.simulatetouch)
 * Author: iolate <iolate@me.com>
 *
 * http://api.iolate.kr/simulatetouch/
 *
 */

/*
typedef enum {
    UIInterfaceOrientationPortrait           = 1,//UIDeviceOrientationPortrait,
    UIInterfaceOrientationPortraitUpsideDown = 2,//UIDeviceOrientationPortraitUpsideDown,
    UIInterfaceOrientationLandscapeLeft      = 4,//UIDeviceOrientationLandscapeRight,
    UIInterfaceOrientationLandscapeRight     = 3,//UIDeviceOrientationLandscapeLeft
} UIInterfaceOrientation;
*/

typedef enum {
    STTouchMove = 0,
    STTouchDown,
    STTouchUp,

    // For these types, (int)point_x denotes button type
    STButtonUp,
    STButtonDown
} STTouchType;

//Library - libsimulatetouch.dylib
@interface SimulateTouch

//  Screen point: Absolute point (Portrait point)
//  Window point: Orientated point

//  Sreen point to window point. Portrait to 'orientation'
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(int)orientation;

//  Window point to screen point. 'orientation' to Portrait.
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(int)orientation;


//  if pathIndex is 0, SimulateTouch alloc its pathIndex.
//  retrun value is pathIndex. if 0, touch was failed.

//  Class methods' point is screen point.
+(int)simulateButtonEvent:(int)index button:(int)button state:(int)state;
+(int)simulateButton:(int)button state:(int)state;
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;
@end