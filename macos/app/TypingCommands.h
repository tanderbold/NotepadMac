// Preferences > Auto-Completion, New document, Tab bar, Recent files,
// Default directory, Searching and Highlighting: the behaviour behind them.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppCompletionSource) {
    NppCompletionFunctions = 0,
    NppCompletionWords,
    NppCompletionBoth,
};

typedef NS_ENUM(NSInteger, NppCompletionKind) {
    NppCompletionKindFunctions = 0,       // the language's whole list (Function Completion)
    NppCompletionKindFunctionsBrief,      // only the names that fit what is typed
    NppCompletionKindWords,               // words of the document (Word Completion)
    NppCompletionKindFunctionsAndWords,
};

@interface EditorController (TypingCommands)

/// Opens the completion list, as AutoCompletion::showAutoComplete. With
/// autoInsert, Word Completion types a lone candidate instead. NO when there
/// is nothing to offer.
- (BOOL)showCompletion:(NppCompletionKind)kind autoInsert:(BOOL)autoInsert;
/// Whether completion ignores case here: the API file says, and plain text does not.
- (BOOL)completionIgnoresCase;
/// What the last list offered; for the tests.
- (nullable NSArray<NSString *> *)lastCompletionList;

/// Called for every character typed; drives completion and auto-insertion.
- (void)handleCharacterAdded:(int)character;

/// Drops the record of the closer put in last; on a tab switch, so that it
/// is never judged against another document.
- (void)forgetAutoCloser;
/// Carries the previous line's indentation onto a new one, and in the languages
/// that use braces opens a level after one. Called when a newline is typed.
- (void)maintainIndentationAfter:(int)character;

/// Candidates the current settings would offer for `prefix`.
- (NSArray<NSString *> *)completionCandidatesForPrefix:(NSString *)prefix;
/// The closing text that should follow `character`, or nil.
- (nullable NSString *)autoInsertionForCharacter:(int)character;
/// The close tag for the element just finished at the caret, or nil.
- (nullable NSString *)closeTagAtCaret;

// New documents
- (void)applyNewDocumentDefaults;
/// The name an untitled tab should take, which may come from its first line.
- (NSString *)untitledNameForDocument:(NppDocument *)doc;

// Recent files
- (void)noteRecentFile:(NSString *)path;
- (NSArray<NSString *> *)recentFiles;
/// Takes a file off the list: it is open now, and the list is of what was closed.
- (void)forgetRecentFile:(NSString *)path;
- (NSString *)displayNameForRecentFile:(NSString *)path;
- (void)clearRecentFiles;

// Default directory
- (NSString *)defaultOpenDirectory;
- (void)rememberOpenDirectory:(NSString *)path;

// Searching and highlighting helpers
/// What the Find field should be pre-filled with, per the settings.
- (NSString *)initialFindTerm;

@end

NS_ASSUME_NONNULL_END
