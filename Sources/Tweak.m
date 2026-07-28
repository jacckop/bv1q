#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "WGTranslations.h"

/*
 * WhitegramArabic NodeFix v6
 *
 * v4 scheduled a complete window scan every time an _ASDisplayView entered a
 * window. Telegram Settings creates many Texture views at once, so hundreds of
 * delayed full-tree scans could pile up on the main thread and make the app
 * hang until iOS terminated it. v5 coalesced those callbacks, but it also
 * required a private runtime helper to write translated attributed strings.
 * That helper is absent on some iOS builds, so the scanner found every string
 * but silently skipped every Texture/Swift text node. v6 keeps the coalesced
 * scanner and restores a guarded ARC-aware fallback for those exact text ivars.
 */

#pragma mark - Runtime helpers

static void WGSendVoid(id object, SEL selector) {
    if (object && [object respondsToSelector:selector]) {
        ((void (*)(id, SEL))objc_msgSend)(object, selector);
    }
}

static id WGSendObject(id object, SEL selector) {
    if (object && [object respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    }
    return nil;
}

static Ivar WGFindIvar(Class cls, const char *name) {
    for (Class cursor = cls; cursor != Nil; cursor = class_getSuperclass(cursor)) {
        Ivar ivar = class_getInstanceVariable(cursor, name);
        if (ivar) {
            return ivar;
        }
    }
    return NULL;
}

typedef void (*WGStrongIvarSetter)(id object, Ivar ivar, id value);

static BOOL WGSetStrongObjectIvar(id object, Ivar ivar, id value) {
    if (!object || !ivar) {
        return NO;
    }

    const char *encoding = ivar_getTypeEncoding(ivar);
    if (!encoding || encoding[0] != '@') {
        return NO;
    }

    ptrdiff_t offset = ivar_getOffset(ivar);
    size_t instanceSize = class_getInstanceSize(object_getClass(object));
    if (offset < 0 || (size_t)offset + sizeof(id) > instanceSize) {
        return NO;
    }

    static WGStrongIvarSetter strongSetter = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        strongSetter = (WGStrongIvarSetter)dlsym(RTLD_DEFAULT, "object_setIvarWithStrongDefault");
    });

    // Under ARC, manually converting raw bytes into an id * slot is rejected by
    // Clang and caused the GitHub Actions build failure in v6. Prefer Apple's
    // private strong-ivar helper when exported, otherwise use object_setIvar.
    // The latter is the same runtime path used successfully by v4, while the
    // coalesced scanner below keeps the Telegram Settings crash fix from v5.
    if (strongSetter) {
        strongSetter(object, ivar, value);
    } else {
        object_setIvar(object, ivar, value);
    }

    id storedValue = object_getIvar(object, ivar);
    return storedValue == value || [storedValue isEqual:value];
}

static BOOL WGObjectIsKindOfRuntimeClass(id object, const char *className) {
    Class cls = objc_getClass(className);
    return cls && object && [object isKindOfClass:cls];
}

static BOOL WGIsKnownTextRenderable(id object) {
    if (!object) {
        return NO;
    }

    return WGObjectIsKindOfRuntimeClass(object, "_TtC7Display17ImmediateTextNode") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtC20TextNodeWithEntities29ImmediateTextNodeWithEntities") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtC7Display17ImmediateTextView") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtCC22MultilineTextComponent22MultilineTextComponent4View") ||
           WGObjectIsKindOfRuntimeClass(object, "_TtCC13ComponentFlow4TextP33_C336015A3F4BB8AB8C7F5EBEFE5DB6BF12MeasureState");
}

static void WGRefreshRenderable(id object) {
    if (!object) {
        return;
    }

    WGSendVoid(object, NSSelectorFromString(@"invalidateCalculatedLayout"));
    WGSendVoid(object, NSSelectorFromString(@"setNeedsLayout"));
    WGSendVoid(object, NSSelectorFromString(@"setNeedsDisplay"));
    WGSendVoid(object, NSSelectorFromString(@"__setNeedsLayout"));
    WGSendVoid(object, NSSelectorFromString(@"__setNeedsDisplay"));

    id view = WGSendObject(object, NSSelectorFromString(@"view"));
    if ([view isKindOfClass:UIView.class]) {
        [(UIView *)view setNeedsLayout];
        [(UIView *)view setNeedsDisplay];
    }
}

static BOOL WGTranslateAttributedTextIvar(id object) {
    if (!WGIsKnownTextRenderable(object)) {
        return NO;
    }

    Ivar ivar = WGFindIvar(object_getClass(object), "attributedText");
    if (!ivar) {
        return NO;
    }

    id value = object_getIvar(object, ivar);
    if (![value isKindOfClass:NSAttributedString.class]) {
        return NO;
    }

    NSAttributedString *source = (NSAttributedString *)value;
    NSAttributedString *translated = WGArabicTranslateAttributedStringExact(source);
    if (!translated || [translated.string isEqualToString:source.string]) {
        return NO;
    }

    if (!WGSetStrongObjectIvar(object, ivar, translated)) {
        return NO;
    }

    WGRefreshRenderable(object);
    return YES;
}

static BOOL WGTranslateComponentTextView(id view) {
    if (!WGObjectIsKindOfRuntimeClass(view, "_TtCC13ComponentFlow4Text4View")) {
        return NO;
    }

    Ivar stateIvar = WGFindIvar(object_getClass(view), "measureState");
    if (!stateIvar) {
        return NO;
    }

    id state = object_getIvar(view, stateIvar);
    if (WGTranslateAttributedTextIvar(state)) {
        WGRefreshRenderable(view);
        return YES;
    }
    return NO;
}

#pragma mark - Visible node scanning

static NSUInteger WGScanDisplayNode(id node,
                                    NSMutableSet<NSValue *> *visited,
                                    NSUInteger depth) {
    if (!node || depth > 48 || visited.count > 1400) {
        return 0;
    }

    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)node];
    if ([visited containsObject:identity]) {
        return 0;
    }
    [visited addObject:identity];

    NSUInteger changes = WGTranslateAttributedTextIvar(node) ? 1 : 0;
    id subnodes = WGSendObject(node, NSSelectorFromString(@"subnodes"));
    if ([subnodes isKindOfClass:NSArray.class]) {
        for (id child in (NSArray *)subnodes) {
            changes += WGScanDisplayNode(child, visited, depth + 1);
        }
    }
    return changes;
}

static NSUInteger WGTranslateExistingUIKitView(UIView *view) {
    NSUInteger changes = 0;

    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.attributedText.length > 0) {
            NSAttributedString *translated = WGArabicTranslateAttributedString(label.attributedText);
            if (![translated.string isEqualToString:label.attributedText.string]) {
                label.attributedText = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
                changes++;
            }
        } else if (label.text.length > 0) {
            NSString *translated = WGArabicTranslateString(label.text);
            if (![translated isEqualToString:label.text]) {
                label.text = translated;
                label.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
                label.textAlignment = NSTextAlignmentNatural;
                changes++;
            }
        }
    } else if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        if (field.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(field.placeholder);
            if (![translated isEqualToString:field.placeholder]) {
                field.placeholder = translated;
                changes++;
            }
        }
    } else if ([view isKindOfClass:UISearchBar.class]) {
        UISearchBar *searchBar = (UISearchBar *)view;
        if (searchBar.placeholder.length > 0) {
            NSString *translated = WGArabicTranslateString(searchBar.placeholder);
            if (![translated isEqualToString:searchBar.placeholder]) {
                searchBar.placeholder = translated;
                changes++;
            }
        }
    }

    return changes;
}

static NSUInteger WGScanViewTree(UIView *view,
                                 NSMutableSet<NSValue *> *visitedNodes,
                                 NSUInteger depth) {
    if (!view || depth > 72 || visitedNodes.count > 1600) {
        return 0;
    }

    NSUInteger changes = WGTranslateExistingUIKitView(view);
    changes += WGTranslateAttributedTextIvar(view) ? 1 : 0;
    changes += WGTranslateComponentTextView(view) ? 1 : 0;

    id node = WGSendObject(view, NSSelectorFromString(@"asyncdisplaykit_node"));
    if (node) {
        changes += WGScanDisplayNode(node, visitedNodes, 0);
    }

    for (UIView *subview in view.subviews) {
        changes += WGScanViewTree(subview, visitedNodes, depth + 1);
    }
    return changes;
}

static NSArray<UIWindow *> *WGVisibleWindows(void) {
    UIApplication *application = UIApplication.sharedApplication;
    NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01) {
                    [windows addObject:window];
                }
            }
        }
    }

    if (windows.count == 0) {
        for (UIWindow *window in application.windows) {
            if (!window.hidden && window.alpha > 0.01) {
                [windows addObject:window];
            }
        }
    }
    return windows.array;
}

static void WGScanAllVisibleWindows(void) {
    if (!WGArabicLocalizationEnabled()) {
        return;
    }

    @autoreleasepool {
        NSMutableSet<NSValue *> *visitedNodes = [NSMutableSet set];
        for (UIWindow *window in WGVisibleWindows()) {
            WGScanViewTree(window, visitedNodes, 0);
        }
    }
}

#pragma mark - Coalesced scan scheduler

static BOOL WGScanPending = NO;
static BOOL WGScanInProgress = NO;
static CFAbsoluteTime WGLastScanTime = 0;

static void WGScheduleVisibleScanAfter(NSTimeInterval requestedDelay) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            WGScheduleVisibleScanAfter(requestedDelay);
        });
        return;
    }

    if (WGScanPending || WGScanInProgress) {
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSTimeInterval throttleRemaining = MAX(0.0, 0.22 - (now - WGLastScanTime));
    NSTimeInterval delay = MAX(requestedDelay, throttleRemaining);
    WGScanPending = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        WGScanPending = NO;
        if (WGScanInProgress) {
            return;
        }

        WGScanInProgress = YES;
        WGScanAllVisibleWindows();
        WGLastScanTime = CFAbsoluteTimeGetCurrent();
        WGScanInProgress = NO;
    });
}

#pragma mark - Stable UIKit hooks

@interface UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text;
- (void)wg_nf_setAttributedText:(NSAttributedString *)text;
@end

@implementation UILabel (WGArabicNodeFix)
- (void)wg_nf_setText:(NSString *)text {
    NSString *translated = WGArabicTranslateString(text);
    [self wg_nf_setText:translated];
    if (text && ![translated isEqualToString:text]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}
- (void)wg_nf_setAttributedText:(NSAttributedString *)text {
    NSAttributedString *translated = WGArabicTranslateAttributedString(text);
    [self wg_nf_setAttributedText:translated];
    if (text && ![translated.string isEqualToString:text.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
        self.textAlignment = NSTextAlignmentNatural;
    }
}
@end

@interface UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state;
- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state;
@end

@implementation UIButton (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title forState:(UIControlState)state {
    NSString *translated = WGArabicTranslateString(title);
    [self wg_nf_setTitle:translated forState:state];
    if (title && ![translated isEqualToString:title]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}
- (void)wg_nf_setAttributedTitle:(NSAttributedString *)title forState:(UIControlState)state {
    NSAttributedString *translated = WGArabicTranslateAttributedString(title);
    [self wg_nf_setAttributedTitle:translated forState:state];
    if (title && ![translated.string isEqualToString:title.string]) {
        self.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    }
}
@end

@interface UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UITextField (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
@end

@implementation UINavigationItem (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}
@end

@interface UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title;
- (void)wg_nf_viewDidAppear:(BOOL)animated;
@end

@implementation UIViewController (WGArabicNodeFix)
- (void)wg_nf_setTitle:(NSString *)title {
    [self wg_nf_setTitle:WGArabicTranslateString(title)];
}
- (void)wg_nf_viewDidAppear:(BOOL)animated {
    [self wg_nf_viewDidAppear:animated];
    WGScheduleVisibleScanAfter(0.10);
}
@end

@interface UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder;
@end

@implementation UISearchBar (WGArabicNodeFix)
- (void)wg_nf_setPlaceholder:(NSString *)placeholder {
    [self wg_nf_setPlaceholder:WGArabicTranslateString(placeholder)];
}
@end

@interface UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle;
@end

@implementation UIAlertController (WGArabicNodeFix)
+ (instancetype)wg_nf_alertControllerWithTitle:(NSString *)title
                                        message:(NSString *)message
                                 preferredStyle:(UIAlertControllerStyle)preferredStyle {
    return [self wg_nf_alertControllerWithTitle:WGArabicTranslateString(title)
                                        message:WGArabicTranslateString(message)
                                 preferredStyle:preferredStyle];
}
@end

@interface UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action;
@end

@implementation UIBarButtonItem (WGArabicNodeFix)
- (instancetype)wg_nf_initWithTitle:(NSString *)title
                              style:(UIBarButtonItemStyle)style
                             target:(id)target
                             action:(SEL)action {
    return [self wg_nf_initWithTitle:WGArabicTranslateString(title)
                               style:style
                              target:target
                              action:action];
}
@end

static void WGSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        return;
    }

    BOOL added = class_addMethod(cls,
                                 original,
                                 method_getImplementation(replacementMethod),
                                 method_getTypeEncoding(replacementMethod));
    if (added) {
        class_replaceMethod(cls,
                            replacement,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

static void WGSwizzleClass(Class cls, SEL original, SEL replacement) {
    WGSwizzle(object_getClass(cls), original, replacement);
}

static void WGInstallUIKitHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // NSBundle and UITextView are deliberately not hooked in v6. Both are
        // app-wide data paths, not display-only APIs, and can affect Telegram's
        // internal logic or user-entered message content.
        WGSwizzle(UILabel.class, @selector(setText:), @selector(wg_nf_setText:));
        WGSwizzle(UILabel.class, @selector(setAttributedText:), @selector(wg_nf_setAttributedText:));
        WGSwizzle(UIButton.class, @selector(setTitle:forState:), @selector(wg_nf_setTitle:forState:));
        WGSwizzle(UIButton.class,
                  @selector(setAttributedTitle:forState:),
                  @selector(wg_nf_setAttributedTitle:forState:));
        WGSwizzle(UITextField.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzle(UINavigationItem.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(setTitle:), @selector(wg_nf_setTitle:));
        WGSwizzle(UIViewController.class, @selector(viewDidAppear:), @selector(wg_nf_viewDidAppear:));
        WGSwizzle(UISearchBar.class, @selector(setPlaceholder:), @selector(wg_nf_setPlaceholder:));
        WGSwizzleClass(UIAlertController.class,
                       @selector(alertControllerWithTitle:message:preferredStyle:),
                       @selector(wg_nf_alertControllerWithTitle:message:preferredStyle:));
        WGSwizzle(UIBarButtonItem.class,
                  @selector(initWithTitle:style:target:action:),
                  @selector(wg_nf_initWithTitle:style:target:action:));
    });
}

#pragma mark - Exact _ASDisplayView hook

static IMP WGOriginalASDisplayViewDidMoveToWindow = NULL;
static BOOL WGASDisplayViewHookInstalled = NO;

static void WGASDisplayViewDidMoveToWindow(id self, SEL _cmd) {
    if (WGOriginalASDisplayViewDidMoveToWindow) {
        ((void (*)(id, SEL))WGOriginalASDisplayViewDidMoveToWindow)(self, _cmd);
    }

    // A single coalesced pass replaces v4's five-pass burst for every row.
    WGScheduleVisibleScanAfter(0.14);
}

static void WGInstallASDisplayViewHook(void) {
    if (WGASDisplayViewHookInstalled) {
        return;
    }

    Class cls = objc_getClass("_ASDisplayView");
    SEL selector = sel_registerName("didMoveToWindow");
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) {
        return;
    }

    WGOriginalASDisplayViewDidMoveToWindow = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    class_replaceMethod(cls, selector, (IMP)WGASDisplayViewDidMoveToWindow, types);
    WGASDisplayViewHookInstalled = YES;
}

#pragma mark - Entry point

__attribute__((constructor))
static void WGArabicNodeFixEntryPoint(void) {
    @autoreleasepool {
        WGInstallUIKitHooks();
        WGInstallASDisplayViewHook();

        dispatch_async(dispatch_get_main_queue(), ^{
            WGInstallASDisplayViewHook();
            WGScheduleVisibleScanAfter(0.35);
        });
    }
}
