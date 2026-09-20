// The toolbar. Notepad++ has a configurable button bar; the macOS counterpart
// is an NSToolbar whose items drive the same menu actions.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppToolbar : NSObject <NSToolbarDelegate>

/// `target` receives the item actions, which are the menu selectors.
- (instancetype)initWithWindow:(NSWindow *)window target:(id)target;

@property (nonatomic) BOOL visible;
/// 0 = icon only, 1 = icon and label, 2 = label only.
@property (nonatomic) NSInteger displayMode;
/// 0 = regular, 1 = small. macOS only honours labels in the regular size, so
/// asking for labels puts the window in the regular style regardless.
@property (nonatomic) NSInteger iconSize;
/// What AppKit is actually showing, which can differ from the request above.
@property (nonatomic, readonly) NSToolbarDisplayMode effectiveDisplayMode;

/// Marks a button as active. The record button is tinted red while a macro is
/// being recorded, which is the only sign the editor gives that it is.
/// Draws the icons again, after the icon set or colour changed.
- (void)reloadIcons;
- (void)setActive:(BOOL)active forCommand:(NSString *)command;
- (BOOL)isActiveForCommand:(NSString *)command;
/// What the button is actually showing, so a test can look at the picture rather
/// than at the flag behind it.
- (nullable NSBitmapImageRep *)renderedImageForCommand:(NSString *)command;

/// Identifiers of the buttons currently on the bar; used by tests.
- (NSArray<NSString *> *)itemIdentifiers;
/// The selector a given button triggers, or NULL.
- (SEL)actionForIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
