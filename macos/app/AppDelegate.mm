#include <fnmatch.h>
#import "NumberSetCommands.h"
#import "NppPanel.h"
#import "AppDelegate.h"
#import "UserLanguages.h"
#import "UserLanguageDialog.h"
#import "ShortcutMapper.h"
#import "ProjectPanel.h"
#import <objc/message.h>
#import "EditorController.h"
#import "EditCommands.h"
#import "SearchCommands.h"
#import "ViewCommands.h"
#import "EncodingCommands.h"
#import "AdvancedEditCommands.h"
#import "AuxPanels.h"
#import "ToolsCommands.h"
#import "SettingsCommands.h"
#import "SettingsPanels.h"
#import "Toolbar.h"
#import "StyleCatalog.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#include "CommandIDs.h"
#import "Accessibility.h"
#import "Localization.h"
#include "LangMap.h"
#import "JsonCommands.h"
#import "MimeCommands.h"
#import "PluginHost.h"
#import "AgentServer.h"
#import "GitCommands.h"
#import "ConverterCommands.h"
#import "ExportCommands.h"
#import "SpellCheck.h"
#import "MarkdownPanel.h"
#import "ImageCommands.h"
#import "CompareCommands.h"
#import "FtpCommands.h"
#import "XmlCommands.h"
#import "RunCommands.h"
#import "FindCommands.h"
#import "LanguageDetection.h"
#import "DocumentListPanel.h"
#import "FunctionListPanel.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#import "JsonCommands.h"
#import "CompareCommands.h"
#import "FtpCommands.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "Tests.h"
#import "InfoWindows.h"
#import "ToolsWindows.h"
#import "UpdateChecker.h"
#import "DockingManager.h"
#import "ScriptCommands.h"
#import "MacroableCommands.h"
#import "ContextMenuFile.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, NppSnapshotOutcome) { NppSnapshotNotUsed, NppSnapshotCovers, NppSnapshotCancelled };

@interface AppDelegate () <NSWindowDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) EditorController *editor;
@property (nonatomic, strong) NSMenu *pluginsMenu;   // third-party plugins are appended here
@property (nonatomic, strong) MarkdownPanel *markdownPanel;
@property (nonatomic, copy) NSString *lastSearchTerm;
@property (nonatomic, strong) DocumentListPanel *docList;
@property (nonatomic, strong) FunctionListPanel *funcList;
@property (nonatomic, strong) CharacterPanel *charPanel;
@property (nonatomic, strong) ClipboardHistoryPanel *clipPanel;
@property (nonatomic, strong) PreferencesWindow *prefsWindow;
@property (nonatomic, strong) StyleConfiguratorWindow *styleWindow;
@property (nonatomic, strong) NppShortcutStore *shortcutStore;
@property (nonatomic, strong) NppShortcutMapper *shortcutMapper;
@property (nonatomic, strong) NSMenu *macroMenu;
@property (nonatomic) NSInteger fixedMacroItemCount;
@property (nonatomic, strong) NppToolbar *toolbar;
@property (nonatomic, strong) NSMenu *recentMenu;
@property (nonatomic, copy) NSArray<NSString *> *recentMenuFiles;   // what recentMenu was built from
@property (nonatomic, strong) NSPanel *jsonTreePanel;
@property (nonatomic, strong) NSTextView *jsonTreeText;
@property (nonatomic, strong) NSPanel *ftpPanel;
@property (nonatomic, strong) NSTableView *ftpTable;
@property (nonatomic, strong) NSArray *ftpEntries;
@property (nonatomic) BOOL alwaysOnTop;
/// View > Post-It and Distraction Free Mode as the modes they are (upstream's
/// _beforeSpecialView), and Always on Top as it was before Post-It.
@property (nonatomic) BOOL postItOn;
@property (nonatomic) BOOL distractionFreeOn;
@property (nonatomic) BOOL alwaysOnTopBeforePostIt;
/// The clipboard as last seen, so the toolbar's Paste follows it (upstream's
/// checkClipboard on WM_CLIPBOARDUPDATE; a Mac sends no such message).
@property (nonatomic) NSInteger seenPasteboardChange;
@property (nonatomic, strong) NSTimer *pasteboardWatch;
@property (nonatomic, strong) NSMenu *runMenu;
@property (nonatomic, strong) NSMenu *execMenu;
@property (nonatomic) NSInteger fixedExecItemCount;
@property (nonatomic, strong, nullable) NppScriptEngine *runningScript;
@property (nonatomic) NSInteger fixedRunItemCount;
/// Files handed over before the editor existed, opened once it does.
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingOpenPaths;
/// The window's close was already put to the user: quitting after it must
/// not ask again about what was declined.
@property (nonatomic) BOOL closingConfirmed;
/// What the command line asked for, parsed once and applied after launch.
@property (nonatomic, strong) NSDictionary *commandLine;
@property (nonatomic, strong) NppUserLanguageDialog *userLanguageDialog;
@property (nonatomic, strong) NSMenu *languageMenu;
@property (nonatomic, strong) NSPanel *findPanel;
@property (nonatomic, strong) NSPanel *switcherPanel;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSMenuItem *> *menuIdentifiers;
@property (nonatomic, strong) NSTableView *switcherTable;
@property (nonatomic, copy) NSArray<NppDocument *> *switcherOrder;
@property (nonatomic) BOOL switching;
@property (nonatomic, strong) id switcherMonitor;
@property (nonatomic, strong) NSTextField *findField;
@property (nonatomic, strong) NSTextField *replaceField;
@property (nonatomic, strong) NSMatrix *modeRadios;
@property (nonatomic, strong) NSButton *matchCaseBox;
@property (nonatomic, strong) NSButton *wholeWordBox;
@property (nonatomic, strong) NSButton *dotNewlineBox;
@property (nonatomic, strong) NSButton *wrapBox;
@property (nonatomic, strong) NSButton *backwardBox;
@property (nonatomic, strong) NSButton *inSelectionBox;
@property (nonatomic, strong) NSTextField *findStatus;
@property (nonatomic, strong) NSProgressIndicator *findProgress;
@property (nonatomic, strong) NSButton *findStopButton;
@property (nonatomic, strong) NppFileSearch *runningSearch;
@property (nonatomic, strong) NSArray<NSButton *> *findSearchButtons;
@property (nonatomic, strong) NppFindSpec *lastFindSpec;
/// The Find dialog's tabs, as Notepad++ has them.
@property (nonatomic, strong) NSSegmentedControl *findTabs;
@property (nonatomic, strong) NSTextField *filtersField;
@property (nonatomic, strong) NSTextField *directoryField;
@property (nonatomic, strong) NSButton *recursiveBox;
@property (nonatomic, strong) NSButton *hiddenBox;
@property (nonatomic, strong) NSButton *bookmarkLineBox;
@property (nonatomic, strong) NSButton *purgeBox;
@property (nonatomic, strong) NSButton *transparencyBox;
@property (nonatomic, strong) NSMatrix *transparencyRadios;
@property (nonatomic, strong) NSSlider *transparencySlider;
@property (nonatomic, strong) NSMutableArray<NSView *> *findOnlyViews;
@property (nonatomic, strong) NSMutableArray<NSView *> *replaceViews;
@property (nonatomic, strong) NSMutableArray<NSView *> *inFilesViews;
@property (nonatomic, strong) NSMutableArray<NSView *> *inProjectsViews;
/// Which project panels Find in Projects searches, as the Windows tab has them.
@property (nonatomic, strong) NSArray<NSButton *> *projectPanelBoxes;
@property (nonatomic, strong) NSMutableArray<NSView *> *markViews;
@end

/// The candidates for a document's language, as a plain list: every one in
/// view, the first selected, a double click choosing it.
@interface NppLanguageChoiceList : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSArray<NSString *> *names;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, copy) void (^chosen)(void);
- (instancetype)initWithNames:(NSArray<NSString *> *)names;
@end

@implementation NppLanguageChoiceList

- (instancetype)initWithNames:(NSArray<NSString *> *)names {
    if (!(self = [super init])) return nil;
    _names = [names copy];

    const CGFloat rowHeight = 22, width = 260;
    CGFloat height = rowHeight * (CGFloat)names.count + 4;
    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.width = width - 4;
    [_table addTableColumn:column];
    _table.headerView = nil;
    _table.rowHeight = rowHeight;
    _table.allowsEmptySelection = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(doubleClicked:);

    _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    _scrollView.documentView = _table;
    _scrollView.hasVerticalScroller = NO;
    _scrollView.borderType = NSBezelBorder;
    [_table reloadData];
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)self.names.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *label = [tableView makeViewWithIdentifier:@"label" owner:self];
    if (!label) {
        label = [NSTextField labelWithString:@""];
        label.identifier = @"label";
    }
    label.stringValue = self.names[(NSUInteger)row];
    return label;
}

- (void)doubleClicked:(id)sender {
    if (self.table.selectedRow >= 0 && self.chosen) self.chosen();
}

@end

/// 1st, 2nd, 3rd, 4th... as the Windows menus write them.
static NSString *Ordinal(NSUInteger n) {
    NSString *suffix = (n % 100 >= 11 && n % 100 <= 13) ? @"th"
        : n % 10 == 1 ? @"st" : n % 10 == 2 ? @"nd" : n % 10 == 3 ? @"rd" : @"th";
    return [NSString stringWithFormat:@"%lu%@", (unsigned long)n, suffix];
}

@implementation AppDelegate

#pragma mark - Launch

#pragma mark - The command line

/// The switches Notepad++ takes, read the way winmain.cpp reads them: a
/// switch is a word starting with "-"; -n, -c, -p, -l carry their value
/// attached; the =-switches carry it after the sign; -z skips the next word;
/// after -notepadStyleCmdline the rest of the line is one file name. What
/// starts with "-" and is none of them is left alone (macOS adds a few of
/// its own); everything else is a file.
- (NSDictionary *)parseCommandLine:(NSArray<NSString *> *)arguments {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSMutableArray *files = [NSMutableArray array];
    NSSet *flags = [NSSet setWithArray:@[@"-multiInst", @"-noPlugin", @"-ro", @"-fullReadOnly",
        @"-fullReadOnlySavingForbidden", @"-nosession", @"-notabbar", @"-systemtray", @"-loadingTime",
        @"-alwaysOnTop", @"-openSession", @"-r", @"-quickPrint", @"-openFoldersAsWorkspace",
        @"-monitor", @"-monitoringMode", @"-export=functionList"]];
    NSArray *valued = @[@"-settingsDir=", @"-titleAdd=", @"-udl=", @"-pluginMessage=", @"-qt=", @"-qf=", @"-qn="];

    for (NSUInteger i = 0; i < arguments.count; ++i) {
        NSString *arg = arguments[i];
        if ([arg isEqualToString:@"-z"]) { i++; continue; }
        if ([arg isEqualToString:@"-notepadStyleCmdline"]) {
            NSArray *rest = [arguments subarrayWithRange:NSMakeRange(i + 1, arguments.count - i - 1)];
            if (rest.count) [files addObject:[rest componentsJoinedByString:@" "]];
            break;
        }
        if ([flags containsObject:arg]) { options[arg] = @YES; continue; }
        BOOL taken = NO;
        for (NSString *prefix in valued) {
            if ([arg hasPrefix:prefix]) { options[prefix] = [arg substringFromIndex:prefix.length]; taken = YES; break; }
        }
        if (taken) continue;
        if (arg.length > 2 && [arg hasPrefix:@"-"]) {
            unichar which = [arg characterAtIndex:1];
            NSString *rest = [arg substringFromIndex:2];
            // A window position may be negative (a screen to the left), as atoi reads it on Windows.
            if ((which == 'x' || which == 'y') && rest.length > 1 && [rest hasPrefix:@"-"] &&
                [[NSCharacterSet decimalDigitCharacterSet] isSupersetOfSet:
                    [NSCharacterSet characterSetWithCharactersInString:[rest substringFromIndex:1]]]) {
                options[[NSString stringWithFormat:@"-%C", which]] = @(rest.integerValue);
                continue;
            }
            if ((which == 'n' || which == 'c' || which == 'p' || which == 'x' || which == 'y') &&
                [[NSCharacterSet decimalDigitCharacterSet] isSupersetOfSet:
                    [NSCharacterSet characterSetWithCharactersInString:rest]]) {
                options[[NSString stringWithFormat:@"-%C", which]] = @(rest.integerValue);
                continue;
            }
            if (which == 'l') { options[@"-l"] = rest; continue; }
        }
        if ([arg hasPrefix:@"-"]) {
            // A user default for this run (NSArgumentDomain) comes as a pair - "-NppMac.agentServer YES",
            // "-NSDocumentRevisionsDebugMode YES", "-AppleLanguages (ru)": its value is not a file.
            BOOL defaultsKey = [arg containsString:@"."] || [arg hasPrefix:@"-NS"] || [arg hasPrefix:@"-Apple"];
            if (defaultsKey && ![arg hasPrefix:@"-psn_"] && i + 1 < arguments.count && ![arguments[i + 1] hasPrefix:@"-"]) i++;
            continue;
        }
        [files addObject:arg];
    }
    options[@"files"] = files;
    // -pluginMessage="..." loses its quotes, as upstream strips them.
    NSString *message = options[@"-pluginMessage="];
    if (message.length >= 2 && [message hasPrefix:@"\""] && [message hasSuffix:@"\""]) {
        options[@"-pluginMessage="] = [message substringWithRange:NSMakeRange(1, message.length - 2)];
    }
    // Exporting the function list or printing and quitting runs silently,
    // with no session read or written, as upstream does.
    if ([options[@"-export=functionList"] boolValue] || [options[@"-quickPrint"] boolValue]) options[@"-nosession"] = @YES;
    return options;
}

/// getMatchedFileNames (Notepad_plus): the files of a folder whose name matches a pattern,
/// in name order, then those of its folders when recursive; hidden folders are left out.
+ (NSArray<NSString *> *)filesMatching:(NSString *)pattern inFolder:(NSString *)folder recursive:(BOOL)recursive {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *files = [NSMutableArray array], *folders = [NSMutableArray array];
    NSArray<NSString *> *names = [[fm contentsOfDirectoryAtPath:folder error:NULL]
                                  sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names) {
        NSString *full = [folder stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDirectory]) continue;
        if (isDirectory) {
            if (recursive && ![name hasPrefix:@"."]) [folders addObject:full];
        } else if (![name isEqualToString:@".DS_Store"] && fnmatch(pattern.fileSystemRepresentation, name.fileSystemRepresentation, 0) == 0) {
            [files addObject:full];
        }
    }
    for (NSString *sub in folders) [files addObjectsFromArray:[self filesMatching:pattern inFolder:sub recursive:YES]];
    return files;
}

- (void)applyCommandLine:(NSDictionary *)options {
    if (!options) return;
    if ([options[@"-alwaysOnTop"] boolValue] && !self.alwaysOnTop) [self toggleAlwaysOnTop:nil];
    if ([options[@"-titleAdd="] length]) self.editor.titleSuffix = options[@"-titleAdd="];
    if ([options[@"-notabbar"] boolValue]) [self.editor hideTabBarForLaunch];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cwd = fm.currentDirectoryPath;
    NSMutableArray<NppDocument *> *opened = [NSMutableArray array];
    void (^openOne)(NSString *) = ^(NSString *file) {
        if ([self.editor openFileAtPath:file error:NULL] && self.editor.currentDocument) {
            [opened addObject:self.editor.currentDocument];
        }
    };
    for (NSString *given in options[@"files"]) {
        NSString *path = given.isAbsolutePath ? given : [cwd stringByAppendingPathComponent:given];
        path = path.stringByStandardizingPath;
        BOOL isDirectory = NO;
        BOOL exists = [fm fileExistsAtPath:path isDirectory:&isDirectory];
        if ([options[@"-openSession"] boolValue]) {
            if (exists) [self.editor loadSessionFrom:path error:NULL];
            continue;
        }
        if (exists && isDirectory && [options[@"-openFoldersAsWorkspace"] boolValue]) {
            [self.editor openFolderAsWorkspace:path];
            continue;
        }
        // Notepad_plus::doOpen: a pattern ("*.txt", "?") opens the files of its folder that match
        // (those of the folders under it too with -r); a folder opens every file under it.
        NSString *name = path.lastPathComponent;
        BOOL globbing = [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?"]].location != NSNotFound;
        if (globbing || (exists && isDirectory)) {
            NSArray<NSString *> *files = globbing
                ? [AppDelegate filesMatching:name inFolder:path.stringByDeletingLastPathComponent recursive:[options[@"-r"] boolValue]]
                : [AppDelegate filesMatching:@"*" inFolder:path recursive:YES];
            if (files.count > 200) {
                NSAlert *ask = [[NSAlert alloc] init];
                ask.messageText = NppL(@"Amount of files to open is too large");
                ask.informativeText = NppLMessage(@"$INT_REPLACE$ files are about to be opened. Are you sure to open them?", nil, (NSInteger)files.count);
                [ask addButtonWithTitle:@"Yes"];
                [ask addButtonWithTitle:@"No"];
                if ([ask runModal] != NSAlertFirstButtonReturn) continue;
            }
            for (NSString *file in files) openOne(file);
            continue;
        }
        if (!exists) {
            // doOpen: a file that is not there is offered for creation when its folder is,
            // and the folder that is missing is named otherwise.
            NSString *folder = path.stringByDeletingLastPathComponent;
            BOOL folderIsThere = NO;
            NSAlert *alert = [[NSAlert alloc] init];
            if ([fm fileExistsAtPath:folder isDirectory:&folderIsThere] && folderIsThere) {
                alert.messageText = NppL(@"Create new file");
                alert.informativeText = NppLMessage(@"\"$STR_REPLACE$\" doesn't exist. Create it?", path, 0);
                [alert addButtonWithTitle:@"Yes"];
                [alert addButtonWithTitle:@"No"];
                if ([alert runModal] != NSAlertFirstButtonReturn) continue;
                if (![fm createFileAtPath:path contents:[NSData data] attributes:nil]) {
                    NSAlert *failed = [[NSAlert alloc] init];
                    failed.messageText = NppL(@"Create new file");
                    failed.informativeText = NppLMessage(@"Cannot create the file \"$STR_REPLACE$\".", path, 0);
                    [failed runModal];
                    continue;
                }
                openOne(path);
            } else {
                alert.messageText = NppL(@"Cannot open file");
                NSString *text = NppL(@"\"$STR_REPLACE1$\" cannot be opened:\nFolder \"$STR_REPLACE2$\" doesn't exist.");
                alert.informativeText = [[text stringByReplacingOccurrencesOfString:@"$STR_REPLACE1$" withString:path]
                                         stringByReplacingOccurrencesOfString:@"$STR_REPLACE2$" withString:folder];
                [alert runModal];
            }
            continue;
        }
        openOne(path);
    }
    for (NSString *key in @[@"-qt=", @"-qf="]) {
        NSString *value = options[key];
        if (!value.length) continue;
        NSString *text = [key isEqualToString:@"-qt="] ? value
            : [NSString stringWithContentsOfFile:value encoding:NSUTF8StringEncoding error:NULL];
        if (!text) continue;
        [self.editor newDocument];
        [self.editor setDocumentText:text];
        [self.editor.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
        [opened addObject:self.editor.currentDocument];
    }

    BOOL readOnly = [options[@"-ro"] boolValue] || [options[@"-fullReadOnly"] boolValue] ||
                    [options[@"-fullReadOnlySavingForbidden"] boolValue];
    NSString *language = [options[@"-udl="] length] ? options[@"-udl="] : options[@"-l"];
    for (NppDocument *doc in opened) {
        [self.editor selectDocumentAtIndex:(NSInteger)[self.editor.documents indexOfObject:doc]];
        if (language.length) [self.editor chooseLanguageNamed:language];
        if (readOnly) [self.editor setReadOnly:YES];
    }
    if (opened.count) {
        [self.editor selectDocumentAtIndex:(NSInteger)[self.editor.documents indexOfObject:opened.lastObject]];
        ScintillaView *sci = self.editor.sci;
        if (options[@"-p"]) {
            [sci message:SCI_GOTOPOS wParam:(uptr_t)[options[@"-p"] longValue] lParam:0];
        } else if (options[@"-n"]) {
            long line = MAX(0, [options[@"-n"] longValue] - 1);
            [sci message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
            if (options[@"-c"]) {
                long column = MAX(0, [options[@"-c"] longValue] - 1);
                [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_FINDCOLUMN wParam:(uptr_t)line lParam:column] lParam:0];
            }
        }
        // -monitor: every file given is watched, not just the last.
        if ([options[@"-monitor"] boolValue] || [options[@"-monitoringMode"] boolValue]) {
            for (NppDocument *doc in opened) {
                [self.editor selectDocumentAtIndex:(NSInteger)[self.editor.documents indexOfObject:doc]];
                [self.editor setMonitoring:YES];
            }
            [self.editor selectDocumentAtIndex:(NSInteger)[self.editor.documents indexOfObject:opened.lastObject]];
        }
    }
    // -x and -y: where the window's top left corner goes, from the screen's.
    if (options[@"-x"] || options[@"-y"]) {
        NSRect visible = (self.window.screen ?: [NSScreen mainScreen]).frame;
        NSRect frame = self.window.frame;
        CGFloat x = options[@"-x"] ? visible.origin.x + [options[@"-x"] doubleValue] : frame.origin.x;
        CGFloat top = options[@"-y"] ? NSMaxY(visible) - [options[@"-y"] doubleValue] : NSMaxY(frame);
        [self.window setFrameTopLeftPoint:NSMakePoint(x, top)];
    }
    // -pluginMessage=: there are no plugins to hand it to.
    if ([options[@"-pluginMessage="] length]) {
        fprintf(stderr, "NotepadMac: -pluginMessage ignored, plugins are not supported: %s\n",
                [options[@"-pluginMessage="] UTF8String]);
    }
    [self.editor refreshChrome];
    [self rebuildRecentMenu];
    // -export=functionList and -quickPrint do their work and quit.
    if (!getenv("NPPMAC_TEST") && ([options[@"-export=functionList"] boolValue] || [options[@"-quickPrint"] boolValue])) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([options[@"-export=functionList"] boolValue]) [FunctionListPanel exportFunctionListOf:self.editor to:nil];
            if ([options[@"-quickPrint"] boolValue]) [self.editor printCurrentShowingPanel:NO];
            [NSApp terminate:nil];
        });
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // Documents are tabs of the editor, not tabbed windows: without this AppKit adds its own
    // Show Next Tab (Ctrl+Tab, which is Notepad++'s), Move Tab to New Window and Merge All
    // Windows to the Window menu.
    NSWindow.allowsAutomaticWindowTabbing = NO;
    // The command line comes first: -settingsDir= decides where everything
    // below reads its settings from.
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    self.commandLine = [self parseCommandLine:
        arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)] : @[]];
    if ([self.commandLine[@"-settingsDir="] length]) {
        [EditorController setSettingsDirectoryForThisLaunch:self.commandLine[@"-settingsDir="]];
    }
    NSRect frame = NSMakeRect(0, 0, 1000, 700);
    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window center];
    self.window.minSize = NSMakeSize(520, 320);

    self.editor = [[EditorController alloc] initWithFrame:frame];
    self.editor.window = self.window;
    [self.editor gitInstall];
    self.window.delegate = self;
    // Files dropped anywhere on the window open, as on Windows.
    [self.window registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    // Opening a file whose name says nothing may turn up several languages that
    // fit; this is what puts them to the user.
    __weak __typeof(self) weakSelf = self;
    self.editor.languageChoiceHandler = ^(NSArray<NppLanguage *> *choices) {
        [weakSelf offerLanguageChoices:choices];
    };
    self.window.contentView = self.editor.view;

    // User-defined languages join the catalog before the Language menu is
    // built from it.
    (void)[[NppPreferences shared] effectiveThemeName];  // sets the catalog's dark mode first
    [[LanguageCatalog sharedCatalog] reloadUserLanguagesFromDirectory:[self.editor supportDirectory]];
    [self buildMenus];
    [self rebuildUserLanguageMenuItems];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userLanguagesChanged:)
                                                 name:NppUserLanguagesDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(savedCommandsChanged:)
                                                 name:@"NppSavedCommandsDidChange" object:nil];

    // Imported themes join the bundled ones in the Preferences picker.
    [StyleCatalog setImportedThemesDirectory:
        [[self.editor supportDirectory] stringByAppendingPathComponent:@"themes"]];
    // The theme was loaded before the settings folder was known, from the bundle only:
    // loaded again, it is the user's saved copy (stylers.xml, themes/) when there is
    // one - Notepad++ reads the user's stylers.xml at start (SETTINGS-094).
    NSString *loadedTheme = [StyleCatalog sharedCatalog].themeName;
    if (loadedTheme.length) {
        [StyleCatalog loadThemeNamed:loadedTheme];
        [self.editor applyLanguage];
    }

    __weak __typeof(self) weakApp = self;
    self.editor.tabContextMenu = ^NSMenu *{ return [weakApp buildTabContextMenu]; };
    // The editor's popup menu, from contextMenu.xml in the settings folder -
    // upstream's default the first time, the user's own after that.
    self.editor.editorContextMenu = ^NSMenu *{
        return [NppContextMenuFile menuFromFile:[weakApp contextMenuPathCreatingDefault:YES] root:@"ScintillaContextMenu"
                                       mainMenu:NSApp.mainMenu identifiers:[weakApp.shortcutStore menuItemsByIdentifier]];
    };
    // And are recorded from here: the menu says when one of its commands runs.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuWillSendAction:)
                                                 name:NSMenuWillSendActionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidSendAction:)
                                                 name:NSMenuDidSendActionNotification object:nil];
    // Macro steps that are menu commands (shortcuts.xml's type 2) find their command here.
    self.editor.menuCommandByIdentifier = ^BOOL(int identifier) {
        NSMenuItem *item = [weakApp.shortcutStore menuItemsByIdentifier][@(identifier)];
        if (!item.action) return NO;
        [item.menu update];
        return item.isEnabled && [NSApp sendAction:item.action to:item.target from:item];
    };
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(findInFolderRequested:)
                                                 name:@"NppFindInFolderRequested" object:nil];
    // The interface in the language chosen: menus now, windows as they come up.
    self.menuIdentifiers = [self.shortcutStore menuItemsByIdentifier];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowBecameKey:)
                                                 name:NSWindowDidBecomeKeyNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuWillShow:)
                                                 name:NSMenuDidBeginTrackingNotification object:nil];
    [self applyLocalization];
    [self installDocumentSwitcher];
    self.toolbar = [[NppToolbar alloc] initWithWindow:self.window target:self];
    [[NppPreferences shared] applyToEditor:self.editor];
    [self applyToolbarPreferences];
    [self.editor setAutosaveEnabled:[NppPreferences shared].autosaveEnabled
                           interval:[NppPreferences shared].autosaveInterval];
    [self.editor restorePanelState];
    [self restoreFloatingPanels];
    [[NppDockingManager shared] restoreFronts];
    if ([self.commandLine[@"-nosession"] boolValue]) {
        self.editor.sessionSavingDisabled = YES;      // neither loaded nor overwritten
    } else if ([NppPreferences shared].restoreSession) {
        [self.editor loadSessionFrom:[self.editor defaultSessionPath] error:NULL];
    }
    // The documents this instance was launched with arrive through
    // application:openFile: before this method runs, and waited here.
    for (NSString *path in self.pendingOpenPaths) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:path error:&err] && err) [[NSAlert alertWithError:err] runModal];
    }
    self.pendingOpenPaths = nil;
    [self applyCommandLine:self.commandLine];
    // New Document > "Always open a new document in addition at startup", with
    // the session remembered, as Notepad_plus_Window::init does after the
    // session and the command line's files: IDM_FILE_NEW.
    if ([NppPreferences shared].openNewDocumentAtStartup && [NppPreferences shared].restoreSession) {
        [self.editor newDocument];
    }

    // Follow the system appearance while Preferences is set to do so.
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance"
               options:NSKeyValueObservingOptionNew context:NULL];

    [self.editor refreshChrome];

    __weak AppDelegate *watcher = self;
    self.pasteboardWatch = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        NSInteger now = [NSPasteboard generalPasteboard].changeCount;
        if (now == watcher.seenPasteboardChange) return;
        watcher.seenPasteboardChange = now;
        [watcher.window.toolbar validateVisibleItems];
    }];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.editor.sci.content];
    [NSApp activateIgnoringOtherApps:YES];

    // The nppmac command line tool speaks over this: the bundle's own id with
    // ".cli", so a copy under another id (the end-to-end suite's) hears only
    // the nppmac inside it.
    [[NSDistributedNotificationCenter defaultCenter]
        addObserver:self selector:@selector(cliRequest:)
               name:[(NSBundle.mainBundle.bundleIdentifier ?: @"org.notepad-plus-plus.mac") stringByAppendingString:@".cli"] object:nil];

    // Third-party plugins, once everything they may call is up.
    NppPluginHost *host = [NppPluginHost shared];
    host.editor = self.editor;
    [host loadPluginsFromDirectory:[host pluginsDirectory] intoMenu:self.pluginsMenu];
    [host notifyPlugins:NPPN_READY];

    if (getenv("NPPMAC_TEST")) {
        [self performSelector:@selector(runTestSuite) withObject:nil afterDelay:0.5];
    }
    if (getenv("NPPMAC_SELFTEST")) {
        [self performSelector:@selector(runSelfTest) withObject:nil afterDelay:0.8];
    }
    if (getenv("NPPMAC_SNAPSHOT")) {
        [self performSelector:@selector(writeSnapshot) withObject:nil afterDelay:1.2];
    }
    // The auto-updater, when it is set to run on startup and its interval is up.
    if ([self automaticUpdateCheckAllowed] && [NppPreferences shared].autoUpdateMode == 1) {
        [self performSelector:@selector(automaticUpdateCheck) withObject:nil afterDelay:3.0];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }

- (void)applicationDidBecomeActive:(NSNotification *)note {
    [self.editor checkFilesOnDisk];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
    if (self.closingConfirmed) return NSTerminateNow;
    if (![self.editor confirmDiscardingProjectChanges]) return NSTerminateCancel;
    // With the session snapshot on and the session restored at launch, the
    // unsaved text comes back next time, so nothing is asked - as on Windows.
    switch ([self snapshotCoversEverything]) {
        case NppSnapshotCovers: return NSTerminateNow;
        case NppSnapshotCancelled: return NSTerminateCancel;   // Cancel at a question is Cancel
        case NppSnapshotNotUsed: break;
    }
    return [self.editor confirmClosingDocuments:self.editor.documents] ? NSTerminateNow
                                                                         : NSTerminateCancel;
}

/// With the session snapshot on and the session restored at launch, a
/// backup pass keeps every unsaved document for the next launch and nothing
/// need be asked - as on Windows. Unless a document could not be backed up
/// (a large file, a failed write): those are asked about as usual.
/// NotUsed: no snapshot, everything is asked about; Covers: nothing (more) to
/// ask; Cancelled: the user cancelled at a question about an uncovered file.
- (NppSnapshotOutcome)snapshotCoversEverything {
    NppPreferences *p = [NppPreferences shared];
    if (!p.autosaveEnabled || !p.restoreSession || self.editor.sessionSavingDisabled) return NppSnapshotNotUsed;
    [self.editor runAutosavePass];
    NSMutableArray *uncovered = [NSMutableArray array];
    for (NppDocument *doc in self.editor.documents) {
        if (doc.modified && !doc.backupPath) [uncovered addObject:doc];
    }
    if (!uncovered.count) return NppSnapshotCovers;
    return [self.editor confirmClosingDocuments:uncovered] ? NppSnapshotCovers : NppSnapshotCancelled;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (![self.editor confirmDiscardingProjectChanges]) return NO;
    switch ([self snapshotCoversEverything]) {
        case NppSnapshotCovers: self.closingConfirmed = YES; return YES;
        case NppSnapshotCancelled: return NO;
        case NppSnapshotNotUsed: break;
    }
    if (![self.editor confirmClosingDocuments:self.editor.documents]) return NO;
    // What was not saved was declined, not forgotten - and its backup goes
    // with it, or the declined text would be back next launch.
    for (NppDocument *doc in self.editor.documents) {
        if (doc.modified) [self.editor dropBackupOfDocument:doc];
    }
    self.closingConfirmed = YES;
    return YES;
}

- (BOOL)application:(NSApplication *)app openFile:(NSString *)filename {
    if (!self.editor) {
        // Delivered before applicationDidFinishLaunching: has built the
        // editor, which is how AppKit hands over the files an instance was
        // launched with. Kept until there is somewhere to open them.
        if (!self.pendingOpenPaths) self.pendingOpenPaths = [NSMutableArray array];
        [self.pendingOpenPaths addObject:filename];
        return YES;
    }
    // "Always in multi-instance mode" hands the file to a second copy of the app
    // instead of adding a tab here.
    if ([self.editor shouldOpenFilesInNewInstance] && self.editor.documents.count > 0) {
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        config.createsNewApplicationInstance = YES;
        [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:filename]]
                           withApplicationAtURL:[[NSBundle mainBundle] bundleURL]
                                  configuration:config completionHandler:nil];
        return YES;
    }
    NSError *err = nil;
    if ([self.editor openFileAtPath:filename error:&err]) return YES;
    if (err) [[NSAlert alertWithError:err] runModal];
    return NO;
}

- (void)applicationWillTerminate:(NSNotification *)note {
    [[NppPluginHost shared] notifyPlugins:NPPN_SHUTDOWN];
    [[NppAgentServer shared] stop];   // takes its socket file with it
    if ([self automaticUpdateCheckAllowed] && [NppPreferences shared].autoUpdateMode == 2) [self updateCheckAtExit];
    [self rememberFloatingPanels];
    [self.editor rememberPanelState];
    if (self.editor.sessionSavingDisabled) return;
    if ([NppPreferences shared].multiInstanceMode == 2 || [NppPreferences shared].restoreSession) {
        [self.editor saveSessionTo:[self.editor defaultSessionPath] error:NULL];
    }
}

#pragma mark - Menus

- (NSMenuItem *)item:(NSString *)title action:(SEL)sel key:(NSString *)key
               flags:(NSEventModifierFlags)flags menu:(NSMenu *)menu {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:sel keyEquivalent:@""];
    // AppKit's default mask (Command) when none is given; Shift in AppKit's spelling (NppSetMenuKey).
    NppSetMenuKey(mi, key, flags ?: (key.length ? NSEventModifierFlagCommand : 0));
    mi.target = self;
    [menu addItem:mi];
    return mi;
}

- (void)buildMenus {
    NSMenu *bar = [[NSMenu alloc] init];
    NSString *appName = @"NotepadMac";

    // ---- Application menu
    // Named, both of them: an NSMenuItem made with -init is titled "NSMenuItem",
    // and the menu bar shows the first item's submenu title as the application's
    // name - which the localiser would then take for an English text to keep.
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:appName action:nil keyEquivalent:@""];
    [bar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appMenu addItemWithTitle:[@"About " stringByAppendingString:appName]
                       action:@selector(showAbout:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:appName]
                                          action:@selector(hide:) keyEquivalent:@"h"];
    hide.target = NSApp;
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    hideOthers.target = NSApp;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
                                          action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    appItem.submenu = appMenu;

    // ---- File
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [bar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [self item:@"New"      action:@selector(newDocument:) key:@"n" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Open…"    action:@selector(openDocument:) key:@"o" flags:NSEventModifierFlagCommand menu:fileMenu];

    NSMenu *revealMenu = [[NSMenu alloc] initWithTitle:@"Open Containing Folder"];
    [self item:@"Finder" action:@selector(revealInFinder:) key:@"" flags:0 menu:revealMenu];
    [self item:@"Terminal" action:@selector(openInTerminal:) key:@"" flags:0 menu:revealMenu];
    // Upstream's third shell, PowerShell (IDM_FILE_OPEN_POWERSHELL): on a Mac both of its
    // shells are Terminal, so the command is kept - for run_command, macros and a Windows
    // shortcuts.xml - on a hidden item that does what Terminal does.
    NSMenuItem *powerShell = [self item:@"PowerShell" action:@selector(openInTerminal:) key:@"" flags:0 menu:revealMenu];
    powerShell.hidden = YES;
    [self item:@"Folder as Workspace" action:@selector(containingFolderAsWorkspace:) key:@"" flags:0 menu:revealMenu];
    NSMenuItem *revealItem = [fileMenu addItemWithTitle:@"Open Containing Folder" action:nil keyEquivalent:@""];
    revealItem.submenu = revealMenu;
    [self item:@"Open in Default Viewer" action:@selector(openInDefaultViewer:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Open Folder as Workspace…" action:@selector(openFolderAsWorkspace:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Pin Tab" action:@selector(togglePin:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Reload from Disk" action:@selector(reloadDocument:) key:@"r" flags:NSEventModifierFlagCommand menu:fileMenu];

    self.recentMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    recentItem.submenu = self.recentMenu;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NppEditorDocumentsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentsDidChange:)
                                                 name:NppEditorDocumentsDidChangeNotification object:nil];
    [self rebuildRecentMenu];
    [self item:@"Restore Last Closed File" action:@selector(restoreLastClosedFile:) key:@"t"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];

    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Save"     action:@selector(saveDocument:) key:@"s" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Save As…" action:@selector(saveDocumentAs:) key:@"s"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];
    [self item:@"Save a Copy As…" action:@selector(saveCopyAs:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Save All" action:@selector(saveAll:) key:@"s"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:fileMenu];
    [self item:@"Rename…" action:@selector(renameDocument:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Close Tab" action:@selector(closeTab:) key:@"w" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Close All" action:@selector(closeAll:) key:@"w"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:fileMenu];

    NSMenu *closeMulti = [[NSMenu alloc] initWithTitle:@"Close Multiple Documents"];
    [self item:@"Close All but Active Document" action:@selector(closeAllButCurrent:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All to the Left" action:@selector(closeAllToLeft:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All to the Right" action:@selector(closeAllToRight:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All Unchanged" action:@selector(closeAllUnchanged:) key:@"" flags:0 menu:closeMulti];
    [self item:@"Close All but Pinned Documents" action:@selector(closeAllButPinned:) key:@"" flags:0 menu:closeMulti];
    NSMenuItem *closeMultiItem = [fileMenu addItemWithTitle:@"Close Multiple Documents" action:nil keyEquivalent:@""];
    closeMultiItem.submenu = closeMulti;

    [self item:@"Move to Trash" action:@selector(moveToTrash:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Load Session…" action:@selector(loadSession:) key:@"" flags:0 menu:fileMenu];
    [self item:@"Save Session…" action:@selector(saveSession:) key:@"" flags:0 menu:fileMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Print…" action:@selector(printDocument:) key:@"p" flags:NSEventModifierFlagCommand menu:fileMenu];
    [self item:@"Print Now" action:@selector(printNow:) key:@"p"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:fileMenu];
    fileItem.submenu = fileMenu;

    // ---- Edit
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [bar addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [self item:@"Undo" action:@selector(undo:) key:@"z" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Redo" action:@selector(redo:) key:@"z"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Cut"   action:@selector(cutText:) key:@"x" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Copy"  action:@selector(copyText:) key:@"c" flags:NSEventModifierFlagCommand menu:editMenu];
    [self item:@"Paste" action:@selector(pasteText:) key:@"v" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Select All" action:@selector(selectAllText:) key:@"a" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Duplicate Line" action:@selector(duplicateLine:) key:@"d" flags:NSEventModifierFlagCommand menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Line Comment" action:@selector(toggleLineComment:) key:@"/" flags:NSEventModifierFlagCommand menu:editMenu];
    // Option+Cmd+/, not upstream's Ctrl+Shift+Q (Shift+Cmd+Q is the system's Log Out) nor
    // Shift+Cmd+/ (it is Cmd+?, which macOS keeps for the Help menu's search and takes off the item).
    [self item:@"Block Comment" action:@selector(toggleBlockComment:) key:@"/"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:editMenu];
    [self item:@"Delete" action:@selector(deleteSelection:) key:@"" flags:0 menu:editMenu];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[NSMenuItem separatorItem]];

    // --- Insert
    NSMenu *insertMenu = [[NSMenu alloc] initWithTitle:@"Insert"];
    [self item:@"Date Time (short)" action:@selector(insertDateShort:) key:@"" flags:0 menu:insertMenu];
    [self item:@"Date Time (long)" action:@selector(insertDateLong:) key:@"" flags:0 menu:insertMenu];
    [self item:@"Date Time (customized)" action:@selector(insertDateCustom:) key:@"" flags:0 menu:insertMenu];
    [editMenu addItemWithTitle:@"Insert" action:nil keyEquivalent:@""].submenu = insertMenu;

    // --- Copy to Clipboard
    NSMenu *clipMenu = [[NSMenu alloc] initWithTitle:@"Copy to Clipboard"];
    [self item:@"Copy Current Full File path" action:@selector(copyFullPath:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy Current Filename" action:@selector(copyFileName:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy Current Dir. Path" action:@selector(copyDirPath:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy All Filenames" action:@selector(copyAllNames:) key:@"" flags:0 menu:clipMenu];
    [self item:@"Copy All File Paths" action:@selector(copyAllPaths:) key:@"" flags:0 menu:clipMenu];
    [editMenu addItemWithTitle:@"Copy to Clipboard" action:nil keyEquivalent:@""].submenu = clipMenu;

    // --- Indent
    NSMenu *indentMenu = [[NSMenu alloc] initWithTitle:@"Indent"];
    [self item:@"Increase Line Indent" action:@selector(increaseIndent:) key:@"]" flags:NSEventModifierFlagCommand menu:indentMenu];
    [self item:@"Decrease Line Indent" action:@selector(decreaseIndent:) key:@"[" flags:NSEventModifierFlagCommand menu:indentMenu];
    [editMenu addItemWithTitle:@"Indent" action:nil keyEquivalent:@""].submenu = indentMenu;

    // --- Convert Case to
    NSMenu *caseMenu = [[NSMenu alloc] initWithTitle:@"Convert Case to"];
    NSArray *caseTitles = @[@"UPPERCASE", @"lowercase", @"Proper Case", @"Proper Case (blend)",
                            @"Sentence case", @"Sentence case (blend)", @"iNVERT cASE", @"ranDOm CasE"];
    for (NSUInteger i = 0; i < caseTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:caseTitles[i]
                                                    action:@selector(convertCase:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [caseMenu addItem:mi];
    }
    [editMenu addItemWithTitle:@"Convert Case to" action:nil keyEquivalent:@""].submenu = caseMenu;

    // --- Line Operations
    NSMenu *lineMenu = [[NSMenu alloc] initWithTitle:@"Line Operations"];
    [self item:@"Remove Duplicate Lines" action:@selector(removeDupLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Consecutive Duplicate Lines" action:@selector(removeConsecutiveDupLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Split Lines" action:@selector(splitLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Join Lines" action:@selector(joinLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Move Up Current Line" action:@selector(moveLineUp:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Move Down Current Line" action:@selector(moveLineDown:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Empty Lines" action:@selector(removeEmptyLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Remove Empty Lines (Containing Blank characters)" action:@selector(removeBlankLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Insert Blank Line Above Current" action:@selector(blankLineAbove:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Insert Blank Line Below Current" action:@selector(blankLineBelow:) key:@"" flags:0 menu:lineMenu];
    [lineMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Reverse Line Order" action:@selector(reverseLines:) key:@"" flags:0 menu:lineMenu];
    [self item:@"Randomize Line Order" action:@selector(randomizeLines:) key:@"" flags:0 menu:lineMenu];
    NSArray *sortNames = @[@"Lexicographically", @"Lex. Ignoring Case", @"In Locale Order",
                           @"As Integers", @"As Decimals (Comma)", @"As Decimals (Dot)", @"By Length"];
    for (NSUInteger i = 0; i < sortNames.count; ++i) {
        for (int desc = 0; desc < 2; ++desc) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:
                [NSString stringWithFormat:@"Sort Lines %@ %@", sortNames[i], desc ? @"Descending" : @"Ascending"]
                                                        action:@selector(sortLines:) keyEquivalent:@""];
            mi.target = self; mi.tag = (NSInteger)(i * 2 + desc);
            [lineMenu addItem:mi];
        }
    }
    [editMenu addItemWithTitle:@"Line Operations" action:nil keyEquivalent:@""].submenu = lineMenu;

    // --- Comment/Uncomment
    NSMenu *commentMenu = [[NSMenu alloc] initWithTitle:@"Comment/Uncomment"];
    [self item:@"Toggle Single Line Comment" action:@selector(toggleLineComment:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Single Line Comment" action:@selector(setLineComment:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Single Line Uncomment" action:@selector(uncommentLines:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Block Comment" action:@selector(streamComment:) key:@"" flags:0 menu:commentMenu];
    [self item:@"Block Uncomment" action:@selector(streamUncomment:) key:@"" flags:0 menu:commentMenu];
    [editMenu addItemWithTitle:@"Comment/Uncomment" action:nil keyEquivalent:@""].submenu = commentMenu;

    // --- EOL Conversion (Notepad_plus.rc: Edit > EOL Conversion, subMenuId edit-eolConversion)
    NSMenu *eolMenu = [[NSMenu alloc] initWithTitle:@"EOL Conversion"];
    [self item:@"Windows (CR LF)" action:@selector(eolCRLF:) key:@"" flags:0 menu:eolMenu];
    [self item:@"Unix (LF)"       action:@selector(eolLF:) key:@"" flags:0 menu:eolMenu];
    [self item:@"Classic Mac (CR)" action:@selector(eolCR:) key:@"" flags:0 menu:eolMenu];
    NSMenuItem *eolItem = [editMenu addItemWithTitle:@"EOL Conversion" action:nil keyEquivalent:@""];
    eolItem.submenu = eolMenu;
    eolItem.identifier = @"edit-eolConversion";

    // --- Blank Operations
    NSMenu *blankMenu = [[NSMenu alloc] initWithTitle:@"Blank Operations"];
    NSArray *blankTitles = @[@"Trim Trailing Space", @"Trim Leading Space",
                             @"Trim Leading and Trailing Space", @"EOL to Space",
                             @"Trim both and EOL to Space", @"TAB to Space",
                             @"Space to TAB (All)", @"Space to TAB (Leading)"];
    for (NSUInteger i = 0; i < blankTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:blankTitles[i]
                                                    action:@selector(applyTrim:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [blankMenu addItem:mi];
    }
    [editMenu addItemWithTitle:@"Blank Operations" action:nil keyEquivalent:@""].submenu = blankMenu;

    // --- Read-Only
    NSMenu *roMenu = [[NSMenu alloc] initWithTitle:@"Read-Only"];
    [self item:@"Read-Only on Current Document" action:@selector(toggleReadOnly:) key:@"" flags:0 menu:roMenu];
    [self item:@"Read-Only for All Documents" action:@selector(readOnlyAll:) key:@"" flags:0 menu:roMenu];
    [self item:@"Clear Read-Only for All Documents" action:@selector(clearReadOnlyAll:) key:@"" flags:0 menu:roMenu];
    [self item:@"Read-Only Attribute on Disk" action:@selector(toggleSystemReadOnly:) key:@"" flags:0 menu:roMenu];
    [editMenu addItemWithTitle:@"Read-Only" action:nil keyEquivalent:@""].submenu = roMenu;

    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Begin/End Select" action:@selector(beginEndSelect:) key:@"" flags:0 menu:editMenu];
    [self item:@"Begin/End Select in Column Mode" action:@selector(beginEndSelectColumn:) key:@"" flags:0 menu:editMenu];

    NSArray *matchTitles = @[@"Ignore Case & Whole Word", @"Match Case Only",
                             @"Match Whole Word Only", @"Match Case & Whole Word"];
    NSMenu *msAll = [[NSMenu alloc] initWithTitle:@"Multi-select All"];
    NSMenu *msNext = [[NSMenu alloc] initWithTitle:@"Multi-select Next"];
    for (NSUInteger i = 0; i < matchTitles.count; ++i) {
        NSMenuItem *a1 = [[NSMenuItem alloc] initWithTitle:matchTitles[i]
                                                    action:@selector(multiSelectAll:) keyEquivalent:@""];
        a1.target = self; a1.tag = (NSInteger)i; [msAll addItem:a1];
        NSMenuItem *a2 = [[NSMenuItem alloc] initWithTitle:matchTitles[i]
                                                    action:@selector(multiSelectNext:) keyEquivalent:@""];
        a2.target = self; a2.tag = (NSInteger)i; [msNext addItem:a2];
    }
    [editMenu addItemWithTitle:@"Multi-select All" action:nil keyEquivalent:@""].submenu = msAll;
    [editMenu addItemWithTitle:@"Multi-select Next" action:nil keyEquivalent:@""].submenu = msNext;
    [self item:@"Undo the Latest Added Multi-Select" action:@selector(multiSelectUndo:) key:@"" flags:0 menu:editMenu];
    [self item:@"Skip Current & Go to Next Multi-select" action:@selector(multiSelectSkip:) key:@"" flags:0 menu:editMenu];

    [editMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Column Mode…" action:@selector(columnModeTip:) key:@"" flags:0 menu:editMenu];
    [self item:@"Column Editor…" action:@selector(columnEditor:) key:@"" flags:0 menu:editMenu];
    [self item:@"Character Panel" action:@selector(toggleCharacterPanel:) key:@"" flags:0 menu:editMenu];
    [self item:@"Clipboard History" action:@selector(toggleClipboardHistory:) key:@"" flags:0 menu:editMenu];

    NSMenu *acMenu = [[NSMenu alloc] initWithTitle:@"Auto-Completion"];
    // Upstream's order and keys: Ctrl+Space, Ctrl+Enter, Ctrl+Shift+Space,
    // Ctrl+Alt+Space. Cmd+Space is Spotlight's, so the space keys keep Control.
    [self item:@"Function Completion" action:@selector(functionCompletion:) key:@" "
         flags:NSEventModifierFlagControl menu:acMenu];
    [self item:@"Word Completion" action:@selector(showAutoComplete:) key:@"\r"
         flags:NSEventModifierFlagCommand menu:acMenu];
    [self item:@"Function Parameters Hint" action:@selector(callTip:) key:@" "
         flags:NSEventModifierFlagControl | NSEventModifierFlagShift menu:acMenu];
    [self item:@"Function Parameters Previous Hint" action:@selector(callTipPrev:) key:@"" flags:0 menu:acMenu];
    [self item:@"Function Parameters Next Hint" action:@selector(callTipNext:) key:@"" flags:0 menu:acMenu];
    [self item:@"Path Completion" action:@selector(pathCompletion:) key:@" "
         flags:NSEventModifierFlagControl | NSEventModifierFlagOption menu:acMenu];
    [editMenu addItemWithTitle:@"Auto-Completion" action:nil keyEquivalent:@""].submenu = acMenu;

    NSMenu *pasteMenu = [[NSMenu alloc] initWithTitle:@"Paste Special"];
    [self item:@"Paste HTML Content" action:@selector(pasteHTML:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Paste RTF Content" action:@selector(pasteRTF:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Copy Binary Content" action:@selector(copyBinary:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Cut Binary Content" action:@selector(cutBinary:) key:@"" flags:0 menu:pasteMenu];
    [self item:@"Paste Binary Content" action:@selector(pasteBinaryContent:) key:@"" flags:0 menu:pasteMenu];
    [editMenu addItemWithTitle:@"Paste Special" action:nil keyEquivalent:@""].submenu = pasteMenu;
    // A Mac reads pictures: the clipboard's image OCR'd at the caret, and a
    // whole image or PDF file into a new document.
    [self item:@"Paste Image as Text" action:@selector(pasteImageAsText:) key:@"" flags:0 menu:editMenu];
    [self item:@"Recognize Text in File…" action:@selector(recognizeTextInFile:) key:@"" flags:0 menu:editMenu];
    // The selected formula's value, or the one ending at the caret, after its "=".
    [self item:@"Calculate" action:@selector(calculateFormula:) key:@"=" flags:NSEventModifierFlagCommand menu:editMenu];
    // The context menu's Selected Numbers in the menu bar too, for a shortcut or an agent's run_command.
    NSMenu *numbersMenu = [[NSMenu alloc] initWithTitle:@"Selected Numbers"];
    [self item:@"Sum" action:@selector(numbersInsertSum:) key:@"" flags:0 menu:numbersMenu];
    [self item:@"Average" action:@selector(numbersInsertAverage:) key:@"" flags:0 menu:numbersMenu];
    [self item:@"Minimum" action:@selector(numbersInsertMinimum:) key:@"" flags:0 menu:numbersMenu];
    [self item:@"Maximum" action:@selector(numbersInsertMaximum:) key:@"" flags:0 menu:numbersMenu];
    [self item:@"Count" action:@selector(numbersInsertCount:) key:@"" flags:0 menu:numbersMenu];
    [numbersMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Sort Ascending" action:@selector(numbersSortAscending:) key:@"" flags:0 menu:numbersMenu];
    [self item:@"Sort Descending" action:@selector(numbersSortDescending:) key:@"" flags:0 menu:numbersMenu];
    [editMenu addItemWithTitle:@"Selected Numbers" action:nil keyEquivalent:@""].submenu = numbersMenu;

    NSMenu *selMenu = [[NSMenu alloc] initWithTitle:@"On Selection"];
    [self item:@"Open File" action:@selector(openSelectedFile:) key:@"" flags:0 menu:selMenu];
    [self item:@"Open Containing Folder in Finder" action:@selector(revealSelectedFile:) key:@"" flags:0 menu:selMenu];
    [self item:@"Redact Selection" action:@selector(redactSelection:) key:@"" flags:0 menu:selMenu];
    [self item:@"Search on Internet" action:@selector(searchOnInternet:) key:@"" flags:0 menu:selMenu];
    [self item:@"Change Search Engine…" action:@selector(changeSearchEngine:) key:@"" flags:0 menu:selMenu];
    [editMenu addItemWithTitle:@"On Selection" action:nil keyEquivalent:@""].submenu = selMenu;

    editItem.submenu = editMenu;

    // ---- Search
    NSMenuItem *searchItem = [[NSMenuItem alloc] init];
    [bar addItem:searchItem];
    NSMenu *searchMenu = [[NSMenu alloc] initWithTitle:@"Search"];
    [self item:@"Find…"      action:@selector(showFind:) key:@"f" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Next"  action:@selector(findNext:) key:@"g" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Find Previous" action:@selector(findPrevious:) key:@"g"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Replace…"   action:@selector(showReplace:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Go to…" action:@selector(goToLine:) key:@"l" flags:NSEventModifierFlagCommand menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Bookmark" action:@selector(toggleBookmark:) key:@"b" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Next Bookmark" action:@selector(nextBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Previous Bookmark" action:@selector(previousBookmark:) key:@"b"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Find in Files…" action:@selector(findInFiles:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Search Results Window" action:@selector(focusSearchResults:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Next Search Result" action:@selector(nextSearchResult:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Previous Search Result" action:@selector(prevSearchResult:) key:@"" flags:0 menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Select and Find Next" action:@selector(selectAndFindNext:) key:@"e" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Select and Find Previous" action:@selector(selectAndFindPrev:) key:@"e"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    [self item:@"Find (Volatile) Next" action:@selector(volatileFindNext:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Find (Volatile) Previous" action:@selector(volatileFindPrev:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Incremental Search" action:@selector(incrementalSearch:) key:@"i" flags:NSEventModifierFlagCommand menu:searchMenu];
    [searchMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Go to Matching Brace" action:@selector(goToMatchingBrace:) key:@"m" flags:NSEventModifierFlagCommand menu:searchMenu];
    [self item:@"Select All In-between {} [] or ()" action:@selector(selectBetweenBraces:) key:@"m"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:searchMenu];
    // The Find dialog on its Mark tab, as IDM_SEARCH_MARK opens it (FindReplaceDlg MARK_DLG).
    [self item:@"Mark…" action:@selector(showMarkTab:) key:@"" flags:0 menu:searchMenu];
    [self item:@"Find characters in range…" action:@selector(findCharsInRange:) key:@"" flags:0 menu:searchMenu];

    // --- marker style submenus, five styles plus the Find Mark style
    NSArray *styleNames = @[@"Using 1st Style", @"Using 2nd Style", @"Using 3rd Style",
                            @"Using 4th Style", @"Using 5th Style"];
    NSMenu *markAllMenu = [[NSMenu alloc] initWithTitle:@"Style All Occurrences of Token"];
    NSMenu *markOneMenu = [[NSMenu alloc] initWithTitle:@"Style One Token"];
    NSMenu *clearMenu   = [[NSMenu alloc] initWithTitle:@"Clear Style"];
    NSMenu *upMenu      = [[NSMenu alloc] initWithTitle:@"Jump Up"];
    NSMenu *downMenu    = [[NSMenu alloc] initWithTitle:@"Jump Down"];
    NSMenu *copyMenu    = [[NSMenu alloc] initWithTitle:@"Copy Styled Text"];
    for (NSUInteger i = 0; i < styleNames.count; ++i) {
        struct { NSMenu *menu; SEL sel; NSString *title; } rows[] = {
            {markAllMenu, @selector(markAllStyle:), styleNames[i]},
            {markOneMenu, @selector(markOneStyle:), styleNames[i]},
            {clearMenu,   @selector(clearStyle:),   [NSString stringWithFormat:@"Clear %@ Style", Ordinal(i + 1)]},
            {upMenu,      @selector(jumpUpStyle:),  [NSString stringWithFormat:@"%@ Style", Ordinal(i + 1)]},
            {downMenu,    @selector(jumpDownStyle:),[NSString stringWithFormat:@"%@ Style", Ordinal(i + 1)]},
            {copyMenu,    @selector(copyStyle:),    [NSString stringWithFormat:@"%@ Style", Ordinal(i + 1)]},
        };
        for (size_t r = 0; r < sizeof(rows)/sizeof(rows[0]); ++r) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:rows[r].title action:rows[r].sel keyEquivalent:@""];
            mi.target = self; mi.tag = (NSInteger)i;
            [rows[r].menu addItem:mi];
        }
    }
    [self item:@"Clear all Styles" action:@selector(clearAllStyles:) key:@"" flags:0 menu:clearMenu];
    for (NSMenu *menu in @[upMenu, downMenu]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"Find Mark Style"
                                                    action:(menu == upMenu ? @selector(jumpUpStyle:) : @selector(jumpDownStyle:))
                                             keyEquivalent:@""];
        mi.target = self; mi.tag = NPPMAC_STYLE_COUNT;
        [menu addItem:mi];
    }
    NSMenuItem *allStyles = [[NSMenuItem alloc] initWithTitle:@"All Styles" action:@selector(copyAllStyles:) keyEquivalent:@""];
    allStyles.target = self;
    [copyMenu addItem:allStyles];
    NSMenuItem *markedClip = [[NSMenuItem alloc] initWithTitle:@"Find Mark Style" action:@selector(copyStyle:) keyEquivalent:@""];
    markedClip.target = self; markedClip.tag = NPPMAC_STYLE_COUNT;
    [copyMenu addItem:markedClip];

    [searchMenu addItem:[NSMenuItem separatorItem]];
    [searchMenu addItemWithTitle:@"Style All Occurrences of Token" action:nil keyEquivalent:@""].submenu = markAllMenu;
    [searchMenu addItemWithTitle:@"Style One Token" action:nil keyEquivalent:@""].submenu = markOneMenu;
    [searchMenu addItemWithTitle:@"Clear Style" action:nil keyEquivalent:@""].submenu = clearMenu;
    [searchMenu addItemWithTitle:@"Jump Up" action:nil keyEquivalent:@""].submenu = upMenu;
    [searchMenu addItemWithTitle:@"Jump Down" action:nil keyEquivalent:@""].submenu = downMenu;
    [searchMenu addItemWithTitle:@"Copy Styled Text" action:nil keyEquivalent:@""].submenu = copyMenu;

    // --- bookmark line operations
    NSMenu *bmMenu = [[NSMenu alloc] initWithTitle:@"Bookmark"];
    // Notepad_plus.rc: Clear All Bookmarks leads the Bookmark submenu (IDM_SEARCH_CLEAR_BOOKMARKS).
    [self item:@"Clear All Bookmarks" action:@selector(clearBookmarks:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Cut Bookmarked Lines" action:@selector(cutMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Copy Bookmarked Lines" action:@selector(copyMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Paste to (Replace) Bookmarked Lines" action:@selector(pasteMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Remove Bookmarked Lines" action:@selector(removeMarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Remove Non-Bookmarked Lines" action:@selector(removeUnmarkedLines:) key:@"" flags:0 menu:bmMenu];
    [self item:@"Inverse Bookmarks" action:@selector(inverseBookmarks:) key:@"" flags:0 menu:bmMenu];
    [searchMenu addItemWithTitle:@"Bookmark" action:nil keyEquivalent:@""].submenu = bmMenu;

    // --- change history
    NSMenu *chMenu = [[NSMenu alloc] initWithTitle:@"Change History"];
    [self item:@"Go to Next Change" action:@selector(nextChange:) key:@"" flags:0 menu:chMenu];
    [self item:@"Go to Previous Change" action:@selector(prevChange:) key:@"" flags:0 menu:chMenu];
    [self item:@"Clear Change History" action:@selector(clearChangeHistory:) key:@"" flags:0 menu:chMenu];
    [searchMenu addItemWithTitle:@"Change History" action:nil keyEquivalent:@""].submenu = chMenu;

    searchItem.submenu = searchMenu;

    // ---- View
    NSMenuItem *viewItem = [[NSMenuItem alloc] init];
    [bar addItem:viewItem];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    // Notepad_plus.rc: View > Zoom (subMenuId view-zoom), Synchronize Across Views in it.
    NSMenu *zoomMenu = [[NSMenu alloc] initWithTitle:@"Zoom"];
    [self item:@"Zoom In"    action:@selector(zoomIn:) key:@"+" flags:NSEventModifierFlagCommand menu:zoomMenu];
    [self item:@"Zoom Out"   action:@selector(zoomOut:) key:@"-" flags:NSEventModifierFlagCommand menu:zoomMenu];
    [self item:@"Actual Size" action:@selector(zoomReset:) key:@"0" flags:NSEventModifierFlagCommand menu:zoomMenu];
    [zoomMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Synchronize Across Views" action:@selector(toggleSyncZoom:) key:@"" flags:0 menu:zoomMenu];
    NSMenuItem *zoomItem = [viewMenu addItemWithTitle:@"Zoom" action:nil keyEquivalent:@""];
    zoomItem.submenu = zoomMenu;
    zoomItem.identifier = @"view-zoom";
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Word Wrap" action:@selector(toggleWordWrap:) key:@"w"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Toggle Insert/Overtype" action:@selector(toggleOvertype:) key:@"" flags:0
          menu:viewMenu];
    [self item:@"Show Whitespace" action:@selector(toggleWhitespace:) key:@"i"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Toggle Fold" action:@selector(toggleFold:) key:@"." flags:NSEventModifierFlagCommand menu:viewMenu];
    [self item:@"Fold All" action:@selector(foldAll:) key:@"." 
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:viewMenu];
    [self item:@"Unfold All" action:@selector(unfoldAll:) key:@"."
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:viewMenu];
    [self item:@"Fold Current Level" action:@selector(foldCurrent:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Unfold Current Level" action:@selector(unfoldCurrent:) key:@"" flags:0 menu:viewMenu];

    NSMenu *foldLevelMenu = [[NSMenu alloc] initWithTitle:@"Fold Level"];
    NSMenu *unfoldLevelMenu = [[NSMenu alloc] initWithTitle:@"Unfold Level"];
    for (NSInteger lvl = 1; lvl <= 8; ++lvl) {
        NSMenuItem *f = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)lvl]
                                                   action:@selector(foldLevel:) keyEquivalent:@""];
        f.target = self; f.tag = lvl; [foldLevelMenu addItem:f];
        NSMenuItem *u = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld", (long)lvl]
                                                   action:@selector(unfoldLevel:) keyEquivalent:@""];
        u.target = self; u.tag = lvl; [unfoldLevelMenu addItem:u];
    }
    [viewMenu addItemWithTitle:@"Fold Level" action:nil keyEquivalent:@""].submenu = foldLevelMenu;
    [viewMenu addItemWithTitle:@"Unfold Level" action:nil keyEquivalent:@""].submenu = unfoldLevelMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *symbolMenu = [[NSMenu alloc] initWithTitle:@"Show Symbol"];
    // Upstream's order (Notepad_plus.rc, Show Symbol); the tag is the NppSymbol.
    struct { NSString *title; NppSymbol symbol; } symbols[] = {
        {@"Show Space and Tab", NppSymbolWhitespace}, {@"Show End of Line", NppSymbolEOL},
        {@"Show Non-Printing Characters", NppSymbolNonPrinting},
        {@"Show Control Characters & Unicode EOL", NppSymbolControlAndUnicodeEOL},
        {@"Show All Characters", NppSymbolAll}, {nil, NppSymbolAll},
        {@"Show Indent Guide", NppSymbolIndentGuide}, {@"Show Wrap Symbol", NppSymbolWrap},
    };
    for (auto &s : symbols) {
        if (!s.title) { [symbolMenu addItem:[NSMenuItem separatorItem]]; continue; }
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:s.title action:@selector(toggleSymbol:) keyEquivalent:@""];
        mi.target = self; mi.tag = s.symbol;
        [symbolMenu addItem:mi];
    }
    [viewMenu addItemWithTitle:@"Show Symbol" action:nil keyEquivalent:@""].submenu = symbolMenu;

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Hide Lines" action:@selector(hideLines:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Show All Hidden Lines" action:@selector(showHiddenLines:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Summary…" action:@selector(showSummary:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Monitoring (tail -f)" action:@selector(toggleMonitoring:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Always on Top" action:@selector(toggleAlwaysOnTop:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Toggle Full Screen Mode" action:@selector(toggleFullScreenMode:) key:@"f"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagControl menu:viewMenu];
    [self item:@"Post-It" action:@selector(togglePostIt:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Distraction Free Mode" action:@selector(toggleDistractionFree:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Folder as Workspace" action:@selector(toggleFileBrowser:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Document List" action:@selector(toggleDocumentList:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Document Map" action:@selector(toggleDocumentMap:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Function List" action:@selector(toggleFunctionList:) key:@"" flags:0 menu:viewMenu];
    NSMenu *projMenu = [[NSMenu alloc] initWithTitle:@"Project Panels"];
    for (NSInteger i = 1; i <= 3; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Project Panel %ld", (long)i]
                                                    action:@selector(toggleProjectPanel:) keyEquivalent:@""];
        mi.target = self; mi.tag = i;
        [projMenu addItem:mi];
    }
    NSMenuItem *projItem = [viewMenu addItemWithTitle:@"Project Panels" action:nil keyEquivalent:@""];
    projItem.submenu = projMenu;
    projItem.identifier = @"view-project";   // english.xml names it "Project"

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Focus on Another View" action:@selector(focusOtherView:) key:@"" flags:0 menu:viewMenu];
    NSMenu *moveViewMenu = [[NSMenu alloc] initWithTitle:@"Move/Clone Current Document"];
    [self item:@"Move to Other View" action:@selector(moveToOtherView:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Clone to Other View" action:@selector(cloneToOtherView:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Move to New Instance" action:@selector(moveToNewInstance:) key:@"" flags:0 menu:moveViewMenu];
    [self item:@"Open in New Instance" action:@selector(openInNewInstance:) key:@"" flags:0 menu:moveViewMenu];
    [viewMenu addItemWithTitle:@"Move/Clone Current Document" action:nil keyEquivalent:@""].submenu = moveViewMenu;
    [self item:@"Synchronize Vertical Scrolling" action:@selector(toggleSyncV:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Synchronize Horizontal Scrolling" action:@selector(toggleSyncH:) key:@"" flags:0 menu:viewMenu];

    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Text Direction RTL" action:@selector(textRTL:) key:@"" flags:0 menu:viewMenu];
    [self item:@"Text Direction LTR" action:@selector(textLTR:) key:@"" flags:0 menu:viewMenu];

    NSMenu *browserMenu = [[NSMenu alloc] initWithTitle:@"View Current File in"];
    NSArray *browsers = @[@[@"Firefox", @"org.mozilla.firefox"],
                          @[@"Chrome", @"com.google.Chrome"],
                          @[@"Edge", @"com.microsoft.edgemac"],
                          @[@"Safari", @"com.apple.Safari"]];
    for (NSArray *b in browsers) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:b[0] action:@selector(viewInBrowser:) keyEquivalent:@""];
        mi.target = self; mi.representedObject = b[1];
        [browserMenu addItem:mi];
    }
    [viewMenu addItemWithTitle:@"View Current File in" action:nil keyEquivalent:@""].submenu = browserMenu;

    // --- Tab navigation and colouring
    NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"Tab"];
    for (NSInteger i = 1; i <= 9; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@ Tab", Ordinal((NSUInteger)i)]
                                                    action:@selector(goToTabNumber:)
                                             keyEquivalent:[NSString stringWithFormat:@"%ld", (long)i]];
        mi.target = self; mi.tag = i;
        mi.keyEquivalentModifierMask = NSEventModifierFlagCommand;
        [tabMenu addItem:mi];
    }
    [tabMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"First Tab" action:@selector(firstTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Last Tab" action:@selector(lastTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Next Tab" action:@selector(nextTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Previous Tab" action:@selector(previousTab:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move Tab Forward" action:@selector(moveTabForward:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move Tab Backward" action:@selector(moveTabBackward:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move to Start" action:@selector(moveTabToStart:) key:@"" flags:0 menu:tabMenu];
    [self item:@"Move to End" action:@selector(moveTabToEnd:) key:@"" flags:0 menu:tabMenu];
    [tabMenu addItem:[NSMenuItem separatorItem]];
    for (NSInteger c = 1; c <= 5; ++c) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Apply Color %ld", (long)c]
                                                    action:@selector(applyTabColour:) keyEquivalent:@""];
        mi.target = self; mi.tag = c;
        [tabMenu addItem:mi];
    }
    NSMenuItem *noColour = [[NSMenuItem alloc] initWithTitle:@"Remove Color"
                                                      action:@selector(applyTabColour:) keyEquivalent:@""];
    noColour.target = self; noColour.tag = 0;
    [tabMenu addItem:noColour];
    [viewMenu addItemWithTitle:@"Tab" action:nil keyEquivalent:@""].submenu = tabMenu;

    viewItem.submenu = viewMenu;

    // ---- Encoding
    NSMenuItem *encItem = [[NSMenuItem alloc] init];
    [bar addItem:encItem];
    NSMenu *encMenu = [[NSMenu alloc] initWithTitle:@"Encoding"];
    struct { NSString *title; NSStringEncoding enc; BOOL bom; } encodings[] = {
        {@"UTF-8",           NSUTF8StringEncoding,               NO},
        {@"UTF-8-BOM",       NSUTF8StringEncoding,               YES},
        {@"UTF-16 LE BOM",   NSUTF16LittleEndianStringEncoding,  YES},
        {@"UTF-16 BE BOM",   NSUTF16BigEndianStringEncoding,     YES},
        {@"ANSI",            NSISOLatin1StringEncoding,          NO},
    };
    for (size_t i = 0; i < sizeof(encodings)/sizeof(encodings[0]); ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:encodings[i].title
                                                    action:@selector(pickEncoding:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = (NSInteger)i;
        [encMenu addItem:mi];
    }

    [encMenu addItem:[NSMenuItem separatorItem]];
    // "Encode in": reinterpret the bytes through another charset.
    NSMenu *charsetMenu = [[NSMenu alloc] initWithTitle:@"Character sets"];
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    NSMutableArray *groupOrder = [NSMutableArray array];
    for (int i = 0; i < kNppCharsetCount; ++i) {
        NSString *group = @(kNppCharsets[i].group);
        NSMenu *sub = groups[group];
        if (!sub) {
            sub = [[NSMenu alloc] initWithTitle:group];
            groups[group] = sub;
            [groupOrder addObject:group];
        }
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@(kNppCharsets[i].label)
                                                    action:@selector(encodeInCharset:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = i;
        [sub addItem:mi];
    }
    for (NSString *group in groupOrder) {
        [charsetMenu addItemWithTitle:group action:nil keyEquivalent:@""].submenu = groups[group];
    }
    [encMenu addItemWithTitle:@"Character sets" action:nil keyEquivalent:@""].submenu = charsetMenu;

    [encMenu addItem:[NSMenuItem separatorItem]];
    // "Convert to": re-encode the text itself.
    struct { NSString *title; SEL sel; } conversions[] = {
        {@"Convert to ANSI",             @selector(convertToANSI:)},
        {@"Convert to UTF-8",            @selector(convertToUTF8:)},
        {@"Convert to UTF-8-BOM",        @selector(convertToUTF8BOM:)},
        {@"Convert to UTF-16 BE BOM",    @selector(convertToUTF16BE:)},
        {@"Convert to UTF-16 LE BOM",    @selector(convertToUTF16LE:)},
    };
    for (size_t i = 0; i < sizeof(conversions)/sizeof(conversions[0]); ++i) {
        [self item:conversions[i].title action:conversions[i].sel key:@"" flags:0 menu:encMenu];
    }
    encItem.submenu = encMenu;

    // ---- Language (populated from Notepad++'s langs.model.xml)
    NSMenuItem *langItem = [[NSMenuItem alloc] init];
    [bar addItem:langItem];
    NSMenu *langMenu = [[NSMenu alloc] initWithTitle:@"Language"];
    self.languageMenu = langMenu;
    [self fillBuiltInLanguageItems:langMenu];
    [langMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *udlMenu = [[NSMenu alloc] initWithTitle:@"User Defined Language"];
    [self item:@"Define your language…" action:@selector(defineUserLanguage:) key:@"" flags:0 menu:udlMenu];
    [self item:@"Open User Defined Language folder…" action:@selector(openUDLFolder:) key:@"" flags:0 menu:udlMenu];
    NSMenuItem *udlSite = [[NSMenuItem alloc] initWithTitle:@"Notepad++ User Defined Languages Collection"
                                                     action:@selector(openHelpLink:) keyEquivalent:@""];
    udlSite.target = self;
    udlSite.representedObject = @"https://github.com/notepad-plus-plus/userDefinedLanguages";
    [udlMenu addItem:udlSite];
    [langMenu addItemWithTitle:@"User Defined Language" action:nil keyEquivalent:@""].submenu = udlMenu;
    // Notepad_plus.rc: "User-Defined" (IDM_LANG_USER) follows the submenu.
    NSMenuItem *plainUser = [[NSMenuItem alloc] initWithTitle:@"User-Defined" action:@selector(pickLanguage:) keyEquivalent:@""];
    plainUser.target = self;
    plainUser.representedObject = @"udf";
    [langMenu addItem:plainUser];
    langItem.submenu = langMenu;

    // ---- Tools
    NSMenuItem *toolsItem = [[NSMenuItem alloc] init];
    [bar addItem:toolsItem];
    NSMenu *toolsMenu = [[NSMenu alloc] initWithTitle:@"Tools"];
    // Hashes: Notepad++'s four digests first and as it has them, then the ones
    // the port adds, then the password hashes, which take settings and a window.
    NSMenu *hashesMenu = [[NSMenu alloc] initWithTitle:@"Hashes"];
    for (NSInteger d = 0; d < NppDigestCount; ++d) {
        NSString *digestName = [EditorController nameOfDigest:(NppDigest)d];
        NSMenu *sub = [[NSMenu alloc] initWithTitle:digestName];
        struct { NSString *title; SEL sel; } rows[] = {
            {@"Generate…",                            @selector(hashGenerate:)},
            {@"Generate from files…",                 @selector(hashFromFiles:)},
            {@"Generate from selection into clipboard", @selector(hashToClipboard:)},
        };
        for (size_t r = 0; r < sizeof(rows)/sizeof(rows[0]); ++r) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:rows[r].title
                                                        action:rows[r].sel keyEquivalent:@""];
            mi.target = self; mi.tag = d;
            [sub addItem:mi];
        }
        [hashesMenu addItemWithTitle:digestName action:nil keyEquivalent:@""].submenu = sub;
    }
    // The password hashes, with the same three commands as the digests have.
    [hashesMenu addItem:[NSMenuItem separatorItem]];
    NSArray<NSString *> *passwordHashes = @[@"bcrypt", @"scrypt", @"Argon2", @"PBKDF2"];      // in NppPasswordHash's order
    for (NSUInteger k = 0; k < passwordHashes.count; ++k) {
        NSMenu *sub = [[NSMenu alloc] initWithTitle:passwordHashes[k]];
        struct { NSString *title; SEL sel; } rows[] = {
            {@"Generate…",                            @selector(passwordHashGenerate:)},
            {@"Generate from files…",                 @selector(passwordHashFromFiles:)},
            {@"Generate from selection into clipboard", @selector(passwordHashToClipboard:)},
        };
        for (size_t r = 0; r < sizeof(rows)/sizeof(rows[0]); ++r) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:rows[r].title action:rows[r].sel keyEquivalent:@""];
            mi.target = self; mi.tag = (NSInteger)k;
            [sub addItem:mi];
        }
        [hashesMenu addItemWithTitle:passwordHashes[k] action:nil keyEquivalent:@""].submenu = sub;
    }
    [toolsMenu addItemWithTitle:@"Hashes" action:nil keyEquivalent:@""].submenu = hashesMenu;

    NSMenu *baseMenu = [[NSMenu alloc] initWithTitle:@"Base"];
    struct { NSString *title; NppBaseEncoding encoding; } bases[] = {
        {@"Base64…", NppBase64}, {@"Base58…", NppBase58}, {@"Base32…", NppBase32},
    };
    for (size_t k = 0; k < sizeof(bases)/sizeof(bases[0]); ++k) {
        NSMenuItem *mi = [baseMenu addItemWithTitle:bases[k].title action:@selector(showBase:) keyEquivalent:@""];
        mi.target = self; mi.tag = bases[k].encoding;
    }
    [toolsMenu addItemWithTitle:@"Base" action:nil keyEquivalent:@""].submenu = baseMenu;
    [self item:@"Password Generator" action:@selector(showPasswordGenerator:) key:@"" flags:0 menu:toolsMenu];
    [self item:@"HTTP Request" action:@selector(showHttpRequest:) key:@"" flags:0 menu:toolsMenu];
    [toolsMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"QR Code from Selection" action:@selector(qrFromSelection:) key:@"" flags:0 menu:toolsMenu];
    [self item:@"Read QR Code from Clipboard" action:@selector(readQRFromClipboard:) key:@"" flags:0 menu:toolsMenu];
    [toolsMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Install Command Line Tool" action:@selector(installCommandLineTool:) key:@"" flags:0 menu:toolsMenu];
    toolsItem.submenu = toolsMenu;

    // ---- Macro
    NSMenuItem *macroItem = [[NSMenuItem alloc] init];
    [bar addItem:macroItem];
    NSMenu *macroMenu = [[NSMenu alloc] initWithTitle:@"Macro"];
    [self item:@"Start Recording" action:@selector(macroStart:) key:@"" flags:0 menu:macroMenu];
    [self item:@"Stop Recording" action:@selector(macroStop:) key:@"" flags:0 menu:macroMenu];
    [self item:@"Playback" action:@selector(macroPlay:) key:@"" flags:0 menu:macroMenu];
    [self item:@"Save Current Recorded Macro…" action:@selector(macroSave:) key:@"" flags:0 menu:macroMenu];
    [self item:@"Run a Macro Multiple Times…" action:@selector(macroRunMultiple:) key:@"" flags:0 menu:macroMenu];
    macroItem.submenu = macroMenu;
    self.macroMenu = macroMenu;
    self.fixedMacroItemCount = macroMenu.numberOfItems;
    [self rebuildMacroMenu];

    // ---- Run
    NSMenuItem *runItem = [[NSMenuItem alloc] init];
    [bar addItem:runItem];
    NSMenu *runMenu = [[NSMenu alloc] initWithTitle:@"Run"];
    [self item:@"Run…" action:@selector(runCommand:) key:@"r"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:runMenu];
    [self item:@"Save Current Command…" action:@selector(saveRunCommand:) key:@"" flags:0 menu:runMenu];
    [self item:@"Manage Saved Commands…" action:@selector(manageRunCommands:) key:@"" flags:0 menu:runMenu];
    [self item:@"Show Console" action:@selector(toggleConsole:) key:@"" flags:0 menu:runMenu];
    [runMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Validate shortcuts" action:@selector(validateShortcuts:) key:@"" flags:0 menu:runMenu];
    [self item:@"Open Plugins Folder…" action:@selector(openPluginsFolder:) key:@"" flags:0 menu:runMenu];
    runItem.submenu = runMenu;
    self.runMenu = runMenu;
    // The saved commands sit below a separator that is added with them, so the
    // menu can be rebuilt without disturbing the fixed entries above it.
    self.fixedRunItemCount = runMenu.numberOfItems;
    [self rebuildRunMenu];

    // ---- Plugins: the functionality Notepad++ gets from its popular plugins,
    // built in rather than loaded, since its plugin ABI is Windows-only.
    NSMenuItem *pluginsItem = [[NSMenuItem alloc] init];
    [bar addItem:pluginsItem];
    NSMenu *pluginsMenu = [[NSMenu alloc] initWithTitle:@"Plugins"];

    NSMenu *jsonMenu = [[NSMenu alloc] initWithTitle:@"JSON"];
    [self item:@"Format" action:@selector(jsonFormat:) key:@"j"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:jsonMenu];
    [self item:@"Compact" action:@selector(jsonCompact:) key:@"" flags:0 menu:jsonMenu];
    [self item:@"Sort Keys" action:@selector(jsonSort:) key:@"" flags:0 menu:jsonMenu];
    [self item:@"Validate" action:@selector(jsonValidate:) key:@"" flags:0 menu:jsonMenu];
    [self item:@"Show JSON Tree" action:@selector(jsonTree:) key:@"" flags:0 menu:jsonMenu];
    [pluginsMenu addItemWithTitle:@"JSON" action:nil keyEquivalent:@""].submenu = jsonMenu;

    NSMenu *compareMenu = [[NSMenu alloc] initWithTitle:@"Compare"];
    [self item:@"Set as First to Compare" action:@selector(compareSetFirst:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Compare" action:@selector(compareRun:) key:@"d"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagOption menu:compareMenu];
    [self item:@"Compare with File…" action:@selector(compareWithFile:) key:@"" flags:0 menu:compareMenu];
    [compareMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Next Difference" action:@selector(compareNext:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Previous Difference" action:@selector(comparePrevious:) key:@"" flags:0 menu:compareMenu];
    [self item:@"First Difference" action:@selector(compareFirst:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Last Difference" action:@selector(compareLast:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Compare Summary" action:@selector(compareSummary:) key:@"" flags:0 menu:compareMenu];
    [compareMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Ignore Case" action:@selector(compareToggleIgnoreCase:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Ignore Spaces" action:@selector(compareToggleIgnoreSpaces:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Ignore Empty Lines" action:@selector(compareToggleIgnoreEmpty:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Detect Moves" action:@selector(compareToggleDetectMoves:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Detect Character Differences" action:@selector(compareToggleCharDiffs:) key:@"" flags:0 menu:compareMenu];
    [compareMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Clear Active Compare" action:@selector(compareClear:) key:@"" flags:0 menu:compareMenu];
    [self item:@"Clear All Compares" action:@selector(compareClearAll:) key:@"" flags:0 menu:compareMenu];
    [pluginsMenu addItemWithTitle:@"Compare" action:nil keyEquivalent:@""].submenu = compareMenu;

    NSMenu *xmlMenu = [[NSMenu alloc] initWithTitle:@"XML"];
    [self item:@"Pretty Print" action:@selector(xmlPretty:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Pretty Print — Indent Attributes" action:@selector(xmlPrettyAttributes:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Linearize" action:@selector(xmlLinearize:) key:@"" flags:0 menu:xmlMenu];
    [xmlMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Check XML Syntax Now" action:@selector(xmlCheckSyntax:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Validate Against Schema…" action:@selector(xmlValidateSchema:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Validate Against DTD" action:@selector(xmlValidateDTD:) key:@"" flags:0 menu:xmlMenu];
    [xmlMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Evaluate XPath Expression…" action:@selector(xmlXPath:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Current XML Path" action:@selector(xmlCurrentPath:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Current XML Path with Predicates" action:@selector(xmlCurrentPathPredicates:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Apply XSL Transformation…" action:@selector(xmlTransform:) key:@"" flags:0 menu:xmlMenu];
    [xmlMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Escape Characters in Selection" action:@selector(xmlEscape:) key:@"" flags:0 menu:xmlMenu];
    [self item:@"Unescape Characters in Selection" action:@selector(xmlUnescape:) key:@"" flags:0 menu:xmlMenu];
    [pluginsMenu addItemWithTitle:@"XML" action:nil keyEquivalent:@""].submenu = xmlMenu;

    // Git, the port's own (Windows has plugins for it): the panel, diffs and
    // history, the everyday operations, branches, and the remote in the console.
    NSMenu *gitMenu = [[NSMenu alloc] initWithTitle:@"Git"];
    [self item:@"Git Panel" action:@selector(gitTogglePanel:) key:@"" flags:0 menu:gitMenu];
    [gitMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Compare with HEAD" action:@selector(gitCompareWithHead:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Clear Active Compare" action:@selector(compareClear:) key:@"" flags:0 menu:gitMenu];   // the way out of the comparison, beside the way in
    [self item:@"Blame" action:@selector(gitBlame:) key:@"" flags:0 menu:gitMenu];
    [self item:@"File History" action:@selector(gitFileHistory:) key:@"" flags:0 menu:gitMenu];
    [gitMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Stage File" action:@selector(gitStage:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Unstage File" action:@selector(gitUnstage:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Revert Change at Caret to HEAD" action:@selector(gitRevertChange:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Discard Changes in File…" action:@selector(gitDiscard:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Commit…" action:@selector(gitCommit:) key:@"" flags:0 menu:gitMenu];
    [gitMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *branchMenu = [[NSMenu alloc] initWithTitle:@"Switch Branch"];
    branchMenu.identifier = @"NppGitBranches";
    branchMenu.delegate = self;
    [gitMenu addItemWithTitle:@"Switch Branch" action:nil keyEquivalent:@""].submenu = branchMenu;
    [self item:@"New Branch…" action:@selector(gitNewBranch:) key:@"" flags:0 menu:gitMenu];
    [gitMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Fetch" action:@selector(gitFetch:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Pull" action:@selector(gitPull:) key:@"" flags:0 menu:gitMenu];
    [self item:@"Push" action:@selector(gitPush:) key:@"" flags:0 menu:gitMenu];
    [gitMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Refresh Git Status" action:@selector(gitRefresh:) key:@"" flags:0 menu:gitMenu];
    [pluginsMenu addItemWithTitle:@"Git" action:nil keyEquivalent:@""].submenu = gitMenu;

    NSMenu *ftpMenu = [[NSMenu alloc] initWithTitle:@"FTP"];
    [self item:@"Connections…" action:@selector(ftpProfiles:) key:@"" flags:0 menu:ftpMenu];
    [self item:@"Connect…" action:@selector(ftpConnect:) key:@"" flags:0 menu:ftpMenu];
    [self item:@"Disconnect" action:@selector(ftpDisconnect:) key:@"" flags:0 menu:ftpMenu];
    [ftpMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Show Remote Files" action:@selector(ftpBrowse:) key:@"" flags:0 menu:ftpMenu];
    [self item:@"Upload Current File" action:@selector(ftpUpload:) key:@"" flags:0 menu:ftpMenu];
    [pluginsMenu addItemWithTitle:@"FTP" action:nil keyEquivalent:@""].submenu = ftpMenu;

    // MIME Tools, with the plugin's own items in the plugin's own order.
    NSMenu *mimeMenu = [[NSMenu alloc] initWithTitle:@"MIME Tools"];
    // The plugin's Base64 items are deliberately not here: Base64 lives in
    // Tools > Base already, and one thing lives in one place.
    struct { NSString *title; SEL sel; NSInteger tag; } mimeRows[] = {
        {@"Quoted-printable Encode",       @selector(mimeQuotedPrintableEncode:), 0},
        {@"Quoted-printable Decode",       @selector(mimeQuotedPrintableDecode:), 0},
        {nil, NULL, 0},
        {@"URL Encode (RFC1738)",          @selector(mimeUrlEncode:),          0},
        {@"URL Encode (RFC1738) by line",  @selector(mimeUrlEncode:),          1},
        {@"URL Encode (Extended)",         @selector(mimeUrlEncode:),          2},
        {@"URL Encode (Extended) by line", @selector(mimeUrlEncode:),          3},
        {@"URL Encode (Full)",             @selector(mimeUrlEncode:),          4},
        {@"URL Encode (Full) by line",     @selector(mimeUrlEncode:),          5},
        {@"URL Decode",                    @selector(mimeUrlDecode:),          0},
        {nil, NULL, 0},
        {@"SAML Decode",                   @selector(mimeSamlDecode:),         0},
    };
    for (size_t r = 0; r < sizeof(mimeRows)/sizeof(mimeRows[0]); ++r) {
        if (!mimeRows[r].title) { [mimeMenu addItem:[NSMenuItem separatorItem]]; continue; }
        NSMenuItem *mi = [self item:mimeRows[r].title action:mimeRows[r].sel key:@"" flags:0 menu:mimeMenu];
        mi.tag = mimeRows[r].tag;
    }
    [pluginsMenu addItemWithTitle:@"MIME Tools" action:nil keyEquivalent:@""].submenu = mimeMenu;

    // Converter, with the plugin's items (its Edit Configuration File became
    // the converterInsertSpace/Uppercase/HexPerLine defaults).
    NSMenu *converterMenu = [[NSMenu alloc] initWithTitle:@"Converter"];
    [self item:@"ASCII -> HEX" action:@selector(converterAsciiToHex:) key:@"" flags:0 menu:converterMenu];
    [self item:@"HEX -> ASCII" action:@selector(converterHexToAscii:) key:@"" flags:0 menu:converterMenu];
    [converterMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Conversion Panel" action:@selector(showConversionPanel:) key:@"" flags:0 menu:converterMenu];
    [pluginsMenu addItemWithTitle:@"Converter" action:nil keyEquivalent:@""].submenu = converterMenu;

    // NppExport's commands, under the plainer name Export.
    NSMenu *exportMenu = [[NSMenu alloc] initWithTitle:@"Export"];
    [self item:@"Export to RTF" action:@selector(exportToRTF:) key:@"" flags:0 menu:exportMenu];
    [self item:@"Export to HTML" action:@selector(exportToHTML:) key:@"" flags:0 menu:exportMenu];
    [exportMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Copy RTF to clipboard" action:@selector(copyRTFToClipboard:) key:@"" flags:0 menu:exportMenu];
    [self item:@"Copy HTML to clipboard" action:@selector(copyHTMLToClipboard:) key:@"" flags:0 menu:exportMenu];
    [self item:@"Copy all formats to clipboard" action:@selector(copyAllFormatsToClipboard:) key:@"" flags:0 menu:exportMenu];
    [pluginsMenu addItemWithTitle:@"Export" action:nil keyEquivalent:@""].submenu = exportMenu;

    // Spell Check (DSpellCheck's job, on the system engine).
    NSMenu *spellMenu = [[NSMenu alloc] initWithTitle:@"Spell Check"];
    [self item:@"Spell Check Document Automatically" action:@selector(toggleSpellCheck:) key:@"" flags:0 menu:spellMenu];
    NSMenu *spellLangMenu = [[NSMenu alloc] initWithTitle:@"Language"];
    spellLangMenu.delegate = self;
    spellLangMenu.identifier = @"NppSpellLanguages";
    [spellMenu addItemWithTitle:@"Language" action:nil keyEquivalent:@""].submenu = spellLangMenu;
    [pluginsMenu addItemWithTitle:@"Spell Check" action:nil keyEquivalent:@""].submenu = spellMenu;

    // MarkdownViewer++'s job, one command: the preview panel.
    [self item:@"Markdown Preview" action:@selector(toggleMarkdownPreview:) key:@"" flags:0 menu:pluginsMenu];

    // NppExec's scripts; its saved scripts follow, rebuilt as they change.
    NSMenu *execMenu = [[NSMenu alloc] initWithTitle:@"NppExec"];
    NSMenuItem *execute = [self item:@"Execute NppExec Script…" action:@selector(executeScriptDialog:) key:@"" flags:0 menu:execMenu];
    execute.keyEquivalent = [NSString stringWithFormat:@"%C", (unichar)NSF6FunctionKey];
    execute.keyEquivalentModifierMask = 0;
    NSMenuItem *again = [self item:@"Execute Previous NppExec Script" action:@selector(executePreviousScript:) key:@"" flags:0 menu:execMenu];
    again.keyEquivalent = [NSString stringWithFormat:@"%C", (unichar)NSF6FunctionKey];
    again.keyEquivalentModifierMask = NSEventModifierFlagControl;
    [self item:@"Stop Running NppExec Script" action:@selector(stopScript:) key:@"" flags:0 menu:execMenu];
    [self item:@"Show NppExec Console" action:@selector(toggleConsole:) key:@"" flags:0 menu:execMenu];
    [pluginsMenu addItemWithTitle:@"NppExec" action:nil keyEquivalent:@""].submenu = execMenu;
    self.execMenu = execMenu;
    self.fixedExecItemCount = execMenu.numberOfItems;
    [self rebuildExecMenu];

    [pluginsMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Open Plugins Folder…" action:@selector(openPluginsFolder:) key:@"" flags:0 menu:pluginsMenu];
    self.pluginsMenu = pluginsMenu;
    pluginsItem.submenu = pluginsMenu;

    // ---- Settings
    NSMenuItem *settingsItem = [[NSMenuItem alloc] init];
    [bar addItem:settingsItem];
    NSMenu *settingsMenu = [[NSMenu alloc] initWithTitle:@"Settings"];
    [self item:@"Preferences…" action:@selector(showPreferences:) key:@"," flags:NSEventModifierFlagCommand menu:settingsMenu];
    [self item:@"Style Configurator…" action:@selector(showStyleConfigurator:) key:@"" flags:0 menu:settingsMenu];
    [self item:@"Shortcut Mapper…" action:@selector(showShortcutMapper:) key:@"" flags:0 menu:settingsMenu];
    [settingsMenu addItem:[NSMenuItem separatorItem]];
    NSMenu *importMenu = [[NSMenu alloc] initWithTitle:@"Import"];
    [self item:@"Import plugin(s)…" action:@selector(importPlugins:) key:@"" flags:0 menu:importMenu];
    [self item:@"Import style theme(s)…" action:@selector(importThemes:) key:@"" flags:0 menu:importMenu];
    [settingsMenu addItemWithTitle:@"Import" action:nil keyEquivalent:@""].submenu = importMenu;
    [self item:@"Edit Popup ContextMenu" action:@selector(editContextMenu:) key:@"" flags:0 menu:settingsMenu];
    settingsItem.submenu = settingsMenu;

    // ---- Window
    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [bar addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [self item:@"Next Tab" action:@selector(nextTab:) key:@"]"
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    [self item:@"Previous Tab" action:@selector(previousTab:) key:@"["
         flags:NSEventModifierFlagCommand | NSEventModifierFlagShift menu:windowMenu];
    [windowMenu addItem:[NSMenuItem separatorItem]];

    NSMenu *sortMenu = [[NSMenu alloc] initWithTitle:@"Sort By"];
    NSArray *sortTitles = @[@"Name A to Z", @"Name Z to A", @"Path A to Z", @"Path Z to A",
                            @"Type A to Z", @"Type Z to A",
                            @"Content Length Ascending", @"Content Length Descending",
                            @"Modified Time Ascending", @"Modified Time Descending"];
    for (NSUInteger i = 0; i < sortTitles.count; ++i) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:sortTitles[i]
                                                    action:@selector(sortTabs:) keyEquivalent:@""];
        mi.target = self; mi.tag = (NSInteger)i;
        [sortMenu addItem:mi];
    }
    [windowMenu addItemWithTitle:@"Sort By" action:nil keyEquivalent:@""].submenu = sortMenu;
    [self item:@"Windows…" action:@selector(showWindowsList:) key:@"" flags:0 menu:windowMenu];
    [self item:@"Recent Window" action:@selector(recentWindow:) key:@"" flags:0 menu:windowMenu];
    // Upstream's tab bar ends in a ▼ that lists the open documents (IDM_DROPLIST_LIST); this tab bar
    // has no such button, so the command - for run_command, macros and shortcuts - is a hidden item
    // showing the same list as Windows….
    [self item:@"Open Documents" action:@selector(showWindowsList:) key:@"" flags:0 menu:windowMenu].hidden = YES;
    windowItem.submenu = windowMenu;

    // ---- Help
    NSMenuItem *helpItem = [[NSMenuItem alloc] init];
    [bar addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    // Upstream's four commands, with their names (and so their translations), leading to this port's own
    // places: the Mac version is released and supported from its repository, and a question about it taken
    // to Notepad++'s site or forum would reach people who did not make it. The manual alone is upstream's:
    // it describes the behaviour this application follows, and there is no other.
    NSArray *links = @[@[@"Notepad++ Home", [NppProjectAddress(@"") stringByAppendingString:@"#readme"]],
                       @[@"Notepad++ Project Page", NppProjectAddress(@"")],
                       @[@"Notepad++ Online User Manual", @"https://npp-user-manual.org/"],
                       @[@"Notepad++ Community (Forum)", NppProjectAddress(@"discussions")]];
    for (NSArray *link in links) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:link[0] action:@selector(openHelpLink:) keyEquivalent:@""];
        mi.target = self; mi.representedObject = link[1];
        [helpMenu addItem:mi];
    }
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Command Line Arguments…" action:@selector(showCommandLineArguments:) key:@"" flags:0 menu:helpMenu];
    [self item:@"Debug Info…" action:@selector(showDebugInfo:) key:@"" flags:0 menu:helpMenu];
    [self item:@"Check for Updates" action:@selector(checkForUpdates:) key:@"" flags:0 menu:helpMenu];
    [self item:@"Set Updater Proxy…" action:@selector(setUpdaterProxy:) key:@"" flags:0 menu:helpMenu];
    [self item:@"About NotepadMac" action:@selector(showAbout:) key:@"" flags:0 menu:helpMenu];
    helpItem.submenu = helpMenu;
    NSApp.helpMenu = helpMenu;
    NSApp.windowsMenu = windowMenu;

    NSApp.mainMenu = bar;
    // The keys the menus were built with are the defaults; shortcuts.xml
    // (or the older preference) says what the user changed.
    self.shortcutStore = [[NppShortcutStore alloc] initWithEditor:self.editor];
    [self.shortcutStore captureMenuDefaults];
    [self.shortcutStore load];
    // What load imported from a Windows shortcuts.xml (macros, Run commands) joins the
    // menus on this launch too: the change notification is not observed yet here.
    [self savedCommandsChanged:nil];
    [self.editor rebuildContextMenu];
}

#pragma mark - Appearance and toolbar

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (![keyPath isEqualToString:@"effectiveAppearance"]) return;
    if ([NppPreferences shared].appearanceMode != 0) return;   // only when following the system
    [[NppPreferences shared] applyToEditor:self.editor];
}

- (void)applyToolbarPreferences {
    NppPreferences *p = [NppPreferences shared];
    self.toolbar.displayMode = p.toolbarDisplayMode;
    self.toolbar.iconSize = p.toolbarIconSize;
    self.toolbar.visible = p.showToolbar;
    [self.toolbar reloadIcons];
}

#pragma mark - JSON

- (void)jsonFormat:(id)sender  { if (![self.editor formatJSONDocument]) [self reportJSONProblem]; }
- (void)jsonCompact:(id)sender { if (![self.editor compactJSONDocument]) [self reportJSONProblem]; }
- (void)jsonSort:(id)sender    { if (![self.editor sortJSONDocument]) [self reportJSONProblem]; }

#pragma mark Mac extras: OCR, QR, the command line

- (void)calculateFormula:(id)sender { [self.editor calculateFormula]; }
- (void)numbersInsert:(NppNumberSetValue)which { if (![self.editor insertNumberSetValue:which]) NppBeep(); }
- (void)numbersInsertSum:(id)sender     { [self numbersInsert:NppNumberSetSum]; }
- (void)numbersInsertAverage:(id)sender { [self numbersInsert:NppNumberSetAverage]; }
- (void)numbersInsertMinimum:(id)sender { [self numbersInsert:NppNumberSetMinimum]; }
- (void)numbersInsertMaximum:(id)sender { [self numbersInsert:NppNumberSetMaximum]; }
- (void)numbersInsertCount:(id)sender   { [self numbersInsert:NppNumberSetCount]; }
- (void)numbersSortAscending:(id)sender  { if (![self.editor sortSelectedNumbersAscending:YES]) NppBeep(); }
- (void)numbersSortDescending:(id)sender { if (![self.editor sortSelectedNumbersAscending:NO]) NppBeep(); }

- (void)pasteImageAsText:(id)sender {
    if (![self.editor pasteImageAsText]) [self reportMimeProblem:@"No text was found in the clipboard's image."];
}

- (void)recognizeTextInFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"png", @"jpg", @"jpeg", @"tiff", @"tif", @"heic",
                               @"webp", @"gif", @"bmp", @"pdf"];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSString *path = panel.URL.path;
    // A many-page PDF takes a while; the recognizing is off the main thread,
    // the document opens back on it.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *text = [EditorController textRecognizedInFileAt:path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!text.length) { [self reportMimeProblem:@"No text was found in the file."]; return; }
            [self.editor newDocument];
            [self.editor.sci setString:text];
            [self.editor refreshChrome];
        });
    });
}

- (void)qrFromSelection:(id)sender {
    NSString *text = [self.editor.sci selectedString];
    if (!text.length) { NppBeep(); return; }
    if (![EditorController qrImageFromText:text side:520]) {
        [self reportMimeProblem:@"The selection is too long for a QR code."];
        return;
    }
    [[NppQrWindow shared] showForText:text];
}

- (void)readQRFromClipboard:(id)sender {
    if (![self.editor insertTextFromClipboardQR])
        [self reportMimeProblem:@"No QR code was found in the clipboard's image."];
}

- (void)installCommandLineTool:(id)sender {
    NSString *helper = [[NSBundle mainBundle].bundlePath
                        stringByAppendingPathComponent:@"Contents/Helpers/nppmac"];
    NSString *link = @"/usr/local/bin/nppmac";
    // The end-to-end suite installs into a folder of its own, never the real one.
    NSString *e2eDir = NSProcessInfo.processInfo.environment[@"NPPMAC_E2E_CLI_DIR"];
    if (getenv("NPPMAC_E2E") && e2eDir.length) link = [e2eDir stringByAppendingPathComponent:@"nppmac"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    [fm removeItemAtPath:link error:NULL];
    BOOL made = [fm createSymbolicLinkAtPath:link withDestinationPath:helper error:&error];
    NSAlert *alert = [[NSAlert alloc] init];
    if (made) {
        alert.messageText = @"The nppmac command is installed.";
        alert.informativeText = @"nppmac file.txt — opens a file\n"
                                @"nppmac +42 file.txt — opens it at line 42\n"
                                @"something | nppmac - — reads standard input";
    } else {
        alert.messageText = @"Could not write to /usr/local/bin.";
        alert.informativeText = [NSString stringWithFormat:
            @"Run this in Terminal:\n\nsudo ln -sf \"%@\" %@", helper, link];
    }
    [alert runModal];
}

/// What the nppmac tool asks for: files (folders open as workspaces), each
/// with a line to land on.
- (void)cliRequest:(NSNotification *)note {
    NSArray *files = note.userInfo[@"files"];
    if (![files isKindOfClass:[NSArray class]]) return;
    for (id entry in files) {
        NSString *path = [entry isKindOfClass:[NSDictionary class]] ? entry[@"path"] : nil;
        if (![path isKindOfClass:[NSString class]] || !path.length) continue;
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) continue;
        if (isDirectory) { [self.editor openFolderAsWorkspace:path]; continue; }
        if (![self.editor openFileAtPath:path error:NULL]) continue;
        long line = [entry[@"line"] respondsToSelector:@selector(longValue)] ? [entry[@"line"] longValue] : 0;
        if (line > 0) {
            [self.editor.sci message:SCI_GOTOLINE wParam:(uptr_t)(line - 1) lParam:0];
            [self.editor.sci message:SCI_VERTICALCENTRECARET wParam:0 lParam:0];
        }
    }
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark Plugins > Spell Check

- (void)toggleSpellCheck:(NSMenuItem *)sender {
    NppPreferences *prefs = [NppPreferences shared];
    prefs.spellCheckEnabled = !prefs.spellCheckEnabled;
    [self.editor spellCheckNow];
}

- (void)chooseSpellLanguage:(NSMenuItem *)sender {
    [NppPreferences shared].spellCheckLanguage = sender.representedObject ?: @"";
    [self.editor spellCheckNow];
}

/// The Language submenu is built when opened: the system's dictionaries can
/// change under a running application.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if ([menu.identifier isEqualToString:@"NppGitBranches"]) { [self fillBranchMenu:menu]; return; }
    if (![menu.identifier isEqualToString:@"NppSpellLanguages"]) return;
    [menu removeAllItems];
    NSString *chosen = [NppPreferences shared].spellCheckLanguage;
    NSMenuItem *automatic = [menu addItemWithTitle:@"Automatic" action:@selector(chooseSpellLanguage:) keyEquivalent:@""];
    automatic.target = self;
    automatic.representedObject = @"";
    automatic.state = chosen.length ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:[NSMenuItem separatorItem]];
    for (NSString *identifier in [NSSpellChecker sharedSpellChecker].availableLanguages) {
        NSString *shown = [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier value:identifier]
                          ?: identifier;
        NSMenuItem *item = [menu addItemWithTitle:shown action:@selector(chooseSpellLanguage:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = identifier;
        item.state = [identifier isEqualToString:chosen] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

#pragma mark Plugins > Git

/// The branches of the current document's repository, the checked-out one ticked.
- (void)fillBranchMenu:(NSMenu *)menu {
    [menu removeAllItems];
    NSString *root = [self.editor gitRootOfCurrentDocument];
    if (!root) {
        NSMenuItem *none = [menu addItemWithTitle:NppL(@"The file is not in a Git repository") action:nil keyEquivalent:@""];
        none.enabled = NO;
        return;
    }
    NSString *current = [NppGit branchOfRepository:root ahead:NULL behind:NULL];
    for (NSString *name in [NppGit branchesOfRepository:root]) {
        NSMenuItem *item = [menu addItemWithTitle:name action:@selector(gitSwitchBranch:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = name;
        item.state = [name isEqualToString:current] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)gitReport:(BOOL)ok {
    if (ok || !self.editor.gitLastError.length) return;
    [self.editor.console showWithoutFocus];
    [self.editor.console appendText:[NSString stringWithFormat:@"[git] %@\n", self.editor.gitLastError]];
}

- (void)gitTogglePanel:(id)sender { [[self.editor gitPanel] toggle]; }
- (void)gitCompareWithHead:(id)sender { [self gitReport:[self.editor gitCompareWithHead]]; }
- (void)gitBlame:(id)sender { [self gitReport:[self.editor gitBlame]]; }
- (void)gitFileHistory:(id)sender { [self gitReport:[self.editor gitFileHistory]]; }
- (void)gitStage:(id)sender { [self gitReport:[self.editor gitStageCurrent]]; }
- (void)gitUnstage:(id)sender { [self gitReport:[self.editor gitUnstageCurrent]]; }
- (void)gitDiscard:(id)sender { [self gitReport:[self.editor gitDiscardCurrent]]; }
- (void)gitRevertChange:(id)sender { [self gitReport:[self.editor gitRevertChangeAtCaret]]; }
- (void)gitCommit:(id)sender { [[NppCommitWindow shared] showForEditor:self.editor]; }
- (void)gitSwitchBranch:(id)sender { [self gitReport:[self.editor gitCheckoutBranch:[sender representedObject]]]; }
- (void)gitNewBranch:(id)sender {
    NSString *name = [self promptForString:NppL(@"New branch name:") default:@""];
    if (name) [self gitReport:[self.editor gitCreateBranch:name]];
}
- (void)gitFetch:(id)sender { [self.editor gitFetch]; }
- (void)gitPull:(id)sender { [self.editor gitPull]; }
- (void)gitPush:(id)sender { [self.editor gitPush]; }
- (void)gitRefresh:(id)sender { [NppGit forgetRepositoryRoots]; [self.editor gitRefreshState]; }

#pragma mark Plugins > Export

- (void)exportStyledAsRTF:(BOOL)rtf {
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *stem = self.editor.currentDocument.displayName.stringByDeletingPathExtension ?: @"Untitled";
    panel.nameFieldStringValue = [stem stringByAppendingPathExtension:rtf ? @"rtf" : @"html"];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSRange range = [self.editor exportRange];
    NSData *data = rtf ? [self.editor exportRTFInRange:range]
                       : [[self.editor exportHTMLInRange:range] dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&err]) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)exportToRTF:(id)sender  { [self exportStyledAsRTF:YES]; }
- (void)exportToHTML:(id)sender { [self exportStyledAsRTF:NO]; }
- (void)copyRTFToClipboard:(id)sender  { [self.editor exportToClipboardRTF:YES HTML:NO]; }
- (void)copyHTMLToClipboard:(id)sender { [self.editor exportToClipboardRTF:NO HTML:YES]; }
- (void)copyAllFormatsToClipboard:(id)sender { [self.editor exportToClipboardRTF:YES HTML:YES]; }

#pragma mark Plugins > Converter

- (void)converterAsciiToHex:(id)sender {
    NppPreferences *prefs = [NppPreferences shared];
    int eolMode = (int)[self.editor.sci message:SCI_GETEOLMODE wParam:0 lParam:0];
    NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
    [self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController converterHexFromText:text
                                          insertSpace:prefs.converterInsertSpace
                                            uppercase:prefs.converterUppercase
                                    charactersPerLine:(NSUInteger)MAX(prefs.converterHexPerLine, 0)
                                                  eol:eol];
    }];
}

- (void)converterHexToAscii:(id)sender {
    if (![self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController converterTextFromHex:text];
    }]) [self reportMimeProblem:@"Hex format is not conformed"];
}

- (void)showConversionPanel:(id)sender {
    NppConverterWindow *window = [NppConverterWindow shared];
    __weak __typeof__(self) weakSelf = self;
    window.insert = ^(NSString *text) {
        [weakSelf.editor.sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    };
    [window show];
}

#pragma mark Plugins > MIME Tools

- (void)mimeQuotedPrintableEncode:(id)sender {
    [self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController mimeQuotedPrintableEncode:text];
    }];
}

- (void)mimeQuotedPrintableDecode:(id)sender {
    if (![self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController mimeQuotedPrintableDecode:text];
    }]) [self reportMimeProblem:@"The selection is not valid Quoted-printable."];
}

- (void)mimeUrlEncode:(NSMenuItem *)sender {
    NppUrlEncodeMethod method = (NppUrlEncodeMethod)(sender.tag / 2);
    BOOL byLine = sender.tag % 2 == 1;
    [self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController mimeUrlEncode:text method:method byLine:byLine];
    }];
}

- (void)mimeUrlDecode:(id)sender {
    [self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController mimeUrlDecode:text];
    }];
}

- (void)mimeSamlDecode:(id)sender {
    if (![self.editor mimeTransformSelection:^NSString *(NSString *text) {
        return [EditorController mimeSamlDecode:text];
    }]) [self reportMimeProblem:@"The selection is not a SAML message."];
}

- (void)reportMimeProblem:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    [alert runModal];
}

- (void)reportJSONProblem {
    NppJsonError *error = [self.editor validateJSONDocument];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"This document is not valid JSON.";
    alert.informativeText = error.line >= 0
        ? [NSString stringWithFormat:@"Line %ld, column %ld.\n\n%@",
           (long)error.line + 1, (long)error.column + 1, error.message]
        : (error.message ?: @"");
    [alert runModal];
}

- (void)jsonValidate:(id)sender {
    NppJsonError *error = [self.editor validateJSONDocument];
    NSAlert *alert = [[NSAlert alloc] init];
    if (!error) {
        alert.messageText = @"Valid JSON.";
    } else {
        alert.messageText = @"Invalid JSON.";
        alert.informativeText = error.line >= 0
            ? [NSString stringWithFormat:@"Line %ld, column %ld.\n\n%@",
               (long)error.line + 1, (long)error.column + 1, error.message]
            : (error.message ?: @"");
    }
    [alert runModal];
}

- (void)jsonTree:(id)sender {
    NSArray *tree = [self.editor jsonTree];
    if (!tree.count) { [self reportJSONProblem]; return; }

    if (!self.jsonTreePanel) {
        NSRect frame = NSMakeRect(0, 0, 460, 500);
        self.jsonTreePanel = [[NppPanel alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
              backing:NSBackingStoreBuffered defer:YES];
        self.jsonTreePanel.title = @"JSON Tree";
        self.jsonTreePanel.releasedWhenClosed = NO;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
        scroll.hasVerticalScroller = YES;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.jsonTreeText = [[NSTextView alloc] initWithFrame:frame];
        self.jsonTreeText.editable = NO;
        self.jsonTreeText.font = [NSFont fontWithName:@"Menlo" size:11];
        scroll.documentView = self.jsonTreeText;
        self.jsonTreePanel.contentView = scroll;
    }

    NSMutableString *rendered = [NSMutableString string];
    for (NSDictionary *node in tree) {
        [rendered appendFormat:@"%@ = %@\n", node[@"path"], node[@"value"]];
    }
    self.jsonTreeText.string = rendered;
    [self.jsonTreePanel makeKeyAndOrderFront:nil];
}

#pragma mark - Compare

- (void)compareSetFirst:(id)sender {
    [self.editor setFirstToCompare];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Set as the first file to compare.";
    alert.informativeText = [self.editor firstToCompare] ?: @"";
    [alert runModal];
}

- (void)compareRun:(id)sender {
    if (![self.editor compareWithFirst]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Nothing to compare with.";
        alert.informativeText = @"Choose \"Set as First to Compare\" on one file, "
                                @"then run Compare on the other.";
        [alert runModal];
        return;
    }
    [self presentText:[self.editor compareSummary] title:@"Compare"];
}

- (void)compareWithFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    if ([self.editor compareWithFileAtPath:panel.URL.path]) {
        [self presentText:[self.editor compareSummary] title:@"Compare"];
    }
}

- (void)compareNext:(id)sender     { [self.editor goToDiff:1]; }
- (void)comparePrevious:(id)sender { [self.editor goToDiff:-1]; }
- (void)compareFirst:(id)sender    { [self.editor goToFirstDiff]; }
- (void)compareLast:(id)sender     { [self.editor goToLastDiff]; }
- (void)compareClear:(id)sender    { [self.editor clearActiveCompare]; }
- (void)compareClearAll:(id)sender { [self.editor clearAllCompares]; }

- (void)compareSummary:(id)sender {
    [self presentText:[self.editor compareSummary] title:@"Compare"];
}

- (void)compareToggleIgnoreCase:(id)sender {
    self.editor.compareIgnoreCase = !self.editor.compareIgnoreCase;
}
- (void)compareToggleIgnoreSpaces:(id)sender {
    self.editor.compareIgnoreSpaces = !self.editor.compareIgnoreSpaces;
}
- (void)compareToggleIgnoreEmpty:(id)sender {
    self.editor.compareIgnoreEmptyLines = !self.editor.compareIgnoreEmptyLines;
    if ([self.editor compareActive]) [self.editor compareRefreshNow];
}
- (void)compareToggleDetectMoves:(id)sender {
    self.editor.compareDetectMoves = !self.editor.compareDetectMoves;
    if ([self.editor compareActive]) [self.editor compareRefreshNow];
}
- (void)compareToggleCharDiffs:(id)sender {
    self.editor.compareCharDiffs = !self.editor.compareCharDiffs;
    if ([self.editor compareActive]) [self.editor compareRefreshNow];
}

#pragma mark - XML

- (void)reportXMLError:(NppXmlError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    if (!error) {
        alert.messageText = @"The document is valid XML.";
    } else {
        alert.messageText = title;
        alert.informativeText = error.line >= 0
            ? [NSString stringWithFormat:@"Line %ld, column %ld.\n\n%@",
               (long)error.line + 1, (long)error.column + 1, error.message]
            : (error.message ?: @"");
    }
    [alert runModal];
}

- (void)xmlPretty:(id)sender {
    if (![self.editor prettyPrintXMLDocument:NppXmlPrettyDefault]) {
        [self reportXMLError:[self.editor checkXMLSyntaxOfDocument] title:@"Cannot format this document."];
    }
}

- (void)xmlPrettyAttributes:(id)sender {
    if (![self.editor prettyPrintXMLDocument:NppXmlPrettyAttributes]) {
        [self reportXMLError:[self.editor checkXMLSyntaxOfDocument] title:@"Cannot format this document."];
    }
}

- (void)xmlLinearize:(id)sender {
    if (![self.editor linearizeXMLDocument]) {
        [self reportXMLError:[self.editor checkXMLSyntaxOfDocument] title:@"Cannot linearize this document."];
    }
}

- (void)xmlCheckSyntax:(id)sender {
    [self reportXMLError:[self.editor checkXMLSyntaxOfDocument] title:@"The document is not well formed."];
}

- (void)xmlValidateDTD:(id)sender {
    NppXmlError *error = [EditorController validateXMLAgainstInternalDTD:
                          [self.editor.sci string] ?: @""];
    [self reportXMLError:error title:@"The document does not match its DTD."];
}

- (void)xmlValidateSchema:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.title = @"Choose an XSD schema";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSString *schema = [NSString stringWithContentsOfFile:panel.URL.path
                                                 encoding:NSUTF8StringEncoding error:NULL];
    if (!schema) { NppBeep(); return; }
    NppXmlError *error = [EditorController validateXML:([self.editor.sci string] ?: @"")
                                         againstSchema:schema];
    [self reportXMLError:error title:@"The document does not match the schema."];
}

- (void)xmlXPath:(id)sender {
    NSString *expression = [self promptForString:@"XPath expression" default:@"//*"];
    if (!expression.length) return;
    NSString *failure = nil;
    NSArray *results = [EditorController evaluateXPath:expression
                                                onText:([self.editor.sci string] ?: @"")
                                                 error:&failure];
    if (!results) { [self presentText:failure ?: @"No result." title:@"XPath"]; return; }
    [self presentText:results.count
        ? [NSString stringWithFormat:@"%lu result(s):\n\n%@", (unsigned long)results.count,
           [results componentsJoinedByString:@"\n"]]
        : @"The expression matched nothing."
                title:@"XPath"];
}

- (void)xmlCurrentPath:(id)sender {
    NSString *path = [self.editor xmlPathAtCaretWithPredicates:NO];
    [self presentText:path ?: @"The current node cannot be resolved." title:@"Current XML Path"];
}

- (void)xmlCurrentPathPredicates:(id)sender {
    NSString *path = [self.editor xmlPathAtCaretWithPredicates:YES];
    [self presentText:path ?: @"The current node cannot be resolved." title:@"Current XML Path"];
}

- (void)xmlTransform:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.title = @"Choose an XSL stylesheet";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSString *sheet = [NSString stringWithContentsOfFile:panel.URL.path
                                                encoding:NSUTF8StringEncoding error:NULL];
    if (!sheet) { NppBeep(); return; }

    NSString *failure = nil;
    NSString *result = [EditorController applyXSL:sheet
                                           toText:([self.editor.sci string] ?: @"") error:&failure];
    if (!result) { [self presentText:failure ?: @"The transformation failed." title:@"XSL"]; return; }
    // The result opens as a new document, leaving the source untouched.
    [self.editor newDocument];
    [self.editor.sci setString:result];
    [self.editor refreshChrome];
}

- (void)xmlEscape:(id)sender   { [self.editor escapeSelectionForXML:YES]; }
- (void)xmlUnescape:(id)sender { [self.editor escapeSelectionForXML:NO]; }

#pragma mark - FTP

- (void)ftpProfiles:(id)sender {
    NSMutableArray *names = [NSMutableArray array];
    for (NppFtpProfile *p in [self.editor ftpProfiles]) {
        [names addObject:[NSString stringWithFormat:@"%@ (%@@%@)", p.name, p.username, p.host]];
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"FTP connections";
    alert.informativeText = names.count ? [names componentsJoinedByString:@"\n"]
                                        : @"No connections saved yet.";
    [alert addButtonWithTitle:@"Add…"];
    [alert addButtonWithTitle:@"Close"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NppFtpProfile *profile = [[NppFtpProfile alloc] init];
    profile.name = [self promptForString:@"Connection name" default:@"server"];
    if (!profile.name.length) return;
    profile.host = [self promptForString:@"Host" default:@""];
    if (!profile.host.length) return;
    NSString *protocol = [self promptForString:@"Protocol: ftp, ftps or sftp" default:@"ftp"];
    profile.protocol = [protocol hasPrefix:@"sftp"] ? NppFtpSFTP
                     : [protocol hasPrefix:@"ftps"] ? NppFtpTLS : NppFtpPlain;
    profile.port = [[self promptForString:@"Port (0 for the default)" default:@"0"] integerValue];
    profile.username = [self promptForString:@"User name" default:@""];
    profile.initialDirectory = [self promptForString:@"Initial directory" default:@"/"];
    [self.editor saveFtpProfile:profile];

    NSString *password = [self promptForString:
        @"Password (stored in the Keychain; leave empty for an SSH key)" default:@""];
    if (password.length) [NppFtpClient storePassword:password forProfile:profile];
}

- (void)ftpConnect:(id)sender {
    NSArray<NppFtpProfile *> *profiles = [self.editor ftpProfiles];
    if (!profiles.count) { [self ftpProfiles:sender]; return; }
    NSMutableArray *names = [NSMutableArray array];
    for (NppFtpProfile *p in profiles) [names addObject:p.name];

    NSString *chosen = [self promptForString:
        [NSString stringWithFormat:@"Connect to which? (%@)", [names componentsJoinedByString:@", "]]
                                     default:names.firstObject];
    NppFtpProfile *profile = [self.editor ftpProfileNamed:chosen];
    if (!profile) { NppBeep(); return; }

    if (![self.editor connectToFtpProfile:profile]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot connect.";
        alert.informativeText = [self.editor ftpConnectError]
            ?: @"The server did not answer, or the credentials were refused.";
        [alert runModal];
        return;
    }
    [self ftpBrowse:sender];
}

- (void)ftpDisconnect:(id)sender {
    [self.editor disconnectFtp];
    [self.ftpPanel orderOut:nil];
}

- (void)ftpBrowse:(id)sender {
    if (![self.editor ftpConnected]) { [self ftpConnect:sender]; return; }
    NSArray *entries = [self.editor ftpListCurrentDirectory];
    if (!entries) {
        [self presentText:[self.editor ftpClient].lastError ?: @"Cannot list the directory."
                    title:@"FTP"];
        return;
    }
    self.ftpEntries = entries;

    if (!self.ftpPanel) {
        NSRect frame = NSMakeRect(0, 0, 420, 460);
        self.ftpPanel = [[NppPanel alloc] initWithContentRect:frame
            styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
              backing:NSBackingStoreBuffered defer:YES];
        self.ftpPanel.title = @"Remote Files";
        self.ftpPanel.releasedWhenClosed = NO;
        self.ftpTable = [[NSTableView alloc] initWithFrame:frame];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"remote"];
        col.width = frame.size.width - 4;
        [self.ftpTable addTableColumn:col];
        self.ftpTable.headerView = nil;
        self.ftpTable.dataSource = (id<NSTableViewDataSource>)self;
        self.ftpTable.target = self;
        self.ftpTable.doubleAction = @selector(ftpRowActivated:);
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
        scroll.hasVerticalScroller = YES;
        scroll.documentView = self.ftpTable;
        scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.ftpPanel.contentView = scroll;
    }
    self.ftpPanel.title = [NSString stringWithFormat:@"Remote Files — %@",
                           [self.editor ftpCurrentDirectory] ?: @"/"];
    [self.ftpTable reloadData];
    [self.ftpPanel makeKeyAndOrderFront:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == self.switcherTable) return [self switcherRowCount];
    return (NSInteger)self.ftpEntries.count + 1;          // row 0 walks up
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (tv == self.switcherTable) return [self switcherTitleAtRow:row];
    if (row == 0) return @"..";
    NSInteger index = row - 1;
    if (index < 0 || index >= (NSInteger)self.ftpEntries.count) return @"";
    NppFtpEntry *entry = self.ftpEntries[(NSUInteger)index];
    return entry.isDirectory
        ? [NSString stringWithFormat:@"%@/", entry.name]
        : [NSString stringWithFormat:@"%@   %lld bytes", entry.name, entry.size];
}

- (void)ftpRowActivated:(id)sender {
    NSInteger row = self.ftpTable.clickedRow;
    if (row == 0) { [self.editor ftpChangeDirectory:@".."]; [self ftpBrowse:nil]; return; }
    NSInteger index = row - 1;
    if (index < 0 || index >= (NSInteger)self.ftpEntries.count) return;

    NppFtpEntry *entry = self.ftpEntries[(NSUInteger)index];
    if (entry.isDirectory) {
        [self.editor ftpChangeDirectory:entry.name];
        [self ftpBrowse:nil];
        return;
    }
    if (![self.editor openRemoteFileAtPath:entry.name]) {
        [self presentText:[self.editor ftpClient].lastError ?: @"Cannot open that file."
                    title:@"FTP"];
    }
}

- (void)ftpUpload:(id)sender {
    if (![self.editor ftpConnected]) { NppBeep(); return; }
    if ([self.editor uploadCurrentDocument]) {
        [self presentText:[NSString stringWithFormat:@"Uploaded to %@",
                           [self.editor remotePathForCurrentDocument] ?: @"the server"]
                    title:@"FTP"];
    } else {
        [self presentText:[self.editor ftpClient].lastError ?: @"The upload failed." title:@"FTP"];
    }
}

#pragma mark - Settings

/// The saved macros at the end of the Macro menu, as Windows lists them.
- (void)rebuildMacroMenu {
    NSMenu *menu = self.macroMenu;
    if (!menu) return;
    while (menu.numberOfItems > self.fixedMacroItemCount) [menu removeItemAtIndex:menu.numberOfItems - 1];
    NSArray *names = [self.editor savedMacroNames];
    if (names.count) [menu addItem:[NSMenuItem separatorItem]];
    for (NSString *name in names) {
        NSMenuItem *entry = [self item:name action:@selector(playSavedMacro:) key:@"" flags:0 menu:menu];
        entry.representedObject = name;
    }
    [self.shortcutStore applyToMenus];
}

- (void)playSavedMacro:(NSMenuItem *)sender {
    [self.editor playSavedMacroNamed:sender.representedObject ?: sender.title];
}

- (void)savedCommandsChanged:(NSNotification *)note {
    [self rebuildMacroMenu];
    [self rebuildRunMenu];
}

- (void)showPreferences:(id)sender {
    if (!self.prefsWindow) self.prefsWindow = [[PreferencesWindow alloc] initWithEditor:self.editor];
    [self.prefsWindow toggle];
}

- (void)showStyleConfigurator:(id)sender {
    if (!self.styleWindow) self.styleWindow = [[StyleConfiguratorWindow alloc] initWithEditor:self.editor];
    [self.styleWindow toggle];
}

- (void)showShortcutMapper:(id)sender {
    if (!self.shortcutMapper) {
        self.shortcutMapper = [[NppShortcutMapper alloc] initWithStore:self.shortcutStore editor:self.editor];
    }
    [self.shortcutMapper toggle];
}

- (void)importPlugins:(id)sender { [self importInto:@"plugins" title:@"Import plugin(s)"]; }
- (void)importThemes:(id)sender  { [self importInto:@"themes" title:@"Import style theme(s)"]; }

- (void)importInto:(NSString *)subdir title:(NSString *)title {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.title = title;
    if ([panel runModal] != NSModalResponseOK) return;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *u in panel.URLs) [paths addObject:u.path];
    NSUInteger n = [self.editor importFiles:paths intoSubdirectory:subdir];
    [self presentText:[NSString stringWithFormat:@"%lu file(s) imported into %@",
                       (unsigned long)n, subdir] title:title];
}

/// contextMenu.xml beside the other settings; upstream's default is written
/// there the first time it is wanted.
- (NSString *)contextMenuPathCreatingDefault:(BOOL)create {
    NSString *path = [[self.editor supportDirectory] stringByAppendingPathComponent:@"contextMenu.xml"];
    if (create && ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [[NppContextMenuFile defaultContents] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    return path;
}

/// IDM_SETTING_EDITCONTEXTMENU: the file itself, opened to be edited. Here it
/// is read at every right click, so saving it is enough.
- (void)editContextMenu:(id)sender {
    if (!getenv("NPPMAC_TEST")) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Editing contextMenu";
        alert.informativeText = @"Editing contextMenu.xml allows you to modify your Notepad++ popup context menu on edit zone.\n"
                                @"Here the change shows as soon as the file is saved.";
        [alert runModal];
    }
    [self.editor openFileAtPath:[self contextMenuPathCreatingDefault:YES] error:NULL];
}

#pragma mark - Language: user defined

- (void)defineUserLanguage:(id)sender {
    if (!self.userLanguageDialog) self.userLanguageDialog = [[NppUserLanguageDialog alloc] initWithEditor:self.editor];
    [self.userLanguageDialog toggle];
}

/// The user languages at the end of the Language menu, redone whenever they
/// are read again.
static const NSInteger kUserLanguageItemTag = 0x55444C;

- (void)rebuildUserLanguageMenuItems {
    NSMenu *menu = self.languageMenu;
    if (!menu) return;
    for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.tag == kUserLanguageItemTag) [menu removeItem:item];
    }
    NSArray<NppLanguage *> *user = [LanguageCatalog sharedCatalog].userLanguages;
    // Notepad_plus::initMenu (udlpos): the user's languages go before the last item, "User-Defined".
    NSMenuItem *plainUser = nil;
    for (NSMenuItem *item in menu.itemArray) if ([item.representedObject isEqual:@"udf"]) plainUser = item;
    NSInteger at = plainUser ? [menu indexOfItem:plainUser] : menu.numberOfItems;
    if (!user.count) return;
    NSMenuItem *separator = [NSMenuItem separatorItem];
    separator.tag = kUserLanguageItemTag;
    [menu insertItem:separator atIndex:at++];
    for (NppLanguage *lang in user) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:lang.name action:@selector(pickLanguage:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = lang.name;
        mi.tag = kUserLanguageItemTag;
        [menu insertItem:mi atIndex:at++];
    }
}

- (void)userLanguagesChanged:(NSNotification *)note { [self rebuildUserLanguageMenuItems]; }

static const NSInteger kBuiltInLanguageItemTag = 0x4C414E;

static NSString *LanguageMenuTitle(NSString *name) { return [LanguageCatalog menuTitleForLanguage:name]; }

/// The built-in languages at the top of the Language menu: Normal Text, then
/// the others by title, in letter submenus when the menu is compact (the
/// default upstream), leaving out those Preferences > Language hides.
- (void)fillBuiltInLanguageItems:(NSMenu *)menu {
    for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.tag == kBuiltInLanguageItemTag) [menu removeItem:item];
    }
    NppPreferences *p = [NppPreferences shared];
    NSSet *hidden = [NSSet setWithArray:p.languageMenuHidden ?: @[]];
    NSArray<NppLanguage *> *langs = [[LanguageCatalog sharedCatalog].allLanguages
        filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppLanguage *l, NSDictionary *b) {
            return !l.userDefined && ![l.name isEqualToString:@"normal"] && [LanguageCatalog languageHasMenuEntry:l.name] &&
                   ![hidden containsObject:l.name];
        }]];
    langs = [langs sortedArrayUsingComparator:^NSComparisonResult(NppLanguage *a, NppLanguage *b) {
        return [LanguageMenuTitle(a.name) caseInsensitiveCompare:LanguageMenuTitle(b.name)];
    }];
    NSInteger at = 0;
    NSMenuItem *(^itemFor)(NSString *) = ^NSMenuItem *(NSString *name) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:LanguageMenuTitle(name) action:@selector(pickLanguage:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = name;
        mi.tag = kBuiltInLanguageItemTag;
        return mi;
    };
    if (![hidden containsObject:@"normal"]) [menu insertItem:itemFor(@"normal") atIndex:at++];
    NSMenuItem *separator = [NSMenuItem separatorItem];
    separator.tag = kBuiltInLanguageItemTag;
    [menu insertItem:separator atIndex:at++];
    if (!p.languageMenuCompact) {
        for (NppLanguage *lang in langs) [menu insertItem:itemFor(lang.name) atIndex:at++];
        return;
    }
    NSMenu *letter = nil;
    for (NppLanguage *lang in langs) {
        NSString *initial = [LanguageMenuTitle(lang.name) substringToIndex:1].uppercaseString;
        if (!letter || ![letter.title isEqualToString:initial]) {
            letter = [[NSMenu alloc] initWithTitle:initial];
            NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:initial action:nil keyEquivalent:@""];
            holder.submenu = letter;
            holder.tag = kBuiltInLanguageItemTag;
            [menu insertItem:holder atIndex:at++];
        }
        [letter addItem:itemFor(lang.name)];
    }
}

- (void)rebuildLanguageMenu {
    if (self.languageMenu) [self fillBuiltInLanguageItems:self.languageMenu];
}

- (void)openUDLFolder:(id)sender {
    NSString *path = [self.editor userDefinedLanguagePath];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
}

#pragma mark - Tools: hashes

- (void)presentText:(NSString *)text title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = text.length ? text : @"(nothing)";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Copy"];
    // Escape leaves it as OK does, as it leaves upstream's message boxes and the Windows dialog
    // (IDCANCEL); an alert gives Escape only to a button called Cancel, and this one has none.
    id escape = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        if (e.keyCode != 53 || e.window != alert.window) return e;
        [alert.buttons.firstObject performClick:nil];
        return nil;
    }];
    NSModalResponse answer = [alert runModal];
    [NSEvent removeMonitor:escape];
    if (answer == NSAlertSecondButtonReturn) [self.editor copyToClipboard:text];
}

- (void)hashGenerate:(NSMenuItem *)sender {
    [[NppDigestWindow shared] showForDigest:(NppDigest)sender.tag fromFiles:NO];
}

- (void)hashFromFiles:(NSMenuItem *)sender {
    [[NppDigestWindow shared] showForDigest:(NppDigest)sender.tag fromFiles:YES];
}

- (void)passwordHashGenerate:(NSMenuItem *)sender {
    [[NppPasswordHashWindow shared] showForKind:(NppPasswordHash)sender.tag fromFiles:NO];
}

- (void)passwordHashFromFiles:(NSMenuItem *)sender {
    [[NppPasswordHashWindow shared] showForKind:(NppPasswordHash)sender.tag fromFiles:YES];
}

/// As the digests' command: of the selection, or of the document when nothing is selected - with the
/// kind's default settings and a salt made for the occasion, which the string put on the clipboard carries.
- (void)passwordHashToClipboard:(NSMenuItem *)sender {
    ScintillaView *sci = self.editor.sci;
    NSString *text = [sci selectedString];
    if (!text.length) text = [sci string];
    NSString *hash = text.length ? [NppPasswordHashWindow defaultHashOf:[text dataUsingEncoding:NSUTF8StringEncoding]
                                                                   kind:(NppPasswordHash)sender.tag] : nil;
    if (!hash) { NppBeep(); return; }
    [self.editor copyToClipboard:hash];
}

/// What is selected in the editor is what one most likely came to encode or decode.
- (void)showBase:(NSMenuItem *)sender {
    NppBaseWindow *window = [NppBaseWindow shared];
    (void)window.panel;
    NSString *selected = [self.editor.sci selectedString];
    if (selected.length) window.input.string = selected;
    [window showForEncoding:(NppBaseEncoding)sender.tag];
}

/// The answer's body as a new document, in the language its content type names - JSON as JSON, a page as HTML.
- (void)showHttpRequest:(id)sender {
    NppHttpWindow *window = [NppHttpWindow shared];
    __weak __typeof__(self) weakSelf = self;
    window.openInNewDocument = ^(NSString *text, NSString *contentType) {
        [weakSelf.editor newDocument];
        [weakSelf.editor.sci setString:text];
        NSString *type = contentType.lowercaseString;
        NSString *language = [type containsString:@"json"] ? @"json" : [type containsString:@"html"] ? @"html"
                           : [type containsString:@"xml"] ? @"xml" : [type containsString:@"javascript"] ? @"javascript"
                           : [type containsString:@"css"] ? @"css" : [type containsString:@"yaml"] ? @"yaml" : nil;
        if (language) [weakSelf.editor setLanguageNamed:language];
        [weakSelf.window makeKeyAndOrderFront:nil];
    };
    [window show];
}

- (void)showPasswordGenerator:(id)sender {
    NppPasswordWindow *window = [NppPasswordWindow shared];
    __weak __typeof__(self) weakSelf = self;
    window.insertIntoDocument = ^(NSString *text) {
        [weakSelf.editor.sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    };
    [window show];
}

- (void)hashToClipboard:(NSMenuItem *)sender {
    NppDigest d = (NppDigest)sender.tag;
    NSString *hash = [self.editor hashOfSelection:d];
    if (!hash) { NppBeep(); return; }
    [self.editor copyToClipboard:hash];
}

#pragma mark - Macro

- (void)macroStart:(id)sender {
    [self.editor startRecordingMacro];
    [self showRecordingState];
}

- (void)macroStop:(id)sender {
    [self.editor stopRecordingMacro];
    [self showRecordingState];
}

/// While a macro is being recorded the record button is red. Nothing else in
/// the window says that recording is going on.
- (void)showRecordingState {
    BOOL recording = [self.editor recordingMacro];
    [self.toolbar setActive:recording forCommand:@"IDM_MACRO_STARTRECORDINGMACRO"];
    [self.editor refreshChrome];
}
- (void)macroPlay:(id)sender  { [self.editor playbackMacro:1]; }

- (void)macroSave:(id)sender {
    NSString *name = [self promptForString:@"Save macro as" default:@"macro"];
    if (name.length && [self.editor saveRecordedMacroAs:name]) {
        [self rebuildMacroMenu];
        [self.shortcutStore save];                 // shortcuts.xml lists macros too, as on Windows
    }
}

- (void)macroRunMultiple:(id)sender {
    NSString *n = [self promptForString:@"Run how many times?" default:@"2"];
    if (!n.length) return;
    [self.editor playbackMacro:(NSUInteger)MAX(1, n.integerValue)];
}

#pragma mark - Window

- (void)sortTabs:(NSMenuItem *)sender {
    NppTabSort key = (NppTabSort)(sender.tag / 2);
    [self.editor sortTabsBy:key ascending:(sender.tag % 2) == 0];
}

- (void)showWindowsList:(id)sender {
    [self presentText:[[self.editor windowList] componentsJoinedByString:@"\n"] title:@"Windows"];
}

- (void)recentWindow:(id)sender { [self.editor activateRecentWindow]; }

#pragma mark - Run and Help

- (void)runCommand:(id)sender {
    NSString *cmd = [self promptForString:@"Run (variables such as $(FULL_CURRENT_PATH) are substituted)"
                                  default:[[NSUserDefaults standardUserDefaults]
                                           stringForKey:@"NppMacLastRunCommand"] ?: @""];
    if (!cmd.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:cmd forKey:@"NppMacLastRunCommand"];
    [self runSavedCommandLine:cmd];
}

/// Runs a command with its output going to the console rather than a dialog, so
/// that something slow can be watched instead of waited on.
- (void)runSavedCommandLine:(NSString *)command {
    [self.editor.console show];
    [self.editor runCommandLineInBackground:command completion:nil];
}

- (void)runSavedCommand:(NSMenuItem *)sender {
    [self runSavedCommandLine:sender.representedObject];
}

- (void)toggleConsole:(id)sender { [self.editor.console toggle]; }

- (void)saveRunCommand:(id)sender {
    NSString *cmd = [self promptForString:@"Command to save"
                                  default:[[NSUserDefaults standardUserDefaults]
                                           stringForKey:@"NppMacLastRunCommand"] ?: @""];
    if (!cmd.length) return;
    NSString *name = [self promptForString:@"Name it" default:@""];
    if (!name.length) return;
    [self.editor saveCommand:[NppSavedCommand commandWithName:name command:cmd]];
    [self rebuildRunMenu];
}

- (void)manageRunCommands:(id)sender {
    NSArray<NppSavedCommand *> *saved = [self.editor savedCommands];
    if (!saved.count) { [self presentText:@"No commands have been saved." title:@"Saved Commands"]; return; }

    NSMutableString *listing = [NSMutableString string];
    for (NppSavedCommand *c in saved) [listing appendFormat:@"%@\t%@\n", c.name, c.command];
    [self presentText:listing title:@"Saved Commands"];

    NSString *remove = [self promptForString:@"Remove which (leave empty to keep all)" default:@""];
    if (!remove.length) return;
    [self.editor removeSavedCommandNamed:remove];
    [self rebuildRunMenu];
}

- (void)rebuildRunMenu {
    NSMenu *menu = self.runMenu;
    if (!menu) return;
    while (menu.numberOfItems > self.fixedRunItemCount)
        [menu removeItemAtIndex:menu.numberOfItems - 1];

    NSArray<NppSavedCommand *> *saved = [self.editor savedCommands];
    if (!saved.count) return;
    [menu addItem:[NSMenuItem separatorItem]];
    for (NppSavedCommand *c in saved) {
        NSMenuItem *entry = [self item:c.name action:@selector(runSavedCommand:) key:@"" flags:0 menu:menu];
        entry.representedObject = c.command;
        entry.toolTip = c.command;
    }
    [self.shortcutStore applyToMenus];
}

#pragma mark - Recording menu commands into a macro

/// The id of a menu item when it is one of the commands upstream records by id.
- (int)macroableIdentifierOf:(NSMenuItem *)item {
    static NSSet<NSNumber *> *macroable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString *, NSNumber *> *byName = [NSMutableDictionary dictionary];
        for (int i = 0; i < kNppMenuCommandIDCount; ++i) byName[@(kNppMenuCommandIDs[i].name)] = @(kNppMenuCommandIDs[i].identifier);
        NSMutableSet *ids = [NSMutableSet set];
        for (int i = 0; i < kNppMacroableCommandCount; ++i) {
            NSNumber *identifier = byName[@(kNppMacroableCommands[i])];
            if (identifier) [ids addObject:identifier];
        }
        macroable = ids;
    });
    if (!item) return 0;
    NSDictionary<NSNumber *, NSMenuItem *> *items = [self.shortcutStore menuItemsByIdentifier];
    for (NSNumber *identifier in items) {
        if (items[identifier] == item) return [macroable containsObject:identifier] ? identifier.intValue : 0;
    }
    return 0;
}

- (void)menuWillSendAction:(NSNotification *)note {
    if (![self.editor recordingMacro] || [self.editor playingMacro]) return;
    if ([self macroableIdentifierOf:note.userInfo[@"MenuItem"]]) [self.editor beginRecordableMenuCommand];
}

- (void)menuDidSendAction:(NSNotification *)note {
    [self.editor endRecordableMenuCommand:[self macroableIdentifierOf:note.userInfo[@"MenuItem"]]];
}

#pragma mark - NppExec scripts

- (void)rebuildExecMenu {
    NSMenu *menu = self.execMenu;
    if (!menu) return;
    while (menu.numberOfItems > self.fixedExecItemCount) [menu removeItemAtIndex:menu.numberOfItems - 1];
    NSArray<NppSavedScript *> *saved = [self.editor savedScripts];
    if (!saved.count) return;
    [menu addItem:[NSMenuItem separatorItem]];
    for (NppSavedScript *script in saved) {
        NSMenuItem *entry = [self item:script.name action:@selector(executeSavedScript:) key:@"" flags:0 menu:menu];
        entry.representedObject = script.name;
        entry.toolTip = script.text;
    }
    [self.shortcutStore applyToMenus];
}

/// NPP_MENUCOMMAND's path: "Edit|Undo" or "Edit\Undo", by the English titles
/// (or the shown ones), without "…" and without the shortcut.
/// A menu item by its path ("Edit|Line Operations|Sort Lines..."), English or
/// as shown, "…"/"..." and "&" ignored; submenus built when opened are
/// built first. nil when there is none.
- (NSMenuItem *)menuItemAtCommandPath:(NSString *)path {
    NSArray *parts = [path componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"|\\"]];
    NSString *(^plain)(NSString *) = ^NSString *(NSString *t) {
        NSString *x = [[t stringByReplacingOccurrencesOfString:@"…" withString:@""] stringByReplacingOccurrencesOfString:@"..." withString:@""];
        x = [x stringByReplacingOccurrencesOfString:@"&" withString:@""];
        NSRange tab = [x rangeOfString:@"\t"];
        if (tab.location != NSNotFound) x = [x substringToIndex:tab.location];
        return [x stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
    };
    NSMenu *menu = NSApp.mainMenu;
    NSMenuItem *found = nil;
    for (NSUInteger i = 0; i < parts.count && menu; ++i) {
        NSString *want = plain(parts[i]);
        found = nil;
        if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
        for (NSMenuItem *item in menu.itemArray) {
            if (item.isSeparatorItem) continue;
            NSString *english = item.submenu && menu == NSApp.mainMenu ? NppEnglishMenuTitle(item.submenu) : NppEnglishTitle(item);
            if ([plain(english) isEqualToString:want] || [plain(item.title) isEqualToString:want]) { found = item; break; }
        }
        if (!found) return nil;
        menu = i + 1 < parts.count ? found.submenu : nil;
    }
    return found;
}

/// A menu item's action as a click on it would send it - with the menu's
/// will/did-send notifications, which the macro recorder listens to. A
/// command for the first responder means the editor's, not the console's.
- (BOOL)performMenuItem:(NSMenuItem *)found {
    if (!found || found.submenu || !found.action) return NO;
    [found.menu update];   // validation decides whether it is enabled
    if (!found.isEnabled) return NO;
    NSDictionary *info = @{@"MenuItem": found};
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuWillSendActionNotification object:found.menu userInfo:info];
    BOOL ran = (!found.target && [self.window.firstResponder tryToPerform:found.action with:found]) ||
               [NSApp sendAction:found.action to:found.target from:found];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidSendActionNotification object:found.menu userInfo:info];
    return ran;
}

- (BOOL)performMenuCommandAtPath:(NSString *)path {
    return [self performMenuItem:[self menuItemAtCommandPath:path]];
}

/// A script runs off the main thread, so the console fills and the editor
/// stays live; the engine comes back to the main thread for the editor.
- (void)executeScriptText:(NSString *)text {
    // One at a time, as NppExec has it: the one running is told to stop - its
    // program is ended with it - and the new one starts when it has.
    self.runningScript.cancelled = YES;
    static dispatch_queue_t scripts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ scripts = dispatch_queue_create("org.notepad-plus-plus.mac.scripts", DISPATCH_QUEUE_SERIAL); });
    [[NSUserDefaults standardUserDefaults] setObject:text forKey:@"NppMac.execLastScript"];
    NppScriptEngine *engine = [[NppScriptEngine alloc] initWithEditor:self.editor];
    __weak AppDelegate *weakSelf = self;
    engine.menuCommandPerformer = ^BOOL(NSString *menuPath) { return [weakSelf performMenuCommandAtPath:menuPath]; };
    self.runningScript = engine;
    [[self.editor console] showWithoutFocus];
    dispatch_async(scripts, ^{
        if (!engine.cancelled) [engine runScript:text arguments:@[]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.runningScript == engine) weakSelf.runningScript = nil;
            [weakSelf rebuildExecMenu];
        });
    });
}

- (void)stopScript:(id)sender {
    if (!self.runningScript) return;
    self.runningScript.cancelled = YES;
    [[self.editor console] appendText:@"- the script was stopped\n"];
}

- (void)executeSavedScript:(NSMenuItem *)sender {
    NppSavedScript *script = [self.editor savedScriptNamed:sender.representedObject ?: @""];
    if (script) [self executeScriptText:script.text];
}

- (void)executePreviousScript:(id)sender {
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:@"NppMac.execLastScript"];
    if (last.length) [self executeScriptText:last]; else [self executeScriptDialog:sender];
}

/// NppExec's Execute dialog: a saved script or a temporary one, edited in place.
- (void)executeScriptDialog:(id)sender {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 380)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Execute NppExec Script";
    NSView *v = panel.contentView;
    NSPopUpButton *choice = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(16, 340, 488, 26)];
    choice.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [choice addItemWithTitle:@"<temporary script>"];
    choice.accessibilityLabel = NppL(@"Script name");   // what the pop-up picks; nothing stands by it
    NSArray<NppSavedScript *> *saved = [self.editor savedScripts];
    for (NppSavedScript *s in saved) [choice.menu addItemWithTitle:s.name action:nil keyEquivalent:@""];
    [v addSubview:choice];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 56, 488, 276)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 488, 276)];
    text.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    text.autoresizingMask = NSViewWidthSizable;
    text.automaticQuoteSubstitutionEnabled = NO;
    text.automaticDashSubstitutionEnabled = NO;
    text.string = [[NSUserDefaults standardUserDefaults] stringForKey:@"NppMac.execLastScript"] ?: @"";
    scroll.documentView = text;
    [v addSubview:scroll];
    NSArray *titles = @[@"Save…", @"Delete", @"Cancel", @"OK"];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        NSButton *b = [NSButton buttonWithTitle:titles[i] target:nil action:nil];
        b.frame = NSMakeRect(i < 2 ? 16 + i * 96 : 520 - 16 - (titles.count - i) * 96, 14, 90, 30);
        b.autoresizingMask = i < 2 ? NSViewMaxXMargin : NSViewMinXMargin;
        b.tag = (NSInteger)i + 100;
        [v addSubview:b];
        [buttons addObject:b];
    }
    buttons[3].keyEquivalent = @"\r";
    buttons[2].keyEquivalent = @"\e";
    // The buttons end the modal session with their tag; the pop-up loads a script.
    for (NSButton *b in buttons) { b.target = self; b.action = @selector(execDialogButton:); }
    choice.target = self;
    choice.action = @selector(execDialogChoice:);
    objc_setAssociatedObject(choice, "text", text, OBJC_ASSOCIATION_RETAIN);
    [panel center];
    [[NppLocalization shared] localizeWindow:panel];
    while (YES) {
        NSModalResponse r = [NSApp runModalForWindow:panel];
        if (r == 100) {   // Save…
            NSString *initial = choice.indexOfSelectedItem > 0 ? choice.titleOfSelectedItem : @"";
            NSString *name = [self promptForString:@"Script name" default:initial];
            if (!name.length) continue;
            [self.editor saveScript:[NppSavedScript scriptNamed:name text:text.string]];
            if (![choice itemWithTitle:name]) [choice.menu addItemWithTitle:name action:nil keyEquivalent:@""];
            [choice selectItemWithTitle:name];
            [self rebuildExecMenu];
            continue;
        }
        if (r == 101) {   // Delete
            if (choice.indexOfSelectedItem > 0) {
                [self.editor removeScriptNamed:choice.titleOfSelectedItem];
                [choice removeItemAtIndex:choice.indexOfSelectedItem];
                [choice selectItemAtIndex:0];
                [self rebuildExecMenu];
            }
            continue;
        }
        [panel orderOut:nil];
        if (r == 103) [self executeScriptText:text.string];
        return;
    }
}

- (void)execDialogButton:(NSButton *)sender { [NSApp stopModalWithCode:sender.tag]; }

- (void)execDialogChoice:(NSPopUpButton *)sender {
    NSTextView *text = objc_getAssociatedObject(sender, "text");
    if (sender.indexOfSelectedItem <= 0) return;
    NppSavedScript *script = [self.editor savedScriptNamed:sender.titleOfSelectedItem];
    if (script) text.string = script.text;
}

- (void)validateShortcuts:(id)sender {
    [self presentText:[self.editor validateShortcutsFile] title:@"Shortcuts"];
}

- (void)openPluginsFolder:(id)sender {
    NSString *dir = [self.editor.defaultSessionPath.stringByDeletingLastPathComponent
                     stringByAppendingPathComponent:@"plugins"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:dir]]];
}

- (void)openHelpLink:(NSMenuItem *)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:sender.representedObject]];
}

- (void)showCommandLineArguments:(id)sender {
    [self presentText:[self.editor commandLineArgumentsHelp] title:@"Command Line Arguments"];
}

- (void)showDebugInfo:(id)sender {
    [[NppDebugInfoWindow shared] showText:[self.editor debugInfo]];
}

#pragma mark - Updates

/// Never from the test suite, a snapshot, or a launch that does one job and quits.
- (BOOL)automaticUpdateCheckAllowed {
    if (getenv("NPPMAC_TEST") || getenv("NPPMAC_SNAPSHOT") || getenv("NPPMAC_SELFTEST")) return NO;
    NSDictionary *options = self.commandLine;
    return ![options[@"-export=functionList"] boolValue] && ![options[@"-quickPrint"] boolValue];
}

/// Upstream's rule (winmain.cpp launchUpdater): run when today reaches the
/// next date, then move the date on by the interval.
- (BOOL)takeScheduledUpdateCheck {
    NppPreferences *p = [NppPreferences shared];
    NSDate *today = [NSDate date];
    if (![NppUpdateChecker isDueOn:today next:p.nextUpdateDate]) return NO;
    p.nextUpdateDate = [NppUpdateChecker dateString:today plusDays:p.updateIntervalDays];
    return YES;
}

- (void)automaticUpdateCheck {
    if (![self takeScheduledUpdateCheck]) return;
    [NppUpdateChecker fetchLatest:^(NppRelease *release, NSError *error) {
        // Quiet unless there is something to take, as WinGUp is when not verbose.
        if (release) [self offerRelease:release verbose:NO];
    }];
}

/// On exit the check has a few seconds; a newer release opens in the browser,
/// as upstream hands over to the updater once Notepad++ has closed.
- (void)updateCheckAtExit {
    if (![self takeScheduledUpdateCheck]) return;
    __block NppRelease *found = nil;
    __block BOOL finished = NO;
    [NppUpdateChecker fetchLatest:^(NppRelease *release, NSError *error) { found = release; finished = YES; }];
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    if (found && [NppUpdateChecker compareVersion:found.version to:[NppUpdateChecker currentVersion]] == NSOrderedDescending) {
        [[NSWorkspace sharedWorkspace] openURL:found.pageURL];
    }
}

- (void)checkForUpdates:(id)sender {
    [NppUpdateChecker fetchLatest:^(NppRelease *release, NSError *error) {
        if (release) { [self offerRelease:release verbose:YES]; return; }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Notepad++ update";
        alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", error.localizedDescription ?: @"",
                                 [NppUpdateChecker latestReleaseURL].absoluteString];
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Open the Releases Page"];
        if ([alert runModal] == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:
                @"https://github.com/%@/releases", [NppPreferences shared].updateRepository]]];
        }
    }];
}

/// WinGUp's two answers: a newer package to download, or none.
- (void)offerRelease:(NppRelease *)release verbose:(BOOL)verbose {
    NSString *current = [NppUpdateChecker currentVersion];
    BOOL newer = [NppUpdateChecker compareVersion:release.version to:current] == NSOrderedDescending;
    if (!newer && !verbose) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Notepad++ update";
    if (!newer) {
        alert.informativeText = [NSString stringWithFormat:@"No update is available.\n\nThis is v%@; the latest release is %@.",
                                 current, release.name];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }
    alert.informativeText = [NSString stringWithFormat:
        @"An update package is available, do you want to download it?\n\n%@ (you have v%@)", release.name, current];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    if ([alert runModal] == NSAlertFirstButtonReturn) [[NSWorkspace sharedWorkspace] openURL:release.pageURL];
}

- (void)setUpdaterProxy:(id)sender {
    NSString *proxy = [self promptForString:@"Updater proxy (host:port)"
                                    default:[[NSUserDefaults standardUserDefaults]
                                             stringForKey:@"NppMacUpdaterProxy"] ?: @""];
    if (proxy) [[NSUserDefaults standardUserDefaults] setObject:proxy forKey:@"NppMacUpdaterProxy"];
}

- (void)showAbout:(id)sender { [[NppAboutWindow shared] show]; }

#pragma mark - Menu validation

/// The toolbar's buttons: an image item asks its target, and without this every
/// button stayed enabled. The rules are upstream's for the toolbar
/// (Notepad_plus::checkDocState, checkClipboard, checkMacroState); the rest are
/// the matching menu items'.
- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    SEL a = item.action;
    if (a == @selector(saveDocument:)) return self.editor.currentDocument.modified;
    if (a == NSSelectorFromString(@"saveAll:")) {
        for (NppDocument *d in self.editor.documents) if (d.modified) return YES;
        return NO;
    }
    if (a == @selector(cutText:) || a == @selector(copyText:)) {
        if ([NppPreferences shared].lineCopyCutWithoutSelection) return YES;   // left as it is, as upstream does
        return [self.editor.sci message:SCI_GETSELECTIONEMPTY] == 0;
    }
    BOOL recording = [self.editor recordingMacro];
    if (a == @selector(macroStart:)) return !recording;
    if (a == @selector(macroStop:)) return recording;
    if (a == @selector(macroPlay:) || a == @selector(macroSave:))
        return !recording && [self.editor recordedStepCount] > 0;
    NSMenuItem *probe = [[NSMenuItem alloc] initWithTitle:@"" action:a keyEquivalent:@""];
    probe.tag = item.tag;
    return [self validateMenuItem:probe];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = item.action;
    // Notepad_plus::command IDM_EDIT_BEGINENDSELECT: the started one is checked and the
    // other kind is greyed out until the selection is ended (EDIT-018).
    if (a == @selector(beginEndSelect:) || a == @selector(beginEndSelectColumn:)) {
        BOOL active = [self.editor beginEndSelectActive];
        BOOL column = active && [self.editor beginEndSelectColumnModeStarted];
        BOOL mine = a == @selector(beginEndSelectColumn:) ? column : (active && !column);
        item.state = mine ? NSControlStateValueOn : NSControlStateValueOff;
        return !active || mine;
    }
    // enableConvertMenuItems: the conversion to the format the document has is greyed out.
    if (a == @selector(eolCRLF:)) return self.editor.currentDocument.eolMode != SC_EOL_CRLF;
    if (a == @selector(eolLF:))   return self.editor.currentDocument.eolMode != SC_EOL_LF;
    if (a == @selector(eolCR:))   return self.editor.currentDocument.eolMode != SC_EOL_CR;
    // Notepad_plus::checkMacroState: the Macro menu follows the recording.
    if (a == @selector(macroStart:) || a == @selector(macroStop:) || a == @selector(macroPlay:) ||
        a == @selector(macroSave:) || a == @selector(macroRunMultiple:)) {
        BOOL recording = [self.editor recordingMacro];
        BOOL recorded = [self.editor recordedStepCount] > 0;
        if (a == @selector(macroStart:)) return !recording;
        if (a == @selector(macroStop:)) return recording;
        if (a == @selector(macroPlay:) || a == @selector(macroSave:)) return recorded && !recording;
        return (recorded && !recording) || [self.editor savedMacroNames].count > 0;
    }
    // checkMenuItem(IDM_EDIT_TOGGLEREADONLY / IDM_EDIT_CHAR_PANEL, ...) as Notepad++ keeps them.
    if (a == @selector(toggleReadOnly:))
        item.state = [self.editor isReadOnly] ? NSControlStateValueOn : NSControlStateValueOff;
    if (a == @selector(toggleCharacterPanel:))
        item.state = self.charPanel.visible ? NSControlStateValueOn : NSControlStateValueOff;
    // The View toggles carry their state as a checkmark (Notepad++ checks each with checkMenuItem).
    NSControlStateValue (^mark)(BOOL) = ^NSControlStateValue(BOOL b) { return b ? NSControlStateValueOn : NSControlStateValueOff; };
    NppDockingManager *dock = [NppDockingManager shared];
    if (a == @selector(toggleSymbol:)) item.state = mark([self.editor symbolVisible:(NppSymbol)item.tag]);
    else if (a == @selector(toggleAlwaysOnTop:)) item.state = mark(self.alwaysOnTop);
    else if (a == @selector(togglePostIt:)) item.state = mark(self.postItOn);
    else if (a == @selector(toggleDistractionFree:)) item.state = mark(self.distractionFreeOn);
    else if (a == @selector(toggleSyncV:)) item.state = mark([self.editor syncVerticalScroll]);
    else if (a == @selector(toggleSyncH:)) item.state = mark([self.editor syncHorizontalScroll]);
    else if (a == @selector(toggleSyncZoom:)) item.state = mark([self.editor syncZoom]);
    else if (a == @selector(toggleDocumentMap:)) item.state = mark([self.editor documentMapVisible]);
    else if (a == @selector(toggleDocumentList:)) item.state = mark(self.docList.visible);
    else if (a == @selector(toggleFunctionList:)) item.state = mark(self.funcList.visible);
    else if (a == @selector(toggleFileBrowser:)) item.state = mark([self.editor workspaceVisible]);
    else if (a == @selector(toggleProjectPanel:))
        item.state = mark([dock isPanelVisible:[NSString stringWithFormat:@"project%ld", (long)item.tag]]);
    else if (a == @selector(toggleMonitoring:)) item.state = mark([self.editor monitoringEnabled]);
    else if (a == @selector(textRTL:)) item.state = mark([self.editor textDirectionIsRTL]);
    else if (a == @selector(textLTR:)) item.state = mark(![self.editor textDirectionIsRTL]);
    // Tab Bar > "Enable pin tab feature" off: Pin Tab is not offered (NppNotification's
    // tab menu: enableItem(IDM_PINTAB, isTabPinEnabled)), in the File menu nor the tab menu.
    if (a == @selector(togglePin:)) {
        // A pinned tab offers "Unpin Tab" (NppNotification: the IDM_PINTAB item renamed by the buffer's state).
        BOOL on = [NppPreferences shared].tabPinFeatureEnabled;
        NSString *title = NppL(on && self.editor.currentDocument.pinned ? @"Unpin Tab" : @"Pin Tab");
        if (![item.title isEqualToString:title]) item.title = title;
        return on;
    }
    if (a == @selector(numbersInsertSum:) || a == @selector(numbersInsertAverage:) || a == @selector(numbersInsertMinimum:) ||
        a == @selector(numbersInsertMaximum:) || a == @selector(numbersInsertCount:) ||
        a == @selector(numbersSortAscending:) || a == @selector(numbersSortDescending:)) {
        return ![self.editor.sci message:SCI_GETREADONLY] && [self.editor numberSetInSelection] != nil;
    }
    if (a == @selector(stopScript:)) return self.runningScript != nil;
    if (a == @selector(toggleSpellCheck:)) {
        item.state = [NppPreferences shared].spellCheckEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (a == @selector(pickLanguage:)) {
        item.state = [item.representedObject isEqualToString:self.editor.currentDocument.language.name]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(reloadDocument:) || a == @selector(moveToTrash:) || a == @selector(revealInFinder:) ||
               a == @selector(openInTerminal:) || a == @selector(containingFolderAsWorkspace:) ||
               a == @selector(openInDefaultViewer:)) {
        // Notepad_plus::checkDocState: what needs a file on disk is off for an untitled document
        // (IDM_FILE_RELOAD, IDM_FILE_DELETE, IDM_FILE_OPEN_FOLDER, IDM_FILE_OPEN_CMD,
        // IDM_FILE_CONTAININGFOLDERASWORKSPACE, IDM_FILE_OPEN_DEFAULT_VIEWER).
        return self.editor.currentDocument.path != nil;
    } else if (a == @selector(saveDocument:)) {
        // Notepad_plus::checkDocState / enableCommand(IDM_FILE_SAVE, isDirty): nothing to save, no
        // Save (a new encoding or BOM counts - the bytes on disk would change).
        NppDocument *doc = self.editor.currentDocument;
        return doc.modified || doc.encodingChanged;
    } else if (a == @selector(saveAll:)) {
        for (NppDocument *doc in self.editor.documents) if (doc.modified || doc.encodingChanged) return YES;
        return NO;
    } else if (a == @selector(toggleMonitoring:)) {
        // checkMenuItem(IDM_VIEW_MONITORING, buf->isMonitoringOn()) in Notepad_plus::checkDocState.
        item.state = [self.editor monitoringEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleAlwaysOnTop:)) {
        // IDM_VIEW_ALWAYSONTOP is checked while the window floats (Notepad_plus::command).
        item.state = self.alwaysOnTop ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWordWrap:)) {
        item.state = [self.editor.sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(toggleWhitespace:)) {
        item.state = [self.editor.sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE
                     ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(undo:)) {
        return [self.editor.sci message:SCI_CANUNDO] != 0;
    } else if (a == @selector(redo:)) {
        return [self.editor.sci message:SCI_CANREDO] != 0;
    } else if (a == @selector(pasteText:)) {
        return [self.editor.sci message:SCI_CANPASTE] != 0;
    } else if (a == @selector(compareToggleIgnoreCase:)) {
        item.state = self.editor.compareIgnoreCase ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(compareToggleIgnoreSpaces:)) {
        item.state = self.editor.compareIgnoreSpaces ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(compareToggleIgnoreEmpty:)) {
        item.state = self.editor.compareIgnoreEmptyLines ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(compareToggleDetectMoves:)) {
        item.state = self.editor.compareDetectMoves ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(compareToggleCharDiffs:)) {
        item.state = self.editor.compareCharDiffs ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(encodeInCharset:)) {
        // checkMenuItem on the character set the document is held in (Notepad_plus::checkUnicodeMenuItems).
        item.state = item.tag == [self.editor currentCharsetIndex] ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (a == @selector(pickEncoding:)) {
        item.state = [item.title isEqualToString:[self.editor encodingDisplayName]]
                     ? NSControlStateValueOn : NSControlStateValueOff;
    }
    return YES;
}

#pragma mark - File actions

- (void)newDocument:(id)sender { [self.editor newDocument]; }

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    panel.directoryURL = [NSURL fileURLWithPath:[self.editor defaultOpenDirectory] isDirectory:YES];
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *url in panel.URLs) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:url.path error:&err] && err) {
            [[NSAlert alertWithError:err] runModal];
        }
    }
}

- (void)saveDocument:(id)sender   { [self.editor saveCurrentDocument]; }
- (void)saveDocumentAs:(id)sender { [self.editor saveCurrentDocumentAs]; }
- (void)closeTab:(id)sender       { [self.editor closeCurrentDocument]; }

- (void)clearRecentDocuments:(id)sender {
    [self.editor clearRecentFiles];
    [self rebuildRecentMenu];
}

/// Rebuilt from the stored list so the display settings take effect at once.
/// Every change of the open documents (a tab closed by any command, by an agent, by Close All)
/// may have put a file on the recent list: the menu follows, as Notepad++'s does (addToRecentFileList).
- (void)documentsDidChange:(NSNotification *)note {
    if (![[self.editor recentFiles] isEqualToArray:self.recentMenuFiles ?: @[]]) [self rebuildRecentMenu];
}

- (void)rebuildRecentMenu {
    self.recentMenuFiles = [self.editor recentFiles];
    [self.recentMenu removeAllItems];
    for (NSString *path in [self.editor recentFiles]) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[self.editor displayNameForRecentFile:path]
                                                    action:@selector(openRecentFile:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = path;
        mi.toolTip = path;
        [self.recentMenu addItem:mi];
    }
    if (self.recentMenu.numberOfItems) [self.recentMenu addItem:[NSMenuItem separatorItem]];
    [self item:@"Open All Recent Files" action:@selector(openAllRecentFiles:) key:@"" flags:0 menu:self.recentMenu];
    [self item:@"Clear Menu" action:@selector(clearRecentDocuments:) key:@"" flags:0 menu:self.recentMenu];
}

- (void)restoreLastClosedFile:(id)sender {
    [self.editor restoreLastClosedFile];
    [self rebuildRecentMenu];
}

- (void)openAllRecentFiles:(id)sender {
    [self.editor openAllRecentFiles];
    [self rebuildRecentMenu];
}

#pragma mark - Files dropped on the window

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard canReadObjectForClasses:@[[NSURL class]]
                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]
        ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    BOOL opened = NO;
    for (NSURL *url in urls) {
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory] && !isDirectory) {
            if ([self.editor openFileAtPath:url.path error:NULL]) opened = YES;
        }
    }
    [self rebuildRecentMenu];
    return opened;
}

- (void)openRecentFile:(NSMenuItem *)sender {
    NSError *err = nil;
    if (![self.editor openFileAtPath:sender.representedObject error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
    [self rebuildRecentMenu];
}

- (void)revealInFinder:(id)sender      { if (![self.editor revealInFinder]) NppBeep(); }
- (void)openInTerminal:(id)sender      { if (![self.editor openContainingFolderInTerminal]) NppBeep(); }
- (void)openInDefaultViewer:(id)sender { if (![self.editor openInDefaultViewer]) NppBeep(); }

- (void)reloadDocument:(id)sender {
    NppDocument *doc = self.editor.currentDocument;
    if (doc.modified && doc.path) {
        NSInteger answer = self.editor.scriptedCloseAnswer;
        if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertFirstButtonReturn;
        if (!answer) {
            NSAlert *ask = [[NSAlert alloc] init];
            ask.messageText = @"Reload";                 // DocReloadWarning
            ask.informativeText = @"Are you sure you want to reload the current file and lose the changes made in Notepad++?";
            [ask addButtonWithTitle:@"Yes"];
            [ask addButtonWithTitle:@"No"];
            answer = [ask runModal];
        }
        if (answer != NSAlertFirstButtonReturn) return;
    }
    NSError *err = nil;
    if (![self.editor reloadCurrentDocument:&err] && err) [[NSAlert alertWithError:err] runModal];
}

- (void)saveCopyAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = self.editor.currentDocument.displayName;
    panel.directoryURL = [self.editor saveDirectoryForDocument:self.editor.currentDocument];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor saveCopyOfCurrentTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)saveAll:(id)sender {
    // Enable Save All confirm dialog, as upstream asks.
    if ([NppPreferences shared].confirmSaveAll && !getenv("NPPMAC_TEST")) {
        NSAlert *ask = [[NSAlert alloc] init];
        ask.messageText = @"Save All Confirmation";
        ask.informativeText = @"Are you sure you want to save all modified documents?\n\nChoose \"Always Yes\" if you don't want to see this dialog again.";
        [ask addButtonWithTitle:@"Yes"];
        [ask addButtonWithTitle:@"No"];
        [ask addButtonWithTitle:@"Always Yes"];
        NSModalResponse answer = [ask runModal];
        if (answer == NSAlertSecondButtonReturn) return;
        if (answer == NSAlertThirdButtonReturn) [NppPreferences shared].confirmSaveAll = NO;
    }
    [self.editor saveAllDocuments];
}

- (void)renameDocument:(id)sender {
    NSString *current = self.editor.currentDocument.path;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Rename";
    panel.nameFieldStringValue = self.editor.currentDocument.displayName;
    if (current) panel.directoryURL = [NSURL fileURLWithPath:current.stringByDeletingLastPathComponent];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor renameCurrentTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)closeAll:(id)sender           { [self.editor closeAllDocuments]; }
- (void)closeAllButCurrent:(id)sender { [self.editor closeAllButCurrent]; }
- (void)closeAllToLeft:(id)sender     { [self.editor closeAllToLeft]; }
- (void)closeAllToRight:(id)sender    { [self.editor closeAllToRight]; }
- (void)closeAllUnchanged:(id)sender  { [self.editor closeAllUnchanged]; }
- (void)closeAllButPinned:(id)sender  { [self.editor closeAllButPinned]; }
- (void)togglePin:(id)sender          { [self.editor togglePinCurrent]; }

- (void)openFolderAsWorkspace:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    [self.editor openFolderAsWorkspace:panel.URL.path];
}

- (void)containingFolderAsWorkspace:(id)sender {
    NSURL *folder = [self.editor containingFolderURL];
    if (!folder) { NppBeep(); return; }
    [self.editor openFolderAsWorkspace:folder.path];
}

- (void)moveToTrash:(id)sender {
    NppDocument *doc = self.editor.currentDocument;
    if (!doc.path) { NppBeep(); return; }
    NSAlert *alert = [[NSAlert alloc] init];
    // DoDeleteOrNot; in English the Mac's word for where it goes.
    NSString *upstream = @"The file \"$STR_REPLACE$\"\nwill be moved to your Recycle Bin and this document will be closed.\nContinue?";
    alert.messageText = NppL(@"Delete file");
    alert.informativeText = [NppLocalization shared].active
        ? NppLMessage(upstream, doc.path, 0)
        : [NSString stringWithFormat:@"The file \"%@\"\nwill be moved to your Trash and this document will be closed.\nContinue?", doc.path];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSError *err = nil;
    if (![self.editor moveCurrentToTrash:&err] && err) [[NSAlert alertWithError:err] runModal];
}

- (void)printDocument:(id)sender { [self.editor printCurrentShowingPanel:YES]; }
- (void)printNow:(id)sender      { [self.editor printCurrentShowingPanel:NO]; }

- (void)loadSession:(id)sender {
    // Notepad_plus::fileLoadSession: "All types", the session extension of MISC. beside it -
    // a session is Notepad++'s XML whatever its name (session.xml from Windows, .npps...).
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor loadSessionFrom:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

- (void)saveSession:(id)sender {
    // fileSaveSession: the file is XML; with a session extension set in MISC. it is the default one.
    NSString *ext = [NppPreferences shared].sessionFileExtension ?: @"";
    if ([ext hasPrefix:@"."]) ext = [ext substringFromIndex:1];
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = [@"session." stringByAppendingString:ext.length ? ext : @"xml"];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *err = nil;
    if (![self.editor saveSessionTo:panel.URL.path error:&err] && err) {
        [[NSAlert alertWithError:err] runModal];
    }
}

#pragma mark - Edit actions (routed straight to Scintilla)

/// The text field that is being edited, when one is.
///
/// These menu items have a target, so they never travel the responder chain --
/// which is what made Cmd+V in the Find panel paste into the document instead
/// of the field the caret was in. Whatever is being edited is asked first, and
/// only the editor is left to handle it.
static NSText *NppEditingFieldEditor(void) {
    NSResponder *responder = NSApp.keyWindow.firstResponder;
    return [responder isKindOfClass:NSText.class] ? (NSText *)responder : nil;
}

/// Sends the standard action to the field being edited. Returns whether it did.
static BOOL NppForwardToFieldEditor(SEL action, id sender) {
    NSText *editor = NppEditingFieldEditor();
    if (!editor || ![editor respondsToSelector:action]) return NO;
    ((void (*)(id, SEL, id))objc_msgSend)(editor, action, sender);
    return YES;
}

- (void)undo:(id)sender {
    if (NppForwardToFieldEditor(@selector(undo:), sender)) return;
    [self.editor.sci message:SCI_UNDO];
}

- (void)redo:(id)sender {
    if (NppForwardToFieldEditor(@selector(redo:), sender)) return;
    [self.editor.sci message:SCI_REDO];
}
/// With nothing selected, Cut and Copy take the whole line -- which is what
/// Notepad++ does, and what it has on by default.
- (void)cutText:(id)sender {
    if (NppForwardToFieldEditor(@selector(cut:), sender)) return;
    ScintillaView *sci = self.editor.sci;
    BOOL empty = [sci message:SCI_GETSELECTIONEMPTY] != 0;
    if (empty && [NppPreferences shared].lineCopyCutWithoutSelection) [sci message:SCI_LINECUT];
    else [sci message:SCI_CUT];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppPasteboardWrittenNotification object:self];
}

- (void)copyText:(id)sender {
    if (NppForwardToFieldEditor(@selector(copy:), sender)) return;
    ScintillaView *sci = self.editor.sci;
    BOOL empty = [sci message:SCI_GETSELECTIONEMPTY] != 0;
    if (empty && [NppPreferences shared].lineCopyCutWithoutSelection) {
        // COPYALLOWLINE is the message that means "the line, with its ending".
        [sci message:SCI_COPYALLOWLINE];
    } else {
        [sci message:SCI_COPY];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:NppPasteboardWrittenNotification object:self];
}
- (void)pasteText:(id)sender {
    if (NppForwardToFieldEditor(@selector(paste:), sender)) return;
    BOOL wasEmpty = [self.editor.sci message:SCI_GETLENGTH wParam:0 lParam:0] == 0;
    [self.editor.sci message:SCI_PASTE];
    // A fragment dropped into an empty document is the other time nothing but
    // the text itself can say what the language is.
    if (wasEmpty) [self detectLanguageFromContents];
}

/// Works the language out from the document's contents, putting the choice to
/// the user when more than one language fits.
- (void)detectLanguageFromContents {
    [self.editor detectLanguageOfCurrentDocumentOffering:self.editor.languageChoiceHandler];
}

- (void)offerLanguageChoices:(NSArray<NppLanguage *> *)choices {
    if (choices.count < 2 || !self.editor.window) return;

    // Every candidate in view at once, likeliest first and already selected:
    // a click and Enter, or a double click, and nothing to open first.
    NppLanguageChoiceList *list = [[NppLanguageChoiceList alloc] initWithNames:
        [choices valueForKey:@"name"]];

    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = @"Which language is this?";
    ask.informativeText = @"The name of this document does not say what it is. "
                          @"These are what its contents look like, likeliest first.";
    ask.accessoryView = list.scrollView;
    [ask addButtonWithTitle:@"Use this one"];
    [ask addButtonWithTitle:@"Leave as text"];
    ask.window.initialFirstResponder = list.table;

    __weak __typeof(self) weakSelf = self;
    __weak NSAlert *weakAsk = ask;
    list.chosen = ^{
        // A double click is the choice made: close the sheet as "Use this one".
        [weakSelf.editor.window endSheet:weakAsk.window returnCode:NSAlertFirstButtonReturn];
    };
    [ask beginSheetModalForWindow:self.editor.window
                completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSInteger picked = list.table.selectedRow;
        if (picked < 0 || picked >= (NSInteger)choices.count) return;
        [weakSelf.editor chooseLanguageNamed:choices[(NSUInteger)picked].name];
    }];
}

- (void)selectAllText:(id)sender {
    if (NppForwardToFieldEditor(@selector(selectAll:), sender)) return;
    [self.editor.sci message:SCI_SELECTALL];
}

- (void)duplicateLine:(id)sender { [self.editor.sci message:SCI_LINEDUPLICATE]; }

#pragma mark - View actions

- (void)zoomIn:(id)sender    { [self.editor.sci message:SCI_ZOOMIN]; }
- (void)zoomOut:(id)sender   { [self.editor.sci message:SCI_ZOOMOUT]; }
- (void)zoomReset:(id)sender { [self.editor.sci message:SCI_SETZOOM wParam:0 lParam:0]; }

// The View toggles are the preference: written there, so that the next
// appearance change or Preferences apply does not put things back, and
// pushed to both views, as Notepad++ does.
- (void)toggleWordWrap:(id)sender {
    NppPreferences *p = [NppPreferences shared];
    p.wordWrap = [self.editor.sci message:SCI_GETWRAPMODE] == SC_WRAP_NONE;
    for (ScintillaView *sci in [self bothViews]) {
        [sci message:SCI_SETWRAPMODE wParam:(uptr_t)(p.wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE) lParam:0];
    }
}

- (NSArray<ScintillaView *> *)bothViews {
    ScintillaView *second = self.editor.secondarySci;
    return second ? @[self.editor.mainSci, second] : @[self.editor.mainSci];
}

- (void)toggleOvertype:(id)sender { [self.editor toggleOvertype]; }

- (void)toggleWhitespace:(id)sender {
    NppPreferences *p = [NppPreferences shared];
    p.showWhitespace = [self.editor.sci message:SCI_GETVIEWWS] == SCWS_INVISIBLE;
    for (ScintillaView *sci in [self bothViews]) {
        [sci message:SCI_SETVIEWWS
               wParam:(uptr_t)(p.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
    }
}

- (void)pickLanguage:(NSMenuItem *)sender {
    [self.editor chooseLanguageNamed:sender.representedObject];
}

#pragma mark - Comment / completion

- (void)toggleLineComment:(id)sender  { [self.editor toggleLineComment]; }
- (void)setLineComment:(id)sender     { [self.editor setLineComment]; }
- (void)toggleBlockComment:(id)sender { [self.editor toggleBlockComment]; }
- (void)showAutoComplete:(id)sender   { [self.editor showAutoCompletion]; }
- (void)functionCompletion:(id)sender { [self.editor showCompletion:NppCompletionKindFunctions autoInsert:NO]; }

#pragma mark - Edit: case, lines, blanks

- (void)convertCase:(NSMenuItem *)sender { [self.editor convertCase:(NppCaseMode)sender.tag]; }

- (void)sortLines:(NSMenuItem *)sender {
    NSInteger failed = [self.editor sortLines:(NppSortKey)(sender.tag / 2)
                                   descending:(sender.tag % 2) == 1];
    if (failed != NSNotFound) {
        // Notepad++ refuses a numeric sort it cannot carry out and says which
        // line stopped it, rather than leaving the file half sorted.
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Sorting Error";
        alert.informativeText = NppLMessage(@"Unable to perform numeric sorting due to line $INT_REPLACE$.", nil, failed + 1);
        [alert runModal];
        return;
    }
}

- (void)applyTrim:(NSMenuItem *)sender { [self.editor applyTrim:(NppTrimMode)sender.tag]; }

- (void)reverseLines:(id)sender   { [self.editor sortLines:NppSortReverseOrder descending:NO]; }
- (void)randomizeLines:(id)sender { [self.editor sortLines:NppSortRandom descending:NO]; }

- (void)removeDupLines:(id)sender            { [self.editor removeDuplicateLines:NO]; }
- (void)removeConsecutiveDupLines:(id)sender { [self.editor removeDuplicateLines:YES]; }
- (void)splitLines:(id)sender                { [self.editor splitLines]; }
- (void)joinLines:(id)sender                 { [self.editor joinLines]; }
- (void)moveLineUp:(id)sender                { [self.editor moveLine:YES]; }
- (void)moveLineDown:(id)sender              { [self.editor moveLine:NO]; }
- (void)removeEmptyLines:(id)sender          { [self.editor removeEmptyLines:NO]; }
- (void)removeBlankLines:(id)sender          { [self.editor removeEmptyLines:YES]; }
- (void)blankLineAbove:(id)sender            { [self.editor insertBlankLine:YES]; }
- (void)blankLineBelow:(id)sender            { [self.editor insertBlankLine:NO]; }
- (void)increaseIndent:(id)sender            { [self.editor changeIndent:YES]; }
- (void)decreaseIndent:(id)sender            { [self.editor changeIndent:NO]; }
- (void)deleteSelection:(id)sender           { [self.editor deleteSelection]; }
- (void)uncommentLines:(id)sender            { [self.editor uncommentLines]; }
- (void)streamComment:(id)sender             { [self.editor streamComment:YES]; }
- (void)streamUncomment:(id)sender           { [self.editor streamComment:NO]; }

- (void)toggleReadOnly:(id)sender    { [self.editor setReadOnly:![self.editor isReadOnly]]; }
- (void)readOnlyAll:(id)sender       { [self.editor setReadOnlyForAllDocuments:YES]; }
- (void)clearReadOnlyAll:(id)sender  { [self.editor setReadOnlyForAllDocuments:NO]; }

// IDM_EDIT_FULLPATHTOCLIP copies getFullPathName, which for an untitled buffer is its name ("new 1").
- (void)copyFullPath:(id)sender  { NppDocument *d = self.editor.currentDocument;
                                   [self.editor copyToClipboard:d.path ?: (d.displayName ?: @"")]; }
- (void)copyFileName:(id)sender  { [self.editor copyToClipboard:self.editor.currentDocument.displayName]; }
- (void)copyDirPath:(id)sender   { [self.editor copyToClipboard:[self.editor containingFolderURL].path ?: @""]; }
- (void)copyAllNames:(id)sender  { [self.editor copyToClipboard:[self.editor allDocumentNames]]; }
- (void)copyAllPaths:(id)sender  { [self.editor copyToClipboard:[self.editor allDocumentPaths]]; }

- (void)insertDateShort:(id)sender { [self.editor insertDateTimeShort:YES]; }
- (void)insertDateLong:(id)sender  { [self.editor insertDateTimeShort:NO]; }

/// As upstream: the format set in Preferences > Date, no question asked.
- (void)insertDateCustom:(id)sender {
    NSString *picture = [NppPreferences shared].customDateFormat.length ? [NppPreferences shared].customDateFormat
                                                                         : @"yyyy-MM-dd HH:mm:ss";
    [self.editor insertCustomDateTime:[NppPreferences dateFormatFromWindowsPicture:picture]];
}

#pragma mark - Edit: multi-select, columns, panels

static NppMatchFlags FlagsForTag(NSInteger tag) {
    switch (tag) {
        case 1: return NppMatchCase;
        case 2: return NppMatchWholeWord;
        case 3: return NppMatchCase | NppMatchWholeWord;
        default: return NppMatchNone;
    }
}

- (void)multiSelectAll:(NSMenuItem *)s  { [self.editor multiSelectAllOccurrences:FlagsForTag(s.tag)]; }
- (void)multiSelectNext:(NSMenuItem *)s { [self.editor multiSelectNextOccurrence:FlagsForTag(s.tag)]; }
- (void)multiSelectUndo:(id)sender      { [self.editor undoLastMultiSelection]; }
- (void)multiSelectSkip:(id)sender      { [self.editor skipCurrentMultiSelection]; }

- (void)beginEndSelect:(id)sender       { [self.editor beginEndSelectColumnMode:NO]; }
- (void)beginEndSelectColumn:(id)sender { [self.editor beginEndSelectColumnMode:YES]; }

- (void)columnModeTip:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Column mode";
    alert.informativeText = @"Hold Option and drag to select a rectangle, or use "
                            @"Begin/End Select in Column Mode. Column Editor then "
                            @"fills every selected row.";
    [alert runModal];
}

- (void)columnEditor:(id)sender {
    if ([self.editor selectionCount] < 1) { NppBeep(); return; }
    NSString *mode = [self promptForString:@"Column Editor - \"text\" or \"number\"?" default:@"text"];
    if (!mode.length) return;
    if ([mode hasPrefix:@"n"]) {
        NSString *from = [self promptForString:@"Initial number" default:@"1"];
        if (!from.length) return;
        NSString *step = [self promptForString:@"Increase by" default:@"1"];
        if (!step.length) return;
        NSString *repeat = [self promptForString:@"Repeat each number" default:@"1"];
        NSString *pad = [self promptForString:@"Leading zeros? yes/no" default:@"no"];
        NSString *format = [self promptForString:@"Format: dec, hex, oct or bin" default:@"dec"];
        int base = [format hasPrefix:@"h"] ? 16 : [format hasPrefix:@"o"] ? 8 : [format hasPrefix:@"b"] ? 2 : 10;
        [self.editor columnInsertNumbersFrom:from.integerValue increment:step.integerValue
                                      repeat:MAX(1, repeat.integerValue)
                                  zeroPadded:[pad hasPrefix:@"y"] base:base];
    } else {
        NSString *text = [self promptForString:@"Text to insert" default:@""];
        if (!text.length) return;
        [self.editor columnInsertText:text];
    }
}

- (void)toggleCharacterPanel:(id)sender {
    if (!self.charPanel) self.charPanel = [[CharacterPanel alloc] initWithEditor:self.editor];
    [self.charPanel toggle];
}

- (void)toggleClipboardHistory:(id)sender {
    if (!self.clipPanel) self.clipPanel = [[ClipboardHistoryPanel alloc] initWithEditor:self.editor];
    [self.clipPanel toggle];
}

- (void)toggleSystemReadOnly:(id)sender { [self.editor toggleSystemReadOnly]; }

- (void)pathCompletion:(id)sender { [self.editor showPathCompletion]; }
- (void)callTip:(id)sender        { [self.editor showFunctionCallTip]; }
- (void)callTipNext:(id)sender    { [self.editor cycleFunctionCallTip:YES]; }
- (void)callTipPrev:(id)sender    { [self.editor cycleFunctionCallTip:NO]; }

- (void)pasteHTML:(id)sender          { [self.editor pasteAsHTML]; }
- (void)pasteRTF:(id)sender           { [self.editor pasteAsRTF]; }
- (void)copyBinary:(id)sender         { [self.editor copySelectionAsBinary]; }
- (void)cutBinary:(id)sender          { [self.editor cutSelectionAsBinary]; }
- (void)pasteBinaryContent:(id)sender { [self.editor pasteBinary]; }

- (void)openSelectedFile:(id)sender   { [self.editor openSelectedFile]; }
- (void)revealSelectedFile:(id)sender { [self.editor revealSelectedFile]; }
- (void)searchOnInternet:(id)sender   { [self.editor searchSelectionOnInternet]; }

- (void)redactSelection:(id)sender {
    BOOL bullet = ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0;
    [self.editor redactSelectionWithBlock:!bullet];
}

- (void)changeSearchEngine:(id)sender {
    NSString *current = [[NppPreferences shared].searchEngineCustom length] ? [NppPreferences shared].searchEngineCustom
        : [[self.editor.searchEngineTemplate stringByReplacingOccurrencesOfString:@"%@" withString:@"$(CURRENT_WORD)"]
           stringByReplacingOccurrencesOfString:@"%%" withString:@"%"];
    NSString *t = [self promptForString:@"Search URL ($(CURRENT_WORD) is the query)" default:current];
    if (!t.length) return;
    [NppPreferences shared].searchEngineCustom = t;
    [NppPreferences shared].searchEngine = 4;
}

#pragma mark - Bookmarks

- (void)toggleBookmark:(id)sender   { [self.editor toggleBookmark]; }
- (void)nextBookmark:(id)sender     { [self.editor nextBookmark]; }
- (void)previousBookmark:(id)sender { [self.editor previousBookmark]; }
- (void)clearBookmarks:(id)sender   { [self.editor clearBookmarks]; }

#pragma mark - View: folds, symbols, window modes, tabs

- (void)foldLevel:(NSMenuItem *)s   { [self.editor foldToLevel:s.tag]; }
- (void)unfoldLevel:(NSMenuItem *)s { [self.editor unfoldToLevel:s.tag]; }
- (void)toggleSymbol:(id)sender { [self.editor toggleSymbol:(NppSymbol)[sender tag]]; }

- (void)hideLines:(id)sender        { [self.editor hideSelectedLines]; }
- (void)showHiddenLines:(id)sender  { [self.editor showAllHiddenLines]; }

/// IDM_VIEW_SUMMARY as Notepad++ writes it: the file's path and times when it
/// has a file, then characters (line endings left out), words, lines, length
/// and the selection, numbers commafied, every label the translation's
/// <MiscStrings> summary-* text, the title its "summary".
- (NSString *)summaryText {
    NSDictionary *s = [self.editor documentSummary];
    NppLocalization *l = [NppLocalization shared];
    NSNumberFormatter *commafy = [[NSNumberFormatter alloc] init];
    commafy.numberStyle = NSNumberFormatterDecimalStyle;           // commafyInt: the user's grouping
    NSString *(^n)(NSString *) = ^NSString *(NSString *key) { return [commafy stringFromNumber:s[key]] ?: @"0"; };
    NSMutableString *out = [NSMutableString string];
    NSString *path = self.editor.currentDocument.path;
    if (path.length) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
        NSDateFormatter *when = [[NSDateFormatter alloc] init];   // GetDateFormat + GetTimeFormat, the user's locale
        when.dateStyle = NSDateFormatterShortStyle;
        when.timeStyle = NSDateFormatterMediumStyle;
        [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-filepath" default:@"Full file path: "], path];
        [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-filecreatetime" default:@"Created: "],
            attrs.fileCreationDate ? [when stringFromDate:attrs.fileCreationDate] : @""];
        [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-filemodifytime" default:@"Modified: "],
            attrs.fileModificationDate ? [when stringFromDate:attrs.fileModificationDate] : @""];
    }
    [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-nbchar" default:@"Characters (without line endings): "], n(@"charactersWithoutEOL")];
    [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-nbword" default:@"Words: "], n(@"words")];
    [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-nbline" default:@"Lines: "], n(@"lines")];
    [out appendFormat:@"%@%@\n", [l stringWithID:@"summary-nbbyte" default:@"Document length: "], n(@"bytes")];
    [out appendFormat:@"%@%@%@%@%@%@", n(@"selectedCharacters"), [l stringWithID:@"summary-nbsel1" default:@" selected characters ("],
        n(@"selectedBytes"), [l stringWithID:@"summary-nbsel2" default:@" bytes) in "],
        n(@"selectedRanges"), [l stringWithID:@"summary-nbrange" default:@" ranges"]];
    return out;
}

- (void)showSummary:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [[NppLocalization shared] stringWithID:@"summary" default:@"Summary"];
    alert.informativeText = [self summaryText];
    [alert runModal];
}

- (void)toggleMonitoring:(id)sender {
    // Refused as upstream refuses it, with its "Monitoring problem" box rather than a bare beep:
    // an unsaved tab or unsaved changes otherwise look like a button that does nothing.
    NSString *why = [self.editor monitoringEnabled] ? nil : [self.editor monitoringRefusal];
    if (why) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Monitoring problem";
        alert.informativeText = why;
        alert.alertStyle = NSAlertStyleWarning;
        [alert addButtonWithTitle:@"OK"];
        if (!getenv("NPPMAC_TEST")) [alert runModal];
        return;
    }
    [self.editor setMonitoring:![self.editor monitoringEnabled]];
}

- (void)toggleAlwaysOnTop:(id)sender {
    self.alwaysOnTop = !self.alwaysOnTop;
    self.window.level = self.alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

- (void)toggleFullScreenMode:(id)sender { [self.window toggleFullScreen:nil]; }

- (void)togglePostIt:(id)sender {
    // Notepad++'s Post-It is a chrome-less always-on-top window
    // (Notepad_plus::postItToggle); Distraction Free ignores it (IDM_VIEW_POSTIT).
    if (self.distractionFreeOn) return;
    BOOL entering = !self.postItOn;
    if (entering) self.alwaysOnTopBeforePostIt = self.alwaysOnTop;
    self.postItOn = entering;
    [self.editor setChromeVisible:!entering];
    // Leaving puts Always on Top back as it was before.
    self.alwaysOnTop = entering || self.alwaysOnTopBeforePostIt;
    self.window.level = self.alwaysOnTop ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

- (void)toggleDistractionFree:(id)sender {
    if (self.postItOn) return;
    self.distractionFreeOn = !self.distractionFreeOn;
    [self.editor setChromeVisible:!self.distractionFreeOn];
}

- (void)toggleFileBrowser:(id)sender {
    if ([self.editor workspaceVisible]) { [self.editor openFolderAsWorkspace:nil]; return; }
    NSURL *folder = [self.editor containingFolderURL];
    if (folder) { [self.editor openFolderAsWorkspace:folder.path]; return; }
    [self openFolderAsWorkspace:sender];
}

/// The floating panels in "Remember panel state": Clipboard History,
/// Document List, Character Panel and Function List, each as Preferences says.
- (void)rememberFloatingPanels {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    NSMutableDictionary *state = [p.panelState mutableCopy] ?: [NSMutableDictionary dictionary];
    state[@"clipboardHistory"] = @(self.clipPanel.visible && [p keepsPanelState:@"clipboardHistory"]);
    state[@"documentList"] = @(self.docList.visible && [p keepsPanelState:@"documentList"]);
    state[@"characterPanel"] = @(self.charPanel.visible && [p keepsPanelState:@"characterPanel"]);
    state[@"functionList"] = @(self.funcList.visible && [p keepsPanelState:@"functionList"]);
    p.panelState = state;
}

- (void)restoreFloatingPanels {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    NSDictionary *state = p.panelState;
    if ([state[@"clipboardHistory"] boolValue] && [p keepsPanelState:@"clipboardHistory"] && !self.clipPanel.visible) [self toggleClipboardHistory:nil];
    if ([state[@"documentList"] boolValue] && [p keepsPanelState:@"documentList"] && !self.docList.visible) [self toggleDocumentList:nil];
    if ([state[@"characterPanel"] boolValue] && [p keepsPanelState:@"characterPanel"] && !self.charPanel.visible) [self toggleCharacterPanel:nil];
    if ([state[@"functionList"] boolValue] && [p keepsPanelState:@"functionList"] && !self.funcList.visible) [self toggleFunctionList:nil];
}

- (void)toggleDocumentList:(id)sender {
    if (!self.docList) self.docList = [[DocumentListPanel alloc] initWithEditor:self.editor];
    [self.docList toggle];
}

- (void)toggleDocumentMap:(id)sender {
    [self.editor setDocumentMapVisible:![self.editor documentMapVisible]];
}

- (void)toggleMarkdownPreview:(id)sender {
    if (!self.markdownPanel) self.markdownPanel = [[MarkdownPanel alloc] initWithEditor:self.editor];
    [self.markdownPanel toggle];
}

- (void)toggleFunctionList:(id)sender {
    if (!self.funcList) self.funcList = [[FunctionListPanel alloc] initWithEditor:self.editor];
    [self.funcList toggle];
}

- (void)toggleProjectPanel:(NSMenuItem *)sender {
    [self.editor showProjectPanel:sender.tag];
}

- (void)focusOtherView:(id)sender   { [self.editor focusOtherView]; }
- (void)moveToOtherView:(id)sender  { [self.editor moveCurrentToOtherView]; }
- (void)cloneToOtherView:(id)sender { [self.editor cloneCurrentToOtherView]; }
- (void)moveToNewInstance:(id)sender { [self.editor openCurrentInNewInstanceMoving:YES]; }
- (void)openInNewInstance:(id)sender { [self.editor openCurrentInNewInstanceMoving:NO]; }

- (void)toggleSyncV:(id)sender    { [self.editor setSyncVerticalScroll:![self.editor syncVerticalScroll]]; }
- (void)toggleSyncH:(id)sender    { [self.editor setSyncHorizontalScroll:![self.editor syncHorizontalScroll]]; }
- (void)toggleSyncZoom:(id)sender { [self.editor setSyncZoom:![self.editor syncZoom]]; }

- (void)textRTL:(id)sender { [self.editor setTextDirectionRTL:YES]; }
- (void)textLTR:(id)sender { [self.editor setTextDirectionRTL:NO]; }

- (void)viewInBrowser:(NSMenuItem *)sender {
    if (![self.editor openCurrentInBrowserBundleID:sender.representedObject]) NppBeep();
}

- (void)goToTabNumber:(NSMenuItem *)s { [self.editor selectTabNumber:s.tag]; }
- (void)firstTab:(id)sender           { [self.editor goToFirstTab]; }
- (void)lastTab:(id)sender            { [self.editor goToLastTab]; }
- (void)moveTabForward:(id)sender     { [self.editor moveCurrentTab:YES]; }
- (void)moveTabBackward:(id)sender    { [self.editor moveCurrentTab:NO]; }
- (void)moveTabToStart:(id)sender     { [self.editor moveCurrentTabToEnd:NO]; }
- (void)moveTabToEnd:(id)sender       { [self.editor moveCurrentTabToEnd:YES]; }
- (void)applyTabColour:(NSMenuItem *)s { [self.editor setTabColour:s.tag]; }

#pragma mark - Search: styles, braces, files

- (void)markAllStyle:(NSMenuItem *)s  { [self.editor markAllOccurrencesOfSelection:s.tag]; }
- (void)markOneStyle:(NSMenuItem *)s  { [self.editor markOneOccurrenceOfSelection:s.tag]; }
- (void)clearStyle:(NSMenuItem *)s    { [self.editor clearStyle:s.tag]; }
- (void)clearAllStyles:(id)sender     { [self.editor clearAllStyles]; }
- (void)jumpUpStyle:(NSMenuItem *)s   { [self.editor jumpToMarker:s.tag forward:NO]; }
- (void)jumpDownStyle:(NSMenuItem *)s { [self.editor jumpToMarker:s.tag forward:YES]; }
- (void)copyStyle:(NSMenuItem *)s     { [self.editor copyToClipboard:[self.editor textOfStyle:s.tag]]; }
- (void)copyAllStyles:(id)sender      { [self.editor copyToClipboard:[self.editor textOfAllStyles]]; }

- (void)goToMatchingBrace:(id)sender   { [self.editor goToMatchingBrace]; }
- (void)selectBetweenBraces:(id)sender { [self.editor selectBetweenMatchingBraces]; }

- (void)markTerm:(id)sender {
    NSString *term = [self promptForString:@"Mark" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self.editor.sci message:SCI_SETSEL wParam:0 lParam:0];
    [self searchFrom:0 forward:YES wrap:NO];
    [self.editor markAllOccurrencesOfSelection:NPPMAC_STYLE_COUNT];
}

- (void)findCharsInRange:(id)sender {
    NSString *from = [self promptForString:@"Mark characters from (decimal code point)" default:@"128"];
    if (!from.length) return;
    NSString *to = [self promptForString:@"…to (decimal code point)" default:@"65535"];
    if (!to.length) return;
    // Code points, not UTF-16 units: a bound above U+FFFF (an emoji) stays what was typed.
    long long lo = from.longLongValue, hi = to.longLongValue;
    if (lo < 0 || hi < lo || hi > 0x10FFFF) { NppBeep(); return; }
    NSUInteger n = [self.editor markCharactersInRangeFrom:(uint32_t)lo to:(uint32_t)hi];
    NSAlert *done = [[NSAlert alloc] init];
    done.messageText = [NSString stringWithFormat:@"%lu character%@ marked", (unsigned long)n, n == 1 ? @"" : @"s"];
    [done runModal];
}

- (void)findInFiles:(id)sender {
    // One dialog with a tab, as Notepad++ has it, rather than a run of prompts.
    [self openFindPanelOnTab:2];
}


- (void)focusSearchResults:(id)sender { [self.editor focusSearchResults]; }
- (void)nextSearchResult:(id)sender   { [self.editor goToSearchResult:YES]; }
- (void)prevSearchResult:(id)sender   { [self.editor goToSearchResult:NO]; }

/// IDM_SEARCH_SETANDFINDNEXT: the selection (or the word at the caret) becomes
/// the Find dialog's "Find what", history and all, and is looked for with the
/// dialog's own options, as a normal search.
- (void)selectAndFind:(BOOL)forward {
    NSString *term = [self.editor initialFindTerm];
    if (!term.length) { NppBeep(); return; }
    if (!self.findPanel) [self buildFindPanel];
    self.findField.stringValue = term;
    [self rememberFindFields:NO files:NO];
    NppFindOptions options = forward ? NppFindNone : NppFindBackward;
    if (self.matchCaseBox.state == NSControlStateValueOn) options |= NppFindMatchCase;
    if (self.wholeWordBox.state == NSControlStateValueOn) options |= NppFindWholeWord;
    if (self.wrapBox.state == NSControlStateValueOn) options |= NppFindWrap;
    NppFindSpec *spec = [NppFindSpec specFor:term mode:NppSearchNormal options:options];
    // IDM_SEARCH_SETANDFINDNEXT puts the word in the Find field, so it is the
    // search Find Next / Find Previous go on with (SEARCH-101).
    NppFindSpec *kept = [NppFindSpec specFor:term mode:NppSearchNormal options:options & ~NppFindBackward];
    self.lastFindSpec = kept;
    self.lastSearchTerm = term;
    [self find:spec forward:forward];
}

/// IDM_SEARCH_VOLATILE_FINDNEXT: the selection only, any case, any word,
/// wrapping, and nothing of it kept in the dialog.
- (void)volatileFind:(BOOL)forward {
    NSString *term = [self.editor.sci selectedString];
    if (!term.length) return;
    [self find:[NppFindSpec specFor:term mode:NppSearchNormal options:NppFindWrap | (forward ? NppFindNone : NppFindBackward)]
       forward:forward];
}

/// Finds, and says in the dialog's status line when the search went round the
/// end of the document, as both commands do upstream.
- (void)find:(NppFindSpec *)spec forward:(BOOL)forward {
    // Where the search starts: after the selection going down, before it going up.
    long before = [self.editor.sci message:forward ? SCI_GETSELECTIONEND : SCI_GETSELECTIONSTART];
    if (![self.editor findNext:spec]) {
        self.findStatus.stringValue = NppLMessage(@"Find: Can't find the text \"$STR_REPLACE$\"", spec.what, 0);
        NppBeep();
        return;
    }
    long after = [self.editor.sci message:SCI_GETSELECTIONSTART];
    BOOL wrapped = forward ? after < before : after >= before;
    self.findStatus.stringValue = !wrapped ? @""
        : NppL(forward ? @"Find: Reached document end, first occurrence from the top found."
                       : @"Find: Reached document beginning, first occurrence from the bottom found.");
}

- (void)selectAndFindNext:(id)sender { [self selectAndFind:YES]; }
- (void)selectAndFindPrev:(id)sender { [self selectAndFind:NO]; }
- (void)volatileFindNext:(id)sender  { [self volatileFind:YES]; }
- (void)volatileFindPrev:(id)sender  { [self volatileFind:NO]; }

- (void)incrementalSearch:(id)sender {
    // macOS already has a first-class incremental find bar; this drives the
    // same search state so ⌘G continues from it.
    NSString *term = [self promptForString:@"Incremental search" default:self.lastSearchTerm];
    if (!term.length) return;
    self.lastSearchTerm = term;
    [self searchFrom:[self.editor.sci message:SCI_GETCURRENTPOS] forward:YES wrap:YES];
}

- (void)cutMarkedLines:(id)sender      { [self.editor cutBookmarkedLines]; }
- (void)copyMarkedLines:(id)sender     { [self.editor copyBookmarkedLines]; }
- (void)pasteMarkedLines:(id)sender    { [self.editor pasteOverBookmarkedLines]; }
- (void)removeMarkedLines:(id)sender   { [self.editor removeBookmarkedLines]; }
- (void)removeUnmarkedLines:(id)sender { [self.editor removeUnbookmarkedLines]; }
- (void)inverseBookmarks:(id)sender    { [self.editor inverseBookmarks]; }

- (void)nextChange:(id)sender         { [self.editor goToNextChange:YES]; }
- (void)prevChange:(id)sender         { [self.editor goToNextChange:NO]; }
- (void)clearChangeHistory:(id)sender { [self.editor clearChangeHistory]; }

#pragma mark - Folding

- (void)toggleFold:(id)sender { [self.editor toggleFoldAtCursor]; }
- (void)foldAll:(id)sender    { [self.editor foldAll:YES]; }
- (void)unfoldAll:(id)sender  { [self.editor foldAll:NO]; }
- (void)foldCurrent:(id)sender   { [self.editor foldCurrent:YES]; }
- (void)unfoldCurrent:(id)sender { [self.editor foldCurrent:NO]; }

#pragma mark - Encoding + EOL

- (void)pickEncoding:(NSMenuItem *)sender {
    struct { NSStringEncoding enc; BOOL bom; } table[] = {
        {NSUTF8StringEncoding,              NO},
        {NSUTF8StringEncoding,              YES},
        {NSUTF16LittleEndianStringEncoding, YES},
        {NSUTF16BigEndianStringEncoding,    YES},
        {NSISOLatin1StringEncoding,         NO},
    };
    NSInteger i = sender.tag;
    if (i < 0 || i >= (NSInteger)(sizeof(table)/sizeof(table[0]))) return;
    // A document in a character set is read again from its file: Notepad++ asks first.
    if ([self.editor currentCharsetIndex] >= 0 && ![self confirmEncodingReread]) return;
    [self.editor encodeInEncoding:table[i].enc withBOM:table[i].bom];
}

/// Notepad_plus::command IDM_FORMAT_* before a re-read: a modified document is
/// saved first or left alone ("Save Current Modification"), and one with an undo
/// history is told it loses it ("Lose Undo Ability Warning"). NO: leave it be.
- (BOOL)confirmEncodingReread {
    NSString *text = NppL(@"You should save the current modification.\nAll the saved modifications cannot be undone.\n\nContinue?");
    if (self.editor.currentDocument.modified) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NppL(@"Save Current Modification");
        alert.informativeText = text;
        [alert addButtonWithTitle:NppL(@"Yes")];
        [alert addButtonWithTitle:NppL(@"No")];
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
        if (![self.editor saveCurrentDocument] || self.editor.currentDocument.modified) return NO;
        [self.editor.sci message:SCI_EMPTYUNDOBUFFER];
    }
    if ([self.editor.sci message:SCI_CANUNDO]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = NppL(@"Lose Undo Ability Warning");
        alert.informativeText = text;
        [alert addButtonWithTitle:NppL(@"Yes")];
        [alert addButtonWithTitle:NppL(@"No")];
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    }
    return YES;
}

- (void)encodeInCharset:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= kNppCharsetCount) return;
    if (![self confirmEncodingReread]) return;
    if (![self.editor reinterpretAsCodepage:kNppCharsets[sender.tag].codepage]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Cannot read this document as %@.",
                             @(kNppCharsets[sender.tag].label)];
        [alert runModal];
    }
}

- (void)convertToANSI:(id)sender {
    // IDM_FORMAT_CONV2_ANSI: a document in a character set is left as it is.
    if ([self.editor currentCharsetIndex] >= 0) return;
    [self.editor setEncoding:NSISOLatin1StringEncoding withBOM:NO];
}
- (void)convertToUTF8:(id)sender    { [self.editor setEncoding:NSUTF8StringEncoding withBOM:NO]; }
- (void)convertToUTF8BOM:(id)sender { [self.editor setEncoding:NSUTF8StringEncoding withBOM:YES]; }
- (void)convertToUTF16BE:(id)sender { [self.editor setEncoding:NSUTF16BigEndianStringEncoding withBOM:YES]; }
- (void)convertToUTF16LE:(id)sender { [self.editor setEncoding:NSUTF16LittleEndianStringEncoding withBOM:YES]; }

- (void)eolCRLF:(id)sender { [self.editor convertEOLTo:SC_EOL_CRLF]; }
- (void)eolLF:(id)sender   { [self.editor convertEOLTo:SC_EOL_LF]; }
- (void)eolCR:(id)sender   { [self.editor convertEOLTo:SC_EOL_CR]; }

#pragma mark - Tabs

#pragma mark - Document Switcher (Ctrl+Tab)

- (void)installDocumentSwitcher {
    __weak __typeof(self) weakSelf = self;
    self.switcherMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskFlagsChanged
                                                                 handler:^NSEvent *(NSEvent *e) {
        __typeof(self) me = weakSelf;
        if (e.type == NSEventTypeFlagsChanged) {
            if (me.switching && !(e.modifierFlags & NSEventModifierFlagControl)) [me endDocumentSwitch];
            return e;
        }
        NSEventModifierFlags f = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        if (e.keyCode == 48 && (f & NSEventModifierFlagControl) && !(f & NSEventModifierFlagCommand)) {
            [me switchDocumentForward:!(f & NSEventModifierFlagShift)];
            return nil;
        }
        return e;
    }];
}

/// Ctrl+Tab and Ctrl+Shift+Tab. With the Document Switcher on, a list shows
/// while Control is held and the order is most recently used first when MRU
/// is on; with it off, they step through the tabs in order.
- (void)switchDocumentForward:(BOOL)forward {
    NppPreferences *p = [NppPreferences shared];
    NSArray<NppDocument *> *docs = self.editor.documents;
    if (docs.count < 2) return;
    if (!self.switching) {
        self.switcherOrder = (p.docSwitcherEnabled && p.docSwitcherMRU) ? [self.editor documentsInRecentOrder] : docs;
        self.switching = p.docSwitcherEnabled;
    }
    NSArray<NppDocument *> *order = self.switcherOrder;
    NSUInteger at = [order indexOfObjectIdenticalTo:self.editor.currentDocument];
    if (at == NSNotFound) at = 0;
    NSUInteger next = forward ? (at + 1) % order.count : (at + order.count - 1) % order.count;
    NSUInteger index = [self.editor.documents indexOfObjectIdenticalTo:order[next]];
    if (index != NSNotFound) [self.editor selectDocumentAtIndex:(NSInteger)index];
    if (self.switching) [self showDocumentSwitcherAt:next];
}

- (void)showDocumentSwitcherAt:(NSUInteger)row {
    if (!self.switcherPanel) {
        NSRect frame = NSMakeRect(0, 0, 360, 240);
        self.switcherPanel = [[NSPanel alloc] initWithContentRect:frame
                                                        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                          backing:NSBackingStoreBuffered defer:YES];
        self.switcherPanel.floatingPanel = YES;
        self.switcherPanel.hasShadow = YES;
        self.switcherTable = [[NSTableView alloc] initWithFrame:frame];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"doc"];
        col.width = NSWidth(frame) - 8;
        [self.switcherTable addTableColumn:col];
        self.switcherTable.headerView = nil;
        self.switcherTable.dataSource = (id<NSTableViewDataSource>)self;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
        scroll.documentView = self.switcherTable;
        self.switcherPanel.contentView = scroll;
    }
    [self.switcherTable reloadData];
    [self.switcherTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.switcherTable scrollRowToVisible:(NSInteger)row];
    NSRect w = self.window.frame;
    [self.switcherPanel setFrameOrigin:NSMakePoint(NSMidX(w) - 180, NSMidY(w) - 120)];
    [self.switcherPanel orderFront:nil];
}

- (void)endDocumentSwitch {
    self.switching = NO;
    [self.switcherPanel orderOut:nil];
}

- (BOOL)documentSwitcherShown { return self.switcherPanel.isVisible; }

- (NSInteger)switcherRowCount { return (NSInteger)self.switcherOrder.count; }

- (NSString *)switcherTitleAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.switcherOrder.count) return @"";
    return self.switcherOrder[(NSUInteger)row].displayName;
}

// The focused view's tabs, as upstream's IDM_VIEW_TAB_NEXT / _PREV on _pDocTab.
- (void)nextTab:(id)sender { [self.editor goToNextTab]; }
- (void)previousTab:(id)sender { [self.editor goToPreviousTab]; }

#pragma mark - Search

- (NSString *)promptForString:(NSString *)title default:(NSString *)def {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = def ?: @"";
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return field.stringValue;
}

/// The tab right-click menu, with the items and submenus Notepad++ gives it
/// by default (NppNotification.cpp), taken from the port's own menu items.
- (NSMenu *)buildTabContextMenu {
    // tabContextMenu.xml, when the user has made one (upstream ships an example to rename).
    NSString *own = [[self.editor supportDirectory] stringByAppendingPathComponent:@"tabContextMenu.xml"];
    NSMenu *described = [NppContextMenuFile menuFromFile:own root:@"TabContextMenu" mainMenu:NSApp.mainMenu
                                             identifiers:[self.shortcutStore menuItemsByIdentifier]];
    if (described.numberOfItems) return described;
    // Upstream's labels (with Finder, Terminal and Trash for their Windows
    // namesakes); the command behind each is found by its id, or by action.
    struct { const char *label; const char *identifier; const char *action; const char *submenu; } layout[] = {
        {"Close", "IDM_FILE_CLOSE", NULL, NULL},
        {"Close All BUT This", "IDM_FILE_CLOSEALL_BUT_CURRENT", NULL, "Close Multiple Tabs"},
        {"Close All BUT Pinned", "IDM_FILE_CLOSEALL_BUT_PINNED", NULL, "Close Multiple Tabs"},
        {"Close All to the Left", "IDM_FILE_CLOSEALL_TOLEFT", NULL, "Close Multiple Tabs"},
        {"Close All to the Right", "IDM_FILE_CLOSEALL_TORIGHT", NULL, "Close Multiple Tabs"},
        {"Close All Unchanged", "IDM_FILE_CLOSEALL_UNCHANGED", NULL, "Close Multiple Tabs"},
        {"Pin Tab", "IDM_PINTAB", "togglePin:", NULL},
        {"Save", "IDM_FILE_SAVE", NULL, NULL},
        {"Save As...", "IDM_FILE_SAVEAS", NULL, NULL},
        {"Open Containing Folder in Finder", "IDM_FILE_OPEN_FOLDER", NULL, "Open into"},
        {"Open Containing Folder in Terminal", "IDM_FILE_OPEN_CMD", NULL, "Open into"},
        {"Open Containing Folder as Workspace", "IDM_FILE_CONTAININGFOLDERASWORKSPACE", NULL, "Open into"},
        {NULL, NULL, NULL, "Open into"},
        {"Open in Default Viewer", "IDM_FILE_OPEN_DEFAULT_VIEWER", NULL, "Open into"},
        {"Rename", "IDM_FILE_RENAME", NULL, NULL},
        {"Move to Trash", "IDM_FILE_DELETE", NULL, NULL},
        {"Reload", "IDM_FILE_RELOAD", NULL, NULL},
        {"Print", "IDM_FILE_PRINT", NULL, NULL},
        {NULL, NULL, NULL, NULL},
        {"Read-Only in Notepad++", "IDM_EDIT_TOGGLEREADONLY", "toggleReadOnly:", NULL},
        {"Read-Only Attribute on Disk", "IDM_EDIT_TOGGLESYSTEMREADONLY", "toggleSystemReadOnly:", NULL},
        {NULL, NULL, NULL, NULL},
        {"Copy Full File Path", "IDM_EDIT_FULLPATHTOCLIP", NULL, "Copy to Clipboard"},
        {"Copy Filename", "IDM_EDIT_FILENAMETOCLIP", NULL, "Copy to Clipboard"},
        {"Copy Current Dir. Path", "IDM_EDIT_CURRENTDIRTOCLIP", NULL, "Copy to Clipboard"},
        {"Move to Start", "IDM_VIEW_GOTO_START", NULL, "Move Document"},
        {"Move to End", "IDM_VIEW_GOTO_END", NULL, "Move Document"},
        {NULL, NULL, NULL, "Move Document"},
        {"Move to Other View", "IDM_VIEW_GOTO_ANOTHER_VIEW", NULL, "Move Document"},
        {"Clone to Other View", "IDM_VIEW_CLONE_TO_ANOTHER_VIEW", NULL, "Move Document"},
        {"Move to New Instance", "IDM_VIEW_GOTO_NEW_INSTANCE", NULL, "Move Document"},
        {"Open in New Instance", "IDM_VIEW_LOAD_IN_NEW_INSTANCE", NULL, "Move Document"},
        {"Apply Color 1", "IDM_VIEW_TAB_COLOUR_1", NULL, "Apply Color to Tab"},
        {"Apply Color 2", "IDM_VIEW_TAB_COLOUR_2", NULL, "Apply Color to Tab"},
        {"Apply Color 3", "IDM_VIEW_TAB_COLOUR_3", NULL, "Apply Color to Tab"},
        {"Apply Color 4", "IDM_VIEW_TAB_COLOUR_4", NULL, "Apply Color to Tab"},
        {"Apply Color 5", "IDM_VIEW_TAB_COLOUR_5", NULL, "Apply Color to Tab"},
        {"Remove Color", "IDM_VIEW_TAB_COLOUR_NONE", NULL, "Apply Color to Tab"},
    };
    NSDictionary<NSNumber *, NSMenuItem *> *items = [self.shortcutStore menuItemsByIdentifier];
    NSMenuItem *(^byAction)(SEL) = ^NSMenuItem *(SEL action) {
        NSMutableArray *queue = [NSApp.mainMenu.itemArray mutableCopy];
        while (queue.count) {
            NSMenuItem *it = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (it.submenu) [queue addObjectsFromArray:it.submenu.itemArray];
            if (it.action == action) return it;
        }
        return nil;
    };
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
    NSMutableDictionary<NSString *, NSMenu *> *submenus = [NSMutableDictionary dictionary];
    for (auto &entry : layout) {
        NSMenu *into = menu;
        if (entry.submenu) {
            NSString *name = @(entry.submenu);
            into = submenus[name];
            if (!into) {
                into = submenus[name] = [[NSMenu alloc] initWithTitle:name];
                [menu addItemWithTitle:NppL(name) action:nil keyEquivalent:@""].submenu = into;
            }
        }
        if (!entry.label) {
            if (into.numberOfItems && !into.itemArray.lastObject.isSeparatorItem) [into addItem:[NSMenuItem separatorItem]];
            continue;
        }
        int identifier = 0;
        for (int i = 0; i < kNppMenuCommandIDCount; ++i) {
            if (!strcmp(kNppMenuCommandIDs[i].name, entry.identifier)) { identifier = kNppMenuCommandIDs[i].identifier; break; }
        }
        NSMenuItem *real = identifier ? items[@(identifier)] : nil;
        if (!real && entry.action) real = byAction(NSSelectorFromString(@(entry.action)));
        if (!real) continue;
        // In the interface language: the tab menu's wording, else the main menu's, else by the English text.
        NppLocalization *l10n = [NppLocalization shared];
        NSString *label = !l10n.active ? @(entry.label)
            : ([l10n tabCommandName:identifier] ?: (identifier ? [l10n commandName:identifier] : nil) ?: NppL(@(entry.label)));
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:label action:real.action keyEquivalent:@""];
        copy.target = real.target;
        copy.tag = real.tag;
        copy.representedObject = real.representedObject;
        [into addItem:copy];
    }
    // Submenus none of whose commands the port has are left out.
    for (NSMenuItem *it in menu.itemArray.copy) {
        if (it.submenu && !it.submenu.numberOfItems) [menu removeItem:it];
    }
    return menu;
}

/// Folder as Workspace > Find in Files...: the Find in Files tab, on that folder.
- (void)findInFolderRequested:(NSNotification *)note {
    [self openFindPanelOnTab:2];
    if ([note.object isKindOfClass:[NSString class]]) self.directoryField.stringValue = note.object;
}

#pragma mark - Localization

- (void)applyLocalization {
    NppLocalization *l = [NppLocalization shared];
    NSString *file = [NppPreferences shared].localizationFile;
    if (![file isEqualToString:l.languageFile ?: @""] || !file.length) [l loadLanguageFile:file];
    [l localizeMenu:NSApp.mainMenu identifiers:self.menuIdentifiers ?: @{}];
    for (NSWindow *w in NSApp.windows) [l localizeWindow:w];
    [self.editor rebuildContextMenu];   // copies of menu titles, made anew in the language
    [[self.editor gitPanel] relocalize];   // its buttons and columns are made once
    [[NppDockingManager shared] relocalize];   // the dock tabs draw their titles
    [self.editor refreshChrome];           // the status bar's words are the language's
    for (NSInteger i = 1; i <= 3; ++i) [[self.editor projectPanel:i] reloadView];   // "Project Panel 1 - file" is composed
}

- (void)windowBecameKey:(NSNotification *)note {
    NppLocalization *l = [NppLocalization shared];
    if (l.active) [l localizeWindow:note.object];
    // In the language it is now shown in: symbol buttons named by their tooltips, fields by their labels.
    NppAXPrepareWindow(note.object);
}

/// Menus rebuilt since (macros, recent files, languages) are translated as they open.
- (void)menuWillShow:(NSNotification *)note {
    NppLocalization *l = [NppLocalization shared];
    if (l.active && note.object == NSApp.mainMenu) [l localizeMenu:NSApp.mainMenu identifiers:self.menuIdentifiers ?: @{}];
}

- (void)showFind:(id)sender    { [self openFindPanelOnTab:0]; }
- (void)showReplace:(id)sender { [self openFindPanelOnTab:1]; }
- (void)showMarkTab:(id)sender { [self openFindPanelOnTab:4]; }

/// Opens the dialog with one of its tabs in front.
- (void)openFindPanelOnTab:(NSInteger)tab {
    if (!self.findPanel) [self buildFindPanel];
    self.findTabs.selectedSegment = tab;
    [self findTabChanged:nil];

    NSString *seed = [self.editor initialFindTerm];
    if (seed.length) self.findField.stringValue = seed;
    if (tab == 2 && (!self.directoryField.stringValue.length || [NppPreferences shared].fillDirectoryFromActiveDocument)) {
        NSString *path = self.editor.currentDocument.path;
        if (path.length) self.directoryField.stringValue = path.stringByDeletingLastPathComponent;
    }
    [self updateInSelectionAvailability];
    [self.findPanel makeKeyAndOrderFront:nil];
    [self.findPanel makeFirstResponder:self.findField];
}

/// Notepad++'s Find dialog is mostly its modes and options; this carries the
/// same ones rather than asking for a string and searching for it literally.

- (NSButton *)findCheckbox:(NSString *)title at:(NSPoint)origin in:(NSView *)parent {
    NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(origin.x, origin.y, 190, 18)];
    [box setButtonType:NSButtonTypeSwitch];
    box.title = title;
    [parent addSubview:box];
    return box;
}

- (NSButton *)findButton:(NSString *)title action:(SEL)action at:(NSPoint)origin in:(NSView *)parent {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(origin.x, origin.y, 110, 26)];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    [parent addSubview:button];
    return button;
}

/// A field with its history in a drop-down, as the dialog's combo boxes are.
- (NSComboBox *)findCombo:(NSRect)frame history:(NSArray<NSString *> *)history in:(NSView *)parent {
    NSComboBox *combo = [[NSComboBox alloc] initWithFrame:frame];
    combo.completes = NO;
    combo.numberOfVisibleItems = 10;
    [combo addItemsWithObjectValues:history ?: @[]];
    [parent addSubview:combo];
    return combo;
}

- (void)buildFindPanel {
    NSRect frame = NSMakeRect(0, 0, 700, 400);
    self.findPanel = [[NppPanel alloc] initWithContentRect:frame
                                                styleMask:(NSWindowStyleMaskTitled |
                                                           NSWindowStyleMaskClosable |
                                                           NSWindowStyleMaskUtilityWindow)
                                                  backing:NSBackingStoreBuffered defer:YES];
    self.findPanel.title = @"Find";
    self.findPanel.releasedWhenClosed = NO;
    // Transparency follows focus; In selection follows the selection.
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(findPanelFocusChanged:) name:NSWindowDidBecomeKeyNotification object:self.findPanel];
    [nc addObserver:self selector:@selector(findPanelFocusChanged:) name:NSWindowDidResignKeyNotification object:self.findPanel];

    // A panel's default content view paints nothing, so in dark mode the labels
    // are white on white. This follows the appearance.
    NSVisualEffectView *content = [[NSVisualEffectView alloc] initWithFrame:frame];
    content.material = NSVisualEffectMaterialWindowBackground;
    content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    content.state = NSVisualEffectStateActive;
    self.findPanel.contentView = content;

    self.findOnlyViews = [NSMutableArray array];
    self.replaceViews = [NSMutableArray array];
    self.inFilesViews = [NSMutableArray array];
    self.inProjectsViews = [NSMutableArray array];
    self.markViews = [NSMutableArray array];
    NppPreferences *prefs = [NppPreferences shared];

    // Notepad++ puts these one behind the other on tabs, and the fields and
    // options below them are shared.
    self.findTabs = [NSSegmentedControl segmentedControlWithLabels:
                     @[@"Find", @"Replace", @"Find in Files", @"Find in Projects", @"Mark"]
                                                      trackingMode:NSSegmentSwitchTrackingSelectOne
                                                            target:self
                                                            action:@selector(findTabChanged:)];
    self.findTabs.frame = NSMakeRect(16, 360, 668, 26);
    self.findTabs.selectedSegment = 0;
    [content addSubview:self.findTabs];

    NSTextField *findLabel = [NSTextField labelWithString:@"Find what:"];
    findLabel.frame = NSMakeRect(16, 328, 90, 18);
    [content addSubview:findLabel];
    self.findField = [self findCombo:NSMakeRect(110, 324, 480, 26) history:prefs.findHistory in:content];

    NSTextField *replaceLabel = [NSTextField labelWithString:@"Replace with:"];
    replaceLabel.frame = NSMakeRect(16, 298, 90, 18);
    [content addSubview:replaceLabel];
    self.replaceField = [self findCombo:NSMakeRect(110, 294, 480, 26) history:prefs.replaceHistory in:content];
    // Swaps the two fields, as the button between them on Windows does.
    NSButton *swap = [NSButton buttonWithTitle:@"⇅" target:self action:@selector(findPanelSwap:)];
    swap.frame = NSMakeRect(594, 308, 44, 26);   // a rounded bezel keeps ~24 pt of margins: 44 leaves the glyph its room
    swap.toolTip = @"Swap Find with Replace";
    [content addSubview:swap];
    [self.replaceViews addObjectsFromArray:@[replaceLabel, self.replaceField, swap]];
    [self.inFilesViews addObjectsFromArray:@[replaceLabel, self.replaceField, swap]];
    [self.inProjectsViews addObjectsFromArray:@[replaceLabel, self.replaceField, swap]];

    NSTextField *filtersLabel = [NSTextField labelWithString:@"Filters:"];
    filtersLabel.frame = NSMakeRect(16, 268, 90, 18);
    [content addSubview:filtersLabel];
    self.filtersField = [self findCombo:NSMakeRect(110, 264, 480, 26) history:prefs.filterHistory in:content];
    self.filtersField.placeholderString = @"*.cpp *.h — blank for every file";
    [self.inFilesViews addObjectsFromArray:@[filtersLabel, self.filtersField]];
    [self.inProjectsViews addObjectsFromArray:@[filtersLabel, self.filtersField]];

    NSTextField *directoryLabel = [NSTextField labelWithString:@"Directory:"];
    directoryLabel.frame = NSMakeRect(16, 238, 90, 18);
    [content addSubview:directoryLabel];
    self.directoryField = [self findCombo:NSMakeRect(110, 234, 420, 26) history:prefs.directoryHistory in:content];
    NSButton *browse = [self findButton:@"Browse…" action:@selector(findPanelBrowse:)
                                     at:NSMakePoint(536, 233) in:content];
    NSButton *fromDoc = [self findButton:@"From doc" action:@selector(findPanelDirectoryFromDocument:)
                                      at:NSMakePoint(110, 203) in:content];
    [self.inFilesViews addObjectsFromArray:@[directoryLabel, self.directoryField, browse, fromDoc]];

    self.recursiveBox = [self findCheckbox:@"In all sub-folders" at:NSMakePoint(240, 208) in:content];
    self.recursiveBox.state = NSControlStateValueOn;
    self.hiddenBox = [self findCheckbox:@"In hidden folders" at:NSMakePoint(430, 208) in:content];
    [self.inFilesViews addObjectsFromArray:@[self.recursiveBox, self.hiddenBox]];

    NSButtonCell *prototype = [[NSButtonCell alloc] init];
    [prototype setButtonType:NSButtonTypeRadio];
    self.modeRadios = [[NSMatrix alloc] initWithFrame:NSMakeRect(16, 110, 250, 66)
                                                 mode:NSRadioModeMatrix
                                            prototype:prototype
                                         numberOfRows:3 numberOfColumns:1];
    NSArray *modeTitles = @[@"Normal", @"Extended (\\n, \\r, \\t, \\0, \\x...)", @"Regular expression"];
    for (NSUInteger i = 0; i < modeTitles.count; ++i) {
        [[self.modeRadios cellAtRow:(NSInteger)i column:0] setTitle:modeTitles[i]];
    }
    // Wide enough for the longest of them, which is otherwise cut short.
    [self.modeRadios setCellSize:NSMakeSize(250, 22)];
    [self.modeRadios selectCellAtRow:0 column:0];
    self.modeRadios.target = self;
    self.modeRadios.action = @selector(findModeChanged:);
    [content addSubview:self.modeRadios];
    self.dotNewlineBox = [self findCheckbox:@". matches newline" at:NSMakePoint(16, 86) in:content];

    self.matchCaseBox   = [self findCheckbox:@"Match case"      at:NSMakePoint(285, 158) in:content];
    self.wholeWordBox   = [self findCheckbox:@"Match whole word only" at:NSMakePoint(285, 136) in:content];
    // Smart highlighting "Use Find dialog settings" reads the boxes as they are, not as the
    // last search left them (upstream asks FindReplaceDlg for the checkbox state): SETTINGS-054.
    for (NSButton *box in @[self.matchCaseBox, self.wholeWordBox]) {
        box.target = self;
        box.action = @selector(findOptionBoxChanged:);
    }
    self.wrapBox        = [self findCheckbox:@"Wrap around"     at:NSMakePoint(285, 114) in:content];
    self.backwardBox    = [self findCheckbox:@"Backward direction" at:NSMakePoint(475, 158) in:content];
    self.inSelectionBox = [self findCheckbox:@"In selection"    at:NSMakePoint(475, 136) in:content];
    self.wrapBox.state = NSControlStateValueOn;
    [self.findOnlyViews addObjectsFromArray:@[self.backwardBox, self.inSelectionBox]];
    [self.replaceViews addObjectsFromArray:@[self.backwardBox, self.inSelectionBox]];

    self.bookmarkLineBox = [self findCheckbox:@"Bookmark line" at:NSMakePoint(475, 114) in:content];
    self.purgeBox = [self findCheckbox:@"Purge for each search" at:NSMakePoint(475, 92) in:content];
    [self.markViews addObjectsFromArray:@[self.bookmarkLineBox, self.purgeBox, self.inSelectionBox]];
    [self findModeChanged:nil];

    // The rows of buttons, one set per tab.
    NSButton *findNext = [self findButton:@"Find Next" action:@selector(findPanelNext:)
                                       at:NSMakePoint(16, 60) in:content];
    findNext.keyEquivalent = @"\r";                       // Enter does the dialog's job
    NSButton *count = [self findButton:@"Count" action:@selector(findPanelCount:)
                                    at:NSMakePoint(128, 60) in:content];
    NSButton *findAllHere = [self findButton:@"Find All in Current Document" action:@selector(findPanelFindAll:)
                                          at:NSMakePoint(240, 60) in:content];
    findAllHere.frame = NSMakeRect(240, 60, 230, 26);
    NSButton *findAllOpen = [self findButton:@"Find All in All Opened Documents"
                                      action:@selector(findPanelFindAllInOpenDocuments:)
                                          at:NSMakePoint(16, 28) in:content];
    findAllOpen.frame = NSMakeRect(16, 28, 260, 26);
    [self.findOnlyViews addObjectsFromArray:@[findNext, count, findAllHere, findAllOpen]];

    NSButton *replaceOne = [self findButton:@"Replace" action:@selector(findPanelReplace:)
                                         at:NSMakePoint(128, 60) in:content];
    NSButton *replaceAll = [self findButton:@"Replace All" action:@selector(findPanelReplaceAll:)
                                         at:NSMakePoint(240, 60) in:content];
    NSButton *replaceAllOpen = [self findButton:@"Replace All in All Opened Documents"
                                         action:@selector(findPanelReplaceAllInOpenDocuments:)
                                             at:NSMakePoint(16, 28) in:content];
    replaceAllOpen.frame = NSMakeRect(16, 28, 280, 26);
    [self.replaceViews addObjectsFromArray:@[findNext, replaceOne, replaceAll, replaceAllOpen]];

    NSButton *filesFind = [self findButton:@"Find All" action:@selector(findPanelFindInFiles:)
                                        at:NSMakePoint(16, 28) in:content];
    NSButton *filesReplace = [self findButton:@"Replace in Files"
                                       action:@selector(findPanelReplaceInFiles:)
                                           at:NSMakePoint(128, 28) in:content];
    filesReplace.frame = NSMakeRect(128, 28, 140, 26);
    [self.inFilesViews addObjectsFromArray:@[filesFind, filesReplace]];

    NSButton *projectsFind = [self findButton:@"Find All"
                                       action:@selector(findPanelFindInProjects:)
                                           at:NSMakePoint(16, 28) in:content];
    NSButton *projectsReplace = [self findButton:@"Replace in Projects"
                                          action:@selector(findPanelReplaceInProjects:)
                                              at:NSMakePoint(128, 28) in:content];
    projectsReplace.frame = NSMakeRect(128, 28, 150, 26);
    [self.inProjectsViews addObjectsFromArray:@[projectsFind, projectsReplace]];
    NSMutableArray *boxes = [NSMutableArray array];
    for (NSInteger i = 1; i <= 3; ++i) {
        NSButton *box = [self findCheckbox:[NSString stringWithFormat:@"Project Panel %ld", (long)i]
                                        at:NSMakePoint(110 + (CGFloat)(i - 1) * 140, 208) in:content];
        box.state = i == 1 ? NSControlStateValueOn : NSControlStateValueOff;
        [boxes addObject:box];
        [self.inProjectsViews addObject:box];
    }
    self.projectPanelBoxes = boxes;

    NSButton *markAll = [self findButton:@"Mark All" action:@selector(findPanelMarkAll:)
                                      at:NSMakePoint(16, 28) in:content];
    NSButton *clearMarks = [self findButton:@"Clear all marks"
                                     action:@selector(findPanelClearMarks:)
                                         at:NSMakePoint(128, 28) in:content];
    clearMarks.frame = NSMakeRect(128, 28, 130, 26);
    NSButton *copyMarked = [self findButton:@"Copy Marked Text"
                                     action:@selector(findPanelCopyMarkedText:)
                                         at:NSMakePoint(262, 28) in:content];
    copyMarked.frame = NSMakeRect(262, 28, 150, 26);
    [self.markViews addObjectsFromArray:@[markAll, clearMarks, copyMarked]];

    // A search over a folder can take a while, so it says how far it has got
    // and can be called off.
    self.findStopButton = [self findButton:@"Stop" action:@selector(findPanelStop:)
                                        at:NSMakePoint(286, 28) in:content];
    self.findStopButton.frame = NSMakeRect(286, 28, 64, 26);
    self.findStopButton.hidden = YES;

    self.findProgress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(358, 32, 120, 18)];
    self.findProgress.style = NSProgressIndicatorStyleBar;
    self.findProgress.indeterminate = YES;
    self.findProgress.displayedWhenStopped = NO;
    [content addSubview:self.findProgress];

    self.findSearchButtons = @[filesFind, filesReplace, projectsFind, projectsReplace];

    self.findStatus = [NSTextField labelWithString:@""];
    self.findStatus.frame = NSMakeRect(16, 6, 500, 18);
    [content addSubview:self.findStatus];

    // Transparency: on losing focus or always, at the chosen level.
    self.transparencyBox = [self findCheckbox:@"Transparency" at:NSMakePoint(540, 72) in:content];
    self.transparencyBox.target = self;
    self.transparencyBox.action = @selector(findTransparencyChanged:);
    self.transparencyBox.state = prefs.findTransparencyMode ? NSControlStateValueOn : NSControlStateValueOff;
    self.transparencyRadios = [[NSMatrix alloc] initWithFrame:NSMakeRect(556, 28, 130, 42)
                                                         mode:NSRadioModeMatrix prototype:prototype
                                                 numberOfRows:2 numberOfColumns:1];
    [[self.transparencyRadios cellAtRow:0 column:0] setTitle:@"On losing focus"];
    [[self.transparencyRadios cellAtRow:1 column:0] setTitle:@"Always"];
    [self.transparencyRadios setCellSize:NSMakeSize(130, 20)];
    [self.transparencyRadios selectCellAtRow:prefs.findTransparencyMode == 2 ? 1 : 0 column:0];
    self.transparencyRadios.target = self;
    self.transparencyRadios.action = @selector(findTransparencyChanged:);
    [content addSubview:self.transparencyRadios];
    self.transparencySlider = [NSSlider sliderWithValue:prefs.findTransparencyLevel ?: 150 minValue:20 maxValue:255
                                                 target:self action:@selector(findTransparencyChanged:)];
    self.transparencySlider.frame = NSMakeRect(556, 4, 128, 22);
    [content addSubview:self.transparencySlider];
    // Upstream's trackbar sits in the group the Transparency check box titles (IDC_TRANSPARENT_GRPBOX):
    // that box is what names it.
    self.transparencySlider.accessibilityTitleUIElement = self.transparencyBox;

    // The options as they were left.
    self.matchCaseBox.state = prefs.findMatchCase ? NSControlStateValueOn : NSControlStateValueOff;
    self.wholeWordBox.state = prefs.findWholeWord ? NSControlStateValueOn : NSControlStateValueOff;
    self.wrapBox.state = prefs.findWrap ? NSControlStateValueOn : NSControlStateValueOff;
    [self.modeRadios selectCellAtRow:MIN(2, MAX(0, prefs.findMode)) column:0];
    [self findModeChanged:nil];
    [self findTabChanged:nil];
    [self applyFindTransparency];
}

/// A status line in upstream's words, which have one form for one and another for many.
- (NSString *)status:(NSString *)one many:(NSString *)many count:(NSUInteger)count {
    return count == 1 ? NppL(one) : NppLMessage(many, nil, (NSInteger)count);
}

- (void)findPanelSwap:(id)sender {
    NSString *what = self.findField.stringValue;
    self.findField.stringValue = self.replaceField.stringValue;
    self.replaceField.stringValue = what;
}

/// Puts a value at the head of a history, keeping at most ten, as the
/// dialog's combo boxes do, and remembers it for the next launch.
- (void)remember:(NSString *)value inCombo:(NSComboBox *)combo key:(NSString *)key {
    if (!value.length || ![combo isKindOfClass:[NSComboBox class]]) return;
    NSMutableArray *items = [combo.objectValues mutableCopy] ?: [NSMutableArray array];
    [items removeObject:value];
    [items insertObject:value atIndex:0];
    while (items.count > 10) [items removeLastObject];
    [combo removeAllItems];
    [combo addItemsWithObjectValues:items];
    combo.stringValue = value;
    [[NppPreferences shared] setValue:items forKey:key];
}

- (void)rememberFindFields:(BOOL)withReplace files:(BOOL)files {
    [self remember:self.findField.stringValue inCombo:(NSComboBox *)self.findField key:@"findHistory"];
    if (withReplace) [self remember:self.replaceField.stringValue inCombo:(NSComboBox *)self.replaceField key:@"replaceHistory"];
    if (files) {
        [self remember:self.filtersField.stringValue inCombo:(NSComboBox *)self.filtersField key:@"filterHistory"];
        [self remember:self.directoryField.stringValue inCombo:(NSComboBox *)self.directoryField key:@"directoryHistory"];
    }
}

- (void)applyFindTransparency {
    NppPreferences *p = [NppPreferences shared];
    BOOL on = self.transparencyBox.state == NSControlStateValueOn;
    BOOL always = [self.transparencyRadios selectedRow] == 1;
    self.transparencyRadios.enabled = on;
    self.transparencySlider.enabled = on;
    p.findTransparencyMode = on ? (always ? 2 : 1) : 0;
    p.findTransparencyLevel = (NSInteger)self.transparencySlider.integerValue;
    BOOL translucent = on && (always || !self.findPanel.isKeyWindow);
    self.findPanel.alphaValue = translucent ? self.transparencySlider.doubleValue / 255.0 : 1.0;
}

- (void)findTransparencyChanged:(id)sender { [self applyFindTransparency]; }

/// In selection means nothing without a selection, so it is greyed out
/// then; a selection big enough ticks it, as Notepad++ does at 1024 characters.
/// FindReplaceDlg's WM_ACTIVATE: "In selection" is offered for one plain
/// selection, and with a threshold other than 0 it is ticked exactly when the
/// selection has that many characters - both ways, so a short selection after a
/// long one clears it (SETTINGS-077). 0 leaves the box as the user set it.
- (void)findOptionBoxChanged:(id)sender {
    NppPreferences *fp = [NppPreferences shared];
    fp.findMatchCase = self.matchCaseBox.state == NSControlStateValueOn;
    fp.findWholeWord = self.wholeWordBox.state == NSControlStateValueOn;
    if (fp.smartHighlightUseFindSettings) [self.editor updateSmartHighlight];
}

- (void)updateInSelectionAvailability {
    ScintillaView *sci = self.editor.sci;
    long start = [sci message:SCI_GETSELECTIONSTART], end = [sci message:SCI_GETSELECTIONEND];
    long characters = end > start ? [sci message:SCI_COUNTCHARACTERS wParam:(uptr_t)start lParam:end] : 0;
    BOOL enabled = characters != 0 && [sci message:SCI_GETSELECTIONMODE] != SC_SEL_RECTANGLE &&
                   [sci message:SCI_GETSELECTIONS] <= 1;
    self.inSelectionBox.enabled = enabled;
    NSInteger threshold = [NppPreferences shared].inSelectionThreshold;
    if (threshold != 0) {
        self.inSelectionBox.state = enabled && characters >= threshold ? NSControlStateValueOn : NSControlStateValueOff;
    } else if (!enabled) {
        self.inSelectionBox.state = NSControlStateValueOff;
    }
}

- (void)findPanelFocusChanged:(NSNotification *)note {
    if ([note.name isEqualToString:NSWindowDidBecomeKeyNotification]) [self updateInSelectionAvailability];
    [self applyFindTransparency];
}

- (void)findPanelFindAllInOpenDocuments:(id)sender {
    NppFindSpec *spec = [self currentFindSpec];
    [self rememberFindFields:NO files:NO];
    NSUInteger hits = 0;
    NSString *report = [self.editor findAllInOpenDocuments:spec hits:&hits];
    [self.editor showSearchResults:report];
    self.findStatus.stringValue = [NSString stringWithFormat:@"%lu found in all opened documents", (unsigned long)hits];
    // Find dialog remains open after search that outputs to results window, or not.
    if (![NppPreferences shared].findDialogStaysOpen) [self.findPanel orderOut:nil];
}

- (void)findPanelReplaceAllInOpenDocuments:(id)sender {
    NppFindSpec *spec = [self currentFindSpec];
    [self rememberFindFields:YES files:NO];
    if (!getenv("NPPMAC_TEST") && [NppPreferences shared].confirmReplaceAllOpenDocs) {
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = @"Replace All in All Opened Documents";
        confirm.informativeText = @"Are you sure you want to replace all occurrences in all open documents?";
        [confirm addButtonWithTitle:@"Replace"];
        [confirm addButtonWithTitle:@"Cancel"];
        if ([confirm runModal] != NSAlertFirstButtonReturn) return;
    }
    [self.editor beginRecordableMenuCommand];
    NSUInteger n = [self.editor replaceAllInOpenDocuments:spec];
    [self.editor recordFindCommand:1635 spec:spec markFlags:0 global:YES];
    self.findStatus.stringValue = [self status:@"Replace in Opened Files: 1 occurrence was replaced"
                                          many:@"Replace in Opened Files: $INT_REPLACE$ occurrences were replaced" count:n];
}

- (void)findPanelCopyMarkedText:(id)sender {
    NSString *text = [self.editor textOfStyle:NPPMAC_STYLE_COUNT];
    if (!text.length) { self.findStatus.stringValue = @"Nothing is marked"; return; }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
    self.findStatus.stringValue = @"Marked text copied";
}

/// The files of the projects in the ticked panels - a panel never opened is
/// loaded with its last workspace first.
- (NSArray<NSString *> *)filesOfTickedProjects {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSInteger panel = 1; panel <= 3; ++panel) {
        if (self.projectPanelBoxes[(NSUInteger)(panel - 1)].state != NSControlStateValueOn) continue;
        NppProjectPanel *p = [self.editor projectPanel:panel];
        if (!p.workspacePath && !p.root.children.count) {
            NSString *last = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppMac.projectWorkspaces"]
                             [[@(panel) stringValue]];
            if (last.length) [p openWorkspace:last];
        }
        for (NSString *f in [p allFilePaths]) if (![files containsObject:f]) [files addObject:f];
    }
    return files;
}

- (void)findPanelReplaceInProjects:(id)sender {
    if (self.runningSearch) return;
    NppFindSpec *spec = [self currentFindSpec];
    [self rememberFindFields:YES files:NO];
    NSArray<NSString *> *files = [self filesOfTickedProjects];
    if (!files.count) { self.findStatus.stringValue = @"The ticked project panels have no files"; return; }
    if (!getenv("NPPMAC_TEST")) {
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = @"Are you sure?";      // replace-in-projects-confirm-*
        confirm.informativeText = @"Do you want to replace all occurrences in all documents in the selected Project Panel(s)?";
        [confirm addButtonWithTitle:@"OK"];
        [confirm addButtonWithTitle:@"Cancel"];
        if ([confirm runModal] != NSAlertFirstButtonReturn) return;
    }
    [self beginSearchUI];
    __weak __typeof(self) weakSelf = self;
    self.runningSearch =
        [self.editor replaceInFilesInBackground:spec paths:files filters:self.filtersField.stringValue
                                       progress:^(NSUInteger scanned, NSUInteger replaced) {
            weakSelf.findStatus.stringValue = [NSString stringWithFormat:@"%lu file%@ searched, %lu replaced",
                (unsigned long)scanned, scanned == 1 ? @"" : @"s", (unsigned long)replaced];
        }
                                     completion:^(NSUInteger replaced, NSUInteger touched, BOOL stopped) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf endSearchUI];
            strongSelf.findStatus.stringValue = [NSString stringWithFormat:@"%lu replaced in %lu file%@%@",
                (unsigned long)replaced, (unsigned long)touched, touched == 1 ? @"" : @"s",
                stopped ? @" (stopped)" : @""];
        }];
}

/// Shows the controls that belong to the tab in front and hides the rest.
- (void)findTabChanged:(id)sender {
    NSArray<NSArray<NSView *> *> *perTab = @[self.findOnlyViews, self.replaceViews,
                                             self.inFilesViews, self.inProjectsViews,
                                             self.markViews];
    NSMutableSet *shown = [NSMutableSet set];
    NSInteger tab = MAX(0, self.findTabs.selectedSegment);
    if (tab < (NSInteger)perTab.count) [shown addObjectsFromArray:perTab[(NSUInteger)tab]];

    NSMutableSet *all = [NSMutableSet set];
    for (NSArray *group in perTab) [all addObjectsFromArray:group];
    for (NSView *view in all) view.hidden = ![shown containsObject:view];
    // The tabs' buttons share their places: the ones now shown take the width their
    // words need, their row moved so that none covers another (German "Nächstes finden").
    NppFlowButtonRows(self.findPanel.contentView);

    // FindReplaceDlg::updateCombos... the title follows the tab in the interface language
    // (the translation's <Find titleFind= titleReplace= titleFindInFiles= ... titleMark=>).
    NSArray *titles = @[@"Find", @"Replace", @"Find in Files", @"Find in Projects", @"Mark"];
    [[NppLocalization shared] setTitle:titles[(NSUInteger)tab] ofWindow:self.findPanel];
    self.findStatus.stringValue = @"";
}

/// What the panel currently describes.
- (NppFindSpec *)currentFindSpec {
    if (!self.findPanel) [self buildFindPanel];
    NppFindSpec *spec = [NppFindSpec specFor:self.findField.stringValue
                                        mode:(NppSearchMode)[self.modeRadios selectedRow]
                                     options:NppFindNone];
    spec.replacement = self.replaceField.stringValue;
    NppFindOptions options = NppFindNone;
    if (self.matchCaseBox.state == NSControlStateValueOn)   options |= NppFindMatchCase;
    if (self.wholeWordBox.state == NSControlStateValueOn)   options |= NppFindWholeWord;
    if (self.wrapBox.state == NSControlStateValueOn)        options |= NppFindWrap;
    if (self.backwardBox.state == NSControlStateValueOn)    options |= NppFindBackward;
    if (self.inSelectionBox.state == NSControlStateValueOn) options |= NppFindInSelection;
    if (self.dotNewlineBox.state == NSControlStateValueOn)  options |= NppFindDotMatchesNewline;
    spec.options = options;
    // The dialog's options are kept between launches, as config.xml keeps them.
    NppPreferences *fp = [NppPreferences shared];
    fp.findMatchCase = (options & NppFindMatchCase) != 0;
    fp.findWholeWord = (options & NppFindWholeWord) != 0;
    fp.findWrap = (options & NppFindWrap) != 0;
    fp.findMode = spec.mode;
    self.lastSearchTerm = spec.what;
    self.lastFindSpec = spec;
    return spec;
}

/// Whole word has no meaning in a regular expression, and ". matches
/// newline" has none outside one: each is greyed out where it does not apply.
- (void)findModeChanged:(id)sender {
    BOOL regex = [self.modeRadios selectedRow] == NppSearchRegex;
    self.wholeWordBox.enabled = !regex;
    self.dotNewlineBox.enabled = regex;
}

/// FindReplaceDlg: a pattern the engine refuses is "Find: Invalid regular
/// expression" (find-status-invalid-re), not "not found" or "0 replaced".
- (BOOL)refusedInvalidPattern:(NppFindSpec *)spec {
    if ([self.editor patternIsValid:spec]) return NO;
    self.findStatus.stringValue = NppL(@"Find: Invalid regular expression");
    NppBeep();   // setStatusbarMessage(..., FSNotFound)
    return YES;
}

- (void)findPanelNext:(id)sender {
    [self rememberFindFields:NO files:NO];
    NppFindSpec *spec = [self currentFindSpec];
    if ([self refusedInvalidPattern:spec]) return;
    [self.editor beginRecordableMenuCommand];
    [self find:spec forward:!(spec.options & NppFindBackward)];
    [self.editor recordFindCommand:1 spec:spec markFlags:0 global:NO];
}

- (void)findPanelCount:(id)sender {
    [self rememberFindFields:NO files:NO];
    if ([self refusedInvalidPattern:[self currentFindSpec]]) return;
    [self.editor beginRecordableMenuCommand];
    NSUInteger n = [self.editor countMatches:[self currentFindSpec]];
    [self.editor recordFindCommand:1614 spec:[self currentFindSpec] markFlags:0 global:YES];
    self.findStatus.stringValue = [self status:@"Count: 1 match" many:@"Count: $INT_REPLACE$ matches" count:n];
}

- (void)findPanelReplace:(id)sender {
    [self rememberFindFields:YES files:NO];
    NppFindSpec *spec = [self currentFindSpec];
    if ([self refusedInvalidPattern:spec]) return;
    [self.editor beginRecordableMenuCommand];
    self.findStatus.stringValue = [self.editor replaceCurrentThenFindNext:spec] ? @"" : NppL(@"Replace: no occurrence was found");
    [self.editor recordFindCommand:1608 spec:spec markFlags:0 global:NO];
}

- (void)findPanelReplaceAll:(id)sender {
    [self rememberFindFields:YES files:NO];
    if ([self refusedInvalidPattern:[self currentFindSpec]]) return;
    // Searching > "Confirm Replace All" (the port's own box, beside upstream's for all
    // opened documents): asks as that one does, in the document's words.
    if (!getenv("NPPMAC_TEST") && [NppPreferences shared].confirmReplaceAll) {
        NSAlert *confirm = [[NSAlert alloc] init];
        confirm.messageText = @"Replace All";
        confirm.informativeText = @"Are you sure you want to replace all occurrences in the current document?";
        [confirm addButtonWithTitle:@"Replace"];
        [confirm addButtonWithTitle:@"Cancel"];
        if ([confirm runModal] != NSAlertFirstButtonReturn) return;
    }
    [self.editor beginRecordableMenuCommand];
    NSUInteger n = [self.editor replaceAll:[self currentFindSpec]];
    [self.editor recordFindCommand:1609 spec:[self currentFindSpec] markFlags:0 global:NO];
    self.findStatus.stringValue = [self status:@"Replace All: 1 occurrence was replaced"
                                          many:@"Replace All: $INT_REPLACE$ occurrences were replaced" count:n];
}

- (void)findPanelBrowse:(id)sender {
    NSOpenPanel *chooser = [NSOpenPanel openPanel];
    chooser.canChooseDirectories = YES;
    chooser.canChooseFiles = NO;
    if ([chooser runModal] != NSModalResponseOK || !chooser.URL) return;
    self.directoryField.stringValue = chooser.URL.path;
}

- (void)findPanelDirectoryFromDocument:(id)sender {
    NSString *path = self.editor.currentDocument.path;
    if (!path.length) { self.findStatus.stringValue = @"This document has no folder"; return; }
    self.directoryField.stringValue = path.stringByDeletingLastPathComponent;
}

/// Find All in the current document: every match listed in the results panel.
- (void)findPanelFindAll:(id)sender {
    [self rememberFindFields:NO files:NO];
    NSUInteger hits = 0;
    NSString *report = [self.editor findAllReport:[self currentFindSpec] hits:&hits];
    [self.editor showSearchResults:report];
    self.findStatus.stringValue = [NSString stringWithFormat:@"%lu found", (unsigned long)hits];
    // Find dialog remains open after search that outputs to results window, or not.
    if (![NppPreferences shared].findDialogStaysOpen) [self.findPanel orderOut:nil];
}

- (void)findPanelFindInFiles:(id)sender {
    if (self.runningSearch) return;
    [self rememberFindFields:NO files:YES];
    NppFindSpec *spec = [self currentFindSpec];
    NSString *folder = self.directoryField.stringValue;
    if (!folder.length) { self.findStatus.stringValue = @"Choose a folder first"; return; }

    // The search runs on its own queue: the window keeps answering, the results
    // tab fills as hits turn up, and Stop calls it off.
    [self.editor showSearchResults:[NSString stringWithFormat:@"Search \"%@\" (%@)\n\nSearching...\n",
                                    spec.what, folder]];
    [self beginSearchUI];
    __weak __typeof(self) weakSelf = self;
    self.runningSearch =
        [self.editor findInFilesInBackground:spec
                                      folder:folder
                                     filters:self.filtersField.stringValue
                                   recursive:self.recursiveBox.state == NSControlStateValueOn
                               includeHidden:self.hiddenBox.state == NSControlStateValueOn
                                    progress:^(NSUInteger scanned, NSUInteger hits, NSString *soFar) {
            __typeof(self) strongSelf = weakSelf;
            strongSelf.findStatus.stringValue =
                [NSString stringWithFormat:@"%lu file%@ searched, %lu found",
                 (unsigned long)scanned, scanned == 1 ? @"" : @"s", (unsigned long)hits];
            [strongSelf.editor updateSearchResults:soFar];
        }
                                  completion:^(NSUInteger hits, NSString *report, BOOL stopped) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf endSearchUI];
            [strongSelf.editor updateSearchResults:report];
            if (!strongSelf.editor.currentDocument.isSearchResults) {
                [strongSelf.editor showSearchResults:report];
            }
            strongSelf.findStatus.stringValue =
                [NSString stringWithFormat:@"%lu found%@", (unsigned long)hits,
                 stopped ? @" (stopped)" : @""];
        }];
}

/// The panel while a folder search is running: progress showing, Stop offered,
/// and the buttons that would start another one out of reach.
- (void)beginSearchUI {
    self.findStopButton.hidden = NO;
    for (NSButton *button in self.findSearchButtons) button.enabled = NO;
    [self.findProgress startAnimation:nil];
    self.findStatus.stringValue = @"Searching...";
}

- (void)endSearchUI {
    self.runningSearch = nil;
    self.findStopButton.hidden = YES;
    for (NSButton *button in self.findSearchButtons) button.enabled = YES;
    [self.findProgress stopAnimation:nil];
}

- (void)findPanelStop:(id)sender {
    [self.runningSearch cancel];
    self.findStatus.stringValue = @"Stopping...";
}


- (void)findPanelReplaceInFiles:(id)sender {
    if (self.runningSearch) return;
    [self rememberFindFields:YES files:YES];
    NppFindSpec *spec = [self currentFindSpec];
    NSString *folder = self.directoryField.stringValue;
    if (!folder.length) { self.findStatus.stringValue = @"Choose a folder first"; return; }

    // Changing files on disk that are not open is worth asking about, which is
    // what Notepad++ does too.
    NSAlert *confirm = [[NSAlert alloc] init];
    // replace-in-files-confirm-*: the folder, then the file types.
    confirm.messageText = @"Are you sure?";
    confirm.informativeText = [NSString stringWithFormat:@"%@\n%@\n\n%@\n%@",
        NppL(@"Are you sure you want to replace all occurrences in:"), folder,
        NppL(@"For file type:"), self.filtersField.stringValue.length ? self.filtersField.stringValue : @"*.*"];
    [confirm addButtonWithTitle:@"OK"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    [self beginSearchUI];
    __weak __typeof(self) weakSelf = self;
    self.runningSearch =
        [self.editor replaceInFilesInBackground:spec
                                         folder:folder
                                        filters:self.filtersField.stringValue
                                      recursive:self.recursiveBox.state == NSControlStateValueOn
                                  includeHidden:self.hiddenBox.state == NSControlStateValueOn
                                       progress:^(NSUInteger scanned, NSUInteger replaced) {
            __typeof(self) strongSelf = weakSelf;
            strongSelf.findStatus.stringValue =
                [NSString stringWithFormat:@"%lu file%@ searched, %lu replaced",
                 (unsigned long)scanned, scanned == 1 ? @"" : @"s", (unsigned long)replaced];
        }
                                     completion:^(NSUInteger replaced, NSUInteger files, BOOL stopped) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf endSearchUI];
            strongSelf.findStatus.stringValue =
                [NSString stringWithFormat:@"%lu replaced in %lu file%@%@",
                 (unsigned long)replaced, (unsigned long)files, files == 1 ? @"" : @"s",
                 stopped ? @" (stopped)" : @""];
        }];
}


/// The projects tab searches the folders the project panels are rooted at.
- (void)findPanelFindInProjects:(id)sender {
    if (self.runningSearch) return;
    [self rememberFindFields:NO files:NO];
    NppFindSpec *spec = [self currentFindSpec];

    NSArray<NSString *> *files = [self filesOfTickedProjects];
    if (!files.count) { self.findStatus.stringValue = @"The ticked project panels have no files"; return; }

    [self.editor showSearchResults:[NSString stringWithFormat:@"Search \"%@\" in the projects\n\nSearching...\n",
                                    spec.what]];
    [self beginSearchUI];
    __weak __typeof(self) weakSelf = self;
    self.runningSearch =
        [self.editor findInFilesInBackground:spec paths:files title:@"the projects"
                                     filters:self.filtersField.stringValue
                                    progress:^(NSUInteger scanned, NSUInteger found, NSString *soFar) {
            __typeof(self) strongSelf = weakSelf;
            strongSelf.findStatus.stringValue = [NSString stringWithFormat:@"%lu file%@ searched, %lu found",
                (unsigned long)scanned, scanned == 1 ? @"" : @"s", (unsigned long)found];
            [strongSelf.editor updateSearchResults:soFar];
        }
                                  completion:^(NSUInteger found, NSString *report, BOOL stopped) {
            __typeof(self) strongSelf = weakSelf;
            [strongSelf endSearchUI];
            [strongSelf.editor updateSearchResults:report];
            if (!strongSelf.editor.currentDocument.isSearchResults) {
                [strongSelf.editor showSearchResults:report];
            }
            strongSelf.findStatus.stringValue = [NSString stringWithFormat:@"%lu found%@",
                                                 (unsigned long)found, stopped ? @" (stopped)" : @""];
        }];
}

- (void)findPanelClearMarks:(id)sender {
    [self.editor clearStyle:NPPMAC_STYLE_COUNT];
    self.findStatus.stringValue = @"Marks cleared";
}

- (void)findPanelMarkAll:(id)sender {
    [self rememberFindFields:NO files:NO];
    NppFindSpec *spec = [self currentFindSpec];
    BOOL purge = self.purgeBox.state == NSControlStateValueOn;
    // Purging also takes away the bookmarks an earlier Mark All put in.
    if (purge && self.bookmarkLineBox.state == NSControlStateValueOn) {
        [self.editor.sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
    }
    NSUInteger n = [self.editor markAll:spec purge:purge];

    // Notepad++ can put a bookmark on every line it marks.
    if (self.bookmarkLineBox.state == NSControlStateValueOn) {
        ScintillaView *sci = self.editor.sci;
        for (NSValue *match in [self.editor rangesOfMatches:spec]) {
            long line = [sci message:SCI_LINEFROMPOSITION
                               wParam:(uptr_t)match.rangeValue.location];
            [sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:1];   // the bookmark marker
        }
    }
    self.findStatus.stringValue = [self status:@"Mark: 1 match" many:@"Mark: $INT_REPLACE$ matches" count:n];
    [self.editor recordFindCommand:1615 spec:spec
                         markFlags:(purge ? 4 : 0) | (self.bookmarkLineBox.state == NSControlStateValueOn ? 16 : 0) global:YES];
}

- (void)findNext:(id)sender {
    if (!self.lastFindSpec.what.length) { [self showFind:sender]; return; }
    NppFindSpec *spec = self.lastFindSpec;
    NppFindOptions saved = spec.options;
    spec.options = saved & ~NppFindBackward;
    if (![self.editor findNext:spec]) NppBeep();
    spec.options = saved;
}

- (void)findPrevious:(id)sender {
    if (!self.lastFindSpec.what.length) { [self showFind:sender]; return; }
    NppFindSpec *spec = self.lastFindSpec;
    NppFindOptions saved = spec.options;
    spec.options = saved | NppFindBackward;
    if (![self.editor findNext:spec]) NppBeep();
    spec.options = saved;
}

/// Returns YES when a match was found and selected.
///
/// SCI_SEARCHINTARGET returns -1 when there is no match and leaves the target
/// range untouched, so the result must be read from the return value. Reading
/// SCI_GETTARGETSTART/END instead reports the range we just set as a hit.
- (BOOL)searchFrom:(long)start forward:(BOOL)forward wrap:(BOOL)wrap {
    ScintillaView *sci = self.editor.sci;
    NSString *term = self.lastSearchTerm;
    if (!term.length) return NO;

    const char *needle = term.UTF8String;
    long needleLen = (long)strlen(needle);
    long docLen = [sci message:SCI_GETLENGTH];

    long found = [self searchTarget:forward ? start : 0
                                 to:forward ? docLen : start
                             needle:needle length:needleLen];

    if (found < 0 && wrap) {
        found = [self searchTarget:forward ? 0 : docLen
                                to:forward ? docLen : 0
                            needle:needle length:needleLen];
    }
    if (found < 0) { NppBeep(); return NO; }

    // Backwards: SCI_SEARCHINTARGET reports the first hit in the range, so take
    // the last one before the caret instead.
    if (!forward) {
        long best = found, probe = found;
        while (probe >= 0) {
            long nextStart = probe + 1;
            if (nextStart >= (forward ? docLen : start)) break;
            probe = [self searchTarget:nextStart to:start needle:needle length:needleLen];
            if (probe >= 0) best = probe;
        }
        found = best;
    }

    [sci message:SCI_SETSEL wParam:(uptr_t)found lParam:found + needleLen];
    [sci message:SCI_SCROLLCARET];
    return YES;
}

/// One SCI_SEARCHINTARGET pass; returns the match position or -1.
- (long)searchTarget:(long)from to:(long)to needle:(const char *)needle length:(long)len {
    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
    [sci message:SCI_SETTARGETEND wParam:(uptr_t)to lParam:0];
    [sci message:SCI_SETSEARCHFLAGS wParam:0 lParam:0];
    return [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
}

- (void)goToLine:(id)sender {
    ScintillaView *sci = self.editor.sci;
    long lines = [sci message:SCI_GETLINECOUNT];
    long length = [sci message:SCI_GETLENGTH];
    NSString *s = [self promptForString:
        [NSString stringWithFormat:@"Go to line (1 to %ld), or @offset (0 to %ld)", lines, length]
                                default:@""];
    if (!s.length) return;
    if (![self goToLineOrOffset:s]) NppBeep();
}

- (BOOL)goToLineOrOffset:(NSString *)s {
    ScintillaView *sci = self.editor.sci;
    long lines = [sci message:SCI_GETLINECOUNT];
    long length = [sci message:SCI_GETLENGTH];
    // An offset, as the Windows dialog's second radio button: written with a
    // leading @ here. As GoToLineDlg::run_dlgProc (IDOK) does it: an offset is
    // snapped with POSITIONAFTER(POSITIONBEFORE(offset)) - never inside a
    // character or a CRLF, and the end stays the end - and a line past the end
    // goes to the last line (SCI_GOTOLINE clamps).
    if ([s hasPrefix:@"@"]) {
        long offset = [s substringFromIndex:1].integerValue;
        if (offset < 0) return NO;
        if (offset > length) offset = length;
        if (offset > 0) offset = [sci message:SCI_POSITIONAFTER wParam:(uptr_t)[sci message:SCI_POSITIONBEFORE wParam:(uptr_t)offset]];
        [sci message:SCI_ENSUREVISIBLE wParam:(uptr_t)[sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)offset]];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)offset lParam:0];
    } else {
        long line = s.integerValue;
        if (line < 1) return NO;
        if (line > lines) line = lines;
        [sci message:SCI_ENSUREVISIBLE wParam:(uptr_t)(line - 1)];
        [sci message:SCI_GOTOLINE wParam:(uptr_t)(line - 1) lParam:0];
    }
    [self.editor refreshChrome];
    return YES;
}

#pragma mark - Test suite

- (void)runTestSuite {
    int failures = NppMacRunTests(self);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);   // exit code carries the result to CI
}

#pragma mark - Snapshot

/// Renders the window's content view straight to a PNG. This deliberately does
/// not go through screencapture(1), which needs Screen Recording permission and
/// silently returns a desktop with no windows when it is not granted.
///
/// Caveat: cacheDisplayInRect: captures Scintilla (which draws itself) but not
/// the text of AppKit controls, so the tab bar and status bar come out blank.
/// Their contents are covered by the self-test instead.
- (void)writeSnapshot {
    const char *dest = getenv("NPPMAC_SNAPSHOT");
    if (!dest) { [NSApp terminate:nil]; return; }

    // Give the caller something worth looking at rather than an empty buffer.
    NSString *sample = getenv("NPPMAC_SNAPSHOT_FILE")
        ? @(getenv("NPPMAC_SNAPSHOT_FILE")) : nil;
    if (sample.length) {
        NSError *err = nil;
        if (![self.editor openFileAtPath:sample error:&err]) {
            fprintf(stderr, "snapshot: cannot open %s\n", sample.UTF8String);
        }
    }
    // Optional: show the split panes so a snapshot can demonstrate them.
    if (getenv("NPPMAC_SNAPSHOT_SPLIT")) {
        [self.editor cloneCurrentToOtherView];
        [self.editor setSyncVerticalScroll:YES];
        [self.editor.secondarySci message:SCI_SETFIRSTVISIBLELINE wParam:40 lParam:0];
    }
    if (getenv("NPPMAC_SNAPSHOT_DOCK")) {
        [self toggleDocumentList:nil];
        [self toggleFunctionList:nil];
        [self.editor setDocumentMapVisible:YES];
        [self.editor openFolderAsWorkspace:[self.editor containingFolderURL].path];
    }
    // NPPMAC_SNAPSHOT_COMPARE=<path>: the sample compared with that file, as Compare shows it.
    if (getenv("NPPMAC_SNAPSHOT_COMPARE")) {
        [self.editor compareWithFileAtPath:@(getenv("NPPMAC_SNAPSHOT_COMPARE"))];
        [self.editor.sci setNeedsDisplay:YES];
        [self.editor.sci display];
    }
    if (getenv("NPPMAC_SNAPSHOT_MAP")) {
        [self.editor setDocumentMapVisible:YES];
        [self.editor.sci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)atoi(getenv("NPPMAC_SNAPSHOT_MAP")) lParam:0];
        [self.editor updateDocumentMap];
    }
    [self.editor refreshChrome];
    // Force the whole hierarchy to redraw before capturing; a split pane can
    // otherwise be cached from a backing store that was never painted.
    [self.window.contentView setNeedsDisplay:YES];
    [self.window displayIfNeeded];
    [self.editor.view displayIfNeeded];

    NSView *view = self.window.contentView;
    // NPPMAC_SNAPSHOT_PANEL=find:<tab>, prefs:<page>, style, mapper, about, debug, commit or git captures that dialog instead.
    const char *panel = getenv("NPPMAC_SNAPSHOT_PANEL");
    if (panel && !strncmp(panel, "find", 4)) {
        [self openFindPanelOnTab:strlen(panel) > 5 ? atoi(panel + 5) : 0];
        view = self.findPanel.contentView;
    } else if (panel && !strncmp(panel, "prefs:", 6)) {
        [self showPreferences:nil];
        NSArray *names = [self.prefsWindow valueForKey:@"pageNames"];
        NSUInteger index = [names indexOfObject:@(panel + 6)];
        if (index != NSNotFound) [self.prefsWindow showPageAtIndex:(NSInteger)index];
        view = [[self.prefsWindow valueForKey:@"panel"] contentView];
    } else if (panel && !strcmp(panel, "style")) {
        [self showStyleConfigurator:nil];
        view = [[self.styleWindow valueForKey:@"panel"] contentView];
    } else if (panel && !strcmp(panel, "mapper")) {
        [self showShortcutMapper:nil];
        NSWindow *mapperWindow = [self.shortcutMapper valueForKey:@"panel"];
        [[NppLocalization shared] localizeWindow:mapperWindow];
        view = mapperWindow.contentView;
    } else if (panel && !strcmp(panel, "about")) {
        [self showAbout:nil];
        view = [NppAboutWindow shared].panel.contentView;
    } else if (panel && !strcmp(panel, "debug")) {
        [self showDebugInfo:nil];
        view = [NppDebugInfoWindow shared].panel.contentView;
    } else if (panel && !strcmp(panel, "commit")) {
        // The Git commit window, on whatever file is open (NPPMAC_SNAPSHOT_FILE opens one first).
        [[NppCommitWindow shared] showForEditor:self.editor];
        view = [NppCommitWindow shared].panel.contentView;
        [view.window.contentView layoutSubtreeIfNeeded];
    } else if (panel && !strcmp(panel, "git")) {
        // The Git panel, floating, at a panel's usual size.
        [[NppDockingManager shared] movePanel:@"git" to:NppDockFloating];
        [[self.editor gitPanel] show];
        view = [self.editor gitPanel].table.enclosingScrollView.superview;
        [view.window.contentView layoutSubtreeIfNeeded];
    } else if (panel && !strncmp(panel, "tools:", 6)) {
        // tools:digest, tools:files, tools:bcrypt, tools:scrypt, tools:argon2, tools:pbkdf2, tools:base, tools:unbase, tools:password, tools:converter
        NSString *which = @(panel + 6);
        NSUInteger kind = [@[@"bcrypt", @"scrypt", @"argon2", @"pbkdf2"] indexOfObject:which];
        if ([which isEqualToString:@"digest"] || [which isEqualToString:@"files"]) {
            NppDigestWindow *w = [NppDigestWindow shared];
            [w showForDigest:NppDigestSHA256 fromFiles:[which isEqualToString:@"files"]];
            w.input.string = @"The quick brown fox\njumps over the lazy dog"; [w refresh];
            view = w.panel.contentView;
        } else if (kind != NSNotFound) {
            NppPasswordHashWindow *w = [NppPasswordHashWindow shared];
            [w showForKind:(NppPasswordHash)kind fromFiles:NO];
            w.input.string = @"correct horse battery staple";
            if (kind == NppPasswordHashBcrypt) [(NSTextField *)w.fields[@"bcryptCost"] setStringValue:@"6"];
            if (kind == NppPasswordHashPBKDF2) [(NSTextField *)w.fields[@"pbkdf2Rounds"] setStringValue:@"1000"];
            [w refreshAndWait];
            w.toVerify.stringValue = w.result.string; [w verifyAndWait];
            view = w.panel.contentView;
        } else if ([which hasSuffix:@"base"]) {
            NppBaseWindow *w = [NppBaseWindow shared];
            [w showForEncoding:NppBase58];
            BOOL decoding = [which isEqualToString:@"unbase"];
            w.direction.selectedSegment = decoding ? 1 : 0;
            w.input.string = decoding ? @"2NEpo7TZRRrLZSi2U" : @"Hello World!"; [w refresh];
            view = w.panel.contentView;
        } else if ([which hasPrefix:@"http"]) {
            // tools:http, or tools:http:<address> to send a request and show its answer
            [self showHttpRequest:nil];
            NppHttpWindow *w = [NppHttpWindow shared];
            if (which.length > 5) { w.address.stringValue = [which substringFromIndex:5]; [w sendAndWait]; }
            view = w.panel.contentView;
        } else if ([which isEqualToString:@"converter"]) {
            [self showConversionPanel:nil];
            NppConverterWindow *w = [NppConverterWindow shared];
            w.hex.stringValue = @"ff";
            [w syncFrom:w.hex];
            view = w.panel.contentView;
        } else {
            [self showPasswordGenerator:nil];
            view = [NppPasswordWindow shared].panel.contentView;
        }
        [view.window.contentView layoutSubtreeIfNeeded];
    }
    if (panel && (!strcmp(panel, "about") || !strcmp(panel, "debug") || !strcmp(panel, "mapper") || !strncmp(panel, "tools:", 6) ||
                  !strcmp(panel, "commit") || !strcmp(panel, "git"))) {
        // The window's frame draws its background, which a view capture leaves out.
        view.wantsLayer = YES;
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
            view.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
        }];
    }
    [view.window displayIfNeeded];

    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

    if ([png writeToFile:@(dest) atomically:YES]) {
        printf("SNAPSHOT wrote %s (%.0fx%.0f)\n", dest, view.bounds.size.width, view.bounds.size.height);
    } else {
        fprintf(stderr, "SNAPSHOT failed to write %s\n", dest);
    }
    [NSApp terminate:nil];
}

#pragma mark - Self-test

- (void)runSelfTest {
    LanguageCatalog *langs = [LanguageCatalog sharedCatalog];
    StyleCatalog *styles = [StyleCatalog sharedCatalog];

    printf("SELFTEST languages_loaded=%lu\n", (unsigned long)langs.allLanguages.count);
    printf("SELFTEST cpp_styles_loaded=%lu\n",
           (unsigned long)[styles stylesForLexerName:@"cpp"].count);
    printf("SELFTEST global_styles_loaded=%lu\n", (unsigned long)styles.globalStyles.count);

    // Extension -> language -> lexer, straight from Notepad++'s own data.
    NSArray *probes = @[@"a.cpp", @"b.py", @"c.rs", @"d.json", @"e.sh", @"f.unknownext"];
    for (NSString *p in probes) {
        NppLanguage *l = [langs languageForFileName:p];
        printf("SELFTEST detect %-14s -> lang=%-10s lexer=%s\n",
               p.UTF8String, l.name.UTF8String, l.lexerID.UTF8String);
    }

    // Open a real file through the normal path and confirm it lexes.
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nppmac_selftest.py"];
    [@"# comment\ndef f(x):\n    return x + 1\n" writeToFile:tmp atomically:YES
                                                  encoding:NSUTF8StringEncoding error:NULL];
    NSError *err = nil;
    BOOL opened = [self.editor openFileAtPath:tmp error:&err];
    printf("SELFTEST open_file=%s tabs=%lu lang=%s\n",
           opened ? "OK" : "FAIL",
           (unsigned long)self.editor.documents.count,
           self.editor.currentDocument.language.name.UTF8String);

    ScintillaView *sci = self.editor.sci;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    long style0 = [sci message:SCI_GETSTYLEAT wParam:0];
    printf("SELFTEST python_comment_style=%ld (SCE_P_COMMENTLINE=%d) match=%s\n",
           style0, SCE_P_COMMENTLINE, style0 == SCE_P_COMMENTLINE ? "YES" : "NO");

    // Search must find a known token.
    self.lastSearchTerm = @"return";
    BOOL found = [self searchFrom:0 forward:YES wrap:YES];
    printf("SELFTEST search_found=%s\n", found ? "YES" : "NO");

    // The snapshot cannot capture AppKit control text, so assert the chrome here.
    for (NSUInteger i = 0; i < self.editor.documents.count; ++i) {
        printf("SELFTEST tab[%lu]=\"%s\"\n", (unsigned long)i,
               self.editor.documents[i].displayName.UTF8String);
    }
    NSString *status = [self.editor valueForKey:@"statusField"]
        ? [(NSTextField *)[self.editor valueForKey:@"statusField"] stringValue] : @"";
    printf("SELFTEST status_nonempty=%s fields=%s\n",
           status.length ? "YES" : "NO",
           ([status containsString:@"Ln "] && [status containsString:@"lines"]) ? "OK" : "MISSING");

    printf("SELFTEST menus=%ld\n", (long)NSApp.mainMenu.numberOfItems);
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    [NSApp terminate:nil];
}

@end
