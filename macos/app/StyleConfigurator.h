// The Style Configurator, as Notepad++'s WordStyleDlg: it edits a copy of the
// current theme's XML, previews every change, and writes the user's copy of
// the theme on Save & Close (stylers.xml for the default one).
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// The language list's first row, standing for the theme's <GlobalStyles>.
FOUNDATION_EXPORT NSString *const NppGlobalStylesName;

@interface StyleConfiguratorWindow : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)show;
@property (nonatomic, readonly) BOOL visible;
/// Number of styles listed for the language currently shown.
@property (nonatomic, readonly) NSInteger styleCount;
/// The theme being edited, and whether it has unsaved changes.
@property (nonatomic, readonly, copy) NSString *themeName;
@property (nonatomic, readonly) BOOL dirty;

// What the controls do, here so the suite can drive them.
- (BOOL)selectLanguage:(NSString *)lexerName;          // NppGlobalStylesName for the global styles
- (BOOL)selectStyleNamed:(NSString *)name;
/// fgColor, bgColor ("RRGGBB"), fontName, fontSize, fontStyle (1 bold, 2 italic, 4 underline).
- (void)setValue:(nullable NSString *)value ofAttribute:(NSString *)attribute;
/// What the system font panel chose: family, size, bold and italic.
- (void)applyChosenFont:(NSFont *)font;
- (void)setUserExtensions:(NSString *)extensions;
- (void)setUserKeywords:(NSString *)keywords;
- (void)setGlobalOverride:(NSString *)flag enabled:(BOOL)on;   // fg bg font fontSize bold italic underline
- (void)selectThemeNamed:(NSString *)name;
- (void)saveAndClose:(nullable id)sender;
- (void)cancel:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
