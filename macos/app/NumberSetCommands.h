// The editor's context menu for selected numbers: for a set of them
// (NumberSet.h) a "Selected Numbers" submenu: Sum, Average, Minimum, Maximum
// and Count write "SUM = 134"... after the numbers, and the numbers sort
// either way in place; for a formula that ends with "=" (Formula.h) "Calculate",
// which writes the value after the "=".
#import "EditorController.h"
#import "NumberSet.h"
#import "Formula.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppNumberSetValue) {
    NppNumberSetSum, NppNumberSetAverage, NppNumberSetMinimum, NppNumberSetMaximum, NppNumberSetCount,
};

@interface EditorController (NumberSetCommands)

/// The numbers the selection holds (every piece of a column or multiple
/// selection); nil when it holds anything else or fewer than two.
- (nullable NppNumberSet *)numberSetInSelection;

/// The submenu item and a separator for the context menu's top; empty when
/// the selection is not a set of numbers.
- (NSArray<NSMenuItem *> *)numberSetMenuItems;

/// The formula the selection holds (one piece only); nil otherwise.
- (nullable NppFormula *)formulaInSelection;

/// "Calculate" and a separator for the context menu's top; Calculate is
/// enabled only when the selection is a formula.
- (NSArray<NSMenuItem *> *)formulaMenuItems;

/// Writes the value after the "=", replacing an old one, as one undo step;
/// the formula and its value stay selected. NO when there is nothing to write
/// or the document is read-only.
- (BOOL)calculateSelectedFormula;

/// The same for the formula that ends at the caret on its line, without a
/// selection: "total: 2 + 3 =|" becomes "total: 2 + 3 = 5|"; with no "="
/// typed, "2+3|" becomes "2+3=5|". The caret ends after the value.
- (BOOL)calculateFormulaAtCaret;

/// Edit > Calculate (Cmd+=) and the context menu's Calculate: the selected
/// formula, or the one at the caret; a beep, and the reason in the status
/// bar, when there is none or it has no value.
- (void)calculateFormula;

/// Writes "SUM = 134" (AVG, MIN, MAX, COUNT) after the selected numbers: on
/// their line when they are on one, else on a line of its own under them.
/// One undo step; the caret ends after it. NO when there is no set of
/// numbers or the document is read-only.
- (BOOL)insertNumberSetValue:(NppNumberSetValue)which;

/// Sorts the selected numbers in place, as one undo step, and keeps them
/// selected. NO when there is no set of numbers or the document is read-only.
- (BOOL)sortSelectedNumbersAscending:(BOOL)ascending;

@end

NS_ASSUME_NONNULL_END
