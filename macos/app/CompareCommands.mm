// Compare, as the ComparePlus plugin does it on Windows: its engine
// (macos/third_party/compareplus - the diff algorithms, moved lines, sub-line
// differences, the alignment of both panes with blank annotations, the
// margin symbols and colours) runs over the two panes here, through the shims
// beside it. Around the engine is what the plugin's Compare.cpp does for the
// user, in this port's own way: the other text in the second pane with the
// document's language and theme, a bar with the summary and navigation,
// Escape to leave, a comparison that follows typing, and the port's own
// revert arrow beside each difference.
#import "CompareCommands.h"
#import "LanguageCatalog.h"
#import "Localization.h"
#import "GitCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>
#include <vector>
#include <cmath>
#include "Engine.h"
#include "NppHelpers.h"

@implementation NppDiffLine
@end

#pragma mark - The engine's surroundings

/// What one comparison holds: the other side's text, the engine's summary, and
/// the alignment it asks for. One editor, one comparison at a time.
namespace {
struct ActiveCompare {
    CompareSummary summary;
    std::string otherText;
    bool mismatch = false;
};
ActiveCompare gCompare;
}

/// The engine reaches the panes through Scintilla's direct function: the
/// document in front is MAIN_VIEW, the other text SUB_VIEW.
static void BindViews(EditorController *ed) {
    sciFunc = (SciFnDirect)[ed.mainSci message:SCI_GETDIRECTFUNCTION wParam:0 lParam:0];
    sciPtr[MAIN_VIEW] = [ed.mainSci message:SCI_GETDIRECTPOINTER wParam:0 lParam:0];
    sciPtr[SUB_VIEW] = [ed.secondarySci message:SCI_GETDIRECTPOINTER wParam:0 lParam:0];
    marginNum = NPPMAC_COMPARE_MARGIN;
    nppBookmarkMarker = 1 << 1;
}

static BOOL DarkAppearance(void) {
    return [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
            isEqualToString:NSAppearanceNameDarkAqua];
}

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

/// Myers' greedy O((N+M)D) difference, in O(N+M) working memory plus
/// checkpoints, with exactly the path the plain algorithm finds.
///
/// The plain algorithm keeps the furthest-reaching x of every diagonal for
/// every step d and walks that trace back from the end: D(D+1) numbers,
/// gigabytes for two unrelated files. Here the walk back needs only, for each
/// step, which neighbour each diagonal came from (one bit), and even those are
/// kept for one segment of steps at a time: the forward pass saves the
/// diagonals every `segment` steps, and a segment is re-run from its checkpoint
/// when the walk reaches it. The walk yields the diagonal of every step; the
/// path is then rebuilt forwards, each snake as long as it goes, which is how
/// the forward pass made it. Linear-space Myers (the middle snake) would find
/// another path of the same length when lines repeat, and the Compare panes and
/// the git margin would pair lines differently; this keeps the pairing.
/// About sqrt(D) checkpoints of 2d+1 numbers and a segment of sqrt(D) rows of
/// d bits: some 45 MB at D = 100 000, where the trace was 80 GB.
/// `ops` gets '=' (a line of each), '-' (a line of a) and '+' (a line of b).
void NppMyersScript(const int *a, long n, const int *b, long m, long segment, std::vector<char> &ops) {
    ops.clear();
    const long max = n + m;
    if (max == 0) return;
    if (segment <= 0) segment = std::max(64L, (long)std::sqrt(32.0 * (double)max));
    // v[k + off]: the furthest x on diagonal k; step d reads only what step
    // d - 1 wrote, and step 0 reads the 0 on diagonal 1.
    const long off = max + 1;
    std::vector<long> v((size_t)(2 * max + 3), 0);
    std::vector<std::vector<int>> checkpoints;     // before step j*segment: diagonals -(s)..s
    std::vector<std::vector<uint64_t>> rows;       // for the segment in hand: bit (k+d)/2 set = came down from k+1

    // One step d of the forward pass, as the plain algorithm takes it.
    auto step = [&](long d, std::vector<uint64_t> &row) -> bool {
        row.assign((size_t)(d / 64 + 1), 0);
        for (long k = -d; k <= d; k += 2) {
            bool down = k == -d || (k != d && v[(size_t)(k - 1 + off)] < v[(size_t)(k + 1 + off)]);
            long x = down ? v[(size_t)(k + 1 + off)] : v[(size_t)(k - 1 + off)] + 1;
            long y = x - k;
            while (x < n && y < m && a[x] == b[y]) { x++; y++; }
            v[(size_t)(k + off)] = x;
            if (down) row[(size_t)((k + d) / 2 / 64)] |= (uint64_t)1 << (((k + d) / 2) % 64);
            if (x >= n && y >= m) return true;
        }
        return false;
    };
    auto save = [&](long s) {
        std::vector<int> cp((size_t)(2 * s + 3));
        for (long k = -s - 1; k <= s + 1; ++k) cp[(size_t)(k + s + 1)] = (int)v[(size_t)(k + off)];
        checkpoints.push_back(std::move(cp));
    };
    auto restore = [&](long s) {
        const std::vector<int> &cp = checkpoints[(size_t)(s / segment)];
        for (long k = -s - 1; k <= s + 1; ++k) v[(size_t)(k + off)] = cp[(size_t)(k + s + 1)];
    };

    long D = 0;
    for (long d = 0; d <= max; ++d) {
        if (d % segment == 0) { save(d); rows.clear(); }
        rows.emplace_back();
        if (step(d, rows.back())) { D = d; break; }
    }

    // Back from the end, one segment at a time: the diagonal of each step.
    // The rows in hand are those of the segment the forward pass ended in.
    std::vector<long> diagonal((size_t)D + 1);
    diagonal[(size_t)D] = n - m;
    long first = D - D % segment;
    for (long d = D; d > 0; --d) {
        if (d < first) {                            // re-run the segment before from its checkpoint
            first -= segment;
            restore(first);
            rows.clear();
            for (long t = first; t < first + segment; ++t) { rows.emplace_back(); step(t, rows.back()); }
        }
        long k = diagonal[(size_t)d], i = (k + d) / 2;
        bool down = (rows[(size_t)(d - first)][(size_t)(i / 64)] >> (i % 64)) & 1;
        diagonal[(size_t)(d - 1)] = down ? k + 1 : k - 1;
    }

    // Forwards along those diagonals: a move onto each, then its snake.
    long x = 0, y = 0;
    for (long d = 0; d <= D; ++d) {
        if (d > 0) {
            if (diagonal[(size_t)(d - 1)] == diagonal[(size_t)d] + 1) { ops.push_back('+'); y++; }
            else { ops.push_back('-'); x++; }
        }
        while (x < n && y < m && a[x] == b[y]) { ops.push_back('='); x++; y++; }
    }
}

/// Myers' O(ND) difference over the lines as the options see them.
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

    // Myers' O((N+M)D) difference, on whole numbers standing for the lines: a
    // line is hashed and compared once (NppMyersScript).
    const long n = (long)a.count, m = (long)b.count;
    std::vector<int> ai((size_t)n), bi((size_t)m);
    {
        NSMutableDictionary<NSString *, NSNumber *> *ids = [NSMutableDictionary dictionary];
        int next = 0;
        auto idOf = [&](NSString *line) -> int {
            NSNumber *known = ids[line];
            if (known) return known.intValue;
            ids[line] = @(next);
            return next++;
        };
        for (long i = 0; i < n; ++i) ai[(size_t)i] = idOf(a[(NSUInteger)i]);
        for (long i = 0; i < m; ++i) bi[(size_t)i] = idOf(b[(NSUInteger)i]);
    }
    std::vector<char> ops;
    NppMyersScript(ai.data(), n, bi.data(), m, 0, ops);
    NSMutableArray<NppDiffLine *> *result = [NSMutableArray arrayWithCapacity:ops.size()];
    long x = 0, y = 0;
    for (char op : ops) {
        NppDiffLine *line = [[NppDiffLine alloc] init];
        line.kind = op == '=' ? NppDiffSame : op == '-' ? NppDiffRemoved : NppDiffAdded;
        line.oldLine = op == '+' ? -1 : [aIndex[(NSUInteger)x++] integerValue];
        line.newLine = op == '-' ? -1 : [bIndex[(NSUInteger)y++] integerValue];
        [result addObject:line];
    }

    // A run of removals followed by a run of additions is a block of changed
    // lines, paired up as far as both runs go, which is how ComparePlus presents
    // it: two lines edited in a row are two changed lines, not one changed and
    // one added. What is left over in the longer run stays removed or added.
    NSMutableArray<NppDiffLine *> *paired = [NSMutableArray array];
    NSUInteger i = 0;
    while (i < result.count) {
        if (result[i].kind != NppDiffRemoved) { [paired addObject:result[i++]]; continue; }
        NSUInteger r = i;
        while (r < result.count && result[r].kind == NppDiffRemoved) r++;
        NSUInteger a = r;
        while (a < result.count && result[a].kind == NppDiffAdded) a++;
        NSUInteger removed = r - i, added = a - r, pairs = MIN(removed, added);
        for (NSUInteger k = 0; k < pairs; ++k) {
            NppDiffLine *line = result[i + k];
            line.kind = NppDiffChanged;
            line.newLine = result[r + k].newLine;
            [paired addObject:line];
        }
        for (NSUInteger k = pairs; k < removed; ++k) [paired addObject:result[i + k]];
        for (NSUInteger k = pairs; k < added; ++k) [paired addObject:result[r + k]];
        i = a;
    }
    return paired;
}


#pragma mark - State

static const char kFirstToCompareKey = 0;
static const char kFirstDocumentKey = 0;
static const char kComparedDocumentKey = 0;
static const char kCurrentDiffKey = 0;

- (NSString *)firstToCompare { return objc_getAssociatedObject(self, &kFirstToCompareKey); }

/// ComparePlus's Set as First marks a buffer, not a file: an untitled document can be
/// first, and what is compared is its text as it is then, unsaved changes included.
- (void)setFirstToCompare {
    NppDocument *doc = [self mainCurrentDocument];
    if (!doc) { NppBeep(); return; }
    objc_setAssociatedObject(self, &kFirstToCompareKey, doc.path ?: doc.displayName, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(self, &kFirstDocumentKey, doc, OBJC_ASSOCIATION_RETAIN);
}

/// The text of an open document, read through a view of its own (as the agent server
/// does) so the tab in front is not touched.
- (NSString *)textOfOpenDocument:(NppDocument *)doc {
    if (doc == [self mainCurrentDocument]) return [self documentText];
    static ScintillaView *reader;
    if (!reader) reader = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    [reader message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    NSString *text = [reader string] ?: @"";
    [reader message:SCI_SETDOCPOINTER wParam:0 lParam:0];
    return text;
}

/// The line-by-line difference of the last comparison, in the four kinds the
/// port's own callers work with (the git margin, the agent, the revert). The
/// engine's own marks - moved lines, sub-line changes - are in the panes.
- (NSArray<NppDiffLine *> *)currentDiff {
    return objc_getAssociatedObject(self, &kCurrentDiffKey) ?: @[];
}

- (BOOL)compareActive { return gCompare.mismatch && [self secondaryViewVisible]; }

- (BOOL)compareIgnoreCase { return [NppPreferences shared].compareIgnoreCase; }
- (void)setCompareIgnoreCase:(BOOL)v { [NppPreferences shared].compareIgnoreCase = v; [self compareRefreshNow]; }
- (BOOL)compareIgnoreSpaces { return [NppPreferences shared].compareIgnoreSpaces; }
- (void)setCompareIgnoreSpaces:(BOOL)v { [NppPreferences shared].compareIgnoreSpaces = v; [self compareRefreshNow]; }
- (BOOL)compareIgnoreEmptyLines { return [NppPreferences shared].compareIgnoreEmptyLines; }
- (void)setCompareIgnoreEmptyLines:(BOOL)v { [NppPreferences shared].compareIgnoreEmptyLines = v; [self compareRefreshNow]; }
- (BOOL)compareDetectMoves { return [NppPreferences shared].compareDetectMoves; }
- (void)setCompareDetectMoves:(BOOL)v { [NppPreferences shared].compareDetectMoves = v; [self compareRefreshNow]; }
- (BOOL)compareCharDiffs { return [NppPreferences shared].compareCharDiffs; }
- (void)setCompareCharDiffs:(BOOL)v { [NppPreferences shared].compareCharDiffs = v; [self compareRefreshNow]; }

#pragma mark - The revert arrow

/// The system's "undo" symbol as a marker image, in the label colour, once per appearance.
- (void)defineRevertMarker {
    ScintillaView *sci = self.mainSci;
    const int side = 14;
    NSImage *symbol = [NSImage imageWithSystemSymbolName:@"arrow.uturn.backward" accessibilityDescription:nil];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:side pixelsHigh:side bitsPerSample:8
                                                             samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                bytesPerRow:side * 4 bitsPerPixel:32];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSImage *tinted = [symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightBold]];
    NSRect box = NSMakeRect(1, 1, side - 2, side - 2);
    [tinted drawInRect:box fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    CGContextRef cg = NSGraphicsContext.currentContext.CGContext;
    CGContextSetBlendMode(cg, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(cg, [NSColor labelColor].CGColor);
    CGContextFillRect(cg, NSMakeRect(0, 0, side, side));
    [NSGraphicsContext restoreGraphicsState];
    // Scintilla wants rows top down and straight alpha; the bitmap is bottom up and premultiplied.
    NSMutableData *pixels = [NSMutableData dataWithLength:(NSUInteger)(side * side * 4)];
    for (int y = 0; y < side; ++y) {
        unsigned char *out = (unsigned char *)pixels.mutableBytes + (size_t)y * side * 4;
        const unsigned char *in = rep.bitmapData + (size_t)(side - 1 - y) * rep.bytesPerRow;
        for (int x = 0; x < side; ++x) {
            unsigned a = in[x * 4 + 3];
            for (int c = 0; c < 3; ++c) out[x * 4 + c] = a ? (unsigned char)MIN(255u, in[x * 4 + c] * 255u / a) : 0;
            out[x * 4 + 3] = (unsigned char)a;
        }
    }
    [sci message:SCI_RGBAIMAGESETWIDTH wParam:(uptr_t)side lParam:0];
    [sci message:SCI_RGBAIMAGESETHEIGHT wParam:(uptr_t)side lParam:0];
    [sci message:SCI_RGBAIMAGESETSCALE wParam:100 lParam:0];
    [sci message:SCI_MARKERDEFINERGBAIMAGE wParam:NPPMAC_MARKER_REVERT lParam:(sptr_t)pixels.bytes];
    [sci message:SCI_SETMARGINCURSORN wParam:NPPMAC_COMPARE_MARGIN lParam:SC_CURSORARROW];
}

/// An arrow beside every run of the line diff: on its changed and added lines, and on the
/// line after lines that were taken out.
- (void)placeRevertArrows:(NSArray<NppDiffLine *> *)diff {
    ScintillaView *sci = self.mainSci;
    [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_MARKER_REVERT lParam:0];
    long lineCount = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
    BOOL removedPending = NO;
    for (NppDiffLine *line in diff) {
        if (line.kind == NppDiffRemoved) { removedPending = YES; continue; }
        if (line.newLine < 0 || line.newLine >= lineCount) continue;
        if (line.kind != NppDiffSame || removedPending) [sci message:SCI_MARKERADD wParam:(uptr_t)line.newLine lParam:NPPMAC_MARKER_REVERT];
        removedPending = NO;
    }
    if (removedPending && lineCount > 0) [sci message:SCI_MARKERADD wParam:(uptr_t)(lineCount - 1) lParam:NPPMAC_MARKER_REVERT];
}

#pragma mark - Running the engine

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

/// The plugin's compare options, from the port's preferences (setupCompare in Compare.cpp).
- (CompareOptions)compareOptions {
    CompareOptions options;
    options.newFileViewId = MAIN_VIEW;
    options.findUniqueMode = false;
    options.neverMarkIgnored = Settings.NeverMarkIgnored;
    options.detectMoves = self.compareDetectMoves;
    options.detectSubBlockDiffs = Settings.DetectSubBlockDiffs;
    options.detectSubLineMoves = Settings.DetectSubLineMoves && options.detectSubBlockDiffs;
    options.detectCharDiffs = self.compareCharDiffs && options.detectSubBlockDiffs;
    options.ignoreEmptyLines = self.compareIgnoreEmptyLines;
    options.ignoreFoldedLines = false;
    options.ignoreHiddenLines = false;
    options.ignoreChangedSpaces = self.compareIgnoreSpaces;
    options.ignoreAllSpaces = false;
    options.ignoreEOL = true;   // the second pane's text is normalised to LF; endings never differ here
    options.ignoreCase = self.compareIgnoreCase;
    options.bookmarksAsSync = false;
    options.recompareOnChange = true;
    options.changedResemblPercent = Settings.ChangedThresholdPercent;
    options.selectionCompare = false;
    return options;
}

/// The engine over the two panes: its marks and indicators go straight into
/// them. YES when they differ; NO when they match (the panes are then clean).
- (BOOL)runEngine {
    BindViews(self);
    Settings.dark = DarkAppearance();
    setStyles(Settings);
    clearWindow(MAIN_VIEW);
    clearWindow(SUB_VIEW);
    gCompare.summary.clear();
    CompareOptions options = [self compareOptions];
    CompareResult result = compareViews(options, L"Compare", gCompare.summary);
    gCompare.mismatch = result == CompareResult::COMPARE_MISMATCH;
    if (gCompare.mismatch) {
        setCompareView(MAIN_VIEW, true, Settings.colors().blank, Settings.colors().caret_line_transparency);
        setCompareView(SUB_VIEW, true, Settings.colors().blank, Settings.colors().caret_line_transparency);
        [self alignPanes];
    }
    return gCompare.mismatch;
}

/// alignDiffs of Compare.cpp, the whole-document case: blank annotations put
/// each difference at the same height in both panes.
- (void)alignPanes {
    const AlignmentInfo_t &alignmentInfo = gCompare.summary.alignmentInfo;
    const intptr_t maxSize = (intptr_t)alignmentInfo.size();
    CallScintilla(MAIN_VIEW, SCI_ANNOTATIONCLEARALL, 0, 0);
    CallScintilla(SUB_VIEW, SCI_ANNOTATIONCLEARALL, 0, 0);
    const intptr_t mainEndLine = getEndNotEmptyLine(MAIN_VIEW);
    const intptr_t subEndLine = getEndNotEmptyLine(SUB_VIEW);
    bool skipFirst = false;
    intptr_t i = 0;
    // A difference at line 0 cannot be aligned with an annotation (there is no line above it):
    // the two panes are padded at their first lines instead.
    for (; i < maxSize && alignmentInfo[i].main.line <= mainEndLine && alignmentInfo[i].sub.line <= subEndLine; ++i) {
        if (alignmentInfo[i].main.line == 0 || alignmentInfo[i].sub.line == 0) {
            skipFirst = (alignmentInfo[i].main.line == alignmentInfo[i].sub.line);
            continue;
        }
        if (i == 0 || skipFirst) break;
        const intptr_t mismatchLen = getVisibleFromDocLine(MAIN_VIEW, alignmentInfo[i].main.line) -
                                     getVisibleFromDocLine(SUB_VIEW, alignmentInfo[i].sub.line);
        if (mismatchLen > 0) {
            addBlankSection(MAIN_VIEW, alignmentInfo[i].main.line, 1, 1, "");
            addBlankSection(SUB_VIEW, alignmentInfo[i].sub.line, mismatchLen + 1, mismatchLen + 1, "");
        } else if (mismatchLen < 0) {
            addBlankSection(MAIN_VIEW, alignmentInfo[i].main.line, -mismatchLen + 1, -mismatchLen + 1, "");
            addBlankSection(SUB_VIEW, alignmentInfo[i].sub.line, 1, 1, "");
        }
        ++i;
        break;
    }
    for (; i < maxSize && alignmentInfo[i].main.line <= mainEndLine && alignmentInfo[i].sub.line <= subEndLine; ++i) {
        intptr_t previousUnhiddenLine = getPreviousUnhiddenLine(MAIN_VIEW, alignmentInfo[i].main.line);
        if (isLineAnnotated(MAIN_VIEW, previousUnhiddenLine)) clearAnnotation(MAIN_VIEW, previousUnhiddenLine);
        previousUnhiddenLine = getPreviousUnhiddenLine(SUB_VIEW, alignmentInfo[i].sub.line);
        if (isLineAnnotated(SUB_VIEW, previousUnhiddenLine)) clearAnnotation(SUB_VIEW, previousUnhiddenLine);
        if (isLineHidden(MAIN_VIEW, alignmentInfo[i].main.line) || isLineHidden(SUB_VIEW, alignmentInfo[i].sub.line)) continue;
        const intptr_t mismatchLen = getVisibleFromDocLine(MAIN_VIEW, alignmentInfo[i].main.line) -
                                     getVisibleFromDocLine(SUB_VIEW, alignmentInfo[i].sub.line);
        if (mismatchLen > 0) {
            if ((i + 1 < maxSize) && (alignmentInfo[i].sub.line == alignmentInfo[i + 1].sub.line)) continue;
            addBlankSection(SUB_VIEW, alignmentInfo[i].sub.line, mismatchLen);
        } else if (mismatchLen < 0) {
            if ((i + 1 < maxSize) && (alignmentInfo[i].main.line == alignmentInfo[i + 1].main.line)) continue;
            addBlankSection(MAIN_VIEW, alignmentInfo[i].main.line, -mismatchLen);
        }
    }
    // The ends: whichever pane is shorter is padded so both scroll to the same bottom.
    const intptr_t mainEndVisible = getVisibleFromDocLine(MAIN_VIEW, mainEndLine) + getWrapCount(MAIN_VIEW, mainEndLine) - 1;
    const intptr_t subEndVisible = getVisibleFromDocLine(SUB_VIEW, subEndLine) + getWrapCount(SUB_VIEW, subEndLine) - 1;
    const intptr_t mismatchLen = mainEndVisible - subEndVisible;
    const intptr_t absMismatchLen = std::abs(mismatchLen);
    const intptr_t linesOnScreen = CallScintilla(MAIN_VIEW, SCI_LINESONSCREEN, 0, 0);
    const intptr_t endMisalignment = (absMismatchLen < linesOnScreen) ? absMismatchLen : linesOnScreen;
    if (mismatchLen > 0) { clearAnnotation(MAIN_VIEW, mainEndLine); addBlankSectionAfter(SUB_VIEW, subEndLine, endMisalignment); }
    else if (mismatchLen < 0) { clearAnnotation(SUB_VIEW, subEndLine); addBlankSectionAfter(MAIN_VIEW, mainEndLine, endMisalignment); }
}

/// The comparison of the document in front with a text: the text goes into the
/// second pane with the document's language and theme, the engine runs, the
/// line diff is kept for the revert and the callers that want it, the bar
/// comes up, and the first difference is put on screen.
- (BOOL)compareCurrentWithText:(NSString *)other {
    if (![self mainCurrentDocument]) { NppBeep(); return NO; }
    gCompare.otherText = other.UTF8String ?: "";
    NSString *normalised = [[other stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    // The text in a document of the pane's own, over the second view's tabs, never in one of them
    // (ComparePlus opens the other file in the other view; its tabs are left as they are).
    [self beginSecondaryScratch];
    [self.secondarySci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.secondarySci setString:normalised];
    [self.secondarySci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    [self.secondarySci message:SCI_SETREADONLY wParam:1 lParam:0];
    NppDocument *doc = [self mainCurrentDocument];
    [self applyLanguageOfDocument:doc toView:self.secondarySci];
    [self applyThemeToView:self.secondarySci forLanguage:doc.language.name ?: @"normal"];
    [self.secondarySci message:SCI_COLOURISE wParam:0 lParam:-1];
    [self.mainSci message:SCI_COLOURISE wParam:0 lParam:-1];
    [self setSyncVerticalScroll:YES];
    [self defineRevertMarker];

    objc_setAssociatedObject(self, &kComparedDocumentKey, doc, OBJC_ASSOCIATION_ASSIGN);
    BOOL mismatch = [self runEngine];
    NSArray *diff = [EditorController diffBetween:[EditorController linesForComparison:normalised] and:[self linesOfCurrentDocument]
                                       ignoreCase:self.compareIgnoreCase ignoreSpaces:self.compareIgnoreSpaces
                                 ignoreEmptyLines:self.compareIgnoreEmptyLines];
    objc_setAssociatedObject(self, &kCurrentDiffKey, mismatch ? diff : @[], OBJC_ASSOCIATION_RETAIN);
    if (mismatch) [self placeRevertArrows:diff];
    [self setCompareBarShown:YES];
    if (mismatch) [self goToFirstDiff];
    [self refreshChrome];
    return YES;
}

- (BOOL)compareWithFileAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) { NppBeep(); return NO; }
    NSString *other = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                   ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!other) { NppBeep(); return NO; }
    return [self compareCurrentWithText:other];
}

- (BOOL)compareWithFirst {
    NppDocument *firstDoc = objc_getAssociatedObject(self, &kFirstDocumentKey);
    if (firstDoc && [self.documents indexOfObjectIdenticalTo:firstDoc] != NSNotFound) {
        if (firstDoc == [self mainCurrentDocument]) { NppBeep(); return NO; }   // a document against itself
        return [self compareCurrentWithText:[self textOfOpenDocument:firstDoc]];
    }
    // The first one has been closed since: its file, if it had one.
    NSString *first = [self firstToCompare];
    if (!first || ![[NSFileManager defaultManager] fileExistsAtPath:first]) { NppBeep(); return NO; }
    return [self compareWithFileAtPath:first];
}

- (void)clearActiveCompare {
    if ([self secondaryViewVisible] && sciPtr[MAIN_VIEW]) {
        BindViews(self);
        clearWindow(MAIN_VIEW);
        clearWindow(SUB_VIEW);
        setNormalView(MAIN_VIEW);
        setNormalView(SUB_VIEW);
    }
    [self.mainSci message:SCI_MARKERDELETEALL wParam:NPPMAC_MARKER_REVERT lParam:0];
    [self.mainSci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0];
    gCompare.mismatch = false;
    gCompare.summary.clear();
    objc_setAssociatedObject(self, &kCurrentDiffKey, nil, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(self, &kComparedDocumentKey, nil, OBJC_ASSOCIATION_ASSIGN);
    [self setCompareBarShown:NO];
    [self setSyncVerticalScroll:NO];
    [self endSecondaryScratch];   // the view's own tabs come back; with none, it goes
    [self refreshChrome];
}

/// A document being closed: the comparison it is in ends with it (ComparePlus clears a
/// pair when one of its files closes), rather than staying over the next tab.
- (void)compareDocumentWillClose:(NppDocument *)doc {
    if (doc && objc_getAssociatedObject(self, &kComparedDocumentKey) == doc && [self compareBar].superview)
        [self clearActiveCompare];
    if (objc_getAssociatedObject(self, &kFirstDocumentKey) == doc) {
        // The first one stays chosen by its file, if it has one.
        objc_setAssociatedObject(self, &kFirstDocumentKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
}

- (void)clearAllCompares {
    objc_setAssociatedObject(self, &kFirstToCompareKey, nil, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(self, &kFirstDocumentKey, nil, OBJC_ASSOCIATION_RETAIN);
    [self clearActiveCompare];
}

#pragma mark - The bar, Escape, following the typing

static const char kCompareBarKey = 0;
static const char kCompareEscapeKey = 0;
static const char kCompareTimerKey = 0;

- (NSView *)compareBar { return objc_getAssociatedObject(self, &kCompareBarKey); }

/// Built once: the summary on the left, Previous / Next and the close button on the right.
- (NSView *)buildCompareBar {
    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 26)];
    bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    bar.wantsLayer = YES;
    NSTextField *summary = [NSTextField labelWithString:@""];
    summary.translatesAutoresizingMaskIntoConstraints = NO;
    summary.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    summary.textColor = [NSColor secondaryLabelColor];
    summary.lineBreakMode = NSLineBreakByTruncatingTail;
    summary.identifier = @"compareSummary";
    NSButton *(^button)(NSString *, SEL, NSString *) = ^NSButton *(NSString *title, SEL action, NSString *tip) {
        NSButton *b = [NSButton buttonWithTitle:NppL(title) target:self action:action];
        b.identifier = title;
        b.controlSize = NSControlSizeSmall;
        b.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        b.bezelStyle = NSBezelStyleRounded;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        b.toolTip = NppL(tip);
        [b setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        return b;
    };
    NSButton *previous = button(@"◀", @selector(comparePreviousPressed:), @"Previous Difference");
    NSButton *next = button(@"▶", @selector(compareNextPressed:), @"Next Difference");
    NSButton *close = button(@"✕", @selector(compareClosePressed:), @"Clear Active Compare");
    close.keyEquivalent = @"\033";   // Escape, when the bar's window has the keyboard in a pane
    [bar addSubview:summary]; [bar addSubview:previous]; [bar addSubview:next]; [bar addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [summary.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:8],
        [summary.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [summary.trailingAnchor constraintLessThanOrEqualToAnchor:previous.leadingAnchor constant:-8],
        [close.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6],
        [close.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [next.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-10],
        [next.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
        [previous.trailingAnchor constraintEqualToAnchor:next.leadingAnchor constant:-4],
        [previous.centerYAnchor constraintEqualToAnchor:bar.centerYAnchor],
    ]];
    objc_setAssociatedObject(self, &kCompareBarKey, bar, OBJC_ASSOCIATION_RETAIN);
    return bar;
}

- (void)comparePreviousPressed:(id)sender { [self goToDiff:-1]; }
- (void)compareNextPressed:(id)sender { [self goToDiff:1]; }
- (void)compareClosePressed:(id)sender { [self clearActiveCompare]; }

- (void)updateCompareBar {
    NSView *bar = [self compareBar];
    if (!bar) return;
    for (NSView *v in bar.subviews) if ([v.identifier isEqualToString:@"compareSummary"]) ((NSTextField *)v).stringValue = [self compareSummary];
}

/// Shown, the bar takes the top of the host and the pane the rest; hidden, the pane has it all.
- (void)setCompareBarShown:(BOOL)shown {
    NSView *host = [self secondaryHost];
    NSView *bar = [self compareBar] ?: (shown ? [self buildCompareBar] : nil);
    const CGFloat barHeight = 26;
    if (shown) {
        if (bar.superview != host) [host addSubview:bar];
        bar.frame = NSMakeRect(0, NSHeight(host.bounds) - barHeight, NSWidth(host.bounds), barHeight);
        bar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
        self.secondarySci.frame = NSMakeRect(0, 0, NSWidth(host.bounds), NSHeight(host.bounds) - barHeight);
        [self updateCompareBar];
        id monitor = objc_getAssociatedObject(self, &kCompareEscapeKey);
        if (!monitor) {
            // Escape in either pane ends the comparison, as the ✕ does.
            __weak EditorController *weakSelf = self;
            monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
                EditorController *me = weakSelf;
                // Identical texts too: the comparison is on screen as long as its bar is.
                if (!me || event.keyCode != 53 || ![me compareBar].superview) return event;
                NSResponder *first = event.window.firstResponder;
                BOOL inPane = [first isKindOfClass:[NSView class]] &&
                    ([(NSView *)first isDescendantOf:me.mainSci] || [(NSView *)first isDescendantOf:me.secondaryHost]);
                if (!inPane) return event;
                [me clearActiveCompare];
                return nil;
            }];
            objc_setAssociatedObject(self, &kCompareEscapeKey, monitor, OBJC_ASSOCIATION_RETAIN);
        }
    } else {
        [bar removeFromSuperview];
        [self layoutSecondaryHost];
        id monitor = objc_getAssociatedObject(self, &kCompareEscapeKey);
        if (monitor) { [NSEvent removeMonitor:monitor]; objc_setAssociatedObject(self, &kCompareEscapeKey, nil, OBJC_ASSOCIATION_RETAIN); }
    }
}

/// The comparison worked out again over what the document is now, the view
/// where it was (ViewLocation of the plugin): what typing leads to.
- (void)compareRefreshNow {
    if (![self compareBar] || [self compareBar].superview == nil) return;
    if (![self secondaryViewVisible]) return;
    BindViews(self);
    const intptr_t firstLine = getFirstLine(MAIN_VIEW);
    const intptr_t offset = getVisibleFromDocLine(MAIN_VIEW, firstLine) - getFirstVisibleLine(MAIN_VIEW);
    BOOL mismatch = [self runEngine];
    NSString *other = [NSString stringWithUTF8String:gCompare.otherText.c_str()] ?: @"";
    NSArray *diff = [EditorController diffBetween:[EditorController linesForComparison:other] and:[self linesOfCurrentDocument]
                                       ignoreCase:self.compareIgnoreCase ignoreSpaces:self.compareIgnoreSpaces
                                 ignoreEmptyLines:self.compareIgnoreEmptyLines];
    objc_setAssociatedObject(self, &kCurrentDiffKey, mismatch ? diff : @[], OBJC_ASSOCIATION_RETAIN);
    [self placeRevertArrows:mismatch ? diff : @[]];
    if (!mismatch) [self.mainSci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0];
    CallScintilla(MAIN_VIEW, SCI_SETFIRSTVISIBLELINE, getVisibleFromDocLine(MAIN_VIEW, firstLine) - offset, 0);
    [self mirrorScrollToSecondary];
    [self updateCompareBar];
    [self refreshChrome];
}

- (void)compareScheduleRefresh {
    if (![self compareBar] || [self compareBar].superview == nil) return;
    NSTimer *pending = objc_getAssociatedObject(self, &kCompareTimerKey);
    [pending invalidate];
    __weak EditorController *weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *t) { [weakSelf compareRefreshNow]; }];
    objc_setAssociatedObject(self, &kCompareTimerKey, timer, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - The revert

- (BOOL)compareRevertChangeAtLine:(long)line {
    NSArray<NppDiffLine *> *diff = [self currentDiff];
    if (!diff.count) { NppBeep(); return NO; }
    ScintillaView *sci = self.mainSci;
    NSArray<NSString *> *old = [EditorController linesForComparison:[self.secondarySci string] ?: @""];
    NSArray<NSString *> *now = [self linesOfCurrentDocument];
    long lineCount = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0];

    // The runs of the diff: a stretch of differing lines, the new-side lines it covers and the
    // old-side lines that stood there; a pure removal covers no new line and sits before the
    // next unchanged one, where its arrow is.
    NSInteger newFirst = -1, newLast = -1, oldFirst = -1, oldLast = -1, anchor = -1;
    BOOL found = NO;
    NSUInteger i = 0;
    while (i < diff.count && !found) {
        if (diff[i].kind == NppDiffSame) { i++; continue; }
        newFirst = newLast = oldFirst = oldLast = -1;
        NSUInteger j = i;
        for (; j < diff.count && diff[j].kind != NppDiffSame; ++j) {
            NppDiffLine *d = diff[j];
            if (d.newLine >= 0) { if (newFirst < 0) newFirst = d.newLine; newLast = d.newLine; }
            if (d.oldLine >= 0) { if (oldFirst < 0) oldFirst = d.oldLine; oldLast = d.oldLine; }
        }
        anchor = j < diff.count ? diff[j].newLine : (NSInteger)now.count - 1;
        if (newFirst >= 0 ? (line >= newFirst && line <= newLast) : line == anchor) found = YES;
        i = j;
    }
    if (!found) { NppBeep(); return NO; }

    NSString *eol = [self mainCurrentDocument].eolMode == SC_EOL_CRLF ? @"\r\n" : [self mainCurrentDocument].eolMode == SC_EOL_CR ? @"\r" : @"\n";
    NSMutableString *replacement = [NSMutableString string];
    for (NSInteger k = oldFirst; oldFirst >= 0 && k <= oldLast; ++k) [replacement appendFormat:@"%@%@", old[(NSUInteger)k], eol];
    long from, to;
    if (newFirst >= 0) {
        from = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)newFirst lParam:0];
        BOOL endingKept = newLast + 1 < lineCount;
        to = endingKept ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(newLast + 1) lParam:0] : [sci message:SCI_GETLENGTH wParam:0 lParam:0];
        if (!endingKept && [replacement hasSuffix:eol]) [replacement deleteCharactersInRange:NSMakeRange(replacement.length - eol.length, eol.length)];
    } else {
        from = to = anchor < lineCount ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)anchor lParam:0] : [sci message:SCI_GETLENGTH wParam:0 lParam:0];
    }
    NSData *utf8 = [replacement dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
    [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)from lParam:to];
    [sci message:SCI_REPLACETARGET wParam:(uptr_t)utf8.length lParam:(sptr_t)utf8.bytes];
    [sci message:SCI_ENDUNDOACTION wParam:0 lParam:0];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)from lParam:0];

    [self compareRefreshNow];
    return YES;
}


#pragma mark - Summary and navigation

- (NSString *)compareSummary {
    if (![self secondaryViewVisible]) return NppL(@"Nothing has been compared.");
    const CompareSummary &s = gCompare.summary;
    if (!gCompare.mismatch) return NppL(@"The files are identical.");
    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:[NSString stringWithFormat:@"%ld added", (long)s.added]];
    [parts addObject:[NSString stringWithFormat:@"%ld removed", (long)s.removed]];
    if (s.moved) [parts addObject:[NSString stringWithFormat:@"%ld moved", (long)s.moved]];
    [parts addObject:[NSString stringWithFormat:@"%ld changed", (long)s.changed]];
    [parts addObject:[NSString stringWithFormat:@"%ld unchanged", (long)s.match]];
    return [[parts componentsJoinedByString:@", "] stringByAppendingString:@"."];
}

/// The differing lines of the document in front, as the engine marked them.
- (NSArray<NSNumber *> *)markedLines {
    NSMutableArray *lines = [NSMutableArray array];
    if (![self secondaryViewVisible] || !gCompare.mismatch) return lines;
    BindViews(self);
    intptr_t count = getLinesCount(MAIN_VIEW);
    for (intptr_t line = 0; line < count; ++line) {
        line = CallScintilla(MAIN_VIEW, SCI_MARKERNEXT, line, MARKER_MASK_LINE);
        if (line < 0) break;
        [lines addObject:@(line)];
    }
    return lines;
}

/// jumpToNextChange of Compare.cpp, for the pane in front: the next run of
/// marked lines in either pane, the caret put on its first line and the line
/// centred when it is off screen; past the last difference it wraps around.
- (BOOL)goToDiff:(NSInteger)direction {
    if (![self compareActive]) { NppBeep(); return NO; }
    BindViews(self);
    const bool down = direction > 0;
    const int view = [self otherViewHasFocus] ? SUB_VIEW : MAIN_VIEW;
    const int otherView = getOtherViewId(view);
    intptr_t line = getCurrentLine(view);
    // Past the run the caret is in, to its edge.
    const unsigned nextMarker = down ? SCI_MARKERNEXT : SCI_MARKERPREVIOUS;
    intptr_t from = line;
    while (from >= 0 && from < getLinesCount(view) && isLineMarked(view, from, MARKER_MASK_LINE)) from += down ? 1 : -1;
    intptr_t otherFrom = otherViewMatchingLine(view, MAX(0, MIN(from, getLinesCount(view) - 1)));
    while (otherFrom >= 0 && otherFrom < getLinesCount(otherView) && isLineMarked(otherView, otherFrom, MARKER_MASK_LINE)) otherFrom += down ? 1 : -1;
    intptr_t next = (from >= 0 && from < getLinesCount(view)) ? CallScintilla(view, nextMarker, from, MARKER_MASK_LINE) : -1;
    intptr_t otherNext = (otherFrom >= 0 && otherFrom < getLinesCount(otherView)) ? CallScintilla(otherView, nextMarker, otherFrom, MARKER_MASK_LINE) : -1;
    int targetView = view;
    intptr_t target = next;
    if (otherNext >= 0) {
        intptr_t otherAsMine = otherViewMatchingLine(otherView, otherNext);
        // Lines only the other pane has sit under the blank annotation after this pane's
        // line otherAsMine: going down, the stop is the line after that gap, or the caret
        // would stay where it is.
        if (down && otherAsMine <= line) otherAsMine = MIN(otherAsMine + 1, getLinesCount(view) - 1);
        if (next < 0 || (down ? otherAsMine < next : otherAsMine > next)) { target = otherAsMine; }
    }
    if (target < 0) {
        // Wrap around, as the plugin does with WrapAround on.
        return down ? [self goToFirstDiff] : [self goToLastDiff];
    }
    if (!isLineVisible(targetView, target)) centerAt(targetView, target);
    CallScintilla(targetView, SCI_ENSUREVISIBLEENFORCEPOLICY, target, 0);
    CallScintilla(targetView, SCI_SETEMPTYSELECTION, getLineStart(targetView, target), 0);
    [self mirrorScrollToSecondary];
    [self refreshChrome];
    return YES;
}

- (BOOL)goToFirstDiff {
    if (![self compareActive]) { NppBeep(); return NO; }
    BindViews(self);
    intptr_t main = CallScintilla(MAIN_VIEW, SCI_MARKERNEXT, 0, MARKER_MASK_LINE);
    intptr_t sub = CallScintilla(SUB_VIEW, SCI_MARKERNEXT, 0, MARKER_MASK_LINE);
    intptr_t line = main;
    if (sub >= 0) { intptr_t asMain = otherViewMatchingLine(SUB_VIEW, sub); if (line < 0 || asMain < line) line = asMain; }
    if (line < 0) { NppBeep(); return NO; }
    if (!isLineVisible(MAIN_VIEW, line)) centerAt(MAIN_VIEW, line);
    CallScintilla(MAIN_VIEW, SCI_SETEMPTYSELECTION, getLineStart(MAIN_VIEW, line), 0);
    [self mirrorScrollToSecondary];
    [self refreshChrome];
    return YES;
}

- (BOOL)goToLastDiff {
    if (![self compareActive]) { NppBeep(); return NO; }
    BindViews(self);
    intptr_t main = CallScintilla(MAIN_VIEW, SCI_MARKERPREVIOUS, getLinesCount(MAIN_VIEW) - 1, MARKER_MASK_LINE);
    intptr_t sub = CallScintilla(SUB_VIEW, SCI_MARKERPREVIOUS, getLinesCount(SUB_VIEW) - 1, MARKER_MASK_LINE);
    intptr_t line = main;
    if (sub >= 0) { intptr_t asMain = otherViewMatchingLine(SUB_VIEW, sub); if (asMain > line) line = asMain; }
    if (line < 0) { NppBeep(); return NO; }
    if (!isLineVisible(MAIN_VIEW, line)) centerAt(MAIN_VIEW, line);
    CallScintilla(MAIN_VIEW, SCI_SETEMPTYSELECTION, getLineStart(MAIN_VIEW, line), 0);
    [self mirrorScrollToSecondary];
    [self refreshChrome];
    return YES;
}

@end
