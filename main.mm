#import <CoreGraphics/CoreGraphics.h>

typedef enum {
    UIInterfaceOrientationPortrait           = 1,//UIDeviceOrientationPortrait,
    UIInterfaceOrientationPortraitUpsideDown = 2,//UIDeviceOrientationPortraitUpsideDown,
    UIInterfaceOrientationLandscapeLeft      = 4,//UIDeviceOrientationLandscapeRight,
    UIInterfaceOrientationLandscapeRight     = 3,//UIDeviceOrientationLandscapeLeft
} UIInterfaceOrientation;

@interface SimulateTouch
+(CGPoint)STScreenToWindowPoint:(CGPoint)point withOrientation:(int)orientation;
+(CGPoint)STWindowToScreenPoint:(CGPoint)point withOrientation:(int)orientation;
+(int)simulateTouch:(int)pathIndex atPoint:(CGPoint)point withType:(int)type;
+(int)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint duration:(float)duration;
@end

#define PRINT_USAGE printf("[Usage]\n 1. Touch:\n    %s touch x y [orientation]\n\n 2. Swipe:\n   %s swipe fromX fromY toX toY [duration(0.3)] [orientation]\n\n[Example]\n   # %s touch 50 100\n   # %s swipe 50 100 100 200 0.5\n\n[Orientation]\n    Portrait:1 UpsideDown:2 Right:3 Left:4\n", argv[0], argv[0], argv[0], argv[0]);

int main(int argc, char **argv, char **envp) {
    if (argc == 1) {
        PRINT_USAGE;
        return 0;
    }
    
    if (!strcmp(argv[1], "touch")) {
        if (argc != 4 && argc != 5) {
            PRINT_USAGE;
            return 0;
        }
        
        if (argc == 4) {
            int x = atoi(argv[2]);
            int y = atoi(argv[3]);
            
            int r = [SimulateTouch simulateTouch:0 atPoint:CGPointMake(x, y) withType:1];
            [SimulateTouch simulateTouch:r atPoint:CGPointMake(x, y) withType:2];
        }else if (argc == 5) {
            int px = atoi(argv[2]);
            int py = atoi(argv[3]);
            CGPoint p = CGPointMake(px, py);
            
            CGPoint rp = [SimulateTouch STWindowToScreenPoint:p withOrientation:atoi(argv[4])];
            int r = [SimulateTouch simulateTouch:0 atPoint:rp withType:1];
            [SimulateTouch simulateTouch:r atPoint:rp withType:2];
        }
        
    }else if (!strcmp(argv[1], "swipe")) {
        if (argc < 6 || argc > 8) {
            PRINT_USAGE;
            return 0;
        }
        
        float duration = 0.3f;
        if (argc == 6) {
            CGPoint fromPoint = CGPointMake(atoi(argv[2]), atoi(argv[3]));
            CGPoint toPoint = CGPointMake(atoi(argv[4]), atoi(argv[5]));
            
            [SimulateTouch simulateSwipeFromPoint:fromPoint toPoint:toPoint duration:duration];
        }else if (argc == 7) {
            CGPoint fromPoint = CGPointMake(atoi(argv[2]), atoi(argv[3]));
            CGPoint toPoint = CGPointMake(atoi(argv[4]), atoi(argv[5]));
            duration = atof(argv[6]);
            [SimulateTouch simulateSwipeFromPoint:fromPoint toPoint:toPoint duration:duration];
        }else if (argc == 8) {
            CGPoint pfromPoint = CGPointMake(atoi(argv[2]), atoi(argv[3]));
            CGPoint ptoPoint = CGPointMake(atoi(argv[4]), atoi(argv[5]));
            
            CGPoint fromPoint = [SimulateTouch STWindowToScreenPoint:pfromPoint withOrientation:atoi(argv[7])];
            CGPoint toPoint = [SimulateTouch STWindowToScreenPoint:ptoPoint withOrientation:atoi(argv[7])];
            
            duration = atof(argv[6]);
            [SimulateTouch simulateSwipeFromPoint:fromPoint toPoint:toPoint duration:duration];
        }
        
        CFRunLoopRunInMode(kCFRunLoopDefaultMode , duration+0.1f, NO);
    }else{
        PRINT_USAGE;
        return 0;
    }
    
    return 0;
}