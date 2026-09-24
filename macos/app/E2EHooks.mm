// Hooks for the end-to-end suite that drives the application from outside
// (a separate project, over the agent socket). Nothing here exists unless the
// process is started with NPPMAC_E2E=1: then the agent server gets e2e_* tools
// that look at what a user would see (menus, windows, controls, the
// Scintilla views, a picture of a window) and act as a user would (click,
// type, pick), and the modal panels a test cannot answer by hand - alerts,
// open and save panels - take queued answers instead of waiting. The
// clipboard is a private pasteboard, so a test never touches the user's.
#import <objc/runtime.h>
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "BehaviourCommands.h"
#import "AgentServer.h"
#import "AppDelegate+Testing.h"
#import "EditorController.h"
#import "ScintillaView.h"
#import "SettingsCommands.h"
#import "ShortcutMapper.h"
#import "CommandIDs.h"
#import "TabBarView.h"
#import "UpdateChecker.h"

typedef NSDictionary *_Nullable (^NppE2EToolBlock)(NSDictionary *args, NSError **error);

@interface NppAgentServer (E2EPrivate)
- (void)addTool:(NSString *)name description:(NSString *)description schema:(NSDictionary *)schema
        handler:(NppE2EToolBlock)handler;
@end

BOOL NppE2EEnabled(void) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ enabled = getenv("NPPMAC_E2E") != NULL; });
    return enabled;
}

static NSError *E2EFail(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *E2EFail(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:@"NppE2E" code:1 userInfo:@{NSLocalizedDescriptionKey: text}];
}

static NSDictionary *E2ESchema(NSDictionary *properties) {
    return @{@"type": @"object", @"properties": properties ?: @{}};
}

static NSString *E2EString(id value) {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSAttributedString class]]) return [value string];
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return value ? [value description] : nil;
}

static NSRect E2EScreenFrame(NSView *view) {
    if (!view.window) return view.frame;
    return [view.window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
}

static NSArray *E2ERect(NSRect r) { return @[@(round(r.origin.x)), @(round(r.origin.y)), @(round(r.size.width)), @(round(r.size.height))]; }

#pragma mark - Queued answers for modal panels

@interface NppE2EState : NSObject
@property (nonatomic, strong) NSMutableArray *alertAnswers;   // NSNumber (1-based button) or NSString (button title)
@property (nonatomic, strong) NSMutableArray *panelAnswers;   // NSString path, NSArray of paths, or NSNull = cancel
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *log;
@property (nonatomic) BOOL realModals;                        // no queued answer: run the real modal loop
@end

@implementation NppE2EState
+ (instancetype)shared {
    static NppE2EState *state;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        state = [NppE2EState new];
        state.alertAnswers = [NSMutableArray array];
        state.panelAnswers = [NSMutableArray array];
        state.log = [NSMutableArray array];
    });
    return state;
}
@end

static const void *kPanelURLs = &kPanelURLs;

static long gE2EBeeps, gE2EMutedBeeps;
void NppE2ECountBeep(BOOL muted) {
    if (!NppE2EEnabled()) return;
    if (muted) gE2EMutedBeeps++; else gE2EBeeps++;
}

/// Sets the controls of an alert's accessory view from an answer:
/// states {title: 0/1} for check boxes and radio buttons, fields [text...] for
/// its editable text fields in order, popups {index-or-title-of-popup: item}.
static void E2EFillAccessory(NSView *root, NSDictionary *answer) {
    if (!root) return;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithObject:root];
    NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
    NSMutableArray<NSPopUpButton *> *popups = [NSMutableArray array];
    for (NSUInteger i = 0; i < views.count; ++i) {
        NSView *v = views[i];
        [views addObjectsFromArray:v.subviews];
        if ([v isKindOfClass:[NSPopUpButton class]]) { [popups addObject:(NSPopUpButton *)v]; continue; }
        if ([v isKindOfClass:[NSButton class]]) {
            NSButton *b = (NSButton *)v;
            id want = answer[@"states"][b.title];
            if (want) { b.state = [want integerValue] ? NSControlStateValueOn : NSControlStateValueOff; if (b.action) [NSApp sendAction:b.action to:b.target from:b]; }
        } else if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable]) {
            [fields addObject:(NSTextField *)v];
        }
    }
    NSArray *texts = answer[@"fields"];
    if (!texts && answer[@"field"]) texts = @[answer[@"field"]];
    for (NSUInteger i = 0; i < texts.count && i < fields.count; ++i) fields[i].stringValue = E2EString(texts[i]) ?: @"";
    NSDictionary *choices = answer[@"popups"];
    for (id key in choices) {
        NSUInteger index = [key integerValue];
        if (index >= popups.count) continue;
        id item = choices[key];
        if ([item isKindOfClass:[NSNumber class]]) [popups[index] selectItemAtIndex:[item integerValue]];
        else [popups[index] selectItemWithTitle:item];
    }
}

static NSModalResponse E2EAnswerAlert(NSAlert *alert, BOOL *handled) {
    NppE2EState *state = [NppE2EState shared];
    // Translated first, as the real run would have it (Localization.mm).
    if ([alert respondsToSelector:NSSelectorFromString(@"npp_localize")]) {
        void (*send)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
        send(alert, NSSelectorFromString(@"npp_localize"));
    }
    [alert layout];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSButton *b in alert.buttons) [buttons addObject:b.title ?: @""];
    NSMutableDictionary *entry = [@{@"kind": @"alert", @"message": alert.messageText ?: @"",
                                    @"informative": alert.informativeText ?: @"", @"buttons": buttons} mutableCopy];
    if (alert.accessoryView) {
        NSMutableArray *fields = [NSMutableArray array];
        for (NSView *v in alert.accessoryView.subviews) if ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable]) [fields addObject:[(NSTextField *)v stringValue]];
        if ([alert.accessoryView isKindOfClass:[NSTextField class]]) [fields addObject:[(NSTextField *)alert.accessoryView stringValue]];
        entry[@"fields"] = fields;
        NSMutableArray *checks = [NSMutableArray array];
        NSMutableArray *walk = [NSMutableArray arrayWithObject:alert.accessoryView];
        for (NSUInteger i = 0; i < walk.count; ++i) {
            [walk addObjectsFromArray:[walk[i] subviews]];
            if ([walk[i] isKindOfClass:[NSButton class]] && ![walk[i] isKindOfClass:[NSPopUpButton class]]) [checks addObject:@{@"title": [walk[i] title] ?: @"", @"state": @([(NSButton *)walk[i] state])}];
            if ([walk[i] isKindOfClass:[NSPopUpButton class]]) [checks addObject:@{@"popup": [(NSPopUpButton *)walk[i] itemTitles], @"selected": [(NSPopUpButton *)walk[i] titleOfSelectedItem] ?: @""}];
        }
        entry[@"controls"] = checks;
    }
    id answer = state.alertAnswers.firstObject;
    if (!answer) {
        if (state.realModals) { *handled = NO; entry[@"answered"] = @"by hand"; [state.log addObject:entry]; return 0; }
        answer = @1;   // the default button, as Return would pick
        entry[@"unexpected"] = @YES;
    } else {
        [state.alertAnswers removeObjectAtIndex:0];
    }
    NSInteger index = 0;
    if ([answer isKindOfClass:[NSDictionary class]]) {
        // {"button": 2 or "Title", "field": "text"}: fill the accessory's text field first.
        E2EFillAccessory(alert.accessoryView, answer);
        if (answer[@"suppress"] && alert.showsSuppressionButton) alert.suppressionButton.state = [answer[@"suppress"] boolValue];
        answer = answer[@"button"] ?: @1;
    }
    if ([answer isKindOfClass:[NSString class]]) {
        index = (NSInteger)[buttons indexOfObject:answer] + 1;
        if (index == 0) index = 1;
    } else {
        index = [answer integerValue];
    }
    if (buttons.count == 0) index = 1;
    else if (index < 1 || index > (NSInteger)buttons.count) index = 1;
    entry[@"answered"] = buttons.count ? buttons[(NSUInteger)index - 1] : @"OK";
    [state.log addObject:entry];
    *handled = YES;
    return NSAlertFirstButtonReturn + index - 1;
}

@implementation NSAlert (NppE2E)
- (NSModalResponse)e2e_runModal {
    BOOL handled = NO;
    NSModalResponse r = E2EAnswerAlert(self, &handled);
    return handled ? r : [self e2e_runModal];
}
- (void)e2e_beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    BOOL handled = NO;
    NSModalResponse r = E2EAnswerAlert(self, &handled);
    if (!handled) { [self e2e_beginSheetModalForWindow:window completionHandler:handler]; return; }
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(r); });
}
@end

@implementation NSSavePanel (NppE2E)
- (NSModalResponse)e2e_runModal {
    NppE2EState *state = [NppE2EState shared];
    NSMutableDictionary *entry = [@{@"kind": [self isKindOfClass:[NSOpenPanel class]] ? @"open" : @"save",
                                    @"title": self.title ?: @"", @"message": self.message ?: @"",
                                    @"name": self.nameFieldStringValue ?: @"",
                                    @"directory": self.directoryURL.path ?: @""} mutableCopy];
    NSMutableArray *types = [NSMutableArray array];
    if (@available(macOS 11.0, *)) for (UTType *t in self.allowedContentTypes) [types addObject:t.preferredFilenameExtension ?: t.identifier];
    entry[@"allowed_types"] = types;
    if ([self isKindOfClass:[NSOpenPanel class]]) {
        NSOpenPanel *o = (NSOpenPanel *)self;
        entry[@"can_choose_directories"] = @(o.canChooseDirectories);
        entry[@"can_choose_files"] = @(o.canChooseFiles);
        entry[@"multiple"] = @(o.allowsMultipleSelection);
    }
    id answer = state.panelAnswers.firstObject;
    if (!answer) {
        if (state.realModals) { entry[@"answered"] = @"by hand"; [state.log addObject:entry]; return [self e2e_runModal]; }
        entry[@"unexpected"] = @YES;
        entry[@"answered"] = @"cancel";
        [state.log addObject:entry];
        return NSModalResponseCancel;
    }
    [state.panelAnswers removeObjectAtIndex:0];
    if (answer == [NSNull null]) { entry[@"answered"] = @"cancel"; [state.log addObject:entry]; return NSModalResponseCancel; }
    NSArray *paths = [answer isKindOfClass:[NSArray class]] ? answer : @[answer];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *p in paths) [urls addObject:[NSURL fileURLWithPath:p]];
    objc_setAssociatedObject(self, kPanelURLs, urls, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    entry[@"answered"] = paths;
    [state.log addObject:entry];
    return NSModalResponseOK;
}
- (NSURL *)e2e_URL {
    NSArray *urls = objc_getAssociatedObject(self, kPanelURLs);
    return urls.count ? urls.firstObject : [self e2e_URL];
}
- (void)e2e_beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    NSModalResponse r = [self runModal];
    if (handler) dispatch_async(dispatch_get_main_queue(), ^{ handler(r); });
}
@end

@implementation NSOpenPanel (NppE2E)
- (NSArray<NSURL *> *)e2e_URLs {
    NSArray *urls = objc_getAssociatedObject(self, kPanelURLs);
    return urls ?: [self e2e_URLs];
}
@end

// Finder and the browser: recorded, not opened.
static void E2ELogOpen(NSString *kind, id what) {
    [[NppE2EState shared].log addObject:@{@"kind": kind, @"target": E2EString(what) ?: @""}];
}
@implementation NSWorkspace (NppE2E)
- (BOOL)e2e_openURL:(NSURL *)url { E2ELogOpen(@"open_url", url.isFileURL ? url.path : url.absoluteString); return YES; }
- (void)e2e_openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^)(NSRunningApplication *, NSError *))h {
    E2ELogOpen(@"open_url", url.isFileURL ? url.path : url.absoluteString);
    if (h) dispatch_async(dispatch_get_main_queue(), ^{ h(nil, nil); });
}
- (void)e2e_openURLs:(NSArray<NSURL *> *)urls withApplicationAtURL:(NSURL *)app configuration:(NSWorkspaceOpenConfiguration *)c completionHandler:(void (^)(NSRunningApplication *, NSError *))h {
    for (NSURL *u in urls) E2ELogOpen(@"open_url_with", [NSString stringWithFormat:@"%@ -> %@", u.path ?: u.absoluteString, app.path]);
    if (h) dispatch_async(dispatch_get_main_queue(), ^{ h(nil, nil); });
}
- (void)e2e_activateFileViewerSelectingURLs:(NSArray<NSURL *> *)urls { for (NSURL *u in urls) E2ELogOpen(@"reveal", u.path); }
- (BOOL)e2e_selectFile:(NSString *)path inFileViewerRootedAtPath:(NSString *)root { E2ELogOpen(@"reveal", path ?: root); return YES; }
- (BOOL)e2e_openFile:(NSString *)path { E2ELogOpen(@"open_file", path); return YES; }
@end

// Printing: to a PDF in NPPMAC_E2E_PRINT_DIR, never a printer, no panels.
static long gE2EPrints;
static void E2EPrepareprint(NSPrintOperation *op) {
    NSString *dir = NSProcessInfo.processInfo.environment[@"NPPMAC_E2E_PRINT_DIR"] ?: NSTemporaryDirectory();
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"print-%ld.pdf", ++gE2EPrints]];
    NSPrintInfo *info = op.printInfo;
    info.jobDisposition = NSPrintSaveJob;
    info.dictionary[NSPrintJobSavingURL] = [NSURL fileURLWithPath:path];
    NSMutableDictionary *entry = [@{@"kind": @"print", @"path": path, @"shows_panel": @(op.showsPrintPanel),
                                    @"job_title": op.jobTitle ?: @"",
                                    @"margins": @[@(info.leftMargin), @(info.topMargin), @(info.rightMargin), @(info.bottomMargin)],
                                    @"orientation": @(info.orientation)} mutableCopy];
    [[NppE2EState shared].log addObject:entry];
    op.showsPrintPanel = NO;
    op.showsProgressPanel = NO;
}
/// Every class that runs print operations itself - NSPrintOperation and the
/// concrete subclass AppKit hands out, which overrides -runOperation, so a
/// hook on the base class alone never sees a real job - is hooked on its own:
/// the job is made a save to a PDF, and one that is still not is refused.
static const char kE2EPrintPrepared = 0;
static void E2EPrepareOnce(NSPrintOperation *op) {
    if (objc_getAssociatedObject(op, &kE2EPrintPrepared)) return;   // [super runOperation] from a subclass
    objc_setAssociatedObject(op, &kE2EPrintPrepared, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    E2EPrepareprint(op);
}
static void E2EHookPrintClass(Class cls) {
    Method run = class_getInstanceMethod(cls, @selector(runOperation));
    if (!run) return;
    IMP original = method_getImplementation(run);
    const char *types = method_getTypeEncoding(run);
    IMP hook = imp_implementationWithBlock(^BOOL(NSPrintOperation *op) {
        E2EPrepareOnce(op);
        // Belt and braces: under the suite nothing but a save-to-file job may run.
        if (![op.printInfo.jobDisposition isEqualToString:NSPrintSaveJob] || !op.printInfo.dictionary[NSPrintJobSavingURL]) {
            NSLog(@"e2e: refused a print job that would reach a printer");
            return NO;
        }
        return ((BOOL (*)(id, SEL))original)(op, @selector(runOperation));
    });
    class_replaceMethod(cls, @selector(runOperation), hook, types);
    // The sheet variant runs the (hooked) job at once and tells the delegate, without a sheet.
    Method modal = class_getInstanceMethod(cls, @selector(runOperationModalForWindow:delegate:didRunSelector:contextInfo:));
    if (!modal) return;
    IMP modalHook = imp_implementationWithBlock(^(NSPrintOperation *op, NSWindow *w, id d, SEL sel, void *ctx) {
        BOOL ok = [op runOperation];
        if (d && sel) {
            void (*send)(id, SEL, NSPrintOperation *, BOOL, void *) = (void (*)(id, SEL, NSPrintOperation *, BOOL, void *))objc_msgSend;
            send(d, sel, op, ok, ctx);
        }
    });
    class_replaceMethod(cls, @selector(runOperationModalForWindow:delegate:didRunSelector:contextInfo:), modalHook,
                        method_getTypeEncoding(modal));
}
static BOOL E2EDefinesOwn(Class cls, SEL sel) {
    unsigned n = 0;
    Method *methods = class_copyMethodList(cls, &n);
    BOOL own = NO;
    for (unsigned i = 0; i < n && !own; ++i) own = method_getName(methods[i]) == sel;
    free(methods);
    return own;
}
static void E2EHookPrinting(void) {
    E2EHookPrintClass([NSPrintOperation class]);
    int count = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; ++i) {
        Class c = classes[i];
        if (c == [NSPrintOperation class]) continue;
        // class_getSuperclass walk: -isSubclassOfClass: would message classes that may not want it yet.
        BOOL printer = NO;
        for (Class k = class_getSuperclass(c); k && !printer; k = class_getSuperclass(k)) printer = k == [NSPrintOperation class];
        if (printer && (E2EDefinesOwn(c, @selector(runOperation)) ||
                        E2EDefinesOwn(c, @selector(runOperationModalForWindow:delegate:didRunSelector:contextInfo:))))
            E2EHookPrintClass(c);
    }
    free(classes);
}

// The clipboard, private to this process's run.
@implementation NSPasteboard (NppE2E)
+ (NSPasteboard *)e2e_generalPasteboard {
    static NSPasteboard *board;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        board = [NSPasteboard pasteboardWithName:[NSString stringWithFormat:@"org.notepad-plus-plus.mac.e2e.%d", getpid()]];
    });
    return board;
}
@end

static void E2ESwap(Class cls, SEL original, SEL replacement, BOOL classMethod) {
    Method a = classMethod ? class_getClassMethod(cls, original) : class_getInstanceMethod(cls, original);
    Method b = classMethod ? class_getClassMethod(cls, replacement) : class_getInstanceMethod(cls, replacement);
    if (!a || !b) return;
    // Give the class its own copy first when the method is inherited, so the
    // swap does not reach the superclass.
    Class target = classMethod ? object_getClass(cls) : cls;
    if (class_addMethod(target, original, method_getImplementation(b), method_getTypeEncoding(b))) {
        class_replaceMethod(target, replacement, method_getImplementation(a), method_getTypeEncoding(a));
    } else {
        method_exchangeImplementations(a, b);
    }
}

void NppE2EInstall(void) {
    if (!NppE2EEnabled()) return;
    // No printer at all for the suite's copy: the shared print info saves to a file from the start.
    [NSPrintInfo sharedPrintInfo].jobDisposition = NSPrintSaveJob;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        E2ESwap([NSAlert class], @selector(runModal), @selector(e2e_runModal), NO);
        E2ESwap([NSAlert class], @selector(beginSheetModalForWindow:completionHandler:), @selector(e2e_beginSheetModalForWindow:completionHandler:), NO);
        E2ESwap([NSSavePanel class], @selector(runModal), @selector(e2e_runModal), NO);
        E2ESwap([NSSavePanel class], @selector(URL), @selector(e2e_URL), NO);
        E2ESwap([NSSavePanel class], @selector(beginSheetModalForWindow:completionHandler:), @selector(e2e_beginSheetModalForWindow:completionHandler:), NO);
        E2ESwap([NSOpenPanel class], @selector(URLs), @selector(e2e_URLs), NO);
        E2ESwap([NSPasteboard class], @selector(generalPasteboard), @selector(e2e_generalPasteboard), YES);
        E2ESwap([NSWorkspace class], @selector(openURL:), @selector(e2e_openURL:), NO);
        E2ESwap([NSWorkspace class], @selector(openURL:configuration:completionHandler:), @selector(e2e_openURL:configuration:completionHandler:), NO);
        E2ESwap([NSWorkspace class], @selector(openURLs:withApplicationAtURL:configuration:completionHandler:), @selector(e2e_openURLs:withApplicationAtURL:configuration:completionHandler:), NO);
        E2ESwap([NSWorkspace class], @selector(activateFileViewerSelectingURLs:), @selector(e2e_activateFileViewerSelectingURLs:), NO);
        E2ESwap([NSWorkspace class], @selector(selectFile:inFileViewerRootedAtPath:), @selector(e2e_selectFile:inFileViewerRootedAtPath:), NO);
        E2ESwap([NSWorkspace class], @selector(openFile:), @selector(e2e_openFile:), NO);
        E2EHookPrinting();
        NSString *release = NSProcessInfo.processInfo.environment[@"NPPMAC_E2E_RELEASE_URL"];
        if (release.length) NppUpdateChecker.latestReleaseURLOverride = [release hasPrefix:@"/"] ? [NSURL fileURLWithPath:release] : [NSURL URLWithString:release];
        E2ESwap([NSEvent class], @selector(modifierFlags), @selector(e2e_modifierFlags), YES);
        E2ESwap([NSApplication class], @selector(keyWindow), @selector(e2e_keyWindow), NO);
        E2ESwap([NSWindow class], @selector(isKeyWindow), @selector(e2e_isKeyWindow), NO);
    });
}

#pragma mark - Windows and controls

static NSArray<NSWindow *> *E2EWindows(void);
static NSArray<NSWindow *> *E2EWindows(void) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSWindow *w in NSApp.windows) {
        NSString *cls = NSStringFromClass(w.class);
        if ([cls hasPrefix:@"NSStatusBar"] || [cls containsString:@"TouchBar"] || [cls containsString:@"AnimationProxy"] || [cls containsString:@"FullScreenTile"]) continue;
        [out addObject:w];
    }
    return out;
}

static NSDictionary *E2EWindowInfo(NSWindow *w) {
    AppDelegate *app = (AppDelegate *)NSApp.delegate;
    NSMutableDictionary *info = [@{@"number": @(w.windowNumber), @"title": w.title ?: @"",
                                   @"class": NSStringFromClass(w.class), @"visible": @(w.isVisible),
                                   @"key": @(w.isKeyWindow), @"main_window": @(w == app.window),
                                   @"modal": @(NSApp.modalWindow == w), @"sheet": @(w.isSheet),
                                   @"frame": E2ERect(w.frame)} mutableCopy];
    if (w.sheetParent) info[@"sheet_parent"] = @(w.sheetParent.windowNumber);
    if (w.attachedSheet) info[@"attached_sheet"] = @(w.attachedSheet.windowNumber);
    if (w.parentWindow) info[@"parent"] = @(w.parentWindow.windowNumber);
    if (w.firstResponder) info[@"first_responder"] = NSStringFromClass(w.firstResponder.class);
    info[@"level"] = @(w.level);
    return info;
}

/// A window by number, "main", "key", "modal", a class name, or its title
/// (exact first, then contained). Visible windows win over hidden ones.
static NSWindow *E2EFindWindow(id spec, NSError **error) {
    AppDelegate *app = (AppDelegate *)NSApp.delegate;
    NSArray<NSWindow *> *windows = E2EWindows();
    if (!spec || [spec isEqual:@"main"]) return app.window;
    if ([spec isKindOfClass:[NSNumber class]]) {
        for (NSWindow *w in windows) if (w.windowNumber == [spec integerValue]) return w;
    } else if ([spec isKindOfClass:[NSString class]]) {
        if ([spec isEqual:@"key"]) return NSApp.keyWindow;
        if ([spec isEqual:@"modal"]) return NSApp.modalWindow;
        NSArray *ordered = [windows sortedArrayUsingComparator:^NSComparisonResult(NSWindow *a, NSWindow *b) {
            return [@(b.isVisible) compare:@(a.isVisible)];
        }];
        for (NSWindow *w in ordered) if ([w.title isEqualToString:spec]) return w;
        for (NSWindow *w in ordered) if ([NSStringFromClass(w.class) isEqualToString:spec]) return w;
        for (NSWindow *w in ordered) if (w.title.length && [w.title rangeOfString:spec options:NSCaseInsensitiveSearch].location != NSNotFound) return w;
    }
    if (error) *error = E2EFail(@"No window %@", spec);
    return nil;
}

static NSDictionary *E2EControlInfo(NSView *v, NSString *path) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"path"] = path;
    d[@"class"] = NSStringFromClass(v.class);
    if (v.identifier.length && ![v.identifier hasPrefix:@"_NS"]) d[@"id"] = v.identifier;
    if (v.isHidden) d[@"hidden"] = @YES;
    if (v.toolTip.length) d[@"tooltip"] = v.toolTip;
    d[@"frame"] = E2ERect(E2EScreenFrame(v));
    if ([v isKindOfClass:[NSControl class]]) {
        NSControl *c = (NSControl *)v;
        if (!c.isEnabled) d[@"enabled"] = @NO;
        // What the text needs against what it has: cut-off text shows here.
        NSCell *cell = c.cell;
        if (cell && ![v isKindOfClass:[NSTableView class]] && ![v isKindOfClass:[NSMatrix class]]) {
            BOOL wraps = cell.wraps || ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v maximumNumberOfLines] != 1 && cell.lineBreakMode == NSLineBreakByWordWrapping);
            NSSize need = wraps ? [cell cellSizeForBounds:NSMakeRect(0, 0, v.bounds.size.width, CGFLOAT_MAX)] : cell.cellSize;
            d[@"cell_size"] = @[@(ceil(need.width)), @(ceil(need.height))];
            d[@"size"] = @[@(v.bounds.size.width), @(v.bounds.size.height)];
            d[@"wraps"] = @(wraps);
            d[@"fits"] = @(need.width <= v.bounds.size.width + 0.5 && need.height <= v.bounds.size.height + 0.5);
        }
    }
    if ([v isKindOfClass:[NppTabBarView class]]) {
        NppTabBarView *bar = (NppTabBarView *)v;
        NSMutableArray *tabs = [NSMutableArray array];
        for (NSInteger i = 0; i < (NSInteger)bar.items.count; ++i) {
            NppTabItem *item = bar.items[(NSUInteger)i];
            NSRect r = [bar frameOfTabAtIndex:i];
            [tabs addObject:@{@"title": item.title ?: @"", @"modified": @(item.modified), @"pinned": @(item.pinned),
                              @"colour": @(item.colour), @"frame": @[@(r.origin.x), @(r.origin.y), @(r.size.width), @(r.size.height)]}];
        }
        d[@"tabs"] = tabs;
        d[@"selected"] = @(bar.selectedIndex);
    }
    if ([v isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *p = (NSPopUpButton *)v;
        d[@"value"] = p.titleOfSelectedItem ?: @"";
        d[@"selected"] = @(p.indexOfSelectedItem);
        d[@"items"] = p.itemTitles;
    } else if ([v isKindOfClass:[NSButton class]]) {
        NSButton *b = (NSButton *)v;
        d[@"title"] = b.title ?: @"";
        d[@"state"] = @(b.state);
        if (b.alternateTitle.length) d[@"alternate_title"] = b.alternateTitle;
    } else if ([v isKindOfClass:[NSSegmentedControl class]]) {
        NSSegmentedControl *s = (NSSegmentedControl *)v;
        NSMutableArray *labels = [NSMutableArray array];
        NSMutableArray *selected = [NSMutableArray array];
        for (NSInteger i = 0; i < s.segmentCount; ++i) {
            [labels addObject:[s labelForSegment:i] ?: [s toolTipForSegment:i] ?: @""];
            if ([s isSelectedForSegment:i]) [selected addObject:@(i)];
        }
        d[@"items"] = labels;
        d[@"selected"] = selected;
    } else if ([v isKindOfClass:[NSMatrix class]]) {
        NSMatrix *m = (NSMatrix *)v;
        NSMutableArray *titles = [NSMutableArray array];
        for (NSInteger r = 0; r < m.numberOfRows; ++r) [titles addObject:[[m cellAtRow:r column:0] title] ?: @""];
        d[@"items"] = titles;
        d[@"selected"] = @(m.selectedRow);
        d[@"value"] = m.selectedCell.title ?: @"";
    } else if ([v isKindOfClass:[NSColorWell class]]) {
        NSColor *c = [[(NSColorWell *)v color] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        d[@"value"] = [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(c.redComponent * 255), (int)lround(c.greenComponent * 255), (int)lround(c.blueComponent * 255)];
    } else if ([v isKindOfClass:[NSSlider class]]) {
        d[@"value"] = @([(NSSlider *)v doubleValue]);
    } else if ([v isKindOfClass:[NSComboBox class]]) {
        NSComboBox *c = (NSComboBox *)v;
        d[@"value"] = c.stringValue ?: @"";
        if (!c.usesDataSource) d[@"items"] = c.objectValues;
    } else if ([v isKindOfClass:[NSTextField class]]) {
        NSTextField *t = (NSTextField *)v;
        d[@"value"] = t.stringValue ?: @"";
        d[@"editable"] = @(t.isEditable);
        if (t.placeholderString.length) d[@"placeholder"] = t.placeholderString;
    } else if ([v isKindOfClass:[NSTextView class]]) {
        NSString *s = [(NSTextView *)v string] ?: @"";
        d[@"value"] = s.length > 20000 ? [s substringToIndex:20000] : s;
        d[@"editable"] = @([(NSTextView *)v isEditable]);
    } else if ([v isKindOfClass:[NSTableView class]]) {
        NSTableView *t = (NSTableView *)v;
        d[@"rows"] = @(t.numberOfRows);
        NSMutableArray *cols = [NSMutableArray array];
        for (NSTableColumn *c in t.tableColumns) [cols addObject:c.title ?: c.identifier ?: @""];
        d[@"columns"] = cols;
        NSMutableArray *sel = [NSMutableArray array];
        [t.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { [sel addObject:@(i)]; }];
        d[@"selected"] = sel;
        // The text of each row, as the cells show it (views or cell values).
        NSMutableArray *rows = [NSMutableArray array];
        for (NSInteger r = 0; r < MIN(t.numberOfRows, 2000); ++r) {
            NSMutableArray *cells = [NSMutableArray array];
            for (NSInteger c = 0; c < t.numberOfColumns; ++c) {
                NSString *text = nil;
                NSView *cell = [t viewAtColumn:c row:r makeIfNecessary:YES];
                if ([cell isKindOfClass:[NSTableCellView class]]) text = [(NSTableCellView *)cell textField].stringValue;
                else if ([cell isKindOfClass:[NSTextField class]]) text = [(NSTextField *)cell stringValue];
                else if ([cell isKindOfClass:[NSButton class]]) text = [NSString stringWithFormat:@"%@%@", [(NSButton *)cell title], [(NSButton *)cell state] ? @" [x]" : @""];
                if (!text && t.dataSource && [t.dataSource respondsToSelector:@selector(tableView:objectValueForTableColumn:row:)]) {
                    text = E2EString([t.dataSource tableView:t objectValueForTableColumn:t.tableColumns[(NSUInteger)c] row:r]);
                }
                [cells addObject:text ?: @""];
            }
            [rows addObject:cells];
        }
        d[@"cells"] = rows;
        if ([v isKindOfClass:[NSOutlineView class]]) {
            NSMutableArray *levels = [NSMutableArray array];
            for (NSInteger r = 0; r < MIN(t.numberOfRows, 2000); ++r) [levels addObject:@([(NSOutlineView *)v levelForRow:r])];
            d[@"levels"] = levels;
        }
    } else if ([v isKindOfClass:[NSTabView class]]) {
        NSTabView *t = (NSTabView *)v;
        NSMutableArray *labels = [NSMutableArray array];
        for (NSTabViewItem *i in t.tabViewItems) [labels addObject:i.label ?: @""];
        d[@"items"] = labels;
        if (t.selectedTabViewItem) d[@"selected"] = @([t indexOfTabViewItem:t.selectedTabViewItem]);
    } else if ([v isKindOfClass:[ScintillaView class]]) {
        ScintillaView *s = (ScintillaView *)v;
        d[@"length"] = @([s message:SCI_GETLENGTH wParam:0 lParam:0]);
    } else if ([v isKindOfClass:[NSImageView class]]) {
        d[@"has_image"] = @([(NSImageView *)v image] != nil);
    } else if ([v isKindOfClass:[NSProgressIndicator class]]) {
        d[@"value"] = @([(NSProgressIndicator *)v doubleValue]);
    } else if ([v isKindOfClass:[NSBox class]]) {
        if ([(NSBox *)v title].length && [(NSBox *)v titlePosition] != NSNoTitle) d[@"title"] = [(NSBox *)v title];
    }
    // Anything else that draws a text of its own (the port's custom views).
    if (!d[@"title"] && !d[@"value"] && ![v isKindOfClass:[NSImageView class]]) {
        for (NSString *key in @[@"title", @"text", @"stringValue", @"label"]) {
            SEL sel = NSSelectorFromString(key);
            if (![v respondsToSelector:sel]) continue;
            NSMethodSignature *sig = [v methodSignatureForSelector:sel];
            if (sig.numberOfArguments != 2 || sig.methodReturnType[0] != '@') continue;
            @try {
                id value = [v valueForKey:key];
                if ([value isKindOfClass:[NSString class]] && [value length] && [value length] < 2000) { d[@"title"] = value; break; }
            } @catch (NSException *e) {}
        }
    }
    return d;
}

static BOOL E2EOpaque(NSView *v) {
    // Views whose inside is theirs alone: nothing a test clicks lives there.
    return [v isKindOfClass:[ScintillaView class]] || [v isKindOfClass:[NSTableView class]] ||
           [v isKindOfClass:[NSPopUpButton class]] || [v isKindOfClass:[NSTextView class]] ||
           [v isKindOfClass:[NSSegmentedControl class]] || [v isKindOfClass:[NSButton class]] ||
           [v isKindOfClass:[NSTextField class]] || [v isKindOfClass:[NSMatrix class]];
}

static void E2EWalk(NSView *v, NSString *path, BOOL includeHidden, NSMutableArray *out) {
    if (v.isHidden && !includeHidden) return;
    BOOL interesting = [v isKindOfClass:[NSControl class]] || [v isKindOfClass:[NSTextView class]] ||
                       [v isKindOfClass:[NSTabView class]] || [v isKindOfClass:[ScintillaView class]] ||
                       [v isKindOfClass:[NSImageView class]] || [v isKindOfClass:[NSProgressIndicator class]] ||
                       [v isKindOfClass:[NppTabBarView class]] ||
                       ([v isKindOfClass:[NSBox class]] && [(NSBox *)v titlePosition] != NSNoTitle) ||
                       [v respondsToSelector:@selector(title)] || v.toolTip.length;
    if ([v isKindOfClass:[NSImageView class]] && ![v isKindOfClass:[NSControl class]]) interesting = YES;
    if ([v isKindOfClass:[NSScroller class]] || [v isKindOfClass:[NSClipView class]] ||
        ([NSStringFromClass(v.class) hasPrefix:@"_NS"] && ![v isKindOfClass:[NSControl class]])) interesting = NO;
    if (interesting) [out addObject:E2EControlInfo(v, path)];
    if (E2EOpaque(v)) return;
    NSArray *subviews = v.subviews;
    for (NSUInteger i = 0; i < subviews.count; ++i) {
        E2EWalk(subviews[i], [NSString stringWithFormat:@"%@.%lu", path, (unsigned long)i], includeHidden, out);
    }
}

static NSView *E2EViewAtPath(NSWindow *w, NSString *path) {
    NSView *v = w.contentView.superview ?: w.contentView;
    NSArray *parts = [path componentsSeparatedByString:@"."];
    for (NSUInteger i = 1; i < parts.count; ++i) {
        NSInteger index = [parts[i] integerValue];
        if (index < 0 || index >= (NSInteger)v.subviews.count) return nil;
        v = v.subviews[(NSUInteger)index];
    }
    return v;
}

/// A control by path, or the first one (index-th) whose title, value, id,
/// tooltip, placeholder or class matches, optionally of a class.
static NSView *E2EFindControl(NSWindow *w, NSDictionary *target, NSError **error) {
    NSString *path = target[@"path"];
    if (path) {
        NSView *v = E2EViewAtPath(w, path);
        if (!v && error) *error = E2EFail(@"No view at %@", path);
        return v;
    }
    NSMutableArray *all = [NSMutableArray array];
    NSView *root = w.contentView.superview ?: w.contentView;
    E2EWalk(root, @"0", [target[@"include_hidden"] boolValue], all);
    NSString *want = E2EString(target[@"title"] ?: target[@"text"]);
    NSString *identifier = target[@"id"], *cls = target[@"class"], *tip = target[@"tooltip"], *placeholder = target[@"placeholder"];
    NSInteger index = [target[@"index"] integerValue];
    for (NSDictionary *d in all) {
        if (cls && ![d[@"class"] isEqualToString:cls]) {
            Class c = NSClassFromString(cls);
            if (!c || ![E2EViewAtPath(w, d[@"path"]) isKindOfClass:c]) continue;
        }
        if (identifier && ![d[@"id"] isEqual:identifier]) continue;
        if (tip && ![d[@"tooltip"] isEqual:tip]) continue;
        if (placeholder && ![d[@"placeholder"] isEqual:placeholder]) continue;
        if (want) {
            NSString *title = [d[@"title"] stringByReplacingOccurrencesOfString:@"&" withString:@""];
            BOOL hit = [d[@"title"] isEqual:want] || [title isEqual:want] || [d[@"value"] isEqual:want] ||
                       [d[@"tooltip"] isEqual:want] || [d[@"alternate_title"] isEqual:want];
            if (!hit) continue;
        }
        if (index-- > 0) continue;
        return E2EViewAtPath(w, d[@"path"]);
    }
    // A plain view asked for by its class alone (a dock container, the document map's zone):
    // not a control, so not in the walk above - looked for among all the views, in order.
    Class wanted = cls ? NSClassFromString(cls) : nil;
    if (wanted && !identifier && !tip && !placeholder && !want) {
        NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:root];
        while (queue.count) {
            NSView *v = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (v.isHidden && ![target[@"include_hidden"] boolValue]) continue;
            if ([v isKindOfClass:wanted] && index-- <= 0) return v;
            [queue addObjectsFromArray:v.subviews];
        }
    }
    if (error) *error = E2EFail(@"No control matching %@ in %@", target, w.title);
    return nil;
}

static void E2ESendAction(NSControl *c) {
    if (c.action) [NSApp sendAction:c.action to:c.target from:c];
}

#pragma mark - Keys

static __weak NSWindow *gE2EForcedKeyWindow;
static NSEventModifierFlags gE2EForcedModifiers;
static BOOL gE2EModifiersForced;

@implementation NSEvent (NppE2EModifiers)
+ (NSEventModifierFlags)e2e_modifierFlags { return gE2EModifiersForced ? gE2EForcedModifiers : [self e2e_modifierFlags]; }
@end

static NSEventModifierFlags E2EModifierFlags(NSArray *names) {
    NSEventModifierFlags flags = 0;
    for (NSString *m in names) {
        if ([m isEqual:@"cmd"]) flags |= NSEventModifierFlagCommand;
        else if ([m isEqual:@"alt"] || [m isEqual:@"option"]) flags |= NSEventModifierFlagOption;
        else if ([m isEqual:@"shift"]) flags |= NSEventModifierFlagShift;
        else if ([m isEqual:@"ctrl"]) flags |= NSEventModifierFlagControl;
    }
    return flags;
}

@implementation NSApplication (NppE2EKey)
- (NSWindow *)e2e_keyWindow { return gE2EForcedKeyWindow ?: [self e2e_keyWindow]; }
@end
@implementation NSWindow (NppE2EKey)
- (BOOL)e2e_isKeyWindow { return (gE2EForcedKeyWindow && gE2EForcedKeyWindow == self) || [self e2e_isKeyWindow]; }
@end

static NSDictionary<NSString *, NSArray *> *E2ENamedKeys(void) {
    // name -> @[characters, key code]
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unichar up = NSUpArrowFunctionKey, down = NSDownArrowFunctionKey, left = NSLeftArrowFunctionKey, right = NSRightArrowFunctionKey;
        unichar home = NSHomeFunctionKey, end = NSEndFunctionKey, pgup = NSPageUpFunctionKey, pgdn = NSPageDownFunctionKey, fwd = NSDeleteFunctionKey;
        NSMutableDictionary *k = [@{
            @"return": @[@"\r", @36], @"enter": @[@"\r", @36], @"tab": @[@"\t", @48], @"space": @[@" ", @49],
            @"delete": @[@"\x7f", @51], @"backspace": @[@"\x7f", @51], @"escape": @[@"\x1b", @53], @"esc": @[@"\x1b", @53],
            @"up": @[[NSString stringWithCharacters:&up length:1], @126], @"down": @[[NSString stringWithCharacters:&down length:1], @125],
            @"left": @[[NSString stringWithCharacters:&left length:1], @123], @"right": @[[NSString stringWithCharacters:&right length:1], @124],
            @"home": @[[NSString stringWithCharacters:&home length:1], @115], @"end": @[[NSString stringWithCharacters:&end length:1], @119],
            @"pageup": @[[NSString stringWithCharacters:&pgup length:1], @116], @"pagedown": @[[NSString stringWithCharacters:&pgdn length:1], @121],
            @"forwarddelete": @[[NSString stringWithCharacters:&fwd length:1], @117],
        } mutableCopy];
        int fcodes[] = {122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111};
        for (int i = 0; i < 12; ++i) {
            unichar f = (unichar)(NSF1FunctionKey + i);
            k[[NSString stringWithFormat:@"f%d", i + 1]] = @[[NSString stringWithCharacters:&f length:1], @(fcodes[i])];
        }
        keys = k;
    });
    return keys;
}

static unsigned short E2EKeyCodeForCharacter(unichar c) {
    static NSDictionary<NSString *, NSNumber *> *codes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        codes = @{@"a": @0, @"s": @1, @"d": @2, @"f": @3, @"h": @4, @"g": @5, @"z": @6, @"x": @7, @"c": @8, @"v": @9,
                  @"b": @11, @"q": @12, @"w": @13, @"e": @14, @"r": @15, @"y": @16, @"t": @17, @"1": @18, @"2": @19,
                  @"3": @20, @"4": @21, @"6": @22, @"5": @23, @"=": @24, @"9": @25, @"7": @26, @"-": @27, @"8": @28,
                  @"0": @29, @"]": @30, @"o": @31, @"u": @32, @"[": @33, @"i": @34, @"p": @35, @"l": @37, @"j": @38,
                  @"'": @39, @"k": @40, @";": @41, @"\\": @42, @",": @43, @"/": @44, @"n": @45, @"m": @46, @".": @47,
                  @"`": @50, @" ": @49};
    });
    NSString *s = [[NSString stringWithCharacters:&c length:1] lowercaseString];
    NSNumber *n = codes[s];
    return n ? n.unsignedShortValue : 0;
}

/// "cmd+shift+f", "escape", "alt+up", "a": one key press, delivered as the
/// window server would - the menu's key equivalents first, then the window.
static BOOL E2EPressKey(NSString *spec, NSWindow *window, NSError **error) {
    NSArray *parts = [spec componentsSeparatedByString:@"+"];
    if ([spec hasSuffix:@"++"]) parts = [[[spec substringToIndex:spec.length - 2] componentsSeparatedByString:@"+"] arrayByAddingObject:@"+"];
    NSEventModifierFlags flags = 0;
    NSString *key = parts.lastObject;
    for (NSUInteger i = 0; i + 1 < parts.count; ++i) {
        NSString *m = [parts[i] lowercaseString];
        if ([m isEqual:@"cmd"] || [m isEqual:@"command"]) flags |= NSEventModifierFlagCommand;
        else if ([m isEqual:@"shift"]) flags |= NSEventModifierFlagShift;
        else if ([m isEqual:@"alt"] || [m isEqual:@"option"] || [m isEqual:@"opt"]) flags |= NSEventModifierFlagOption;
        else if ([m isEqual:@"ctrl"] || [m isEqual:@"control"]) flags |= NSEventModifierFlagControl;
        else if ([m isEqual:@"fn"]) flags |= NSEventModifierFlagFunction;
        else { if (error) *error = E2EFail(@"Unknown modifier %@", m); return NO; }
    }
    NSString *chars, *plain;
    unsigned short code;
    NSArray *named = E2ENamedKeys()[key.lowercaseString];
    if (named && key.length > 1) {
        chars = plain = named[0];
        code = [named[1] unsignedShortValue];
        if ([key.lowercaseString hasPrefix:@"f"] || [@[@"up", @"down", @"left", @"right", @"home", @"end", @"pageup", @"pagedown", @"forwarddelete"] containsObject:key.lowercaseString]) flags |= NSEventModifierFlagFunction;
    } else if (key.length == 1) {
        plain = key.lowercaseString;
        chars = (flags & NSEventModifierFlagShift) ? key.uppercaseString : key;
        if ([key isEqualToString:key.uppercaseString] && ![key isEqualToString:key.lowercaseString]) { flags |= NSEventModifierFlagShift; chars = key; }
        code = E2EKeyCodeForCharacter([key characterAtIndex:0]);
        if (flags & NSEventModifierFlagControl) {
            unichar c = [plain characterAtIndex:0];
            if (c >= 'a' && c <= 'z') { unichar ctl = (unichar)(c - 'a' + 1); chars = [NSString stringWithCharacters:&ctl length:1]; }
        }
    } else {
        if (error) *error = E2EFail(@"Unknown key %@", key);
        return NO;
    }
    NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags
                                    timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                                      context:nil characters:chars charactersIgnoringModifiers:plain isARepeat:NO keyCode:code];
    NSEvent *up = [NSEvent keyEventWithType:NSEventTypeKeyUp location:NSZeroPoint modifierFlags:flags
                                  timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
                                    context:nil characters:chars charactersIgnoringModifiers:plain isARepeat:NO keyCode:code];
    BOOL chord = (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagFunction)) != 0 ||
                 ((flags & NSEventModifierFlagOption) && code != 0);
    BOOL handled = NO;
    (void)chord; (void)handled;
    // The application need not be active (the suite runs beside the user's
    // work), and AppKit gives key events to the key window only, so for the
    // length of the press the target window counts as key: the event then
    // takes AppKit's own route - local monitors, key equivalents, the menus,
    // the first responder.
    gE2EForcedKeyWindow = window;
    [NSApp sendEvent:down];
    [NSApp sendEvent:up];
    gE2EForcedKeyWindow = nil;
    return YES;
}

#pragma mark - Menus

static NSMenuItem *E2EMenuItemAtPath(NSMenu *menu, NSString *path) {
    NSArray *parts = [path componentsSeparatedByString:@"|"];
    NSMenuItem *found = nil;
    for (NSString *raw in parts) {
        NSString *want = [raw stringByReplacingOccurrencesOfString:@"&" withString:@""];
        found = nil;
        if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
        [menu update];
        for (NSMenuItem *item in menu.itemArray) {
            NSString *title = [[item.title stringByReplacingOccurrencesOfString:@"&" withString:@""]
                               stringByReplacingOccurrencesOfString:@"…" withString:@"..."];
            NSString *w2 = [want stringByReplacingOccurrencesOfString:@"…" withString:@"..."];
            NSString *sub = [item.submenu.title stringByReplacingOccurrencesOfString:@"&" withString:@""];
            if ([title isEqualToString:w2] || (!title.length && [sub isEqualToString:w2]) ||
                (item.submenu && [sub isEqualToString:w2] && menu == NSApp.mainMenu)) { found = item; break; }
        }
        if (!found) return nil;
        menu = found.submenu;
    }
    return found;
}

static NSDictionary *E2EMenuItemInfo(NSMenuItem *item) {
    [item.menu update];
    NSMutableDictionary *d = [@{@"title": item.title ?: @"", @"enabled": @(item.isEnabled), @"checked": @(item.state == NSControlStateValueOn),
                                @"state": @(item.state), @"hidden": @(item.isHidden), @"tag": @(item.tag)} mutableCopy];
    if (item.keyEquivalent.length) {
        NSMutableString *k = [NSMutableString string];
        NSEventModifierFlags m = item.keyEquivalentModifierMask;
        if (m & NSEventModifierFlagControl) [k appendString:@"ctrl+"];
        if (m & NSEventModifierFlagOption) [k appendString:@"alt+"];
        if (m & NSEventModifierFlagShift) [k appendString:@"shift+"];
        if (m & NSEventModifierFlagCommand) [k appendString:@"cmd+"];
        [k appendString:item.keyEquivalent];
        d[@"key"] = k;
    }
    if (item.submenu) d[@"submenu_items"] = @(item.submenu.numberOfItems);
    if (item.action) d[@"action"] = NSStringFromSelector(item.action);
    return d;
}

/// The editor's right-click menu, built as a right click builds it.
static NSMenu *E2EEditorContextMenu(void) {
    AppDelegate *app = (AppDelegate *)NSApp.delegate;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context"];
    SEL sel = NSSelectorFromString(@"contextMenuItems");
    if (![app.editor respondsToSelector:sel]) return menu;
    NSArray *(*send)(id, SEL) = (NSArray *(*)(id, SEL))objc_msgSend;
    for (NSMenuItem *item in send(app.editor, sel)) {
        if (item.menu) [item.menu removeItem:item];
        [menu addItem:item];
    }
    return menu;
}

static NSArray *E2EMenuTree(NSMenu *menu, NSInteger depth) {
    NSMutableArray *out = [NSMutableArray array];
    if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
    [menu update];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) { [out addObject:@{@"separator": @YES}]; continue; }
        NSMutableDictionary *d = [E2EMenuItemInfo(item) mutableCopy];
        if (item.submenu && depth > 0) d[@"items"] = E2EMenuTree(item.submenu, depth - 1);
        [out addObject:d];
    }
    return out;
}

/// A click: the mouse-up is queued before the mouse-down is sent. A view that
/// tracks the mouse on a down (NSTableView, sliders, buttons in a loop) pulls
/// the up from the queue and returns; sent one after the other, the down never
/// returned (it waited for an up only it could let through) and the main
/// thread hung. A view that does not track leaves the up queued, and it is
/// taken back and delivered here, so the click is still over on return.
/// `view` given: the events go to it directly (a custom view without a window
/// route), else through NSApp.
static void E2EClickAt(NSWindow *w, NSPoint inWindow, NSEventModifierFlags flags, NSInteger clickCount, NSView *view) {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:inWindow modifierFlags:flags timestamp:now
                                   windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:clickCount pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:inWindow modifierFlags:flags timestamp:now
                                 windowNumber:w.windowNumber context:nil eventNumber:0 clickCount:clickCount pressure:1];
    [NSApp postEvent:up atStart:YES];
    if (view) [view mouseDown:down]; else [NSApp sendEvent:down];
    NSEvent *left = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate distantPast]
                                          inMode:NSDefaultRunLoopMode dequeue:YES];
    if (left) { if (view) [view mouseUp:left]; else [NSApp sendEvent:left]; }
}

#pragma mark - Values across the JSON boundary

static id E2EJSONValue(id value) {
    if (!value || value == [NSNull null]) return [NSNull null];
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id v in value) [a addObject:E2EJSONValue(v)];
        return a;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id k in value) d[[k description]] = E2EJSONValue(value[k]);
        return d;
    }
    if ([value isKindOfClass:[NSData class]]) return [(NSData *)value base64EncodedStringWithOptions:0];
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path] ?: [value absoluteString];
    if ([value isKindOfClass:[NSDate class]]) return @([(NSDate *)value timeIntervalSince1970]);
    if ([value isKindOfClass:[NSAttributedString class]]) return [value string];
    if ([value isKindOfClass:[NSWindow class]]) return E2EWindowInfo(value);
    if ([value isKindOfClass:[NSSet class]]) return E2EJSONValue([value allObjects]);
    return [value description];
}

/// Calls a method with 0-2 arguments (objects, numbers or BOOLs as the
/// signature says) and returns what it returns, made JSON.
static id E2EInvoke(id target, NSString *selectorName, NSArray *arguments, NSError **error) {
    SEL sel = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:sel]) { if (error) *error = E2EFail(@"%@ does not respond to %@", NSStringFromClass([target class]), selectorName); return nil; }
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    NSMutableArray *keep = [NSMutableArray array];
    for (NSUInteger i = 0; i + 2 < sig.numberOfArguments; ++i) {
        id arg = i < arguments.count ? arguments[i] : [NSNull null];
        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V') type++;
        switch (*type) {
            case '@': { id obj = arg == [NSNull null] ? nil : arg; if (obj) [keep addObject:obj]; [inv setArgument:&obj atIndex:(NSInteger)i + 2]; break; }
            case 'B': { BOOL b = [arg boolValue]; [inv setArgument:&b atIndex:(NSInteger)i + 2]; break; }
            case 'c': { char c = (char)[arg intValue]; [inv setArgument:&c atIndex:(NSInteger)i + 2]; break; }
            case 'i': { int n = [arg intValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case 'I': { unsigned n = [arg unsignedIntValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case 'q': case 'l': { long long n = [arg longLongValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case 'Q': case 'L': { unsigned long long n = [arg unsignedLongLongValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case 'd': { double n = [arg doubleValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case 'f': { float n = [arg floatValue]; [inv setArgument:&n atIndex:(NSInteger)i + 2]; break; }
            case ':': { SEL s = NSSelectorFromString(arg); [inv setArgument:&s atIndex:(NSInteger)i + 2]; break; }
            default: if (error) *error = E2EFail(@"Cannot pass argument %lu of %@ (type %s)", (unsigned long)i, selectorName, type); return nil;
        }
    }
    [inv invoke];
    const char *rtype = sig.methodReturnType;
    while (*rtype == 'r' || *rtype == 'n' || *rtype == 'N' || *rtype == 'o' || *rtype == 'O' || *rtype == 'R' || *rtype == 'V') rtype++;
    switch (*rtype) {
        case 'v': return [NSNull null];
        case '@': { __unsafe_unretained id r = nil; [inv getReturnValue:&r]; return E2EJSONValue(r); }
        case 'B': { BOOL r; [inv getReturnValue:&r]; return @(r); }
        case 'c': { char r; [inv getReturnValue:&r]; return @(r); }
        case 'i': { int r; [inv getReturnValue:&r]; return @(r); }
        case 'I': { unsigned r; [inv getReturnValue:&r]; return @(r); }
        case 'q': case 'l': { long long r; [inv getReturnValue:&r]; return @(r); }
        case 'Q': case 'L': { unsigned long long r; [inv getReturnValue:&r]; return @(r); }
        case 'd': { double r; [inv getReturnValue:&r]; return @(r); }
        case 'f': { float r; [inv getReturnValue:&r]; return @(r); }
        case '{': {
            NSString *t = @(rtype);
            if ([t hasPrefix:@"{CGRect"]) { NSRect r; [inv getReturnValue:&r]; return E2ERect(r); }
            if ([t hasPrefix:@"{_NSRange"]) { NSRange r; [inv getReturnValue:&r]; return @[@(r.location), @(r.length)]; }
            if ([t hasPrefix:@"{CGSize"]) { NSSize r; [inv getReturnValue:&r]; return @[@(r.width), @(r.height)]; }
            if ([t hasPrefix:@"{CGPoint"]) { NSPoint r; [inv getReturnValue:&r]; return @[@(r.x), @(r.y)]; }
            return @"<struct>";
        }
        default: return @"<unsupported return>";
    }
}

static id E2ETarget(NSString *name, NSError **error) {
    AppDelegate *app = (AppDelegate *)NSApp.delegate;
    EditorController *ed = app.editor;
    if (!name.length || [name isEqual:@"app"]) return app;
    if ([name isEqual:@"editor"]) return ed;
    if ([name isEqual:@"nsapp"]) return NSApp;
    if ([name isEqual:@"sci"]) return ed.sci;
    if ([name isEqual:@"sub"]) return ed.secondarySci;
    if ([name isEqual:@"window"]) return app.window;
    if ([name isEqual:@"prefs"]) return [NppPreferences shared];
    if ([name isEqual:@"document"]) return ed.currentDocument;
    if ([name isEqual:@"first_responder"]) return app.window.firstResponder;
    if ([name isEqual:@"key_first_responder"]) return NSApp.keyWindow.firstResponder;
    if ([name hasPrefix:@"class:"]) {
        // A shared object of a class: +shared, +sharedCatalog, +defaultManager...
        Class c = NSClassFromString([name substringFromIndex:6]);
        for (NSString *s in @[@"shared", @"sharedCatalog", @"sharedInstance", @"sharedManager"]) {
            if ([c respondsToSelector:NSSelectorFromString(s)]) {
                id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
                return send(c, NSSelectorFromString(s));
            }
        }
        if (c) return c;
    }
    if ([name hasPrefix:@"window:"]) {
        NSWindow *w = E2EFindWindow([name substringFromIndex:7], error);
        return w;
    }
    if ([name hasPrefix:@"delegate:"]) {
        NSWindow *w = E2EFindWindow([name substringFromIndex:9], error);
        return w.delegate ?: w.windowController;
    }
    if (error) *error = E2EFail(@"No target %@", name);
    return nil;
}

#pragma mark - Tools

@implementation NppAgentServer (E2E)

- (void)registerE2ETools {
    if (!NppE2EEnabled()) return;
    NppE2EInstall();

    [self addTool:@"e2e_sci"
      description:@"E2E: sends a Scintilla message to a view (main, sub, front = the focused one, map). lparam is an "
                  @"integer or a string (passed as a C string); returns=string reads a string answer the way "
                  @"SCI_GETTEXT-style messages give one (first asking for the length with lparam 0)."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        EditorController *ed = app.editor;
        NSString *which = args[@"view"] ?: @"main";
        ScintillaView *sci = ed.sci;
        if ([which isEqual:@"sub"]) sci = ed.secondarySci;
        else if ([which isEqual:@"front"]) {
            id responder = app.window.firstResponder;
            if ([responder isKindOfClass:[NSView class]] && ed.secondarySci && [(NSView *)responder isDescendantOf:ed.secondarySci]) sci = ed.secondarySci;
        }
        else if (![which isEqual:@"main"]) {
            id v = nil;
            @try { v = [ed valueForKey:which]; } @catch (NSException *e) {}
            if ([v isKindOfClass:[ScintillaView class]]) sci = v; else { *error = E2EFail(@"No view %@", which); return nil; }
        }
        if (!sci) { *error = E2EFail(@"View %@ is not there", which); return nil; }
        unsigned int message = [args[@"message"] unsignedIntValue];
        uptr_t w = (uptr_t)[args[@"wparam"] longLongValue];
        id l = args[@"lparam"];
        if ([args[@"returns"] isEqual:@"string"]) {
            sptr_t length = [sci message:message wParam:w lParam:0];
            if (length < 0) length = 0;
            NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)length + 2];
            // SCI_GETTEXT and SCI_GETCURLINE take the buffer's size in wParam: asked with 0 (the
            // length query) they would copy nothing on the second call.
            if (!w && (message == SCI_GETTEXT || message == SCI_GETCURLINE)) w = (uptr_t)length + 1;
            [sci message:message wParam:w lParam:(sptr_t)buffer.mutableBytes];
            NSString *s = [[NSString alloc] initWithBytes:buffer.bytes length:strnlen((const char *)buffer.bytes, (size_t)length + 1) encoding:NSUTF8StringEncoding] ?: @"";
            return @{@"result": @(length), @"text": s};
        }
        sptr_t result;
        if ([l isKindOfClass:[NSString class]]) {
            result = [sci message:message wParam:w lParam:(sptr_t)[l UTF8String]];
        } else {
            result = [sci message:message wParam:w lParam:(sptr_t)[l longLongValue]];
        }
        return @{@"result": @(result)};
    }];

    [self addTool:@"e2e_menu"
      description:@"E2E: menu items' state. commands: IDM names, ids or menu paths (A|B|C); tree: a top menu's "
                  @"title (or 'main') to dump with depth; context: 'tab' for the tab context menu."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        NSDictionary<NSNumber *, NSMenuItem *> *byId = [app.shortcutStore menuItemsByIdentifier];
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NSArray *commands = args[@"commands"];
        if ([commands isKindOfClass:[NSArray class]]) {
            NSMutableDictionary *items = [NSMutableDictionary dictionary];
            for (id c in commands) {
                NSMenuItem *item = nil;
                if ([c isKindOfClass:[NSNumber class]]) item = byId[c];
                else if ([c hasPrefix:@"IDM_"]) {
                    for (int i = 0; i < kNppMenuCommandIDCount; ++i) if (!strcmp(kNppMenuCommandIDs[i].name, [c UTF8String])) { item = byId[@(kNppMenuCommandIDs[i].identifier)]; break; }
                } else item = E2EMenuItemAtPath(NSApp.mainMenu, c);
                items[[c description]] = item ? E2EMenuItemInfo(item) : [NSNull null];
            }
            out[@"items"] = items;
        }
        NSString *tree = args[@"tree"];
        if (tree) {
            NSMenu *menu = NSApp.mainMenu;
            if (![tree isEqual:@"main"]) {
                NSMenuItem *top = E2EMenuItemAtPath(NSApp.mainMenu, tree);
                if (!top.submenu) { *error = E2EFail(@"No menu %@", tree); return nil; }
                menu = top.submenu;
            }
            out[@"tree"] = E2EMenuTree(menu, args[@"depth"] ? [args[@"depth"] integerValue] : 1);
        }
        if ([args[@"context"] isEqual:@"tab"]) out[@"tree"] = E2EMenuTree([app buildTabContextMenu], 2);
        if ([args[@"context"] isEqual:@"editor"]) {
            out[@"tree"] = E2EMenuTree(E2EEditorContextMenu(), 2);
        }
        return out;
    }];

    [self addTool:@"e2e_menu_invoke"
      description:@"E2E: performs a menu item found by its path (A|B|C) in the main menu, or in the tab/editor "
                  @"context menu (context=tab|editor), as a click on it would."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        NSMenu *root = NSApp.mainMenu;
        if ([args[@"context"] isEqual:@"tab"]) root = [app buildTabContextMenu];
        if ([args[@"context"] isEqual:@"editor"]) root = E2EEditorContextMenu();
        NSMenuItem *item = E2EMenuItemAtPath(root, args[@"path"] ?: @"");
        if (!item) { *error = E2EFail(@"No menu item %@", args[@"path"]); return nil; }
        [item.menu update];
        if (!item.isEnabled) return @{@"ran": @NO, @"enabled": @NO};
        NSInteger index = [item.menu indexOfItem:item];
        // Held keys, for commands that read them (Redact with Shift).
        gE2EForcedModifiers = E2EModifierFlags(args[@"modifiers"]);
        gE2EModifiersForced = [args[@"modifiers"] count] > 0;
        [item.menu performActionForItemAtIndex:index];
        gE2EModifiersForced = NO;
        return @{@"ran": @YES, @"enabled": @YES, @"title": item.title};
    }];

    [self addTool:@"e2e_windows"
      description:@"E2E: the application's windows (number, title, class, visible, key, modal, sheet, frame)."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSMutableArray *out = [NSMutableArray array];
        BOOL all = [args[@"all"] boolValue];
        for (NSWindow *w in E2EWindows()) if (all || w.isVisible) [out addObject:E2EWindowInfo(w)];
        return @{@"windows": out, @"modal": NSApp.modalWindow ? @(NSApp.modalWindow.windowNumber) : [NSNull null],
                 @"key": NSApp.keyWindow ? @(NSApp.keyWindow.windowNumber) : [NSNull null],
                 @"active": @(NSApp.isActive)};
    }];

    [self addTool:@"e2e_ui"
      description:@"E2E: the controls in a window (window: number, title, class, main, key, modal), each with a path, "
                  @"class, title/value/state/items, enabled, tooltip, frame; tables with their cells. toolbar=true adds "
                  @"the toolbar's items."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSWindow *w = E2EFindWindow(args[@"window"], error);
        if (!w) return nil;
        [w.contentView layoutSubtreeIfNeeded];
        NSMutableArray *controls = [NSMutableArray array];
        NSView *root = w.contentView.superview ?: w.contentView;
        E2EWalk(root, @"0", [args[@"include_hidden"] boolValue], controls);
        NSMutableDictionary *out = [@{@"window": E2EWindowInfo(w), @"controls": controls} mutableCopy];
        if (w.toolbar) {
            [w.toolbar validateVisibleItems];   // as the user would see it after the next event
            NSMutableArray *items = [NSMutableArray array];
            for (NSToolbarItem *i in w.toolbar.items) {
                [items addObject:@{@"id": i.itemIdentifier ?: @"", @"label": i.label ?: @"", @"tooltip": i.toolTip ?: @"",
                                   @"enabled": @(i.isEnabled), @"action": i.action ? NSStringFromSelector(i.action) : @""}];
            }
            out[@"toolbar"] = @{@"visible": @(w.toolbar.isVisible), @"items": items};
        }
        return out;
    }];

    [self addTool:@"e2e_act"
      description:@"E2E: acts on a control as a user would. window + target {path | title | id | class | tooltip | "
                  @"placeholder, index}; action: click, set_value (value), set_state (value 0/1), select (value: "
                  @"title or index for popups, segments, tabs; row for tables), double_click (tables), set_text "
                  @"(text views), focus, close_window, toolbar (value: item id or label)."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSWindow *w = E2EFindWindow(args[@"window"], error);
        if (!w) return nil;
        NSString *action = args[@"action"] ?: @"click";
        id value = args[@"value"];
        if ([action isEqual:@"close_window"]) {
            if (NSApp.modalWindow == w) [NSApp abortModal];
            if (w.sheetParent) [w.sheetParent endSheet:w returnCode:NSModalResponseCancel];
            [w performClose:nil];
            if (w.isVisible && ![args[@"polite"] boolValue]) [w close];
            return @{@"closed": @(!w.isVisible)};
        }
        if ([action isEqual:@"resize_window"]) {
            NSArray *size = value;
            NSRect f = w.frame;
            NSRect content = [w contentRectForFrameRect:f];
            content.size = NSMakeSize([size[0] doubleValue], [size[1] doubleValue]);
            NSRect nf = [w frameRectForContentRect:content];
            nf.origin.y = NSMaxY(f) - nf.size.height;   // the top edge stays
            [w setFrame:nf display:YES];
            return @{@"frame": E2ERect(w.frame), @"content": E2ERect([w contentRectForFrameRect:w.frame])};
        }
        if ([action isEqual:@"toolbar"]) {
            // AppKit validates the toolbar on every event, long before a real click lands.
            [w.toolbar validateVisibleItems];
            for (NSToolbarItem *i in w.toolbar.items) {
                if ([i.itemIdentifier isEqual:value] || [i.label isEqual:value] || [i.toolTip isEqual:value]) {
                    if (!i.isEnabled) return @{@"ran": @NO};
                    [NSApp sendAction:i.action to:i.target from:i];
                    return @{@"ran": @YES};
                }
            }
            *error = E2EFail(@"No toolbar item %@", value);
            return nil;
        }
        NSView *v = E2EFindControl(w, args[@"target"] ?: @{}, error);
        if (!v) return nil;
        if ([v isKindOfClass:[NSControl class]] && ![(NSControl *)v isEnabled] && ![action isEqual:@"focus"]) {
            return @{@"acted": @NO, @"reason": @"disabled", @"control": E2EControlInfo(v, @"")};
        }
        if ([action isEqual:@"click"]) {
            if ([v isKindOfClass:[NSButton class]]) [(NSButton *)v performClick:nil];
            else if ([v isKindOfClass:[NSControl class]]) E2ESendAction((NSControl *)v);
            else {
                // A custom view that takes clicks: a mouse down and up in its middle.
                NSPoint mid = [v convertPoint:NSMakePoint(NSMidX(v.bounds), NSMidY(v.bounds)) toView:nil];
                E2EClickAt(w, mid, 0, 1, v);
            }
        } else if ([action isEqual:@"set_value"]) {
            NSString *s = E2EString(value) ?: @"";
            if ([v isKindOfClass:[NSTextView class]]) {
                NSTextView *t = (NSTextView *)v;
                if ([t shouldChangeTextInRange:NSMakeRange(0, t.string.length) replacementString:s]) { t.string = s; [t didChangeText]; }
            } else if ([v isKindOfClass:[NSColorWell class]]) {
                unsigned rgb = 0;
                [[NSScanner scannerWithString:[s stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&rgb];
                [(NSColorWell *)v setColor:[NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0 green:((rgb >> 8) & 0xff) / 255.0 blue:(rgb & 0xff) / 255.0 alpha:1]];
                E2ESendAction((NSControl *)v);
            } else if ([v isKindOfClass:[NSSlider class]]) {
                [(NSSlider *)v setDoubleValue:[value doubleValue]];
                E2ESendAction((NSControl *)v);
            } else if ([v isKindOfClass:[NSControl class]]) {
                NSControl *c = (NSControl *)v;
                c.stringValue = s;
                [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:c
                                                                  userInfo:@{@"NSFieldEditor": [w fieldEditor:YES forObject:c] ?: [NSNull null]}];
                id delegate = [c respondsToSelector:@selector(delegate)] ? [(id)c delegate] : nil;
                if ([delegate respondsToSelector:@selector(controlTextDidEndEditing:)] && [args[@"end_editing"] boolValue]) {
                    [delegate controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:c]];
                }
                if ([args[@"send_action"] boolValue]) E2ESendAction(c);
            }
        } else if ([action isEqual:@"set_state"]) {
            if (![v isKindOfClass:[NSButton class]]) { *error = E2EFail(@"Not a button"); return nil; }
            NSButton *b = (NSButton *)v;
            NSControlStateValue want = [value integerValue] ? NSControlStateValueOn : NSControlStateValueOff;
            if (b.state != want) [b performClick:nil];
            if (b.state != want) { b.state = want; E2ESendAction(b); }
        } else if ([action isEqual:@"select"]) {
            if ([v isKindOfClass:[NSPopUpButton class]]) {
                NSPopUpButton *p = (NSPopUpButton *)v;
                NSInteger i = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : [p indexOfItemWithTitle:value];
                if (i < 0 || i >= p.numberOfItems) { *error = E2EFail(@"No item %@", value); return nil; }
                [p selectItemAtIndex:i];
                E2ESendAction(p);
            } else if ([v isKindOfClass:[NSMatrix class]]) {
                NSMatrix *m = (NSMatrix *)v;
                NSInteger row = -1;
                if ([value isKindOfClass:[NSNumber class]]) row = [value integerValue];
                else for (NSInteger r = 0; r < m.numberOfRows; ++r) if ([[[m cellAtRow:r column:0] title] isEqual:value]) row = r;
                if (row < 0 || row >= m.numberOfRows) { *error = E2EFail(@"No row %@", value); return nil; }
                [m selectCellAtRow:row column:0];
                E2ESendAction(m);
            } else if ([v isKindOfClass:[NSSegmentedControl class]]) {
                NSSegmentedControl *s = (NSSegmentedControl *)v;
                NSInteger i = -1;
                if ([value isKindOfClass:[NSNumber class]]) i = [value integerValue];
                else for (NSInteger k = 0; k < s.segmentCount; ++k) if ([[s labelForSegment:k] isEqual:value] || [[s toolTipForSegment:k] isEqual:value]) i = k;
                if (i < 0 || i >= s.segmentCount) { *error = E2EFail(@"No segment %@", value); return nil; }
                if (s.trackingMode == NSSegmentSwitchTrackingSelectAny) [s setSelected:![s isSelectedForSegment:i] forSegment:i];
                else s.selectedSegment = i;
                E2ESendAction(s);
            } else if ([v isKindOfClass:[NSTabView class]]) {
                NSTabView *t = (NSTabView *)v;
                if ([value isKindOfClass:[NSNumber class]]) [t selectTabViewItemAtIndex:[value integerValue]];
                else {
                    NSInteger found = -1;
                    for (NSTabViewItem *item in t.tabViewItems) if ([item.label isEqual:value]) found = [t indexOfTabViewItem:item];
                    if (found < 0) { *error = E2EFail(@"No tab %@", value); return nil; }
                    [t selectTabViewItemAtIndex:found];
                }
            } else if ([v isKindOfClass:[NSTableView class]]) {
                NSTableView *t = (NSTableView *)v;
                NSInteger row = [value integerValue];
                if (row < 0 || row >= t.numberOfRows) { *error = E2EFail(@"No row %ld", (long)row); return nil; }
                [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:[args[@"extend"] boolValue]];
                [t scrollRowToVisible:row];
                if ([args[@"send_action"] boolValue] && t.action) [NSApp sendAction:t.action to:t.target from:t];
            } else if ([v isKindOfClass:[NSComboBox class]]) {
                NSComboBox *c = (NSComboBox *)v;
                NSInteger i = [value isKindOfClass:[NSNumber class]] ? [value integerValue] : [c indexOfItemWithObjectValue:value];
                if (i < 0) { c.stringValue = E2EString(value); } else [c selectItemAtIndex:i];
                E2ESendAction(c);
            } else { *error = E2EFail(@"Cannot select in %@", NSStringFromClass(v.class)); return nil; }
        } else if ([action isEqual:@"double_click"]) {
            if (![v isKindOfClass:[NSTableView class]]) { *error = E2EFail(@"Not a table"); return nil; }
            NSTableView *t = (NSTableView *)v;
            NSInteger row = [value integerValue];
            if (row < 0 || row >= t.numberOfRows) { *error = E2EFail(@"No row %ld", (long)row); return nil; }
            [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            // clickedRow, which double actions read, comes only from a real
            // click: two mouse downs and ups in the row's middle.
            [t scrollRowToVisible:row];
            NSRect rect = [t rectOfRow:row];
            if (args[@"column"]) {
                NSInteger column = [args[@"column"] integerValue];
                [t scrollColumnToVisible:column];
                rect = NSIntersectionRect(rect, [t rectOfColumn:column]);
            }
            // The part of the row on screen: a table wider than its panel (a narrow dock) has its
            // middle out of sight, and a click there lands on whatever is beside the panel.
            NSRect shown = NSIntersectionRect(rect, t.visibleRect);
            if (!NSIsEmptyRect(shown)) rect = shown;
            NSPoint p = [t convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
            gE2EForcedKeyWindow = w;
            for (NSInteger c = 1; c <= 2; ++c) E2EClickAt(w, p, 0, c, nil);
            gE2EForcedKeyWindow = nil;
        } else if ([action isEqual:@"set_text"]) {
            if (![v isKindOfClass:[NSTextView class]]) { *error = E2EFail(@"Not a text view"); return nil; }
            NSTextView *t = (NSTextView *)v;
            NSString *s = E2EString(value) ?: @"";
            [t setSelectedRange:NSMakeRange(0, t.string.length)];
            [t insertText:s replacementRange:NSMakeRange(0, t.string.length)];
        } else if ([action isEqual:@"focus"]) {
            [w makeKeyAndOrderFront:nil];
            [w makeFirstResponder:v];
        } else {
            *error = E2EFail(@"Unknown action %@", action);
            return nil;
        }
        NSMutableDictionary *after = [@{@"acted": @YES} mutableCopy];
        if (v.window) after[@"control"] = E2EControlInfo(v, @"");
        return after;
    }];

    [self addTool:@"e2e_keys"
      description:@"E2E: key presses, as the keyboard would send them: keys is a list like [\"cmd+f\", \"escape\", "
                  @"\"alt+shift+down\"]; text types each character in turn. Sent to window (default: key, else main)."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        NSWindow *w = args[@"window"] ? E2EFindWindow(args[@"window"], error) : (NSApp.keyWindow ?: app.window);
        if (!w) return nil;
        if (!w.isKeyWindow) [w makeKeyAndOrderFront:nil];
        long sent = 0;
        // hold: modifiers pressed (a flagsChanged event) before the keys;
        // release: let go of them after (the Ctrl+Tab switcher acts on that).
        NSEventModifierFlags held = E2EModifierFlags(args[@"hold"]);
        void (^flags)(NSEventModifierFlags) = ^(NSEventModifierFlags f) {
            NSEvent *e = [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:f
                                         timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber
                                           context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO
                                           keyCode:(f & NSEventModifierFlagControl) ? 59 : (f & NSEventModifierFlagOption) ? 58 : (f & NSEventModifierFlagShift) ? 56 : 55];
            gE2EForcedKeyWindow = w;
            gE2EForcedModifiers = f;
            gE2EModifiersForced = YES;
            [NSApp sendEvent:e];
            gE2EForcedKeyWindow = nil;
        };
        if (held) flags(held);
        for (NSString *k in args[@"keys"] ?: @[]) {
            if (!E2EPressKey(k, w, error)) return nil;
            sent++;
        }
        if ([args[@"release"] boolValue]) { flags(0); gE2EModifiersForced = NO; }
        else if (held && ![args[@"keep_held"] boolValue]) gE2EModifiersForced = NO;
        NSDictionary *marked = args[@"marked"];
        if ([marked isKindOfClass:[NSDictionary class]]) {
            // An input method's composition: the marked (underlined) stages,
            // then the committed text.
            id fr = w.firstResponder;
            if ([fr isKindOfClass:[ScintillaView class]]) fr = [(ScintillaView *)fr content];
            for (NSString *stage in marked[@"stages"] ?: @[]) {
                [fr setMarkedText:stage selectedRange:NSMakeRange(stage.length, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
            }
            if (marked[@"commit"]) [fr insertText:marked[@"commit"] replacementRange:NSMakeRange(NSNotFound, 0)];
            else if ([marked[@"cancel"] boolValue]) [fr unmarkText];
            sent++;
        }
        NSString *text = args[@"text"];
        if ([text isKindOfClass:[NSString class]]) {
            __block BOOL ok = YES;
            [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences
                                  usingBlock:^(NSString *ch, NSRange r1, NSRange r2, BOOL *stop) {
                NSString *spec = [ch isEqual:@"\n"] ? @"return" : [ch isEqual:@"\t"] ? @"tab" : ch;
                id fr = w.firstResponder;
                if ([fr isKindOfClass:[ScintillaView class]]) fr = [(ScintillaView *)fr content];
                BOOL printable = ch.length > 1 || ([ch characterAtIndex:0] >= 0x20 && [ch characterAtIndex:0] != 0x7f);
                if (printable && [fr respondsToSelector:@selector(insertText:replacementRange:)] && [args[@"as_input_method"] ?: @YES boolValue]) {
                    // What an input method hands over for a typed character:
                    // Scintilla's typing path (auto-close, auto-completion,
                    // auto-indent on the next Return) sees it as typed.
                    [fr insertText:ch replacementRange:NSMakeRange(NSNotFound, 0)];
                } else if (ch.length > 1 || [ch characterAtIndex:0] > 0x7e) {
                    // Outside the keyboard map: as an input method would give it.
                    id responder = w.firstResponder;
                    if ([responder respondsToSelector:@selector(insertText:replacementRange:)]) [responder insertText:ch replacementRange:NSMakeRange(NSNotFound, 0)];
                } else if (!E2EPressKey(spec, w, NULL)) { ok = NO; *stop = YES; }
            }];
            if (!ok) { *error = E2EFail(@"Could not type %@", text); return nil; }
            sent += (long)text.length;
        }
        return @{@"sent": @(sent), @"window": @(w.windowNumber)};
    }];

    [self addTool:@"e2e_snapshot"
      description:@"E2E: renders a window's content (window as for e2e_ui; main by default) to a PNG at path."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSWindow *w = E2EFindWindow(args[@"window"], error);
        if (!w) return nil;
        NSString *path = args[@"path"];
        if (!path.length) { *error = E2EFail(@"Give a path"); return nil; }
        // frame=true: the whole window, title bar and toolbar included.
        NSView *view = [args[@"frame"] boolValue] ? (w.contentView.superview ?: w.contentView) : w.contentView;
        [view layoutSubtreeIfNeeded];
        [view setNeedsDisplay:YES];
        [w displayIfNeeded];
        NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:path atomically:YES]) { *error = E2EFail(@"Cannot write %@", path); return nil; }
        return @{@"path": path, @"width": @(rep.pixelsWide), @"height": @(rep.pixelsHigh)};
    }];

    [self addTool:@"e2e_prefs"
      description:@"E2E: preferences (NSUserDefaults keys without the NppMac. prefix). get: list of names; set: "
                  @"{name: value} (null removes), then applied to the editor as Preferences would; all=true lists every "
                  @"stored one."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NSDictionary *set = args[@"set"];
        if ([set isKindOfClass:[NSDictionary class]]) {
            for (NSString *k in set) {
                id v = set[k];
                NSString *key = [@"NppMac." stringByAppendingString:k];
                if (v == [NSNull null]) [d removeObjectForKey:key]; else [d setObject:v forKey:key];
            }
            if (![args[@"no_apply"] boolValue]) {
                [[NppPreferences shared] applyToEditor:app.editor];
                [app applyToolbarPreferences];
                [app.editor refreshChrome];
            }
        }
        for (NSString *k in args[@"get"] ?: @[]) out[k] = E2EJSONValue([d objectForKey:[@"NppMac." stringByAppendingString:k]]);
        if ([args[@"all"] boolValue]) {
            NSDictionary *everything = [d persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
            NSMutableDictionary *mine = [NSMutableDictionary dictionary];
            for (NSString *k in everything) if ([k hasPrefix:@"NppMac."]) mine[[k substringFromIndex:7]] = E2EJSONValue(everything[k]);
            out[@"all"] = mine;
        }
        return @{@"values": out};
    }];

    [self addTool:@"e2e_clipboard"
      description:@"E2E: the (private) clipboard: set puts a string on it; always returns its string and types."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        if ([args[@"set"] isKindOfClass:[NSString class]]) {
            [pb clearContents];
            [pb setString:args[@"set"] forType:NSPasteboardTypeString];
        }
        if ([args[@"clear"] boolValue]) [pb clearContents];
        if ([args[@"set_types"] isKindOfClass:[NSDictionary class]]) {
            // {type: text} - e.g. public.html, public.rtf beside public.utf8-plain-text.
            [pb clearContents];
            NSDictionary *types = args[@"set_types"];
            [pb declareTypes:types.allKeys owner:nil];
            for (NSString *t in types) [pb setData:[types[t] dataUsingEncoding:NSUTF8StringEncoding] forType:t];
        }
        if ([args[@"image"] isKindOfClass:[NSString class]]) {
            // An image file's picture on the clipboard, as a screenshot or a
            // Copy Image in another application leaves it.
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:args[@"image"]];
            if (!image) { *error = E2EFail(@"Cannot read the image %@", args[@"image"]); return nil; }
            [pb clearContents];
            [pb writeObjects:@[image]];
        }
        if ([args[@"files"] isKindOfClass:[NSArray class]]) {
            NSMutableArray *urls = [NSMutableArray array];
            for (NSString *p in args[@"files"]) [urls addObject:[NSURL fileURLWithPath:p]];
            [pb clearContents];
            [pb writeObjects:urls];
        }
        NSMutableArray *types = [NSMutableArray array];
        for (NSString *t in pb.types ?: @[]) [types addObject:t];
        NSMutableDictionary *out = [@{@"text": [pb stringForType:NSPasteboardTypeString] ?: [NSNull null], @"types": types} mutableCopy];
        if ([args[@"type"] isKindOfClass:[NSString class]]) {
            NSData *data = [pb dataForType:args[@"type"]];
            out[@"data"] = data ? [data base64EncodedStringWithOptions:0] : [NSNull null];
        }
        return out;
    }];

    [self addTool:@"e2e_answers"
      description:@"E2E: queues answers for modal alerts (alerts: 1-based button numbers, button titles, or "
                  @"{button, field}) and open/save panels (panels: a path, a list of paths, or null to cancel). "
                  @"real_modals=true lets an unanswered one run for real (to drive it with e2e_act from another "
                  @"connection); otherwise it takes its default and is logged as unexpected. clear=true empties the queues."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NppE2EState *s = [NppE2EState shared];
        if ([args[@"clear"] boolValue]) { [s.alertAnswers removeAllObjects]; [s.panelAnswers removeAllObjects]; }
        for (id a in args[@"alerts"] ?: @[]) [s.alertAnswers addObject:a];
        for (id p in args[@"panels"] ?: @[]) [s.panelAnswers addObject:p];
        if (args[@"real_modals"]) s.realModals = [args[@"real_modals"] boolValue];
        return @{@"alerts_queued": @(s.alertAnswers.count), @"panels_queued": @(s.panelAnswers.count), @"real_modals": @(s.realModals)};
    }];

    [self addTool:@"e2e_log"
      description:@"E2E: the alerts and panels shown since the last clear (what they said, which answer they took). "
                  @"clear=true empties it after reading."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NppE2EState *s = [NppE2EState shared];
        NSArray *entries = [s.log copy];
        if ([args[@"clear"] boolValue]) [s.log removeAllObjects];
        return @{@"entries": entries};
    }];

    [self addTool:@"e2e_invoke"
      description:@"E2E: calls a method (selector with up to two arguments) on target: app, editor, sci, sub, window, "
                  @"prefs, document, first_responder, class:<Name> (its shared instance), window:<spec>, "
                  @"delegate:<window spec>. For what has no menu command: a panel's button action, a view mode. key "
                  @"reads a property by key path instead."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        id target = E2ETarget(args[@"target"], error);
        if (!target) return nil;
        if ([args[@"key"] isKindOfClass:[NSString class]]) {
            id value = nil;
            @try { value = [target valueForKeyPath:args[@"key"]]; }
            @catch (NSException *e) { *error = E2EFail(@"%@", e.reason); return nil; }
            return @{@"value": E2EJSONValue(value)};
        }
        id result = E2EInvoke(target, args[@"selector"] ?: @"", args[@"arguments"] ?: @[], error);
        if (!result) return nil;
        return @{@"value": result};
    }];

    [self addTool:@"e2e_counters"
      description:@"E2E: beeps since launch (NppBeep; muted ones counted apart). reset=true zeroes them."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSDictionary *out = @{@"beeps": @(gE2EBeeps), @"muted_beeps": @(gE2EMutedBeeps)};
        if ([args[@"reset"] boolValue]) gE2EBeeps = gE2EMutedBeeps = 0;
        return out;
    }];

    [self addTool:@"e2e_mouse"
      description:@"E2E: a mouse click on a view: window + target (as e2e_act; or view: main|sub for the editors), "
                  @"point [x, y] in the view's own coordinates (default: its middle; for an editor, point may be "
                  @"{line, column} one-based), clicks (1, 2, 3), modifiers ['cmd','alt','shift','ctrl'], "
                  @"button left|right. A right click does not pop the menu up: it returns the menu the view gives "
                  @"for it, and performs menu_path (A|B) in it when given."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        NSView *v = nil;
        NSWindow *w = nil;
        NSString *editor = args[@"view"];
        if ([editor isEqual:@"main"] || [editor isEqual:@"sub"]) {
            ScintillaView *sci = [editor isEqual:@"sub"] ? app.editor.secondarySci : app.editor.sci;
            v = sci.content;
            w = sci.window;
            id point = args[@"point"];
            if ([point isKindOfClass:[NSDictionary class]]) {
                long line = [point[@"line"] longValue] - 1, col = MAX(0, [point[@"column"] longValue] - 1);
                long pos = [sci message:SCI_FINDCOLUMN wParam:(uptr_t)line lParam:col];
                long x = point[@"x"] ? [point[@"x"] longValue] : [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:pos];
                if (point[@"margin"]) {
                    // The middle of margin N, counted from the left edge.
                    long left = 0, m = [point[@"margin"] longValue];
                    for (long k = 0; k < m; ++k) left += [sci message:SCI_GETMARGINWIDTHN wParam:(uptr_t)k lParam:0];
                    x = left + [sci message:SCI_GETMARGINWIDTHN wParam:(uptr_t)m lParam:0] / 2;
                }
                long y = [sci message:SCI_POINTYFROMPOSITION wParam:0 lParam:pos] + [sci message:SCI_TEXTHEIGHT wParam:(uptr_t)line lParam:0] / 2;
                NSPoint inContent = NSMakePoint(x + 1, y);   // Scintilla's client coordinates are the content view's visible rect
                NSRect visible = v.visibleRect;
                args = [args mutableCopy];
                [(NSMutableDictionary *)args setObject:@[@(visible.origin.x + inContent.x), @(visible.origin.y + inContent.y)] forKey:@"point"];
            }
        } else {
            w = E2EFindWindow(args[@"window"], error);
            if (!w) return nil;
            v = E2EFindControl(w, args[@"target"] ?: @{}, error);
            if (!v) return nil;
        }
        NSPoint local = NSMakePoint(NSMidX(v.bounds), NSMidY(v.bounds));
        NSArray *pt = args[@"point"];
        if ([pt isKindOfClass:[NSArray class]] && pt.count == 2) local = NSMakePoint([pt[0] doubleValue], [pt[1] doubleValue]);
        NSPoint inWindow = [v convertPoint:local toView:nil];
        NSEventModifierFlags flags = 0;
        for (NSString *m in args[@"modifiers"] ?: @[]) {
            if ([m isEqual:@"cmd"]) flags |= NSEventModifierFlagCommand;
            else if ([m isEqual:@"alt"] || [m isEqual:@"option"]) flags |= NSEventModifierFlagOption;
            else if ([m isEqual:@"shift"]) flags |= NSEventModifierFlagShift;
            else if ([m isEqual:@"ctrl"]) flags |= NSEventModifierFlagControl;
        }
        BOOL right = [args[@"button"] isEqual:@"right"];
        if (right) {
            // What the editor's event monitor does for a real right click (menuForEvent: below
            // does not pass it): the caret moves unless the selection is to be kept.
            [app.editor contextClickAtWindowPoint:inWindow window:w];
            NSEvent *e = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:inWindow modifierFlags:flags
                                           timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:w.windowNumber
                                             context:nil eventNumber:0 clickCount:1 pressure:1];
            NSView *hit = [w.contentView.superview hitTest:inWindow] ?: v;
            NSMenu *menu = nil;
            for (NSView *h = hit; h && !menu; h = h.superview) menu = [h menuForEvent:e];
            if (!menu) return @{@"menu": [NSNull null]};
            NSString *path = args[@"menu_path"];
            if (path) {
                NSMenuItem *item = E2EMenuItemAtPath(menu, path);
                if (!item) { *error = E2EFail(@"No item %@ in the context menu", path); return nil; }
                [item.menu update];
                if (!item.isEnabled) return @{@"ran": @NO, @"menu": E2EMenuTree(menu, 2)};
                [item.menu performActionForItemAtIndex:[item.menu indexOfItem:item]];
                return @{@"ran": @YES};
            }
            return @{@"menu": E2EMenuTree(menu, 2)};
        }
        NSInteger clicks = args[@"clicks"] ? [args[@"clicks"] integerValue] : 1;
        gE2EForcedKeyWindow = w;
        for (NSInteger c = 1; c <= clicks; ++c) E2EClickAt(w, inWindow, flags, c, nil);
        gE2EForcedKeyWindow = nil;
        return @{@"clicked": @(clicks), @"at": @[@(inWindow.x), @(inWindow.y)]};
    }];

    [self addTool:@"e2e_idle"
      description:@"E2E: lets the run loop turn for seconds (default 0.1), so timers and delayed work run."
           schema:E2ESchema(@{})
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        double seconds = args[@"seconds"] ? [args[@"seconds"] doubleValue] : 0.1;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
        return @{@"idle": @(seconds)};
    }];
}

@end
