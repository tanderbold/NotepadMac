#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

void NppE2EInstall(void);   // E2EHooks.mm: nothing unless NPPMAC_E2E=1

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NppE2EInstall();
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
