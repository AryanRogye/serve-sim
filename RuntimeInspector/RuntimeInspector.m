#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdarg.h>
#import <unistd.h>

static NSString *RIClassName(id object) {
    if (!object) return @"nil";
    return NSStringFromClass([object class]) ?: @"unknown";
}

static NSString *RIObjectDescription(id object) {
    if (!object) return @"nil";
    NSString *className = RIClassName(object);
    if ([object respondsToSelector:@selector(accessibilityIdentifier)]) {
        NSString *identifier = [object accessibilityIdentifier];
        if (identifier.length > 0) {
            return [NSString stringWithFormat:@"%@#%@", className, identifier];
        }
    }
    return className;
}

static NSString *RIControlEventsDescription(UIControlEvents events) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    if (events & UIControlEventTouchDown) [names addObject:@"touchDown"];
    if (events & UIControlEventTouchDownRepeat) [names addObject:@"touchDownRepeat"];
    if (events & UIControlEventTouchDragInside) [names addObject:@"touchDragInside"];
    if (events & UIControlEventTouchDragOutside) [names addObject:@"touchDragOutside"];
    if (events & UIControlEventTouchDragEnter) [names addObject:@"touchDragEnter"];
    if (events & UIControlEventTouchDragExit) [names addObject:@"touchDragExit"];
    if (events & UIControlEventTouchUpInside) [names addObject:@"touchUpInside"];
    if (events & UIControlEventTouchUpOutside) [names addObject:@"touchUpOutside"];
    if (events & UIControlEventTouchCancel) [names addObject:@"touchCancel"];
    if (events & UIControlEventValueChanged) [names addObject:@"valueChanged"];
    if (events & UIControlEventPrimaryActionTriggered) [names addObject:@"primaryActionTriggered"];
    if (events & UIControlEventEditingDidBegin) [names addObject:@"editingDidBegin"];
    if (events & UIControlEventEditingChanged) [names addObject:@"editingChanged"];
    if (events & UIControlEventEditingDidEnd) [names addObject:@"editingDidEnd"];
    if (events & UIControlEventEditingDidEndOnExit) [names addObject:@"editingDidEndOnExit"];
    if (names.count == 0) return [NSString stringWithFormat:@"0x%lx", (unsigned long)events];
    return [names componentsJoinedByString:@"|"];
}

static NSString *RICallStackDescription(void) {
    NSArray<NSString *> *symbols = [NSThread callStackSymbols];
    if (symbols.count == 0) return @"<empty>";
    return [symbols componentsJoinedByString:@"\n[RuntimeInspector] "];
}

static void RILogIntercept(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void RILogIntercept(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSLog(@"[RuntimeInspector] %@\n[RuntimeInspector] callStackSymbols:\n[RuntimeInspector] %@",
          message,
          RICallStackDescription());
}

static void RIExchangeInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        NSLog(@"[RuntimeInspector] swizzle skipped class=%@ original=%@ replacement=%@",
              NSStringFromClass(cls), NSStringFromSelector(original), NSStringFromSelector(replacement));
        return;
    }
    method_exchangeImplementations(originalMethod, replacementMethod);
    NSLog(@"[RuntimeInspector] swizzled %@ %@", NSStringFromClass(cls), NSStringFromSelector(original));
}

@interface UIApplication (RuntimeInspector)
- (BOOL)ri_sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event;
@end

@implementation UIApplication (RuntimeInspector)

- (BOOL)ri_sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    RILogIntercept(@"UIApplication.sendAction action=%@ target=%@ sender=%@ event=%@",
                   NSStringFromSelector(action),
                   RIObjectDescription(target),
                   RIObjectDescription(sender),
                   RIClassName(event));

    return [self ri_sendAction:action to:target from:sender forEvent:event];
}

@end

@interface UIControl (RuntimeInspector)
- (void)ri_addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents;
- (void)ri_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event;
@end

@implementation UIControl (RuntimeInspector)

- (void)ri_addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)controlEvents {
    RILogIntercept(@"UIControl.addTarget control=%@ target=%@ action=%@ events=%@",
                   RIObjectDescription(self),
                   RIObjectDescription(target),
                   NSStringFromSelector(action),
                   RIControlEventsDescription(controlEvents));

    [self ri_addTarget:target action:action forControlEvents:controlEvents];
}

- (void)ri_sendAction:(SEL)action to:(id)target forEvent:(UIEvent *)event {
    RILogIntercept(@"UIControl.sendAction control=%@ target=%@ action=%@ event=%@",
                   RIObjectDescription(self),
                   RIObjectDescription(target),
                   NSStringFromSelector(action),
                   RIClassName(event));

    [self ri_sendAction:action to:target forEvent:event];
}

@end

@interface UIGestureRecognizer (RuntimeInspector)
- (instancetype)ri_initWithTarget:(id)target action:(SEL)action;
- (void)ri_addTarget:(id)target action:(SEL)action;
@end

@implementation UIGestureRecognizer (RuntimeInspector)

- (instancetype)ri_initWithTarget:(id)target action:(SEL)action {
    RILogIntercept(@"UIGestureRecognizer.init recognizer=%@ target=%@ action=%@",
                   RIObjectDescription(self),
                   RIObjectDescription(target),
                   NSStringFromSelector(action));

    return [self ri_initWithTarget:target action:action];
}

- (void)ri_addTarget:(id)target action:(SEL)action {
    RILogIntercept(@"UIGestureRecognizer.addTarget recognizer=%@ target=%@ action=%@",
                   RIObjectDescription(self),
                   RIObjectDescription(target),
                   NSStringFromSelector(action));

    [self ri_addTarget:target action:action];
}

@end

__attribute__((constructor))
static void RuntimeInspectorInstall(void) {
    @autoreleasepool {
        NSLog(@"[RuntimeInspector] loaded pid=%d process=%@", getpid(), NSProcessInfo.processInfo.processName);

        RIExchangeInstanceMethod(
            UIApplication.class,
            @selector(sendAction:to:from:forEvent:),
            @selector(ri_sendAction:to:from:forEvent:)
        );

        RIExchangeInstanceMethod(
            UIControl.class,
            @selector(addTarget:action:forControlEvents:),
            @selector(ri_addTarget:action:forControlEvents:)
        );

        RIExchangeInstanceMethod(
            UIControl.class,
            @selector(sendAction:to:forEvent:),
            @selector(ri_sendAction:to:forEvent:)
        );

        RIExchangeInstanceMethod(
            UIGestureRecognizer.class,
            @selector(initWithTarget:action:),
            @selector(ri_initWithTarget:action:)
        );

        RIExchangeInstanceMethod(
            UIGestureRecognizer.class,
            @selector(addTarget:action:),
            @selector(ri_addTarget:action:)
        );
    }
}
