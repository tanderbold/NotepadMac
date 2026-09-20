// Docking, as Notepad++'s DockingManager: panels live in four containers
// around the editor - left, right, top and bottom - as tabs, or float in
// windows of their own. A panel's tab is dragged to an edge of the window to
// dock it there, or anywhere else to float it; its right-click menu does the
// same. Where each panel lives and how big the containers are is kept.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppDockPlace) {
    NppDockLeft = 0,
    NppDockRight,
    NppDockTop,
    NppDockBottom,
    NppDockFloating,
};

/// Posted with the panel's identifier as object when it is shown or hidden.
FOUNDATION_EXPORT NSNotificationName const NppDockPanelVisibilityDidChangeNotification;

@interface NppDockingManager : NSObject
+ (instancetype)shared;

/// The editor's side-by-side split and the view the docks go around; set by
/// the editor when it builds its window.
- (void)attachToSplit:(NSSplitView *)split center:(NSView *)center;

/// A panel, with the place it goes the first time (a remembered place wins).
- (void)registerPanel:(NSString *)identifier title:(NSString *)title view:(NSView *)view
         defaultPlace:(NppDockPlace)place;
- (BOOL)hasPanel:(NSString *)identifier;
- (void)showPanel:(NSString *)identifier;
- (void)hidePanel:(NSString *)identifier;
- (void)togglePanel:(NSString *)identifier;
/// Shown: docked or floating, whether or not it is the tab in front.
- (BOOL)isPanelVisible:(NSString *)identifier;
- (NppDockPlace)placeOfPanel:(NSString *)identifier;
/// Docks or floats a panel; a hidden one is shown there.
- (void)movePanel:(NSString *)identifier to:(NppDockPlace)place;
/// The shown panels in a container, in tab order, and the one in front.
- (NSArray<NSString *> *)panelsIn:(NppDockPlace)place;
- (nullable NSString *)frontPanelIn:(NppDockPlace)place;
/// After the panels of the last launch are shown again: the tab that was in
/// front of each container is put in front.
/// Floating together: `identifier` becomes a tab of the window `other` floats in.
- (void)floatPanel:(NSString *)identifier withPanel:(NSString *)other;
/// The panels sharing a floating window with this one (itself included), in tab order.
- (NSArray<NSString *> *)panelsFloatingWith:(NSString *)identifier;
- (void)restoreFronts;
/// A tab let go at a point of the screen: docked at an edge, joined to the floating window there, or floated.
- (void)dragOfPanel:(NSString *)identifier endedAtScreenPoint:(NSPoint)point;
/// Where a panel let go at a point of the screen would go, in screen
/// coordinates: what the drag shows before the button is released.
- (NSRect)previewRectForPanel:(NSString *)identifier atScreenPoint:(NSPoint)point;
/// Where a drop at a point on screen docks a panel: an edge of the main
/// window, or floating anywhere else.
- (NppDockPlace)placeForDropAtScreenPoint:(NSPoint)point;
/// Width of the left / right containers and height of the top / bottom ones.
- (CGFloat)sizeOfPlace:(NppDockPlace)place;
@end

NS_ASSUME_NONNULL_END
