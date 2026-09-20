// View-menu commands: tab navigation and colouring, fold levels, symbol
// display, window modes, file monitoring and document summary.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppSymbol) {
    NppSymbolWhitespace, NppSymbolEOL, NppSymbolNonPrinting,
    NppSymbolControlAndUnicodeEOL, NppSymbolIndentGuide, NppSymbolWrap,
};

typedef NS_ENUM(NSInteger, NppWindowMode) {
    NppWindowNormal, NppWindowFullScreen, NppWindowPostIt, NppWindowDistractionFree,
};

@interface EditorController (ViewCommands)

// Tabs
- (BOOL)selectTabNumber:(NSInteger)oneBased;      // 1..9
- (void)goToFirstTab;
- (void)goToLastTab;
- (void)goToNextTab;
- (void)goToPreviousTab;
- (BOOL)moveCurrentTab:(BOOL)forward;
- (void)moveCurrentTabToEnd:(BOOL)end;            // NO = start
- (void)setTabColour:(NSInteger)colour;           // 0 = none, 1..5

// Fold levels
- (void)foldToLevel:(NSInteger)level;             // 1..8
- (void)unfoldToLevel:(NSInteger)level;

// Symbols
- (BOOL)symbolVisible:(NppSymbol)symbol;
- (void)toggleSymbol:(NppSymbol)symbol;

// Lines
- (BOOL)hideSelectedLines;
- (void)showAllHiddenLines;

// Text direction
- (void)setTextDirectionRTL:(BOOL)rtl;
- (BOOL)textDirectionIsRTL;

// Document info
- (NSDictionary<NSString *, NSNumber *> *)documentSummary;

// External viewers
- (BOOL)openCurrentInBrowserBundleID:(NSString *)bundleID;

// Monitoring (tail -f)
- (BOOL)monitoringEnabled;
- (void)stopMonitoringDocument:(NppDocument *)doc;
/// A monitored document's file changed (the watcher calls this).
- (void)monitoredDocumentChanged:(NppDocument *)doc;
/// Loads what a monitored document missed while it was not in front.
- (void)catchUpMonitoredDocument;
- (void)setMonitoring:(BOOL)on;

@end

NS_ASSUME_NONNULL_END
