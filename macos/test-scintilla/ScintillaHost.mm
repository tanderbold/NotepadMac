// A Scintilla instance with no user interface, so Scintilla's own Python tests
// can drive it on macOS.
//
// Those tests are written against the direct-call interface -- fn(ptr, msg, w, l)
// -- which is the same on every platform. The Windows harness gets that pointer
// from a window it creates; here the same pointer comes from a ScintillaView
// living in an off-screen window. Nothing else about the tests has to change.
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#include "Scintilla.h"
#include "ILexer.h"
#include "Lexilla.h"

extern "C" {

/// Creates the instance and keeps it alive for the life of the process.
void *NppTestScintillaCreate(void) {
    static ScintillaView *view;
    static NSWindow *window;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // AppKit needs to be initialised before any view is made, even one that
        // is never shown.
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 800, 600);
        window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
        view = [[ScintillaView alloc] initWithFrame:frame];
        window.contentView = view;
    });
    return (__bridge void *)view;
}

/// The direct interface. The Cocoa port does not answer SCI_GETDIRECTFUNCTION,
/// so the function is supplied here with the signature every host expects --
/// fn(ptr, message, wParam, lParam) -- forwarding to the view. The "pointer" is
/// the view itself.
static sptr_t NppTestSend(void *instance, unsigned int message,
                          uptr_t wParam, sptr_t lParam) {
    ScintillaView *view = (__bridge ScintillaView *)instance;
    return [view message:message wParam:wParam lParam:lParam];
}

void *NppTestScintillaDirectFunction(void *instance) {
    (void)instance;
    return (void *)NppTestSend;
}

void *NppTestScintillaDirectPointer(void *instance) {
    return instance;
}

/// Lexilla is linked in, so a lexer is created here rather than loaded.
void *NppTestCreateLexer(const char *name) {
    return CreateLexer(name);
}

/// Lets the run loop do whatever it has queued, which is what the tests mean by
/// DoEvents.
void NppTestDoEvents(void) {
    @autoreleasepool {
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.01];
        while (true) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                                untilDate:[NSDate distantPast]
                                                   inMode:NSDefaultRunLoopMode
                                                  dequeue:YES];
            if (!event) break;
            [NSApp sendEvent:event];
        }
        [[NSRunLoop currentRunLoop] runUntilDate:until];
    }
}

}
