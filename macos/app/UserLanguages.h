// User Defined Languages, read from userDefineLang.xml and the userDefineLangs
// folder and driven into Lexilla's "user" lexer with the same properties,
// keyword lists and styles Notepad++ hands it (ScintillaEditView::setUserLexer).
// Before this the file was written and never read: no user language was
// ever highlighted.
#import <Foundation/Foundation.h>
#import "LanguageCatalog.h"
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// One <UserLang> as the file describes it.
@interface NppUserLanguage : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *extensions;
@property (nonatomic) BOOL caseIgnored, allowFoldOfComments, foldCompact;
@property (nonatomic) int forcePureLC, decimalSeparator;
/// Whether keyword group 1..8 matches by prefix.
@property (nonatomic, copy) NSArray<NSNumber *> *prefixes;
/// The 28 keyword lists, by SCE_USER_KWLIST_* index, as written in the file.
@property (nonatomic, copy) NSArray<NSString *> *keywordLists;
/// SCE_USER_STYLE_* id -> {fg, bg, fontName, fontStyle, fontSize, nesting}.
@property (nonatomic, copy) NSDictionary<NSNumber *, NSDictionary *> *styles;
/// A small number of its own, for the lexer's cache; a pointer would not
/// survive the lexer's int conversion.
@property (nonatomic) int identifier;
/// darkModeTheme="yes": the variant for dark mode.
@property (nonatomic) BOOL darkModeTheme;
/// The file it was read from, and so where it is written back.
@property (nonatomic, copy, nullable) NSString *sourcePath;

/// Every language in an XML file of Notepad++'s userDefineLang shape.
+ (NSArray<NppUserLanguage *> *)languagesInFile:(NSString *)path;

/// A new language with nothing in it and the styles a new one gets on
/// Windows: black on white, nothing nested.
+ (instancetype)emptyLanguageNamed:(NSString *)name;

/// Writes languages as Notepad++ writes userDefineLang.xml, so the file
/// reads back on Windows unchanged.
+ (BOOL)writeLanguages:(NSArray<NppUserLanguage *> *)languages toFile:(NSString *)path;

/// The names Notepad++ writes: keyword list i, style id i.
+ (NSArray<NSString *> *)keywordListNames;
+ (NSArray<NSString *> *)styleNames;

/// The field values of a prefixed list ("00# 01 02 03/* 04*/"): the text of
/// code `code`, as the dialog shows it ((groups)) kept whole. The inverse
/// builds the list back from the fields in code order (convertTo/retrieve).
+ (NSString *)fieldForCode:(int)code inList:(NSString *)list;
+ (NSString *)listFromFields:(NSArray<NSString *> *)fields;
@end

@interface LanguageCatalog (UserLanguages)
/// Reads userDefineLang.xml and userDefineLangs/*.xml under the settings
/// folder and lists their languages in the catalog, replacing whatever user
/// languages were listed before. A user language's extensions win over the
/// built-in ones, as on Windows.
- (NSArray<NppUserLanguage *> *)reloadUserLanguagesFromDirectory:(NSString *)directory;
/// The definition behind a language listed from a file, or nil.
- (nullable NppUserLanguage *)userLanguageNamed:(NSString *)name;
/// Every user language read, in order.
- (NSArray<NppUserLanguage *> *)allUserLanguages;

/// Where the application bundles the user languages Notepad++ ships
/// (markdown, light and dark); read after the user's own, and shadowed by a
/// user file of the same name.
+ (nullable NSString *)bundledUserLanguagesDirectory;

// Keeping them. Each writes the file concerned, reads everything back, and
// returns NO with nothing changed when it cannot.
/// Writes the language back to the file it came from (a bundled one goes to
/// a copy of that file in the user's folder); a new one goes to
/// userDefineLang.xml.
- (BOOL)saveUserLanguage:(NppUserLanguage *)udl directory:(NSString *)directory;
/// A copy under a new name, in userDefineLang.xml. NO when the name is taken.
- (BOOL)saveUserLanguage:(NppUserLanguage *)udl asName:(NSString *)name directory:(NSString *)directory;
- (BOOL)renameUserLanguage:(NppUserLanguage *)udl to:(NSString *)name directory:(NSString *)directory;
- (BOOL)removeUserLanguage:(NppUserLanguage *)udl directory:(NSString *)directory;
/// The languages of an XML file, added to userDefineLang.xml as Windows adds
/// them; those whose names are taken are skipped. Returns the names added.
- (NSArray<NSString *> *)importUserLanguagesFromFile:(NSString *)path directory:(NSString *)directory;
- (BOOL)exportUserLanguage:(NppUserLanguage *)udl toFile:(NSString *)path;
@end

/// Posted when the user languages were read again, so menus can follow.
extern NSString *const NppUserLanguagesDidChangeNotification;

@interface EditorController (UserLanguages)
/// Sets the "user" lexer up for the language: the properties and keyword
/// lists as setUserLexer sends them. The lexer is already in place.
- (void)configureUserLexerFor:(NppUserLanguage *)udl;
/// The language's own styles, on top of the theme's default.
- (void)applyUserLanguageStyles:(NppUserLanguage *)udl;
@end

NS_ASSUME_NONNULL_END
