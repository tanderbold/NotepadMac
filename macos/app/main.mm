#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

void NppE2EInstall(void);   // E2EHooks.mm: nothing unless NPPMAC_E2E=1

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NppE2EInstall();
        // The command line is read by -[AppDelegate parseCommandLine:] with Notepad++'s meaning
        // (-z skips the next word, -notepadStyleCmdline takes the rest as one name, -openSession
        // takes a session file...). Without this AppKit also hands every word that does not start
        // with "-" to application:openFile: - in its own order, and whether it is a file or not.
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"NSTreatUnknownArgumentsAsOpen": @"NO"}];
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
