typedef enum {
    STTouchMove = 0,
    STTouchDown,
    STTouchUp
} STTouchType;

@interface UIApplication (SimulateTouch)

//if pathIndex is 0, SimulateTouch alloc its pathIndex.
//retrun value is pathIndex. if 0, touch was failed.

-(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(STTouchType)type;
-(int)simulateSwipe:(int)pathIndex fromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint withType:(STTouchType)type;
@end