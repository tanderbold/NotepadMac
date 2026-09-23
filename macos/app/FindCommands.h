// Find and Replace as Notepad++ has them: three search modes, the options that
// go with them, and replacement that understands back-references. What was here
// before searched for a literal string and nothing else.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppSearchMode) {
    NppSearchNormal = 0,    ///< the text as typed
    NppSearchExtended,      ///< \n, \t, \xHH and the rest
    NppSearchRegex,         ///< a regular expression
};

typedef NS_OPTIONS(NSInteger, NppFindOptions) {
    NppFindNone        = 0,
    NppFindMatchCase   = 1 << 0,
    NppFindWholeWord   = 1 << 1,
    NppFindWrap        = 1 << 2,
    NppFindBackward    = 1 << 3,
    NppFindInSelection = 1 << 4,
    NppFindDotMatchesNewline = 1 << 5,   ///< regular expressions only: '.' may match a line ending
};

/// What to look for, and what to put in its place.
@interface NppFindSpec : NSObject
@property (nonatomic, copy) NSString *what;
@property (nonatomic, copy, nullable) NSString *replacement;
@property (nonatomic) NppSearchMode mode;
@property (nonatomic) NppFindOptions options;
+ (instancetype)specFor:(NSString *)what mode:(NppSearchMode)mode options:(NppFindOptions)options;
@end

/// A search that is running. Holding one lets the caller stop it.
@interface NppFileSearch : NSObject
@property (atomic, readonly) BOOL cancelled;
- (void)cancel;
@end

@interface EditorController (FindCommands)

/// The escapes Extended mode understands: \r \n \0 \t \\, and \b \o \d \x \u
/// with their fixed digit counts. Anything else keeps its backslash, exactly as
/// upstream leaves it.
+ (NSString *)convertExtendedToString:(NSString *)query;

/// Finds and selects the next match, returning whether there was one.
/// NO for a regular expression the engine refuses (a lone "(", "a{2,1}"): the
/// dialog then says so rather than "not found" (find-status-invalid-re).
- (BOOL)patternIsValid:(NppFindSpec *)spec;
- (BOOL)findNext:(NppFindSpec *)spec;
/// How many matches the document holds.
- (NSUInteger)countMatches:(NppFindSpec *)spec;
/// Replaces every match, returning how many.
- (NSUInteger)replaceAll:(NppFindSpec *)spec;
/// Replaces the selection when it is already a match, then finds the next one.
- (BOOL)replaceCurrentThenFindNext:(NppFindSpec *)spec;
/// Marks every match with the Find mark style, returning how many.
- (NSUInteger)markAll:(NppFindSpec *)spec;
/// The same, keeping the marks already there unless `purge`.
- (NSUInteger)markAll:(NppFindSpec *)spec purge:(BOOL)purge;
/// Searching a folder, which is what the Find in Files tab does. The filter is
/// what Notepad++ takes there: patterns such as "*.cpp *.h", empty for all.
- (NSUInteger)findInFiles:(NppFindSpec *)spec
                   folder:(NSString *)folder
                  filters:(nullable NSString *)filters
                recursive:(BOOL)recursive
            includeHidden:(BOOL)includeHidden
                   report:(NSString *_Nullable *_Nullable)report;

/// The same walk, replacing as it goes. Returns how many files were changed.
- (NSUInteger)replaceInFiles:(NppFindSpec *)spec
                      folder:(NSString *)folder
                     filters:(nullable NSString *)filters
                   recursive:(BOOL)recursive
               includeHidden:(BOOL)includeHidden
                 changedFiles:(NSUInteger *_Nullable)changedFiles;

/// The same search, off the main thread, so the window keeps answering while it
/// runs. `progress` and `completion` are called on the main thread; `progress`
/// carries what has been found so far, and the report grows as it goes.
/// The same over a list of files - the files of the projects - rather than a folder.
- (NppFileSearch *)findInFilesInBackground:(NppFindSpec *)spec
                                     paths:(NSArray<NSString *> *)paths
                                     title:(NSString *)title
                                   filters:(nullable NSString *)filters
                                  progress:(nullable void (^)(NSUInteger scanned, NSUInteger found, NSString *soFar))progress
                                completion:(nullable void (^)(NSUInteger found, NSString *report, BOOL stopped))completion;

- (NppFileSearch *)findInFilesInBackground:(NppFindSpec *)spec
                                    folder:(NSString *)folder
                                   filters:(nullable NSString *)filters
                                 recursive:(BOOL)recursive
                             includeHidden:(BOOL)includeHidden
                                  progress:(nullable void (^)(NSUInteger scanned, NSUInteger hits,
                                                              NSString *reportSoFar))progress
                                completion:(nullable void (^)(NSUInteger hits, NSString *report,
                                                              BOOL cancelled))completion;

/// Replacing across files, off the main thread, and stoppable the same way.
- (NppFileSearch *)replaceInFilesInBackground:(NppFindSpec *)spec
                                       folder:(NSString *)folder
                                      filters:(nullable NSString *)filters
                                    recursive:(BOOL)recursive
                                includeHidden:(BOOL)includeHidden
                                     progress:(nullable void (^)(NSUInteger scanned, NSUInteger replaced))progress
                                   completion:(nullable void (^)(NSUInteger replaced, NSUInteger files,
                                                                 BOOL cancelled))completion;

/// Replace in Projects: the same over a list of files.
- (NppFileSearch *)replaceInFilesInBackground:(NppFindSpec *)spec
                                        paths:(NSArray<NSString *> *)paths
                                      filters:(nullable NSString *)filters
                                     progress:(nullable void (^)(NSUInteger scanned, NSUInteger replaced))progress
                                   completion:(nullable void (^)(NSUInteger replaced, NSUInteger files,
                                                                 BOOL cancelled))completion;

/// Find All in Current Document, as the report the results tab shows.
- (NSString *)findAllReport:(NppFindSpec *)spec hits:(NSUInteger *_Nullable)hits;
/// Find All in All Opened Documents: a heading per document with hits.
- (NSString *)findAllInOpenDocuments:(NppFindSpec *)spec hits:(NSUInteger *_Nullable)hits;
/// Replace All in All Opened Documents; how many were replaced.
- (NSUInteger)replaceAllInOpenDocuments:(NppFindSpec *)spec;
/// The replacement text for one match; for the tests.
- (NSString *)replacementFor:(NppFindSpec *)spec
                      groups:(NSArray<NSValue *> *)groups
                        data:(NSData *)data;

/// The lines of a file, counted as the editor counts them: CRLF, CR and LF all
/// end a line. Splitting on LF alone numbers the lines of a file with CR or
/// mixed endings differently from the document the result leads to, and a
/// result is then off by however many carriage returns came before it.
+ (NSArray<NSString *> *)linesOfText:(NSString *)text;

/// One line of a file as a search report shows it: without carriage returns, so
/// that a hit takes exactly one line whatever the file's line endings are.
+ (NSString *)singleReportLine:(NSString *)text;

/// Whether a file name is one the filter asks for.
+ (BOOL)name:(NSString *)name matchesFilters:(nullable NSString *)filters;

/// Whether a folder on the way to the file is one the filter says to stay
/// out of: "!\\build" in the filter keeps every build folder out.
+ (BOOL)relativePath:(NSString *)relative isInFolderExcludedByFilters:(nullable NSString *)filters;

/// Byte ranges of every match; the others are built on this.
- (NSArray<NSValue *> *)rangesOfMatches:(NppFindSpec *)spec;

@end

NS_ASSUME_NONNULL_END
