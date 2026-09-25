// Accessibility for what AppKit cannot describe by itself: the parts of the
// views that draw them (a tab of the tab bar and its close button, a dock's
// tabs), and the buttons whose face is a symbol rather than words. Windows
// Notepad++ gets this from Win32's own controls (a tab control exposes its
// items to UI Automation); the port's custom views say it here.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One part of a view that draws its parts itself: where it is in the view,
/// what it is, and what pressing it does.
@interface NppAXElement : NSAccessibilityElement
+ (instancetype)elementInView:(NSView *)view role:(NSAccessibilityRole)role label:(NSString *)label;
@property (nonatomic, weak, nullable) NSView *hostView;
/// In the host view's coordinates.
@property (nonatomic) NSRect rectInView;
@property (nonatomic, copy, nullable) void (^pressHandler)(void);
/// Its right-click menu, for VoiceOver's "show menu" (VO-Shift-M).
@property (nonatomic, copy, nullable) void (^showMenuHandler)(void);
@end

/// A button whose title is empty or a symbol (◀, ✕, an image) is read by
/// VoiceOver as that symbol or not at all: it is given its tooltip - the words
/// a sighted user gets on hovering - as its label, unless it has one. Goes
/// through the view and everything under it.
FOUNDATION_EXPORT void NppAXLabelSymbolButtons(NSView *root);

/// Win32 names a dialog's edit or combo box that has no name of its own after the static
/// text before it (oleacc's rule), which is how Notepad++'s dialogs read to a screen reader.
/// The port's windows are laid out rather than listed, so "before" is where the eye finds
/// it: the nearest label to the left on the control's row, else the one just above it. Each
/// field, pop-up, combo box, slider, stepper, colour well or text view (placed by its scroll view)
/// under the view without a label or a title element of its own is given that label as its
/// title element (a titled check box counts on the row: "☐ Transparency ——○——"); a field with
/// no label by it is named by its placeholder.
FOUNDATION_EXPORT void NppAXLinkLabels(NSView *root);

/// Both of the above, for what a window holds.
FOUNDATION_EXPORT void NppAXPrepareWindow(NSWindow *window);

NS_ASSUME_NONNULL_END
