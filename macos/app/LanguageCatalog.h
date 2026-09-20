// Loads Notepad++'s own language definitions (langs.model.xml) at runtime and
// resolves a file name to the Lexilla lexer and keyword sets Notepad++ uses.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppLanguage : NSObject
@property (nonatomic, copy) NSString *name;              // e.g. "cpp"
@property (nonatomic, copy) NSString *lexerID;           // Lexilla lexer, e.g. "cpp"
@property (nonatomic, copy) NSArray<NSString *> *extensions;
/// Scintilla keyword-set index -> space-separated words.
/// Index follows Notepad++'s LANG_INDEX_*: instre1=0, instre2=1, type1=2 ... type7=8.
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *keywordSets;
@property (nonatomic, copy, nullable) NSString *commentLine;
@property (nonatomic, copy, nullable) NSString *commentStart;
@property (nonatomic, copy, nullable) NSString *commentEnd;
/// A user-defined language, driven by the user lexer.
@property (nonatomic) BOOL userDefined;
/// A user language made for dark mode; among several claiming an
/// extension, the one matching the current mode is chosen, as on Windows.
@property (nonatomic) BOOL darkModeTheme;
@end

@interface LanguageCatalog : NSObject
/// Parses langs.model.xml from the app bundle. Never nil; empty if the file is missing.
/// The title upstream's Language menu gives a language ("C++", "None (Normal Text)").
+ (NSString *)menuTitleForLanguage:(NSString *)name;
+ (instancetype)sharedCatalog;
@property (nonatomic, readonly) NSArray<NppLanguage *> *allLanguages;
@property (nonatomic, readonly) NSString *sourcePath;
- (nullable NppLanguage *)languageNamed:(NSString *)name;
/// Matches on file extension; falls back to the "normal" language.
- (nullable NppLanguage *)languageForFileName:(NSString *)fileName;

/// Lists user-defined languages, replacing the ones listed before: their
/// names join the catalog and their extensions win over the built-in ones.
- (void)registerUserLanguages:(NSArray<NppLanguage *> *)languages;
/// The user languages listed, in the order they were read.
@property (nonatomic, readonly) NSArray<NppLanguage *> *userLanguages;
/// Whether dark mode is on, for choosing between a light and a dark user
/// language that claim the same extension. Set by whoever applies themes.
@property (nonatomic) BOOL darkMode;
@end

/// Notepad++'s keyword set for a keywordClass ("instre1" is 0, "type1" 2 ...).
FOUNDATION_EXPORT NSNumber *_Nullable NppKeywordSetIndex(NSString *attrName);

NS_ASSUME_NONNULL_END
