#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>
#import <unistd.h>

@interface VSVimTestScrollEvent : NSEvent
@property NSPoint testLocation;
@property CGFloat testDeltaX;
@property CGFloat testDeltaY;
@property NSInteger testWindowNumber;
@end
@implementation VSVimTestScrollEvent
- (NSEventType)type { return NSEventTypeScrollWheel; }
- (NSPoint)locationInWindow { return self.testLocation; }
- (CGFloat)scrollingDeltaX { return self.testDeltaX; }
- (CGFloat)scrollingDeltaY { return self.testDeltaY; }
- (BOOL)hasPreciseScrollingDeltas { return YES; }
- (NSEventPhase)phase { return NSEventPhaseChanged; }
- (NSEventModifierFlags)modifierFlags { return 0; }
- (NSInteger)windowNumber { return self.testWindowNumber; }
@end

static void capture_own_window(NSString *path) {
    NSWindow *target = NSApp.keyWindow ?: NSApp.mainWindow;
    if (!target) target = NSApp.windows.firstObject;
    if (!target) return;
    CGWindowID wanted = (CGWindowID)target.windowNumber;
    CGFloat scale = target.backingScaleFactor;
    [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        SCWindow *selected = nil;
        for (SCWindow *window in content.windows) if (window.windowID == wanted) { selected = window; break; }
        if (!selected) {
            NSString *message = error.localizedDescription ?: @"Own test window unavailable";
            [message writeToFile:[path stringByAppendingString:@".error"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            return;
        }
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:selected];
        SCStreamConfiguration *config = [SCStreamConfiguration new];
        config.width = (size_t)(selected.frame.size.width * scale);
        config.height = (size_t)(selected.frame.size.height * scale);
        config.showsCursor = NO;
        [SCScreenshotManager captureImageWithFilter:filter configuration:config completionHandler:^(CGImageRef image, NSError *failure) {
            if (!image) {
                [(failure.localizedDescription ?: @"No capture image") writeToFile:[path stringByAppendingString:@".error"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
                return;
            }
            NSURL *url = [NSURL fileURLWithPath:path];
            CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
            if (destination) {
                CGImageDestinationAddImage(destination, image, NULL);
                CGImageDestinationFinalize(destination);
                CFRelease(destination);
            }
        }];
    }];
}


static void perform_test_action(NSWindow *window, NSDictionary *action) {
    NSString *kind = action[@"type"];
    if ([kind isEqualToString:@"metadata"]) {
        NSDictionary *metadata=@{@"active":@(NSApp.isActive), @"key":@(window.isKeyWindow), @"visible":@(window.isVisible), @"occluded":@(!(window.occlusionState & NSWindowOcclusionStateVisible)), @"scale":@(window.backingScaleFactor), @"width":@(window.frame.size.width), @"height":@(window.frame.size.height)};
        [[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil] writeToFile:action[@"path"] atomically:YES];return;
    }
    static NSRunningApplication *previousFront;
    if ([kind isEqualToString:@"activate"]) {
        previousFront=NSWorkspace.sharedWorkspace.frontmostApplication;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSRunningApplication.currentApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        [NSApp activateIgnoringOtherApps:YES];[window makeKeyAndOrderFront:nil];return;
    }
    if ([kind isEqualToString:@"restore-front"]) {
        if (previousFront && previousFront.processIdentifier!=NSProcessInfo.processInfo.processIdentifier) [previousFront activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        previousFront=nil;return;
    }
    if ([kind isEqualToString:@"capture"]) { capture_own_window(action[@"path"]); return; }
    if ([kind isEqualToString:@"resize"]) {
        NSRect frame = window.frame;
        frame.size = NSMakeSize([action[@"width"] doubleValue], [action[@"height"] doubleValue]);
        [window setFrame:frame display:YES]; return;
    }
    double x=[action[@"x"] doubleValue], y=[action[@"y"] doubleValue];
    NSPoint point = NSMakePoint(x, window.frame.size.height-y);
    if ([kind isEqualToString:@"wheel"]) {
        VSVimTestScrollEvent *event = [VSVimTestScrollEvent new];
        event.testLocation=point;
        event.testDeltaX=[action[@"dx"] doubleValue];
        event.testDeltaY=[action[@"dy"] doubleValue];
        event.testWindowNumber=window.windowNumber;
        NSView *target = [window.contentView hitTest:point] ?: window.contentView;
        [target scrollWheel:event];
        return;
    }
    NSTimeInterval stamp = NSProcessInfo.processInfo.systemUptime;
    NSEventModifierFlags flags = [action[@"cmd"] boolValue] ? NSEventModifierFlagCommand : 0;
    if ([action[@"shift"] boolValue]) flags |= NSEventModifierFlagShift;
    if ([action[@"ctrl"] boolValue]) flags |= NSEventModifierFlagControl;
    if ([kind isEqualToString:@"key"]) {
        NSString *text = action[@"text"] ?: @"";
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:stamp windowNumber:window.windowNumber context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:[action[@"code"] unsignedShortValue]];
        [window sendEvent:event]; return;
    }
    NSDictionary *types=@{@"down":@(NSEventTypeLeftMouseDown), @"up":@(NSEventTypeLeftMouseUp), @"move":@(NSEventTypeMouseMoved), @"drag":@(NSEventTypeLeftMouseDragged)};
    NSNumber *type=types[kind];
    if (type) {
        NSEvent *event = [NSEvent mouseEventWithType:(NSEventType)type.unsignedIntegerValue location:point modifierFlags:flags timestamp:stamp windowNumber:window.windowNumber context:nil eventNumber:1 clickCount:action[@"count"] ? [action[@"count"] integerValue] : 1 pressure:[kind isEqualToString:@"up"] ? 0 : 1];
        [window sendEvent:event];
    }
}

__attribute__((constructor)) static void schedule_minimap_capture(void) {
    if (strcmp(getprogname(), "sprite") != 0) return;
    const char *capture_path = getenv("VSVIM_CAPTURE_PATH");
    if (capture_path) {
        NSString *path = [NSString stringWithUTF8String:capture_path];
        double delay = getenv("VSVIM_CAPTURE_DELAY") ? atof(getenv("VSVIM_CAPTURE_DELAY")) : 20.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ capture_own_window(path); });
    }
    const char *control_path = getenv("VSVIM_CONTROL_PATH");
    if (control_path) {
        NSString *path = [NSString stringWithUTF8String:control_path];
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),100*NSEC_PER_MSEC,10*NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer,^{
            NSData *data=[NSData dataWithContentsOfFile:path];
            if (!data) return;
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            NSArray *actions=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSWindow *window=NSApp.keyWindow ?: NSApp.mainWindow ?: NSApp.windows.firstObject;
            if (!window || ![actions isKindOfClass:NSArray.class]) return;
            for (NSDictionary *action in actions) perform_test_action(window,action);
            [@"done" writeToFile:[path stringByAppendingString:@".done"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        });
        dispatch_resume(timer);
    }
}
