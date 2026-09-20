#import "CompareCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

@implementation NppDiffLine
@end

@implementation EditorController (CompareCommands)

#pragma mark - The difference itself

/// Lines are compared through this, so the ignore options change what counts
/// as equal rather than being applied afterwards.
static NSString *NormalisedLine(NSString *line, BOOL ignoreCase, BOOL ignoreSpaces) {
    NSString *out = line;
    if (ignoreSpaces) {
        NSArray *parts = [out componentsSeparatedByCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *kept = [NSMutableArray array];
        for (NSString *p in parts) if (p.length) [kept addObject:p];
        out = [kept componentsJoinedByString:@" "];
    }
    if (ignoreCase) out = out.lowercaseString;
    return out;
}

/// Myers' O(ND) difference. The trace of each step is kept so the path can be
/// walked back once the end is reached.
+ (NSArray<NppDiffLine *> *)diffBetween:(NSArray<NSString *> *)oldLines
                                    and:(NSArray<NSString *> *)newLines
                             ignoreCase:(BOOL)ignoreCase
                           ignoreSpaces:(BOOL)ignoreSpaces
                       ignoreEmptyLines:(BOOL)ignoreEmptyLines {

    NSMutableArray<NSString *> *a = [NSMutableArray array];
    NSMutableArray<NSNumber *> *aIndex = [NSMutableArray array];
    NSMutableArray<NSString *> *b = [NSMutableArray array];
    NSMutableArray<NSNumber *> *bIndex = [NSMutableArray array];

    for (NSUInteger i = 0; i < oldLines.count; ++i) {
        NSString *norm = NormalisedLine(oldLines[i], ignoreCase, ignoreSpaces);
        if (ignoreEmptyLines && !norm.length) continue;
        [a addObject:norm];
        [aIndex addObject:@(i)];
    }
    for (NSUInteger i = 0; i < newLines.count; ++i) {
        NSString *norm = NormalisedLine(newLines[i], ignoreCase, ignoreSpaces);
        if (ignoreEmptyLines && !norm.length) continue;
        [b addObject:norm];
        [bIndex addObject:@(i)];
    }

    NSInteger n = (NSInteger)a.count, m = (NSInteger)b.count;
    NSInteger max = n + m;
    NSMutableArray<NSArray<NSNumber *> *> *trace = [NSMutableArray array];

    // v is indexed by diagonal k, offset by max so k can be negative.
    NSMutableArray<NSNumber *> *v = [NSMutableArray arrayWithCapacity:(NSUInteger)(2 * max + 1)];
    for (NSInteger i = 0; i <= 2 * max; ++i) [v addObject:@0];

    BOOL reachedEnd = NO;
    for (NSInteger d = 0; d <= max && !reachedEnd; ++d) {
        [trace addObject:[v copy]];
        for (NSInteger k = -d; k <= d; k += 2) {
            NSInteger x;
            if (k == -d || (k != d && [v[(NSUInteger)(k - 1 + max)] integerValue] <
                                      [v[(NSUInteger)(k + 1 + max)] integerValue])) {
                x = [v[(NSUInteger)(k + 1 + max)] integerValue];
            } else {
                x = [v[(NSUInteger)(k - 1 + max)] integerValue] + 1;
            }
            NSInteger y = x - k;
            while (x < n && y < m && [a[(NSUInteger)x] isEqualToString:b[(NSUInteger)y]]) { x++; y++; }
            v[(NSUInteger)(k + max)] = @(x);
            if (x >= n && y >= m) { reachedEnd = YES; break; }
        }
    }

    // Walk the trace backwards to recover the path.
    NSMutableArray<NppDiffLine *> *reversed = [NSMutableArray array];
    NSInteger x = n, y = m;
    for (NSInteger d = (NSInteger)trace.count - 1; d >= 0 && (x > 0 || y > 0); --d) {
        NSArray<NSNumber *> *vd = trace[(NSUInteger)d];
        NSInteger k = x - y;
        NSInteger prevK;
        if (k == -d || (k != d && [vd[(NSUInteger)(k - 1 + max)] integerValue] <
                                  [vd[(NSUInteger)(k + 1 + max)] integerValue])) {
            prevK = k + 1;
        } else {
            prevK = k - 1;
        }
        NSInteger prevX = [vd[(NSUInteger)(prevK + max)] integerValue];
        NSInteger prevY = prevX - prevK;

        while (x > prevX && y > prevY) {
            NppDiffLine *line = [[NppDiffLine alloc] init];
            line.kind = NppDiffSame;
            line.oldLine = [aIndex[(NSUInteger)(x - 1)] integerValue];
            line.newLine = [bIndex[(NSUInteger)(y - 1)] integerValue];
            [reversed addObject:line];
            x--; y--;
        }
        if (d == 0) break;
        NppDiffLine *line = [[NppDiffLine alloc] init];
        if (x > prevX) {
            line.kind = NppDiffRemoved;
            line.oldLine = [aIndex[(NSUInteger)(x - 1)] integerValue];
            line.newLine = -1;
            x--;
        } else {
            line.kind = NppDiffAdded;
            line.oldLine = -1;
            line.newLine = [bIndex[(NSUInteger)(y - 1)] integerValue];
            y--;
        }
        [reversed addObject:line];
    }

    NSMutableArray<NppDiffLine *> *result = [NSMutableArray array];
    for (NppDiffLine *line in reversed.reverseObjectEnumerator) [result addObject:line];

    // A removal immediately followed by an addition is one changed line, which
    // is how ComparePlus presents it.
    for (NSUInteger i = 0; i + 1 < result.count; ++i) {
        if (result[i].kind == NppDiffRemoved && result[i + 1].kind == NppDiffAdded) {
            result[i].kind = NppDiffChanged;
            result[i].newLine = result[i + 1].newLine;
            [result removeObjectAtIndex:i + 1];
        }
    }
    return result;
}

#pragma mark - State

static const char kFirstToCompareKey = 0;
static const char kCurrentDiffKey = 0;

- (NSString *)firstToCompare { return objc_getAssociatedObject(self, &kFirstToCompareKey); }

- (void)setFirstToCompare {
    NSString *path = self.currentDocument.path;
    objc_setAssociatedObject(self, &kFirstToCompareKey,
                             path ?: self.currentDocument.displayName, OBJC_ASSOCIATION_COPY);
    [self refreshChrome];
}

- (NSArray<NppDiffLine *> *)currentDiff {
    return objc_getAssociatedObject(self, &kCurrentDiffKey) ?: @[];
}

- (BOOL)compareActive { return [self currentDiff].count > 0; }

- (BOOL)compareIgnoreCase { return [NppPreferences shared].compareIgnoreCase; }
- (void)setCompareIgnoreCase:(BOOL)v { [NppPreferences shared].compareIgnoreCase = v; }
- (BOOL)compareIgnoreSpaces { return [NppPreferences shared].compareIgnoreSpaces; }
- (void)setCompareIgnoreSpaces:(BOOL)v { [NppPreferences shared].compareIgnoreSpaces = v; }
- (BOOL)compareIgnoreEmptyLines { return [NppPreferences shared].compareIgnoreEmptyLines; }
- (void)setCompareIgnoreEmptyLines:(BOOL)v { [NppPreferences shared].compareIgnoreEmptyLines = v; }

#pragma mark - Marking

- (void)defineCompareMarkers {
    ScintillaView *sci = self.sci;
    struct { int marker; long colour; } marks[] = {
        {NPPMAC_MARKER_ADDED,   0x90EE90},   // BGR: light green
        {NPPMAC_MARKER_REMOVED, 0x9090FF},   // light red
        {NPPMAC_MARKER_CHANGED, 0xC0E0FF},   // light amber
        {NPPMAC_MARKER_MOVED,   0xE0D0A0},   // light blue-grey
    };
    for (size_t i = 0; i < sizeof(marks)/sizeof(marks[0]); ++i) {
        // A marker with no margin is drawn as a whole-line background, which is
        // exactly what a compared line wants.
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)marks[i].marker lParam:SC_MARK_BACKGROUND];
        [sci message:SCI_MARKERSETBACK wParam:(uptr_t)marks[i].marker lParam:marks[i].colour];
        [sci message:SCI_MARKERSETALPHA wParam:(uptr_t)marks[i].marker lParam:80];
    }
}

- (void)clearCompareMarkers {
    for (int m = NPPMAC_MARKER_ADDED; m <= NPPMAC_MARKER_MOVED; ++m) {
        [self.sci message:SCI_MARKERDELETEALL wParam:(uptr_t)m lParam:0];
        [self.secondarySci message:SCI_MARKERDELETEALL wParam:(uptr_t)m lParam:0];
    }
}

- (void)markDiff:(NSArray<NppDiffLine *> *)diff {
    [self defineCompareMarkers];
    [self clearCompareMarkers];
    ScintillaView *sci = self.sci;

    for (NppDiffLine *line in diff) {
        if (line.kind == NppDiffSame || line.newLine < 0) continue;
        int marker = line.kind == NppDiffAdded ? NPPMAC_MARKER_ADDED
                   : line.kind == NppDiffChanged ? NPPMAC_MARKER_CHANGED
                                                 : NPPMAC_MARKER_REMOVED;
        [sci message:SCI_MARKERADD wParam:(uptr_t)line.newLine lParam:marker];
    }
    // Lines only in the old file are marked in the pane showing it.
    for (NppDiffLine *line in diff) {
        if (line.kind != NppDiffRemoved || line.oldLine < 0) continue;
        [self.secondarySci message:SCI_MARKERADD wParam:(uptr_t)line.oldLine
                            lParam:NPPMAC_MARKER_REMOVED];
    }
}

#pragma mark - Commands

+ (NSArray<NSString *> *)linesForComparison:(NSString *)text {
    // CRLF, LF and CR are all endings; a CR left on a line would make every
    // line of a Windows file differ from a Unix one.
    NSString *normalised = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                            stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    return [normalised componentsSeparatedByString:@"\n"];
}

- (NSArray<NSString *> *)linesOfCurrentDocument {
    return [EditorController linesForComparison:[self documentText]];
}

- (BOOL)compareWithFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { NppBeep(); return NO; }
    NSString *other = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                   ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!other) { NppBeep(); return NO; }

    NSArray *oldLines = [EditorController linesForComparison:other];
    NSArray *newLines = [self linesOfCurrentDocument];
    NSArray *diff = [EditorController diffBetween:oldLines and:newLines
                                       ignoreCase:self.compareIgnoreCase
                                     ignoreSpaces:self.compareIgnoreSpaces
                                 ignoreEmptyLines:self.compareIgnoreEmptyLines];
    objc_setAssociatedObject(self, &kCurrentDiffKey, diff, OBJC_ASSOCIATION_RETAIN);

    // The other file goes into the second pane, so both sides are visible.
    [self setSecondaryViewVisible:YES];
    [self.secondarySci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.secondarySci setString:other];
    [self.secondarySci message:SCI_SETREADONLY wParam:1 lParam:0];
    [self setSyncVerticalScroll:YES];

    [self markDiff:diff];
    [self refreshChrome];
    return YES;
}

- (BOOL)compareWithFirst {
    NSString *first = [self firstToCompare];
    if (!first.length) { NppBeep(); return NO; }
    if ([first isEqualToString:self.currentDocument.path]) { NppBeep(); return NO; }
    return [self compareWithFileAtPath:first];
}

- (void)clearActiveCompare {
    objc_setAssociatedObject(self, &kCurrentDiffKey, nil, OBJC_ASSOCIATION_RETAIN);
    [self clearCompareMarkers];
    [self setSyncVerticalScroll:NO];
    [self setSecondaryViewVisible:NO];
    [self refreshChrome];
}

- (void)clearAllCompares {
    objc_setAssociatedObject(self, &kFirstToCompareKey, nil, OBJC_ASSOCIATION_COPY);
    [self clearActiveCompare];
}

- (NSString *)compareSummary {
    NSUInteger added = 0, removed = 0, changed = 0, same = 0;
    for (NppDiffLine *line in [self currentDiff]) {
        switch (line.kind) {
            case NppDiffAdded:   added++;   break;
            case NppDiffRemoved: removed++; break;
            case NppDiffChanged: changed++; break;
            default:             same++;    break;
        }
    }
    if (!added && !removed && !changed) {
        return same ? @"The files are identical." : @"Nothing has been compared.";
    }
    return [NSString stringWithFormat:@"%lu added, %lu removed, %lu changed, %lu unchanged.",
            (unsigned long)added, (unsigned long)removed,
            (unsigned long)changed, (unsigned long)same];
}

#pragma mark - Navigation

/// Lines in the current document that a comparison marked.
- (NSArray<NSNumber *> *)markedLines {
    NSMutableArray *lines = [NSMutableArray array];
    for (NppDiffLine *line in [self currentDiff]) {
        if (line.kind == NppDiffSame || line.newLine < 0) continue;
        [lines addObject:@(line.newLine)];
    }
    return lines;
}

- (BOOL)goToDiff:(NSInteger)direction {
    NSArray *lines = [self markedLines];
    if (!lines.count) { NppBeep(); return NO; }
    ScintillaView *sci = self.sci;
    NSInteger current = [sci message:SCI_LINEFROMPOSITION
                              wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];

    NSNumber *target = nil;
    if (direction > 0) {
        for (NSNumber *l in lines) if (l.integerValue > current) { target = l; break; }
        if (!target) target = lines.firstObject;              // wrap
    } else {
        for (NSNumber *l in lines.reverseObjectEnumerator) {
            if (l.integerValue < current) { target = l; break; }
        }
        if (!target) target = lines.lastObject;
    }
    [sci message:SCI_GOTOLINE wParam:(uptr_t)target.integerValue lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)goToFirstDiff {
    NSArray *lines = [self markedLines];
    if (!lines.count) { NppBeep(); return NO; }
    [self.sci message:SCI_GOTOLINE wParam:(uptr_t)[lines.firstObject integerValue] lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)goToLastDiff {
    NSArray *lines = [self markedLines];
    if (!lines.count) { NppBeep(); return NO; }
    [self.sci message:SCI_GOTOLINE wParam:(uptr_t)[lines.lastObject integerValue] lParam:0];
    [self refreshChrome];
    return YES;
}

@end
