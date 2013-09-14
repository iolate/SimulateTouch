//
//  SimulateTouch.h
//  SimulateTouch 0.4
//  http://api.iolate.kr/simulatetouch/
//
//  Created by iolate, 2013
//

typedef enum {
    STTouchMove = 0,
    STTouchDown,
    STTouchUp
} STTouchType;

@interface UIApplication (SimulateTouch)

//  Screen point: Absolute point (Portrait point)
//  Window point: Orientated point

//  Sreen point to window point. Portrait to 'orientation'
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;

//  Window point to screen point. 'orientation' to Portrait.
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;


//  if pathIndex is 0, SimulateTouch alloc its pathIndex.
//  retrun value is pathIndex. if 0, touch was failed.

//  Class methods' point is screen point.
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;


//  Instance Methods are for compatibility with old versions.
//  Recommend to use class methods.
//  Instance methods' point is window point.
-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;

//  -simulateSwipe:fromPoint:toPoint:withType: -> pathIndex and type may not work. use 0 or any numbers.
//duration:0.3f
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(STTouchType)type;

@end

//Library - libsimulatetouch.dylib
@interface SimulateTouch
//Same as in UIApplication (SimulateTouch).
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(UIInterfaceOrientation)orientation;
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;
@end