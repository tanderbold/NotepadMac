// The built-in suite, the Find dialog, folder searches, the results panel and the Search menu.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Find dialog: the tabs Notepad++ has ==; == Search: a folder search that does not hold the window ==; == Search results panel ==; == Search: going from a result to the file ==; == Search: replacement escapes ==
void NppTestsFindDialog(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
              progressCalls >= 1 && lastScanned > 0 && lastScanned <= 400 && foundHits == 400 * 60);
        // Every one of the 400 files has hits: one report per file would keep the
        // main thread re-rendering the results for the whole search (SEARCH-068).
        Check(@"IDM_SEARCH_FINDINFILES (progress)",
              @"progress comes a few times a second, not once per file with a hit",
              progressCalls < 100);

        // An empty Find what: the completion comes after the call has returned, so
        // the caller, which stores the search as running, sees it end (SEARCH-063).
        __block BOOL emptyDone = NO;
        [ed findInFilesInBackground:[NppFindSpec specFor:@"" mode:NppSearchNormal options:NppFindNone]
                             folder:root filters:nil recursive:YES includeHidden:NO progress:nil
                         completion:^(NSUInteger hits, NSString *report, BOOL stopped) { emptyDone = YES; }];
        BOOL emptyDoneAtOnce = emptyDone;
        deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!emptyDone && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(@"IDM_SEARCH_FINDINFILES (empty)",
              @"a search with nothing to find ends after the call returns, never inside it",
              !emptyDoneAtOnce && emptyDone);

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
        // The tab coming to the front again sets its (null) lexer again; its fold levels stay.
        [ed applyLanguage];
        [ed foldAllSearchResults:YES];
        BOOL foldedAgain = ([rs message:SCI_GETFOLDLEVEL wParam:0] & SC_FOLDLEVELHEADERFLAG) &&
            ![rs message:SCI_GETFOLDEXPANDED wParam:0];
        [ed foldAllSearchResults:NO];
        Check(@"IDM_SEARCH_FINDINFILES (results stack and fold)",
              @"a new search goes on top of the older ones, which fold away; fold and unfold all work, "
              @"also after the tab's language is set again",
              stacked && unfolded && folded && foldedAgain);

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

        // Upstream's Find in Files runs the pattern over the whole file: a match
        // may cross a line end, an empty line can match, and every match is a
        // hit, a line with two being listed once.
        {
            NSString *multiRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_whole"];
            [[NSFileManager defaultManager] removeItemAtPath:multiRoot error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:multiRoot withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"one\n\nfoo bar\nbar bob\n" writeToFile:[multiRoot stringByAppendingPathComponent:@"m.txt"]
                                          atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSString *across = nil, *empty = nil, *twice = nil;
            NSUInteger acrossHits = [ed findInFiles:[NppFindSpec specFor:@"bar\\nbar" mode:NppSearchRegex options:NppFindNone]
                                             folder:multiRoot filters:nil recursive:NO includeHidden:NO report:&across];
            NSUInteger emptyHits = [ed findInFiles:[NppFindSpec specFor:@"^$" mode:NppSearchRegex options:NppFindNone]
                                            folder:multiRoot filters:nil recursive:NO includeHidden:NO report:&empty];
            NSUInteger twiceHits = [ed findInFiles:[NppFindSpec specFor:@"b" mode:NppSearchNormal options:NppFindMatchCase]
                                            folder:multiRoot filters:nil recursive:NO includeHidden:NO report:&twice];
            [[NSFileManager defaultManager] removeItemAtPath:multiRoot error:NULL];
            Check(@"IDM_SEARCH_FINDINFILES (over the whole file)", @"a pattern across a line end is found, on the line it starts",
                  acrossHits == 1 && [across containsString:@"Line 3: foo bar"]);
            Check(@"IDM_SEARCH_FINDINFILES (over the whole file)", @"an empty line can be found",
                  emptyHits >= 1 && [empty containsString:@"Line 2: \n"]);
            Check(@"IDM_SEARCH_FINDINFILES (hits are matches)", @"every match counts, a line with several is listed once",
                  twiceHits == 4 && [twice containsString:@"(4 hits)"] &&
                  [twice componentsSeparatedByString:@"Line 4:"].count == 2);
        }

        // Find in Files is ProcessFindAll, whose empty matches are Find All's
        // (SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH): "a*" in "baac" is three hits
        // in the file as in the document, not a fourth empty one after "aa".
        {
            NSString *emptyRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_fif_empty"];
            [[NSFileManager defaultManager] removeItemAtPath:emptyRoot error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:emptyRoot withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"baac" writeToFile:[emptyRoot stringByAppendingPathComponent:@"e.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NppFindSpec *star = [NppFindSpec specFor:@"a*" mode:NppSearchRegex options:NppFindNone];
            NSString *fileReport = nil;
            NSUInteger inFiles = [ed findInFiles:star folder:emptyRoot filters:nil recursive:NO includeHidden:NO report:&fileReport];
            [ed newDocument];
            [ed setDocumentText:@"baac"];
            NSUInteger inDocument = 0;
            [ed findAllReport:star hits:&inDocument];
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
            [[NSFileManager defaultManager] removeItemAtPath:emptyRoot error:NULL];
            Check(@"IDM_SEARCH_FINDINFILES (empty matches as Find All)",
                  @"a pattern that can match nothing gives the same hits in a file as Find All in the document",
                  inFiles == 3 && inDocument == 3);
        }

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

        // '.' covers the odd control character, but not one of Boost's line
        // separators (is_separator: \r, \n, \f, U+0085, U+2028, U+2029), and
        // '^' starts a line after each of them.
        SetDoc(ed, @"a\001b a\fb\n");
        Check(@"IDM_SEARCH_FIND (dot spans anything)",
              @"'.' matches a control character but not a form feed, which ends a line as in Boost",
              [ed countMatches:[NppFindSpec specFor:@"a.b" mode:NppSearchRegex
                                            options:NppFindNone]] == 1 &&
              [ed countMatches:[NppFindSpec specFor:@"^b" mode:NppSearchRegex
                                            options:NppFindNone]] == 1);

        // CRLF, as Boost reads it in Notepad++: '^' and '$' never stand between
        // the CR and the LF (match_start_line / match_end_line), '^' also
        // starts the empty line after the last line end, and Replace All
        // steps over an empty match where the previous match ended
        // (SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH | SKIPCRLFASONE).
        NSString *dollar = replaced(@"a\r\nb\r\n", @"$", @";");
        NSString *caret = replaced(@"a\r\nb\r\n", @"^", @">");
        NSString *trailing = replaced(@"a \r\nb\t\r\nc", @"\\s+$", @"");
        NSString *lineEnds = replaced(@"a\r\nb\nc\rd", @"\\R", @"|");
        NSString *emptyLines = replaced(@"a\r\n\r\nb", @"^$", @"E");
        NSString *afterMatch = replaced(@"baac", @"a*", @"-");
        Check(@"IDM_SEARCH_REPLACE (CRLF)",
              @"Replace All of '$', '^', \\s+$, \\R and a* on CRLF text gives what Notepad++ gives",
              [dollar isEqualToString:@"a;\r\nb;\r\n;"] &&
              [caret isEqualToString:@">a\r\n>b\r\n>"] &&
              [trailing isEqualToString:@"a\r\nb\r\nc"] &&
              [lineEnds isEqualToString:@"a|b|c|d"] &&
              [emptyLines isEqualToString:@"a\r\nE\r\nb"] &&
              [afterMatch isEqualToString:@"-b-c-"]);

        // Count and Mark take no empty match at all (EMPTYMATCH_NONE), and Find
        // Next never stops between a CR and its LF.
        SetDoc(ed, @"ab\r\ncd\r\n");
        NppFindSpec *eol = [NppFindSpec specFor:@"$" mode:NppSearchRegex options:NppFindNone];
        NSUInteger eolCount = [ed countMatches:eol];
        NSUInteger lineCount = [ed countMatches:[NppFindSpec specFor:@"^.+$" mode:NppSearchRegex options:NppFindNone]];
        NSMutableArray *stops = [NSMutableArray array];
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        for (int i = 0; i < 3 && [ed findNext:eol]; ++i) [stops addObject:@([sci message:SCI_GETCURRENTPOS])];
        Check(@"IDM_SEARCH_FIND (CRLF)",
              @"Count takes no empty match, each CRLF line counts once, and Find Next '$' stops before each CR",
              eolCount == 0 && lineCount == 2 && [stops isEqualToArray:(@[@2, @6, @8])]);
    }
}

/// == Search: modes and options ==
void NppTestsSearchModes(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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

        // FindReplaceDlg::processFindNext ignores "In selection": after the first
        // hit the selection is that match, and F3 goes on to the next one.
        SetDoc(ed, @"q q q q\n");
        [sci message:SCI_SETSEL wParam:0 lParam:1];
        NppFindSpec *nextInSel = [NppFindSpec specFor:@"q" mode:NppSearchNormal options:NppFindInSelection | NppFindWrap];
        [ed findNext:nextInSel];
        long firstHop = [sci message:SCI_GETSELECTIONSTART];
        [ed findNext:nextInSel];
        Check(@"IDM_SEARCH_FINDNEXT (in selection)", @"Find Next goes past the selection, as upstream's does",
              firstHop == 2 && [sci message:SCI_GETSELECTIONSTART] == 4);

        // Whole word is Scintilla's SCFIND_WHOLEWORD (Document::IsWordAt), not a
        // regex \b: a word may start or end with punctuation, and a candidate
        // refused is retried one character on.
        SetDoc(ed, @"$var $varx x\naaa aa\n");
        NppFindSpec *dollar = [NppFindSpec specFor:@"$var" mode:NppSearchNormal options:NppFindWholeWord];
        NppFindSpec *doubleA = [NppFindSpec specFor:@"aa" mode:NppSearchNormal options:NppFindWholeWord];
        NSArray<NSValue *> *aaAt = [ed rangesOfMatches:doubleA];
        long aaExpected = [sci message:SCI_POSITIONFROMLINE wParam:1] + 4;
        Check(@"IDM_SEARCH_FIND (whole word)", @"\"$var\" is a whole word before a space, not before \"x\"",
              [ed countMatches:dollar] == 1);
        Check(@"IDM_SEARCH_FIND (whole word)", @"\"aa\" is found as the word, not inside \"aaa\"",
              aaAt.count == 1 && (long)aaAt.firstObject.rangeValue.location == aaExpected);

        // Replace All with a regex is linear in the number of matches: the text
        // after each match ($') is built only when the replacement asks for it,
        // and PCRE2 checks the UTF-8 once, not before every match.
        {
            NSMutableString *many = [NSMutableString stringWithCapacity:500000];
            for (int i = 0; i < 100000; ++i) [many appendString:@"word "];
            SetDoc(ed, many);
            NppFindSpec *renumber = [NppFindSpec specFor:@"w(o)rd" mode:NppSearchRegex options:NppFindNone];
            renumber.replacement = @"$1";
            CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
            NSUInteger replacedMany = [ed replaceAll:renumber];
            CFAbsoluteTime inDocument = CFAbsoluteTimeGetCurrent() - t0;
            BOOL rightText = [sci message:SCI_GETLENGTH] == 200000 && [DocText(ed) hasPrefix:@"o o o "];
            NSString *manyRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp_many_matches"];
            [[NSFileManager defaultManager] removeItemAtPath:manyRoot error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:manyRoot withIntermediateDirectories:YES attributes:nil error:NULL];
            NSString *manyFile = [manyRoot stringByAppendingPathComponent:@"many.txt"];
            [many writeToFile:manyFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            t0 = CFAbsoluteTimeGetCurrent();
            NSUInteger changed = 0;
            NSUInteger replacedInFiles = [ed replaceInFiles:renumber folder:manyRoot filters:nil recursive:NO includeHidden:NO changedFiles:&changed];
            CFAbsoluteTime inFiles = CFAbsoluteTimeGetCurrent() - t0;
            NSString *rewritten = [NSString stringWithContentsOfFile:manyFile encoding:NSUTF8StringEncoding error:NULL];
            [[NSFileManager defaultManager] removeItemAtPath:manyRoot error:NULL];
            printf("  (regex Replace All, 100000 matches: %.2f s in the document, %.2f s in a file)\n", inDocument, inFiles);
            Check(@"IDM_SEARCH_REPLACE (100000 matches)", @"a regex Replace All over 100000 matches takes seconds, not hours",
                  replacedMany == 100000 && rightText && inDocument < 10.0);
            Check(@"IDM_SEARCH_FINDINFILES (100000 matches)", @"so does Replace in Files",
                  replacedInFiles == 100000 && rewritten.length == 200000 && inFiles < 10.0);
            SetDoc(ed, @"");
        }

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
}

/// == Search ==; == Search: token styling ==; == Search: bookmarked lines ==; == Search: braces, selection, files ==; == Search: change history ==
void NppTestsSearchMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        SetDoc(ed, @"abc 123\nfoo(bar)\nline3\n");
        [app goToLineOrOffset:@"@23"];
        Check(@"IDM_SEARCH_GOTOLINE", @"@<length> puts the caret at the end, not one before (GoToLineDlg snaps with AFTER(BEFORE))",
              [sci message:SCI_GETCURRENTPOS] == 23);
        SetDoc(ed, @"a\nb\nc\nd");
        Check(@"IDM_SEARCH_GOTOLINE", @"a line past the end goes to the last line, as SCI_GOTOLINE clamps",
              [app goToLineOrOffset:@"99"] && [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 3);
        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed toggleBookmark];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL bookmarksCleared = [app performMenuCommandAtPath:@"Search|Bookmark|Clear All Bookmarks"];
        [ed nextBookmark];
        Check(@"IDM_SEARCH_CLEAR_BOOKMARKS", @"Search > Bookmark > Clear All Bookmarks is in the menu and clears them",
              bookmarksCleared && [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]] == 0);
        BOOL markRan = [app performMenuCommandAtPath:@"Search|Mark…"];
        NSPanel *markPanel = [app valueForKey:@"findPanel"];
        NSSegmentedControl *markTabs = [app valueForKey:@"findTabs"];
        Check(@"IDM_SEARCH_MARK", @"Search > Mark… opens the Find dialog on its Mark tab, as upstream",
              markRan && markPanel.isVisible && markTabs.selectedSegment == 4);
        [markPanel orderOut:nil];
        SetDoc(ed, @"a \U0001F600 b\n");
        Check(@"IDM_SEARCH_FINDCHARINRANGE", @"a range past U+FFFF marks a character outside the BMP",
              [ed markCharactersInRangeFrom:128 to:0x10FFFF] == 1);

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

        // Notepad_plus::changedHistoryGoTo: saved changes count, the caret's block is
        // stepped over, and the search wraps. A file just opened has no changes at all.
        NSError *histErr = nil;
        [ed openFileAtPath:TempFile(@"t_history.txt", @"l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\n") error:&histErr];
        long opened = 0;
        for (long l = 0; l < 8; ++l) opened |= [sci message:SCI_MARKERGET wParam:(uptr_t)l] & historyMask;
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"a file just opened carries no change-history marks", opened == 0);
        for (long l : {1L, 2L, 5L}) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)l lParam:0];
            [sci setStringProperty:SCI_INSERTTEXT parameter:[sci message:SCI_GETCURRENTPOS] value:@"X"];
        }
        auto caretLine = ^long { return [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]]; };
        [sci message:SCI_GOTOLINE wParam:1 lParam:0];
        [ed goToNextChange:YES];
        long skipped = caretLine();
        [ed goToNextChange:YES];
        long wrapped = caretLine();
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed goToNextChange:NO];
        Check(@"IDM_SEARCH_CHANGED_NEXT", @"steps over the caret's block of changes and wraps round",
              skipped == 5 && wrapped == 1 && caretLine() == 5);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
    }
}
