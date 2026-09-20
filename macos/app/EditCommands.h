// Edit-menu commands: case conversion, line operations, blank operations,
// indentation, clipboard copies, insertion and read-only state.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppCaseMode) {
    NppCaseUpper, NppCaseLower,
    NppCaseProperForce, NppCaseProperBlend,
    NppCaseSentenceForce, NppCaseSentenceBlend,
    NppCaseInvert, NppCaseRandom,
};

typedef NS_ENUM(NSInteger, NppSortKey) {
    NppSortLexicographic, NppSortLexicographicCaseInsensitive, NppSortLocale,
    NppSortInteger, NppSortDecimalComma, NppSortDecimalDot, NppSortLength,
    NppSortReverseOrder, NppSortRandom,
};

typedef NS_ENUM(NSInteger, NppTrimMode) {
    NppTrimTrailing, NppTrimLeading, NppTrimBoth,
    NppTrimEOLToSpace, NppTrimAll,
    NppTabToSpace, NppSpaceToTabAll, NppSpaceToTabLeading,
};

@interface EditorController (EditCommands)

/// Rewrites the selected characters, or the whole document when nothing is
/// selected. Shared by the case, XML-escaping and similar commands.
- (void)transformSelectedText:(NSString *(^)(NSString *selected))transform;

- (void)convertCase:(NppCaseMode)mode;
/// Sorts, returning the index of the line that stopped a decimal sort, or
/// NSNotFound when it went through. Notepad++ refuses a numeric sort that meets
/// a line it cannot read, and says which line it was.
- (NSInteger)sortLines:(NppSortKey)key descending:(BOOL)descending;
- (void)removeDuplicateLines:(BOOL)consecutiveOnly;
- (void)splitLines;
- (void)joinLines;
- (void)moveLine:(BOOL)up;
- (void)removeEmptyLines:(BOOL)alsoBlankOnly;
- (void)insertBlankLine:(BOOL)above;
- (void)applyTrim:(NppTrimMode)mode;
- (void)changeIndent:(BOOL)increase;
- (void)deleteSelection;

- (void)copyToClipboard:(NSString *)string;
- (NSString *)allDocumentNames;
- (NSString *)allDocumentPaths;
- (void)insertDateTimeShort:(BOOL)shortForm;
- (void)insertCustomDateTime:(NSString *)format;

- (void)uncommentLines;                       // IDM_EDIT_BLOCK_UNCOMMENT
- (void)streamComment:(BOOL)comment;          // IDM_EDIT_STREAM_COMMENT / _UNCOMMENT

- (void)setReadOnly:(BOOL)readOnly;
- (void)setReadOnlyForAllDocuments:(BOOL)readOnly;
- (BOOL)isReadOnly;

@end

NS_ASSUME_NONNULL_END
