// Loads Notepad++'s own colour scheme (stylers.model.xml) so the macOS editor
// renders with the same default theme as Notepad++ on Windows.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One <WordsStyle>/<WidgetStyle> entry.
@interface NppStyle : NSObject
@property (nonatomic) int styleID;
@property (nonatomic, strong, nullable) NSColor *foreground;
@property (nonatomic, strong, nullable) NSColor *background;
@property (nonatomic) int fontStyle;                       // bit 1 bold, 2 italic, 4 underline
@property (nonatomic, copy, nullable) NSString *fontName;
@property (nonatomic) int fontSize;                        // 0 = unset
@property (nonatomic, copy, nullable) NSString *keywordClass;  // "instre1", "type1", ...
@property (nonatomic, copy, nullable) NSString *name;          // <WidgetStyle name="..."> 
/// Keywords the user added to this style's keyword class (the element's text).
@property (nonatomic, copy, nullable) NSString *userKeywords;
@end

@interface StyleCatalog : NSObject
+ (instancetype)sharedCatalog;

/// Themes are the same XML as stylers.model.xml. Notepad++ ships a folder of
/// them; imported ones live beside the app's other support files.
+ (NSArray<NSString *> *)availableThemeNames;      // "Default" plus every theme found
+ (nullable NSString *)pathForThemeNamed:(NSString *)name;
/// Reloads the shared catalogue from a theme. "Default" restores stylers.model.xml.
+ (void)loadThemeNamed:(NSString *)name;
+ (void)setImportedThemesDirectory:(nullable NSString *)dir;
/// Where the user's own copy of a theme is written: the imported-themes
/// folder, or stylers.xml beside it for "Default". It is read in preference
/// to the shipped one, as Notepad++ reads the user's stylers.xml.
+ (nullable NSString *)userPathForThemeNamed:(NSString *)name;
/// Reads a theme from a file under a name, for previewing unsaved changes.
+ (void)loadThemeFromFile:(NSString *)path named:(NSString *)name;
@property (nonatomic, readonly, copy) NSString *themeName;
/// Styles for a Notepad++ lexer name (the <LexerType name="..."> key), or nil.
- (nullable NSArray<NppStyle *> *)stylesForLexerName:(NSString *)lexerName;
/// Entries from <GlobalStyles>, keyed by their name attribute.
/// Several share styleID="0", so the name is the only unique key.
@property (nonatomic, readonly) NSDictionary<NSString *, NppStyle *> *globalStyles;
/// The same, in the order the theme lists them.
@property (nonatomic, readonly) NSArray<NppStyle *> *orderedGlobalStyles;
/// The lexers the theme has styles for, in its order, with their descriptions.
@property (nonatomic, readonly) NSArray<NSString *> *lexerNames;
- (nullable NSString *)descriptionOfLexer:(NSString *)lexerName;
/// Extensions the user gave a lexer (the LexerType's ext attribute).
- (NSArray<NSString *> *)userExtensionsForLexer:(NSString *)lexerName;
@end

NS_ASSUME_NONNULL_END
