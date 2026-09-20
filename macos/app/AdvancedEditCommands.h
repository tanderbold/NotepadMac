// The remaining Edit-menu commands: multi-selection, column editing, actions on
// the selection, paste special and auto-completion helpers.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_OPTIONS(NSInteger, NppMatchFlags) {
    NppMatchNone      = 0,
    NppMatchCase      = 1 << 0,
    NppMatchWholeWord = 1 << 1,
};

@interface EditorController (AdvancedEditCommands)

// Multi-selection
- (NSUInteger)multiSelectAllOccurrences:(NppMatchFlags)flags;
- (BOOL)multiSelectNextOccurrence:(NppMatchFlags)flags;
- (BOOL)undoLastMultiSelection;
- (BOOL)skipCurrentMultiSelection;
- (NSUInteger)selectionCount;

// Begin/End select (sticky anchor)
- (BOOL)beginEndSelectColumnMode:(BOOL)columnMode;
- (BOOL)beginEndSelectActive;

// Column editor
- (BOOL)columnInsertText:(NSString *)text;
- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment
                    zeroPadded:(BOOL)padded base:(int)base;
/// The same, each number repeated `repeat` times before the next.
- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment repeat:(long)repeat
                    zeroPadded:(BOOL)padded base:(int)base;

// On selection
- (nullable NSString *)selectionAsPath;
- (BOOL)openSelectedFile;
- (BOOL)revealSelectedFile;
- (BOOL)redactSelectionWithBlock:(BOOL)solidBlock;
- (BOOL)searchSelectionOnInternet;
@property (nonatomic, copy) NSString *searchEngineTemplate;   // %@ is the query

// Paste special
- (BOOL)pasteAsHTML;
- (BOOL)pasteAsRTF;
- (BOOL)copySelectionAsBinary;
- (BOOL)cutSelectionAsBinary;
- (BOOL)pasteBinary;

// Auto-completion helpers
- (BOOL)showPathCompletion;
/// What the call tip would show, one entry per overload; exposed so a test can
/// check the text rather than only that a tip appeared.
- (NSArray<NSString *> *)callTipCandidates;
- (BOOL)showFunctionCallTip;
- (BOOL)cycleFunctionCallTip:(BOOL)forward;
/// FunctionCallTip::updateCalltip: after `ch` is typed (0 when asked for),
/// shows or refreshes the shipped signature of the function the caret is in,
/// with the current parameter highlighted; closes it when there is none.
- (BOOL)updateCallTipForCharacter:(int)ch force:(BOOL)needShown;
- (BOOL)apiCallTipVisible;
/// name, param (index), overload (index) of the tip shown; for the tests.
- (nullable NSDictionary *)apiCallTipState;
/// SCN_CALLTIPCLICK: the arrows step between overloads.
- (void)callTipClicked:(long)position;

// File attribute
- (BOOL)systemReadOnly;
- (BOOL)toggleSystemReadOnly;

@end

NS_ASSUME_NONNULL_END
