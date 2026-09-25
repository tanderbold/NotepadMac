// The built-in suite, the Edit menu: undo and redo, sorting, the line, blank, case, clipboard and selection commands, selected numbers.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Edit ==
void NppTestsEdit(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        Check(@"IDM_EDIT_BLOCK_COMMENT", @"line comment toggles both ways", commented && restored);

        // The selection follows the text: toggling twice without reselecting restores (EDIT-052).
        SetDoc(ed, @"int a;\n  int b;\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        [ed toggleLineComment];
        Check(@"IDM_EDIT_BLOCK_COMMENT", @"the lines stay selected, so a second toggle takes the comments off",
              [DocText(ed) isEqualToString:@"int a;\n  int b;\n"]);
        // Single Line Comment always adds a level (EDIT-054).
        SetDoc(ed, @"// a\nb\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed setLineComment];
        Check(@"IDM_EDIT_BLOCK_COMMENT_SET", @"adds a comment level to every line, commented or not",
              [DocText(ed) isEqualToString:@"// // a\n// b\n"]);
        // A language with only a stream comment wraps each line (EDIT-056).
        [ed setLanguageNamed:@"html"];
        SetDoc(ed, @"<p>hi</p>\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed toggleLineComment];
        BOOL wrappedHtml = [DocText(ed) isEqualToString:@"<!-- <p>hi</p> -->\n"];
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_COMMENT", @"HTML lines are wrapped in <!-- --> and unwrapped again",
              wrappedHtml && [DocText(ed) isEqualToString:@"<p>hi</p>\n"]);
        [ed setLanguageNamed:@"cpp"];

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
}

/// == Sorting: the way Notepad++ sorts ==
void NppTestsSorting(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
}

/// == Edit: convert case ==; == Edit: sorting ==; == Edit: line operations ==; == Edit: blank operations ==; == Edit: indent, delete, comments, read-only ==; == Edit: clipboard and insert ==; == Edit: multi-selection ==; == Edit: begin/end select and column editor ==; == Edit: paste special ==; == Edit: on selection ==; == Edit: completion, panels, file attribute ==
void NppTestsEditMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
        SetDoc(ed, @"keep\n");
        [sci message:SCI_SETEMPTYSELECTION wParam:2];
        [ed convertCase:NppCaseUpper];
        Check(@"IDM_EDIT_UPPERCASE", @"with nothing selected nothing changes (convertSelectedTextTo)",
              [DocText(ed) isEqualToString:@"keep\n"]);
        // The same letters on both lines: a rectangle is made by pixels, and a proportional font
        // (no Consolas on the Mac) would make "ab" and "ef" differ in width.
        SetDoc(ed, @"ab cd\nab gh\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:8];
        [ed convertCase:NppCaseUpper];
        Check(@"IDM_EDIT_UPPERCASE", @"a rectangular selection converts only the rectangle",
              [DocText(ed) isEqualToString:@"AB cd\nAB gh\n"]);
        [sci message:SCI_SETEMPTYSELECTION wParam:0];
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

        long edgeMode = [sci message:SCI_GETEDGEMODE], edgeColumn = [sci message:SCI_GETEDGECOLUMN];
        [sci message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0];
        SetDoc(ed, @"one two three\n");
        [sci message:SCI_SETEDGECOLUMN wParam:7 lParam:0];
        [ed splitLines];
        Check(@"IDM_EDIT_SPLIT_LINES", @"breaks a long line at the edge column",
              [[DocText(ed) componentsSeparatedByString:@"\n"] count] > 2);
        // IDM_EDIT_SPLIT_LINES with a caret splits the caret's line only (getSelectionLinesRange).
        SetDoc(ed, @"one two three\nfour five six\n");
        [sci message:SCI_GOTOPOS wParam:[sci message:SCI_POSITIONFROMLINE wParam:1] lParam:0];
        [ed splitLines];
        Check(@"IDM_EDIT_SPLIT_LINES", @"with a caret only the caret's line is split",
              [DocText(ed) hasPrefix:@"one two three\nfour "] && ![DocText(ed) hasSuffix:@"four five six\n"]);
        [sci message:SCI_SETEDGECOLUMN wParam:(uptr_t)edgeColumn lParam:0];
        [sci message:SCI_SETEDGEMODE wParam:(uptr_t)edgeMode lParam:0];

        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed joinLines];
        Check(@"IDM_EDIT_JOIN_LINES", @"joins with single spaces",
              [DocText(ed) hasPrefix:@"a b c"]);
        // NppCommands.cpp IDM_EDIT_JOIN_LINES: nothing when the range is one line.
        SetDoc(ed, @"a\nb\nc\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        [ed joinLines];
        Check(@"IDM_EDIT_JOIN_LINES", @"with only a caret nothing is joined",
              [DocText(ed) isEqualToString:@"a\nb\nc\n"]);
        // SCI_LINESJOIN adds no second space after a line that ends in one.
        SetDoc(ed, @"a \nb\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed joinLines];
        Check(@"IDM_EDIT_JOIN_LINES", @"a line ending in a space is joined without another",
              [DocText(ed) isEqualToString:@"a b\n"]);

        // Line and case transforms change only the lines they change (upstream
        // goes through the target): bookmarks and folds elsewhere stay, and
        // one undo gives the text back.
        {
            NSMutableString *big = [NSMutableString string];
            for (int i = 0; i < 600; ++i) {
                if (i == 200) [big appendString:@"int f() {\n"];
                else if (i == 205) [big appendString:@"}\n"];
                // (Editing inside a folded block shows it: Scintilla's SC_AUTOMATICFOLD_SHOW.)
                else if (i > 200 && i < 205) [big appendFormat:@"    return %d;\n", i];
                else [big appendFormat:@"line %d word  \n", i];
            }
            [ed setLanguageNamed:@"cpp"];
            SetDoc(ed, big);
            [sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL (^marked)(long) = ^BOOL(long ln) {
                return ([sci message:SCI_MARKERGET wParam:(uptr_t)ln] & (1 << 1)) != 0;
            };
            [sci message:SCI_MARKERADD wParam:100 lParam:1];
            [sci message:SCI_MARKERADD wParam:500 lParam:1];
            [sci message:SCI_FOLDLINE wParam:200 lParam:SC_FOLDACTION_CONTRACT];
            BOOL (^kept)(void) = ^BOOL {
                return marked(100) && marked(500) && [sci message:SCI_GETFOLDEXPANDED wParam:200] == 0;
            };
            long wordAt = [sci message:SCI_POSITIONFROMLINE wParam:300] + 9;
            [sci message:SCI_SETSEL wParam:(uptr_t)wordAt lParam:wordAt + 4];
            [ed convertCase:NppCaseUpper];
            Check(@"IDM_EDIT_UPPERCASE", @"upper-casing one word keeps the bookmarks and folds of other lines",
                  kept() && [DocText(ed) containsString:@"line 300 WORD"]);
            [sci message:SCI_SETSEL wParam:(uptr_t)[sci message:SCI_POSITIONFROMLINE wParam:10]
                  lParam:[sci message:SCI_POSITIONFROMLINE wParam:20]];
            [ed sortLines:NppSortLexicographic descending:YES];
            Check(@"IDM_EDIT_SORTLINES_LEXICOGRAPHIC_DESCENDING", @"sorting some lines keeps bookmarks and folds elsewhere",
                  kept() && [DocText(ed) containsString:@"line 19 word  \nline 18"]);
            [sci message:SCI_SETEMPTYSELECTION wParam:0];
            [ed applyTrim:NppTrimTrailing];
            Check(@"IDM_EDIT_TRIMTRAILING", @"trimming every line keeps the bookmarked lines' marks and the fold",
                  kept() && ![DocText(ed) containsString:@"word  \n"]);
            [sci message:SCI_UNDO];
            Check(@"IDM_EDIT_TRIMTRAILING", @"one undo gives the trimmed spaces back",
                  [DocText(ed) containsString:@"line 400 word  \n"]);
            [sci message:SCI_INSERTTEXT wParam:[sci message:SCI_POSITIONFROMLINE wParam:300] lParam:(sptr_t)"line 1 word  \n"];
            [sci message:SCI_SETEMPTYSELECTION wParam:0];
            [ed removeDuplicateLines:NO];
            Check(@"IDM_EDIT_REMOVE_ANY_DUP_LINES", @"removing a duplicate keeps the marks of the lines that stay",
                  kept() && [sci message:SCI_GETLINECOUNT] == 601);
            [sci message:SCI_MARKERDELETEALL wParam:1];
            [sci message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND];
            [ed setLanguageNamed:@"normal"];
        }

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
            // wsTabConvert: the spaces reaching the stop after "a" become a tab, the one past
            // it stays, so "b" keeps its column (9).
            {NppSpaceToTabAll,      @"    a    b\n",  @"\ta\t b\n",  @"IDM_EDIT_SW2TAB_ALL"},
            {NppTabToSpace,         @"ab\t\tc\n",     @"ab      c\n", @"IDM_EDIT_TAB2SW"},   // to the next stop, not 4 each
            {NppSpaceToTabLeading,  @"    a    b\n",  @"\ta    b\n",  @"IDM_EDIT_SW2TAB_LEADING"},
        };
        for (size_t i = 0; i < sizeof(trims)/sizeof(trims[0]); ++i) {
            SetDoc(ed, trims[i].in);
            [ed applyTrim:trims[i].mode];
            Check(trims[i].cmd, @"transforms whitespace as expected",
                  [DocText(ed) isEqualToString:trims[i].want]);
        }

        SetDoc(ed, @"\ta\n\tb\n");
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:4];
        [ed applyTrim:NppTabToSpace];
        Check(@"IDM_EDIT_TAB2SW", @"a rectangular selection is left alone (block selection is not supported)",
              [DocText(ed) isEqualToString:@"\ta\n\tb\n"]);
        [sci message:SCI_SETEMPTYSELECTION wParam:0];

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

        // A multi-line selection keeps its lines selected, so Decrease twice goes back (EDIT-026).
        indentPrefs.useSpaces = NO; indentPrefs.tabWidth = 4; [ed applyDocumentSettings];
        SetDoc(ed, @"a\n  b\nc\n");
        [sci message:SCI_SETSEL wParam:0 lParam:5];
        [ed changeIndent:YES]; [ed changeIndent:NO]; [ed changeIndent:NO];
        BOOL multiBack = [DocText(ed) isEqualToString:@"a\nb\nc\n"];
        indentPrefs.useSpaces = spacesWas; indentPrefs.tabWidth = widthWas; [ed applyDocumentSettings];
        Check(@"IDM_EDIT_RMV_TAB", @"a multi-line selection stays selected: indent then unindent twice restores it", multiBack);

        // Skip Current & Go to Next moves on (EDIT-092).
        SetDoc(ed, @"foo foo foo");
        [sci message:SCI_SETSEL wParam:0 lParam:3];
        [sci message:SCI_ADDSELECTION wParam:7 lParam:4];
        [ed skipCurrentMultiSelection];
        long skN = [sci message:SCI_GETSELECTIONS];
        long s0 = [sci message:SCI_GETSELECTIONNSTART wParam:0], s1 = [sci message:SCI_GETSELECTIONNSTART wParam:skN - 1];
        Check(@"IDM_EDIT_MULTISELECTSSKIP", @"the current occurrence is dropped and the next one taken",
              skN == 2 && s0 == 0 && s1 == 8);

        SetDoc(ed, @"delete me\n");
        [sci message:SCI_SETSEL wParam:0 lParam:7];
        [ed deleteSelection];
        Check(@"IDM_EDIT_DELETE", @"removes the selection",
              ![DocText(ed) hasPrefix:@"delete"]);

        [ed setLanguageNamed:@"cpp"];
        SetDoc(ed, @"// x\n// y\n");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_UNCOMMENT", @"strips the line comment token",
              [DocText(ed) isEqualToString:@"x\ny\n"]);
        // doBlockComment(cm_uncomment) with a caret: that line only.
        SetDoc(ed, @"// x\n// y\n");
        [sci message:SCI_GOTOPOS wParam:1 lParam:0];
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_UNCOMMENT", @"with a caret only the caret's line is uncommented",
              [DocText(ed) isEqualToString:@"x\n// y\n"]);
        // undoStreamComment looks around the caret.
        SetDoc(ed, @"a /* body */ b\n/* other */\n");
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];
        [ed streamComment:NO];
        Check(@"IDM_EDIT_STREAM_UNCOMMENT", @"a caret inside a stream comment takes that comment off",
              [DocText(ed) isEqualToString:@"a body b\n/* other */\n"]);
        // A line with no line comment falls back to the stream comment (doBlockComment).
        SetDoc(ed, @"/* z */\n");
        [sci message:SCI_GOTOPOS wParam:3 lParam:0];
        [ed uncommentLines];
        Check(@"IDM_EDIT_BLOCK_UNCOMMENT", @"no line comment on the line: the stream comment around the caret comes off",
              [DocText(ed) isEqualToString:@"z\n"]);

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
        [ed newDocument];
        NSString *untitledName = ed.currentDocument.displayName;
        [app performMenuCommandAtPath:@"Edit|Copy to Clipboard|Copy Current Full File path"];
        BOOL fullIsName = [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:untitledName];
        BOOL listed = [[[ed allDocumentPaths] componentsSeparatedByString:@"\n"] containsObject:untitledName];
        Check(@"IDM_EDIT_FULLPATHTOCLIP", @"an untitled document's full path is its name, and Copy All File Paths lists it",
              fullIsName && listed);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];

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
        {
            const char withNul[] = {'a', 0, 'b'};
            [sci message:SCI_CLEARALL];
            [sci message:SCI_ADDTEXT wParam:3 lParam:(sptr_t)withNul];
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            Check(@"IDM_EDIT_COPY_BINARY", @"a selection holding a NUL byte is copied too", [[ed hexOfSelection] isEqualToString:@"61 00 62"]);
        }
        SetDoc(ed, @"é👍 ok");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[@"é👍" lengthOfBytesUsingEncoding:NSUTF8StringEncoding]];
        [ed redactSelectionWithBlock:YES];
        Check(@"IDM_EDIT_REDACT_SELECTION", @"one block per character, as SCI_COUNTCHARACTERS counts (👍 is one)",
              [DocText(ed) isEqualToString:@"██ ok"]);
        SetDoc(ed, @"keep me\n");
        [sci message:SCI_SETREADONLY wParam:1 lParam:0];
        [sci message:SCI_SELECTALL];
        [app performMenuCommandAtPath:@"Edit|Convert Case to|UPPERCASE"];
        [ed convertEOLTo:SC_EOL_CRLF];
        Check(@"IDM_EDIT_TOGGLEREADONLY", @"a read-only document is not changed by Convert Case or an EOL conversion",
              [DocText(ed) isEqualToString:@"keep me\n"] && [sci message:SCI_GETEOLMODE] != SC_EOL_CRLF);
        NSMenuItem *roItem = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *it in top.submenu.itemArray)
                for (NSMenuItem *sub in it.submenu.itemArray)
                    if (sub.action == @selector(toggleReadOnly:)) roItem = sub;
        [(id<NSMenuItemValidation>)app validateMenuItem:roItem];
        BOOL shownOn = roItem.state == NSControlStateValueOn;
        [sci message:SCI_SETREADONLY wParam:0 lParam:0];
        [(id<NSMenuItemValidation>)app validateMenuItem:roItem];
        Check(@"IDM_EDIT_TOGGLEREADONLY", @"Read-Only on Current Document is checked while the document is read-only",
              roItem && shownOn && roItem.state == NSControlStateValueOff);

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
}

/// == Selected numbers ==
void NppTestsSelectedNumbers(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
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
}
