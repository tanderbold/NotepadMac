// Multi-document editor built on one ScintillaView, switching Scintilla
// documents per tab -- the same model Notepad++ uses on Windows.
#import <Cocoa/Cocoa.h>
#import "TabBarView.h"

@class ScintillaView;
@class NppLanguage;

@class NppProjectPanel;

NS_ASSUME_NONNULL_BEGIN

/// NSBeep, unless MISC. > Mute all sounds is on.
FOUNDATION_EXPORT void NppBeep(void);

/// The font Scintilla is given for a style's font name: the name itself when
/// the Mac has that font, else the system's monospaced font (SF Mono). A theme
/// from Windows names Consolas, which only Microsoft Office brings; Core Text
/// would otherwise hand back Helvetica, a proportional face, and the columns
/// of a text would no longer line up. The name stored in the settings is left
/// as the user or the theme wrote it.
FOUNDATION_EXPORT NSString *NppAvailableFontName(NSString *name);
/// A path with symlinks and dots resolved (realpath), to tell whether two spellings are one file.
FOUNDATION_EXPORT NSString *NppCanonicalPath(NSString *path);

/// Posted whenever the set of open documents changes, so panels listing them
/// can reload instead of drawing from a stale row count.
extern NSString *const NppEditorDocumentsDidChangeNotification;

@interface NppDocument : NSObject
@property (nonatomic) void *docPointer;                 // Scintilla document
@property (nonatomic, copy, nullable) NSString *path;   // nil until saved
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong, nullable) NppLanguage *language;
@property (nonatomic) BOOL modified;
@property (nonatomic) NSStringEncoding encoding;   // encoding the file was read with / will be written with
@property (nonatomic) BOOL hasBOM;
/// Non-zero when the document is held in a Windows code page that has no
/// NSStringEncoding of its own (currently only 720); 0 means use `encoding`.
@property (nonatomic) unsigned int codepage;
@property (nonatomic) int eolMode;                 // SC_EOL_CRLF / SC_EOL_LF / SC_EOL_CR
/// The tab Find All and Find in Files report into; not a name a user's own document could have.
@property (nonatomic) BOOL isSearchResults;
@property (nonatomic) BOOL pinned;                 // survives Close All but Pinned
@property (nonatomic) NSInteger tabColour;         // 0 = none, 1..5 as in Notepad++
/// Set when the language was chosen from the menu rather than worked out from
/// the file name. Renaming then leaves it alone, as Notepad++ does.
@property (nonatomic) BOOL languageChosenByUser;
/// The encoding or BOM was changed since the last save: the bytes on disk
/// differ from what would be written even when the text does not.
@property (nonatomic) BOOL encodingChanged;
/// Where the periodic backup of this document's unsaved text is, once one
/// has been written; nil otherwise. Removed when the document is saved or
/// closed, and read back with the session after a crash or a quit.
@property (nonatomic, copy, nullable) NSString *backupPath;
/// The file's modification date as last read or written here, to notice
/// when another program has changed it.
@property (nonatomic, strong, nullable) NSDate *fileModificationDate;
/// Where the caret and the view were when this document was last in front,
/// put back when it comes to the front again.
@property (nonatomic) long caretPosition;
@property (nonatomic) long anchorPosition;
@property (nonatomic) long firstVisibleLine;
/// The bookmarked lines as last recorded for the session, for a document
/// that is not in front (Scintilla answers for the view's document only).
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *bookmarkedLines;
/// Monitoring (tail -f): the file is watched and the document kept read-only;
/// a change while it is not in front is loaded when it comes to the front.
@property (nonatomic) BOOL monitoring;
/// Read-only as the user set it (Edit > Read-Only), kept in the session.
@property (nonatomic) BOOL userReadOnly;
/// The folded lines, recorded when the document leaves the front: Scintilla
/// keeps folds per view, so a tab switch would otherwise lose them.
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *foldedLines;
@property (nonatomic, strong, nullable) id monitorSource;
@property (nonatomic) BOOL monitorReloadPending;
@end

@interface EditorController : NSObject <NppTabBarDelegate>
@property (nonatomic, readonly) ScintillaView *sci;
@property (nonatomic, readonly) NSView *view;           // tab bar + editor + status bar
@property (nonatomic, readonly) NSArray<NppDocument *> *documents;
@property (nonatomic, readonly, nullable) NppDocument *currentDocument;
@property (nonatomic, weak, nullable) NSWindow *window;
/// Added to the window title, as -titleAdd= on the command line asks.
@property (nonatomic, copy, nullable) NSString *titleSuffix;
/// Builds the tab right-click menu (for the document in front); the Document
/// List offers the same one for a file.
@property (nonatomic, copy, nullable) NSMenu *_Nonnull (^tabContextMenu)(void);

/// The text of the document in front, and its replacement: read and written
/// by length, so that a NUL byte inside a file is kept rather than ending it.
- (NSString *)documentText;
- (void)setDocumentText:(NSString *)text;
/// Files at least this big are mapped and handed to Scintilla as bytes; for tests.
/// A file's text read the way Open reads it - BOM, UTF-16, UTF-8, then the
/// character set uchardet finds - for searching files that are not open.
/// Nil for a binary file.
+ (nullable NSString *)textOfFileAtPath:(NSString *)path encoding:(nullable NSStringEncoding *)encoding
                                 hasBOM:(nullable BOOL *)hasBOM;
+ (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding hasBOM:(BOOL)hasBOM;
+ (void)setStreamingThreshold:(unsigned long long)bytes;

/// Looks at every open file on disk: one changed by another program is
/// reloaded (after asking, unless the setting says to do it silently), one
/// that is gone is either kept, as modified, or closed. Called when the
/// application comes to the front.
- (void)checkFilesOnDisk;

/// Removes the periodic backup of a document, once it is saved or closed.
- (void)dropBackupOfDocument:(NppDocument *)doc;

/// Reopens the file closed last, from the recent list. NO when there is none.
- (BOOL)restoreLastClosedFile;
/// Opens every file on the recent list.
- (NSUInteger)openAllRecentFiles;

/// Asks, for every modified document among `docs`, whether to save it, not
/// save it, or stop. Returns NO when the user stopped or a save failed; the
/// documents the user chose to save are saved by then. Every close that can
/// throw text away - one tab, Close All and its variants, the window,
/// quitting - goes through this.
- (BOOL)confirmClosingDocuments:(NSArray<NppDocument *> *)docs;

/// What confirmClosingDocuments: answers without asking: 0 asks;
/// NSAlertFirstButtonReturn saves, NSAlertSecondButtonReturn does not,
/// NSAlertThirdButtonReturn cancels. For the tests.
@property (nonatomic) NSInteger scriptedCloseAnswer;

/// -nosession on the command line: the session is neither loaded nor
/// written, so the real last session is left for the next launch.
@property (nonatomic) BOOL sessionSavingDisabled;

- (instancetype)initWithFrame:(NSRect)frame;

- (void)newDocument;
- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)saveCurrentDocument;          // prompts if unsaved
/// Writes the current document to `path` in its own encoding, making a backup
/// first when Preferences asks for one.
- (BOOL)writeCurrentToPath:(NSString *)path;
- (BOOL)saveCurrentDocumentAs;
/// Where Save As and Save a Copy As start: the document's folder, else the default directory.
- (nullable NSURL *)saveDirectoryForDocument:(NppDocument *)doc;
/// Save As without the panel; NO when another tab has that file.
- (BOOL)saveCurrentDocumentAsPath:(NSString *)path;
- (void)closeCurrentDocument;
/// Non-interactive close used by the Close All family and by tests.
- (void)closeDocumentAtIndex:(NSInteger)index discardChanges:(BOOL)discard;

// File commands
- (BOOL)reloadCurrentDocument:(NSError **)error;
- (BOOL)saveCopyOfCurrentTo:(NSString *)path error:(NSError **)error;
- (NSUInteger)saveAllDocuments;
- (BOOL)renameCurrentTo:(NSString *)newPath error:(NSError **)error;
- (BOOL)moveCurrentToTrash:(NSError **)error;
- (void)closeAllDocuments;
- (void)closeAllButCurrent;
- (void)closeAllToLeft;
- (void)closeAllToRight;
- (void)closeAllUnchanged;
- (void)closeAllButPinned;
- (void)togglePinCurrent;
- (BOOL)printCurrentShowingPanel:(BOOL)showPanel;
/// The print job, built but not run -- lets tests check it without printing.
- (nullable NSPrintOperation *)printOperationForCurrentShowingPanel:(BOOL)showPanel;

// "Open Containing Folder" family. The target is resolved separately from the
// launch so tests can check it without opening Finder or Terminal.
- (nullable NSURL *)containingFolderURL;
- (BOOL)revealInFinder;
- (BOOL)openContainingFolderInTerminal;   // macOS stand-in for both cmd and PowerShell
- (BOOL)openInDefaultViewer;

// Folder as Workspace
- (void)openFolderAsWorkspace:(nullable NSString *)path;   // nil hides the panel
- (BOOL)workspaceVisible;
- (nullable NSString *)workspaceRootPath;
/// Every Folder as Workspace root.
- (NSArray<NSString *> *)workspaceRootPaths;
/// The folded lines of the document in front.
- (NSArray<NSNumber *> *)currentFoldedLines;
- (void)foldLines:(NSArray<NSNumber *> *)lines;
- (NSArray<NSString *> *)workspaceTopLevelNames;

// Sessions
- (BOOL)saveSessionTo:(NSString *)path error:(NSError **)error;
/// A session is written as Notepad++'s session.xml and read from that, from
/// one Windows wrote, or from the JSON earlier builds of the port wrote.
+ (NSXMLDocument *)sessionXMLFromDictionary:(NSDictionary *)session;
+ (nullable NSDictionary *)sessionDictionaryFromXML:(NSData *)data;
- (BOOL)loadSessionFrom:(NSString *)path error:(NSError **)error;
- (NSString *)defaultSessionPath;
- (void)selectDocumentAtIndex:(NSInteger)index;

- (void)setLanguageNamed:(NSString *)langName;   // manual override
/// The same, marking the choice as the user's so a rename will not undo it.
- (void)chooseLanguageNamed:(NSString *)langName;
- (void)setEncoding:(NSStringEncoding)enc withBOM:(BOOL)bom;   // re-saves in this encoding
- (void)convertEOLTo:(int)eolMode;
- (NSString *)encodingDisplayName;
/// The kNppCharsets row the current document is held in, -1 for Unicode and ANSI.
- (int)currentCharsetIndex;

// Editing commands
- (void)toggleLineComment;
/// IDM_EDIT_BLOCK_COMMENT_SET: one more comment level on every selected line.
- (void)setLineComment;
- (void)toggleBlockComment;
- (void)toggleBookmark;
- (void)nextBookmark;
- (void)previousBookmark;
- (void)clearBookmarks;
- (void)foldAll:(BOOL)fold;
- (void)toggleFoldAtCursor;
- (void)foldCurrent:(BOOL)fold;   // IDM_VIEW_FOLD_CURRENT / IDM_VIEW_UNFOLD_CURRENT
- (void)showAutoCompletion;
- (void)applyTheme;                               // re-apply npp styles (e.g. on appearance change)
- (void)applyLanguage;                            // re-attach lexer, keywords and styles
/// The same for any view: the second pane showing a text of its own (Compare) needs the lexer and styles too.
- (void)applyLanguageOfDocument:(NppDocument *)doc toView:(ScintillaView *)sci;
- (void)applyThemeToView:(ScintillaView *)sci forLanguage:(NSString *)langName;
/// The editor's popup menu as contextMenu.xml describes it; without one (or
/// when it names nothing this build has) the commands listed in Preferences.
@property (nonatomic, copy, nullable) NSMenu *_Nullable (^editorContextMenu)(void);
- (void)rebuildContextMenu;                       // right-click menu from Preferences
- (void)applyTabBarPreferences;                   // layout and behaviour of the tab bar
/// Overtype: what the status bar shows as INS or OVR, and what the Insert key
/// switches between.
@property (nonatomic) BOOL overtype;
- (void)toggleOvertype;
/// Pushes the editor settings that are not per document into Scintilla.
- (void)applyEditorPreferences;

- (void)refreshChrome;                            // tab titles + status bar
/// What a click on the path in the status bar does: the full path to the clipboard, "Copied" shown for a moment.
- (void)copyPathFromStatusBar;
/// Text to the clipboard, with "Copied: <text>" in the status bar for a moment.
- (void)copyText:(NSString *)text;
/// A message in the status bar's path field for a moment.
- (void)flashStatus:(NSString *)message;
/// -notabbar: the tab bar hidden for this run, the status bar kept.
@property (nonatomic) BOOL tabBarHiddenForLaunch;
- (void)hideTabBarForLaunch;
- (void)setChromeVisible:(BOOL)visible;           // hides tab bar + status bar
- (BOOL)chromeVisible;

/// The tab bar above the panes (rows as Multi-line needs) or down their left (Vertical); hidden, none.
- (void)layoutEditorArea;
// Second editor pane. Notepad++ calls these "views"; here the primary pane
// owns the tab bar and the secondary one shows a moved or cloned document.
@property (nonatomic, readonly) ScintillaView *secondarySci;
- (BOOL)secondaryViewVisible;
- (void)setSecondaryViewVisible:(BOOL)visible;
- (void)focusOtherView;
- (BOOL)otherViewHasFocus;
- (BOOL)moveCurrentToOtherView;
/// What the second view shows, while it is shown.
- (nullable NppDocument *)documentInSecondaryView;
/// The view the second pane lives in, with room above it for Compare's bar.
- (NSView *)secondaryHost;
- (BOOL)cloneCurrentToOtherView;
- (BOOL)syncVerticalScroll;
- (void)setSyncVerticalScroll:(BOOL)on;
- (BOOL)syncHorizontalScroll;
- (void)setSyncHorizontalScroll:(BOOL)on;
- (BOOL)syncZoom;
- (void)setSyncZoom:(BOOL)on;
- (void)mirrorScrollToSecondary;
- (void)mirrorScrollFromSecondary;
/// Synchronize Zoom: a pane's zoom put on the other, on its SCN_ZOOM only.
- (void)mirrorZoomToSecondary;
- (void)mirrorZoomFromSecondary;
- (BOOL)openCurrentInNewInstanceMoving:(BOOL)closeHere;

// Document Map: a shrunken read-only view of the same buffer.
- (BOOL)documentMapVisible;
- (void)setDocumentMapVisible:(BOOL)visible;
/// Where the map's view zone is, in the map's own (flipped) coordinates.
- (NSRect)documentMapZone;
/// What a click or drag in the map at `y` does: centres the editor there.
- (void)scrollFromDocumentMapAtY:(CGFloat)y;
- (void)updateDocumentMap;
/// The editor's colours and wrapping, given to the map.
- (void)mirrorStylesToDocumentMap;
/// Document Peeker: what hovering tab `index` does (-1 leaves the tabs).
- (void)peekAtTabIndex:(NSInteger)index;
- (void)applyStatusBarVisibility;
/// The open documents, the one used last first: the Document Switcher's order.
- (NSArray<NppDocument *> *)documentsInRecentOrder;
/// Tab width, tabs or spaces and the rest Scintilla keeps per document.
- (void)applyDocumentSettings;
- (BOOL)statusBarVisible;
- (BOOL)documentPeekerVisible;
- (nullable void *)documentPeekerDocument;

// Project panels 1..3, each keeping its own folder root.
- (void)showProjectPanel:(NSInteger)index;        // 1..3; same index again hides it
- (NSInteger)activeProjectPanel;                  // 0 when none is shown
/// Project Panel 1, 2 or 3, with its workspace.
- (nullable NppProjectPanel *)projectPanel:(NSInteger)index;
/// Save, Don't Save or Cancel for every changed workspace; NO if cancelled.
- (BOOL)confirmDiscardingProjectChanges;

@end

NS_ASSUME_NONNULL_END
