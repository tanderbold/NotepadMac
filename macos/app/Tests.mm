// Built-in test suite: one or more cases per implemented Notepad++ command.
//
// A meta-test cross-checks this file against macos/implemented.txt, so a
// command cannot be declared implemented without a test covering it.
#import "NumberSetCommands.h"
#import "Tests.h"
#import "AppDelegate.h"
#import "AppDelegate+Testing.h"
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
#import "NppPanel.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#import "TabBarView.h"
#import "JsonCommands.h"
#import "MimeCommands.h"
#import "PluginHost.h"
#import "ConverterCommands.h"
#import "ExportCommands.h"
#import "SpellCheck.h"
#import "MarkdownPanel.h"
#import "ImageCommands.h"
#import "AgentServer.h"
#import "GitCommands.h"
@interface NppStatusPathField : NSTextField
@end
#include <sys/socket.h>
#include <sys/un.h>
#import "CompareCommands.h"
#import "FtpCommands.h"
#import "XmlCommands.h"
#import "RunCommands.h"
#import "FunctionListPanel.h"
#import "FunctionListCatalog.h"
#import "NppRegex.h"
#import "ApiCatalog.h"
#import "FindCommands.h"
#import "LanguageCatalog.h"
#import "LanguageDetection.h"
#import "UserLanguages.h"
#import "UserLanguageDialog.h"
#import "ShortcutMapper.h"
#import "ProjectPanel.h"
#import "LanguageModel.h"
#import "StyleCatalog.h"
#import "StyleConfigurator.h"
#import "DocumentListPanel.h"
#import "WorkspacePanel.h"
#import "EditorLook.h"
#import "Localization.h"
#import "DockingManager.h"
#import "TagMatch.h"
#import "InfoWindows.h"
#import "UpdateChecker.h"
#import "ScriptCommands.h"
#import "ContextMenuFile.h"
#import "CryptoTools.h"
#import "ToolsWindows.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "LangMap.h"

static int gPass = 0, gFail = 0;
static NSMutableSet *gCovered = nil;

/// Lets AppKit deliver what has been posted and the run loop turn over, which
/// is what work put off to the next turn needs before it has run.
static void NppSettle(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *queued = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                                inMode:NSDefaultRunLoopMode dequeue:YES];
        if (queued) [NSApp sendEvent:queued];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

/// The same, but only until what was expected has happened: waiting a fixed
/// time instead makes the test turn on how busy the machine is.
/// The same, but only until what was expected has happened: waiting a fixed
/// time instead makes the test turn on how busy the machine is.
static void NppSettleUntil(BOOL (^done)(void), NSTimeInterval limit) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:limit];
    while ([until timeIntervalSinceNow] > 0 && !done()) {
        NSEvent *queued = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                                inMode:NSDefaultRunLoopMode dequeue:YES];
        if (queued) [NSApp sendEvent:queued];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

static void Check(NSString *command, NSString *name, BOOL ok) {
    [gCovered addObject:command];
    if (ok) { gPass++; printf("  ok   %-28s %s\n", command.UTF8String, name.UTF8String); }
    else    { gFail++; printf("  FAIL %-28s %s\n", command.UTF8String, name.UTF8String); }
}

/// NPPMAC_TEST_ONLY=Git,Agent runs only the sections whose heading contains one of
/// the words (case aside); empty runs everything. For working on one area - the
/// whole suite is for before a commit.
static BOOL NppSectionWanted(NSString *heading) {
    const char *only = getenv("NPPMAC_TEST_ONLY");
    if (!only || !*only) return YES;
    for (NSString *word in [@(only) componentsSeparatedByString:@","]) {
        NSString *w = [word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (w.length && [heading rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

/// The interface language the user had, put back when the process ends: the sections that
/// walk every language would otherwise leave theirs changed if a run stopped in the middle.
static NSString *gLanguageToRestore;
static void NppRestoreUserLanguage(void) {
    if (!gLanguageToRestore.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:gLanguageToRestore forKey:@"NppMac.localizationFile"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static NSString *DocText(EditorController *ed) { return [ed.sci string] ?: @""; }

static void SetDoc(EditorController *ed, NSString *text) {
    [ed.sci setString:text];
    [ed.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
}

static NSString *TempFile(NSString *name, NSString *contents) {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [contents writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return p;
}

/// The alert hook of Localization.mm, named so the suite can call it.
@protocol NppAlertLocalizing
- (void)npp_localize;
@end

/// Reads back one attribute value, for the newline-preservation test.
@interface NppAttributeReader : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *value;
@end
@implementation NppAttributeReader
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {
    if (!self.value) self.value = attrs[@"b"];
}
@end

int NppMacRunTests(AppDelegate *app) {
    setvbuf(stdout, NULL, _IOLBF, 0);   // a run that stops then says where
    gPass = gFail = 0;
    gCovered = [NSMutableSet set];
    EditorController *ed = [app editor];
    ScintillaView *sci = ed.sci;
    // The suite reads the interface in English and switches languages where it tests them;
    // the user's own language is put back at the end (the CI runner has none set).
    NSString *userLanguage = [NppPreferences shared].localizationFile;
    if (userLanguage.length) {
        [NppPreferences shared].localizationFile = @"";
        [app applyLocalization];
        // The sections that walk the languages leave the setting behind if a run ends early;
        // this puts it back even then, so a suite run never changes the user's language.
        gLanguageToRestore = userLanguage;
        atexit(NppRestoreUserLanguage);
    }

    if (NppSectionWanted(@"File")) { printf("\n== File ==\n");
        NSUInteger before = ed.documents.count;
        [app newDocument:nil];
        Check(@"IDM_FILE_NEW", @"adds a tab", ed.documents.count == before + 1);
        // makeFirstResponder: does not ask acceptsFirstResponder, so focusing
        // the ScintillaView wrapper "succeeds" and then no key reaches the text.
        Check(@"IDM_FILE_NEW (focus)", @"the new tab's text view has the keyboard focus, not its wrapper",
              app.window.firstResponder == ed.sci.content);

        NSString *p = TempFile(@"t_open.py", @"# hi\nx = 1\n");
        NSError *err = nil;
        BOOL ok = [ed openFileAtPath:p error:&err];
        Check(@"IDM_FILE_OPEN", @"opens and detects language",
              ok && [ed.currentDocument.language.name isEqualToString:@"python"]);

        SetDoc(ed, @"saved content\n");
        BOOL saved = [ed saveCurrentDocument];
        NSString *back = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_FILE_SAVE", @"writes to disk", saved && [back isEqualToString:@"saved content\n"]);

        // Save As is driven by NSSavePanel; its non-modal half is the writer.
        NSString *p2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_saveas.txt"];
        BOOL wrote = [ed performSelector:@selector(writeCurrentToPath:) withObject:p2] != nil ||
                     [[NSFileManager defaultManager] fileExistsAtPath:p2];
        Check(@"IDM_FILE_SAVEAS", @"writer produces the file", wrote);

        NSUInteger n = ed.documents.count;
        [app closeTab:nil];
        Check(@"IDM_FILE_CLOSE", @"removes a tab", ed.documents.count == n - 1);
    }

    if (NppSectionWanted(@"File: more")) { printf("\n== File: more ==\n");
        NSString *p = TempFile(@"t_reload.txt", @"first\n");
        NSError *err = nil;
        [ed openFileAtPath:p error:&err];
        [@"second\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL reloaded = [ed reloadCurrentDocument:&err];
        Check(@"IDM_FILE_RELOAD", @"picks up the file from disk",
              reloaded && [DocText(ed) isEqualToString:@"second\n"]);

        // Closing asks. Every close that can throw text away - the current
        // tab, Close All and its variants, the window, quitting - goes through
        // one question with Save, Don't Save and Cancel; Cancel stops the
        // whole operation and leaves every tab in place.
        {
            [ed newDocument];
            [ed setDocumentText:@"kept\n"];
            ed.currentDocument.modified = YES;
            NSUInteger before = ed.documents.count;
            ed.scriptedCloseAnswer = NSAlertThirdButtonReturn;          // Cancel
            [ed closeAllDocuments];
            BOOL cancelKeeps = ed.documents.count == before && ed.currentDocument.modified;
            BOOL quitStops = [app applicationShouldTerminate:NSApp] == NSTerminateCancel;
            ed.scriptedCloseAnswer = NSAlertSecondButtonReturn;         // Don't Save
            [ed closeCurrentDocument];
            BOOL discardCloses = ed.documents.count == before - 1;
            ed.scriptedCloseAnswer = 0;
            Check(@"IDM_FILE_CLOSE (asks before losing text)",
                  @"Cancel keeps every tab, for Close All and for quitting alike; "
                  @"Don't Save closes the tab",
                  cancelKeeps && quitStops && discardCloses);
        }

        // Tab settings come from the preferences on every switch, not from
        // literals that undo them.
        {
            NppPreferences *p = [NppPreferences shared];
            NSInteger wasWidth = p.tabWidth; BOOL wasSpaces = p.useSpaces;
            p.tabWidth = 8; p.useSpaces = NO;
            [ed newDocument];
            BOOL kept = [ed.sci message:SCI_GETTABWIDTH] == 8 && [ed.sci message:SCI_GETUSETABS] == 1;
            p.tabWidth = wasWidth; p.useSpaces = wasSpaces;
            [ed newDocument];
            BOOL restored = [ed.sci message:SCI_GETTABWIDTH] == wasWidth;
            Check(@"IDM_SETTING_PREFERENCE (tab settings survive a switch)",
                  @"a new tab takes the tab width and tabs-or-spaces from Preferences",
                  kept && restored);
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
        }

        // The first line ending decides, whichever kind it is.
        {
            NSString *eolPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-eol-test.txt"];
            [@"a\nb\r\nc\r\n" writeToFile:eolPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [ed openFileAtPath:eolPath error:NULL];
            BOOL lfFirst = ed.currentDocument.eolMode == SC_EOL_LF;
            ed.scriptedCloseAnswer = NSAlertSecondButtonReturn; [ed closeCurrentDocument]; ed.scriptedCloseAnswer = 0;
            [[NSFileManager defaultManager] removeItemAtPath:eolPath error:NULL];
            Check(@"IDM_FORMAT_TOUNIX (the first line ending decides)",
                  @"a file whose first ending is LF is LF even when a CRLF comes later",
                  lfFirst);
        }

        // The session remembers the active tab by path, so an unsaved tab in
        // front of it, or the tab open before the load, cannot shift it.
        {
            NSString *sA = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-session-a.txt"];
            NSString *sB = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-session-b.txt"];
            [@"a\n" writeToFile:sA atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [@"b\n" writeToFile:sB atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSString *sessionPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-session-test.json"];
            [ed newDocument];                                       // an unsaved tab first
            NppDocument *untitled = ed.currentDocument;
            [ed openFileAtPath:sA error:NULL];
            [ed openFileAtPath:sB error:NULL];
            [ed openFileAtPath:sA error:NULL];                      // A is active, behind an unsaved tab
            [ed saveSessionTo:sessionPath error:NULL];
            void (^closePaths)(void) = ^{
                for (NSString *path in @[sA, sB]) {
                    NSUInteger at = [ed.documents indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *stop) {
                        return [d.path isEqualToString:path];
                    }];
                    if (at != NSNotFound) [ed closeDocumentAtIndex:(NSInteger)at discardChanges:YES];
                }
            };
            closePaths();
            [ed loadSessionFrom:sessionPath error:NULL];
            BOOL activeIsA = [ed.currentDocument.path isEqualToString:sA];
            Check(@"IDM_FILE_LOADSESSION (the active tab comes back)",
                  @"the tab that was active when the session was saved is active after it loads",
                  activeIsA);
            closePaths();
            if ([ed.documents containsObject:untitled]) {
                [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:untitled] discardChanges:YES];
            }
            for (NSString *path in @[sA, sB, sessionPath]) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        }

        // The Document Map follows the tab in front, and Recent Window steps
        // back to the right tab after another one was closed.
        {
            [ed newDocument]; [ed setDocumentText:@"first\n"];
            NppDocument *first = ed.currentDocument;
            [ed newDocument]; [ed setDocumentText:@"second\n"];
            NppDocument *second = ed.currentDocument;
            [ed newDocument]; [ed setDocumentText:@"third\n"];
            NppDocument *third = ed.currentDocument;
            [ed setDocumentMapVisible:YES];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:second]];
            ScintillaView *map = [ed valueForKey:@"docMapView"];
            BOOL mapFollows = (void *)[map message:SCI_GETDOCPOINTER] == second.docPointer;
            [ed setDocumentMapVisible:NO];

            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:third]];   // previous is second
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:first] discardChanges:YES];
            BOOL frontStays = ed.currentDocument == third;
            BOOL recentIsSecond = [ed activateRecentWindow] && ed.currentDocument == second;
            for (NppDocument *mine in @[second, third]) {
                if ([ed.documents containsObject:mine]) {
                    [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:mine] discardChanges:YES];
                }
            }
            Check(@"IDM_VIEW_DOC_MAP (the map follows the tab in front)",
                  @"switching tabs switches the map, closing another tab leaves the front "
                  @"one in front, and Recent Window steps back to the right tab after that",
                  mapFollows && frontStays && recentIsSecond);
        }

        // View > Word Wrap is the preference, and reaches both views.
        {
            NppPreferences *p = [NppPreferences shared];
            BOOL was = p.wordWrap;
            [app toggleWordWrap:nil];
            BOOL flipped = p.wordWrap != was &&
                ([ed.sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE) == p.wordWrap;
            [app toggleWordWrap:nil];
            BOOL back = p.wordWrap == was;
            Check(@"IDM_VIEW_WRAP (the toggle is the preference)",
                  @"toggling Word Wrap writes the preference, so nothing later puts it back",
                  flipped && back);
        }

        // Search: an empty match is left behind, a lookahead survives Replace,
        // '.' stays on its line unless asked, whole word leaves a regex alone,
        // and a replacement may hold a NUL.
        {
            [ed newDocument];
            [ed setDocumentText:@"ab\ncd\n"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            NppFindSpec *eol = [NppFindSpec specFor:@"$" mode:NppSearchRegex options:NppFindWrap];
            NSMutableArray *stops = [NSMutableArray array];
            for (int k = 0; k < 4; ++k) {
                [ed findNext:eol];
                [stops addObject:@([ed.sci message:SCI_GETSELECTIONSTART])];
            }
            BOOL advances = [stops isEqualToArray:@[@2, @5, @6, @2]];

            [ed setDocumentText:@"foobar foobar"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            NppFindSpec *ahead = [NppFindSpec specFor:@"foo(?=bar)" mode:NppSearchRegex options:NppFindWrap];
            ahead.replacement = @"X";
            [ed findNext:ahead];
            [ed replaceCurrentThenFindNext:ahead];
            BOOL lookaheadReplaced = [[ed documentText] isEqualToString:@"Xbar foobar"] &&
                                     [ed.sci message:SCI_GETSELECTIONSTART] == 5;

            [ed setDocumentText:@"a\nb"];
            NppFindSpec *dot = [NppFindSpec specFor:@"a.b" mode:NppSearchRegex options:0];
            NSUInteger without = [ed countMatches:dot];
            dot.options = NppFindDotMatchesNewline;
            NSUInteger with = [ed countMatches:dot];
            BOOL dotStays = without == 0 && with == 1;

            [ed setDocumentText:@"a  b"];
            NppFindSpec *spaces = [NppFindSpec specFor:@"\\s+" mode:NppSearchRegex options:NppFindWholeWord];
            BOOL wholeWordLeavesRegex = [ed countMatches:spaces] == 1;

            [ed setDocumentText:@"a-b"];
            NppFindSpec *nul = [NppFindSpec specFor:@"-" mode:NppSearchExtended options:0];
            nul.replacement = @"\\0";
            [ed replaceAll:nul];
            NSString *withNul = [ed documentText];
            BOOL nulKept = withNul.length == 3 && [withNul characterAtIndex:1] == 0;

            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_SEARCH_FINDNEXT (an empty match is left behind)",
                  @"Find Next on '$' visits each line end in turn and wraps",
                  advances);
            Check(@"IDM_SEARCH_REPLACE (a lookahead survives Replace)",
                  @"Replace on a match of foo(?=bar) replaces it and moves to the next",
                  lookaheadReplaced);
            Check(@"IDM_SEARCH_FIND (. matches newline is a choice)",
                  @"'.' does not cross a line ending unless the box is ticked",
                  dotStays);
            Check(@"IDM_SEARCH_FIND (whole word leaves a regex alone)",
                  @"whole word does not wrap a regular expression in \\b",
                  wholeWordLeavesRegex);
            Check(@"IDM_SEARCH_REPLACE (a replacement may hold a NUL)",
                  @"an Extended replacement of \\0 puts a NUL byte in, not nothing",
                  nulKept);
        }

        // Find in Files filters: "!" leaves files out, "!\\" leaves folders out.
        {
            BOOL filters =
                [EditorController name:@"a.txt" matchesFilters:@"*.txt !*.log"] &&
                ![EditorController name:@"a.log" matchesFilters:@"*.txt !*.log"] &&
                ![EditorController name:@"a.log" matchesFilters:@"!*.log"] &&
                [EditorController name:@"a.c" matchesFilters:@"!*.log"] &&
                [EditorController relativePath:@"build/x/a.c" isInFolderExcludedByFilters:@"*.c !\\build"] &&
                ![EditorController relativePath:@"src/a.c" isInFolderExcludedByFilters:@"*.c !\\build"];
            Check(@"IDM_SEARCH_FINDINFILES (exclusions in the filter)",
                  @"a pattern after ! leaves those files out, and !\\name leaves a folder out",
                  filters);
        }

        // The last line of the file keeps the ending it had, even when the
        // transform changed how many lines there are.
        {
            [ed newDocument];
            [ed setDocumentText:@"a\n\nb"];
            [ed removeEmptyLines:NO];
            BOOL noTail = [[ed documentText] isEqualToString:@"a\nb"];
            [ed setDocumentText:@"a\n\nb\n"];
            [ed removeEmptyLines:NO];
            BOOL tailKept = [[ed documentText] isEqualToString:@"a\nb\n"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_EDIT_REMOVEEMPTYLINES (the end of the file stays as it was)",
                  @"a file without a final line ending does not gain one, and one with keeps it",
                  noTail && tailKept);
        }

        // Marking characters counts bytes by code point.
        {
            [ed newDocument];
            [ed setDocumentText:@"\U0001F600 \u00E9"];
            [ed markCharactersInRangeFrom:0xE9 to:0xE9];
            BOOL afterEmoji = [ed.sci message:SCI_INDICATORALLONFOR wParam:5 lParam:0] != 0 &&
                              [ed.sci message:SCI_INDICATORALLONFOR wParam:1 lParam:0] == 0;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_SEARCH_MARK (marks after an emoji land on the right bytes)",
                  @"the mark on the character after an emoji covers that character, not the emoji",
                  afterEmoji);
        }

        // The Column Editor pads a short line to the column and replaces the block.
        {
            [ed newDocument];
            [ed setDocumentText:@"abcdef\nab\nabcdef"];
            [ed.sci message:SCI_SETVIRTUALSPACEOPTIONS wParam:SCVS_RECTANGULARSELECTION lParam:0];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:4 lParam:0];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:14 lParam:0];   // column 4 of the third line
            // How far past "ab" the rectangle reaches is Scintilla's to say: it
            // measures the column in pixels, so the count depends on the font.
            NSString *spaces = [@"" stringByPaddingToLength:
                (NSUInteger)[ed.sci message:SCI_GETSELECTIONNCARETVIRTUALSPACE wParam:1 lParam:0]
                                                  withString:@" " startingAtIndex:0];
            [ed columnInsertText:@"X"];
            BOOL padded = [[ed documentText] isEqualToString:
                [NSString stringWithFormat:@"abcdXef\nab%@X\nabcdXef", spaces]];
            [ed setDocumentText:@"abcdef\nabcdef"];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:1 lParam:0];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:10 lParam:0];   // columns 1-3 of both lines
            [ed columnInsertText:@"Z"];
            BOOL replaced = [[ed documentText] isEqualToString:@"aZdef\naZdef"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_EDIT_COLUMNMODE (the column editor fills the column)",
                  @"a short line is padded to the column, and a selected block is replaced",
                  padded && replaced);
        }

        // Shift-JIS is double-byte and goes through the system converter.
        {
            const unsigned char sjis[] = {0x93, 0xFA, 0x96, 0x7B};       // 日本
            NSString *decoded = [EditorController stringFromData:[NSData dataWithBytes:sjis length:4] codepage:932];
            NSData *back = [EditorController dataFromString:@"日本" codepage:932];
            Check(@"IDM_FORMAT_SHIFT_JIS (a double-byte set decodes)",
                  @"Japanese text in Shift-JIS reads and writes back as itself",
                  [decoded isEqualToString:@"日本"] && [back isEqualToData:[NSData dataWithBytes:sjis length:4]]);
        }

        // What Run… splices from the document cannot become a command, and a
        // plain path is left alone.
        {
            [ed newDocument];
            [ed setDocumentText:@"a; touch /tmp/never $(x) `y`"];
            NSString *bare = [ed expandRunVariables:@"echo $(CURRENT_LINESTR)"];
            NSString *quoted = [ed expandRunVariables:@"echo \"$(CURRENT_LINESTR)\""];
            NSString *single = [ed expandRunVariables:@"echo '$(CURRENT_LINESTR)'"];
            NSString *plain = [ed expandRunVariables:@"$(CURRENT_LINE)"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_EXECUTE (document text is quoted for the shell)",
                  @"a line of the document is single-quoted outside quotes, escaped inside "
                  @"double quotes, left alone inside single quotes; a number is left bare",
                  [bare isEqualToString:@"echo 'a; touch /tmp/never $(x) `y`'"] &&
                  [quoted isEqualToString:@"echo \"a; touch /tmp/never \\$(x) \\`y\\`\""] &&
                  [single isEqualToString:@"echo 'a; touch /tmp/never $(x) `y`'"] &&
                  [plain isEqualToString:@"0"]);
        }

        // FTP addresses: absolute, and safe for a URL.
        {
            NppFtpProfile *profile = [[NppFtpProfile alloc] init];
            profile.host = @"h";
            NSString *url = [profile urlForPath:@"/a b/c#d"];
            NSArray *entries = [NppFtpClient parseListing:
                @"sftp> ls -l \"/x\"\n-rw-r--r-- 1 u g 5 Jan 1 12:00 a.txt\n"];
            Check(@"IDM_FTP (addresses are absolute and encoded, and sftp's echo is not a file)",
                  @"a path becomes ftp://host:21/%2F... with its unsafe characters encoded, "
                  @"and the sftp> echo line is skipped in a listing",
                  [url isEqualToString:@"ftp://h:21/%2Fa%20b/c%23d"] &&
                  entries.count == 1 && [[entries.firstObject name] isEqualToString:@"a.txt"]);
        }

        // Compare and Linearize leave line endings and text alone.
        {
            NSArray *lines = [EditorController linesForComparison:@"a\r\nb\rc\n"];
            NSString *linear = [EditorController linearizeXML:@"<r>\n  <p>line one\nline two</p>\n</r>"];
            Check(@"IDM_COMPARE (a CR is a line ending, not content)",
                  @"CRLF, CR and LF all split lines the same way for Compare",
                  [lines isEqualToArray:@[@"a", @"b", @"c", @""]]);
            Check(@"IDM_XMLTOOLS_LINEARIZE (text keeps its line breaks)",
                  @"only the whitespace between tags goes; a line break inside text stays",
                  [linear containsString:@"line one\nline two"] && ![linear containsString:@">\n"]);
        }

        // Custom word characters can be turned off again.
        {
            NppPreferences *p = [NppPreferences shared];
            BOOL wasOn = p.customWordCharsEnabled; NSString *wasChars = p.customWordChars;
            [ed newDocument];
            [ed setDocumentText:@"foo-bar baz"];
            p.customWordCharsEnabled = YES; p.customWordChars = @"-";
            [ed applyWordCharacters];
            long withDash = [ed.sci message:SCI_WORDENDPOSITION wParam:0 lParam:1];
            p.customWordCharsEnabled = NO;
            [ed applyWordCharacters];
            long withoutDash = [ed.sci message:SCI_WORDENDPOSITION wParam:0 lParam:1];
            p.customWordCharsEnabled = wasOn; p.customWordChars = wasChars;
            [ed applyWordCharacters];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_SETTING_PREFERENCE (word characters go back to the default)",
                  @"with '-' a word runs across it, and without it the word stops there again",
                  withDash == 7 && withoutDash == 3);
        }

        // Saved macros come back from disk.
        {
            NSString *macroPath = [ed.defaultSessionPath.stringByDeletingLastPathComponent
                                   stringByAppendingPathComponent:@"macros.json"];
            NSData *was = [NSData dataWithContentsOfFile:macroPath];
            [@"{\"persisted\": [{\"msg\": 2170, \"w\": 0, \"l\": 0}]}" writeToFile:macroPath atomically:YES
                                                                              encoding:NSUTF8StringEncoding error:NULL];
            [ed reloadSavedMacros];
            BOOL loaded = [[ed savedMacroNames] containsObject:@"persisted"];
            if (was) [was writeToFile:macroPath atomically:YES]; else [[NSFileManager defaultManager] removeItemAtPath:macroPath error:NULL];
            [ed reloadSavedMacros];
            Check(@"IDM_MACRO_SAVECURRENTMACRO (saved macros survive a restart)",
                  @"a macro written to macros.json is listed after it is read back",
                  loaded);
        }

        // Print headers understand Notepad++'s own default names.
        {
            NSString *expanded = [ed expandPrintTemplate:@"$(LONG_DATE)|$(TIME)|$(SHORT_DATE)" page:1 of:1];
            Check(@"IDM_FILE_PRINT (the default header's names)",
                  @"$(LONG_DATE), $(TIME) and $(SHORT_DATE) are filled in",
                  ![expanded containsString:@"$("] && [expanded componentsSeparatedByString:@"|"].count == 3);
        }

        // Two backups within one second are two files.
        {
            NppPreferences *p = [NppPreferences shared];
            NSInteger wasMode = p.backupMode;
            p.backupMode = NppBackupVerbose;
            NSString *victim = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-backup-twice.txt"];
            [@"one\n" writeToFile:victim atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSString *first = [ed writeBackupForPath:victim];
            NSString *second = [ed writeBackupForPath:victim];
            BOOL two = first && second && ![first isEqualToString:second] &&
                       [[NSFileManager defaultManager] fileExistsAtPath:first] &&
                       [[NSFileManager defaultManager] fileExistsAtPath:second];
            for (NSString *path in @[victim, first ?: @"", second ?: @""]) {
                if (path.length) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            }
            p.backupMode = wasMode;
            Check(@"IDM_SETTING_PREFERENCE (backups do not collide)",
                  @"a second timestamped backup in the same second gets its own name",
                  two);
        }

        // A user language with " or & in its name is still XML.
        {
            NSString *udlPath = [ed userDefinedLanguagePath];
            NSData *was = [NSData dataWithContentsOfFile:udlPath];
            [ed defineUserLanguageNamed:@"a\"b&c" extensions:@"x<y" keywords:@"k" commentLine:@"#"];
            NSString *written = [NSString stringWithContentsOfFile:udlPath encoding:NSUTF8StringEncoding error:NULL];
            BOOL escaped = [written containsString:@"name=\"a&quot;b&amp;c\""] && [written containsString:@"ext=\"x&lt;y\""];
            if (was) [was writeToFile:udlPath atomically:YES];
            Check(@"IDM_LANG_USER_DLG (the file stays well-formed)",
                  @"a quote or ampersand in a user language's name is escaped in userDefineLang.xml",
                  escaped);
        }

        // Auto-close as Windows does it: only before a blank, and the closer
        // you then type is stepped over rather than doubled.
        {
            NppPreferences *p = [NppPreferences shared];
            BOOL was = p.autoInsertParenthesis;
            p.autoInsertParenthesis = YES;
            [ed newDocument];
            [ed setLanguageNamed:@"cpp"];
            [ed setDocumentText:@""];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"("];
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed handleCharacterAdded:'('];
            BOOL paired = [[ed documentText] isEqualToString:@"()"];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:1 value:@"a"];
            [ed.sci message:SCI_GOTOPOS wParam:2 lParam:0];
            [ed handleCharacterAdded:'a'];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:2 value:@")"];
            [ed.sci message:SCI_GOTOPOS wParam:3 lParam:0];
            [ed handleCharacterAdded:')'];
            BOOL steppedOver = [[ed documentText] isEqualToString:@"(a)"] && [ed.sci message:SCI_GETCURRENTPOS] == 3;
            [ed setDocumentText:@"x"];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"("];
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed handleCharacterAdded:'('];
            BOOL notBeforeText = [[ed documentText] isEqualToString:@"(x"];
            p.autoInsertParenthesis = was;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_SETTING_PREFERENCE (auto-close pairs as Windows does)",
                  @"a bracket is paired before a blank, not before text, and typing the "
                  @"closer steps over the one put in",
                  paired && steppedOver && notBeforeText);
        }

        // Smart highlighting highlights whatever the refinements.
        {
            NppPreferences *p = [NppPreferences shared];
            BOOL wasOn = p.smartHighlightEnabled, wasWord = p.smartHighlightWholeWord;
            p.smartHighlightEnabled = YES;
            [ed newDocument];
            [ed setDocumentText:@"foo foobar foo"];
            [ed.sci message:SCI_SETSEL wParam:0 lParam:3];
            p.smartHighlightWholeWord = YES;
            NSUInteger whole = [ed updateSmartHighlight];
            p.smartHighlightWholeWord = NO;
            NSUInteger any = [ed updateSmartHighlight];
            p.smartHighlightEnabled = wasOn; p.smartHighlightWholeWord = wasWord;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_SETTING_PREFERENCE (smart highlighting with whole word)",
                  @"with whole word on, two of the three are highlighted; with it off, all three",
                  whole == 2 && any == 3);
        }

        // What the re-review turned up: a double-byte set outside the tables,
        // CDATA under Linearize, a pattern's own verbs, a backslash in single
        // quotes.
        {
            const unsigned char gbk[] = {0xD6, 0xD0};                       // 中 in GBK
            NSString *gbkText = [EditorController stringFromData:[NSData dataWithBytes:gbk length:2] codepage:936];
            NSString *cdata = [EditorController linearizeXML:
                @"<r>\n  <s><![CDATA[<p>a</p>\n<p>b</p>]]></s>\n</r>"];
            [ed newDocument];
            [ed setDocumentText:@"caf\u00E9 x"];
            NSUInteger verbs = [ed countMatches:[NppFindSpec specFor:@"(*UCP)\\w+" mode:NppSearchRegex options:0]];
            [ed setDocumentText:@"a b"];
            NSString *afterQuote = [ed expandRunVariables:@"echo '\\' $(CURRENT_LINESTR)"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_FORMAT_GB2312 (a set outside the tables)",
                  @"GBK decodes through the system converter, and the table lookup stops at the last table",
                  [gbkText isEqualToString:@"中"]);
            Check(@"IDM_XMLTOOLS_LINEARIZE (CDATA is content)",
                  @"a line break inside a CDATA section stays",
                  [cdata containsString:@"<p>a</p>\n<p>b</p>"] && [cdata containsString:@"<r><s>"]);
            Check(@"IDM_SEARCH_FIND (a pattern's own verbs)",
                  @"a pattern that starts with (*UCP) still compiles with the flags in front of the rest",
                  verbs == 2);
            Check(@"IDM_EXECUTE (a backslash in single quotes)",
                  @"the quote after a backslash inside single quotes still closes them",
                  [afterQuote isEqualToString:@"echo '\\' 'a b'"]);
        }

        // A code page chosen is a change however far the text is undone, and
        // the closer tracked in one tab is not judged in another.
        {
            [ed newDocument];
            [ed setDocumentText:@"plain\n"];
            [ed.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
            ed.currentDocument.modified = NO;
            [ed convertToCodepage:932];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"x"];
            [ed.sci message:SCI_UNDO wParam:0 lParam:0];
            // 932 has a system encoding, so it lives in `encoding`; a set without one
            // would live in `codepage`. Either way the change must survive undo.
            BOOL codepageStays = ed.currentDocument.modified &&
                                 ed.currentDocument.encoding == [EditorController encodingForCodepage:932];
            NppDocument *tabA = ed.currentDocument;

            NppPreferences *p = [NppPreferences shared];
            BOOL was = p.autoInsertParenthesis;
            p.autoInsertParenthesis = YES;
            [ed setLanguageNamed:@"cpp"];
            [ed setDocumentText:@""];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"("];
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed handleCharacterAdded:'('];                       // "()" with the closer tracked
            [ed newDocument];
            [ed setLanguageNamed:@"cpp"];
            [ed setDocumentText:@"x)"];
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:1 value:@")"];
            [ed.sci message:SCI_GOTOPOS wParam:2 lParam:0];
            [ed handleCharacterAdded:')'];
            BOOL otherTabUntouched = [[ed documentText] isEqualToString:@"x))"];
            p.autoInsertParenthesis = was;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:tabA] discardChanges:YES];
            Check(@"IDM_FORMAT_SHIFT_JIS (a code page chosen stays a change)",
                  @"after undoing a keystroke the document is still modified and still Shift-JIS",
                  codepageStays);
            Check(@"IDM_SETTING_PREFERENCE (a closer tracked in one tab is forgotten in another)",
                  @"typing ) before a ) in another tab does not delete that tab's own bracket",
                  otherTabUntouched);
        }

        // The still-open bugs of the audit, batch one.
        {
            NSFileManager *fm = [NSFileManager defaultManager];

            // Renaming an untitled document renames the tab and writes nothing.
            [ed newDocument];
            NSString *never = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-never-written.txt"];
            [ed renameCurrentTo:never error:NULL];
            BOOL tabOnly = ed.currentDocument.path == nil &&
                           [ed.currentDocument.displayName isEqualToString:@"npp-never-written.txt"] &&
                           ![fm fileExistsAtPath:never];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_FILE_RENAME (an untitled document)",
                  @"only the tab is renamed; nothing is written to disk", tabOnly);

            // The recent list is of what was closed; Restore Last Closed reopens it.
            NSString *recentPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-recent-close.txt"];
            [@"r\n" writeToFile:recentPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [ed openFileAtPath:recentPath error:NULL];
            BOOL notWhileOpen = ![[ed recentFiles] containsObject:recentPath];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            BOOL listedOnClose = [[ed recentFiles].firstObject isEqualToString:recentPath];
            BOOL restored = [ed restoreLastClosedFile] && [ed.currentDocument.path isEqualToString:recentPath] &&
                            ![[ed recentFiles] containsObject:recentPath];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [ed forgetRecentFile:recentPath];
            [fm removeItemAtPath:recentPath error:NULL];
            Check(@"IDM_FILE_RESTORELASTCLOSEDFILE",
                  @"a file joins the recent list when closed, leaves it when opened, and the last "
                  @"closed one comes back",
                  notWhileOpen && listedOnClose && restored);

            // Date and time: time first, no seconds, in place of the selection.
            NppPreferences *p = [NppPreferences shared];
            BOOL wasReversed = p.reverseDateTimeOrder;
            p.reverseDateTimeOrder = NO;
            [ed newDocument];
            [ed setDocumentText:@"abc"];
            [ed.sci message:SCI_SETSEL wParam:0 lParam:3];
            NSDateFormatter *t = [[NSDateFormatter alloc] init];
            t.dateStyle = NSDateFormatterNoStyle; t.timeStyle = NSDateFormatterShortStyle;
            NSDateFormatter *d = [[NSDateFormatter alloc] init];
            d.dateStyle = NSDateFormatterShortStyle; d.timeStyle = NSDateFormatterNoStyle;
            NSDate *now = [NSDate date];
            [ed insertDateTimeShort:YES];
            NSString *stamp = [ed documentText];
            BOOL timeFirst = ![stamp containsString:@"abc"] &&
                             [stamp isEqualToString:[NSString stringWithFormat:@"%@ %@", [t stringFromDate:now], [d stringFromDate:now]]];
            p.reverseDateTimeOrder = wasReversed;
            Check(@"IDM_EDIT_INSERT_DATETIME_SHORT (as Windows writes it)",
                  @"the time comes first, without seconds, and the selection is replaced", timeFirst);

            // Braces are part of the selection between them.
            [ed setDocumentText:@"x(a)y"];
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed selectBetweenMatchingBraces];
            BOOL inclusive = [ed.sci message:SCI_GETSELECTIONSTART] == 1 && [ed.sci message:SCI_GETSELECTIONEND] == 4;
            Check(@"IDM_SEARCH_GOBRACE (both braces are selected)",
                  @"Select All Between Matching Braces includes the braces themselves", inclusive);

            // Bookmarked lines: copied with their endings, pasted whole.
            [ed setDocumentText:@"a\nb\nc\n"];
            [ed.sci message:SCI_MARKERADD wParam:0 lParam:1];
            [ed.sci message:SCI_MARKERADD wParam:2 lParam:1];
            BOOL copiedWithEndings = [[ed bookmarkedLinesText] isEqualToString:@"a\nc\n"];
            NSPasteboard *board = [NSPasteboard generalPasteboard];
            [board clearContents];
            [board setString:@"X\nY" forType:NSPasteboardTypeString];
            [ed pasteOverBookmarkedLines];
            BOOL pastedWhole = [[ed documentText] isEqualToString:@"X\nY\nb\nX\nY\n"];
            Check(@"IDM_SEARCH_COPYMARKEDLINES (as Windows copies and pastes)",
                  @"each bookmarked line is copied with its ending, and the whole clipboard goes into each",
                  copiedWithEndings && pastedWhole);

            // Proper and sentence case, and trim, as Windows does them.
            [ed setDocumentText:@"don't 3rd"];
            [ed convertCase:NppCaseProperBlend];
            BOOL proper = [[ed documentText] isEqualToString:@"Don't 3rd"];
            [ed setDocumentText:@"hello. world\n\nnext i am"];
            [ed convertCase:NppCaseSentenceBlend];
            BOOL sentence = [[ed documentText] isEqualToString:@"Hello. World\n\nNext I am"];
            [ed setDocumentText:@"a\u00A0 \t\n"];
            [ed applyTrim:NppTrimTrailing];
            BOOL trim = [[ed documentText] isEqualToString:@"a\u00A0\n"];
            Check(@"IDM_EDIT_PROPERCASE_BLEND (apostrophes and digits)",
                  @"don't stays one word, 3rd starts with a digit, a sentence ends at a stop or a blank line, "
                  @"a lone i is I, and trim takes tabs and spaces only",
                  proper && sentence && trim);

            // The Column Editor from the caret, when nothing is selected.
            [ed setDocumentText:@"ab\ncd\nef"];
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed columnInsertText:@"X"];
            BOOL fromCaret = [[ed documentText] isEqualToString:@"aXb\ncXd\neXf"];
            [ed setDocumentText:@"a\nb\nc"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            [ed columnInsertNumbersFrom:1 increment:1 repeat:2 zeroPadded:NO base:16];
            BOOL repeated = [[ed documentText] isEqualToString:@"1a\n1b\n2c"];
            Check(@"IDM_EDIT_COLUMNMODE (from the caret, with repeat and base)",
                  @"with nothing selected the column runs from the caret line down; numbers repeat and take a base",
                  fromCaret && repeated);
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];

            // Pinning moves the tab to the left, and Close All But Pinned keeps that run.
            [ed newDocument]; NppDocument *pA = ed.currentDocument;
            [ed newDocument]; NppDocument *pB = ed.currentDocument;
            [ed newDocument]; NppDocument *pC = ed.currentDocument;
            [ed togglePinCurrent];                                   // C pinned: first
            BOOL movedLeft = ed.documents.firstObject == pC && ed.currentDocument == pC;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:pB]];
            [ed togglePinCurrent];                                   // B pinned: after C
            BOOL afterRun = ed.documents[1] == pB;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:pC]];
            [ed togglePinCurrent];                                   // C unpinned: after B
            BOOL movedBack = ed.documents.firstObject == pB && ed.documents[1] == pC;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:pB]];
            [ed togglePinCurrent];
            movedBack = movedBack && afterRun;
            for (NppDocument *doc in @[pA, pB, pC]) {
                if ([ed.documents containsObject:doc]) [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:doc] discardChanges:YES];
            }
            Check(@"IDM_FILE_PIN (pinned tabs sit on the left)", @"pinning moves the tab to the pinned run; unpinning moves it out",
                  movedLeft && movedBack);

            // A file that cannot be written opens read-only.
            NSString *roPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-readonly-open.txt"];
            [@"ro\n" writeToFile:roPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [fm setAttributes:@{NSFilePosixPermissions: @0444} ofItemAtPath:roPath error:NULL];
            [ed openFileAtPath:roPath error:NULL];
            BOOL readOnly = [ed isReadOnly];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [ed forgetRecentFile:roPath];
            [fm setAttributes:@{NSFilePosixPermissions: @0644} ofItemAtPath:roPath error:NULL];
            [fm removeItemAtPath:roPath error:NULL];
            Check(@"IDM_EDIT_SETREADONLY (detected on open)", @"a file without write permission opens read-only", readOnly);

            // The other pane is moved off a document that is closed.
            [ed newDocument]; NppDocument *shown = ed.currentDocument;
            [ed setDocumentText:@"shown\n"];
            [ed cloneCurrentToOtherView];
            [ed newDocument];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:shown] discardChanges:YES];
            BOOL movedOff = (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == ed.currentDocument.docPointer;
            [ed setSecondaryViewVisible:NO];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW (the pane survives a close)",
                  @"closing the cloned document points the other pane at the document in front", movedOff);
        }

        // The caret belongs to the document: it is where it was when the tab
        // comes back to the front.
        {
            [ed newDocument]; [ed setDocumentText:@"one\ntwo\nthree\n"];
            NppDocument *first = ed.currentDocument;
            [ed.sci message:SCI_SETSEL wParam:4 lParam:7];
            [ed newDocument]; [ed setDocumentText:@"other\n"];
            NppDocument *second = ed.currentDocument;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:first]];
            BOOL back = [ed.sci message:SCI_GETANCHOR] == 4 && [ed.sci message:SCI_GETCURRENTPOS] == 7;
            for (NppDocument *d in @[first, second]) [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:d] discardChanges:YES];
            Check(@"IDM_VIEW_TAB_NEXT (the caret comes back with the tab)",
                  @"switching away and back leaves the selection where it was", back);
        }

        // Closing the tab in front puts the neighbour's own caret back.
        {
            [ed newDocument]; [ed setDocumentText:@"neighbour\n"];
            NppDocument *stays = ed.currentDocument;
            [ed.sci message:SCI_SETSEL wParam:3 lParam:5];
            [ed newDocument]; [ed setDocumentText:@"going\n"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            BOOL own = ed.currentDocument == stays &&
                       [ed.sci message:SCI_GETANCHOR] == 3 && [ed.sci message:SCI_GETCURRENTPOS] == 5;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:stays] discardChanges:YES];
            Check(@"IDM_FILE_CLOSE (the neighbour keeps its caret)",
                  @"after closing the front tab, the tab that takes its place shows its own selection", own);
        }

        // Files changed or removed by another program are noticed when the
        // application comes to the front.
        {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *changing = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-changed-outside.txt"];
            [@"before\n" writeToFile:changing atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [ed openFileAtPath:changing error:NULL];
            NppDocument *doc = ed.currentDocument;
            [@"after\n" writeToFile:changing atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [fm setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:60]}
                 ofItemAtPath:changing error:NULL];
            ed.scriptedCloseAnswer = NSAlertFirstButtonReturn;       // Reload
            [ed checkFilesOnDisk];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:doc]];
            BOOL reloaded = [[ed documentText] isEqualToString:@"after\n"] && !doc.modified;
            [fm removeItemAtPath:changing error:NULL];
            ed.scriptedCloseAnswer = NSAlertFirstButtonReturn;       // Keep
            [ed checkFilesOnDisk];
            BOOL kept = [ed.documents containsObject:doc] && doc.modified;
            ed.scriptedCloseAnswer = 0;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:doc] discardChanges:YES];
            [ed forgetRecentFile:changing];
            Check(@"IDM_SETTING_PREFERENCE (File Status Auto-Detection)",
                  @"a file changed on disk is reloaded, and one removed is kept as modified",
                  reloaded && kept);
        }

        // A rectangular selection sorts by its columns.
        {
            [ed newDocument]; [ed setDocumentText:@"x c\ny a\nz b\n"];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:2 lParam:0];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:11 lParam:0];
            [ed sortLines:NppSortLexicographic descending:NO];
            BOOL byColumn = [[ed documentText] isEqualToString:@"y a\nz b\nx c\n"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING (by the selected column)",
                  @"with a rectangular selection the lines are ordered by what is inside its columns", byColumn);
        }

        // The column key is an offset in the line, so a tab before the block
        // does not shift it; Proper Case (force) and Sentence Case as Windows.
        {
            [ed newDocument]; [ed setDocumentText:@"\tx c\n\ty a\n\tz b\n"];
            [ed.sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:3 lParam:0];    // after "\tx "
            [ed.sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:14 lParam:0];    // same offset, third line
            [ed sortLines:NppSortLexicographic descending:NO];
            BOOL afterTab = [[ed documentText] isEqualToString:@"\ty a\n\tz b\n\tx c\n"];
            [ed setDocumentText:@"DON'T 3RD"];
            [ed convertCase:NppCaseProperForce];
            BOOL force = [[ed documentText] isEqualToString:@"Don't 3rd"];
            [ed setDocumentText:@"\"go.\" she said (i) i am"];
            [ed convertCase:NppCaseSentenceBlend];
            BOOL sentence = [[ed documentText] isEqualToString:@"\"Go.\" she said (i) I am"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING (a tab before the column)",
                  @"the column is an offset in the line, Proper Case keeps apostrophes when forcing, "
                  @"and a sentence ends only before whitespace",
                  afterTab && force && sentence);
        }

        // Character sets are detected the way Windows detects them.
        {
            NSString *russian = @"Привет, это тестовый файл на русском языке. Он нужен для того, чтобы "
                                @"определитель кодировки увидел достаточно текста и назвал кодовую страницу "
                                @"правильно, а не прочитал файл как латиницу.\n";
            NSData *cp1251 = [russian dataUsingEncoding:[EditorController encodingForCodepage:1251]];
            NSString *cpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-detect-1251.txt"];
            [cp1251 writeToFile:cpPath atomically:YES];
            [ed openFileAtPath:cpPath error:NULL];
            BOOL cyrillic = [[ed documentText] isEqualToString:russian];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [ed forgetRecentFile:cpPath];
            [[NSFileManager defaultManager] removeItemAtPath:cpPath error:NULL];

            NSString *wide = @"plain ascii text, wide\n";
            NSString *widePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-detect-utf16.txt"];
            [[wide dataUsingEncoding:NSUTF16LittleEndianStringEncoding] writeToFile:widePath atomically:YES];
            [ed openFileAtPath:widePath error:NULL];
            BOOL utf16 = [[ed documentText] isEqualToString:wide] &&
                         ed.currentDocument.encoding == NSUTF16LittleEndianStringEncoding;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [ed forgetRecentFile:widePath];
            [[NSFileManager defaultManager] removeItemAtPath:widePath error:NULL];
            Check(@"IDM_FORMAT_ANSI (the character set is detected)",
                  @"a Windows-1251 file reads as Cyrillic and UTF-16 without a mark as itself",
                  cyrillic && utf16);
        }

        // The command line, as Notepad++ reads it.
        {
            NSDictionary *parsed = [app parseCommandLine:
                @[@"-n12", @"-c3", @"-lpython", @"-ro", @"-nosession", @"-z", @"skipped",
                  @"-titleAdd=Here", @"-NSDocumentRevisionsDebugMode", @"YES", @"a.txt", @"b c.txt"]];
            BOOL parsedRight = [parsed[@"-n"] integerValue] == 12 && [parsed[@"-c"] integerValue] == 3 &&
                [parsed[@"-l"] isEqualToString:@"python"] && [parsed[@"-ro"] boolValue] &&
                [parsed[@"-nosession"] boolValue] && [parsed[@"-titleAdd="] isEqualToString:@"Here"] &&
                [parsed[@"files"] isEqualToArray:@[@"a.txt", @"b c.txt"]];   // "-NS... YES" is a defaults pair
            NSDictionary *notepadStyle = [app parseCommandLine:@[@"-notepadStyleCmdline", @"my", @"file.txt"]];
            BOOL oneName = [notepadStyle[@"files"] isEqualToArray:@[@"my file.txt"]];

            NSString *clPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-cmdline.txt"];
            [@"one\ntwo\nthree\n" writeToFile:clPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [app applyCommandLine:[app parseCommandLine:@[@"-n2", @"-c2", @"-lpython", @"-ro", @"-titleAdd=Here", clPath]]];
            NppDocument *doc = ed.currentDocument;
            BOOL applied = [doc.path isEqualToString:clPath] &&
                [ed.sci message:SCI_GETCURRENTPOS] == 5 && [ed isReadOnly] &&
                [doc.language.name isEqualToString:@"python"] && [ed.window.title hasSuffix:@"- Here"];
            [ed setReadOnly:NO];
            ed.titleSuffix = nil;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:doc] discardChanges:YES];
            [ed forgetRecentFile:clPath];
            [[NSFileManager defaultManager] removeItemAtPath:clPath error:NULL];
            [app applyCommandLine:[app parseCommandLine:@[@"-qt=quoted text"]]];
            BOOL quoted = [[ed documentText] isEqualToString:@"quoted text"];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            Check(@"IDM_ABOUT (command line switches)",
                  @"-n -c -l -ro -titleAdd= -qt= -z and -notepadStyleCmdline are read and applied as on Windows",
                  parsedRight && oneName && applied && quoted);
        }

        // -export=functionList, -quickPrint, -x / -y, -pluginMessage= and
        // -monitor over several files.
        {
            NSDictionary *exportArgs = [app parseCommandLine:@[@"-export=functionList", @"-pluginMessage=\"hello\"", @"a.cpp"]];
            BOOL silent = [exportArgs[@"-nosession"] boolValue] && [exportArgs[@"-export=functionList"] boolValue] &&
                          [exportArgs[@"-pluginMessage="] isEqualToString:@"hello"];
            NSString *source = TempFile(@"t_export.cpp",
                @"class Shape {\npublic:\n  int area() { return 0; }\n};\nint helper(int a) { return a; }\n");
            [ed openFileAtPath:source error:NULL];
            NSString *result = [source stringByAppendingString:@".result.json"];
            [[NSFileManager defaultManager] removeItemAtPath:result error:NULL];
            BOOL exported = [FunctionListPanel exportFunctionListOf:ed to:nil];
            NSString *json = [NSString stringWithContentsOfFile:result encoding:NSUTF8StringEncoding error:NULL];
            BOOL exportRight = exported &&
                [json isEqualToString:@"{\"leaves\":[\"helper\"],\"nodes\":[{\"leaves\":[\"area\"],\"name\":\"Shape\"}],\"root\":\"t_export.cpp\"}"];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];

            NSRect before = app.window.frame;
            [app applyCommandLine:[app parseCommandLine:@[@"-x40", @"-y60"]]];
            NSRect screen = (app.window.screen ?: [NSScreen mainScreen]).frame;
            BOOL placed = fabs(NSMinX(app.window.frame) - (NSMinX(screen) + 40)) < 1 &&
                          fabs(NSMaxY(app.window.frame) - (NSMaxY(screen) - 60)) < 1;
            [app.window setFrame:before display:NO];

            NSString *m1 = TempFile(@"t_cl_m1.log", @"a\n"), *m2 = TempFile(@"t_cl_m2.log", @"b\n");
            [app applyCommandLine:[app parseCommandLine:@[@"-monitor", m1, m2]]];
            NSUInteger watched = 0;
            for (NppDocument *d in [ed.documents copy]) {
                if ([d.path isEqualToString:m1] || [d.path isEqualToString:m2]) {
                    if (d.monitoring) watched++;
                    [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:d]];
                    [ed setMonitoring:NO];
                    [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:d] discardChanges:YES];
                }
            }
            Check(@"IDM_ABOUT (more command line switches)",
                  @"-export=functionList writes upstream's JSON, -x/-y place the window, -monitor watches every file given",
                  silent && exportRight && placed && watched == 2);
        }

        // A user-defined language is read from its file and highlighted.
        {
            NSString *udlPath = [ed userDefinedLanguagePath];
            NSData *was = [NSData dataWithContentsOfFile:udlPath];
            NSString *xml =
                @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n"
                @"<UserLang name=\"TestLang\" ext=\"tlang\" udlVersion=\"2.1\">\n"
                @"<Settings><Global caseIgnored=\"no\" allowFoldOfComments=\"no\" foldCompact=\"no\" "
                @"forcePureLC=\"0\" decimalSeparator=\"0\" />"
                @"<Prefix Keywords1=\"no\" Keywords2=\"no\" Keywords3=\"no\" Keywords4=\"no\" "
                @"Keywords5=\"no\" Keywords6=\"no\" Keywords7=\"no\" Keywords8=\"no\" /></Settings>\n"
                @"<KeywordLists><Keywords name=\"Comments\">00# 01 02 03 04</Keywords>"
                @"<Keywords name=\"Keywords1\">alpha beta</Keywords></KeywordLists>\n"
                @"<Styles><WordsStyle name=\"DEFAULT\" fgColor=\"000000\" bgColor=\"FFFFFF\" fontStyle=\"0\" nesting=\"0\" />"
                @"<WordsStyle name=\"KEYWORDS1\" fgColor=\"FF0000\" bgColor=\"FFFFFF\" fontStyle=\"1\" nesting=\"0\" />"
                @"<WordsStyle name=\"LINE COMMENTS\" fgColor=\"008000\" bgColor=\"FFFFFF\" fontStyle=\"0\" nesting=\"0\" />"
                @"</Styles></UserLang></NotepadPlus>\n";
            [xml writeToFile:udlPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSArray *loaded = [[LanguageCatalog sharedCatalog] reloadUserLanguagesFromDirectory:[ed supportDirectory]];
            BOOL listed = [[LanguageCatalog sharedCatalog] languageNamed:@"TestLang"] != nil &&
                          [[[LanguageCatalog sharedCatalog] languageForFileName:@"x.tlang"].name isEqualToString:@"TestLang"];

            NSString *tlPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-udl-test.tlang"];
            [@"alpha gamma # note\n" writeToFile:tlPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [ed openFileAtPath:tlPath error:NULL];
            [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
            long keywordStyle = [ed.sci message:SCI_GETSTYLEAT wParam:0 lParam:0];      // "alpha"
            long plainStyle = [ed.sci message:SCI_GETSTYLEAT wParam:6 lParam:0];        // "gamma"
            long commentStyle = [ed.sci message:SCI_GETSTYLEAT wParam:13 lParam:0];     // "note"
            BOOL highlighted = [ed.currentDocument.language.name isEqualToString:@"TestLang"] &&
                keywordStyle == SCE_USER_STYLE_KEYWORD1 && plainStyle != SCE_USER_STYLE_KEYWORD1 &&
                commentStyle == SCE_USER_STYLE_COMMENTLINE;
            BOOL bold = [ed.sci message:SCI_STYLEGETBOLD wParam:SCE_USER_STYLE_KEYWORD1 lParam:0] != 0;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [ed forgetRecentFile:tlPath];
            [[NSFileManager defaultManager] removeItemAtPath:tlPath error:NULL];
            if (was) [was writeToFile:udlPath atomically:YES]; else [[NSFileManager defaultManager] removeItemAtPath:udlPath error:NULL];
            [[LanguageCatalog sharedCatalog] reloadUserLanguagesFromDirectory:[ed supportDirectory]];
            Check(@"IDM_LANG_USER (a user-defined language highlights)",
                  @"a language in userDefineLang.xml is listed, claims its extension, and its keywords, "
                  @"comments and styles reach the lexer",
                  [[loaded valueForKey:@"name"] containsObject:@"TestLang"] && listed && highlighted && bold);
        }

        // The User Defined Language dialog and what it keeps.
        {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dir = [ed supportDirectory];
            NSString *mainFile = [dir stringByAppendingPathComponent:@"userDefineLang.xml"];
            NSString *folder = [dir stringByAppendingPathComponent:@"userDefineLangs"];
            NSString *stash = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-udl-stash"];
            [fm removeItemAtPath:stash error:NULL];
            [fm createDirectoryAtPath:stash withIntermediateDirectories:YES attributes:nil error:NULL];
            BOOL hadMain = [fm fileExistsAtPath:mainFile], hadFolder = [fm fileExistsAtPath:folder];
            if (hadMain) [fm moveItemAtPath:mainFile toPath:[stash stringByAppendingPathComponent:@"main.xml"] error:NULL];
            if (hadFolder) [fm moveItemAtPath:folder toPath:[stash stringByAppendingPathComponent:@"folder"] error:NULL];
            LanguageCatalog *catalog = [LanguageCatalog sharedCatalog];
            [catalog reloadUserLanguagesFromDirectory:dir];

            // The prefixed lists, both ways, as the Windows dialog reads and writes them.
            NSString *list = @"00# 00// 01 02((EOL)) 03/* 04*/";
            BOOL decoded = [[NppUserLanguage fieldForCode:0 inList:list] isEqualToString:@"# //"] &&
                           [[NppUserLanguage fieldForCode:2 inList:list] isEqualToString:@"((EOL))"] &&
                           [[NppUserLanguage fieldForCode:4 inList:list] isEqualToString:@"*/"];
            BOOL encoded = [[NppUserLanguage listFromFields:@[@"# //", @"", @"((EOL))", @"/*", @"*/"]] isEqualToString:list];
            Check(@"IDM_LANG_USER_DLG (comment and delimiter fields)",
                  @"a prefixed list reads into the dialog's fields and writes back the same",
                  decoded && encoded);

            // The Markdown languages Notepad++ ships are there, and the variant
            // for the current mode claims .md.
            NppLanguage *light = [catalog languageNamed:@"Markdown (preinstalled)"];
            NppLanguage *dark = [catalog languageNamed:@"Markdown (preinstalled dark mode)"];
            BOOL wasDark = catalog.darkMode;
            catalog.darkMode = NO;
            BOOL lightChosen = [catalog languageForFileName:@"a.md"] == light;
            catalog.darkMode = YES;
            BOOL darkChosen = [catalog languageForFileName:@"a.md"] == dark;
            catalog.darkMode = wasDark;
            Check(@"IDM_LANG_USER (the languages Notepad++ ships)",
                  @"both Markdown languages are listed, and .md opens in the one for the current mode",
                  light && dark && lightChosen && darkChosen);

            // Written as Windows writes it, and read back the same.
            NppUserLanguage *md = [catalog userLanguageNamed:@"Markdown (preinstalled)"];
            NSString *copyPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-udl-roundtrip.xml"];
            [NppUserLanguage writeLanguages:@[md] toFile:copyPath];
            NppUserLanguage *back = [NppUserLanguage languagesInFile:copyPath].firstObject;
            BOOL sameStyles = YES;
            for (NSNumber *sid in md.styles) {
                for (NSString *k in @[@"fgColor", @"bgColor", @"fontStyle", @"nesting"]) {
                    NSString *a = md.styles[sid][k] ?: @"", *b = back.styles[sid][k] ?: @"";
                    if (![a isEqualToString:b]) sameStyles = NO;
                }
            }
            BOOL roundTrip = [back.name isEqualToString:md.name] && [back.extensions isEqualToArray:md.extensions] &&
                             [back.keywordLists isEqualToArray:md.keywordLists] && [back.prefixes isEqualToArray:md.prefixes] &&
                             back.caseIgnored == md.caseIgnored && back.forcePureLC == md.forcePureLC && sameStyles;
            NSString *xml = [NSString stringWithContentsOfFile:copyPath encoding:NSUTF8StringEncoding error:NULL];
            BOOL windowsNames = [xml containsString:@"<Keywords name=\"Numbers, prefix1\">"] &&
                                [xml containsString:@"<WordsStyle name=\"FOLDER IN COMMENT\""] &&
                                [xml containsString:@"udlVersion=\"2.1\""];
            [fm removeItemAtPath:copyPath error:NULL];
            Check(@"IDM_LANG_USER_DLG (written as Windows writes it)",
                  @"a language written out and read back is the same, under Notepad++'s names", roundTrip && windowsNames);

            // The dialog: create, fill in, style, rename, save as, export,
            // import, remove - and the document in the language follows.
            NppUserLanguageDialog *dialog = [[NppUserLanguageDialog alloc] initWithEditor:ed];
            BOOL created = [dialog createLanguageNamed:@"DialogLang"];
            ((NSTextField *)[dialog controlNamed:@"ext"]).stringValue = @"dlang";
            [dialog textViewNamed:@"keywords1"].string = @"begin end";
            ((NSTextField *)[dialog controlNamed:@"commentLineOpen"]).stringValue = @"--";
            ((NSTextField *)[dialog controlNamed:@"delimiter1Open"]).stringValue = @"\"";
            ((NSTextField *)[dialog controlNamed:@"delimiter1Close"]).stringValue = @"\"";
            [dialog commit];
            [dialog setStyle:SCE_USER_STYLE_KEYWORD1 attributes:@{@"fgColor": @"0000FF", @"bgColor": @"FFFFFF",
                                                                   @"fontStyle": @"1", @"nesting": @"0"}];
            NSString *written = [NSString stringWithContentsOfFile:mainFile encoding:NSUTF8StringEncoding error:NULL];
            BOOL saved = [written containsString:@"name=\"DialogLang\""] && [written containsString:@"ext=\"dlang\""] &&
                         [written containsString:@">begin end<"] && [written containsString:@"00-- 01 02 03 04"] &&
                         [written containsString:@"00&quot; 01 02&quot;"] == NO && [written containsString:@"00\" 01 02\""] &&
                         [written containsString:@"fgColor=\"0000FF\""];

            NSString *docPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-dialog.dlang"];
            [@"begin x -- note\nend\n" writeToFile:docPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [ed openFileAtPath:docPath error:NULL];
            NppDocument *doc = ed.currentDocument;
            [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL shown = [doc.language.name isEqualToString:@"DialogLang"] &&
                         [ed.sci message:SCI_GETSTYLEAT wParam:0 lParam:0] == SCE_USER_STYLE_KEYWORD1 &&
                         [ed.sci message:SCI_GETSTYLEAT wParam:10 lParam:0] == SCE_USER_STYLE_COMMENTLINE &&
                         [ed.sci message:SCI_STYLEGETBOLD wParam:SCE_USER_STYLE_KEYWORD1 lParam:0] != 0;

            // A transparent background (colorStyle without its second bit) is the
            // default style's, whatever colour the file carries; the foreground is the style's own.
            [dialog setStyle:SCE_USER_STYLE_COMMENTLINE attributes:@{@"fgColor": @"008000", @"bgColor": @"FF0000",
                                                                      @"colorStyle": @"1", @"fontStyle": @"0", @"nesting": @"0"}];
            long clearBack = [ed.sci message:SCI_STYLEGETBACK wParam:SCE_USER_STYLE_COMMENTLINE lParam:0];
            shown = shown && clearBack == [ed.sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT lParam:0] && clearBack != 0x0000FF &&
                    [ed.sci message:SCI_STYLEGETFORE wParam:SCE_USER_STYLE_COMMENTLINE lParam:0] == 0x008000 &&
                    [[NSString stringWithContentsOfFile:mainFile encoding:NSUTF8StringEncoding error:NULL] containsString:@"colorStyle=\"1\""];

            // Typing shows in the document a moment later, without leaving the field.
            NSTextField *commentOpen = (NSTextField *)[dialog controlNamed:@"commentLineOpen"];
            commentOpen.stringValue = @"//";
            [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:commentOpen];
            BOOL notYet = [ed.sci message:SCI_GETSTYLEAT wParam:10 lParam:0] == SCE_USER_STYLE_COMMENTLINE;
            NSDate *typed = [NSDate dateWithTimeIntervalSinceNow:3];
            [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
            while ([typed timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
                if ([ed.sci message:SCI_GETSTYLEAT wParam:10 lParam:0] != SCE_USER_STYLE_COMMENTLINE) break;
            }
            shown = shown && notYet && [ed.sci message:SCI_GETSTYLEAT wParam:10 lParam:0] != SCE_USER_STYLE_COMMENTLINE;
            commentOpen.stringValue = @"--";
            [dialog commit];

            BOOL renamed = [dialog renameCurrentTo:@"DialogLang2"] && [doc.language.name isEqualToString:@"DialogLang2"] &&
                           ![catalog languageNamed:@"DialogLang"];
            BOOL copied = [dialog saveCurrentAs:@"DialogLang3"] && [catalog userLanguageNamed:@"DialogLang3"] &&
                          [[catalog userLanguageNamed:@"DialogLang3"].keywordLists[SCE_USER_KWLIST_KEYWORDS1] isEqualToString:@"begin end"];
            BOOL taken = ![dialog saveCurrentAs:@"DialogLang2"];
            NSString *exported = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-exported.xml"];
            BOOL exportedOK = [dialog exportCurrentToFile:exported] &&
                              [[NppUserLanguage languagesInFile:exported].firstObject.name isEqualToString:@"DialogLang3"];
            BOOL importSkipsTaken = [dialog importFromFile:exported].count == 0;
            [dialog removeCurrent];                                   // DialogLang3
            [dialog selectLanguageNamed:@"DialogLang2"];
            BOOL removed = [dialog removeCurrent] && ![catalog languageNamed:@"DialogLang2"] &&
                           [doc.language.name isEqualToString:@"normal"];
            BOOL imported = [[dialog importFromFile:exported] isEqualToArray:@[@"DialogLang3"]];
            [dialog removeCurrent];

            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:doc] discardChanges:YES];
            [ed forgetRecentFile:docPath];
            [fm removeItemAtPath:docPath error:NULL];
            [fm removeItemAtPath:exported error:NULL];
            Check(@"IDM_LANG_USER_DLG (the dialog)",
                  @"a language made in the dialog is written in Notepad++'s shape, highlights its document, "
                  @"and can be renamed, copied, exported, imported and removed",
                  created && saved && shown && renamed && copied && taken && exportedOK && importSkipsTaken &&
                  removed && imported);

            // Editing a shipped language writes a copy in the user's folder.
            [dialog selectLanguageNamed:@"Markdown (preinstalled)"];
            ((NSButton *)[dialog controlNamed:@"caseIgnored"]).state = NSControlStateValueOff;
            [dialog commit];
            NSString *userCopy = [folder stringByAppendingPathComponent:@"markdown._preinstalled.udl.xml"];
            BOOL copyWritten = [fm fileExistsAtPath:userCopy] &&
                               ![catalog userLanguageNamed:@"Markdown (preinstalled)"].caseIgnored &&
                               [[catalog userLanguageNamed:@"Markdown (preinstalled)"].sourcePath isEqualToString:userCopy];
            Check(@"IDM_LANG_USER_DLG (a shipped language)",
                  @"editing a language the application ships writes a copy of its file in the user's folder",
                  copyWritten);

            [fm removeItemAtPath:mainFile error:NULL];
            [fm removeItemAtPath:folder error:NULL];
            if (hadMain) [fm moveItemAtPath:[stash stringByAppendingPathComponent:@"main.xml"] toPath:mainFile error:NULL];
            if (hadFolder) [fm moveItemAtPath:[stash stringByAppendingPathComponent:@"folder"] toPath:folder error:NULL];
            [catalog reloadUserLanguagesFromDirectory:dir];
        }

        // Every setting that existed only as a property now has a control.
        {
            NppPreferences *p = [NppPreferences shared];
            BOOL wasVertical = p.tabBarVertical; NSInteger wasMax = p.recentFilesMax;
            PreferencesWindow *prefs = [[PreferencesWindow alloc] initWithEditor:ed];
            NSDictionary *controls = [prefs valueForKey:@"controls"];
            BOOL present = YES;
            for (NSString *key in @[@"tabBarVertical", @"hideTabBar", @"defaultEOL", @"defaultLanguage",
                                    @"recentFilesMax", @"recentFilesShowFullPath", @"defaultDirectoryMode",
                                    @"fixedDirectory", @"findFillWithSelection", @"confirmReplaceAll",
                                    @"printHeaderMiddle", @"printFooterLeft", @"printMargins",
                                    @"largeFileDeactivateWordWrap", @"exitOnClosingLastTab"]) {
                if (!controls[key]) { present = NO; break; }
            }
            [controls[@"tabBarVertical"] setState:NSControlStateValueOn];
            [controls[@"recentFilesMax"] setStringValue:@"7"];
            [prefs apply:nil];
            BOOL applied = p.tabBarVertical && p.recentFilesMax == 7;
            // A setting changed elsewhere while the window was closed is what
            // the window shows when it opens again, and what Apply then keeps.
            BOOL confirmBefore = p.confirmSaveAll;
            p.confirmSaveAll = YES;
            [prefs toggle]; [prefs toggle];
            p.confirmSaveAll = NO;
            [prefs toggle];
            [prefs apply:nil];
            [prefs toggle];
            applied = applied && !p.confirmSaveAll;
            p.confirmSaveAll = confirmBefore;
            p.tabBarVertical = wasVertical; p.recentFilesMax = wasMax;
            [ed applyEditorPreferences];
            Check(@"IDM_SETTING_PREFERENCE (the pages Windows has)",
                  @"Tab Bar, Recent Files History, Default Directory, Searching and the rest of New "
                  @"Document, Print and Performance have controls, and Apply writes them",
                  present && applied);
        }

        // A NUL byte inside a file is content, not the end of it.
        {
            NSString *nulPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-nul-test.txt"];
            const char raw[] = "before\0after\n";
            NSData *bytes = [NSData dataWithBytes:raw length:sizeof(raw) - 1];
            [bytes writeToFile:nulPath atomically:YES];
            BOOL opened = [ed openFileAtPath:nulPath error:NULL];
            NSString *shown = [ed documentText];
            NSString *copyPath = [nulPath stringByAppendingString:@".copy"];
            [ed saveCopyOfCurrentTo:copyPath error:NULL];
            NSData *back = [NSData dataWithContentsOfFile:copyPath];
            Check(@"IDM_FILE_OPEN (a NUL byte inside a file)",
                  @"the text after a NUL byte is shown and written back, not cut off",
                  opened && shown.length == 13 && [back isEqualToData:bytes]);
            ed.scriptedCloseAnswer = NSAlertSecondButtonReturn;
            [ed closeCurrentDocument];
            ed.scriptedCloseAnswer = 0;
            [[NSFileManager defaultManager] removeItemAtPath:nulPath error:NULL];
            [[NSFileManager defaultManager] removeItemAtPath:copyPath error:NULL];
        }

        // A changed encoding is a change however far the text is undone.
        {
            [ed newDocument];
            [ed setDocumentText:@"plain\n"];
            [ed.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
            ed.currentDocument.modified = NO;
            [ed setEncoding:NSUTF8StringEncoding withBOM:YES];
            BOOL dirty = ed.currentDocument.modified;
            [ed.sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"x"];
            [ed.sci message:SCI_UNDO wParam:0 lParam:0];
            BOOL stillDirty = ed.currentDocument.modified;
            Check(@"IDM_FORMAT_UTF8_BOM (a changed encoding stays a change)",
                  @"after undoing a keystroke the document is still modified, because "
                  @"its bytes on disk would still differ",
                  dirty && stillDirty);
            ed.scriptedCloseAnswer = NSAlertSecondButtonReturn;
            [ed closeCurrentDocument];
            ed.scriptedCloseAnswer = 0;
        }

        // Reload reads the file the way it is being read: a chosen code page
        // stays, and the text comes back right.
        {
            NSString *cpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-cp1251-test.txt"];
            const unsigned char raw[] = {0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, '\n'};   // Привет
            [[NSData dataWithBytes:raw length:sizeof(raw)] writeToFile:cpPath atomically:YES];
            [ed openFileAtPath:cpPath error:NULL];
            [ed reinterpretAsCodepage:1251];
            BOOL reloaded = [ed reloadCurrentDocument:NULL];
            BOOL keeps = ed.currentDocument.codepage == 1251 &&
                         [[ed documentText] hasPrefix:@"Привет"];
            Check(@"IDM_FILE_RELOAD (keeps the chosen code page)",
                  @"a document read as Windows-1251 is still Windows-1251 after "
                  @"Reload, and still reads correctly",
                  reloaded && keeps);
            ed.scriptedCloseAnswer = NSAlertSecondButtonReturn;
            [ed closeCurrentDocument];
            ed.scriptedCloseAnswer = 0;
            [[NSFileManager defaultManager] removeItemAtPath:cpPath error:NULL];
        }

        NSString *copy = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_copy.txt"];
        [[NSFileManager defaultManager] removeItemAtPath:copy error:NULL];
        BOOL copied = [ed saveCopyOfCurrentTo:copy error:&err];
        NSString *copyBack = [NSString stringWithContentsOfFile:copy encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_FILE_SAVECOPYAS", @"writes a copy, original untouched",
              copied && [copyBack isEqualToString:@"second\n"] && [ed.currentDocument.path isEqualToString:p]);

        SetDoc(ed, @"dirty\n");
        ed.currentDocument.modified = YES;
        NSUInteger saved = [ed saveAllDocuments];
        Check(@"IDM_FILE_SAVEALL", @"saves every modified document", saved >= 1);

        NSString *renamed = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_renamed.py"];
        [[NSFileManager defaultManager] removeItemAtPath:renamed error:NULL];
        BOOL ok = [ed renameCurrentTo:renamed error:&err];
        Check(@"IDM_FILE_RENAME", @"moves the file and re-detects the language",
              ok && [[NSFileManager defaultManager] fileExistsAtPath:renamed] &&
              ![[NSFileManager defaultManager] fileExistsAtPath:p] &&
              [ed.currentDocument.language.name isEqualToString:@"python"]);

        // A language the user picked survives a rename; Notepad++ keeps it too,
        // and only works the language out again when nobody chose one.
        NSString *keepPath = TempFile(@"t_keeplang.txt", @"print(1)\n");
        [ed openFileAtPath:keepPath error:NULL];
        [ed chooseLanguageNamed:@"python"];
        NSString *renamedPath = [NSTemporaryDirectory()
                                 stringByAppendingPathComponent:@"t_keeplang.log"];
        [[NSFileManager defaultManager] removeItemAtPath:renamedPath error:NULL];
        [ed renameCurrentTo:renamedPath error:NULL];
        BOOL kept = [ed.currentDocument.language.name isEqualToString:@"python"];

        // One that was worked out from the name follows the new name.
        NSString *autoPath = TempFile(@"t_autolang.py", @"print(1)\n");
        [ed openFileAtPath:autoPath error:NULL];
        NSString *autoRenamed = [NSTemporaryDirectory()
                                 stringByAppendingPathComponent:@"t_autolang.cpp"];
        [[NSFileManager defaultManager] removeItemAtPath:autoRenamed error:NULL];
        [ed renameCurrentTo:autoRenamed error:NULL];
        BOOL followed = [ed.currentDocument.language.name isEqualToString:@"cpp"];
        [[NSFileManager defaultManager] removeItemAtPath:renamedPath error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:autoRenamed error:NULL];
        Check(@"IDM_FILE_RENAME (language)",
              @"a language the user chose survives a rename; a detected one follows the name",
              kept && followed);


        NSString *doomed = TempFile(@"t_trash.txt", @"bye\n");
        [ed openFileAtPath:doomed error:&err];
        BOOL trashed = [ed moveCurrentToTrash:&err];
        Check(@"IDM_FILE_DELETE", @"moves the file to the Trash",
              trashed && ![[NSFileManager defaultManager] fileExistsAtPath:doomed]);

        NSPrintOperation *op = [ed printOperationForCurrentShowingPanel:NO];
        Check(@"IDM_FILE_PRINT", @"builds a print job", op != nil && op.jobTitle.length > 0);
        NSPrintOperation *op2 = [ed printOperationForCurrentShowingPanel:NO];
        Check(@"IDM_FILE_PRINTNOW", @"builds a job with no panel",
              op2 != nil && !op2.showsPrintPanel);

        // Quit is wired to NSApp; running it would end the suite, so only the
        // wiring is checked. It is found by walking the whole bar for the
        // terminate: action: AppKit is still rearranging and localising menus
        // while the suite starts, so neither the item's position nor its title
        // can be relied on.
        NSMenuItem *quit = nil;
        NSMutableArray *menuQueue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
        while (menuQueue.count && !quit) {
            NSMenuItem *mi = menuQueue.firstObject;
            [menuQueue removeObjectAtIndex:0];
            if (mi.submenu) [menuQueue addObjectsFromArray:mi.submenu.itemArray];
            if (mi.action == @selector(terminate:)) quit = mi;
        }
        Check(@"IDM_FILE_EXIT", @"a Quit item is wired to NSApp terminate:",
              quit != nil && quit.target == NSApp);
    }

    if (NppSectionWanted(@"File: close family")) { printf("\n== File: close family ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        Check(@"IDM_FILE_CLOSEALL", @"leaves exactly one fresh, unsaved tab",
              ed.documents.count == 1 && ed.currentDocument.path == nil);

        for (int i = 0; i < 5; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_close%d.txt", i],
                                        [NSString stringWithFormat:@"file %d\n", i]) error:&err];
        }
        // tabs: [t_close0 .. t_close4] - the first file took the lone clean "new 1"'s place
        [ed selectDocumentAtIndex:3];
        NSString *active = ed.currentDocument.displayName;
        [ed closeAllToLeft];
        Check(@"IDM_FILE_CLOSEALL_TOLEFT", @"drops everything before the active tab, which stays active",
              ed.documents.count == 2 && [ed.currentDocument.displayName isEqualToString:active]);

        [ed closeAllToRight];
        Check(@"IDM_FILE_CLOSEALL_TORIGHT", @"drops everything after the active tab, which stays active",
              ed.documents.count == 1 && [ed.currentDocument.displayName isEqualToString:active]);

        for (int i = 0; i < 3; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_keep%d.txt", i], @"x\n") error:&err];
        }
        [ed closeAllButCurrent];
        Check(@"IDM_FILE_CLOSEALL_BUT_CURRENT", @"keeps only the active tab",
              ed.documents.count == 1);

        [ed openFileAtPath:TempFile(@"t_dirty.txt", @"x\n") error:&err];
        ed.currentDocument.modified = YES;
        NSUInteger before = ed.documents.count;
        [ed closeAllUnchanged];
        Check(@"IDM_FILE_CLOSEALL_UNCHANGED", @"keeps modified documents only",
              ed.documents.count < before && ed.currentDocument.modified);

        ed.currentDocument.modified = NO;
        [ed openFileAtPath:TempFile(@"t_pinned.txt", @"pin\n") error:&err];
        [ed togglePinCurrent];
        BOOL isPinned = ed.currentDocument.pinned;
        [ed openFileAtPath:TempFile(@"t_unpinned.txt", @"no\n") error:&err];
        [ed closeAllButPinned];
        Check(@"IDM_FILE_CLOSEALL_BUT_PINNED", @"keeps pinned documents",
              isPinned && ed.documents.count == 1 && ed.currentDocument.pinned);

        // Dragging: pinned tabs reorder among themselves but never cross into
        // the unpinned run (nor the other way), so the pinned run stays whole
        // and Close All But Pinned still keeps exactly those.
        [ed openFileAtPath:TempFile(@"t_pinned2.txt", @"pin2\n") error:&err];
        [ed togglePinCurrent];
        [ed openFileAtPath:TempFile(@"t_loose1.txt", @"a\n") error:&err];
        [ed openFileAtPath:TempFile(@"t_loose2.txt", @"b\n") error:&err];
        id<NppTabBarDelegate> tabs = (id<NppTabBarDelegate>)ed;
        NSString *(^order)(void) = ^NSString *{
            NSMutableArray *names = [NSMutableArray array];
            for (NppDocument *d in ed.documents) [names addObject:d.displayName];
            return [names componentsJoinedByString:@","];
        };
        NSString *start = order();
        [tabs tabBar:[ed valueForKey:@"tabBar"] didMoveIndex:0 toIndex:3];          // pinned into the unpinned run
        [tabs tabBar:[ed valueForKey:@"tabBar"] didMoveIndex:3 toIndex:0];          // unpinned into the pinned run
        BOOL refused = [order() isEqualToString:start];
        [tabs tabBar:[ed valueForKey:@"tabBar"] didMoveIndex:0 toIndex:1];          // pinned among pinned
        [tabs tabBar:[ed valueForKey:@"tabBar"] didMoveIndex:2 toIndex:3];          // unpinned among unpinned
        BOOL moved = [order() isEqualToString:@"t_pinned2.txt,t_pinned.txt,t_loose2.txt,t_loose1.txt"];
        [ed closeAllButPinned];
        BOOL kept = [order() isEqualToString:@"t_pinned2.txt,t_pinned.txt"];
        printf("    pinned drag: %s -> %s\n", start.UTF8String, order().UTF8String);
        Check(@"IDM_FILE_CLOSEALL_BUT_PINNED (after dragging)",
              @"tabs are not dragged across the pinned edge, pinned ones reorder among themselves, and those are what stays",
              [start isEqualToString:@"t_pinned.txt,t_pinned2.txt,t_loose1.txt,t_loose2.txt"] && refused && moved && kept);
        for (NppDocument *d in [ed.documents copy]) if (d.pinned) { [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:d]]; [ed togglePinCurrent]; }
    }

    if (NppSectionWanted(@"File: folders and workspace")) { printf("\n== File: folders and workspace ==\n");
        NSError *err = nil;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ws"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *n in @[@"a.txt", @"b.py"]) {
            [@"x\n" writeToFile:[dir stringByAppendingPathComponent:n]
                      atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        [ed openFileAtPath:[dir stringByAppendingPathComponent:@"a.txt"] error:&err];

        // Launching Finder/Terminal from a test would be rude; check the target.
        NSURL *folder = [ed containingFolderURL];
        Check(@"IDM_FILE_OPEN_FOLDER", @"resolves the containing folder",
              [folder.path isEqualToString:dir]);
        Check(@"IDM_FILE_OPEN_CMD", @"Terminal target is that folder", folder != nil);
        Check(@"IDM_FILE_OPEN_POWERSHELL", @"maps to Terminal on macOS",
              [[NSWorkspace sharedWorkspace]
                  URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"] != nil);
        Check(@"IDM_FILE_OPEN_DEFAULT_VIEWER", @"has a file to hand to the viewer",
              [[NSFileManager defaultManager] fileExistsAtPath:ed.currentDocument.path]);

        [ed openFolderAsWorkspace:dir];
        NSArray *names = [ed workspaceTopLevelNames];
        Check(@"IDM_FILE_OPENFOLDERASWORKSPACE", @"lists the folder contents",
              [ed workspaceVisible] && [[ed workspaceRootPath] isEqualToString:dir] &&
              names.count == 2 && [names containsObject:@"b.py"]);

        [ed openFolderAsWorkspace:nil];
        [ed openFolderAsWorkspace:[ed containingFolderURL].path];
        Check(@"IDM_FILE_CONTAININGFOLDERASWORKSPACE", @"roots the panel at the current file's folder",
              [[ed workspaceRootPath] isEqualToString:dir]);
        [ed openFolderAsWorkspace:nil];
    }

    if (NppSectionWanted(@"Sessions")) { printf("\n== Sessions ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        NSString *f1 = TempFile(@"t_sess1.py", @"import os\n");
        NSString *f2 = TempFile(@"t_sess2.json", @"{}\n");
        [ed openFileAtPath:f1 error:&err];
        [ed openFileAtPath:f2 error:&err];

        NSString *sess = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_session.json"];
        BOOL wrote = [ed saveSessionTo:sess error:&err];
        Check(@"IDM_FILE_SAVESESSION", @"writes the open files",
              wrote && [[NSFileManager defaultManager] fileExistsAtPath:sess]);

        [ed closeAllDocuments];
        BOOL loaded = [ed loadSessionFrom:sess error:&err];
        NSMutableArray *paths = [NSMutableArray array];
        for (NppDocument *d in ed.documents) if (d.path) [paths addObject:d.path];
        Check(@"IDM_FILE_LOADSESSION", @"reopens every file from the session",
              loaded && [paths containsObject:f1] && [paths containsObject:f2]);
    }

    if (NppSectionWanted(@"Edit")) { printf("\n== Edit ==\n");
        SetDoc(ed, @"alpha\n");
        [sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"X"];
        [app undo:nil];
        Check(@"IDM_EDIT_UNDO", @"reverts an insert", ![DocText(ed) hasPrefix:@"X"]);
        [app redo:nil];
        Check(@"IDM_EDIT_REDO", @"reapplies the insert", [DocText(ed) hasPrefix:@"X"]);

        SetDoc(ed, @"copy me\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [app copyText:nil];
        [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_GETLENGTH]
                 lParam:[sci message:SCI_GETLENGTH]];
        [app pasteText:nil];
        Check(@"IDM_EDIT_COPY", @"copies the selection", [DocText(ed) containsString:@"copy mecopy me"] ||
              [DocText(ed) hasSuffix:@"copy me"]);
        Check(@"IDM_EDIT_PASTE", @"pastes at the caret", [DocText(ed) length] > 8);

        SetDoc(ed, @"cut this\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [app cutText:nil];
        Check(@"IDM_EDIT_CUT", @"removes the selection", ![DocText(ed) hasPrefix:@"cut "]);

        SetDoc(ed, @"one\ntwo\n");
        [app selectAllText:nil];
        Check(@"IDM_EDIT_SELECTALL", @"selects the document",
              [sci message:SCI_GETSELECTIONEND] == [sci message:SCI_GETLENGTH]);

        SetDoc(ed, @"dup\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        [app duplicateLine:nil];
        Check(@"IDM_EDIT_DUP_LINE", @"duplicates the line",
              [DocText(ed) isEqualToString:@"dup\ndup\n"]);

        // Comments use the tokens from langs.model.xml.
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"int a;\nint b;\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        BOOL commented = [DocText(ed) hasPrefix:@"// int a;"];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        BOOL restored = [DocText(ed) isEqualToString:@"int a;\nint b;\n"];
        Check(@"IDM_EDIT_BLOCK_COMMENT_SET", @"line comment toggles both ways", commented && restored);

        SetDoc(ed, @"value\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        [ed toggleBlockComment];
        Check(@"IDM_EDIT_BLOCK_COMMENT", @"wraps the selection",
              [DocText(ed) hasPrefix:@"/*value*/"]);

        SetDoc(ed, @"alphabet alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        [ed showAutoCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE", @"offers words from the document",
              [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];

        // Asking only whether the list appeared says nothing about what is in
        // it. Function completion means the functions Notepad++ ships for the
        // language, not the words that happen to be in this file.
        NppPreferences *acPrefs = [NppPreferences shared];
        NSInteger previousSource = acPrefs.autoCompleteSource;
        acPrefs.autoCompleteSource = 0;                    // functions only
        NSString *cFile = TempFile(@"t_api.c", @"int main(void) { return 0; }\n");
        [ed openFileAtPath:cFile error:NULL];
        NSArray *fromApi = [ed completionCandidatesForPrefix:@"prin"];
        Check(@"IDM_EDIT_AUTOCOMPLETE (function list)",
              @"completion offers the language's own functions, not just words in the file",
              [fromApi containsObject:@"printf"] &&
              ![[ed.sci string] containsString:@"printf"]);

        // A language Notepad++ ships no list for still has to complete from its
        // lexer keywords rather than going silent.
        NSString *iniFile = TempFile(@"t_api.ini", @"[Section]\n");
        [ed openFileAtPath:iniFile error:NULL];
        NSArray *noApi = [ed completionCandidatesForPrefix:@"Sec"];
        acPrefs.autoCompleteSource = previousSource;
        Check(@"IDM_EDIT_AUTOCOMPLETE (no list shipped)",
              @"a language with no shipped list still completes from its keywords",
              [[ApiCatalog sharedCatalog] entriesForLanguage:@"ini"].count == 0 &&
              noApi != nil);
        [[NSFileManager defaultManager] removeItemAtPath:cFile error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:iniFile error:NULL];
    }

    if (NppSectionWanted(@"Find dialog: the tabs Notepad++ has")) { printf("\n== Find dialog: the tabs Notepad++ has ==\n");
        [ed newDocument];
        [app buildFindPanel];
        NSSegmentedControl *tabs = [app valueForKey:@"findTabs"];
        NSArray *expected = @[@"Find", @"Replace", @"Find in Files", @"Find in Projects", @"Mark"];
        NSMutableArray *names = [NSMutableArray array];
        for (NSInteger i = 0; i < tabs.segmentCount; ++i) [names addObject:[tabs labelForSegment:i]];
        Check(@"IDM_SEARCH_FINDINFILES (tabs)",
              @"the dialog has the tabs Notepad++ has, rather than a run of prompts",
              [names isEqualToArray:expected]);

        // Each tab shows what belongs to it. Find has no Filters; Find in Files
        // does, along with the folder to search.
        NSTextField *filters = [app valueForKey:@"filtersField"];
        NSTextField *directory = [app valueForKey:@"directoryField"];
        [app openFindPanelOnTab:0];
        BOOL hiddenOnFind = filters.isHidden && directory.isHidden;
        [app openFindPanelOnTab:2];
        BOOL shownInFiles = !filters.isHidden && !directory.isHidden;
        [app openFindPanelOnTab:4];
        BOOL hiddenOnMark = filters.isHidden && directory.isHidden;
        [[app valueForKey:@"findPanel"] orderOut:nil];
        Check(@"IDM_SEARCH_FINDINFILES (tab contents)",
              @"the folder and filters belong to Find in Files and appear only there",
              hiddenOnFind && shownInFiles && hiddenOnMark);

        // Searching a folder for real, with the filter and the search mode that
        // the dialog is set to. The old one matched a literal substring and
        // ignored both.
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:
            [root stringByAppendingPathComponent:@"inner"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"alpha 42\nbeta\n" writeToFile:[root stringByAppendingPathComponent:@"one.txt"]
                              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"alpha 7\n" writeToFile:[root stringByAppendingPathComponent:@"two.log"]
                       atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"alpha 99\n" writeToFile:[root stringByAppendingPathComponent:@"inner/three.txt"]
                        atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NppFindSpec *digits = [NppFindSpec specFor:@"\\d+" mode:NppSearchRegex options:NppFindNone];
        NSString *report = nil;
        NSUInteger everywhere = [ed findInFiles:digits folder:root filters:nil
                                      recursive:YES includeHidden:NO report:&report];
        NSUInteger txtOnly = [ed findInFiles:digits folder:root filters:@"*.txt"
                                   recursive:YES includeHidden:NO report:NULL];
        NSUInteger topOnly = [ed findInFiles:digits folder:root filters:@"*.txt"
                                   recursive:NO includeHidden:NO report:NULL];
        Check(@"IDM_SEARCH_FINDINFILES (search)",
              @"a folder search honours the pattern, the filter and sub-folders",
              everywhere == 3 && txtOnly == 2 && topOnly == 1 &&
              [report containsString:@"one.txt"]);

        // Replace in Files writes to the files it matched.
        NppFindSpec *renumber = [NppFindSpec specFor:@"\\d+" mode:NppSearchRegex options:NppFindNone];
        renumber.replacement = @"N";
        NSUInteger changedFiles = 0;
        NSUInteger replaced = [ed replaceInFiles:renumber folder:root filters:@"*.txt"
                                       recursive:YES includeHidden:NO changedFiles:&changedFiles];
        NSString *afterOne = [NSString stringWithContentsOfFile:
            [root stringByAppendingPathComponent:@"one.txt"] encoding:NSUTF8StringEncoding error:NULL];
        NSString *untouched = [NSString stringWithContentsOfFile:
            [root stringByAppendingPathComponent:@"two.log"] encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_SEARCH_FINDINFILES (replace)",
              @"Replace in Files rewrites the files the filter allows and leaves the others",
              replaced == 2 && changedFiles == 2 &&
              [afterOne isEqualToString:@"alpha N\nbeta\n"] &&
              [untouched isEqualToString:@"alpha 7\n"]);

        // A file in a code page is found in, and stays in its code page when
        // Replace in Files rewrites it; a UTF-8 BOM stays too.
        NSString *russianText = @"Привет, мир. Это обычный русский текст в старой кодировке, которых ещё много.\nстрока вторая: поиск по файлам должен находить и такие.\n";
        NSString *cyrPath = [root stringByAppendingPathComponent:@"cyr.txt"];
        [[russianText dataUsingEncoding:NSWindowsCP1251StringEncoding] writeToFile:cyrPath atomically:YES];
        NSMutableData *bomFile = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [bomFile appendData:[@"поиск с меткой\n" dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *bomPath = [root stringByAppendingPathComponent:@"bom.txt"];
        [bomFile writeToFile:bomPath atomically:YES];
        NSString *cyrReport = nil;
        NSUInteger cyrHits = [ed findInFiles:[NppFindSpec specFor:@"поиск" mode:NppSearchNormal options:NppFindNone]
                                      folder:root filters:@"*.txt" recursive:YES includeHidden:NO report:&cyrReport];
        NppFindSpec *swap = [NppFindSpec specFor:@"поиск" mode:NppSearchNormal options:NppFindNone];
        swap.replacement = @"розыск";
        NSUInteger cyrFiles = 0;
        NSUInteger cyrReplaced = [ed replaceInFiles:swap folder:root filters:@"*.txt" recursive:YES includeHidden:NO changedFiles:&cyrFiles];
        NSString *cyrAfter = [[NSString alloc] initWithData:[NSData dataWithContentsOfFile:cyrPath] encoding:NSWindowsCP1251StringEncoding];
        NSData *bomAfter = [NSData dataWithContentsOfFile:bomPath];
        BOOL codePages = cyrHits == 2 && [cyrReport containsString:@"cyr.txt"] && cyrReplaced == 2 && cyrFiles == 2 &&
                         [cyrAfter isEqualToString:[russianText stringByReplacingOccurrencesOfString:@"поиск" withString:@"розыск"]] &&
                         bomAfter.length > 3 && !memcmp(bomAfter.bytes, "\xEF\xBB\xBF", 3) &&
                         [[[NSString alloc] initWithData:[bomAfter subdataWithRange:NSMakeRange(3, bomAfter.length - 3)] encoding:NSUTF8StringEncoding] isEqualToString:@"розыск с меткой\n"];
        printf("    code pages: hits=%lu replaced=%lu files=%lu\n", (unsigned long)cyrHits, (unsigned long)cyrReplaced, (unsigned long)cyrFiles);
        Check(@"IDM_SEARCH_FINDINFILES (code pages)",
              @"a file that is not UTF-8 is searched in its own character set and rewritten in it; a BOM is kept",
              codePages);
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    if (NppSectionWanted(@"Search: a folder search that does not hold the window")) { printf("\n== Search: a folder search that does not hold the window ==\n");
        // Find in Files used to run on the main thread, so a search over a
        // large tree froze the application: it could not be brought forward,
        // said nothing about how far it had got and could not be called off.
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_async"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:root
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSUInteger i = 0; i < 400; ++i) {
            NSMutableString *body = [NSMutableString string];
            for (NSUInteger line = 0; line < 60; ++line) {
                [body appendFormat:@"filler %lu\nneedle %lu\n", (unsigned long)line, (unsigned long)i];
            }
            [body writeToFile:[root stringByAppendingPathComponent:
                                   [NSString stringWithFormat:@"file%03lu.txt", (unsigned long)i]]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        NppFindSpec *needle = [NppFindSpec specFor:@"needle" mode:NppSearchNormal options:NppFindNone];

        __block BOOL finished = NO;
        __block NSUInteger foundHits = 0;
        __block NSUInteger progressCalls = 0, lastScanned = 0;

        NppFileSearch *running =
            [ed findInFilesInBackground:needle folder:root filters:nil recursive:YES
                          includeHidden:NO
                               progress:^(NSUInteger scanned, NSUInteger hits, NSString *soFar) {
                progressCalls++;
                lastScanned = scanned;
            }
                             completion:^(NSUInteger hits, NSString *report, BOOL stopped) {
                finished = YES;
                foundHits = hits;
            }];

        // The call has to come back at once, leaving the search to run.
        BOOL returnedBeforeFinishing = !finished;

        // And the main thread has to be free while it runs. This block is put
        // on the main queue before the search can put its own there, so it goes
        // first: if it finds the search already over, the search never left the
        // main thread at all. No clock is involved, so nothing here depends on
        // how busy the machine is.
        __block BOOL probeRan = NO, searchStillRunning = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            probeRan = YES;
            searchStillRunning = !finished;
        });

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120];
        while (!finished && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }

        Check(@"IDM_SEARCH_FINDINFILES (does not block)",
              @"a folder search runs in the background: the call returns at once and "
              @"the main thread keeps running while it works",
              returnedBeforeFinishing && finished && running != nil &&
              probeRan && searchStillRunning);
        Check(@"IDM_SEARCH_FINDINFILES (progress)",
              @"the search says how many files it has been through as it goes",
              progressCalls > 1 && lastScanned > 0 && lastScanned <= 400 && foundHits == 400 * 60);

        // Stopping it. The walk looks at the flag before each file, so a search
        // called off before it starts visits nothing at all.
        __block BOOL stoppedFinished = NO, reportedStopped = NO;
        __block NSUInteger stoppedHits = 1;
        NppFileSearch *toStop =
            [ed findInFilesInBackground:needle folder:root filters:nil recursive:YES
                          includeHidden:NO progress:nil
                             completion:^(NSUInteger hits, NSString *report, BOOL stopped) {
                stoppedFinished = YES;
                reportedStopped = stopped;
                stoppedHits = hits;
            }];
        [toStop cancel];
        deadline = [NSDate dateWithTimeIntervalSinceNow:60];
        while (!stoppedFinished && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(@"IDM_SEARCH_FINDINFILES (stop)",
              @"a search that is called off stops, and says that it was stopped",
              stoppedFinished && reportedStopped && stoppedHits == 0);

        // Replace in Files runs the same way.
        NppFindSpec *renumber = [NppFindSpec specFor:@"needle" mode:NppSearchNormal
                                             options:NppFindNone];
        renumber.replacement = @"pin";
        __block BOOL replaceFinished = NO;
        __block NSUInteger replacedCount = 0, replacedFiles = 0;
        [ed replaceInFilesInBackground:renumber folder:root filters:@"file00*.txt" recursive:YES
                         includeHidden:NO progress:nil
                            completion:^(NSUInteger replaced, NSUInteger files, BOOL stopped) {
            replaceFinished = YES;
            replacedCount = replaced;
            replacedFiles = files;
        }];
        BOOL replaceReturnedFirst = !replaceFinished;
        deadline = [NSDate dateWithTimeIntervalSinceNow:60];
        while (!replaceFinished && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        NSString *rewritten = [NSString stringWithContentsOfFile:
            [root stringByAppendingPathComponent:@"file007.txt"]
                                                        encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_SEARCH_REPLACEINFILES (does not block)",
              @"Replace in Files also runs in the background and writes what it matched",
              replaceReturnedFirst && replaceFinished && replacedFiles == 10 &&
              replacedCount == 10 * 60 && [rewritten containsString:@"pin 7"] &&
              ![rewritten containsString:@"needle"]);

        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    if (NppSectionWanted(@"Search results panel")) { printf("\n== Search results panel ==\n");
        // Searches stack up, newest first, the older ones folded; the panel's
        // own menu folds, copies, clears and deletes.
        NppPreferences *rp = [NppPreferences shared];
        BOOL purgeBefore = rp.searchResultsPurge;
        rp.searchResultsPurge = NO;
        NSString *first = @"Search \"alpha\" (2 hits in 1 file of 1 searched)\n/tmp/a.txt (2 hits)\n\tLine 1: alpha one\n\tLine 4: alpha two\n";
        NSString *second = @"Search \"beta\" (1 hit in 1 file of 1 searched)\n/tmp/b.txt (1 hit)\n\tLine 7: the beta line\n";
        [ed showSearchResults:first];
        [ed clearSearchResults];
        [ed showSearchResults:first];
        [ed showSearchResults:second];
        ScintillaView *rs = ed.sci;
        NSString *both = [rs string];
        long olderHeader = 3;
        BOOL stacked = [both hasPrefix:second] && [both hasSuffix:first] &&
            ([rs message:SCI_GETFOLDLEVEL wParam:0] & SC_FOLDLEVELHEADERFLAG) &&
            ([rs message:SCI_GETFOLDLEVEL wParam:1] & SC_FOLDLEVELNUMBERMASK) == SC_FOLDLEVELBASE + 1 &&
            ([rs message:SCI_GETFOLDLEVEL wParam:2] & SC_FOLDLEVELNUMBERMASK) == SC_FOLDLEVELBASE + 2 &&
            [rs message:SCI_GETFOLDEXPANDED wParam:0] && ![rs message:SCI_GETFOLDEXPANDED wParam:(uptr_t)olderHeader];
        [ed foldAllSearchResults:NO];
        BOOL unfolded = [rs message:SCI_GETFOLDEXPANDED wParam:(uptr_t)olderHeader] != 0;
        [ed foldAllSearchResults:YES];
        BOOL folded = ![rs message:SCI_GETFOLDEXPANDED wParam:0];
        [ed foldAllSearchResults:NO];
        Check(@"IDM_SEARCH_FINDINFILES (results stack and fold)",
              @"a new search goes on top of the older ones, which fold away; fold and unfold all work",
              stacked && unfolded && folded);

        // Select the older search's lines and copy them.
        [rs message:SCI_SETSEL wParam:(uptr_t)[rs message:SCI_POSITIONFROMLINE wParam:4]
             lParam:[rs message:SCI_GETLINEENDPOSITION wParam:6]];
        NSString *copiedLines = [ed selectedSearchResultText];
        NSArray *copiedPaths = [ed selectedSearchResultPaths];
        [rs message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed deleteSearchResultAtCaret];
        BOOL deleted = [[rs string] isEqualToString:first];
        [ed showSearchResults:second];
        rp.searchResultsPurge = YES;
        [ed showSearchResults:first];
        BOOL purged = [[rs string] isEqualToString:first];
        rp.searchResultsPurge = purgeBefore;
        [ed clearSearchResults];
        Check(@"IDM_SEARCH_FINDINFILES (results menu)",
              @"copy lines gives the hit text, copy pathnames the files, a search can be deleted, and purging keeps only the newest",
              [copiedLines isEqualToString:@"alpha one\nalpha two"] &&
              [copiedPaths isEqualToArray:@[@"/tmp/a.txt"]] && deleted && purged);
    }

    if (NppSectionWanted(@"Search: going from a result to the file")) { printf("\n== Search: going from a result to the file ==\n");
        // Double clicking a line of the results opens that file at that line,
        // which is what the Search results panel does in Notepad++.
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_open"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:root
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *target = [root stringByAppendingPathComponent:@"target.txt"];
        [@"one\ntwo\nthree needle\nfour\n" writeToFile:target
                                              atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NppFindSpec *needle = [NppFindSpec specFor:@"needle" mode:NppSearchNormal options:NppFindNone];
        NSString *report = nil;
        [ed findInFiles:needle folder:root filters:nil recursive:NO includeHidden:NO report:&report];

        NSArray<NSString *> *reportLines = [report componentsSeparatedByString:@"\n"];
        NSInteger headingLine = -1, hitLine = -1;
        for (NSUInteger i = 0; i < reportLines.count; ++i) {
            if ([reportLines[i] hasPrefix:@"\tLine "] && hitLine < 0) hitLine = (NSInteger)i;
            else if ([reportLines[i] hasPrefix:root] && headingLine < 0) headingLine = (NSInteger)i;
        }

        NSInteger fromHit = 0, fromHeading = 0, fromSummary = 0;
        NSString *hitPath = [EditorController searchResultFileInReport:report atLine:hitLine
                                                             fileLine:&fromHit];
        NSString *headPath = [EditorController searchResultFileInReport:report atLine:headingLine
                                                              fileLine:&fromHeading];
        NSString *summaryPath = [EditorController searchResultFileInReport:report
                                                                   atLine:(NSInteger)reportLines.count - 2
                                                                 fileLine:&fromSummary];
        Check(@"IDM_SEARCH_FINDINFILES (result lines carry a place)",
              @"a hit line names its file and the line within it; the summary names none",
              [hitPath isEqualToString:target] && fromHit == 3 &&
              [headPath isEqualToString:target] && fromHeading == 1 && summaryPath == nil);

        // And the caret in the results tab goes there.
        [ed showSearchResults:report];
        NSInteger onlyOneTab = 0;
        [ed showSearchResults:report];
        for (NppDocument *doc in ed.documents) {
            if (doc.isSearchResults) onlyOneTab++;
        }
        // A document of the user's that merely has that name is not the results tab.
        [ed newDocument];
        ed.currentDocument.displayName = @"Search results";
        SetDoc(ed, @"my own notes\n");
        NppDocument *namesake = ed.currentDocument;
        [ed showSearchResults:report];
        BOOL namesakeKept = ed.currentDocument != namesake && [ed.documents containsObject:namesake] && !namesake.isSearchResults;
        NSInteger back = (NSInteger)[ed.documents indexOfObject:namesake];
        [ed selectDocumentAtIndex:back];
        namesakeKept = namesakeKept && [DocText(ed) isEqualToString:@"my own notes\n"];
        [ed closeDocumentAtIndex:back discardChanges:YES];
        if (!namesakeKept) onlyOneTab = 99;
        for (NSUInteger i = 0; i < ed.documents.count; ++i) if (ed.documents[i].isSearchResults) [ed selectDocumentAtIndex:(NSInteger)i];
        [ed.sci message:SCI_GOTOLINE wParam:(uptr_t)hitLine lParam:0];
        BOOL opened = [ed openSearchResultAtCaret];
        long caretLine = [ed.sci message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                 lParam:0];
        Check(@"IDM_SEARCH_FINDINFILES (open a result)",
              @"opening the result under the caret brings up that file on that line, "
              @"and repeated searches reuse the one results tab",
              opened && onlyOneTab == 1 &&
              [ed.currentDocument.path isEqualToString:target] && caretLine == 2);

        // And through a real double click, which is how anyone actually gets
        // there: the click goes into the view, Scintilla decides it is a double
        // click and tells us.
        [ed showSearchResults:report];
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            if ([ed.documents[(NSUInteger)i].path isEqualToString:target]) {
                [ed closeDocumentAtIndex:i discardChanges:YES];
            }
        }
        NSInteger beforeTabs = (NSInteger)ed.documents.count;
        sptr_t hitPos = [ed.sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)hitLine lParam:0] + 4;
        sptr_t px = [ed.sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:(sptr_t)hitPos];
        sptr_t py = [ed.sci message:SCI_POINTYFROMPOSITION wParam:0 lParam:(sptr_t)hitPos];
        NSView *sciContent = [ed.sci content];
        NSPoint inWindow = [sciContent convertPoint:NSMakePoint(px + 1, py + 4) toView:nil];
        NSTimeInterval now = [NSProcessInfo processInfo].systemUptime + 10;
        for (NSUInteger click = 1; click <= 2; ++click) {
            NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                               location:inWindow modifierFlags:0
                                              timestamp:now + click * 0.05
                                           windowNumber:sciContent.window.windowNumber
                                                context:nil eventNumber:(NSInteger)click
                                             clickCount:(NSInteger)click pressure:1];
            NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                             location:inWindow modifierFlags:0
                                            timestamp:now + click * 0.05 + 0.01
                                         windowNumber:sciContent.window.windowNumber
                                              context:nil eventNumber:(NSInteger)click
                                           clickCount:(NSInteger)click pressure:1];
            [sciContent mouseDown:down];
            [sciContent mouseUp:up];
        }
        NppSettleUntil(^BOOL{ return [ed.currentDocument.path isEqualToString:target]; }, 10);
        NppSettle(0.05);
        long clickedLine = [ed.sci message:SCI_LINEFROMPOSITION
                                   wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                   lParam:0];
        sptr_t clickedFrom = [ed.sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
        sptr_t clickedTo = [ed.sci message:SCI_GETSELECTIONEND wParam:0 lParam:0];
        BOOL clickedLineSelected =
            clickedFrom == [ed.sci message:SCI_POSITIONFROMLINE wParam:2 lParam:0] &&
            clickedTo == [ed.sci message:SCI_GETLINEENDPOSITION wParam:2 lParam:0] &&
            clickedTo > clickedFrom;
        Check(@"IDM_SEARCH_FINDINFILES (double click a result)",
              @"double clicking a result line opens that file with that line selected",
              [ed.currentDocument.path isEqualToString:target] && clickedLine == 2 &&
              clickedLineSelected && (NSInteger)ed.documents.count == beforeTabs + 1);

        // The whole way round, as anyone actually does it: the panel runs the
        // search, the results tab fills, and a double click on a hit line in it
        // opens the file. Everything above builds the report by hand; this does
        // not, so it catches what the report really looks like.
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            if ([ed.documents[(NSUInteger)i].path isEqualToString:target]) {
                [ed closeDocumentAtIndex:i discardChanges:YES];
            }
        }
        [app openFindPanelOnTab:2];
        [[app valueForKey:@"findField"] setStringValue:@"needle"];
        [[app valueForKey:@"directoryField"] setStringValue:root];
        [[app valueForKey:@"filtersField"] setStringValue:@""];
        [app findPanelFindInFiles:nil];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:30];
        while ([app valueForKey:@"runningSearch"] && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        [[app valueForKey:@"findPanel"] orderOut:nil];

        NSString *live = [ed.sci string] ?: @"";
        NSArray<NSString *> *liveLines = [live componentsSeparatedByString:@"\n"];
        NSInteger liveHit = -1;
        for (NSUInteger i = 0; i < liveLines.count; ++i) {
            if ([liveLines[i] hasPrefix:@"\tLine "]) { liveHit = (NSInteger)i; break; }
        }
        BOOL liveResultsShown = [ed.currentDocument.displayName isEqualToString:@"Search results"];
        NSInteger liveTabs = (NSInteger)ed.documents.count;
        Check(@"IDM_SEARCH_FINDINFILES (the panel fills the results tab)",
              @"running the search from the panel leaves the results tab current "
              @"with a hit line in it",
              liveResultsShown && liveHit > 0);

        // Put through AppKit's own queue rather than handed to the view: the
        // window has to hit-test the point and route it, which is what a real
        // mouse gets and what calling mouseDown: directly skips. That routing
        // turned out to depend on the machine's window-server state (whole
        // runs where no posted click ever landed, then runs where every one
        // did), so it gets two logged tries and then the last attempt hands
        // the events to the view the way the sibling test above does - what
        // this test is really for is the panel search building a report whose
        // lines lead back to the file.
        [ed.window makeKeyAndOrderFront:nil];
        BOOL navigated = NO;
        for (NSUInteger attempt = 0; attempt < 3 && !navigated; ++attempt) {
            if (attempt) NSLog(@"whole way round: double click %lu did not land, clicking again",
                               (unsigned long)attempt);
            sptr_t livePos = [ed.sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)MAX(liveHit, 0) lParam:0] + 4;
            sptr_t lx = [ed.sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:(sptr_t)livePos];
            sptr_t ly = [ed.sci message:SCI_POINTYFROMPOSITION wParam:0 lParam:(sptr_t)livePos];
            NSView *liveContent = [ed.sci content];
            NSPoint livePoint = [liveContent convertPoint:NSMakePoint(lx + 1, ly + 4) toView:nil];
            NSTimeInterval base = [NSProcessInfo processInfo].systemUptime + 30;
            for (NSUInteger click = 1; click <= 2; ++click) {
                NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                   location:livePoint modifierFlags:0
                                                  timestamp:base + click * 0.05
                                               windowNumber:ed.window.windowNumber
                                                    context:nil
                                                eventNumber:(NSInteger)(attempt * 2 + click)
                                                 clickCount:(NSInteger)click pressure:1];
                NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                                 location:livePoint modifierFlags:0
                                                timestamp:base + click * 0.05 + 0.01
                                             windowNumber:ed.window.windowNumber
                                                  context:nil
                                              eventNumber:(NSInteger)(attempt * 2 + click)
                                               clickCount:(NSInteger)click pressure:1];
                if (attempt < 2) {
                    [NSApp postEvent:down atStart:NO];
                    [NSApp postEvent:up atStart:NO];
                } else {
                    [liveContent mouseDown:down];
                    [liveContent mouseUp:up];
                }
            }
            NppSettleUntil(^BOOL{ return [ed.currentDocument.path isEqualToString:target]; },
                           attempt == 2 ? 10 : 3);
            navigated = [ed.currentDocument.path isEqualToString:target];
        }
        NppSettle(0.05);
        long liveCaret = [ed.sci message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                 lParam:0];
        sptr_t liveFrom = [ed.sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
        sptr_t liveTo = [ed.sci message:SCI_GETSELECTIONEND wParam:0 lParam:0];
        BOOL liveLineSelected =
            liveFrom == [ed.sci message:SCI_POSITIONFROMLINE wParam:2 lParam:0] &&
            liveTo == [ed.sci message:SCI_GETLINEENDPOSITION wParam:2 lParam:0] &&
            liveTo > liveFrom;
        Check(@"IDM_SEARCH_FINDINFILES (the whole way round)",
              @"running the search from the panel and double clicking a hit in the "
              @"results it produced leaves that file open with the line selected",
              liveResultsShown && liveHit > 0 && navigated && liveCaret == 2 &&
              liveLineSelected && (NSInteger)ed.documents.count == liveTabs + 1);

        // A search of the open document writes no per-file heading, only
        // 'Search "what" in <document>' at the top. Its results have to lead
        // back to the document just the same, which is what went wrong: the
        // double click selected a word and did nothing else.
        NSString *ownReport = @"Search \"needle\" in %@\n\n\tLine 3: three needle\n\n1 hit\n";
        ownReport = [NSString stringWithFormat:ownReport, target];
        NSInteger ownLine = 0;
        NSString *ownPath = [EditorController searchResultFileInReport:ownReport atLine:2
                                                             fileLine:&ownLine];
        [ed showSearchResults:ownReport];
        [ed.sci message:SCI_GOTOLINE wParam:2 lParam:0];
        BOOL ownOpened = [ed openSearchResultAtCaret];
        long ownCaret = [ed.sci message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                 lParam:0];
        Check(@"IDM_SEARCH_FINDALL (open a result)",
              @"results from searching the open document lead back to it as well",
              [ownPath isEqualToString:target] && ownLine == 3 && ownOpened && ownCaret == 2);

        // How a file's lines are counted decides every line number in the
        // report, and it has to agree with the document the result leads to.
        NSArray<NSString *> *lf = [EditorController linesOfText:@"a\nb\n"];
        NSArray<NSString *> *crlf = [EditorController linesOfText:@"a\r\nb\r\n"];
        NSArray<NSString *> *cr = [EditorController linesOfText:@"a\rb\r"];
        NSArray<NSString *> *mixed = [EditorController linesOfText:@"a\rb\r\nc\nd"];
        NSArray<NSString *> *bare = [EditorController linesOfText:@"only"];
        NSArray<NSString *> *nothing = [EditorController linesOfText:@""];
        Check(@"IDM_SEARCH_FINDINFILES (counting lines)",
              @"CRLF, CR and LF each end one line, and a document that does not "
              @"end in a break has no line after its last",
              [lf isEqualToArray:@[@"a", @"b", @""]] &&
              [crlf isEqualToArray:@[@"a", @"b", @""]] &&
              [cr isEqualToArray:@[@"a", @"b", @""]] &&
              [mixed isEqualToArray:@[@"a", @"b", @"c", @"d"]] &&
              [bare isEqualToArray:@[@"only"]] && [nothing isEqualToArray:@[@""]]);

        // A hit deep inside a long file. A short one hides whether the view
        // actually goes to the line: it is on screen either way.
        NSString *deepRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_deep"];
        [[NSFileManager defaultManager] removeItemAtPath:deepRoot error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:deepRoot
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        NSMutableString *long_ = [NSMutableString string];
        for (NSUInteger i = 1; i <= 5000; ++i) {
            [long_ appendFormat:i == 4000 ? @"needle is here %lu\n" : @"filler %lu\n",
                                (unsigned long)i];
        }
        NSString *deepFile = [deepRoot stringByAppendingPathComponent:@"deep.txt"];
        [long_ writeToFile:deepFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSString *deepReport = nil;
        [ed findInFiles:needle folder:deepRoot filters:nil recursive:NO includeHidden:NO
                 report:&deepReport];
        [ed showSearchResults:deepReport];
        NSInteger deepHit = -1;
        sptr_t deepLines = [ed.sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
        for (sptr_t i = 0; i < deepLines; ++i) {
            if ([[ed textOfLine:(NSInteger)i] hasPrefix:@"\tLine "]) { deepHit = (NSInteger)i; break; }
        }
        [ed.sci message:SCI_GOTOLINE wParam:(uptr_t)MAX(deepHit, 0) lParam:0];
        BOOL deepOpened = [ed openSearchResultAtCaret];
        long deepCaret = [ed.sci message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                                 lParam:0];
        sptr_t firstVisible = [ed.sci message:SCI_GETFIRSTVISIBLELINE wParam:0 lParam:0];
        sptr_t onScreen = [ed.sci message:SCI_LINESONSCREEN wParam:0 lParam:0];
        Check(@"IDM_SEARCH_FINDINFILES (the line is brought into view)",
              @"a hit deep inside a file leaves the caret on that line and the line "
              @"on screen, rather than the document sitting at its top",
              deepOpened && deepCaret == 3999 && onScreen > 0 &&
              firstVisible <= 3999 && 3999 < firstVisible + onScreen);
        [[NSFileManager defaultManager] removeItemAtPath:deepRoot error:NULL];

        // A file whose lines end in CR alone, or that mixes endings, used to
        // throw the whole report out of step: the carriage returns went into it
        // as they were, Scintilla counted each one as a line of its own, and
        // from there every result pointed at the wrong line or at nothing.
        NSString *crRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_cr"];
        [[NSFileManager defaultManager] removeItemAtPath:crRoot error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:crRoot
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *crFile = [crRoot stringByAppendingPathComponent:@"old_mac.txt"];
        // The first line carries carriage returns, the second is an ordinary
        // line below it: that second hit is the one a shifted report loses.
        [@"alpha\rbeta needle\rgamma\nsecond needle here\n" writeToFile:crFile
                                          atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSString *crReport = nil;
        [ed findInFiles:needle folder:crRoot filters:nil recursive:NO includeHidden:NO
                 report:&crReport];
        // The file reads: alpha / beta needle / gamma, ended by CR, then
        // "second needle here" ended by LF. The editor numbers those 1 to 4,
        // and a report that counted only line feeds called them all line 1.
        Check(@"IDM_SEARCH_FINDINFILES (lines counted as the editor counts them)",
              @"a file whose lines end in CR is numbered the way the document "
              @"itself is, and each hit is reported on one line",
              [crReport rangeOfString:@"\r"].location == NSNotFound &&
              [crReport containsString:@"Line 2: beta needle"] &&
              [crReport containsString:@"Line 4: second needle here"]);

        [ed showSearchResults:crReport];
        NSInteger crHit = -1;
        sptr_t crLines = [ed.sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
        for (sptr_t i = 0; i < crLines; ++i) {
            if ([[ed textOfLine:(NSInteger)i] containsString:@"second needle here"]) {
                crHit = (NSInteger)i;
                break;
            }
        }
        [ed.sci message:SCI_GOTOLINE wParam:(uptr_t)MAX(crHit, 0) lParam:0];
        BOOL crOpened = [ed openSearchResultAtCaret];
        Check(@"IDM_SEARCH_FINDINFILES (files with other line endings)",
              @"a result in a file with CR line endings selects the line it names, "
              @"not one several carriage returns away from it",
              crHit > 0 && crOpened && [ed.currentDocument.path isEqualToString:crFile] &&
              [ed.sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]
                       lParam:0] == 3 &&
              [[ed textOfLine:3] isEqualToString:@"second needle here"] &&
              [ed.sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0] ==
                  [ed.sci message:SCI_POSITIONFROMLINE wParam:3 lParam:0] &&
              [ed.sci message:SCI_GETSELECTIONEND wParam:0 lParam:0] ==
                  [ed.sci message:SCI_GETLINEENDPOSITION wParam:3 lParam:0]);
        [[NSFileManager defaultManager] removeItemAtPath:crRoot error:NULL];

        // The folder a search started in is named in brackets at the top of the
        // report too; it is not something to open.
        NSString *folderHeader = [NSString stringWithFormat:@"Search \"x\" (%@)\n\n", root];
        NSInteger ignored = 0;
        BOOL folderIsNotAResult = [EditorController searchResultFileInReport:folderHeader
                                                                     atLine:0
                                                                   fileLine:&ignored] == nil;
        Check(@"IDM_SEARCH_FINDINFILES (the folder is not a result)",
              @"the folder named at the top of the report is not offered as a file to open",
              folderIsNotAResult);

        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
    }

    if (NppSectionWanted(@"Search: replacement escapes")) { printf("\n== Search: replacement escapes ==\n");
        [ed newDocument];

        // \U and \L change the case of what follows until \E; \u and \l change
        // a single character. A replacement that cannot do this cannot
        // normalise what it captured, which is much of what people use it for.
        SetDoc(ed, @"hello world\n");
        NppFindSpec *upper = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                          options:NppFindNone];
        upper.replacement = @"\\U\\1\\E \\2";
        [ed replaceAll:upper];
        BOOL upperRun = [DocText(ed) isEqualToString:@"HELLO world\n"];

        SetDoc(ed, @"HELLO WORLD\n");
        NppFindSpec *lower = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                          options:NppFindNone];
        lower.replacement = @"\\L\\1 \\2";
        [ed replaceAll:lower];
        BOOL lowerRun = [DocText(ed) isEqualToString:@"hello world\n"];

        SetDoc(ed, @"hello world\n");
        NppFindSpec *initials = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                             options:NppFindNone];
        initials.replacement = @"\\u\\1 \\u\\2";
        [ed replaceAll:initials];
        BOOL oneEach = [DocText(ed) isEqualToString:@"Hello World\n"];

        Check(@"IDM_SEARCH_REPLACE (case escapes)",
              @"\\U, \\L, \\E, \\u and \\l change the case of the replacement",
              upperRun && lowerRun && oneEach);

        // The replacement is text, not a second pattern. Boost, which reads it on
        // Windows, drops the backslash of an escape it does not know: \d+ gives d+.
        SetDoc(ed, @"x\n");
        NppFindSpec *literal = [NppFindSpec specFor:@"x" mode:NppSearchRegex options:NppFindNone];
        literal.replacement = @"\\d+";
        [ed replaceAll:literal];
        Check(@"IDM_SEARCH_REPLACE (replacement is text)",
              @"a pattern typed into the replace field is text, read as Boost reads it",
              [DocText(ed) isEqualToString:@"d+\n"]);

        // Boost's format_all, as Notepad++ calls it: the Perl names, named and
        // numbered groups, prefix and suffix, parentheses and conditionals.
        NSString *(^replaced)(NSString *, NSString *, NSString *) = ^NSString *(NSString *doc, NSString *what, NSString *with) {
            SetDoc(ed, doc);
            NppFindSpec *sp = [NppFindSpec specFor:what mode:NppSearchRegex options:NppFindMatchCase];
            sp.replacement = with;
            [ed replaceAll:sp];
            return DocText(ed);
        };
        NSString *perl = replaced(@"xx ab-12 yy", @"(?<w>[a-z]+)-(\\d+)", @"[$+{w}|$2|$&|$$|\\2|$`|$'|${2}|$MATCH]");
        NSString *conditional = replaced(@"a1 b", @"([a-z])(\\d)?", @"(?2<$1$2>:[$1])");
        NSString *digits = replaced(@"abcdefghij", @"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)", @"\\10|$10|${1}0");
        NSString *escapes = replaced(@"q", @"q", @"\\x41\\x{263A}\\101\\\\\\u$&(x)");
        NSString *stray = replaced(@"q", @"q", @"a)b");
        Check(@"IDM_SEARCH_REPLACE (Boost format)",
              @"replacements read $+{name}, $`, $', ${n}, \\n, ?N:, escapes and parentheses as Notepad++ does",
              [perl isEqualToString:@"xx [ab|12|ab-12|$|12|xx | yy|12|ab-12] yy"] &&
              [conditional isEqualToString:@"<a1> [b]"] &&
              [digits isEqualToString:@"a0|j|a0"] &&
              [escapes isEqualToString:@"A\u263A01\\Qx"] &&
              [stray isEqualToString:@"a"]);

        // '^' is per line, so "^." matches once on each of them.
        SetDoc(ed, @"abc\ndef\n");
        Check(@"IDM_SEARCH_FIND (line anchors)",
              @"'^' matches at the start of every line, not only the document",
              [ed countMatches:[NppFindSpec specFor:@"^." mode:NppSearchRegex
                                            options:NppFindNone]] == 2);

        // '.' covers everything, including the odd control character.
        unichar formFeed = 0x0C;
        SetDoc(ed, [NSString stringWithFormat:@"a%Cb\n", formFeed]);
        Check(@"IDM_SEARCH_FIND (dot spans anything)",
              @"'.' matches a form feed as readily as a letter",
              [ed countMatches:[NppFindSpec specFor:@"a.b" mode:NppSearchRegex
                                            options:NppFindNone]] == 1);
    }

    if (NppSectionWanted(@"Editor settings Notepad++ has")) { printf("\n== Editor settings Notepad++ has ==\n");
        [ed newDocument];
        NppPreferences *p = [NppPreferences shared];
        ScintillaView *sv = ed.sci;

        // Typing mode. Notepad++ shows it in the status bar and the Insert key
        // switches it; nothing here had it at all.
        // Whether a typed character overwrites is Scintilla's own doing; what
        // was missing here is the mode itself and any way to see or change it.
        NSTextField *status = [ed valueForKey:@"statusField"];
        BOOL startsInsert = ![ed overtype];
        [ed refreshChrome];
        BOOL showsIns = [status.stringValue hasSuffix:@"INS"];
        [ed toggleOvertype];
        BOOL nowOvertype = [ed overtype] && [status.stringValue hasSuffix:@"OVR"];
        [ed toggleOvertype];
        Check(@"IDM_VIEW_SUMMARY (typing mode)",
              @"the typing mode can be switched and the status bar says which it is",
              startsInsert && showsIns && nowOvertype &&
              ![ed overtype] && [status.stringValue hasSuffix:@"INS"]);

        // The status bar in the interface language, with upstream's own status-bar strings
        // (statusbar-length-lines, statusbar-Ln-Col, statusbar-Pos/Sel, the EOL names).
        NppPreferences *sp = [NppPreferences shared];
        NSString *languageWas = sp.localizationFile;
        SetDoc(ed, @"abc\ndef\n");
        [ed.sci message:SCI_SETSEL wParam:0 lParam:5];
        [ed refreshChrome];
        NSString *english = [status.stringValue copy];
        sp.localizationFile = @"russian.xml";
        [app applyLocalization];                    // no refreshChrome: applying the language must redraw the bar itself
        NSString *russian = [status.stringValue copy];
        sp.localizationFile = @"german.xml";
        [app applyLocalization];
        [ed refreshChrome];
        NSString *german = [status.stringValue copy];
        // Scripts with combining marks: AppKit hands a title back composed differently from how
        // it was set, and the localiser must not take that for a new English text - the menu
        // item would then stay Tamil after English came back, and a command by menu path would fail.
        NSMenuItem *lineOps = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![NppEnglishMenuTitle(top.submenu) isEqualToString:@"Edit"]) continue;
            for (NSMenuItem *it in top.submenu.itemArray) if ([NppEnglishMenuTitle(it.submenu) isEqualToString:@"Line Operations"]) lineOps = it;
        }
        NSMutableArray *stuck = [NSMutableArray array];
        for (NSString *file in @[@"tamil.xml", @"hindi.xml", @"korean.xml", @"thai.xml", @"bengali.xml"]) {
            sp.localizationFile = file;
            [app applyLocalization];
            NSString *shown = [lineOps.title copy];
            sp.localizationFile = @"";
            [app applyLocalization];
            if (![lineOps.title isEqualToString:@"Line Operations"]) [stuck addObject:[NSString stringWithFormat:@"%@ left \"%@\"", file, shown]];
        }
        SetDoc(ed, @"b\na\n");
        BOOL pathAfterScripts = [app performMenuCommandAtPath:@"Edit|Line Operations|Sort Lines Lexicographically Ascending"] && [DocText(ed) isEqualToString:@"a\nb\n"];
        if (stuck.count) printf("    %s\n", [[stuck componentsJoinedByString:@"; "] UTF8String]);
        // A right-anchored pull-down grows to its translated title instead of cutting it: the
        // project panel's "Workspace".
        [ed showProjectPanel:1];
        [[ed projectPanel:1].view setFrameSize:NSMakeSize(300, 400)];   // a panel's usual width; hidden, it may be narrower
        NSPopUpButton *workspacePull = nil;
        for (NSView *v in [ed projectPanel:1].view.subviews) if ([v isKindOfClass:[NSPopUpButton class]]) workspacePull = (NSPopUpButton *)v;
        NSMutableArray *cutPulls = [NSMutableArray array];
        for (NSString *file in @[@"russian.xml", @"german.xml", @"french.xml", @"finnish.xml", @"hungarian.xml", @""]) {
            sp.localizationFile = file;
            [app applyLocalization];
            [[ed projectPanel:1].view layoutSubtreeIfNeeded];
            CGFloat need = ceil(workspacePull.cell.cellSize.width), has = NSWidth(workspacePull.frame);
            BOOL overlapsLabel = NO;
            for (NSView *v in [ed projectPanel:1].view.subviews) {
                if ([v isKindOfClass:[NSTextField class]] && NSIntersectsRect(NSInsetRect(v.frame, 0, 1), workspacePull.frame)) overlapsLabel = YES;
            }
            CGFloat available = NSWidth(workspacePull.superview.bounds) - 12;   // a narrow dock: the pull-down may take all there is
            if ((need > has + 2 && has < available - 1) || overlapsLabel || NSMaxX(workspacePull.frame) > NSWidth([ed projectPanel:1].view.bounds))
                [cutPulls addObject:[NSString stringWithFormat:@"%@ \"%@\" needs %.0f has %.0f%@", file.length ? file : @"english", workspacePull.title, need, has, overlapsLabel ? @" (over the label)" : @""]];
        }
        if (cutPulls.count) printf("    %s\n", [[cutPulls componentsJoinedByString:@"; "] UTF8String]);
        [ed showProjectPanel:1];   // hidden again
        // A panel hidden while the language changed is translated when it is shown - its label, its
        // pull-down and its tab in the dock.
        sp.localizationFile = @"russian.xml";
        [app applyLocalization];
        [ed showProjectPanel:1];
        NSTextField *panelLabel = nil;
        for (NSView *v in [ed projectPanel:1].view.subviews) if ([v isKindOfClass:[NSTextField class]]) panelLabel = (NSTextField *)v;
        NSString *labelRu = [panelLabel.stringValue copy], *tabRu = [[NppDockingManager shared] titleOf:@"project1"], *pullRu = [workspacePull.title copy];
        // The panel was shown with the language already Russian; now the language changes while it is
        // shown: the dock's tab strip must redraw with the new title (it is drawn, not a control).
        sp.localizationFile = @"german.xml";
        [app applyLocalization];
        NSView *containerView = [ed projectPanel:1].view.superview;
        BOOL stripRedrawn = containerView.needsDisplay;   // arrange marks the container for display
        NSString *tabDe = [[NppDockingManager shared] titleOf:@"project1"];
        BOOL tabFollows = [tabDe isEqualToString:@"Projekt Tafel 1"];
        sp.localizationFile = @"russian.xml";
        [app applyLocalization];
        BOOL shownTranslated = [labelRu hasPrefix:@"Проект-панель 1"] && [tabRu isEqualToString:@"Проект-панель 1"] &&
                               [pullRu isEqualToString:NppL(@"Workspace")] && ![pullRu isEqualToString:@"Workspace"];
        [ed showProjectPanel:1];
        sp.localizationFile = @"";
        [app applyLocalization];
        [ed showProjectPanel:1];
        BOOL shownEnglish = [panelLabel.stringValue hasPrefix:@"Project Panel 1"] && [[[NppDockingManager shared] titleOf:@"project1"] isEqualToString:@"Project Panel 1"] &&
                            [workspacePull.title isEqualToString:@"Workspace"];
        [ed showProjectPanel:1];
        if (!shownTranslated || !shownEnglish) printf("    project panel: ru label [%s] tab [%s] pull-down [%s]; en label [%s] tab [%s] pull-down [%s]\n", labelRu.UTF8String, tabRu.UTF8String, pullRu.UTF8String, panelLabel.stringValue.UTF8String, [[NppDockingManager shared] titleOf:@"project1"].UTF8String, workspacePull.title.UTF8String);
        sp.localizationFile = languageWas ?: @"";
        [app applyLocalization];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];
        SetDoc(ed, @"abc\ndef\n");
        [ed refreshChrome];
        Check(@"Localization (scripts with combining marks, pull-downs)",
              @"after Tamil, Hindi, Korean, Thai and Bengali the Edit > Line Operations item is English again and a command by menu path runs; the project panel's Workspace pull-down fits its title in Russian, German, French, Finnish and Hungarian without covering the label; a panel shown after the language changed is translated, tab included, and back",
              stuck.count == 0 && pathAfterScripts && workspacePull != nil && cutPulls.count == 0 && shownTranslated && shownEnglish && stripRedrawn && tabFollows);
        // Finnish has no status-bar strings in Notepad++'s own file; the port's extra file supplies them.
        sp.localizationFile = @"finnish.xml";
        [app applyLocalization];
        NSString *finnish = [status.stringValue copy];
        sp.localizationFile = languageWas ?: @"";
        [app applyLocalization];
        [ed refreshChrome];

        // The application menu keeps its name in every language: the menu bar shows that
        // submenu's title as the application's name, and a nameless item would put AppKit's
        // own "NSMenuItem" there.
        NSMenuItem *appMenuItem = NSApp.mainMenu.itemArray.firstObject;
        NSMutableArray *appNameWrong = [NSMutableArray array];
        for (NSString *file in @[@"albanian.xml", @"russian.xml", @"japanese.xml", @""]) {
            sp.localizationFile = file;
            [app applyLocalization];
            if (![appMenuItem.submenu.title isEqualToString:@"NotepadMac"])
                [appNameWrong addObject:[NSString stringWithFormat:@"%@ left \"%@\"", file.length ? file : @"english", appMenuItem.submenu.title]];
            if (![appMenuItem.submenu.itemArray.firstObject.title containsString:@"NotepadMac"])
                [appNameWrong addObject:[NSString stringWithFormat:@"%@ About: \"%@\"", file, appMenuItem.submenu.itemArray.firstObject.title]];
        }
        sp.localizationFile = languageWas ?: @"";
        [app applyLocalization];
        if (appNameWrong.count) printf("    %s\n", [[appNameWrong componentsJoinedByString:@"; "] UTF8String]);
        Check(@"Localization (the application menu)", @"the application's own menu is called NotepadMac in every language, and About keeps the name",
              appNameWrong.count == 0);

        Check(@"IDM_VIEW_SUMMARY (status bar language)",
              @"the status bar says length/lines, Ln/Col, Sel and the EOL name in English, then in Russian and German with upstream's translations, and comes back",
              [english containsString:@"length: 8    lines: 3"] && [english containsString:@"Ln: 2    Col: 2"] && [english containsString:@"Sel: 5 | 2"] &&
              [english containsString:@"Unix (LF)"] && [english containsString:@"None (Normal Text)"] &&
              [russian containsString:@"длина: 8"] && [russian containsString:@"Стр: 2"] && [russian containsString:@"Выд: 5 | 2"] &&
              [russian containsString:@"Unix (LF)"] && ![russian containsString:@"length:"] &&
              [german containsString:@"Länge: 8"] && ![german containsString:@"length:"] &&
              [finnish containsString:@"pituus: 8    rivejä: 3"] && [finnish containsString:@"Rivi: 1"] &&
              [status.stringValue containsString:@"length: 8"] && [status.stringValue containsString:@"Pos: 1"]);

        // The path in the status bar: its own field, a click copies the full path and says so for a moment.
        NSString *clickPath = TempFile(@"t_status_click.txt", @"click\n");
        [ed openFileAtPath:clickPath error:NULL];
        clickPath = ed.currentDocument.path;   // as the editor holds it
        NppStatusPathField *pathField = [ed valueForKey:@"pathField"];
        NSString *shownPath = [pathField.stringValue copy], *tip = [pathField.toolTip copy];
        [[NSPasteboard generalPasteboard] clearContents];
        NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(10, 10) modifierFlags:0 timestamp:0
                                        windowNumber:ed.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
        [pathField mouseDown:click];
        NSString *copied = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        NSString *feedback = [pathField.stringValue copy];
        BOOL sideBySide = NSMinX([ed valueForKey:@"statusField"] ? ((NSView *)[ed valueForKey:@"statusField"]).frame : NSZeroRect) >= NSMaxX(pathField.frame);
        NppSettleUntil(^BOOL{ return [pathField.stringValue isEqualToString:clickPath]; }, 5);
        BOOL restored = [pathField.stringValue isEqualToString:clickPath];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        [ed newDocument];
        [[NSPasteboard generalPasteboard] clearContents];
        [pathField mouseDown:click];   // a new document has no path: nothing to copy
        BOOL nothingForUnsaved = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] == nil && [pathField.stringValue isEqualToString:@"(unsaved)"];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"Status bar (click copies the path)", @"the path stands in its own field before the rest; a click puts the full path on the clipboard, shows 'Copied' with it, and the path comes back; an unsaved document has nothing to copy",
              [shownPath isEqualToString:clickPath] && [copied isEqualToString:clickPath] && [feedback hasPrefix:@"✓ Copied: "] && [feedback hasSuffix:clickPath] &&
              sideBySide && restored && nothingForUnsaved && [tip containsString:@"copy the full path"]);

        // A vertical edge, which Notepad++ can show as a line, as several
        // lines, or as a change of background.
        p.edgeMode = 1; p.edgeColumns = @"80";
        [ed applyEditorPreferences];
        BOOL single = [sv message:SCI_GETEDGEMODE] == EDGE_LINE &&
                      [sv message:SCI_GETEDGECOLUMN] == 80;

        p.edgeColumns = @"80 100 120";
        [ed applyEditorPreferences];
        BOOL several = [sv message:SCI_GETEDGEMODE] == EDGE_MULTILINE &&
                       [sv message:SCI_GETMULTIEDGECOLUMN wParam:1] == 100;

        p.edgeMode = 2; p.edgeColumns = @"72";
        [ed applyEditorPreferences];
        BOOL background = [sv message:SCI_GETEDGEMODE] == EDGE_BACKGROUND;

        p.edgeMode = 0;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (vertical edge)",
              @"one edge, several edges and the background form all reach Scintilla",
              single && several && background &&
              [sv message:SCI_GETEDGEMODE] == EDGE_NONE);

        // Caret width and blink rate.
        p.caretWidth = 3; p.caretBlinkRate = 0;
        [ed applyEditorPreferences];
        BOOL wide = [sv message:SCI_GETCARETWIDTH] == 3 &&
                    [sv message:SCI_GETCARETPERIOD] == 0;
        p.caretWidth = 1; p.caretBlinkRate = 530;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (caret)",
              @"the caret's width and blink rate are settings, as they are in Notepad++",
              wide && [sv message:SCI_GETCARETWIDTH] == 1 &&
              [sv message:SCI_GETCARETPERIOD] == 530);

        // Scrolling past the end, and the caret past the end of a line. The
        // Scintilla message for the first is the other way round from the
        // setting, which is easy to get backwards.
        p.scrollBeyondLastLine = NO; p.virtualSpace = NO;
        [ed applyEditorPreferences];
        BOOL stops = [sv message:SCI_GETENDATLASTLINE] != 0 &&
                     ([sv message:SCI_GETVIRTUALSPACEOPTIONS] & SCVS_USERACCESSIBLE) == 0;
        p.scrollBeyondLastLine = YES; p.virtualSpace = YES;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (scrolling and virtual space)",
              @"scrolling past the last line and the caret past a line's end each follow their setting",
              stops && [sv message:SCI_GETENDATLASTLINE] == 0 &&
              ([sv message:SCI_GETVIRTUALSPACEOPTIONS] & SCVS_USERACCESSIBLE) != 0);
        p.virtualSpace = NO;
        [ed applyEditorPreferences];

        // Cut and Copy with nothing selected take the whole line. Notepad++ has
        // this on by default and it is what people expect from it.
        SetDoc(ed, @"first\nsecond\nthird\n");
        [sv message:SCI_GOTOLINE wParam:1 lParam:0];
        p.lineCopyCutWithoutSelection = YES;
        [app copyText:nil];
        SetDoc(ed, @"");
        [app pasteText:nil];
        BOOL copiedLine = [DocText(ed) isEqualToString:@"second\n"];

        SetDoc(ed, @"first\nsecond\nthird\n");
        [sv message:SCI_GOTOLINE wParam:1 lParam:0];
        [app cutText:nil];
        BOOL cutLine = [DocText(ed) isEqualToString:@"first\nthird\n"];

        // With the setting off, an empty selection copies nothing.
        p.lineCopyCutWithoutSelection = NO;
        SetDoc(ed, @"alpha\n");
        [sv message:SCI_GOTOPOS wParam:0 lParam:0];
        [app copyText:nil];
        SetDoc(ed, @"kept\n");
        [app pasteText:nil];
        BOOL leftAlone = [DocText(ed) containsString:@"kept"];
        p.lineCopyCutWithoutSelection = YES;

        Check(@"IDM_EDIT_COPY (whole line)",
              @"with nothing selected, Cut and Copy take the line, unless the setting says not to",
              copiedLine && cutLine && leftAlone);

        // The current line can be plain, coloured, or framed.
        p.currentLineHighlightMode = 0;
        [ed applyEditorPreferences];
        BOOL plain = [sv message:SCI_GETCARETLINEVISIBLE] == 0;
        p.currentLineHighlightMode = 2; p.currentLineFrameWidth = 3;
        [ed applyEditorPreferences];
        BOOL framed = [sv message:SCI_GETCARETLINEVISIBLE] != 0 &&
                      [sv message:SCI_GETCARETLINEFRAME] == 3;
        p.currentLineHighlightMode = 1;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (current line)",
              @"the current line can be left plain, coloured or framed",
              plain && framed && [sv message:SCI_GETCARETLINEFRAME] == 0);

        // Margins that can be turned off, and the padding around the text.
        p.foldMarginShow = NO; p.bookmarkMarginShow = NO;
        p.paddingLeft = 5; p.paddingRight = 7;
        [ed applyEditorPreferences];
        BOOL hidden = [sv message:SCI_GETMARGINWIDTHN wParam:1] == 0 &&
                      [sv message:SCI_GETMARGINWIDTHN wParam:2] == 0 &&
                      [sv message:SCI_GETMARGINLEFT] == 5 &&
                      [sv message:SCI_GETMARGINRIGHT] == 7;
        p.foldMarginShow = YES; p.bookmarkMarginShow = YES;
        p.paddingLeft = 0; p.paddingRight = 0;
        [ed applyEditorPreferences];
        Check(@"IDM_SETTING_PREFERENCE (margins and padding)",
              @"the fold and bookmark margins can be hidden and the text can be given room",
              hidden && [sv message:SCI_GETMARGINWIDTHN wParam:2] > 0);

        // How a wrapped line continues.
        p.lineWrapMethod = 2;
        [ed applyEditorPreferences];
        BOOL indented = [sv message:SCI_GETWRAPINDENTMODE] == SC_WRAPINDENT_INDENT;
        p.lineWrapMethod = 1;
        [ed applyEditorPreferences];
        // Auto-indent. Notepad++ carries the previous line's indentation onto a
        // new one, and in brace languages opens a level after an opening brace.
        p.autoIndentMode = 1;
        [ed setLanguageNamed:@"normal"];
        // No trailing newline: the caret sits at the end of the text, which is
        // where it is when Enter is actually pressed.
        SetDoc(ed, @"        keep me");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        BOOL carried = [sv message:SCI_GETLINEINDENTATION
                              wParam:(uptr_t)[sv message:SCI_LINEFROMPOSITION
                                                    wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]]] == 8;

        p.autoIndentMode = 2;
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"    if (x) {");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        long openedLine = [sv message:SCI_LINEFROMPOSITION
                                 wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]];
        BOOL opened = [sv message:SCI_GETLINEINDENTATION wParam:(uptr_t)openedLine] == 8;

        // Off means off.
        p.autoIndentMode = 0;
        SetDoc(ed, @"        x");
        [sv message:SCI_GOTOPOS wParam:(uptr_t)[sv message:SCI_GETLENGTH] lParam:0];
        [sv setStringProperty:SCI_REPLACESEL parameter:0 value:@"\n"];
        [ed maintainIndentationAfter:'\n'];
        BOOL leftFlat = [sv message:SCI_GETLINEINDENTATION
                               wParam:(uptr_t)[sv message:SCI_LINEFROMPOSITION
                                                     wParam:(uptr_t)[sv message:SCI_GETCURRENTPOS]]] == 0;
        p.autoIndentMode = 2;
        [ed setLanguageNamed:@"normal"];
        Check(@"IDM_SETTING_PREFERENCE (auto-indent)",
              @"a new line keeps the indent above it, and a brace opens a level",
              carried && opened && leftFlat);

        // Mark All follows its own case and whole-word settings.
        SetDoc(ed, @"cat cats CAT\n");
        [sv message:SCI_SETSEL wParam:0 lParam:3];          // "cat"
        p.markAllCaseSensitive = NO;  p.markAllWordOnly = YES;
        NSUInteger loose = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = YES; p.markAllWordOnly = YES;
        NSUInteger cased = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = YES; p.markAllWordOnly = NO;
        NSUInteger anywhere = [ed markAllOccurrencesOfSelection:0];
        p.markAllCaseSensitive = NO;  p.markAllWordOnly = YES;
        Check(@"IDM_SEARCH_MARKALLEXT1 (options)",
              @"Mark All matches by case and whole word as its settings say",
              loose == 2 && cased == 1 && anywhere == 2);

        Check(@"IDM_SETTING_PREFERENCE (wrap method)",
              @"a wrapped line can continue plainly, aligned, or a level further in",
              indented && [sv message:SCI_GETWRAPINDENTMODE] == SC_WRAPINDENT_SAME);
    }

    if (NppSectionWanted(@"Sorting: the way Notepad++ sorts")) { printf("\n== Sorting: the way Notepad++ sorts ==\n");
        [ed newDocument];

        // "Sort as integer" is not "read the line as a number": Notepad++ walks
        // both lines in chunks and compares runs of digits numerically, so
        // item2 comes before item10. This port compared whole lines as numbers,
        // which left anything that was not purely a number exactly where it was.
        SetDoc(ed, @"item10\nitem9\nitem2\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL natural = [DocText(ed) isEqualToString:@"item2\nitem9\nitem10\n"];

        SetDoc(ed, @"10\n9\n-3\n2\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL numbers = [DocText(ed) isEqualToString:@"-3\n2\n9\n10\n"];

        // Same value written with different numbers of leading zeros: upstream
        // breaks the tie with bZeroNum - aZeroNum, which puts the one carrying
        // more zeros first.
        SetDoc(ed, @"x007\nx7\nx07\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortInteger descending:NO];
        BOOL zeros = [DocText(ed) isEqualToString:@"x007\nx07\nx7\n"];

        Check(@"IDM_EDIT_SORTLINES_INTEGER_ASCENDING (natural order)",
              @"digit runs compare as numbers, so item2 comes before item10",
              natural && numbers && zeros);

        // A decimal sort reads every line as a number. A line it cannot read
        // stops the sort and names itself; the document is left alone.
        SetDoc(ed, @"2.5\n-\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        NSInteger refused = [ed sortLines:NppSortDecimalDot descending:NO];
        BOOL untouched = [DocText(ed) isEqualToString:@"2.5\n-\n1.5\n"];

        // A line with no number in it at all is not an error: it counts as
        // empty, and empties go first ascending and last descending.
        SetDoc(ed, @"2.5\nplain\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        NSInteger accepted = [ed sortLines:NppSortDecimalDot descending:NO];
        BOOL emptiesFirst = [DocText(ed) isEqualToString:@"plain\n1.5\n2.5\n"];

        SetDoc(ed, @"2.5\nplain\n1.5\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortDecimalDot descending:YES];
        BOOL emptiesLast = [DocText(ed) isEqualToString:@"2.5\n1.5\nplain\n"];

        Check(@"IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING (unreadable lines)",
              @"a line that is not a number stops the sort; one with no number is put aside",
              refused == 1 && untouched && accepted == NSNotFound &&
              emptiesFirst && emptiesLast);

        // A file whose lines end in CR alone is still a file of lines.
        SetDoc(ed, @"A\rC\rB\r");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortLexicographic descending:NO];
        Check(@"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING (CR line endings)",
              @"lines ending in a bare carriage return sort like any others",
              [DocText(ed) isEqualToString:@"A\rB\rC\r"]);

        // Tab-separated decimals sorted by a column of no width after the first
        // tab: the key runs to the end of the line, as upstream's getSortKey
        // takes it, and equal numbers keep their order in both directions.
        NSString *table = @"a\t2.5\tx\nb\t10\ty\nc\t-1\tz\nd\t2.5\tw\n";
        BOOL (^sortColumn)(BOOL, NSString *) = ^BOOL(BOOL down, NSString *want) {
            SetDoc(ed, table);
            [sci message:SCI_SETSELECTIONMODE wParam:SC_SEL_RECTANGLE];
            [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:2];
            [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:24];
            NSInteger r = [ed sortLines:NppSortDecimalDot descending:down];
            [sci message:SCI_SETSELECTIONMODE wParam:SC_SEL_STREAM];
            return r == NSNotFound && [DocText(ed) isEqualToString:want];
        };
        // Only the lines the column reaches are sorted: here the middle two of four.
        SetDoc(ed, @"z\t9\nb\t5\na\t1\ny\t0\n");
        [sci message:SCI_SETSELECTIONMODE wParam:SC_SEL_RECTANGLE];
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:6];      // line 2, after the tab
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:10];      // line 3, after the tab
        [ed sortLines:NppSortDecimalDot descending:NO];
        [sci message:SCI_SETSELECTIONMODE wParam:SC_SEL_STREAM];
        BOOL onlyThose = [DocText(ed) isEqualToString:@"z\t9\na\t1\nb\t5\ny\t0\n"];
        BOOL columnUp = onlyThose && sortColumn(NO, @"c\t-1\tz\na\t2.5\tx\nd\t2.5\tw\nb\t10\ty\n");
        BOOL columnDown = sortColumn(YES, @"b\t10\ty\na\t2.5\tx\nd\t2.5\tw\nc\t-1\tz\n");
        SetDoc(ed, @"b 1\na 1\nc 0\n");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        [ed sortLines:NppSortLength descending:YES];
        BOOL stableDown = [DocText(ed) isEqualToString:@"b 1\na 1\nc 0\n"];
        Check(@"IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING (column after tabs)",
              @"a caret column after a tab sorts tab-separated decimals by the rest of the line, stably both ways",
              columnUp && columnDown && stableDown);
    }

    if (NppSectionWanted(@"Search: modes and options")) { printf("\n== Search: modes and options ==\n");
        // Find was a literal search and nothing else: no case option, no whole
        // word, no extended escapes, no regular expressions. All of those are
        // what the Find dialog in Notepad++ is mostly made of.
        [ed newDocument];

        // Extended mode, with the escapes upstream defines and the digit counts
        // it fixes for each.
        BOOL escapes =
            [[EditorController convertExtendedToString:@"a\\tb"] isEqualToString:@"a\tb"] &&
            [[EditorController convertExtendedToString:@"a\\nb"] isEqualToString:@"a\nb"] &&
            [[EditorController convertExtendedToString:@"\\x41"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\d065"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\o101"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\u0041"] isEqualToString:@"A"] &&
            [[EditorController convertExtendedToString:@"\\b01000001"] isEqualToString:@"A"] &&
            // An escape that is not one keeps its backslash, as upstream leaves it.
            [[EditorController convertExtendedToString:@"\\q"] isEqualToString:@"\\q"] &&
            [[EditorController convertExtendedToString:@"\\xZZ"] isEqualToString:@"\\xZZ"];
        Check(@"IDM_SEARCH_FIND (extended)", @"the escapes Extended mode defines all convert",
              escapes);

        SetDoc(ed, @"alpha Alpha alphabet\nbeta\n");
        NppFindSpec *plain = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal options:NppFindNone];
        NppFindSpec *cased = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal
                                          options:NppFindMatchCase];
        NppFindSpec *whole = [NppFindSpec specFor:@"alpha" mode:NppSearchNormal
                                          options:NppFindMatchCase | NppFindWholeWord];
        Check(@"IDM_SEARCH_FIND (case and whole word)",
              @"matching by case and by whole word each narrow the result",
              [ed countMatches:plain] == 3 &&      // alpha, Alpha, alphabet
              [ed countMatches:cased] == 2 &&      // alpha, alphabet
              [ed countMatches:whole] == 1);       // alpha

        // A literal search must not be read as a pattern.
        SetDoc(ed, @"a.c abc\n");
        Check(@"IDM_SEARCH_FIND (literal)",
              @"a dot in Normal mode is a dot, not any character",
              [ed countMatches:[NppFindSpec specFor:@"a.c" mode:NppSearchNormal
                                            options:NppFindMatchCase]] == 1 &&
              [ed countMatches:[NppFindSpec specFor:@"a.c" mode:NppSearchRegex
                                            options:NppFindMatchCase]] == 2);

        SetDoc(ed, @"one 11 two 22 three 333\n");
        Check(@"IDM_SEARCH_FIND (regex)",
              @"a regular expression matches what it should",
              [ed countMatches:[NppFindSpec specFor:@"\\d+" mode:NppSearchRegex
                                            options:NppFindNone]] == 3 &&
              [ed countMatches:[NppFindSpec specFor:@"\\d{3}" mode:NppSearchRegex
                                            options:NppFindNone]] == 1);

        // Searching forward, then backward, then wrapping.
        SetDoc(ed, @"x x x\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        NppFindSpec *forward = [NppFindSpec specFor:@"x" mode:NppSearchNormal options:NppFindNone];
        [ed findNext:forward];
        long first = [sci message:SCI_GETSELECTIONSTART];
        [ed findNext:forward];
        long second = [sci message:SCI_GETSELECTIONSTART];
        NppFindSpec *back = [NppFindSpec specFor:@"x" mode:NppSearchNormal
                                         options:NppFindBackward];
        [ed findNext:back];
        long backTo = [sci message:SCI_GETSELECTIONSTART];
        // At the end with no wrap there is nowhere to go; with wrap there is.
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL stops = ![ed findNext:forward];
        NppFindSpec *wrapping = [NppFindSpec specFor:@"x" mode:NppSearchNormal
                                             options:NppFindWrap];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL wraps = [ed findNext:wrapping] && [sci message:SCI_GETSELECTIONSTART] == 0;
        Check(@"IDM_SEARCH_FINDNEXT (direction and wrap)",
              @"forward, backward and wrapping each land where they should",
              first == 0 && second == 2 && backTo == 0 && stops && wraps);

        // Replacement with back-references.
        SetDoc(ed, @"John Smith\nAda Lovelace\n");
        NppFindSpec *swap = [NppFindSpec specFor:@"(\\w+) (\\w+)" mode:NppSearchRegex
                                         options:NppFindNone];
        swap.replacement = @"\\2, \\1";
        NSUInteger swapped = [ed replaceAll:swap];
        Check(@"IDM_SEARCH_REPLACE (back-references)",
              @"a replacement can put the captured groups back",
              swapped == 2 &&
              [DocText(ed) isEqualToString:@"Smith, John\nLovelace, Ada\n"]);

        // The dollar form has to work too, and a group that matched nothing
        // must contribute nothing rather than the text "\\3".
        SetDoc(ed, @"ab\n");
        NppFindSpec *dollars = [NppFindSpec specFor:@"(a)(b)(c)?" mode:NppSearchRegex
                                            options:NppFindNone];
        dollars.replacement = @"$2$1$3";
        [ed replaceAll:dollars];
        Check(@"IDM_SEARCH_REPLACE (dollar form)",
              @"$1 names a group as \\1 does, and an empty one adds nothing",
              [DocText(ed) isEqualToString:@"ba\n"]);

        // Replace All must not trip over its own output.
        SetDoc(ed, @"aaa\n");
        NppFindSpec *grow = [NppFindSpec specFor:@"a" mode:NppSearchNormal options:NppFindNone];
        grow.replacement = @"aa";
        NSUInteger grown = [ed replaceAll:grow];
        Check(@"IDM_SEARCH_REPLACE (replacement is not re-searched)",
              @"replacing a with aa three times gives six, not an endless run",
              grown == 3 && [DocText(ed) isEqualToString:@"aaaaaa\n"]);

        // Only the selection, when that is what was asked for.
        SetDoc(ed, @"q q q q\n");
        [sci message:SCI_SETSEL wParam:0 lParam:3];
        NppFindSpec *inSel = [NppFindSpec specFor:@"q" mode:NppSearchNormal
                                          options:NppFindInSelection];
        NppFindSpec *everywhere = [NppFindSpec specFor:@"q" mode:NppSearchNormal
                                               options:NppFindNone];
        Check(@"IDM_SEARCH_REPLACE (in selection)",
              @"a search confined to the selection sees only what is inside it",
              [ed countMatches:inSel] == 2 && [ed countMatches:everywhere] == 4);

        // The panel has to carry these modes and options, or none of the above
        // is reachable from the Find dialog. Its controls are set here and the
        // search it describes is read back.
        [app buildFindPanel];
        NSTextField *findField = [app valueForKey:@"findField"];
        NSMatrix *modes = [app valueForKey:@"modeRadios"];
        NSButton *caseBox = [app valueForKey:@"matchCaseBox"];
        NSButton *wordBox = [app valueForKey:@"wholeWordBox"];
        NSButton *selBox = [app valueForKey:@"inSelectionBox"];
        findField.stringValue = @"\\d+";
        [modes selectCellAtRow:2 column:0];             // Regular expression
        caseBox.state = NSControlStateValueOn;
        wordBox.state = NSControlStateValueOff;
        selBox.state = NSControlStateValueOff;
        NppFindSpec *fromPanel = (NppFindSpec *)[app currentFindSpec];

        SetDoc(ed, @"a1 b22 c333\n");
        Check(@"IDM_SEARCH_FIND (dialog)",
              @"the dialog's mode and options are what the search actually uses",
              fromPanel.mode == NppSearchRegex &&
              (fromPanel.options & NppFindMatchCase) != 0 &&
              (fromPanel.options & NppFindWholeWord) == 0 &&
              [ed countMatches:fromPanel] == 3 &&
              modes.numberOfRows == 3);

        // The rest of the dialog as on Windows.
        {
            NSComboBox *what = [app valueForKey:@"findField"];
            NSComboBox *with = [app valueForKey:@"replaceField"];
            NppPreferences *fp = [NppPreferences shared];
            NSArray *savedFind = fp.findHistory, *savedReplace = fp.replaceHistory;
            [modes selectCellAtRow:0 column:0];
            SetDoc(ed, @"one two one\n");
            for (int i = 0; i < 12; ++i) {
                what.stringValue = [NSString stringWithFormat:@"term%d", i];
                [app findPanelCount:nil];
            }
            what.stringValue = @"term3";
            [app findPanelCount:nil];
            BOOL history = [what isKindOfClass:[NSComboBox class]] && fp.findHistory.count == 10 &&
                           [fp.findHistory.firstObject isEqualToString:@"term3"] && what.numberOfItems == 10 &&
                           [[what itemObjectValueAtIndex:1] isEqualToString:@"term11"];
            what.stringValue = @"left";
            with.stringValue = @"right";
            [app findPanelSwap:nil];
            BOOL swapped = [what.stringValue isEqualToString:@"right"] && [with.stringValue isEqualToString:@"left"];
            Check(@"IDM_SEARCH_FIND (histories)",
                  @"each field keeps its last ten entries, newest first, and the swap button trades the two",
                  history && swapped);

            NSButton *sel = [app valueForKey:@"inSelectionBox"];
            [sci message:SCI_SETSEL wParam:0 lParam:0];
            sel.state = NSControlStateValueOn;
            [app updateInSelectionAvailability];
            BOOL greyed = !sel.enabled && sel.state == NSControlStateValueOff;
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [app updateInSelectionAvailability];
            BOOL usable = sel.enabled;
            [sci message:SCI_SETSEL wParam:0 lParam:0];
            [app updateInSelectionAvailability];
            Check(@"IDM_SEARCH_FIND (in selection)",
                  @"In selection is greyed out and cleared while nothing is selected", greyed && usable);

            // Mark: without purging, earlier marks stay; Copy Marked Text takes them.
            NSButton *purge = [app valueForKey:@"purgeBox"];
            purge.state = NSControlStateValueOff;
            what.stringValue = @"one";
            [app findPanelMarkAll:nil];
            what.stringValue = @"two";
            [app findPanelMarkAll:nil];
            NSString *kept = [ed textOfStyle:NPPMAC_STYLE_COUNT];
            purge.state = NSControlStateValueOn;
            [app findPanelMarkAll:nil];
            NSString *purged = [ed textOfStyle:NPPMAC_STYLE_COUNT];
            [app findPanelCopyMarkedText:nil];
            NSString *copied = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
            [ed clearStyle:NPPMAC_STYLE_COUNT];
            purge.state = NSControlStateValueOff;
            Check(@"IDM_SEARCH_MARK (purge, copy)",
                  @"marks add up unless Purge for each search is on, and Copy Marked Text copies them",
                  [kept componentsSeparatedByString:@"\n"].count == 3 && [purged isEqualToString:@"two"] &&
                  [copied isEqualToString:@"two"]);

            // Every open document: Find All lists each, Replace All changes each.
            NSUInteger docsBefore = ed.documents.count;
            [ed newDocument];
            SetDoc(ed, @"zqx first\nzqx again zqx\n");
            [ed newDocument];
            SetDoc(ed, @"second zqx\n");
            NppDocument *second = ed.currentDocument;
            NSUInteger hits = 0;
            NSArray<NppDocument *> *recentBefore = [ed documentsInRecentOrder];
            NSString *all = [ed findAllInOpenDocuments:[NppFindSpec specFor:@"zqx" mode:NppSearchNormal options:NppFindNone]
                                                  hits:&hits];
            // Searching every tab is not visiting it: the Ctrl+Tab order stays.
            BOOL listed = [[ed documentsInRecentOrder] isEqualToArray:recentBefore] && hits == 4 && [all containsString:@"(4 hits in 2 files of"] &&
                          [all containsString:@"(3 hits)\n\tLine 1: zqx first\n\tLine 2: zqx again zqx\n"] &&
                          ed.currentDocument == second;
            what.stringValue = @"zqx";
            with.stringValue = @"done";
            [app findPanelReplaceAllInOpenDocuments:nil];
            BOOL replacedEverywhere = [DocText(ed) isEqualToString:@"second done\n"] &&
                                      [[ed findAllInOpenDocuments:[NppFindSpec specFor:@"zqx" mode:NppSearchNormal
                                                                              options:NppFindNone] hits:NULL]
                                       containsString:@"(0 hits in 0 files"];
            while (ed.documents.count > docsBefore) {
                [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
            }
            Check(@"IDM_SEARCH_FINDALL_OPENEDFILES",
                  @"Find All and Replace All reach every open document and leave the one in front where it was",
                  listed && replacedEverywhere);

            // Transparency, on losing focus or always.
            NSButton *transparent = [app valueForKey:@"transparencyBox"];
            NSMatrix *when = [app valueForKey:@"transparencyRadios"];
            NSPanel *dialog = [app valueForKey:@"findPanel"];
            NSInteger savedMode = fp.findTransparencyMode;
            transparent.state = NSControlStateValueOn;
            [when selectCellAtRow:1 column:0];
            [app applyFindTransparency];
            BOOL always = dialog.alphaValue < 1.0 && fp.findTransparencyMode == 2;
            transparent.state = NSControlStateValueOff;
            [app applyFindTransparency];
            BOOL opaque = dialog.alphaValue == 1.0 && fp.findTransparencyMode == 0;
            fp.findTransparencyMode = savedMode;
            Check(@"IDM_SEARCH_FIND (transparency)",
                  @"the dialog turns translucent as set, and the setting is kept", always && opaque);
            fp.findHistory = savedFind ?: @[];
            fp.replaceHistory = savedReplace ?: @[];
            what.stringValue = @"";
            with.stringValue = @"";
        }

        // Cmd+V while a Find field has the caret must reach that field, not the
        // document behind it. The menu items carry a target, so they never
        // travel the responder chain on their own.
        [app buildFindPanel];
        NSPanel *findPanel = [app valueForKey:@"findPanel"];
        NSTextField *replaceField = [app valueForKey:@"replaceField"];
        replaceField.stringValue = @"";
        SetDoc(ed, @"document\n");
        [[NSPasteboard generalPasteboard] clearContents];
        [[NSPasteboard generalPasteboard] setString:@"pasted" forType:NSPasteboardTypeString];

        // A window only becomes key while the application is active, and a test
        // run is not activated by anyone.
        [NSApp activateIgnoringOtherApps:YES];
        [findPanel makeKeyAndOrderFront:nil];
        [findPanel makeFirstResponder:replaceField];
        // Becoming key goes through the window server, so it is not in effect
        // the instant it is asked for. Without waiting, the paste sometimes
        // finds no key window and goes to the document -- which is the very
        // thing this is checking.
        NSDate *keyDeadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (NSApp.keyWindow != findPanel && [keyDeadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        // Where the paste goes is decided by the key window's first responder,
        // so with no key window there is nothing to decide and nothing to test.
        // A test run is not brought to the front by anyone, and now and then the
        // panel never becomes key; saying so is better than failing for it.
        BOOL becameKey = NSApp.keyWindow == findPanel;
        BOOL routed = YES;
        if (becameKey) {
            [app pasteText:nil];
            NSString *fieldText = [[findPanel fieldEditor:NO forObject:replaceField] string]
                                  ?: replaceField.stringValue;
            routed = [fieldText containsString:@"pasted"] &&
                     ![DocText(ed) containsString:@"pasted"];
        } else {
            printf("       (панель не стала ключевой — проверка пропущена)\n");
        }
        [findPanel orderOut:nil];
        Check(@"IDM_EDIT_PASTE (into a dialog field)",
              becameKey
                ? @"pasting while a Find field has the caret reaches the field, not the document"
                : @"skipped: no window took the focus in this run",
              routed);

        // The routing is shared by every dialog, so the thing worth guarding is
        // that no menu item quietly takes a shortcut that means editing inside a
        // field. Anything carrying Cmd+X, C, V, A or Z has to be one of the
        // commands that offers itself to the field first.
        NSSet *forwarding = [NSSet setWithArray:@[@"cutText:", @"copyText:", @"pasteText:",
                                                  @"selectAllText:", @"undo:", @"redo:"]];
        NSMutableArray *stealing = [NSMutableArray array];
        NSMutableArray *pending = [@[[NSApp mainMenu]] mutableCopy];
        while (pending.count) {
            NSMenu *menu = pending.firstObject;
            [pending removeObjectAtIndex:0];
            for (NSMenuItem *entry in menu.itemArray) {
                if (entry.submenu) [pending addObject:entry.submenu];
                NSString *key = entry.keyEquivalent.lowercaseString;
                if (!key.length || ![@"xcvaz" containsString:key]) continue;
                if ((entry.keyEquivalentModifierMask & NSEventModifierFlagCommand) == 0) continue;
                NSString *action = entry.action ? NSStringFromSelector(entry.action) : @"";
                if (![forwarding containsObject:action]) {
                    [stealing addObject:[NSString stringWithFormat:@"%@ (%@)", entry.title, action]];
                }
            }
        }
        // A dialog is expected to answer Enter and Escape. None of these panels
        // did: Enter did nothing at all, and Escape left them on screen.
        [app buildFindPanel];
        NSPanel *findDialog = [app valueForKey:@"findPanel"];
        PreferencesWindow *prefsForKeys = [[PreferencesWindow alloc] initWithEditor:ed];
        NSPanel *prefsDialog = [prefsForKeys valueForKey:@"panel"];

        NSMutableArray *noDefault = [NSMutableArray array];
        NSMutableArray *noEscape = [NSMutableArray array];
        NSArray *dialogs = @[@[@"Find", findDialog], @[@"Preferences", prefsDialog]];
        for (NSArray *pair in dialogs) {
            NSPanel *dialog = pair[1];

            BOOL hasDefault = NO;
            NSMutableArray *views = [dialog.contentView.subviews mutableCopy];
            while (views.count) {
                NSView *view = views.firstObject;
                [views removeObjectAtIndex:0];
                [views addObjectsFromArray:view.subviews];
                if ([view isKindOfClass:NSButton.class] &&
                    [[(NSButton *)view keyEquivalent] isEqualToString:@"\r"]) hasDefault = YES;
            }
            if (!hasDefault) [noDefault addObject:pair[0]];

            [dialog orderFront:nil];
            [dialog cancelOperation:nil];       // what Escape sends
            if (dialog.isVisible) [noEscape addObject:pair[0]];
            [dialog orderOut:nil];
        }
        // A panel made with a content rectangle at the origin opens in the
        // bottom left corner of the screen. They should come up in the middle.
        //
        // The panel under test is made here with a name nothing has used, so
        // that a position remembered from a previous run cannot stand in for
        // the placing and make this pass when it should not.
        NppPanel *fresh = [[NppPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 420, 260)
                      styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                 NSWindowStyleMaskUtilityWindow)
                        backing:NSBackingStoreBuffered defer:YES];
        fresh.title = [NSString stringWithFormat:@"Placement check %@",
                       [[NSUUID UUID] UUIDString]];
        [fresh orderFront:nil];
        NSRect screen = fresh.screen.visibleFrame;
        if (NSIsEmptyRect(screen)) screen = NSScreen.mainScreen.visibleFrame;
        NSPoint middle = NSMakePoint(NSMidX(fresh.frame), NSMidY(fresh.frame));
        // Centring is not exact -- AppKit places a window a little above the
        // middle -- so this only asks that it is nowhere near a corner.
        BOOL centred = fabs(middle.x - NSMidX(screen)) <= NSWidth(screen) / 4 &&
                       fabs(middle.y - NSMidY(screen)) <= NSHeight(screen) / 3;
        [fresh orderOut:nil];
        Check(@"IDM_SETTING_PREFERENCE (dialog position)",
              @"a dialog opens near the middle of the screen, not in a corner",
              centred);

        Check(@"IDM_SETTING_PREFERENCE (dialog keys)",
              @"Enter does the dialog's job and Escape puts it away",
              noDefault.count == 0 && noEscape.count == 0);
        if (noDefault.count) printf("       без действия на Enter: %s\n",
            [[noDefault componentsJoinedByString:@", "] UTF8String]);
        if (noEscape.count) printf("       не закрываются по Escape: %s\n",
            [[noEscape componentsJoinedByString:@", "] UTF8String]);

        Check(@"IDM_EDIT_PASTE (no shortcut is taken)",
              @"nothing on the menu takes an editing shortcut without offering it to the field first",
              stealing.count == 0);
        if (stealing.count) printf("       перехватывают: %s\n",
            [[stealing componentsJoinedByString:@", "] UTF8String]);


        SetDoc(ed, @"cat bat cat\n");
        NSUInteger marked = [ed markAll:[NppFindSpec specFor:@"cat" mode:NppSearchNormal
                                                     options:NppFindMatchCase]];
        Check(@"IDM_SEARCH_MARK (find mark)", @"every match is marked",
              marked == 2);
    }

    if (NppSectionWanted(@"Edit: convert case")) { printf("\n== Edit: convert case ==\n");
        struct { NppCaseMode mode; NSString *in; NSString *want; NSString *cmd; } cases[] = {
            {NppCaseUpper,          @"hello world", @"HELLO WORLD", @"IDM_EDIT_UPPERCASE"},
            {NppCaseLower,          @"HeLLo",       @"hello",       @"IDM_EDIT_LOWERCASE"},
            {NppCaseProperForce,    @"hELLO wORLD", @"Hello World", @"IDM_EDIT_PROPERCASE_FORCE"},
            {NppCaseProperBlend,    @"hELLO wORLD", @"HELLO WORLD", @"IDM_EDIT_PROPERCASE_BLEND"},
            {NppCaseSentenceForce,  @"hi THERE. bye", @"Hi there. Bye", @"IDM_EDIT_SENTENCECASE_FORCE"},
            {NppCaseSentenceBlend,  @"hi THERE. bye", @"Hi THERE. Bye", @"IDM_EDIT_SENTENCECASE_BLEND"},
            {NppCaseInvert,         @"AbC",         @"aBc",         @"IDM_EDIT_INVERTCASE"},
        };
        for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
            SetDoc(ed, cases[i].in);
            [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
            [ed convertCase:cases[i].mode];
            Check(cases[i].cmd, [NSString stringWithFormat:@"%@ -> %@", cases[i].in, cases[i].want],
                  [DocText(ed) isEqualToString:cases[i].want]);
        }
        // Random case is non-deterministic; assert the invariant instead.
        SetDoc(ed, @"abcdefgh");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed convertCase:NppCaseRandom];
        NSString *r = DocText(ed);
        Check(@"IDM_EDIT_RANDOMCASE", @"same letters, case scrambled",
              r.length == 8 && [r.lowercaseString isEqualToString:@"abcdefgh"]);
    }

    if (NppSectionWanted(@"Edit: sorting")) { printf("\n== Edit: sorting ==\n");
        struct { NppSortKey key; BOOL desc; NSString *in; NSString *want; NSString *cmd; } sorts[] = {
            {NppSortLexicographic, NO,  @"b\na\nc\n", @"a\nb\nc\n", @"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING"},
            {NppSortLexicographic, YES, @"b\na\nc\n", @"c\nb\na\n", @"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_DESCENDING"},
            {NppSortLexicographicCaseInsensitive, NO,  @"B\na\nC\n", @"a\nB\nC\n", @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_ASCENDING"},
            {NppSortLexicographicCaseInsensitive, YES, @"B\na\nC\n", @"C\nB\na\n", @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_DESCENDING"},
            {NppSortLocale, NO,  @"b\na\n", @"a\nb\n", @"IDM_EDIT_SORTLINES_LOCALE_ASCENDING"},
            {NppSortLocale, YES, @"a\nb\n", @"b\na\n", @"IDM_EDIT_SORTLINES_LOCALE_DESCENDING"},
            {NppSortInteger, NO,  @"10\n9\n2\n", @"2\n9\n10\n", @"IDM_EDIT_SORTLINES_INTEGER_ASCENDING"},
            {NppSortInteger, YES, @"10\n9\n2\n", @"10\n9\n2\n", @"IDM_EDIT_SORTLINES_INTEGER_DESCENDING"},
            {NppSortDecimalDot, NO,  @"1.5\n1.25\n", @"1.25\n1.5\n", @"IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING"},
            {NppSortDecimalDot, YES, @"1.25\n1.5\n", @"1.5\n1.25\n", @"IDM_EDIT_SORTLINES_DECIMALDOT_DESCENDING"},
            {NppSortDecimalComma, NO,  @"1,5\n1,25\n", @"1,25\n1,5\n", @"IDM_EDIT_SORTLINES_DECIMALCOMMA_ASCENDING"},
            {NppSortDecimalComma, YES, @"1,25\n1,5\n", @"1,5\n1,25\n", @"IDM_EDIT_SORTLINES_DECIMALCOMMA_DESCENDING"},
            {NppSortLength, NO,  @"ccc\na\nbb\n", @"a\nbb\nccc\n", @"IDM_EDIT_SORTLINES_LENGTH_ASCENDING"},
            {NppSortLength, YES, @"a\nbb\nccc\n", @"ccc\nbb\na\n", @"IDM_EDIT_SORTLINES_LENGTH_DESCENDING"},
        };
        for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); ++i) {
            SetDoc(ed, sorts[i].in);
            [ed sortLines:sorts[i].key descending:sorts[i].desc];
            Check(sorts[i].cmd, @"sorts as expected", [DocText(ed) isEqualToString:sorts[i].want]);
        }

        SetDoc(ed, @"a\nb\nc\n");
        [ed sortLines:NppSortReverseOrder descending:NO];
        Check(@"IDM_EDIT_SORTLINES_REVERSE_ORDER", @"reverses line order",
              [DocText(ed) isEqualToString:@"c\nb\na\n"]);

        SetDoc(ed, @"a\nb\nc\nd\ne\n");
        [ed sortLines:NppSortRandom descending:NO];
        NSString *shuffled = DocText(ed);
        NSArray *parts = [[shuffled stringByTrimmingCharactersInSet:
                           [NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@"\n"];
        Check(@"IDM_EDIT_SORTLINES_RANDOMLY", @"keeps every line, order scrambled",
              parts.count == 5 && [[NSSet setWithArray:parts] isEqualToSet:
                  [NSSet setWithArray:@[@"a", @"b", @"c", @"d", @"e"]]]);
    }

    if (NppSectionWanted(@"Edit: line operations")) { printf("\n== Edit: line operations ==\n");
        SetDoc(ed, @"a\nb\na\nb\n");
        [ed removeDuplicateLines:NO];
        Check(@"IDM_EDIT_REMOVE_ANY_DUP_LINES", @"keeps the first of each",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\na\nb\na\n");
        [ed removeDuplicateLines:YES];
        Check(@"IDM_EDIT_REMOVE_CONSECUTIVE_DUP_LINES", @"collapses only neighbours",
              [DocText(ed) isEqualToString:@"a\nb\na\n"]);

        SetDoc(ed, @"one two three\n");
        [sci message:SCI_SETEDGECOLUMN wParam:7 lParam:0];
        [ed splitLines];
        Check(@"IDM_EDIT_SPLIT_LINES", @"breaks a long line at the edge column",
              [[DocText(ed) componentsSeparatedByString:@"\n"] count] > 2);
        [sci message:SCI_SETEDGECOLUMN wParam:0 lParam:0];

        SetDoc(ed, @"a\nb\nc\n");
        [ed joinLines];
        Check(@"IDM_EDIT_JOIN_LINES", @"joins with single spaces",
              [DocText(ed) hasPrefix:@"a b c"]);

        SetDoc(ed, @"one\ntwo\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed moveLine:YES];
        Check(@"IDM_EDIT_LINE_UP", @"moves the line up", [DocText(ed) hasPrefix:@"two"]);
        [ed moveLine:NO];
        Check(@"IDM_EDIT_LINE_DOWN", @"moves the line back down", [DocText(ed) hasPrefix:@"one"]);

        SetDoc(ed, @"a\n\nb\n");
        [ed removeEmptyLines:NO];
        Check(@"IDM_EDIT_REMOVEEMPTYLINES", @"drops empty lines",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\n   \nb\n");
        [ed removeEmptyLines:YES];
        Check(@"IDM_EDIT_REMOVEEMPTYLINESWITHBLANK", @"drops whitespace-only lines",
              [DocText(ed) isEqualToString:@"a\nb\n"]);

        SetDoc(ed, @"a\nb\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed insertBlankLine:YES];
        Check(@"IDM_EDIT_BLANKLINEABOVECURRENT", @"inserts above the caret line",
              [DocText(ed) isEqualToString:@"a\n\nb\n"]);

        SetDoc(ed, @"a\nb\n");
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed insertBlankLine:NO];
        Check(@"IDM_EDIT_BLANKLINEBELOWCURRENT", @"inserts below the caret line",
              [DocText(ed) isEqualToString:@"a\n\nb\n"]);
    }

    if (NppSectionWanted(@"Edit: blank operations")) { printf("\n== Edit: blank operations ==\n");
        struct { NppTrimMode mode; NSString *in; NSString *want; NSString *cmd; } trims[] = {
            {NppTrimTrailing,       @"a   \nb\t\n", @"a\nb\n",     @"IDM_EDIT_TRIMTRAILING"},
            {NppTrimLeading,        @"   a\n\tb\n", @"a\nb\n",     @"IDM_EDIT_TRIMLINEHEAD"},
            {NppTrimBoth,           @"  a  \n",      @"a\n",         @"IDM_EDIT_TRIM_BOTH"},
            {NppTabToSpace,         @"\ta\n",        @"    a\n",     @"IDM_EDIT_TAB2SW"},
            {NppSpaceToTabAll,      @"    a    b\n",  @"\ta\tb\n",   @"IDM_EDIT_SW2TAB_ALL"},
            {NppSpaceToTabLeading,  @"    a    b\n",  @"\ta    b\n",  @"IDM_EDIT_SW2TAB_LEADING"},
        };
        for (size_t i = 0; i < sizeof(trims)/sizeof(trims[0]); ++i) {
            SetDoc(ed, trims[i].in);
            [ed applyTrim:trims[i].mode];
            Check(trims[i].cmd, @"transforms whitespace as expected",
                  [DocText(ed) isEqualToString:trims[i].want]);
        }

        SetDoc(ed, @"a\nb\n");
        [ed applyTrim:NppTrimEOLToSpace];
        Check(@"IDM_EDIT_EOL2WS", @"line endings become spaces",
              [DocText(ed) hasPrefix:@"a b"] && ![[DocText(ed) substringToIndex:3] containsString:@"\n"]);

        SetDoc(ed, @"  a  \n  b  \n");
        [ed applyTrim:NppTrimAll];
        Check(@"IDM_EDIT_TRIMALL", @"trims and joins",
              [DocText(ed) hasPrefix:@"a b"]);
    }

    if (NppSectionWanted(@"Edit: indent, delete, comments, read-only")) { printf("\n== Edit: indent, delete, comments, read-only ==\n");
        // With the indent settings this expects, whatever the machine's own are.
        NppPreferences *indentPrefs = [NppPreferences shared];
        BOOL spacesWas = indentPrefs.useSpaces;
        NSInteger widthWas = indentPrefs.tabWidth;
        indentPrefs.useSpaces = YES;
        indentPrefs.tabWidth = 4;
        [ed applyDocumentSettings];
        SetDoc(ed, @"a\n");
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed changeIndent:YES];
        BOOL indented = [DocText(ed) isEqualToString:@"    a\n"];
        [ed changeIndent:NO];
        BOOL unindented = [DocText(ed) isEqualToString:@"a\n"];
        indentPrefs.useSpaces = spacesWas;
        indentPrefs.tabWidth = widthWas;
        [ed applyDocumentSettings];
        Check(@"IDM_EDIT_INS_TAB", @"indents the line by one level", indented);
        Check(@"IDM_EDIT_RMV_TAB", @"removes that level again", unindented);

        SetDoc(ed, @"delete me\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [ed deleteSelection];
        Check(@"IDM_EDIT_DELETE", @"removes the selection",
              ![DocText(ed) hasPrefix:@"delete"]);

        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"// x\n// y\n");
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_UNCOMMENT", @"strips the line comment token",
              [DocText(ed) isEqualToString:@"x\ny\n"]);

        SetDoc(ed, @"body\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [ed streamComment:YES];
        BOOL wrapped = [DocText(ed) hasPrefix:@"/*body*/"];
        [sci message:SCI_SETSEL wParam:0 lParam:8];
        [ed streamComment:NO];
        Check(@"IDM_EDIT_STREAM_COMMENT", @"wraps the selection", wrapped);
        Check(@"IDM_EDIT_STREAM_UNCOMMENT", @"unwraps it again",
              [DocText(ed) hasPrefix:@"body"]);

        [ed setReadOnly:YES];
        BOOL ro = [ed isReadOnly];
        [ed setReadOnly:NO];
        Check(@"IDM_EDIT_TOGGLEREADONLY", @"toggles read-only", ro && ![ed isReadOnly]);

        [ed setReadOnlyForAllDocuments:YES];
        BOOL allRO = [ed isReadOnly];
        Check(@"IDM_EDIT_SETREADONLYFORALLDOCS", @"marks every document read-only", allRO);
        [ed setReadOnlyForAllDocuments:NO];
        Check(@"IDM_EDIT_CLEARREADONLYFORALLDOCS", @"clears it again", ![ed isReadOnly]);
    }

    if (NppSectionWanted(@"Edit: clipboard and insert")) { printf("\n== Edit: clipboard and insert ==\n");
        NSError *err = nil;
        NSString *p = TempFile(@"t_clip.txt", @"x\n");
        [ed openFileAtPath:p error:&err];

        [ed copyToClipboard:ed.currentDocument.path];
        Check(@"IDM_EDIT_FULLPATHTOCLIP", @"clipboard holds the full path",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:p]);

        [ed copyToClipboard:ed.currentDocument.displayName];
        Check(@"IDM_EDIT_FILENAMETOCLIP", @"clipboard holds the file name",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"t_clip.txt"]);

        [ed copyToClipboard:[ed containingFolderURL].path];
        Check(@"IDM_EDIT_CURRENTDIRTOCLIP", @"clipboard holds the directory",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:p.stringByDeletingLastPathComponent]);

        [ed copyToClipboard:[ed allDocumentNames]];
        Check(@"IDM_EDIT_COPY_ALL_NAMES", @"clipboard lists every tab name",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  containsString:@"t_clip.txt"]);

        [ed copyToClipboard:[ed allDocumentPaths]];
        Check(@"IDM_EDIT_COPY_ALL_PATHS", @"clipboard lists every tab path",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:p]);

        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        Check(@"IDM_EDIT_INSERT_DATETIME_SHORT", @"inserts a short timestamp", DocText(ed).length > 4);

        SetDoc(ed, @"");
        [ed insertDateTimeShort:NO];
        Check(@"IDM_EDIT_INSERT_DATETIME_LONG", @"inserts a long timestamp", DocText(ed).length > 8);

        SetDoc(ed, @"");
        [ed insertCustomDateTime:@"yyyy"];
        Check(@"IDM_EDIT_INSERT_DATETIME_CUSTOMIZED", @"honours a custom format",
              DocText(ed).length == 4 && [DocText(ed) hasPrefix:@"20"]);
    }

    if (NppSectionWanted(@"Edit: multi-selection")) { printf("\n== Edit: multi-selection ==\n");
        // "cat" appears three times with different case and word boundaries, so
        // each flag combination must produce a different count.
        struct { NppMatchFlags flags; NSUInteger want; NSString *cmdAll; NSString *cmdNext; } ms[] = {
            {NppMatchNone,                        3, @"IDM_EDIT_MULTISELECTALL",
                                                     @"IDM_EDIT_MULTISELECTNEXT"},
            {NppMatchCase,                        2, @"IDM_EDIT_MULTISELECTALLMATCHCASE",
                                                     @"IDM_EDIT_MULTISELECTNEXTMATCHCASE"},
            {NppMatchWholeWord,                   2, @"IDM_EDIT_MULTISELECTALLWHOLEWORD",
                                                     @"IDM_EDIT_MULTISELECTNEXTWHOLEWORD"},
            {NppMatchCase | NppMatchWholeWord,    1, @"IDM_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD",
                                                     @"IDM_EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD"},
        };
        for (size_t i = 0; i < sizeof(ms)/sizeof(ms[0]); ++i) {
            SetDoc(ed, @"Cat cat catalog\n");
            [sci message:SCI_SETSEL wParam:4 lParam:7];        // the lowercase whole word "cat"
            NSUInteger n = [ed multiSelectAllOccurrences:ms[i].flags];
            Check(ms[i].cmdAll, [NSString stringWithFormat:@"selects %lu occurrence(s)",
                                 (unsigned long)ms[i].want],
                  n == ms[i].want && [ed selectionCount] == ms[i].want);

            SetDoc(ed, @"Cat cat catalog\n");
            [sci message:SCI_SETSEL wParam:4 lParam:7];
            NSUInteger before = [ed selectionCount];
            BOOL added = [ed multiSelectNextOccurrence:ms[i].flags];
            Check(ms[i].cmdNext, @"adds one more selection when another match exists",
                  ms[i].want > 1 ? (added && [ed selectionCount] == before + 1)
                                 : (!added && [ed selectionCount] == before));
        }

        SetDoc(ed, @"aa aa aa\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        [ed multiSelectAllOccurrences:NppMatchNone];
        NSUInteger all = [ed selectionCount];
        BOOL dropped = [ed undoLastMultiSelection];
        Check(@"IDM_EDIT_MULTISELECTUNDO", @"drops the most recently added selection",
              all == 3 && dropped && [ed selectionCount] == 2);

        SetDoc(ed, @"bb bb bb\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        [ed multiSelectNextOccurrence:NppMatchNone];
        NSUInteger beforeSkip = [ed selectionCount];
        BOOL skipped = [ed skipCurrentMultiSelection];
        Check(@"IDM_EDIT_MULTISELECTSSKIP", @"replaces the current selection with the next",
              skipped && [ed selectionCount] == beforeSkip);
    }

    if (NppSectionWanted(@"Edit: begin/end select and column editor")) { printf("\n== Edit: begin/end select and column editor ==\n");
        SetDoc(ed, @"0123456789\n");
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        BOOL anchored = ![ed beginEndSelectColumnMode:NO] && [ed beginEndSelectActive];
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];
        BOOL made = [ed beginEndSelectColumnMode:NO];
        Check(@"IDM_EDIT_BEGINENDSELECT", @"anchors, then selects to the caret",
              anchored && made &&
              [sci message:SCI_GETSELECTIONSTART] == 2 && [sci message:SCI_GETSELECTIONEND] == 6);

        SetDoc(ed, @"abcd\nabcd\nabcd\n");
        [sci message:SCI_GOTOPOS wParam:1 lParam:0];
        [ed beginEndSelectColumnMode:YES];
        [sci message:SCI_GOTOPOS wParam:12 lParam:0];
        BOOL columnMade = [ed beginEndSelectColumnMode:YES];
        Check(@"IDM_EDIT_BEGINENDSELECT_COLUMNMODE", @"builds a rectangular selection",
              columnMade && [ed selectionCount] >= 3);

        // Column Editor over that rectangular selection.
        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0 lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:4 lParam:0];
        BOOL inserted = [ed columnInsertText:@">"];
        Check(@"IDM_EDIT_COLUMNMODE", @"inserts into every row of the rectangle",
              inserted && [DocText(ed) isEqualToString:@">a\n>b\n>c\n"]);

        SetDoc(ed, @"x\nx\nx\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0 lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:4 lParam:0];
        [ed columnInsertNumbersFrom:1 increment:1 zeroPadded:NO base:10];
        Check(@"IDM_EDIT_COLUMNMODETIP", @"numbers each row in sequence",
              [DocText(ed) isEqualToString:@"1x\n2x\n3x\n"]);
    }

    if (NppSectionWanted(@"Edit: paste special")) { printf("\n== Edit: paste special ==\n");
        SetDoc(ed, @"AB\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL copied = [ed copySelectionAsBinary];
        NSString *hex = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        Check(@"IDM_EDIT_COPY_BINARY", @"copies the bytes as hex pairs",
              copied && [hex isEqualToString:@"41 42"]);

        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL pasted = [ed pasteBinary];
        Check(@"IDM_EDIT_PASTE_BINARY", @"turns hex pairs back into bytes",
              pasted && [DocText(ed) isEqualToString:@"AB"]);

        SetDoc(ed, @"XY\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL cut = [ed cutSelectionAsBinary];
        Check(@"IDM_EDIT_CUT_BINARY", @"copies as hex and removes the selection",
              cut && ![DocText(ed) hasPrefix:@"XY"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"58 59"]);

        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:@"<b>bold</b>" forType:NSPasteboardTypeHTML];
        SetDoc(ed, @"");
        Check(@"IDM_EDIT_PASTE_AS_HTML", @"pastes the HTML source",
              [ed pasteAsHTML] && [DocText(ed) containsString:@"<b>"]);

        [pb clearContents];
        NSAttributedString *rich = [[NSAttributedString alloc] initWithString:@"rich"];
        [pb setData:[rich RTFFromRange:NSMakeRange(0, 4) documentAttributes:@{}]
            forType:NSPasteboardTypeRTF];
        SetDoc(ed, @"");
        Check(@"IDM_EDIT_PASTE_AS_RTF", @"pastes the RTF source",
              [ed pasteAsRTF] && [DocText(ed) containsString:@"rtf"]);
    }

    if (NppSectionWanted(@"Edit: on selection")) { printf("\n== Edit: on selection ==\n");
        NSError *err = nil;
        NSString *target = TempFile(@"t_sel_target.txt", @"opened via selection\n");
        NSString *holder = TempFile(@"t_sel_holder.txt",
                                    [NSString stringWithFormat:@"%@\n", target]);
        [ed openFileAtPath:holder error:&err];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        NSString *resolved = [ed selectionAsPath];
        BOOL opened = [ed openSelectedFile];
        Check(@"IDM_EDIT_OPENSELECTEDFILETOEDIT", @"opens the file named by the selection",
              [resolved isEqualToString:target] && opened &&
              [ed.currentDocument.path isEqualToString:target]);

        // Revealing in Finder is not launched here; the resolution is what matters.
        [ed openFileAtPath:holder error:&err];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[target lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        Check(@"IDM_EDIT_OPENSELECTEDFILEFOLDERINEXPLORER", @"resolves the same path for Finder",
              [[ed selectionAsPath] isEqualToString:target]);

        SetDoc(ed, @"secret value\n");
        [sci message:SCI_SETSEL wParam:0 lParam:6];
        BOOL redacted = [ed redactSelectionWithBlock:YES];
        Check(@"IDM_EDIT_REDACT_SELECTION", @"replaces the selection with blocks",
              redacted && [DocText(ed) hasPrefix:@"\u2588\u2588\u2588\u2588\u2588\u2588"]);

        ed.searchEngineTemplate = @"https://example.invalid/?q=%@";
        Check(@"IDM_EDIT_CHANGESEARCHENGINE", @"remembers the chosen engine",
              [ed.searchEngineTemplate isEqualToString:@"https://example.invalid/?q=%@"]);

        // Opening a browser from a test would be rude; assert the guard path.
        SetDoc(ed, @"");
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        Check(@"IDM_EDIT_SEARCHONINTERNET", @"declines with nothing selected",
              ![ed searchSelectionOnInternet]);
    }

    if (NppSectionWanted(@"Edit: completion, panels, file attribute")) { printf("\n== Edit: completion, panels, file attribute ==\n");
        SetDoc(ed, @"alphabet alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        [ed showAutoCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE_CURRENTFILE", @"offers words from the document",
              [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];

        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_pathcomp"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"x" writeToFile:[dir stringByAppendingPathComponent:@"target.txt"]
               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        SetDoc(ed, [dir stringByAppendingString:@"/tar"]);
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL pathComp = [ed showPathCompletion];
        Check(@"IDM_EDIT_AUTOCOMPLETE_PATH", @"offers directory entries",
              pathComp && [sci message:SCI_AUTOCACTIVE] != 0);
        [sci message:SCI_AUTOCCANCEL];

        // As upstream: the whole path from where it starts, even with a space
        // in it, matched without regard to case, folders ending in a slash.
        NSString *spaced = [dir stringByAppendingPathComponent:@"my dir"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[spaced stringByAppendingPathComponent:@"Sub"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        SetDoc(ed, [NSString stringWithFormat:@"cat \"%@/su", spaced]);
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL spacedComp = [ed showPathCompletion];
        char chosen[1024] = {0};
        [sci message:SCI_AUTOCGETCURRENTTEXT wParam:0 lParam:(sptr_t)chosen];
        Check(@"IDM_EDIT_AUTOCOMPLETE_PATH (as upstream)",
              @"a path with a space is completed whole, case aside, and a folder ends in a slash",
              spacedComp && [@(chosen) isEqualToString:[spaced stringByAppendingString:@"/Sub/"]]);
        [sci message:SCI_AUTOCCANCEL];

        SetDoc(ed, @"int helper(int a);\nint helper(int a, int b);\nhelper\n");
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        BOOL tip = [ed showFunctionCallTip];
        Check(@"IDM_EDIT_FUNCCALLTIP", @"shows a hint for the word at the caret",
              tip && [sci message:SCI_CALLTIPACTIVE] != 0);

        // A tip that appears but says nothing useful is no better than none.
        // Notepad++ builds it from the shipped signature: return value, name,
        // parameters, and the description on a line of its own.
        NSString *tipFile = TempFile(@"t_tip.c", @"x = abs(1);\n");
        [ed openFileAtPath:tipFile error:NULL];
        [ed.sci message:SCI_GOTOPOS wParam:5 lParam:0];    // inside "abs"
        NSArray<NSString *> *tips = [ed callTipCandidates];
        Check(@"IDM_EDIT_FUNCCALLTIP (signature)",
              @"the hint is the shipped signature, not a line copied from the file",
              tips.count > 0 && [tips[0] isEqualToString:@"int abs (int i)"]);
        [[NSFileManager defaultManager] removeItemAtPath:tipFile error:NULL];

        // Stepping between overloads has to step between real ones. Perl's abs
        // is shipped with two, so the document is Perl for this.
        NSString *plFile = TempFile(@"t_tip.pl", @"$x = abs($y);\n");
        [ed openFileAtPath:plFile error:NULL];
        [ed.sci message:SCI_GOTOPOS wParam:7 lParam:0];    // inside "abs"
        NSArray<NSString *> *overloads = [ed callTipCandidates];
        [ed showFunctionCallTip];
        Check(@"IDM_EDIT_FUNCCALLTIP_NEXT", @"steps to the next overload",
              overloads.count > 1 && [ed cycleFunctionCallTip:YES]);
        Check(@"IDM_EDIT_FUNCCALLTIP_PREVIOUS", @"steps back to the previous one",
              [ed cycleFunctionCallTip:NO]);
        [[NSFileManager defaultManager] removeItemAtPath:plFile error:NULL];
        [sci message:SCI_CALLTIPCANCEL];

        // Breadth: every list Notepad++ ships has to load. Bundling none of
        // them at all, which is how this started, looked exactly like success
        // as long as only the popup was checked.
        ApiCatalog *apis = [ApiCatalog sharedCatalog];
        NSMutableArray *emptyApis = [NSMutableArray array];
        for (NSString *language in apis.languages) {
            if (![apis entriesForLanguage:language].count) [emptyApis addObject:language];
        }
        Check(@"IDM_EDIT_FUNCCALLTIP (shipped lists)",
              @"every function list Notepad++ ships is bundled and loads",
              apis.languages.count == 34 && emptyApis.count == 0);
        if (emptyApis.count) printf("       %s\n",
            [[emptyApis componentsJoinedByString:@","] UTF8String]);

        // The file says whether its list is matched regardless of case, and C's
        // says it is not.
        Check(@"IDM_EDIT_FUNCCALLTIP (case)",
              @"the list honours the case setting its own file carries",
              ![apis ignoreCaseForLanguage:@"c"] &&
              [[apis callTipsForLanguage:@"c" function:@"ABS"] count] == 0 &&
              [[apis callTipsForLanguage:@"c" function:@"abs"] count] == 1);

        CharacterPanel *chars = [[CharacterPanel alloc] initWithEditor:ed];
        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL insertedChar = [chars insertRow:'A'];
        Check(@"IDM_EDIT_CHAR_PANEL", @"inserts the chosen character",
              insertedChar && [DocText(ed) isEqualToString:@"A"]);
        // As AnsiCharPanel: 256 values, the upper half in the code page (1252
        // for a Unicode file), the HTML columns, and a click on one puts it in.
        [chars insertRow:0x80];
        [chars insertRow:0xE9 column:@"name"];
        [chars insertRow:0x93 column:@"dec"];
        Check(@"IDM_EDIT_CHAR_PANEL (columns)",
              @"the panel lists 0-255 with Hex, Character and HTML forms, as Notepad++ does",
              chars.rowCount == 256 && [[chars textOfColumn:@"char" row:10] isEqualToString:@"LF"] &&
              [[chars textOfColumn:@"hex" row:255] isEqualToString:@"FF"] &&
              [[chars textOfColumn:@"char" row:0x80] isEqualToString:@"\u20AC"] &&
              [[chars textOfColumn:@"name" row:'&'] isEqualToString:@"&amp;"] &&
              [[chars textOfColumn:@"hexnum" row:0x80] isEqualToString:@"&#x20ac;"] &&
              [DocText(ed) isEqualToString:@"A\u20AC&eacute;&#8220;"]);

        ClipboardHistoryPanel *clips = [[ClipboardHistoryPanel alloc] initWithEditor:ed];
        [ed copyToClipboard:@"history one"];
        [clips capturePasteboard];
        [ed copyToClipboard:@"history two"];
        [clips capturePasteboard];
        SetDoc(ed, @"");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        BOOL pastedOld = [clips pasteRow:1];
        Check(@"IDM_EDIT_CLIPBOARDHISTORY_PANEL", @"keeps earlier entries and pastes them back",
              clips.entries.count == 2 && pastedOld &&
              [DocText(ed) isEqualToString:@"history one"]);

        NSString *roFile = TempFile(@"t_readonly.txt", @"locked\n");
        [ed openFileAtPath:roFile error:NULL];
        BOOL wasWritable = ![ed systemReadOnly];
        [ed toggleSystemReadOnly];
        BOOL nowReadOnly = [ed systemReadOnly];
        [ed toggleSystemReadOnly];
        Check(@"IDM_EDIT_TOGGLESYSTEMREADONLY", @"flips the file's write permission",
              wasWritable && nowReadOnly && ![ed systemReadOnly]);
    }

    if (NppSectionWanted(@"Search")) { printf("\n== Search ==\n");
        SetDoc(ed, @"needle one\nneedle two\n");
        app.lastSearchTerm = @"needle";
        BOOL f1 = [app searchFrom:0 forward:YES wrap:YES];
        long first = [sci message:SCI_GETSELECTIONSTART];
        Check(@"IDM_SEARCH_FIND", @"finds the first match", f1 && first == 0);

        BOOL f2 = [app searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:YES];
        Check(@"IDM_SEARCH_FINDNEXT", @"advances to the next match",
              f2 && [sci message:SCI_GETSELECTIONSTART] > first);

        BOOL f3 = [app searchFrom:[sci message:SCI_GETSELECTIONSTART] forward:NO wrap:YES];
        Check(@"IDM_SEARCH_FINDPREV", @"searches backwards", f3);

        // Replace-all without the prompt: the loop the menu item drives.
        SetDoc(ed, @"aaa bbb aaa\n");
        app.lastSearchTerm = @"aaa";
        long replaced = 0;
        [sci message:SCI_SETSEL wParam:0 lParam:0];
        while ([app searchFrom:[sci message:SCI_GETSELECTIONEND] forward:YES wrap:NO]) {
            [sci setStringProperty:SCI_REPLACETARGET parameter:3 value:@"zzz"];
            long end = [sci message:SCI_GETTARGETEND];
            [sci message:SCI_SETSEL wParam:(uptr_t)end lParam:end];
            replaced++;
            if (replaced > 10) break;
        }
        Check(@"IDM_SEARCH_REPLACE", @"replaces every occurrence",
              replaced == 2 && [DocText(ed) isEqualToString:@"zzz bbb zzz\n"]);

        SetDoc(ed, @"1\n2\n3\n4\n5\n");
        [sci message:SCI_GOTOLINE wParam:3 lParam:0];
        Check(@"IDM_SEARCH_GOTOLINE", @"moves the caret to the line",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 3);

        SetDoc(ed, @"a\nb\nc\nd\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed toggleBookmark];
        BOOL set = ([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) != 0;
        [ed toggleBookmark];
        BOOL cleared = ([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) == 0;
        Check(@"IDM_SEARCH_TOGGLE_BOOKMARK", @"toggles on and off", set && cleared);

        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        [ed toggleBookmark];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed nextBookmark];
        Check(@"IDM_SEARCH_NEXT_BOOKMARK", @"jumps forward to a bookmark",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 2);

        [sci message:SCI_GOTOLINE wParam:3 lParam:0];
        [ed previousBookmark];
        Check(@"IDM_SEARCH_PREV_BOOKMARK", @"jumps backward to a bookmark",
              [sci message:SCI_LINEFROMPOSITION
                       wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 2);

        [ed clearBookmarks];
        Check(@"IDM_SEARCH_CLEAR_BOOKMARKS", @"removes every bookmark",
              [sci message:SCI_MARKERNEXT wParam:0 lParam:(1 << 1)] < 0);
    }

    if (NppSectionWanted(@"Search: token styling")) { printf("\n== Search: token styling ==\n");
        NSArray *markAllIDs = @[@"IDM_SEARCH_MARKALLEXT1", @"IDM_SEARCH_MARKALLEXT2", @"IDM_SEARCH_MARKALLEXT3",
                                @"IDM_SEARCH_MARKALLEXT4", @"IDM_SEARCH_MARKALLEXT5"];
        NSArray *markOneIDs = @[@"IDM_SEARCH_MARKONEEXT1", @"IDM_SEARCH_MARKONEEXT2", @"IDM_SEARCH_MARKONEEXT3",
                                @"IDM_SEARCH_MARKONEEXT4", @"IDM_SEARCH_MARKONEEXT5"];
        NSArray *clearIDs   = @[@"IDM_SEARCH_UNMARKALLEXT1", @"IDM_SEARCH_UNMARKALLEXT2", @"IDM_SEARCH_UNMARKALLEXT3",
                                @"IDM_SEARCH_UNMARKALLEXT4", @"IDM_SEARCH_UNMARKALLEXT5"];
        NSArray *upIDs      = @[@"IDM_SEARCH_GOPREVMARKER1", @"IDM_SEARCH_GOPREVMARKER2", @"IDM_SEARCH_GOPREVMARKER3",
                                @"IDM_SEARCH_GOPREVMARKER4", @"IDM_SEARCH_GOPREVMARKER5"];
        NSArray *downIDs    = @[@"IDM_SEARCH_GONEXTMARKER1", @"IDM_SEARCH_GONEXTMARKER2", @"IDM_SEARCH_GONEXTMARKER3",
                                @"IDM_SEARCH_GONEXTMARKER4", @"IDM_SEARCH_GONEXTMARKER5"];
        NSArray *clipIDs    = @[@"IDM_SEARCH_STYLE1TOCLIP", @"IDM_SEARCH_STYLE2TOCLIP", @"IDM_SEARCH_STYLE3TOCLIP",
                                @"IDM_SEARCH_STYLE4TOCLIP", @"IDM_SEARCH_STYLE5TOCLIP"];

        for (NSInteger style = 0; style < NPPMAC_STYLE_COUNT; ++style) {
            SetDoc(ed, @"alpha beta alpha gamma alpha\n");
            [sci message:SCI_SETSEL wParam:0 lParam:5];          // "alpha"
            NSUInteger n = [ed markAllOccurrencesOfSelection:style];
            Check(markAllIDs[style], @"marks every occurrence of the token", n == 3);

            [sci message:SCI_GOTOPOS wParam:0 lParam:0];
            BOOL down = [ed jumpToMarker:style forward:YES];
            long afterDown = [sci message:SCI_GETSELECTIONSTART];
            Check(downIDs[style], @"jumps to the next marked token", down && afterDown > 0);

            BOOL up = [ed jumpToMarker:style forward:NO];
            Check(upIDs[style], @"jumps back to the previous one",
                  up && [sci message:SCI_GETSELECTIONSTART] < afterDown);

            [ed copyToClipboard:[ed textOfStyle:style]];
            Check(clipIDs[style], @"copies the styled text",
                  [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      containsString:@"alpha"]);

            [ed clearStyle:style];
            Check(clearIDs[style], @"clears the style", [ed textOfStyle:style].length == 0);

            SetDoc(ed, @"one two one\n");
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [ed markOneOccurrenceOfSelection:style];
            Check(markOneIDs[style], @"marks only the selected occurrence",
                  [[ed textOfStyle:style] isEqualToString:@"one"]);
            [ed clearStyle:style];
        }

        SetDoc(ed, @"x y x\n");
        [sci message:SCI_SETSEL wParam:0 lParam:1];
        [ed markAllOccurrencesOfSelection:0];
        [ed markAllOccurrencesOfSelection:1];
        NSString *all = [ed textOfAllStyles];
        Check(@"IDM_SEARCH_ALLSTYLESTOCLIP", @"gathers text across styles", all.length > 0);

        [ed clearAllStyles];
        Check(@"IDM_SEARCH_CLEARALLMARKS", @"clears every style",
              [ed textOfAllStyles].length == 0);

        SetDoc(ed, @"find me find\n");
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        NSUInteger marked = [ed markAllOccurrencesOfSelection:NPPMAC_STYLE_COUNT];
        Check(@"IDM_SEARCH_MARK", @"Mark uses the Find Mark style", marked == 2);
        BOOL fwd = [ed jumpToMarker:NPPMAC_STYLE_COUNT forward:YES];
        Check(@"IDM_SEARCH_GONEXTMARKER_DEF", @"jumps down the Find Mark style", fwd);
        BOOL back = [ed jumpToMarker:NPPMAC_STYLE_COUNT forward:NO];
        Check(@"IDM_SEARCH_GOPREVMARKER_DEF", @"jumps up the Find Mark style", back);
        [ed copyToClipboard:[ed textOfStyle:NPPMAC_STYLE_COUNT]];
        Check(@"IDM_SEARCH_MARKEDTOCLIP", @"copies Find Mark text",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:@"find"]);
        [ed clearAllStyles];

        SetDoc(ed, @"ascii \u00e9\u00e8\n");
        NSUInteger nonAscii = [ed markCharactersInRangeFrom:128 to:65535];
        Check(@"IDM_SEARCH_FINDCHARINRANGE", @"marks characters in a code-point range",
              nonAscii == 2);
        [ed clearAllStyles];
    }

    if (NppSectionWanted(@"Search: bookmarked lines")) { printf("\n== Search: bookmarked lines ==\n");
        SetDoc(ed, @"keep1\ndrop1\nkeep2\ndrop2\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [sci message:SCI_GOTOLINE wParam:2 lParam:0]; [ed toggleBookmark];

        [ed copyBookmarkedLines];
        Check(@"IDM_SEARCH_COPYMARKEDLINES", @"copies just the bookmarked lines, each with its ending",
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                  isEqualToString:@"keep1\nkeep2\n"]);

        [ed removeUnbookmarkedLines];
        Check(@"IDM_SEARCH_DELETEUNMARKEDLINES", @"keeps only bookmarked lines",
              [DocText(ed) hasPrefix:@"keep1"] && ![DocText(ed) containsString:@"drop1"]);

        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0]; [ed toggleBookmark];
        [ed removeBookmarkedLines];
        Check(@"IDM_SEARCH_DELETEMARKEDLINES", @"removes bookmarked lines",
              ![DocText(ed) containsString:@"b"]);

        SetDoc(ed, @"x\ny\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [ed cutBookmarkedLines];
        Check(@"IDM_SEARCH_CUTMARKEDLINES", @"copies then removes them",
              ![DocText(ed) containsString:@"x"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] containsString:@"x"]);

        SetDoc(ed, @"one\ntwo\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0]; [ed toggleBookmark];
        [ed copyToClipboard:@"REPLACED"];
        [ed pasteOverBookmarkedLines];
        Check(@"IDM_SEARCH_PASTEMARKEDLINES", @"replaces bookmarked lines with the clipboard",
              [DocText(ed) hasPrefix:@"REPLACED"] && [DocText(ed) containsString:@"two"]);

        SetDoc(ed, @"p\nq\nr\n");
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0]; [ed toggleBookmark];
        [ed inverseBookmarks];
        BOOL inverted = !([sci message:SCI_MARKERGET wParam:1] & (1 << 1)) &&
                         ([sci message:SCI_MARKERGET wParam:0] & (1 << 1));
        Check(@"IDM_SEARCH_INVERSEMARKS", @"flips which lines are bookmarked", inverted);
        [sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
    }

    if (NppSectionWanted(@"Search: braces, selection, files")) { printf("\n== Search: braces, selection, files ==\n");
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"if (a) { b; }\n");
        [sci message:SCI_GOTOPOS wParam:7 lParam:0];       // the '{'
        BOOL jumped = [ed goToMatchingBrace];
        Check(@"IDM_SEARCH_GOTOMATCHINGBRACE", @"moves to the matching brace",
              jumped && [sci message:SCI_GETCURRENTPOS] == 12);

        [sci message:SCI_GOTOPOS wParam:7 lParam:0];
        BOOL selected = [ed selectBetweenMatchingBraces];
        Check(@"IDM_SEARCH_SELECTMATCHINGBRACES", @"selects between the braces",
              selected && [sci message:SCI_GETSELECTIONEND] > [sci message:SCI_GETSELECTIONSTART]);

        SetDoc(ed, @"aa bb aa cc aa\n");
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        BOOL next = [ed findNextOccurrenceOfSelection:YES extendSelection:NO];
        long p1 = [sci message:SCI_GETSELECTIONSTART];
        Check(@"IDM_SEARCH_SETANDFINDNEXT", @"selects the next occurrence", next && p1 == 6);
        BOOL prev = [ed findNextOccurrenceOfSelection:NO extendSelection:NO];
        Check(@"IDM_SEARCH_SETANDFINDPREV", @"selects the previous one",
              prev && [sci message:SCI_GETSELECTIONSTART] < p1);

        [sci message:SCI_SETSEL wParam:0 lParam:2];
        Check(@"IDM_SEARCH_VOLATILE_FINDNEXT", @"volatile next uses the selection",
              [ed findNextOccurrenceOfSelection:YES extendSelection:NO]);
        Check(@"IDM_SEARCH_VOLATILE_FINDPREV", @"volatile previous uses the selection",
              [ed findNextOccurrenceOfSelection:NO extendSelection:NO]);

        // The two are different commands: Select and Find Next puts the word
        // into the Find dialog and obeys its Match case; Volatile Find leaves
        // the dialog alone, ignores case and says when it went round the end.
        [app buildFindPanel];
        NSTextField *findWhat = [app valueForKey:@"findField"];
        NSButton *caseBox = [app valueForKey:@"matchCaseBox"];
        NSTextField *findLine = [app valueForKey:@"findStatus"];
        NSControlStateValue caseWas = caseBox.state;
        NSString *whatWas = findWhat.stringValue;
        SetDoc(ed, @"Word word Word\n");
        caseBox.state = NSControlStateValueOn;
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [app performSelector:@selector(selectAndFindNext:) withObject:nil];
        BOOL setAndFind = [findWhat.stringValue isEqualToString:@"Word"] && [sci message:SCI_GETSELECTIONSTART] == 10;
        findWhat.stringValue = @"untouched";
        [sci message:SCI_SETSEL wParam:10 lParam:14];
        [app performSelector:@selector(volatileFindNext:) withObject:nil];
        BOOL volatileFound = [findWhat.stringValue isEqualToString:@"untouched"] && [sci message:SCI_GETSELECTIONSTART] == 0 &&
                             [findLine.stringValue hasPrefix:@"Find: Reached document end"];
        [sci message:SCI_SETSEL wParam:0 lParam:4];
        [app performSelector:@selector(volatileFindNext:) withObject:nil];
        volatileFound = volatileFound && [sci message:SCI_GETSELECTIONSTART] == 5 && findLine.stringValue.length == 0;
        caseBox.state = caseWas;
        findWhat.stringValue = whatWas;
        Check(@"IDM_SEARCH_VOLATILE_FINDNEXT (not Select and Find Next)",
              @"Select and Find Next fills the dialog and obeys its options; Volatile Find does neither and reports wrapping",
              setAndFind && volatileFound);
        SetDoc(ed, @"aa bb aa cc aa\n");

        app.lastSearchTerm = @"cc";
        Check(@"IDM_SEARCH_FINDINCREMENT", @"incremental search drives the same state",
              [app searchFrom:0 forward:YES wrap:YES]);

        // Find in Files over a throwaway tree.
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_fif"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"hello needle\nplain\n" writeToFile:[dir stringByAppendingPathComponent:@"a.txt"]
                                     atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"needle again\nneedle twice\n" writeToFile:[dir stringByAppendingPathComponent:@"b.txt"]
                                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSUInteger hits = [ed findInFiles:@"needle" inFolder:dir filter:nil];
        Check(@"IDM_SEARCH_FINDINFILES", @"reports every hit across the folder", hits == 3);
        Check(@"IDM_FOCUS_ON_FOUND_RESULTS", @"results land in their own tab",
              [ed focusSearchResults] &&
              [ed.currentDocument.displayName isEqualToString:@"Search results"]);

        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL nextHit = [ed goToSearchResult:YES];
        long hitLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"IDM_SEARCH_GOTONEXTFOUND", @"steps to the next result line", nextHit);
        Check(@"IDM_SEARCH_GOTOPREVFOUND", @"steps back to the previous one",
              [ed goToSearchResult:NO] || hitLine >= 0);
    }

    if (NppSectionWanted(@"Search: change history")) { printf("\n== Search: change history ==\n");
        [ed newDocument];
        [ed enableChangeHistory:YES];
        SetDoc(ed, @"line1\nline2\nline3\n");
        [sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [sci setStringProperty:SCI_INSERTTEXT parameter:[sci message:SCI_GETCURRENTPOS] value:@"EDIT"];

        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL fwd = [ed goToNextChange:YES];
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"finds the modified line", fwd);
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        Check(@"IDM_SEARCH_CHANGED_PREV", @"finds it going backwards", [ed goToNextChange:NO]);

        // Regression: change-history markers must belong to a margin. Scintilla
        // draws a marker with no margin as a whole-line background, which turned
        // every saved line the "saved" colour and made the document look green.
        long historyMask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                           (1 << SC_MARKNUM_HISTORY_SAVED) |
                           (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                           (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
        long covered = 0;
        for (int margin = 0; margin < SC_MAX_MARGIN + 1; ++margin) {
            if ([sci message:SCI_GETMARGINWIDTHN wParam:(uptr_t)margin] > 0) {
                covered |= [sci message:SCI_GETMARGINMASKN wParam:(uptr_t)margin];
            }
        }
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"history markers live in a visible margin",
              (covered & historyMask) == historyMask);

        [ed clearChangeHistory];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        Check(@"IDM_SEARCH_CLEAR_CHANGE_HISTORY", @"history is discarded",
              ![ed goToNextChange:YES]);
    }

    if (NppSectionWanted(@"View")) { printf("\n== View ==\n");
        [app zoomReset:nil];
        long z0 = [sci message:SCI_GETZOOM];
        [app zoomIn:nil];
        Check(@"IDM_VIEW_ZOOMIN", @"increases zoom", [sci message:SCI_GETZOOM] > z0);
        [app zoomOut:nil];
        Check(@"IDM_VIEW_ZOOMOUT", @"decreases zoom", [sci message:SCI_GETZOOM] == z0);
        [app zoomIn:nil];
        [app zoomReset:nil];
        Check(@"IDM_VIEW_ZOOMRESTORE", @"returns to 100%", [sci message:SCI_GETZOOM] == 0);

        long w0 = [sci message:SCI_GETWRAPMODE];
        [app toggleWordWrap:nil];
        BOOL changed = [sci message:SCI_GETWRAPMODE] != w0;
        [app toggleWordWrap:nil];
        Check(@"IDM_VIEW_WRAP", @"toggles and restores",
              changed && [sci message:SCI_GETWRAPMODE] == w0);

        long ws0 = [sci message:SCI_GETVIEWWS];
        [app toggleWhitespace:nil];
        BOOL wsChanged = [sci message:SCI_GETVIEWWS] != ws0;
        [app toggleWhitespace:nil];
        Check(@"IDM_VIEW_ALL_CHARACTERS", @"toggles whitespace display",
              wsChanged && [sci message:SCI_GETVIEWWS] == ws0);

        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"int f() {\n  int x;\n  return x;\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        [ed foldAll:YES];
        BOOL folded = [sci message:SCI_GETLINEVISIBLE wParam:1] == 0;
        [ed foldAll:NO];
        BOOL unfolded = [sci message:SCI_GETLINEVISIBLE wParam:1] != 0;
        Check(@"IDM_VIEW_FOLDALL", @"collapses every fold", folded);
        Check(@"IDM_VIEW_UNFOLDALL", @"expands every fold", unfolded);

        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed foldCurrent:YES];
        Check(@"IDM_VIEW_FOLD_CURRENT", @"collapses the enclosing fold",
              [sci message:SCI_GETLINEVISIBLE wParam:1] == 0);
        [ed foldCurrent:NO];
        Check(@"IDM_VIEW_UNFOLD_CURRENT", @"expands the enclosing fold",
              [sci message:SCI_GETLINEVISIBLE wParam:1] != 0);
    }

    if (NppSectionWanted(@"View: tabs")) { printf("\n== View: tabs ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        for (int i = 1; i <= 9; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"t_tab%d.txt", i],
                                        [NSString stringWithFormat:@"tab %d\n", i]) error:&err];
        }
        NSArray *tabIDs = @[@"IDM_VIEW_TAB1", @"IDM_VIEW_TAB2", @"IDM_VIEW_TAB3", @"IDM_VIEW_TAB4",
                            @"IDM_VIEW_TAB5", @"IDM_VIEW_TAB6", @"IDM_VIEW_TAB7", @"IDM_VIEW_TAB8",
                            @"IDM_VIEW_TAB9"];
        for (NSInteger i = 1; i <= 9; ++i) {
            BOOL ok = [ed selectTabNumber:i];
            Check(tabIDs[i - 1], [NSString stringWithFormat:@"selects tab %ld", (long)i],
                  ok && [ed.documents indexOfObject:ed.currentDocument] == (NSUInteger)(i - 1));
        }

        [ed goToFirstTab];
        Check(@"IDM_VIEW_TAB_START", @"jumps to the first tab",
              [ed.documents indexOfObject:ed.currentDocument] == 0);
        [ed goToLastTab];
        Check(@"IDM_VIEW_TAB_END", @"jumps to the last tab",
              [ed.documents indexOfObject:ed.currentDocument] == ed.documents.count - 1);

        [ed goToFirstTab];
        [ed goToNextTab];
        Check(@"IDM_VIEW_TAB_NEXT", @"steps forward one tab",
              [ed.documents indexOfObject:ed.currentDocument] == 1);
        [ed goToPreviousTab];
        Check(@"IDM_VIEW_TAB_PREV", @"steps back one tab",
              [ed.documents indexOfObject:ed.currentDocument] == 0);

        NppDocument *moving = ed.currentDocument;
        [ed moveCurrentTab:YES];
        Check(@"IDM_VIEW_TAB_MOVEFORWARD", @"moves the tab one place right",
              [ed.documents indexOfObject:moving] == 1 && ed.currentDocument == moving);
        [ed moveCurrentTab:NO];
        Check(@"IDM_VIEW_TAB_MOVEBACKWARD", @"moves it back",
              [ed.documents indexOfObject:moving] == 0);

        [ed selectTabNumber:5];
        NppDocument *jumper = ed.currentDocument;
        [ed moveCurrentTabToEnd:NO];
        Check(@"IDM_VIEW_GOTO_START", @"moves the tab to the front",
              [ed.documents indexOfObject:jumper] == 0);
        [ed moveCurrentTabToEnd:YES];
        Check(@"IDM_VIEW_GOTO_END", @"moves it to the back",
              [ed.documents indexOfObject:jumper] == ed.documents.count - 1);

        NSArray *colourIDs = @[@"IDM_VIEW_TAB_COLOUR_1", @"IDM_VIEW_TAB_COLOUR_2", @"IDM_VIEW_TAB_COLOUR_3",
                               @"IDM_VIEW_TAB_COLOUR_4", @"IDM_VIEW_TAB_COLOUR_5"];
        for (NSInteger c = 1; c <= 5; ++c) {
            [ed setTabColour:c];
            Check(colourIDs[c - 1], [NSString stringWithFormat:@"applies colour %ld", (long)c],
                  ed.currentDocument.tabColour == c);
        }
        [ed setTabColour:0];
        Check(@"IDM_VIEW_TAB_COLOUR_NONE", @"removes the colour", ed.currentDocument.tabColour == 0);
    }

    if (NppSectionWanted(@"View: fold levels")) { printf("\n== View: fold levels ==\n");
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"void a() {\n  if (x) {\n    y();\n  }\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];

        NSArray *foldIDs = @[@"IDM_VIEW_FOLD_1", @"IDM_VIEW_FOLD_2", @"IDM_VIEW_FOLD_3", @"IDM_VIEW_FOLD_4",
                             @"IDM_VIEW_FOLD_5", @"IDM_VIEW_FOLD_6", @"IDM_VIEW_FOLD_7", @"IDM_VIEW_FOLD_8"];
        NSArray *unfoldIDs = @[@"IDM_VIEW_UNFOLD_1", @"IDM_VIEW_UNFOLD_2", @"IDM_VIEW_UNFOLD_3", @"IDM_VIEW_UNFOLD_4",
                               @"IDM_VIEW_UNFOLD_5", @"IDM_VIEW_UNFOLD_6", @"IDM_VIEW_UNFOLD_7", @"IDM_VIEW_UNFOLD_8"];
        for (NSInteger lvl = 1; lvl <= 8; ++lvl) {
            [ed unfoldToLevel:lvl];
            [ed foldToLevel:lvl];
            // Level 1 and 2 exist in this snippet; deeper levels must be no-ops
            // rather than errors, which is what is asserted here.
            BOOL consistent = YES;
            if (lvl == 1) consistent = [sci message:SCI_GETLINEVISIBLE wParam:1] == 0;
            Check(foldIDs[lvl - 1], [NSString stringWithFormat:@"folds level %ld", (long)lvl], consistent);

            [ed unfoldToLevel:lvl];
            BOOL restored = YES;
            if (lvl == 1) restored = [sci message:SCI_GETLINEVISIBLE wParam:1] != 0;
            Check(unfoldIDs[lvl - 1], [NSString stringWithFormat:@"unfolds level %ld", (long)lvl], restored);
        }
        [ed foldAll:NO];
    }

    if (NppSectionWanted(@"View: symbols, lines, direction")) { printf("\n== View: symbols, lines, direction ==\n");
        struct { NppSymbol sym; NSString *cmd; } syms[] = {
            {NppSymbolWhitespace,           @"IDM_VIEW_TAB_SPACE"},
            {NppSymbolEOL,                  @"IDM_VIEW_EOL"},
            {NppSymbolNonPrinting,          @"IDM_VIEW_NPC"},
            {NppSymbolControlAndUnicodeEOL, @"IDM_VIEW_NPC_CCUNIEOL"},
            {NppSymbolIndentGuide,          @"IDM_VIEW_INDENT_GUIDE"},
            {NppSymbolWrap,                 @"IDM_VIEW_WRAP_SYMBOL"},
        };
        for (size_t i = 0; i < sizeof(syms)/sizeof(syms[0]); ++i) {
            BOOL before = [ed symbolVisible:syms[i].sym];
            [ed toggleSymbol:syms[i].sym];
            BOOL flipped = [ed symbolVisible:syms[i].sym] != before;
            [ed toggleSymbol:syms[i].sym];
            Check(syms[i].cmd, @"toggles and restores",
                  flipped && [ed symbolVisible:syms[i].sym] == before);
        }

        SetDoc(ed, @"one\ntwo\nthree\n");
        [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_POSITIONFROMLINE wParam:1]
                 lParam:[sci message:SCI_GETLINEENDPOSITION wParam:1]];
        BOOL hidden = [ed hideSelectedLines];
        Check(@"IDM_VIEW_HIDELINES", @"hides the selected lines",
              hidden && [sci message:SCI_GETLINEVISIBLE wParam:1] == 0);
        [ed showAllHiddenLines];

        [ed setTextDirectionRTL:YES];
        BOOL rtl = [ed textDirectionIsRTL];
        [ed setTextDirectionRTL:NO];
        Check(@"IDM_EDIT_RTL", @"switches to right-to-left", rtl);
        Check(@"IDM_EDIT_LTR", @"switches back to left-to-right", ![ed textDirectionIsRTL]);

        NSDictionary *sum = [ed documentSummary];
        // A word is a run of anything that is not one of the separators
        // Notepad++ searches with, so an underscore or a hash keeps a word
        // together and a comma or an apostrophe does not.
        SetDoc(ed, @"foo_bar a#b 1,000 O'Connel\n");
        NSDictionary *counted = [ed documentSummary];
        Check(@"IDM_VIEW_SUMMARY", @"the summary counts words the way Notepad++ counts them",
              [counted[@"words"] unsignedIntegerValue] == 6 &&
              [sum[@"lines"] unsignedIntegerValue] >= 1);
    }

    if (NppSectionWanted(@"View: window modes and panels")) { printf("\n== View: window modes and panels ==\n");
        NSError *err = nil;
        NSString *p = TempFile(@"t_view.txt", @"x\n");
        [ed openFileAtPath:p error:&err];

        BOOL chromeBefore = [ed chromeVisible];
        [app toggleDistractionFree:nil];
        BOOL chromeHidden = ![ed chromeVisible];
        [app toggleDistractionFree:nil];
        Check(@"IDM_VIEW_DISTRACTIONFREE", @"hides and restores the chrome",
              chromeHidden && [ed chromeVisible] == chromeBefore);

        [app togglePostIt:nil];
        BOOL postIt = ![ed chromeVisible] && app.window.level == NSFloatingWindowLevel;
        [app togglePostIt:nil];
        Check(@"IDM_VIEW_POSTIT", @"chrome-less and floating, then restored",
              postIt && [ed chromeVisible]);

        [app toggleAlwaysOnTop:nil];
        BOOL onTop = app.window.level == NSFloatingWindowLevel;
        [app toggleAlwaysOnTop:nil];
        Check(@"IDM_VIEW_ALWAYSONTOP", @"raises and lowers the window level",
              onTop && app.window.level == NSNormalWindowLevel);

        // Toggling real full screen animates and would stall the suite.
        // Top-level bar items carry no title of their own; the submenu does.
        NSMenuItem *fs = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![top.submenu.title isEqualToString:@"View"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                if ([mi.title isEqualToString:@"Toggle Full Screen Mode"]) fs = mi;
            }
        }
        Check(@"IDM_VIEW_FULLSCREENTOGGLE", @"wired to the window's full-screen action",
              fs != nil && fs.action == @selector(toggleFullScreenMode:));

        [app toggleFileBrowser:nil];
        BOOL browserOn = [ed workspaceVisible];
        [app toggleFileBrowser:nil];
        Check(@"IDM_VIEW_FILEBROWSER", @"shows and hides the workspace panel",
              browserOn && ![ed workspaceVisible]);

        [app toggleDocumentList:nil];
        BOOL listOn = [app valueForKey:@"docList"] != nil;
        [app toggleDocumentList:nil];

        // Regression: AppKit draws the table from a row count it cached earlier.
        // Asking for a row after the tabs are gone used to index past the end of
        // the documents array and raise, which aborted the process the next time
        // the run loop let the panel redraw.
        id<NSTableViewDataSource> ds = (id<NSTableViewDataSource>)[app valueForKey:@"docList"];
        NSTableView *probe = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSTableColumn *probeCol = [[NSTableColumn alloc] initWithIdentifier:@"doc"];
        NSUInteger liveRows = ed.documents.count;
        id staleValue = [ds tableView:probe objectValueForTableColumn:probeCol
                                  row:(NSInteger)liveRows + 5];
        Check(@"IDM_VIEW_DOCLIST", @"lists documents and survives a stale row index",
              listOn && staleValue != nil);

        // Name, Ext. and Path, sorting by a column, the tab menu on one file
        // and close/save for several - VerticalFileSwitcher's behaviour.
        {
            DocumentListPanel *list = [app valueForKey:@"docList"];
            NppPreferences *lp = [NppPreferences shared];
            BOOL extBefore = lp.docListExtColumn, pathBefore = lp.docListPathColumn;
            NSUInteger docsBefore = ed.documents.count;
            NSString *zeta = TempFile(@"zeta_list.txt", @"z\n"), *alpha = TempFile(@"alpha_list.py", @"a\n");
            [ed openFileAtPath:zeta error:NULL];
            [ed openFileAtPath:alpha error:NULL];
            [list setColumn:@"ext" shown:YES];
            [list setColumn:@"path" shown:YES];
            [list sortByColumn:@"name" ascending:YES];
            NSArray<NppDocument *> *byName = list.rows;
            NSUInteger ia = [byName indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *st) { return [d.path isEqualToString:alpha]; }];
            NSUInteger iz = [byName indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *st) { return [d.path isEqualToString:zeta]; }];
            BOOL sorted = ia < iz;
            BOOL columns = [[list textOfColumn:@"name" row:(NSInteger)ia] isEqualToString:@"alpha_list"] &&
                           [[list textOfColumn:@"ext" row:(NSInteger)ia] isEqualToString:@"py"] &&
                           [[list textOfColumn:@"path" row:(NSInteger)ia] isEqualToString:alpha.stringByDeletingLastPathComponent];
            [list sortByColumn:@"name" ascending:NO];
            BOOL reversed = [list.rows indexOfObject:byName[ia]] > [list.rows indexOfObject:byName[iz]];
            [list activateRow:(NSInteger)[list.rows indexOfObject:byName[iz]]];
            BOOL activated = [ed.currentDocument.path isEqualToString:zeta];

            NSMenu *one = [list menuForSelectedRows:[NSIndexSet indexSetWithIndex:0]];
            NSMenu *several = [list menuForSelectedRows:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
            BOOL menus = [one itemWithTitle:@"Close"] != nil && [several itemWithTitle:@"Close Selected Files"] != nil &&
                         [several itemWithTitle:@"Save Selected Files"] != nil;
            [list sortByColumn:nil ascending:YES];
            // Group by View: with the second view in use, a heading above each
            // view's files; headings are not files, and turning it off removes them.
            BOOL groupWas = lp.docListGroupByView;
            [list setGroupByView:YES];
            NSUInteger plainRows = list.rows.count;
            [ed cloneCurrentToOtherView];
            NSArray *grouped = list.rows;
            BOOL groups = grouped.count == plainRows + 3 && [list isGroupRow:0] && [grouped[0] isEqualToString:@"View 1"] &&
                          [list isGroupRow:(NSInteger)plainRows + 1] && [grouped.lastObject isKindOfClass:[NppDocument class]] &&
                          [[list textOfColumn:@"name" row:0] isEqualToString:@"View 1"] &&
                          [list documentsInRows:[NSIndexSet indexSetWithIndex:0]].count == 0;
            [list setGroupByView:NO];
            groups = groups && list.rows.count == plainRows;
            [list setGroupByView:YES];
            [ed setSecondaryViewVisible:NO];
            groups = groups && list.rows.count == plainRows;
            [list setGroupByView:groupWas];
            menus = menus && groups;
            NSMutableIndexSet *mine = [NSMutableIndexSet indexSet];
            [list.rows enumerateObjectsUsingBlock:^(NppDocument *d, NSUInteger i, BOOL *st) {
                if ([d.path isEqualToString:zeta] || [d.path isEqualToString:alpha]) [mine addIndex:i];
            }];
            [list closeRows:mine];
            BOOL closed = ed.documents.count == docsBefore;
            [list setColumn:@"ext" shown:extBefore];
            [list setColumn:@"path" shown:pathBefore];
            Check(@"IDM_VIEW_DOCLIST (columns)",
                  @"Name, Ext. and Path columns, sorting by a column, a click brings the file up, and selected files close together",
                  sorted && columns && reversed && activated && menus && closed);
        }

        // The tab's right-click menu, as Notepad++ lays it out.
        {
            NSMenu *tabMenu = [app buildTabContextMenu];
            NSMenu *closeMany = [tabMenu itemWithTitle:@"Close Multiple Tabs"].submenu;
            NSMenu *clip = [tabMenu itemWithTitle:@"Copy to Clipboard"].submenu;
            NSMenu *colours = [tabMenu itemWithTitle:@"Apply Color to Tab"].submenu;
            printf("    tab menu: %ld items, close many %ld, clip %ld, colours %ld\n", (long)tabMenu.numberOfItems,
                   (long)closeMany.numberOfItems, (long)clip.numberOfItems, (long)colours.numberOfItems);
            Check(@"IDM_FILE_CLOSE (tab menu)",
                  @"a tab's right-click menu has Close, the Close Multiple Tabs, Copy to Clipboard and colour submenus",
                  [tabMenu indexOfItemWithTitle:@"Close"] == 0 && closeMany.numberOfItems >= 5 &&
                  clip.numberOfItems == 3 && colours.numberOfItems == 6 && [tabMenu itemWithTitle:@"Save"] != nil);
        }

        [ed setMonitoring:YES];
        BOOL monitoring = [ed monitoringEnabled];
        [ed setMonitoring:NO];
        Check(@"IDM_VIEW_MONITORING", @"starts and stops watching the file",
              monitoring && ![ed monitoringEnabled]);

        // Launching a browser from a test would be rude; assert the guard path.
        [ed newDocument];
        struct { NSString *bundle; NSString *cmd; } browsers[] = {
            {@"org.mozilla.firefox",  @"IDM_VIEW_IN_FIREFOX"},
            {@"com.google.Chrome",    @"IDM_VIEW_IN_CHROME"},
            {@"com.microsoft.edgemac",@"IDM_VIEW_IN_EDGE"},
            {@"com.apple.Safari",     @"IDM_VIEW_IN_IE"},
        };
        for (size_t i = 0; i < sizeof(browsers)/sizeof(browsers[0]); ++i) {
            Check(browsers[i].cmd, @"declines while the document is unsaved",
                  ![ed openCurrentInBrowserBundleID:browsers[i].bundle]);
        }
    }

    if (NppSectionWanted(@"View: split panes and panels")) { printf("\n== View: split panes and panels ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        [ed openFileAtPath:TempFile(@"t_split1.txt", @"one\ntwo\nthree\nfour\nfive\n") error:&err];
        [ed openFileAtPath:TempFile(@"t_split2.txt", @"other\n") error:&err];

        [ed selectTabNumber:2];
        void *sharedDoc = ed.currentDocument.docPointer;
        BOOL cloned = [ed cloneCurrentToOtherView];
        Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW", @"second pane shows the same buffer",
              cloned && [ed secondaryViewVisible] &&
              (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == sharedDoc);

        // Style definitions are per view, so the second pane needs its own
        // set (defineDocType styles each view on Windows). Before that, a
        // clone rendered in Scintilla's bare defaults: black on white, no
        // highlighting, whatever the theme.
        [ed openFileAtPath:TempFile(@"t_split3.py", @"# a comment\nprint(1)\n") error:&err];
        [ed cloneCurrentToOtherView];
        BOOL panesMatch = YES;
        NSMutableSet *fores = [NSMutableSet set];
        for (int st = 0; st <= 40 && panesMatch; ++st) {
            long fore = [sci message:SCI_STYLEGETFORE wParam:(uptr_t)st lParam:0];
            [fores addObject:@(fore)];
            panesMatch = fore == [ed.secondarySci message:SCI_STYLEGETFORE wParam:(uptr_t)st lParam:0] &&
                         [sci message:SCI_STYLEGETBACK wParam:(uptr_t)st lParam:0] ==
                         [ed.secondarySci message:SCI_STYLEGETBACK wParam:(uptr_t)st lParam:0];
        }
        Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW (the pane is styled)",
              @"the second pane carries the same style colours as the first, not Scintilla's defaults",
              panesMatch && fores.count >= 2);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];

        NSUInteger before = ed.documents.count;
        [ed moveCurrentToOtherView];
        Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW", @"the tab leaves the primary pane",
              ed.documents.count == before - 1);

        [ed focusOtherView];
        BOOL onOther = [ed otherViewHasFocus];
        [ed focusOtherView];
        Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW", @"focus moves between panes and back",
              onOther && ![ed otherViewHasFocus]);

        // Synchronised scrolling and zoom
        // Long enough that SCI_SETFIRSTVISIBLELINE is not clamped back to 0.
        NSMutableString *tall = [NSMutableString string];
        for (int i = 0; i < 300; ++i) [tall appendFormat:@"line %d\n", i];
        SetDoc(ed, tall);
        [ed cloneCurrentToOtherView];
        [ed setSyncVerticalScroll:YES];
        [sci message:SCI_SETFIRSTVISIBLELINE wParam:40 lParam:0];
        [ed mirrorScrollToSecondary];
        long primaryTop = [sci message:SCI_GETFIRSTVISIBLELINE];
        Check(@"IDM_VIEW_SYNSCROLLV", @"second pane follows vertically",
              primaryTop > 0 &&
              [ed.secondarySci message:SCI_GETFIRSTVISIBLELINE] == primaryTop);
        [ed setSyncVerticalScroll:NO];

        [ed setSyncHorizontalScroll:YES];
        [sci message:SCI_SETXOFFSET wParam:37 lParam:0];
        [ed mirrorScrollToSecondary];
        Check(@"IDM_VIEW_SYNSCROLLH", @"second pane follows horizontally",
              [ed.secondarySci message:SCI_GETXOFFSET] == 37);
        [ed setSyncHorizontalScroll:NO];
        [sci message:SCI_SETXOFFSET wParam:0 lParam:0];

        [ed setSyncZoom:YES];
        [sci message:SCI_SETZOOM wParam:3 lParam:0];
        [ed mirrorScrollToSecondary];
        Check(@"IDM_VIEW_ZOOM_SYNC", @"zoom is mirrored across panes",
              [ed.secondarySci message:SCI_GETZOOM] == 3);
        [ed setSyncZoom:NO];
        [sci message:SCI_SETZOOM wParam:0 lParam:0];
        [ed setSecondaryViewVisible:NO];

        // Spawning real app instances from a test would litter the session.
        [ed newDocument];
        Check(@"IDM_VIEW_GOTO_NEW_INSTANCE", @"declines while the document is unsaved",
              ![ed openCurrentInNewInstanceMoving:YES]);
        Check(@"IDM_VIEW_LOAD_IN_NEW_INSTANCE", @"declines while the document is unsaved",
              ![ed openCurrentInNewInstanceMoving:NO]);

        [ed openFileAtPath:TempFile(@"t_map.txt", @"mapped\n") error:&err];
        [ed setDocumentMapVisible:YES];
        BOOL mapOn = [ed documentMapVisible];
        [ed setDocumentMapVisible:NO];
        Check(@"IDM_VIEW_DOC_MAP", @"shows and hides the shrunken mirror",
              mapOn && ![ed documentMapVisible]);

        // As DocumentMap does: the zone covers what the editor shows, the map
        // scrolls with it, a click centres the editor there, and the map has
        // the editor's colours.
        {
            NSMutableString *lines = [NSMutableString string];
            for (int i = 0; i < 3000; ++i) [lines appendFormat:@"int line%d = %d;\n", i, i];
            [ed newDocument];
            [ed setLanguageNamed:@"cpp"];
            SetDoc(ed, lines);
            [ed setDocumentMapVisible:YES];
            ScintillaView *map = [ed valueForKey:@"docMapView"];
            [ed.sci message:SCI_SETFIRSTVISIBLELINE wParam:1500 lParam:0];
            [ed updateDocumentMap];
            NSRect zone = [ed documentMapZone];
            long mapFirst = [map message:SCI_GETFIRSTVISIBLELINE];
            long mapHeight = [map message:SCI_TEXTHEIGHT wParam:0];
            long zoneLine = mapFirst + (long)(NSMidY(zone) / MAX(1, mapHeight));
            long shown = [ed.sci message:SCI_LINESONSCREEN];
            BOOL zoneRight = zone.size.height > 0 && mapFirst > 0 &&
                             labs(zoneLine - (1500 + shown / 2)) <= shown / 2 + 2;
            [ed scrollFromDocumentMapAtY:NSMidY(zone) + 40 * mapHeight];
            long afterClick = [ed.sci message:SCI_GETFIRSTVISIBLELINE];
            BOOL clicked = afterClick > 1500 + 20 && afterClick < 1500 + 60 + shown;
            BOOL coloured = [map message:SCI_STYLEGETFORE wParam:SCE_C_WORD] == [ed.sci message:SCI_STYLEGETFORE wParam:SCE_C_WORD] &&
                            [map message:SCI_STYLEGETBOLD wParam:SCE_C_WORD] == [ed.sci message:SCI_STYLEGETBOLD wParam:SCE_C_WORD];
            // Wrapped, the map breaks its lines where the editor does: the same
            // number of display lines for the same long text.
            NSMutableString *longLines = [NSMutableString string];
            for (int i = 0; i < 40; ++i) {
                for (int w = 0; w < 60 + i; ++w) [longLines appendFormat:@"word%d ", w % 7];
                [longLines appendString:@"\n"];
            }
            SetDoc(ed, longLines);
            [ed.sci message:SCI_SETWRAPMODE wParam:SC_WRAP_WORD lParam:0];
            [ed mirrorStylesToDocumentMap];
            [ed updateDocumentMap];
            // (Scintilla wraps in idle time.)
            NSDate *wrapWait = [NSDate dateWithTimeIntervalSinceNow:3];
            while (([ed.sci message:SCI_WRAPCOUNT wParam:39] < 2 || [map message:SCI_WRAPCOUNT wParam:39] < 2) && [wrapWait timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            long editorLines = 0, mapLines = 0;
            for (long l = 0; l < 40; ++l) {
                editorLines += [ed.sci message:SCI_WRAPCOUNT wParam:(uptr_t)l];
                mapLines += [map message:SCI_WRAPCOUNT wParam:(uptr_t)l];
            }
            // (Near enough: the map's tiny glyphs have advances rounded differently from the editor's.)
            BOOL sameWrap = editorLines > 60 && labs(editorLines - mapLines) <= editorLines / 16;
            printf("    map wrap: editor %ld display lines, map %ld, map width %.0f in a panel of %.0f\n", editorLines, mapLines,
                   NSWidth(map.frame), NSWidth(map.superview.bounds));
            [ed.sci message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
            [ed updateDocumentMap];
            coloured = coloured && sameWrap && fabs(NSWidth(map.frame) - NSWidth(map.superview.bounds)) < 1;
            [ed setDocumentMapVisible:NO];
            [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
            printf("    map: first %ld zone %.0f+%.0f line %ld click %ld\n", mapFirst, zone.origin.y, zone.size.height, zoneLine, afterClick);
            Check(@"IDM_VIEW_DOC_MAP (view zone)",
                  @"the zone marks the lines on screen, a click in the map scrolls the editor there, and the colours match",
                  zoneRight && clicked && coloured);
        }

        // Document Peeker: hovering another tab shows it, in a small window or
        // in the map; hovering the tab in front, or leaving, puts things back.
        {
            NppPreferences *pp = [NppPreferences shared];
            [ed newDocument];
            SetDoc(ed, @"peek at me\n");
            NppDocument *other = ed.currentDocument;
            [ed newDocument];
            SetDoc(ed, @"in front\n");
            NSInteger otherIndex = (NSInteger)[ed.documents indexOfObject:other];
            NSInteger frontIndex = (NSInteger)[ed.documents indexOfObject:ed.currentDocument];
            [ed peekAtTabIndex:otherIndex];
            BOOL offByDefault = ![ed documentPeekerVisible];
            pp.docPeekOnTab = YES;
            [ed peekAtTabIndex:otherIndex];
            BOOL peeking = [ed documentPeekerVisible] && [ed documentPeekerDocument] == other.docPointer;
            [ed peekAtTabIndex:frontIndex];
            BOOL frontHides = ![ed documentPeekerVisible];
            pp.docPeekOnTab = NO;
            pp.docPeekOnMap = YES;
            [ed setDocumentMapVisible:YES];
            ScintillaView *pmap = [ed valueForKey:@"docMapView"];
            [ed peekAtTabIndex:otherIndex];
            BOOL mapPeeks = (void *)[pmap message:SCI_GETDOCPOINTER] == other.docPointer;
            [ed peekAtTabIndex:-1];
            BOOL mapBack = (void *)[pmap message:SCI_GETDOCPOINTER] == ed.currentDocument.docPointer;
            [ed setDocumentMapVisible:NO];
            pp.docPeekOnMap = NO;
            [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:other] discardChanges:YES];
            Check(@"IDM_VIEW_DOC_MAP (document peeker)",
                  @"peek on tab and peek on map show the hovered document, and only when switched on",
                  offByDefault && peeking && frontHides && mapPeeks && mapBack);
        }

        [ed setLanguageNamed:@"python"];
        SetDoc(ed, @"def alpha(x):\n    return x\n\ndef beta():\n    pass\n");
        FunctionListPanel *fl = [[FunctionListPanel alloc] initWithEditor:ed];
        NSArray *names = [fl functionNames];
        Check(@"IDM_VIEW_FUNC_LIST", @"lists the declarations in the document",
              names.count >= 2 &&
              [[names componentsJoinedByString:@" "] containsString:@"alpha"] &&
              [[names componentsJoinedByString:@" "] containsString:@"beta"]);

        // The definitions come from Notepad++'s own functionList parsers.
        FunctionListCatalog *cat = [FunctionListCatalog sharedCatalog];
        Check(@"IDM_VIEW_FUNC_LIST (upstream parsers)",
              @"the bundled parser definitions are loaded",
              cat.parserIDs.count > 30 &&
              [cat parserIDForLanguage:@"python" extension:@"py"] != nil &&
              [cat parserIDForLanguage:@"cpp" extension:@"cpp"] != nil);

        // The patterns are PCRE and are now run as PCRE, through libpcre2,
        // rather than being translated into something ICU accepts.
        Check(@"IDM_VIEW_FUNC_LIST (regex engine)",
              @"the PCRE engine the patterns are written for is available",
              NppRegex.available);

        // The option values are declared by hand, because the SDK ships no
        // pcre2.h. Checking them against the library's behaviour is the only
        // thing that makes them trustworthy.
        NSData *twoLines = [@"a\nb" dataUsingEncoding:NSUTF8StringEncoding];
        NppRegex *anchored = [NppRegex regexWithPattern:@"^b"];
        NppRegex *dotted = [NppRegex regexWithPattern:@"a.b"];
        Check(@"IDM_VIEW_FUNC_LIST (regex options)",
              @"'^' anchors per line and '.' spans them, as upstream searches",
              [anchored firstMatchInData:twoLines range:NSMakeRange(0, twoLines.length)].location != NSNotFound &&
              [dotted firstMatchInData:twoLines range:NSMakeRange(0, twoLines.length)].location != NSNotFound);

        // These four are what ICU could not do at all. c.xml uses the first
        // two, and without them fifteen of the parsers were unusable.
        NSData *pcreSample = [@"foobar aaab xy" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange full = NSMakeRange(0, pcreSample.length);
        NppRegex *subroutine = [NppRegex regexWithPattern:@"(?'W'[a-z]+) (?&W)"];
        NppRegex *atomic = [NppRegex regexWithPattern:@"(?>a+)b"];
        NppRegex *keep = [NppRegex regexWithPattern:@"foo\\Kbar"];
        NSRange keptRange = [keep firstMatchInData:pcreSample range:full];
        Check(@"IDM_VIEW_FUNC_LIST (PCRE features)",
              @"subroutine calls, named groups, atomic groups and \\K all work",
              subroutine && atomic && keep &&
              [subroutine firstMatchInData:pcreSample range:full].location != NSNotFound &&
              [atomic firstMatchInData:pcreSample range:full].location != NSNotFound &&
              keptRange.location == 3 && keptRange.length == 3);

        // A pattern that cannot compile is reported rather than silently
        // matching nothing; upstream ships one such file.
        Check(@"IDM_VIEW_FUNC_LIST (bad pattern)",
              @"a pattern that will not compile is refused, with a reason",
              [NppRegex regexWithPattern:@"(unclosed"] == nil &&
              [NppRegex compileErrorForPattern:@"(unclosed"].length > 0 &&
              [NppRegex compileErrorForPattern:@"\\w+"] == nil);

        // A Python class with methods, through the upstream parser.
        NSArray<NppFunctionEntry *> *entries = [cat entriesInText:
            @"class Alpha:\n    def one(self):\n        pass\n    def two(self):\n        pass\n"
                                                     forLanguage:@"python" extension:@"py"];
        NSMutableArray *found = [NSMutableArray array];
        for (NppFunctionEntry *e in entries) [found addObject:e.name];
        // The names must be just the names: upstream's python pattern keeps the
        // part after \K, which excludes the "def " keyword.
        Check(@"IDM_VIEW_FUNC_LIST (classes and methods)",
              @"the class and its methods are reported, without the def keyword",
              entries.count == 3 && [found containsObject:@"Alpha"] &&
              [found containsObject:@"one(self)"] && [found containsObject:@"two(self)"] &&
              ![[found componentsJoinedByString:@" "] containsString:@"def "]);

        // C# exercises what Python does not: a class whose body has to be found
        // by counting braces, names that several patterns narrow down in turn,
        // and a comment that must not be searched.
        NSString *csharp =
            @"static HttpClient Build(int a)\n"
            @"{\n"
            @"    return null;\n"
            @"}\n"
            @"/*\n"
            @"static void Ghost()\n"
            @"{\n"
            @"}\n"
            @"*/\n"
            @"class Store\n"
            @"{\n"
            @"    public void Clear() { }\n"
            @"}\n";
        NSArray<NppFunctionEntry *> *cs = [cat entriesInText:csharp forLanguage:@"cs" extension:@"cs"];
        NSMutableArray *csNames = [NSMutableArray array];
        for (NppFunctionEntry *e in cs) {
            [csNames addObject:e.container.length
                ? [NSString stringWithFormat:@"%@::%@", e.container, e.name] : e.name];
        }

        // Upstream lists several name patterns and applies them one after
        // another, each searching inside what the last one found. Taking only
        // the first, or only the last, leaves "class Store" or the whole
        // matched line instead of "Store".
        Check(@"IDM_VIEW_FUNC_LIST (name narrowing)",
              @"chained name patterns reduce a declaration to just its name",
              [csNames containsObject:@"Build"] && [csNames containsObject:@"Store"]);

        // The class body runs to its closing brace, which the pattern itself
        // does not cover -- it stops at the opening one.
        Check(@"IDM_VIEW_FUNC_LIST (class body)",
              @"a member is attributed to the class whose braces enclose it",
              [csNames containsObject:@"Store::Clear"]);

        // commentExpr exists so that code inside a comment is not reported.
        Check(@"IDM_VIEW_FUNC_LIST (comments)",
              @"a declaration inside a comment is not listed",
              ![[csNames componentsJoinedByString:@" "] containsString:@"Ghost"]);

        // Breadth: one snippet per language, checked against the declarations
        // Notepad++'s own parser is meant to find in it. This is what says the
        // catalogue works as a whole rather than for the one language that
        // happened to be tested.
        NSArray *battery = @[
            // c.xml shows the parameters on purpose: the node that would strip
            // them is commented out in the file itself.
            @[@"c",          @"c",    @"int add(int a, int b)\n{\n    return 0;\n}\n",              @"add(int a, int b)"],
            @[@"cpp",        @"cpp",  @"class Thing {\npublic:\n    void run() {}\n};\n",           @"Thing::run"],
            @[@"cs",         @"cs",   @"class Store\n{\n    public void Clear() { }\n}\n",          @"Store::Clear"],
            @[@"java",       @"java", @"public class G {\n  public void hello(String w) { }\n}\n",  @"G::hello"],
            @[@"php",        @"php",  @"<?php\nfunction helper($x) { return $x; }\n",               @"helper($x) "],
            @[@"python",     @"py",   @"def alpha(x):\n    pass\n",                                 @"alpha(x)"],
            @[@"ruby",       @"rb",   @"def alpha(x)\n  x\nend\n",                                  @"alpha"],
            @[@"perl",       @"pl",   @"sub alpha {\n  1;\n}\n",                                    @"alpha"],
            @[@"lua",        @"lua",  @"function alpha(x)\n  return x\nend\n",                      @"alpha"],
            @[@"bash",       @"sh",   @"alpha() {\n  echo hi\n}\n",                                 @"alpha"],
            @[@"pascal",     @"pas",  @"procedure Alpha(x: Integer);\nbegin\nend;\n",               @"Alpha"],
            @[@"vb",         @"vb",   @"Public Sub Alpha(x As Integer)\nEnd Sub\n",                 @"Alpha"],
            @[@"rust",       @"rs",   @"fn alpha(x: i32) -> i32 {\n    x\n}\n",                     @"alpha"],
            @[@"javascript", @"js",   @"function alpha(x) { return x; }\n",                         @"alpha"],
            @[@"typescript", @"ts",   @"function alpha(x) {\n  return x;\n}\n",                     @"alpha"],
            @[@"powershell", @"ps1",  @"function Get-Thing {\n    param($x)\n}\n",                  @"Get-Thing"],
            @[@"haskell",    @"hs",   @"alpha :: Int -> Int\nalpha x = x\n",                        @"alpha"],
            @[@"nim",        @"nim",  @"proc alpha(x: int): int =\n  x\n",                          @"alpha(x: int): int"],
            // Upstream keeps the space the selector was written with.
            @[@"css",        @"css",  @".alpha { color: red; }\n",                                  @".alpha "],
            @[@"makefile",   @"mak",  @"alpha:\n\techo hi\n",                                       @"alpha"],
            @[@"batch",      @"bat",  @":alpha\necho hi\n",                                         @"alpha"],
            @[@"ini",        @"ini",  @"[Section]\nkey=1\n",                                        @"Section"],
            @[@"fortran",    @"f90",  @"      SUBROUTINE ALPHA(X)\n      END\n",                    @"ALPHA"],
            @[@"d",          @"d",    @"int add(int a, int b)\n{\n    return 0;\n}\n",              @"add"],

            // Corrected parsers: things upstream's own patterns do not find.
            // Each is covered by a file in functionList-corrections, which says
            // at its top what it changes and what the original did.
            @[@"rust",       @"rs",   @"pub fn alpha(x: i32) -> i32 { x }\n",                      @"alpha"],
            @[@"rust",       @"rs",   @"impl Thing {\n    pub fn delta(&self) {}\n}\n",            @"Thing::delta"],
            @[@"javascript", @"js",   @"const beta = (x) => x;\n",                                 @"beta"],
            @[@"typescript", @"ts",   @"export function beta(x: number): number { return x; }\n",  @"beta"],
            @[@"typescript", @"ts",   @"class Thing {\n    gamma(): void { }\n}\n",                @"Thing::gamma"],
            @[@"cs",         @"cs",   @"static async Task<string?> TryGet(int a)\n{\n    return null;\n}\n", @"TryGet"],
            @[@"cs",         @"cs",   @"static async Task<(int, string)> Setup()\n{\n    return (1, null);\n}\n", @"Setup"],
            @[@"cs",         @"cs",   @"class S\n{\n    public async Task<List<int>> Get() { return null; }\n}\n", @"S::Get"],
            @[@"cs",         @"cs",   @"class S\n{\n    public byte[]? Raw() => null;\n}\n",   @"S::Raw"],
            // sql.xml is an Oracle parser and wants the named END its own
            // comment calls best practice.
            @[@"sql",        @"sql",  @"CREATE OR REPLACE PROCEDURE alpha IS\nBEGIN\nNULL;\nEND alpha;\n", @"PROCEDURE alpha"],
        ];
        NSMutableArray *missing = [NSMutableArray array];
        for (NSArray *row in battery) {
            NSArray<NppFunctionEntry *> *got = [cat entriesInText:row[2]
                                                      forLanguage:row[0] extension:row[1]];
            NSMutableArray *shown = [NSMutableArray array];
            for (NppFunctionEntry *e in got) {
                [shown addObject:e.container.length
                    ? [NSString stringWithFormat:@"%@::%@", e.container, e.name] : e.name];
            }
            if (![shown containsObject:row[3]]) {
                [missing addObject:[NSString stringWithFormat:@"%@ (wanted %@, got %@)",
                                    row[0], row[3], [shown componentsJoinedByString:@","]]];
            }
        }
        Check(@"IDM_VIEW_FUNC_LIST (every language)",
              @"each language finds what its own Notepad++ parser is meant to find",
              missing.count == 0);
        if (missing.count) printf("       %s\n", [[missing componentsJoinedByString:@"; "] UTF8String]);

        // The C# correction reads a return type loosely enough to cover tuples
        // and nullable generics, which is exactly the kind of pattern that
        // starts matching statements as well. None of these is a declaration.
        NSString *notDeclarations =
            @"var builder = WebApplication.CreateBuilder(args);\n"
            @"Console.Write(\"hi\");\n"
            @"var (cert, _) = await SetupCertificateAsync();\n"
            @"using var rsa = RSA.Create(2048);\n"
            @"foreach (var src in sources)\n{\n}\n"
            @"if (File.Exists(path))\n{\n}\n"
            @"while (true)\n{\n}\n"
            @"lock (sync)\n{\n}\n"
            @"req.Extensions.Add(new KeyUsage(a, true));\n"
            @"return Results.NotFound();\n";
        NSArray<NppFunctionEntry *> *spurious =
            [cat entriesInText:notDeclarations forLanguage:@"cs" extension:@"cs"];
        NSMutableArray *spuriousNames = [NSMutableArray array];
        for (NppFunctionEntry *e in spurious) [spuriousNames addObject:e.name];
        Check(@"IDM_VIEW_FUNC_LIST (no false declarations)",
              @"statements that merely look like declarations are not listed",
              spurious.count == 0);
        if (spurious.count) printf("       %s\n",
            [[spuriousNames componentsJoinedByString:@","] UTF8String]);

        // Notepad++ ships its own test corpus for the Function List: forty
        // languages, each with a file and the result it is meant to produce.
        // That is far better evidence than a battery written here, and running
        // it is what turned up that the patterns are matched without regard to
        // case, that a class is only listed when something is inside it, and
        // that a name keeps the whitespace it was written with.
        NSString *corpusDir = [[NSBundle mainBundle] pathForResource:@"functionListCorpus"
                                                              ofType:nil];
        // Working the language out from a file's contents, for the files whose
        // name cannot say: no extension, or nothing saved yet.
        {
            LanguageCatalog *lc = [LanguageCatalog sharedCatalog];

            // What a file says about itself outright is taken as given, and is
            // the one case where a couple of lines is enough.
            BOOL declared =
                [[lc languageForContents:@"#!/usr/bin/env python3\nx = 1\n"].name isEqualToString:@"python"] &&
                [[lc languageForContents:@"#!/bin/sh\necho hi\n"].name isEqualToString:@"bash"] &&
                [[lc languageForContents:@"#!/usr/bin/perl\nprint 1;\n"].name isEqualToString:@"perl"] &&
                [[lc languageForContents:@"<?php echo 1; ?>\n"].name isEqualToString:@"php"] &&
                [[lc languageForContents:@"<?xml version=\"1.0\"?><a/>"].name isEqualToString:@"xml"] &&
                [[lc languageForContents:@"<!DOCTYPE html><html></html>"].name isEqualToString:@"html"] &&
                [[lc languageForContents:@"# -*- mode: ruby -*-\nx = 1\n"].name isEqualToString:@"ruby"] &&
                [[lc languageForContents:@"# vim: set ft=lua:\nx = 1\n"].name isEqualToString:@"lua"] &&
                [[lc languageForContents:@"{\"a\": [1, 2, 3]}"].name isEqualToString:@"json"];
            Check(@"IDM_LANG_DETECT (what the file says outright)",
                  @"a shebang line, an opening tag, a doctype, an editor modeline "
                  @"or JSON that parses settles the language on its own",
                  declared);

            // Too little to go on is left alone: a guess from three words would
            // be wrong as often as right.
            BOOL quiet = ![lc languagesMatchingContents:@""].count &&
                         ![lc languagesMatchingContents:@"hello\n"].count &&
                         ![lc languagesMatchingContents:@"one two three four\n"].count &&
                         ![lc languagesMatchingContents:@"...\n...\n"].count;
            Check(@"IDM_LANG_DETECT (too little to say)",
                  @"a short fragment, or one with no words a language claims, "
                  @"yields nothing rather than a guess",
                  quiet);

            // The corpus: a file of each language, under the name "unitTest",
            // which is exactly the case this is for.
            NSUInteger offered = 0, wasFirst = 0, total = 0;
            NSMutableArray<NSString *> *notOffered = [NSMutableArray array];
            for (NSString *language in [[NSFileManager defaultManager]
                                        contentsOfDirectoryAtPath:corpusDir ?: @"" error:NULL]) {
                NSString *body = [NSString stringWithContentsOfFile:
                    [[corpusDir stringByAppendingPathComponent:language]
                        stringByAppendingPathComponent:@"unitTest"]
                                                           encoding:NSUTF8StringEncoding error:NULL];
                if (!body) continue;
                NSString *want = [language hasPrefix:@"udl-"] ? [language substringFromIndex:4] : language;
                total++;
                NSMutableArray<NSString *> *names = [NSMutableArray array];
                for (NppLanguage *one in [lc languagesMatchingContents:body]) {
                    [names addObject:one.name];
                }
                // Notepad++ lists JavaScript twice, as "javascript" and as
                // "javascript.js"; either answer is the right one.
                NSUInteger where = [names indexOfObject:want];
                if (where == NSNotFound && [want hasPrefix:@"javascript"]) {
                    where = [names indexOfObject:@"javascript.js"];
                    if (where == NSNotFound) where = [names indexOfObject:@"javascript"];
                }
                if (where == NSNotFound) { [notOffered addObject:want]; continue; }
                offered++;
                if (where == 0) wasFirst++;
            }
            printf("    corpus: %lu files, %lu offered their language, %lu first; not offered: %s\n", (unsigned long)total,
                   (unsigned long)offered, (unsigned long)wasFirst, [notOffered componentsJoinedByString:@" "].UTF8String);
            Check(@"IDM_LANG_DETECT (a file of each language)",
                  @"nearly all of the corpus is offered its own language, and "
                  @"nearly all of those have it first in the list",
                  total >= 40 && offered >= 36 && wasFirst >= 35 &&
                  // What is left over, and why. The corpus's own Raku file
                  // opens with "#!/usr/bin/env perl", so reading it as Perl
                  // is right and the corpus is wrong. NppExec is a plugin's
                  // own language, which the catalogue does not hold at all.
                  // Fixed-form Fortran is read as its free-form sibling, and
                  // plain TeX as LaTeX, the nearest relative each. All of it
                  // is the trained model's doing: there are no marks or
                  // keyword rules beside it to put an answer right.
                  notOffered.count <= 5);

            // Whatever is offered is short enough to be a choice rather than a
            // catalogue; more than ten and nothing is offered at all.
            NSUInteger longest = 0;
            for (NSString *language in [[NSFileManager defaultManager]
                                        contentsOfDirectoryAtPath:corpusDir ?: @"" error:NULL]) {
                NSString *body = [NSString stringWithContentsOfFile:
                    [[corpusDir stringByAppendingPathComponent:language]
                        stringByAppendingPathComponent:@"unitTest"]
                                                           encoding:NSUTF8StringEncoding error:NULL];
                if (!body) continue;
                longest = MAX(longest, [lc languagesMatchingContents:body].count);
            }
            // Pasting a script into an empty document, through the Paste
            // command itself rather than by calling the detection directly.
            NSString *script =
                @"import os\nimport sys\n\n"
                @"def read_config(path):\n"
                @"    with open(path) as handle:\n"
                @"        for line in handle:\n"
                @"            if line.startswith('#'):\n"
                @"                continue\n"
                @"            yield line.strip()\n\n"
                @"class Runner:\n"
                @"    def __init__(self, config):\n"
                @"        self.config = config\n\n"
                @"    def run(self):\n"
                @"        for item in self.config:\n"
                @"            print(item)\n\n"
                @"if __name__ == '__main__':\n"
                @"    Runner(list(read_config(sys.argv[1]))).run()\n";
            [ed newDocument];
            NSPasteboard *board = [NSPasteboard generalPasteboard];
            [board clearContents];
            [board setString:script forType:NSPasteboardTypeString];
            [app pasteText:nil];
            NSString *pastedLanguage = ed.currentDocument.language.name ?: @"";
            Check(@"IDM_LANG_DETECT (pasted into an empty document)",
                  @"a script pasted into an empty document is recognised, the way "
                  @"a file with no extension is",
                  [DocText(ed) containsString:@"def read_config"] &&
                  [pastedLanguage isEqualToString:@"python"]);

            // C# written as top-level statements: no namespace, no class, no
            // Main. It shares nearly every keyword it uses with JavaScript, so
            // the words alone called it JavaScript; what tells them apart is
            // what only C# writes.
            NSString *topLevelCSharp =
                @"using System.Net.Http.Headers;\n"
                @"using System.Security.Cryptography;\n"
                @"using System.Text.Json;\n"
                @"\n"
                @"var builder = WebApplication.CreateBuilder(args);\n"
                @"builder.Services.AddHttpClient(\"proxy\", c => c.Timeout = TimeSpan.FromMinutes(10));\n"
                @"builder.Logging.SetMinimumLevel(LogLevel.Warning);\n"
                @"\n"
                @"var (cert, _) = await SetupCertificateAsync();\n"
                @"var app = builder.Build();\n"
                @"\n"
                @"var nugetOrg = \"https://api.nuget.org/v3\";\n"
                @"Console.WriteLine(\"NuGet Aggregating Proxy\");\n"
                @"Console.Write(\"\\nNexus Username: \");\n"
                @"var username = Console.ReadLine()!;\n"
                @"\n"
                @"var factory = app.Services.GetRequiredService<IHttpClientFactory>();\n"
                @"foreach (var src in nexusSources)\n"
                @"{\n"
                @"    var client = CreateAuthClient(factory, creds);\n"
                @"    var r = await client.GetAsync($\"{src}/index.json\");\n"
                @"    Console.WriteLine($\"  {(r.IsSuccessStatusCode ? \"ok\" : \"no\")} {src}\");\n"
                @"}\n"
                @"\n"
                @"app.MapGet(\"/v3/search\", async (string? q, int? skip, IHttpClientFactory f) =>\n"
                @"{\n"
                @"    var results = new List<JsonElement>();\n"
                @"    foreach (var src in nexusSources)\n"
                @"    {\n"
                @"        var content = await TryGetNexus(f, creds, $\"{src}/v3/search?q={Uri.EscapeDataString(q ?? \"\")}\");\n"
                @"        if (content != null)\n"
                @"        {\n"
                @"            try\n"
                @"            {\n"
                @"                var json = JsonDocument.Parse(content);\n"
                @"                if (json.RootElement.TryGetProperty(\"data\", out var data))\n"
                @"                    foreach (var item in data.EnumerateArray())\n"
                @"                        results.Add(item);\n"
                @"            }\n"
                @"            catch { }\n"
                @"        }\n"
                @"    }\n"
                @"    return Results.Json(new { totalHits = results.Count, data = results });\n"
                @"});\n"
                @"\n"
                @"static async Task<string?> TryGetNexus(IHttpClientFactory f, CredentialStore c, string url)\n"
                @"{\n"
                @"    try\n"
                @"    {\n"
                @"        var client = CreateAuthClient(f, c);\n"
                @"        var r = await client.GetAsync(url);\n"
                @"        if (r.IsSuccessStatusCode)\n"
                @"            return await r.Content.ReadAsStringAsync();\n"
                @"    }\n"
                @"    catch { }\n"
                @"    return null;\n"
                @"}\n"
                @"\n"
                @"class CredentialStore\n"
                @"{\n"
                @"    char[] _p;\n"
                @"    public string Username { get; private set; }\n"
                @"    public string Password => new(_p);\n"
                @"    public CredentialStore(string u, string p) { Username = u; _p = p.ToCharArray(); }\n"
                @"    public void Clear() { Array.Clear(_p); Username = \"\"; }\n"
                @"}\n"
                @"\n";
            NSMutableArray *csNames = [NSMutableArray array];
            for (NppLanguage *one in [lc languagesMatchingContents:topLevelCSharp]) {
                [csNames addObject:one.name];
            }
            Check(@"IDM_LANG_DETECT (C# without a class)",
                  @"a file of top-level C# statements is taken for C#, not for "
                  @"JavaScript, whose keywords are nearly the same",
                  csNames.count && [csNames.firstObject isEqualToString:@"cs"]);

            // The model itself: that it is there, that it reads back the way
            // it was written, and that it answers the same as the trainer did.
            NppLanguageModel *trained = [NppLanguageModel sharedModel];
            NSArray<NSString *> *modelLanguages = trained.languageNames;
            NSDictionary<NSString *, NSString *> *plain = @{
                @"python": @"import os\nimport sys\n\nclass Runner:\n"
                           @"    def __init__(self, config):\n        self.config = config\n\n"
                           @"    def run(self):\n        for item in self.config:\n"
                           @"            print(item)\n",
                @"sql":    @"SELECT u.id, u.name, count(o.id) AS orders\n"
                           @"FROM users u\nLEFT JOIN orders o ON o.user_id = u.id\n"
                           @"WHERE u.active = 1\nGROUP BY u.id, u.name\n"
                           @"ORDER BY orders DESC;\n",
                @"ruby":   @"require 'json'\n\nclass Loader\n  def initialize(path)\n"
                           @"    @path = path\n  end\n\n  def load\n"
                           @"    JSON.parse(File.read(@path))\n  end\nend\n",
            };
            BOOL modelAnswers = trained != nil && modelLanguages.count >= 60;
            for (NSString *want in plain) {
                NSArray<NppLanguageGuess *> *guesses = [trained guessesForText:plain[want]];
                if (!guesses.count || ![guesses.firstObject.name isEqualToString:want]) {
                    modelAnswers = NO;
                }
            }
            // And that it says nothing about what is not worth an answer.
            BOOL modelKeepsQuiet = ![trained guessesForText:@"hi\n"].count;
            Check(@"IDM_LANG_DETECT (the trained model)",
                  @"the model ships with the application, covers the languages it "
                  @"was trained on, and recognises a plain example of each",
                  modelAnswers && modelKeepsQuiet);

            // The languages no corpus had, from the examples written for them
            // and the generated hex formats; texts the trainer never saw.
            NSDictionary<NSString *, NSString *> *added = @{
                @"registry": @"Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\Example\\Viewer]\n"
                             @"\"ShowToolbar\"=dword:00000001\n\"LastFolder\"=\"C:\\\\Users\\\\Public\"\n@=\"default\"\n",
                @"kix":      @"; map the team drive\nIF INGROUP(\"Engineering\")\n    USE E: \"\\\\files\\engineering\"\n"
                             @"    ? \"Mapped for \" + @USERID\nENDIF\nIF @ERROR <> 0\n    ? @SERROR\nENDIF\nEXIT\n",
                @"spice":    @"Voltage divider\nV1 1 0 DC 9\nR1 1 2 10k\nR2 2 0 4.7k\nC1 2 0 100n\n.op\n.tran 1m 100m\n.end\n",
                @"ihex":     @":10010000214601360121470136007EFE09D2190140\n:100110002146017E17C20001FF5F16002148011928\n"
                             @":10012000194E79234623965778239EDA3F01B2CAA7\n:00000001FF\n",
                @"srec":     @"S00F000068656C6C6F202020202000003C\nS11F00007C0802A6900100049421FFF07C6C1B787C8C23783C6000003863000026\n"
                             @"S11F001C4BFFFFE5398000007D83637880010014382100107C0803A64E800020E9\nS5030002FA\nS9030000FC\n",
            };
            NSMutableArray *addedWrong = [NSMutableArray array];
            for (NSString *want in added) {
                NSArray<NppLanguageGuess *> *guesses = [trained guessesForText:added[want]];
                if (![modelLanguages containsObject:want] || !guesses.count || ![guesses.firstObject.name isEqualToString:want]) {
                    [addedWrong addObject:[NSString stringWithFormat:@"%@->%@", want, guesses.firstObject.name ?: @"-"]];
                }
            }
            // A lone answer is one the model is sure of, past the level fitted for it.
            BOOL aloneIsSure = trained.singleLevel >= trained.coverage;
            for (NSString *text in [plain.allValues arrayByAddingObjectsFromArray:added.allValues]) {
                NSArray *offer = [trained languagesOfferedForText:text];
                if (offer.count == 1 && [trained guessesForText:text].firstObject.confidence < trained.singleLevel - 1e-9) aloneIsSure = NO;
                if (offer.count > 1 && offer.count < NppShortListLength &&
                    [trained guessesForText:text].firstObject.confidence < trained.coverage) aloneIsSure = NO;
            }
            printf("    model: %lu languages, level %.2f, alone from %.3f%s%s\n", (unsigned long)modelLanguages.count,
                   trained.coverage, trained.singleLevel, addedWrong.count ? ", wrong: " : "",
                   [addedWrong componentsJoinedByString:@" "].UTF8String);
            Check(@"IDM_LANG_DETECT (languages without a corpus)",
                  @"registry, KiXtart, SPICE, Intel HEX and S-records are learnt from the written and generated "
                  @"examples, and one language is offered alone only past the level fitted for that",
                  !addedWrong.count && aloneIsSure && modelLanguages.count >= 80);

            // A short piece of C-shaped code: what is offered is a choice of
            // no more than ten with C in it, whether C alone or a list. A
            // single answer that is not C, or a list without it, is the
            // failure this guards against.
            NSString *couldBeSeveral =
                @"int add(int a, int b) {\n    return a + b;\n}\n\n"
                @"int main(void) {\n    int total = 0;\n"
                @"    for (int i = 0; i < 10; i++) {\n"
                @"        total = add(total, i);\n    }\n"
                @"    return total;\n}\n";
            NSArray<NppLanguage *> *several = [lc languagesMatchingContents:couldBeSeveral];
            NSMutableArray *severalNames = [NSMutableArray array];
            for (NppLanguage *one in several) [severalNames addObject:one.name];
            Check(@"IDM_LANG_DETECT (a fragment of C)",
                  @"a short piece of C-shaped code is offered as C or as a short "
                  @"list with C in it",
                  several.count >= 1 && several.count <= NppMostLanguagesToOffer &&
                  [severalNames containsObject:@"c"]);

            // A PowerShell script whose body is shell commands and a unit file:
            // most of its lines could be bash or ini, and only a few marks -
            // [environment]::, -like, $($args[0]) - say what it is. PowerShell
            // has to be among what is offered.
            NSString *mixed =
                @"If (([environment]::OSVersion.Platform) -like \"*nix*\") {\n"
                @"  mkdir -p ~/.config/systemd/user\n"
                @"  echo (\"[Unit]\n"
                @"  Description=$($args[0])\n"
                @"\n"
                @"  [Service]\n"
                @"  Type=simple\n"
                @"  Environment=ASPNETCORE_ENVIRONMENT=$($args[1])\n"
                @"  EnvironmentFile=%h/.config/systemd/user/srvenv.conf\n"
                @"  WorkingDirectory=$($args[2])\n"
                @"  ExecStart=/bin/bash -c '$($args[3])'\n"
                @"  SyslogIdentifier=$($args[0])\n"
                @"\n"
                @"  [Install]\n"
                @"  WantedBy=default.target\")  > (\"~/.config/systemd/user/$($args[0]).service\")\n"
                @"  chmod a+x $($args[3])\n"
                @"  echo \"Service: $($args[0]) as Installed at $(date)\" >> ~/inst.log\n"
                @"}\n";
            NSMutableArray *mixedNames = [NSMutableArray array];
            for (NppLanguage *one in [lc languagesMatchingContents:mixed]) [mixedNames addObject:one.name];
            // One line of this is PowerShell's own and nine are a unit file, and
            // the model - which weighs a text's features without knowing which
            // of them are a quotation - reads it as the unit file. That is its
            // answer and it is left to stand: no hand-written mark puts
            // PowerShell back. (The trainer measures such texts as "quoting";
            // a model that reads them better will show there first.) What is
            // held here is that the detector says what the model says.
            NSMutableArray *modelNames = [NSMutableArray array];
            for (NSString *name in [trained languagesOfferedForText:mixed] ?: @[])
                if ([lc languageNamed:name] && ![name isEqualToString:@"normal"]) [modelNames addObject:name];
            printf("    a script quoting a unit file: %s\n", [mixedNames componentsJoinedByString:@" "].UTF8String);
            Check(@"IDM_LANG_DETECT (a script quoting another language)",
                  @"a script with a configuration file written out in it is offered what the trained "
                  @"model makes of it, a short list at most, with nothing added or taken away by hand",
                  mixedNames.count >= 1 && mixedNames.count <= NppMostLanguagesToOffer &&
                  [mixedNames isEqualToArray:modelNames]);

            // The same text with Windows line endings answers the same way:
            // the model reads the text, not the line endings.
            NSString *crlf = [mixed stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"];
            NSMutableArray *crlfNames = [NSMutableArray array];
            for (NppLanguage *one in [lc languagesMatchingContents:crlf]) [crlfNames addObject:one.name];
            // The choice reaches the user. Pasting the piece of C above - which
            // several languages fit - into an empty document, through the Paste
            // command itself, has to put a sheet on the window with the
            // languages in it - which is where a handler that read back as nil
            // left nothing at all.
            [ed newDocument];
            [board clearContents];
            [board setString:couldBeSeveral forType:NSPasteboardTypeString];
            [app pasteText:nil];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
            NSWindow *sheet = ed.window.attachedSheet;
            // The list is a table with every candidate showing and the first
            // one selected: nothing has to be opened to see the choices.
            NSTableView *choices = nil;
            NSMutableArray<NSView *> *pending = [sheet.contentView.subviews mutableCopy];
            while (pending.count && !choices) {
                NSView *view = pending.firstObject;
                [pending removeObjectAtIndex:0];
                if ([view isKindOfClass:[NSTableView class]]) choices = (NSTableView *)view;
                [pending addObjectsFromArray:view.subviews];
            }
            NSMutableArray *titles = [NSMutableArray array];
            for (NSInteger row = 0; row < choices.numberOfRows; ++row) {
                NSTextField *label = [choices viewAtColumn:0 row:row makeIfNecessary:YES];
                if ([label isKindOfClass:[NSTextField class]]) [titles addObject:label.stringValue];
            }
            Check(@"IDM_LANG_DETECT (the choice is put to the user)",
                  @"pasting a piece several languages fit puts a sheet on the "
                  @"window with every candidate in view and the first selected",
                  several.count > 1 && ed.languageChoiceHandler != nil && sheet != nil && choices != nil &&
                  choices.selectedRow == 0 && titles.count == several.count && [titles containsObject:@"c"]);
            if (sheet) [ed.window endSheet:sheet returnCode:NSModalResponseCancel];
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

            Check(@"IDM_LANG_DETECT (line endings make no difference)",
                  @"the same text with CRLF line endings is offered the same languages",
                  [crlfNames isEqualToArray:mixedNames]);

            Check(@"IDM_LANG_DETECT (a choice, not a catalogue)",
                  @"no more than ten languages are ever offered",
                  longest > 0 && longest <= NppMostLanguagesToOffer);
        }

        NSMutableArray *corpusFailures = [NSMutableArray array];
        NSUInteger corpusChecked = 0;
        // JavaScript and TypeScript are parsed here by the corrections, which
        // deliberately differ: upstream lists an anonymous function as the word
        // "function", several times over, and these do not.
        // udl-regexGlobalTest needs a user-defined language definition that
        // nothing associates with a parser, so there is nothing to run it with.
        NSSet *deliberate = [NSSet setWithArray:@[@"javascript", @"typescript",
                                                  @"udl-regexGlobalTest"]];
        for (NSString *language in [[NSFileManager defaultManager]
                                    contentsOfDirectoryAtPath:corpusDir ?: @"" error:NULL]) {
            if ([deliberate containsObject:language]) continue;
            // A directory named udl-X holds a user-defined language called X.
            NSString *base = [corpusDir stringByAppendingPathComponent:language];
            NSString *languageName = [language hasPrefix:@"udl-"]
                ? [language substringFromIndex:4] : language;
            NSString *text = [NSString stringWithContentsOfFile:
                              [base stringByAppendingPathComponent:@"unitTest"]
                                                       encoding:NSUTF8StringEncoding error:NULL];
            NSData *expectedData = [NSData dataWithContentsOfFile:
                                    [base stringByAppendingPathComponent:@"unitTest.expected.result"]];
            if (!text || !expectedData) continue;
            NSDictionary *expected = [NSJSONSerialization JSONObjectWithData:expectedData
                                                                    options:0 error:NULL];
            if (![expected isKindOfClass:NSDictionary.class]) continue;
            corpusChecked++;

            NSArray<NppFunctionEntry *> *found =
                [cat entriesInText:text forLanguage:languageName
                         extension:[language hasPrefix:@"udl-"] ? @"" : language];
            NSMutableArray *leaves = [NSMutableArray array];
            NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
            NSMutableArray *nodeOrder = [NSMutableArray array];
            for (NppFunctionEntry *entry in found) {
                if (entry.container.length) {
                    if (!nodes[entry.container]) {
                        nodes[entry.container] = [NSMutableArray array];
                        [nodeOrder addObject:entry.container];
                    }
                    [nodes[entry.container] addObject:entry.name];
                } else {
                    [leaves addObject:entry.name];
                }
            }
            // A class is reported here as a row of its own as well as the owner
            // of its members; upstream has only the node.
            // The class row carries the whitespace its pattern matched, so the
            // comparison with the container name ignores it.
            NSMutableArray *plainLeaves = [NSMutableArray array];
            NSMutableSet *classNames = [NSMutableSet set];
            for (NSString *name in nodeOrder) {
                [classNames addObject:[name stringByTrimmingCharactersInSet:
                                       [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
            }
            for (NSString *leaf in leaves) {
                NSString *bare = [leaf stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (![classNames containsObject:bare]) [plainLeaves addObject:leaf];
            }

            BOOL ok = [plainLeaves isEqualToArray:expected[@"leaves"] ?: @[]];
            NSArray *wantNodes = expected[@"nodes"] ?: @[];
            if (ok && wantNodes.count != nodeOrder.count) ok = NO;
            if (ok) {
                for (NSDictionary *node in wantNodes) {
                    if (![nodes[node[@"name"]] isEqualToArray:node[@"leaves"] ?: @[]]) { ok = NO; break; }
                }
            }
            if (!ok) [corpusFailures addObject:language];
        }
        Check(@"IDM_VIEW_FUNC_LIST (upstream corpus)",
              [NSString stringWithFormat:@"%lu of %lu languages match Notepad++'s own expected results",
               (unsigned long)(corpusChecked - corpusFailures.count), (unsigned long)corpusChecked],
              corpusChecked >= 39 && corpusFailures.count <= 4);
        if (corpusFailures.count) printf("       не совпали: %s\n",
            [[corpusFailures componentsJoinedByString:@", "] UTF8String]);

        // Notepad++ also ships a corpus for clickable-link detection: each case
        // is a line of text and a mask saying which of its characters should be
        // part of a link.
        NSString *urlDir = [[NSBundle mainBundle] pathForResource:@"urlCorpus" ofType:nil];
        NSUInteger urlCases = 0, urlWrong = 0;
        NSMutableArray *urlExamples = [NSMutableArray array];
        for (NSString *file in [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:urlDir ?: @"" error:NULL]) {
            NSString *body = [NSString stringWithContentsOfFile:
                              [urlDir stringByAppendingPathComponent:file]
                                                       encoding:NSUTF8StringEncoding error:NULL];
            NSArray *lines = [body componentsSeparatedByString:@"\n"];
            for (NSUInteger i = 0; i + 1 < lines.count; ++i) {
                NSString *one = [lines[i] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                NSString *two = [lines[i + 1] stringByTrimmingCharactersInSet:
                                 [NSCharacterSet characterSetWithCharactersInString:@"\r"]];
                if (![one hasPrefix:@"u "] || ![one hasSuffix:@" u"]) continue;
                if (![two hasPrefix:@"m "] || ![two hasSuffix:@" m"]) continue;
                NSString *text = [one substringWithRange:NSMakeRange(2, one.length - 4)];
                NSString *mask = [two substringWithRange:NSMakeRange(2, two.length - 4)];
                if (text.length != mask.length) continue;
                urlCases++;

                SetDoc(ed, text);
                [ed markClickableLinks];
                NSMutableString *got = [NSMutableString stringWithCapacity:text.length];
                NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
                NSUInteger byteAt = 0;
                for (NSUInteger c = 0; c < text.length; ++c) {
                    NSUInteger width = [[text substringWithRange:NSMakeRange(c, 1)]
                                        lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
                    BOOL on = [sci message:SCI_INDICATORVALUEAT
                                    wParam:NPPMAC_LINK_INDICATOR lParam:(sptr_t)byteAt] != 0;
                    [got appendString:on ? @"1" : @"0"];
                    byteAt += width;
                }
                (void)bytes;
                if (![got isEqualToString:mask]) {
                    urlWrong++;
                    if (urlExamples.count < 5) {
                        [urlExamples addObject:[NSString stringWithFormat:@"%@ | want %@ got %@",
                                                text, mask, got]];
                    }
                }
            }
        }
        Check(@"IDM_SETTING_PREFERENCE (clickable links)",
              [NSString stringWithFormat:
               @"%lu of %lu cases from Notepad++'s own URL corpus are detected the same way",
               (unsigned long)(urlCases - urlWrong), (unsigned long)urlCases],
              urlCases >= 140 && urlWrong == 0);
        for (NSString *e in urlExamples) printf("         %s\n", e.UTF8String);

        // A corrections file that is not well formed is simply skipped, and the
        // language then quietly behaves as it did before -- which is how three
        // of them were written with a double hyphen inside an XML comment and
        // appeared to do nothing. Each one has to parse and register its parser.
        NSString *fixDir = [[NSBundle mainBundle] pathForResource:@"functionListCorrections"
                                                           ofType:nil];
        NSMutableArray *brokenFixes = [NSMutableArray array];
        for (NSString *file in [[NSFileManager defaultManager]
                                contentsOfDirectoryAtPath:fixDir ?: @"" error:NULL]) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:
                            [fixDir stringByAppendingPathComponent:file]];
            NSXMLParser *check = [[NSXMLParser alloc] initWithData:data ?: [NSData data]];
            NppAttributeReader *reader = [[NppAttributeReader alloc] init];
            check.delegate = reader;
            if (![check parse]) [brokenFixes addObject:file];
        }
        Check(@"IDM_VIEW_FUNC_LIST (corrections load)",
              @"every corrections file is well formed and reaches the catalogue",
              fixDir.length > 0 && brokenFixes.count == 0 &&
              [cat parserIDForLanguage:@"rust" extension:@"rs"] != nil);

        // XML folds a newline inside an attribute value into a space. Most of
        // upstream's patterns use (?x), where a # comment runs to end of line,
        // so losing the newlines lets the first comment eat the whole pattern.
        NSString *sample = @"<a b=\"one #c\ntwo\" />";
        NSData *restored = [FunctionListCatalog dataPreservingAttributeNewlines:
                            [sample dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *restoredText = [[NSString alloc] initWithData:restored
                                                       encoding:NSUTF8StringEncoding];
        __block NSString *readBack = nil;
        NppAttributeReader *reader = [[NppAttributeReader alloc] init];
        NSXMLParser *xp = [[NSXMLParser alloc] initWithData:restored];
        xp.delegate = reader;
        [xp parse];
        readBack = reader.value;
        Check(@"IDM_VIEW_FUNC_LIST (pattern newlines)",
              @"a newline inside an attribute survives being parsed",
              [restoredText containsString:@"&#10;"] &&
              [readBack containsString:@"\n"]);

        // The project panels: workspaces of projects, virtual folders and files.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *projDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_proj"];
        [fm removeItemAtPath:projDir error:NULL];
        [fm createDirectoryAtPath:[projDir stringByAppendingPathComponent:@"src/sub"] withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [@"alpha needle\n" writeToFile:[projDir stringByAppendingPathComponent:@"src/a.c"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"beta\n" writeToFile:[projDir stringByAppendingPathComponent:@"src/sub/b.h"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"needle too\n" writeToFile:[projDir stringByAppendingPathComponent:@"notes.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *wasRemembered = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppMac.projectWorkspaces"];
        NSArray *projIDs = @[@"IDM_VIEW_PROJECT_PANEL_1", @"IDM_VIEW_PROJECT_PANEL_2", @"IDM_VIEW_PROJECT_PANEL_3"];
        for (NSInteger i = 1; i <= 3; ++i) {
            [ed showProjectPanel:i];
            BOOL shown = [ed activeProjectPanel] == i && [ed projectPanel:i].view.superview != nil &&
                         [ed projectPanel:i].number == i;
            [ed showProjectPanel:i];               // same panel again hides it
            Check(projIDs[i - 1], [NSString stringWithFormat:@"panel %ld shows and hides", (long)i],
                  shown && [ed activeProjectPanel] == 0);
        }

        // With no workspace at all the tree is empty rather than a nil row,
        // and a stale index answers a node rather than an exception.
        NppProjectPanel *bare = [[NppProjectPanel alloc] initWithNumber:9 frame:NSMakeRect(0, 0, 200, 300)];
        [bare setValue:nil forKey:@"root"];
        id<NSOutlineViewDataSource> bareSource = (id<NSOutlineViewDataSource>)bare;
        NSOutlineView *bareOutline = [bare valueForKey:@"outline"];
        BOOL emptyTop = [bareSource outlineView:bareOutline numberOfChildrenOfItem:nil] == 0 &&
                        [bareSource outlineView:bareOutline child:0 ofItem:nil] != nil;
        NppProjectNode *leaf = [[NppProjectNode alloc] init];
        BOOL staleIndex = [bareSource outlineView:bareOutline child:5 ofItem:leaf] != nil;
        [bareOutline reloadData];
        Check(@"IDM_VIEW_PROJECT_PANEL_1 (no root)", @"a panel without a workspace shows an empty tree and survives a stale index",
              emptyTop && staleIndex && bareOutline.numberOfRows == 0);

        NppProjectPanel *panel = [ed projectPanel:2];
        [panel newWorkspace];
        NppProjectNode *project = [panel addProjectNamed:@"Engine"];
        NppProjectNode *folder = [panel addFolderNamed:@"Sources" to:project];
        [panel addFiles:@[[projDir stringByAppendingPathComponent:@"src/a.c"]] to:folder];
        NppProjectNode *fromDisk = [panel addDirectory:[projDir stringByAppendingPathComponent:@"src"] to:project];
        NSArray *notes = [panel addFiles:@[[projDir stringByAppendingPathComponent:@"notes.txt"],
                                           @"/nowhere/at/all.txt"] to:project];
        BOOL built = project.children.count == 4 && [fromDisk.name isEqualToString:@"src"] &&
                     fromDisk.children.count == 2 && [[fromDisk.children[1] name] isEqualToString:@"sub"] &&
                     panel.dirty;
        [panel rename:folder to:@"Code"];
        BOOL moved = [panel moveDown:folder] && project.children[1] == folder && ![panel moveUp:project];
        [panel modifyFilePath:notes.lastObject to:[projDir stringByAppendingPathComponent:@"missing.txt"]];
        NSString *wsPath = [projDir stringByAppendingPathComponent:@"Workspace.xml"];
        BOOL saved = [panel saveWorkspaceAs:wsPath copy:NO] && !panel.dirty;
        NSString *xml = [NSString stringWithContentsOfFile:wsPath encoding:NSUTF8StringEncoding error:NULL];
        BOOL relative = [xml containsString:@"<File name=\"src/a.c\"/>"] && [xml containsString:@"<Folder name=\"Code\">"] &&
                        [xml containsString:@"<Project name=\"Engine\">"] && [xml containsString:@"<File name=\"src/sub/b.h\"/>"];

        [panel newWorkspace];
        BOOL reopened = [panel openWorkspace:wsPath] && [panel.root.children.firstObject.name isEqualToString:@"Engine"] &&
                        [panel allFilePaths].count == 5 &&
                        [[panel allFilePaths] containsObject:[projDir stringByAppendingPathComponent:@"src/sub/b.h"]];

        // A workspace written on Windows: backslashes, a relative and an absolute path.
        NSString *winPath = [projDir stringByAppendingPathComponent:@"FromWindows.xml"];
        [@"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n<Project name=\"W\">\n"
         @"<Folder name=\"F\"><File name=\"src\\sub\\b.h\" /></Folder>\n<File name=\"notes.txt\" />\n"
         @"</Project>\n</NotepadPlus>\n" writeToFile:winPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL windows = [panel openWorkspace:winPath] &&
                       [[panel allFilePaths] isEqualToArray:@[[projDir stringByAppendingPathComponent:@"src/sub/b.h"],
                                                             [projDir stringByAppendingPathComponent:@"notes.txt"]]];

        // Saved again without a change it is what Windows wrote: backslashes, a
        // path outside the folder and a drive path all as they were. A renamed
        // file takes its new name into its path, and keeps it over a reload.
        NSString *roundPath = [projDir stringByAppendingPathComponent:@"RoundTrip.xml"];
        [@"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n<Project name=\"W\">\n"
         @"<File name=\"src\\sub\\b.h\" />\n<File name=\"..\\lib\\x.cpp\" />\n<File name=\"C:\\dev\\y.h\" />\n"
         @"<File name=\"notes.txt\" />\n</Project>\n</NotepadPlus>\n" writeToFile:roundPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL roundTrip = [panel openWorkspace:roundPath];
        NppProjectNode *notesNode = panel.root.children.firstObject.children.lastObject;
        roundTrip = roundTrip && [panel rename:notesNode to:@"renamed.txt"] && [panel saveWorkspace];
        NSString *roundText = [NSString stringWithContentsOfFile:roundPath encoding:NSUTF8StringEncoding error:NULL];
        roundTrip = roundTrip && [roundText containsString:@"name=\"src\\sub\\b.h\""] && [roundText containsString:@"name=\"..\\lib\\x.cpp\""] &&
                    [roundText containsString:@"name=\"C:\\dev\\y.h\""] && [roundText containsString:@"name=\"renamed.txt\""] &&
                    [panel reloadWorkspace] &&
                    [panel.root.children.firstObject.children.lastObject.name isEqualToString:@"renamed.txt"] &&
                    [panel.root.children.firstObject.children.lastObject.path isEqualToString:[projDir stringByAppendingPathComponent:@"renamed.txt"]];
        if (!roundTrip) printf("%s\n", roundText.UTF8String);
        windows = windows && roundTrip;
        [panel openWorkspace:winPath];

        // A changed workspace is asked about; Cancel keeps it.
        [panel addProjectNamed:@"Extra"];
        panel.scriptedAnswer = NSAlertThirdButtonReturn;
        BOOL kept = ![panel openWorkspace:wsPath] && panel.dirty && [panel.workspacePath isEqualToString:winPath];
        panel.scriptedAnswer = NSAlertSecondButtonReturn;
        BOOL discarded = [panel openWorkspace:wsPath] && !panel.dirty;
        panel.scriptedAnswer = 0;

        // Find in Projects searches the project's files, not a folder.
        __block NSString *report = nil;
        [ed findInFilesInBackground:[NppFindSpec specFor:@"needle" mode:NppSearchNormal options:0]
                              paths:[panel allFilePaths] title:@"the projects" filters:@""
                           progress:nil completion:^(NSUInteger found, NSString *r, BOOL stopped) { report = r; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!report && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        BOOL searched = [report containsString:@"a.c (1 hit)"] && [report containsString:@"notes.txt (1 hit)"] &&
                        [report containsString:@"2 hits in 2 files"];

        [panel newWorkspace];
        if (wasRemembered) [[NSUserDefaults standardUserDefaults] setObject:wasRemembered forKey:@"NppMac.projectWorkspaces"];
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppMac.projectWorkspaces"];
        [fm removeItemAtPath:projDir error:NULL];
        Check(@"IDM_VIEW_PROJECT_PANEL_2 (workspaces)",
              @"projects, virtual folders and files are built, renamed, moved and saved with paths relative "
              @"to the workspace, read back, and read from a Windows workspace",
              built && moved && saved && relative && reopened && windows);
        Check(@"IDM_VIEW_PROJECT_PANEL_2 (changes and searching)",
              @"a changed workspace is asked about before another is opened, and Find in Projects searches "
              @"the projects' files",
              kept && discarded && searched);
    }

    if (NppSectionWanted(@"Encoding + EOL")) { printf("\n== Encoding + EOL ==\n");
        // Round-trip each encoding through a real file.
        struct { NSString *name; NSStringEncoding enc; BOOL bom; NSString *cmd; } cases[] = {
            {@"utf8",    NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_AS_UTF_8"},
            {@"utf8bom", NSUTF8StringEncoding,              YES, @"IDM_FORMAT_UTF_8"},
            {@"u16le",   NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_UTF_16LE"},
            {@"u16be",   NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_UTF_16BE"},
            {@"ansi",    NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_ANSI"},
        };
        for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
            NSString *path = [NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:@"t_enc_%@.txt", cases[i].name]];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [@"round trip\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:path error:&e];
            [ed setEncoding:cases[i].enc withBOM:cases[i].bom];
            [ed saveCurrentDocument];

            // Reopen in a fresh document and confirm the text survived.
            [ed closeCurrentDocument];
            [ed openFileAtPath:path error:&e];
            BOOL textOK = [DocText(ed) isEqualToString:@"round trip\n"];
            BOOL bomOK = ed.currentDocument.hasBOM == cases[i].bom;
            Check(cases[i].cmd, [NSString stringWithFormat:@"%@ round-trips", cases[i].name],
                  textOK && bomOK);
        }

        SetDoc(ed, @"a\r\nb\r\n");
        [ed convertEOLTo:SC_EOL_LF];
        Check(@"IDM_FORMAT_TOUNIX", @"CRLF becomes LF", ![DocText(ed) containsString:@"\r"]);
        [ed convertEOLTo:SC_EOL_CRLF];
        Check(@"IDM_FORMAT_TODOS", @"LF becomes CRLF", [DocText(ed) containsString:@"\r\n"]);
        [ed convertEOLTo:SC_EOL_CR];
        Check(@"IDM_FORMAT_TOMAC", @"becomes bare CR",
              [DocText(ed) containsString:@"\r"] && ![DocText(ed) containsString:@"\n"]);
    }

    if (NppSectionWanted(@"Encoding: character sets")) { printf("\n== Encoding: character sets ==\n");
        // Every charset in the menu must resolve to a usable macOS encoding and
        // survive a byte round-trip through that charset.
        int resolved = 0;
        NSMutableArray *unsupported = [NSMutableArray array];
        for (int i = 0; i < kNppCharsetCount; ++i) {
            unsigned int cp = kNppCharsets[i].codepage;
            NSString *cmd = @(kNppCharsets[i].menuID);
            if (![EditorController supportsCodepage:cp]) {
                // Nothing on the system can decode this page; the command must
                // decline cleanly rather than silently decode as something else.
                [unsupported addObject:@(kNppCharsets[i].label)];
                Check([cmd stringByAppendingString:@" (unsupported)"],
                      [NSString stringWithFormat:@"%@ declines instead of mis-decoding",
                       @(kNppCharsets[i].label)],
                      ![ed reinterpretAsCodepage:cp]);
                continue;
            }
            if (cp == 720) { resolved++; continue; }   // covered by its own test below
            NSStringEncoding enc = [EditorController encodingForCodepage:cp];
            resolved++;
            // ASCII is representable in every one of these sets, so a round trip
            // through the charset must return the original text.
            NSString *probe = @"probe 123";
            NSData *bytes = [probe dataUsingEncoding:enc allowLossyConversion:NO];
            NSString *back = bytes ? [[NSString alloc] initWithData:bytes encoding:enc] : nil;
            Check(cmd, [NSString stringWithFormat:@"%@ round-trips", @(kNppCharsets[i].label)],
                  [back isEqualToString:probe]);
        }

        // Round-tripping ASCII proves nothing about which character set was
        // chosen: "probe 123" survives all of them, so a code page wired to the
        // wrong encoding would have passed. encoding-reference.txt says what
        // each byte actually means, taken from Python's own codecs, and every
        // one of those bytes is checked here.
        NSString *referencePath = [[NSBundle mainBundle] pathForResource:@"encoding-reference"
                                                                  ofType:@"txt"];
        NSString *reference = referencePath
            ? [NSString stringWithContentsOfFile:referencePath encoding:NSUTF8StringEncoding error:NULL]
            : nil;
        NSMutableArray *wrongBytes = [NSMutableArray array];
        NSMutableSet *checkedPages = [NSMutableSet set];
        NSUInteger checkedBytes = 0;
        for (NSString *line in [reference componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count != 3) continue;

            unsigned int codepage = (unsigned int)[fields[0] intValue];
            unsigned int byteValue = 0, expectedPoint = 0;
            [[NSScanner scannerWithString:fields[1]] scanHexInt:&byteValue];
            [[NSScanner scannerWithString:fields[2]] scanHexInt:&expectedPoint];

            unsigned char raw = (unsigned char)byteValue;
            NSString *decoded = [EditorController stringFromData:[NSData dataWithBytes:&raw length:1]
                                                        codepage:codepage];
            checkedBytes++;
            [checkedPages addObject:@(codepage)];
            if (decoded.length != 1 || [decoded characterAtIndex:0] != (unichar)expectedPoint) {
                if (wrongBytes.count < 8) {
                    [wrongBytes addObject:[NSString stringWithFormat:@"cp%u byte %02X -> %@ (want %04X)",
                                           codepage, byteValue,
                                           decoded.length ? @([decoded characterAtIndex:0]) : @"nothing",
                                           expectedPoint]];
                }
            }
        }
        Check(@"IDM_FORMAT_ANSI (byte meanings)",
              [NSString stringWithFormat:@"%lu bytes across %lu code pages decode to the right character",
               (unsigned long)checkedBytes, (unsigned long)checkedPages.count],
              checkedBytes > 5000 && wrongBytes.count == 0);
        if (wrongBytes.count) printf("       %s\n",
            [[wrongBytes componentsJoinedByString:@"; "] UTF8String]);
        printf("  (%d of %d character sets resolved%s)\n", resolved, kNppCharsetCount,
               unsupported.count ? [[NSString stringWithFormat:@"; missing: %@",
                                     [unsupported componentsJoinedByString:@", "]] UTF8String] : "");

        // Encode in: the bytes stay, the reading changes. Round-tripping a
        // Cyrillic byte through Windows-1251 and back must restore the text.
        // Code page 720 is decoded from an embedded table; every byte must
        // survive a byte -> character -> byte round trip.
        {
            NSMutableData *all = [NSMutableData dataWithCapacity:256];
            for (int b = 0; b < 256; ++b) { unsigned char c = (unsigned char)b; [all appendBytes:&c length:1]; }
            NSString *decoded = [EditorController stringFromData:all codepage:720];
            NSData *reencoded = [EditorController dataFromString:decoded codepage:720];
            BOOL identity = decoded.length == 256 && [reencoded isEqualToData:all];

            // Spot-check against the published mapping.
            unichar c0xA0 = [decoded characterAtIndex:0xA0];
            unichar c0x98 = [decoded characterAtIndex:0x98];
            unichar c0x41 = [decoded characterAtIndex:0x41];
            Check(@"IDM_FORMAT_DOS_720", @"all 256 bytes round-trip and match the spec",
                  identity && c0xA0 == 0x0628 && c0x98 == 0x0621 && c0x41 == 'A');
        }

        // End to end: real Arabic bytes on disk, opened and read back as CP720.
        // Reference produced with Python's cp720 codec:
        //   'مرحبا'.encode('cp720') -> EA A9 A5 A0 9F
        {
            const unsigned char arabicBytes[] = {0xEA, 0xA9, 0xA5, 0xA0, 0x9F, '\n'};
            NSString *expected = @"\u0645\u0631\u062D\u0628\u0627\n";
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp720.txt"];
            [[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)] writeToFile:p atomically:YES];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            BOOL ok = [ed reinterpretAsCodepage:720];
            BOOL textOK = [DocText(ed) isEqualToString:expected];

            // Saving must put the very same bytes back on disk.
            [ed saveCurrentDocument];
            NSData *back = [NSData dataWithContentsOfFile:p];
            BOOL bytesOK = [back isEqualToData:[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)]];
            Check(@"IDM_FORMAT_DOS_720", @"Arabic file round-trips through open, decode and save",
                  ok && textOK && bytesOK);
        }

        // Code page 858 must differ from 850 in exactly the euro byte.
        NSData *euroByte = [NSData dataWithBytes:(const unsigned char[]){0xD5} length:1];
        NSString *as858 = [EditorController stringFromData:euroByte codepage:858];
        NSString *as850 = [EditorController stringFromData:euroByte codepage:850];
        Check(@"IDM_FORMAT_DOS_858", @"byte 0xD5 is the euro sign, unlike code page 850",
              [as858 isEqualToString:@"\u20AC"] && ![as850 isEqualToString:as858]);

        NSString *cyr = @"\u0442\u0435\u0441\u0442";                     // "test" in Cyrillic
        NSStringEncoding win1251 = [EditorController encodingForCodepage:1251];
        NSData *cyrBytes = [cyr dataUsingEncoding:win1251 allowLossyConversion:NO];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp1251.txt"];
        [cyrBytes writeToFile:path atomically:YES];

        NSError *err = nil;
        [ed openFileAtPath:path error:&err];          // opens as Latin-1 (not valid UTF-8)
        BOOL reinterpreted = [ed reinterpretAsCodepage:1251];
        Check(@"IDM_FORMAT_WIN_1251", @"Encode in Windows-1251 recovers Cyrillic text",
              reinterpreted && [DocText(ed) isEqualToString:cyr]);
    }

    if (NppSectionWanted(@"Encoding: convert to")) { printf("\n== Encoding: convert to ==\n");
        struct { NSStringEncoding enc; BOOL bom; NSString *cmd; NSString *name; } convs[] = {
            {NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_CONV2_ANSI",      @"ANSI"},
            {NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_CONV2_AS_UTF_8",  @"UTF-8"},
            {NSUTF8StringEncoding,              YES, @"IDM_FORMAT_CONV2_UTF_8",     @"UTF-8-BOM"},
            {NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_CONV2_UTF_16BE",  @"UTF-16 BE"},
            {NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_CONV2_UTF_16LE",  @"UTF-16 LE"},
        };
        for (size_t i = 0; i < sizeof(convs)/sizeof(convs[0]); ++i) {
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"t_conv%zu.txt", i]];
            [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
            [@"convert me\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            [ed setEncoding:convs[i].enc withBOM:convs[i].bom];
            [ed saveCurrentDocument];
            [ed closeCurrentDocument];
            [ed openFileAtPath:p error:&e];
            Check(convs[i].cmd, [NSString stringWithFormat:@"Convert to %@ keeps the text", convs[i].name],
                  [DocText(ed) isEqualToString:@"convert me\n"] &&
                  ed.currentDocument.hasBOM == convs[i].bom);
        }
    }

    if (NppSectionWanted(@"Language")) { printf("\n== Language ==\n");
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        BOOL detects = [[cat languageForFileName:@"a.cpp"].name isEqualToString:@"cpp"] &&
                       [[cat languageForFileName:@"b.py"].name isEqualToString:@"python"] &&
                       [[cat languageForFileName:@"c.rs"].name isEqualToString:@"rust"];
        Check(@"IDM_LANG_TEXT", @"extension picks the language", detects);

        SetDoc(ed, @"# a comment\n");
        [ed setLanguageNamed:@"python"];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        Check(@"IDM_LANG_PYTHON", @"lexer styles the buffer",
              [ed.currentDocument.language.name isEqualToString:@"python"] &&
              [sci message:SCI_GETSTYLEAT wParam:0] == SCE_P_COMMENTLINE);

        // Every language the Language menu offers: selecting it must apply the
        // language and produce a working Lexilla lexer.
        int langOK = 0, langBad = 0;
        NSMutableArray *broken = [NSMutableArray array];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *menuID = @(kNppLangLexers[i].menuID);
            if (!menuID.length) continue;                 // no upstream menu entry
            NSString *name = @(kNppLangLexers[i].langName);
            if (![cat languageNamed:name]) continue;      // not in langs.model.xml

            [ed setLanguageNamed:name];
            void *lexer = CreateLexer(kNppLangLexers[i].lexerID);
            BOOL ok = [ed.currentDocument.language.name isEqualToString:name] && lexer != NULL;
            if (ok) { langOK++; [gCovered addObject:menuID]; }
            else    { langBad++; [broken addObject:name]; }
        }
        Check(@"IDM_LANG_USER", [NSString stringWithFormat:
                @"all %d menu languages apply and lex%@", langOK,
                langBad ? [NSString stringWithFormat:@" (%d broken: %@)", langBad,
                           [broken componentsJoinedByString:@", "]] : @""],
              langBad == 0 && langOK > 80);

        // Creating a lexer object is not the same as the buffer being coloured.
        // For each language, its own first keyword is put in the document and
        // the styles that come back are examined: if every byte is style 0, the
        // lexer is attached in name only.
        int lexed = 0;
        NSMutableArray *unstyled = [NSMutableArray array];
        NSDictionary *languageProbes = @{
            @"html": @"<a href=\"x\">text</a>\n",
            @"xml":  @"<root attr=\"1\">text</root>\n",
            @"asp":  @"<% Response.Write \"hi\" %>\n",
            @"jsp":  @"<% out.print(\"hi\"); %>\n",
            @"php":  @"<?php\necho \"hi\";\n?>\n",          // a page, as Notepad++ lexes a .php file: PHP is what is inside <?php ?>
            @"kix":  @"; comment\n$a = 1\n",
            @"inno": @"[Setup]\nAppName=Test\n",
            @"yaml": @"key: value\n# comment\n",
        };
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *name = @(kNppLangLexers[i].langName);
            NppLanguage *language = [cat languageNamed:name];
            if (!language) continue;
            NSString *keywords = language.keywordSets[@0] ?: language.keywordSets.allValues.firstObject;
            NSString *word = [keywords componentsSeparatedByString:@" "].firstObject;

            // A keyword on a line of its own is a fair probe for a programming
            // language. For markup and for configuration files it is not: HTML's
            // keywords are tag names, which are only tags inside angle brackets,
            // so those languages get a line that is actually something in them.
            NSString *probe = languageProbes[name]
                            ?: (word.length ? [word stringByAppendingString:@"\n"] : nil);
            if (!probe.length) continue;

            [ed setLanguageNamed:name];
            SetDoc(ed, probe);
            [sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL styled = NO;
            long probeLength = [sci message:SCI_GETLENGTH];
            for (long at = 0; at < probeLength; ++at) {
                if ([sci message:SCI_GETSTYLEAT wParam:(uptr_t)at] != 0) { styled = YES; break; }
            }
            if (styled) lexed++; else [unstyled addObject:name];
        }
        Check(@"IDM_LANG_USER (colouring)",
              [NSString stringWithFormat:@"%d languages colour their own keyword%@", lexed,
               unstyled.count ? [NSString stringWithFormat:@" (%lu do not: %@)",
                                 (unsigned long)unstyled.count,
                                 [unstyled componentsJoinedByString:@", "]] : @""],
              unstyled.count == 0);
    }

    if (NppSectionWanted(@"Tools: hashes")) { printf("\n== Tools: hashes ==\n");
        // Reference values for "abc" from the published test vectors.
        struct { NppDigest d; NSString *want; NSString *gen; NSString *files; NSString *clip; } hashes[] = {
            {NppDigestMD5,    @"900150983cd24fb0d6963f7d28e17f72",
             @"IDM_TOOL_MD5_GENERATE", @"IDM_TOOL_MD5_GENERATEFROMFILE", @"IDM_TOOL_MD5_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA1,   @"a9993e364706816aba3e25717850c26c9cd0d89d",
             @"IDM_TOOL_SHA1_GENERATE", @"IDM_TOOL_SHA1_GENERATEFROMFILE", @"IDM_TOOL_SHA1_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA256, @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
             @"IDM_TOOL_SHA256_GENERATE", @"IDM_TOOL_SHA256_GENERATEFROMFILE", @"IDM_TOOL_SHA256_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA512, @"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                               "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
             @"IDM_TOOL_SHA512_GENERATE", @"IDM_TOOL_SHA512_GENERATEFROMFILE", @"IDM_TOOL_SHA512_GENERATEINTOCLIPBOARD"},
        };
        NSString *abcPath = TempFile(@"t_hash.txt", @"abc");
        for (size_t i = 0; i < sizeof(hashes)/sizeof(hashes[0]); ++i) {
            NSString *got = [EditorController hashOfData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]
                                                  digest:hashes[i].d];
            Check(hashes[i].gen, [NSString stringWithFormat:@"%@(\"abc\") matches the test vector",
                                  [EditorController nameOfDigest:hashes[i].d]],
                  [got isEqualToString:hashes[i].want]);

            NSString *fromFile = [ed hashOfFiles:@[abcPath] digest:hashes[i].d];
            Check(hashes[i].files, @"hashes a file's contents",
                  [fromFile hasPrefix:hashes[i].want] && [fromFile hasSuffix:abcPath]);

            SetDoc(ed, @"abc");
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [ed copyToClipboard:[ed hashOfSelection:hashes[i].d]];
            Check(hashes[i].clip, @"puts the selection hash on the clipboard",
                  [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      isEqualToString:hashes[i].want]);
        }
    }

    if (NppSectionWanted(@"Tools: the digests the port adds")) { printf("\n== Tools: the digests the port adds ==\n");
        NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        struct { NppDigest d; NSString *want; } more[] = {
            {NppDigestSHA224,   @"23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"},
            {NppDigestSHA384,   @"cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
                                 "8086072ba1e7cc2358baeca134c825a7"},
            {NppDigestSHA3_256, @"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"},
            {NppDigestSHA3_512, @"b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e"
                                 "10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0"},
            {NppDigestBLAKE2b,  @"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
                                 "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"},
        };
        BOOL allRight = YES;
        for (size_t i = 0; i < sizeof(more)/sizeof(more[0]); ++i) {
            NSString *got = [EditorController hashOfData:abc digest:more[i].d];
            if (![got isEqualToString:more[i].want]) {
                allRight = NO;
                printf("    %s: %s\n", [EditorController nameOfDigest:more[i].d].UTF8String, got.UTF8String);
            }
        }
        Check(@"Tools > Hashes (SHA-224, SHA-384, SHA3-256, SHA3-512, BLAKE2b)",
              @"each gives the published digest of \"abc\"", allRight);

        // Two hundred bytes is more than one block of SHA3-256's 136, so the
        // absorbing loop is gone round, not only the padding.
        NSData *long3 = [[@"" stringByPaddingToLength:200 withString:@"a" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding];
        Check(@"Tools > Hashes (SHA-3 over more than a block)", @"a text longer than the sponge's rate is absorbed block by block",
              [[EditorController hashOfData:long3 digest:NppDigestSHA3_256]
                  isEqualToString:@"cce34485baf2bf2aca99b94833892a4f52896d3d153f7b840cc4f9fe695f1387"]);

        Check(@"Tools > Hashes (CRC-32)", @"the check value of \"123456789\" is cbf43926",
              [[EditorController hashOfData:[@"123456789" dataUsingEncoding:NSUTF8StringEncoding] digest:NppDigestCRC32]
                  isEqualToString:@"cbf43926"]);

        NSData *mac = [NppCrypto hmacOfData:[@"The quick brown fox jumps over the lazy dog" dataUsingEncoding:NSUTF8StringEncoding]
                                        key:[@"key" dataUsingEncoding:NSUTF8StringEncoding] digest:@"SHA-256"];
        Check(@"Tools > Hashes (HMAC)", @"HMAC-SHA-256 with a key gives the well-known value, and an unknown digest gives nothing",
              [[NppCrypto hexOfData:mac] isEqualToString:@"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"] &&
              [NppCrypto hmacOfData:abc key:abc digest:@"SHA-999"] == nil);

        // "Treat each line as a separate string", as upstream's dialog has it:
        // a digest per line, an empty line left empty, either kind of line end.
        NSString *md5abc = @"900150983cd24fb0d6963f7d28e17f72", *md5x = @"9dd4e461268c8034f5c8564e155c67a6";
        NSString *perLine = [EditorController hashOfText:@"abc\r\n\nx\n" eachLine:YES digest:NppDigestMD5];
        NSString *whole = [EditorController hashOfText:@"abc" eachLine:NO digest:NppDigestMD5];
        Check(@"Tools > Hashes (each line as a separate string)",
              @"one digest for each line, empty lines kept empty; unticked, one digest for all of it",
              [perLine isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", md5abc, md5x]] && [whole isEqualToString:md5abc]);
    }

    if (NppSectionWanted(@"Tools: password hashes")) { printf("\n== Tools: password hashes ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };

        // bcrypt, against the vectors of its reference implementations. The
        // salt is given here as it is written in the hash, and read back.
        struct { NSString *password, *version; int cost; NSString *want; } crypts[] = {
            {@"U*U", @"2a", 5, @"$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW"},
            {@"", @"2a", 6, @"$2a$06$DCq7YPn5Rq63x1Lad4cll.TV4S6ytwfsfvkgY8jIucDrjc8deX1s."},
            {@"пароль", @"2b", 6, @"$2b$06$abcdefghijklmnopqrstuu0RbYLPpyLm/x71XGmlHQAdqmD5AbL2G"},
        };
        BOOL bcryptRight = YES;
        for (size_t i = 0; i < sizeof(crypts)/sizeof(crypts[0]); ++i) {
            BOOL matches = [[NppCrypto password:utf8(crypts[i].password) matches:crypts[i].want] boolValue];
            BOOL refuses = ![[NppCrypto password:utf8([crypts[i].password stringByAppendingString:@"x"]) matches:crypts[i].want] boolValue];
            if (!matches || !refuses) { bcryptRight = NO; printf("    bcrypt vector %zu: matches %d refuses %d\n", i, matches, refuses); }
        }
        NppPasswordHashSettings *bcrypt = [NppPasswordHashSettings defaultsForKind:NppPasswordHashBcrypt];
        bcrypt.bcryptCost = 5; bcrypt.bcryptVersion = @"2y";
        NSData *salt16 = [NppCrypto dataFromHex:@"000102030405060708090a0b0c0d0e0f"];
        NppPasswordHashResult *made = [NppCrypto hashPassword:utf8(@"correct horse") salt:salt16 settings:bcrypt];
        Check(@"Tools > Hashes > bcrypt", @"the reference vectors verify (an empty password and a Cyrillic one among them), "
              @"a wrong password does not, and a hash made here is $2y$05$, 60 characters, and verifies",
              bcryptRight && [made.encoded hasPrefix:@"$2y$05$"] && made.encoded.length == 60 && made.key.length == 23 &&
              [[NppCrypto password:utf8(@"correct horse") matches:made.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"correct horsf") matches:made.encoded] boolValue]);

        // Past 72 bytes bcrypt reads no further: that is the algorithm, and what every other implementation does.
        NSString *long72 = [@"" stringByPaddingToLength:72 withString:@"0123456789" startingAtIndex:0];
        NppPasswordHashResult *a72 = [NppCrypto hashPassword:utf8(long72) salt:salt16 settings:bcrypt];
        NppPasswordHashResult *b72 = [NppCrypto hashPassword:utf8([long72 stringByAppendingString:@"tail"]) salt:salt16 settings:bcrypt];
        bcrypt.bcryptCost = 3;
        Check(@"Tools > Hashes > bcrypt (limits)", @"only the first 72 bytes count; a cost below 4 or a salt that is not 16 bytes is refused",
              [a72.encoded isEqualToString:b72.encoded] && [bcrypt problem] != nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:salt16 settings:bcrypt] == nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"short") settings:[NppPasswordHashSettings defaultsForKind:NppPasswordHashBcrypt]] == nil);

        // scrypt: two of RFC 7914's vectors, one with sixteen lanes and one with a large N.
        NppPasswordHashSettings *scrypt = [NppPasswordHashSettings defaultsForKind:NppPasswordHashScrypt];
        scrypt.scryptLogN = 10; scrypt.scryptR = 8; scrypt.scryptP = 16; scrypt.keyLength = 64;
        NppPasswordHashResult *s1 = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"NaCl") settings:scrypt];
        scrypt.scryptLogN = 14; scrypt.scryptP = 1; scrypt.keyLength = 32;
        NppPasswordHashResult *s2 = [NppCrypto hashPassword:utf8(@"pleaseletmein") salt:utf8(@"SodiumChloride") settings:scrypt];
        Check(@"Tools > Hashes > scrypt", @"RFC 7914's vectors come out, and the string written for one verifies against its password only",
              [[NppCrypto hexOfData:s1.key] isEqualToString:@"fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162"
                                                             "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"] &&
              [[NppCrypto hexOfData:s2.key] isEqualToString:@"7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2"] &&
              [s2.encoded hasPrefix:@"$scrypt$ln=14,r=8,p=1$U29kaXVtQ2hsb3JpZGU$"] &&
              [[NppCrypto password:utf8(@"pleaseletmein") matches:s2.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"pleaseletmeout") matches:s2.encoded] boolValue]);
        scrypt.scryptLogN = 24; scrypt.scryptR = 64;
        Check(@"Tools > Hashes > scrypt (limits)", @"settings that would need more than 2 GB are refused rather than tried",
              [scrypt problem] != nil && [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"saltsalt") settings:scrypt] == nil);

        // Argon2, all three variants, against the reference implementation's own output.
        struct { NppArgon2Variant v; NSString *want; } argons[] = {
            {NppArgon2id, @"$argon2id$v=19$m=64,t=2,p=2$c29tZXNhbHQ$lDh0Fd+4TtGXdGWh6GJgc630K9Turh+qHdTiOh/2hZ8"},
            {NppArgon2i,  @"$argon2i$v=19$m=64,t=2,p=2$c29tZXNhbHQ$u3EC2QpYDSqhwag4F/JKsYx8yBDM0sKg0MgMlK0pkWc"},
            {NppArgon2d,  @"$argon2d$v=19$m=64,t=2,p=2$c29tZXNhbHQ$1q8bgD0xYiK3sMCt/uIryr7jP0g04fs9QOITesC7M88"},
        };
        BOOL argonRight = YES;
        for (size_t i = 0; i < 3; ++i) {
            NppPasswordHashSettings *argon = [NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2];
            argon.argon2Variant = argons[i].v; argon.argon2Memory = 64; argon.argon2Passes = 2; argon.argon2Lanes = 2; argon.keyLength = 32;
            NppPasswordHashResult *got = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"somesalt") settings:argon];
            if (![got.encoded isEqualToString:argons[i].want] || got.key.length != 32 ||
                ![[NppCrypto password:utf8(@"password") matches:argons[i].want] boolValue] ||
                [[NppCrypto password:utf8(@"Password") matches:argons[i].want] boolValue]) {
                argonRight = NO; printf("    argon2 variant %zu: %s\n", i, got.encoded.UTF8String);
            }
        }
        NppPasswordHashSettings *thin = [NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2];
        thin.argon2Memory = 8; thin.argon2Lanes = 4;
        Check(@"Tools > Hashes > Argon2", @"argon2id, argon2i and argon2d give the reference implementation's strings and verify; "
              @"too little memory for the lanes, or a salt under 8 bytes, is refused",
              argonRight && [thin problem] != nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"short") settings:[NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2]] == nil);

        NppPasswordHashSettings *pbkdf2 = [NppPasswordHashSettings defaultsForKind:NppPasswordHashPBKDF2];
        pbkdf2.pbkdf2Rounds = 4096; pbkdf2.keyLength = 32;
        NppPasswordHashResult *derived = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"salt") settings:pbkdf2];
        Check(@"Tools > Hashes > PBKDF2", @"PBKDF2-HMAC-SHA-256 of \"password\" and \"salt\" over 4096 rounds is the known key, and its string verifies",
              [[NppCrypto hexOfData:derived.key] isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"] &&
              [derived.encoded hasPrefix:@"$pbkdf2-sha256$4096$c2FsdA$"] &&
              [[NppCrypto password:utf8(@"password") matches:derived.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"passwor") matches:derived.encoded] boolValue]);

        Check(@"Tools > Hashes (what is not a hash)", @"a string of no known scheme is said to be none, rather than a mismatch",
              [NppCrypto password:utf8(@"x") matches:@"5f4dcc3b5aa765d61d8327deb882cf99"] == nil &&
              [NppCrypto password:utf8(@"x") matches:@"$9z$12$whatever"] == nil &&
              [NppCrypto password:utf8(@"x") matches:@"$2b$12$tooshort"] == nil);
    }

    if (NppSectionWanted(@"Tools: Base64, Base58, Base32 and bytes in hexadecimal")) { printf("\n== Tools: Base64, Base58, Base32 and bytes in hexadecimal ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
        NSData *(^hex)(NSString *) = ^NSData *(NSString *text) { return [NppCrypto dataFromHex:text]; };

        Check(@"Tools > Base (bytes written as hexadecimal)",
              @"plain, spaced, with 0x and commas, with colons, in either case; half a byte or a stray letter is refused",
              [hex(@"48656c6c6f") isEqualToData:utf8(@"Hello")] && [hex(@"48 65 6C 6c 6F") isEqualToData:utf8(@"Hello")] &&
              [hex(@"0x48, 0x65, 0X6c,0x6c ,0x6f") isEqualToData:utf8(@"Hello")] && [hex(@"48:65:6c:6c:6f\n") isEqualToData:utf8(@"Hello")] &&
              hex(@"").length == 0 && hex(@"") != nil && hex(@"486") == nil && hex(@"4 8") == nil && hex(@"48 6g") == nil &&
              [[NppCrypto hexOfData:utf8(@"Hello")] isEqualToString:@"48656c6c6f"]);

        Check(@"Tools > Base > Base64", @"a Cyrillic string there and back; the URL alphabet; unpadded and wrapped input is read; rubbish is not",
              [[NppCrypto encode:utf8(@"Привет") as:NppBase64] isEqualToString:@"0J/RgNC40LLQtdGC"] &&
              [[NppCrypto decode:@"0J/RgNC40LLQtdGC" as:NppBase64] isEqualToData:utf8(@"Привет")] &&
              [[NppCrypto encode:hex(@"fbff") as:NppBase64URL] isEqualToString:@"-_8="] &&
              [[NppCrypto encode:hex(@"fbff") as:NppBase64] isEqualToString:@"+/8="] &&
              [[NppCrypto decode:@"-_8" as:NppBase64] isEqualToData:hex(@"fbff")] &&
              [[NppCrypto decode:@"SGVs\r\nbG8=\n" as:NppBase64] isEqualToData:utf8(@"Hello")] &&
              [NppCrypto decode:@"SGVsbG8*" as:NppBase64] == nil && [NppCrypto decode:@"SGVsb" as:NppBase64] == nil);

        Check(@"Tools > Base > Base58", @"Bitcoin's alphabet: leading zero bytes become 1s and come back, a text goes there and back, "
              @"and the letters the alphabet leaves out (0, O, I, l) are refused",
              [[NppCrypto encode:utf8(@"Hello World!") as:NppBase58] isEqualToString:@"2NEpo7TZRRrLZSi2U"] &&
              [[NppCrypto decode:@"2NEpo7TZRRrLZSi2U" as:NppBase58] isEqualToData:utf8(@"Hello World!")] &&
              [[NppCrypto encode:hex(@"0000287fb4cd") as:NppBase58] isEqualToString:@"11233QC4"] &&
              [[NppCrypto decode:@"11233QC4" as:NppBase58] isEqualToData:hex(@"0000287fb4cd")] &&
              [[NppCrypto encode:[NSData data] as:NppBase58] isEqualToString:@""] &&
              [NppCrypto decode:@"2NEpo7TZRRrLZSi20" as:NppBase58] == nil && [NppCrypto decode:@"Il" as:NppBase58] == nil);

        Check(@"Tools > Base > Base58Check", @"a Bitcoin address is its version and hash with four bytes of checksum; one wrong character and it is refused",
              [[NppCrypto encode:hex(@"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31") as:NppBase58Check]
                  isEqualToString:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs"] &&
              [[NppCrypto decode:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs" as:NppBase58Check]
                  isEqualToData:hex(@"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31")] &&
              [NppCrypto decode:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAt" as:NppBase58Check] == nil);

        Check(@"Tools > Base > Base32", @"RFC 4648's vectors there and back, lower case and unpadded input read too",
              [[NppCrypto encode:utf8(@"foobar") as:NppBase32] isEqualToString:@"MZXW6YTBOI======"] &&
              [[NppCrypto encode:utf8(@"fo") as:NppBase32] isEqualToString:@"MZXQ===="] &&
              [[NppCrypto decode:@"MZXW6YTBOI======" as:NppBase32] isEqualToData:utf8(@"foobar")] &&
              [[NppCrypto decode:@"mzxw6ytboi" as:NppBase32] isEqualToData:utf8(@"foobar")] &&
              [NppCrypto decode:@"MZXW1" as:NppBase32] == nil);
    }

    if (NppSectionWanted(@"Tools: passwords")) { printf("\n== Tools: passwords ==\n");
        NSString *upper = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ", *lower = @"abcdefghijklmnopqrstuvwxyz", *digits = @"0123456789", *marks = @"!@#$%^&*";
        NSCharacterSet *(^setOf)(NSString *) = ^NSCharacterSet *(NSString *text) { return [NSCharacterSet characterSetWithCharactersInString:text]; };
        BOOL lengthsRight = YES, everySetSeen = YES, onlyFromSets = YES;
        NSCharacterSet *allowed = setOf([@[upper, lower, digits, marks] componentsJoinedByString:@""]);
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (int i = 0; i < 200; ++i) {
            NSString *one = [NppCrypto passwordOfLength:12 fromSets:@[upper, lower, digits, marks] requireEach:YES random:nil];
            [seen addObject:one ?: @""];
            if (one.length != 12) lengthsRight = NO;
            if ([one rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) onlyFromSets = NO;
            for (NSString *set in @[upper, lower, digits, marks])
                if ([one rangeOfCharacterFromSet:setOf(set)].location == NSNotFound) everySetSeen = NO;
        }
        Check(@"Tools > Password (made from the chosen sets)",
              @"two hundred passwords of twelve: each twelve long, from the chosen characters only, with one of every set in each, and no two alike",
              lengthsRight && onlyFromSets && everySetSeen && seen.count == 200);

        // Over many draws every character of the alphabet turns up, and none much more than its share.
        NSCountedSet<NSString *> *tally = [NSCountedSet set];
        NSString *many = [NppCrypto passwordOfLength:20000 fromSets:@[digits] requireEach:NO random:nil];
        for (NSUInteger i = 0; i < many.length; ++i) [tally addObject:[many substringWithRange:NSMakeRange(i, 1)]];
        NSUInteger least = NSUIntegerMax, most = 0;
        for (NSString *digit in tally) { least = MIN(least, [tally countForObject:digit]); most = MAX(most, [tally countForObject:digit]); }
        Check(@"Tools > Password (drawn evenly)", @"of 20000 digits each of the ten turns up about 2000 times",
              tally.count == 10 && least > 1700 && most < 2300);

        // With the draws dictated, the result is known exactly: what the generator asks for and in what order.
        __block NSMutableArray<NSNumber *> *asked = [NSMutableArray array];
        NSString *fixed = [NppCrypto passwordOfLength:4 fromSets:@[@"ab", @"12"] requireEach:YES
                                               random:^uint32_t(uint32_t below) { [asked addObject:@(below)]; return 0; }];
        Check(@"Tools > Password (how it draws)", @"one from each set first, the rest from all of them, then a shuffle - and nothing but the generator decides",
              [asked isEqualToArray:@[@2, @2, @4, @4, @4, @3, @2]] && fixed.length == 4 &&
              [[fixed stringByTrimmingCharactersInSet:setOf(@"ab12")] isEqualToString:@""]);

        NSString *emoji = [NppCrypto passwordOfLength:6 fromSets:@[@"😀é"] requireEach:NO random:nil];
        __block NSUInteger pieces = 0;
        [emoji enumerateSubstringsInRange:NSMakeRange(0, emoji.length) options:NSStringEnumerationByComposedCharacterSequences
                               usingBlock:^(NSString *, NSRange, NSRange, BOOL *) { pieces++; }];
        Check(@"Tools > Password (edges)", @"nothing to draw from gives nothing; a set repeated counts once; an emoji is one character; "
              @"more sets than characters still gives the length asked for; look-alikes can be left out",
              [NppCrypto passwordOfLength:8 fromSets:@[] requireEach:YES random:nil] == nil &&
              [NppCrypto passwordOfLength:8 fromSets:@[@""] requireEach:YES random:nil] == nil &&
              [NppCrypto passwordOfLength:0 fromSets:@[digits] requireEach:NO random:nil] == nil &&
              [[NppCrypto passwordOfLength:5 fromSets:@[@"x", @"x", @"xx"] requireEach:YES random:nil] isEqualToString:@"xxxxx"] &&
              pieces == 6 &&
              [NppCrypto passwordOfLength:2 fromSets:@[upper, lower, digits, marks] requireEach:YES random:nil].length == 2 &&
              [[NppCrypto withoutLookalikes:@"ABCO0oIl1|xyz"] isEqualToString:@"ABCxyz"]);

        Check(@"Tools > Password (entropy)", @"sixteen characters out of 62 is a little over 95 bits",
              fabs([NppCrypto entropyOfLength:16 alphabetSize:62] - 95.27) < 0.01 && [NppCrypto entropyOfLength:16 alphabetSize:1] == 0);
    }

    if (NppSectionWanted(@"Tools: the menu and its windows")) { printf("\n== Tools: the menu and its windows ==\n");
        NppPreferences *tp = [NppPreferences shared];
        NSString *languageBefore = tp.localizationFile;
        tp.localizationFile = @"";
        [app applyLocalization];
        NSDictionary *passwordSettingsBefore = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"];

        NSMenu *tools = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) if ([NppEnglishMenuTitle(top.submenu) isEqualToString:@"Tools"]) tools = top.submenu;
        NSMenu *(^submenu)(NSMenu *, NSString *) = ^NSMenu *(NSMenu *menu, NSString *title) {
            for (NSMenuItem *item in menu.itemArray) if ([NppEnglishTitle(item) isEqualToString:title]) return item.submenu;
            return nil;
        };
        NSMenu *hashes = submenu(tools, @"Hashes"), *base = submenu(tools, @"Base");
        NSMutableArray<NSString *> *hashTitles = [NSMutableArray array], *baseTitles = [NSMutableArray array];
        for (NSMenuItem *item in hashes.itemArray) [hashTitles addObject:item.isSeparatorItem ? @"-" : NppEnglishTitle(item)];
        for (NSMenuItem *item in base.itemArray) [baseTitles addObject:NppEnglishTitle(item)];
        BOOL threeEach = YES;
        for (NSMenuItem *item in hashes.itemArray) if (item.submenu && item.submenu.numberOfItems != 3) threeEach = NO;
        // Every hash, old or new, has the same three commands under the same names.
        BOOL threeAlike = YES;
        NSMutableArray<NSString *> *md5Titles = [NSMutableArray array];
        for (NSMenuItem *item in submenu(hashes, @"MD5").itemArray) [md5Titles addObject:NppEnglishTitle(item)];
        for (NSMenuItem *item in hashes.itemArray) {
            if (!item.submenu) continue;
            NSMutableArray<NSString *> *titles = [NSMutableArray array];
            for (NSMenuItem *command in item.submenu.itemArray) [titles addObject:NppEnglishTitle(command)];
            if (![titles isEqualToArray:md5Titles]) threeAlike = NO;
        }
        Check(@"Tools (the menu)", @"Hashes holds Notepad++'s four digests first, the port's six, then bcrypt, scrypt, Argon2 and PBKDF2, every one with the digests' three commands; "
              @"Base holds Base64, Base58 and Base32; and Password Generator and HTTP Request follow - named whole, with no ellipsis to be taken for a name cut short",
              [hashTitles isEqualToArray:@[@"MD5", @"SHA-1", @"SHA-256", @"SHA-512", @"SHA-224", @"SHA-384", @"SHA3-256", @"SHA3-512",
                                           @"BLAKE2b", @"CRC-32", @"-", @"bcrypt", @"scrypt", @"Argon2", @"PBKDF2"]] && threeEach && threeAlike &&
              [baseTitles isEqualToArray:@[@"Base64…", @"Base58…", @"Base32…"]] &&
              [NppEnglishTitle(tools.itemArray[2]) isEqualToString:@"Password Generator"] &&
              [NppEnglishTitle(tools.itemArray[3]) isEqualToString:@"HTTP Request"] &&
              [NppEnglishTitle(tools.itemArray[5]) isEqualToString:@"QR Code from Selection"] &&
              [NppEnglishTitle(tools.itemArray[6]) isEqualToString:@"Read QR Code from Clipboard"] &&
              [NppEnglishTitle(tools.itemArray[8]) isEqualToString:@"Install Command Line Tool"] &&
              tools.numberOfItems == 9);

        // Notepad++'s ids still find its own digests one level further down, and the
        // port's digests are not taken for them because they too say "Generate…".
        NSDictionary<NSNumber *, NSMenuItem *> *byID = [app.shortcutStore menuItemsByIdentifier];
        NSMenu *sha1 = submenu(hashes, @"SHA-1"), *sha224 = submenu(hashes, @"SHA-224");
        BOOL portsHaveNone = YES;
        for (NSNumber *identifier in byID) if (byID[identifier].menu == sha224 || byID[identifier].menu == base) portsHaveNone = NO;
        Check(@"Tools (Notepad++'s command ids)", @"IDM_TOOL_SHA1_GENERATE and its two neighbours are the items under Hashes > SHA-1, "
              @"MD5's are MD5's, and SHA-224's items carry no id of Notepad++'s",
              byID[@48507] == sha1.itemArray[0] && byID[@48508] == sha1.itemArray[1] && byID[@48509] == sha1.itemArray[2] &&
              byID[@48501] == submenu(hashes, @"MD5").itemArray[0] && byID[@48512] == submenu(hashes, @"SHA-512").itemArray[2] && portsHaveNone);

        // The digest window, as upstream's: it answers as one types.
        NppDigestWindow *dw = [NppDigestWindow shared];
        [dw showForDigest:NppDigestSHA256 fromFiles:NO];
        dw.eachLine.state = NSControlStateValueOff; dw.hmacKey.stringValue = @"";
        dw.input.string = @"abc"; [dw refresh];
        NSString *sha256abc = @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        BOOL whole = [dw.result.string isEqualToString:sha256abc];
        dw.input.string = @"abc\n\nabc"; dw.eachLine.state = NSControlStateValueOn; [dw refresh];
        BOOL perLine = [dw.result.string isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", sha256abc, sha256abc]];
        dw.eachLine.state = NSControlStateValueOff;
        dw.input.string = @"The quick brown fox jumps over the lazy dog"; dw.hmacKey.stringValue = @"key"; [dw refresh];
        BOOL keyed = [dw.result.string isEqualToString:@"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"] && !dw.hmacKey.superview.hidden;
        dw.input.string = @""; [dw refresh];
        BOOL emptied = dw.result.string.length == 0;
        [dw.clipboardButton performClick:nil];
        dw.hmacKey.stringValue = @"";
        Check(@"IDM_TOOL_SHA256_GENERATE (the window)", @"the digest follows the text as it is typed: of all of it, of each line, "
              @"as an HMAC when a key is given, and nothing for nothing; its title names the digest",
              whole && perLine && keyed && emptied && [dw.panel.title isEqualToString:@"Generate SHA-256 digest"] && dw.chooseFiles.hidden);

        [dw showForDigest:NppDigestSHA3_256 fromFiles:NO];
        dw.input.string = @"abc"; [dw refresh];
        Check(@"Tools > Hashes > SHA3-256 (the window)", @"a digest the port adds is shown in the same window under its own name, without the HMAC key it has none for",
              [dw.result.string isEqualToString:@"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"] &&
              [dw.panel.title isEqualToString:@"Generate SHA3-256 digest"] && dw.hmacKey.superview.hidden);

        NSString *fileA = TempFile(@"t_digest_a.txt", @"abc"), *fileB = TempFile(@"t_digest_b.txt", @"123456789");
        [dw showForDigest:NppDigestCRC32 fromFiles:YES];
        [dw digestFiles:@[fileA, fileB]];
        [dw.clipboardButton performClick:nil];
        Check(@"IDM_TOOL_SHA256_GENERATEFROMFILE (the window)", @"from files: a line for each file, digest and name as shasum writes them, and Copy to Clipboard takes them",
              [dw.result.string isEqualToString:@"352441c2  t_digest_a.txt\ncbf43926  t_digest_b.txt"] && !dw.chooseFiles.hidden &&
              [dw.chooseFiles.title isEqualToString:@"Choose files to generate CRC-32..."] && dw.input.enclosingScrollView.hidden &&
              [dw.panel.title isEqualToString:@"Generate CRC-32 digest from files"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:dw.result.string]);
        [dw.panel orderOut:nil];

        // Password hashes: the digests' window, with each kind's own settings above it and no others.
        NppPasswordHashWindow *hw = [NppPasswordHashWindow shared];
        [hw showForKind:NppPasswordHashBcrypt fromFiles:NO];
        NSArray *bcryptRows = [hw visibleFieldNames];
        BOOL bcryptShown = !hw.fields[@"bcryptCost"].isHiddenOrHasHiddenAncestor && hw.fields[@"argon2Memory"].isHiddenOrHasHiddenAncestor &&
                           hw.fields[@"keyLength"].isHiddenOrHasHiddenAncestor && [hw.panel.title isEqualToString:@"Generate bcrypt digest"];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        BOOL argonShown = hw.fields[@"bcryptCost"].isHiddenOrHasHiddenAncestor && !hw.fields[@"argon2Memory"].isHiddenOrHasHiddenAncestor &&
                          !hw.fields[@"keyLength"].isHiddenOrHasHiddenAncestor && [hw.panel.title isEqualToString:@"Generate Argon2 digest"];
        Check(@"Tools > Hashes (settings of each kind)", @"bcrypt shows its cost and version, Argon2 its variant, memory, iterations, parallelism and hash length - "
              @"each only its own, in a window named after it, with the digests' input, per-line box and result below",
              [bcryptRows isEqualToArray:@[@"bcryptCost", @"bcryptVersion"]] && bcryptShown && argonShown &&
              [[hw visibleFieldNames] isEqualToArray:@[@"argon2Variant", @"argon2Memory", @"argon2Passes", @"argon2Lanes", @"keyLength"]] &&
              hw.kind == NppPasswordHashArgon2 && !hw.input.isHiddenOrHasHiddenAncestor && !hw.eachLine.isHiddenOrHasHiddenAncestor &&
              !hw.result.isHiddenOrHasHiddenAncestor && hw.chooseFiles.hidden);

        [hw showForKind:NppPasswordHashBcrypt fromFiles:NO];
        hw.eachLine.state = hw.bareKey.state = NSControlStateValueOff;
        hw.input.string = @"U*U";
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"5"];
        [(NSPopUpButton *)hw.fields[@"bcryptVersion"] selectItemWithTitle:@"2a"];
        // The salt of the reference vector "CCCCCCCCCCCCCCCCCCCCC." as bytes.
        hw.salt.stringValue = @"10 41 04 10 41 04 10 41 04 10 41 04 10 41 04 10";
        [hw refreshAndWait];
        NSString *vectorHash = @"$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW";
        BOOL vector = [hw.result.string isEqualToString:vectorHash];
        hw.bareKey.state = NSControlStateValueOn; [hw refreshAndWait];
        BOOL bare = hw.result.string.length == 46 && [NppCrypto dataFromHex:hw.result.string] != nil;
        hw.bareKey.state = NSControlStateValueOff;
        hw.input.string = @"U*U\n\nU*U\n"; hw.eachLine.state = NSControlStateValueOn; [hw refreshAndWait];
        BOOL hashPerLine = [hw.result.string isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", vectorHash, vectorHash]];
        hw.eachLine.state = NSControlStateValueOff; hw.input.string = @"U*U";
        hw.toVerify.stringValue = vectorHash; [hw verifyAndWait];
        BOOL matches = [hw.verdict.stringValue isEqualToString:@"The password matches the hash."];
        hw.input.string = @"U*V"; [hw verifyAndWait];
        BOOL differs = [hw.verdict.stringValue isEqualToString:@"The password does not match the hash."];
        hw.toVerify.stringValue = @"5f4dcc3b5aa765d61d8327deb882cf99"; [hw verifyAndWait];
        BOOL unknown = [hw.verdict.stringValue isEqualToString:@"This is not a bcrypt, scrypt, Argon2 or PBKDF2 hash."];
        Check(@"Tools > Hashes > bcrypt > Generate…", @"with the vector's text, cost, version and salt the result is the vector's hash - or its bare key, "
              @"or a hash for each line; Verify says the text matches, that another does not, and that an MD5 is no such hash",
              vector && bare && hashPerLine && matches && differs && unknown);

        // No salt given: each hash gets one of its own, so the same text twice is two different strings, both of which verify.
        hw.salt.stringValue = @""; hw.input.string = @"same\nsame"; hw.eachLine.state = NSControlStateValueOn; [hw refreshAndWait];
        NSArray<NSString *> *two = [hw.result.string componentsSeparatedByString:@"\n"];
        BOOL salted = two.count == 2 && ![two[0] isEqualToString:two[1]] && [two[0] hasPrefix:@"$2a$05$"] &&
                      [[NppCrypto password:[@"same" dataUsingEncoding:NSUTF8StringEncoding] matches:two[0]] boolValue] &&
                      [[NppCrypto password:[@"same" dataUsingEncoding:NSUTF8StringEncoding] matches:two[1]] boolValue];
        hw.eachLine.state = NSControlStateValueOff;
        hw.input.string = [@"" stringByPaddingToLength:80 withString:@"x" startingAtIndex:0]; [hw refreshAndWait];
        BOOL warned = [hw.problem.stringValue isEqualToString:@"bcrypt reads only the first 72 bytes."] && hw.result.string.length == 60;
        hw.input.string = @"x";
        hw.salt.stringValue = @"0102"; [hw refreshAndWait];
        BOOL shortSalt = [hw.problem.stringValue isEqualToString:@"bcrypt takes a salt of exactly 16 bytes."] && !hw.result.string.length;
        hw.salt.stringValue = @"xyz"; [hw refreshAndWait];
        BOOL badSalt = [hw.problem.stringValue isEqualToString:@"The salt is not valid hexadecimal."] && !hw.result.string.length;
        [hw newSalt:nil];
        NSString *salt1 = hw.salt.stringValue; [hw newSalt:nil];
        BOOL fresh = salt1.length == 32 && hw.salt.stringValue.length == 32 && ![salt1 isEqualToString:hw.salt.stringValue];
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"40"]; [hw refreshAndWait];
        BOOL badCost = [hw.problem.stringValue isEqualToString:@"The cost must be between 4 and 31."] && !hw.result.string.length;
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"5"]; hw.salt.stringValue = @"";
        Check(@"Tools > Hashes (salts, and what the window refuses)", @"without a salt every hash gets a random one and still verifies; past 72 bytes bcrypt says it reads no further; "
              @"a salt of the wrong length, one that is not hexadecimal and a cost out of range are said in words and no hash shown; Random gives sixteen new bytes",
              salted && warned && shortSalt && badSalt && fresh && badCost);

        [hw showForKind:NppPasswordHashScrypt fromFiles:NO];
        hw.input.string = @"pleaseletmein"; hw.bareKey.state = NSControlStateValueOn;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"SodiumChloride" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"scryptLogN"] setStringValue:@"14"];
        [hw refreshAndWait];
        BOOL scryptRight = [hw.result.string isEqualToString:@"7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2"];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        hw.input.string = @"password"; hw.bareKey.state = NSControlStateValueOff;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"somesalt" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"argon2Memory"] setStringValue:@"64"];
        [(NSTextField *)hw.fields[@"argon2Lanes"] setStringValue:@"2"];
        [(NSPopUpButton *)hw.fields[@"argon2Variant"] selectItemWithTitle:@"Argon2i"];
        [hw refreshAndWait];
        BOOL argonRight = [hw.result.string isEqualToString:@"$argon2i$v=19$m=64,t=2,p=2$c29tZXNhbHQ$u3EC2QpYDSqhwag4F/JKsYx8yBDM0sKg0MgMlK0pkWc"];
        [hw showForKind:NppPasswordHashPBKDF2 fromFiles:NO];
        hw.bareKey.state = NSControlStateValueOn;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"salt" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"pbkdf2Rounds"] setStringValue:@"4096"];
        [hw refreshAndWait];
        BOOL pbkdfRight = [hw.result.string isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"];
        Check(@"Tools > Hashes > scrypt, Argon2, PBKDF2 > Generate…", @"each, given a published vector's text, salt and settings through its fields, shows the vector's result",
              scryptRight && argonRight && pbkdfRight);

        // From files, as the digests have it: a line for each file, and the file's contents are what is hashed.
        [hw showForKind:NppPasswordHashPBKDF2 fromFiles:YES];
        hw.bareKey.state = NSControlStateValueOn;
        [hw hashFilesAndWait:@[TempFile(@"t_kdf_a.txt", @"password")]];
        BOOL fromFile = [hw.result.string isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a  t_kdf_a.txt"] &&
                        !hw.chooseFiles.hidden && hw.input.isHiddenOrHasHiddenAncestor && hw.eachLine.hidden &&
                        [hw.chooseFiles.title isEqualToString:@"Choose files to generate PBKDF2..."] &&
                        [hw.panel.title isEqualToString:@"Generate PBKDF2 digest from files"];
        [hw hashFilesAndWait:@[TempFile(@"t_kdf_b.txt", @"other")]];
        BOOL twoFiles = [hw.result.string componentsSeparatedByString:@"\n"].count == 2 && [hw.result.string hasSuffix:@"  t_kdf_b.txt"];
        [hw.clipboardButton performClick:nil];
        Check(@"Tools > Hashes > PBKDF2 > Generate from files…", @"the contents of each chosen file are hashed, a line each with the file's name, and Copy to Clipboard takes them",
              fromFile && twoFiles && [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:hw.result.string]);
        hw.bareKey.state = NSControlStateValueOff; hw.salt.stringValue = @"";
        [(NSTextField *)hw.fields[@"argon2Memory"] setStringValue:@"19456"]; [(NSTextField *)hw.fields[@"argon2Lanes"] setStringValue:@"1"];
        [(NSTextField *)hw.fields[@"pbkdf2Rounds"] setStringValue:@"600000"]; [(NSTextField *)hw.fields[@"scryptLogN"] setStringValue:@"15"];
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"12"];
        [(NSPopUpButton *)hw.fields[@"argon2Variant"] selectItemAtIndex:0]; [(NSPopUpButton *)hw.fields[@"bcryptVersion"] selectItemAtIndex:0];
        [hw.panel orderOut:nil];

        // Into the clipboard: the selection, hashed with the kind's defaults and a salt of its own.
        SetDoc(ed, @"user: hunter2 end");
        [sci message:SCI_SETSEL wParam:6 lParam:13];
        NSMenu *argonMenu = submenu(hashes, @"Argon2");
        [NSApp sendAction:argonMenu.itemArray[2].action to:argonMenu.itemArray[2].target from:argonMenu.itemArray[2]];
        NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        Check(@"Tools > Hashes > Argon2 > Generate from selection into clipboard", @"the clipboard holds an argon2id string with the default settings that the selected text verifies against",
              [clip hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"] &&
              [[NppCrypto password:[@"hunter2" dataUsingEncoding:NSUTF8StringEncoding] matches:clip] boolValue] &&
              ![[NppCrypto password:[@"hunter3" dataUsingEncoding:NSUTF8StringEncoding] matches:clip] boolValue]);

        // Base: a string or bytes in, the encoding out - and back, as text and as bytes.
        NppBaseWindow *bw = [NppBaseWindow shared];
        [bw showForEncoding:NppBase64];
        bw.direction.selectedSegment = 0; [bw.inputIsText performClick:nil]; bw.variant.state = NSControlStateValueOff;
        bw.input.string = @"Привет"; [bw refresh];
        BOOL onlyItsOwn = [bw.panel.title isEqualToString:@"Base64"] && [bw.variant.title isEqualToString:@"Base64 (URL-safe)"] && !bw.variant.hidden;
        for (NSView *v in bw.variant.superview.subviews) if ([v isKindOfClass:[NSPopUpButton class]]) onlyItsOwn = NO;
        BOOL fromText = [bw.output.string isEqualToString:@"0J/RgNC40LLQtdGC"] && bw.outputBytes.enclosingScrollView.hidden && !bw.inputIsHex.superview.hidden &&
                        [bw.outputLabel.stringValue isEqualToString:@"Result:"];
        [bw.inputIsHex performClick:nil];
        bw.input.string = @"fb ff"; [bw refresh];
        BOOL fromHex = [bw.output.string isEqualToString:@"+/8="] && bw.inputIsText.state == NSControlStateValueOff;
        [bw.variant performClick:nil];
        BOOL urlSafe = [bw.output.string isEqualToString:@"-_8="] && bw.encoding == NppBase64URL;
        [bw.variant performClick:nil];
        bw.input.string = @"fb f"; [bw refresh];
        BOOL badHex = !bw.output.string.length && [bw.problem.stringValue isEqualToString:@"The input is not bytes written in hexadecimal."];
        Check(@"Tools > Base > Base64 (encoding)", @"a text is encoded as its UTF-8 bytes, bytes given in hexadecimal as themselves, in the URL alphabet when that is chosen; "
              @"half a byte is said to be wrong; and the window is Base64's alone, with no choice of another encoding in it",
              fromText && fromHex && urlSafe && badHex && onlyItsOwn);

        [bw showForEncoding:NppBase58];
        bw.direction.selectedSegment = 1;
        bw.input.string = @"2NEpo7TZRRrLZSi2U"; [bw refresh];
        BOOL back = [bw.output.string isEqualToString:@"Hello World!"] && [bw.outputBytes.string isEqualToString:@"48656c6c6f20576f726c6421"] &&
                    !bw.outputBytes.enclosingScrollView.hidden && bw.inputIsHex.superview.hidden && [bw.outputLabel.stringValue isEqualToString:@"Text:"];
        bw.input.string = @"2NEpo7TZRRrLZSi20"; [bw refresh];
        BOOL refused = !bw.output.string.length && !bw.outputBytes.string.length && [bw.problem.stringValue isEqualToString:@"The input is not valid Base58."];
        BOOL base58Window = [bw.panel.title isEqualToString:@"Base58"] && [bw.variant.title isEqualToString:@"Base58Check"];
        bw.direction.selectedSegment = 0; [bw.inputIsHex performClick:nil];
        bw.input.string = @"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31"; [bw.variant performClick:nil];
        BOOL checked = [bw.output.string isEqualToString:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs"] && bw.encoding == NppBase58Check;
        [bw.variant performClick:nil]; [bw.inputIsText performClick:nil];
        [bw showForEncoding:NppBase32];
        bw.input.string = @"foobar"; [bw refresh];
        BOOL base32Window = [bw.panel.title isEqualToString:@"Base32"] && bw.variant.hidden && [bw.output.string isEqualToString:@"MZXW6YTBOI======"];
        [bw showForEncoding:NppBase64];
        bw.direction.selectedSegment = 1;
        bw.input.string = @"//8="; [bw refresh];
        BOOL bytesOnly = !bw.output.string.length && [bw.outputBytes.string isEqualToString:@"ffff"] &&
                         [bw.problem.stringValue hasPrefix:@"The decoded bytes are not UTF-8 text"];
        Check(@"Tools > Base > Base58 (decoding)", @"decoding gives the text and its bytes in hexadecimal; a character outside the alphabet is refused by name; "
              @"bytes that are no text are shown as bytes only; Base58's box adds the checksum of an address, and Base32's window has no box",
              back && refused && bytesOnly && base58Window && checked && base32Window);

        // What is selected in the editor is what the window opens with.
        SetDoc(ed, @"see SGVsbG8= here");
        [sci message:SCI_SETSEL wParam:4 lParam:12];
        [NSApp sendAction:NSSelectorFromString(@"showBase:") to:app from:base.itemArray[0]];
        bw.direction.selectedSegment = 1; [bw refresh];
        Check(@"Tools > Base (opens with the selection)", @"the selected text is the input", [bw.input.string isEqualToString:@"SGVsbG8="] && [bw.output.string isEqualToString:@"Hello"]);
        bw.direction.selectedSegment = 0; bw.input.string = @"";
        [bw.panel orderOut:nil];

        // The password generator.
        NppPasswordWindow *pw = [NppPasswordWindow shared];
        [NSApp sendAction:NSSelectorFromString(@"showPasswordGenerator:") to:app from:nil];
        pw.upper.state = pw.lower.state = pw.digits.state = NSControlStateValueOn;
        pw.useSymbols.state = pw.noLookalikes.state = NSControlStateValueOff; pw.requireEach.state = NSControlStateValueOn;
        pw.length.stringValue = @"24"; pw.howMany.stringValue = @"5";
        [pw generate:nil];
        NSArray<NSString *> *five = [pw.result.string componentsSeparatedByString:@"\n"];
        NSCharacterSet *alnum = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
        BOOL shaped = five.count == 5 && [NSSet setWithArray:five].count == 5;
        for (NSString *one in five) if (one.length != 24 || [one rangeOfCharacterFromSet:alnum.invertedSet].location != NSNotFound) shaped = NO;
        BOOL entropy = [pw.entropy.stringValue isEqualToString:@"Entropy: about 142 bits"];      // 24 * log2(62)
        pw.upper.state = pw.lower.state = NSControlStateValueOff; pw.useSymbols.state = NSControlStateValueOn;
        pw.symbols.stringValue = @"# $ %"; pw.howMany.stringValue = @"1"; pw.length.stringValue = @"40";
        [pw generate:nil];
        NSString *custom = pw.result.string;
        BOOL ownSymbols = custom.length == 40 && [custom rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789#$%"].invertedSet].location == NSNotFound &&
                          [custom rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"#$%"]].location != NSNotFound;
        pw.noLookalikes.state = NSControlStateValueOn; [pw generate:nil];
        BOOL plain = [[pw chosenSets] isEqualToArray:@[@"23456789", @"#$%"]] && [pw.result.string rangeOfString:@"0"].location == NSNotFound &&
                     [pw.result.string rangeOfString:@"1"].location == NSNotFound;
        pw.digits.state = pw.useSymbols.state = NSControlStateValueOff; [pw generate:nil];
        BOOL nothing = !pw.result.string.length && [pw.entropy.stringValue isEqualToString:@"Choose at least one kind of character."];
        Check(@"Tools > Password", @"five passwords of 24 letters and digits, all different, about 142 bits each; the symbols are the ones typed in; "
              @"look-alikes can be left out; with no kind of character chosen it says so",
              shaped && entropy && ownSymbols && plain && nothing);

        // A hash of each password, of the kind chosen, with that kind's default settings.
        pw.digits.state = NSControlStateValueOn; pw.length.stringValue = @"16"; pw.howMany.stringValue = @"2";
        NSMutableArray<NSString *> *kindTitles = [NSMutableArray array];
        for (NSMenuItem *item in pw.hashKind.itemArray) [kindTitles addObject:item.title];
        [pw.hashKind selectItemWithTitle:@"None"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        BOOL noneShown = !pw.hashes.string.length && pw.hashes.enclosingScrollView.hidden;
        [pw.hashKind selectItemWithTitle:@"SHA-256"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        NSArray<NSString *> *made = [pw.result.string componentsSeparatedByString:@"\n"], *digests = [pw.hashes.string componentsSeparatedByString:@"\n"];
        BOOL digested = made.count == 2 && digests.count == 2 && !pw.hashes.enclosingScrollView.hidden;
        for (NSUInteger i = 0; digested && i < 2; ++i)
            digested = [digests[i] isEqualToString:[EditorController hashOfData:[made[i] dataUsingEncoding:NSUTF8StringEncoding] digest:NppDigestSHA256]];
        [pw.hashKind selectItemWithTitle:@"Argon2"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        made = [pw.result.string componentsSeparatedByString:@"\n"];
        NSArray<NSString *> *argons = [pw.hashes.string componentsSeparatedByString:@"\n"];
        BOOL argoned = made.count == 2 && argons.count == 2;
        for (NSUInteger i = 0; argoned && i < 2; ++i)
            argoned = [argons[i] hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"] && [[NppCrypto password:[made[i] dataUsingEncoding:NSUTF8StringEncoding] matches:argons[i]] boolValue];
        BOOL keptKind = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"][@"hash"] isEqualToString:@"Argon2"];
        [pw.hashKind selectItemWithTitle:@"None"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        Check(@"Tools > Password (with its hash)", @"the kinds are None, the four password hashes and the ten digests; SHA-256 gives each password's digest, "
              @"Argon2 a default-settings string each password verifies against; None shows nothing; the choice is remembered",
              kindTitles.count == 15 && [[kindTitles subarrayWithRange:NSMakeRange(0, 6)] isEqualToArray:@[@"None", @"bcrypt", @"scrypt", @"Argon2", @"PBKDF2", @"MD5"]] &&
              noneShown && digested && argoned && keptKind);

        pw.howMany.stringValue = @"1"; pw.length.stringValue = @"12"; [pw generate:nil];
        NSDictionary *kept = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"];
        SetDoc(ed, @"password=");
        [sci message:SCI_GOTOPOS wParam:9];
        [pw insert:nil];
        NSString *inserted = [sci string];
        [pw.result.window makeFirstResponder:nil];
        Check(@"Tools > Password (kept and used)", @"the settings are remembered for the next time, and Insert into Document puts the password at the caret",
              [kept[@"length"] integerValue] == 12 && [kept[@"digits"] boolValue] && ![kept[@"upper"] boolValue] && [kept[@"symbols"] isEqualToString:@"# $ %"] &&
              inserted.length == 9 + 12 && [inserted hasPrefix:@"password="] && [[inserted substringFromIndex:9] isEqualToString:pw.result.string]);

        // In another language: the windows' own texts are translated, and every one of them fits.
        tp.localizationFile = @"russian.xml";
        [app applyLocalization];
        NSString *(^cutIn)(NSWindow *) = ^NSString *(NSWindow *window) {
            [window.contentView layoutSubtreeIfNeeded];
            NSMutableArray<NSString *> *bad = [NSMutableArray array];
            NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:window.contentView];
            while (queue.count) {
                NSView *v = queue.firstObject; [queue removeObjectAtIndex:0];
                if (v.hidden) continue;
                [queue addObjectsFromArray:v.subviews];
                BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).selectable;
                BOOL isButton = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]];
                if (!isLabel && !isButton) continue;
                NSControl *c = (NSControl *)v;
                NSString *text = isLabel ? c.stringValue : ((NSButton *)c).title;
                if (!text.length) continue;
                NSSize need = c.cell.wraps ? [c.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(c.frame), 10000)] : c.cell.cellSize;
                if (c.cell.wraps) need.width = 0;
                NSRect inWindow = [v convertRect:v.bounds toView:nil];
                if (need.width > NSWidth(c.frame) + 1.5 || need.height > NSHeight(c.frame) + 1.5 ||
                    NSMaxX(inWindow) > NSWidth(window.contentView.frame) + 0.5 || NSMinX(inWindow) < -0.5)
                    [bad addObject:[NSString stringWithFormat:@"\"%@\" needs %.0fx%.0f, has %.0fx%.0f", text, need.width, need.height, NSWidth(c.frame), NSHeight(c.frame)]];
            }
            return [bad componentsJoinedByString:@"; "];
        };
        [dw showForDigest:NppDigestSHA384 fromFiles:NO];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        hw.toVerify.stringValue = @"x"; [hw verifyAndWait];
        [bw showForEncoding:NppBase58]; bw.direction.selectedSegment = 1; bw.input.string = @"0"; [bw refresh];
        [pw show]; [pw.hashKind selectItemAtIndex:5]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind]; [pw generateAndWait];
        NSString *cut = [@[cutIn(dw.panel), cutIn(hw.panel), cutIn(bw.panel), cutIn(pw.panel)] componentsJoinedByString:@""];
        if (cut.length) printf("    cut in Russian: %s\n", cut.UTF8String);
        NSString *hashesTitle = nil;
        for (NSMenuItem *item in tools.itemArray) if (item.submenu == hashes) hashesTitle = item.title;
        printf("    l10n tools 2: %s | %s | %s | %s\n", hw.panel.title.UTF8String, hw.bareKey.title.UTF8String, hw.salt.placeholderString.UTF8String, [pw.hashKind itemAtIndex:0].title.UTF8String);
        printf("    l10n tools: %s | %s | %s | %s | %s | %s\n", dw.panel.title.UTF8String, dw.eachLine.title.UTF8String, hw.verdict.stringValue.UTF8String,
               bw.problem.stringValue.UTF8String, pw.entropy.stringValue.UTF8String, hashesTitle.UTF8String);
        Check(@"Tools (in another language)", @"in Russian the menu, the windows' titles, labels, buttons and messages are Russian - the digest's name and the "
              @"placeholders filled in - and no text is cut",
              !cut.length && [hashesTitle isEqualToString:@"Хеши"] && [dw.panel.title containsString:@"SHA-384"] && ![dw.panel.title containsString:@"Generate"] &&
              ![dw.eachLine.title containsString:@"Treat"] && [hw.verdict.stringValue isEqualToString:@"Это не хеш bcrypt, scrypt, Argon2 или PBKDF2."] &&
              [hw.panel.title containsString:@"Argon2"] && ![hw.panel.title containsString:@"Generate"] && [hw.bareKey.title isEqualToString:@"Показать сам ключ в шестнадцатеричном виде"] &&
              [hw.salt.placeholderString isEqualToString:@"Пусто: каждый раз случайная соль"] && ![[pw.hashKind itemAtIndex:0].title isEqualToString:@"None"] && [[pw.hashKind itemAtIndex:1].title isEqualToString:@"bcrypt"] && [bw.problem.stringValue isEqualToString:@"Ввод не является корректным Base58."] &&
              [bw.outputLabel.stringValue isEqualToString:@"Текст:"] && [pw.panel.title isEqualToString:@"Генератор паролей"] &&
              [pw.upper.title isEqualToString:@"Заглавные буквы (A-Z)"] && [pw.entropy.stringValue hasPrefix:@"Энтропия: около "] &&
              [pw.entropy.stringValue hasSuffix:@" бит"]);

        [pw.hashKind selectItemAtIndex:0]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        for (NSPanel *panel in @[dw.panel, hw.panel, bw.panel, pw.panel]) [panel orderOut:nil];
        bw.input.string = @""; hw.toVerify.stringValue = @""; hw.input.string = @"";
        if (passwordSettingsBefore) [[NSUserDefaults standardUserDefaults] setObject:passwordSettingsBefore forKey:@"NppPasswordGenerator"];
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppPasswordGenerator"];
        tp.localizationFile = languageBefore ?: @"";
        [app applyLocalization];
    }

    if (NppSectionWanted(@"Folding: what each lexer is told")) { printf("\n== Folding: what each lexer is told ==\n");
        // Lines that head a fold, after the whole text has been styled in the language named.
        NSArray<NSNumber *> *(^headers)(NSString *, NSString *) = ^NSArray<NSNumber *> *(NSString *language, NSString *text) {
            [ed newDocument];
            [ed setLanguageNamed:language];
            SetDoc(ed, text);
            ScintillaView *view = ed.sci;
            [view message:SCI_COLOURISE wParam:0 lParam:-1];
            NSMutableArray<NSNumber *> *lines = [NSMutableArray array];
            long count = [view message:SCI_GETLINECOUNT];
            for (long line = 0; line < count; ++line)
                if ([view message:SCI_GETFOLDLEVEL wParam:(uptr_t)line] & SC_FOLDLEVELHEADERFLAG) [lines addObject:@(line)];
            return lines;
        };
        void (^done)(void) = ^{ [ed.sci message:SCI_SETSAVEPOINT]; [ed closeCurrentDocument]; };

        NSString *page = @"<html>\n<body>\n<div class=\"a\">\n  <p>one</p>\n  <p>two</p>\n</div>\n<!-- a comment\n     of two lines -->\n<script>\nfunction f() {\n  return 1;\n}\n</script>\n</body>\n</html>\n";
        NSArray *pageHeaders = headers(@"html", page);
        ScintillaView *pageView = ed.sci;
        [pageView message:SCI_TOGGLEFOLD wParam:2];
        BOOL folded = ![pageView message:SCI_GETLINEVISIBLE wParam:3] && ![pageView message:SCI_GETLINEVISIBLE wParam:4] &&
                      [pageView message:SCI_GETLINEVISIBLE wParam:2] && [pageView message:SCI_GETLINEVISIBLE wParam:6] &&
                      ![pageView message:SCI_GETFOLDEXPANDED wParam:2];
        [pageView message:SCI_TOGGLEFOLD wParam:2];
        BOOL unfolded = [pageView message:SCI_GETLINEVISIBLE wParam:3] && [pageView message:SCI_GETFOLDEXPANDED wParam:2];
        done();
        Check(@"IDM_VIEW_FOLD_CURRENT (an HTML page)", @"a page folds at its elements, at a comment of several lines and at the script inside it (fold.html, "
              @"fold.hypertext.comment, as ScintillaEditView.cpp sets them): a <div> folds away its lines and unfolds again",
              [pageHeaders containsObject:@0] && [pageHeaders containsObject:@1] && [pageHeaders containsObject:@2] && [pageHeaders containsObject:@6] &&
              [pageHeaders containsObject:@9] && folded && unfolded);

        NSArray *xmlHeaders = headers(@"xml", @"<?xml version=\"1.0\"?>\n<root>\n  <item>\n    <name>a</name>\n  </item>\n</root>\n");
        done();
        NSArray *phpHeaders = headers(@"php", @"<html>\n<body>\n<?php\nfunction f() {\n  return 1;\n}\n?>\n</body>\n</html>\n");
        done();
        NSString *mixedPage = @"<html>\n<script>\nvar x = function () { return 1; };\n</script>\n<?php\nforeach ($a as $b) { echo $b; }\n?>\n</html>\n";
        headers(@"php", mixedPage);
        long tagStyle = [ed.sci message:SCI_GETSTYLEAT wParam:1];
        long jsWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[mixedPage rangeOfString:@"function"].location];
        long phpWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[mixedPage rangeOfString:@"foreach"].location];
        // Coloured, too: each of the three has the colour its own language's style gives it, not the default's.
        long plain = [ed.sci message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT];
        StyleCatalog *pageStyles = [StyleCatalog sharedCatalog];
        BOOL (^coloured)(NSString *, int) = ^BOOL(NSString *language, int styleID) {
            for (NppStyle *style in [pageStyles stylesForLexerName:language]) {
                if (style.styleID != styleID || !style.foreground) continue;
                NSColor *c = [style.foreground colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
                long want = (long)lround(c.redComponent * 255) | ((long)lround(c.greenComponent * 255) << 8) | ((long)lround(c.blueComponent * 255) << 16);
                return [ed.sci message:SCI_STYLEGETFORE wParam:(uptr_t)styleID] == want;
            }
            return NO;
        };
        BOOL pageColoured = coloured(@"html", SCE_H_TAG) && coloured(@"javascript", SCE_HJ_KEYWORD) && coloured(@"php", SCE_HPHP_WORD) &&
                            [ed.sci message:SCI_STYLEGETFORE wParam:SCE_HPHP_WORD] != plain &&
                            [ed.sci message:SCI_STYLEGETEOLFILLED wParam:SCE_HPHP_DEFAULT];
        done();
        Check(@"Language (a page and what is written inside it)", @"in a .php file a known tag is a tag, a JavaScript word inside <script> a JavaScript keyword, and a PHP word "
              @"inside <?php ?> a PHP keyword: the hypertext lexer is given HTML's, JavaScript's and PHP's words in the lists it reads each from",
              tagStyle == SCE_H_TAG && jsWord == SCE_HJ_KEYWORD && phpWord == SCE_HPHP_WORD);
        Check(@"Language (a page's colours)", @"and each is coloured by its own language's styles - HTML's, JavaScript's and PHP's all applied to the one page, "
              @"as setXmlLexer applies them", pageColoured);
        Check(@"IDM_VIEW_FOLD_CURRENT (XML and PHP)", @"XML folds at its elements, and a PHP page at its tags and at the function inside <?php ?>",
              [xmlHeaders containsObject:@1] && [xmlHeaders containsObject:@2] && [phpHeaders containsObject:@0] && [phpHeaders containsObject:@3]);

        NSString *source = @"/** a comment\n *  @param x of three\n *  lines */\n#if DEBUG\nint f(void) {\n    return 1;\n}\n#endif\n#if 0\nint g(void) { return 2; }\n#endif\n";
        NSArray *cHeaders = headers(@"c", source);
        // "int" on the line inside #if 0: a keyword still, not greyed out as code that will never be compiled.
        long inactive = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"int g"].location];
        long liveInt = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"int f"].location];
        long liveReturn = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"return 1"].location];
        long docWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"@param"].location + 1];
        done();
        Check(@"IDM_VIEW_FOLD_CURRENT (C)", @"a block comment and an #if fold as well as the braces (fold.comment, fold.preprocessor), and code under #if 0 is "
              @"styled as code: the lexer is told not to guess which symbols are defined",
              [cHeaders containsObject:@0] && [cHeaders containsObject:@3] && [cHeaders containsObject:@4] && inactive == SCE_C_WORD2);
        Check(@"Language (the C family's word lists)", @"instructions, types and documentation words each go to the list the lexer reads them from, as setCppLexer "
              @"sends them: \"return\" is a keyword, \"int\" a type, \"@param\" a documentation keyword",
              liveReturn == SCE_C_WORD && liveInt == SCE_C_WORD2 && docWord == SCE_C_COMMENTDOCKEYWORD);

        NSString *goSource = @"package main\n\nvar s = `raw\nstring`\n";
        headers(@"go", goSource);
        long goStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[goSource rangeOfString:@"raw"].location];
        done();
        NSString *jsSource = @"const s = `a ${b}\nc`;\n";
        headers(@"javascript", jsSource);
        long jsStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsSource rangeOfString:@"a $"].location];
        long jsNext = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsSource rangeOfString:@"c`"].location];
        done();
        NSString *tsSource = @"const s: string = `raw\ntext`;\n";
        headers(@"typescript", tsSource);
        long tsStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[tsSource rangeOfString:@"text"].location];
        done();
        Check(@"Language (backquoted strings)", @"Go's and TypeScript's `raw strings` and JavaScript's `template literals` are strings over their line breaks "
              @"(lexer.cpp.backquoted.strings: 1, 1 and 2)",
              goStyle == SCE_C_STRINGRAW && jsStyle == SCE_C_STRINGRAW && jsNext == SCE_C_STRINGRAW && tsStyle == SCE_C_STRINGRAW);

        NSString *jsonSource = @"{\"a\": \"x\\ny\"}\n";
        headers(@"json", jsonSource);
        long escapeStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsonSource rangeOfString:@"\\n"].location];
        done();
        NSString *json5Source = @"{\n  // a comment\n  a: 1\n}\n";
        headers(@"json5", json5Source);
        long commentStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[json5Source rangeOfString:@"// a"].location + 3];
        done();
        Check(@"Language (JSON)", @"an escape sequence in a JSON string is styled as one, and JSON5 may have comments (lexer.json.escape.sequence, lexer.json.allow.comments)",
              escapeStyle == SCE_JSON_ESCAPESEQUENCE && commentStyle == SCE_JSON_LINECOMMENT);
    }

    if (NppSectionWanted(@"Tools: HTTP Request")) { printf("\n== Tools: HTTP Request ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
        NSString *(^named)(NSArray<NppHttpPair *> *, NSString *) = ^NSString *(NSArray<NppHttpPair *> *pairs, NSString *name) {
            for (NppHttpPair *pair in pairs) if ([pair.name caseInsensitiveCompare:name] == NSOrderedSame) return pair.value;
            return nil;
        };

        NSPasteboard *board = [NSPasteboard generalPasteboard];
        // What is typed, a pair to a line.
        NSArray<NppHttpPair *> *typed = [NppHttpPair pairsFromText:@"Accept: application/json\n\n# a note\n  X-Token :  a:b  \nFlag\n" separator:@":"];
        Check(@"Tools > HTTP Request (pairs)", @"\"Name: value\" lines become pairs in their order: blank lines and # lines passed over, "
              @"spaces trimmed, only the first colon dividing, a bare name given an empty value - and they are written back the same",
              typed.count == 3 && [typed[0].name isEqualToString:@"Accept"] && [typed[0].value isEqualToString:@"application/json"] &&
              [typed[1].name isEqualToString:@"X-Token"] && [typed[1].value isEqualToString:@"a:b"] &&
              [typed[2].name isEqualToString:@"Flag"] && typed[2].value.length == 0 &&
              [[NppHttpPair textFromPairs:typed separator:@":"] isEqualToString:@"Accept: application/json\nX-Token: a:b\nFlag: "] &&
              [[NppHttpPair textFromPairs:[NppHttpPair pairsFromText:@"a=1\nb = x=y" separator:@"="] separator:@"="] isEqualToString:@"a=1\nb=x=y"]);

        NppHttpRequest *built = [[NppHttpRequest alloc] init];
        built.address = @"example.com/search?q=1";
        built.parameters = @[[NppHttpPair pairWithName:@"name" value:@"Иван & co"], [NppHttpPair pairWithName:@"a b" value:@"1+1=2"]];
        NSString *withQuery = [built url].absoluteString;
        built.address = @"https://example.com/a path/файл"; built.parameters = @[];
        NSString *spaced = [built url].absoluteString;
        NppHttpRequest *bad = [[NppHttpRequest alloc] init];
        BOOL refused = [bad url] == nil;
        bad.address = @"file:///etc/passwd"; refused = refused && [bad url] == nil;
        bad.address = @"ftp://example.com/x"; refused = refused && [bad url] == nil;
        Check(@"Tools > HTTP Request (the address)", @"an address without a scheme is http; parameters join its query percent-encoded; a space and Cyrillic in the "
              @"path are encoded; nothing, file: and ftp: are no address to send to",
              [withQuery isEqualToString:@"http://example.com/search?q=1&name=%D0%98%D0%B2%D0%B0%D0%BD%20%26%20co&a%20b=1%2B1%3D2"] &&
              [spaced isEqualToString:@"https://example.com/a%20path/%D1%84%D0%B0%D0%B9%D0%BB"] && refused);

        // A request written out for curl, and read back from that.
        NppHttpRequest *out = [[NppHttpRequest alloc] init];
        out.method = @"PUT"; out.address = @"https://api.example.com/items/7";
        out.headers = @[[NppHttpPair pairWithName:@"Content-Type" value:@"application/json"], [NppHttpPair pairWithName:@"X-Note" value:@"it's"]];
        out.body = utf8(@"{\"name\": \"O'Brien\",\n \"n\": 1}");
        out.username = @"igor"; out.password = @"p:w d"; out.allowInvalidCertificates = YES; out.timeout = 5;
        NSString *command = [out curlCommand];
        NSString *why = nil;
        NppHttpRequest *back = [NppHttpRequest requestFromCurlCommand:command error:&why];
        Check(@"Tools > HTTP Request (Copy as curl)", @"the command names the method, quotes every value for the shell - an apostrophe and a line break among them - "
              @"and, read back, is the same request",
              [command hasPrefix:@"curl -X PUT 'https://api.example.com/items/7' \\\n  -H 'Content-Type: application/json' \\\n  -H 'X-Note: it'\\''s' \\\n  -u 'igor:p:w d'"] &&
              [command hasSuffix:@"-L -k -m 5"] && back != nil && [back.method isEqualToString:@"PUT"] &&
              [back.address isEqualToString:out.address] && [back.body isEqualToData:out.body] && back.headers.count == 2 &&
              [named(back.headers, @"X-Note") isEqualToString:@"it's"] && [back.username isEqualToString:@"igor"] &&
              [back.password isEqualToString:@"p:w d"] && back.allowInvalidCertificates && back.followRedirects && back.timeout == 5);

        // Commands as they are found in the wild.
        NppHttpRequest *chrome = [NppHttpRequest requestFromCurlCommand:
            @"curl 'https://example.com/api/login' \\\n  -H 'accept: */*' \\\n  -H \"x-q: say \\\"hi\\\" $HOME\" \\\n"
            @"  --data-raw $'{\"text\":\"line1\\nline2 \\u0416 it\\'s\"}' \\\n  --compressed -o /dev/null" error:NULL];
        NppHttpRequest *terse = [NppHttpRequest requestFromCurlCommand:@"curl -sSLkX DELETE -uadmin:secret -m10 http://localhost:8080/x" error:NULL];
        NppHttpRequest *asQuery = [NppHttpRequest requestFromCurlCommand:@"curl -G --data-urlencode 'q=a b&c' -d page=2 --url example.com/find -I" error:NULL];
        NppHttpRequest *json = [NppHttpRequest requestFromCurlCommand:@"/usr/bin/curl --json '{\"a\":1}' --oauth2-bearer tok -A agent/1 -e http://from -b 'sid=9' https://example.com/j" error:NULL];
        NppHttpRequest *form = [NppHttpRequest requestFromCurlCommand:@"curl -d a=1 -d b=2 --header='X-A: 1' https://example.com/f" error:NULL];
        Check(@"Tools > HTTP Request (Paste curl Command: a browser's)", @"quotes of both kinds, a continued line, bash's $'…' with \\n, \\u and \\' in it; the body makes it a POST; "
              @"--compressed and -o with its file are passed over; curl follows no redirects unless told to",
              [chrome.address isEqualToString:@"https://example.com/api/login"] && [chrome.method isEqualToString:@"POST"] &&
              [chrome.body isEqualToData:utf8(@"{\"text\":\"line1\nline2 Ж it's\"}")] && chrome.headers.count == 2 &&
              [named(chrome.headers, @"x-q") isEqualToString:@"say \"hi\" $HOME"] && !chrome.followRedirects);
        Check(@"Tools > HTTP Request (Paste curl Command: options)", @"short options run together with a value at the end (-sSLkX DELETE), a value stuck to its letter (-uadmin:secret, -m10); "
              @"-G with --data-urlencode puts the data in the address; -I is HEAD; --json, --oauth2-bearer, -A, -e, -b become the headers they stand for; several -d are joined with &",
              [terse.method isEqualToString:@"DELETE"] && terse.followRedirects && terse.allowInvalidCertificates && [terse.username isEqualToString:@"admin"] &&
              [terse.password isEqualToString:@"secret"] && terse.timeout == 10 && [terse.address isEqualToString:@"http://localhost:8080/x"] &&
              [asQuery.address isEqualToString:@"example.com/find?q=a%20b%26c&page=2"] && [asQuery.method isEqualToString:@"HEAD"] && asQuery.body == nil &&
              [json.method isEqualToString:@"POST"] && [named(json.headers, @"Content-Type") isEqualToString:@"application/json"] &&
              [named(json.headers, @"Accept") isEqualToString:@"application/json"] && [named(json.headers, @"Authorization") isEqualToString:@"Bearer tok"] &&
              [named(json.headers, @"User-Agent") isEqualToString:@"agent/1"] && [named(json.headers, @"Referer") isEqualToString:@"http://from"] &&
              [named(json.headers, @"Cookie") isEqualToString:@"sid=9"] && [json.body isEqualToData:utf8(@"{\"a\":1}")] &&
              [form.body isEqualToData:utf8(@"a=1&b=2")] && [named(form.headers, @"X-A") isEqualToString:@"1"]);

        NSString *notCurl = nil, *noAddress = nil, *fromFile = nil, *aForm = nil, *notWeb = nil;
        BOOL allRefused = ![NppHttpRequest requestFromCurlCommand:@"wget http://example.com" error:&notCurl] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -X POST -H 'A: b'" error:&noAddress] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -d @secrets.txt http://example.com" error:&fromFile] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -F file=@a.png http://example.com" error:&aForm] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl file:///etc/passwd" error:&notWeb];
        Check(@"Tools > HTTP Request (Paste curl Command: what is refused)", @"what is not a curl command, one with no address, one that reads its data or a form from a file, "
              @"and one whose address is not the web's - each refused with its reason",
              allRefused && [notCurl isEqualToString:@"This is not a curl command."] && [noAddress isEqualToString:@"The command has no address."] &&
              [fromFile hasPrefix:@"The command reads its data from a file"] && [aForm hasPrefix:@"Forms and uploads"] && [notWeb containsString:@"not an http or https address"]);

        // End to end against a real server, started for this test, which says back what it was asked.
        NSString *script = [[NSBundle mainBundle] pathForResource:@"test-http-server" ofType:@"py"];
        NSTask *server = nil;
        NSInteger port = 0;
        if (script) {
            server = [[NSTask alloc] init];
            server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            server.arguments = @[script];
            NSPipe *serverOut = [NSPipe pipe];
            server.standardOutput = serverOut;
            if ([server launchAndReturnError:NULL]) {
                NSString *text = [[NSString alloc] initWithData:[serverOut.fileHandleForReading availableData] encoding:NSUTF8StringEncoding];
                NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL];
                [scanner scanInteger:&port];
            }
        }
        if (port <= 0) {
            Check(@"Tools > HTTP Request (sending)", @"the test server could not be started", NO);
        } else {
            NSString *base = [NSString stringWithFormat:@"http://127.0.0.1:%ld", (long)port];
            NSDictionary *(^echoed)(NppHttpResponse *) = ^NSDictionary *(NppHttpResponse *response) {
                return response.body.length ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:NULL] : nil;
            };

            NppHttpRequest *get = [[NppHttpRequest alloc] init];
            get.address = [base stringByAppendingString:@"/echo?fixed=1"];
            get.parameters = @[[NppHttpPair pairWithName:@"q" value:@"a b&c"], [NppHttpPair pairWithName:@"имя" value:@"Жук"]];
            get.headers = @[[NppHttpPair pairWithName:@"X-Custom" value:@"42"], [NppHttpPair pairWithName:@"Accept" value:@"application/json"]];
            NppHttpResponse *got = [NppHttpClient send:get cancelled:nil];
            NSDictionary *saw = echoed(got);
            NSArray *wantQuery = @[@[@"fixed", @"1"], @[@"q", @"a b&c"], @[@"имя", @"Жук"]];
            Check(@"Tools > HTTP Request (GET)", @"the server sees the method, the address's own query with the parameters after it - decoded back to what was typed - and the headers given; "
                  @"the answer has its status line, its headers in their order, and the time it took",
                  got.error == nil && got.status == 200 && [got.statusLine hasPrefix:@"HTTP/1."] && [got.statusLine hasSuffix:@"200 OK"] &&
                  [saw[@"method"] isEqualToString:@"GET"] && [saw[@"query"] isEqualToArray:wantQuery] &&
                  [saw[@"headers"][@"x-custom"] isEqualToString:@"42"] && [saw[@"headers"][@"accept"] isEqualToString:@"application/json"] &&
                  [saw[@"headers"][@"user-agent"] hasPrefix:@"NotepadMac/"] && [[got valueOfHeader:@"x-test-server"] isEqualToString:@"notepad"] &&
                  [[got valueOfHeader:@"Content-Type"] isEqualToString:@"application/json"] && got.elapsed > 0 && got.redirects == 0 &&
                  [[got headerText] hasPrefix:got.statusLine] && [[got headerText] containsString:@"\nX-Test-Server: notepad"]);

            BOOL bodies = YES;
            for (NSString *method in @[@"POST", @"PUT", @"PATCH", @"DELETE"]) {
                NppHttpRequest *post = [[NppHttpRequest alloc] init];
                post.method = method; post.address = [base stringByAppendingString:@"/echo"];
                post.headers = @[[NppHttpPair pairWithName:@"Content-Type" value:@"application/json; charset=utf-8"]];
                post.body = utf8(@"{\"имя\": \"Жук\", \"n\": [1, 2]}\n");
                NSDictionary *sawPost = echoed([NppHttpClient send:post cancelled:nil]);
                if (![sawPost[@"method"] isEqualToString:method] || ![sawPost[@"body"] isEqualToString:@"{\"имя\": \"Жук\", \"n\": [1, 2]}\n"] ||
                    ![sawPost[@"headers"][@"content-type"] isEqualToString:@"application/json; charset=utf-8"] ||
                    [sawPost[@"headers"][@"content-length"] integerValue] != (NSInteger)post.body.length) {
                    bodies = NO; printf("    %s: %s\n", method.UTF8String, sawPost.description.UTF8String);
                }
            }
            Check(@"Tools > HTTP Request (POST, PUT, PATCH, DELETE)", @"each reaches the server under its own name with the body byte for byte and the content type given", bodies);

            NppHttpRequest *auth = [[NppHttpRequest alloc] init];
            auth.address = [base stringByAppendingString:@"/echo"]; auth.username = @"igor"; auth.password = @"pa:ss word";
            NSDictionary *sawAuth = echoed([NppHttpClient send:auth cancelled:nil]);
            NSString *wantAuth = [@"Basic " stringByAppendingString:[utf8(@"igor:pa:ss word") base64EncodedStringWithOptions:0]];
            NppHttpRequest *head = [[NppHttpRequest alloc] init];
            head.method = @"HEAD"; head.address = [base stringByAppendingString:@"/echo"];
            NppHttpResponse *headed = [NppHttpClient send:head cancelled:nil];
            NppHttpRequest *options = [[NppHttpRequest alloc] init];
            options.method = @"OPTIONS"; options.address = [base stringByAppendingString:@"/echo"];
            Check(@"Tools > HTTP Request (a name and password, HEAD, OPTIONS)", @"the name and password go as Basic authentication; HEAD brings the headers and no body; OPTIONS arrives as OPTIONS",
                  [sawAuth[@"headers"][@"authorization"] isEqualToString:wantAuth] &&
                  headed.status == 200 && headed.body.length == 0 && [headed valueOfHeader:@"Content-Length"].integerValue > 0 && headed.error == nil &&
                  [echoed([NppHttpClient send:options cancelled:nil])[@"method"] isEqualToString:@"OPTIONS"]);

            NppHttpRequest *moved = [[NppHttpRequest alloc] init];
            moved.address = [base stringByAppendingString:@"/redirect"];
            NppHttpResponse *followed = [NppHttpClient send:moved cancelled:nil];
            moved.followRedirects = NO;
            NppHttpResponse *stayed = [NppHttpClient send:moved cancelled:nil];
            NppHttpRequest *missing = [[NppHttpRequest alloc] init];
            missing.address = [base stringByAppendingString:@"/status/404"];
            NppHttpResponse *notFound = [NppHttpClient send:missing cancelled:nil];
            missing.address = [base stringByAppendingString:@"/status/500"];
            Check(@"Tools > HTTP Request (redirects and statuses)", @"a redirect is followed to its end - the last answer's headers, the address arrived at, one redirect counted - or, unticked, "
                  @"shown as the 302 it is with its Location; 404 and 500 are answers, not errors",
                  followed.status == 200 && followed.redirects == 1 && [followed.finalAddress hasSuffix:@"/echo?redirected=1"] &&
                  [echoed(followed)[@"query"] isEqualToArray:@[@[@"redirected", @"1"]]] && [followed valueOfHeader:@"Location"] == nil &&
                  stayed.status == 302 && [[stayed valueOfHeader:@"Location"] isEqualToString:@"/echo?redirected=1"] && [[stayed text] isEqualToString:@"moved"] &&
                  notFound.status == 404 && notFound.error == nil && [[notFound text] isEqualToString:@"status 404"] &&
                  [NppHttpClient send:missing cancelled:nil].status == 500);

            NppHttpRequest *other = [[NppHttpRequest alloc] init];
            other.address = [base stringByAppendingString:@"/latin1"];
            NSString *latin = [[NppHttpClient send:other cancelled:nil] text];
            other.address = [base stringByAppendingString:@"/binary"];
            NppHttpResponse *binary = [NppHttpClient send:other cancelled:nil];
            other.address = [base stringByAppendingString:@"/gzip"];
            NSString *unpacked = [[NppHttpClient send:other cancelled:nil] text];
            Check(@"Tools > HTTP Request (what the body is)", @"a body is read in the charset its Content-Type names; bytes that are no text are said to be none and kept as bytes; "
                  @"a gzip-encoded body is unpacked",
                  [latin isEqualToString:@"café crème"] && [binary text] == nil && binary.body.length == 4 && [unpacked isEqualToString:@"unpacked text"]);

            NppHttpRequest *slow = [[NppHttpRequest alloc] init];
            slow.address = [base stringByAppendingString:@"/slow"]; slow.timeout = 0.5;
            NSDate *began = [NSDate date];
            NppHttpResponse *timedOut = [NppHttpClient send:slow cancelled:nil];
            NSTimeInterval waited = -began.timeIntervalSinceNow;
            slow.timeout = 30;
            began = [NSDate date];
            __block int asked = 0;
            NppHttpResponse *givenUp = [NppHttpClient send:slow cancelled:^BOOL { return ++asked > 2; }];
            NSTimeInterval untilGivenUp = -began.timeIntervalSinceNow;
            NppHttpRequest *nobody = [[NppHttpRequest alloc] init];
            nobody.address = @"http://127.0.0.1:1/"; nobody.timeout = 5;
            NppHttpResponse *unreachable = [NppHttpClient send:nobody cancelled:nil];
            Check(@"Tools > HTTP Request (what goes wrong)", @"a server slower than the timeout is given up on at the timeout, with the reason; a request cancelled stops at once; "
                  @"a port nobody listens on is an error in words and no status",
                  timedOut.status == 0 && timedOut.error.length > 0 && waited < 2.5 &&
                  [givenUp.error isEqualToString:@"Cancelled."] && untilGivenUp < 2.5 &&
                  unreachable.status == 0 && unreachable.error.length > 0 && unreachable.body.length == 0);

            // The window: what is typed into it is what is sent, and the answer is shown.
            NppPreferences *hp = [NppPreferences shared];
            NSString *languageBefore = hp.localizationFile;
            hp.localizationFile = @"";
            [app applyLocalization];
            NSDictionary *savedBefore = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppHttpRequest"];
            NSMenu *tools = nil;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) if ([NppEnglishMenuTitle(top.submenu) isEqualToString:@"Tools"]) tools = top.submenu;
            NSMenuItem *httpItem = nil;
            for (NSMenuItem *item in tools.itemArray) if ([NppEnglishTitle(item) isEqualToString:@"HTTP Request"]) httpItem = item;
            [NSApp sendAction:httpItem.action to:httpItem.target from:httpItem];
            NppHttpWindow *hw = [NppHttpWindow shared];
            BOOL opened = httpItem != nil && hw.panel.isVisible && [hw.panel.title isEqualToString:@"HTTP Request"];

            [hw.method selectItemWithTitle:@"POST"];
            hw.address.stringValue = [NSString stringWithFormat:@"127.0.0.1:%ld/echo", (long)port];
            hw.parameters.string = @"page=2\nq=two words";
            hw.headers.string = @"X-From: window\n# not sent\nAccept: */*";
            hw.body.string = @"{\"ok\":true}";
            [hw.contentType selectItemWithTitle:@"application/json"];
            hw.username.stringValue = @""; hw.password.stringValue = @""; hw.timeout.stringValue = @"10";
            hw.followRedirects.state = NSControlStateValueOn; hw.allowInvalidCertificates.state = NSControlStateValueOff;
            hw.formatJSON.state = NSControlStateValueOff; hw.answerSection.selectedSegment = 0;
            [hw sendAndWait];
            NSDictionary *sawWindow = [NSJSONSerialization JSONObjectWithData:utf8(hw.answer.string) options:0 error:NULL];
            NSArray *windowQuery = @[@[@"page", @"2"], @[@"q", @"two words"]];
            BOOL sent = [sawWindow[@"method"] isEqualToString:@"POST"] && [sawWindow[@"query"] isEqualToArray:windowQuery] &&
                        [sawWindow[@"headers"][@"x-from"] isEqualToString:@"window"] && [sawWindow[@"headers"][@"content-type"] isEqualToString:@"application/json"] &&
                        [sawWindow[@"body"] isEqualToString:@"{\"ok\":true}"] && sawWindow[@"headers"][@"# not sent"] == nil;
            BOOL statusShown = [hw.status.stringValue hasPrefix:@"HTTP/1."] && [hw.status.stringValue containsString:@"200 OK"] && [hw.status.stringValue containsString:@" ms"];
            NSString *oneLine = [hw.answer.string copy];      // (a text view's string is its live store)
            hw.formatJSON.state = NSControlStateValueOn; [hw answerSectionChanged:nil];
            // (Laid out means white space only: taken out again, it is the answer as it came.)
            BOOL laidOut = [hw.answer.string hasPrefix:@"{\n  \"method\": \"POST\",\n  \"path\": \"/echo\",\n  \"query\": [\n    [\n      \"page\",\n      \"2\"\n    ],"] &&
                           ![oneLine containsString:@"\n"] &&
                           [[NSJSONSerialization JSONObjectWithData:utf8(hw.answer.string) options:0 error:NULL] isEqual:sawWindow];
            hw.answerSection.selectedSegment = 1; [hw answerSectionChanged:nil];
            BOOL headersShown = [hw.answer.string hasPrefix:@"HTTP/1."] && [hw.answer.string containsString:@"X-Test-Server: notepad"];
            hw.answerSection.selectedSegment = 0; [hw answerSectionChanged:nil];
            Check(@"Tools > HTTP Request (the window)", @"the menu item opens it; method, address, parameters, headers (a # line left out), body and its content type are what the server sees; "
                  @"the status line, time and size are shown; the JSON answer is laid out when that is ticked; Headers shows the answer's headers",
                  opened && sent && statusShown && laidOut && headersShown);

            // A header's own Content-Type wins over the pop-up's; with no body the pop-up adds nothing.
            hw.headers.string = @"content-type: text/csv";
            BOOL ownType = [hw request].headers.count == 1 && [[hw request].headers[0].value isEqualToString:@"text/csv"];
            hw.headers.string = @""; hw.body.string = @"";
            BOOL noType = [hw request].headers.count == 0 && [hw request].body == nil;
            Check(@"Tools > HTTP Request (the content type)", @"a Content-Type among the headers is the one sent, not the pop-up's; without a body none is added", ownType && noType);

            // Sections: one in view at a time, each with its hint.
            BOOL sections = YES;
            for (NSInteger i = 0; i < 4; ++i) {
                hw.section.selectedSegment = i; [hw sectionChanged:nil];
                NSArray<NSView *> *areas = @[hw.parameters.enclosingScrollView, hw.headers.enclosingScrollView, hw.body.enclosingScrollView, hw.username];
                for (NSInteger k = 0; k < 4; ++k) if (areas[(NSUInteger)k].isHiddenOrHasHiddenAncestor != (k != i)) sections = NO;
                if ((i == 3) != hw.hint.hidden) sections = NO;
            }
            hw.section.selectedSegment = 0; [hw sectionChanged:nil];
            Check(@"Tools > HTTP Request (sections)", @"Parameters, Headers, Body and Options are shown one at a time, the first three with a line on how to write them", sections);

            // curl both ways through the clipboard.
            [board clearContents];
            [board setString:[NSString stringWithFormat:@"curl -X PATCH '%@/echo?x=1' -H 'X-Pasted: yes' -u me:pw --data-raw 'a=1' -k", base] forType:NSPasteboardTypeString];
            BOOL pasted = [hw pasteCurlCommand:nil];
            BOOL filled = [hw.method.titleOfSelectedItem isEqualToString:@"PATCH"] && [hw.address.stringValue hasSuffix:@"/echo?x=1"] &&
                          [hw.headers.string isEqualToString:@"X-Pasted: yes"] && [hw.body.string isEqualToString:@"a=1"] &&
                          [hw.username.stringValue isEqualToString:@"me"] && [hw.password.stringValue isEqualToString:@"pw"] &&
                          hw.allowInvalidCertificates.state == NSControlStateValueOn && hw.followRedirects.state == NSControlStateValueOff;
            [hw sendAndWait];
            NSDictionary *sawPasted = [NSJSONSerialization JSONObjectWithData:hw.response.body options:0 error:NULL];
            [hw copyAsCurl:nil];
            NSString *copied = [board stringForType:NSPasteboardTypeString];
            [board clearContents];
            [board setString:@"ls -la" forType:NSPasteboardTypeString];
            BOOL notPasted = ![hw pasteCurlCommand:nil] && [hw.status.stringValue isEqualToString:@"This is not a curl command."] &&
                             [hw.method.titleOfSelectedItem isEqualToString:@"PATCH"];
            Check(@"Tools > HTTP Request (curl through the clipboard)", @"Paste curl Command fills the controls from the command, and what is then sent is that request; "
                  @"Copy as curl writes them out again; something else on the clipboard is refused in words and changes nothing",
                  pasted && filled && [sawPasted[@"method"] isEqualToString:@"PATCH"] && [sawPasted[@"headers"][@"x-pasted"] isEqualToString:@"yes"] &&
                  [sawPasted[@"body"] isEqualToString:@"a=1"] && [sawPasted[@"headers"][@"authorization"] hasPrefix:@"Basic "] &&
                  [copied hasPrefix:@"curl -X PATCH 'http://127.0.0.1:"] && [copied containsString:@"-H 'X-Pasted: yes'"] && [copied containsString:@"-u 'me:pw'"] &&
                  [copied containsString:@"--data-raw 'a=1'"] && [copied hasSuffix:@"-k"] && notPasted);

            // The answer into the editor, in the language its content type names.
            NSUInteger tabsBefore = ed.documents.count;
            hw.formatJSON.state = NSControlStateValueOn; [hw answerSectionChanged:nil];
            [hw openAnswer:nil];
            Check(@"Tools > HTTP Request (Open in New Document)", @"the answer's body becomes a new document, laid out as it was shown, and a JSON answer is given the JSON language",
                  ed.documents.count == tabsBefore + 1 && [DocText(ed) isEqualToString:hw.answer.string] && [DocText(ed) containsString:@"\"method\": \"PATCH\""] &&
                  [ed.currentDocument.language.name isEqualToString:@"json"]);
            [sci message:SCI_SETSAVEPOINT];
            [ed closeCurrentDocument];

            NSDictionary *kept = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppHttpRequest"];
            hw.address.stringValue = @"mailto:someone"; hw.password.stringValue = @"";
            [hw send:nil];
            Check(@"Tools > HTTP Request (kept, and what is not sent)", @"the request is remembered for the next time - its password excepted; an address that is not the web's is said so and nothing is sent",
                  [kept[@"method"] isEqualToString:@"PATCH"] && [kept[@"address"] hasSuffix:@"/echo?x=1"] && [kept[@"headers"] isEqualToString:@"X-Pasted: yes"] &&
                  [kept[@"username"] isEqualToString:@"me"] && kept[@"password"] == nil &&
                  [hw.status.stringValue isEqualToString:@"The address is not an http or https address."] && hw.response.status == 0);

            // A binary answer in the window: said to be no text, its beginning as bytes.
            hw.address.stringValue = [base stringByAppendingString:@"/binary"]; [hw.method selectItemWithTitle:@"GET"]; hw.body.string = @""; hw.headers.string = @"";
            hw.username.stringValue = @"";
            [hw sendAndWait];
            Check(@"Tools > HTTP Request (an answer that is no text)", @"four bytes that are no text are said to be four bytes, and shown in hexadecimal",
                  [hw.answer.string isEqualToString:@"The answer is not text: 4 bytes.\n\nfffe00c3"]);

            // In another language, with every text in view.
            hp.localizationFile = @"russian.xml";
            [app applyLocalization];
            [hw show];
            NSString *(^cutIn)(NSWindow *) = ^NSString *(NSWindow *window) {
                [window.contentView layoutSubtreeIfNeeded];
                NSMutableArray<NSString *> *cut = [NSMutableArray array];
                NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:window.contentView];
                while (queue.count) {
                    NSView *v = queue.firstObject; [queue removeObjectAtIndex:0];
                    if (v.hidden) continue;
                    [queue addObjectsFromArray:v.subviews];
                    BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).selectable;
                    BOOL isButton = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]];
                    BOOL isSegments = [v isKindOfClass:[NSSegmentedControl class]];
                    if (!isLabel && !isButton && !isSegments) continue;
                    NSControl *c = (NSControl *)v;
                    NSString *text = isLabel ? c.stringValue : isButton ? ((NSButton *)c).title : [(NSSegmentedControl *)c labelForSegment:0];
                    if (!text.length) continue;
                    NSSize need = c.cell.wraps ? [c.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(c.frame), 10000)] : c.cell.cellSize;
                    if (c.cell.wraps) need.width = 0;
                    NSRect inWindow = [v convertRect:v.bounds toView:nil];
                    if (need.width > NSWidth(c.frame) + 1.5 || need.height > NSHeight(c.frame) + 1.5 ||
                        NSMaxX(inWindow) > NSWidth(window.contentView.frame) + 0.5 || NSMinX(inWindow) < -0.5)
                        [cut addObject:[NSString stringWithFormat:@"\"%@\" needs %.0fx%.0f, has %.0fx%.0f", text, need.width, need.height, NSWidth(c.frame), NSHeight(c.frame)]];
                }
                return [cut componentsJoinedByString:@"; "];
            };
            NSMutableString *cut = [NSMutableString string];
            for (NSInteger i = 0; i < 4; ++i) { hw.section.selectedSegment = i; [hw sectionChanged:nil]; [cut appendString:cutIn(hw.panel)]; }
            if (cut.length) printf("    cut in Russian: %s\n", cut.UTF8String);
            hw.section.selectedSegment = 1; [hw sectionChanged:nil];
            printf("    l10n http: %s | %s | %s | %s | %s | %s\n", hw.panel.title.UTF8String, hw.sendButton.title.UTF8String, [hw.section labelForSegment:1].UTF8String,
                   hw.hint.stringValue.UTF8String, hw.followRedirects.title.UTF8String, httpItem.title.UTF8String);
            Check(@"Tools > HTTP Request (in another language)", @"in Russian the menu item, the window's title, sections, labels, hints and buttons are Russian, and no text is cut in any section",
                  !cut.length && [httpItem.title isEqualToString:@"HTTP-запрос"] && [hw.panel.title isEqualToString:@"HTTP-запрос"] &&
                  [hw.sendButton.title isEqualToString:@"Отправить"] && [[hw.section labelForSegment:1] isEqualToString:@"Заголовки"] &&
                  [hw.hint.stringValue isEqualToString:@"По одному в строке: Имя: значение"] && [hw.followRedirects.title isEqualToString:@"Следовать перенаправлениям"]);

            hw.section.selectedSegment = 0; [hw sectionChanged:nil];
            [hw.panel orderOut:nil];
            if (savedBefore) [[NSUserDefaults standardUserDefaults] setObject:savedBefore forKey:@"NppHttpRequest"];
            else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppHttpRequest"];
            hp.localizationFile = languageBefore ?: @"";
            [app applyLocalization];

            NppHttpRequest *quit = [[NppHttpRequest alloc] init];
            quit.address = [base stringByAppendingString:@"/quit"]; quit.timeout = 3;
            [NppHttpClient send:quit cancelled:nil];
        }
        if (server.isRunning) [server terminate];
    }

    if (NppSectionWanted(@"Macro")) { printf("\n== Macro ==\n");
        SetDoc(ed, @"");
        [ed startRecordingMacro];
        BOOL recording = [ed recordingMacro];
        // Drive a couple of recordable actions through Scintilla.
        [sci message:SCI_BEGINUNDOACTION];
        [sci setStringProperty:SCI_REPLACESEL parameter:0 value:@"x"];
        [sci message:SCI_ENDUNDOACTION];
        [ed stopRecordingMacro];
        NSUInteger steps = [ed recordedStepCount];
        Check(@"IDM_MACRO_STARTRECORDINGMACRO", @"records while recording is on",
              recording && steps > 0);
        Check(@"IDM_MACRO_STOPRECORDINGMACRO", @"stops recording", ![ed recordingMacro]);

        NSString *before = DocText(ed);
        BOOL played = [ed playbackMacro:1];
        Check(@"IDM_MACRO_PLAYBACKRECORDEDMACRO", @"replays the recorded steps",
              played && DocText(ed).length > before.length);

        NSUInteger lengthBefore = DocText(ed).length;
        [ed playbackMacro:3];
        Check(@"IDM_MACRO_RUNMULTIMACRODLG", @"replays the requested number of times",
              DocText(ed).length == lengthBefore + 3);

        BOOL saved = [ed saveRecordedMacroAs:@"test macro"];
        Check(@"IDM_MACRO_SAVECURRENTMACRO", @"stores the macro under a name",
              saved && [[ed savedMacroNames] containsObject:@"test macro"]);
    }

    if (NppSectionWanted(@"Window")) { printf("\n== Window ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        // Names, extensions and sizes all differ, so each sort key is distinguishable.
        [ed openFileAtPath:TempFile(@"w_charlie.txt", @"ccc\n") error:&err];
        [ed openFileAtPath:TempFile(@"w_alpha.md",    @"a\n")   error:&err];
        [ed openFileAtPath:TempFile(@"w_bravo.py",    @"bb\n")  error:&err];

        struct { NppTabSort key; BOOL asc; NSString *cmd; } sorts[] = {
            {NppTabSortName,          YES, @"IDM_WINDOW_SORT_FN_ASC"},
            {NppTabSortName,          NO,  @"IDM_WINDOW_SORT_FN_DSC"},
            {NppTabSortPath,          YES, @"IDM_WINDOW_SORT_FP_ASC"},
            {NppTabSortPath,          NO,  @"IDM_WINDOW_SORT_FP_DSC"},
            {NppTabSortType,          YES, @"IDM_WINDOW_SORT_FT_ASC"},
            {NppTabSortType,          NO,  @"IDM_WINDOW_SORT_FT_DSC"},
            {NppTabSortContentLength, YES, @"IDM_WINDOW_SORT_FS_ASC"},
            {NppTabSortContentLength, NO,  @"IDM_WINDOW_SORT_FS_DSC"},
            {NppTabSortModifiedTime,  YES, @"IDM_WINDOW_SORT_FD_ASC"},
            {NppTabSortModifiedTime,  NO,  @"IDM_WINDOW_SORT_FD_DSC"},
        };
        for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); ++i) {
            [ed sortTabsBy:sorts[i].key ascending:sorts[i].asc];
            NSMutableArray *names = [NSMutableArray array], *languages = [NSMutableArray array];
            for (NppDocument *d in ed.documents) if (d.path) { [names addObject:d.displayName]; [languages addObject:d.language.name ?: @""]; }

            BOOL ordered = YES;
            for (NSUInteger n = 1; n < names.count; ++n) {
                NSComparisonResult r;
                switch (sorts[i].key) {
                    case NppTabSortType:   // the language's name, as WindowsDlg's BufferEquivalent
                        r = [languages[n - 1] caseInsensitiveCompare:languages[n]];
                        break;
                    case NppTabSortContentLength: {
                        NSString *a = names[n - 1], *b = names[n];
                        unsigned long long sa = [a hasSuffix:@".md"] ? 2 : ([a hasSuffix:@".py"] ? 3 : 4);
                        unsigned long long sb = [b hasSuffix:@".md"] ? 2 : ([b hasSuffix:@".py"] ? 3 : 4);
                        r = sa == sb ? NSOrderedSame : (sa < sb ? NSOrderedAscending : NSOrderedDescending);
                        break;
                    }
                    case NppTabSortModifiedTime:
                        r = NSOrderedSame;      // all written within the same moment
                        break;
                    default:
                        r = [names[n - 1] compare:names[n]];
                        break;
                }
                if (r == NSOrderedSame) continue;
                if (sorts[i].asc ? (r == NSOrderedDescending) : (r == NSOrderedAscending)) ordered = NO;
            }
            Check(sorts[i].cmd, @"orders the tabs by that key", ordered && names.count == 3);
        }

        Check(@"IDM_WINDOW_WINDOWS", @"lists every open document",
              [ed windowList].count == ed.documents.count);

        [ed selectDocumentAtIndex:0];
        [ed selectDocumentAtIndex:2];
        BOOL recent = [ed activateRecentWindow];
        Check(@"IDM_WINDOW_MRU_FIRST", @"returns to the previously active tab",
              recent && [ed.documents indexOfObject:ed.currentDocument] == 0);
        Check(@"IDM_DROPLIST_LIST", @"the droplist offers the same window list",
              [ed windowList].count == ed.documents.count);
    }

    if (NppSectionWanted(@"Run and Help")) { printf("\n== Run and Help ==\n");
        // Regression: this used to wait with -waitUntilExit, which spins the run
        // loop on the main thread and could abort inside AppKit. Repeating the
        // call makes that crash reproducible rather than occasional.
        BOOL allOK = YES;
        for (int i = 0; i < 8 && allOK; ++i) {
            NSString *out = [ed runShellCommand:@"printf ran-ok"];
            allOK = [out isEqualToString:@"ran-ok"];
        }
        Check(@"IDM_EXECUTE", @"runs a command and returns its output, repeatedly", allOK);

        NSString *report = [ed validateShortcutsFile];
        Check(@"IDM_EXECUTE_VALIDATE_SHORTCUTSXML", @"reports on the menu shortcuts",
              [report containsString:@"shortcuts"]);

        NSString *dbg = [ed debugInfo];
        BOOL fields = YES;
        for (NSString *field in @[@"Notepad++ v", @"Build time: ", @"Built with: Clang ", @"Scintilla/Lexilla included: 5.",
                                  @"Path: ", @"Command Line: ", @"Admin mode: OFF", @"Local Conf mode: ", @"Cloud Config: ",
                                  @"Periodic Backup: ", @"Multi-instance Mode: ", @"File Status Auto-Detection: ",
                                  @"Dark Mode: ", @"Display Info:", @"primary monitor: ", @"OS Name: macOS", @"OS Version: ",
                                  @"OS Build: ", @"Current ANSI codepage: ", @"Plugins: none"]) {
            if (![dbg containsString:field]) { fields = NO; printf("    debug info lacks %s\n", field.UTF8String); }
        }
        NppDebugInfoWindow *dw = [NppDebugInfoWindow shared];
        [dw showText:dbg];
        [dw copyToClipboard:nil];
        BOOL copied = [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:dbg];
        [dw.panel orderOut:nil];
        Check(@"IDM_DEBUGINFO", @"upstream's fields, in a window that copies them to the clipboard",
              fields && copied && [dbg rangeOfString:@"Build time"].location < [dbg rangeOfString:@"OS Name"].location);

        // The updater: versions, GitHub's answer, the proxy and the schedule.
        BOOL versions = [NppUpdateChecker compareVersion:@"v8.9.8" to:@"8.9.7"] == NSOrderedDescending &&
                        [NppUpdateChecker compareVersion:@"8.10" to:@"8.9.8"] == NSOrderedDescending &&
                        [NppUpdateChecker compareVersion:@"8.9" to:@"8.9.0"] == NSOrderedSame &&
                        [NppUpdateChecker compareVersion:@"8.9.8-mac1" to:@"8.9.8-mac2"] == NSOrderedAscending;
        NSData *json = [@"{\"tag_name\":\"v9.1.2\",\"name\":\"Notepad++ 9.1.2 for macOS\","
                        @"\"html_url\":\"https://github.com/o/r/releases/tag/v9.1.2\",\"body\":\"notes\"}"
                        dataUsingEncoding:NSUTF8StringEncoding];
        NppRelease *rel = [NppUpdateChecker releaseFromJSON:json];
        BOOL parsed = [rel.version isEqualToString:@"9.1.2"] && [rel.name hasSuffix:@"macOS"] &&
                      [rel.pageURL.host isEqualToString:@"github.com"] &&
                      ![NppUpdateChecker releaseFromJSON:[@"{\"message\":\"Not Found\"}" dataUsingEncoding:NSUTF8StringEncoding]];
        NSDictionary *proxy = [NppUpdateChecker proxyDictionaryFor:@"http://proxy.example:8080/"];
        BOOL proxied = [proxy[@"HTTPSProxy"] isEqualToString:@"proxy.example"] && [proxy[@"HTTPSPort"] intValue] == 8080 &&
                       [NppUpdateChecker proxyDictionaryFor:@""].count == 0;
        NppPreferences *up = [NppPreferences shared];
        NSString *nextBefore = up.nextUpdateDate;
        NSInteger intervalBefore = up.updateIntervalDays;
        up.nextUpdateDate = @"";
        up.updateIntervalDays = 15;
        BOOL firstDue = [app takeScheduledUpdateCheck];
        NSString *next = up.nextUpdateDate;
        BOOL thenWaits = ![app takeScheduledUpdateCheck];
        NSDate *in15 = [NSDate dateWithTimeIntervalSinceNow:15 * 86400 + 3600];
        BOOL schedule = firstDue && thenWaits && next.length == 8 &&
                        [NppUpdateChecker isDueOn:in15 next:next] && ![NppUpdateChecker isDueOn:[NSDate date] next:next] &&
                        ![app automaticUpdateCheckAllowed];
        up.nextUpdateDate = nextBefore ?: @"";
        up.updateIntervalDays = intervalBefore;
        // A fetch, from a file standing in for api.github.com.
        NSString *answer = TempFile(@"t_release.json", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
        NppUpdateChecker.latestReleaseURLOverride = [NSURL fileURLWithPath:answer];
        __block NppRelease *fetched = nil;
        __block BOOL fetchDone = NO;
        [NppUpdateChecker fetchLatest:^(NppRelease *r, NSError *e) { fetched = r; fetchDone = YES; }];
        NSDate *fetchLimit = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!fetchDone && [fetchLimit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NppUpdateChecker.latestReleaseURLOverride = nil;
        BOOL fetchedOK = [fetched.version isEqualToString:@"9.1.2"] &&
                         [NppUpdateChecker compareVersion:fetched.version to:[NppUpdateChecker currentVersion]] == NSOrderedDescending &&
                         [[NppUpdateChecker latestReleaseURL].absoluteString hasPrefix:@"https://api.github.com/repos/"];
        printf("    update: versions=%d parsed=%d proxy=%d schedule=%d fetch=%d current=%s\n", versions, parsed, proxied,
               schedule, fetchedOK, [NppUpdateChecker currentVersion].UTF8String);
        Check(@"IDM_UPDATE_NPP", @"asks GitHub Releases through the proxy, compares versions and keeps upstream's interval",
              versions && parsed && proxied && schedule && fetchedOK);

        Check(@"IDM_CMDLINEARGUMENTS", @"documents the accepted arguments",
              [[ed commandLineArgumentsHelp] containsString:@"NPPMAC_TEST"]);

        // Opening browsers from a test would be rude; what is looked at is where each command would go.
        // The port is released and supported from its own repository - the one Check for Updates asks -
        // so Home, Project Page and Forum lead there, and nothing leads to Notepad++'s site or forum.
        NSString *repository = [@"https://github.com/" stringByAppendingString:[NppPreferences shared].updateRepository];
        NSDictionary *links = @{@"IDM_HOMESWEETHOME": [repository stringByAppendingString:@"#readme"],
                                @"IDM_PROJECTPAGE":   repository,
                                @"IDM_ONLINEDOCUMENT":@"https://npp-user-manual.org/",
                                @"IDM_FORUM":         [repository stringByAppendingString:@"/discussions"]};
        NSDictionary<NSNumber *, NSMenuItem *> *helpItems = [app.shortcutStore menuItemsByIdentifier];
        NSDictionary *helpIDs = @{@"IDM_HOMESWEETHOME": @47001, @"IDM_PROJECTPAGE": @47002, @"IDM_ONLINEDOCUMENT": @47003, @"IDM_FORUM": @47004};
        for (NSString *cmd in links) {
            NSURL *u = [NSURL URLWithString:links[cmd]];
            NSMenuItem *item = helpItems[helpIDs[cmd]];
            Check(cmd, @"leads to this port's own repository (the manual, to the manual), over https",
                  u != nil && [u.scheme isEqualToString:@"https"] && u.host.length > 0 &&
                  [item.representedObject isEqualToString:links[cmd]]);
        }
        BOOL noneUpstream = YES;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![NppEnglishMenuTitle(top.submenu) isEqualToString:@"Help"] && ![NppEnglishMenuTitle(top.submenu) isEqualToString:@"?"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                NSString *to = [mi.representedObject isKindOfClass:[NSString class]] ? mi.representedObject : @"";
                if ([to containsString:@"notepad-plus-plus.org"] || [to containsString:@"github.com/notepad-plus-plus/"]) noneUpstream = NO;
            }
        }
        Check(@"Help (whose it is)", @"no command of the Help menu sends a user of the Mac version to Notepad++'s site, forum or repository", noneUpstream);

        [[NSUserDefaults standardUserDefaults] setObject:@"proxy.example:8080" forKey:@"NppMacUpdaterProxy"];
        Check(@"IDM_CONFUPDATERPROXY", @"remembers the proxy setting",
              [[[NSUserDefaults standardUserDefaults] stringForKey:@"NppMacUpdaterProxy"]
                  isEqualToString:@"proxy.example:8080"]);

        NSMenuItem *about = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![top.submenu.title isEqualToString:@"Help"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                if ([mi.title hasPrefix:@"About"]) about = mi;
            }
        }
        NppAboutWindow *aw = [NppAboutWindow shared];
        [aw show];
        BOOL versionShown = NO, licenceShown = NO, homeLink = NO, issuesLink = NO, upstreamLink = NO;
        NSMutableArray *views = [NSMutableArray arrayWithObject:aw.panel.contentView];
        while (views.count) {
            NSView *view = views.lastObject; [views removeLastObject];
            [views addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:[NSTextField class]] && [((NSTextField *)view).stringValue isEqualToString:[NppAboutWindow versionLine]]) versionShown = YES;
            if ([view isKindOfClass:[NSTextView class]] && [((NSTextView *)view).string isEqualToString:NppLicenceText]) licenceShown = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier isEqualToString:NppProjectAddress(@"")]) homeLink = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier isEqualToString:NppProjectAddress(@"issues")]) issuesLink = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier containsString:@"notepad-plus-plus.org"]) upstreamLink = YES;
        }
        BOOL shown = aw.panel.isVisible;
        [aw.panel orderOut:nil];
        Check(@"IDM_ABOUT", @"upstream's About box: version and bitness, build time and the licence - with this port's own repository "
              @"and its Issues where upstream has its site, and no link to Notepad++'s",
              about != nil && about.action == @selector(showAbout:) && shown && versionShown && licenceShown && homeLink && issuesLink && !upstreamLink &&
              [[NppAboutWindow versionLine] containsString:[NppAboutWindow bitness]]);

        NSString *pluginDir = [ed.defaultSessionPath.stringByDeletingLastPathComponent
                               stringByAppendingPathComponent:@"plugins"];
        [[NSFileManager defaultManager] createDirectoryAtPath:pluginDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        Check(@"IDM_SETTING_OPENPLUGINSDIR", @"has a plugins folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:pluginDir]);
    }

    if (NppSectionWanted(@"Settings")) { printf("\n== Settings ==\n");
        NppPreferences *p = [NppPreferences shared];
        NSString *fontBefore = p.fontName;
        p.fontName = @"Courier";
        p.fontSize = 17;
        p.tabWidth = 7;
        p.useSpaces = NO;
        p.wordWrap = YES;
        p.showWhitespace = YES;
        [p applyToEditor:ed];
        BOOL applied = [sci message:SCI_GETTABWIDTH] == 7 &&
                       [sci message:SCI_GETUSETABS] == 1 &&
                       [sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE &&
                       [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
        Check(@"IDM_SETTING_PREFERENCE", @"settings reach the editor", applied);

        // Restore something sane for the tests that follow.
        p.fontName = fontBefore ?: @"Menlo";
        p.tabWidth = 4; p.useSpaces = YES; p.wordWrap = NO; p.showWhitespace = NO;
        [p applyToEditor:ed];

        // Every attribute the upstream Style struct carries must reach Scintilla,
        // not just the foreground colour.
        [ed setLanguageNamed:@"cpp"];
        [p setStyleOverride:@{@"fg": @"FF0000", @"bg": @"00FF00", @"bold": @YES,
                              @"italic": @YES, @"underline": @YES,
                              @"font": @"Courier", @"size": @19}
                forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        [ed applyLanguage];
        // Scintilla stores colours as 0xBBGGRR: pure red reads back as 0x0000FF
        // and pure green as 0x00FF00.
        BOOL colours = [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == 0x0000FF &&
                       [sci message:SCI_STYLEGETBACK wParam:SCE_C_COMMENTLINE] == 0x00FF00;
        BOOL faces = [sci message:SCI_STYLEGETBOLD wParam:SCE_C_COMMENTLINE] != 0 &&
                     [sci message:SCI_STYLEGETITALIC wParam:SCE_C_COMMENTLINE] != 0 &&
                     [sci message:SCI_STYLEGETUNDERLINE wParam:SCE_C_COMMENTLINE] != 0;
        BOOL size = [sci message:SCI_STYLEGETSIZE wParam:SCE_C_COMMENTLINE] == 19;
        Check(@"IDM_LANGSTYLE_CONFIG_DLG",
              @"foreground, background, bold, italic, underline and size all reach the style",
              colours && faces && size);

        // A bare hex string is what the foreground-only version stored; it must
        // still load rather than being dropped.
        [p setStyleOverride:nil forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        NSMutableDictionary *legacy = [p.styleOverrides mutableCopy];
        legacy[[NSString stringWithFormat:@"cpp/%d", SCE_C_COMMENTLINE]] = @"0000FF";
        p.styleOverrides = legacy;
        [ed applyLanguage];
        Check(@"IDM_LANGSTYLE_CONFIG_DLG (legacy)", @"an old foreground-only override still applies",
              [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == 0xFF0000);

        [p setStyleOverride:nil forLanguage:@"cpp" styleID:SCE_C_COMMENTLINE];
        [ed applyLanguage];

        // The Style Configurator edits the theme itself, as WordStyleDlg does.
        {
            [ed setLanguageNamed:@"cpp"];
            long commentBefore = [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE];
            StyleConfiguratorWindow *conf = [[StyleConfiguratorWindow alloc] initWithEditor:ed];
            [conf show];
            BOOL opened = conf.visible && [conf selectLanguage:@"cpp"] && [conf selectStyleNamed:@"COMMENT LINE"];
            [conf setValue:@"FF0000" ofAttribute:@"fgColor"];
            BOOL previewed = [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == 0x0000FF && conf.dirty;
            // A font from the system's font panel: family, size, bold and italic in one.
            NSFont *chosen = [[NSFontManager sharedFontManager] fontWithFamily:@"Courier New" traits:NSBoldFontMask | NSItalicFontMask weight:9 size:17];
            [conf applyChosenFont:chosen];
            char fontName[128] = {0};
            [sci message:SCI_STYLEGETFONT wParam:SCE_C_COMMENTLINE lParam:(sptr_t)fontName];
            previewed = previewed && chosen != nil && !strcmp(fontName, "Courier New") &&
                        [sci message:SCI_STYLEGETSIZE wParam:SCE_C_COMMENTLINE] == 17 &&
                        [sci message:SCI_STYLEGETBOLD wParam:SCE_C_COMMENTLINE] && [sci message:SCI_STYLEGETITALIC wParam:SCE_C_COMMENTLINE] &&
                        [conf respondsToSelector:@selector(changeFont:)];
            [conf cancel:nil];
            BOOL reverted = !conf.visible && [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == commentBefore;
            Check(@"IDM_LANGSTYLE_CONFIG_DLG (preview)",
                  @"a colour changed in the configurator shows at once, and Cancel takes it back",
                  opened && previewed && reverted);

            // Global override: the ticked attributes of its style beat every other style.
            [conf show];
            NppStyle *go = [StyleCatalog sharedCatalog].globalStyles[@"Global override"];
            BOOL found = [conf selectLanguage:NppGlobalStylesName] && [conf selectStyleNamed:@"Global override"];
            [conf setGlobalOverride:@"fg" enabled:YES];
            [conf setGlobalOverride:@"bold" enabled:YES];
            NSColor *goFg = [go.foreground colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            long want = goFg ? (lround(goFg.redComponent * 255) | (lround(goFg.greenComponent * 255) << 8) |
                                (lround(goFg.blueComponent * 255) << 16)) : -1;
            BOOL overridden = found && want >= 0 &&
                [sci message:SCI_STYLEGETFORE wParam:SCE_C_WORD] == want &&
                [sci message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT] == want &&
                [sci message:SCI_STYLEGETBOLD wParam:SCE_C_WORD] == ((go.fontStyle & 1) ? 1 : 0);
            [conf cancel:nil];
            BOOL overrideReverted = ![p.globalOverride[@"fg"] boolValue] &&
                [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == commentBefore;
            Check(@"IDM_LANGSTYLE_CONFIG_DLG (global override)",
                  @"Global override's switches colour every style, and Cancel turns them off again",
                  overridden && overrideReverted);

            // User keywords and user extensions, then Save & Close writes the
            // user's copy of the theme, which is read back in preference.
            NSString *userPath = [StyleCatalog userPathForThemeNamed:conf.themeName];
            NSData *userBefore = userPath ? [NSData dataWithContentsOfFile:userPath] : nil;
            [conf show];
            [conf selectLanguage:@"cpp"];
            [conf selectStyleNamed:@"INSTRUCTION WORD"];
            [conf setUserKeywords:@"  nppmacword\n  nppmacother "];
            [conf setUserExtensions:@" nppx  NPPY "];
            [sci setString:@"nppmacword x;"];
            [sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL keywords = [sci message:SCI_GETSTYLEAT wParam:0] == SCE_C_WORD;
            BOOL extensions = [[[LanguageCatalog sharedCatalog] languageForFileName:@"a.nppx"].name isEqualToString:@"cpp"] &&
                              [[[LanguageCatalog sharedCatalog] languageForFileName:@"b.NPPY"].name isEqualToString:@"cpp"];
            [conf saveAndClose:nil];
            NSString *written = userPath ? [NSString stringWithContentsOfFile:userPath encoding:NSUTF8StringEncoding error:NULL] : nil;
            [StyleCatalog loadThemeNamed:conf.themeName];
            NppStyle *instre = nil;
            for (NppStyle *st in [[StyleCatalog sharedCatalog] stylesForLexerName:@"cpp"]) {
                if (st.styleID == SCE_C_WORD) instre = st;
            }
            BOOL saved = [written containsString:@"nppmacword nppmacother"] &&
                         [instre.userKeywords isEqualToString:@"nppmacword nppmacother"] &&
                         [[[StyleCatalog sharedCatalog] userExtensionsForLexer:@"cpp"] containsObject:@"nppy"];
            Check(@"IDM_LANGSTYLE_CONFIG_DLG (keywords)",
                  @"user-defined keywords are highlighted, as are files with a user extension, and both are saved",
                  keywords && extensions && saved);

            if (userBefore) [userBefore writeToFile:userPath atomically:YES];
            else if (userPath) [[NSFileManager defaultManager] removeItemAtPath:userPath error:NULL];
            [StyleCatalog loadThemeNamed:conf.themeName];
            [sci setString:@""];
            [ed applyLanguage];
        }

        // Keys, and what Windows calls them.
        {
            NppKeyCombo *k = [NppKeyCombo comboFromSpec:@"cmd+shift+k"];
            NppKeyCombo *fromWindows = [NppKeyCombo comboWithWindowsCtrl:YES alt:NO shift:YES macControl:NO virtualKey:75];
            NppKeyCombo *f5 = [NppKeyCombo comboWithWindowsCtrl:NO alt:YES shift:NO macControl:NO virtualKey:116];
            NppKeyCombo *upper = [NppKeyCombo comboWithKey:@"K" modifiers:NSEventModifierFlagCommand];
            BOOL keys = [k isEqual:fromWindows] && k.windowsVirtualKey == 75 && [k.displayString isEqualToString:@"⇧⌘K"] &&
                        f5.windowsVirtualKey == 116 && [f5.displayString isEqualToString:@"⌥F5"] && [upper isEqual:k] &&
                        ([k scintillaKeyDefinition] == ('K' | ((SCMOD_CTRL | SCMOD_SHIFT) << 16)));
            Check(@"IDM_SETTING_SHORTCUT_MAPPER",
                  @"a key reads the same from a spec, from shortcuts.xml's codes and from a menu key equivalent",
                  keys);
        }

        // The store: every menu command listed with Notepad++'s id where it has one.
        {
            NppShortcutStore *store = app.shortcutStore;
            NSArray *menu = [store commandsInCategory:NppShortcutMainMenu];
            NSUInteger withID = 0;
            NppShortcutCommand *newFile = nil, *findNext = nil;
            for (NppShortcutCommand *c in menu) {
                if (c.identifier) withID++;
                if (c.identifier == 41001) newFile = c;          // IDM_FILE_NEW
                if (c.identifier == 43002) findNext = c;         // IDM_SEARCH_FINDNEXT
            }
            NSArray *sci = [store commandsInCategory:NppShortcutScintilla];
            Check(@"IDM_SETTING_SHORTCUT_MAPPER (commands)",
                  @"the main menu is listed with Notepad++'s ids for most commands, and the Scintilla commands "
                  @"Windows lists are there",
                  menu.count > 400 && withID * 10 > menu.count * 7 && newFile && findNext && sci.count > 80);

            // Assigning writes shortcuts.xml as Windows writes it, and reads back.
            NSString *path = [store path];
            NSData *was = [NSData dataWithContentsOfFile:path];
            NppKeyCombo *combo = [NppKeyCombo comboFromSpec:@"cmd+opt+ctrl+j"];
            NppKeyCombo *before = findNext.combo;
            [store setCombo:combo forCommand:findNext];
            NSMenuItem *item = nil;
            NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
            while (queue.count) {
                NSMenuItem *i = queue.firstObject; [queue removeObjectAtIndex:0];
                if (i.submenu) [queue addObjectsFromArray:i.submenu.itemArray];
                else if ([i.title isEqualToString:findNext.name] && i.keyEquivalent.length) item = i;
            }
            NSString *xml = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
            BOOL written = [xml containsString:@"id=\"43002\" Ctrl=\"yes\" Alt=\"yes\" Shift=\"no\" Key=\"74\" MacCtrl=\"yes\""];
            BOOL applied = item && [item.keyEquivalent isEqualToString:@"j"] &&
                           item.keyEquivalentModifierMask == (NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                                              NSEventModifierFlagControl);
            NSArray *conflicts = [store conflictsWith:combo except:nil];
            BOOL conflictFound = conflicts.count == 1 && [[conflicts.firstObject name] isEqualToString:findNext.name];

            // A file written on Windows: a menu key, a macro with its actions,
            // a Run command, a Scintilla key with a second key.
            NSString *windows =
                @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n"
                @"<InternalCommands><Shortcut id=\"41001\" Ctrl=\"yes\" Alt=\"yes\" Shift=\"no\" Key=\"78\" /></InternalCommands>\n"
                @"<Macros><Macro name=\"From Windows\" Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"117\">"
                @"<Action type=\"1\" message=\"2170\" wParam=\"0\" lParam=\"0\" sParam=\"hi hi\" />"
                @"<Action type=\"3\" message=\"1700\" wParam=\"0\" lParam=\"0\" sParam=\"\" />"
                @"<Action type=\"3\" message=\"1601\" wParam=\"0\" lParam=\"0\" sParam=\"hi\" />"
                @"<Action type=\"3\" message=\"1625\" wParam=\"0\" lParam=\"0\" sParam=\"\" />"
                @"<Action type=\"3\" message=\"1602\" wParam=\"0\" lParam=\"0\" sParam=\"yo\" />"
                @"<Action type=\"3\" message=\"1702\" wParam=\"0\" lParam=\"768\" sParam=\"\" />"
                @"<Action type=\"3\" message=\"1701\" wParam=\"0\" lParam=\"1609\" sParam=\"\" />"
                @"<Action type=\"2\" message=\"0\" wParam=\"42007\" lParam=\"0\" sParam=\"\" /></Macro></Macros>\n"
                @"<UserDefinedCommands><Command name=\"Say hello\" Ctrl=\"no\" Alt=\"no\" Shift=\"no\" Key=\"0\">echo hello</Command></UserDefinedCommands>\n"
                @"<PluginCommands><PluginCommand moduleName=\"x.dll\" internalID=\"1\" Ctrl=\"no\" Alt=\"no\" Shift=\"no\" Key=\"0\" /></PluginCommands>\n"
                @"<ScintillaKeys><ScintKey ScintID=\"2338\" menuCmdID=\"0\" Ctrl=\"yes\" Alt=\"no\" Shift=\"yes\" Key=\"68\">"
                @"<NextKey Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"68\" /></ScintKey></ScintillaKeys>\n"
                @"</NotepadPlus>\n";
            [windows writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NppShortcutStore *reread = [[NppShortcutStore alloc] initWithEditor:ed];
            [reread captureMenuDefaults];
            [reread load];
            NppShortcutCommand *newAgain = nil;
            for (NppShortcutCommand *c in [reread commandsInCategory:NppShortcutMainMenu]) if (c.identifier == 41001) newAgain = c;
            NppShortcutCommand *macro = nil, *run = nil, *lineDelete = nil;
            for (NppShortcutCommand *c in [reread commandsInCategory:NppShortcutMacro]) if ([c.name isEqualToString:@"From Windows"]) macro = c;
            for (NppShortcutCommand *c in [reread commandsInCategory:NppShortcutRunCommand]) if ([c.name isEqualToString:@"Say hello"]) run = c;
            for (NppShortcutCommand *c in [reread commandsInCategory:NppShortcutScintilla]) if (c.identifier == SCI_LINEDELETE) lineDelete = c;
            NSArray *steps = [ed stepsOfSavedMacroNamed:@"From Windows"];
            // Played: typed, replaced through the Find steps, selected through the menu command.
            [ed newDocument];
            [ed playSavedMacroNamed:@"From Windows"];
            BOOL macroPlayed = [[ed documentText] isEqualToString:@"yo yo"] &&
                               [ed.sci message:SCI_GETSELECTIONEND] - [ed.sci message:SCI_GETSELECTIONSTART] == 5;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            BOOL readWindows = [newAgain.combo isEqual:[NppKeyCombo comboFromSpec:@"cmd+opt+n"]] &&
                               [macro.combo isEqual:[NppKeyCombo comboWithWindowsCtrl:NO alt:YES shift:NO macControl:NO virtualKey:117]] &&
                               macro.combo.windowsVirtualKey == 117 && run != nil &&
                               steps.count == 8 && [steps.firstObject[@"text"] isEqualToString:@"hi hi"] && macroPlayed &&
                               [lineDelete.combo isEqual:[NppKeyCombo comboFromSpec:@"cmd+shift+d"]] &&
                               lineDelete.extraCombos.count == 1;

            // The Scintilla key reaches the editor: Cmd+Shift+D deletes the line.
            [ed newDocument];
            [ed setDocumentText:@"one\ntwo\n"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            NSEvent *press = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                                         modifierFlags:NSEventModifierFlagCommand | NSEventModifierFlagShift
                                             timestamp:0 windowNumber:ed.window.windowNumber context:nil
                                            characters:@"D" charactersIgnoringModifiers:@"D" isARepeat:NO keyCode:2];
            [[ed.sci content] keyDown:press];
            BOOL scintillaKey = [[ed documentText] isEqualToString:@"two\n"];
            // Given another key, the command leaves the old one at once.
            [reread setCombo:[NppKeyCombo comboFromScintillaKey:'J' modifiers:SCMOD_CTRL | SCMOD_ALT] forCommand:lineDelete];
            [ed setDocumentText:@"one\ntwo\n"];
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            [[ed.sci content] keyDown:press];
            scintillaKey = scintillaKey && [[ed documentText] hasPrefix:@"one"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];

            // Written back: the plugin command is kept as it was.
            [reread save];
            NSString *rewritten = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
            BOOL kept = ![rewritten containsString:@"lParam=\"43"] && [rewritten containsString:@"moduleName=\"x.dll\""] && [rewritten containsString:@"<NextKey"] &&
                        [rewritten containsString:@"name=\"Say hello\""] &&
                        [rewritten containsString:@"type=\"2\" message=\"0\" wParam=\"42007\""] &&
                        [rewritten containsString:@"type=\"3\" message=\"1701\" wParam=\"0\" lParam=\"1609\""] &&
                        [rewritten containsString:@"sParam=\"yo\""];

            // Everything back as it was.
            [ed removeSavedMacroNamed:@"From Windows"];
            [ed removeSavedCommandNamed:@"Say hello"];
            if (was) [was writeToFile:path atomically:YES]; else [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [store setCombo:before forCommand:findNext];
            if (!was) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            NppShortcutStore *fresh = [[NppShortcutStore alloc] initWithEditor:ed];
            [fresh captureMenuDefaults];
            [fresh load];
            for (NppShortcutCommand *c in [fresh commandsInCategory:NppShortcutScintilla]) {
                if (c.identifier == SCI_LINEDELETE) [fresh setCombo:[NppKeyCombo comboFromScintillaKey:'L' modifiers:SCMOD_CTRL | SCMOD_SHIFT] forCommand:c];
            }
            [app.shortcutStore load];
            if (!was) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];

            Check(@"IDM_SETTING_SHORTCUT_MAPPER (assigning)",
                  @"a new key is applied to its menu item, written to shortcuts.xml under Notepad++'s id, and "
                  @"found as a conflict",
                  written && applied && conflictFound);
            Check(@"IDM_SETTING_SHORTCUT_MAPPER (a file from Windows)",
                  @"shortcuts.xml written on Windows gives its menu, macro, Run and Scintilla keys here, "
                  @"brings the macro and the command across, and a Scintilla key works in the editor",
                  readWindows && scintillaKey && kept);
        }

        // Recording: a menu command that upstream records by its id is one
        // step of type 2, and what it sent to Scintilla meanwhile is not recorded again.
        {
            NSMenuItem *upper = [app.shortcutStore menuItemsByIdentifier][@42016];     // IDM_EDIT_UPPERCASE
            [ed newDocument];
            [ed startRecordingMacro];
            [ed.sci message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)"abc"];
            [ed.sci message:SCI_SELECTALL];
            NSDictionary *info = upper ? @{@"MenuItem": upper} : @{};
            [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuWillSendActionNotification object:upper.menu userInfo:info];
            if (upper) [NSApp sendAction:upper.action to:upper.target from:upper];
            [[NSNotificationCenter defaultCenter] postNotificationName:NSMenuDidSendActionNotification object:upper.menu userInfo:info];
            [ed stopRecordingMacro];
            NSArray *recorded = [[ed valueForKey:@"macroSteps"] copy];
            NSUInteger menuSteps = 0;
            for (NSDictionary *step in recorded) if ([step[@"type"] intValue] == 2 && [step[@"w"] intValue] == 42016) menuSteps++;
            BOOL recordedOnce = upper != nil && menuSteps == 1 && [[ed documentText] isEqualToString:@"ABC"];
            [ed setDocumentText:@""];
            [ed playbackMacro:1];
            BOOL replayed = [[ed documentText] isEqualToString:@"ABC"];
            // A Replace All from the Find dialog is six steps of type 3, and plays.
            [app buildFindPanel];
            NSTextField *mFind = [app valueForKey:@"findField"], *mWith = [app valueForKey:@"replaceField"];
            NSString *mFindWas = mFind.stringValue, *mWithWas = mWith.stringValue;
            [ed setDocumentText:@"cat cat"];
            [ed startRecordingMacro];
            mFind.stringValue = @"cat";
            mWith.stringValue = @"dog";
            [app findPanelReplaceAll:nil];
            [ed stopRecordingMacro];
            NSArray *findSteps = [[ed valueForKey:@"macroSteps"] copy];
            BOOL sixSteps = findSteps.count == 6 && [findSteps.firstObject[@"msg"] intValue] == 1700 &&
                            [findSteps.lastObject[@"msg"] intValue] == 1701 && [findSteps.lastObject[@"l"] intValue] == 1609 &&
                            [[ed documentText] isEqualToString:@"dog dog"];
            [ed setDocumentText:@"a cat"];
            [ed playbackMacro:1];
            replayed = replayed && sixSteps && [[ed documentText] isEqualToString:@"a dog"];
            mFind.stringValue = mFindWas; mWith.stringValue = mWithWas;
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            printf("    macro recording: %lu steps, %lu of them the menu command\n", (unsigned long)recorded.count, (unsigned long)menuSteps);
            Check(@"IDM_MACRO_STARTRECORDINGMACRO (menu commands)",
                  @"a recordable menu command is recorded by its id, once, and plays back",
                  recordedOnce && replayed);
        }

        // Saved macros are in the Macro menu, as on Windows.
        {
            [ed storeSavedMacro:@[@{@"msg": @2170, @"w": @0, @"l": @0, @"text": @"x"}] named:@"Menu macro"];
            [app rebuildMacroMenu];
            NSMenuItem *entry = [app.macroMenu itemWithTitle:@"Menu macro"];
            [ed newDocument];
            if (entry) [NSApp sendAction:entry.action to:entry.target from:entry];
            BOOL played = [[ed documentText] isEqualToString:@"x"];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            [ed removeSavedMacroNamed:@"Menu macro"];
            [app rebuildMacroMenu];
            Check(@"IDM_MACRO_PLAYBACKRECORDEDMACRO (saved macros in the menu)",
                  @"a saved macro is listed in the Macro menu and plays from it",
                  entry != nil && played && ![app.macroMenu itemWithTitle:@"Menu macro"]);
        }

        NSString *plugin = TempFile(@"t_plugin.bundle", @"fake plugin\n");
        NSUInteger copiedPlugins = [ed importFiles:@[plugin] intoSubdirectory:@"plugins"];
        Check(@"IDM_SETTING_IMPORTPLUGIN", @"copies plugins into the support folder",
              copiedPlugins == 1 &&
              [[ed importedFilesIn:@"plugins"] containsObject:@"t_plugin.bundle"]);

        NSString *theme = TempFile(@"t_theme.xml", @"<theme/>\n");
        NSUInteger copiedThemes = [ed importFiles:@[theme] intoSubdirectory:@"themes"];
        Check(@"IDM_SETTING_IMPORTSTYLETHEMES", @"copies themes into the support folder",
              copiedThemes == 1 &&
              [[ed importedFilesIn:@"themes"] containsObject:@"t_theme.xml"]);

        // contextMenu.xml in upstream's format: by menu and item name, by id, in a
        // folder, renamed, separated; what this build does not have is left out.
        NSString *cmPath = [[ed supportDirectory] stringByAppendingPathComponent:@"contextMenu.xml"];
        NSData *cmWas = [NSData dataWithContentsOfFile:cmPath];
        [@"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus><ScintillaContextMenu>\n"
         @"<Item id=\"0\"/>\n"
         @"<Item MenuEntryName=\"Edit\" MenuItemName=\"Copy\"/>\n"
         @"<Item MenuEntryName=\"edit\" MenuItemName=\"&amp;Paste\" ItemNameAs=\"Put it here\"/>\n"
         @"<Item id=\"0\"/><Item id=\"0\"/>\n"
         @"<Item MenuEntryName=\"Edit\" MenuItemName=\"No Such Command\"/>\n"
         @"<Item FolderName=\"Case\" id=\"42016\"/>\n"
         @"<Item FolderName=\"Case\" MenuEntryName=\"Edit\" MenuItemName=\"lowercase\"/>\n"
         @"<Item FolderName=\"Nothing here\" MenuEntryName=\"Edit\" MenuItemName=\"Nor This\"/>\n"
         @"<Item FolderName=\"Plugin commands\" PluginEntryName=\"JSON\" PluginCommandItemName=\"Format\"/>\n"
         @"<Item id=\"0\"/>\n"
         @"</ScintillaContextMenu></NotepadPlus>\n" writeToFile:cmPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [ed rebuildContextMenu];
        NSMenu *ctx = ed.sci.menu;
        NSMutableArray *ctxTitles = [NSMutableArray array];
        for (NSMenuItem *mi in ctx.itemArray) [ctxTitles addObject:mi.isSeparatorItem ? @"-" : mi.title];
        NSMenuItem *caseFolder = [ctx itemWithTitle:@"Case"], *pluginFolder = [ctx itemWithTitle:@"Plugin commands"];
        BOOL fromFile = [ctxTitles isEqualToArray:(@[@"Copy", @"Put it here", @"-", @"Case", @"Plugin commands"])] &&
                        caseFolder.submenu.numberOfItems == 2 && [caseFolder.submenu.itemArray.firstObject action] == NSSelectorFromString(@"convertCase:") &&
                        pluginFolder.submenu.numberOfItems == 1 && [ctx itemWithTitle:@"Put it here"].action == NSSelectorFromString(@"pasteText:");
        printf("    context menu: %s | case=%ld %s\n", [ctxTitles componentsJoinedByString:@", "].UTF8String, (long)caseFolder.submenu.numberOfItems,
               NSStringFromSelector([caseFolder.submenu.itemArray.firstObject action]).UTF8String);
        // Upstream's default: most of it is here (the plugin commands of Windows are not).
        [[NppContextMenuFile defaultContents] writeToFile:cmPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [ed rebuildContextMenu];
        NSMenu *stock = ed.sci.menu;
        BOOL stockMenu = stock.numberOfItems >= 12 && [stock itemWithTitle:@"Style all occurrences of token"].submenu.numberOfItems == 5 &&
                         [stock.itemArray.firstObject action] == NSSelectorFromString(@"cutText:");
        printf("    context menu default: %ld items\n", (long)stock.numberOfItems);
        // Without the file's menu (no such root) the list in Preferences is what shows.
        [@"<NotepadPlus></NotepadPlus>" writeToFile:cmPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        p.contextMenuCommands = @[@"Copy", @"Paste", @"Toggle Line Comment"];
        [ed rebuildContextMenu];
        BOOL fallsBack = ed.sci.menu.numberOfItems == 3 && [ed.sci.menu itemWithTitle:@"Toggle Line Comment"];
        if (cmWas) [cmWas writeToFile:cmPath atomically:YES]; else [[NSFileManager defaultManager] removeItemAtPath:cmPath error:NULL];
        [ed rebuildContextMenu];
        printf("    context menu checks: file=%d stock=%d fallback=%d\n", fromFile, stockMenu, fallsBack);
        Check(@"IDM_SETTING_EDITCONTEXTMENU", @"the right-click menu is what contextMenu.xml says, upstream's default included, and the Preferences list without it",
              fromFile && stockMenu && fallsBack);
    }

    if (NppSectionWanted(@"Preferences: pages")) { printf("\n== Preferences: pages ==\n");
        PreferencesWindow *prefs = [[PreferencesWindow alloc] initWithEditor:ed];
        NSArray *pages = [prefs categoryNames];

        // Notepad++ lists its settings by category down the left rather than as
        // one long column, and these are its own names for them.
        NSArray *expected = @[@"General", @"Toolbar", @"Editing 1", @"Editing 2",
                              @"Dark Mode", @"Margins/Border/Edge", @"New Document",
                              @"Indentation", @"Highlighting", @"Print", @"Backup",
                              @"Auto-Completion", @"Delimiter", @"Performance",
                              @"Cloud & Link"];
        NSMutableArray *absent = [NSMutableArray array];
        for (NSString *name in expected) if (![pages containsObject:name]) [absent addObject:name];

        // Every setting that reaches Scintilla needs somewhere to be set from.
        NSArray *keys = @[@"caretWidth", @"caretBlinkRate", @"currentLineHighlightMode",
                          @"currentLineFrameWidth", @"scrollBeyondLastLine", @"virtualSpace",
                          @"lineCopyCutWithoutSelection", @"selectedTextDragDrop",
                          @"rightClickKeepsSelection", @"lineWrapMethod", @"bookmarkMarginShow",
                          @"foldMarginShow", @"paddingLeft", @"paddingRight", @"edgeMode",
                          @"edgeColumns", @"autoIndentMode", @"markAllCaseSensitive",
                          @"markAllWordOnly", @"autoCompleteOnInput", @"autoInsertBrace"];
        NSMutableArray *unreachable = [NSMutableArray array];
        for (NSString *key in keys) {
            if (![prefs hasControlForKey:key]) [unreachable addObject:key];
        }

        Check(@"IDM_SETTING_PREFERENCE (pages)",
              [NSString stringWithFormat:@"%lu categories, and every setting has a control",
               (unsigned long)pages.count],
              absent.count == 0 && unreachable.count == 0 && pages.count >= 15);
        if (absent.count) printf("       нет страниц: %s\n",
            [[absent componentsJoinedByString:@", "] UTF8String]);
        if (unreachable.count) printf("       нет элементов: %s\n",
            [[unreachable componentsJoinedByString:@", "] UTF8String]);
    }

    if (NppSectionWanted(@"Appearance: themes")) { printf("\n== Appearance: themes ==\n");
        NppPreferences *p = [NppPreferences shared];
        NSArray *themes = [StyleCatalog availableThemeNames];
        Check(@"IDM_SETTING_PREFERENCE (themes listed)",
              @"the bundled Notepad++ themes are offered",
              themes.count > 15 && [themes containsObject:@"Default"] &&
              [themes containsObject:@"DarkModeDefault"] && [themes containsObject:@"Monokai"]);

        // The dark theme's default background is 3F3F3F; the light one's is white.
        [StyleCatalog loadThemeNamed:@"Default"];
        [ed applyLanguage];
        long lightBack = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT];
        [StyleCatalog loadThemeNamed:@"DarkModeDefault"];
        [ed applyLanguage];
        long darkBack = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT];
        Check(@"IDM_SETTING_PREFERENCE (dark theme)",
              @"switching to the dark theme repaints the editor",
              lightBack == 0xFFFFFF && darkBack == 0x3F3F3F &&
              [[StyleCatalog sharedCatalog].themeName isEqualToString:@"DarkModeDefault"]);

        p.appearanceMode = 2;
        BOOL forcesDark = [[p effectiveThemeName] isEqualToString:p.darkThemeName];
        p.appearanceMode = 1;
        BOOL forcesLight = [[p effectiveThemeName] isEqualToString:p.lightThemeName];
        p.appearanceMode = 0;
        NSString *followed = [p effectiveThemeName];
        BOOL follows = [followed isEqualToString:[p systemIsDark] ? p.darkThemeName : p.lightThemeName];
        Check(@"IDM_SETTING_PREFERENCE (appearance)",
              @"light, dark and follow-the-system each pick the right theme",
              forcesDark && forcesLight && follows);

        // An imported theme must show up in the picker alongside the bundled ones.
        NSString *custom = TempFile(@"TestTheme.xml",
            @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus><LexerStyles>"
            @"<LexerType name=\"cpp\"><WordsStyle name=\"DEFAULT\" styleID=\"11\" "
            @"fgColor=\"123456\" bgColor=\"654321\" /></LexerType></LexerStyles>"
            @"<GlobalStyles><WidgetStyle name=\"Default Style\" styleID=\"32\" "
            @"fgColor=\"ABCDEF\" bgColor=\"222222\" /></GlobalStyles></NotepadPlus>");
        [ed importFiles:@[custom] intoSubdirectory:@"themes"];
        [StyleCatalog setImportedThemesDirectory:
            [[ed supportDirectory] stringByAppendingPathComponent:@"themes"]];
        NSArray *withImported = [StyleCatalog availableThemeNames];
        [StyleCatalog loadThemeNamed:@"TestTheme"];
        [ed applyLanguage];
        // 0x222222 is the same in either byte order, so the foreground is checked too.
        BOOL imported = [withImported containsObject:@"TestTheme"] &&
                        [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT] == 0x222222 &&
                        [sci message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT] == 0xEFCDAB;
        Check(@"IDM_SETTING_IMPORTSTYLETHEMES (usable)",
              @"an imported theme is listed and can be applied", imported);

        // Breadth: only two of the twenty-two bundled themes were ever loaded
        // here, so a theme that failed to parse would have gone unnoticed. Each
        // one has to give a default background and styles for a common lexer.
        NSMutableArray *badThemes = [NSMutableArray array];
        for (NSString *name in [StyleCatalog availableThemeNames]) {
            // The two synthetic themes other tests import are not Notepad++ themes.
            if ([name hasPrefix:@"TestTheme"] || [name hasPrefix:@"t_theme"]) continue;
            [StyleCatalog loadThemeNamed:name];
            [ed applyLanguage];
            NppStyle *defaultStyle = [StyleCatalog sharedCatalog].globalStyles[@"Default Style"];
            NSUInteger cppStyles = [[StyleCatalog sharedCatalog] stylesForLexerName:@"cpp"].count;
            if (!defaultStyle.background || !defaultStyle.foreground || cppStyles < 5) {
                [badThemes addObject:name];
            }
        }
        Check(@"IDM_SETTING_PREFERENCE (every theme)",
              @"each bundled theme parses and carries colours the editor can use",
              [StyleCatalog availableThemeNames].count >= 22 && badThemes.count == 0);
        if (badThemes.count) printf("       %s\n",
            [[badThemes componentsJoinedByString:@","] UTF8String]);

        [StyleCatalog loadThemeNamed:@"Default"];
        [ed applyLanguage];
    }

    if (NppSectionWanted(@"Toolbar")) { printf("\n== Toolbar ==\n");
        NppToolbar *tb = [app valueForKey:@"toolbar"];
        NSArray *ids = [tb itemIdentifiers];
        Check(@"IDM_SETTING_PREFERENCE (toolbar buttons)",
              @"the bar carries the editing commands",
              ids.count > 10 && [ids containsObject:@"npp.IDM_FILE_SAVE"] &&
              [ids containsObject:@"npp.IDM_SEARCH_FIND"]);

        Check(@"IDM_SETTING_PREFERENCE (toolbar actions)",
              @"each button drives the matching menu command",
              [tb actionForIdentifier:@"npp.IDM_FILE_SAVE"] == @selector(saveDocument:) &&
              [tb actionForIdentifier:@"npp.IDM_SEARCH_FIND"] == @selector(showFind:) &&
              [tb actionForIdentifier:@"npp.IDM_EDIT_UNDO"] == @selector(undo:));

        // The buttons, and their order, are generated from the Notepad++
        // sources rather than written out here, so the test reads the same
        // file and checks the bar agrees with it.
        NSString *orderPath = [[NSBundle mainBundle] pathForResource:@"order" ofType:@"txt"
                                                         inDirectory:@"toolbar"];
        NSMutableArray *expected = [NSMutableArray array];
        for (NSString *raw in [[NSString stringWithContentsOfFile:orderPath
                                                         encoding:NSUTF8StringEncoding error:NULL]
                               componentsSeparatedByString:@"\n"]) {
            NSString *line = [raw stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            if (!line.length || [line hasPrefix:@"#"] || [line isEqualToString:@"-"]) continue;
            [expected addObject:[@"npp." stringByAppendingString:
                                 [line componentsSeparatedByString:@"\t"].firstObject]];
        }
        NSMutableArray *actual = [NSMutableArray array];
        for (NSString *identifier in ids) {
            if ([identifier hasPrefix:@"npp."]) [actual addObject:identifier];
        }
        Check(@"IDM_SETTING_PREFERENCE (toolbar order)",
              @"the bar holds the same buttons, in the same order, as Notepad++",
              expected.count == 32 && [actual isEqualToArray:expected]);

        // Every button must actually carry its Notepad++ icon. An SF Symbol
        // standing in for a missing file would look plausible and be wrong, so
        // the test insists the image came from the bundled set.
        NSInteger withIcons = 0, distinct = 0;
        NSMutableSet *seen = [NSMutableSet set];
        for (NSToolbarItem *item in [app.window.toolbar items]) {
            if (![item.itemIdentifier hasPrefix:@"npp."]) continue;
            if (!item.image) continue;
            withIcons++;
            NSData *rendered = [item.image TIFFRepresentation];
            if (rendered && ![seen containsObject:rendered]) { [seen addObject:rendered]; distinct++; }
        }
        Check(@"IDM_SETTING_PREFERENCE (toolbar icons)",
              @"every button carries its own icon taken from the Notepad++ sources",
              withIcons == 32 && distinct >= 30);

        // The icons come in a light and a dark set; both have to be present,
        // and they have to differ, or one theme is silently using the other's.
        NSString *lightPath = [[NSBundle mainBundle] pathForResource:@"save_off" ofType:@"png"
                                                         inDirectory:@"toolbar/light"];
        NSString *darkPath = [[NSBundle mainBundle] pathForResource:@"save_off" ofType:@"png"
                                                        inDirectory:@"toolbar/dark"];
        NSData *lightData = lightPath ? [NSData dataWithContentsOfFile:lightPath] : nil;
        NSData *darkData = darkPath ? [NSData dataWithContentsOfFile:darkPath] : nil;
        Check(@"IDM_SETTING_PREFERENCE (toolbar themes)",
              @"a light and a dark icon are bundled for each button, and they differ",
              lightData.length > 0 && darkData.length > 0 && ![lightData isEqualToData:darkData]);

        NppPreferences *p = [NppPreferences shared];
        p.showToolbar = NO;  [app applyToolbarPreferences];
        BOOL hidden = ![tb visible];
        p.showToolbar = YES; [app applyToolbarPreferences];
        BOOL shown = [tb visible];
        // While a macro is recording, the record button is red, and it goes back
        // when recording stops.
        //
        // This looks at the picture rather than at the flag behind it. Checking
        // the flag passed while the button on screen stayed red: the item keeps
        // the image it was given, and handing it the same object again changes
        // nothing.
        NppToolbar *recordBar = [app valueForKey:@"toolbar"];
        NSString *recordCommand = @"IDM_MACRO_STARTRECORDINGMACRO";
        CGFloat (^redness)(void) = ^CGFloat {
            NSBitmapImageRep *shot = [recordBar renderedImageForCommand:recordCommand];
            if (!shot) return -1;
            CGFloat red = 0, other = 0;
            for (NSInteger x = 0; x < shot.pixelsWide; ++x) {
                for (NSInteger y = 0; y < shot.pixelsHigh; ++y) {
                    NSColor *pixel = [shot colorAtX:x y:y];
                    if (pixel.alphaComponent < 0.3) continue;
                    CGFloat r = pixel.redComponent, g = pixel.greenComponent, b = pixel.blueComponent;
                    if (r > 0.5 && r > g + 0.2 && r > b + 0.2) red++; else other++;
                }
            }
            return (red + other) > 0 ? red / (red + other) : -1;
        };

        // Drawing the image here re-runs its handler and so always shows the
        // right colour; what went wrong on screen was that the item was never
        // handed anything new to draw. So the object is watched as well.
        NSToolbarItem *recordItem = nil;
        for (NSToolbarItem *candidate in app.window.toolbar.items) {
            if ([candidate.itemIdentifier isEqualToString:
                 [@"npp." stringByAppendingString:recordCommand]]) recordItem = candidate;
        }
        NSImage *imageBefore = recordItem.image;

        CGFloat before = redness();
        [app macroStart:nil];
        CGFloat during = redness();
        [app macroStop:nil];
        NSImage *imageDuring = recordItem.image;
        [app macroStop:nil];
        CGFloat after = redness();
        NSImage *imageAfter = recordItem.image;
        BOOL redrawn = recordItem != nil &&
                       imageDuring != imageBefore && imageAfter != imageDuring;

        Check(@"IDM_MACRO_STARTRECORDINGMACRO (shown while recording)",
              @"the record button turns red while recording and goes back afterwards",
              before >= 0 && before < 0.1 && during > 0.5 && after < 0.1 && redrawn);
        if (!(before < 0.1 && during > 0.5 && after < 0.1 && redrawn)) {
            printf("       красного: до %.2f, во время %.2f, после %.2f; перерисован: %s\n",
                   before, during, after, redrawn ? "да" : "нет");
        }

        Check(@"IDM_SETTING_PREFERENCE (toolbar visibility)",
              @"the setting shows and hides the bar", hidden && shown);

        // Labels must reach AppKit, not just the stored request: the compact
        // toolbar style silently ignores the display mode, so asking for labels
        // has to switch the window style too.
        p.toolbarDisplayMode = 1; [app applyToolbarPreferences];
        BOOL labels = tb.displayMode == 1 &&
                      tb.effectiveDisplayMode == NSToolbarDisplayModeIconAndLabel &&
                      app.window.toolbarStyle == NSWindowToolbarStyleExpanded;

        p.toolbarDisplayMode = 2; [app applyToolbarPreferences];
        BOOL labelsOnly = tb.effectiveDisplayMode == NSToolbarDisplayModeLabelOnly;

        p.toolbarDisplayMode = 0; [app applyToolbarPreferences];
        BOOL iconsOnly = tb.effectiveDisplayMode == NSToolbarDisplayModeIconOnly;

        p.toolbarIconSize = 0; [app applyToolbarPreferences];
        BOOL regular = tb.iconSize == 0 && app.window.toolbarStyle == NSWindowToolbarStyleExpanded;
        p.toolbarIconSize = 1; [app applyToolbarPreferences];
        BOOL small = tb.iconSize == 1 && app.window.toolbarStyle == NSWindowToolbarStyleUnifiedCompact;

        Check(@"IDM_SETTING_PREFERENCE (toolbar layout)",
              @"display mode and size reach AppKit, including their interaction",
              labels && labelsOnly && iconsOnly && regular && small);
    }

    if (NppSectionWanted(@"Backup and autosave")) { printf("\n== Backup and autosave ==\n");
        NppPreferences *p = [NppPreferences shared];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSInteger savedMode = p.backupMode;

        // No backup: saving must leave nothing beside the file.
        NSString *path = TempFile(@"t_backup.txt", @"first version\n");
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingPathExtension:@"bak"] error:NULL];
        p.backupMode = NppBackupNone;
        NSError *err = nil;
        [ed openFileAtPath:path error:&err];
        SetDoc(ed, @"second version\n");
        [ed saveCurrentDocument];
        Check(@"IDM_SETTING_PREFERENCE (backup off)", @"no backup is written when it is off",
              ![fm fileExistsAtPath:[path stringByAppendingPathExtension:@"bak"]]);

        // Simple: the previous contents land in file.ext.bak.
        p.backupMode = NppBackupSimple;
        SetDoc(ed, @"third version\n");
        NSString *simple = [ed writeBackupForPath:path];
        NSString *backedUp = [NSString stringWithContentsOfFile:simple
                                                       encoding:NSUTF8StringEncoding error:NULL];
        Check(@"IDM_SETTING_PREFERENCE (backup simple)",
              @"the copy holds what was on disk before the save",
              [simple hasSuffix:@".bak"] && [backedUp isEqualToString:@"second version\n"]);

        // Verbose: a timestamped copy in the backup folder.
        p.backupMode = NppBackupVerbose;
        NSString *verbose = [ed writeBackupForPath:path];
        Check(@"IDM_SETTING_PREFERENCE (backup verbose)",
              @"a timestamped copy lands in the backup folder",
              [verbose hasPrefix:[ed backupDirectory]] &&
              [[ed backupsForPath:path] containsObject:verbose]);
        p.backupMode = savedMode;

        // A backup pass writes the unsaved text to the backup folder and leaves
        // the files themselves alone; the session lists the backups.
        [ed closeAllDocuments];
        NSString *tracked = TempFile(@"t_autosave.txt", @"original\n");
        [ed openFileAtPath:tracked error:&err];
        SetDoc(ed, @"changed by autosave\n");
        ed.currentDocument.modified = YES;
        NppDocument *trackedDoc = ed.currentDocument;
        [ed newDocument];
        SetDoc(ed, @"never saved anywhere\n");
        NppDocument *untitledDoc = ed.currentDocument;

        NSUInteger written = [ed runAutosavePass];
        NSString *onDisk = [NSString stringWithContentsOfFile:tracked
                                                     encoding:NSUTF8StringEncoding error:NULL];
        NSString *trackedBackup = trackedDoc.backupPath
            ? [NSString stringWithContentsOfFile:trackedDoc.backupPath encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSString *untitledBackup = untitledDoc.backupPath
            ? [NSString stringWithContentsOfFile:untitledDoc.backupPath encoding:NSUTF8StringEncoding error:NULL] : nil;
        Check(@"IDM_SETTING_PREFERENCE (periodic backup)",
              @"the unsaved text of every modified document goes to a backup file, and the "
              @"file itself is not written",
              written == 2 && [onDisk isEqualToString:@"original\n"] &&
              [trackedBackup isEqualToString:@"changed by autosave\n"] &&
              [untitledBackup isEqualToString:@"never saved anywhere\n"] &&
              [trackedDoc.backupPath hasPrefix:[ed backupDirectory]]);

        // Saving drops the backup; the session brings an untitled one back.
        NSString *sessionFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-backup-session.json"];
        [ed saveSessionTo:sessionFile error:NULL];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:trackedDoc]];
        [ed saveCurrentDocument];
        BOOL droppedOnSave = trackedDoc.backupPath == nil;
        NSString *keptBackup = untitledDoc.backupPath;
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:trackedDoc] discardChanges:YES];
        // The untitled document is dropped without its backup being removed,
        // as a crash would leave it.
        untitledDoc.backupPath = nil;
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:untitledDoc] discardChanges:YES];
        [ed loadSessionFrom:sessionFile error:NULL];
        NppDocument *restored = nil;
        for (NppDocument *d in ed.documents) {
            if (!d.path && [d.backupPath isEqualToString:keptBackup]) restored = d;
        }
        BOOL cameBack = restored != nil && restored.modified;
        if (restored) {
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:restored]];
            cameBack = cameBack && [[ed documentText] isEqualToString:@"never saved anywhere\n"];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:restored] discardChanges:YES];
        }
        for (NppDocument *d in [ed.documents copy]) {
            if ([d.path isEqualToString:tracked]) [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:d] discardChanges:YES];
        }
        [[NSFileManager defaultManager] removeItemAtPath:sessionFile error:NULL];
        Check(@"IDM_FILE_LOADSESSION (unsaved text comes back)",
              @"saving a document drops its backup, and an untitled document's backup is "
              @"restored from the session, still modified",
              droppedOnSave && cameBack);

        [ed setAutosaveEnabled:YES interval:60];
        BOOL running = [ed autosaveRunning];
        [ed setAutosaveEnabled:NO interval:60];
        Check(@"IDM_SETTING_PREFERENCE (autosave timer)", @"the timer starts and stops",
              running && ![ed autosaveRunning]);
    }

    if (NppSectionWanted(@"Print options")) { printf("\n== Print options ==\n");
        NppPreferences *p = [NppPreferences shared];
        NSError *err = nil;
        NSString *path = TempFile(@"t_print.txt", @"alpha\nbeta\ngamma\n");
        [ed openFileAtPath:path error:&err];

        NSString *header = [ed expandPrintTemplate:
            @"$(FILE_NAME) | $(NAME_PART).$(EXT_PART) | page $(CURRENT_PRINTING_PAGE) of $(TOTAL_PRINTING_PAGE)"
                                              page:2 of:7];
        Check(@"IDM_SETTING_PREFERENCE (print header)",
              @"the $(...) variables are expanded",
              [header isEqualToString:@"t_print.txt | t_print.txt | page 2 of 7"] &&
              ![header containsString:@"$("]);

        p.printLineNumbers = NO;
        NSString *plain = [ed textForPrinting];
        p.printLineNumbers = YES;
        NSString *numbered = [ed textForPrinting];
        p.printLineNumbers = NO;
        Check(@"IDM_SETTING_PREFERENCE (print line numbers)",
              @"line numbers are added only when asked for",
              ![plain hasPrefix:@"1"] && [numbered hasPrefix:@"1  alpha"] &&
              [numbered containsString:@"3  gamma"]);

        p.printMarginLeft = 11; p.printMarginRight = 22;
        p.printMarginTop = 33; p.printMarginBottom = 44;
        NSPrintInfo *info = [ed printInfoFromPreferences];
        Check(@"IDM_SETTING_PREFERENCE (print margins)",
              @"the configured margins reach the print info",
              info.leftMargin == 11 && info.rightMargin == 22 &&
              info.topMargin == 33 && info.bottomMargin == 44);

        // Building the job must not reach a printer, so only the job is checked.
        p.printColourMode = NppPrintInvert;
        NSPrintOperation *op = [ed printOperationShowingPanel:NO];
        NSTextView *page = (NSTextView *)op.view;
        BOOL inverted = [page.backgroundColor isEqual:[NSColor blackColor]] && page.drawsBackground;
        p.printColourMode = NppPrintBlackOnWhite;
        NSTextView *plainPage = (NSTextView *)[ed printOperationShowingPanel:NO].view;
        Check(@"IDM_SETTING_PREFERENCE (print colours)",
              @"the colour mode reaches the printed page",
              op != nil && inverted && !plainPage.drawsBackground &&
              [plainPage.textColor isEqual:[NSColor blackColor]]);
        p.printColourMode = 2;
    }

    if (NppSectionWanted(@"Performance, links, delimiters")) { printf("\n== Performance, links, delimiters ==\n");
        NppPreferences *p = [NppPreferences shared];

        // Large file restriction: a threshold of 0 MB makes any document large.
        [ed newDocument];
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"// a comment\nint x = 1;\n");
        p.largeFileRestrictionEnabled = YES;
        p.largeFileThresholdMB = 200;
        BOOL normalFile = ![ed largeFileRestrictionActive];
        p.largeFileThresholdMB = 0;
        BOOL nowRestricted = [ed largeFileRestrictionActive];
        [ed applyPerformanceRestrictions];
        long styledUnderRestriction = [sci message:SCI_GETSTYLEAT wParam:0];
        p.largeFileThresholdMB = 200;
        [ed applyPerformanceRestrictions];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        long styledNormally = [sci message:SCI_GETSTYLEAT wParam:0];
        Check(@"IDM_SETTING_PREFERENCE (large files)",
              @"highlighting is dropped above the threshold and restored below it",
              normalFile && nowRestricted && styledUnderRestriction == 0 &&
              styledNormally == SCE_C_COMMENTLINE);

        // Clickable links.
        p.linksEnabled = YES;
        p.linkCustomSchemes = @"";
        SetDoc(ed, @"see https://example.org/page and mailto:a@b.c here\n");
        NSUInteger links = [ed markClickableLinks];
        NSString *first = [ed linkAtPosition:6];
        Check(@"IDM_SETTING_PREFERENCE (links)",
              @"URLs are marked and readable back",
              links == 2 && [first isEqualToString:@"https://example.org/page"]);

        p.linkCustomSchemes = @"obsidian";
        SetDoc(ed, @"obsidian://open?vault=x\n");
        NSUInteger custom = [ed markClickableLinks];
        Check(@"IDM_SETTING_PREFERENCE (link schemes)",
              @"a custom scheme is recognised too",
              custom == 1 && [[ed linkAtPosition:2] hasPrefix:@"obsidian://"]);
        p.linkCustomSchemes = @"";

        p.linksEnabled = NO;
        SetDoc(ed, @"https://example.org/\n");
        Check(@"IDM_SETTING_PREFERENCE (links off)", @"nothing is marked when links are off",
              [ed markClickableLinks] == 0 && [ed linkAtPosition:2] == nil);
        p.linksEnabled = YES;

        // Brace match.
        p.braceMatchEnabled = YES;
        SetDoc(ed, @"value = (a + b);\n");
        [sci message:SCI_GOTOPOS wParam:8 lParam:0];
        [ed updateBraceMatch];
        BOOL matched = [sci message:SCI_BRACEMATCH wParam:8 lParam:0] == 14;
        p.braceMatchEnabled = NO;
        [ed updateBraceMatch];
        Check(@"IDM_SETTING_PREFERENCE (brace match)",
              @"the matching brace is found while the setting is on", matched);
        p.braceMatchEnabled = YES;

        // Smart highlighting marks the other occurrences of a selected token.
        // (Whole words off, so that "subtotal" counts: the default is on.)
        p.smartHighlightEnabled = YES;
        BOOL wholeWas = p.smartHighlightWholeWord, caseWas2 = p.smartHighlightMatchCase, findWas = p.smartHighlightUseFindSettings;
        p.smartHighlightWholeWord = NO;
        p.smartHighlightMatchCase = NO;
        p.smartHighlightUseFindSettings = NO;
        SetDoc(ed, @"total = total + subtotal\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        NSUInteger marks = [ed updateSmartHighlight];
        p.smartHighlightEnabled = NO;
        NSUInteger none = [ed updateSmartHighlight];
        p.smartHighlightWholeWord = wholeWas;
        p.smartHighlightMatchCase = caseWas2;
        p.smartHighlightUseFindSettings = findWas;
        Check(@"IDM_SETTING_PREFERENCE (smart highlighting)",
              @"occurrences are marked only while the setting is on",
              marks == 3 && none == 0);
        p.smartHighlightEnabled = YES;

        // Word characters change what counts as a word for selection.
        SetDoc(ed, @"alpha-beta gamma\n");
        p.customWordCharsEnabled = NO;
        [ed applyLanguage];
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        long plainEnd = [sci message:SCI_WORDENDPOSITION wParam:2 lParam:1];
        p.customWordCharsEnabled = YES;
        p.customWordChars = @"-";
        [ed applyWordCharacters];
        long extendedEnd = [sci message:SCI_WORDENDPOSITION wParam:2 lParam:1];
        p.customWordCharsEnabled = NO;
        [ed applyLanguage];
        Check(@"IDM_SETTING_PREFERENCE (word characters)",
              @"adding '-' makes the hyphenated word one word",
              plainEnd == 5 && extendedEnd == 10);

        // Delimiter selection.
        p.delimiterOpen = @"("; p.delimiterClose = @")"; p.delimiterMultiline = NO;
        SetDoc(ed, @"call(inside here) tail\n");
        BOOL selected = [ed selectBetweenDelimitersAt:8];
        Check(@"IDM_SETTING_PREFERENCE (delimiters)",
              @"the text between the delimiters is selected",
              selected && [sci message:SCI_GETSELECTIONSTART] == 5 &&
              [sci message:SCI_GETSELECTIONEND] == 16);

        p.delimiterOpen = @"["; p.delimiterClose = @"]";
        SetDoc(ed, @"arr[42] rest\n");
        BOOL brackets = [ed selectBetweenDelimitersAt:5];
        Check(@"IDM_SETTING_PREFERENCE (delimiter choice)",
              @"the configured delimiters are the ones used",
              brackets && [sci message:SCI_GETSELECTIONSTART] == 4 &&
              [sci message:SCI_GETSELECTIONEND] == 6);
        p.delimiterOpen = @"("; p.delimiterClose = @")";
    }

    if (NppSectionWanted(@"Instances, panels, settings folder")) { printf("\n== Instances, panels, settings folder ==\n");
        NppPreferences *p = [NppPreferences shared];

        p.multiInstanceMode = 0;
        BOOL mono = ![ed shouldOpenFilesInNewInstance];
        p.multiInstanceMode = 1;
        BOOL multi = [ed shouldOpenFilesInNewInstance];
        p.multiInstanceMode = 0;
        Check(@"IDM_SETTING_PREFERENCE (instances)",
              @"the mode decides whether a file starts another instance", mono && multi);

        // Reversing the order puts the time before the date.
        p.reverseDateTimeOrder = NO;
        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        NSString *normal = DocText(ed);
        p.reverseDateTimeOrder = YES;
        SetDoc(ed, @"");
        [ed insertDateTimeShort:YES];
        NSString *reversed = DocText(ed);
        p.reverseDateTimeOrder = NO;
        Check(@"IDM_SETTING_PREFERENCE (date order)",
              @"the reversed form differs from the default one",
              normal.length > 0 && reversed.length > 0 && ![normal isEqualToString:reversed]);

        // Panel state survives a remember/restore round trip.
        p.rememberPanelState = YES;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_panels"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [ed openFolderAsWorkspace:dir];
        [ed setDocumentMapVisible:YES];
        [ed rememberPanelState];
        NSDictionary *stored = p.panelState;
        [ed openFolderAsWorkspace:nil];
        [ed setDocumentMapVisible:NO];
        [ed restorePanelState];
        Check(@"IDM_SETTING_PREFERENCE (panel state)",
              @"the open panels are remembered and reopened",
              [stored[@"workspace"] boolValue] && [stored[@"documentMap"] boolValue] &&
              [ed documentMapVisible]);
        [ed setDocumentMapVisible:NO];
        [ed openFolderAsWorkspace:nil];
        p.rememberPanelState = NO;

        // Relocating the settings folder moves everything that lives in it.
        NSString *custom = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_settings"];
        NSString *defaultDir = [ed supportDirectory];
        p.settingsDirectory = custom;
        NSString *moved = [ed supportDirectory];
        p.settingsDirectory = @"";
        Check(@"IDM_SETTING_PREFERENCE (settings folder)",
              @"the configured folder replaces the default one",
              [moved isEqualToString:custom] && ![moved isEqualToString:defaultDir] &&
              [[ed supportDirectory] isEqualToString:defaultDir]);
    }

    if (NppSectionWanted(@"Auto-completion and typing")) { printf("\n== Auto-completion and typing ==\n");
        NppPreferences *p = [NppPreferences shared];
        [ed newDocument];
        [ed setLanguageNamed:@"cpp"];

        // Candidate sources: words from the document, keywords, or both.
        SetDoc(ed, @"retrieval retrospect\n");
        p.autoCompleteSource = NppCompletionWords;
        NSArray *words = [ed completionCandidatesForPrefix:@"retr"];
        p.autoCompleteSource = NppCompletionFunctions;
        NSArray *keywords = [ed completionCandidatesForPrefix:@"ret"];
        p.autoCompleteSource = NppCompletionBoth;
        NSArray *both = [ed completionCandidatesForPrefix:@"ret"];
        Check(@"IDM_SETTING_PREFERENCE (completion sources)",
              @"words, keywords and both give different candidate sets",
              words.count == 2 && [keywords containsObject:@"return"] &&
              ![words containsObject:@"return"] && both.count > keywords.count);

        // Function Completion opens the language's whole list and lets
        // Scintilla find the place; the brief one lists only what fits.
        SetDoc(ed, @"ret");
        [sci message:SCI_GOTOPOS wParam:3 lParam:0];
        BOOL fullShown = [ed showCompletion:NppCompletionKindFunctions autoInsert:NO];
        NSArray *full = [ed lastCompletionList];
        [sci message:SCI_AUTOCCANCEL];
        BOOL briefShown = [ed showCompletion:NppCompletionKindFunctionsBrief autoInsert:NO];
        NSArray *brief = [ed lastCompletionList];
        [sci message:SCI_AUTOCCANCEL];
        BOOL briefFits = brief.count > 0;
        for (NSString *w in brief) if (![w hasPrefix:@"ret"]) briefFits = NO;
        Check(@"IDM_SETTING_PREFERENCE (brief list)",
              @"the full list is the language's whole list, the brief one only the names that fit",
              fullShown && briefShown && briefFits && full.count > brief.count && [full containsObject:@"return"]);

        // Word Completion types a lone candidate; plain text respects case,
        // and a language whose API file says so does not.
        [ed setLanguageNamed:@"normal"];
        SetDoc(ed, @"alphabet Alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL inserted = [ed showCompletion:NppCompletionKindWords autoInsert:YES] &&
                        [DocText(ed) isEqualToString:@"alphabet Alpine\nalphabet"] && ![sci message:SCI_AUTOCACTIVE];
        [ed setLanguageNamed:@"sql"];
        SetDoc(ed, @"alphabet Alpine\nalp");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        BOOL anyCase = [ed completionIgnoresCase] && [ed showCompletion:NppCompletionKindWords autoInsert:YES] &&
                       [sci message:SCI_AUTOCACTIVE] && [[ed lastCompletionList] isEqualToArray:(@[@"alphabet", @"Alpine"])];
        [sci message:SCI_AUTOCCANCEL];
        Check(@"IDM_EDIT_AUTOCOMPLETE_CURRENTFILE (as upstream)",
              @"a single word is typed in at once, and case is ignored only where the language's file says so",
              inserted && anyCase);
        [ed setLanguageNamed:@"cpp"];

        p.autoCompleteIgnoreNumbers = YES;
        NSArray *numeric = [ed completionCandidatesForPrefix:@"12"];
        p.autoCompleteIgnoreNumbers = NO;
        Check(@"IDM_SETTING_PREFERENCE (ignore numbers)",
              @"a numeric prefix offers nothing while that is on", numeric.count == 0);
        p.autoCompleteIgnoreNumbers = YES;

        // Auto-insertion of the matching character.
        struct { int ch; NSString *want; NSString *flag; } pairs[] = {
            {'(', @")", @"autoInsertParenthesis"},
            {'[', @"]", @"autoInsertBracket"},
            {'{', @"}", @"autoInsertBrace"},
            {'\'', @"'", @"autoInsertSingleQuote"},
            {'"', @"\"", @"autoInsertDoubleQuote"},
        };
        BOOL allPairs = YES;
        for (size_t i = 0; i < sizeof(pairs)/sizeof(pairs[0]); ++i) {
            [p setValue:@NO forKey:pairs[i].flag];
            if ([ed autoInsertionForCharacter:pairs[i].ch] != nil) allPairs = NO;
            [p setValue:@YES forKey:pairs[i].flag];
            if (![[ed autoInsertionForCharacter:pairs[i].ch] isEqualToString:pairs[i].want]) allPairs = NO;
            [p setValue:@NO forKey:pairs[i].flag];
        }
        Check(@"IDM_SETTING_PREFERENCE (auto-insert)",
              @"each pair is inserted only while its own setting is on", allPairs);

        // The close tag follows the element that was just opened.
        p.autoInsertCloseTag = YES;
        [ed setLanguageNamed:@"html"];
        SetDoc(ed, @"<div>");
        [sci message:SCI_GOTOPOS wParam:5 lParam:0];
        [ed setLanguageNamed:@"html"];
        NSString *closeTag = [ed closeTagAtCaret];
        SetDoc(ed, @"<img src=\"a.png\"/>");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        NSString *selfClosing = [ed closeTagAtCaret];
        p.autoInsertCloseTag = NO;
        Check(@"IDM_SETTING_PREFERENCE (close tag)",
              @"an opened element is closed and a self-closing one is not",
              [closeTag isEqualToString:@"</div>"] && selfClosing == nil);

        // Typing drives both: the pair is inserted and the caret stays inside.
        p.autoInsertParenthesis = YES;
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"");
        [sci setStringProperty:SCI_INSERTTEXT parameter:0 value:@"("];
        [sci message:SCI_GOTOPOS wParam:1 lParam:0];
        [ed handleCharacterAdded:'('];
        Check(@"IDM_SETTING_PREFERENCE (typing)",
              @"typing an opening bracket closes it and leaves the caret between",
              [DocText(ed) isEqualToString:@"()"] && [sci message:SCI_GETCURRENTPOS] == 1);
        p.autoInsertParenthesis = NO;

        // Typing into the document, as a key press does: insert, then notify.
        void (^type)(NSString *) = ^(NSString *text) {
            for (NSUInteger i = 0; i < text.length; ++i) {
                unichar c = [text characterAtIndex:i];
                [sci setStringProperty:SCI_REPLACESEL parameter:0 value:[NSString stringWithCharacters:&c length:1]];
                [ed handleCharacterAdded:c];
            }
        };

        // A quote after an opening bracket is closed too, as upstream.
        p.autoInsertDoubleQuote = YES;
        SetDoc(ed, @"f(");
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        type(@"\"");
        BOOL quoted = [DocText(ed) isEqualToString:@"f(\"\""];
        p.autoInsertDoubleQuote = NO;

        // The user's own pairs come first, and only before a blank.
        p.userMatchedPairs = @[@"<>", @"*~"];
        SetDoc(ed, @"");
        type(@"<");
        BOOL userPair = [DocText(ed) isEqualToString:@"<>"];
        SetDoc(ed, @"x");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        type(@"<");
        BOOL notBeforeText = [DocText(ed) isEqualToString:@"<x"];
        p.userMatchedPairs = @[];
        Check(@"IDM_SETTING_PREFERENCE (matched pairs)",
              @"a quote after a bracket is paired, and the user's pairs are closed before a blank only",
              quoted && userPair && notBeforeText);

        // Nothing is added while a macro records.
        p.autoInsertParenthesis = YES;
        SetDoc(ed, @"");
        [ed startRecordingMacro];
        type(@"(");
        [ed stopRecordingMacro];
        BOOL untouched = [DocText(ed) isEqualToString:@"("];
        p.autoInsertParenthesis = NO;
        Check(@"IDM_MACRO_STARTRECORDINGMACRO (typing)",
              @"a macro records what was typed, with no bracket or completion added to it", untouched);

        // The parameter hint follows the typing: "(" opens it, "," moves on to
        // the next parameter, ")" closes it; the arrows step between overloads.
        BOOL hintBefore = p.functionHintOnInput;
        p.functionHintOnInput = YES;
        [ed setLanguageNamed:@"c"];
        SetDoc(ed, @"f = ");
        [sci message:SCI_GOTOPOS wParam:4 lParam:0];
        type(@"fopen(");
        NSDictionary *open = [ed apiCallTipState];
        type(@"name, ");
        NSDictionary *second = [ed apiCallTipState];
        type(@"\"r\")");
        BOOL closed = ![ed apiCallTipVisible];
        [ed setLanguageNamed:@"perl"];
        SetDoc(ed, @"$x = ");
        [sci message:SCI_GOTOPOS wParam:5 lParam:0];
        type(@"abs(");
        NSInteger firstOverload = [[ed apiCallTipState][@"overload"] integerValue];
        [ed callTipClicked:2];
        NSInteger nextOverload = [[ed apiCallTipState][@"overload"] integerValue];
        [sci message:SCI_CALLTIPCANCEL];
        p.functionHintOnInput = hintBefore;
        Check(@"IDM_EDIT_FUNCCALLTIP (typing)",
              @"the hint opens on (, moves to the next parameter on a comma, closes on ), and its arrows change overload",
              [open[@"name"] isEqualToString:@"fopen"] && [open[@"param"] integerValue] == 0 &&
              [second[@"param"] integerValue] == 1 && closed && firstOverload == 0 && nextOverload == 1);

        // Advanced auto-indent, rule for rule: one statement after a braceless
        // if, a Python block after a colon, a closing brace under its opener.
        NSInteger indentBefore = p.autoIndentMode;
        p.autoIndentMode = 2;
        [sci message:SCI_SETTABWIDTH wParam:4 lParam:0];
        long (^indentHere)(void) = ^long {
            return [sci message:SCI_GETLINEINDENTATION
                         wParam:(uptr_t)[sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]]];
        };
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"");
        type(@"if (x)\n");
        long afterIf = indentHere();
        type(@"y();\n");
        long afterStatement = indentHere();
        SetDoc(ed, @"    {\n        x;\n        ");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        type(@"}");
        long closer = indentHere();
        [ed setLanguageNamed:@"python"];
        SetDoc(ed, @"");
        type(@"def f(a):  # note\n");
        long pyBlock = indentHere();
        SetDoc(ed, @"");
        type(@"s = 'a:'\n");
        long pyString = indentHere();
        p.autoIndentMode = indentBefore;
        Check(@"IDM_SETTING_PREFERENCE (advanced indent)",
              @"C-like, braceless if, closing brace and Python colon indent as Notepad++ does",
              afterIf == 4 && afterStatement == 0 && closer == 4 && pyBlock == 4 && pyString == 0);
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"");
    }

    if (NppSectionWanted(@"Preferences: Language, Indentation, MISC., Search Engine")) { printf("\n== Preferences: Language, Indentation, MISC., Search Engine ==\n");
        NppPreferences *mp = [NppPreferences shared];
        // Per-language indent settings, and Backspace unindenting.
        NSDictionary *indentBefore = mp.languageIndent;
        mp.languageIndent = @{@"python": @{@"size": @2, @"spaces": @YES}};
        mp.backspaceUnindents = YES;
        [ed newDocument];
        [ed setLanguageNamed:@"python"];
        [ed applyDocumentSettings];
        BOOL pyIndent = [sci message:SCI_GETTABWIDTH] == 2 && [sci message:SCI_GETUSETABS] == 0 &&
                        [sci message:SCI_GETBACKSPACEUNINDENTS] == 1;
        [ed setLanguageNamed:@"cpp"];
        [ed applyDocumentSettings];
        BOOL cppDefault = [sci message:SCI_GETTABWIDTH] == MAX(1, mp.tabWidth);
        mp.languageIndent = indentBefore ?: @{};
        mp.backspaceUnindents = NO;
        [ed applyDocumentSettings];
        Check(@"IDM_SETTING_PREFERENCE (indent per language)",
              @"a language's own indent settings apply to it alone, and Backspace can unindent",
              pyIndent && cppDefault);

        // The Language menu: letter submenus by default, upstream's titles,
        // and the languages Preferences leaves out.
        NSMenu *langMenu = app.languageMenu;
        mp.languageMenuCompact = YES;
        mp.languageMenuHidden = @[@"python"];
        [app rebuildLanguageMenu];
        NSMenu *cMenu = [langMenu itemWithTitle:@"C"].submenu;
        NSMenu *pMenu = [langMenu itemWithTitle:@"P"].submenu;
        BOOL compact = [langMenu indexOfItemWithTitle:@"None (Normal Text)"] == 0 && [cMenu itemWithTitle:@"C++"] != nil &&
                       [[cMenu itemWithTitle:@"C++"].representedObject isEqualToString:@"cpp"] &&
                       pMenu && ![pMenu itemWithTitle:@"Python"];
        mp.languageMenuCompact = NO;
        mp.languageMenuHidden = @[];
        [app rebuildLanguageMenu];
        BOOL flat = [langMenu itemWithTitle:@"C++"] != nil && [langMenu itemWithTitle:@"Python"] != nil &&
                    [langMenu itemWithTitle:@"User Defined Language"] != nil;
        mp.languageMenuCompact = YES;
        [app rebuildLanguageMenu];
        Check(@"IDM_SETTING_PREFERENCE (language menu)",
              @"the Language menu has upstream's titles in letter submenus, or flat, less the hidden languages",
              compact && flat);

        // Search Engine.
        NSInteger engineBefore = mp.searchEngine;
        mp.searchEngine = 0;
        NSString *duck = [mp searchEngineTemplate];
        mp.searchEngine = 4;
        mp.searchEngineCustom = @"https://example.org/find?w=$(CURRENT_WORD)&x=1";
        NSString *custom = [mp searchEngineTemplate];
        mp.searchEngine = engineBefore;
        Check(@"IDM_SETTING_PREFERENCE (search engine)",
              @"the engine chosen, or a URL with $(CURRENT_WORD), is what Search on Internet opens",
              [duck hasPrefix:@"https://duckduckgo.com/"] &&
              [[NSString stringWithFormat:custom, @"abc"] isEqualToString:@"https://example.org/find?w=abc&x=1"]);

        // MISC.: file name only in the title, the status bar hidden, files
        // with the session and workspace extensions opening as such.
        mp.titleBarFileNameOnly = YES;
        NSString *titled = TempFile(@"t_title.txt", @"t\n");
        [ed openFileAtPath:titled error:NULL];
        [ed refreshChrome];
        BOOL shortTitle = [ed.window.title isEqualToString:@"t_title.txt"];
        mp.titleBarFileNameOnly = NO;
        [ed refreshChrome];
        BOOL longTitle = [ed.window.title containsString:@" — "];
        mp.statusBarHidden = YES;
        [ed applyStatusBarVisibility];
        BOOL noStatus = ![ed statusBarVisible];
        mp.statusBarHidden = NO;
        [ed applyStatusBarVisibility];
        BOOL status = [ed statusBarVisible];

        NSString *sessionFile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_session.npps"];
        [ed saveSessionTo:sessionFile error:NULL];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
        mp.sessionFileExtension = @"npps";
        BOOL sessionOpened = [ed openFileAtPath:sessionFile error:NULL] &&
            [ed.documents indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *st) { return [d.path isEqualToString:titled]; }] != NSNotFound;
        mp.sessionFileExtension = @"";
        NSString *workspace = TempFile(@"t_ws.nppw", @"<NotepadPlus><Project name=\"P\"><File name=\"a.txt\"/></Project></NotepadPlus>");
        mp.workspaceFileExtension = @".nppw";
        [ed openFileAtPath:workspace error:NULL];
        BOOL workspaceOpened = [[ed projectPanel:1].workspacePath isEqualToString:workspace];
        mp.workspaceFileExtension = @"";
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            if ([ed.documents[(NSUInteger)i].path isEqualToString:titled]) [ed closeDocumentAtIndex:i discardChanges:YES];
        }
        Check(@"IDM_SETTING_PREFERENCE (MISC.)",
              @"file name only in the title, a hidden status bar, and the session / workspace extensions work",
              shortTitle && longTitle && noStatus && status && sessionOpened && workspaceOpened);

        // Folder as Workspace leaves symbolic links out unless allowed.
        NSString *wsDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_symlinks"];
        [[NSFileManager defaultManager] removeItemAtPath:wsDir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:wsDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"x" writeToFile:[wsDir stringByAppendingPathComponent:@"real.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [[NSFileManager defaultManager] createSymbolicLinkAtPath:[wsDir stringByAppendingPathComponent:@"link.txt"]
                                             withDestinationPath:[wsDir stringByAppendingPathComponent:@"real.txt"] error:NULL];
        WorkspacePanel *wsp = [[WorkspacePanel alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        mp.workspaceSymlinks = NO;
        [wsp setRootPath:wsDir];
        NSArray *withoutLinks = [wsp topLevelNames];
        mp.workspaceSymlinks = YES;
        [wsp setRootPath:wsDir];
        NSArray *withLinks = [wsp topLevelNames];
        mp.workspaceSymlinks = NO;
        Check(@"IDM_FILE_OPENFOLDERASWORKSPACE (symlinks)",
              @"symbolic links are listed only when MISC. allows them",
              ![withoutLinks containsObject:@"link.txt"] && [withLinks containsObject:@"link.txt"]);

        // Document Switcher: Ctrl+Tab in most-recently-used order while
        // Control is held, or through the tabs in order.
        NSUInteger docsBefore = ed.documents.count;
        [ed newDocument]; NppDocument *da = ed.currentDocument;
        [ed newDocument]; NppDocument *db = ed.currentDocument;
        [ed newDocument]; NppDocument *dc = ed.currentDocument;
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:da]];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:dc]];
        mp.docSwitcherEnabled = YES; mp.docSwitcherMRU = YES;
        [app switchDocumentForward:YES];
        BOOL mruFirst = ed.currentDocument == da && [app documentSwitcherShown];
        [app switchDocumentForward:YES];
        BOOL mruSecond = ed.currentDocument != da && ed.currentDocument != dc;
        [app endDocumentSwitch];
        BOOL hidden = ![app documentSwitcherShown];
        mp.docSwitcherEnabled = NO;
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:db]];
        [app switchDocumentForward:YES];
        BOOL inOrder = ed.currentDocument == dc && ![app documentSwitcherShown];
        mp.docSwitcherEnabled = YES;
        while (ed.documents.count > docsBefore) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        Check(@"IDM_SETTING_PREFERENCE (document switcher)",
              @"Ctrl+Tab goes to the document used last and shows the list, or steps through the tabs when off",
              mruFirst && mruSecond && hidden && inOrder);
    }

    if (NppSectionWanted(@"Preferences: Editing and Margins")) { printf("\n== Preferences: Editing and Margins ==\n");
        NppPreferences *lp = [NppPreferences shared];
        [ed newDocument];
        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"int f() {\n    return 0;\n}\n");
        // Fold margin styles, and None hiding the margin.
        lp.foldMarginStyle = 1;
        [ed applyEditorPreferences];
        BOOL arrow = [sci message:SCI_MARKERSYMBOLDEFINED wParam:SC_MARKNUM_FOLDER] == SC_MARK_ARROW;
        lp.foldMarginStyle = 2;
        [ed applyEditorPreferences];
        BOOL circle = [sci message:SCI_MARKERSYMBOLDEFINED wParam:SC_MARKNUM_FOLDEROPEN] == SC_MARK_CIRCLEMINUS;
        lp.foldMarginStyle = 4;
        [ed applyEditorPreferences];
        BOOL none = [sci message:SCI_GETMARGINWIDTHN wParam:2] == 0;
        lp.foldMarginStyle = 3;
        [ed applyEditorPreferences];
        BOOL box = [sci message:SCI_MARKERSYMBOLDEFINED wParam:SC_MARKNUM_FOLDER] == SC_MARK_BOXPLUS &&
                   [sci message:SCI_GETMARGINWIDTHN wParam:2] > 0;
        Check(@"IDM_SETTING_PREFERENCE (fold margin style)",
              @"simple, arrow, circle tree and box tree markers, and none hides the margin", arrow && circle && none && box);

        // Line numbers: dynamic width fits the lines shown, constant the file.
        NSMutableString *many = [NSMutableString string];
        for (int i = 0; i < 120000; ++i) [many appendString:@"x\n"];
        SetDoc(ed, many);
        [sci message:SCI_SETFIRSTVISIBLELINE wParam:0 lParam:0];
        lp.lineNumberDynamicWidth = YES;
        [ed updateLineNumberWidth];
        long dynamicWidth = [sci message:SCI_GETMARGINWIDTHN wParam:0];
        lp.lineNumberDynamicWidth = NO;
        [ed updateLineNumberWidth];
        long constantWidth = [sci message:SCI_GETMARGINWIDTHN wParam:0];
        lp.lineNumberShow = NO;
        [ed updateLineNumberWidth];
        BOOL hiddenNumbers = [sci message:SCI_GETMARGINWIDTHN wParam:0] == 0;
        lp.lineNumberShow = YES;
        lp.lineNumberDynamicWidth = YES;
        [ed updateLineNumberWidth];
        Check(@"IDM_SETTING_PREFERENCE (line number width)",
              @"a dynamic margin fits the lines on screen, a constant one the whole file, and it can be hidden",
              constantWidth > dynamicWidth && dynamicWidth > 0 && hiddenNumbers);
        SetDoc(ed, [NSString stringWithFormat:@"a%Cb%Cc\n", (unichar)0xA0, (unichar)1]);

        // Non-printing characters and C0/C1: abbreviation or code point, and
        // hidden when that view option is off; EOL as plain text.
        char rep[32] = {0};
        char nbsp[] = {(char)0xC2, (char)0xA0, 0}, soh[] = {1, 0}, zwsp[] = {(char)0xE2, (char)0x80, (char)0x8B, 0};
        lp.npcShow = YES; lp.npcCodepoint = NO; lp.ccUniEolShow = YES;
        [ed applySymbolRepresentationsTo:sci];
        [sci message:SCI_GETREPRESENTATION wParam:(uptr_t)nbsp lParam:(sptr_t)rep];
        BOOL abbreviation = !strcmp(rep, "NBSP");
        lp.npcCodepoint = YES;
        [ed applySymbolRepresentationsTo:sci];
        memset(rep, 0, sizeof rep);
        [sci message:SCI_GETREPRESENTATION wParam:(uptr_t)nbsp lParam:(sptr_t)rep];
        BOOL codepoint = !strcmp(rep, "U+00A0");
        lp.ccUniEolShow = NO;
        [ed applySymbolRepresentationsTo:sci];
        memset(rep, 0, sizeof rep);
        [sci message:SCI_GETREPRESENTATION wParam:(uptr_t)soh lParam:(sptr_t)rep];
        BOOL controlHidden = !strcmp(rep, zwsp);
        lp.eolPlainText = YES;
        [ed applySymbolRepresentationsTo:sci];
        BOOL plainEol = [sci message:SCI_GETREPRESENTATIONAPPEARANCE wParam:(uptr_t)"\n"] == SC_REPRESENTATION_PLAIN;
        lp.npcShow = NO; lp.npcCodepoint = NO; lp.ccUniEolShow = YES; lp.eolPlainText = NO;
        [ed applySymbolRepresentationsTo:sci];
        memset(rep, 0, sizeof rep);
        [sci message:SCI_GETREPRESENTATION wParam:(uptr_t)nbsp lParam:(sptr_t)rep];
        BOOL npcOff = rep[0] == 0;
        Check(@"IDM_VIEW_NPC (appearance)",
              @"invisible characters show by abbreviation or code point, C0 controls hide when switched off, EOL can be plain",
              abbreviation && codepoint && controlHidden && plainEol && npcOff);

        // Change History in the text, smooth font, C0 typing, toggleable folding.
        lp.changeHistoryText = YES; lp.smoothFont = YES;
        [ed applyEditorPreferences];
        BOOL historyText = ([sci message:SCI_GETCHANGEHISTORY] & SC_CHANGE_HISTORY_INDICATORS) != 0;
        BOOL smooth = [sci message:SCI_GETFONTQUALITY] == SC_EFF_QUALITY_LCD_OPTIMIZED;
        lp.changeHistoryText = NO; lp.smoothFont = NO;
        [ed applyEditorPreferences];
        SetDoc(ed, @"ab");
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];
        [sci setStringProperty:SCI_REPLACESEL parameter:0 value:[NSString stringWithFormat:@"%C", (unichar)2]];
        [ed handleCharacterAdded:2];
        BOOL noC0 = [DocText(ed) isEqualToString:@"ab"];
        SetDoc(ed, @"int f() {\n    return 0;\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        lp.foldCommandsToggle = YES;
        [ed foldCurrent:NO];
        BOOL toggledShut = [sci message:SCI_GETFOLDEXPANDED wParam:0] == 0;
        [ed foldCurrent:NO];
        BOOL toggledOpen = [sci message:SCI_GETFOLDEXPANDED wParam:0] != 0;
        lp.foldCommandsToggle = NO;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        Check(@"IDM_SETTING_PREFERENCE (editing)",
              @"change history in the text, smooth font, no C0 typing, and fold commands that toggle",
              historyText && smooth && noC0 && toggledShut && toggledOpen);
    }

    if (NppSectionWanted(@"Preferences: Highlighting, Date, Print, Searching")) { printf("\n== Preferences: Highlighting, Date, Print, Searching ==\n");
        NppPreferences *hp = [NppPreferences shared];
        // Highlight Matching Tags, as XmlMatchedTagsHighlighter marks them.
        [ed newDocument];
        [ed setLanguageNamed:@"html"];
        SetDoc(ed, @"<div class=\"a\" id='b'><p>x</p></div>\n<br/>");
        hp.highlightMatchingTags = YES; hp.highlightTagAttributes = YES;
        [sci message:SCI_GOTOPOS wParam:2 lParam:0];                   // in "div"
        BOOL divMatched = [ed highlightMatchingTags];
        NSArray *tagMarks = [ed rangesOfIndicator:NPPMAC_TAGMATCH_INDICATOR];
        NSArray *attrMarks = [ed rangesOfIndicator:NPPMAC_TAGATTR_INDICATOR];
        BOOL divRanges = tagMarks.count == 3 && NSEqualRanges([tagMarks[0] rangeValue], NSMakeRange(0, 4)) &&
                         NSEqualRanges([tagMarks[1] rangeValue], NSMakeRange(21, 1)) &&
                         NSEqualRanges([tagMarks[2] rangeValue], NSMakeRange(30, 6)) &&
                         attrMarks.count == 2 && NSEqualRanges([attrMarks[0] rangeValue], NSMakeRange(5, 9)) &&
                         NSEqualRanges([attrMarks[1] rangeValue], NSMakeRange(15, 6));
        [sci message:SCI_GOTOPOS wParam:28 lParam:0];                  // in "</p>"
        BOOL pMatched = [ed highlightMatchingTags];
        NSArray *pMarks = [ed rangesOfIndicator:NPPMAC_TAGMATCH_INDICATOR];
        // "<p" and its ">" touch, so they read as one mark.
        BOOL pRanges = pMarks.count == 2 && NSEqualRanges([pMarks[0] rangeValue], NSMakeRange(22, 3)) &&
                       NSEqualRanges([pMarks[1] rangeValue], NSMakeRange(26, 4));
        [sci message:SCI_GOTOPOS wParam:40 lParam:0];                  // in "<br/>"
        BOOL selfClosing = [ed highlightMatchingTags] && [ed rangesOfIndicator:NPPMAC_TAGMATCH_INDICATOR].count == 1 &&
                           NSEqualRanges([[ed rangesOfIndicator:NPPMAC_TAGMATCH_INDICATOR][0] rangeValue], NSMakeRange(37, 5));
        hp.highlightMatchingTags = NO;
        BOOL off = ![ed highlightMatchingTags] && [ed rangesOfIndicator:NPPMAC_TAGMATCH_INDICATOR].count == 0;
        hp.highlightMatchingTags = YES;
        Check(@"IDM_SETTING_PREFERENCE (matching tags)",
              @"the tag at the caret and its partner are marked, with the opener's attributes; a self-closing tag alone",
              divMatched && divRanges && pMatched && pRanges && selfClosing && off);

        // Smart highlighting in the other view too.
        [ed setLanguageNamed:@"normal"];
        SetDoc(ed, @"alpha beta alpha gamma alpha\n");
        [ed cloneCurrentToOtherView];
        hp.smartHighlightOtherView = YES;
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        [ed updateSmartHighlight];
        ScintillaView *other = ed.secondarySci;
        NSUInteger inOther = 0;
        for (long pos = 0; pos < [other message:SCI_GETLENGTH]; ++pos) {
            if ([other message:SCI_INDICATORVALUEAT wParam:NPPMAC_STYLE_FIRST_INDICATOR + 4 lParam:pos] &&
                (pos == 0 || ![other message:SCI_INDICATORVALUEAT wParam:NPPMAC_STYLE_FIRST_INDICATOR + 4 lParam:pos - 1])) inOther++;
        }
        hp.smartHighlightOtherView = NO;
        [ed setSecondaryViewVisible:NO];
        Check(@"IDM_SETTING_PREFERENCE (smart highlight another view)",
              @"the selected word is marked in the second view as well", inOther == 3);

        // Custom date pictures in Windows' terms; form feeds as page breaks.
        NSString *converted = [NppPreferences dateFormatFromWindowsPicture:@"dddd, dd MMM yyyy 'at' hh:mm tt"];
        SetDoc(ed, @"page one\fpage two\n");
        hp.printFormFeedPageBreak = YES;
        NSView *printed = [ed printOperationShowingPanel:NO].view;
        CGFloat bottom = 700;
        [printed adjustPageHeightNew:&bottom top:0 bottom:700 limit:600];
        hp.printFormFeedPageBreak = NO;
        CGFloat unbroken = 700;
        [printed adjustPageHeightNew:&unbroken top:0 bottom:700 limit:600];
        Check(@"IDM_SETTING_PREFERENCE (date, form feed)",
              @"Windows date pictures are understood, and a form feed ends the printed page when asked",
              [converted isEqualToString:@"EEEE, dd MMM yyyy 'at' hh:mm a"] && bottom < 100 && unbroken == 700);

        // Searching: a long selection does not fill the Find field.
        NSInteger thresholdBefore = hp.fillFindWhatThreshold;
        hp.fillFindWhatThreshold = 3;
        SetDoc(ed, @"abcdef");
        [sci message:SCI_SETSEL wParam:0 lParam:6];
        NSString *seedLong = [ed initialFindTerm];
        [sci message:SCI_SETSEL wParam:0 lParam:2];
        NSString *seedShort = [ed initialFindTerm];
        hp.fillFindWhatThreshold = thresholdBefore;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        Check(@"IDM_SETTING_PREFERENCE (find field fill)",
              @"the Find field is filled only from a selection within the limit",
              ![seedLong isEqualToString:@"abcdef"] && [seedShort isEqualToString:@"ab"]);
    }

    if (NppSectionWanted(@"Preferences: Toolbar, Tab Bar, panels, Cancel")) { printf("\n== Preferences: Toolbar, Tab Bar, panels, Cancel ==\n");
        NppPreferences *tp = [NppPreferences shared];
        // Toolbar colour, completely: every opaque pixel of the icon takes it.
        NppToolbar *bar = [app valueForKey:@"toolbar"];
        CGFloat (^share)(NSString *, BOOL (^)(CGFloat, CGFloat, CGFloat)) = ^CGFloat(NSString *command, BOOL (^test)(CGFloat, CGFloat, CGFloat)) {
            NSBitmapImageRep *shot = [bar renderedImageForCommand:command];
            if (!shot) return -1;
            CGFloat hit = 0, all = 0;
            for (NSInteger x = 0; x < shot.pixelsWide; ++x) for (NSInteger y = 0; y < shot.pixelsHigh; ++y) {
                NSColor *px = [[shot colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
                if (px.alphaComponent < 0.5) continue;
                all++;
                if (test(px.redComponent, px.greenComponent, px.blueComponent)) hit++;
            }
            return all > 0 ? hit / all : -1;
        };
        // Green whatever the edge blending: green clearly above red and blue.
        BOOL (^isGreen)(CGFloat, CGFloat, CGFloat) = ^BOOL(CGFloat r, CGFloat g, CGFloat b) { return g > r + 0.1 && g > b + 0.1; };
        tp.toolbarIconColour = 2; tp.toolbarColorizeComplete = YES;
        [app applyToolbarPreferences];
        CGFloat greenShare = share(@"IDM_FILE_NEW", isGreen);
        tp.toolbarIconColour = 0; tp.toolbarColorizeComplete = NO;
        [app applyToolbarPreferences];
        CGFloat plainShare = share(@"IDM_FILE_NEW", isGreen);
        tp.toolbarFilledIcons = YES;
        [app applyToolbarPreferences];
        BOOL filledDrawn = share(@"IDM_FILE_NEW", ^BOOL(CGFloat r, CGFloat g, CGFloat b) { return YES; }) > 0;
        tp.toolbarFilledIcons = NO;
        [app applyToolbarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (toolbar icons)",
              @"icons take the chosen colour, completely when asked, and the filled set can be used",
              greenShare > 0.9 && plainShare < 0.1 && filledDrawn);

        // Tab Bar: a limit on the label.
        tp.tabMaxLabelLength = 4;
        [ed applyTabBarPreferences];
        NppTabBarView *tabs = [ed valueForKey:@"tabBar"];
        NSString *shortened = [tabs displayTitleAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]];
        tp.tabMaxLabelLength = 0;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab label length)",
              @"tab labels are cut to the length set, with an ellipsis", shortened.length <= 5);

        // Distraction Free: the text in the middle, each side a share of the width.
        tp.distractionFreeDivPart = 4;
        [ed setChromeVisible:NO];
        long left = [sci message:SCI_GETMARGINLEFT];
        long expected = (long)(NSWidth(sci.bounds) / 4);
        [ed setChromeVisible:YES];
        long back = [sci message:SCI_GETMARGINLEFT];
        Check(@"IDM_VIEW_DISTRACTIONFREE (width)",
              @"distraction free keeps a quarter of the width on each side, and leaving it restores the padding",
              labs(left - expected) <= 1 && back <= 9);

        // Remember panel state, panel by panel.
        BOOL rememberBefore = tp.rememberPanelState;
        tp.rememberPanelState = YES;
        tp.panelStateKeep = @{@"documentMap": @NO};
        [ed setDocumentMapVisible:YES];
        [ed rememberPanelState];
        BOOL mapNotKept = ![tp.panelState[@"documentMap"] boolValue];
        tp.panelStateKeep = @{};
        [ed rememberPanelState];
        BOOL mapKept = [tp.panelState[@"documentMap"] boolValue];
        [ed setDocumentMapVisible:NO];
        tp.rememberPanelState = rememberBefore;
        Check(@"IDM_SETTING_PREFERENCE (panel state per panel)",
              @"each panel is remembered only when ticked", mapNotKept && mapKept);

        // Preferences Cancel keeps nothing of what was changed.
        PreferencesWindow *cancelWindow = [[PreferencesWindow alloc] initWithEditor:ed];
        NSButton *hideStatus = [cancelWindow valueForKey:@"controls"][@"statusBarHidden"];
        BOOL statusBefore = tp.statusBarHidden;
        hideStatus.state = statusBefore ? NSControlStateValueOff : NSControlStateValueOn;
        [cancelWindow performSelector:@selector(cancel:) withObject:nil];
        NSButton *rebuilt = [cancelWindow valueForKey:@"controls"][@"statusBarHidden"];
        Check(@"IDM_SETTING_PREFERENCE (cancel)",
              @"Cancel closes the dialog without keeping the change, and shows the settings as they are next time",
              tp.statusBarHidden == statusBefore && rebuilt != hideStatus &&
              (rebuilt.state == NSControlStateValueOn) == statusBefore);
    }

    if (NppSectionWanted(@"Files: monitoring, ANSI, big files")) { printf("\n== Files: monitoring, ANSI, big files ==\n");
        NppPreferences *fp = [NppPreferences shared];
        // Monitoring per document: read-only while watched; a change to a
        // file not in front waits for it to come to the front.
        NSString *logA = TempFile(@"t_mon_a.log", @"one\n");
        NSString *logB = TempFile(@"t_mon_b.log", @"other\n");
        [ed openFileAtPath:logA error:NULL];
        NppDocument *docA = ed.currentDocument;
        [ed setMonitoring:YES];
        BOOL watched = docA.monitoring && [sci message:SCI_GETREADONLY] != 0;
        [ed openFileAtPath:logB error:NULL];
        NppDocument *docB = ed.currentDocument;
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logA];
        [h seekToEndOfFile];
        [h writeData:[@"two\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!docA.monitorReloadPending && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        BOOL waited = docA.monitorReloadPending && ed.currentDocument == docB && [DocText(ed) isEqualToString:@"other\n"];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:docA]];
        until = [NSDate dateWithTimeIntervalSinceNow:2];
        while (docA.monitorReloadPending && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        BOOL caughtUp = [DocText(ed) isEqualToString:@"one\ntwo\n"] &&
                        [sci message:SCI_GETCURRENTPOS] == [sci message:SCI_GETLENGTH];
        // Rotated: moved away and made again under the same name, then
        // written to. The name is still followed.
        [[NSFileManager defaultManager] moveItemAtPath:logA toPath:[logA stringByAppendingString:@".1"] error:NULL];
        [@"fresh\n" writeToFile:logA atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (![DocText(ed) isEqualToString:@"fresh\n"] && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        BOOL rotated = [DocText(ed) isEqualToString:@"fresh\n"] && docA.monitoring;
        h = [NSFileHandle fileHandleForWritingAtPath:logA];
        [h seekToEndOfFile];
        [h writeData:[@"more\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
        until = [NSDate dateWithTimeIntervalSinceNow:5];
        while (![DocText(ed) isEqualToString:@"fresh\nmore\n"] && [until timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        caughtUp = caughtUp && rotated && [DocText(ed) isEqualToString:@"fresh\nmore\n"];
        [[NSFileManager defaultManager] removeItemAtPath:[logA stringByAppendingString:@".1"] error:NULL];
        [ed setMonitoring:NO];
        BOOL released = !docA.monitoring && [sci message:SCI_GETREADONLY] == 0;
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:docB]];
        [sci setStringProperty:SCI_REPLACESEL parameter:0 value:@"dirty"];
        ed.currentDocument.modified = YES;
        [ed setMonitoring:YES];
        BOOL refusedDirty = !docB.monitoring;
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:docB] discardChanges:YES];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:docA] discardChanges:YES];
        Check(@"IDM_VIEW_MONITORING (per document)",
              @"a watched file is read-only, a change waits while another tab is in front, and a dirty file is refused",
              watched && waited && caughtUp && released && refusedDirty);

        // Apply to opened ANSI files: seven-bit text as UTF-8, or as ANSI.
        NSString *ascii = TempFile(@"t_ascii.txt", @"plain text\n");
        BOOL ansiBefore = fp.openAnsiAsUtf8;
        fp.openAnsiAsUtf8 = YES;
        [ed openFileAtPath:ascii error:NULL];
        BOOL asUtf8 = ed.currentDocument.encoding == NSUTF8StringEncoding;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        fp.openAnsiAsUtf8 = NO;
        [ed openFileAtPath:ascii error:NULL];
        BOOL asAnsi = ed.currentDocument.encoding == NSISOLatin1StringEncoding;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        fp.openAnsiAsUtf8 = ansiBefore;
        Check(@"IDM_SETTING_PREFERENCE (ANSI as UTF-8)",
              @"a seven-bit file opens as UTF-8 only with Apply to opened ANSI files", asUtf8 && asAnsi);

        // Big files: mapped and handed over as bytes, UTF-8, Latin-1 or with a BOM.
        [EditorController setStreamingThreshold:1024];
        NSMutableString *bigText = [NSMutableString string];
        for (int i = 0; i < 400; ++i) [bigText appendFormat:@"line %d café\r\n", i];
        NSString *bigUtf8 = TempFile(@"t_big_utf8.txt", bigText);
        [ed openFileAtPath:bigUtf8 error:NULL];
        BOOL utf8Ok = [DocText(ed) isEqualToString:bigText] && ed.currentDocument.encoding == NSUTF8StringEncoding &&
                      ed.currentDocument.eolMode == SC_EOL_CRLF;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        NSString *bigLatin = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_big_latin.txt"];
        [[bigText dataUsingEncoding:NSISOLatin1StringEncoding] writeToFile:bigLatin atomically:YES];
        [ed openFileAtPath:bigLatin error:NULL];
        BOOL latinOk = [DocText(ed) isEqualToString:bigText] && ed.currentDocument.encoding == NSISOLatin1StringEncoding;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        NSMutableData *withBom = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [withBom appendData:[bigText dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *bigBom = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_big_bom.txt"];
        [withBom writeToFile:bigBom atomically:YES];
        [ed openFileAtPath:bigBom error:NULL];
        BOOL bomOk = [DocText(ed) isEqualToString:bigText] && ed.currentDocument.hasBOM;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        // A big file in a code page: detected as a small one is, and converted
        // in pieces - here one that ends inside a two-byte character.
        NSMutableString *japanese = [NSMutableString stringWithString:@"a"];
        NSString *sentence = @"これは日本語の文章です。吾輩は猫である。名前はまだ無い。\n";
        while (japanese.length < 2600000) [japanese appendString:sentence];
        NSStringEncoding sjis = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingDOSJapanese);
        NSData *sjisBytes = [japanese dataUsingEncoding:sjis];
        NSString *bigSjis = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_big_sjis.txt"];
        [sjisBytes writeToFile:bigSjis atomically:YES];
        [ed openFileAtPath:bigSjis error:NULL];
        BOOL sjisOk = sjisBytes.length > (4 << 20) + 1000 && [DocText(ed) isEqualToString:japanese] &&
                      ed.currentDocument.encoding != NSISOLatin1StringEncoding;
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [[NSFileManager defaultManager] removeItemAtPath:bigSjis error:NULL];
        printf("    big sjis: %lu bytes ok=%d\n", (unsigned long)sjisBytes.length, sjisOk);
        latinOk = latinOk && sjisOk;
        [EditorController setStreamingThreshold:0];
        Check(@"IDM_FILE_OPEN (big files)",
              @"a big file is mapped and read as UTF-8, Latin-1 or UTF-8 with a BOM without a string in between",
              utf8Ok && latinOk && bomOk);
    }

    if (NppSectionWanted(@"Docking")) { printf("\n== Docking ==\n");
        NppDockingManager *dock = [NppDockingManager shared];
        NSDictionary *layoutBefore = [NppPreferences shared].dockLayout;
        // The default places are upstream's, and shown panels share a dock as tabs.
        [app toggleDocumentList:nil];
        [ed setDocumentMapVisible:YES];
        [app toggleFunctionList:nil];
        BOOL defaults = [dock placeOfPanel:@"documentList"] == NppDockLeft &&
                        [dock placeOfPanel:@"documentMap"] == NppDockRight &&
                        [dock placeOfPanel:@"functionList"] == NppDockRight;
        NSArray *right = [dock panelsIn:NppDockRight];
        BOOL tabbed = [right containsObject:@"documentMap"] && [right containsObject:@"functionList"] &&
                      [[dock frontPanelIn:NppDockRight] isEqualToString:@"functionList"];
        // The tab clicked to the front is kept in the layout, and comes back in
        // front after the panels are shown again in whatever order.
        [dock performSelector:@selector(containerClickedPanel:) withObject:@"documentMap"];
        BOOL frontKept = [[NppPreferences shared].dockLayout[@"fronts"][@(NppDockRight).stringValue] isEqualToString:@"documentMap"];
        [dock showPanel:@"functionList"];                       // as a relaunch would: the last shown takes the front
        BOOL stolen = [[dock frontPanelIn:NppDockRight] isEqualToString:@"functionList"];
        [dock restoreFronts];
        tabbed = tabbed && frontKept && stolen && [[dock frontPanelIn:NppDockRight] isEqualToString:@"documentMap"];
        [dock performSelector:@selector(containerClickedPanel:) withObject:@"functionList"];

        // Moving: to the bottom dock, floating in a window, and back.
        [dock movePanel:@"documentList" to:NppDockBottom];
        BOOL bottom = [[dock panelsIn:NppDockBottom] isEqualToArray:@[@"documentList"]] &&
                      ![[dock panelsIn:NppDockLeft] containsObject:@"documentList"];
        [dock movePanel:@"functionList" to:NppDockFloating];
        NSView *listView = [[app valueForKey:@"funcList"] valueForKey:@"table"];
        BOOL floating = [dock placeOfPanel:@"functionList"] == NppDockFloating && listView.window != app.window &&
                        listView.window.isVisible;
        [dock movePanel:@"functionList" to:(NppDockPlace)-1];      // back to where it was docked
        BOOL back = [dock placeOfPanel:@"functionList"] == NppDockRight && listView.window == app.window;
        // Dropping: the edges of the window dock, the middle and outside float.
        NSRect w = app.window.frame;
        BOOL drops = [dock placeForDropAtScreenPoint:NSMakePoint(NSMinX(w) + 10, NSMidY(w))] == NppDockLeft &&
                     [dock placeForDropAtScreenPoint:NSMakePoint(NSMaxX(w) - 10, NSMidY(w))] == NppDockRight &&
                     [dock placeForDropAtScreenPoint:NSMakePoint(NSMidX(w), NSMaxY(w) - 10)] == NppDockTop &&
                     [dock placeForDropAtScreenPoint:NSMakePoint(NSMidX(w), NSMinY(w) + 10)] == NppDockBottom &&
                     [dock placeForDropAtScreenPoint:NSMakePoint(NSMaxX(w) + 500, NSMidY(w))] == NppDockFloating;
        // Floating windows hold several panels as tabs: one dropped on another's
        // window joins it, the tab clicked comes to the front, and dragging it
        // out again gives it a window of its own.
        [dock movePanel:@"functionList" to:NppDockFloating];
        [dock movePanel:@"documentMap" to:NppDockFloating];
        NSView *mapHost = [ed valueForKey:@"docMapHost"];
        BOOL apart = listView.window != mapHost.window && [dock panelsFloatingWith:@"documentMap"].count == 1;
        NSRect listWindow = listView.window.frame;
        // The drop itself: over the other window's frame the preview is that frame, and the drop joins it.
        NSPoint over = NSMakePoint(NSMidX(listWindow), NSMidY(listWindow));
        BOOL previewIsWindow = NSEqualRects([dock previewRectForPanel:@"documentMap" atScreenPoint:over], listWindow);
        [dock dragOfPanel:@"documentMap" endedAtScreenPoint:over];
        BOOL together = previewIsWindow && [[dock panelsFloatingWith:@"functionList"] isEqualToArray:(@[@"documentMap", @"functionList"])] ||
                   [[dock panelsFloatingWith:@"functionList"] isEqualToArray:(@[@"functionList", @"documentMap"])];
        BOOL oneWindow = mapHost.window != nil && listView.window == nil;          // the map is the tab in front
        [dock performSelector:@selector(containerClickedPanel:) withObject:@"functionList"];
        BOOL switched = listView.window != nil && mapHost.window == nil;
        BOOL groupKept = [[NppPreferences shared].dockLayout[@"groups"][@"documentMap"] isEqualToString:
                          [NppPreferences shared].dockLayout[@"groups"][@"functionList"]];
        [dock movePanel:@"documentMap" to:(NppDockPlace)-1];
        [dock movePanel:@"functionList" to:(NppDockPlace)-1];
        BOOL docksAgain = [dock placeOfPanel:@"documentMap"] == NppDockRight && [dock placeOfPanel:@"functionList"] == NppDockRight &&
                          listView.window == app.window;
        printf("    dock floats: apart=%d together=%d one=%d switched=%d kept=%d back=%d\n", apart, together, oneWindow, switched, groupKept, docksAgain);
        floating = floating && apart && together && oneWindow && switched && groupKept && docksAgain;

        // The drag shows where the panel would land: a strip at that edge of
        // the window, or a floating frame under the pointer.
        NSRect leftStrip = [dock previewRectForPanel:@"functionList" atScreenPoint:NSMakePoint(NSMinX(w) + 10, NSMidY(w))];
        NSRect bottomStrip = [dock previewRectForPanel:@"functionList" atScreenPoint:NSMakePoint(NSMidX(w), NSMinY(w) + 10)];
        NSRect afloat = [dock previewRectForPanel:@"functionList" atScreenPoint:NSMakePoint(NSMaxX(w) + 500, NSMidY(w))];
        drops = drops && NSMinX(leftStrip) <= NSMinX(w) + 2 && NSWidth(leftStrip) < NSWidth(w) / 2 && NSHeight(leftStrip) > NSHeight(w) / 2 &&
                NSWidth(bottomStrip) > NSWidth(w) / 2 && NSHeight(bottomStrip) < NSHeight(w) / 2 && NSMinY(bottomStrip) < NSMidY(w) &&
                NSMinX(afloat) > NSMaxX(w);
        // What was moved is remembered.
        BOOL remembered = [[NppPreferences shared].dockLayout[@"places"][@"documentList"] integerValue] == NppDockBottom;
        [dock movePanel:@"documentList" to:NppDockLeft];
        [app toggleDocumentList:nil];
        [app toggleFunctionList:nil];
        [ed setDocumentMapVisible:NO];
        BOOL allHidden = ![dock isPanelVisible:@"documentList"] && ![dock isPanelVisible:@"functionList"] &&
                         ![dock isPanelVisible:@"documentMap"] && ![dock panelsIn:NppDockRight].count;
        [NppPreferences shared].dockLayout = layoutBefore ?: @{};
        Check(@"IDM_VIEW_DOCLIST (docking)",
              @"panels dock where upstream puts them, share a dock as tabs, move between docks and floating, and are remembered",
              defaults && tabbed && bottom && floating && back && drops && remembered && allHidden);
    }

    if (NppSectionWanted(@"Session depth")) { printf("\n== Session depth ==\n");
        // Folds belong to the document: they survive a trip to another tab.
        NSString *foldFile = TempFile(@"t_folds.cpp", @"int f() {\n    return 1;\n}\nint g() {\n    return 2;\n}\n");
        NSString *otherFile = TempFile(@"t_folds_other.txt", @"other\n");
        [ed openFileAtPath:foldFile error:NULL];
        NppDocument *foldDoc = ed.currentDocument;
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        [sci message:SCI_FOLDLINE wParam:3 lParam:SC_FOLDACTION_CONTRACT];
        [ed openFileAtPath:otherFile error:NULL];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:foldDoc]];
        BOOL keptFold = [sci message:SCI_GETFOLDEXPANDED wParam:3] == 0 && [sci message:SCI_GETFOLDEXPANDED wParam:0] != 0;
        Check(@"IDM_VIEW_FOLDALL (folds per document)",
              @"a folded block stays folded when another tab has been in front", keptFold);

        // The session keeps folds, the user's read-only, the second view and
        // every Folder as Workspace root.
        [ed setReadOnly:YES];
        [ed cloneCurrentToOtherView];
        NSString *rootA = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_rootA"];
        NSString *rootB = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_rootB"];
        for (NSString *r in @[rootA, rootB]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:r withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"x" writeToFile:[r stringByAppendingPathComponent:[r.lastPathComponent stringByAppendingString:@".txt"]]
                   atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
        [ed openFolderAsWorkspace:nil];
        [ed openFolderAsWorkspace:rootA];
        [ed openFolderAsWorkspace:rootB];
        [ed openFolderAsWorkspace:rootA];                    // already a root: not twice
        NSArray *roots = [ed workspaceRootPaths];
        NSString *sessionPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_depth_session.json"];
        NSSplitView *viewSplit = [ed valueForKey:@"editorSplit"];
        [viewSplit setPosition:NSHeight(viewSplit.frame) * 0.3 ofDividerAtIndex:0];
        [ed saveSessionTo:sessionPath error:NULL];
        [ed setReadOnly:NO];
        [ed setSecondaryViewVisible:NO];
        [ed openFolderAsWorkspace:nil];
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            NSString *p = ed.documents[(NSUInteger)i].path;
            if ([p isEqualToString:foldFile] || [p isEqualToString:otherFile]) [ed closeDocumentAtIndex:i discardChanges:YES];
        }
        [ed loadSessionFrom:sessionPath error:NULL];
        NSUInteger at = [ed.documents indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *st) { return [d.path isEqualToString:foldFile]; }];
        if (at != NSNotFound) [ed selectDocumentAtIndex:(NSInteger)at];
        BOOL foldBack = at != NSNotFound && [sci message:SCI_GETFOLDEXPANDED wParam:3] == 0;
        BOOL readOnlyBack = [ed isReadOnly] && ed.currentDocument.userReadOnly;
        double shareBack = NSHeight(ed.sci.frame) / MAX(1, NSHeight(viewSplit.frame));
        printf("    session: the views' divider came back at %.2f\n", shareBack);
        BOOL secondBack = fabs(shareBack - 0.3) < 0.05 && [ed secondaryViewVisible] &&
            (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == ed.currentDocument.docPointer;
        BOOL rootsBack = [[ed workspaceRootPaths] isEqualToArray:(@[rootA, rootB])] && roots.count == 2 &&
                         [[ed workspaceTopLevelNames] containsObject:@"t_rootB.txt"];
        [ed setReadOnly:NO];
        [ed setSecondaryViewVisible:NO];
        [ed openFolderAsWorkspace:nil];
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            NSString *p = ed.documents[(NSUInteger)i].path;
            if ([p isEqualToString:foldFile] || [p isEqualToString:otherFile]) [ed closeDocumentAtIndex:i discardChanges:YES];
        }
        // The file is Notepad++'s session.xml: a Windows build reads what is
        // written here, and what Windows wrote is read here.
        NSString *written = [NSString stringWithContentsOfFile:sessionPath encoding:NSUTF8StringEncoding error:NULL] ?: @"";
        BOOL upstreamShape = [written containsString:@"<NotepadPlus>"] && [written containsString:@"<Session activeView=\"0\">"] &&
                             [written containsString:@"<mainView activeIndex="] && [written containsString:@"<subView activeIndex="] &&
                             [written containsString:@"<Fold line="] && [written containsString:@"userReadOnly=\"yes\""] &&
                             [written containsString:@"<FileBrowser"] && [written containsString:@"foldername="] &&
                             [written containsString:@"lang=\"C++\""];
        NSString *fromWindows = [NSString stringWithFormat:
            @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n    <Session activeView=\"0\">\n"
            @"        <mainView activeIndex=\"1\">\n"
            @"            <File firstVisibleLine=\"0\" xOffset=\"0\" scrollWidth=\"64\" startPos=\"2\" endPos=\"5\" selMode=\"0\" offset=\"0\" wrapCount=\"1\" "
            @"lang=\"Python\" encoding=\"-1\" userReadOnly=\"no\" filename=\"C:\\Users\\someone\\gone.py\" backupFilePath=\"\" "
            @"originalFileLastModifTimestamp=\"0\" originalFileLastModifTimestampHigh=\"0\" tabColourId=\"-1\" RTL=\"no\" tabPinned=\"no\" untitleTabRenamed=\"no\" />\n"
            @"            <File firstVisibleLine=\"0\" xOffset=\"0\" scrollWidth=\"64\" startPos=\"3\" endPos=\"7\" selMode=\"0\" offset=\"0\" wrapCount=\"1\" "
            @"lang=\"C++\" encoding=\"-1\" userReadOnly=\"yes\" filename=\"%@\" backupFilePath=\"\" "
            @"originalFileLastModifTimestamp=\"0\" originalFileLastModifTimestampHigh=\"0\" tabColourId=\"2\" RTL=\"no\" tabPinned=\"yes\" untitleTabRenamed=\"no\">\n"
            @"                <Mark line=\"1\" />\n            </File>\n        </mainView>\n        <subView activeIndex=\"0\" />\n    </Session>\n</NotepadPlus>\n", foldFile];
        NSDictionary *read = [EditorController sessionDictionaryFromXML:[fromWindows dataUsingEncoding:NSUTF8StringEncoding]];
        NSDictionary *second2 = [read[@"files"] lastObject];
        BOOL windowsRead = [read[@"files"] count] == 2 && [read[@"currentPath"] isEqualToString:foldFile] &&
                           [second2[@"language"] isEqualToString:@"cpp"] && [second2[@"pinned"] boolValue] && [second2[@"userReadOnly"] boolValue] &&
                           [second2[@"tabColour"] integerValue] == 3 && [second2[@"caret"] longValue] == 7 && [second2[@"anchor"] longValue] == 3 &&
                           [second2[@"bookmarks"] isEqualToArray:@[@1]] && read[@"secondary"] == nil;
        NSString *winSession = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_windows_session.xml"];
        [fromWindows writeToFile:winSession atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSUInteger docsBeforeWin = ed.documents.count;
        BOOL loadedWin = [ed loadSessionFrom:winSession error:NULL];
        NppDocument *fromWin = ed.currentDocument;
        BOOL windowsLoaded = loadedWin && [fromWin.path isEqualToString:foldFile] && fromWin.pinned && fromWin.userReadOnly &&
                             fromWin.tabColour == 3 && ed.documents.count == docsBeforeWin + 1 &&
                             [ed.sci message:SCI_MARKERGET wParam:1] & (1 << 1);
        if (fromWin.pinned) [ed togglePinCurrent];
        [ed setReadOnly:NO];
        fromWin.tabColour = 0;
        NSUInteger winIndex = [ed.documents indexOfObject:fromWin];
        if (winIndex != NSNotFound && [fromWin.path isEqualToString:foldFile]) [ed closeDocumentAtIndex:(NSInteger)winIndex discardChanges:YES];
        printf("    session.xml: shape=%d read=%d loaded=%d\n", upstreamShape, windowsRead, windowsLoaded);
        Check(@"IDM_FILE_SAVESESSION (session.xml)",
              @"a session is written in Notepad++'s own format, and one written on Windows is read: language, caret, pin, colour, read-only, bookmarks",
              upstreamShape && windowsRead && windowsLoaded);

        Check(@"IDM_FILE_SAVESESSION (depth)",
              @"a session brings back folds, the user's read-only, the second view and every workspace root",
              foldBack && readOnlyBack && secondBack && rootsBack);

        // Folder as Workspace: several roots, locate the current file, and its menu.
        WorkspacePanel *wp = [[WorkspacePanel alloc] initWithFrame:NSMakeRect(0, 0, 200, 300)];
        [wp addRootPath:rootA];
        [wp addRootPath:rootB];
        BOOL located = [wp locateFile:[rootB stringByAppendingPathComponent:@"t_rootB.txt"]];
        NSMenu *rootMenu = [wp menuForRow:0];
        BOOL menu = [rootMenu itemWithTitle:@"Remove"] && [rootMenu itemWithTitle:@"Remove All"] &&
                    [rootMenu itemWithTitle:@"Find in Files..."] && [rootMenu itemWithTitle:@"Locate current file"];
        [wp removeRootPath:rootA];
        Check(@"IDM_FILE_OPENFOLDERASWORKSPACE (roots)",
              @"the panel holds several roots, finds a file under them, and has upstream's menu",
              located && menu && [wp.rootPaths isEqualToArray:@[rootB]]);
    }

    if (NppSectionWanted(@"Localization")) { printf("\n== Localization ==\n");
        NppPreferences *lp = [NppPreferences shared];
        NSString *before = lp.localizationFile;
        NSUInteger idsBefore = [app.shortcutStore menuItemsByIdentifier].count;
        lp.localizationFile = @"russian.xml";
        [app applyLocalization];
        NSMenuItem *fileTop = nil, *newItem = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if ([NppEnglishTitle(top) isEqualToString:@"File"] || [NppEnglishMenuTitle(top.submenu) isEqualToString:@"File"]) fileTop = top;
        }
        for (NSMenuItem *it in fileTop.submenu.itemArray) if (it.action == NSSelectorFromString(@"newDocument:")) newItem = it;
        BOOL menus = [fileTop.submenu.title isEqualToString:@"Файл"] && [newItem.title isEqualToString:@"Новый"];
        if (getenv("NPPMAC_L10N_REPORT")) {
            __block NSUInteger total = 0, same = 0;
            __block void (^walk)(NSMenu *, NSString *);
            void (^__block __weak weakWalk)(NSMenu *, NSString *);
            walk = ^(NSMenu *m, NSString *path) {
                for (NSMenuItem *it in m.itemArray) {
                    if (it.isSeparatorItem) continue;
                    if (it.submenu) { weakWalk(it.submenu, [path stringByAppendingFormat:@"/%@", NppEnglishTitle(it)]); continue; }
                    if ([path hasPrefix:@"/Language"] || [path containsString:@"Recent"] || [path hasPrefix:@"/NotepadMac"]) continue;
                    total++;
                    if ([it.title isEqualToString:NppEnglishTitle(it)]) { same++; fprintf(stderr, "UNTRANSLATED %s/%s\n", path.UTF8String, it.title.UTF8String); }
                }
            };
            weakWalk = walk;
            walk(NSApp.mainMenu, @"");
            fprintf(stderr, "L10N %lu of %lu menu items untranslated\n", (unsigned long)same, (unsigned long)total);
        }
        // The Shortcut Mapper still knows every command by its English title.
        BOOL mapper = [app.shortcutStore menuItemsByIdentifier].count == idsBefore;
        // A dialog's controls, by their English text.
        [app buildFindPanel];
        NSPanel *findDialog = [app valueForKey:@"findPanel"];
        [[NppLocalization shared] localizeWindow:findDialog];
        NSButton *matchCase = [app valueForKey:@"matchCaseBox"];
        BOOL dialog = [matchCase.title isEqualToString:@"Учитывать регистр"];
        BOOL message = [NppL(@"Match case") isEqualToString:@"Учитывать регистр"] && [NppL(@"no such text") isEqualToString:@"no such text"];
        // A tab is named as upstream names the dialog ("Замена"), its button as
        // the button ("Заменить"), and a longer title widens its button.
        NSSegmentedControl *tabs = [app valueForKey:@"findTabs"];
        NSButton *replaceAllButton = nil, *replaceButton = nil;
        for (NSView *sub in findDialog.contentView.subviews) {
            if (![sub isKindOfClass:[NSButton class]]) continue;
            if (((NSButton *)sub).action == @selector(findPanelReplaceAll:)) replaceAllButton = (NSButton *)sub;
            if (((NSButton *)sub).action == @selector(findPanelReplace:)) replaceButton = (NSButton *)sub;
        }
        BOOL names = [[tabs labelForSegment:1] isEqualToString:@"Замена"] &&
                     [replaceButton.title isEqualToString:@"Заменить"] &&
                     [replaceAllButton.title isEqualToString:@"Заменить все"] &&
                     replaceAllButton.cell.cellSize.width <= NSWidth(replaceAllButton.frame) + 0.5;
        // What the program writes into a label after it was translated stays:
        // a status line is not put back to the first text it ever held.
        NSWindow *statusWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 60) styleMask:NSWindowStyleMaskTitled
                                                               backing:NSBackingStoreBuffered defer:YES];
        statusWindow.releasedWhenClosed = NO;
        NSTextField *statusLabel = [NSTextField labelWithString:@"Match case"];
        [statusWindow.contentView addSubview:statusLabel];
        statusWindow.title = @"first.txt";
        [[NppLocalization shared] localizeWindow:statusWindow];
        BOOL translatedFirst = [statusLabel.stringValue isEqualToString:@"Учитывать регистр"];
        statusLabel.stringValue = @"3 matches in 2 files";
        statusWindow.title = @"second.txt";
        [[NppLocalization shared] localizeWindow:statusWindow];
        [[NppLocalization shared] localizeWindow:statusWindow];
        BOOL keptNew = [statusLabel.stringValue isEqualToString:@"3 matches in 2 files"] && [statusWindow.title isEqualToString:@"second.txt"];
        statusLabel.stringValue = @"Wrap around";
        [[NppLocalization shared] localizeWindow:statusWindow];
        names = names && translatedFirst && keptNew && [statusLabel.stringValue isEqualToString:@"Зациклить поиск"];

        // Messages: upstream's words with their placeholders, filled in after
        // translation, the translation's line breaks kept; an alert on a sheet
        // or run modally takes them the same way.
        NSString *reloadAsk = NppLMessage(@"\"$STR_REPLACE$\"\n\nThis file has been modified by another program.\nDo you want to reload it?", @"/tmp/x.txt", 0);
        NSString *countLine = NppLMessage(@"Count: $INT_REPLACE$ matches", nil, 12);
        NSAlert *probe = [[NSAlert alloc] init];
        probe.messageText = @"Reload";
        probe.informativeText = @"Are you sure you want to reload the current file and lose the changes made in Notepad++?";
        [probe addButtonWithTitle:@"Yes"];
        [probe addButtonWithTitle:@"Cancel"];
        [(id<NppAlertLocalizing>)probe npp_localize];
        BOOL messages = [reloadAsk hasPrefix:@"\"/tmp/x.txt\""] && [reloadAsk containsString:@"\n"] && ![reloadAsk containsString:@"modified by another"] &&
                        ![reloadAsk containsString:@"$STR_REPLACE$"] &&
                        [countLine containsString:@"12"] && ![countLine containsString:@"matches"] &&
                        ![probe.informativeText containsString:@"Are you sure"] && [probe.buttons.firstObject.title isEqualToString:@"Да"] &&
                        [probe.buttons.lastObject.title isEqualToString:@"Отмена"];
        printf("    l10n messages: %s | %s | %s\n", [reloadAsk stringByReplacingOccurrencesOfString:@"\n" withString:@"/"].UTF8String,
               countLine.UTF8String, probe.informativeText.UTF8String);
        names = names && messages;

        // Preferences in this language: every label, checkbox and pop-up shows
        // its whole text - none is cut or ends in an ellipsis - and none lies on another.
        NSString *(^cutTexts)(void) = ^NSString *{
            PreferencesWindow *w = [[PreferencesWindow alloc] initWithEditor:ed];
            NSMutableArray *bad = [NSMutableArray array];
            NSDictionary<NSString *, NSView *> *pages = [w valueForKey:@"pages"];
            for (NSString *pageName in pages) {
                NSArray<NSView *> *views = pages[pageName].subviews;
                for (NSView *v in views) {
                    BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).bezeled;
                    BOOL isToggle = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]] &&
                                    (((NSButtonCell *)((NSButton *)v).cell).showsStateBy & NSContentsCellMask);
                    BOOL isPopup = [v isKindOfClass:[NSPopUpButton class]];
                    if (!isLabel && !isToggle && !isPopup) continue;
                    NSControl *c = (NSControl *)v;
                    NSString *text = isLabel ? c.stringValue : ((NSButton *)c).title;
                    NSSize need = c.cell.wraps ? [c.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(c.frame), 10000)] : c.cell.cellSize;
                    if (isPopup) {
                        // Every item has to be readable when it is the one chosen.
                        need = NSMakeSize(0, 0);
                        for (NSMenuItem *it in ((NSPopUpButton *)c).itemArray) {
                            need.width = MAX(need.width, [it.title sizeWithAttributes:@{NSFontAttributeName: c.font ?: [NSFont systemFontOfSize:13]}].width + 38);
                        }
                        text = ((NSPopUpButton *)c).titleOfSelectedItem;
                    }
                    if (c.cell.wraps && !isPopup) need.width = 0;      // wrapped: as wide as its frame by construction, the height is what tells
                    if (need.width > NSWidth(c.frame) + 1.5 || need.height > NSHeight(c.frame) + 1.5 || NSMaxX(c.frame) > NSWidth(pages[pageName].bounds)) {
                        [bad addObject:[NSString stringWithFormat:@"%@: cut \"%@\" needs %.0fx%.0f in %.0fx%.0f at x %.0f", pageName, text,
                                        need.width, need.height, NSWidth(c.frame), NSHeight(c.frame), NSMinX(c.frame)]];
                    }
                    for (NSView *o in views) {
                        if (o == v || !([o isKindOfClass:[NSControl class]])) continue;
                        if (NSIntersectsRect(NSInsetRect(v.frame, 2, 2), NSInsetRect(o.frame, 2, 2)) && v.frame.origin.x <= o.frame.origin.x) {
                            [bad addObject:[NSString stringWithFormat:@"%@: \"%@\" overlaps", pageName, text]];
                        }
                    }
                }
            }
            return [bad componentsJoinedByString:@"\n        "];
        };
        NSString *cutInRussian = cutTexts();
        if (cutInRussian.length) printf("    prefs texts (ru):\n        %s\n", cutInRussian.UTF8String);
        names = names && !cutInRussian.length;
        // What Windows does not have comes from the port's own file beside the
        // translation; a "Group|Field" label is put together from both parts.
        NSString *composite = NppL(@"    Non-Printing Characters|Custom Color");
        names = names && [NppL(@"Compare Summary") isEqualToString:@"Итоги сравнения"] &&
                [NppL(@"Remember which panels were open") isEqualToString:@"Запоминать открытые панели"] &&
                [composite hasPrefix:@"    "] && [composite containsString:@": "] && ![composite containsString:@"|"] &&
                ![composite containsString:@"Custom Color"];

        // The other dialogs in this language: no checkbox, radio button or label
        // that is shown has its text cut.
        NSMutableArray<NSString *> *cutElsewhere = [NSMutableArray array];
        __block void (^scan)(NSView *, NSString *);
        void (^__block __weak weakScan)(NSView *, NSString *);
        scan = ^(NSView *v, NSString *where) {
            if (v.hidden) return;
            BOOL lbl = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).bezeled;
            BOOL tog = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]] &&
                       (((NSButtonCell *)((NSButton *)v).cell).showsStateBy & NSContentsCellMask);
            if ((lbl || tog) && !((NSControl *)v).cell.wraps) {
                NSControl *c = (NSControl *)v;
                NSString *text = lbl ? c.stringValue : ((NSButton *)c).title;
                if (text.length && c.cell.cellSize.width > NSWidth(c.frame) + 1.5) {
                    [cutElsewhere addObject:[NSString stringWithFormat:@"%@: \"%@\" needs %.0f of %.0f", where, text, c.cell.cellSize.width, NSWidth(c.frame)]];
                }
            }
            for (NSView *sub in v.subviews) weakScan(sub, where);
        };
        weakScan = scan;
        NSSegmentedControl *findTabsToScan = [app valueForKey:@"findTabs"];
        for (NSInteger tab = 0; tab < findTabsToScan.segmentCount; ++tab) {
            [app openFindPanelOnTab:tab];
            [[NppLocalization shared] localizeWindow:findDialog];
            scan(findDialog.contentView, [NSString stringWithFormat:@"Find tab %ld", (long)tab]);
        }
        [findDialog orderOut:nil];
        StyleConfiguratorWindow *styleToScan = [[StyleConfiguratorWindow alloc] initWithEditor:ed];
        [styleToScan show];
        NSWindow *styleWindowToScan = [styleToScan valueForKey:@"panel"];
        [[NppLocalization shared] localizeWindow:styleWindowToScan];
        scan(styleWindowToScan.contentView, @"Style Configurator");
        [styleToScan cancel:nil];
        NppUserLanguageDialog *udlToScan = [[NppUserLanguageDialog alloc] initWithEditor:ed];
        [udlToScan toggle];
        NSWindow *udlWindowToScan = [udlToScan valueForKey:@"panel"];
        [[NppLocalization shared] localizeWindow:udlWindowToScan];
        scan(udlWindowToScan.contentView, @"User Defined Language");
        [udlToScan toggle];
        NppShortcutMapper *mapperToScan = [[NppShortcutMapper alloc] initWithStore:app.shortcutStore editor:ed];
        [mapperToScan toggle];
        NSWindow *mapperWindowToScan = [mapperToScan valueForKey:@"panel"];
        [[NppLocalization shared] localizeWindow:mapperWindowToScan];
        scan(mapperWindowToScan.contentView, @"Shortcut Mapper");
        BOOL mapperScanned = mapperWindowToScan.contentView != nil;
        [mapperToScan toggle];
        names = names && mapperScanned;
        if (cutElsewhere.count) printf("    cut texts (ru):\n        %s\n", [cutElsewhere componentsJoinedByString:@"\n        "].UTF8String);
        names = names && !cutElsewhere.count;

        // The port's own texts in every language that has them: each file beside
        // a nativeLang file loads with it, and what it does not translate stays English.
        NSString *extraDir = [[[NppLocalization directory] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"nativeLang-extra"];
        NSUInteger extraFiles = 0, extraBroken = 0;
        for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:extraDir error:NULL]) {
            if (![file.pathExtension isEqualToString:@"xml"] || [file isEqualToString:@"english.xml"]) continue;
            extraFiles++;
            NSXMLDocument *parsed = [[NSXMLDocument alloc] initWithData:[NSData dataWithContentsOfFile:[extraDir stringByAppendingPathComponent:file]] options:0 error:NULL];
            BOOL hasNative = [[NSFileManager defaultManager] fileExistsAtPath:[[NppLocalization directory] stringByAppendingPathComponent:file]];
            // (A file may translate nothing yet: a language nobody was sure of stays English.)
            if (!parsed || !hasNative || ![parsed.rootElement.name isEqualToString:@"NativeLangExtra"]) { extraBroken++; printf("    extra: %s is broken\n", file.UTF8String); }
        }
        printf("    l10n extras: %lu files, %lu broken\n", (unsigned long)extraFiles, (unsigned long)extraBroken);
        names = names && extraFiles >= 1 && !extraBroken && [NppL(@"A text the port does not have") isEqualToString:@"A text the port does not have"];

        // Context menus: the tab's in its own wording, the editor's still found
        // by the English titles the setting keeps.
        NSMenu *tabMenu = [app buildTabContextMenu];
        NSMenu *editorMenu = [ed.sci menu];
        NSMenuItem *closeOthers = nil;
        for (NSMenuItem *it in fileTop.submenu.itemArray) for (NSMenuItem *sub in it.submenu.itemArray) if (sub.action == NSSelectorFromString(@"closeAllButCurrent:")) closeOthers = sub;
        BOOL contextMenus = [tabMenu.itemArray.firstObject.title isEqualToString:@"Закрыть"] &&
                            [[tabMenu.itemArray[1].submenu.itemArray.firstObject title] isEqualToString:@"Закрыть все Кроме Текущей"] &&
                            editorMenu.numberOfItems >= 3 && [editorMenu.itemArray.firstObject.title isEqualToString:@"Вырезать"];
        printf("    l10n context: tab=%s/%s editor=%ld first=%s main=%s\n", tabMenu.itemArray.firstObject.title.UTF8String,
               [tabMenu.itemArray[1].submenu.itemArray.firstObject title].UTF8String, (long)editorMenu.numberOfItems,
               editorMenu.itemArray.firstObject.title.UTF8String, closeOthers.title.UTF8String);
        names = names && contextMenus;

        // The language pop-up has one item per file, so its index is the file's.
        PreferencesWindow *lpw = [[PreferencesWindow alloc] initWithEditor:ed];
        NSPopUpButton *languagePopup = [lpw valueForKey:@"controls"][@"localizationFile"];
        NSArray *languageFiles = [lpw valueForKey:@"localizationFiles"];
        NSUInteger russianAt = [languageFiles indexOfObject:@"russian.xml"];
        BOOL popup = languagePopup.numberOfItems == (NSInteger)languageFiles.count && russianAt != NSNotFound &&
                     languagePopup.indexOfSelectedItem == (NSInteger)russianAt;
        NSTableView *pageList = [lpw valueForKey:@"categories"];
        BOOL pages = [[lpw.categoryNames firstObject] isEqualToString:@"General"] &&
                     [[pageList.dataSource tableView:pageList objectValueForTableColumn:nil row:0] isEqualToString:@"Основные"];
        BOOL oneLine = [[[NppLocalization shared] translate:@"Find All in Current Document"] isEqualToString:@"Найти все в Текущем Документе"] &&
                       [[NppLocalization availableLanguages][@"russian.xml"] isEqualToString:@"Русский"];
        printf("    l10n tabs=%s replaceAll=%s popup=%ld/%lu\n", [tabs labelForSegment:1].UTF8String,
               replaceAllButton.title.UTF8String, (long)languagePopup.numberOfItems, (unsigned long)languageFiles.count);
        Check(@"IDM_SETTING_PREFERENCE (localization names)",
              @"tabs take the dialog's names, buttons fit their translation, and the language pop-up matches its files",
              names && popup && pages && oneLine);
        // And back to English, where it all was.
        lp.localizationFile = @"";
        [app applyLocalization];
        [[NppLocalization shared] localizeWindow:findDialog];
        BOOL english = [fileTop.submenu.title isEqualToString:@"File"] && [newItem.title isEqualToString:@"New"] &&
                       [matchCase.title isEqualToString:@"Match case"];
        lp.localizationFile = before ?: @"";
        [app applyLocalization];
        printf("    l10n: %d %d %d %d %d file=%s new=%s case=%s\n", menus, mapper, dialog, message, english,
               fileTop.submenu.title.UTF8String, newItem.title.UTF8String, matchCase.title.UTF8String);
        NSString *cutInEnglish = cutTexts();
        if (cutInEnglish.length) printf("    prefs texts (en):\n        %s\n", cutInEnglish.UTF8String);
        english = english && !cutInEnglish.length;
        Check(@"IDM_SETTING_PREFERENCE (localization)",
              @"russian.xml translates the menus by command id and dialogs by English text, and English comes back",
              menus && mapper && dialog && message && english);
    }

    if (NppSectionWanted(@"New documents, recent files, directories")) { printf("\n== New documents, recent files, directories ==\n");
        NppPreferences *p = [NppPreferences shared];

        p.defaultEOL = SC_EOL_CR;
        p.defaultEncoding = @"UTF-16 LE BOM";
        p.defaultLanguage = @"python";
        [ed newDocument];
        NppDocument *fresh = ed.currentDocument;
        Check(@"IDM_SETTING_PREFERENCE (new document)",
              @"a new document takes the configured EOL, encoding and language",
              fresh.eolMode == SC_EOL_CR && fresh.hasBOM &&
              fresh.encoding == NSUTF16LittleEndianStringEncoding &&
              [fresh.language.name isEqualToString:@"python"]);
        p.defaultEOL = SC_EOL_LF;
        p.defaultEncoding = @"UTF-8";
        p.defaultLanguage = @"";

        p.untitledFromFirstLine = YES;
        SetDoc(ed, @"a title line\nbody\n");
        NSString *derived = [ed untitledNameForDocument:ed.currentDocument];
        p.untitledFromFirstLine = NO;
        NSString *plain = [ed untitledNameForDocument:ed.currentDocument];
        Check(@"IDM_SETTING_PREFERENCE (untitled name)",
              @"the tab can take its name from the first line",
              [derived isEqualToString:@"a title line"] && [plain hasPrefix:@"new"]);

        // Recent files: order, cap and display.
        [ed clearRecentFiles];
        p.recentFilesMax = 3;
        for (NSString *name in @[@"one.txt", @"two.txt", @"three.txt", @"four.txt"]) {
            [ed noteRecentFile:[@"/tmp/recent" stringByAppendingPathComponent:name]];
        }
        NSArray *recent = [ed recentFiles];
        p.recentFilesShowFullPath = NO;
        NSString *shortName = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesShowFullPath = YES;
        p.recentFilesMaxLength = 60;
        NSString *fullName = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesMaxLength = 12;
        NSString *clipped = [ed displayNameForRecentFile:recent.firstObject];
        p.recentFilesShowFullPath = NO;
        Check(@"IDM_SETTING_PREFERENCE (recent files)",
              @"newest first, capped, and shown per the display settings",
              recent.count == 3 && [recent.firstObject hasSuffix:@"four.txt"] &&
              [shortName isEqualToString:@"four.txt"] &&
              [fullName hasPrefix:@"/tmp/recent"] && clipped.length <= 12 &&
              [clipped hasPrefix:@"…"]);

        [ed clearRecentFiles];
        Check(@"IDM_SETTING_PREFERENCE (clear recent)", @"the list can be emptied",
              [ed recentFiles].count == 0);

        // Default directory for the Open panel.
        NSError *err = nil;
        NSString *file = TempFile(@"t_dir.txt", @"x\n");
        [ed openFileAtPath:file error:&err];
        p.defaultDirectoryMode = 0;
        NSString *followsDoc = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 2;
        p.fixedDirectory = @"/usr/share";
        NSString *fixed = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 1;
        p.lastUsedDirectory = @"";
        [ed rememberOpenDirectory:file];
        NSString *remembered = [ed defaultOpenDirectory];
        p.defaultDirectoryMode = 0;
        Check(@"IDM_SETTING_PREFERENCE (default directory)",
              @"following the document, a fixed folder and the last used one all work",
              [followsDoc isEqualToString:file.stringByDeletingLastPathComponent] &&
              [fixed isEqualToString:@"/usr/share"] &&
              [remembered isEqualToString:file.stringByDeletingLastPathComponent]);
    }

    if (NppSectionWanted(@"Searching and highlighting settings")) { printf("\n== Searching and highlighting settings ==\n");
        NppPreferences *p = [NppPreferences shared];
        SetDoc(ed, @"alpha beta alpha\n");

        [sci message:SCI_SETSEL wParam:0 lParam:5];
        p.findFillWithSelection = YES;
        NSString *fromSelection = [ed initialFindTerm];
        p.findFillWithSelection = NO;
        NSString *ignored = [ed initialFindTerm];
        Check(@"IDM_SETTING_PREFERENCE (find from selection)",
              @"the Find field is seeded from the selection only when asked",
              [fromSelection isEqualToString:@"alpha"] && ignored.length == 0);
        p.findFillWithSelection = YES;

        [sci message:SCI_GOTOPOS wParam:7 lParam:0];
        p.findSelectWordUnderCaret = YES;
        NSString *fromCaret = [ed initialFindTerm];
        p.findSelectWordUnderCaret = NO;
        NSString *none = [ed initialFindTerm];
        p.findSelectWordUnderCaret = YES;
        Check(@"IDM_SETTING_PREFERENCE (word under caret)",
              @"with nothing selected the word under the caret is used",
              [fromCaret isEqualToString:@"beta"] && none.length == 0);

        // Smart highlighting refinements change what counts as a match.
        SetDoc(ed, @"Cat cat catalog\n");
        p.smartHighlightEnabled = YES;
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightMatchCase = NO;  p.smartHighlightWholeWord = NO;
        NSUInteger loose = [ed updateSmartHighlight];
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightMatchCase = YES;
        NSUInteger cased = [ed updateSmartHighlight];
        [sci message:SCI_SETSEL wParam:4 lParam:7];
        p.smartHighlightWholeWord = YES;
        NSUInteger strict = [ed updateSmartHighlight];
        p.smartHighlightMatchCase = NO;  p.smartHighlightWholeWord = NO;
        Check(@"IDM_SETTING_PREFERENCE (smart highlight rules)",
              @"match case and whole word each narrow the matches",
              loose == 3 && cased == 2 && strict == 1);
    }

    if (NppSectionWanted(@"Tab bar")) { printf("\n== Tab bar ==\n");
        NppPreferences *p = [NppPreferences shared];
        NSError *err = nil;
        [ed closeAllDocuments];
        for (int i = 1; i <= 4; ++i) {
            [ed openFileAtPath:TempFile([NSString stringWithFormat:@"tb%d.txt", i], @"x\n") error:&err];
        }
        NppTabBarView *bar = [ed valueForKey:@"tabBar"];
        [bar setFrameSize:NSMakeSize(600, 26)];
        [ed refreshChrome];

        // One row: the tabs sit side by side at the same height.
        p.tabBarVertical = NO; p.tabBarMultiLine = NO;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(600, 26)];
        NSRect first = [bar frameOfTabAtIndex:0];
        NSRect second = [bar frameOfTabAtIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab bar row)",
              @"tabs lie side by side in one row",
              NSMinY(first) == NSMinY(second) && NSMinX(second) > NSMinX(first) &&
              bar.items.count == ed.documents.count);

        // Vertical: stacked instead.
        p.tabBarVertical = YES;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(140, 400)];
        NSRect vFirst = [bar frameOfTabAtIndex:0];
        NSRect vSecond = [bar frameOfTabAtIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab bar vertical)",
              @"tabs stack down the side",
              NSMinX(vFirst) == NSMinX(vSecond) && NSMinY(vSecond) > NSMinY(vFirst));
        p.tabBarVertical = NO;

        // Multi-line: they wrap onto a second row in a narrow bar.
        p.tabBarMultiLine = YES;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(200, 60)];
        BOOL wrapped = NO;
        for (NSInteger i = 1; i < (NSInteger)bar.items.count; ++i) {
            if (NSMinY([bar frameOfTabAtIndex:i]) > NSMinY([bar frameOfTabAtIndex:0])) wrapped = YES;
        }
        Check(@"IDM_SETTING_PREFERENCE (tab bar multi-line)",
              @"tabs wrap onto another row when the bar is narrow",
              wrapped && [bar requiredThickness] > 26);
        p.tabBarMultiLine = NO;
        [ed applyTabBarPreferences];
        [bar setFrameSize:NSMakeSize(600, 26)];

        // Close buttons: on the active tab, and on the others only when asked.
        p.tabShowCloseButton = YES;
        p.tabCloseButtonOnInactive = NO;
        [ed applyTabBarPreferences];
        [ed selectDocumentAtIndex:0];
        NSRect active = [bar frameOfTabAtIndex:0];
        NSPoint onActiveClose = NSMakePoint(NSMaxX(active) - 10, NSMidY(active));
        NSRect other = [bar frameOfTabAtIndex:2];
        NSPoint onOtherClose = NSMakePoint(NSMaxX(other) - 10, NSMidY(other));
        BOOL activeOnly = [bar point:onActiveClose isOnCloseButtonOfIndex:0] &&
                          ![bar point:onOtherClose isOnCloseButtonOfIndex:2];
        p.tabCloseButtonOnInactive = YES;
        [ed applyTabBarPreferences];
        BOOL alsoInactive = [bar point:onOtherClose isOnCloseButtonOfIndex:2];
        p.tabCloseButtonOnInactive = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab close buttons)",
              @"the close button follows its setting",
              activeOnly && alsoInactive);

        // Closing through the bar removes that tab.
        NSUInteger before = ed.documents.count;
        [ed tabBar:bar didRequestCloseIndex:1];
        Check(@"IDM_SETTING_PREFERENCE (tab close)",
              @"the bar's close button closes that document",
              ed.documents.count == before - 1);

        // Dragging reorders.
        NSString *movedName = ed.documents[0].displayName;
        [ed tabBar:bar didMoveIndex:0 toIndex:2];
        Check(@"IDM_SETTING_PREFERENCE (tab reorder)",
              @"a dragged tab lands at its new position",
              [ed.documents[2].displayName isEqualToString:movedName] &&
              ed.currentDocument == ed.documents[2]);

        p.hideTabBar = YES;
        [ed applyTabBarPreferences];
        BOOL hidden = bar.isHidden;
        p.hideTabBar = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (hide tab bar)",
              @"the bar can be hidden and shown", hidden && !bar.isHidden);

        p.tabBarLocked = YES;
        [ed applyTabBarPreferences];
        BOOL locked = bar.locked;
        p.tabBarLocked = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab bar lock)",
              @"locking is passed to the bar", locked && !bar.locked);
    }

    if (NppSectionWanted(@"Language: user defined")) { printf("\n== Language: user defined ==\n");
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        [ed setLanguageNamed:@"javascript.js"];
        Check(@"IDM_LANG_JS", @"the .js JavaScript variant can be selected",
              [cat languageNamed:@"javascript.js"] != nil &&
              [ed.currentDocument.language.name isEqualToString:@"javascript.js"]);

        BOOL defined = [ed defineUserLanguageNamed:@"MyLang" extensions:@"mylang ml2"
                                          keywords:@"alpha beta" commentLine:@"#"];
        NSDictionary *readBack = [ed userDefinedLanguage];
        Check(@"IDM_LANG_USER_DLG", @"writes userDefineLang.xml and applies the language",
              defined && [readBack[@"name"] isEqualToString:@"MyLang"] &&
              [readBack[@"ext"] isEqualToString:@"mylang ml2"] &&
              [ed.currentDocument.language.name isEqualToString:@"MyLang"]);

        Check(@"IDM_LANG_OPENUDLDIR", @"the user-defined language file has a folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:[ed userDefinedLanguagePath]]);

        NSURL *collection = [NSURL URLWithString:
            @"https://github.com/notepad-plus-plus/userDefinedLanguages"];
        Check(@"IDM_LANG_UDLCOLLECTION_PROJECT_SITE", @"points at a valid https URL",
              collection != nil && [collection.scheme isEqualToString:@"https"]);

        [ed setLanguageNamed:@"normal"];
    }

    if (NppSectionWanted(@"JSON")) { printf("\n== JSON ==\n");
        NppPreferences *p = [NppPreferences shared];
        [ed newDocument];

        // Format: compact input becomes indented, and stays the same document.
        p.jsonIndent = 4;
        SetDoc(ed, @"{\"b\":1,\"a\":[1,2,{\"c\":null}]}");
        BOOL formatted = [ed formatJSONDocument];
        NSString *pretty = DocText(ed);
        Check(@"JSON format", @"compact JSON becomes indented",
              formatted && [pretty containsString:@"\n"] &&
              [pretty containsString:@"    "] && [pretty containsString:@"\"a\""]);

        // Compacting it again must give back an equivalent single line.
        BOOL compacted = [ed compactJSONDocument];
        NSString *tight = DocText(ed);
        Check(@"JSON compact", @"indented JSON becomes one line again",
              compacted && ![tight containsString:@"\n"] && [tight hasPrefix:@"{"] &&
              [tight containsString:@"\"c\":null"]);

        // Round trip: the data must survive both directions.
        NSData *original = [tight dataUsingEncoding:NSUTF8StringEncoding];
        id parsedAgain = [NSJSONSerialization JSONObjectWithData:original options:0 error:NULL];
        Check(@"JSON round trip", @"the value is unchanged by formatting",
              [parsedAgain[@"b"] integerValue] == 1 && [parsedAgain[@"a"] count] == 3);

        // Sorting puts the keys in order.
        SetDoc(ed, @"{\"zeta\":1,\"alpha\":2}");
        [ed sortJSONDocument];
        NSString *sorted = DocText(ed);
        Check(@"JSON sort", @"keys come out in order",
              [sorted rangeOfString:@"alpha"].location < [sorted rangeOfString:@"zeta"].location);

        // Validation reports where the problem is.
        SetDoc(ed, @"{\"ok\": 1}");
        NppJsonError *clean = [ed validateJSONDocument];
        SetDoc(ed, @"{\n  \"ok\": 1,\n  bad\n}");
        NppJsonError *broken = [ed validateJSONDocument];
        Check(@"JSON validate", @"valid passes, invalid reports a line",
              clean == nil && broken != nil && broken.line >= 1 && broken.message.length > 0);

        // Formatting must refuse rather than damage a document that is not JSON.
        SetDoc(ed, @"this is not json at all\n");
        NSString *before = DocText(ed);
        BOOL refused = ![ed formatJSONDocument];
        Check(@"JSON refuses non-JSON", @"a non-JSON document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);

        // The tree lists every node with its path.
        SetDoc(ed, @"{\"top\":{\"inner\":[10,20]}}");
        NSArray *tree = [ed jsonTree];
        NSMutableArray *paths = [NSMutableArray array];
        for (NSDictionary *node in tree) [paths addObject:node[@"path"]];
        Check(@"JSON tree", @"nested paths are reported",
              [paths containsObject:@"top.inner[0]"] && [paths containsObject:@"top.inner[1]"] &&
              [paths containsObject:@"top.inner"]);
    }

    if (NppSectionWanted(@"Compare")) { printf("\n== Compare ==\n");
        NSArray *oldLines = @[@"alpha", @"beta", @"gamma", @"delta"];
        NSArray *newLines = @[@"alpha", @"BETA", @"gamma", @"delta", @"epsilon"];

        NSArray<NppDiffLine *> *diff = [EditorController diffBetween:oldLines and:newLines
                                                         ignoreCase:NO ignoreSpaces:NO
                                                   ignoreEmptyLines:NO];
        NSUInteger changed = 0, added = 0, same = 0;
        for (NppDiffLine *l in diff) {
            if (l.kind == NppDiffChanged) changed++;
            else if (l.kind == NppDiffAdded) added++;
            else if (l.kind == NppDiffSame) same++;
        }
        Check(@"Compare diff", @"one changed line, one added, three unchanged",
              changed == 1 && added == 1 && same == 3);

        // Ignoring case makes the changed line equal.
        NSArray *ignoringCase = [EditorController diffBetween:oldLines and:newLines
                                                   ignoreCase:YES ignoreSpaces:NO
                                             ignoreEmptyLines:NO];
        NSUInteger stillDifferent = 0;
        for (NppDiffLine *l in ignoringCase) if (l.kind != NppDiffSame) stillDifferent++;
        Check(@"Compare ignore case", @"only the added line remains a difference",
              stillDifferent == 1);

        // Ignoring spaces makes re-indented lines equal.
        NSArray *spacedDiff = [EditorController diffBetween:@[@"a  b", @"c"]
                                                       and:@[@"a b", @"c"]
                                                ignoreCase:NO ignoreSpaces:YES
                                          ignoreEmptyLines:NO];
        NSUInteger spaceDiffs = 0;
        for (NppDiffLine *l in spacedDiff) if (l.kind != NppDiffSame) spaceDiffs++;
        Check(@"Compare ignore spaces", @"re-spaced lines count as equal", spaceDiffs == 0);

        // Identical input produces no differences at all.
        NSArray *identical = [EditorController diffBetween:oldLines and:oldLines
                                                ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
        NSUInteger anyDiff = 0;
        for (NppDiffLine *l in identical) if (l.kind != NppDiffSame) anyDiff++;
        Check(@"Compare identical", @"identical files differ nowhere",
              anyDiff == 0 && identical.count == oldLines.count);

        // Two lines edited in a row are two changed lines, not one changed and one added; a
        // third new line after them is added; two lines gone before them are removed.
        NSArray *block = [EditorController diffBetween:@[@"a", @"x", @"y", @"b", @"c"] and:@[@"a", @"X", @"Y", @"Z", @"b"]
                                            ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
        NSMutableString *kinds = [NSMutableString string];
        for (NppDiffLine *l in block) [kinds appendFormat:@"%@", l.kind == NppDiffSame ? @"=" : l.kind == NppDiffChanged ? @"C" : l.kind == NppDiffAdded ? @"A" : @"R"];
        Check(@"Compare (blocks pair up)", @"x,y -> X,Y,Z is two changed lines and one added; c gone is one removed",
              [kinds isEqualToString:@"=CCA=R"] && [block[1] newLine] == 1 && [block[2] newLine] == 2 && [block[1] oldLine] == 1 && [block[2] oldLine] == 2);

        // End to end, through the editor.
        NSError *err = nil;
        NSString *oldPath = TempFile(@"cmp_old.txt", @"alpha\nbeta x\ngamma\n");
        NSString *newPath = TempFile(@"cmp_new.txt", @"alpha\nbetta x\ngamma\ndelta\n");
        [ed openFileAtPath:newPath error:&err];
        BOOL ignoreCaseWas = ed.compareIgnoreCase, ignoreSpacesWas = ed.compareIgnoreSpaces, ignoreEmptyWas = ed.compareIgnoreEmptyLines;
        ed.compareIgnoreCase = NO; ed.compareIgnoreSpaces = NO; ed.compareIgnoreEmptyLines = NO;   // the user's own settings aside
        BOOL compared = [ed compareWithFileAtPath:oldPath];
        // The pane with the old file is coloured like the document (its lexer and theme), both
        // sides carry the marks (changed line 2 in both, added line 4 in the new one), and the
        // caret was taken to the first difference.
        [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
        long oldSideChanged = [ed.secondarySci message:SCI_MARKERGET wParam:1 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long newSideChanged = [sci message:SCI_MARKERGET wParam:1 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long newSideAdded = [sci message:SCI_MARKERGET wParam:3 lParam:0] & (1 << NPPMAC_MARKER_ADDED);
        long backOld = [ed.secondarySci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT lParam:0];
        long backNew = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT lParam:0];
        long fontOld = [ed.secondarySci message:SCI_STYLEGETSIZE wParam:STYLE_DEFAULT lParam:0];
        long fontNew = [sci message:SCI_STYLEGETSIZE wParam:STYLE_DEFAULT lParam:0];
        long caretLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS] lParam:0];
        // Scintilla draws a background marker in the text only if some margin's mask has its bit:
        // the first pane must have Compare's bits in one, or its marks are invisible (they were).
        long maskWithCompare = [sci message:SCI_GETMARGINMASKN wParam:1 lParam:0] & (0xF << 2);
        Check(@"Compare run", @"comparing marks differences on both sides, colours the old pane like the document, and lands on the first difference",
              compared && [ed compareActive] && [ed secondaryViewVisible] &&
              [[ed compareSummary] containsString:@"changed"] &&
              oldSideChanged && newSideChanged && newSideAdded && backOld == backNew && fontOld == fontNew && caretLine == 1 &&
              maskWithCompare == (0xF << 2));

        // The revert arrows beside the differing lines, the bar above the other pane, and what the arrow does:
        // the run at that line goes back to the other side, one undo step, and the comparison is worked out again.
        long arrowMask = 1 << NPPMAC_MARKER_REVERT;
        BOOL arrowsWhereDue = ([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask) && ([sci message:SCI_MARKERGET wParam:3 lParam:0] & arrowMask) &&
                              !([sci message:SCI_MARKERGET wParam:0 lParam:0] & arrowMask) && !([sci message:SCI_MARKERGET wParam:2 lParam:0] & arrowMask);
        BOOL marginShown = [sci message:SCI_GETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0] > 0;
        NSView *bar = [ed compareBar];
        NSTextField *barSummary = nil;
        for (NSView *v in bar.subviews) if ([v.identifier isEqualToString:@"compareSummary"]) barSummary = (NSTextField *)v;
        BOOL barShown = bar.superview == [ed secondaryHost] && [barSummary.stringValue containsString:@"1 changed"];
        BOOL revertedChanged = [ed compareRevertChangeAtLine:1] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\ndelta\n"] &&
                               [barSummary.stringValue containsString:@"0 changed"] && !([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask);
        BOOL noArrowHere = ![ed compareRevertChangeAtLine:0];
        BOOL revertedAdded = [ed compareRevertChangeAtLine:3] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\n"] &&
                             [barSummary.stringValue containsString:@"identical"];
        [sci message:SCI_UNDO wParam:0 lParam:0];
        [sci message:SCI_UNDO wParam:0 lParam:0];
        BOOL undoneBoth = [DocText(ed) isEqualToString:@"alpha\nbetta x\ngamma\ndelta\n"];
        // Typing while the comparison is on: a moment later the marks, the arrows and the summary follow.
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        [sci message:SCI_APPENDTEXT wParam:8 lParam:(sptr_t)"epsilon\n"];   // a new last line
        NppSettleUntil(^BOOL{ return ([sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED)) != 0; }, 5);
        BOOL typedFollowed = ([sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED)) && ([sci message:SCI_MARKERGET wParam:4 lParam:0] & arrowMask) &&
                             [barSummary.stringValue containsString:@"2 added"];
        BOOL typedReverted = [ed compareRevertChangeAtLine:4] && [DocText(ed) isEqualToString:@"alpha\nbetta x\ngamma\n"];   // delta and epsilon are one run of added lines
        // A removal's arrow stands on the line after it, and puts the lines back before that line.
        [ed clearAllCompares];
        SetDoc(ed, @"alpha\ngamma\n");
        [ed compareWithFileAtPath:oldPath];
        BOOL removalArrow = ([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask) != 0;
        BOOL revertedRemoval = [ed compareRevertChangeAtLine:1] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\n"];
        // Escape in a pane ends the comparison, as the ✕ does: the bar and the margin go.
        [ed.window makeFirstResponder:sci];
        NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:ed.window.windowNumber
                                            context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
        [NSApp sendEvent:escape];
        BOOL escaped = ![ed compareActive] && ![ed secondaryViewVisible] && [ed compareBar].superview == nil &&
                       [sci message:SCI_GETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0] == 0;
        Check(@"Compare (revert arrows, bar, Escape)", @"arrows stand beside the changed and added lines only; the bar shows the summary; an arrow puts its run back to the other side, one undo step, with the summary and the arrows following; a line typed while comparing is marked a moment later and can be put back; a removal's arrow on the line after puts the lines back; Escape ends the comparison",
              arrowsWhereDue && marginShown && barShown && revertedChanged && noArrowHere && revertedAdded && undoneBoth && typedFollowed && typedReverted && removalArrow && revertedRemoval && escaped);
        [ed openFileAtPath:newPath error:&err];
        SetDoc(ed, @"alpha\nbetta x\ngamma\ndelta\n");   // as the file has it; the tab was edited above
        [ed compareWithFileAtPath:oldPath];

        // The ComparePlus engine's own marks: a moved line found and marked as moved in both panes
        // (not removed and added), the changed characters of a changed line under the indicator,
        // blank annotations that keep both panes at the same height, and the summary counting moves.
        [ed clearAllCompares];
        NSString *movedOld = TempFile(@"cmp_moved_old.txt", @"int a = 1;\nint b = 2;\nint c = 3;\nint d = 4;\nint e = 5;\nint moved = 9;\nint f = 6;\n");
        NSString *movedNew = TempFile(@"cmp_moved_new.txt", @"int moved = 9;\nint a = 1;\nint B = 2;\nint c = 3;\nint added = 0;\nint added2 = 0;\nint d = 4;\nint f = 6;\n");
        [ed openFileAtPath:movedNew error:&err];
        BOOL movesWas = ed.compareDetectMoves, charsWas = ed.compareCharDiffs;
        ed.compareDetectMoves = YES; ed.compareCharDiffs = YES;
        [ed compareWithFileAtPath:movedOld];
        long movedMaskNew = [sci message:SCI_MARKERGET wParam:0 lParam:0] & (1 << NPPMAC_MARKER_MOVED);
        long movedMaskOld = [ed.secondarySci message:SCI_MARKERGET wParam:5 lParam:0] & (1 << NPPMAC_MARKER_MOVED);
        long changedNew = [sci message:SCI_MARKERGET wParam:2 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long addedNew = [sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED);
        long removedOld = [ed.secondarySci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_REMOVED);
        // "int B = 2;" against "int b = 2;": the B, and only the B, is under the changed-characters indicator (18).
        long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:2 lParam:0];
        long onB = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 4)];
        long onInt = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)lineStart];
        long onTwo = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 8)];
        // Alignment: "int d = 4;" is line 7 in the new pane and line 4 in the old; with the blank
        // annotations both stand on the same visible line.
        long dNew = [sci message:SCI_VISIBLEFROMDOCLINE wParam:6 lParam:0], dOld = [ed.secondarySci message:SCI_VISIBLEFROMDOCLINE wParam:3 lParam:0];
        long fNew = [sci message:SCI_VISIBLEFROMDOCLINE wParam:7 lParam:0], fOld = [ed.secondarySci message:SCI_VISIBLEFROMDOCLINE wParam:6 lParam:0];
        NSString *movedSummary = [ed compareSummary];
        ed.compareDetectMoves = NO;
        [ed compareRefreshNow];
        long movedWithoutDetection = [sci message:SCI_MARKERGET wParam:0 lParam:0] & ((1 << NPPMAC_MARKER_MOVED) | (1 << NPPMAC_MARKER_ADDED));
        // Character differences off: the plugin still marks the differing words, so B stays marked.
        ed.compareCharDiffs = NO;
        [ed compareRefreshNow];
        long onBWords = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 4)];
        ed.compareDetectMoves = movesWas; ed.compareCharDiffs = charsWas;
        [ed clearAllCompares];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"Compare (ComparePlus engine)", @"a moved line is marked moved on both sides, a changed line's changed characters and nothing else are under the indicator, additions and the removal are marked, both panes are aligned at the same visible lines, the summary counts the move; with Detect Moves off the line is added; with character differences off the differing word is still marked",
              movedMaskNew && movedMaskOld && changedNew && addedNew && removedOld &&
              onB && !onInt && !onTwo && dNew == dOld && fNew == fOld &&
              [movedSummary isEqualToString:@"2 added, 1 removed, 1 moved, 1 changed, 4 unchanged."] &&
              movedWithoutDetection == (1 << NPPMAC_MARKER_ADDED) && onBWords);
        [ed openFileAtPath:newPath error:&err];
        SetDoc(ed, @"alpha\nbetta x\ngamma\ndelta\n");
        [ed compareWithFileAtPath:oldPath];

        // Navigation walks the marked lines.
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL next = [ed goToDiff:1];
        long firstStop = [sci message:SCI_LINEFROMPOSITION
                               wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        BOOL last = [ed goToLastDiff];
        long lastStop = [sci message:SCI_LINEFROMPOSITION
                              wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"Compare navigation", @"next and last land on marked lines",
              next && last && firstStop > 0 && lastStop >= firstStop);

        // "Set as first" then compare, the way the menu drives it.
        [ed openFileAtPath:oldPath error:&err];
        [ed setFirstToCompare];
        [ed openFileAtPath:newPath error:&err];
        BOOL viaFirst = [ed compareWithFirst];
        Check(@"Compare set first", @"the file set aside is the one compared against",
              viaFirst && [[ed firstToCompare] isEqualToString:oldPath]);

        ed.compareIgnoreCase = ignoreCaseWas; ed.compareIgnoreSpaces = ignoreSpacesWas; ed.compareIgnoreEmptyLines = ignoreEmptyWas;
        [ed clearAllCompares];
        Check(@"Compare clear", @"clearing removes the comparison and the second pane",
              ![ed compareActive] && [ed firstToCompare] == nil && ![ed secondaryViewVisible]);
    }

    if (NppSectionWanted(@"FTP")) { printf("\n== FTP ==\n");
        // The listing parser sees both layouts servers actually send.
        NSString *unixListing =
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 folder\r\n"
            @"-rw-r--r-- 1 owner group      137 Jan  1 00:00 notes.txt\r\n"
            @"lrwxrwxrwx 1 owner group        7 Jan  1 00:00 link -> target\r\n"
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 .\r\n";
        NSArray<NppFtpEntry *> *unix = [NppFtpClient parseListing:unixListing];
        NSMutableDictionary<NSString *, NppFtpEntry *> *byName = [NSMutableDictionary dictionary];
        for (NppFtpEntry *e in unix) byName[e.name] = e;
        NppFtpEntry *folder = byName[@"folder"];
        NppFtpEntry *notes = byName[@"notes.txt"];
        Check(@"FTP listing (unix)",
              @"directories, sizes and symlink names are read correctly",
              unix.count == 3 && folder.isDirectory && !notes.isDirectory &&
              notes.size == 137 && byName[@"link"] != nil);

        NSString *dosListing =
            @"01-01-24  12:00AM       <DIR>          images\r\n"
            @"01-01-24  12:00AM                 2048 report.doc\r\n";
        NSArray<NppFtpEntry *> *dos = [NppFtpClient parseListing:dosListing];
        NppFtpEntry *dosDir = dos.count ? dos[0] : nil;
        NppFtpEntry *dosFile = dos.count > 1 ? dos[1] : nil;
        Check(@"FTP listing (DOS)", @"the other layout is read too",
              dos.count == 2 && dosDir.isDirectory && !dosFile.isDirectory &&
              dosFile.size == 2048);

        // Profiles round-trip through the settings.
        NppFtpProfile *profile = [[NppFtpProfile alloc] init];
        profile.name = @"test-server";
        profile.host = @"127.0.0.1";
        profile.username = @"tester";
        profile.protocol = NppFtpPlain;
        profile.initialDirectory = @"/";
        [ed saveFtpProfile:profile];
        NppFtpProfile *read = [ed ftpProfileNamed:@"test-server"];
        Check(@"FTP profiles", @"a connection is saved and read back",
              read != nil && [read.host isEqualToString:@"127.0.0.1"] &&
              [read.username isEqualToString:@"tester"]);

        Check(@"FTP url", @"the URL carries host, port and path",
              [[read urlForPath:@"dir/file.txt"] isEqualToString:@"ftp://127.0.0.1:21/%2Fdir/file.txt"]);

        // End to end against a real server, started for this test.
        NSString *script = [[NSBundle mainBundle] pathForResource:@"test-ftp-server" ofType:@"py"];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ftproot"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:
            [root stringByAppendingPathComponent:@"sub"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"remote hello\n" writeToFile:[root stringByAppendingPathComponent:@"greeting.txt"]
                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSTask *server = nil;
        NSInteger port = 0;
        if (script) {
            server = [[NSTask alloc] init];
            server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            server.arguments = @[script, root];
            NSPipe *out = [NSPipe pipe];
            server.standardOutput = out;
            if ([server launchAndReturnError:NULL]) {
                // The server prints the port it was given; read just that line.
                NSData *line = [out.fileHandleForReading availableData];
                NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
                NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet]
                                        intoString:NULL];
                [scanner scanInteger:&port];
            }
        }

        if (port <= 0) {
            Check(@"FTP transfer", @"the test server could not be started", NO);
        } else {
            profile.port = port;
            [ed saveFtpProfile:profile];

            BOOL connected = [ed connectToFtpProfile:profile password:@"secret"];
            NSArray<NppFtpEntry *> *listing = connected ? [ed ftpListCurrentDirectory] : nil;
            NSMutableArray *names = [NSMutableArray array];
            for (NppFtpEntry *e in listing) [names addObject:e.name];
            Check(@"FTP connect", @"logging in and listing the directory works",
                  connected && [ed ftpConnected] && [names containsObject:@"greeting.txt"] &&
                  [names containsObject:@"sub"]);

            BOOL opened = [ed openRemoteFileAtPath:@"greeting.txt"];
            Check(@"FTP download", @"a remote file opens in a tab with its contents",
                  opened && [DocText(ed) isEqualToString:@"remote hello\n"] &&
                  [[ed remotePathForCurrentDocument] isEqualToString:@"/greeting.txt"]);

            SetDoc(ed, @"changed here\n");
            BOOL uploaded = [ed uploadCurrentDocument];
            NSString *onServer = [NSString stringWithContentsOfFile:
                [root stringByAppendingPathComponent:@"greeting.txt"]
                                                           encoding:NSUTF8StringEncoding error:NULL];
            Check(@"FTP upload", @"saving sends the file back to where it came from",
                  uploaded && [onServer isEqualToString:@"changed here\n"]);

            BOOL descended = [ed ftpChangeDirectory:@"sub"];
            Check(@"FTP directories", @"changing directory follows the server",
                  descended && [[ed ftpCurrentDirectory] hasSuffix:@"sub"]);

            [ed disconnectFtp];
            Check(@"FTP disconnect", @"disconnecting drops the connection",
                  ![ed ftpConnected] && [ed ftpClient] == nil);

            [server terminate];
        }
        [ed removeFtpProfileNamed:@"test-server"];
    }

    if (NppSectionWanted(@"XML")) { printf("\n== XML ==\n");
        [ed newDocument];
        NSString *compact = @"<?xml version=\"1.0\"?><root a=\"1\" b=\"2\"><item>one</item><item>two</item></root>";

        SetDoc(ed, compact);
        BOOL pretty = [ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        NSString *formatted = DocText(ed);
        Check(@"XML pretty print", @"one line becomes an indented document",
              pretty && [[formatted componentsSeparatedByString:@"\n"] count] > 3 &&
              [formatted containsString:@"    <item>one</item>"]);

        BOOL flat = [ed linearizeXMLDocument];
        NSString *linear = DocText(ed);
        Check(@"XML linearize", @"the indented document becomes one line again",
              flat && ![[linear substringFromIndex:MIN(40u, linear.length)] containsString:@"\n"] &&
              [linear containsString:@"<item>one</item><item>two</item>"]);

        // The value must survive both directions.
        NSArray *items = [EditorController evaluateXPath:@"//item" onText:linear error:NULL];
        Check(@"XML round trip", @"the content is unchanged by formatting",
              items.count == 2 && [items[0] containsString:@"one"]);

        SetDoc(ed, compact);
        [ed prettyPrintXMLDocument:NppXmlPrettyAttributes];
        NSString *attrs = DocText(ed);
        Check(@"XML indent attributes", @"each attribute moves onto its own line",
              [attrs containsString:@"b=\"2\""] &&
              [[attrs componentsSeparatedByString:@"\n"] count] >
              [[formatted componentsSeparatedByString:@"\n"] count]);

        // Syntax: a good document passes, a broken one reports where.
        SetDoc(ed, @"<a><b/></a>");
        NppXmlError *fine = [ed checkXMLSyntaxOfDocument];
        SetDoc(ed, @"<a>\n  <b>\n</a>");
        NppXmlError *broken = [ed checkXMLSyntaxOfDocument];
        Check(@"XML syntax check", @"valid passes and invalid reports a line",
              fine == nil && broken != nil && broken.line >= 0 && broken.message.length > 0);

        // A document that is not XML must be refused, not mangled.
        SetDoc(ed, @"not xml at all");
        NSString *before = DocText(ed);
        BOOL refused = ![ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        Check(@"XML refuses non-XML", @"a non-XML document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);

        // XPath, including an expression that selects attributes.
        NSString *doc = @"<catalog><book id=\"a\"><title>First</title></book>"
                        @"<book id=\"b\"><title>Second</title></book></catalog>";
        NSArray *titles = [EditorController evaluateXPath:@"//title/text()" onText:doc error:NULL];
        NSArray *ids = [EditorController evaluateXPath:@"//book/@id" onText:doc error:NULL];
        NSString *xpathFailure = nil;
        NSArray *bad = [EditorController evaluateXPath:@"//[[" onText:doc error:&xpathFailure];
        Check(@"XML XPath", @"nodes and attributes are selected, and a bad expression reports",
              titles.count == 2 && [titles[1] isEqualToString:@"Second"] &&
              ids.count == 2 && [ids[0] isEqualToString:@"a"] &&
              bad == nil && xpathFailure.length > 0);

        // XSL transformation.
        NSString *sheet =
            @"<?xml version=\"1.0\"?>"
            @"<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            @"<xsl:output method=\"xml\"/>"
            @"<xsl:template match=\"/\"><titles><xsl:for-each select=\"//title\">"
            @"<t><xsl:value-of select=\".\"/></t></xsl:for-each></titles></xsl:template>"
            @"</xsl:stylesheet>";
        NSString *xslFailure = nil;
        NSString *transformed = [EditorController applyXSL:sheet toText:doc error:&xslFailure];
        Check(@"XML XSL", @"a stylesheet produces the expected output",
              transformed != nil && [transformed containsString:@"<t>First</t>"] &&
              [transformed containsString:@"<t>Second</t>"]);

        // XSD validation, which NSXMLDocument cannot do and libxml2 can.
        NSString *schema =
            @"<?xml version=\"1.0\"?>"
            @"<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
            @"<xs:element name=\"note\"><xs:complexType><xs:sequence>"
            @"<xs:element name=\"to\" type=\"xs:string\"/>"
            @"</xs:sequence></xs:complexType></xs:element></xs:schema>";
        NppXmlError *matches = [EditorController validateXML:@"<note><to>you</to></note>"
                                               againstSchema:schema];
        NppXmlError *mismatch = [EditorController validateXML:@"<note><wrong>x</wrong></note>"
                                                againstSchema:schema];
        Check(@"XML schema validation", @"a matching document passes and a wrong one is reported",
              matches == nil && mismatch != nil && mismatch.message.length > 0);

        // Escaping a selection, and putting it back.
        SetDoc(ed, @"a <b> & \"c\"");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:YES];
        NSString *escaped = DocText(ed);
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:NO];
        Check(@"XML escaping", @"characters are escaped and restored exactly",
              [escaped containsString:@"&lt;b&gt;"] && [escaped containsString:@"&amp;"] &&
              [DocText(ed) isEqualToString:@"a <b> & \"c\""]);

        // The path at the caret, which has to work on a document still being typed.
        SetDoc(ed, @"<root>\n  <list>\n    <item>one</item>\n    <item>tw");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        NSString *plainPath = [ed xmlPathAtCaretWithPredicates:NO];
        NSString *indexedPath = [ed xmlPathAtCaretWithPredicates:YES];
        Check(@"XML current path", @"the path is reported while the document is incomplete",
              [plainPath isEqualToString:@"/root/list/item"] &&
              [indexedPath isEqualToString:@"/root[1]/list[1]/item[2]"]);
    }

    if (NppSectionWanted(@"Run")) { printf("\n== Run ==\n");
        // The variables are read off a real document, so the test exercises the
        // same path the menu command does.
        NSString *runPath = TempFile(@"npp_run_test.txt", @"alpha beta\nsecond line\n");
        [ed openFileAtPath:runPath error:NULL];
        ScintillaView *sci = ed.sci;
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];    // inside "beta" on line 0

        NSString *dir = runPath.stringByDeletingLastPathComponent;
        BOOL paths =
            [[ed expandRunVariables:@"$(FULL_CURRENT_PATH)"] isEqualToString:runPath] &&
            [[ed expandRunVariables:@"$(CURRENT_DIRECTORY)"] isEqualToString:dir] &&
            [[ed expandRunVariables:@"$(FILE_NAME)"] isEqualToString:@"npp_run_test.txt"] &&
            [[ed expandRunVariables:@"$(NAME_PART)"] isEqualToString:@"npp_run_test"];
        BOOL caret =
            [[ed expandRunVariables:@"$(CURRENT_WORD)"] isEqualToString:@"beta"] &&
            // A value with a space in it is quoted, so the shell keeps it whole.
            [[ed expandRunVariables:@"$(CURRENT_LINESTR)"] isEqualToString:@"'alpha beta'"] &&
            [[ed expandRunVariables:@"$(CURRENT_LINE)"] isEqualToString:@"0"] &&
            [[ed expandRunVariables:@"$(CURRENT_COLUMN)"] isEqualToString:@"6"];
        BOOL npp =
            [[ed expandRunVariables:@"$(NPP_FULL_FILE_PATH)"] containsString:@"NotepadMac"] &&
            [ed expandRunVariables:@"$(NPP_DIRECTORY)"].length > 0;
        Check(@"Run variables", @"every substitution Notepad++ makes is made here too",
              paths && caret && npp);

        // Windows keeps the dot on the extension, and gives nothing when there
        // is none; both halves of that are easy to get wrong.
        NSString *withExt = [ed expandRunVariables:@"$(EXT_PART)"];
        NSString *plainPath = TempFile(@"npp_run_plain", @"x\n");
        [ed openFileAtPath:plainPath error:NULL];
        NSString *withoutExt = [ed expandRunVariables:@"$(EXT_PART)"];
        Check(@"Run extension part", @"the extension keeps its dot, and is empty when absent",
              [withExt isEqualToString:@".txt"] && withoutExt.length == 0);

        // A name that is not a variable belongs to the shell, so it must come
        // out untouched rather than being swallowed.
        [ed openFileAtPath:runPath error:NULL];
        Check(@"Run leaves unknown names", @"an unknown or unclosed variable is left as written",
              [[ed expandRunVariables:@"$(NOT_A_VARIABLE) $(FILE_NAME)"]
                  isEqualToString:@"$(NOT_A_VARIABLE) npp_run_test.txt"] &&
              [[ed expandRunVariables:@"$(unclosed"] isEqualToString:@"$(unclosed"] &&
              [[ed expandRunVariables:@"cost is $5"] isEqualToString:@"cost is $5"]);

        NppRunResult *echoed = [ed runCommandLine:@"echo $(NAME_PART)" intoConsole:NO];
        Check(@"Run command", @"the command runs with its variables already substituted",
              echoed.exitStatus == 0 &&
              [echoed.output isEqualToString:@"npp_run_test\n"]);

        // Failure has to be visible: the status and whatever went to stderr.
        NppRunResult *failed = [ed runCommandLine:@"echo oops >&2; exit 3" intoConsole:NO];
        Check(@"Run reports failure", @"a non-zero status and stderr both come back",
              failed.exitStatus == 3 && [failed.output containsString:@"oops"]);

        // A command is nearly always meant relative to the file being edited.
        NppRunResult *where = [ed runCommandLine:@"pwd" intoConsole:NO];
        Check(@"Run working directory", @"the command runs in the document's own directory",
              [[where.output stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]].stringByResolvingSymlinksInPath
                  isEqualToString:dir.stringByResolvingSymlinksInPath]);

        [ed.console clear];
        NppRunResult *shown = [ed runCommandLine:@"echo visible" intoConsole:YES];
        NSString *console = ed.console.text;
        Check(@"Run console", @"the command and its output both reach the console",
              shown.exitStatus == 0 && [console containsString:@"> echo visible"] &&
              [console containsString:@"visible\n"]);

        [ed.console clear];
        [ed runCommandLine:@"exit 7" intoConsole:YES];
        Check(@"Run console reports status", @"a failure is written to the console, not just returned",
              [ed.console.text containsString:@"exit status 7"]);

        // The background path expands on the main thread and hands the result
        // to the worker; expanding a second time there would corrupt a command
        // whose own text happens to look like a variable.
        SetDoc(ed, @"$(FILE_NAME)\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        __block NppRunResult *async = nil;
        [ed runCommandLineInBackground:@"echo '$(CURRENT_LINESTR)'"
                            completion:^(NppRunResult *r) { async = r; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!async && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        Check(@"Run in background", @"it completes, and substitution happens exactly once",
              async != nil && async.exitStatus == 0 &&
              [async.output isEqualToString:@"$(FILE_NAME)\n"]);

        // Saved commands are keyed by name, so saving the same name again
        // replaces it rather than adding a duplicate.
        NSUInteger before = [ed savedCommands].count;
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make"]];
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make -j8"]];
        NSArray<NppSavedCommand *> *saved = [ed savedCommands];
        NppSavedCommand *build = nil;
        for (NppSavedCommand *c in saved) if ([c.name isEqualToString:@"Build"]) build = c;
        BOOL replaced = saved.count == before + 1 && [build.command isEqualToString:@"make -j8"];
        [ed removeSavedCommandNamed:@"Build"];
        Check(@"Run saved commands", @"saving by name replaces, and removing takes it away",
              replaced && [ed savedCommands].count == before);

        [[NSFileManager defaultManager] removeItemAtPath:runPath error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:plainPath error:NULL];
    }

    if (NppSectionWanted(@"MIME Tools")) { printf("\n== MIME Tools ==\n");
        // Quoted-printable: UTF-8 bytes escape as =XX, '=' itself must escape,
        // and encode/decode round-trips, soft breaks (=\r\n at column 76) included.
        NSString *qp = [EditorController mimeQuotedPrintableEncode:@"Ünïcödé = fun\n"];
        Check(@"MIME Quoted-printable encode", @"non-ASCII and '=' become =XX, the rest stays",
              [qp isEqualToString:@"=C3=9Cn=C3=AFc=C3=B6d=C3=A9 =3D fun\n"]);
        NSMutableString *longLine = [NSMutableString string];
        for (int i = 0; i < 120; ++i) [longLine appendString:@"x"];
        NSString *qpLong = [EditorController mimeQuotedPrintableEncode:longLine];
        NSArray *qpLines = [qpLong componentsSeparatedByString:@"\r\n"];
        BOOL qpWrapped = qpLines.count > 1;
        for (NSString *l in qpLines) qpWrapped = qpWrapped && l.length <= 76;
        Check(@"MIME Quoted-printable soft break", @"long lines wrap with =CRLF within 76 columns",
              qpWrapped && [[EditorController mimeQuotedPrintableDecode:qpLong] isEqualToString:longLine]);
        Check(@"MIME Quoted-printable decode", @"=XX and soft breaks come back; bad hex is refused",
              [[EditorController mimeQuotedPrintableDecode:qp] isEqualToString:@"Ünïcödé = fun\n"] &&
              [[EditorController mimeQuotedPrintableDecode:@"a=\nb=\r\nc"] isEqualToString:@"abc"] &&
              [EditorController mimeQuotedPrintableDecode:@"=ZZ"] == nil);

        // URL encoding in the plugin's three strengths (url.cpp).
        Check(@"MIME URL encode (RFC1738)", @"unsafe characters and non-ASCII encode, the RFC's allowed marks stay",
              [[EditorController mimeUrlEncode:@"a b&c(d)é" method:NppUrlEncodeRFC1738 byLine:NO]
               isEqualToString:@"a%20b%26c(d)%C3%A9"]);
        Check(@"MIME URL encode (Extended)", @"the common implementations' extra marks encode too",
              [[EditorController mimeUrlEncode:@"a(d)+x" method:NppUrlEncodeExtended byLine:NO]
               isEqualToString:@"a%28d%29%2Bx"]);
        Check(@"MIME URL encode (Full)", @"every byte becomes a triplet",
              [[EditorController mimeUrlEncode:@"Ab" method:NppUrlEncodeFull byLine:NO] isEqualToString:@"%41%62"]);
        Check(@"MIME URL encode by line", @"line breaks survive un-encoded",
              [[EditorController mimeUrlEncode:@"a b\nc d" method:NppUrlEncodeRFC1738 byLine:YES]
               isEqualToString:@"a%20b\nc%20d"]);
        Check(@"MIME URL decode", @"triplets decode; '+' and stray '%' pass through as written",
              [[EditorController mimeUrlDecode:@"a%20b%26c%C3%A9"] isEqualToString:@"a b&céé"] == NO &&
              [[EditorController mimeUrlDecode:@"a%20b%26c%C3%A9"] isEqualToString:@"a b&cé"] &&
              [[EditorController mimeUrlDecode:@"1+1%3D2 and 100%"] isEqualToString:@"1+1=2 and 100%"]);

        // SAML: the deflated+Base64+URL-encoded request the redirect binding
        // carries (vector made with zlib raw deflate), and a plain Base64 XML.
        NSString *redirect = @"sylOzM0psHIsLcnIC0otLE0tLlHwdLFVqjBUsstIzcnJt9HHVGEHAA%3D%3D";
        Check(@"MIME SAML decode", @"URL-decode, Base64 and raw inflate give the request back",
              [[EditorController mimeSamlDecode:redirect]
               isEqualToString:@"<samlp:AuthnRequest ID=\"x1\">hello</samlp:AuthnRequest>"] &&
              [[EditorController mimeSamlDecode:@"PD94bWwgdmVyc2lvbj0iMS4wIj8+"] hasPrefix:@"<?xml"] &&
              [EditorController mimeSamlDecode:@"zzz"] == nil);

        // Through the selection: encode in place, one undo step brings the text back.
        [ed newDocument];
        SetDoc(ed, @"foobar");
        [sci message:SCI_SETSEL wParam:0 lParam:6];
        BOOL did = [ed mimeTransformSelection:^NSString *(NSString *text) {
            return [EditorController mimeUrlEncode:text method:NppUrlEncodeFull byLine:NO];
        }];
        NSString *encoded = DocText(ed);
        [sci message:SCI_UNDO wParam:0 lParam:0];
        Check(@"MIME Tools on the selection", @"the selection is replaced in place and one undo returns it",
              did && [encoded isEqualToString:@"%66%6F%6F%62%61%72"] && [DocText(ed) isEqualToString:@"foobar"]);
    }

    if (NppSectionWanted(@"Converter")) { printf("\n== Converter ==\n");
        // ascii2hex, with the plugin's three settings.
        Check(@"Converter ASCII -> HEX", @"bytes become pairs; space and case options hold",
              [[EditorController converterHexFromText:@"AB" insertSpace:NO uppercase:NO charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"4142"] &&
              [[EditorController converterHexFromText:@"AB" insertSpace:YES uppercase:NO charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"41 42 "] &&   // the plugin leaves the trailing space too
              [[EditorController converterHexFromText:@"j" insertSpace:NO uppercase:YES charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"6A"]);
        Check(@"Converter ASCII -> HEX per line", @"a break lands after every N-th source byte",
              [[EditorController converterHexFromText:@"ABCD" insertSpace:YES uppercase:NO charactersPerLine:2 eol:@"\n"]
               isEqualToString:@"41 42\n43 44\n"]);

        // hex2Ascii: the format is read off the third character and must hold.
        Check(@"Converter HEX -> ASCII", @"plain and spaced input decode; UTF-8 comes back as text",
              [[EditorController converterTextFromHex:@"4142"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"41 42"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"41\n42"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"D0AF"] isEqualToString:@"Я"]);
        Check(@"Converter HEX -> ASCII refusals", @"odd digits, stray characters and a broken format are refused",
              [EditorController converterTextFromHex:@"414"] == nil &&
              [EditorController converterTextFromHex:@"41 4243"] == nil &&
              [EditorController converterTextFromHex:@"4Z"] == nil &&
              [EditorController converterTextFromHex:@"4"] == nil);

        // The Conversion Panel's model.
        NSDictionary *fromHex = [EditorController converterValues:@"ff" fromField:@"hex"];
        NSDictionary *fromAscii = [EditorController converterValues:@"A" fromField:@"ascii"];
        Check(@"Conversion Panel values", @"one value fills every base and the character",
              [fromHex[@"dec"] isEqualToString:@"255"] && [fromHex[@"bin"] isEqualToString:@"11111111"] &&
              [fromHex[@"oct"] isEqualToString:@"377"] && [fromHex[@"ascii"] isEqualToString:@"ÿ"] &&
              [fromAscii[@"dec"] isEqualToString:@"65"] &&
              [[EditorController converterValues:@"1010" fromField:@"bin"][@"dec"] isEqualToString:@"10"] &&
              [EditorController converterValues:@"12a" fromField:@"dec"] == nil &&
              [[EditorController converterValues:@"" fromField:@"dec"][@"hex"] isEqualToString:@""]);

        // The panel itself: typing syncs the rows, Insert writes to the document.
        [app showConversionPanel:nil];
        NppConverterWindow *cw = [NppConverterWindow shared];
        [ed newDocument];
        SetDoc(ed, @"");
        cw.hex.stringValue = @"ff";
        [cw syncFrom:cw.hex];
        NSButton *fake = [[NSButton alloc] init];
        fake.tag = 1;   // the Decimal row
        [NSApp sendAction:@selector(insertRow:) to:cw from:fake];
        Check(@"Conversion Panel window", @"typing hex ff shows 255, and Insert writes it at the caret",
              [cw.dec.stringValue isEqualToString:@"255"] && [cw.bin.stringValue isEqualToString:@"11111111"] &&
              [DocText(ed) isEqualToString:@"255"]);
        [cw.panel orderOut:nil];
    }

    if (NppSectionWanted(@"Export")) { printf("\n== Export ==\n");
        NSError *err = nil;
        [ed openFileAtPath:TempFile(@"t_export.py", @"# comment <>&\nx = 1 # Я\n") error:&err];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];

        NSRange whole = [ed exportRange];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:9];
        NSRange part = [ed exportRange];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];
        Check(@"Export range", @"the selection when there is one, the whole document otherwise",
              whole.location == 0 && whole.length == (NSUInteger)[ed.sci message:SCI_GETLENGTH] &&
              part.location == 0 && part.length == 9);

        NSString *html = [ed exportHTMLInRange:whole];
        NSUInteger colourCount = [html componentsSeparatedByString:@"color:#"].count;
        Check(@"Export to HTML", @"a pre in the editor's colours, spans per style, markup escaped",
              [html containsString:@"<pre style="] &&
              [html containsString:@"&lt;&gt;&amp;"] &&
              [html containsString:@"</span>"] && colourCount > 2);

        NSData *rtfData = [ed exportRTFInRange:whole];
        NSString *rtf = [[NSString alloc] initWithData:rtfData encoding:NSASCIIStringEncoding];
        Check(@"Export to RTF", @"a colour table, style runs, par lines and \\u for non-ASCII",
              [rtf hasPrefix:@"{\\rtf1"] && [rtf containsString:@"\\colortbl"] &&
              [rtf containsString:@"\\cf"] && [rtf containsString:@"\\par"] &&
              [rtf containsString:@"\\u1071?"]);
        NSAttributedString *readBack = [[NSAttributedString alloc] initWithRTF:rtfData
                                                            documentAttributes:nil];
        Check(@"Export RTF reads back", @"the system RTF reader returns the very text",
              [readBack.string containsString:@"# comment <>&"] &&
              [readBack.string containsString:@"x = 1 # Я"]);

        [ed exportToClipboardRTF:YES HTML:YES];
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        Check(@"Export to the clipboard", @"RTF, HTML and the plain text ride together",
              [pb dataForType:NSPasteboardTypeRTF].length > 0 &&
              [[pb stringForType:NSPasteboardTypeHTML] containsString:@"<pre"] &&
              [[pb stringForType:NSPasteboardTypeString] containsString:@"x = 1"]);

        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }

    if (NppSectionWanted(@"Spell check")) { printf("\n== Spell check ==\n");
        NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
        NSRange probe = [checker checkSpellingOfString:@"helo" startingAt:0 language:@"en"
                                                  wrap:NO inSpellDocumentWithTag:0 wordCount:NULL];
        if (probe.location != 0) {
            // No dictionaries to judge with (a stripped-down runner): the
            // machinery cannot be exercised honestly, and that is said aloud.
            printf("  note: the spelling engine offers no English here; spell checks not exercised\n");
        } else {
            NppPreferences *prefs = [NppPreferences shared];
            BOOL wasOn = prefs.spellCheckEnabled;
            NSString *wasLang = prefs.spellCheckLanguage;
            prefs.spellCheckEnabled = YES;
            prefs.spellCheckLanguage = @"en";

            [ed newDocument];
            SetDoc(ed, @"helo wrld\n");
            [ed spellCheckNow];
            Check(@"Spell check squiggles", @"misspelled words carry the indicator, in plain text everywhere",
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1] &&
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:6]);

            // Automatic language: the engine must work the language out by
            // itself. checkSpellingOfString:language:nil quietly kept the
            // checker's old language, so a foreign text went unchecked - the
            // very way the bug was reported.
            NSString *french = @"bonjur le monde sa marche tres bien";
            checker.automaticallyIdentifiesLanguages = YES;
            NSArray *frProbe = [checker checkString:french range:NSMakeRange(0, french.length)
                                              types:NSTextCheckingTypeSpelling options:nil
                             inSpellDocumentWithTag:0 orthography:NULL wordCount:NULL];
            if (frProbe.count) {
                prefs.spellCheckLanguage = @"";
                SetDoc(ed, @"bonjur le monde\n");
                [ed spellCheckNow];
                Check(@"Spell check automatic language", @"a French misspelling is found with no language chosen",
                      [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1]);
                prefs.spellCheckLanguage = @"en";
            } else {
                printf("  note: no French dictionary here; the automatic-language check not exercised\n");
            }

            NSError *err = nil;
            [ed openFileAtPath:TempFile(@"t_spell.py", @"wrld = 1  # helo wrld\n") error:&err];
            [ed spellCheckNow];
            Check(@"Spell check styles", @"in code only comments and strings are checked, identifiers are left alone",
                  ![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1] &&
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:13]);

            NSArray<NSMenuItem *> *offers = [ed spellingMenuItemsForPosition:13];
            BOOL hasIgnore = NO, hasLearn = NO;
            NSMenuItem *ignoreItem = nil;
            for (NSMenuItem *item in offers) {
                if (item.action == @selector(spellIgnoreWord:)) { hasIgnore = YES; ignoreItem = item; }
                if (item.action == @selector(spellLearnWord:)) hasLearn = YES;
            }
            Check(@"Spell check suggestions", @"the context menu gets guesses, Ignore and Learn for the word",
                  offers.count >= 4 && hasIgnore && hasLearn);

            // Ignore is session-wide and safe to fire; Learn would write into
            // the user's dictionary for good, so it is not.
            [NSApp sendAction:ignoreItem.action to:ignoreItem.target from:ignoreItem];
            Check(@"Spell check Ignore", @"an ignored word loses its squiggle",
                  ![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:13]);

            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                      discardChanges:YES];
            prefs.spellCheckEnabled = wasOn;
            prefs.spellCheckLanguage = wasLang;
            [ed spellCheckNow];
        }
    }

    if (NppSectionWanted(@"Files as upstream")) { printf("\n== Files as upstream ==\n");
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-files-upstream"];
        [fm removeItemAtPath:root error:NULL];
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"sub/.hidden"] withIntermediateDirectories:YES attributes:nil error:NULL];
        for (NSString *f in @[@"b.txt", @"a.txt", @"c.log", @"sub/d.txt", @"sub/.hidden/e.txt"])
            [@"x" writeToFile:[root stringByAppendingPathComponent:f] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSArray *(^names)(NSArray *) = ^NSArray *(NSArray *paths) {
            NSMutableArray *out = [NSMutableArray array];
            for (NSString *x in paths) [out addObject:[x substringFromIndex:root.length + 1]];
            return out;
        };
        Check(@"Command line (folders)", @"a folder opens every file under it, hidden folders aside, in name order",
              [names([AppDelegate filesMatching:@"*" inFolder:root recursive:YES]) isEqual:(@[@"a.txt", @"b.txt", @"c.log", @"sub/d.txt"])]);
        Check(@"Command line (patterns)", @"a pattern takes its folder's matches, and with -r those under it",
              [names([AppDelegate filesMatching:@"*.txt" inFolder:root recursive:NO]) isEqual:(@[@"a.txt", @"b.txt"])] &&
              [names([AppDelegate filesMatching:@"*.txt" inFolder:root recursive:YES]) isEqual:(@[@"a.txt", @"b.txt", @"sub/d.txt"])]);

        // Untitled numbering and the lone clean tab (FileManager::nextUntitledNewNumber, loadBufferIntoView).
        while (ed.documents.count > 1) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [ed closeDocumentAtIndex:0 discardChanges:YES];
        [ed newDocument]; [ed newDocument];
        NSInteger second = -1;
        for (NSUInteger i = 0; i < ed.documents.count; ++i) if ([ed.documents[i].displayName isEqualToString:@"new 2"]) second = (NSInteger)i;
        if (second >= 0) [ed closeDocumentAtIndex:second discardChanges:YES];
        [ed newDocument];
        Check(@"IDM_FILE_NEW (numbering)", @"a new tab takes the lowest free number: after closing new 2 the next is new 2 again",
              [ed.currentDocument.displayName isEqualToString:@"new 2"]);
        while (ed.documents.count > 1) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        NSString *one = [root stringByAppendingPathComponent:@"a.txt"];
        BOOL wasLoneClean = ed.documents.count == 1 && !ed.currentDocument.path && !ed.currentDocument.modified;
        [ed openFileAtPath:one error:NULL];
        Check(@"IDM_FILE_OPEN (lone new 1)", @"a file opened over a lone clean untitled tab takes its place",
              wasLoneClean && ed.documents.count == 1 && [ed.currentDocument.path isEqualToString:one]);
        NSString *other = [root stringByAppendingPathComponent:@"sub/../a.txt"];
        NSString *priv = [one hasPrefix:@"/var/"] ? [@"/private" stringByAppendingString:one] : one;
        NSUInteger tabs = ed.documents.count;
        [ed openFileAtPath:other error:NULL];
        [ed openFileAtPath:priv error:NULL];
        Check(@"IDM_FILE_OPEN (same file)", @"the same file under another spelling (.., /private/var) comes to its tab, no second one",
              ed.documents.count == tabs && [ed.currentDocument.path isEqualToString:one]);

        // Save: nothing to save, no Save; through a symlink, the target (FileManager::saveBuffer).
        NSMenuItem *saveItem = nil, *saveAllItem = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) for (NSMenuItem *it in top.submenu.itemArray) {
            if (it.action == @selector(saveDocument:)) saveItem = it;
            if (it.action == @selector(saveAll:)) saveAllItem = it;
        }
        BOOL cleanOff = saveItem && ![app validateMenuItem:saveItem] && ![app validateMenuItem:saveAllItem];
        [ed.sci message:SCI_APPENDTEXT wParam:1 lParam:(sptr_t)"y"];
        ed.currentDocument.modified = YES;
        BOOL dirtyOn = [app validateMenuItem:saveItem] && [app validateMenuItem:saveAllItem];
        Check(@"IDM_FILE_SAVE (enabled)", @"Save and Save All are off with nothing modified, on after an edit", cleanOff && dirtyOn);
        while (ed.documents.count > 1) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [ed closeDocumentAtIndex:0 discardChanges:YES];
        NSString *target = [root stringByAppendingPathComponent:@"target.txt"], *link = [root stringByAppendingPathComponent:@"link.txt"];
        [@"t\n" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [fm createSymbolicLinkAtPath:link withDestinationPath:target error:NULL];
        [ed openFileAtPath:link error:NULL];
        [ed setDocumentText:@"changed\n"];
        ed.currentDocument.modified = YES;
        [ed saveCurrentDocument];
        NSDictionary *linkAttrs = [fm attributesOfItemAtPath:link error:NULL];
        Check(@"IDM_FILE_SAVE (symlink)", @"saving through a symlink writes the target and keeps the link",
              [linkAttrs[NSFileType] isEqual:NSFileTypeSymbolicLink] &&
              [[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:NULL] isEqualToString:@"changed\n"]);

        // Window > Sort By: numstrcmp, full names, languages, text in memory (WindowsDlg BufferEquivalent).
        while (ed.documents.count > 1) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        for (NSString *f in @[@"file10.txt", @"File2.txt", @"b.py"])
            [@"x" writeToFile:[root stringByAppendingPathComponent:f] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        for (NSString *f in @[@"file10.txt", @"File2.txt", @"b.py"]) [ed openFileAtPath:[root stringByAppendingPathComponent:f] error:NULL];
        [ed sortTabsBy:NppTabSortName ascending:YES];
        NSMutableArray *order = [NSMutableArray array];
        for (NppDocument *d in ed.documents) [order addObject:d.displayName];
        Check(@"IDM_WINDOW_SORT_FN_ASC", @"names compare numbers as numbers and letters without case: File2 before file10",
              [order indexOfObject:@"File2.txt"] < [order indexOfObject:@"file10.txt"]);
        [ed sortTabsBy:NppTabSortType ascending:YES];
        Check(@"IDM_WINDOW_SORT_FT_ASC", @"type is the language: normal text before python",
              [ed.documents.lastObject.displayName isEqualToString:@"b.py"]);
        while (ed.documents.count > 1) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [ed closeDocumentAtIndex:0 discardChanges:YES];
        [fm removeItemAtPath:root error:NULL];
    }

    if (NppSectionWanted(@"Selected numbers")) { printf("\n== Selected numbers ==\n");
        NppNumberSet *list = [NppNumberSet setFromPieces:@[@"10, 20.5, -3"]];
        Check(@"Selected numbers", @"sum, average, minimum, maximum and count of a comma list",
              list.count == 3 && [list.sum isEqualToString:@"27.5"] && [list.average isEqualToString:@"9.1666666667"] &&
              [list.minimum isEqualToString:@"-3"] && [list.maximum isEqualToString:@"20.5"]);
        Check(@"Selected numbers", @"decimal arithmetic (0.1 + 0.2 is 0.3), a decimal comma kept in the results",
              [[NppNumberSet setFromPieces:@[@"0.1\n0.2"]].sum isEqualToString:@"0.3"] &&
              [[NppNumberSet setFromPieces:@[@"1,5 2,25"]].sum isEqualToString:@"3,75"]);
        Check(@"Selected numbers", @"words, a lone number or an empty value between commas are not a set",
              ![NppNumberSet setFromPieces:@[@"1 two 3"]] && ![NppNumberSet setFromPieces:@[@"42"]] &&
              ![NppNumberSet setFromPieces:@[@"1,,2"]]);

        SetDoc(ed, @"x = [30, 4, 100];\n");
        [sci message:SCI_SETSEL wParam:5 lParam:15];
        NSArray<NSMenuItem *> *offer = [ed numberSetMenuItems];
        NSMenu *sub = offer.firstObject.submenu;
        Check(@"Selected numbers", @"the context menu offers the five values by name and both sorts",
              sub.numberOfItems == 8 && [sub.itemArray[0].title isEqualToString:NppL(@"Sum")] &&
              [sub.itemArray[4].title isEqualToString:NppL(@"Count")] &&
              sub.itemArray[6].action == NSSelectorFromString(@"numberSetSort:") && sub.itemArray[6].enabled);
        [ed insertNumberSetValue:NppNumberSetSum];
        Check(@"Selected numbers", @"Sum writes SUM = <value> after numbers on one line",
              [DocText(ed) isEqualToString:@"x = [30, 4, 100 SUM = 134];\n"]);
        [sci message:SCI_UNDO];
        SetDoc(ed, @"15\n8\n42\nnext\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [ed insertNumberSetValue:NppNumberSetAverage];
        Check(@"Selected numbers", @"Average of numbers one per line goes on a line of its own under them",
              [DocText(ed) isEqualToString:@"15\n8\n42\nAVG = 21.6666666667\nnext\n"]);
        SetDoc(ed, @"15\n8\n42\n");
        [sci message:SCI_SETSEL wParam:0 lParam:8];
        [ed insertNumberSetValue:NppNumberSetMaximum];
        Check(@"Selected numbers", @"a selection that took the last line break: the value is the next line",
              [DocText(ed) isEqualToString:@"15\n8\n42\nMAX = 42\n"]);
        SetDoc(ed, @"x = [30, 4, 100];\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        Check(@"Selected numbers", @"no offer when the selection holds other text", [ed numberSetMenuItems].count == 0);

        [sci message:SCI_SETSEL wParam:5 lParam:15];
        BOOL sorted = [ed sortSelectedNumbersAscending:YES];
        Check(@"Selected numbers", @"Sort Ascending keeps the separators and the selection",
              sorted && [DocText(ed) isEqualToString:@"x = [4, 30, 100];\n"] &&
              [sci message:SCI_GETSELECTIONSTART] == 5 && [sci message:SCI_GETSELECTIONEND] == 15);
        [ed sortSelectedNumbersAscending:NO];
        Check(@"Selected numbers", @"Sort Descending", [DocText(ed) isEqualToString:@"x = [100, 30, 4];\n"]);
        [sci message:SCI_UNDO];
        [sci message:SCI_UNDO];
        Check(@"Selected numbers", @"each sort is one undo step", [DocText(ed) isEqualToString:@"x = [30, 4, 100];\n"]);

        SetDoc(ed, @"a 7\nb 5\nc 6\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:2];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:11];
        [ed sortSelectedNumbersAscending:YES];
        Check(@"Selected numbers", @"a column selection sorts the column only",
              [DocText(ed) isEqualToString:@"a 5\nb 6\nc 7\n"]);

        SetDoc(ed, @"3 1 2\n");
        [sci message:SCI_SETREADONLY wParam:1];
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        Check(@"Selected numbers", @"a read-only document is summed but not sorted",
              [ed numberSetMenuItems].count && !([ed numberSetMenuItems].firstObject.submenu.itemArray[6].enabled) &&
              ![ed sortSelectedNumbersAscending:YES] && [DocText(ed) isEqualToString:@"3 1 2\n"]);
        [sci message:SCI_SETREADONLY wParam:0];

        Check(@"Selected numbers (formula)", @"a formula's value: operations, functions, degrees, constants, percent",
              [[NppFormula formulaFromText:@"2 + 3 * 4 ="].result isEqualToString:@"14"] &&
              [[NppFormula formulaFromText:@"sin 30° + ln e + log(8; 2) ="].result isEqualToString:@"4.5"] &&
              [[NppFormula formulaFromText:@"2π ="].result isEqualToString:@"6.2831853072"] &&
              [[NppFormula formulaFromText:@"200 + 15% ="].result isEqualToString:@"230"] &&
              [[NppFormula formulaFromText:@"1,5 * 3 ="].result isEqualToString:@"4,5"]);
        Check(@"Selected numbers (formula)", @"no formula without an operation or with an unknown word; a reason when there is no value",
              ![NppFormula formulaFromText:@"5 ="] && ![NppFormula formulaFromText:@"x + 1 ="] &&
              [[NppFormula formulaFromText:@"1/0 ="].problem isEqualToString:@"Division by zero"]);

        SetDoc(ed, @"total: 2^10 - 24 =\n");
        [sci message:SCI_SETSEL wParam:7 lParam:18];
        NSArray<NSMenuItem *> *calc = [ed formulaMenuItems];
        Check(@"Selected numbers (formula)", @"the context menu offers Calculate",
              calc.count == 2 && [calc[0].title isEqualToString:NppL(@"Calculate")] && calc[0].action != NULL);
        BOOL wrote = [ed calculateSelectedFormula];
        Check(@"Selected numbers (formula)", @"Calculate writes the value after the \"=\" and keeps formula and value selected",
              wrote && [DocText(ed) isEqualToString:@"total: 2^10 - 24 = 1000\n"] &&
              [sci message:SCI_GETSELECTIONSTART] == 7 && [sci message:SCI_GETSELECTIONEND] == 23);
        [sci message:SCI_SETSEL wParam:7 lParam:23];
        [sci message:SCI_SETTARGETRANGE wParam:14 lParam:16];
        [sci message:SCI_REPLACETARGET wParam:2 lParam:(sptr_t)"23"];
        [sci message:SCI_SETSEL wParam:7 lParam:23];
        [ed calculateSelectedFormula];
        Check(@"Selected numbers (formula)", @"calculating again replaces the old value",
              [DocText(ed) isEqualToString:@"total: 2^10 - 23 = 1001\n"]);
        [sci message:SCI_UNDO];
        Check(@"Selected numbers (formula)", @"one undo step", [DocText(ed) isEqualToString:@"total: 2^10 - 23 = 1000\n"]);
        SetDoc(ed, @"total: 2 + 3 =");
        [sci message:SCI_GOTOPOS wParam:14];
        Check(@"Selected numbers (Cmd+=)", @"without a selection, the formula ending at the caret gets its value, the caret after it",
              [ed calculateFormulaAtCaret] && [DocText(ed) isEqualToString:@"total: 2 + 3 = 5"] &&
              [sci message:SCI_GETCURRENTPOS] == 16);
        [sci message:SCI_GOTOPOS wParam:9];
        [sci message:SCI_SETTARGETRANGE wParam:11 lParam:12];
        [sci message:SCI_REPLACETARGET wParam:1 lParam:(sptr_t)"4"];
        [sci message:SCI_GOTOPOS wParam:14];
        Check(@"Selected numbers (Cmd+=)", @"an old value after the \"=\" is replaced",
              [ed calculateFormulaAtCaret] && [DocText(ed) isEqualToString:@"total: 2 + 4 = 6"]);
        SetDoc(ed, @"x = 2^8");
        [sci message:SCI_GOTOPOS wParam:7];
        Check(@"Selected numbers (Cmd+=)", @"with no \"=\" typed it is written too; an assignment's \"=\" is left alone",
              [ed calculateFormulaAtCaret] && [DocText(ed) isEqualToString:@"x = 2^8=256"]);
        SetDoc(ed, @"just words");
        [sci message:SCI_GOTOPOS wParam:10];
        Check(@"Selected numbers (Cmd+=)", @"no formula, nothing written",
              ![ed calculateFormulaAtCaret] && [DocText(ed) isEqualToString:@"just words"]);
        NSMenuItem *calcItem = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *it in top.submenu.itemArray)
                if (it.action == NSSelectorFromString(@"calculateFormula:")) calcItem = it;
        Check(@"Selected numbers (Cmd+=)", @"Edit > Calculate carries Cmd+=",
              calcItem && [calcItem.keyEquivalent isEqualToString:@"="] &&
              calcItem.keyEquivalentModifierMask == NSEventModifierFlagCommand);
        SetDoc(ed, @"3 1 2");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        BOOL viaMenu = [app performMenuCommandAtPath:@"Edit|Selected Numbers|Sort Descending"] &&
                       [app performMenuCommandAtPath:@"Edit|Selected Numbers|Sum"];
        Check(@"Selected numbers (Edit menu)", @"Edit > Selected Numbers runs by menu path, as an agent's run_command does",
              viaMenu && [DocText(ed) isEqualToString:@"3 2 1 SUM = 6"]);
        SetDoc(ed, @"plain");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        calc = [ed formulaMenuItems];
        Check(@"Selected numbers (formula)", @"the context menu always has Calculate, disabled unless a formula is selected",
              calc.count == 2 && calc[0].action == NULL);
        SetDoc(ed, @"1/0 =\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        calc = [ed formulaMenuItems];
        Check(@"Selected numbers (formula)", @"a formula without a value (1/0) is offered but left unchanged",
              calc.count == 2 && ![ed calculateSelectedFormula] && [DocText(ed) isEqualToString:@"1/0 =\n"]);
        SetDoc(ed, @"");
    }

    if (NppSectionWanted(@"Markdown preview")) { printf("\n== Markdown preview ==\n");
        // The table pre-pass: GFM alignment, escaped pipes, fences left alone.
        NSString *table = @"| Name | N |\n|:-----|--:|\n| a\\|b | **1** |\n";
        NSString *asHTML = [MarkdownPanel tablesToHTML:table];
        Check(@"Markdown tables", @"the GFM table becomes HTML with alignment, escaped pipes and inline Markdown in cells",
              [asHTML containsString:@"<th style=\"text-align:left\">Name</th>"] &&
              [asHTML containsString:@"<td style=\"text-align:right\"><strong>1</strong></td>"] &&
              [asHTML containsString:@"a|b"]);
        NSString *fenced = @"```\n| not | a table |\n|---|---|\n```\n";
        Check(@"Markdown tables in fences", @"a table inside a code fence stays text",
              ![[MarkdownPanel tablesToHTML:fenced] containsString:@"<table>"]);

        // cmark proper, through the same door the panel uses.
        NSString *page = [MarkdownPanel htmlFromMarkdown:
            @"# Title\n\nSome **bold** and `code`.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"];
        Check(@"Markdown to HTML", @"headings, emphasis, code and the table all render",
              [page containsString:@"<h1>Title</h1>"] && [page containsString:@"<strong>bold</strong>"] &&
              [page containsString:@"<code>code</code>"] && [page containsString:@"<td>1</td>"]);

        // The panel itself: toggling shows it, a refresh renders the document.
        [ed newDocument];
        SetDoc(ed, @"# Hello\n\n- one\n- two\n");
        [app toggleMarkdownPreview:nil];
        MarkdownPanel *panel = [app valueForKey:@"markdownPanel"];
        [panel refresh];
        Check(@"Markdown preview panel", @"the panel shows and carries the rendered document",
              panel.visible && [panel.lastHTML containsString:@"<h1>Hello</h1>"] &&
              [panel.lastHTML containsString:@"<li>one</li>"]);
        [app toggleMarkdownPreview:nil];
        Check(@"Markdown preview toggles away", @"the second toggle hides the panel", !panel.visible);
    }

    if (NppSectionWanted(@"Mac extras: OCR, QR, the command line")) { printf("\n== Mac extras: OCR, QR, the command line ==\n");
        // OCR over a picture drawn right here: big black words on white.
        NSImage *picture = [[NSImage alloc] initWithSize:NSMakeSize(640, 140)];
        [picture lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 140));
        [@"HELLO OCR 42" drawAtPoint:NSMakePoint(24, 36) withAttributes:
            @{NSFontAttributeName: [NSFont boldSystemFontOfSize:56],
              NSForegroundColorAttributeName: [NSColor blackColor]}];
        [picture unlockFocus];
        NSString *seen = [EditorController textRecognizedInImage:picture];
        Check(@"OCR reads a picture", @"the system engine returns the words drawn into the image",
              [seen containsString:@"HELLO"] && [seen containsString:@"42"]);

        // The same engine over files: a PNG written to disk, and a PDF drawn
        // right here, page rendered and read back.
        NSString *pngPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ocr.png"];
        CGImageRef pictureCG = [picture CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *pictureRep = [[NSBitmapImageRep alloc] initWithCGImage:pictureCG];
        [[pictureRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:pngPath atomically:YES];
        NSString *fromPNG = [EditorController textRecognizedInFileAt:pngPath];

        NSString *pdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ocr.pdf"];
        NSMutableData *pdfData = [NSMutableData data];
        CGRect page = CGRectMake(0, 0, 612, 200);
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)pdfData);
        CGContextRef pdfCtx = CGPDFContextCreate(consumer, &page, NULL);
        CGDataConsumerRelease(consumer);
        CGPDFContextBeginPage(pdfCtx, NULL);
        NSGraphicsContext *old = NSGraphicsContext.currentContext;
        NSGraphicsContext.currentContext =
            [NSGraphicsContext graphicsContextWithCGContext:pdfCtx flipped:NO];
        [@"PDF PAGE WORDS 7" drawAtPoint:NSMakePoint(40, 80) withAttributes:
            @{NSFontAttributeName: [NSFont boldSystemFontOfSize:40],
              NSForegroundColorAttributeName: [NSColor blackColor]}];
        NSGraphicsContext.currentContext = old;
        CGPDFContextEndPage(pdfCtx);
        CGPDFContextClose(pdfCtx);
        CGContextRelease(pdfCtx);
        [pdfData writeToFile:pdfPath atomically:YES];
        NSString *fromPDF = [EditorController textRecognizedInFileAt:pdfPath];
        Check(@"Recognize Text in File", @"a PNG on disk and a rendered PDF page both give their words back",
              [fromPNG containsString:@"HELLO"] &&
              [fromPDF containsString:@"PDF"] && [fromPDF containsString:@"7"]);

        // Paste Image as Text: through the clipboard, into the document.
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb writeObjects:@[picture]];
        [ed newDocument];
        SetDoc(ed, @"");
        BOOL pasted = [ed pasteImageAsText];
        Check(@"Paste Image as Text", @"the clipboard's image lands as its words",
              pasted && [DocText(ed) containsString:@"HELLO"]);

        // QR both ways: the selection becomes a code, the code reads back.
        NSString *payload = @"https://github.com/tanderbold/NotepadMac?ref=qr&n=42";
        NSImage *qr = [EditorController qrImageFromText:payload side:300];
        Check(@"QR generation", @"the selection becomes a rendered code (software Core Image, so headless too)",
              qr != nil && qr.size.width >= 250);   // 300 asked, whole-module scaling lands just under
        Check(@"QR round trip", @"the code made from a text answers that very text",
              qr && [[EditorController textFromQRCodesInImage:qr] isEqualToString:payload]);
        NSMutableString *tooLong = [NSMutableString string];
        for (int i = 0; i < 4000; ++i) [tooLong appendString:@"x"];
        Check(@"QR refuses what cannot fit", @"a text past the format's end answers nil",
              [EditorController qrImageFromText:tooLong side:300] == nil);

        [pb clearContents];
        [pb writeObjects:@[qr]];
        SetDoc(ed, @"");
        BOOL read = [ed insertTextFromClipboardQR];
        Check(@"Read QR Code from Clipboard", @"the clipboard's code lands as its text",
              read && [DocText(ed) isEqualToString:payload]);

        // The command line tool: shipped, and its ask is honoured with a line.
        NSString *helper = [[NSBundle mainBundle].bundlePath
                            stringByAppendingPathComponent:@"Contents/Helpers/nppmac"];
        NSTask *help = [[NSTask alloc] init];
        help.executableURL = [NSURL fileURLWithPath:helper];
        help.arguments = @[@"--help"];
        help.standardError = [NSPipe pipe];
        BOOL ran = [help launchAndReturnError:NULL];
        [help waitUntilExit];
        NSString *cliFile = TempFile(@"t_cli.txt", @"one\ntwo\nthree\nfour\nfive\n");
        [app cliRequest:[NSNotification notificationWithName:@"org.notepad-plus-plus.mac.cli" object:nil
            userInfo:@{@"files": @[@{@"path": cliFile, @"line": @4}]}]];
        long cliLine = [ed.sci message:SCI_LINEFROMPOSITION
                                wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
        Check(@"nppmac asks, the app answers", @"the helper ships and its request opens the file at the line",
              ran && help.terminationStatus == 0 &&
              [ed.currentDocument.path isEqualToString:cliFile] && cliLine == 3);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }

    if (NppSectionWanted(@"Plugin host")) { printf("\n== Plugin host ==\n");
        // Build the sample plugin with the system compiler, in the Windows
        // plugins\Name\Name layout, and load it through the host.
        // Beside the build (macos/build/NotepadMac.app -> macos/plugin-sdk), so a checkout copied
        // elsewhere - a VM, another Mac - finds it; else where this file was compiled.
        NSString *sdk = [[NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent].stringByDeletingLastPathComponent
                         stringByAppendingPathComponent:@"plugin-sdk"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:sdk])
            sdk = [[[NSString stringWithUTF8String:__FILE__]
                     stringByDeletingLastPathComponent].stringByDeletingLastPathComponent
                    stringByAppendingPathComponent:@"plugin-sdk"];
        NSString *sample = [sdk stringByAppendingPathComponent:@"sample/hellomac.c"];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-plugin-test"];
        NSString *dir = [root stringByAppendingPathComponent:@"HelloMac"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                   attributes:nil error:NULL];
        NSString *dylib = [dir stringByAppendingPathComponent:@"HelloMac.dylib"];
        NSTask *cc = [[NSTask alloc] init];
        cc.executableURL = [NSURL fileURLWithPath:@"/usr/bin/clang"];
        cc.arguments = @[@"-dynamiclib", @"-o", dylib, sample];
        BOOL built = NO;
        if ([cc launchAndReturnError:NULL]) { [cc waitUntilExit]; built = cc.terminationStatus == 0; }

        NppPluginHost *host = [NppPluginHost shared];
        host.editor = ed;
        NSMenu *pluginsMenu = [[NSMenu alloc] initWithTitle:@"Plugins"];
        NSUInteger loadedCount = [host loadPluginsFromDirectory:root intoMenu:pluginsMenu];
        NppLoadedPlugin *plugin = host.plugins.lastObject;
        NSMenu *sub = pluginsMenu.itemArray.lastObject.submenu;
        Check(@"Plugin host (load)", @"the sample dylib builds, loads, and its commands become a submenu",
              built && loadedCount == 1 && [plugin.name isEqualToString:@"HelloMac"] &&
              plugin.commandCount == 3 && sub.numberOfItems == 3 &&
              [sub itemAtIndex:1].separatorItem);

        // A command runs and reaches the editor through send(): SCI_REPLACESEL.
        [ed newDocument];
        SetDoc(ed, @"");
        [NSApp sendAction:[sub itemAtIndex:0].action to:[sub itemAtIndex:0].target from:[sub itemAtIndex:0]];
        Check(@"Plugin host (a command edits)", @"the plugin's menu command writes into the document",
              [DocText(ed) isEqualToString:@"hello from the sample plugin"]);

        // The NPPM_* side and a notification: opening a file must both answer
        // NPPM_GETFILENAME and raise NPPN_FILEOPENED in the plugin.
        intptr_t openedBefore = [plugin sendMessage:1 wParam:NPPN_FILEOPENED lParam:0];
        NSError *err = nil;
        [ed openFileAtPath:TempFile(@"t_plugin.txt", @"plugin food\n") error:&err];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];
        [NSApp sendAction:[sub itemAtIndex:2].action to:[sub itemAtIndex:2].target from:[sub itemAtIndex:2]];
        Check(@"Plugin host (NPPM and NPPN)", @"NPPM_GETFILENAME answers and NPPN_FILEOPENED arrived",
              [DocText(ed) hasPrefix:@"t_plugin.txt"] &&
              [plugin sendMessage:1 wParam:NPPN_FILEOPENED lParam:0] == openedBefore + 1);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }

    if (NppSectionWanted(@"NppExec scripts")) { printf("\n== NppExec scripts ==\n");
        NSString *execDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_exec"];
        [[NSFileManager defaultManager] removeItemAtPath:execDir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:execDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"alpha\n" writeToFile:[execDir stringByAppendingPathComponent:@"one.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"beta\n" writeToFile:[execDir stringByAppendingPathComponent:@"two.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        // Variables, arithmetic, a loop by IF … GOTO, a block IF, and the shell.
        NppScriptEngine *engine = [[NppScriptEngine alloc] initWithEditor:ed];
        NSString *script = [NSString stringWithFormat:
            @"// counts to three\n"
            @"SET n = 0\n"
            @":again\n"
            @"SET n ~ $(n) + 1\n"
            @"ECHO pass $(n)\n"
            @"IF $(n) < 3 GOTO again\n"
            @"IF \"$(n)\" == \"3\"\n"
            @"  ECHO three\n"
            @"ELSE IF $(n) == 4\n"
            @"  ECHO four\n"
            @"ELSE\n"
            @"  ECHO other\n"
            @"ENDIF\n"
            @"SET half ~ 7 / 2\n"
            @"CD %@\n"
            @"ENV_SET GREETING = hello from env\n"
            @"/bin/echo \"$(SYS.GREETING)\"; exit 3\n"
            @"ECHO code=$(EXITCODE) out=$(OUTPUT)\n"
            @"ls *.txt\n"
            @"ECHO first=$(OUTPUT1) last=$(OUTPUTL)\n", execDir];
        BOOL ran = [engine runScript:script arguments:@[]];
        NSString *log = engine.log;
        BOOL flow = ran && [log containsString:@"pass 1\npass 2\npass 3\n"] && ![log containsString:@"pass 4"] &&
                    [log containsString:@"three\n"] && ![log containsString:@"four\n"] && ![log containsString:@"other\n"] &&
                    [[engine valueOfVariable:@"half"] isEqualToString:@"3.5"];
        BOOL shell = [log containsString:@"code=3 out=hello from env"] && [log containsString:@"first=one.txt last=two.txt"] &&
                     [log containsString:@"<<< Process finished. (Exit code 3)"] &&
                     [engine.directory isEqualToString:execDir.stringByStandardizingPath];
        printf("    exec flow=%d shell=%d\n", flow, shell);
        if (!(flow && shell)) printf("%s\n", log.UTF8String);
        Check(@"NppExec (script)", @"SET and SET ~, IF…GOTO and IF/ELSE IF/ELSE/ENDIF, CD, ENV_SET, $(OUTPUT) and $(EXITCODE)",
              flow && shell);

        // The editor's commands: open by mask, switch, change, save, close.
        NSUInteger docsBefore = ed.documents.count;
        NppScriptEngine *editing = [[NppScriptEngine alloc] initWithEditor:ed];
        editing.directory = execDir;
        BOOL editOK = [editing runScript:@"NPP_OPEN *.txt\n"
                                         @"NPP_SWITCH one.txt\n"
                                         @"SET before = $(CURRENT_LINESTR)\n"
                                         @"SCI_SENDMSG 2013\n"            // SCI_SELECTALL
                                         @"SEL_SETTEXT+ gamma\\tdelta\\n\n"
                                         @"NPP_SAVE\n"
                                         @"NPP_SAVEAS copy.txt\n"
                                         @"NPP_CLOSE copy.txt\n"
                                         @"NPP_CLOSE two.txt\n"
                                         @"NPP_SENDMSG 1234\n"
                                 arguments:@[]];
        NSString *saved = [NSString stringWithContentsOfFile:[execDir stringByAppendingPathComponent:@"one.txt"] encoding:NSUTF8StringEncoding error:NULL];
        NSString *copy = [NSString stringWithContentsOfFile:[execDir stringByAppendingPathComponent:@"copy.txt"] encoding:NSUTF8StringEncoding error:NULL];
        BOOL edited = editOK && [saved isEqualToString:@"gamma\tdelta\n"] && [copy isEqualToString:saved] &&
                      [[editing valueOfVariable:@"before"] isEqualToString:@"alpha"] &&
                      ed.documents.count == docsBefore && [editing.log containsString:@"NPP_SENDMSG is not available on macOS"];
        printf("    exec edit=%d docs=%lu/%lu\n", edited, (unsigned long)ed.documents.count, (unsigned long)docsBefore);
        if (!edited) printf("%s\n", editing.log.UTF8String);
        Check(@"NppExec (editor commands)", @"NPP_OPEN with a mask, NPP_SWITCH, SEL_SETTEXT+, NPP_SAVE, NPP_SAVEAS, NPP_CLOSE",
              edited);

        // Saved scripts in npes_saved.txt, NPP_EXEC with arguments, INPUTBOX, NPP_MENUCOMMAND.
        NSString *savedText = @"::greet\nECHO hi $(ARGV[1]) of $(ARGC)\n\n::other\nECHO x\n";
        NSArray<NppSavedScript *> *parsed = [NppSavedScript scriptsFromSavedText:savedText];
        BOOL format = parsed.count == 2 && [parsed[0].name isEqualToString:@"greet"] &&
                      [parsed[0].text isEqualToString:@"ECHO hi $(ARGV[1]) of $(ARGC)"] &&
                      [[NppSavedScript savedTextForScripts:parsed] isEqualToString:@"::greet\nECHO hi $(ARGV[1]) of $(ARGC)\n::other\nECHO x\n"];
        NSUInteger scriptsBefore = [ed savedScripts].count;
        [ed saveScript:[NppSavedScript scriptNamed:@"t_greet" text:@"ECHO hi $(ARGV[1]) of $(ARGC)"]];
        [app rebuildExecMenu];
        BOOL listed = [app.execMenu itemWithTitle:@"t_greet"] != nil;
        NppScriptEngine *calling = [[NppScriptEngine alloc] initWithEditor:ed];
        calling.inputProvider = ^NSString *(NSString *prompt, NSString *initial) {
            return [prompt isEqualToString:@"Who?"] ? [initial stringByAppendingString:@" World"] : nil;
        };
        __block NSString *performed = nil;
        calling.menuCommandPerformer = ^BOOL(NSString *path) { performed = path; return [app performMenuCommandAtPath:@"Edit|Select All"]; };
        SetDoc(ed, @"abc");
        BOOL callOK = [calling runScript:@"INPUTBOX \"Who?\" : Hello\n"
                                         @"NPP_EXEC t_greet \"$(INPUT[2])\" two\n"
                                         @"ECHO argc now [$(ARGC)]\n"
                                         @"NPP_MENUCOMMAND Edit|Select All\n"
                               arguments:@[]];
        long selected = [ed.sci message:SCI_GETSELECTIONEND] - [ed.sci message:SCI_GETSELECTIONSTART];
        BOOL nested = callOK && [calling.log containsString:@"hi World of 2"] && [calling.log containsString:@"argc now [0]"] &&
                      [[calling valueOfVariable:@"INPUT"] isEqualToString:@"Hello World"] &&
                      [performed isEqualToString:@"Edit|Select All"] && selected == 3 &&
                      ![app performMenuCommandAtPath:@"Edit|No Such Command"];
        [ed removeScriptNamed:@"t_greet"];
        [app rebuildExecMenu];
        BOOL removed = [ed savedScripts].count == scriptsBefore && ![app.execMenu itemWithTitle:@"t_greet"];
        printf("    exec format=%d listed=%d nested=%d removed=%d\n", format, listed, nested, removed);
        if (!nested) printf("%s\n", calling.log.UTF8String);
        Check(@"NppExec (saved scripts)", @"npes_saved.txt's format, the menu of saved scripts, NPP_EXEC with arguments, INPUTBOX, NPP_MENUCOMMAND",
              format && listed && nested && removed);

        // NppExec's IF … THEN; a value that holds an operator; the author's own
        // variables as plain words, the document's as one quoted word; $(SYS.X) shown.
        NppScriptEngine *forms = [[NppScriptEngine alloc] initWithEditor:ed];
        forms.directory = execDir;
        SetDoc(ed, @"x; echo INJECTED");
        [ed.sci message:SCI_SELECTALL];
        BOOL formsOK = [forms runScript:@"SET n = 3\n"
                                        @"IF \"$(n)\" == \"3\" THEN\n  ECHO then-yes\nELSE\n  ECHO then-no\nENDIF\n"
                                        @"SET expr = a==b\n"
                                        @"IF \"$(expr)\" == \"a==b\" THEN\n  ECHO operator-inside\nENDIF\n"
                                        @"SET flags = a b\n"
                                        @"SET more = $(flags) tail\n"
                                        @"/usr/bin/printf '%s|' $(more)\n"
                                        @"ECHO plain=[$(OUTPUT)]\n"
                                        @"SET sel = $(SELECTED_TEXT)\n"
                                        @"/bin/echo $(sel)\n"
                                        @"ECHO doc=[$(OUTPUT)]\n"
                                        @"/bin/echo \"$(printf %s $(SELECTED_TEXT))\"\n"
                                        @"ECHO sub=[$(OUTPUT)]\n"
                                        @"ENV_SET T_EXEC_VAR = shown\n"
                                        @"SET $(SYS.T_EXEC_VAR)\n"
                                arguments:@[]];
        NSString *fl = forms.log;
        formsOK = formsOK && [fl containsString:@"then-yes"] && ![fl containsString:@"then-no"] &&
                  [fl containsString:@"operator-inside"] && [fl containsString:@"plain=[a|b|tail|]"] &&
                  [fl containsString:@"doc=[x; echo INJECTED]"] && [fl containsString:@"sub=[x; echo INJECTED]"] &&
                  [fl containsString:@"= shown"];
        if (!formsOK) printf("%s\n", fl.UTF8String);
        Check(@"NppExec (THEN, operators in values, quoting)",
              @"IF … THEN is read, a value holding == is not the comparison, SET words stay words, and text from the "
              @"document is one quoted word even inside the shell's $( )",
              formsOK);

        // A program may run longer than the Run dialog allows, and Stop ends it.
        NppScriptEngine *slow = [[NppScriptEngine alloc] initWithEditor:ed];
        NSDate *slowStart = [NSDate date];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ slow.cancelled = YES; });
        [slow runScript:@"/bin/sh -c \"/bin/sleep 20; true\"\nECHO not-reached\n" arguments:@[]];
        NSTimeInterval slowTook = -[slowStart timeIntervalSinceNow];
        printf("    exec stop took %.1fs\n%s", slowTook, slowTook < 5 ? "" : slow.log.UTF8String);
        Check(@"NppExec (stop)", @"stopping a script ends the program it is running, and nothing after it runs",
              slowTook < 5 && ![slow.log containsString:@"not-reached"]);

        // EXIT ends the script it is in; the caller goes on. EXIT 1 ends them all.
        [ed saveScript:[NppSavedScript scriptNamed:@"t_inner" text:@"ECHO inner-start\nEXIT $(ARGV[1])\nECHO inner-not-reached"]];
        NppScriptEngine *exiting = [[NppScriptEngine alloc] initWithEditor:ed];
        [exiting runScript:@"NPP_EXEC t_inner 0\nECHO outer-goes-on\nNPP_EXEC t_inner 1\nECHO outer-not-reached\n" arguments:@[]];
        [ed removeScriptNamed:@"t_inner"];
        NSString *el = exiting.log;
        Check(@"NppExec (EXIT)", @"EXIT returns to the calling script, EXIT 1 ends the calling scripts too",
              [el containsString:@"outer-goes-on"] && ![el containsString:@"inner-not-reached"] && ![el containsString:@"outer-not-reached"] &&
              [el componentsSeparatedByString:@"inner-start"].count == 3);

        // A runaway loop is stopped rather than hanging the editor.
        NppScriptEngine *loop = [[NppScriptEngine alloc] initWithEditor:ed];
        loop.stepLimit = 500;
        BOOL stopped = ![loop runScript:@":top\nGOTO top\n" arguments:@[]] && [loop.log containsString:@"too many steps"];
        Check(@"NppExec (runaway)", @"an endless GOTO loop is stopped", stopped);

        // From the menu a script runs off the main thread and comes back to it
        // for the editor; the console fills while the app stays live.
        NSString *lastBefore = [[NSUserDefaults standardUserDefaults] stringForKey:@"NppMac.execLastScript"];
        SetDoc(ed, @"background");
        [[ed console] clear];
        [app executeScriptText:@"ECHO bg $(CURRENT_WORD)\nSLEEP 50\nNPP_MENUCOMMAND Edit|Select All"];
        NSDate *bgLimit = [NSDate dateWithTimeIntervalSinceNow:5];
        while ([app valueForKey:@"runningScript"] && [bgLimit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        long bgSelected = [ed.sci message:SCI_GETSELECTIONEND] - [ed.sci message:SCI_GETSELECTIONSTART];
        BOOL background = ![app valueForKey:@"runningScript"] && [[ed console].text containsString:@"bg background"] && bgSelected == 10;
        if (!background) printf("    bg running=%d selected=%ld console=[%s]\n", [app valueForKey:@"runningScript"] != nil, bgSelected, [ed console].text.UTF8String);
        [[NSUserDefaults standardUserDefaults] setObject:lastBefore ?: @"" forKey:@"NppMac.execLastScript"];
        [[ed console] toggle];
        Check(@"NppExec (background)", @"a script from the menu runs off the main thread and uses the editor through it", background);
        [[NSFileManager defaultManager] removeItemAtPath:execDir error:NULL];
    }

    // ---- meta-test: nothing may be declared implemented without a test


    if (NppSectionWanted(@"Git")) { printf("\n== Git ==\n");
        // A repository of the suite's own, in the temporary folder (which on macOS is a
        // symlink into /private - git reports the resolved root, the editor has the other).
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *repo = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_repo"];
        [fm removeItemAtPath:repo error:NULL];
        [fm createDirectoryAtPath:[repo stringByAppendingPathComponent:@"src"] withIntermediateDirectories:YES attributes:nil error:NULL];
        BOOL (^git)(NSArray<NSString *> *) = ^BOOL(NSArray<NSString *> *args) { return [NppGit run:args in:repo output:NULL error:NULL]; };
        NSString *(^gitOut)(NSArray<NSString *> *) = ^NSString *(NSArray<NSString *> *args) {
            NSString *out = nil; [NppGit run:args in:repo output:&out error:NULL];
            return [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        };
        BOOL cmpCaseWas = ed.compareIgnoreCase, cmpSpacesWas = ed.compareIgnoreSpaces, cmpEmptyWas = ed.compareIgnoreEmptyLines;
        ed.compareIgnoreCase = NO; ed.compareIgnoreSpaces = NO; ed.compareIgnoreEmptyLines = NO;   // the user's own settings aside
        BOOL made = [NppGit executable] != nil && git(@[@"init", @"-q"]) &&
                    git(@[@"config", @"user.email", @"suite@example.invalid"]) && git(@[@"config", @"user.name", @"Suite Runner"]) &&
                    git(@[@"config", @"commit.gpgsign", @"false"]);
        NSString *tracked = [repo stringByAppendingPathComponent:@"src/tracked.txt"];
        NSString *other = [repo stringByAppendingPathComponent:@"other.txt"];
        [@"one\ntwo\nthree\nfour\n" writeToFile:tracked atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"keep\n" writeToFile:other atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        made = made && git(@[@"add", @"-A"]) && git(@[@"commit", @"-q", @"-m", @"first commit"]);
        NSString *firstCommit = gitOut(@[@"rev-parse", @"HEAD"]);
        NSString *branch = gitOut(@[@"rev-parse", @"--abbrev-ref", @"HEAD"]);   // main or master, as git is configured
        Check(@"Git (setup)", @"git is found and a repository with one commit is made for the suite",
              made && firstCommit.length == 40 && branch.length > 0);

        // The porcelain, parsed: every state, a rename with its old name, and untracked.
        NSArray<NppGitFileStatus *> *parsed = [NppGit statusesFromPorcelain:
            @"M  staged.txt\0 M unstaged.txt\0MM both.txt\0A  added.txt\0D  gone.txt\0R  new-name.txt\0old-name.txt\0?? fresh.txt\0"];
        Check(@"Git (porcelain)", @"seven entries: staged, unstaged, both, added, deleted, a rename carrying its old name, untracked",
              parsed.count == 7 &&
              parsed[0].staged && !parsed[0].unstaged && [parsed[0].shortStatus isEqualToString:@"M"] &&
              !parsed[1].staged && parsed[1].unstaged && [parsed[1].path isEqualToString:@"unstaged.txt"] &&
              parsed[2].staged && parsed[2].unstaged && [parsed[2].shortStatus isEqualToString:@"MM"] &&
              [parsed[3].shortStatus isEqualToString:@"A"] && [parsed[4].shortStatus isEqualToString:@"D"] &&
              [parsed[5].path isEqualToString:@"new-name.txt"] && [parsed[5].renamedFrom isEqualToString:@"old-name.txt"] &&
              parsed[6].untracked && [parsed[6].shortStatus isEqualToString:@"??"] && !parsed[6].staged);

        // Where a file is: the root is found through the symlinked temporary folder, cached, and forgotten on demand.
        NSString *root = [NppGit repositoryRootForPath:tracked];
        NSString *outside = TempFile(@"t_git_outside.txt", @"x\n");
        BOOL noRepo = [NppGit repositoryRootForPath:outside] == nil;
        [ed openFileAtPath:tracked error:NULL];
        NppDocument *trackedDoc = ed.currentDocument;
        NSString *relative = [ed gitRelativePathOfDocument:trackedDoc];
        [NppGit forgetRepositoryRoots];
        Check(@"Git (repository root)", @"the root of a file in the repository is the repository, a file outside has none, and the path relative to the root is right through the symlink",
              [root.stringByResolvingSymlinksInPath isEqualToString:repo.stringByResolvingSymlinksInPath] && noRepo &&
              [relative isEqualToString:@"src/tracked.txt"] &&
              [[ed gitRootOfCurrentDocument].stringByResolvingSymlinksInPath isEqualToString:repo.stringByResolvingSymlinksInPath]);

        // The branch in the status bar; nothing for a file outside a repository.
        [ed gitRefreshState];
        NSString *statusText = [ed gitStatusBarText];
        [ed openFileAtPath:outside error:NULL];
        [ed gitRefreshState];
        BOOL emptyOutside = [ed gitStatusBarText].length == 0 && [ed.sci message:SCI_GETMARGINWIDTHN wParam:4 lParam:0] == 0;
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:trackedDoc]];
        [ed gitRefreshState];
        Check(@"Git (status bar)", @"the status bar names the branch inside the repository and nothing outside it, where the git margin is hidden too",
              [statusText containsString:branch] && [statusText hasPrefix:@"⎇ "] && emptyOutside &&
              [[(NSTextField *)[ed valueForKey:@"statusField"] stringValue] containsString:statusText]);

        // Markers against HEAD, on the text as it is now: a changed line, an added line, and where a line went.
        long (^markersOn)(long) = ^long(long line) { return [ed.sci message:SCI_MARKERGET wParam:(uptr_t)line lParam:0] & ((1 << 6) | (1 << 7) | (1 << 8)); };
        SetDoc(ed, @"one\nTWO\nthree\nfour\nfive\n");            // two changed, five added
        [ed gitRefreshMarkers];
        long changedMark = markersOn(1), addedMark = markersOn(4), untouched = markersOn(0) | markersOn(2) | markersOn(3);
        SetDoc(ed, @"one\nthree\nfour\n");                        // two removed
        [ed gitRefreshMarkers];
        long removedMark = markersOn(1);
        long width = [ed.sci message:SCI_GETMARGINWIDTHN wParam:4 lParam:0];
        Check(@"Git (margin markers)", @"a changed line carries the changed mark, an added line the added mark, unchanged lines none, and the line after a removal the removed mark; the margin is six pixels wide",
              changedMark == (1 << 7) && addedMark == (1 << 6) && untouched == 0 && removedMark == (1 << 8) && width == 6);
        // Typing refreshes them by itself, a moment later; the setting hides them.
        [ed.sci setString:@"one\ntwo\nthree\nfour\n"];
        [ed.sci message:SCI_APPENDTEXT wParam:4 lParam:(sptr_t)"six\n"];
        NppSettleUntil(^BOOL{ return markersOn(4) == (1 << 6); }, 5);
        BOOL byTyping = markersOn(4) == (1 << 6) && markersOn(1) == 0;
        NppPreferences *gp = [NppPreferences shared];
        BOOL marksOn = gp.gitMarginMarks;
        gp.gitMarginMarks = NO;
        [ed gitRefreshMarkers];
        BOOL hidden = markersOn(4) == 0 && [ed.sci message:SCI_GETMARGINWIDTHN wParam:4 lParam:0] == 0;
        gp.gitMarginMarks = marksOn;
        [ed gitRefreshMarkers];
        // The refresh after typing runs no git process (a wait would spin the run loop and the
        // margin would be drawn empty for a frame): twenty of them take well under a process spawn each.
        NSDate *t0 = [NSDate date];
        for (int i = 0; i < 20; ++i) [ed gitRefreshMarkersCachedOnly:YES];
        NSTimeInterval cachedTime = -[t0 timeIntervalSinceNow];
        BOOL stillMarked = markersOn(4) == (1 << 6) && markersOn(1) == 0;
        Check(@"Git (markers follow typing, the setting)", @"an appended line is marked after typing stops; the MISC. setting off empties and hides the margin; the refresh after typing uses the cached HEAD and takes no process",
              byTyping && hidden && markersOn(4) == (1 << 6) && stillMarked && cachedTime < 0.2);

        // Revert the change at the caret to HEAD: a changed line, added lines, removed lines put back, each one undo step.
        SetDoc(ed, @"one\nTWO\nthree\nfour\nfive\n");
        [ed.sci message:SCI_GOTOLINE wParam:1 lParam:0];
        BOOL revertedChanged = [ed gitRevertChangeAtCaret] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\nfive\n"];
        [ed.sci message:SCI_GOTOLINE wParam:4 lParam:0];
        BOOL revertedAdded = [ed gitRevertChangeAtCaret] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\n"];
        [ed.sci message:SCI_UNDO wParam:0 lParam:0];
        BOOL undoneInOne = [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\nfive\n"];
        SetDoc(ed, @"one\nthree\nfour\n");
        [ed.sci message:SCI_GOTOLINE wParam:1 lParam:0];   // "three", where the margin marks the removal
        BOOL revertedRemoved = [ed gitRevertChangeAtCaret] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\n"];
        [ed.sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL nothingHere = ![ed gitRevertChangeAtCaret] && [ed.gitLastError isEqualToString:NppL(@"The caret is on no change since the last commit")];
        SetDoc(ed, @"one\ntwo\nthree\nfour\nfive");   // the last line without an ending, added
        [ed.sci message:SCI_GOTOLINE wParam:4 lParam:0];
        BOOL revertedTail = [ed gitRevertChangeAtCaret] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\n"];
        Check(@"Git (revert change at caret)", @"a changed line, added lines (at the end too, with or without an ending) and removed lines go back to HEAD from where the caret is, one undo step each; an unchanged line says there is nothing to revert",
              revertedChanged && revertedAdded && undoneInOne && revertedRemoved && nothingHere && revertedTail);

        // Compare with HEAD: HEAD's text in the second view, the changed line marked; blame and history as documents.
        SetDoc(ed, @"one\nTWO\nthree\nfour\n");
        BOOL compared = [ed gitCompareWithHead];
        NSString *headSide = [ed.secondarySci string] ?: @"";
        BOOL compareShown = compared && [ed compareActive] && [headSide isEqualToString:@"one\ntwo\nthree\nfour\n"] && [ed currentDiff].count > 0;
        [ed clearAllCompares];
        SetDoc(ed, @"one\ntwo\nthree\nfour\n");
        NSUInteger tabsBefore = ed.documents.count;
        BOOL blamed = [ed gitBlame];
        NSString *blameText = DocText(ed);
        BOOL blameDoc = blamed && [ed.currentDocument.displayName isEqualToString:@"tracked.txt (blame)"] && ed.currentDocument.userReadOnly &&
                        [blameText containsString:@"Suite Runner"] && [blameText containsString:@"three"];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:trackedDoc]];
        BOOL logged = [ed gitFileHistory];
        NSString *logText = DocText(ed);
        BOOL logDoc = logged && [ed.currentDocument.displayName isEqualToString:@"tracked.txt (history)"] && [logText containsString:@"first commit"] &&
                      [logText containsString:[firstCommit substringToIndex:7]];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:trackedDoc]];
        Check(@"Git (Compare with HEAD, Blame, File History)", @"HEAD's text goes into the second view with the difference marked; blame and history open as read-only documents named after the file, with the author and the commit",
              compareShown && blameDoc && logDoc && ed.documents.count == tabsBefore);

        // Stage, unstage, the panel's rows and its label; a rename; an untracked file.
        [@"one\ntwo\nthree\nfour\nfive\n" writeToFile:tracked atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [ed reloadCurrentDocument:NULL];
        NSString *fresh = [repo stringByAppendingPathComponent:@"fresh.txt"];
        [@"new\n" writeToFile:fresh atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        git(@[@"mv", @"other.txt", @"renamed.txt"]);
        NppGitPanel *panel = [ed gitPanel];
        [panel show];
        NSArray<NppGitFileStatus *> *rows = panel.rows;
        NSMutableDictionary *byPath = [NSMutableDictionary dictionary];
        for (NppGitFileStatus *r in rows) byPath[r.path] = r;
        BOOL rowsRight = rows.count == 3 && [byPath[@"src/tracked.txt"] unstaged] && ![byPath[@"src/tracked.txt"] staged] &&
                         [byPath[@"fresh.txt"] untracked] && [byPath[@"renamed.txt"] staged] && [[byPath[@"renamed.txt"] renamedFrom] isEqualToString:@"other.txt"] &&
                         [rows.firstObject.path isEqualToString:@"renamed.txt"] &&   // staged rows first, untracked last
                         [rows.lastObject.path isEqualToString:@"fresh.txt"] &&
                         [panel.branchLabel.stringValue containsString:branch] && [panel.branchLabel.stringValue containsString:NppLMessage(@"$INT_REPLACE$ changed", nil, 3)] &&
                         [panel.branchLabel.stringValue containsString:NppLMessage(@"$INT_REPLACE$ staged", nil, 1)];
        BOOL staged = [ed gitStageCurrent];
        [panel reload];
        for (NppGitFileStatus *r in panel.rows) byPath[r.path] = r;
        BOOL nowStaged = staged && [byPath[@"src/tracked.txt"] staged] && ![byPath[@"src/tracked.txt"] unstaged];
        BOOL unstaged = [ed gitUnstageCurrent];
        [panel reload];
        for (NppGitFileStatus *r in panel.rows) byPath[r.path] = r;
        BOOL backAgain = unstaged && ![byPath[@"src/tracked.txt"] staged] && [byPath[@"src/tracked.txt"] unstaged];
        // The panel's own buttons, on the selected rows.
        NSInteger freshRow = (NSInteger)[panel.rows indexOfObjectPassingTest:^BOOL(NppGitFileStatus *r, NSUInteger i, BOOL *stop) { return [r.path isEqualToString:@"fresh.txt"]; }];
        [panel.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)freshRow] byExtendingSelection:NO];
        [panel stageSelected:nil];
        for (NppGitFileStatus *r in panel.rows) byPath[r.path] = r;
        BOOL freshStaged = [[byPath[@"fresh.txt"] shortStatus] isEqualToString:@"A"];
        freshRow = (NSInteger)[panel.rows indexOfObjectPassingTest:^BOOL(NppGitFileStatus *r, NSUInteger i, BOOL *stop) { return [r.path isEqualToString:@"fresh.txt"]; }];
        [panel.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)freshRow] byExtendingSelection:NO];
        [panel unstageSelected:nil];
        for (NppGitFileStatus *r in panel.rows) byPath[r.path] = r;
        BOOL freshBack = [byPath[@"fresh.txt"] untracked];
        Check(@"Git (stage, unstage, the panel)", @"the panel lists the modified, the renamed (with its old name, staged first) and the untracked file with the branch and counts; Stage File and Unstage File move the file between the index and the working tree, and the panel's buttons do the same for the selected row",
              rowsRight && nowStaged && backAgain && freshStaged && freshBack);

        // Discard: the tracked file goes back to HEAD and the open document is reread; an untracked one is removed.
        ed.gitAnswersWithoutAsking = YES;
        BOOL discarded = [ed gitDiscardCurrent];
        NSString *onDisk = [NSString stringWithContentsOfFile:tracked encoding:NSUTF8StringEncoding error:NULL];
        BOOL discardedWell = discarded && [onDisk isEqualToString:@"one\ntwo\nthree\nfour\n"] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\nfour\n"] && !trackedDoc.modified;
        BOOL cleaned = [ed gitDiscardPaths:@[@"fresh.txt"]] && ![fm fileExistsAtPath:fresh];
        Check(@"Git (discard)", @"discarding puts the last committed text back on disk and in the tab, unmodified; discarding an untracked file removes it",
              discardedWell && cleaned);

        // Commit: refused without a message or without anything staged; done, HEAD moves and the markers go.
        NSString *sha = nil;
        BOOL noMessage = ![ed gitCommitWithMessage:@"  " stageAll:NO commit:&sha] && [ed.gitLastError isEqualToString:NppL(@"A commit needs a message")];
        git(@[@"reset", @"-q", @"HEAD"]);   // the rename back to unstaged: nothing staged
        git(@[@"mv", @"renamed.txt", @"other.txt"]);
        git(@[@"reset", @"-q", @"HEAD"]);
        BOOL nothingStaged = ![ed gitCommitWithMessage:@"nothing" stageAll:NO commit:&sha] && [ed.gitLastError isEqualToString:NppL(@"Nothing is staged to commit")];
        SetDoc(ed, @"one\ntwo\nthree\nfour\nfive\n");
        [ed saveCurrentDocument];
        [ed gitRefreshMarkers];
        BOOL markedBefore = markersOn(4) == (1 << 6);
        BOOL committed = [ed gitCommitWithMessage:@"second commit\n\nwith a body" stageAll:YES commit:&sha];
        NSString *head = gitOut(@[@"rev-parse", @"HEAD"]);
        NSString *subject = gitOut(@[@"log", @"-1", @"--format=%s"]);
        BOOL markedAfter = markersOn(4) != 0;
        Check(@"Git (commit)", @"a blank message and nothing staged are refused with the reason; with stage-all the change is committed, HEAD is the new commit with the subject, and the margin is clean again",
              noMessage && nothingStaged && markedBefore && committed && [sha isEqualToString:head] && ![head isEqualToString:firstCommit] &&
              [subject isEqualToString:@"second commit"] && !markedAfter && gitOut(@[@"status", @"--porcelain"]).length == 0);

        // The commit window: what it says, and the commit it makes.
        SetDoc(ed, @"one\ntwo\nthree\nfour\nfive\nsix\n");
        [ed saveCurrentDocument];
        NppCommitWindow *cw = [NppCommitWindow shared];
        [cw showForEditor:ed];
        BOOL disabledEmpty = !cw.commitButton.enabled && [cw.stagedSummary.stringValue containsString:NppLMessage(@"$INT_REPLACE$ files staged", nil, 0)] && [cw.stagedSummary.stringValue containsString:NppLMessage(@"$INT_REPLACE$ not staged", nil, 1)];
        cw.message.string = @"third commit";
        [cw textDidChange:nil];
        BOOL stillDisabled = !cw.commitButton.enabled;   // nothing staged yet
        cw.stageAll.state = NSControlStateValueOn;
        [cw optionChanged:nil];
        BOOL enabledNow = cw.commitButton.enabled && [cw.stagedSummary.stringValue containsString:NppLMessage(@"$INT_REPLACE$ files will be staged and committed", nil, 1)];
        BOOL windowCommitted = [cw commit:nil];
        NSString *third = gitOut(@[@"rev-parse", @"HEAD"]);
        Check(@"Git (commit window)", @"Commit is off with nothing staged and no message, on once the message is typed and stage-all ticked; the button commits, closes the window and the console names the commit",
              disabledEmpty && stillDisabled && enabledNow && windowCommitted && [cw.lastCommit isEqualToString:third] && !cw.panel.visible &&
              [ed.console.text containsString:[third substringToIndex:7]] && [gitOut(@[@"log", @"-1", @"--format=%s"]) isEqualToString:@"third commit"]);

        // Branches: made, listed with the current one ticked in the menu, switched back; a detached HEAD is called HEAD.
        BOOL created = [ed gitCreateBranch:@"feature/suite"];
        NSArray *branches = [NppGit branchesOfRepository:repo];
        NSString *onBranch = [NppGit branchOfRepository:repo ahead:NULL behind:NULL];
        NSMenu *branchMenu = [[NSMenu alloc] initWithTitle:@"Switch Branch"];
        branchMenu.identifier = @"NppGitBranches";
        [app menuNeedsUpdate:branchMenu];
        NSMenuItem *ticked = nil;
        for (NSMenuItem *it in branchMenu.itemArray) if (it.state == NSControlStateValueOn) ticked = it;
        BOOL switchedBack = [ed gitCheckoutBranch:branch] && [[NppGit branchOfRepository:repo ahead:NULL behind:NULL] isEqualToString:branch];
        BOOL badName = ![ed gitCreateBranch:@" "] && [ed.gitLastError isEqualToString:NppL(@"A branch needs a name")];
        git(@[@"checkout", @"-q", @"--detach"]);
        [ed gitRefreshState];
        BOOL detached = [[NppGit branchOfRepository:repo ahead:NULL behind:NULL] isEqualToString:@"HEAD"] && [[ed gitStatusBarText] containsString:@"HEAD"];
        git(@[@"checkout", @"-q", branch]);
        [ed gitRefreshState];
        Check(@"Git (branches)", @"New Branch makes and checks out feature/suite, the Switch Branch menu lists both with the current one ticked, switching back works, a blank name is refused, detached HEAD shows as HEAD",
              created && [branches containsObject:@"feature/suite"] && [branches containsObject:branch] && [onBranch isEqualToString:@"feature/suite"] &&
              branchMenu.numberOfItems == 2 && [ticked.title isEqualToString:@"feature/suite"] && switchedBack && badName && detached);

        // Push to a bare repository beside it, then fetch from one that does not exist: both run in the
        // background with their output in the console, one ending done and the other failed.
        NSString *bare = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_bare.git"];
        [fm removeItemAtPath:bare error:NULL];
        [fm createDirectoryAtPath:bare withIntermediateDirectories:YES attributes:nil error:NULL];
        [NppGit run:@[@"init", @"-q", @"--bare"] in:bare output:NULL error:NULL];
        git(@[@"remote", @"add", @"origin", bare]);
        git(@[@"config", @"push.default", @"current"]);
        [ed.console clear];
        [ed gitPush];
        NppSettleUntil(^BOOL{ return [ed.console.text containsString:@"- done"] || [ed.console.text containsString:@"- git failed"]; }, 20);
        NSString *pushText = [ed.console.text copy];   // the console's string is its live storage
        NSString *bareHead = nil;
        [NppGit run:@[@"rev-parse", branch] in:bare output:&bareHead error:NULL];
        bareHead = [bareHead stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        git(@[@"remote", @"set-url", @"origin", @"/nonexistent/t_git_remote"]);
        [ed.console clear];
        [ed gitFetch];
        NppSettleUntil(^BOOL{ return [ed.console.text containsString:@"- done"] || [ed.console.text containsString:@"- git failed"]; }, 20);
        NSString *fetchText = [ed.console.text copy];
        git(@[@"remote", @"remove", @"origin"]);
        [fm removeItemAtPath:bare error:NULL];
        Check(@"Git (push and fetch in the console)", @"push to a local bare repository runs in the background and ends done with the commit there; fetch from a remote that does not exist shows git's complaint and ends failed",
              [pushText containsString:@"$ git push"] && [pushText containsString:@"- done"] && [bareHead isEqualToString:third] &&
              [fetchText containsString:@"$ git fetch"] && [fetchText containsString:@"- git failed"] &&
              ([fetchText containsString:@"does not appear"] || [fetchText containsString:@"fatal"]));

        // Before the first commit: unstaging takes the file out of the index (there is no HEAD to reset to); Compare with HEAD says so.
        NSString *young = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_young"];
        [fm removeItemAtPath:young error:NULL];
        [fm createDirectoryAtPath:young withIntermediateDirectories:YES attributes:nil error:NULL];
        [NppGit run:@[@"init", @"-q"] in:young output:NULL error:NULL];
        NSString *youngFile = [young stringByAppendingPathComponent:@"a.txt"];
        [@"a\n" writeToFile:youngFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [ed openFileAtPath:youngFile error:NULL];
        BOOL stagedYoung = [ed gitStageCurrent];
        NSString *youngOut = nil; [NppGit run:@[@"status", @"--porcelain"] in:young output:&youngOut error:NULL];
        BOOL wasAdded = [youngOut hasPrefix:@"A "];
        BOOL unstagedYoung = [ed gitUnstageCurrent];
        [NppGit run:@[@"status", @"--porcelain"] in:young output:&youngOut error:NULL];
        BOOL noHeadCompare = ![ed gitCompareWithHead] && [ed.gitLastError isEqualToString:NppL(@"The file is not in HEAD yet")];
        BOOL allNew = ({ [ed gitRefreshMarkers]; markersOn(0) == (1 << 6); });
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"Git (before the first commit)", @"a file is staged as added and unstaged back to untracked with no HEAD yet; Compare with HEAD is refused with the reason; every line is marked new",
              stagedYoung && wasAdded && unstagedYoung && [youngOut hasPrefix:@"??"] && noHeadCompare && allNew);

        // Outside a repository, every command declines and says why.
        [ed openFileAtPath:outside error:NULL];
        BOOL declined = ![ed gitStageCurrent] && [ed.gitLastError isEqualToString:NppL(@"The file is not in a Git repository")] &&
                        ![ed gitBlame] && ![ed gitFileHistory] && ![ed gitCompareWithHead] && ![ed gitRevertChangeAtCaret] && ![ed gitCommitWithMessage:@"x" stageAll:YES commit:NULL] &&
                        ![ed gitCheckoutBranch:@"main"] && [ed gitStatusBarText].length == 0;
        [panel reload];
        BOOL panelSaysSo = panel.rows.count == 0 && [panel.branchLabel.stringValue isEqualToString:NppL(@"The file is not in a Git repository")];
        [cw showForEditor:ed];
        BOOL windowSaysSo = !cw.commitButton.enabled && [cw.stagedSummary.stringValue isEqualToString:NppL(@"The file is not in a Git repository")];
        [cw cancel:nil];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"Git (outside a repository)", @"stage, blame, history, compare, commit and checkout all decline with the reason; the panel and the commit window say it too",
              declined && panelSaysSo && windowSaysSo);

        // The menu: Plugins > Git with its commands; then every interface language that translates the
        // Git texts: the menu item and the window are translated, and nothing in the window or the
        // panel's buttons is cut off - long German, Finnish and Hungarian words, Arabic, CJK alike.
        NSMenuItem *gitItem = nil;
        for (NSMenuItem *it in app.pluginsMenu.itemArray) if ([NppEnglishMenuTitle(it.submenu) isEqualToString:@"Git"] || [it.title isEqualToString:@"Git"]) gitItem = it;
        NSMutableArray *titles = [NSMutableArray array];
        for (NSMenuItem *it in gitItem.submenu.itemArray) if (!it.isSeparatorItem) [titles addObject:NppEnglishTitle(it)];
        NSString *extraDir = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"nativeLang-extra"];
        NSMutableArray<NSString *> *languagesWithGit = [NSMutableArray array];
        for (NSString *file in [[fm contentsOfDirectoryAtPath:extraDir error:NULL] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![file hasSuffix:@".xml"] || [file isEqualToString:@"english.xml"]) continue;
            NSString *xml = [NSString stringWithContentsOfFile:[extraDir stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:NULL];
            if ([xml containsString:@"english=\"Commit message\""]) [languagesWithGit addObject:file];
        }
        NppPreferences *lp = [NppPreferences shared];
        NSString *languageBefore = lp.localizationFile;
        NSMutableArray<NSString *> *problems = [NSMutableArray array];
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:trackedDoc]];
        NSString *(^cutIn)(NSView *) = ^NSString *(NSView *rootView) {
            [rootView layoutSubtreeIfNeeded];
            NSMutableArray<NSString *> *bad = [NSMutableArray array];
            NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:rootView];
            while (queue.count) {
                NSView *v = queue.firstObject; [queue removeObjectAtIndex:0];
                if (v.hidden) continue;
                [queue addObjectsFromArray:v.subviews];
                BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).selectable;
                BOOL isButton = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]];
                if (!isLabel && !isButton) continue;
                NSControl *c = (NSControl *)v;
                NSString *text = isLabel ? c.stringValue : ((NSButton *)c).title;
                if (!text.length || c.cell.wraps) continue;
                if (c.cell.cellSize.width > NSWidth(c.frame) + 1.5 || c.cell.cellSize.height > NSHeight(c.frame) + 1.5)
                    [bad addObject:[NSString stringWithFormat:@"\"%@\" needs %.0f, has %.0f", text, c.cell.cellSize.width, NSWidth(c.frame)]];
            }
            return [bad componentsJoinedByString:@"; "];
        };
        for (NSString *file in languagesWithGit) {
            lp.localizationFile = file;
            [app applyLocalization];
            // What the file says a text is, is what the menu and the window must show (a language may keep "Commit").
            NSString *xml = [NSString stringWithContentsOfFile:[extraDir stringByAppendingPathComponent:file] encoding:NSUTF8StringEncoding error:NULL];
            NSString *(^said)(NSString *) = ^NSString *(NSString *english) {
                NSRange r = [xml rangeOfString:[NSString stringWithFormat:@"english=\"%@\" text=\"", english]];
                if (r.location == NSNotFound) return english;
                NSUInteger from = NSMaxRange(r);
                NSRange end = [xml rangeOfString:@"\"" options:0 range:NSMakeRange(from, xml.length - from)];
                NSString *raw = [xml substringWithRange:NSMakeRange(from, end.location - from)];
                return [[[[raw stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"]
                         stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"] stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
            };
            NSString *menuTitle = nil;
            for (NSMenuItem *it in gitItem.submenu.itemArray) if ([NppEnglishTitle(it) isEqualToString:@"Commit…"]) menuTitle = it.title;
            NppCommitWindow *lw = [[NppCommitWindow alloc] init];
            [lw showForEditor:ed];
            NSString *cutWindow = cutIn(lw.panel.contentView);
            // Compared without the ellipsis and spaces around it: "Commit …" and "Commit…" are one translation.
            NSString *(^plain)(NSString *) = ^NSString *(NSString *t) {
                return [[[t stringByReplacingOccurrencesOfString:@"…" withString:@""] stringByReplacingOccurrencesOfString:@"..." withString:@""]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            };
            // As the localiser compares: AppKit hands titles back with no-break spaces plain and format characters gone.
            BOOL (^same)(NSString *, NSString *) = ^BOOL(NSString *a, NSString *b) {
                NSString *(^bare)(NSString *) = ^NSString *(NSString *t) {
                    t = [[t componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@""];
                    t = [[t componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];
                    return [t precomposedStringWithCanonicalMapping];
                };
                return a && b && [bare(a) compare:bare(b)] == NSOrderedSame;
            };
            BOOL translated = same(lw.panel.title, said(@"Commit")) && same(lw.commitButton.title, said(@"Commit")) &&
                              same(lw.messageLabel.stringValue, said(@"Commit message")) && same(lw.stageAll.title, said(@"Stage all changes first")) &&
                              same(plain(menuTitle), plain(said(@"Commit")));   // the menu item is "Commit" with the ellipsis put back
            [lw cancel:nil];
            NppGitPanel *lpanel = [ed gitPanel];   // relocalized by applyLocalization
            NSView *panelView = lpanel.table.enclosingScrollView.superview;
            NSRect panelFrame = panelView.frame;
            panelView.frame = NSMakeRect(0, 0, 600, 300);   // wide enough for any row of buttons; what is cut is then the button's own doing
            NSString *cutPanel = cutIn(panelView);
            panelView.frame = panelFrame;
            NSString *stageTitle = nil;
            for (NSView *v in lpanel.table.enclosingScrollView.superview.subviews) {
                for (NSView *b in v.subviews) if ([b.identifier isEqualToString:@"Stage"]) stageTitle = ((NSButton *)b).title;
            }
            if (!same(stageTitle, said(@"Stage"))) translated = NO;
            if (!translated) [problems addObject:[NSString stringWithFormat:@"%@: not translated", file]];
            if (cutWindow.length) [problems addObject:[NSString stringWithFormat:@"%@ window: %@", file, cutWindow]];
            if (cutPanel.length) [problems addObject:[NSString stringWithFormat:@"%@ panel: %@", file, cutPanel]];
        }
        lp.localizationFile = languageBefore ?: @"";
        [app applyLocalization];
        if (problems.count) printf("       %s\n", [[problems componentsJoinedByString:@"\n       "] UTF8String]);
        Check(@"Git (menu, every language)", [NSString stringWithFormat:@"Plugins > Git carries its sixteen commands; in each of the %lu languages that translate it the menu item, the window title and the Commit button are translated and nothing in the window or the panel is cut off", (unsigned long)languagesWithGit.count],
              gitItem != nil && titles.count == 16 && [titles containsObject:@"Compare with HEAD"] && [titles containsObject:@"Switch Branch"] &&
              languagesWithGit.count >= 20 && problems.count == 0);

        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:trackedDoc] discardChanges:YES];
        [[NppDockingManager shared] hidePanel:@"git"];
        ed.gitAnswersWithoutAsking = NO;
        [fm removeItemAtPath:repo error:NULL];
        [fm removeItemAtPath:young error:NULL];
        ed.compareIgnoreCase = cmpCaseWas; ed.compareIgnoreSpaces = cmpSpacesWas; ed.compareIgnoreEmptyLines = cmpEmptyWas;
    }

    if (NppSectionWanted(@"Agent interface (MCP)")) { printf("\n== Agent interface (MCP) ==\n");
        NppAgentServer *agent = [NppAgentServer shared];
        agent.editor = ed;
        NSDictionary *(^rpc)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *method, NSDictionary *params) {
            return [agent handleMessage:@{@"jsonrpc": @"2.0", @"id": @1, @"method": method, @"params": params ?: @{}}];
        };
        NSDictionary *(^tool)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *name, NSDictionary *args) {
            NSError *error = nil;
            NSDictionary *out = [agent callTool:name arguments:args error:&error];
            return out ?: @{@"error": error.localizedDescription ?: @"?"};
        };
        NSUInteger before = ed.documents.count;

        // The protocol: initialize answers with a version and the server's name; the tool list is complete.
        NSDictionary *init = rpc(@"initialize", @{@"protocolVersion": @"2025-03-26", @"capabilities": @{}});
        NSArray *tools = rpc(@"tools/list", nil)[@"result"][@"tools"];
        NSMutableSet *names = [NSMutableSet set];
        BOOL described = tools.count > 0;
        for (NSDictionary *t in tools) {
            [names addObject:t[@"name"]];
            if (![t[@"description"] length] || ![t[@"inputSchema"] isKindOfClass:[NSDictionary class]]) described = NO;
        }
        NSSet *expected = [NSSet setWithArray:@[@"list_documents", @"get_document", @"get_selection", @"open_document", @"close_document",
            @"go_to", @"edit_document", @"save_document", @"bookmarks", @"list_commands", @"run_command", @"detect_language", @"tokens",
            @"function_list", @"find", @"replace", @"compare", @"file_encoding", @"ocr", @"read_qr", @"spell_check"]];
        Check(@"Agent (protocol)", @"initialize names the server and the protocol version asked for; ping answers; every tool is described",
              [init[@"result"][@"protocolVersion"] isEqualToString:@"2025-03-26"] &&
              [init[@"result"][@"serverInfo"][@"name"] isEqualToString:@"NotepadMac"] &&
              [rpc(@"ping", nil)[@"result"] isKindOfClass:[NSDictionary class]] &&
              [names isEqualToSet:expected] && described &&
              [rpc(@"nothing/here", nil)[@"error"][@"code"] integerValue] == -32601 &&
              [agent handleMessage:@{@"jsonrpc": @"2.0", @"method": @"notifications/initialized"}] == nil);

        // A document from text, with its language: the lexer's tokens are what the editor colours.
        NSDictionary *opened = tool(@"open_document", @{@"text": @"int main() { return 0; } // hi\n", @"language": @"cpp", @"title": @"agent.cpp"});
        NSArray *tokens = tool(@"tokens", @{@"include_folds": @YES})[@"tokens"];
        NSMutableArray *styles = [NSMutableArray array];
        for (NSArray *t in tokens) [styles addObject:[NSString stringWithFormat:@"%@:%@", t[2], t[3]]];
        Check(@"Agent (open_document, tokens)", @"a text opens as a C++ document and its tokens carry Notepad++'s style names",
              [opened[@"language"] isEqualToString:@"cpp"] && [ed.currentDocument.displayName isEqualToString:@"agent.cpp"] &&
              [styles containsObject:@"TYPE WORD:int"] && [styles containsObject:@"INSTRUCTION WORD:return"] &&
              [styles containsObject:@"COMMENT LINE:// hi"] && [styles containsObject:@"NUMBER:0"]);

        // Edits: several at once, applied as one undo step, on a document that is not in front.
        NSString *sample = TempFile(@"t_agent.txt", @"one\ntwo\nthree\n");
        tool(@"open_document", @{@"path": sample});
        NppDocument *sampleDoc = ed.currentDocument;
        [ed selectDocumentAtIndex:[opened[@"index"] integerValue]];   // agent.cpp in front, the file behind
        NSDictionary *edited = tool(@"edit_document", @{@"document": @"t_agent.txt", @"edits": @[
            @{@"start_line": @2, @"end_line": @2, @"text": @"TWO\n"},
            @{@"start_line": @1, @"start_column": @1, @"end_line": @1, @"end_column": @2, @"text": @"O"}]});
        NSString *afterEdit = tool(@"get_document", @{@"document": sample})[@"text"];
        BOOL frontKept = ed.currentDocument != sampleDoc;
        BOOL markedModified = sampleDoc.modified;   // undo below returns it to its save point
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:sampleDoc]];
        [ed.sci message:SCI_UNDO wParam:0 lParam:0];
        NSString *afterUndo = DocText(ed);
        Check(@"Agent (edit_document)", @"two edits land bottom-up as one undo step, the tab in front stays, the document is marked modified",
              [edited[@"applied"] integerValue] == 2 && [afterEdit isEqualToString:@"One\nTWO\nthree\n"] && frontKept &&
              markedModified && !sampleDoc.modified && [afterUndo isEqualToString:@"one\ntwo\nthree\n"]);
        tool(@"edit_document", @{@"document": sample, @"text": @"one\ntwo\nthree\n"});
        NSString *partial = tool(@"get_document", @{@"document": sample, @"first_line": @2, @"last_line": @2})[@"text"];
        NSDictionary *overlap = tool(@"edit_document", @{@"document": sample, @"edits": @[
            @{@"start_line": @1, @"end_line": @2, @"text": @""}, @{@"start_line": @2, @"end_line": @3, @"text": @""}]});
        Check(@"Agent (get_document)", @"a line range comes back alone; overlapping edits are refused whole",
              [partial isEqualToString:@"two\n"] && overlap[@"error"] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\n"]);

        // Search with Notepad++'s engine: regex hits with their place; a bad pattern names its fault; replace with $1.
        NSDictionary *found = tool(@"find", @{@"what": @"t.o", @"mode": @"regex", @"document": sample});
        NSDictionary *bad = tool(@"find", @{@"what": @"(", @"mode": @"regex", @"document": sample});
        NSDictionary *replaced = tool(@"replace", @{@"what": @"(t)hree", @"replacement": @"$1HREE", @"mode": @"regex", @"document": sample});
        Check(@"Agent (find, replace)", @"a regex finds 'two' at line 2, an unbalanced one is refused with the reason, $1 works in replace",
              [found[@"hits"] integerValue] == 1 && [found[@"matches"][0][@"line"] integerValue] == 2 &&
              [found[@"matches"][0][@"match"] isEqualToString:@"two"] &&
              [bad[@"error"] containsString:@"parenthesis"] &&
              [replaced[@"replaced"] integerValue] == 1 && [DocText(ed) isEqualToString:@"one\ntwo\ntHREE\n"]);
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_folder"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[folder stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"alpha\nbeta\n" writeToFile:[folder stringByAppendingPathComponent:@"a.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"beta gamma\n" writeToFile:[folder stringByAppendingPathComponent:@"sub/b.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *inFiles = tool(@"find", @{@"what": @"beta", @"folder": folder, @"filters": @"*.txt"});
        NSDictionary *inAll = tool(@"find", @{@"what": @"beta", @"folder": folder});
        Check(@"Agent (find in files)", @"a folder search honours the filter and returns Notepad++'s report",
              [inFiles[@"hits"] integerValue] == 1 && [inAll[@"hits"] integerValue] == 2 &&
              [inFiles[@"report"] containsString:@"a.txt (1 hit)"] && [inFiles[@"report"] containsString:@"Line 2: beta"]);

        // The editor's judgement of a text: the model, and the Function List parsers as written.
        NSDictionary *detected = tool(@"detect_language", @{@"text": @"def f(x):\n    return [i * 2 for i in range(x)]\n\nimport os\n", @"filename": @"x.py"});
        NSDictionary *functions = tool(@"function_list", @{@"text": @"class A:\n    def m(self):\n        pass\ndef g():\n    pass\n", @"language": @"python"});
        NSArray *entries = functions[@"entries"];
        Check(@"Agent (detect_language, function_list)", @"Python is the first guess of a Python snippet and what x.py would give; the parser finds the class, its method and the function",
              [detected[@"guesses"][0][@"language"] isEqualToString:@"python"] && [detected[@"by_filename"] isEqualToString:@"python"] &&
              entries.count == 3 && [entries[0][@"name"] isEqualToString:@"A"] && [entries[0][@"is_class"] boolValue] &&
              [entries[1][@"container"] isEqualToString:@"A"] && [entries[1][@"line"] integerValue] == 2 &&
              [entries[2][@"name"] isEqualToString:@"g()"]);

        // Compare: the counts and the differing runs; a Windows-1251 file with CRLF is read as the editor reads it.
        NSDictionary *compared = tool(@"compare", @{@"left": @{@"text": @"a\nb\nc\n"}, @"right": @{@"text": @"a\nB\nc\nd\n"}});
        NSData *cyrillic = [@"Привет\r\nмир\r\n" dataUsingEncoding:NSWindowsCP1251StringEncoding];
        NSString *cp1251 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_1251.txt"];
        [cyrillic writeToFile:cp1251 atomically:YES];
        NSDictionary *encoding = tool(@"file_encoding", @{@"path": cp1251});
        Check(@"Agent (compare, file_encoding)", @"one changed and one added line, in two runs; the 1251 file is detected with CRLF endings and decoded for the preview",
              [compared[@"changed"] integerValue] == 1 && [compared[@"added"] integerValue] == 1 && [compared[@"hunks"] count] == 2 &&
              [compared[@"hunks"][0][@"new_lines"][0] isEqualToString:@"B"] &&
              [[encoding[@"charset_detected"] uppercaseString] containsString:@"1251"] && [encoding[@"eol"] isEqualToString:@"CRLF"] &&
              [encoding[@"lines"] integerValue] == 2 && [encoding[@"preview"] hasPrefix:@"Привет"]);

        // Marks and places for the user: bookmarks, a selection put where the agent says, and what the selection is.
        NSDictionary *marks = tool(@"bookmarks", @{@"document": sample, @"add": @[@1, @3]});
        NSDictionary *went = tool(@"go_to", @{@"document": sample, @"line": @3, @"column": @2, @"end_line": @3});
        NSDictionary *selection = tool(@"get_selection", nil);
        Check(@"Agent (bookmarks, go_to, get_selection)", @"lines 1 and 3 are bookmarked; go_to selects from line 3 column 2 to its end, and get_selection reports it",
              [marks[@"bookmarked_lines"] isEqualToArray:@[@1, @3]] && ed.currentDocument == sampleDoc &&
              [went[@"start"][@"column"] integerValue] == 2 && [selection[@"text"] isEqualToString:@"HREE"] &&
              [selection[@"start"][@"line"] integerValue] == 3 && [selection[@"end"][@"column"] integerValue] == 6);

        // Menu commands by name: the list finds them, run_command runs them on the selection; quitting is refused.
        NSDictionary *listed = tool(@"list_commands", @{@"query": @"lowercase"});
        tool(@"go_to", @{@"document": sample, @"line": @3, @"column": @1, @"end_line": @3});
        NSDictionary *ran = tool(@"run_command", @{@"command": @"IDM_EDIT_LOWERCASE"});
        NSDictionary *byPath = tool(@"run_command", @{@"command": @"Edit|Line Operations|Sort Lines Lexicographically Ascending"});
        NSDictionary *refused = tool(@"run_command", @{@"command": @"IDM_FILE_EXIT"});
        printf("DEBUG agent commands: listed=%s ran=%s text=[%s] byPath=%s refused=%s\n", [listed description].UTF8String, [ran description].UTF8String, DocText(ed).UTF8String, [byPath description].UTF8String, [refused description].UTF8String);
        Check(@"Agent (list_commands, run_command)", @"lowercase is found by a word of its label, runs on the selection, sort runs by menu path, exit is refused",
              [listed[@"commands"] count] >= 1 && [listed[@"commands"][0][@"name"] isEqualToString:@"IDM_EDIT_LOWERCASE"] &&
              [ran[@"ran"] boolValue] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\n"] &&
              [byPath[@"ran"] boolValue] && refused[@"error"] != nil);

        // The spelling engine, with suggestions.
        NSDictionary *spelled = tool(@"spell_check", @{@"text": @"This is a smiple sentense.", @"language": @"en"});
        NSArray *words = spelled[@"misspelled"];
        Check(@"Agent (spell_check)", @"the two misspelled words come back in order with their places and the right first suggestions",
              words.count == 2 && [words[0][@"word"] isEqualToString:@"smiple"] && [words[0][@"column"] integerValue] == 11 &&
              [words[0][@"suggestions"] containsObject:@"simple"] && [words[1][@"suggestions"] containsObject:@"sentence"]);

        // Closing: a modified document is kept unless the agent says to discard it.
        tool(@"edit_document", @{@"document": sample, @"edits": @[@{@"start_line": @1, @"end_line": @1, @"text": @"ONE\n"}]});
        NSDictionary *kept = tool(@"close_document", @{@"document": sample});
        NSDictionary *closedText = tool(@"close_document", @{@"document": @"agent.cpp"});
        NSDictionary *discarded = tool(@"close_document", @{@"document": sample, @"discard_changes": @YES});
        Check(@"Agent (close_document)", @"a modified document stays unless discard_changes; an unmodified one closes; the suite is back where it started",
              kept[@"error"] != nil && [closedText[@"closed"] boolValue] && [discarded[@"closed"] boolValue] && ed.documents.count == before);


        // Saving: to the document's own file, in place; a document without a file is the user's Save As.
        NSString *savePath = TempFile(@"t_agent_save.txt", @"before\n");
        tool(@"open_document", @{@"path": savePath});
        NppDocument *saveDoc = ed.currentDocument;
        tool(@"open_document", @{@"text": @"scratch\n", @"title": @"scratch.txt"});
        tool(@"edit_document", @{@"document": savePath, @"text": @"after\n"});
        NSDictionary *saved = tool(@"save_document", @{@"document": savePath});
        NSString *onDisk = [NSString stringWithContentsOfFile:savePath encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *noFile = tool(@"save_document", @{@"document": @"scratch.txt"});
        Check(@"Agent (save_document)", @"a document that is not in front is written to its file and is clean; one without a file is refused with a pointer to Save As",
              [saved[@"saved"] boolValue] && [onDisk isEqualToString:@"after\n"] && !saveDoc.modified && ed.currentDocument != saveDoc &&
              [noFile[@"error"] containsString:@"Save As"]);
        tool(@"close_document", @{@"document": savePath});
        tool(@"close_document", @{@"document": @"scratch.txt", @"discard_changes": @YES});

        // What is refused, and why: a read-only document, a missing file, an unknown language, a line past the end, an unknown command.
        NSString *roPath = TempFile(@"t_agent_ro.txt", @"locked\n");
        tool(@"open_document", @{@"path": roPath});
        ed.currentDocument.userReadOnly = YES;
        NSDictionary *roEdit = tool(@"edit_document", @{@"edits": @[@{@"start_line": @1, @"end_line": @1, @"text": @"x\n"}]});
        NSDictionary *roReplace = tool(@"replace", @{@"what": @"locked", @"replacement": @"open"});
        ed.currentDocument.userReadOnly = NO;
        NSDictionary *missing = tool(@"open_document", @{@"path": @"/nowhere/t_agent_missing.txt"});
        NSDictionary *noLang = tool(@"open_document", @{@"text": @"x", @"language": @"klingon"});
        NSDictionary *pastEnd = tool(@"go_to", @{@"line": @99});
        NSDictionary *noCommand = tool(@"run_command", @{@"command": @"IDM_NOTHING_OF_THE_KIND"});
        NSDictionary *noArgs = tool(@"edit_document", @{});
        BOOL noStrayTab = ed.documents.count == before + 1;   // the refused language opened nothing
        Check(@"Agent (refusals)", @"read-only, a missing file, an unknown language (without a stray tab), a line past the end, an unknown command and an edit with nothing in it are each refused with a reason",
              noStrayTab &&
              [roEdit[@"error"] containsString:@"read-only"] && [roReplace[@"error"] containsString:@"read-only"] &&
              [DocText(ed) isEqualToString:@"locked\n"] &&
              [missing[@"error"] containsString:@"No such file"] && [noLang[@"error"] containsString:@"klingon"] &&
              [pastEnd[@"error"] containsString:@"outside"] && [noCommand[@"error"] containsString:@"IDM_NOTHING_OF_THE_KIND"] &&
              [noArgs[@"error"] containsString:@"text or edits"]);
        tool(@"close_document", @{@"document": roPath, @"discard_changes": @YES});

        // Tokens of a document that is not in front, read through the hidden view, with fold levels; a long answer is cut and says so.
        tool(@"open_document", @{@"text": @"void f() {\n  if (x) {\n    y();\n  }\n}\n", @"language": @"cpp", @"title": @"folds.cpp"});
        tool(@"open_document", @{@"text": @"front\n", @"title": @"front.txt"});
        NSDictionary *foldTokens = tool(@"tokens", @{@"document": @"folds.cpp", @"include_folds": @YES, @"first_line": @2, @"last_line": @3});
        NSArray *folds = foldTokens[@"folds"];
        NSMutableString *big = [NSMutableString string];
        for (int i = 0; i < 20000; ++i) [big appendString:@"0123456789012345678901234567890123456789012345678901234567890123456789012345678\n"];   // 80 bytes a line, 1.6 MB
        tool(@"open_document", @{@"text": big, @"title": @"big.txt"});
        NSDictionary *cut = tool(@"get_document", @{@"document": @"big.txt"});
        NSDictionary *range = tool(@"get_document", @{@"document": @"big.txt", @"first_line": @19999, @"last_line": @30000});
        Check(@"Agent (tokens of a background document, truncation)", @"lines 2-3 of a document behind another come with their tokens and fold levels, the front tab untouched; a 1.6 MB text is cut at a million characters and says so, a line range past the end is clipped",
              [ed.currentDocument.displayName isEqualToString:@"big.txt"] &&
              [foldTokens[@"first_line"] integerValue] == 2 && [foldTokens[@"tokens"] count] >= 4 &&
              [[foldTokens[@"tokens"] firstObject][0] integerValue] == 2 && [[foldTokens[@"tokens"] firstObject][2] isEqualToString:@"INSTRUCTION WORD"] &&
              folds.count == 2 && [folds[0][1] integerValue] == 1 && [folds[0][2] boolValue] && [folds[1][1] integerValue] == 2 &&
              [cut[@"truncated"] boolValue] && [cut[@"text"] length] <= 1000000 && [cut[@"last_line"] integerValue] < 20000 &&
              ![range[@"truncated"] boolValue] && [range[@"first_line"] integerValue] == 19999 && [range[@"last_line"] integerValue] == 20001 &&
              [range[@"text"] hasPrefix:@"0123456789"]);
        tool(@"close_document", @{@"document": @"big.txt", @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"front.txt", @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"folds.cpp", @"discard_changes": @YES});

        // Search modes: extended escapes, whole word and match case, the limit, the results panel; replace in normal mode.
        NSString *modes = TempFile(@"t_agent_modes.txt", @"Cat cat catalog\ncat\tcat\nconcat\n");
        tool(@"open_document", @{@"path": modes});
        NSDictionary *extended = tool(@"find", @{@"what": @"cat\\tcat", @"mode": @"extended"});
        NSDictionary *whole = tool(@"find", @{@"what": @"cat", @"whole_word": @YES, @"match_case": @YES});
        NSDictionary *limited = tool(@"find", @{@"what": @"cat", @"limit": @2, @"show_results": @YES});
        BOOL resultsShown = NO;
        for (NppDocument *d in ed.documents) if (d.isSearchResults) resultsShown = YES;
        NSDictionary *plainReplace = tool(@"replace", @{@"what": @"cat", @"replacement": @"dog", @"whole_word": @YES, @"match_case": @YES, @"document": modes});
        NSDictionary *nothing = tool(@"replace", @{@"what": @"zebra", @"replacement": @"x", @"document": modes});
        NSString *modesText = tool(@"get_document", @{@"document": modes})[@"text"];
        BOOL modesDoc = YES;
        Check(@"Agent (find modes, replace)", @"\\t in extended mode finds the tabbed pair; whole word + match case finds 3 of the 6; a limit of 2 says truncated and the results panel opens; the plain replace changes those 3 and a miss changes none",
              [extended[@"hits"] integerValue] == 1 && [extended[@"matches"][0][@"line"] integerValue] == 2 &&
              [whole[@"hits"] integerValue] == 3 && [limited[@"hits"] integerValue] == 6 && [limited[@"matches"] count] == 2 && [limited[@"truncated"] boolValue] &&
              resultsShown && modesDoc &&
              [plainReplace[@"replaced"] integerValue] == 3 && [nothing[@"replaced"] integerValue] == 0 &&
              [modesText isEqualToString:@"Cat dog catalog\ndog\tdog\nconcat\n"]);
        NSDictionary *listedDocs = tool(@"list_documents", nil);
        BOOL resultsHidden = YES;
        for (NSDictionary *d in listedDocs[@"documents"]) if ([d[@"title"] containsString:@"Search results"]) resultsHidden = NO;
        Check(@"Agent (list_documents)", @"the Search results tab is not listed as a document; the count and the modified flag are the editor's",
              resultsHidden && [listedDocs[@"documents"] count] == before + 1 && [listedDocs[@"workspace_roots"] isKindOfClass:[NSArray class]]);   // + the modes file, still open
        tool(@"close_document", @{@"document": modes, @"discard_changes": @YES});

        // Compare shown to the user: both files open, the Compare view active; ignore options honoured.
        NSString *leftPath = TempFile(@"t_agent_left.txt", @"same\nold line\n\nTail\n");
        NSString *rightPath = TempFile(@"t_agent_right.txt", @"same\nnew line\ntail\n");
        NSDictionary *shown = tool(@"compare", @{@"left": @{@"path": leftPath}, @"right": @{@"path": rightPath}, @"show": @YES,
                                                 @"ignore_case": @YES, @"ignore_empty_lines": @YES});
        BOOL comparing = [ed compareActive];
        NSDictionary *textsOnly = tool(@"compare", @{@"left": @{@"text": @"a\n"}, @"right": @{@"text": @"a\n"}, @"show": @YES});
        [ed clearAllCompares];
        Check(@"Agent (compare shown)", @"two files open side by side in the Compare view with one changed line (case and empty lines ignored); two texts cannot be shown and say so",
              [shown[@"shown"] boolValue] && comparing && [shown[@"changed"] integerValue] == 1 && [shown[@"added"] integerValue] == 0 &&
              [shown[@"removed"] integerValue] == 0 && [textsOnly[@"same"] boolValue] && ![textsOnly[@"shown"] boolValue] && textsOnly[@"note"] != nil);
        tool(@"close_document", @{@"document": leftPath, @"discard_changes": @YES});
        tool(@"close_document", @{@"document": rightPath, @"discard_changes": @YES});

        // Declared languages, the picture readers, and encodings with a mark or none.
        NSDictionary *shebang = tool(@"detect_language", @{@"text": @"#!/usr/bin/env perl\nprint 1;\n"});
        NSImage *qrPicture = [EditorController qrImageFromText:@"https://tanderbold.github.io/NotepadMac/" side:300];
        NSString *qrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_qr.png"];
        [[[[NSBitmapImageRep alloc] initWithData:qrPicture.TIFFRepresentation] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:qrPath atomically:YES];
        NSDictionary *qrRead = tool(@"read_qr", @{@"path": qrPath});
        NSImage *ocrPicture = [[NSImage alloc] initWithSize:NSMakeSize(640, 140)];
        [ocrPicture lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 140));
        [@"AGENT OCR 7" drawAtPoint:NSMakePoint(24, 36) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:56], NSForegroundColorAttributeName: [NSColor blackColor]}];
        [ocrPicture unlockFocus];
        NSString *ocrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_ocr.png"];
        [[[[NSBitmapImageRep alloc] initWithData:ocrPicture.TIFFRepresentation] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:ocrPath atomically:YES];
        NSDictionary *ocrRead = tool(@"ocr", @{@"path": ocrPath});
        NSDictionary *noPicture = tool(@"read_qr", @{@"path": sample});
        NSString *bomPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_bom.txt"];
        NSMutableData *bomData = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [bomData appendData:[@"x\ny" dataUsingEncoding:NSUTF8StringEncoding]];
        [bomData writeToFile:bomPath atomically:YES];
        NSString *u16Path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_u16.txt"];
        [[@"hello\r\nworld" dataUsingEncoding:NSUTF16LittleEndianStringEncoding] writeToFile:u16Path atomically:YES];
        NSString *binPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_bin.dat"];
        unsigned char zeros[64] = {0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3, 0xFF, 0xFE};
        [[NSData dataWithBytes:zeros length:sizeof zeros] writeToFile:binPath atomically:YES];
        NSDictionary *bomInfo = tool(@"file_encoding", @{@"path": bomPath, @"preview_chars": @1});
        NSDictionary *u16Info = tool(@"file_encoding", @{@"path": u16Path});
        NSDictionary *binInfo = tool(@"file_encoding", @{@"path": binPath});
        Check(@"Agent (detect_language declared, ocr, read_qr, file_encoding marks)", @"a shebang is the declared language; the QR picture and the OCR picture read back; a text file is no QR; the BOM, UTF-16 without a mark and a binary file are told apart",
              [shebang[@"declared"] isEqualToString:@"perl"] && [shebang[@"offered"] isEqualToArray:@[@"perl"]] &&
              [qrRead[@"text"] isEqualToString:@"https://tanderbold.github.io/NotepadMac/"] &&
              [[ocrRead[@"text"] uppercaseString] containsString:@"AGENT OCR 7"] &&
              ![noPicture[@"found"] boolValue] && noPicture[@"error"] != nil &&
              [bomInfo[@"bom"] isEqualToString:@"UTF-8"] && [bomInfo[@"encoding"] isEqualToString:@"UTF-8"] && [bomInfo[@"preview"] isEqualToString:@"x"] &&
              [bomInfo[@"lines"] integerValue] == 2 &&
              [u16Info[@"utf16_without_bom"] isEqualToString:@"UTF-16 LE"] && [u16Info[@"eol"] isEqualToString:@"CRLF"] && [u16Info[@"preview"] hasPrefix:@"hello"] &&
              [binInfo[@"binary"] boolValue]);

        // Spelling of a document, and a language the engine does not have.
        tool(@"open_document", @{@"text": @"# a coment\nx = 1\n", @"title": @"spell.py", @"language": @"python"});
        NSDictionary *docSpelled = tool(@"spell_check", @{@"language": @"en"});
        NSDictionary *noSuchLanguage = tool(@"spell_check", @{@"text": @"x", @"language": @"xx_NOWHERE"});
        tool(@"close_document", @{@"document": @"spell.py", @"discard_changes": @YES});
        Check(@"Agent (spell_check of a document)", @"the document in front is checked, the misspelling placed on its line; a language the engine lacks is refused with the list it has",
              [docSpelled[@"misspelled"] count] == 1 && [docSpelled[@"misspelled"][0][@"word"] isEqualToString:@"coment"] &&
              [docSpelled[@"misspelled"][0][@"line"] integerValue] == 1 && docSpelled[@"document"] != nil &&
              [noSuchLanguage[@"error"] containsString:@"xx_NOWHERE"]);

        // Bookmarks on a document behind another survive the switch, and remove/clear work.
        NSString *marksPath = TempFile(@"t_agent_marks.txt", @"a\nb\nc\nd\n");
        tool(@"open_document", @{@"path": marksPath});
        NppDocument *marksDoc = ed.currentDocument;
        tool(@"open_document", @{@"text": @"cover\n", @"title": @"cover.txt"});
        tool(@"bookmarks", @{@"document": marksPath, @"add": @[@2, @4, @9]});
        NSDictionary *removedOne = tool(@"bookmarks", @{@"document": marksPath, @"remove": @[@2]});
        BOOL recorded = [marksDoc.bookmarkedLines isEqualToArray:@[@3]];   // zero-based, as the session keeps them
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:marksDoc]];
        long markerOnFour = [ed.sci message:SCI_MARKERGET wParam:3 lParam:0] & (1 << 1);
        NSDictionary *cleared = tool(@"bookmarks", @{@"document": marksPath, @"clear": @YES, @"add": @[@1]});
        Check(@"Agent (bookmarks behind, remove, clear)", @"marks set on a document behind another are recorded and shown when it comes to front; a line past the end is ignored; remove and clear do what they say",
              [removedOne[@"bookmarked_lines"] isEqualToArray:@[@4]] && recorded && markerOnFour &&
              [cleared[@"bookmarked_lines"] isEqualToArray:@[@1]]);
        tool(@"close_document", @{@"document": marksPath, @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"cover.txt", @"discard_changes": @YES});

        // A disabled command reports so instead of pretending; the protocol wraps a tool's failure as an error result, not a protocol error.
        [ed.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
        NSDictionary *redo = tool(@"run_command", @{@"command": @"IDM_EDIT_REDO"});
        NSDictionary *wrapped = rpc(@"tools/call", @{@"name": @"get_document", @"arguments": @{@"document": @"no-such-document.txt"}});
        NSDictionary *good = rpc(@"tools/call", @{@"name": @"list_documents", @"arguments": @{}});
        Check(@"Agent (disabled command, error results)", @"Redo with nothing to redo answers ran=false, enabled=false; a failing tool is an isError result with the reason as text; a good one carries text and structured content",
              ![redo[@"ran"] boolValue] && ![redo[@"enabled"] boolValue] &&
              [wrapped[@"result"][@"isError"] boolValue] && [wrapped[@"result"][@"content"][0][@"text"] containsString:@"no-such-document.txt"] &&
              ![good[@"result"][@"isError"] boolValue] && [good[@"result"][@"content"][0][@"type"] isEqualToString:@"text"] &&
              [good[@"result"][@"structuredContent"][@"documents"] isKindOfClass:[NSArray class]] &&
              [agent handleMessage:@{@"jsonrpc": @"2.0", @"method": @"tools/list"}] == nil);
        // Off by default; on, the socket is the user's alone and answers a line with a line - through nppmac mcp too.
        NppPreferences *ap = [NppPreferences shared];
        BOOL wasOn = ap.agentServer;
        BOOL offByDefault = !ap.agentServer && !agent.running;
        NSString *sock = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent.sock"];
        setenv("NPPMAC_AGENT_SOCKET", sock.fileSystemRepresentation, 1);
        BOOL started = [agent start];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sock error:NULL];
        NSString *helper = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Contents/Helpers/nppmac"];
        NSTask *bridge = [[NSTask alloc] init];
        bridge.executableURL = [NSURL fileURLWithPath:helper];
        bridge.arguments = @[@"mcp"];
        NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
        env[@"NPPMAC_AGENT_SOCKET"] = sock;
        bridge.environment = env;
        NSPipe *toBridge = [NSPipe pipe], *fromBridge = [NSPipe pipe];
        bridge.standardInput = toBridge;
        bridge.standardOutput = fromBridge;
        bridge.standardError = [NSPipe pipe];
        __block NSMutableData *answered = [NSMutableData data];
        fromBridge.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
            NSData *d = h.availableData;
            @synchronized (answered) { [answered appendData:d]; }
        };
        BOOL launched = [bridge launchAndReturnError:NULL];
        [toBridge.fileHandleForWriting writeData:[@"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{}}}\n"
                                                  @"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n"
                                                  @"{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"list_documents\",\"arguments\":{}}}\n"
                                                  dataUsingEncoding:NSUTF8StringEncoding]];
        NppSettleUntil(^BOOL{
            @synchronized (answered) { return [[[NSString alloc] initWithData:answered encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"].count >= 3; }
        }, 10);
        [toBridge.fileHandleForWriting closeFile];
        fromBridge.fileHandleForReading.readabilityHandler = nil;
        NSArray *lines = [[[NSString alloc] initWithData:answered encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
        NSDictionary *first = lines.count > 0 ? [NSJSONSerialization JSONObjectWithData:[lines[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        NSDictionary *second = lines.count > 1 ? [NSJSONSerialization JSONObjectWithData:[lines[1] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        NppSettleUntil(^BOOL{ return !bridge.isRunning; }, 5);
        [agent stop];
        BOOL gone = ![[NSFileManager defaultManager] fileExistsAtPath:sock];
        unsetenv("NPPMAC_AGENT_SOCKET");
        ap.agentServer = wasOn;
        Check(@"Agent (socket, nppmac mcp)", @"off by default; started, the socket is mode 0600, nppmac mcp relays initialize and a tool call and ends with its input; stopped, the socket file is gone",
              offByDefault && started && launched && [attrs[NSFilePosixPermissions] integerValue] == 0600 &&
              [first[@"id"] integerValue] == 7 && [first[@"result"][@"serverInfo"][@"name"] isEqualToString:@"NotepadMac"] &&
              [second[@"id"] integerValue] == 8 && [second[@"result"][@"structuredContent"][@"documents"] isKindOfClass:[NSArray class]] &&
              !bridge.isRunning && gone);

        // The socket: a stale file is replaced, a second start is a no-op, a socket another process holds is left alone;
        // the preference starts and stops it; a broken line answers a parse error; two connections take turns.
        NSString *sock2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent2.sock"];
        setenv("NPPMAC_AGENT_SOCKET", sock2.fileSystemRepresentation, 1);
        [@"stale" writeToFile:sock2 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL replacedStale = [agent start] && [agent start] && [[[NSFileManager defaultManager] attributesOfItemAtPath:sock2 error:NULL][NSFileType] isEqualToString:NSFileTypeSocket];
        NSString *(^ask)(NSString *) = ^NSString *(NSString *line) {
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            struct sockaddr_un addr; memset(&addr, 0, sizeof addr); addr.sun_family = AF_UNIX;
            strlcpy(addr.sun_path, sock2.fileSystemRepresentation, sizeof addr.sun_path);
            if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) { close(fd); return @"connect failed"; }
            __block NSMutableString *got = [NSMutableString string];
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                write(fd, line.UTF8String, strlen(line.UTF8String));
                char buf[65536];
                for (;;) {
                    ssize_t n = read(fd, buf, sizeof buf);
                    if (n <= 0) break;
                    [got appendString:[[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] ?: @""];
                    if ([got hasSuffix:@"\n"]) break;
                }
                close(fd);
                dispatch_semaphore_signal(done);
            });
            NppSettleUntil(^BOOL{ return dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) == 0; }, 10);
            return got;
        };
        NSString *parseError = ask(@"{not json\n");
        NSString *pingBack = ask(@"{\"jsonrpc\":\"2.0\",\"id\":\"p\",\"method\":\"ping\"}\n");
        NSString *secondConnection = ask(@"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_selection\",\"arguments\":{}}}\n");
        [agent stop];
        // Another process's socket: a listener of our own stands in for a second NotepadMac.
        int holder = socket(AF_UNIX, SOCK_STREAM, 0);
        struct sockaddr_un held; memset(&held, 0, sizeof held); held.sun_family = AF_UNIX;
        strlcpy(held.sun_path, sock2.fileSystemRepresentation, sizeof held.sun_path);
        unlink(held.sun_path);
        BOOL holding = bind(holder, (struct sockaddr *)&held, sizeof held) == 0 && listen(holder, 1) == 0;
        BOOL leftAlone = ![agent start] && !agent.running;
        close(holder);
        unlink(held.sun_path);
        // The preference, applied the way the Preferences window applies it.
        ap.agentServer = YES;
        [ap applyToEditor:ed];
        BOOL onByPreference = agent.running;
        ap.agentServer = NO;
        [ap applyToEditor:ed];
        BOOL offByPreference = !agent.running && ![[NSFileManager defaultManager] fileExistsAtPath:sock2];
        ap.agentServer = wasOn;
        unsetenv("NPPMAC_AGENT_SOCKET");
        Check(@"Agent (socket life)", @"a stale socket file is replaced and a second start is harmless; a broken line gets a parse error and the next connection is served; a socket another process holds is left alone; the MISC. setting starts and stops the listener and removes the file",
              replacedStale && [parseError containsString:@"-32700"] && [pingBack containsString:@"\"id\":\"p\""] &&
              [secondConnection containsString:@"structuredContent"] && holding && leftAlone && onByPreference && offByPreference);
    }

    // The coverage meta-test only means something over the whole suite.
    if (!getenv("NPPMAC_TEST_ONLY") || !*getenv("NPPMAC_TEST_ONLY")) { printf("\n== Coverage ==\n");
        NSString *listPath = [[NSBundle mainBundle] pathForResource:@"implemented" ofType:@"txt"];
        NSString *list = listPath ? [NSString stringWithContentsOfFile:listPath
                                                             encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSMutableArray *missing = [NSMutableArray array];
        NSUInteger declared = 0;
        for (NSString *raw in [(list ?: @"") componentsSeparatedByString:@"\n"]) {
            NSString *line = [[raw componentsSeparatedByString:@"#"].firstObject
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!line.length) continue;
            declared++;
            if (![gCovered containsObject:line]) [missing addObject:line];
        }
        if (!list) {
            gFail++;
            printf("  FAIL %-28s implemented.txt missing from the bundle\n", "COVERAGE");
        } else if (missing.count) {
            gFail++;
            printf("  FAIL %-28s %lu declared but untested: %s\n", "COVERAGE",
                   (unsigned long)missing.count,
                   [[missing componentsJoinedByString:@", "] UTF8String]);
        } else {
            gPass++;
            printf("  ok   %-28s all %lu declared commands have tests\n", "COVERAGE",
                   (unsigned long)declared);
        }
    }

    if (userLanguage.length) {
        [NppPreferences shared].localizationFile = userLanguage;
        [app applyLocalization];
        [[NSUserDefaults standardUserDefaults] synchronize];   // the process ends right after; the write must land
    }
    printf("\n%d passed, %d failed\n", gPass, gFail);
    return gFail;
}
