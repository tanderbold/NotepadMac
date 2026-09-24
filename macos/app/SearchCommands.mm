#import "SearchCommands.h"
#import "FindCommands.h"
#import "SettingsCommands.h"
#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

#define NPPMAC_BOOKMARK_MARKER 1

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *SliceBytes(NSData *data, long start, long end) {
    if (start < 0) start = 0;
    if (end > (long)data.length) end = (long)data.length;
    if (end <= start) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

@implementation EditorController (SearchCommands)

#pragma mark - Indicator plumbing

/// style 0..4 -> indicators 8..12; NPPMAC_STYLE_COUNT -> the Find Mark indicator.
static int IndicatorFor(NSInteger style) {
    if (style == NPPMAC_SMART_STYLE) return NPPMAC_SMART_INDICATOR;
    if (style >= NPPMAC_STYLE_COUNT) return NPPMAC_FIND_MARK_INDICATOR;
    if (style < 0) style = 0;
    return NPPMAC_STYLE_FIRST_INDICATOR + (int)style;
}

- (void)ensureIndicatorConfigured:(int)indicator {
    ScintillaView *sci = self.sci;
    static const long colours[] = {
        0x00FFFF,   // yellow-ish (BGR)
        0x7FFF00,   // green
        0xFF7F7F,   // blue
        0xFF7FFF,   // magenta
        0x7FFFFF,   // orange
        0x00A5FF,   // find mark
    };
    // Smart highlighting keeps the look it had on mark style 5's indicator.
    int slot = indicator == NPPMAC_SMART_INDICATOR ? 4 : indicator - NPPMAC_STYLE_FIRST_INDICATOR;
    if (slot < 0 || slot > NPPMAC_STYLE_COUNT) slot = NPPMAC_STYLE_COUNT;
    [sci message:SCI_INDICSETSTYLE wParam:(uptr_t)indicator lParam:INDIC_ROUNDBOX];
    [sci message:SCI_INDICSETALPHA wParam:(uptr_t)indicator lParam:80];
    [sci message:SCI_INDICSETUNDER wParam:(uptr_t)indicator lParam:1];
    [sci message:SCI_INDICSETFORE wParam:(uptr_t)indicator lParam:colours[slot]];
}

- (NSString *)selectedText {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (a == b) {   // fall back to the word under the caret, as Notepad++ does
        long pos = [sci message:SCI_GETCURRENTPOS];
        a = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        b = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
    }
    if (b <= a) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, a, b);
}

/// Byte offsets of every occurrence of `term`.
- (NSArray<NSNumber *> *)occurrencesOf:(NSString *)term {
    // Plain matching, which is what the callers that do not offer the choice
    // have always used.
    return [self occurrencesOf:term matchCase:NO wholeWord:NO];
}

- (NSArray<NSNumber *> *)occurrencesOf:(NSString *)term
                             matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    if (!term.length) return out;
    const char *needle = term.UTF8String;
    long len = Utf8Len(term);
    long docLen = [sci message:SCI_GETLENGTH];
    long from = 0;
    while (from < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)docLen lParam:0];
        long flags = (matchCase ? SCFIND_MATCHCASE : 0) | (wholeWord ? SCFIND_WHOLEWORD : 0);
        [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags lParam:0];
        long hit = [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
        if (hit < 0) break;
        [out addObject:@(hit)];
        from = hit + MAX(1, len);
    }
    return out;
}

#pragma mark - Token styling

- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style {
    // Mark All has its own case and whole-word settings, as it does in
    // Notepad++; smart highlighting has separate ones and asks explicitly.
    NppPreferences *prefs = [NppPreferences shared];
    return [self markAllOccurrencesOfSelection:style
                                     matchCase:prefs.markAllCaseSensitive
                                     wholeWord:prefs.markAllWordOnly];
}

- (NSUInteger)markAllOccurrencesOfSelection:(NSInteger)style
                                  matchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    ScintillaView *sci = self.sci;
    NSString *term = [self selectedText];
    if (!term.length) { NppBeep(); return 0; }
    int ind = IndicatorFor(style);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    NSArray *hits = [self occurrencesOf:term matchCase:matchCase wholeWord:wholeWord];
    long len = Utf8Len(term);
    for (NSNumber *hit in hits) {
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)hit.longValue lParam:len];
    }
    return hits.count;
}

- (void)markOneOccurrenceOfSelection:(NSInteger)style {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) { NppBeep(); return; }
    int ind = IndicatorFor(style);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)a lParam:b - a];
}

- (void)clearStyle:(NSInteger)style {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(style);
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
}

- (void)clearAllStyles {
    for (NSInteger i = 0; i <= NPPMAC_STYLE_COUNT; ++i) [self clearStyle:i];
}

/// Ranges carrying the indicator, as {start, length} pairs.
- (NSArray<NSValue *> *)rangesOfStyle:(NSInteger)style {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(style);
    long docLen = [sci message:SCI_GETLENGTH];
    NSMutableArray *out = [NSMutableArray array];
    long pos = 0;
    while (pos < docLen) {
        if ([sci message:SCI_INDICATORVALUEAT wParam:(uptr_t)ind lParam:pos]) {
            long end = [sci message:SCI_INDICATOREND wParam:(uptr_t)ind lParam:pos];
            if (end <= pos) break;
            [out addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)pos, (NSUInteger)(end - pos))]];
            pos = end;
        } else {
            long next = [sci message:SCI_INDICATOREND wParam:(uptr_t)ind lParam:pos];
            pos = (next > pos) ? next : pos + 1;
        }
    }
    return out;
}

- (BOOL)jumpToMarker:(NSInteger)style forward:(BOOL)forward {
    ScintillaView *sci = self.sci;
    NSArray *ranges = [self rangesOfStyle:style];
    if (!ranges.count) { NppBeep(); return NO; }
    // Measure from the far edge of the current selection, otherwise jumping back
    // from a selected marker lands on that same marker.
    long caret = forward ? [sci message:SCI_GETSELECTIONEND]
                         : [sci message:SCI_GETSELECTIONSTART];

    NSRange chosen = forward ? [ranges.firstObject rangeValue] : [ranges.lastObject rangeValue];
    if (forward) {
        for (NSValue *v in ranges) {
            if ((long)v.rangeValue.location > caret) { chosen = v.rangeValue; break; }
        }
    } else {
        for (NSValue *v in ranges.reverseObjectEnumerator) {
            if ((long)v.rangeValue.location < caret) { chosen = v.rangeValue; break; }
        }
    }
    [sci message:SCI_SETSEL wParam:(uptr_t)chosen.location
             lParam:(sptr_t)(chosen.location + chosen.length)];
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (NSString *)textOfStyle:(NSInteger)style {
    NSData *data = [([self.sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableArray *out = [NSMutableArray array];
    for (NSValue *v in [self rangesOfStyle:style]) {
        NSRange r = v.rangeValue;
        [out addObject:SliceBytes(data, (long)r.location, (long)(r.location + r.length))];
    }
    return [out componentsJoinedByString:@"\n"];
}

- (NSString *)textOfAllStyles {
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger i = 0; i < NPPMAC_STYLE_COUNT; ++i) {
        NSString *t = [self textOfStyle:i];
        if (t.length) [out addObject:t];
    }
    return [out componentsJoinedByString:@"\n"];
}

#pragma mark - Bookmarked lines

- (NSArray<NSNumber *> *)bookmarkedLines {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if ([sci message:SCI_MARKERGET wParam:(uptr_t)line] & (1 << NPPMAC_BOOKMARK_MARKER)) {
            [out addObject:@(line)];
        }
    }
    return out;
}

- (NSString *)lineText:(long)line {
    ScintillaView *sci = self.sci;
    long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, start, end);
}

- (NSString *)bookmarkedLinesText {
    // Each line with its own ending, as Windows copies them.
    ScintillaView *sci = self.sci;
    NSMutableString *out = [NSMutableString string];
    NSData *data = [[self documentText] dataUsingEncoding:NSUTF8StringEncoding];
    for (NSNumber *n in [self bookmarkedLines]) {
        long line = n.longValue;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long end = start + [sci message:SCI_LINELENGTH wParam:(uptr_t)line];
        [out appendString:SliceBytes(data, start, end)];
    }
    return out;
}

- (void)copyBookmarkedLines {
    [self copyToClipboard:[self bookmarkedLinesText]];
}

- (void)cutBookmarkedLines {
    [self copyBookmarkedLines];
    [self removeBookmarkedLines];
}

- (void)deleteLines:(NSArray<NSNumber *> *)lines {
    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    // Bottom-up so earlier line numbers stay valid.
    for (NSNumber *n in lines.reverseObjectEnumerator) {
        long line = n.longValue;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long next = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(line + 1)];
        if (next <= start) next = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
        [sci message:SCI_DELETERANGE wParam:(uptr_t)start lParam:next - start];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)removeBookmarkedLines { [self deleteLines:[self bookmarkedLines]]; }

- (void)removeUnbookmarkedLines {
    NSSet *marked = [NSSet setWithArray:[self bookmarkedLines]];
    NSMutableArray *others = [NSMutableArray array];
    long total = [self.sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if (![marked containsObject:@(line)]) [others addObject:@(line)];
    }
    [self deleteLines:others];
}

- (void)pasteOverBookmarkedLines {
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
    NSArray *lines = [self bookmarkedLines];
    if (!lines.count) { NppBeep(); return; }

    // Every marked line becomes the whole of the clipboard, as on Windows;
    // a clipboard of several lines goes into each marked line whole.
    ScintillaView *sci = self.sci;
    NSString *text = clip;
    while ([text hasSuffix:@"\n"] || [text hasSuffix:@"\r"]) text = [text substringToIndex:text.length - 1];
    [sci message:SCI_BEGINUNDOACTION];
    for (NSNumber *n in lines.reverseObjectEnumerator) {
        long line = n.longValue;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)start lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)end lParam:0];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(text) value:text];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
}

- (void)inverseBookmarks {
    ScintillaView *sci = self.sci;
    NSSet *marked = [NSSet setWithArray:[self bookmarkedLines]];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        if ([marked containsObject:@(line)]) {
            [sci message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
        } else {
            [sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
        }
    }
}

#pragma mark - Braces

- (BOOL)goToMatchingBrace {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    if (match < 0 && pos > 0) {
        pos -= 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    }
    if (match < 0) { NppBeep(); return NO; }
    [sci message:SCI_GOTOPOS wParam:(uptr_t)match lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)selectBetweenMatchingBraces {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    if (match < 0 && pos > 0) {
        pos -= 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)pos lParam:0];
    }
    if (match < 0) { NppBeep(); return NO; }
    // Both braces are part of it, as on Windows.
    long from = MIN(pos, match), to = MAX(pos, match) + 1;
    [sci message:SCI_SETSEL wParam:(uptr_t)from lParam:to];
    [self refreshChrome];
    return YES;
}

#pragma mark - Find in Files

- (NSUInteger)findInFiles:(NSString *)term inFolder:(NSString *)folder filter:(NSString *)filter {
    if (!term.length || !folder.length) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *walker = [fm enumeratorAtPath:folder];
    NSMutableString *report = [NSMutableString stringWithFormat:
        @"Search \"%@\" in %@\n\n", term, folder];
    NSUInteger hits = 0, files = 0;

    for (NSString *rel in walker) {
        NSString *full = [folder stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
        if (filter.length && ![rel.pathExtension.lowercaseString
                               isEqualToString:filter.lowercaseString]) continue;

        NSString *content = [NSString stringWithContentsOfFile:full encoding:NSUTF8StringEncoding error:NULL];
        if (!content) continue;                       // binary or another encoding

        NSArray *lines = [EditorController linesOfText:content];
        NSMutableString *fileBlock = [NSMutableString string];
        NSUInteger fileHits = 0;
        for (NSUInteger i = 0; i < lines.count; ++i) {
            if ([lines[i] rangeOfString:term].location == NSNotFound) continue;
            fileHits++;
            [fileBlock appendFormat:@"\tLine %lu: %@\n", (unsigned long)(i + 1),
                                    [EditorController singleReportLine:lines[i]]];
        }
        if (fileHits) {
            files++;
            hits += fileHits;
            [report appendFormat:@"%@ (%lu hit%@)\n%@\n", full, (unsigned long)fileHits,
                                 fileHits == 1 ? @"" : @"s", fileBlock];
        }
    }
    [report appendFormat:@"\n%lu hit%@ in %lu file%@\n", (unsigned long)hits, hits == 1 ? @"" : @"s",
                         (unsigned long)files, files == 1 ? @"" : @"s"];

    [self showSearchResults:report];
    return hits;
}

static const char kOlderResultsKey = 0;

/// What the results tab held before the search now running: Notepad++ keeps
/// earlier searches below the new one, folded, unless it is told to purge.
- (NSString *)olderSearchResults { return objc_getAssociatedObject(self, &kOlderResultsKey) ?: @""; }

- (void)showSearchResults:(NSString *)report {
    // Notepad++ docks a results panel; here the results are a tab of their own.
    // An earlier one is reused, so a search that reports as it goes does not
    // leave a trail of tabs behind it.
    NSInteger existing = [self searchResultsTabIndex];
    NSString *older = @"";
    if (existing >= 0) {
        [self selectDocumentAtIndex:existing];
        if (![NppPreferences shared].searchResultsPurge) older = [self.sci string] ?: @"";
    } else {
        [self newDocument];
    }
    objc_setAssociatedObject(self, &kOlderResultsKey, older, OBJC_ASSOCIATION_COPY);
    self.currentDocument.displayName = @"Search results";
    self.currentDocument.isSearchResults = YES;
    [self.sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.sci setString:[(report ?: @"") stringByAppendingString:older]];
    [self.sci message:SCI_SETREADONLY wParam:1 lParam:0];   // results are read, not edited, as the Finder is
    [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    [self foldSearchResults];
    [self refreshChrome];
}

- (void)updateSearchResults:(NSString *)report {
    // While the user is looking at something else, leaving their document alone
    // matters more than a live count; the finished report still arrives.
    if (!self.currentDocument.isSearchResults) return;

    // Whether the view was at the top decides whether it stays with the new
    // search as it grows or stays where the user scrolled to.
    sptr_t first = [self.sci message:SCI_GETFIRSTVISIBLELINE wParam:0 lParam:0];
    sptr_t lines = [self.sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
    sptr_t onScreen = [self.sci message:SCI_LINESONSCREEN wParam:0 lParam:0];
    BOOL atBottom = (first + onScreen) >= lines - 1;
    NSString *older = [self olderSearchResults];

    [self.sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.sci setString:[(report ?: @"") stringByAppendingString:older]];
    [self.sci message:SCI_SETREADONLY wParam:1 lParam:0];   // results are read, not edited, as the Finder is
    [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    [self foldSearchResults];
    if (atBottom && !older.length) {
        [self.sci message:SCI_GOTOPOS
                  wParam:(uptr_t)[self.sci message:SCI_GETLENGTH wParam:0 lParam:0] lParam:0];
    } else {
        [self.sci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)first lParam:0];
    }
}

/// The fold structure of the results, as Notepad++'s searchResult lexer
/// gives it: a search, then each file it found something in, then the hits.
/// Every search but the newest is folded away.
- (void)foldSearchResults {
    ScintillaView *sci = self.sci;
    long count = [sci message:SCI_GETLINECOUNT];
    NSArray<NSString *> *lines = [([sci string] ?: @"") componentsSeparatedByString:@"\n"];
    BOOL firstSearch = YES;
    for (long i = 0; i < count && i < (long)lines.count; ++i) {
        NSString *line = lines[(NSUInteger)i];
        int level;
        if ([line hasPrefix:@"Search \""]) level = SC_FOLDLEVELBASE | SC_FOLDLEVELHEADERFLAG;
        else if (![line hasPrefix:@"\t"] && ([line hasSuffix:@" hit)"] || [line hasSuffix:@" hits)"]))
            level = (SC_FOLDLEVELBASE + 1) | SC_FOLDLEVELHEADERFLAG;
        else level = SC_FOLDLEVELBASE + 2;
        [sci message:SCI_SETFOLDLEVEL wParam:(uptr_t)i lParam:level];
    }
    for (long i = 0; i < count && i < (long)lines.count; ++i) {
        if (![lines[(NSUInteger)i] hasPrefix:@"Search \""]) continue;
        [sci message:SCI_FOLDLINE wParam:(uptr_t)i lParam:firstSearch ? SC_FOLDACTION_EXPAND : SC_FOLDACTION_CONTRACT];
        firstSearch = NO;
    }
}

- (BOOL)showingSearchResults {
    return self.currentDocument.isSearchResults;
}

#pragma mark - The results tab's own commands

- (void)foldAllSearchResults:(BOOL)fold {
    if (![self showingSearchResults]) return;
    [self.sci message:SCI_FOLDALL wParam:fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND lParam:0];
}

/// The lines the selection touches.
- (NSArray<NSString *> *)selectedSearchResultLines {
    ScintillaView *sci = self.sci;
    long from = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONSTART]];
    long to = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONEND]];
    NSArray<NSString *> *lines = [([sci string] ?: @"") componentsSeparatedByString:@"\n"];
    NSMutableArray *out = [NSMutableArray array];
    for (long i = from; i <= to && i < (long)lines.count; ++i) [out addObject:lines[(NSUInteger)i]];
    return out;
}

/// Copy Selected Line(s): the text of the hits, without "Line n:".
- (NSString *)selectedSearchResultText {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [self selectedSearchResultLines]) {
        if (![line hasPrefix:@"\t"]) continue;
        NSRange colon = [line rangeOfString:@": "];
        if ([EditorController searchResultLineInHitLine:line] && colon.location != NSNotFound) {
            [out addObject:[line substringFromIndex:NSMaxRange(colon)]];
        }
    }
    return [out componentsJoinedByString:@"\n"];
}

/// Copy Selected Pathname(s): the files the selected lines belong to, once each.
- (NSArray<NSString *> *)selectedSearchResultPaths {
    ScintillaView *sci = self.sci;
    NSString *report = [sci string] ?: @"";
    long from = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONSTART]];
    long to = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETSELECTIONEND]];
    NSMutableOrderedSet *paths = [NSMutableOrderedSet orderedSet];
    for (long i = from; i <= to; ++i) {
        NSString *path = [EditorController searchResultTargetInReport:report atLine:i fileLine:NULL];
        if (path.length) [paths addObject:path];
    }
    return paths.array;
}

- (void)copySearchResultLines {
    NSString *text = [self selectedSearchResultText];
    if (!text.length) { NppBeep(); return; }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
}

- (void)copySearchResultPaths {
    NSArray *paths = [self selectedSearchResultPaths];
    if (!paths.count) { NppBeep(); return; }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:[paths componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

- (void)openSearchResultPaths {
    for (NSString *path in [self selectedSearchResultPaths]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [self openFileAtPath:path error:NULL];
    }
}

- (void)clearSearchResults {
    if (![self showingSearchResults]) return;
    objc_setAssociatedObject(self, &kOlderResultsKey, @"", OBJC_ASSOCIATION_COPY);
    [self.sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.sci setString:@""];
    [self.sci message:SCI_SETREADONLY wParam:1 lParam:0];   // results are read, not edited, as the Finder is
    [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
}

/// Removes the search the caret is in, with all its hits.
- (void)deleteSearchResultAtCaret {
    if (![self showingSearchResults]) return;
    ScintillaView *sci = self.sci;
    NSArray<NSString *> *lines = [([sci string] ?: @"") componentsSeparatedByString:@"\n"];
    long caretLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long start = caretLine;
    while (start >= 0 && ![lines[(NSUInteger)start] hasPrefix:@"Search \""]) start--;
    if (start < 0) { NppBeep(); return; }
    long end = caretLine + 1;
    while (end < (long)lines.count && ![lines[(NSUInteger)end] hasPrefix:@"Search \""]) end++;
    long from = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)start];
    long to = end < (long)lines.count ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)end] : [sci message:SCI_GETLENGTH];
    [sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [sci message:SCI_DELETERANGE wParam:(uptr_t)from lParam:to - from];
    [sci message:SCI_SETREADONLY wParam:1 lParam:0];   // results are read, not edited, as the Finder is
    [sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    objc_setAssociatedObject(self, &kOlderResultsKey, [sci string] ?: @"", OBJC_ASSOCIATION_COPY);
    [self foldSearchResults];
}

+ (NSString *)searchResultTargetInHeading:(NSString *)head {
    // A folder search heads each file with "<path> (3 hits)".
    NSRange count = [head rangeOfString:@" (" options:NSBackwardsSearch];
    if (count.location != NSNotFound && [head hasSuffix:@")"]) {
        return [head substringToIndex:count.location];
    }

    // A search of the open document has no such heading; all it writes is
    // 'Search "what" in <document>' at the top, and the hits below it.
    if ([head hasPrefix:@"Search \""]) {
        NSRange marker = [head rangeOfString:@"\" in " options:NSBackwardsSearch];
        if (marker.location != NSNotFound) return [head substringFromIndex:NSMaxRange(marker)];
    }
    return nil;
}

/// The line number a hit line carries, or 0 when the line is not a hit.
+ (NSInteger)searchResultLineInHitLine:(NSString *)text {
    if (![text hasPrefix:@"\t"]) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    scanner.charactersToBeSkipped = [NSCharacterSet whitespaceCharacterSet];
    NSInteger wanted = 0;
    if (![scanner scanString:@"Line" intoString:NULL]) return 0;
    if (![scanner scanInteger:&wanted]) return 0;
    return wanted;
}

+ (NSString *)searchResultTargetInReport:(NSString *)report
                                  atLine:(NSInteger)line
                                fileLine:(NSInteger *)fileLine {
    if (fileLine) *fileLine = 1;
    NSArray<NSString *> *lines = [(report ?: @"") componentsSeparatedByString:@"\n"];
    if (line < 0 || line >= (NSInteger)lines.count) return nil;

    // A hit reads "\tLine 42: ...", and what it belongs to is the nearest
    // heading above it.
    NSInteger heading = line;
    NSInteger wanted = 0;
    if ([lines[(NSUInteger)line] hasPrefix:@"\t"]) {
        NSScanner *scanner = [NSScanner scannerWithString:lines[(NSUInteger)line]];
        scanner.charactersToBeSkipped = [NSCharacterSet whitespaceCharacterSet];
        if (![scanner scanString:@"Line" intoString:NULL]) return nil;
        if (![scanner scanInteger:&wanted]) return nil;
        while (heading >= 0 &&
               ([lines[(NSUInteger)heading] hasPrefix:@"\t"] || !lines[(NSUInteger)heading].length)) {
            heading--;
        }
        if (heading < 0) return nil;
    }

    NSString *target = [self searchResultTargetInHeading:lines[(NSUInteger)heading]];
    if (!target.length) return nil;

    if (fileLine) *fileLine = wanted > 0 ? wanted : 1;
    return target;
}

+ (NSString *)searchResultFileInReport:(NSString *)report
                                atLine:(NSInteger)line
                              fileLine:(NSInteger *)fileLine {
    NSString *target = [self searchResultTargetInReport:report atLine:line fileLine:fileLine];
    BOOL directory = NO;
    // The folder a search started in also ends in brackets; it is not a result.
    if (!target || ![[NSFileManager defaultManager] fileExistsAtPath:target isDirectory:&directory]
        || directory) {
        if (fileLine) *fileLine = 1;
        return nil;
    }
    return target;
}

/// The text of one line of the document, as Scintilla counts lines. Splitting
/// the whole text on "\n" instead would put the lines out of step with the
/// caret whenever a carriage return sits inside one.
- (NSString *)textOfLine:(NSInteger)line {
    if (line < 0) return @"";
    sptr_t start = [self.sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
    sptr_t end = [self.sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
    if (end <= start) return @"";
    NSData *bytes = [([self.sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)end > bytes.length) return @"";
    NSString *text = [[NSString alloc] initWithData:
        [bytes subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]
                                           encoding:NSUTF8StringEncoding];
    return text ?: @"";
}

- (BOOL)openSearchResultAtCaret {
    if (!self.currentDocument.isSearchResults) return NO;

    sptr_t position = [self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];
    NSInteger line = (NSInteger)[self.sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)position lParam:0];

    NSInteger target = [EditorController searchResultLineInHitLine:[self textOfLine:line]];
    NSInteger heading = line;
    if (target > 0) {
        // Up to the file this hit belongs to, past the blank lines between
        // one file's hits and the next.
        NSString *above = nil;
        while (heading >= 0) {
            above = [self textOfLine:heading];
            if (![above hasPrefix:@"\t"] && above.length) break;
            heading--;
        }
        if (heading < 0) return NO;
    } else {
        target = 1;
    }

    NSString *where = [EditorController searchResultTargetInHeading:[self textOfLine:heading]];
    if (!where.length) return NO;

    BOOL directory = NO;
    BOOL onDisk = [[NSFileManager defaultManager] fileExistsAtPath:where isDirectory:&directory]
                  && !directory;
    if (onDisk) {
        if (![self openFileAtPath:where error:NULL]) return NO;
    } else {
        // A search of the open document names it by the title on its tab, which
        // is all an unsaved one has.
        NSInteger found = -1;
        for (NSUInteger i = 0; i < self.documents.count; ++i) {
            if ([self.documents[i].displayName isEqualToString:where]) { found = (NSInteger)i; break; }
        }
        if (found < 0) return NO;
        [self selectDocumentAtIndex:found];
    }

    [self selectLine:target - 1];
    return YES;
}

/// Puts the caret on a line and selects it, the way arriving from a search
/// result should leave the document: the line is visible, folded sections above
/// it are opened, and it is plain which line was meant.
- (void)selectLine:(NSInteger)line {
    ScintillaView *sci = self.sci;
    sptr_t last = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0] - 1;
    sptr_t wanted = MAX((sptr_t)0, MIN((sptr_t)line, last));
    [sci message:SCI_ENSUREVISIBLEENFORCEPOLICY wParam:(uptr_t)wanted lParam:0];
    [sci message:SCI_GOTOLINE wParam:(uptr_t)wanted lParam:0];
    sptr_t start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)wanted lParam:0];
    sptr_t end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)wanted lParam:0];
    if (end == start && wanted < last) {
        // An empty line has nothing to highlight; taking in its line break
        // leaves a mark, rather than looking as though nothing happened.
        end = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(wanted + 1) lParam:0];
    }
    [sci message:SCI_SETSEL wParam:(uptr_t)start lParam:(sptr_t)end];
    [sci message:SCI_SCROLLCARET wParam:0 lParam:0];
    [self refreshChrome];
}

- (NSInteger)searchResultsTabIndex {
    for (NSUInteger i = 0; i < self.documents.count; ++i) {
        if (self.documents[i].isSearchResults) return (NSInteger)i;
    }
    return -1;
}

- (BOOL)focusSearchResults {
    NSInteger idx = [self searchResultsTabIndex];
    if (idx < 0) { NppBeep(); return NO; }
    [self selectDocumentAtIndex:idx];
    return YES;
}

- (BOOL)goToSearchResult:(BOOL)forward {
    if (![self focusSearchResults]) return NO;
    ScintillaView *sci = self.sci;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long total = [sci message:SCI_GETLINECOUNT];

    for (long probe = line + (forward ? 1 : -1); probe >= 0 && probe < total;
         probe += (forward ? 1 : -1)) {
        if ([[self lineText:probe] hasPrefix:@"\tLine "]) {
            [sci message:SCI_GOTOLINE wParam:(uptr_t)probe lParam:0];
            [self refreshChrome];
            return YES;
        }
    }
    NppBeep();
    return NO;
}

#pragma mark - Select and find / volatile find

- (BOOL)findNextOccurrenceOfSelection:(BOOL)forward extendSelection:(BOOL)extend {
    ScintillaView *sci = self.sci;
    NSString *term = [self selectedText];
    if (!term.length) { NppBeep(); return NO; }

    NSArray *hits = [self occurrencesOf:term];
    if (!hits.count) { NppBeep(); return NO; }
    long caret = [sci message:SCI_GETSELECTIONSTART];
    long len = Utf8Len(term);

    long target = forward ? [hits.firstObject longValue] : [hits.lastObject longValue];
    if (forward) {
        for (NSNumber *h in hits) if (h.longValue > caret) { target = h.longValue; break; }
    } else {
        for (NSNumber *h in hits.reverseObjectEnumerator) if (h.longValue < caret) { target = h.longValue; break; }
    }

    if (extend) {
        [sci message:SCI_ADDSELECTION wParam:(uptr_t)target lParam:target + len];
    } else {
        [sci message:SCI_SETSEL wParam:(uptr_t)target lParam:target + len];
    }
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (NSUInteger)markCharactersInRangeFrom:(uint32_t)from to:(uint32_t)to {
    ScintillaView *sci = self.sci;
    int ind = IndicatorFor(NPPMAC_STYLE_COUNT);
    [self ensureIndicatorConfigured:ind];
    [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    NSString *text = [self documentText];
    NSUInteger marked = 0;
    long bytePos = 0;
    // Walked by code point: a character outside the BMP is two UTF-16 units
    // and four bytes, and counting it as two characters of no bytes put
    // every later mark four bytes early.
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        NSUInteger units = 1;
        uint32_t scalar = c;
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < text.length &&
            CFStringIsSurrogateLowCharacter([text characterAtIndex:i + 1])) {
            scalar = CFStringGetLongCharacterForSurrogatePair(c, [text characterAtIndex:i + 1]);
            units = 2;
        }
        long charBytes = Utf8Len([text substringWithRange:NSMakeRange(i, units)]);
        if (scalar >= from && scalar <= to) {
            [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)bytePos lParam:charBytes];
            marked++;
        }
        bytePos += charBytes;
        i += units - 1;
    }
    return marked;
}

#pragma mark - Change history

- (void)enableChangeHistory:(BOOL)on {
    [self.sci message:SCI_SETCHANGEHISTORY
               wParam:(uptr_t)(on ? (SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS) : SC_CHANGE_HISTORY_DISABLED)
               lParam:0];
}

// Notepad_plus::changedHistoryGoTo: saved changes count too, the block of
// changed lines the caret is in is stepped over, and the search wraps round.
- (BOOL)goToNextChange:(BOOL)forward {
    ScintillaView *sci = self.sci;
    long mask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                (1 << SC_MARKNUM_HISTORY_SAVED) |
                (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
    long current = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long total = [sci message:SCI_GETLINECOUNT];
    // Change-history markers are derived per line rather than stored in the
    // marker list, so they are read with MARKERGET line by line.
    BOOL (^changed)(long) = ^BOOL(long l) { return ([sci message:SCI_MARKERGET wParam:(uptr_t)l] & mask) != 0; };
    long (^previous)(long) = ^long(long from) {   // SCI_MARKERPREVIOUS
        for (long l = from; l >= 0; --l) if (changed(l)) return l;
        return -1;
    };
    long line = -1, block = current;
    if (forward) {
        // From the caret's own line: it may be unchanged with the next one changed.
        for (long l = current; l < total; ++l) {
            if (!changed(l)) continue;
            if (l != block) { line = l; break; }
            block++;   // still the caret's block
        }
        if (line == -1)   // wrap round
            for (long l = 0; l < current + 1 && l < total; ++l) if (changed(l)) { line = l; break; }
    } else {
        while (true) {
            line = previous(block);
            if (line == -1 || line != block) break;
            block--;
        }
        if (line == -1) line = previous(total - 1);   // wrap round
    }
    if (line == -1) { NppBeep(); return NO; }
    [sci message:SCI_ENSUREVISIBLEENFORCEPOLICY wParam:(uptr_t)line];
    [sci message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
    [self refreshChrome];
    return YES;
}

- (void)clearChangeHistory {
    // Toggling the feature off and on is how Scintilla discards the recorded history.
    [self enableChangeHistory:NO];
    [self enableChangeHistory:YES];
    [self refreshChrome];
}

@end
