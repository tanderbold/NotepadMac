// How the editor draws what Preferences > Editing and Margins control, as
// ScintillaEditView does it: font quality, selected text colour, EOL and
// non-printing character representations, the fold margin's style and
// colours, the line number margin's width and Change History.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (Look)
/// Everything below, on the editor and the second view.
- (void)applyLook;
/// setCRLF, showNpc and showCcUniEol together: the representations for line
/// ends, invisible Unicode characters and C0/C1 controls.
- (void)applySymbolRepresentationsTo:(id)sci;
/// The fold markers in the style chosen, in the theme's Fold colours.
- (void)applyFoldMarkersTo:(id)sci;
/// Wide enough for the biggest line number shown (dynamic) or in the file.
- (void)updateLineNumberWidth;
@end

NS_ASSUME_NONNULL_END
