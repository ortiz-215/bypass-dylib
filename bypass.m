// recon.m — vuelca la estructura de la app en pantalla
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

static NSArray *bpKw(void) {
    return @[@"key", @"auth", @"login", @"licen", @"session", @"token",
             @"api", @"rx7", @"modz", @"user", @"account", @"activ",
             @"valid", @"subscri", @"premium"];
}

static BOOL bpMatch(NSString *s) {
    NSString *l = s.lowercaseString;
    for (NSString *k in bpKw()) if ([l containsString:k]) return YES;
    return NO;
}

static NSString *bpReport(void) {
    NSMutableString *o = [NSMutableString string];
    NSBundle *b = [NSBundle mainBundle];

    [o appendFormat:@"BUNDLE: %@\nVERSION: %@\nEXEC: %@\n\n",
        b.bundleIdentifier, [b objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
        b.executablePath];

    // --- frameworks / dylibs cargados ---
    [o appendString:@"==== IMAGENES CARGADAS ====\n"];
    uint32_t n = _dyld_image_count();
    NSMutableArray *imgs = [NSMutableArray array];
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm) [imgs addObject:[NSString stringWithUTF8String:nm]];
    }
    [o appendFormat:@"total: %lu\n", (unsigned long)imgs.count];
    for (NSString *s in imgs) {
        if (bpMatch(s) || [s containsString:@".app/"] || [s containsString:@"Frameworks/"])
            [o appendFormat:@"%@\n", s.lastPathComponent];
    }

    NSString *blob = [imgs componentsJoinedByString:@" "].lowercaseString;
    [o appendString:@"\nVEREDICTO: "];
    if ([blob containsString:@"flutter"]) [o appendString:@"FLUTTER\n"];
    else if ([blob containsString:@"react"] || [blob containsString:@"hermes"] || [blob containsString:@"jsc"]) [o appendString:@"REACT NATIVE\n"];
    else if ([blob containsString:@"unity"]) [o appendString:@"UNITY\n"];
    else if ([blob containsString:@"cordova"] || [blob containsString:@"capacitor"]) [o appendString:@"WEBVIEW / HIBRIDA\n"];
    else [o appendString:@"NATIVA (objc/swift)\n"];

    // --- contenido del bundle ---
    NSString *root = b.bundlePath;
    for (NSString *sub in @[@"", @"Frameworks"]) {
        NSString *d = [root stringByAppendingPathComponent:sub];
        NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:d error:nil];
        [o appendFormat:@"\n==== ARCHIVOS /%@ (%lu) ====\n", sub, (unsigned long)items.count];
        NSInteger c = 0;
        for (NSString *i in [items sortedArrayUsingSelector:@selector(compare:)]) {
            [o appendFormat:@"%@\n", i];
            if (++c > 120) { [o appendString:@"...\n"]; break; }
        }
    }

    // --- preferencias ---
    [o appendString:@"\n==== USERDEFAULTS ====\n"];
    NSDictionary *ud = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
    for (NSString *k in ud.allKeys) {
        NSString *v = [NSString stringWithFormat:@"%@", ud[k]];
        if (v.length > 120) v = [v substringToIndex:120];
        [o appendFormat:@"%@ = %@\n", k, v];
    }

    // --- clases ---
    [o appendString:@"\n==== CLASES CON COINCIDENCIAS ====\n"];
    int total = objc_getClassList(NULL, 0);
    Class *list = (Class *)malloc(sizeof(Class) * total);
    total = objc_getClassList(list, total);
    int shown = 0;
    for (int i = 0; i < total; i++) {
        NSString *cn = NSStringFromClass(list[i]);
        if (!bpMatch(cn)) continue;
        if ([cn hasPrefix:@"NS"] || [cn hasPrefix:@"UI"] || [cn hasPrefix:@"__"]) continue;
        if (shown++ > 60) { [o appendString:@"...\n"]; break; }
        [o appendFormat:@"\n### %@\n", cn];

        unsigned int mc = 0;
        Method *ms = class_copyMethodList(list[i], &mc);
        for (unsigned int j = 0; j < mc && j < 40; j++)
            [o appendFormat:@"  -%@\n", NSStringFromSelector(method_getName(ms[j]))];
        free(ms);

        Class meta = object_getClass(list[i]);
        unsigned int cc = 0;
        Method *cms = class_copyMethodList(meta, &cc);
        for (unsigned int j = 0; j < cc && j < 20; j++)
            [o appendFormat:@"  +%@\n", NSStringFromSelector(method_getName(cms[j]))];
        free(cms);
    }
    free(list);
    [o appendFormat:@"\nTOTAL CLASES: %d\n", total];
    return o;
}

@interface BPVC : UIViewController
@property (nonatomic, strong) NSString *text;
@end

@implementation BPVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.text = self.text;
    tv.editable = NO;
    tv.textColor = [UIColor greenColor];
    tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.95];
    tv.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    [self.view addSubview:tv];

    UIStackView *bar = [[UIStackView alloc] initWithFrame:CGRectZero];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.distribution = UIStackViewDistributionFillEqually;
    bar.spacing = 8;

    UIButton *cp = [UIButton buttonWithType:UIButtonTypeSystem];
    [cp setTitle:@"COPIAR" forState:UIControlStateNormal];
    [cp addTarget:self action:@selector(bpCopy) forControlEvents:UIControlEventTouchUpInside];

    UIButton *cl = [UIButton buttonWithType:UIButtonTypeSystem];
    [cl setTitle:@"CERRAR" forState:UIControlStateNormal];
    [cl addTarget:self action:@selector(bpClose) forControlEvents:UIControlEventTouchUpInside];

    [bar addArrangedSubview:cp];
    [bar addArrangedSubview:cl];
    [self.view addSubview:bar];

    [NSLayoutConstraint activateConstraints:@[
        [bar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [bar.heightAnchor constraintEqualToConstant:40],
        [tv.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:8],
        [tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)bpCopy {
    UIPasteboard.generalPasteboard.string = self.text;
}

- (void)bpClose {
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if ([w.rootViewController isKindOfClass:BPVC.class]) w.hidden = YES;
    }
}

@end

static UIWindow *gWin;

static void bpShow(NSString *t) {
    UIWindowScene *sc = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:UIWindowScene.class]) { sc = (UIWindowScene *)s; break; }
    }
    if (!sc) return;
    gWin = [[UIWindow alloc] initWithWindowScene:sc];
    gWin.windowLevel = UIWindowLevelAlert + 100;
    BPVC *vc = [BPVC new];
    vc.text = t;
    gWin.rootViewController = vc;
    gWin.hidden = NO;
}

__attribute__((constructor))
static void bpInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        @try {
            NSString *r = bpReport();
            NSLog(@"[recon]\n%@", r);
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            [r writeToFile:[docs stringByAppendingPathComponent:@"recon.txt"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
            bpShow(r);
        } @catch (NSException *e) {
            NSLog(@"[recon] excepcion %@", e);
        }
    });
}
