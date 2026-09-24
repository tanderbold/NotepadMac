// The tab bar. Replaces the segmented control with something that can carry a
// close button and a pin marker per tab, be dragged to reorder, and lay itself
// out horizontally, over several rows, or down the side.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class NppTabBarView;

@protocol NppTabBarDelegate <NSObject>
- (void)tabBar:(NppTabBarView *)bar didSelectIndex:(NSInteger)index;
- (void)tabBar:(NppTabBarView *)bar didRequestCloseIndex:(NSInteger)index;
- (void)tabBar:(NppTabBarView *)bar didMoveIndex:(NSInteger)from toIndex:(NSInteger)to;
@optional
/// The right-click menu of a tab, which is brought to the front first.
- (nullable NSMenu *)tabBar:(NppTabBarView *)bar menuForIndex:(NSInteger)index;
/// The pointer came onto a tab, or (-1) left the bar: the Document Peeker's cue.
- (void)tabBar:(NppTabBarView *)bar hoveredIndex:(NSInteger)index;
@end

/// What the bar needs to know about one tab.
@interface NppTabItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL modified;
@property (nonatomic) BOOL pinned;
@property (nonatomic) NSInteger colour;     // 0 none, 1..5
@end

@interface NppTabBarView : NSView
@property (nonatomic, weak) id<NppTabBarDelegate> tabDelegate;
@property (nonatomic, copy) NSArray<NppTabItem *> *items;
@property (nonatomic) NSInteger selectedIndex;

/// Layout and behaviour, driven by Preferences.
@property (nonatomic) BOOL vertical;
@property (nonatomic) BOOL multiLine;
@property (nonatomic) BOOL showCloseButtons;
@property (nonatomic) BOOL closeButtonsOnInactiveTabs;
@property (nonatomic) BOOL doubleClickCloses;
@property (nonatomic) BOOL locked;          // no drag and drop
/// Tab Bar page: a coloured bar on the active tab, inactive tabs in their own
/// colours, reduced size, and a limit on the label (0 for none).
@property (nonatomic) BOOL drawActiveBar;
@property (nonatomic) BOOL colourInactiveTabs;
@property (nonatomic) BOOL reduced;
@property (nonatomic) NSInteger maxLabelLength;
/// From the theme: Active tab focused / unfocused indicator, Active tab text, Inactive tabs.
@property (nonatomic, strong, nullable) NSColor *activeBarColour, *activeBarUnfocusedColour, *activeTextColour;
@property (nonatomic, strong, nullable) NSColor *inactiveTextColour, *inactiveBackColour;
/// The bar of the view with the focus (NPPM_INTERNAL_ISFOCUSEDTAB): its active tab's bar is in the
/// focused colour, the other view's in the unfocused one. YES unless told otherwise.
@property (nonatomic) BOOL inFocusedView;
/// The label a tab shows, shortened to the limit.
- (NSString *)displayTitleAtIndex:(NSInteger)index;

/// The height (or width, when vertical) the bar needs for its current layout.
- (CGFloat)requiredThickness;
/// Frame of a tab, for tests and for hit testing.
- (NSRect)frameOfTabAtIndex:(NSInteger)index;
- (NSInteger)indexOfTabAtPoint:(NSPoint)point;
- (BOOL)point:(NSPoint)point isOnCloseButtonOfIndex:(NSInteger)index;
@end

NS_ASSUME_NONNULL_END
