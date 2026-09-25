// The built-in suite, the editor settings, the Preferences pages, localisation and new-document defaults.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Editor settings Notepad++ has ==
void NppTestsEditorSettings(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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

        {
            // A narrower window: the path field gets at most half the bar again, not the width it had.
            NSView *box = [ed valueForKey:@"container"];
            NSTextField *pf = [ed valueForKey:@"pathField"];
            NSRect was = box.frame;
            pf.stringValue = [@"" stringByPaddingToLength:300 withString:@"/deep" startingAtIndex:0];
            [ed performSelector:NSSelectorFromString(@"layoutStatusFields")];
            [box setFrameSize:NSMakeSize(640, NSHeight(was))];
            BOOL halved = NSWidth(pf.frame) <= 320 + 1;
            [box setFrameSize:was.size];
            [ed refreshChrome];
            Check(@"Status bar (window size)", @"the path field takes at most half the bar after the window is resized", halved);
        }
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
        // "None" survives the theme being put on again (its caret-line colour turned the line back on).
        p.currentLineHighlightMode = 0;
        [ed applyEditorPreferences];
        [ed applyTheme];
        BOOL stillPlain = [sv message:SCI_GETCARETLINEVISIBLE] == 0;
        p.currentLineHighlightMode = 1;
        [ed applyEditorPreferences];
        [ed applyTheme];
        Check(@"IDM_SETTING_PREFERENCE (current line, theme)",
              @"None stays off after the theme is applied again; Highlight comes back with it (SETTINGS-020)",
              stillPlain && [sv message:SCI_GETCARETLINEVISIBLE] != 0);

        // Editing 1's font, once chosen, wins over the theme's Default Style font (SETTINGS-018).
        NSString *wasFont = p.fontName; NSInteger wasSize = p.fontSize;
        BOOL hadChosenFont = p.chosenFontName != nil, hadChosenSize = p.chosenFontSize > 0;
        p.fontName = @"Courier"; p.fontSize = 17;
        [ed applyEditorPreferences];
        [ed applyTheme];
        char fontBuf[128] = {0};
        [sv message:SCI_STYLEGETFONT wParam:STYLE_DEFAULT lParam:(sptr_t)fontBuf];
        BOOL chosenWins = strcmp(fontBuf, "Courier") == 0 && [sv message:SCI_STYLEGETSIZE wParam:STYLE_DEFAULT] == 17;
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        if (hadChosenFont) p.fontName = wasFont; else if (domain) [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppMac.fontName"];
        if (hadChosenSize) p.fontSize = wasSize; else if (domain) [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppMac.fontSize"];
        [ed applyEditorPreferences];
        [ed applyTheme];
        Check(@"IDM_SETTING_PREFERENCE (font)",
              @"a font chosen on Editing 1 is the editor's, over the theme's Default Style font",
              chosenWins);

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
}

/// == Settings ==; == Preferences: pages ==; == Window tabbing ==; == Block Comment key ==; == New document defaults ==; == Appearance: themes ==; == Toolbar ==; == Backup and autosave ==; == Print options ==; == Performance, links, delimiters ==; == Instances, panels, settings folder ==; == Auto-completion and typing ==; == Preferences: Language, Indentation, MISC., Search Engine ==; == Preferences: Editing and Margins ==; == Preferences: Highlighting, Date, Print, Searching ==; == Preferences: Toolbar, Tab Bar, panels, Cancel ==
void NppTestsPreferences(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
            NSButton *saveClose = nil;
            for (NSView *v in [[conf valueForKey:@"panel"] contentView].subviews)
                if ([v isKindOfClass:[NSButton class]] && [((NSButton *)v).title containsString:@"Close"]) saveClose = (NSButton *)v;
            Check(@"IDM_LANGSTYLE_CONFIG_DLG", @"the button reads \"Save & Close\", not upstream's escaped \"&&\"",
                  [NppLocalization shared].active || [saveClose.title isEqualToString:@"Save & Close"]);
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

        // A Run command's key reaches its menu item even where a default has it: Ctrl+Alt+H
        // from Windows is Cmd+Opt+H, Hide Others' - the key the user gave wins.
        {
            NSMenuItem *(^itemTitled)(NSString *) = ^NSMenuItem *(NSString *title) {
                __block NSMenuItem *found = nil;
                __block void (^walk)(NSMenu *);
                void (^walker)(NSMenu *) = ^(NSMenu *m) {
                    for (NSMenuItem *i in m.itemArray) {
                        if ([i.title isEqualToString:title]) found = i;
                        if (i.submenu) walk(i.submenu);
                    }
                };
                walk = walker;
                walker(NSApp.mainMenu);
                walk = nil;
                return found;
            };
            [ed saveCommand:[NppSavedCommand commandWithName:@"Key test" command:@"echo k"]];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NppSavedCommandsDidChange" object:nil];
            NppShortcutCommand *keyed = nil;
            for (NppShortcutCommand *c in [app.shortcutStore commandsInCategory:NppShortcutRunCommand])
                if ([c.name isEqualToString:@"Key test"]) keyed = c;
            NppKeyCombo *ctrlAltH = [NppKeyCombo comboWithWindowsCtrl:YES alt:YES shift:NO macControl:NO virtualKey:72];
            [app.shortcutStore setCombo:ctrlAltH forCommand:keyed];
            [app.shortcutStore applyToMenus];
            NSMenuItem *run = itemTitled(@"Key test"), *hideOthers = itemTitled(@"Hide Others");
            BOOL taken = [run.keyEquivalent isEqualToString:@"h"] &&
                         (run.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask) ==
                             (NSEventModifierFlagCommand | NSEventModifierFlagOption) &&
                         hideOthers && hideOthers.keyEquivalent.length == 0;
            [app.shortcutStore setCombo:nil forCommand:keyed];
            [ed removeSavedCommandNamed:@"Key test"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NppSavedCommandsDidChange" object:nil];
            [app.shortcutStore applyToMenus];
            Check(@"IDM_SETTING_SHORTCUT_MAPPER (a key a default has)",
                  @"a Run command's Cmd+Opt+H is on its item, taken from Hide Others, which gets it back after",
                  taken && [itemTitled(@"Hide Others").keyEquivalent isEqualToString:@"h"]);
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
        Check(@"Preferences (defaults)", @"a new document in addition at startup is off, as upstream (_addNewDocumentOnStartup = false)",
              [[[NSUserDefaults standardUserDefaults] volatileDomainForName:NSRegistrationDomain][@"NppMac.openNewDocumentAtStartup"] isEqual:@NO]);
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

    if (NppSectionWanted(@"Window tabbing")) { printf("\n== Window tabbing ==\n");
        Check(@"Window menu (window tabbing)",
              @"AppKit's window tabs are off, so the Window menu has no Show Next Tab (Ctrl+Tab) or Merge All Windows of its own",
              !NSWindow.allowsAutomaticWindowTabbing);
    }

    if (NppSectionWanted(@"Block Comment key")) { printf("\n== Block Comment key ==\n");
        NSMenuItem *block = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *it in top.submenu.itemArray) {
                if (it.action == NSSelectorFromString(@"toggleBlockComment:")) block = it;
                for (NSMenuItem *sub in it.submenu.itemArray)
                    if (sub.action == NSSelectorFromString(@"toggleBlockComment:")) block = sub;
            }
        Check(@"IDM_EDIT_STREAM_COMMENT (key)",
              @"Block Comment is Option+Cmd+/: Shift+Cmd+/ is Cmd+?, which macOS keeps for the Help menu's search",
              block && [block.keyEquivalent isEqualToString:@"/"] &&
              (block.keyEquivalentModifierMask & NSEventModifierFlagDeviceIndependentFlagsMask) ==
                  (NSEventModifierFlagCommand | NSEventModifierFlagOption));
    }

    if (NppSectionWanted(@"New document defaults")) { printf("\n== New document defaults ==\n");
        // The registered default, whatever the user set: NewDocDefaultSettings::_addNewDocumentOnStartup.
        NSDictionary *registered = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSRegistrationDomain];
        Check(@"IDM_SETTING_PREFERENCE (new document at startup)",
              @"\"Always open a new document in addition at startup\" is off by default, as upstream",
              [registered[@"NppMac.openNewDocumentAtStartup"] isEqual:@NO]);
        Check(@"IDM_SETTING_PREFERENCE (remember session)",
              @"\"Remember current session for next launch\" is on by default, as upstream (NppGUI::_rememberLastSession)",
              [registered[@"NppMac.restoreSession"] isEqual:@YES]);
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
        p.appearanceMode = 1;
        [p applyToEditor:ed];
        BOOL chromeLight = [NSApp.appearance.name isEqualToString:NSAppearanceNameAqua];
        p.appearanceMode = 2;
        [p applyToEditor:ed];
        BOOL chromeDark = [NSApp.appearance.name isEqualToString:NSAppearanceNameDarkAqua];
        p.appearanceMode = 0;
        [p applyToEditor:ed];
        Check(@"IDM_SETTING_PREFERENCE (appearance)",
              @"Light and Dark dress the whole interface, following the system leaves it to the system",
              chromeLight && chromeDark && NSApp.appearance == nil);

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

        // Notepad_plus::checkMacroState reaches every button, those in the overflow of a narrow
        // window too: with nothing recorded, Stop Recording and Play are greyed out.
        NSToolbarItem *stopItem = nil, *playItem = nil;
        for (NSToolbarItem *item in app.window.toolbar.items) {
            if (item.action == @selector(macroStop:)) stopItem = item;
            if (item.action == @selector(macroPlay:)) playItem = item;
        }
        stopItem.enabled = YES; playItem.enabled = YES;   // as a button no validation has reached is
        [ed refreshChrome];
        Check(@"IDM_MACRO_STOPRECORDINGMACRO (toolbar)", @"every button follows the state, visible or in the overflow",
              stopItem && playItem && !stopItem.isEnabled && (playItem.isEnabled == ([ed recordedStepCount] > 0)));

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

        // Styled output, as upstream's SCI_FORMATRANGEFULL: each style's colour and
        // bold, line numbers in their own style; the editor's styles are left whole.
        SetDoc(ed, @"// note\nint x;\n");
        [ed setLanguageNamed:@"cpp"];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        long commentFore = [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE];
        long wordBold = [sci message:SCI_STYLEGETBOLD wParam:(uptr_t)[sci message:SCI_GETSTYLEAT wParam:8]];   // "int"
        p.printColourMode = NppPrintWYSIWYG;
        p.printLineNumbers = YES;
        NSString *fontWas = p.fontName;
        p.fontName = @"Menlo";                       // a family with a bold face
        NSTextStorage *styled = ((NSTextView *)[ed printOperationShowingPanel:NO].view).textStorage;
        p.printLineNumbers = NO;
        p.fontName = fontWas;
        NSRange noteAt = [styled.string rangeOfString:@"// note"];
        NSRange intAt = [styled.string rangeOfString:@"int"];
        NSColor *noteColour = noteAt.length ? [[styled attribute:NSForegroundColorAttributeName atIndex:noteAt.location
                                                 effectiveRange:NULL] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] : nil;
        NSFont *intFont = intAt.length ? [styled attribute:NSFontAttributeName atIndex:intAt.location effectiveRange:NULL] : nil;
        BOOL intBold = (intFont.fontDescriptor.symbolicTraits & NSFontDescriptorTraitBold) != 0;
        long printedFore = noteColour ? (lround(noteColour.redComponent * 255) | lround(noteColour.greenComponent * 255) << 8 |
                                         lround(noteColour.blueComponent * 255) << 16) : -1;
        Check(@"IDM_FILE_PRINT (styled)",
              @"the print keeps each style's colour and bold, with numbered lines, and leaves the editor's styles whole",
              [styled.string hasPrefix:@"1  // note"] && [styled.string containsString:@"2  int x;"] &&
              printedFore == commentFore && intBold == (wordBold != 0) &&
              [sci message:SCI_STYLEGETFORE wParam:SCE_C_COMMENTLINE] == commentFore &&
              [sci message:SCI_TEXTWIDTH wParam:STYLE_LINENUMBER lParam:(sptr_t)"_999"] > 0);
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

        // A right click outside the selection puts the caret where it was made - on the
        // character under it, the margins beside the text counted as Scintilla counts them.
        SetDoc(ed, @"abc def\n");
        [sci message:SCI_SETSEL wParam:0 lParam:3];
        // Where "d" is in the content view: the margins are a ruler beside it, so the text
        // starts at its left edge, a character is as wide as Scintilla measures it.
        NSRect shown = sci.content.visibleRect;
        long charWidth = [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:6] - [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:5];
        NSPoint local = NSMakePoint(shown.origin.x + 5 * charWidth + charWidth / 2,
                                    shown.origin.y + [sci message:SCI_POINTYFROMPOSITION wParam:0 lParam:5] + 2);
        NSPoint inWindow = [sci.content convertPoint:local toView:nil];
        BOOL wasKept = p.rightClickKeepsSelection;
        p.rightClickKeepsSelection = NO;
        [ed contextClickAtWindowPoint:inWindow window:sci.window];
        BOOL moved = [sci message:SCI_GETSELECTIONSTART] == 5 && [sci message:SCI_GETSELECTIONEND] == 5;
        [sci message:SCI_SETSEL wParam:0 lParam:3];
        p.rightClickKeepsSelection = YES;
        [ed contextClickAtWindowPoint:inWindow window:sci.window];
        BOOL kept = [sci message:SCI_GETSELECTIONSTART] == 0 && [sci message:SCI_GETSELECTIONEND] == 3;
        p.rightClickKeepsSelection = wasKept;
        Check(@"IDM_SETTING_PREFERENCE (right click)",
              @"a right click on \"def\" moves the caret there, or keeps the selection when asked to",
              moved && kept);
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
            if ([other message:SCI_INDICATORVALUEAT wParam:NPPMAC_SMART_INDICATOR lParam:pos] &&
                (pos == 0 || ![other message:SCI_INDICATORVALUEAT wParam:NPPMAC_SMART_INDICATOR lParam:pos - 1])) inOther++;
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
}

/// == Localization ==; == New documents, recent files, directories ==; == Searching and highlighting settings ==
void NppTestsLocalizationAndDefaults(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        {
            // The port's own wording (nativeLang-extra) wins over upstream's translation of a
            // like-named command; the Find window's title follows its tab in the translation.
            __block NSMenuItem *trash = nil, *count = nil;
            __block void (^find)(NSMenu *);
            void (^__block __weak weakFind)(NSMenu *);
            find = ^(NSMenu *m) {
                for (NSMenuItem *it in m.itemArray) {
                    if (it.submenu) { weakFind(it.submenu); continue; }
                    if (it.action == NSSelectorFromString(@"moveToTrash:")) trash = it;
                    if (it.action == NSSelectorFromString(@"numbersInsertCount:")) count = it;
                }
            };
            weakFind = find;
            find(NSApp.mainMenu);
            Check(@"Localization (own wording)", @"Move to Trash and Selected Numbers > Count read as nativeLang-extra words them",
                  (!trash || [trash.title isEqualToString:@"Переместить в Корзину"]) && [count.title isEqualToString:@"Количество"]);
        }
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

        // Push buttons too, in long-word and CJK languages (L10N-015): each is as wide
        // as its words, and a row moved to make room covers nothing else in it.
        NSMutableArray<NSString *> *cutButtons = [NSMutableArray array];
        __block void (^pushScan)(NSView *, NSString *) = nil;
        void (^__block __weak weakPushScan)(NSView *, NSString *);
        pushScan = ^(NSView *v, NSString *where) {
            if (v.hidden) return;
            NSMutableArray<NSButton *> *row = [NSMutableArray array];
            for (NSView *sub in v.subviews) {
                if (sub.hidden || ![sub isKindOfClass:[NSButton class]] || [sub isKindOfClass:[NSPopUpButton class]]) continue;
                NSButton *b = (NSButton *)sub;
                if (!b.title.length || (((NSButtonCell *)b.cell).showsStateBy & NSContentsCellMask) || !b.isBordered || NSHeight(b.frame) < 24) continue;
                if (b.cell.cellSize.width > NSWidth(b.frame) + 1.5)
                    [cutButtons addObject:[NSString stringWithFormat:@"%@: \"%@\" needs %.0f of %.0f", where, b.title, b.cell.cellSize.width, NSWidth(b.frame)]];
                for (NSButton *other in row)
                    if (NSIntersectsRect(NSInsetRect(other.frame, 1, 1), NSInsetRect(b.frame, 1, 1)))
                        [cutButtons addObject:[NSString stringWithFormat:@"%@: \"%@\" covers \"%@\"", where, b.title, other.title]];
                [row addObject:b];
            }
            for (NSView *sub in v.subviews) weakPushScan(sub, where);
        };
        weakPushScan = pushScan;
        for (NSString *file in @[@"german.xml", @"hungarian.xml", @"finnish.xml", @"french.xml", @"japanese.xml", @"russian.xml"]) {
            lp.localizationFile = file;
            [app applyLocalization];
            for (NSInteger tab = 0; tab < findTabsToScan.segmentCount; ++tab) {
                [app openFindPanelOnTab:tab];
                [[NppLocalization shared] localizeWindow:findDialog];
                pushScan(findDialog.contentView, [NSString stringWithFormat:@"%@ Find tab %ld", file, (long)tab]);
            }
            [findDialog orderOut:nil];
            StyleConfiguratorWindow *style = [[StyleConfiguratorWindow alloc] initWithEditor:ed];
            [style show];
            NSWindow *styleWindow = [style valueForKey:@"panel"];
            [[NppLocalization shared] localizeWindow:styleWindow];
            pushScan(styleWindow.contentView, [file stringByAppendingString:@" Style Configurator"]);
            [style cancel:nil];
            NppShortcutMapper *mapper = [[NppShortcutMapper alloc] initWithStore:app.shortcutStore editor:ed];
            [mapper toggle];
            NSWindow *mapperWindow = [mapper valueForKey:@"panel"];
            [[NppLocalization shared] localizeWindow:mapperWindow];
            pushScan(mapperWindow.contentView, [file stringByAppendingString:@" Shortcut Mapper"]);
            [mapper toggle];
            NppUserLanguageDialog *udl = [[NppUserLanguageDialog alloc] initWithEditor:ed];
            [udl toggle];
            NSWindow *udlWindow = [udl valueForKey:@"panel"];
            [[NppLocalization shared] localizeWindow:udlWindow];
            pushScan(udlWindow.contentView, [file stringByAppendingString:@" User Defined Language"]);
            [udl toggle];
            PreferencesWindow *pages = [[PreferencesWindow alloc] initWithEditor:ed];
            [pages toggle];
            NSWindow *pagesWindow = [pages valueForKey:@"panel"];
            for (NSUInteger page = 0; page < [pages categoryNames].count; ++page) {
                [pages showPageAtIndex:(NSInteger)page];
                [[NppLocalization shared] localizeWindow:pagesWindow];
                pushScan(pagesWindow.contentView, [NSString stringWithFormat:@"%@ Preferences page %lu", file, (unsigned long)page]);
            }
            [pages toggle];
        }
        lp.localizationFile = @"russian.xml";
        [app applyLocalization];
        if (cutButtons.count) printf("    cut or covered buttons:\n        %s\n", [cutButtons componentsJoinedByString:@"\n        "].UTF8String);
        Check(@"Localization (buttons fit)",
              @"in German, Hungarian, Finnish, French, Japanese and Russian every push button of Find, the Style Configurator, the Shortcut Mapper, User Defined Language and Preferences fits its title and covers no other",
              cutButtons.count == 0);

        // The Summary as upstream writes it, by <MiscStrings> id (IDM_VIEW_SUMMARY).
        NSString *summary = [app summaryText];
        NSString *summaryTitle = [[NppLocalization shared] stringWithID:@"summary" default:@"Summary"];
        Check(@"IDM_VIEW_SUMMARY (translated)",
              @"the Summary's title and labels are the translation's summary strings, as upstream shows them",
              [summaryTitle isEqualToString:@"Информация о Файле"] && [summary containsString:@"Символов (без окончания строки) :  "] &&
              [summary containsString:@"Строк :  "] && ![summary containsString:@"Characters"]);

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
}
