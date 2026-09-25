// The built-in suite, the View menu, split panes, docking, the tab bar and fonts.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == View ==; == View: tabs ==; == View: fold levels ==; == View: symbols, lines, direction ==; == View: window modes and panels ==; == View: split panes and panels ==
void NppTestsViewMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        SetDoc(ed, @"int f() {\n  if (a) {\n    b;\n  }\n}\n");
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        [ed foldAll:YES];
        BOOL innerFolded = [sci message:SCI_GETFOLDEXPANDED wParam:1] == 0;
        [ed unfoldToLevel:1];
        Check(@"IDM_VIEW_FOLDALL", @"folds every level, so Unfold Level 1 opens only the outer block",
              innerFolded && [sci message:SCI_GETFOLDEXPANDED wParam:0] && ![sci message:SCI_GETFOLDEXPANDED wParam:1]);
        [ed foldAll:NO];
        SetDoc(ed, @"int f() {\n  int x;\n  return x;\n}\n");   // the text the checks below use
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];

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

        // Moving a tab is not a switch of tabs: the neighbour it passes keeps its own caret and
        // bookmarks, the moved tab its caret (the exchange once made the neighbour "leave").
        {
            NppDocument *neighbour = ed.documents[1];
            [ed selectDocumentAtIndex:1];
            SetDoc(ed, @"n1\nn2\nn3\n");
            [ed.sci message:SCI_GOTOPOS wParam:1 lParam:0];
            [ed selectDocumentAtIndex:0];
            SetDoc(ed, @"m1\nm2\nm3\nm4\n");
            [ed.sci message:SCI_MARKERADD wParam:2 lParam:1];   // the bookmark marker
            [ed.sci message:SCI_GOTOPOS wParam:7 lParam:0];
            [ed moveCurrentTab:YES];
            BOOL movedKeepsCaret = ed.currentDocument == moving && [ed.sci message:SCI_GETCURRENTPOS] == 7;
            BOOL neighbourMarks = ![neighbour.bookmarkedLines containsObject:@2];
            [ed moveCurrentTabToEnd:NO];
            BOOL stillCaret = ed.currentDocument == moving && [ed.sci message:SCI_GETCURRENTPOS] == 7;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:neighbour]];
            BOOL neighbourCaret = [ed.sci message:SCI_GETCURRENTPOS] == 1;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:moving]];
            [ed.sci message:SCI_MARKERDELETEALL wParam:1 lParam:0];
            Check(@"IDM_VIEW_TAB_MOVEFORWARD (not a switch)",
                  @"Move Tab Forward and Move to Start leave the neighbour its caret and bookmarks and the moved tab its caret",
                  movedKeepsCaret && neighbourMarks && stillCaret && neighbourCaret && [ed.documents indexOfObject:moving] == 0);
        }

        [ed selectTabNumber:5];
        NppDocument *jumper = ed.currentDocument;
        [ed moveCurrentTabToEnd:NO];
        Check(@"IDM_VIEW_GOTO_START", @"moves the tab to the front",
              [ed.documents indexOfObject:jumper] == 0);
        [ed moveCurrentTabToEnd:YES];
        Check(@"IDM_VIEW_GOTO_END", @"moves it to the back",
              [ed.documents indexOfObject:jumper] == ed.documents.count - 1);

        // Pinned tabs stay first: an unpinned tab stops after them (VIEW-087).
        NppDocument *pinnedDoc = ed.documents.firstObject;
        pinnedDoc.pinned = YES;
        [ed moveCurrentTabToEnd:NO];
        BOOL afterPinned = [ed.documents indexOfObject:jumper] == 1;
        BOOL cannotPass = ![ed moveCurrentTab:NO] && [ed.documents indexOfObject:jumper] == 1;
        pinnedDoc.pinned = NO;
        [ed refreshChrome];
        Check(@"IDM_VIEW_GOTO_START (pinned tabs)",
              @"Move to Start and Move Tab Backward stop an unpinned tab after the pinned ones",
              afterPinned && cannotPass);

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

        // Both views, the checkmark and Show All Characters (VIEW-004/005/018-023).
        {
            NSMenuItem *symbolItem = [[NSMenuItem alloc] initWithTitle:@"" action:NSSelectorFromString(@"toggleSymbol:") keyEquivalent:@""];
            symbolItem.tag = NppSymbolEOL; symbolItem.target = app;
            BOOL wasEOL = [ed symbolVisible:NppSymbolEOL];
            [ed toggleSymbol:NppSymbolEOL];
            [app validateMenuItem:symbolItem];
            BOOL checkFollows = (symbolItem.state == NSControlStateValueOn) == !wasEOL;
            ScintillaView *other = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            [ed applySymbolsToView:other];
            BOOL otherToo = ([other message:SCI_GETVIEWEOL] != 0) == !wasEOL;
            [ed toggleSymbol:NppSymbolEOL];
            Check(@"IDM_VIEW_EOL (both views, checkmark)",
                  @"Show End of Line is kept, applied to any view and checked in the menu", checkFollows && otherToo);

            BOOL allBefore = [ed symbolVisible:NppSymbolAll];
            [ed toggleSymbol:NppSymbolAll];
            BOOL allFlipped = [ed symbolVisible:NppSymbolWhitespace] == !allBefore && [ed symbolVisible:NppSymbolEOL] == !allBefore &&
                              [ed symbolVisible:NppSymbolNonPrinting] == !allBefore &&
                              [ed symbolVisible:NppSymbolControlAndUnicodeEOL] == !allBefore;
            [ed toggleSymbol:NppSymbolAll];
            Check(@"IDM_VIEW_ALL_CHARACTERS", @"Show All Characters turns the four invisible-character symbols on and off together",
                  allFlipped);
        }

        SetDoc(ed, @"one\ntwo\nthree\n");
        [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_POSITIONFROMLINE wParam:1]
                 lParam:[sci message:SCI_GETLINEENDPOSITION wParam:1]];
        BOOL hidden = [ed hideSelectedLines];
        Check(@"IDM_VIEW_HIDELINES", @"hides the selected lines",
              hidden && [sci message:SCI_GETLINEVISIBLE wParam:1] == 0);
        [ed showAllHiddenLines];
        Check(@"IDM_VIEW_UNHIDELINES", @"Show All Hidden Lines shows them again",
              [sci message:SCI_GETLINEVISIBLE wParam:1] != 0);

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

        // Post-It keeps an Always on Top from before; Distraction Free ignores Post-It (VIEW-011/012).
        [app toggleAlwaysOnTop:nil];
        [app togglePostIt:nil];
        [app togglePostIt:nil];
        BOOL keptOnTop = app.window.level == NSFloatingWindowLevel;
        [app toggleAlwaysOnTop:nil];
        [app toggleDistractionFree:nil];
        [app togglePostIt:nil];
        BOOL ignored = app.window.level == NSNormalWindowLevel && ![ed chromeVisible];
        [app toggleDistractionFree:nil];
        Check(@"IDM_VIEW_POSTIT (special views)",
              @"leaving Post-It keeps Always on Top as it was; in Distraction Free Post-It does nothing",
              keptOnTop && ignored && [ed chromeVisible]);

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

        // Upstream's submenus (Notepad_plus.rc): View > Zoom, View > Project, Edit > EOL Conversion,
        // each named by its subMenuId in every language, the zoom keys kept.
        NSDictionary<NSNumber *, NSMenuItem *> *menuIDs = [app.shortcutStore menuItemsByIdentifier];
        NSMenuItem *(^parentOf)(NSMenuItem *) = ^NSMenuItem *(NSMenuItem *mi) {
            for (NSMenuItem *top in NSApp.mainMenu.itemArray)
                for (NSMenuItem *sub in top.submenu.itemArray) if (sub.submenu == mi.menu) return sub;
            return nil;
        };
        NSMenuItem *zoomSub = parentOf(menuIDs[@44023]), *eolSub = parentOf(menuIDs[@45002]), *projSub = parentOf(menuIDs[@44081]);
        NSEventModifierFlags zoomMods = 0;
        NSString *zoomKey = menuIDs[@44023] ? NppMenuItemKey(menuIDs[@44023], &zoomMods) : nil;
        BOOL submenusPlaced = [zoomSub.identifier isEqualToString:@"view-zoom"] && [eolSub.identifier isEqualToString:@"edit-eolConversion"] &&
                              [projSub.identifier isEqualToString:@"view-project"] && menuIDs[@44024].menu == zoomSub.submenu &&
                              menuIDs[@44033].menu == zoomSub.submenu && menuIDs[@44027].menu == zoomSub.submenu &&
                              menuIDs[@45001].menu == eolSub.submenu && menuIDs[@45003].menu == eolSub.submenu &&
                              [zoomKey isEqualToString:@"+"] && zoomMods == NSEventModifierFlagCommand;
        if (!submenusPlaced) printf("    submenus: zoom [%s] %s eol [%s] %s project [%s] %s; zoom key [%s] %lx\n",
                                    zoomSub.title.UTF8String, zoomSub.identifier.UTF8String, eolSub.title.UTF8String, eolSub.identifier.UTF8String,
                                    projSub.title.UTF8String, projSub.identifier.UTF8String, zoomKey.UTF8String, (unsigned long)zoomMods);
        NppPreferences *viewPrefs = [NppPreferences shared];
        NSString *viewLanguageWas = viewPrefs.localizationFile;
        viewPrefs.localizationFile = @"russian.xml";
        [app applyLocalization];
        BOOL submenusRu = [zoomSub.title isEqualToString:@"Масштаб текста"] && [eolSub.title isEqualToString:@"Формат Конца Строк"] &&
                          [projSub.title isEqualToString:@"Проект (панель)"] && [menuIDs[@46180].title isEqualToString:@"Пользовательский"];
        if (!submenusRu) printf("    ru: [%s] [%s] [%s] [%s]\n", zoomSub.title.UTF8String, eolSub.title.UTF8String, projSub.title.UTF8String, menuIDs[@46180].title.UTF8String);
        viewPrefs.localizationFile = viewLanguageWas ?: @"";
        [app applyLocalization];
        Check(@"IDM_VIEW_ZOOMIN (submenus)",
              @"Zoom, Project and EOL Conversion are upstream's submenus, named by their subMenuId in Russian, Cmd++ kept",
              submenusPlaced && submenusRu && [zoomSub.title isEqualToString:@"Zoom"]);

        // Commands with no Mac counterpart of their own, kept by id: IE is the system browser (Safari),
        // PowerShell a second Terminal, the tab bar's ▼ the Windows… list, and "User-Defined".
        NSMenuItem *ie = menuIDs[@44103], *ps = menuIDs[@41027], *drop = menuIDs[@14001], *udlItem = menuIDs[@46180];
        Check(@"IDM_VIEW_IN_IE", @"the system browser, Safari; Edge stays Edge",
              [ie.title isEqualToString:@"Safari"] && [menuIDs[@44102].title isEqualToString:@"Edge"]);
        Check(@"IDM_FILE_OPEN_POWERSHELL", @"a hidden twin of Open Containing Folder > Terminal",
              ps.isHidden && ps.action == menuIDs[@41020].action && ps.menu == menuIDs[@41020].menu);
        Check(@"IDM_DROPLIST_LIST", @"a hidden item showing the Windows… list",
              drop.isHidden && drop.action == NSSelectorFromString(@"showWindowsList:"));
        Check(@"IDM_LANG_USER", @"\"User-Defined\" ends the Language menu, after the user's own languages",
              [udlItem.title isEqualToString:@"User-Defined"] && !udlItem.isHidden && udlItem.menu.itemArray.lastObject == udlItem);

        // A shifted key is set as AppKit matches it - the shifted character, no Shift in the
        // mask - so Cmd+G never reaches the item that has Shift+Cmd+G.
        NSMenuItem *findPrev = menuIDs[@43010], *nextTab = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *mi in top.submenu.itemArray) if (mi.action == NSSelectorFromString(@"nextTab:") && mi.keyEquivalent.length) nextTab = mi;
        NSEventModifierFlags prevMods = 0, tabMods = 0;
        NSString *prevKey = NppMenuItemKey(findPrev, &prevMods), *tabKey = nextTab ? NppMenuItemKey(nextTab, &tabMods) : nil;
        if (![findPrev.keyEquivalent isEqualToString:@"G"] || ![nextTab.keyEquivalent isEqualToString:@"}"])
            printf("    keys: find previous [%s] %lx -> [%s] %lx; next tab [%s] %lx -> [%s] %lx\n",
               findPrev.keyEquivalent.UTF8String, (unsigned long)findPrev.keyEquivalentModifierMask, prevKey.UTF8String, (unsigned long)prevMods,
               nextTab.keyEquivalent.UTF8String, (unsigned long)nextTab.keyEquivalentModifierMask, tabKey.UTF8String, (unsigned long)tabMods);
        Check(@"IDM_SEARCH_FINDPREV (key)", @"Shift+Cmd+G is \"G\" with Command alone; Next Tab's Shift+Cmd+] is \"}\"",
              [findPrev.keyEquivalent isEqualToString:@"G"] && !(findPrev.keyEquivalentModifierMask & NSEventModifierFlagShift) &&
              [prevKey isEqualToString:@"g"] && prevMods == (NSEventModifierFlagCommand | NSEventModifierFlagShift) &&
              [nextTab.keyEquivalent isEqualToString:@"}"] && [tabKey isEqualToString:@"]"] &&
              tabMods == (NSEventModifierFlagCommand | NSEventModifierFlagShift));

        // None (Normal Text) takes the lexer off: no style or fold level of the language before stays.
        [ed newDocument];
        SetDoc(ed, @"def f():\n    return 1\n");
        [ed setLanguageNamed:@"python"];
        [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
        BOOL styledBefore = [ed.sci message:SCI_GETSTYLEAT wParam:0] != 0;
        [ed setLanguageNamed:@"normal"];
        [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
        BOOL plain = YES;
        NSInteger docLength = [ed.sci message:SCI_GETLENGTH];
        for (NSInteger p = 0; p < docLength; ++p) if ([ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)p] != 0) plain = NO;
        BOOL noFolds = !([ed.sci message:SCI_GETFOLDLEVEL wParam:0] & SC_FOLDLEVELHEADERFLAG);
        Check(@"IDM_LANG_TEXT (styles)", @"after Python every style byte is 0 and no line is a fold header",
              styledBefore && plain && noFolds);
        [ed closeDocumentAtIndex:(NSInteger)ed.documents.count - 1 discardChanges:YES];

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
        NSRect mainPane = ed.sci.frame, subPane = [ed.secondarySci convertRect:ed.secondarySci.bounds toView:ed.sci.superview];
        Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW", @"the two views stand side by side, as Notepad++ splits them (POS_VERTICAL)",
              NSMinX(subPane) >= NSMaxX(mainPane) && NSWidth(mainPane) > 0 && NSWidth(subPane) > 0 &&
              fabs(NSHeight(mainPane) - NSHeight(subPane)) < 30);

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

        NSUInteger before = ed.mainViewDocuments.count, open = ed.documents.count;
        [ed moveCurrentToOtherView];
        Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW", @"the tab leaves the primary pane, the document stays open",
              ed.mainViewDocuments.count == before - 1 && ed.documents.count == open);

        [ed focusOtherView];
        BOOL onOther = [ed otherViewHasFocus];
        // The status bar follows the focused view: its caret line, not the main view's.
        [ed.secondarySci message:SCI_APPENDTEXT wParam:3 lParam:(sptr_t)"\n\n\n"];
        [ed.secondarySci message:SCI_DOCUMENTEND];
        long subLine = [ed.secondarySci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[ed.secondarySci message:SCI_GETCURRENTPOS]] + 1;
        [ed.mainSci message:SCI_DOCUMENTSTART];
        [ed refreshChrome];
        NSTextField *statusText = [ed valueForKey:@"statusField"];
        BOOL follows = subLine > 1 && [statusText.stringValue containsString:[NSString stringWithFormat:@"Ln: %ld ", subLine]];
        [ed focusOtherView];
        Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW", @"focus moves between panes and back",
              onOther && ![ed otherViewHasFocus]);
        Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW (status bar)", @"the status bar shows the focused view's caret",
              follows);

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

        // Each view has its tab list, as upstream's _mainDocTab and _subDocTab.
        {
            [ed closeAllDocuments];
            NSString *pa = TempFile(@"t_views_a.txt", @"aaa\n"), *pb = TempFile(@"t_views_b.txt", @"bbb\n"),
                     *pc = TempFile(@"t_views_c.txt", @"ccc\n");
            for (NSString *p in @[pa, pb, pc]) [ed openFileAtPath:p error:&err];
            NppDocument *da = ed.documents[0], *db = ed.documents[1], *dc = ed.documents[2];
            NSArray *(^paths)(NSArray<NppDocument *> *) = ^NSArray *(NSArray<NppDocument *> *list) { return [list valueForKey:@"path"]; };
            NppTabBarView *mainBar = [ed valueForKey:@"tabBar"], *subBar = [ed valueForKey:@"subTabBar"];
            [ed selectDocumentAtIndex:1];
            [ed.sci message:SCI_APPENDTEXT wParam:1 lParam:(sptr_t)"!"];
            BOOL moved = [ed moveCurrentToOtherView];
            Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW (own tabs)",
                  @"Move to Other View takes the tab into the second view's tabs, unsaved changes and all; the main view shows a neighbour",
                  moved && [paths(ed.mainViewDocuments) isEqualToArray:(@[pa, pc])] && [ed.subViewDocuments isEqualToArray:@[db]] &&
                  [ed.documents containsObject:db] && db.modified && db.secondViewOnly &&
                  mainBar.items.count == 2 && subBar.items.count == 1 && !subBar.hidden &&
                  (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == db.docPointer &&
                  [[ed.secondarySci string] isEqualToString:@"bbb\n!"] && ed.currentDocument != db);

            // What the second pane shows, drawn as the window draws it: its margin and text, not a
            // plain field (its tab bar, above it in the same host, once painted over the whole pane).
            {
                NSView *content = app.window.contentView;
                [content layoutSubtreeIfNeeded];
                [content displayIfNeeded];
                NSRect pane = [ed.secondarySci convertRect:ed.secondarySci.bounds toView:content];
                NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:pane];
                [content cacheDisplayInRect:pane toBitmapImageRep:rep];
                NSMutableSet *colours = [NSMutableSet set];
                for (NSInteger y = 0; y < rep.pixelsHigh; y += 3)
                    for (NSInteger x = 0; x < rep.pixelsWide; x += 3) {
                        NSUInteger px[4] = {0};
                        [rep getPixel:px atX:x y:y];
                        [colours addObject:@((px[0] << 16) | (px[1] << 8) | px[2])];
                    }
                Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW (drawn)",
                      @"the second view draws its document - line numbers and text - rather than an empty field",
                      NSWidth(pane) > 50 && colours.count > 3);
            }

            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:dc]];
            [ed cloneCurrentToOtherView];
            BOOL cloned = [ed.subViewDocuments isEqualToArray:(@[db, dc])] && [ed.mainViewDocuments containsObject:dc] &&
                          [ed documentInSecondaryView] == dc && subBar.selectedIndex == 1;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:da]];
            Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW (own tabs)",
                  @"Clone shows the document in both views' tabs; each view keeps its own document in front",
                  cloned && ed.currentDocument == da && [ed documentInSecondaryView] == dc);

            // Coming back to the application with the focus in the second view checks the files on
            // disk and leaves both views as they were: the main view's tab, the second view's
            // document (its own or a clone), the focus. A file changed on disk that only the second
            // view has is reloaded there (prepareBufferChangedDialog brings it up in the view that has it).
            {
                NppPreferences *prefs = [NppPreferences shared];
                BOOL detectWas = prefs.fileAutoDetection;
                prefs.fileAutoDetection = YES;
                BOOL (^asBefore)(NppDocument *) = ^BOOL(NppDocument *second) {
                    return [ed mainCurrentDocument] == da && (void *)[ed.mainSci message:SCI_GETDOCPOINTER] == da.docPointer &&
                           [ed documentInSecondaryView] == second && [ed otherViewHasFocus] && ed.currentDocument == second;
                };
                [ed showDocumentInSecondaryView:db];
                [app.window makeFirstResponder:ed.secondarySci.content];
                [ed checkFilesOnDisk];
                BOOL ownKept = asBefore(db);
                [ed showDocumentInSecondaryView:dc];
                [app.window makeFirstResponder:ed.secondarySci.content];
                [ed checkFilesOnDisk];
                BOOL cloneKept = asBefore(dc);
                [@"bbb changed\n" writeToFile:pb atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: [NSDate dateWithTimeIntervalSinceNow:60]}
                                                 ofItemAtPath:pb error:NULL];
                ed.scriptedCloseAnswer = NSAlertFirstButtonReturn;       // Reload
                [ed checkFilesOnDisk];
                ed.scriptedCloseAnswer = 0;
                BOOL reloadedThere = asBefore(dc) && !db.modified && [ed.mainViewDocuments isEqualToArray:(@[da, dc])];
                [ed showDocumentInSecondaryView:db];
                BOOL newText = [[ed.secondarySci string] isEqualToString:@"bbb changed\n"];
                // Put back as the checks below expect it: the file as it was, the unsaved "!" on top.
                [@"bbb\n" writeToFile:pb atomically:YES encoding:NSUTF8StringEncoding error:NULL];
                [ed.secondarySci setString:@"bbb\n"];
                [ed.secondarySci message:SCI_SETSAVEPOINT];
                [ed.secondarySci message:SCI_APPENDTEXT wParam:1 lParam:(sptr_t)"!"];
                db.fileModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:pb error:NULL] fileModificationDate];
                [ed showDocumentInSecondaryView:dc];
                prefs.fileAutoDetection = detectWas;
                [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:da]];
                Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW (activation keeps the views)",
                      @"checking the files on disk with the focus in the second view keeps each view's document and the focus; a change to the second view's own file is reloaded there",
                      ownKept && cloneKept && reloadedThere && newText);
            }

            // Session: both views' tabs, as upstream's mainView and subView File entries.
            NSString *sess = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_views_session.xml"];
            [ed saveSessionTo:sess error:NULL];
            NSString *xml = [NSString stringWithContentsOfFile:sess encoding:NSUTF8StringEncoding error:NULL] ?: @"";
            NSRange subAt = [xml rangeOfString:@"<subView"], mainAt = [xml rangeOfString:@"<mainView"];
            NSString *subPart = subAt.location != NSNotFound ? [xml substringFromIndex:subAt.location] : @"";
            NSString *mainPart = mainAt.location != NSNotFound && subAt.location != NSNotFound
                ? [xml substringWithRange:NSMakeRange(mainAt.location, subAt.location - mainAt.location)] : @"";
            BOOL written = [subPart containsString:pb] && [subPart containsString:pc] && [subPart containsString:@"activeIndex=\"1\""] &&
                           [mainPart containsString:pa] && [mainPart containsString:pc] && ![mainPart containsString:pb];

            // Per view closing: the clone's main tab goes without the document; its last tab closes it.
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:dc]];
            [ed closeCurrentDocument];
            BOOL mainTabOnly = ![ed.mainViewDocuments containsObject:dc] && [ed.documents containsObject:dc] &&
                               [ed.subViewDocuments containsObject:dc];
            [(id<NppTabBarDelegate>)ed tabBar:subBar didRequestCloseIndex:(NSInteger)[ed.subViewDocuments indexOfObject:dc]];
            Check(@"IDM_FILE_CLOSE (per view)",
                  @"closing a clone's tab in one view leaves it open in the other; closing its last tab closes it",
                  mainTabOnly && ![ed.documents containsObject:dc] && [ed.subViewDocuments isEqualToArray:@[db]] &&
                  [ed documentInSecondaryView] == db);

            // Compare borrows the pane, not the view's document.
            [ed compareCurrentWithText:@"zzz\n"];
            BOOL comparing = [[ed.secondarySci string] isEqualToString:@"zzz\n"];
            [ed clearActiveCompare];
            Check(@"IDM_VIEW_CLONE_TO_ANOTHER_VIEW (compare)",
                  @"a comparison shows its text in the second pane and gives the view its tab back, untouched",
                  comparing && [ed secondaryViewVisible] && [ed documentInSecondaryView] == db &&
                  [[ed.secondarySci string] isEqualToString:@"bbb\n!"] && !subBar.hidden);

            // From the second view: Move to Other View brings the tab back, and the emptied view goes.
            [ed.window makeFirstResponder:ed.secondarySci.content];
            BOOL focused = [ed otherViewHasFocus];
            [ed moveCurrentToOtherView];
            Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW (from the second view)",
                  @"the second view's tab goes back to the main view's tabs; the view with none left is hidden",
                  focused && ([ed.mainViewDocuments containsObject:db] && !db.secondViewOnly && ed.subViewDocuments.count == 0 &&
                               ![ed secondaryViewVisible] && ed.currentDocument == db));

            [ed closeAllDocuments];
            BOOL loaded = [ed loadSessionFrom:sess error:NULL];
            NppDocument *(^named)(NSString *) = ^NppDocument *(NSString *p) {
                for (NppDocument *d in ed.documents) if ([d.path isEqualToString:p]) return d;
                return nil;
            };
            NppDocument *lb = named(pb), *lc = named(pc);
            Check(@"IDM_FILE_LOADSESSION (both views)",
                  @"a session keeps each view's tabs: the moved file comes back in the second view only, the clone in both",
                  written && loaded && lb && lc && lb.secondViewOnly && [ed.subViewDocuments isEqualToArray:(@[lb, lc])] &&
                  [ed.mainViewDocuments containsObject:lc] && ![ed.mainViewDocuments containsObject:lb] &&
                  [ed documentInSecondaryView] == lc && lb.modified == NO);
            [ed setSecondaryViewVisible:NO];
            BOOL gaveBack = [ed.mainViewDocuments containsObject:lb] && !lb.secondViewOnly;
            Check(@"IDM_VIEW_GOTO_ANOTHER_VIEW (view hidden)", @"hiding the second view gives its documents back to the main view's tabs", gaveBack);
            [ed closeAllDocuments];
        }

        // The focused view is the one commands act on, as upstream's _pEditView and _pDocTab
        // follow the focus: its document is edited, saved, converted and shown in the chrome.
        {
            [ed closeAllDocuments];
            NSString *pa = TempFile(@"t_focus_a.txt", @"alpha\n"), *pb = TempFile(@"t_focus_b.txt", @"beta\n");
            [ed openFileAtPath:pa error:&err];
            [ed openFileAtPath:pb error:&err];
            NppDocument *da = nil, *db = nil;
            for (NppDocument *d in ed.documents) { if ([d.path isEqualToString:pa]) da = d; if ([d.path isEqualToString:pb]) db = d; }
            NppTabBarView *mainBar = [ed valueForKey:@"tabBar"], *subBar = [ed valueForKey:@"subTabBar"];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:db]];
            [ed moveCurrentToOtherView];                                   // b only in the second view, a in the main one
            [ed.window makeFirstResponder:ed.secondarySci.content];
            BOOL follows = [ed secondaryViewIsActive] && ed.sci == ed.secondarySci && ed.otherSci == ed.mainSci &&
                           ed.currentDocument == db && [ed mainCurrentDocument] == da;
            Check(@"IDM_VIEW_SWITCHTO_OTHER_VIEW (active view)",
                  @"with the focus in the second view, the editor and the document commands work on are that view's",
                  follows);

            // Edit: typing there marks its document modified (its own savepoint notification), not the other.
            [ed.sci message:SCI_DOCUMENTEND];
            [ed.sci message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)"x"];
            [ed refreshChrome];
            BOOL title = [ed.window.title containsString:@"t_focus_b.txt"];
            BOOL statusFollows = subBar.inFocusedView && !mainBar.inFocusedView;
            Check(@"IDM_EDIT (focused view)",
                  @"an edit in the second view changes and marks its document; the window title and the active tab indicator follow that view",
                  db.modified && !da.modified && [[ed.secondarySci string] isEqualToString:@"beta\nx"] &&
                  [[ed.mainSci string] isEqualToString:@"alpha\n"] && title && statusFollows);

            // Encoding / Format: EOL conversion; Language: the lexer of the second view's document.
            [ed convertEOLTo:SC_EOL_CRLF];
            [ed setLanguageNamed:@"python"];
            [ed toggleBookmark];
            long bookmarked = [ed.secondarySci message:SCI_MARKERGET wParam:(uptr_t)[ed.secondarySci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[ed.secondarySci message:SCI_GETCURRENTPOS]]] & (1 << 1);
            Check(@"IDM_FORMAT_TODOS (focused view)",
                  @"EOL conversion, the language and a bookmark go to the second view's document, the main view's stays as it was",
                  [[ed.secondarySci string] isEqualToString:@"beta\r\nx"] && db.eolMode == SC_EOL_CRLF &&
                  [[ed.mainSci string] isEqualToString:@"alpha\n"] && da.eolMode != SC_EOL_CRLF &&
                  [db.language.name isEqualToString:@"python"] && ![da.language.name isEqualToString:@"python"] &&
                  bookmarked != 0 && [ed.mainSci message:SCI_MARKERNEXT wParam:0 lParam:(1 << 1)] == -1);

            // File: Save writes the second view's document.
            [ed saveCurrentDocument];
            NSString *onDisk = [NSString stringWithContentsOfFile:pb encoding:NSUTF8StringEncoding error:NULL];
            NSString *otherOnDisk = [NSString stringWithContentsOfFile:pa encoding:NSUTF8StringEncoding error:NULL];
            Check(@"IDM_FILE_SAVE (focused view)",
                  @"Save writes the focused second view's document and clears its modified mark",
                  [onDisk isEqualToString:@"beta\r\nx"] && [otherOnDisk isEqualToString:@"alpha\n"] && !db.modified);

            // Search: Find acts in the focused view.
            [ed.sci message:SCI_GOTOPOS wParam:0 lParam:0];
            [ed.sci message:SCI_SETTARGETSTART wParam:0 lParam:0];
            [ed.sci message:SCI_SETTARGETEND wParam:(uptr_t)[ed.sci message:SCI_GETLENGTH] lParam:0];
            long found = [ed.sci message:SCI_SEARCHINTARGET wParam:3 lParam:(sptr_t)"eta"];
            Check(@"IDM_SEARCH_FIND (focused view)", @"the second view's text is what a search in it sees", found == 1);

            // Tabs: Ctrl+Tab goes through the focused view's tabs; a main-view tab brings the focus back.
            [ed.window makeFirstResponder:ed.mainSci.content];
            [ed cloneCurrentToOtherView];                                  // a in both views
            [ed.window makeFirstResponder:ed.secondarySci.content];
            NppDocument *subFront = [ed documentInSecondaryView];
            [ed goToNextTab];
            BOOL cycled = [ed documentInSecondaryView] != subFront && [ed secondaryViewIsActive] && [ed mainCurrentDocument] == da;
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:da]];
            Check(@"IDM_VIEW_TAB_NEXT (focused view)",
                  @"Next Tab goes through the second view's tabs while it has the focus; choosing a main-view tab gives the main view the focus",
                  cycled && ![ed otherViewHasFocus] && ed.currentDocument == da && ed.sci == ed.mainSci);

            // The second view's tab bar follows the Tab Bar preferences as the main one does.
            NppPreferences *tp = [NppPreferences shared];
            BOOL wasVertical = tp.tabBarVertical, wasMulti = tp.tabBarMultiLine, wasReduced = tp.tabReduced, wasClose = tp.tabShowCloseButton;
            tp.tabBarVertical = YES; tp.tabReduced = YES; tp.tabShowCloseButton = NO;
            [ed applyTabBarPreferences];
            NSView *host = [ed secondaryHost];
            BOOL vertical = subBar.vertical && subBar.reduced && !subBar.showCloseButtons &&
                            NSHeight(subBar.frame) == NSHeight(host.bounds) && NSMinX(ed.secondarySci.frame) >= NSWidth(subBar.frame) - 0.5 &&
                            NSWidth(subBar.frame) > 40;
            tp.tabBarVertical = NO; tp.tabBarMultiLine = YES;
            [ed applyTabBarPreferences];
            BOOL multi = subBar.multiLine && !subBar.vertical && NSMaxY(ed.secondarySci.frame) <= NSMinY(subBar.frame) + 0.5;
            tp.tabBarVertical = wasVertical; tp.tabBarMultiLine = wasMulti; tp.tabReduced = wasReduced; tp.tabShowCloseButton = wasClose;
            [ed applyTabBarPreferences];
            Check(@"IDM_SETTING_PREFERENCE (second view's tab bar)",
                  @"the second view's tab bar is vertical, multi-line, reduced and without close buttons when the preferences say so",
                  vertical && multi);

            // Session: an untitled document only in the second view comes back there, from its backup.
            [ed newDocument];
            SetDoc(ed, @"only in the second view\n");
            ed.currentDocument.modified = YES;
            NppDocument *untitled = ed.currentDocument;
            NSString *untitledName = untitled.displayName;
            [ed moveCurrentToOtherView];
            [ed runAutosavePass];
            NSString *sess = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_focus_session.xml"];
            [ed saveSessionTo:sess error:NULL];
            NSString *xml = [NSString stringWithContentsOfFile:sess encoding:NSUTF8StringEncoding error:NULL] ?: @"";
            NSRange subAt = [xml rangeOfString:@"<subView"];
            NSString *subPart = subAt.location != NSNotFound ? [xml substringFromIndex:subAt.location] : @"";
            NSString *mainPart = subAt.location != NSNotFound ? [xml substringToIndex:subAt.location] : xml;
            NSString *backup = untitled.backupPath;
            BOOL written = untitled.secondViewOnly && backup.length && [subPart containsString:backup] && ![mainPart containsString:backup];
            untitled.backupPath = nil;                                     // closed as a crash would leave it
            [ed closeAllDocuments];
            [ed loadSessionFrom:sess error:NULL];
            NppDocument *back = nil;
            for (NppDocument *d in ed.documents) if (!d.path && [d.backupPath isEqualToString:backup ?: @"-"]) back = d;
            BOOL restored = back && back.secondViewOnly && [ed.subViewDocuments containsObject:back] &&
                            ![ed.mainViewDocuments containsObject:back] && [back.displayName isEqualToString:untitledName] && back.modified &&
                            (void *)[ed.secondarySci message:SCI_GETDOCPOINTER] == back.docPointer &&
                            [[ed.secondarySci string] isEqualToString:@"only in the second view\n"];
            Check(@"IDM_FILE_LOADSESSION (untitled in the second view)",
                  @"an untitled document only in the second view is written in subView with its backup and comes back in that view",
                  written && restored);
            if (backup) [[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];
            [[NSFileManager defaultManager] removeItemAtPath:sess error:NULL];
            [ed setSecondaryViewVisible:NO];
            [ed closeAllDocuments];
        }

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
        {
            // Shown, the list follows the editor: parsed again on a language change (and on a switch or a
            // save), not on every keystroke.
            [fl toggle];
            SetDoc(ed, @"def alpha(x):\n    return x\n\ndef gamma():\n    pass\n");
            [ed refreshChrome];
            NSString *(^listed)(void) = ^NSString *{
                NSMutableArray *n = [NSMutableArray array];
                for (NSDictionary *e in [fl valueForKey:@"entries"]) [n addObject:e[@"name"]];
                return [n componentsJoinedByString:@" "];
            };
            BOOL notWhileTyping = ![listed() containsString:@"gamma"];
            [ed setLanguageNamed:@"cpp"];
            [ed refreshChrome];
            [ed setLanguageNamed:@"python"];
            [ed refreshChrome];
            BOOL afterLanguage = [listed() containsString:@"gamma"];
            [fl toggle];
            Check(@"IDM_VIEW_FUNC_LIST (follows the editor)", @"the shown list is parsed again when the language changes, not while typing",
                  notWhileTyping && afterLanguage);
        }

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

            // JSON with comments and trailing commas is JSON5 (the json5 lexer is for it), not
            // JSON: texts the trainer never saw, where JSON is not even offered; plain JSON stays JSON.
            NSString *jsonc = @"{\n    // the editor as I like it\n    \"editor.fontSize\": 13,\n    \"editor.rulers\": [80, 120],\n"
                              @"    /* keep the tabs */\n    \"files.trimTrailingWhitespace\": true,\n"
                              @"    \"search.exclude\": {\n        \"**/build\": true,\n    },\n}\n";
            NSString *plainJson = @"{\n  \"name\": \"viewer\",\n  \"version\": \"2.1.0\",\n  \"private\": true,\n  \"scripts\": {\n"
                                  @"    \"build\": \"tsc -p .\",\n    \"test\": \"jest\"\n  },\n"
                                  @"  \"dependencies\": {\n    \"left-pad\": \"^1.3.0\"\n  }\n}\n";
            BOOL jsoncIsJson5 = [[trained guessesForText:jsonc].firstObject.name isEqualToString:@"json5"] &&
                                ![[trained languagesOfferedForText:jsonc] containsObject:@"json"];
            BOOL jsonIsJson = [[trained guessesForText:plainJson].firstObject.name isEqualToString:@"json"];
            Check(@"IDM_LANG_DETECT (JSON5)",
                  @"JSON with comments and trailing commas is taken for JSON5, not offered as JSON, and plain JSON stays JSON",
                  jsoncIsJson5 && jsonIsJson);

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
}

/// == Docking ==
void NppTestsDocking(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Docking")) { printf("\n== Docking ==\n");
        NppDockingManager *dock = [NppDockingManager shared];
        NSDictionary *layoutBefore = [NppPreferences shared].dockLayout;
        {
            // A panel not made yet this run keeps its stored place when the layout is saved again.
            NSMutableDictionary *withGhost = [layoutBefore mutableCopy] ?: [NSMutableDictionary dictionary];
            NSMutableDictionary *ghostPlaces = [withGhost[@"places"] mutableCopy] ?: [NSMutableDictionary dictionary];
            ghostPlaces[@"t_unmade_panel"] = @(NppDockBottom);
            withGhost[@"places"] = ghostPlaces;
            [NppPreferences shared].dockLayout = withGhost;
            [dock performSelector:NSSelectorFromString(@"saveLayout")];
            Check(@"Docking (layout kept)", @"saving the layout keeps the place of a panel not made yet this run",
                  [[NppPreferences shared].dockLayout[@"places"][@"t_unmade_panel"] integerValue] == NppDockBottom);
            [NppPreferences shared].dockLayout = layoutBefore;
        }
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
        // The window made wider and back: the docks keep their size, the editor takes the difference.
        NSRect frameBefore = app.window.frame;
        CGFloat rightBefore = [dock sizeOfPlace:NppDockRight];
        [app.window setFrame:NSInsetRect(frameBefore, -80, 0) display:YES];
        [app.window setFrame:frameBefore display:YES];
        BOOL keptOnResize = fabs([dock sizeOfPlace:NppDockRight] - rightBefore) < 1 &&
            fabs([[NppPreferences shared].dockLayout[@"sizes"][@(NppDockRight).stringValue] doubleValue] - rightBefore) < 1;
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
        drops = drops && NSMinX(leftStrip) <= NSMinX(w) + 2 && NSWidth(leftStrip) < NSWidth(w) &&
                fabs(NSWidth(leftStrip) - ([dock sizeOfPlace:NppDockLeft] ?: 220)) < 1 && NSHeight(leftStrip) > NSHeight(w) / 2 &&
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
        Check(@"IDM_VIEW_DOCLIST (window resized)",
              @"a window made wider and back leaves the docks' sizes, shown and stored, as they were (only a divider dragged changes them)",
              keptOnResize);
    }
}

/// == Tab bar ==
void NppTestsTabBar(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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

        CGFloat shownH = NSHeight(ed.sci.frame);
        p.hideTabBar = YES;
        [ed applyTabBarPreferences];
        BOOL hidden = bar.isHidden;
        CGFloat hiddenH = NSHeight(ed.sci.frame);
        p.hideTabBar = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (hide tab bar)",
              @"the bar can be hidden and shown, and the editor takes its room meanwhile",
              hidden && !bar.isHidden && hiddenH == shownH + NSHeight(bar.frame) && NSHeight(ed.sci.frame) == shownH);

        p.tabBarLocked = YES;
        [ed applyTabBarPreferences];
        BOOL locked = bar.locked;
        p.tabBarLocked = NO;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab bar lock)",
              @"locking is passed to the bar", locked && !bar.locked);
    }
}

/// == Font fallback ==; == Tab bar layout ==
void NppTestsFontAndTabLayout(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Font fallback")) { printf("\n== Font fallback ==\n");
        // A font the Mac lacks (Consolas, which only Microsoft Office brings) gives the system's
        // monospaced font; Core Text alone would answer Helvetica, whose columns do not line up.
        NSString *mono = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular].fontName;
        Check(@"Font fallback", @"a missing font name gives the system's monospaced font, an installed one is kept",
              [NppAvailableFontName(@"NoSuchFontNppMac") isEqualToString:mono] &&
              [NppAvailableFontName(@"Menlo") isEqualToString:@"Menlo"] &&
              [NppAvailableFontName(@"Courier New") isEqualToString:@"Courier New"]);

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        id wasFont = [ud objectForKey:@"NppMac.fontName"];
        [NppPreferences shared].fontName = @"NoSuchFontNppMac";
        SetDoc(ed, @"iiiiiiii\nWWWWWWWW\n");
        [ed applyLanguage];
        char face[256] = {0};
        [sci message:SCI_STYLEGETFONT wParam:STYLE_DEFAULT lParam:(sptr_t)face];
        long line2 = [sci message:SCI_POSITIONFROMLINE wParam:1];
        long narrow = [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:8];
        long wide = [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:line2 + 8];
        Check(@"Font fallback", @"with the chosen font missing the editor is set in the monospaced font and columns line up",
              [@(face) isEqualToString:mono] && narrow == wide && narrow > 0);
        if (wasFont) [ud setObject:wasFont forKey:@"NppMac.fontName"]; else [ud removeObjectForKey:@"NppMac.fontName"];
        [ed applyLanguage];
        SetDoc(ed, @"");
    }

    if (NppSectionWanted(@"Tab bar layout")) { printf("\n== Tab bar layout ==\n");
        // TabBarPlus with TCS_VERTICAL: a column of tabs left of the panes; Multi-line: as many rows as needed.
        NppPreferences *tp = [NppPreferences shared];
        BOOL wasVertical = tp.tabBarVertical, wasMulti = tp.tabBarMultiLine, wasHidden = tp.hideTabBar;
        tp.hideTabBar = NO;
        NSView *bar = [ed valueForKey:@"tabBar"], *panes = [ed valueForKey:@"editorSplit"], *area = [ed valueForKey:@"editorArea"];
        tp.tabBarVertical = YES;
        [ed applyTabBarPreferences];
        BOOL side = NSHeight(bar.frame) > NSWidth(bar.frame) && NSMaxX(bar.frame) <= NSMinX(panes.frame) + 0.5 &&
                    NSHeight(panes.frame) == NSHeight(area.bounds);
        tp.tabBarVertical = NO;
        [ed applyTabBarPreferences];
        BOOL strip = NSWidth(bar.frame) == NSWidth(area.bounds) && NSHeight(bar.frame) == 28 &&
                     NSMaxY(panes.frame) <= NSMinY(bar.frame) + 0.5 && NSMinX(panes.frame) == 0;
        Check(@"IDM_SETTING_PREFERENCE (tab bar vertical)",
              @"Vertical puts the tab bar in a column left of the panes, and back in the strip above them",
              side && strip);
        NSMutableArray<NSString *> *made = [NSMutableArray array];
        for (int i = 0; i < 14; ++i) { [ed newDocument]; [made addObject:ed.currentDocument.displayName ?: @""]; }
        tp.tabBarMultiLine = YES;
        [ed applyTabBarPreferences];
        [ed refreshChrome];
        BOOL rows = NSHeight(bar.frame) > 28 && NSMaxY(panes.frame) <= NSMinY(bar.frame) + 0.5;
        tp.tabBarMultiLine = wasMulti;
        [ed applyTabBarPreferences];
        Check(@"IDM_SETTING_PREFERENCE (tab bar multi-line)", @"Multi-line makes the strip as tall as its rows; the panes give it the room",
              rows && NSHeight(bar.frame) == 28);
        for (NSInteger i = (NSInteger)ed.documents.count - 1; i >= 0; --i) {
            if ([made containsObject:ed.documents[(NSUInteger)i].displayName ?: @""] && !ed.documents[(NSUInteger)i].path)
                [ed closeDocumentAtIndex:i discardChanges:YES];
        }
        tp.tabBarVertical = wasVertical; tp.hideTabBar = wasHidden;
        [ed applyTabBarPreferences];
    }
}
