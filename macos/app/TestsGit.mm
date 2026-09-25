// The built-in suite, the Git panel and commands.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Git ==
void NppTestsGit(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        // The panel made narrower and wider: the file column takes the difference, the narrow two keep theirs.
        {
            NSScrollView *tableScroll = panel.table.enclosingScrollView;
            NSSize before = tableScroll.frame.size;
            NSTableColumn *stagedCol = panel.table.tableColumns[0], *fileCol = panel.table.tableColumns.lastObject;
            CGFloat stagedWidth = stagedCol.width;
            // The table style's inset stays between the last column and the edge; 260 and 420 are
            // wide enough for the file column's minimum.
            BOOL fills = YES;
            CGFloat fileAt[2] = {0, 0}, roomAt[2] = {0, 0};
            NSArray<NSNumber *> *widths = @[@260, @420];
            for (NSUInteger k = 0; k < widths.count; ++k) {
                [tableScroll setFrameSize:NSMakeSize(widths[k].doubleValue, before.height)];
                [tableScroll tile];
                roomAt[k] = NSWidth(tableScroll.contentView.bounds);
                fileAt[k] = fileCol.width;
                CGFloat end = NSMaxX([panel.table rectOfColumn:(NSInteger)panel.table.tableColumns.count - 1]);
                fills = fills && end <= roomAt[k] + 1 && end >= roomAt[k] - 12 && fabs(stagedCol.width - stagedWidth) < 1;
            }
            fills = fills && fabs((fileAt[1] - fileAt[0]) - (roomAt[1] - roomAt[0])) <= 1;
            if (!fills) printf("    columns: room %.1f/%.1f file %.1f/%.1f staged %.1f/%.1f\n",
                               roomAt[0], roomAt[1], fileAt[0], fileAt[1], stagedCol.width, stagedWidth);
            [tableScroll setFrameSize:before];
            [tableScroll tile];
            Check(@"Git (the panel's columns)", @"a narrower or wider panel gives or takes the room from the file column, which ends at the panel's edge",
                  fills);
        }

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

        // A repository from elsewhere - an archive, a clone of someone's - is in the user's own name,
        // so git lets its .git/config name programs: the fsmonitor hook, a filter, a textconv, and
        // .git/hooks. Opening a file of it makes the editor ask git about it by itself (the branch,
        // the margin, the panel), and Blame and History only read: none of those may run them.
        NSString *hostile = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_hostile"];
        NSString *ran = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_hostile_ran"];
        [fm removeItemAtPath:hostile error:NULL];
        [fm removeItemAtPath:ran error:NULL];
        [fm createDirectoryAtPath:hostile withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:ran withIntermediateDirectories:YES attributes:nil error:NULL];
        BOOL (^inHostile)(NSString *, NSArray<NSString *> *) = ^BOOL(NSString *where, NSArray<NSString *> *args) {
            NSArray *identity = @[@"-c", @"user.email=suite@example.invalid", @"-c", @"user.name=Suite Runner", @"-c", @"commit.gpgsign=false"];
            return [NppGit run:[identity arrayByAddingObjectsFromArray:args] in:where output:NULL error:NULL];
        };
        NSString *nested = [hostile stringByAppendingPathComponent:@"nested"];
        [fm createDirectoryAtPath:nested withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *hostileFile = [hostile stringByAppendingPathComponent:@"a.txt"];
        [@"one\n" writeToFile:hostileFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"*.txt filter=evil diff=evil\n" writeToFile:[hostile stringByAppendingPathComponent:@".gitattributes"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"n\n" writeToFile:[nested stringByAppendingPathComponent:@"n.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"*.txt filter=inner\n" writeToFile:[nested stringByAppendingPathComponent:@".gitattributes"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL hostileMade = inHostile(nested, @[@"init", @"-q"]) && inHostile(nested, @[@"add", @"-A"]) && inHostile(nested, @[@"commit", @"-q", @"-m", @"inner"]) &&
                           inHostile(hostile, @[@"init", @"-q"]) && inHostile(hostile, @[@"add", @"-A"]) && inHostile(hostile, @[@"commit", @"-q", @"-m", @"outer"]);
        NSString *(^touch)(NSString *) = ^NSString *(NSString *name) {
            return [NSString stringWithFormat:@"touch '%@'; cat", [ran stringByAppendingPathComponent:name]];
        };
        hostileMade = hostileMade &&
            inHostile(hostile, @[@"config", @"core.fsmonitor", [NSString stringWithFormat:@"touch '%@'; false", [ran stringByAppendingPathComponent:@"fsmonitor"]]]) &&
            inHostile(hostile, @[@"config", @"filter.evil.clean", touch(@"clean")]) && inHostile(hostile, @[@"config", @"filter.evil.required", @"true"]) &&
            inHostile(hostile, @[@"config", @"diff.evil.textconv", touch(@"textconv")]) &&
            inHostile(nested, @[@"config", @"filter.inner.clean", touch(@"nested-clean")]);
        NSString *hook = [hostile stringByAppendingPathComponent:@".git/hooks/post-index-change"];
        [[NSString stringWithFormat:@"#!/bin/sh\ntouch '%@'\n", [ran stringByAppendingPathComponent:@"hook"]] writeToFile:hook atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:hook error:NULL];
        // Changed, and the same size, so that status has to read them to know.
        NSDate *past = [NSDate dateWithTimeIntervalSinceNow:-120];
        [fm setAttributes:@{NSFileModificationDate: past} ofItemAtPath:hostileFile error:NULL];
        [NppGit run:@[@"update-index", @"--refresh"] in:hostile output:NULL error:NULL];
        [fm removeItemAtPath:ran error:NULL];
        [fm createDirectoryAtPath:ran withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"two\n" writeToFile:hostileFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"m\n" writeToFile:[nested stringByAppendingPathComponent:@"n.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [NppGit forgetRepositoryRoots];
        [ed openFileAtPath:hostileFile error:NULL];
        [ed gitRefreshState];
        [panel reload];
        BOOL listed = NO;
        for (NppGitFileStatus *row in panel.rows) if ([row.path isEqualToString:@"a.txt"] && row.unstaged) listed = YES;
        NSInteger hostileTabs = (NSInteger)ed.documents.count;
        BOOL blamedHostile = [ed gitBlame];
        while ((NSInteger)ed.documents.count > hostileTabs) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [ed openFileAtPath:hostileFile error:NULL];
        BOOL historyHostile = [ed gitFileHistory];
        while ((NSInteger)ed.documents.count > hostileTabs) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
        [ed openFileAtPath:hostileFile error:NULL];
        NSArray *whatRan = [fm contentsOfDirectoryAtPath:ran error:NULL] ?: @[];
        if (whatRan.count) printf("       ran: %s\n", [[whatRan componentsJoinedByString:@", "] UTF8String]);
        Check(@"Git (a repository from elsewhere)", @"the status bar, the margin, the panel, Blame and History run none of the programs the repository's config names "
              @"(fsmonitor, a filter, a textconv, a hook, a nested repository's filter) and still show the file as changed",
              hostileMade && whatRan.count == 0 && listed && blamedHostile && historyHostile && [[ed gitStatusBarText] hasPrefix:@"⎇ "]);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        [NppGit forgetRepositoryRoots];
        [fm removeItemAtPath:hostile error:NULL];
        [fm removeItemAtPath:ran error:NULL];

        // A file opened under another spelling of its path than the disk's - another case (the file
        // system does not mind), the other Unicode form of an accented name (git precomposes) - is
        // still the repository's file: stage, unstage, blame, history and discard work on it.
        NSString *spelt = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_git_Spelt"];
        [fm removeItemAtPath:spelt error:NULL];
        NSString *accented = [[spelt stringByAppendingPathComponent:@"Sub"] stringByAppendingPathComponent:@"Caf\u00e9.txt"];
        [fm createDirectoryAtPath:accented.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"first\n" writeToFile:accented atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *gone = [[spelt stringByAppendingPathComponent:@"Sub"] stringByAppendingPathComponent:@"gone.txt"];
        [@"gone\n" writeToFile:gone atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL speltMade = inHostile(spelt, @[@"init", @"-q"]) && inHostile(spelt, @[@"add", @"-A"]) && inHostile(spelt, @[@"commit", @"-q", @"-m", @"first"]);
        [@"second\n" writeToFile:accented atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *otherSpelling = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"T_GIT_SPELT"] stringByAppendingPathComponent:@"sub"]
                                   stringByAppendingPathComponent:@"CAFE\u0301.TXT"];                                   // decomposed, and in capitals
        BOOL openedSpelt = [ed openFileAtPath:otherSpelling error:NULL] && [ed.currentDocument.path isEqualToString:otherSpelling];
        NSString *speltRelative = [ed gitRelativePathOfDocument:ed.currentDocument];
        NSString *(^speltStatus)(void) = ^NSString *{
            NSString *out = nil; [NppGit run:@[@"status", @"--porcelain"] in:spelt output:&out error:NULL];
            return [out stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet] ?: @"";   // " M" keeps its space
        };
        BOOL speltStaged = NO, speltUnstaged = NO, speltBlamed = NO, speltLogged = NO, speltDiscarded = NO, speltGoneStaged = NO;
        NSString *crash = nil;
        @try {
            speltStaged = [ed gitStageCurrent] && [speltStatus() hasPrefix:@"M "];
            speltUnstaged = [ed gitUnstageCurrent] && [speltStatus() hasPrefix:@" M"];
            NSInteger speltTabs = (NSInteger)ed.documents.count;
            NppDocument *speltDoc = ed.currentDocument;
            speltBlamed = [ed gitBlame] && [ed documentText].length > 0;
            while ((NSInteger)ed.documents.count > speltTabs) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:speltDoc]];
            speltLogged = [ed gitFileHistory] && [[ed documentText] containsString:@"first"];
            while ((NSInteger)ed.documents.count > speltTabs) [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:speltDoc]];
            speltDiscarded = [ed gitDiscardCurrent] && speltStatus().length == 0 && [[ed documentText] isEqualToString:@"first\n"];
            // Deleted from disk meanwhile, the tab kept: a path that is not the disk's spelling can no longer
            // be put right from the file, only from its folder; it is still the repository's, and staging
            // stages the deletion.
            NSString *goneOtherwise = [[[NSTemporaryDirectory() stringByAppendingPathComponent:@"T_GIT_SPELT"] stringByAppendingPathComponent:@"sub"]
                                       stringByAppendingPathComponent:@"gone.txt"];           // its folders in other capitals
            [ed openFileAtPath:goneOtherwise error:NULL];
            [fm removeItemAtPath:gone error:NULL];
            speltGoneStaged = [ed gitStageCurrent] && [speltStatus() hasPrefix:@"D  Sub/gone.txt"];
        } @catch (NSException *e) { crash = e.reason ?: e.name; }
        if (crash) printf("       raised: %s\n", crash.UTF8String);
        Check(@"Git (the path spelt otherwise)", @"a file opened in other capitals and the decomposed form of its accented name has its path in the repository "
              @"as the disk spells it, and stage, unstage, blame, history and discard all work on it; a file deleted under its tab is staged as deleted",
              speltMade && openedSpelt && [speltRelative.precomposedStringWithCanonicalMapping isEqualToString:@"Sub/Caf\u00e9.txt"] && !crash &&
              speltStaged && speltUnstaged && speltBlamed && speltLogged && speltDiscarded && speltGoneStaged);
        for (NppDocument *d in [ed.documents copy])
            if ([d.path isEqualToString:otherSpelling] || [d.path.lastPathComponent isEqualToString:@"gone.txt"]) [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:d] discardChanges:YES];
        [NppGit forgetRepositoryRoots];
        [fm removeItemAtPath:spelt error:NULL];

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
}
