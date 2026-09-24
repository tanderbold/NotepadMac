// Localisation from Notepad++'s own translations (installer/nativeLang/*.xml):
// menu commands by their command id, top menus and submenus by upstream's
// menuId / subMenuId, and every other string - dialog controls, window
// titles, message boxes - by the English text it has in english.xml.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// A control given this identifier keeps its texts as they are (names in their own language).
FOUNDATION_EXPORT NSString *const NppUntranslatedIdentifier;
/// Lays out the rows of push buttons in a view after their titles changed:
/// each button as wide as its words (at least its English width); a row by the
/// right edge keeps its right margin, the others their left x, the English gaps
/// kept; a window whose content no longer fits grows. Hidden buttons are left
/// out: call it again when a tab shows other ones.
FOUNDATION_EXPORT void NppFlowButtonRows(NSView *parent);

@interface NppLocalization : NSObject
+ (instancetype)shared;
/// The translations there are: file name -> the language's own name.
+ (NSDictionary<NSString *, NSString *> *)availableLanguages;
/// Loads "russian.xml" (or none for English); YES when it was found.
- (BOOL)loadLanguageFile:(nullable NSString *)fileName;
@property (nonatomic, readonly, copy, nullable) NSString *languageFile;
@property (nonatomic, readonly) BOOL active;
/// A menu command's text, by upstream's command id.
/// The bundled folder of nativeLang files; the port's own texts are in "nativeLang-extra" beside it.
+ (NSString *)directory;
- (nullable NSString *)commandName:(int)identifier;
/// The tab context menu's own wording for a command, when the file has one.
- (nullable NSString *)tabCommandName:(int)identifier;
/// The translation of an English string, or the string itself.
- (NSString *)translate:(nullable NSString *)english;
/// As translate:, preferring the names upstream gives windows and tabs.
- (NSString *)translateTitle:(nullable NSString *)english;
/// The main menu: commands by id (from `idsByItem`), menus and submenus by name.
- (void)localizeMenu:(NSMenu *)menu identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)idsByItem;
/// A message in upstream's wording, with its $STR_REPLACE$ and $INT_REPLACE$ filled in.
- (NSString *)message:(NSString *)english string:(nullable NSString *)string number:(NSInteger)number;
/// A window's controls and title.
- (void)localizeWindow:(NSWindow *)window;
/// A window title that changes after the window was localized (the Find window's tabs):
/// the English text kept as the original, the translation shown.
- (void)setTitle:(NSString *)english ofWindow:(NSWindow *)window;
- (void)localizeView:(NSView *)view;
@end

/// The translated form of an English interface string.
FOUNDATION_EXPORT NSString *NppL(NSString *english);
/// A message by upstream's English text - placeholders and all - translated and filled in.
FOUNDATION_EXPORT NSString *NppLMessage(NSString *english, NSString *_Nullable string, NSInteger number);
/// A menu item's or menu's English title, whatever it shows now: what the
/// Shortcut Mapper and shortcuts.xml go by.
FOUNDATION_EXPORT NSString *NppEnglishTitle(NSMenuItem *item);
FOUNDATION_EXPORT NSString *NppEnglishMenuTitle(NSMenu *menu);

NS_ASSUME_NONNULL_END
