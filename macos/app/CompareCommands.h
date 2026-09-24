// File comparison, in the shape ComparePlus offers it: set one file aside,
// compare it with another, mark the differences and step through them.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// The markers of compared lines are the ComparePlus engine's (macos/third_party/compareplus,
/// shim/NppHelpers.h): whole-line backgrounds on these numbers, with symbols in the margin.
#define NPPMAC_MARKER_CHANGED 0
#define NPPMAC_MARKER_ADDED   2
#define NPPMAC_MARKER_REMOVED 3
#define NPPMAC_MARKER_MOVED   4
/// The revert arrow beside a differing line, the port's own, in the engine's margin (5).
#define NPPMAC_MARKER_REVERT  9
#define NPPMAC_COMPARE_MARGIN 5
typedef NS_ENUM(NSInteger, NppDiffKind) {
    NppDiffSame = 0,
    NppDiffAdded,       // only in the new file
    NppDiffRemoved,     // only in the old file
    NppDiffChanged,     // a removal and an addition on the same run
};

/// One line's verdict.
@interface NppDiffLine : NSObject
@property (nonatomic) NppDiffKind kind;
@property (nonatomic) NSInteger oldLine;   // -1 when the line is not in the old file
@property (nonatomic) NSInteger newLine;   // -1 when the line is not in the new file
@end

@interface EditorController (CompareCommands)

/// The line-by-line difference, using Myers' algorithm as ComparePlus does.
/// The lines of a text as Compare sees them: split on CRLF, LF and CR alike.
+ (NSArray<NSString *> *)linesForComparison:(NSString *)text;

+ (NSArray<NppDiffLine *> *)diffBetween:(NSArray<NSString *> *)oldLines
                                    and:(NSArray<NSString *> *)newLines
                         ignoreCase:(BOOL)ignoreCase
                       ignoreSpaces:(BOOL)ignoreSpaces
                   ignoreEmptyLines:(BOOL)ignoreEmptyLines;

// The commands
- (void)setFirstToCompare;
- (nullable NSString *)firstToCompare;
- (BOOL)compareWithFirst;
- (BOOL)compareWithFileAtPath:(NSString *)path;
- (void)clearActiveCompare;
/// The editor is closing this document: a comparison it is in ends.
- (void)compareDocumentWillClose:(NppDocument *)doc;
- (void)clearAllCompares;
- (BOOL)compareActive;

/// Differences found by the last comparison, in document order.
- (NSArray<NppDiffLine *> *)currentDiff;
- (NSString *)compareSummary;
- (BOOL)goToDiff:(NSInteger)direction;   // +1 next, -1 previous
- (BOOL)goToFirstDiff;
- (BOOL)goToLastDiff;
/// The differing run a line belongs to - changed or added lines, or the place lines were taken
/// out - replaced by what the other side has there, as one undo step; then the comparison is
/// worked out again. What the arrow in the margin does. NO when the line is on no difference.
- (BOOL)compareRevertChangeAtLine:(long)line;
/// The comparison worked out again over what the document is now - typing while it is on
/// changes what differs - at once, or a moment after typing stops.
- (void)compareRefreshNow;
- (void)compareScheduleRefresh;
/// The bar above the other pane: the summary, Previous / Next, and the way out.
@property (nonatomic, readonly, nullable) NSView *compareBar;

/// The document in front against a text, as the menu commands do it with a file.
- (BOOL)compareCurrentWithText:(NSString *)text;
// Options, as the plugin's Compare Options dialog has them.
@property (nonatomic) BOOL compareIgnoreCase;
@property (nonatomic) BOOL compareIgnoreSpaces;
@property (nonatomic) BOOL compareIgnoreEmptyLines;
@property (nonatomic) BOOL compareDetectMoves;
@property (nonatomic) BOOL compareCharDiffs;

@end

NS_ASSUME_NONNULL_END
