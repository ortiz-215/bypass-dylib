// bypass.m — dylib de bypass de login
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "fishhook.h"

#define LOG(fmt, ...) NSLog(@"[bypass] " fmt, ##__VA_ARGS__)

#pragma mark - interruptor

static BOOL bpEnabled(void) {
    return ![[NSFileManager defaultManager] fileExistsAtPath:
             [NSTemporaryDirectory() stringByAppendingPathComponent:@"bypass.off"]];
}

#pragma mark - helpers

static Class bpCls(NSString *name) {
    Class c = NSClassFromString(name);
    if (!c) LOG(@"NO existe la clase %@", name);
    return c;
}

static void bpSwz(Class cls, SEL orig, SEL repl) {
    if (!cls) { LOG(@"clase nula: %@", NSStringFromSelector(orig)); return; }
    Method a = class_getInstanceMethod(cls, orig);
    Method b = class_getInstanceMethod(cls, repl);
    if (!a || !b) {
        LOG(@"falta metodo en %@: %@", cls, NSStringFromSelector(a ? repl : orig));
        return;
    }
    if (class_addMethod(cls, orig, method_getImplementation(b), method_getTypeEncoding(b)))
        class_replaceMethod(cls, repl, method_getImplementation(a), method_getTypeEncoding(a));
    else
        method_exchangeImplementations(a, b);
    LOG(@"swizzled %@ -%@", cls, NSStringFromSelector(orig));
}

static void bpForceBool(Class cls, SEL sel, BOOL value) {
    if (!cls) { LOG(@"clase nula para %@", NSStringFromSelector(sel)); return; }
    BOOL (^blk)(id) = ^BOOL(id self) { return value; };
    class_replaceMethod(cls, sel, imp_implementationWithBlock(blk), "c@:");
    LOG(@"forzado %@ -%@ => %d", cls, NSStringFromSelector(sel), value);
}

static void bpForceObject(Class cls, SEL sel, id value) {
    if (!cls) { LOG(@"clase nula para %@", NSStringFromSelector(sel)); return; }
    id (^blk)(id) = ^id(id self) { return value; };
    class_replaceMethod(cls, sel, imp_implementationWithBlock(blk), "@@:");
    LOG(@"forzado %@ -%@ => %@", cls, NSStringFromSelector(sel), value);
}

#pragma mark - capa 1: estado de sesion

static void bpPatchAuthState(void) {
    Class auth = bpCls(@"AuthManager");
    bpForceBool(auth, @selector(isLoggedIn), YES);
    bpForceBool(auth, @selector(isAuthenticated), YES);
    bpForceObject(auth, @selector(accessToken), @"bypass-token");
    bpForceObject(auth, @selector(authToken), @"bypass-token");
}

#pragma mark - capa 2: UI

@interface NSObject (BPUI)
- (void)bp_viewDidAppear:(BOOL)animated;
- (void)bp_application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts;
@end

@implementation NSObject (BPUI)

- (void)bp_application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    [self bp_application:app didFinishLaunchingWithOptions:opts];
    LOG(@"didFinishLaunching interceptado");
}

- (void)bp_viewDidAppear:(BOOL)animated {
    [self bp_viewDidAppear:animated];

    UIWindow *win = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) {
            id del = ((UIWindowScene *)s).delegate;
            if ([del respondsToSelector:@selector(window)]) win = [del window];
        }
    }
    if (!win) win = UIApplication.sharedApplication.windows.firstObject;

    Class mainCls = bpCls(@"MainTabBarController");
    if (!mainCls || !win) return;

    if ([win.rootViewController isKindOfClass:mainCls]) return;

    UIViewController *main = [[mainCls alloc] init];
    [UIView transitionWithView:win duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ win.rootViewController = main; }
                    completion:nil];
    LOG(@"root cambiado a %@", mainCls);
}

@end

#pragma mark - capa 3: keychain

static OSStatus (*bp_orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus bp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus st = bp_orig_SecItemCopyMatching(query, result);
    if (st != errSecSuccess && result) {
        *result = (__bridge_retained CFTypeRef)
            [@"bypass-token" dataUsingEncoding:NSUTF8StringEncoding];
        LOG(@"keychain miss -> token falso");
        return errSecSuccess;
    }
    return st;
}

#pragma mark - arranque

static void bpSetup(void) {
    bpPatchAuthState();

    bpSwz(bpCls(@"LoginViewController"),
          @selector(viewDidAppear:), @selector(bp_viewDidAppear:));

    bpSwz(bpCls(@"AppDelegate"),
          @selector(application:didFinishLaunchingWithOptions:),
          @selector(bp_application:didFinishLaunchingWithOptions:));

    struct rebinding rb[] = {
        { "SecItemCopyMatching", bp_SecItemCopyMatching,
          (void **)&bp_orig_SecItemCopyMatching },
    };
    rebind_symbols(rb, 1);

    LOG(@"bypass activo");
}

__attribute__((constructor))
static void bpInit(void) {
    if (!bpEnabled()) { LOG(@"bypass desactivado"); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ bpSetup(); });
}
