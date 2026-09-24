// The behaviour behind Preferences > Performance, Cloud (clickable links),
// Delimiter and Multi-instance.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// Indicator used to underline clickable links; above the marker styles.
#define NPPMAC_LINK_INDICATOR 14

@interface EditorController (BehaviourCommands)

/// A right (or control-) click at a point of a window: in an editor's text,
/// outside its selection, it puts the caret there, as Scintilla does on Windows
/// before the context menu - unless "Keep selection when right-click outside of
/// selection" is ticked (ScintillaEditView's WM_RBUTTONDOWN). The editor's event
/// monitor calls it for real clicks; the e2e hook for the clicks it makes.
- (void)contextClickAtWindowPoint:(NSPoint)point window:(NSWindow *)window;
/// Installs the monitor above; once, from the editor's set-up.
- (void)installContextClickMonitor;

// Large file restriction
/// YES when the current document is over the configured size and the
/// restrictions apply to it.
- (BOOL)largeFileRestrictionActive;
/// Re-evaluates the restriction for the current document and applies it.
- (void)applyPerformanceRestrictions;

// Clickable links
- (NSUInteger)markClickableLinks;
- (nullable NSString *)linkAtPosition:(long)position;
- (BOOL)openLinkAtPosition:(long)position;

// Brace match and smart highlighting, both driven from caret movement
- (void)updateBraceMatch;
- (NSUInteger)updateSmartHighlight;

// Word characters and delimiter selection
- (void)applyWordCharacters;
/// Selects between the configured delimiters around `position`.
- (BOOL)selectBetweenDelimitersAt:(long)position;

// Multi-instance
/// Whether a file opened from the Finder should start another instance.
- (BOOL)shouldOpenFilesInNewInstance;
- (void)rememberPanelState;
- (void)restorePanelState;

/// Highlight another view: the selected word marked in the second view.
- (NSUInteger)smartHighlightOtherViewMatchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;
@end

NS_ASSUME_NONNULL_END
