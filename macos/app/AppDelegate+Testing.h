#import "ShortcutMapper.h"
// Surface used by the built-in test suite (NPPMAC_TEST=1). These are the very
// code paths the menu items drive; tests call them directly so no modal panel
// is involved.
#import "AppDelegate.h"

@class EditorController;

@interface AppDelegate (Testing)
@property (nonatomic, copy) NSString *lastSearchTerm;
- (EditorController *)editor;
- (BOOL)searchFrom:(long)start forward:(BOOL)forward wrap:(BOOL)wrap;

// Find panel: the controls the Find dialog carries, and what they add up to.
- (void)buildFindPanel;
- (void)openFindPanelOnTab:(NSInteger)tab;
- (void)showConversionPanel:(id)sender;
- (void)toggleMarkdownPreview:(id)sender;
- (void)cliRequest:(NSNotification *)note;
- (void)findPanelFindInFiles:(id)sender;
- (void)findPanelFindAll:(id)sender;
- (id)currentFindSpec;
- (void)findPanelCount:(id)sender;
- (void)findPanelMarkAll:(id)sender;
- (void)findPanelCopyMarkedText:(id)sender;
- (void)findPanelFindAllInOpenDocuments:(id)sender;
- (void)findPanelReplaceAllInOpenDocuments:(id)sender;
- (void)findPanelReplaceAll:(id)sender;
- (void)findPanelSwap:(id)sender;
- (void)updateInSelectionAvailability;
- (void)applyFindTransparency;

// File
- (void)newDocument:(id)sender;
- (void)closeTab:(id)sender;
// Edit
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)cutText:(id)sender;
- (void)copyText:(id)sender;
- (void)pasteText:(id)sender;
- (void)selectAllText:(id)sender;
- (void)duplicateLine:(id)sender;
// Window / view modes
@property (nonatomic, strong) NSWindow *window;
- (void)toggleDistractionFree:(id)sender;
- (void)togglePostIt:(id)sender;
- (void)toggleAlwaysOnTop:(id)sender;
- (void)toggleFileBrowser:(id)sender;
- (void)toggleDocumentList:(id)sender;
- (void)toggleFunctionList:(id)sender;
- (void)applyToolbarPreferences;
- (void)macroStart:(id)sender;
- (void)macroStop:(id)sender;
// View
- (void)zoomIn:(id)sender;
- (void)zoomOut:(id)sender;
- (void)zoomReset:(id)sender;
- (void)toggleWordWrap:(id)sender;
- (void)toggleWhitespace:(id)sender;
/// The command line, parsed and applied; here so the suite can drive them.
- (NSDictionary *)parseCommandLine:(NSArray<NSString *> *)arguments;
- (void)applyCommandLine:(NSDictionary *)options;
@property (nonatomic, readonly) NppShortcutStore *shortcutStore;
@property (nonatomic, readonly) NSMenu *macroMenu;
- (void)rebuildMacroMenu;
- (NSMenu *)buildTabContextMenu;
- (void)rebuildLanguageMenu;
- (void)applyLocalization;
- (void)switchDocumentForward:(BOOL)forward;
- (void)endDocumentSwitch;
- (BOOL)documentSwitcherShown;
- (void)saveAll:(id)sender;
@property (nonatomic, strong) NSMenu *languageMenu;
/// The auto-updater's schedule: YES and the next date moved on when due.
- (BOOL)takeScheduledUpdateCheck;
- (BOOL)automaticUpdateCheckAllowed;
/// NppExec: a menu command by its path, and the menu of saved scripts.
- (BOOL)performMenuCommandAtPath:(NSString *)path;
/// Search > Go to... with the prompt's answer: a line, or @offset. NO when it is not one.
- (BOOL)goToLineOrOffset:(NSString *)answer;
/// The command line's folders and patterns: the files they open, in order (getMatchedFileNames).
+ (NSArray<NSString *> *)filesMatching:(NSString *)pattern inFolder:(NSString *)folder recursive:(BOOL)recursive;
- (void)rebuildExecMenu;
- (void)executeScriptText:(NSString *)text;
- (void)stopScript:(id)sender;
@property (nonatomic, strong) NSMenu *execMenu;
/// Plugins, with the port's stand-ins and the Git submenu.
@property (nonatomic, strong) NSMenu *pluginsMenu;
/// Menus filled when opened: the spelling languages, the Git branches.
- (void)menuNeedsUpdate:(NSMenu *)menu;
@end
