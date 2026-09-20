// File comparison, in the shape ComparePlus offers it: set one file aside,
// compare it with another, mark the differences and step through them.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// Markers for compared lines; above the fold markers and the bookmark.
#define NPPMAC_MARKER_ADDED   2
#define NPPMAC_MARKER_REMOVED 3
#define NPPMAC_MARKER_CHANGED 4
#define NPPMAC_MARKER_MOVED   5

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
- (void)clearAllCompares;
- (BOOL)compareActive;

/// Differences found by the last comparison, in document order.
- (NSArray<NppDiffLine *> *)currentDiff;
- (NSString *)compareSummary;
- (BOOL)goToDiff:(NSInteger)direction;   // +1 next, -1 previous
- (BOOL)goToFirstDiff;
- (BOOL)goToLastDiff;

// Options
@property (nonatomic) BOOL compareIgnoreCase;
@property (nonatomic) BOOL compareIgnoreSpaces;
@property (nonatomic) BOOL compareIgnoreEmptyLines;

@end

NS_ASSUME_NONNULL_END
