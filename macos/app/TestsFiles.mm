// The built-in suite, the File menu, sessions, file monitoring and the file dialogs as upstream has them.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// What AppKit hands a drag destination, for a drop made without the window server:
/// the pasteboard of the drag, where it is, what the source allows.
@interface NppTestDrop : NSObject
@property (nonatomic, strong) NSPasteboard *draggingPasteboard;
@property (nonatomic) NSPoint draggingLocation;
@property (nonatomic, weak) NSWindow *draggingDestinationWindow;
@end
@implementation NppTestDrop
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationCopy | NSDragOperationLink | NSDragOperationGeneric; }
- (id)draggingSource { return nil; }
- (NSInteger)draggingSequenceNumber { return 1; }
- (NSInteger)numberOfValidItemsForDrop { return 1; }
@end

/// Drops `paths` at the middle of `target` the way AppKit would: to the deepest view under the
/// point that takes file URLs, entered, performed and concluded. Returns that view.
static NSView *DropPaths(NSArray<NSString *> *paths, NSView *target) {
    NSWindow *window = target.window;
    NSRect shown = target.visibleRect;             // the text view is as tall as the document
    NSPoint inWindow = [target convertPoint:NSMakePoint(NSMidX(shown), NSMidY(shown)) toView:nil];
    NSView *frame = window.contentView.superview;
    NSView *view = [frame hitTest:[frame convertPoint:inWindow fromView:nil]];
    while (view && ![view.registeredDraggedTypes containsObject:NSPasteboardTypeFileURL]) view = view.superview;
    NSMutableArray *urls = [NSMutableArray array];
    for (NSString *path in paths) [urls addObject:[NSURL fileURLWithPath:path]];
    NSPasteboard *board = [NSPasteboard pasteboardWithUniqueName];
    [board clearContents];
    [board writeObjects:urls];
    NppTestDrop *drop = [[NppTestDrop alloc] init];
    drop.draggingPasteboard = board;
    drop.draggingLocation = inWindow;
    drop.draggingDestinationWindow = window;
    id<NSDraggingDestination> destination = (id<NSDraggingDestination>)(view ?: (id)window.delegate);
    id<NSDraggingInfo> info = (id<NSDraggingInfo>)drop;
    if ([destination draggingEntered:info] != NSDragOperationNone &&
        (![destination respondsToSelector:@selector(prepareForDragOperation:)] || [destination prepareForDragOperation:info]))
        [destination performDragOperation:info];
    if ([destination respondsToSelector:@selector(concludeDragOperation:)]) [destination concludeDragOperation:info];
    [board releaseGlobally];
    return view;
}

/// == File ==; == File: more ==; == File: close family ==; == File: folders and workspace ==; == Sessions ==
void NppTestsFiles(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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

            [ed setDocumentText:@"café cafés яблоко\n"];
            NSUInteger wholeCafe = [ed countMatches:[NppFindSpec specFor:@"café" mode:NppSearchNormal options:NppFindWholeWord | NppFindMatchCase]];
            NSUInteger cyrillicWords = [ed countMatches:[NppFindSpec specFor:@"\\b\\w+\\b" mode:NppSearchRegex options:0]];
            Check(@"IDM_SEARCH_FIND", @"whole word and \\w, \\b know every script, as Boost's do (PCRE2_UCP)",
                  wholeCafe == 1 && cyrillicWords == 3);
            Check(@"IDM_SEARCH_FIND", @"a pattern the engine refuses is invalid (the dialog says so), a literal \"(\" is not",
                  ![ed patternIsValid:[NppFindSpec specFor:@"(" mode:NppSearchRegex options:0]] &&
                  ![ed patternIsValid:[NppFindSpec specFor:@"a{2,1}" mode:NppSearchRegex options:0]] &&
                  [ed patternIsValid:[NppFindSpec specFor:@"(" mode:NppSearchNormal options:0]]);
            // "Replace: Don't move to the following occurrence": the caret stays after
            // the replaced text (processReplace, _replaceStopsWithoutFindingNext).
            NppPreferences *rp = [NppPreferences shared];
            BOOL wasStay = rp.replaceStaysOnOccurrence;
            rp.replaceStaysOnOccurrence = YES;
            [ed setDocumentText:@"cat cat cat"];
            [ed.sci message:SCI_SETSEL wParam:0 lParam:3];
            NppFindSpec *cat = [NppFindSpec specFor:@"cat" mode:NppSearchNormal options:NppFindWrap];
            cat.replacement = @"dog";
            [ed replaceCurrentThenFindNext:cat];
            BOOL stayed = [[ed documentText] isEqualToString:@"dog cat cat"] &&
                          [ed.sci message:SCI_GETSELECTIONSTART] == 3 && [ed.sci message:SCI_GETSELECTIONEND] == 3;
            rp.replaceStaysOnOccurrence = wasStay;

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
            Check(@"IDM_SEARCH_REPLACE (don't move on)",
                  @"with Replace: Don't move to the following occurrence, the caret stays after the replacement",
                  stayed);
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
            [ed.sci message:SCI_SELECTALL];   // convertSelectedTextTo acts on a selection only
            [ed convertCase:NppCaseProperBlend];
            BOOL proper = [[ed documentText] isEqualToString:@"Don't 3rd"];
            [ed setDocumentText:@"hello. world\n\nnext i am"];
            [ed.sci message:SCI_SELECTALL];   // convertSelectedTextTo acts on a selection only
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
            void *closedPointer = shown.docPointer;
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:shown] discardChanges:YES];
            // Its last tab gone, the second view goes too (upstream hides a view left with no tabs).
            BOOL movedOff = (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] != closedPointer && ![ed secondaryViewVisible];
            [ed setSecondaryViewVisible:NO];
            [ed closeDocumentAtIndex:ed.documents.count - 1 discardChanges:YES];
            Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW (the pane survives a close)",
                  @"closing the cloned document takes the other pane off it; the view with no tabs left is hidden", movedOff);
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
            [ed.sci message:SCI_SELECTALL];   // convertSelectedTextTo acts on a selection only
            [ed convertCase:NppCaseProperForce];
            BOOL force = [[ed documentText] isEqualToString:@"Don't 3rd"];
            [ed setDocumentText:@"\"go.\" she said (i) i am"];
            [ed.sci message:SCI_SELECTALL];   // convertSelectedTextTo acts on a selection only
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
            // The port's own boxes are written by Apply too (SETTINGS-007/043/089).
            BOOL wasDetect = p.detectLanguageFromContent, wasMarks = p.gitMarginMarks, wasAgent = p.agentServer;
            PreferencesWindow *own = [[PreferencesWindow alloc] initWithEditor:ed];
            NSDictionary *ownControls = [own valueForKey:@"controls"];
            [ownControls[@"detectLanguageFromContent"] setState:wasDetect ? NSControlStateValueOff : NSControlStateValueOn];
            [ownControls[@"gitMarginMarks"] setState:wasMarks ? NSControlStateValueOff : NSControlStateValueOn];
            [ownControls[@"agentServer"] setState:wasAgent ? NSControlStateValueOn : NSControlStateValueOff];
            [own apply:nil];
            BOOL ownApplied = p.detectLanguageFromContent == !wasDetect && p.gitMarginMarks == !wasMarks;
            p.detectLanguageFromContent = wasDetect; p.gitMarginMarks = wasMarks; p.agentServer = wasAgent;
            [ed applyEditorPreferences];
            Check(@"IDM_SETTING_PREFERENCE (the port's boxes)",
                  @"Apply writes the content detection and Git margin boxes", ownApplied);
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
            // setUniModeText names a character set by its menu label, and the menu checks it.
            NSMenuItem *win1251 = nil, *koi8 = nil;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray)
                for (NSMenuItem *it in top.submenu.itemArray)
                    for (NSMenuItem *group in it.submenu.itemArray)
                        for (NSMenuItem *cs in group.submenu.itemArray) {
                            if (cs.action != NSSelectorFromString(@"encodeInCharset:")) continue;
                            if ([cs.title isEqualToString:@"Windows-1251"]) win1251 = cs;
                            if ([cs.title isEqualToString:@"KOI8-R"]) koi8 = cs;
                        }
            [(id<NSMenuItemValidation>)app validateMenuItem:win1251];
            [(id<NSMenuItemValidation>)app validateMenuItem:koi8];
            Check(@"IDM_FORMAT_WIN_1251", @"the status bar names the character set and the menu checks it",
                  [[ed encodingDisplayName] isEqualToString:@"Windows-1251"] && win1251 && koi8 &&
                  win1251.state == NSControlStateValueOn && koi8.state == NSControlStateValueOff);
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
        // Cmd+W typed in the Find window closes that window, not the document behind it (upstream
        // gives the main window's accelerators to the main window only).
        {
            [ed newDocument];
            NppDocument *behind = ed.currentDocument;
            NSUInteger count = ed.documents.count;
            [app performSelector:@selector(showFind:) withObject:nil];
            NSPanel *find = [app valueForKey:@"findPanel"];
            [find makeKeyAndOrderFront:nil];
            NppSettleUntil(^BOOL { return find.isKeyWindow; }, 2);
            BOOL wasKey = find.isKeyWindow;
            NSEvent *cmdW = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagCommand
                                            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:find.windowNumber context:nil
                                           characters:@"w" charactersIgnoringModifiers:@"w" isARepeat:NO keyCode:13];
            [NSApp postEvent:cmdW atStart:NO];
            NppSettleUntil(^BOOL { return !find.isVisible || ![ed.documents containsObject:behind]; }, 2);
            BOOL documentKept = [ed.documents containsObject:behind] && ed.documents.count == count;
            BOOL panelClosed = !find.isVisible;
            [find orderOut:nil];
            [ed.window makeKeyAndOrderFront:nil];
            if ([ed.documents containsObject:behind])
                [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:behind] discardChanges:YES];
            Check(@"IDM_FILE_CLOSE (typed in another window)",
                  @"Cmd+W in the Find window closes the Find window and leaves the document behind it open",
                  wasKey && documentKept && panelClosed);
        }
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

        // Files dropped on the text, most of the window: the text view is the deepest one under
        // the pointer that takes file URLs, so it gets the drop, not the window; they open as
        // Notepad_plus::dropFiles opens them, the last one in front. A folder alone opens as
        // Folder as Workspace; files and folders together are refused.
        {
            NSString *one = [dir stringByAppendingPathComponent:@"dropped one.txt"];
            NSString *two = [dir stringByAppendingPathComponent:@"dropped two.txt"];
            NSString *sub = [dir stringByAppendingPathComponent:@"dropped folder"];
            [@"1\n" writeToFile:one atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [@"2\n" writeToFile:two atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:sub withIntermediateDirectories:YES attributes:nil error:NULL];
            BOOL (^isOpen)(NSString *) = ^BOOL(NSString *path) {
                for (NppDocument *d in ed.documents) if ([d.path isEqualToString:path]) return YES;
                return NO;
            };
            NSView *receiver = DropPaths(@[one, two], ed.sci.content);
            NppSettleUntil(^BOOL { return isOpen(one) && isOpen(two); }, 3);
            BOOL textTookIt = receiver == (NSView *)ed.sci.content;
            BOOL bothOpen = isOpen(one) && isOpen(two);
            BOOL lastInFront = [ed.currentDocument.path isEqualToString:two];
            NSUInteger before = ed.documents.count;
            DropPaths(@[one, sub], ed.sci.content);
            NppSettle(0.2);
            BOOL mixedRefused = ed.documents.count == before && ![[ed workspaceRootPaths] containsObject:sub];
            DropPaths(@[sub], ed.sci.content);
            NppSettleUntil(^BOOL { return [[ed workspaceRootPaths] containsObject:sub]; }, 3);
            BOOL folderAsWorkspace = [[ed workspaceRootPaths] containsObject:sub];
            [ed openFolderAsWorkspace:nil];
            for (NSString *path in @[one, two]) {
                for (NSUInteger i = 0; i < ed.documents.count; ++i) {
                    if ([ed.documents[i].path isEqualToString:path]) { [ed closeDocumentAtIndex:(NSInteger)i discardChanges:YES]; break; }
                }
            }
            Check(@"File (dropped on the text)", @"files dropped on the text open, the last in front; a folder opens as a workspace; both together are refused",
                  textTookIt && bothOpen && lastInFront && mixedRefused && folderAsWorkspace);
        }
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
}

/// == Files: monitoring, ANSI, big files ==
void NppTestsFileMonitoring(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
}

/// == Session depth ==
void NppTestsSessionDepth(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        // Along the split's own axis: the views stand side by side, so the divider moves across.
        CGFloat (^extent)(NSView *) = ^CGFloat(NSView *v) { return viewSplit.vertical ? NSWidth(v.frame) : NSHeight(v.frame); };
        [viewSplit setPosition:extent(viewSplit) * 0.3 ofDividerAtIndex:0];
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
        double shareBack = extent(ed.sci) / MAX(1, extent(viewSplit));
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
        // A lone clean untitled tab gives its place to the file opened over it (FILE-007, loadBufferIntoView).
        BOOL loneClean = docsBeforeWin == 1 && !ed.documents[0].path && !ed.documents[0].modified;
        BOOL loadedWin = [ed loadSessionFrom:winSession error:NULL];
        NppDocument *fromWin = ed.currentDocument;
        BOOL windowsLoaded = loadedWin && [fromWin.path isEqualToString:foldFile] && fromWin.pinned && fromWin.userReadOnly &&
                             fromWin.tabColour == 3 && ed.documents.count == docsBeforeWin + (loneClean ? 0 : 1) &&
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
}

/// == Files as upstream ==
void NppTestsFilesAsUpstream(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
}
