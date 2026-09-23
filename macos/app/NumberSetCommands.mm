#import "NumberSetCommands.h"
#import "Localization.h"
#import "ScintillaView.h"

/// Above this the context menu does not read the selection for numbers, so it opens at once.
static const long kMostNumberSetBytes = 4 * 1024 * 1024;

static NSString *SelectedText(ScintillaView *sci, long start, long end) {
    if (end <= start) return @"";
    NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)(end - start) + 1];
    struct { struct { long cpMin, cpMax; } chrg; char *lpstrText; } tr;
    tr.chrg.cpMin = start;
    tr.chrg.cpMax = end;
    tr.lpstrText = (char *)buffer.mutableBytes;
    [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
    return [NSString stringWithUTF8String:(const char *)buffer.bytes] ?: @"";
}

@implementation EditorController (NumberSetCommands)

/// The selection's non-empty pieces in document order, as {start, end} byte offsets.
- (NSArray<NSArray<NSNumber *> *> *)numberSetRanges {
    ScintillaView *sci = self.sci;
    NSMutableArray<NSArray<NSNumber *> *> *ranges = [NSMutableArray array];
    long total = 0;
    long n = [sci message:SCI_GETSELECTIONS];
    for (long i = 0; i < n; ++i) {
        long start = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i];
        long end = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
        if (end <= start) continue;
        total += end - start;
        if (total > kMostNumberSetBytes) return @[];
        [ranges addObject:@[@(start), @(end)]];
    }
    [ranges sortUsingComparator:^NSComparisonResult(NSArray<NSNumber *> *a, NSArray<NSNumber *> *b) {
        return [a[0] compare:b[0]];
    }];
    return ranges;
}

- (NSArray<NSString *> *)textsOfRanges:(NSArray<NSArray<NSNumber *> *> *)ranges {
    NSMutableArray<NSString *> *texts = [NSMutableArray arrayWithCapacity:ranges.count];
    for (NSArray<NSNumber *> *r in ranges) [texts addObject:SelectedText(self.sci, r[0].longValue, r[1].longValue)];
    return texts;
}

- (nullable NppNumberSet *)numberSetInSelection {
    NSArray *ranges = [self numberSetRanges];
    return ranges.count ? [NppNumberSet setFromPieces:[self textsOfRanges:ranges]] : nil;
}

- (NSArray<NSMenuItem *> *)numberSetMenuItems {
    NppNumberSet *set = [self numberSetInSelection];
    if (!set) return @[];
    NSMenu *sub = [[NSMenu alloc] initWithTitle:NppL(@"Selected Numbers")];
    sub.autoenablesItems = NO;
    BOOL writable = ![self.sci message:SCI_GETREADONLY];
    NSArray<NSString *> *names = @[@"Sum", @"Average", @"Minimum", @"Maximum", @"Count"];
    for (NSUInteger k = 0; k < names.count; ++k) {
        NSMenuItem *item = [sub addItemWithTitle:NppL(names[k]) action:@selector(numberSetInsertValue:) keyEquivalent:@""];
        item.target = self;
        item.tag = (NSInteger)k;
        item.enabled = writable;
    }
    [sub addItem:[NSMenuItem separatorItem]];
    struct { NSString *title; NSInteger ascending; } sorts[] = {{@"Sort Ascending", 1}, {@"Sort Descending", 0}};
    for (auto &sort : sorts) {
        NSMenuItem *item = [sub addItemWithTitle:NppL(sort.title) action:@selector(numberSetSort:) keyEquivalent:@""];
        item.target = self;
        item.tag = sort.ascending;
        item.enabled = writable;
    }
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:NppL(@"Selected Numbers") action:NULL keyEquivalent:@""];
    top.submenu = sub;
    return @[top, [NSMenuItem separatorItem]];
}

- (nullable NppFormula *)formulaInSelection {
    NSArray<NSArray<NSNumber *> *> *ranges = [self numberSetRanges];
    if (ranges.count != 1) return nil;
    return [NppFormula formulaFromText:[self textsOfRanges:ranges].firstObject];
}

- (NSArray<NSMenuItem *> *)formulaMenuItems {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NppL(@"Calculate")
                                                  action:@selector(formulaCalculate:) keyEquivalent:@""];
    item.target = self;
    // The menu enables items by their action, so one that cannot run has none.
    if (![self formulaInSelection] || [self.sci message:SCI_GETREADONLY]) item.action = NULL;
    return @[item, [NSMenuItem separatorItem]];
}

- (void)formulaCalculate:(NSMenuItem *)sender {
    [self calculateFormula];
}

- (void)calculateFormula {
    BOOL selection = [self.sci message:SCI_GETSELECTIONSTART] != [self.sci message:SCI_GETSELECTIONEND];
    if (selection ? [self calculateSelectedFormula] : [self calculateFormulaAtCaret]) return;
    NppBeep();
    // A formula without a value (1/0) is left as it is, and the status bar says why.
    NSString *problem = selection ? [self formulaInSelection].problem : self.formulaAtCaretProblem;
    if (problem) [self flashStatus:[NSString stringWithFormat:@"⚠ %@", NppL(problem)]];
}

static NSString *gFormulaAtCaretProblem;
- (nullable NSString *)formulaAtCaretProblem { return gFormulaAtCaretProblem; }

/// The formula that ends at the caret on its line: the longest piece, from
/// the start of a word on, that reads as one ("total: 2 + 3 =" gives
/// "2 + 3 ="); with no "=" typed yet, as if there were one.
- (BOOL)calculateFormulaAtCaret {
    gFormulaAtCaretProblem = nil;
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) return NO;
    long caret = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret];
    long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    if (caret - lineStart > 4000) return NO;
    NSString *before = SelectedText(sci, lineStart, caret);
    NSString *after = SelectedText(sci, caret, lineEnd);
    // An old result right after the caret is part of it, to be replaced.
    static NSRegularExpression *oldResult = [NSRegularExpression regularExpressionWithPattern:
        @"^[ \\t]*(?:[+\\-\\x{2212}]?[0-9]+(?:[.,][0-9]+)?(?:[eE][+\\-]?[0-9]+)?)?[ \\t]*$" options:0 error:NULL];
    BOOL takesRest = [oldResult firstMatchInString:after options:0 range:NSMakeRange(0, after.length)] != nil;
    NSString *segment = takesRest ? [before stringByAppendingString:after] : before;
    long segmentEnd = takesRest ? lineEnd : caret;
    // "2 + 3 =|", "2 + 3 = 7|": the "=" is typed (an "=" further left is an
    // assignment, "x = 2 + 3|", and the formula comes after it).
    static NSRegularExpression *typed = [NSRegularExpression regularExpressionWithPattern:
        @"=[ \\t]*(?:[+\\-\\x{2212}]?[0-9]+(?:[.,][0-9]+)?(?:[eE][+\\-]?[0-9]+)?)?[ \\t]*$" options:0 error:NULL];
    BOOL typedEquals = [typed firstMatchInString:before options:0 range:NSMakeRange(0, before.length)] != nil;
    if (!typedEquals) { segment = [before stringByAppendingString:@"="]; segmentEnd = caret; }

    NSCharacterSet *wordy = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger k = 0; k < segment.length; ++k) {
        unichar c = [segment characterAtIndex:k];
        if ([NSCharacterSet.whitespaceCharacterSet characterIsMember:c]) continue;
        if (k > 0) {
            unichar p = [segment characterAtIndex:k - 1];
            if ([wordy characterIsMember:p] || p == '.' || p == ',') continue;
        }
        NppFormula *formula = [NppFormula formulaFromText:[segment substringFromIndex:k]];
        if (!formula) continue;
        if (!formula.result) { gFormulaAtCaretProblem = formula.problem; return NO; }
        NSString *piece = [segment substringFromIndex:k];
        NSRange r = formula.replacedRange;
        NSString *insert = formula.replacement;
        long from, to;
        if (typedEquals) {
            long pieceStart = segmentEnd - (long)[piece lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            from = pieceStart + (long)[[piece substringToIndex:r.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            to = from + (long)[[piece substringWithRange:r] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        } else {
            // The "=" is ours: it and the value go in at the caret.
            from = to = caret;
            insert = [@"=" stringByAppendingString:insert];
        }
        NSData *utf8 = [insert dataUsingEncoding:NSUTF8StringEncoding];
        [sci message:SCI_BEGINUNDOACTION];
        [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)from lParam:to];
        [sci message:SCI_REPLACETARGET wParam:utf8.length lParam:(sptr_t)utf8.bytes];
        [sci message:SCI_ENDUNDOACTION];
        [sci message:SCI_GOTOPOS wParam:(uptr_t)(from + (long)utf8.length)];
        [self refreshChrome];
        return YES;
    }
    return NO;
}

- (BOOL)calculateSelectedFormula {
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) return NO;
    NSArray<NSArray<NSNumber *> *> *ranges = [self numberSetRanges];
    if (ranges.count != 1) return NO;
    NSString *text = [self textsOfRanges:ranges].firstObject;
    NppFormula *formula = [NppFormula formulaFromText:text];
    if (!formula.result) return NO;
    long start = ranges[0][0].longValue, end = ranges[0][1].longValue;
    // The replaced part's place in bytes: what precedes it and what it is, in UTF-8.
    NSRange r = formula.replacedRange;
    long from = start + (long)[[text substringToIndex:r.location] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    long to = from + (long)[[text substringWithRange:r] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSData *utf8 = [formula.replacement dataUsingEncoding:NSUTF8StringEncoding];
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)from lParam:to];
    [sci message:SCI_REPLACETARGET wParam:utf8.length lParam:(sptr_t)utf8.bytes];
    [sci message:SCI_ENDUNDOACTION];
    // The formula with its value selected, so it can be changed and calculated again.
    long newEnd = end + (long)utf8.length - (to - from);
    [sci message:SCI_SETSEL wParam:(uptr_t)start lParam:newEnd];
    [self refreshChrome];
    return YES;
}

- (void)numberSetInsertValue:(NSMenuItem *)sender {
    if (![self insertNumberSetValue:(NppNumberSetValue)sender.tag]) NppBeep();
}

- (BOOL)insertNumberSetValue:(NppNumberSetValue)which {
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) return NO;
    NSArray<NSArray<NSNumber *> *> *ranges = [self numberSetRanges];
    if (!ranges.count) return NO;
    NSArray<NSString *> *texts = [self textsOfRanges:ranges];
    NppNumberSet *set = [NppNumberSet setFromPieces:texts];
    if (!set) return NO;
    NSString *value = which == NppNumberSetSum ? set.sum : which == NppNumberSetAverage ? set.average
                    : which == NppNumberSetMinimum ? set.minimum : which == NppNumberSetMaximum ? set.maximum
                    : [NSString stringWithFormat:@"%lu", (unsigned long)set.count];
    NSString *label = @[@"SUM", @"AVG", @"MIN", @"MAX", @"COUNT"][which];
    NSString *line = [NSString stringWithFormat:@"%@ = %@", label, value];

    long start = ranges.firstObject[0].longValue, end = ranges.lastObject[1].longValue;
    long firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)start];
    long lastLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)end];
    int eolMode = (int)[sci message:SCI_GETEOLMODE];
    NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
    long at;
    NSString *insert;
    if (lastLine == firstLine) {
        // "30, 4, 100" -> "30, 4, 100 SUM = 134", on the same line.
        at = end;
        unichar before = at > 0 ? (unichar)[sci message:SCI_GETCHARAT wParam:(uptr_t)(at - 1)] : ' ';
        insert = [(before == ' ' || before == '\t' ? @"" : @" ") stringByAppendingString:line];
    } else if (end == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine]) {
        // The selection took the last line's break too: the value is the next line.
        at = end;
        insert = [line stringByAppendingString:eol];
    } else {
        // One per line or a column: a line of its own under the numbers.
        at = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)lastLine];
        insert = [eol stringByAppendingString:line];
    }
    NSData *utf8 = [insert dataUsingEncoding:NSUTF8StringEncoding];
    [sci message:SCI_BEGINUNDOACTION];
    [sci message:SCI_INSERTTEXT wParam:(uptr_t)at lParam:(sptr_t)insert.UTF8String];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(at + (long)utf8.length)];
    [self refreshChrome];
    return YES;
}

- (void)numberSetSort:(NSMenuItem *)sender {
    if (![self sortSelectedNumbersAscending:sender.tag == 1]) NppBeep();
}

- (BOOL)sortSelectedNumbersAscending:(BOOL)ascending {
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) return NO;
    NSArray<NSArray<NSNumber *> *> *ranges = [self numberSetRanges];
    if (!ranges.count) return NO;
    NSArray<NSString *> *texts = [self textsOfRanges:ranges];
    NppNumberSet *set = [NppNumberSet setFromPieces:texts];
    if (!set) return NO;
    NSArray<NSString *> *sorted = [set piecesSortedAscending:ascending];

    // Top-down, carrying the change in length to the pieces below.
    NSMutableArray<NSArray<NSNumber *> *> *placed = [NSMutableArray arrayWithCapacity:ranges.count];
    long shift = 0;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSUInteger i = 0; i < ranges.count; ++i) {
        long start = ranges[i][0].longValue + shift, end = ranges[i][1].longValue + shift;
        NSData *utf8 = [sorted[i] dataUsingEncoding:NSUTF8StringEncoding];
        if (![sorted[i] isEqualToString:texts[i]]) {
            [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)start lParam:end];
            [sci message:SCI_REPLACETARGET wParam:utf8.length lParam:(sptr_t)utf8.bytes];
        }
        long newEnd = start + (long)utf8.length;
        [placed addObject:@[@(start), @(newEnd)]];
        shift += newEnd - end;
    }
    [sci message:SCI_ENDUNDOACTION];

    // The same pieces stay selected, now holding the sorted numbers.
    [sci message:SCI_SETSELECTION wParam:(uptr_t)placed[0][1].longValue lParam:placed[0][0].longValue];
    for (NSUInteger i = 1; i < placed.count; ++i) {
        [sci message:SCI_ADDSELECTION wParam:(uptr_t)placed[i][1].longValue lParam:placed[i][0].longValue];
    }
    [self refreshChrome];
    return YES;
}

@end
