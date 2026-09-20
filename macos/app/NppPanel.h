// A panel that behaves the way a dialog on this platform is expected to:
// Escape puts it away.
//
// AppKit gives that to a sheet or an alert, but not to a panel a program makes
// for itself, and none of the panels here had it.
#import <Cocoa/Cocoa.h>

@interface NppPanel : NSPanel
@end
