#import "AdvancedEditCommands.h"
#import "SettingsCommands.h"
#import "ApiCatalog.h"
#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>
#include <vector>

static long Utf8Length(NSString *s) { return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding]; }

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

@implementation EditorController (AdvancedEditCommands)

#pragma mark - Shared

- (NSString *)currentSelectionOrWord {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (a == b) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        a = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        b = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
    }
    if (b <= a) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, a, b);
}

/// Byte offsets of every match of `term` under the given flags.
- (NSArray<NSNumber *> *)matchesOf:(NSString *)term flags:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    if (!term.length) return out;

    long sciFlags = 0;
    if (flags & NppMatchCase) sciFlags |= SCFIND_MATCHCASE;
    if (flags & NppMatchWholeWord) sciFlags |= SCFIND_WHOLEWORD;

    const char *needle = term.UTF8String;
    long len = Utf8Len(term);
    long docLen = [sci message:SCI_GETLENGTH];
    long from = 0;
    while (from < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)docLen lParam:0];
        [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)sciFlags lParam:0];
        long hit = [sci message:SCI_SEARCHINTARGET wParam:(uptr_t)len lParam:(sptr_t)needle];
        if (hit < 0) break;
        [out addObject:@(hit)];
        from = hit + MAX(1, len);
    }
    return out;
}

#pragma mark - Multi-selection

- (NSUInteger)selectionCount { return (NSUInteger)[self.sci message:SCI_GETSELECTIONS]; }

- (NSUInteger)multiSelectAllOccurrences:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSString *term = [self currentSelectionOrWord];
    NSArray *hits = [self matchesOf:term flags:flags];
    if (!hits.count) { NppBeep(); return 0; }

    long len = Utf8Len(term);
    [sci message:SCI_SETSELECTION wParam:(uptr_t)[hits.firstObject longValue]
             lParam:[hits.firstObject longValue] + len];
    for (NSUInteger i = 1; i < hits.count; ++i) {
        long at = [hits[i] longValue];
        [sci message:SCI_ADDSELECTION wParam:(uptr_t)(at + len) lParam:at];
    }
    [self refreshChrome];
    return hits.count;
}

- (BOOL)multiSelectNextOccurrence:(NppMatchFlags)flags {
    ScintillaView *sci = self.sci;
    NSString *term = [self currentSelectionOrWord];
    NSArray *hits = [self matchesOf:term flags:flags];
    if (hits.count < 2) { NppBeep(); return NO; }

    long len = Utf8Len(term);
    long last = [sci message:SCI_GETSELECTIONNCARET
                      wParam:(uptr_t)([sci message:SCI_GETSELECTIONS] - 1)];
    long target = -1;
    for (NSNumber *h in hits) {
        if (h.longValue + len > last) { target = h.longValue; break; }
    }
    if (target < 0) target = [hits.firstObject longValue];    // wrap around
    [sci message:SCI_ADDSELECTION wParam:(uptr_t)(target + len) lParam:target];
    [sci message:SCI_SCROLLCARET];
    [self refreshChrome];
    return YES;
}

- (BOOL)undoLastMultiSelection {
    ScintillaView *sci = self.sci;
    long n = [sci message:SCI_GETSELECTIONS];
    if (n < 2) { NppBeep(); return NO; }
    [sci message:SCI_DROPSELECTIONN wParam:(uptr_t)(n - 1) lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)skipCurrentMultiSelection {
    ScintillaView *sci = self.sci;
    long n = [sci message:SCI_GETSELECTIONS];
    if (n < 1) { NppBeep(); return NO; }
    // Drop the selection the caret is on, then take the one after it.
    long main = [sci message:SCI_GETMAINSELECTION];
    if (n > 1) [sci message:SCI_DROPSELECTIONN wParam:(uptr_t)main lParam:0];
    return [self multiSelectNextOccurrence:NppMatchNone];
}

#pragma mark - Begin/End select

static const char kBeginEndAnchorKey = 0;

- (BOOL)beginEndSelectActive {
    return objc_getAssociatedObject(self, &kBeginEndAnchorKey) != nil;
}

/// First call drops an anchor, second extends the selection to the caret --
/// Notepad++'s Begin/End Select, in normal or column mode.
- (BOOL)beginEndSelectColumnMode:(BOOL)columnMode {
    ScintillaView *sci = self.sci;
    NSNumber *anchor = objc_getAssociatedObject(self, &kBeginEndAnchorKey);
    long caret = [sci message:SCI_GETCURRENTPOS];

    if (!anchor) {
        objc_setAssociatedObject(self, &kBeginEndAnchorKey, @(caret), OBJC_ASSOCIATION_RETAIN);
        return NO;                       // anchor dropped, selection not made yet
    }
    objc_setAssociatedObject(self, &kBeginEndAnchorKey, nil, OBJC_ASSOCIATION_RETAIN);

    if (columnMode) {
        [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:(uptr_t)anchor.longValue lParam:0];
        [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:(uptr_t)caret lParam:0];
    } else {
        [sci message:SCI_SETSEL wParam:(uptr_t)anchor.longValue lParam:caret];
    }
    [self refreshChrome];
    return YES;
}

#pragma mark - Column editor

/// Inserts into each row of a rectangular selection, as the Column Editor does.
- (BOOL)columnApply:(NSString *(^)(NSUInteger row))textForRow {
    ScintillaView *sci = self.sci;
    long selections = [sci message:SCI_GETSELECTIONS];
    if (selections < 1) return NO;

    // Each row: what it covers, and how far past the end of a short line the
    // rectangle reaches (virtual space), which becomes real spaces.
    NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
    if (selections == 1 && ![sci message:SCI_SELECTIONISRECTANGLE] &&
        [sci message:SCI_GETSELECTIONSTART] == [sci message:SCI_GETSELECTIONEND]) {
        // No block: the column at the caret, from its line to the last, as
        // the Column Editor works on Windows.
        long caret = [sci message:SCI_GETCURRENTPOS];
        long column = [sci message:SCI_GETCOLUMN wParam:(uptr_t)caret];
        long first = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret];
        long lines = [sci message:SCI_GETLINECOUNT];
        for (long line = first; line < lines; ++line) {
            long at = [sci message:SCI_FINDCOLUMN wParam:(uptr_t)line lParam:column];
            // Padded only when the line ends short of the column; inside a
            // tab's span the text goes in at the tab, as Windows puts it.
            long lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
            long pad = at >= lineEnd ? MAX(0, column - [sci message:SCI_GETCOLUMN wParam:(uptr_t)at]) : 0;
            [rows addObject:@{@"start": @(at), @"end": @(at), @"pad": @(pad)}];
        }
        selections = 0;
    }
    for (long i = 0; i < selections; ++i) {
        long start = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i];
        long end = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
        long anchorSpace = [sci message:SCI_GETSELECTIONNANCHORVIRTUALSPACE wParam:(uptr_t)i];
        long caretSpace = [sci message:SCI_GETSELECTIONNCARETVIRTUALSPACE wParam:(uptr_t)i];
        long pad = start == end ? MIN(anchorSpace, caretSpace) : 0;
        [rows addObject:@{@"start": @(start), @"end": @(end), @"pad": @(pad)}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];

    [sci message:SCI_BEGINUNDOACTION];
    // Bottom-up so earlier offsets stay valid. The selected column is
    // replaced, as the Column Editor does, not pushed along.
    for (NSUInteger i = rows.count; i > 0; --i) {
        NSString *text = textForRow(i - 1);
        if (!text.length) continue;
        NSDictionary *row = rows[i - 1];
        NSString *padded = [[@"" stringByPaddingToLength:[row[@"pad"] unsignedIntegerValue]
                                              withString:@" " startingAtIndex:0]
                            stringByAppendingString:text];
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)[row[@"start"] longValue]
                                        lParam:[row[@"end"] longValue]];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(padded) value:padded];
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

- (BOOL)columnInsertText:(NSString *)text {
    if (!text.length) return NO;
    return [self columnApply:^NSString *(NSUInteger row) { return text; }];
}

- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment
                     zeroPadded:(BOOL)padded base:(int)base {
    return [self columnInsertNumbersFrom:initial increment:increment repeat:1 zeroPadded:padded base:base];
}

- (BOOL)columnInsertNumbersFrom:(long)initial increment:(long)increment repeat:(long)repeat
                     zeroPadded:(BOOL)padded base:(int)base {
    ScintillaView *sci = self.sci;
    long rows = [sci message:SCI_GETSELECTIONS];
    if (rows < 1) return NO;
    if (rows == 1 && ![sci message:SCI_SELECTIONISRECTANGLE] &&
        [sci message:SCI_GETSELECTIONSTART] == [sci message:SCI_GETSELECTIONEND]) {
        rows = [sci message:SCI_GETLINECOUNT] -
               [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    }
    repeat = MAX(1, repeat);

    NSMutableArray *rendered = [NSMutableArray array];
    NSUInteger widest = 0;
    for (long i = 0; i < rows; ++i) {
        // "Repeat" writes each number that many times before moving on.
        long value = initial + increment * (i / repeat);
        NSString *s;
        switch (base) {
            case 16: s = [NSString stringWithFormat:@"%lX", value]; break;
            case 8:  s = [NSString stringWithFormat:@"%lo", value]; break;
            case 2: {
                NSMutableString *bits = [NSMutableString string];
                for (long v = value; v > 0; v >>= 1) [bits insertString:(v & 1) ? @"1" : @"0" atIndex:0];
                s = bits.length ? bits : @"0";
                break;
            }
            default: s = [NSString stringWithFormat:@"%ld", value]; break;
        }
        widest = MAX(widest, s.length);
        [rendered addObject:s];
    }
    if (padded) {
        for (NSUInteger i = 0; i < rendered.count; ++i) {
            NSString *s = rendered[i];
            if (s.length < widest) {
                rendered[i] = [[@"" stringByPaddingToLength:widest - s.length
                                                 withString:@"0" startingAtIndex:0]
                               stringByAppendingString:s];
            }
        }
    }
    return [self columnApply:^NSString *(NSUInteger row) {
        return row < rendered.count ? rendered[row] : @"";
    }];
}

#pragma mark - On selection

- (NSString *)selectionAsPath {
    NSString *raw = [[self currentSelectionOrWord]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!raw.length) return nil;
    if ([raw hasPrefix:@"\""] && [raw hasSuffix:@"\""] && raw.length > 1) {
        raw = [raw substringWithRange:NSMakeRange(1, raw.length - 2)];
    }
    if ([raw hasPrefix:@"~"]) raw = raw.stringByExpandingTildeInPath;
    if (![raw hasPrefix:@"/"]) {
        NSString *base = self.currentDocument.path.stringByDeletingLastPathComponent;
        if (base.length) raw = [base stringByAppendingPathComponent:raw];
    }
    return [[NSFileManager defaultManager] fileExistsAtPath:raw] ? raw : nil;
}

- (BOOL)openSelectedFile {
    NSString *path = [self selectionAsPath];
    if (!path) { NppBeep(); return NO; }
    return [self openFileAtPath:path error:NULL];
}

- (BOOL)revealSelectedFile {
    NSString *path = [self selectionAsPath];
    if (!path) { NppBeep(); return NO; }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    return YES;
}

- (BOOL)redactSelectionWithBlock:(BOOL)solidBlock {
    ScintillaView *sci = self.sci;
    long selections = [sci message:SCI_GETSELECTIONS];
    if (selections < 1) return NO;
    // Notepad++ offers a full block or a bullet; █ and ●.
    NSString *mark = solidBlock ? @"█" : @"●";
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];

    BOOL any = NO;
    [sci message:SCI_BEGINUNDOACTION];
    for (long i = selections - 1; i >= 0; --i) {
        long a = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i];
        long b = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
        if (b <= a) continue;
        NSUInteger chars = SliceBytes(doc, a, b).length;
        NSMutableString *replacement = [NSMutableString string];
        for (NSUInteger c = 0; c < chars; ++c) [replacement appendString:mark];
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)a lParam:0];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)b lParam:0];
        [sci setStringProperty:SCI_REPLACETARGET parameter:Utf8Len(replacement) value:replacement];
        any = YES;
    }
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    if (!any) NppBeep();
    return any;
}

static const char kSearchEngineKey = 0;

- (NSString *)searchEngineTemplate {
    NSString *stored = objc_getAssociatedObject(self, &kSearchEngineKey);
    return stored ?: [[NppPreferences shared] searchEngineTemplate];
}

- (void)setSearchEngineTemplate:(NSString *)engineTemplate {
    objc_setAssociatedObject(self, &kSearchEngineKey, [engineTemplate copy], OBJC_ASSOCIATION_COPY);
}

- (BOOL)searchSelectionOnInternet {
    NSString *term = [self currentSelectionOrWord];
    if (!term.length) { NppBeep(); return NO; }
    NSString *escaped = [term stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]] ?: @"";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:self.searchEngineTemplate, escaped]];
    if (!url) { NppBeep(); return NO; }
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Paste special

- (void)insertStringAtCaret:(NSString *)text {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(pos + Utf8Len(text)) lParam:0];
    [self refreshChrome];
}

- (BOOL)pasteAsHTML {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSString *html = [pb stringForType:NSPasteboardTypeHTML];
    if (!html.length) {
        NSData *data = [pb dataForType:NSPasteboardTypeHTML];
        html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    }
    if (!html.length) { NppBeep(); return NO; }
    [self insertStringAtCaret:html];
    return YES;
}

- (BOOL)pasteAsRTF {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *rtf = [pb dataForType:NSPasteboardTypeRTF];
    if (!rtf) { NppBeep(); return NO; }
    NSString *text = [[NSString alloc] initWithData:rtf encoding:NSASCIIStringEncoding];
    if (!text.length) { NppBeep(); return NO; }
    [self insertStringAtCaret:text];
    return YES;
}

/// Notepad++'s binary clipboard keeps the raw bytes; here they travel as hex
/// pairs, which survives the text-only pasteboard without losing anything.
- (NSString *)hexOfSelection {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) return nil;
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)b > doc.length) return nil;
    NSData *slice = [doc subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))];
    const unsigned char *bytes = (const unsigned char *)slice.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:slice.length * 3];
    for (NSUInteger i = 0; i < slice.length; ++i) {
        if (i) [hex appendString:@" "];
        [hex appendFormat:@"%02X", bytes[i]];
    }
    return hex;
}

- (BOOL)copySelectionAsBinary {
    NSString *hex = [self hexOfSelection];
    if (!hex) { NppBeep(); return NO; }
    [self copyToClipboard:hex];
    return YES;
}

- (BOOL)cutSelectionAsBinary {
    if (![self copySelectionAsBinary]) return NO;
    [self.sci message:SCI_CLEAR];
    [self refreshChrome];
    return YES;
}

- (BOOL)pasteBinary {
    NSString *hex = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!hex.length) { NppBeep(); return NO; }
    NSMutableData *bytes = [NSMutableData data];
    for (NSString *pair in [hex componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (pair.length != 2) continue;
        unsigned int value = 0;
        if (![[NSScanner scannerWithString:pair] scanHexInt:&value]) continue;
        unsigned char b = (unsigned char)value;
        [bytes appendBytes:&b length:1];
    }
    if (!bytes.length) { NppBeep(); return NO; }
    NSString *text = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:bytes encoding:NSISOLatin1StringEncoding];
    if (!text) { NppBeep(); return NO; }
    [self insertStringAtCaret:text];
    return YES;
}

#pragma mark - Auto-completion helpers

/// Where a path being typed starts, as getRawPath finds a drive letter: a
/// "/" or "~/" at the start of the line or after a blank, quote or bracket.
static NSInteger PathStart(NSString *line) {
    for (NSInteger i = (NSInteger)line.length - 1; i >= 0; --i) {
        unichar c = [line characterAtIndex:(NSUInteger)i];
        BOOL tilde = c == '~' && (NSUInteger)i + 1 < line.length && [line characterAtIndex:(NSUInteger)i + 1] == '/';
        if (c != '/' && !tilde) continue;
        if (c == '/' && i > 0 && [line characterAtIndex:(NSUInteger)i - 1] == '~') continue;   // the "~/" is found next
        unichar before = i > 0 ? [line characterAtIndex:(NSUInteger)i - 1] : ' ';
        if (before == '\'' || before == '"' || before == '(' ||
            [[NSCharacterSet whitespaceCharacterSet] characterIsMember:before]) return i;
    }
    return NSNotFound;
}

- (BOOL)showPathCompletion {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long lineStart = [sci message:SCI_POSITIONFROMLINE
                             wParam:(uptr_t)[sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos]];
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSString *before = SliceBytes(doc, lineStart, pos);

    // What was typed, and the folder to list: the folder itself when the
    // typing names one, otherwise the one its last "/" ends.
    NSInteger start = PathStart(before);
    if (start == NSNotFound) { NppBeep(); return NO; }
    NSString *raw = [before substringFromIndex:(NSUInteger)start];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSString *expanded = raw.stringByExpandingTildeInPath;
    if ([fm fileExistsAtPath:expanded isDirectory:&isDir] && !isDir) { NppBeep(); return NO; }
    NSString *typedFolder;
    if (isDir) typedFolder = raw;
    else {
        NSRange slash = [raw rangeOfString:@"/" options:NSBackwardsSearch];
        typedFolder = [raw substringToIndex:slash.location];
        if (!typedFolder.length) typedFolder = @"/";
    }
    NSString *folder = typedFolder.stringByExpandingTildeInPath;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:folder error:NULL];
    if (!names) { NppBeep(); return NO; }

    NSString *withSlash = [typedFolder hasSuffix:@"/"] ? typedFolder : [typedFolder stringByAppendingString:@"/"];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if (entries.count >= 2000) break;           // a huge folder would look like a hang
        BOOL dir = NO;
        [fm fileExistsAtPath:[folder stringByAppendingPathComponent:name] isDirectory:&dir];
        [entries addObject:[NSString stringWithFormat:@"%@%@%@", withSlash, name, dir ? @"/" : @""]];
    }
    if (!entries.count) { NppBeep(); return NO; }

    [sci message:SCI_AUTOCSETSEPARATOR wParam:(uptr_t)'\n' lParam:0];
    [sci message:SCI_AUTOCSETIGNORECASE wParam:1 lParam:0];
    [sci message:SCI_AUTOCSETCASEINSENSITIVEBEHAVIOUR wParam:SC_CASEINSENSITIVEBEHAVIOUR_IGNORECASE lParam:0];
    [sci setStringProperty:SCI_AUTOCSHOW parameter:(long)[raw lengthOfBytesUsingEncoding:NSUTF8StringEncoding]
                     value:[entries componentsJoinedByString:@"\n"]];
    return YES;
}

/// What to show for the word under the caret: the signatures Notepad++ ships for
/// this language, and failing that the lines in this file that look like a
/// declaration of it.
- (NSArray<NSString *> *)callTipCandidates {
    NSString *word = [self currentSelectionOrWord];
    if (!word.length) return @[];

    NSArray<NSString *> *fromApi =
        [[ApiCatalog sharedCatalog] callTipsForLanguage:self.currentDocument.language.name ?: @""
                                               function:word];
    if (fromApi.count) return fromApi;

    NSMutableArray *tips = [NSMutableArray array];
    for (NSString *line in [([self.sci string] ?: @"") componentsSeparatedByString:@"\n"]) {
        if ([line rangeOfString:word].location == NSNotFound) continue;
        if ([line rangeOfString:@"("].location == NSNotFound) continue;
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length && ![tips containsObject:trimmed]) [tips addObject:trimmed];
    }
    return tips;
}

static const char kCallTipIndexKey = 0;
static const char kApiCallTipKey = 0;

#pragma mark - Call tips from the API files

/// The function the caret is inside, and which of its parameters, found as
/// FunctionCallTip::getCursorFunction does: the line up to the caret is cut
/// into identifiers and single characters, and brackets are followed on a
/// stack so that nested calls and plain parentheses are told apart.
- (nullable NSDictionary *)functionAtCaretWithEnvironment:(NSDictionary<NSString *, NSString *> *)env {
    ScintillaView *sci = self.sci;
    long caret = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret];
    long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    if (caret - lineStart < 2 || lineEnd - lineStart + 3 >= 256) return nil;
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSString *text = SliceBytes(doc, lineStart, caret);

    unichar start = [env[@"start"] characterAtIndex:0], stop = [env[@"stop"] characterAtIndex:0];
    unichar param = [env[@"param"] characterAtIndex:0], terminal = [env[@"terminal"] characterAtIndex:0];
    NSString *wordChars = env[@"wordChars"] ?: @"";
    BOOL (^isWordChar)(unichar) = ^BOOL(unichar c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' ||
               (c < 128 && [wordChars rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound);
    };

    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    NSMutableArray<NSNumber *> *isIdentifier = [NSMutableArray array];
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (isWordChar(c)) {
            NSUInteger j = i;
            while (j < text.length && isWordChar([text characterAtIndex:j])) ++j;
            [tokens addObject:[text substringWithRange:NSMakeRange(i, j - i)]];
            [isIdentifier addObject:@YES];
            i = j - 1;
        } else if (c != ' ' && c != '\t' && c != '\n' && c != '\r') {
            [tokens addObject:[NSString stringWithCharacters:&c length:1]];
            [isIdentifier addObject:@NO];
        }
    }

    typedef struct { NSInteger lastIdentifier, lastFunction, param; } Values;
    Values cur = {-1, -1, 0};
    std::vector<Values> stack;
    for (NSInteger i = 0; i < (NSInteger)tokens.count; ++i) {
        if (isIdentifier[(NSUInteger)i].boolValue) { cur.lastIdentifier = i; continue; }
        unichar c = [tokens[(NSUInteger)i] characterAtIndex:0];
        if (c == start) {
            stack.push_back(cur);
            if (i > 0 && cur.lastIdentifier == i - 1) { cur.lastFunction = cur.lastIdentifier; cur.param = 0; }
            else cur.lastFunction = -1;                       // "( x + y )" is no call
        } else if (c == param && cur.lastFunction > -1) {
            cur.param++;
        } else if (c == stop) {
            if (!stack.empty()) { cur = stack.back(); stack.pop_back(); }
            else cur = Values{-1, -1, 0};
        } else if (c == terminal) {
            stack.clear();
            cur = Values{-1, -1, 0};
        }
    }
    while (cur.lastFunction == -1 && !stack.empty()) { cur = stack.back(); stack.pop_back(); }
    if (cur.lastFunction < 0) return nil;
    return @{@"name": tokens[(NSUInteger)cur.lastFunction], @"param": @(cur.param)};
}

- (void)closeApiCallTip {
    if (objc_getAssociatedObject(self, &kApiCallTipKey)) [self.sci message:SCI_CALLTIPCANCEL];
    objc_setAssociatedObject(self, &kApiCallTipKey, nil, OBJC_ASSOCIATION_RETAIN);
}

/// Draws the tip for the tracked function: the overload, arrows to step
/// between overloads, and the current parameter highlighted.
- (void)drawApiCallTip:(NSMutableDictionary *)state {
    ScintillaView *sci = self.sci;
    NppApiEntry *entry = state[@"entry"];
    NSDictionary *env = state[@"env"];
    NSUInteger overload = [state[@"overload"] unsignedIntegerValue];
    NSUInteger param = [state[@"param"] unsignedIntegerValue];
    if (overload >= entry.overloads.count) overload = 0;
    // A parameter beyond this overload's picks the first overload that has it.
    if (param >= entry.overloads[overload].params.count + 1) {
        for (NSUInteger i = 0; i < entry.overloads.count; ++i) {
            if (param < entry.overloads[i].params.count + 1) { overload = i; break; }
        }
    }
    state[@"overload"] = @(overload);
    NppApiOverload *o = entry.overloads[overload];

    NSMutableString *tip = [NSMutableString string];
    if (entry.overloads.count > 1) {
        [tip appendFormat:@"\001%lu of %lu\002", (unsigned long)overload + 1, (unsigned long)entry.overloads.count];
    }
    [tip appendFormat:@"%@ %@ %@", o.returnValue, state[@"name"], env[@"start"]];
    long hlStart = 0, hlEnd = 0;
    for (NSUInteger i = 0; i < o.params.count; ++i) {
        if (i == param) {
            hlStart = Utf8Length(tip);
            hlEnd = hlStart + Utf8Length(o.params[i]);
        }
        [tip appendString:o.params[i]];
        if (i + 1 < o.params.count) [tip appendFormat:@"%@ ", env[@"param"]];
    }
    [tip appendString:env[@"stop"]];
    if (o.descr.length) [tip appendFormat:@"\n%@", o.descr];

    [sci message:SCI_CALLTIPCANCEL];
    [sci setStringProperty:SCI_CALLTIPSHOW parameter:[state[@"startPos"] longValue] value:tip];
    if (hlStart != hlEnd) [sci message:SCI_CALLTIPSETHLT wParam:(uptr_t)hlStart lParam:hlEnd];
    objc_setAssociatedObject(self, &kApiCallTipKey, state, OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)updateCallTipForCharacter:(int)ch force:(BOOL)needShown {
    NSString *language = self.currentDocument.language.name ?: @"";
    NSDictionary *env = [[ApiCatalog sharedCatalog] callTipEnvironmentForLanguage:language];
    if (!env) return NO;
    NSMutableDictionary *state = objc_getAssociatedObject(self, &kApiCallTipKey);
    BOOL visible = state && [self.sci message:SCI_CALLTIPACTIVE] != 0;
    if (!needShown && ch != [env[@"start"] characterAtIndex:0] &&
        ch != [env[@"param"] characterAtIndex:0] && !visible) return NO;

    NSDictionary *found = [self functionAtCaretWithEnvironment:env];
    NppApiEntry *entry = found ? [[ApiCatalog sharedCatalog] functionNamed:found[@"name"] inLanguage:language] : nil;
    if (!entry) { [self closeApiCallTip]; return NO; }

    BOOL same = visible && [state[@"entry"] isEqual:entry];
    NSMutableDictionary *next = [NSMutableDictionary dictionary];
    next[@"entry"] = entry;
    next[@"env"] = env;
    next[@"name"] = found[@"name"];
    next[@"param"] = found[@"param"];
    next[@"overload"] = same ? state[@"overload"] : @0;
    next[@"startPos"] = visible ? state[@"startPos"] : @([self.sci message:SCI_GETCURRENTPOS]);
    [self drawApiCallTip:next];
    return YES;
}

- (BOOL)apiCallTipVisible {
    return objc_getAssociatedObject(self, &kApiCallTipKey) && [self.sci message:SCI_CALLTIPACTIVE] != 0;
}

- (nullable NSDictionary *)apiCallTipState {
    return [self apiCallTipVisible] ? [objc_getAssociatedObject(self, &kApiCallTipKey) copy] : nil;
}

- (void)callTipClicked:(long)position {
    if (position == 1) [self cycleFunctionCallTip:NO];
    else if (position == 2) [self cycleFunctionCallTip:YES];
}

- (BOOL)showFunctionCallTip {
    // The shipped signature of the function the caret is in, as Notepad++
    // shows it; failing that, what callTipCandidates finds for the word.
    if ([self updateCallTipForCharacter:0 force:YES]) return YES;
    NSArray *tips = [self callTipCandidates];
    if (!tips.count) { NppBeep(); return NO; }
    objc_setAssociatedObject(self, &kCallTipIndexKey, @0, OBJC_ASSOCIATION_RETAIN);
    NSString *body = tips.count > 1
        ? [NSString stringWithFormat:@"%@   (1 of %lu)", tips[0], (unsigned long)tips.count]
        : tips[0];
    [self.sci setStringProperty:SCI_CALLTIPSHOW
                      parameter:[self.sci message:SCI_GETCURRENTPOS] value:body];
    return YES;
}

- (BOOL)cycleFunctionCallTip:(BOOL)forward {
    NSMutableDictionary *state = objc_getAssociatedObject(self, &kApiCallTipKey);
    if (state && [self.sci message:SCI_CALLTIPACTIVE] != 0) {
        NppApiEntry *entry = state[@"entry"];
        NSUInteger n = entry.overloads.count;
        if (n < 2) { NppBeep(); return NO; }
        NSUInteger cur = [state[@"overload"] unsignedIntegerValue];
        state[@"overload"] = @(forward ? (cur + 1) % n : (cur + n - 1) % n);
        // Stepping by hand chooses the overload; the parameter no longer does.
        state[@"param"] = @0;
        [self drawApiCallTip:state];
        return YES;
    }
    NSArray *tips = [self callTipCandidates];
    if (tips.count < 2) { NppBeep(); return NO; }
    NSNumber *stored = objc_getAssociatedObject(self, &kCallTipIndexKey);
    NSInteger idx = (stored.integerValue + (forward ? 1 : -1) + (NSInteger)tips.count)
                    % (NSInteger)tips.count;
    objc_setAssociatedObject(self, &kCallTipIndexKey, @(idx), OBJC_ASSOCIATION_RETAIN);
    NSString *body = [NSString stringWithFormat:@"%@   (%ld of %lu)",
                      tips[(NSUInteger)idx], (long)idx + 1, (unsigned long)tips.count];
    [self.sci setStringProperty:SCI_CALLTIPSHOW
                      parameter:[self.sci message:SCI_GETCURRENTPOS] value:body];
    return YES;
}

#pragma mark - File attribute

/// Notepad++ toggles the Windows read-only attribute; the macOS counterpart is
/// the file's write permission.
- (BOOL)systemReadOnly {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    return ![[NSFileManager defaultManager] isWritableFileAtPath:path];
}

- (BOOL)toggleSystemReadOnly {
    NSString *path = self.currentDocument.path;
    if (!path.length) { NppBeep(); return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
    if (!attrs) { NppBeep(); return NO; }

    NSUInteger perms = [attrs[NSFilePosixPermissions] unsignedIntegerValue];
    NSUInteger updated = [self systemReadOnly] ? (perms | 0200) : (perms & ~(NSUInteger)0222);
    if (![fm setAttributes:@{NSFilePosixPermissions: @(updated)} ofItemAtPath:path error:NULL]) {
        NppBeep();
        return NO;
    }
    [self refreshChrome];
    return YES;
}

@end
