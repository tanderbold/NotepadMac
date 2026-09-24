// Search-menu commands: token styling with five marker styles, bookmark line
// operations, brace matching, Find in Files and incremental search.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// Notepad++ offers five "style all occurrences" colours; these map onto
/// Scintilla indicators 8..12, which sit above the range lexers use.
#define NPPMAC_STYLE_COUNT 5
#define NPPMAC_STYLE_FIRST_INDICATOR 8
/// Indicator 13 backs "Find Mark Style", the one Find's Mark All writes.
#define NPPMAC_FIND_MARK_INDICATOR 13
/// Smart highlighting has an indicator of its own, as upstream's
/// SCE_UNIVERSAL_FOUND_STYLE_SMART is apart from the five mark styles: on 12 it
/// cleared mark style 5 at every selection change (SEARCH-109..122). Its style
/// number for the calls below is NPPMAC_SMART_STYLE.
#define NPPMAC_SMART_INDICATOR 19
#define NPPMAC_SMART_STYLE 100

@interface EditorController (SearchCommands)

// Token styling. style is 0..4, or NPPMAC_STYLE_COUNT for the Find Mark style.
- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style;
/// The same, with the matching rules given rather than taken from the Mark All
/// settings; smart highlighting has settings of its own.
- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style
                                  matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord;
- (void)markOneOccurrenceOfSelection:(NSInteger)style;
- (void)clearStyle:(NSInteger)style;
- (void)clearAllStyles;
- (BOOL)jumpToMarker:(NSInteger)style forward:(BOOL)forward;
- (NSString *)textOfStyle:(NSInteger)style;
- (NSString *)textOfAllStyles;

// Bookmark line operations
- (NSString *)bookmarkedLinesText;
- (void)cutBookmarkedLines;
- (void)copyBookmarkedLines;
- (void)pasteOverBookmarkedLines;
- (void)removeBookmarkedLines;
- (void)removeUnbookmarkedLines;
- (void)inverseBookmarks;

// Braces
- (BOOL)goToMatchingBrace;
- (BOOL)selectBetweenMatchingBraces;

// Find in Files
- (NSUInteger)findInFiles:(NSString *)term
                inFolder:(NSString *)folder
                  filter:(nullable NSString *)filter;
/// Puts a report into the "Search results" tab, which is where every kind of
/// find-all here leaves its output.
- (void)showSearchResults:(NSString *)report;
/// Replaces what the results tab holds while a search is still running, so hits
/// appear as they are found. Does nothing when that tab is not the one on screen.
- (void)updateSearchResults:(NSString *)report;
/// What a heading line of a search report names: a file path, or the title of
/// the document that was searched. Nil when the line is not a heading.
+ (nullable NSString *)searchResultTargetInHeading:(NSString *)head;
/// The line number a hit line carries, or 0 when it is not a hit line.
+ (NSInteger)searchResultLineInHitLine:(NSString *)text;
/// What a results line points at: a file path, or the title of an open document
/// when the search was of the document itself. `line` is one-based.
+ (nullable NSString *)searchResultTargetInReport:(NSString *)report
                                           atLine:(NSInteger)line
                                         fileLine:(nullable NSInteger *)fileLine;
/// The file and line a results line refers to, or nil when it refers to none.
/// `line` is one-based, as the report writes it.
+ (nullable NSString *)searchResultFileInReport:(NSString *)report
                                         atLine:(NSInteger)line
                                       fileLine:(nullable NSInteger *)fileLine;
/// The text of one line, as Scintilla counts lines.
- (NSString *)textOfLine:(NSInteger)line;
/// Puts the caret on a line of the current document and selects that line.
- (void)selectLine:(NSInteger)line;
/// Opens what the caret sits on in the results tab. This is what a double click
/// there does, the way Notepad++ jumps from a result to the file.
- (BOOL)openSearchResultAtCaret;

// The results tab, as Notepad++'s Search results panel: searches stack up,
// newest first and the older ones folded, and its context menu has these.
- (BOOL)showingSearchResults;
- (void)foldSearchResults;
- (void)foldAllSearchResults:(BOOL)fold;
- (NSString *)selectedSearchResultText;
- (NSArray<NSString *> *)selectedSearchResultPaths;
- (void)copySearchResultLines;
- (void)copySearchResultPaths;
- (void)openSearchResultPaths;
- (void)clearSearchResults;
- (void)deleteSearchResultAtCaret;
- (BOOL)focusSearchResults;
- (BOOL)goToSearchResult:(BOOL)forward;

// Incremental / volatile search helpers
- (BOOL)findNextOccurrenceOfSelection:(BOOL)forward extendSelection:(BOOL)extend;
- (NSUInteger)markCharactersInRangeFrom:(uint32_t)from to:(uint32_t)to;

// Change history
- (void)enableChangeHistory:(BOOL)on;
- (BOOL)goToNextChange:(BOOL)forward;
- (void)clearChangeHistory;

@end

NS_ASSUME_NONNULL_END
