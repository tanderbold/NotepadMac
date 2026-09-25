// The built-in suite, what upstream gets from plugins (JSON, Compare, FTP, XML, Run, MIME, Converter, Export, spell check, Markdown), the plugin host and NppExec.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"
#import <WebKit/WebKit.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>

// A navigation as WebKit hands one to the preview's delegate, made up: a link click cannot be
// made without a window server's events, and the delegate reads only these.
@interface NppTestFrame : NSObject
@property (nonatomic) BOOL isMainFrame;
@end
@implementation NppTestFrame
@end
@interface NppTestNavigation : NSObject
@property (nonatomic) NSURLRequest *request;
@property (nonatomic) WKNavigationType navigationType;
@property (nonatomic) NppTestFrame *targetFrame;
@end
@implementation NppTestNavigation
@end

#include <mach/mach.h>
#include <random>
#include <string>
#include <vector>

/// Myers' greedy difference as it was written before the checkpoints: the
/// whole trace kept, then walked back. The reference the new one must equal.
static std::string TraceMyersScript(const std::vector<int> &a, const std::vector<int> &b) {
    const long n = (long)a.size(), m = (long)b.size(), max = n + m;
    if (!max) return "";
    std::vector<long> v((size_t)(2 * max + 1), 0);
    std::vector<std::vector<long>> trace;
    for (long d = 0; d <= max; ++d) {
        std::vector<long> snapshot((size_t)(2 * d + 1));
        for (long k = -d; k <= d; ++k) snapshot[(size_t)(k + d)] = v[(size_t)(k + max)];
        trace.push_back(std::move(snapshot));
        bool end = false;
        for (long k = -d; k <= d; k += 2) {
            long x = (k == -d || (k != d && v[(size_t)(k - 1 + max)] < v[(size_t)(k + 1 + max)])) ? v[(size_t)(k + 1 + max)] : v[(size_t)(k - 1 + max)] + 1;
            long y = x - k;
            while (x < n && y < m && a[(size_t)x] == b[(size_t)y]) { x++; y++; }
            v[(size_t)(k + max)] = x;
            if (x >= n && y >= m) { end = true; break; }
        }
        if (end) break;
    }
    std::string reversed;
    long x = n, y = m;
    for (long d = (long)trace.size() - 1; d >= 0 && (x > 0 || y > 0); --d) {
        const std::vector<long> &vd = trace[(size_t)d];
        auto at = [&](long k) -> long { return (k < -d || k > d) ? 0 : vd[(size_t)(k + d)]; };
        long k = x - y, prevK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
        long prevX = at(prevK), prevY = prevX - prevK;
        while (x > prevX && y > prevY) { reversed += '='; x--; y--; }
        if (d == 0) break;
        if (x > prevX) { reversed += '-'; x--; } else { reversed += '+'; y--; }
    }
    return std::string(reversed.rbegin(), reversed.rend());
}

static uint64_t PhysicalFootprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint;
}

/// == JSON ==; == Compare ==; == FTP ==; == XML ==; == Run ==; == MIME Tools ==; == Converter ==; == Export ==; == Spell check ==
void NppTestsPluginCommands(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"JSON")) { printf("\n== JSON ==\n");
        NppPreferences *p = [NppPreferences shared];
        [ed newDocument];

        // Format: compact input becomes indented, and stays the same document.
        p.jsonIndent = 4;
        SetDoc(ed, @"{\"b\":1,\"a\":[1,2,{\"c\":null}]}");
        BOOL formatted = [ed formatJSONDocument];
        NSString *pretty = DocText(ed);
        Check(@"JSON format", @"compact JSON becomes indented",
              formatted && [pretty containsString:@"\n"] &&
              [pretty containsString:@"    "] && [pretty containsString:@"\"a\""]);

        // Compacting it again must give back an equivalent single line.
        BOOL compacted = [ed compactJSONDocument];
        NSString *tight = DocText(ed);
        Check(@"JSON compact", @"indented JSON becomes one line again",
              compacted && ![tight containsString:@"\n"] && [tight hasPrefix:@"{"] &&
              [tight containsString:@"\"c\":null"]);

        // Round trip: the data must survive both directions.
        NSData *original = [tight dataUsingEncoding:NSUTF8StringEncoding];
        id parsedAgain = [NSJSONSerialization JSONObjectWithData:original options:0 error:NULL];
        Check(@"JSON round trip", @"the value is unchanged by formatting",
              [parsedAgain[@"b"] integerValue] == 1 && [parsedAgain[@"a"] count] == 3);

        // Sorting puts the keys in order.
        SetDoc(ed, @"{\"zeta\":1,\"alpha\":2}");
        [ed sortJSONDocument];
        NSString *sorted = DocText(ed);
        Check(@"JSON sort", @"keys come out in order",
              [sorted rangeOfString:@"alpha"].location < [sorted rangeOfString:@"zeta"].location);

        // Validation reports where the problem is.
        SetDoc(ed, @"{\"ok\": 1}");
        NppJsonError *clean = [ed validateJSONDocument];
        SetDoc(ed, @"{\n  \"ok\": 1,\n  bad\n}");
        NppJsonError *broken = [ed validateJSONDocument];
        Check(@"JSON validate", @"valid passes, invalid reports a line",
              clean == nil && broken != nil && broken.line >= 1 && broken.message.length > 0);

        // Formatting must refuse rather than damage a document that is not JSON.
        SetDoc(ed, @"this is not json at all\n");
        NSString *before = DocText(ed);
        BOOL refused = ![ed formatJSONDocument];
        Check(@"JSON refuses non-JSON", @"a non-JSON document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);
        // What follows a NUL is part of the document: formatting reads it all (a NUL is no JSON, so
        // the format is refused), never the part before the NUL, which would replace everything.
        NSData *(^allBytes)(void) = ^NSData *{
            long n = [ed.sci message:SCI_GETLENGTH];
            return [NSData dataWithBytes:(const char *)[ed.sci message:SCI_GETCHARACTERPOINTER] length:(NSUInteger)n];
        };
        [ed.sci message:SCI_CLEARALL];
        [ed.sci message:SCI_APPENDTEXT wParam:15 lParam:(sptr_t)"{\"a\":1}\0{\"b\":2}"];
        NSData *jsonBefore = allBytes();
        BOOL jsonNulRefused = ![ed formatJSONDocument];
        Check(@"JSON (a NUL inside)", @"a document with a NUL after its first object is refused whole and left as it was",
              jsonNulRefused && [allBytes() isEqualToData:jsonBefore]);

        // The tree lists every node with its path.
        SetDoc(ed, @"{\"top\":{\"inner\":[10,20]}}");
        NSArray *tree = [ed jsonTree];
        NSMutableArray *paths = [NSMutableArray array];
        for (NSDictionary *node in tree) [paths addObject:node[@"path"]];
        Check(@"JSON tree", @"nested paths are reported",
              [paths containsObject:@"top.inner[0]"] && [paths containsObject:@"top.inner[1]"] &&
              [paths containsObject:@"top.inner"]);

        // JSON Viewer's Format keeps the members in the document's order and writes "key": value.
        p.jsonIndent = 2;
        SetDoc(ed, @"{\"zeta\":1,\"alpha\":2,\"mid\":{\"y\":1,\"x\":2},\"l\":[],\"o\":{}}");
        [ed formatJSONDocument];
        NSString *kept = DocText(ed);
        Check(@"JSON format (order)", @"members keep their order, \"key\": value, empty {} and []",
              [kept isEqualToString:@"{\n  \"zeta\": 1,\n  \"alpha\": 2,\n  \"mid\": {\n    \"y\": 1,\n    \"x\": 2\n  },\n  \"l\": [],\n  \"o\": {}\n}"]);
        SetDoc(ed, @"{\"n\": 1.50, \"s\": \"a\\/b \\u00e9 \\ud83d\\ude00\\n\", \"t\": true}");
        [ed compactJSONDocument];
        Check(@"JSON compact (as written)", @"numbers as written, escapes decoded, / not escaped",
              [DocText(ed) isEqualToString:@"{\"n\":1.50,\"s\":\"a/b é 😀\\n\",\"t\":true}"]);
        // RFC 8259, as JSON Viewer: a trailing comma is not JSON, though NSJSONSerialization takes it.
        SetDoc(ed, @"{\"a\":1,}");
        NppJsonError *trailing = [ed validateJSONDocument];
        SetDoc(ed, @"[1,2,]");
        NppJsonError *trailingItem = [ed validateJSONDocument];
        Check(@"JSON validate (trailing comma)", @"a trailing comma is invalid, at its line and column",
              trailing && trailing.line == 0 && trailing.column == 7 && trailingItem && trailingItem.column == 5);
        SetDoc(ed, @"{\"t\":true,\"f\":false,\"n\":null,\"x\":-0.5e3}");
        NSMutableArray *leaves = [NSMutableArray array];
        for (NSDictionary *node in [ed jsonTree]) [leaves addObject:[NSString stringWithFormat:@"%@ = %@", node[@"path"], node[@"value"]]];
        Check(@"JSON tree (literals)", @"true, false, null and numbers as written, keys sorted",
              [leaves isEqualToArray:@[@"{} = {4}", @"f = false", @"n = null", @"t = true", @"x = -0.5e3"]]);
    }

    if (NppSectionWanted(@"Compare")) { printf("\n== Compare ==\n");
        NSArray *oldLines = @[@"alpha", @"beta", @"gamma", @"delta"];
        NSArray *newLines = @[@"alpha", @"BETA", @"gamma", @"delta", @"epsilon"];

        NSArray<NppDiffLine *> *diff = [EditorController diffBetween:oldLines and:newLines
                                                         ignoreCase:NO ignoreSpaces:NO
                                                   ignoreEmptyLines:NO];
        NSUInteger changed = 0, added = 0, same = 0;
        for (NppDiffLine *l in diff) {
            if (l.kind == NppDiffChanged) changed++;
            else if (l.kind == NppDiffAdded) added++;
            else if (l.kind == NppDiffSame) same++;
        }
        Check(@"Compare diff", @"one changed line, one added, three unchanged",
              changed == 1 && added == 1 && same == 3);

        // Ignoring case makes the changed line equal.
        NSArray *ignoringCase = [EditorController diffBetween:oldLines and:newLines
                                                   ignoreCase:YES ignoreSpaces:NO
                                             ignoreEmptyLines:NO];
        NSUInteger stillDifferent = 0;
        for (NppDiffLine *l in ignoringCase) if (l.kind != NppDiffSame) stillDifferent++;
        Check(@"Compare ignore case", @"only the added line remains a difference",
              stillDifferent == 1);

        // Ignoring spaces makes re-indented lines equal.
        {
            NSMutableArray *bigOld = [NSMutableArray arrayWithCapacity:50000];
            for (int i = 0; i < 50000; ++i) [bigOld addObject:@"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"];
            NSMutableArray *bigNew = [bigOld mutableCopy];
            [bigNew addObject:@"new line"];
            NSDate *t0 = [NSDate date];
            NSArray<NppDiffLine *> *bigDiff = [EditorController diffBetween:bigOld and:bigNew ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
            NSTimeInterval took = -t0.timeIntervalSinceNow;
            NSUInteger added = 0; for (NppDiffLine *d in bigDiff) if (d.kind == NppDiffAdded) added++;
            Check(@"Compare (big file)", @"50000 equal lines and one added: one added line, well under a second",
                  added == 1 && bigDiff.lastObject.kind == NppDiffAdded && took < 1.0);
        }
        // The checkpointed walk finds the very path the whole trace did, lines
        // that repeat included (few distinct lines, many ties), whatever the
        // segment length.
        {
            std::mt19937 random(20260925);
            NSUInteger pairs = 0, differing = 0;
            for (int round = 0; round < 3000; ++round) {
                int n = (int)(random() % 40), m = (int)(random() % 40), alphabet = 1 + (int)(random() % 5);
                std::vector<int> a((size_t)n), b((size_t)m);
                for (int &line : a) line = (int)(random() % (unsigned)alphabet);
                for (int &line : b) line = (int)(random() % (unsigned)alphabet);
                if (round % 3 == 0) {                   // a few edits apart, as files usually are
                    b = a;
                    for (int e = (int)(random() % 4); e > 0; --e) {
                        if (!b.empty() && random() % 2) b.erase(b.begin() + (long)(random() % b.size()));
                        else b.insert(b.begin() + (long)(b.empty() ? 0 : random() % b.size()), (int)(random() % (unsigned)alphabet));
                    }
                }
                std::string expected = TraceMyersScript(a, b);
                for (long segment : {1L, 2L, 3L, 7L, 0L}) {
                    std::vector<char> ops;
                    NppMyersScript(a.data(), (long)a.size(), b.data(), (long)b.size(), segment, ops);
                    pairs++;
                    if (std::string(ops.begin(), ops.end()) != expected) differing++;
                }
            }
            Check(@"Compare (same path as before)", @"on 3000 random pairs the edit script equals the whole-trace Myers, at every segment length",
                  pairs == 15000 && differing == 0);
        }
        // Two unrelated texts of 5000 lines (D = 10000): the trace needed
        // D(D+1) numbers, 800 MB, on the main thread; now a few MB.
        {
            NSMutableArray *left = [NSMutableArray array], *right = [NSMutableArray array];
            for (int i = 0; i < 5000; ++i) {
                [left addObject:[NSString stringWithFormat:@"left %d", i]];
                [right addObject:[NSString stringWithFormat:@"right %d", i]];
            }
            uint64_t before = PhysicalFootprint();
            __block uint64_t peak = before;
            __block NSArray<NppDiffLine *> *unrelated = nil;
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            NSDate *t0 = [NSDate date];
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                unrelated = [EditorController diffBetween:left and:right ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
                dispatch_semaphore_signal(done);
            });
            // Sampled while it runs: the peak is what would have hurt.
            while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC))) {
                peak = MAX(peak, PhysicalFootprint());
                if (-t0.timeIntervalSinceNow > 60) break;
            }
            NSTimeInterval took = -t0.timeIntervalSinceNow;
            NSUInteger changedLines = 0; for (NppDiffLine *d in unrelated) if (d.kind == NppDiffChanged) changedLines++;
            printf("  (unrelated 5000 lines: %.2f s, %.0f MB above the start)\n", took, (double)(peak - before) / 1e6);
            Check(@"Compare (unrelated files)", @"two unrelated 5000-line texts: 5000 changed lines, under 100 MB more and 20 s",
                  unrelated.count == 5000 && changedLines == 5000 && peak - before < 100000000ull && took < 20);
        }
        NSArray *spacedDiff = [EditorController diffBetween:@[@"a  b", @"c"]
                                                       and:@[@"a b", @"c"]
                                                ignoreCase:NO ignoreSpaces:YES
                                          ignoreEmptyLines:NO];
        NSUInteger spaceDiffs = 0;
        for (NppDiffLine *l in spacedDiff) if (l.kind != NppDiffSame) spaceDiffs++;
        Check(@"Compare ignore spaces", @"re-spaced lines count as equal", spaceDiffs == 0);

        // Identical input produces no differences at all.
        NSArray *identical = [EditorController diffBetween:oldLines and:oldLines
                                                ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
        NSUInteger anyDiff = 0;
        for (NppDiffLine *l in identical) if (l.kind != NppDiffSame) anyDiff++;
        Check(@"Compare identical", @"identical files differ nowhere",
              anyDiff == 0 && identical.count == oldLines.count);

        // Two lines edited in a row are two changed lines, not one changed and one added; a
        // third new line after them is added; two lines gone before them are removed.
        NSArray *block = [EditorController diffBetween:@[@"a", @"x", @"y", @"b", @"c"] and:@[@"a", @"X", @"Y", @"Z", @"b"]
                                            ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
        NSMutableString *kinds = [NSMutableString string];
        for (NppDiffLine *l in block) [kinds appendFormat:@"%@", l.kind == NppDiffSame ? @"=" : l.kind == NppDiffChanged ? @"C" : l.kind == NppDiffAdded ? @"A" : @"R"];
        Check(@"Compare (blocks pair up)", @"x,y -> X,Y,Z is two changed lines and one added; c gone is one removed",
              [kinds isEqualToString:@"=CCA=R"] && [block[1] newLine] == 1 && [block[2] newLine] == 2 && [block[1] oldLine] == 1 && [block[2] oldLine] == 2);

        // End to end, through the editor.
        NSError *err = nil;
        NSString *oldPath = TempFile(@"cmp_old.txt", @"alpha\nbeta x\ngamma\n");
        NSString *newPath = TempFile(@"cmp_new.txt", @"alpha\nbetta x\ngamma\ndelta\n");
        [ed openFileAtPath:newPath error:&err];
        BOOL ignoreCaseWas = ed.compareIgnoreCase, ignoreSpacesWas = ed.compareIgnoreSpaces, ignoreEmptyWas = ed.compareIgnoreEmptyLines;
        ed.compareIgnoreCase = NO; ed.compareIgnoreSpaces = NO; ed.compareIgnoreEmptyLines = NO;   // the user's own settings aside
        BOOL compared = [ed compareWithFileAtPath:oldPath];
        // The pane with the old file is coloured like the document (its lexer and theme), both
        // sides carry the marks (changed line 2 in both, added line 4 in the new one), and the
        // caret was taken to the first difference.
        [ed.sci message:SCI_COLOURISE wParam:0 lParam:-1];
        long oldSideChanged = [ed.secondarySci message:SCI_MARKERGET wParam:1 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long newSideChanged = [sci message:SCI_MARKERGET wParam:1 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long newSideAdded = [sci message:SCI_MARKERGET wParam:3 lParam:0] & (1 << NPPMAC_MARKER_ADDED);
        long backOld = [ed.secondarySci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT lParam:0];
        long backNew = [sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT lParam:0];
        long fontOld = [ed.secondarySci message:SCI_STYLEGETSIZE wParam:STYLE_DEFAULT lParam:0];
        long fontNew = [sci message:SCI_STYLEGETSIZE wParam:STYLE_DEFAULT lParam:0];
        long caretLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS] lParam:0];
        // Scintilla draws a background marker in the text only if some margin's mask has its bit:
        // the first pane must have Compare's bits in one, or its marks are invisible (they were).
        long maskWithCompare = [sci message:SCI_GETMARGINMASKN wParam:1 lParam:0] & (0xF << 2);
        Check(@"Compare run", @"comparing marks differences on both sides, colours the old pane like the document, and lands on the first difference",
              compared && [ed compareActive] && [ed secondaryViewVisible] &&
              [[ed compareSummary] containsString:@"changed"] &&
              oldSideChanged && newSideChanged && newSideAdded && backOld == backNew && fontOld == fontNew && caretLine == 1 &&
              maskWithCompare == (0xF << 2));

        // The revert arrows beside the differing lines, the bar above the other pane, and what the arrow does:
        // the run at that line goes back to the other side, one undo step, and the comparison is worked out again.
        long arrowMask = 1 << NPPMAC_MARKER_REVERT;
        BOOL arrowsWhereDue = ([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask) && ([sci message:SCI_MARKERGET wParam:3 lParam:0] & arrowMask) &&
                              !([sci message:SCI_MARKERGET wParam:0 lParam:0] & arrowMask) && !([sci message:SCI_MARKERGET wParam:2 lParam:0] & arrowMask);
        BOOL marginShown = [sci message:SCI_GETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0] > 0;
        NSView *bar = [ed compareBar];
        NSTextField *barSummary = nil;
        for (NSView *v in bar.subviews) if ([v.identifier isEqualToString:@"compareSummary"]) barSummary = (NSTextField *)v;
        BOOL barShown = bar.superview == [ed secondaryHost] && [barSummary.stringValue containsString:@"1 changed"];
        BOOL revertedChanged = [ed compareRevertChangeAtLine:1] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\ndelta\n"] &&
                               [barSummary.stringValue containsString:@"0 changed"] && !([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask);
        BOOL noArrowHere = ![ed compareRevertChangeAtLine:0];
        BOOL revertedAdded = [ed compareRevertChangeAtLine:3] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\n"] &&
                             [barSummary.stringValue containsString:@"identical"];
        [sci message:SCI_UNDO wParam:0 lParam:0];
        [sci message:SCI_UNDO wParam:0 lParam:0];
        BOOL undoneBoth = [DocText(ed) isEqualToString:@"alpha\nbetta x\ngamma\ndelta\n"];
        // Typing while the comparison is on: a moment later the marks, the arrows and the summary follow.
        [sci message:SCI_GOTOLINE wParam:2 lParam:0];
        [sci message:SCI_APPENDTEXT wParam:8 lParam:(sptr_t)"epsilon\n"];   // a new last line
        NppSettleUntil(^BOOL{ return ([sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED)) != 0; }, 5);
        BOOL typedFollowed = ([sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED)) && ([sci message:SCI_MARKERGET wParam:4 lParam:0] & arrowMask) &&
                             [barSummary.stringValue containsString:@"2 added"];
        BOOL typedReverted = [ed compareRevertChangeAtLine:4] && [DocText(ed) isEqualToString:@"alpha\nbetta x\ngamma\n"];   // delta and epsilon are one run of added lines
        // A removal's arrow stands on the line after it, and puts the lines back before that line.
        [ed clearAllCompares];
        SetDoc(ed, @"alpha\ngamma\n");
        [ed compareWithFileAtPath:oldPath];
        BOOL removalArrow = ([sci message:SCI_MARKERGET wParam:1 lParam:0] & arrowMask) != 0;
        BOOL revertedRemoval = [ed compareRevertChangeAtLine:1] && [DocText(ed) isEqualToString:@"alpha\nbeta x\ngamma\n"];
        // Escape in a pane ends the comparison, as the ✕ does: the bar and the margin go.
        [ed.window makeFirstResponder:sci];
        NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:ed.window.windowNumber
                                            context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
        [NSApp sendEvent:escape];
        BOOL escaped = ![ed compareActive] && ![ed secondaryViewVisible] && [ed compareBar].superview == nil &&
                       [sci message:SCI_GETMARGINWIDTHN wParam:NPPMAC_COMPARE_MARGIN lParam:0] == 0;
        Check(@"Compare (revert arrows, bar, Escape)", @"arrows stand beside the changed and added lines only; the bar shows the summary; an arrow puts its run back to the other side, one undo step, with the summary and the arrows following; a line typed while comparing is marked a moment later and can be put back; a removal's arrow on the line after puts the lines back; Escape ends the comparison",
              arrowsWhereDue && marginShown && barShown && revertedChanged && noArrowHere && revertedAdded && undoneBoth && typedFollowed && typedReverted && removalArrow && revertedRemoval && escaped);
        [ed openFileAtPath:newPath error:&err];
        SetDoc(ed, @"alpha\nbetta x\ngamma\ndelta\n");   // as the file has it; the tab was edited above
        [ed compareWithFileAtPath:oldPath];

        // The ComparePlus engine's own marks: a moved line found and marked as moved in both panes
        // (not removed and added), the changed characters of a changed line under the indicator,
        // blank annotations that keep both panes at the same height, and the summary counting moves.
        [ed clearAllCompares];
        NSString *movedOld = TempFile(@"cmp_moved_old.txt", @"int a = 1;\nint b = 2;\nint c = 3;\nint d = 4;\nint e = 5;\nint moved = 9;\nint f = 6;\n");
        NSString *movedNew = TempFile(@"cmp_moved_new.txt", @"int moved = 9;\nint a = 1;\nint B = 2;\nint c = 3;\nint added = 0;\nint added2 = 0;\nint d = 4;\nint f = 6;\n");
        [ed openFileAtPath:movedNew error:&err];
        BOOL movesWas = ed.compareDetectMoves, charsWas = ed.compareCharDiffs;
        ed.compareDetectMoves = YES; ed.compareCharDiffs = YES;
        [ed compareWithFileAtPath:movedOld];
        long movedMaskNew = [sci message:SCI_MARKERGET wParam:0 lParam:0] & (1 << NPPMAC_MARKER_MOVED);
        long movedMaskOld = [ed.secondarySci message:SCI_MARKERGET wParam:5 lParam:0] & (1 << NPPMAC_MARKER_MOVED);
        long changedNew = [sci message:SCI_MARKERGET wParam:2 lParam:0] & (1 << NPPMAC_MARKER_CHANGED);
        long addedNew = [sci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_ADDED);
        long removedOld = [ed.secondarySci message:SCI_MARKERGET wParam:4 lParam:0] & (1 << NPPMAC_MARKER_REMOVED);
        // "int B = 2;" against "int b = 2;": the B, and only the B, is under the changed-characters indicator (18).
        long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:2 lParam:0];
        long onB = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 4)];
        long onInt = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)lineStart];
        long onTwo = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 8)];
        // Alignment: "int d = 4;" is line 7 in the new pane and line 4 in the old; with the blank
        // annotations both stand on the same visible line.
        long dNew = [sci message:SCI_VISIBLEFROMDOCLINE wParam:6 lParam:0], dOld = [ed.secondarySci message:SCI_VISIBLEFROMDOCLINE wParam:3 lParam:0];
        long fNew = [sci message:SCI_VISIBLEFROMDOCLINE wParam:7 lParam:0], fOld = [ed.secondarySci message:SCI_VISIBLEFROMDOCLINE wParam:6 lParam:0];
        NSString *movedSummary = [ed compareSummary];
        ed.compareDetectMoves = NO;
        [ed compareRefreshNow];
        long movedWithoutDetection = [sci message:SCI_MARKERGET wParam:0 lParam:0] & ((1 << NPPMAC_MARKER_MOVED) | (1 << NPPMAC_MARKER_ADDED));
        // Character differences off: the plugin still marks the differing words, so B stays marked.
        ed.compareCharDiffs = NO;
        [ed compareRefreshNow];
        long onBWords = [sci message:SCI_INDICATORVALUEAT wParam:18 lParam:(uptr_t)(lineStart + 4)];
        ed.compareDetectMoves = movesWas; ed.compareCharDiffs = charsWas;
        [ed clearAllCompares];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"Compare (ComparePlus engine)", @"a moved line is marked moved on both sides, a changed line's changed characters and nothing else are under the indicator, additions and the removal are marked, both panes are aligned at the same visible lines, the summary counts the move; with Detect Moves off the line is added; with character differences off the differing word is still marked",
              movedMaskNew && movedMaskOld && changedNew && addedNew && removedOld &&
              onB && !onInt && !onTwo && dNew == dOld && fNew == fOld &&
              [movedSummary isEqualToString:@"2 added, 1 removed, 1 moved, 1 changed, 4 unchanged."] &&
              movedWithoutDetection == (1 << NPPMAC_MARKER_ADDED) && onBWords);
        [ed openFileAtPath:newPath error:&err];
        SetDoc(ed, @"alpha\nbetta x\ngamma\ndelta\n");
        [ed compareWithFileAtPath:oldPath];

        // Navigation walks the marked lines.
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        BOOL next = [ed goToDiff:1];
        long firstStop = [sci message:SCI_LINEFROMPOSITION
                               wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        BOOL last = [ed goToLastDiff];
        long lastStop = [sci message:SCI_LINEFROMPOSITION
                              wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"Compare navigation", @"next and last land on marked lines",
              next && last && firstStop > 0 && lastStop >= firstStop);

        // "Set as first" then compare, the way the menu drives it.
        [ed openFileAtPath:oldPath error:&err];
        [ed setFirstToCompare];
        [ed openFileAtPath:newPath error:&err];
        BOOL viaFirst = [ed compareWithFirst];
        Check(@"Compare set first", @"the file set aside is the one compared against",
              viaFirst && [[ed firstToCompare] isEqualToString:oldPath]);

        // ComparePlus compares buffers: the first one's unsaved text, not its file.
        [ed clearAllCompares];
        [ed openFileAtPath:oldPath error:&err];
        NSString *savedOld = DocText(ed);
        SetDoc(ed, @"unsaved first\n");
        [ed setFirstToCompare];
        [ed openFileAtPath:newPath error:&err];
        [ed compareWithFirst];
        Check(@"Compare set first (unsaved)", @"the first document's text as it is now, not as saved",
              [[ed.secondarySci string] isEqualToString:@"unsaved first\n"]);
        [ed clearAllCompares];
        [ed openFileAtPath:oldPath error:&err];
        SetDoc(ed, savedOld);

        // The options re-run a comparison on screen, identical results included.
        ed.compareIgnoreCase = NO; ed.compareIgnoreSpaces = NO; ed.compareIgnoreEmptyLines = NO;
        [ed openFileAtPath:newPath error:&err];
        SetDoc(ed, @"alpha\n");
        [ed compareCurrentWithText:@"ALPHA\n"];
        BOOL differs = [ed compareActive];
        ed.compareIgnoreCase = YES;
        BOOL sameNow = ![ed compareActive];
        ed.compareIgnoreCase = NO;
        Check(@"Compare options re-run", @"Ignore Case makes it identical at once, and off brings the difference back",
              differs && sameNow && [ed compareActive]);

        // Next Difference stops at a removal only the other pane shows (jumpToNextChange).
        SetDoc(ed, @"a\nc\nd\nX\n");
        [ed compareCurrentWithText:@"a\nb\nc\nd\n"];
        [sci message:SCI_GOTOLINE wParam:0 lParam:0];
        [ed goToDiff:1];
        long stop1 = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        [ed goToDiff:1];
        long stop2 = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        Check(@"Compare navigation (removal)", @"the removal is a stop of its own, then the addition",
              stop1 == 1 && stop2 == 3);

        // Closing the compared document ends the comparison.
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];
        Check(@"Compare ends with its document", @"closing the compared document takes the comparison away",
              ![ed secondaryViewVisible] && ![ed compareActive]);

        ed.compareIgnoreCase = ignoreCaseWas; ed.compareIgnoreSpaces = ignoreSpacesWas; ed.compareIgnoreEmptyLines = ignoreEmptyWas;
        [ed clearAllCompares];
        Check(@"Compare clear", @"clearing removes the comparison and the second pane",
              ![ed compareActive] && [ed firstToCompare] == nil && ![ed secondaryViewVisible]);
    }

    if (NppSectionWanted(@"FTP")) { printf("\n== FTP ==\n");
        // The listing parser sees both layouts servers actually send.
        NSString *unixListing =
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 folder\r\n"
            @"-rw-r--r-- 1 owner group      137 Jan  1 00:00 notes.txt\r\n"
            @"lrwxrwxrwx 1 owner group        7 Jan  1 00:00 link -> target\r\n"
            @"drwxr-xr-x 2 owner group     4096 Jan  1 00:00 .\r\n";
        NSArray<NppFtpEntry *> *unix = [NppFtpClient parseListing:unixListing];
        NSMutableDictionary<NSString *, NppFtpEntry *> *byName = [NSMutableDictionary dictionary];
        for (NppFtpEntry *e in unix) byName[e.name] = e;
        NppFtpEntry *folder = byName[@"folder"];
        NppFtpEntry *notes = byName[@"notes.txt"];
        Check(@"FTP listing (unix)",
              @"directories, sizes and symlink names are read correctly",
              unix.count == 3 && folder.isDirectory && !notes.isDirectory &&
              notes.size == 137 && byName[@"link"] != nil);

        NSString *dosListing =
            @"01-01-24  12:00AM       <DIR>          images\r\n"
            @"01-01-24  12:00AM                 2048 report.doc\r\n";
        NSArray<NppFtpEntry *> *dos = [NppFtpClient parseListing:dosListing];
        NppFtpEntry *dosDir = dos.count ? dos[0] : nil;
        NppFtpEntry *dosFile = dos.count > 1 ? dos[1] : nil;
        Check(@"FTP listing (DOS)", @"the other layout is read too",
              dos.count == 2 && dosDir.isDirectory && !dosFile.isDirectory &&
              dosFile.size == 2048);

        // Profiles round-trip through the settings.
        NppFtpProfile *profile = [[NppFtpProfile alloc] init];
        profile.name = @"test-server";
        profile.host = @"127.0.0.1";
        profile.username = @"tester";
        profile.protocol = NppFtpPlain;
        profile.initialDirectory = @"/";
        [ed saveFtpProfile:profile];
        NppFtpProfile *read = [ed ftpProfileNamed:@"test-server"];
        Check(@"FTP profiles", @"a connection is saved and read back",
              read != nil && [read.host isEqualToString:@"127.0.0.1"] &&
              [read.username isEqualToString:@"tester"]);

        Check(@"FTP url", @"the URL carries host, port and path",
              [[read urlForPath:@"dir/file.txt"] isEqualToString:@"ftp://127.0.0.1:21/%2Fdir/file.txt"]);

        // End to end against a real server, started for this test.
        NSString *script = [[NSBundle mainBundle] pathForResource:@"test-ftp-server" ofType:@"py"];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ftproot"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:
            [root stringByAppendingPathComponent:@"sub"]
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"remote hello\n" writeToFile:[root stringByAppendingPathComponent:@"greeting.txt"]
                            atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        NSTask *server = nil;
        NSInteger port = 0;
        if (script) {
            server = [[NSTask alloc] init];
            server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            server.arguments = @[script, root];
            NSPipe *out = [NSPipe pipe];
            server.standardOutput = out;
            if ([server launchAndReturnError:NULL]) {
                // The server prints the port it was given; read just that line.
                NSData *line = [out.fileHandleForReading availableData];
                NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
                NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet]
                                        intoString:NULL];
                [scanner scanInteger:&port];
            }
        }

        if (port <= 0) {
            Check(@"FTP transfer", @"the test server could not be started", NO);
        } else {
            profile.port = port;
            [ed saveFtpProfile:profile];

            BOOL connected = [ed connectToFtpProfile:profile password:@"secret"];
            NSArray<NppFtpEntry *> *listing = connected ? [ed ftpListCurrentDirectory] : nil;
            NSMutableArray *names = [NSMutableArray array];
            for (NppFtpEntry *e in listing) [names addObject:e.name];
            Check(@"FTP connect", @"logging in and listing the directory works",
                  connected && [ed ftpConnected] && [names containsObject:@"greeting.txt"] &&
                  [names containsObject:@"sub"]);

            BOOL opened = [ed openRemoteFileAtPath:@"greeting.txt"];
            Check(@"FTP download", @"a remote file opens in a tab with its contents",
                  opened && [DocText(ed) isEqualToString:@"remote hello\n"] &&
                  [[ed remotePathForCurrentDocument] isEqualToString:@"/greeting.txt"]);

            SetDoc(ed, @"changed here\n");
            BOOL uploaded = [ed uploadCurrentDocument];
            NSString *onServer = [NSString stringWithContentsOfFile:
                [root stringByAppendingPathComponent:@"greeting.txt"]
                                                           encoding:NSUTF8StringEncoding error:NULL];
            Check(@"FTP upload", @"saving sends the file back to where it came from",
                  uploaded && [onServer isEqualToString:@"changed here\n"]);

            BOOL descended = [ed ftpChangeDirectory:@"sub"];
            Check(@"FTP directories", @"changing directory follows the server",
                  descended && [[ed ftpCurrentDirectory] hasSuffix:@"sub"]);

            // NppFTP uploads the file as Save writes it: a UTF-8-BOM document keeps its EF BB BF.
            [ed openRemoteFileAtPath:@"/greeting.txt"];
            ed.currentDocument.encoding = NSUTF8StringEncoding;
            ed.currentDocument.hasBOM = YES;
            SetDoc(ed, @"bom here\n");
            [ed uploadCurrentDocument];
            NSData *bomBytes = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"greeting.txt"]];
            Check(@"FTP upload (BOM)", @"a UTF-8-BOM document is uploaded with its BOM",
                  bomBytes.length > 3 && memcmp(bomBytes.bytes, "\xEF\xBB\xBF" "bom here\n", 12) == 0);
            ed.currentDocument.hasBOM = NO;

            // A file belongs to the server it came from: after connecting to another one, Upload does not
            // send it to the same path there (NppFTP's cache is per profile). It goes where a local file
            // would, into the folder being browsed.
            NSString *rootB = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ftproot_b"];
            [[NSFileManager defaultManager] removeItemAtPath:rootB error:NULL];
            [[NSFileManager defaultManager] createDirectoryAtPath:[rootB stringByAppendingPathComponent:@"incoming"]
                                      withIntermediateDirectories:YES attributes:nil error:NULL];
            [@"B's own\n" writeToFile:[rootB stringByAppendingPathComponent:@"greeting.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            NSTask *serverB = [[NSTask alloc] init];
            serverB.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            serverB.arguments = @[script, rootB];
            NSPipe *outB = [NSPipe pipe];
            serverB.standardOutput = outB;
            NSInteger portB = 0;
            if ([serverB launchAndReturnError:NULL]) {
                NSScanner *scanner = [NSScanner scannerWithString:[[NSString alloc] initWithData:[outB.fileHandleForReading availableData] encoding:NSUTF8StringEncoding] ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL];
                [scanner scanInteger:&portB];
            }
            [ed openRemoteFileAtPath:@"/greeting.txt"];            // from the first server
            NppDocument *fromA = ed.currentDocument;
            [ed disconnectFtp];
            NppFtpProfile *other = [[NppFtpProfile alloc] init];
            other.name = @"test-server-b"; other.host = @"127.0.0.1"; other.port = portB; other.username = @"tester";
            other.protocol = NppFtpPlain; other.initialDirectory = @"/incoming";
            BOOL connectedB = portB > 0 && [ed connectToFtpProfile:other password:@"secret"];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:fromA]];
            NSString *mappedOnB = [ed remotePathForCurrentDocument];
            SetDoc(ed, @"meant for A\n");
            BOOL uploadedB = [ed uploadCurrentDocument];
            NSString *bGreeting = [NSString stringWithContentsOfFile:[rootB stringByAppendingPathComponent:@"greeting.txt"] encoding:NSUTF8StringEncoding error:NULL];
            NSString *bIncoming = [NSString stringWithContentsOfFile:[rootB stringByAppendingPathComponent:@"incoming/greeting.txt"] encoding:NSUTF8StringEncoding error:NULL];
            [ed disconnectFtp];
            [ed connectToFtpProfile:profile password:@"secret"];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:fromA]];
            NSString *mappedOnA = [ed remotePathForCurrentDocument];
            Check(@"FTP upload (another server)", @"after connecting to a second server, a file downloaded from the first is not uploaded over the same path "
                  @"there but into the folder being browsed; back on the first server it knows its path again",
                  connectedB && mappedOnB == nil && uploadedB && [bGreeting isEqualToString:@"B's own\n"] &&
                  [bIncoming isEqualToString:@"meant for A\n"] && [mappedOnA isEqualToString:@"/greeting.txt"]);
            [serverB terminate];
            [[NSFileManager defaultManager] removeItemAtPath:rootB error:NULL];

            // A failed Connect says why, in the transfer's own words.
            NppFtpProfile *dead = [[NppFtpProfile alloc] init];
            dead.name = @"test-dead"; dead.host = @"127.0.0.1"; dead.port = 1; dead.username = @"tester";
            BOOL deadOK = [ed connectToFtpProfile:dead password:@""];
            NSString *why = [ed ftpConnectError];
            Check(@"FTP connect error", @"a refused connection keeps curl's reason for the alert",
                  !deadOK && why.length > 0 && [why.lowercaseString containsString:@"connect"]);

            // SFTP to a port that does not speak SSH gives up (ConnectTimeout) instead of hanging.
            NppFtpProfile *notSSH = [[NppFtpProfile alloc] init];
            notSSH.name = @"test-sftp"; notSSH.host = @"127.0.0.1"; notSSH.port = port; notSSH.username = @"tester";
            notSSH.protocol = NppFtpSFTP;
            NSDate *sftpStart = [NSDate date];
            BOOL sftpOK = [ed connectToFtpProfile:notSSH password:@""];
            NSTimeInterval sftpTook = -sftpStart.timeIntervalSinceNow;
            Check(@"FTP sftp timeout", @"SFTP against a non-SSH port fails within the connect timeout",
                  !sftpOK && sftpTook < 25 && [ed ftpConnectError].length > 0);
            if (sftpTook >= 25) printf("    sftp took %.1fs\n", sftpTook);
            [ed connectToFtpProfile:profile password:@"secret"];

            [ed disconnectFtp];
            Check(@"FTP disconnect", @"disconnecting drops the connection",
                  ![ed ftpConnected] && [ed ftpClient] == nil);

            [server terminate];
        }
        [ed removeFtpProfileNamed:@"test-server"];
    }

    if (NppSectionWanted(@"XML")) { printf("\n== XML ==\n");
        [ed newDocument];
        NSString *compact = @"<?xml version=\"1.0\"?><root a=\"1\" b=\"2\"><item>one</item><item>two</item></root>";

        SetDoc(ed, compact);
        BOOL pretty = [ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        NSString *formatted = DocText(ed);
        Check(@"XML pretty print", @"one line becomes an indented document",
              pretty && [[formatted componentsSeparatedByString:@"\n"] count] > 3 &&
              [formatted containsString:@"    <item>one</item>"]);

        BOOL flat = [ed linearizeXMLDocument];
        NSString *linear = DocText(ed);
        Check(@"XML linearize", @"the indented document becomes one line again",
              flat && ![[linear substringFromIndex:MIN(40u, linear.length)] containsString:@"\n"] &&
              [linear containsString:@"<item>one</item><item>two</item>"]);

        // The value must survive both directions.
        NSArray *items = [EditorController evaluateXPath:@"//item" onText:linear error:NULL];
        Check(@"XML round trip", @"the content is unchanged by formatting",
              items.count == 2 && [items[0] containsString:@"one"]);

        SetDoc(ed, compact);
        [ed prettyPrintXMLDocument:NppXmlPrettyAttributes];
        NSString *attrs = DocText(ed);
        Check(@"XML indent attributes", @"each attribute moves onto its own line",
              [attrs containsString:@"b=\"2\""] &&
              [[attrs componentsSeparatedByString:@"\n"] count] >
              [[formatted componentsSeparatedByString:@"\n"] count]);

        // Syntax: a good document passes, a broken one reports where.
        SetDoc(ed, @"<a><b/></a>");
        NppXmlError *fine = [ed checkXMLSyntaxOfDocument];
        SetDoc(ed, @"<a>\n  <b>\n</a>");
        NppXmlError *broken = [ed checkXMLSyntaxOfDocument];
        Check(@"XML syntax check", @"valid passes and invalid reports a line",
              fine == nil && broken != nil && broken.line >= 0 && broken.message.length > 0);

        // A document that is not XML must be refused, not mangled.
        SetDoc(ed, @"not xml at all");
        NSString *before = DocText(ed);
        BOOL refused = ![ed prettyPrintXMLDocument:NppXmlPrettyDefault];
        Check(@"XML refuses non-XML", @"a non-XML document is left untouched",
              refused && [DocText(ed) isEqualToString:before]);
        // The same for XML: the part before a NUL is not the document.
        [ed.sci message:SCI_CLEARALL];
        [ed.sci message:SCI_APPENDTEXT wParam:15 lParam:(sptr_t)"<a><b/></a>\0<c>"];
        long xmlLength = [ed.sci message:SCI_GETLENGTH];
        BOOL xmlNulRefused = ![ed prettyPrintXMLDocument:NppXmlPrettyDefault] && ![ed linearizeXMLDocument];
        Check(@"XML (a NUL inside)", @"a document with a NUL after its root element is refused whole and left as it was",
              xmlNulRefused && [ed.sci message:SCI_GETLENGTH] == xmlLength && xmlLength == 15);

        // XPath, including an expression that selects attributes.
        NSString *doc = @"<catalog><book id=\"a\"><title>First</title></book>"
                        @"<book id=\"b\"><title>Second</title></book></catalog>";
        NSArray *titles = [EditorController evaluateXPath:@"//title/text()" onText:doc error:NULL];
        NSArray *ids = [EditorController evaluateXPath:@"//book/@id" onText:doc error:NULL];
        NSString *xpathFailure = nil;
        NSArray *bad = [EditorController evaluateXPath:@"//[[" onText:doc error:&xpathFailure];
        Check(@"XML XPath", @"nodes and attributes are selected, and a bad expression reports",
              titles.count == 2 && [titles[1] isEqualToString:@"Second"] &&
              ids.count == 2 && [ids[0] isEqualToString:@"a"] &&
              bad == nil && xpathFailure.length > 0);

        // XSL transformation.
        NSString *sheet =
            @"<?xml version=\"1.0\"?>"
            @"<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            @"<xsl:output method=\"xml\"/>"
            @"<xsl:template match=\"/\"><titles><xsl:for-each select=\"//title\">"
            @"<t><xsl:value-of select=\".\"/></t></xsl:for-each></titles></xsl:template>"
            @"</xsl:stylesheet>";
        NSString *xslFailure = nil;
        NSString *transformed = [EditorController applyXSL:sheet toText:doc error:&xslFailure];
        Check(@"XML XSL", @"a stylesheet produces the expected output",
              transformed != nil && [transformed containsString:@"<t>First</t>"] &&
              [transformed containsString:@"<t>Second</t>"]);

        // XSD validation, which NSXMLDocument cannot do and libxml2 can.
        NSString *schema =
            @"<?xml version=\"1.0\"?>"
            @"<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
            @"<xs:element name=\"note\"><xs:complexType><xs:sequence>"
            @"<xs:element name=\"to\" type=\"xs:string\"/>"
            @"</xs:sequence></xs:complexType></xs:element></xs:schema>";
        NppXmlError *matches = [EditorController validateXML:@"<note><to>you</to></note>"
                                               againstSchema:schema];
        NppXmlError *mismatch = [EditorController validateXML:@"<note><wrong>x</wrong></note>"
                                                againstSchema:schema];
        Check(@"XML schema validation", @"a matching document passes and a wrong one is reported",
              matches == nil && mismatch != nil && mismatch.message.length > 0);

        // Escaping a selection, and putting it back.
        SetDoc(ed, @"a <b> & \"c\"");
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:YES];
        NSString *escaped = DocText(ed);
        [sci message:SCI_SETSEL wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
        [ed escapeSelectionForXML:NO];
        Check(@"XML escaping", @"characters are escaped and restored exactly",
              [escaped containsString:@"&lt;b&gt;"] && [escaped containsString:@"&amp;"] &&
              [DocText(ed) isEqualToString:@"a <b> & \"c\""]);

        // The path at the caret, which has to work on a document still being typed.
        SetDoc(ed, @"<root>\n  <list>\n    <item>one</item>\n    <item>tw");
        [sci message:SCI_GOTOPOS wParam:(uptr_t)[sci message:SCI_GETLENGTH] lParam:0];
        NSString *plainPath = [ed xmlPathAtCaretWithPredicates:NO];
        NSString *indexedPath = [ed xmlPathAtCaretWithPredicates:YES];
        Check(@"XML current path", @"the path is reported while the document is incomplete",
              [plainPath isEqualToString:@"/root/list/item"] &&
              [indexedPath isEqualToString:@"/root[1]/list[1]/item[2]"]);
    }

    if (NppSectionWanted(@"Run")) { printf("\n== Run ==\n");
        // Run hands a program over and leaves it going (Command::run, ShellExecute): one that takes
        // longer than half a minute is not stopped. Started first, looked at last.
        __block NppRunResult *longRun = nil;
        [ed runCommandLineInBackground:@"sleep 32; echo still-running" completion:^(NppRunResult *r) { longRun = r; }];
        NSDate *longStart = [NSDate date];
        // The variables are read off a real document, so the test exercises the
        // same path the menu command does.
        NSString *runPath = TempFile(@"npp_run_test.txt", @"alpha beta\nsecond line\n");
        [ed openFileAtPath:runPath error:NULL];
        ScintillaView *sci = ed.sci;
        [sci message:SCI_GOTOPOS wParam:6 lParam:0];    // inside "beta" on line 0

        NSString *dir = runPath.stringByDeletingLastPathComponent;
        BOOL paths =
            [[ed expandRunVariables:@"$(FULL_CURRENT_PATH)"] isEqualToString:runPath] &&
            [[ed expandRunVariables:@"$(CURRENT_DIRECTORY)"] isEqualToString:dir] &&
            [[ed expandRunVariables:@"$(FILE_NAME)"] isEqualToString:@"npp_run_test.txt"] &&
            [[ed expandRunVariables:@"$(NAME_PART)"] isEqualToString:@"npp_run_test"];
        BOOL caret =
            [[ed expandRunVariables:@"$(CURRENT_WORD)"] isEqualToString:@"beta"] &&
            // A value with a space in it is quoted, so the shell keeps it whole.
            [[ed expandRunVariables:@"$(CURRENT_LINESTR)"] isEqualToString:@"'alpha beta'"] &&
            [[ed expandRunVariables:@"$(CURRENT_LINE)"] isEqualToString:@"0"] &&
            [[ed expandRunVariables:@"$(CURRENT_COLUMN)"] isEqualToString:@"6"];
        BOOL npp =
            [[ed expandRunVariables:@"$(NPP_FULL_FILE_PATH)"] containsString:@"NotepadMac"] &&
            [ed expandRunVariables:@"$(NPP_DIRECTORY)"].length > 0;
        Check(@"Run variables", @"every substitution Notepad++ makes is made here too",
              paths && caret && npp);

        // Windows keeps the dot on the extension, and gives nothing when there
        // is none; both halves of that are easy to get wrong.
        NSString *withExt = [ed expandRunVariables:@"$(EXT_PART)"];
        NSString *plainPath = TempFile(@"npp_run_plain", @"x\n");
        [ed openFileAtPath:plainPath error:NULL];
        NSString *withoutExt = [ed expandRunVariables:@"$(EXT_PART)"];
        Check(@"Run extension part", @"the extension keeps its dot, and is empty when absent",
              [withExt isEqualToString:@".txt"] && withoutExt.length == 0);

        // A name that is not a variable belongs to the shell, so it must come
        // out untouched rather than being swallowed.
        [ed openFileAtPath:runPath error:NULL];
        Check(@"Run leaves unknown names", @"an unknown or unclosed variable is left as written",
              [[ed expandRunVariables:@"$(NOT_A_VARIABLE) $(FILE_NAME)"]
                  isEqualToString:@"$(NOT_A_VARIABLE) npp_run_test.txt"] &&
              [[ed expandRunVariables:@"$(unclosed"] isEqualToString:@"$(unclosed"] &&
              [[ed expandRunVariables:@"cost is $5"] isEqualToString:@"cost is $5"]);

        NppRunResult *echoed = [ed runCommandLine:@"echo $(NAME_PART)" intoConsole:NO];
        Check(@"Run command", @"the command runs with its variables already substituted",
              echoed.exitStatus == 0 &&
              [echoed.output isEqualToString:@"npp_run_test\n"]);

        // Failure has to be visible: the status and whatever went to stderr.
        NppRunResult *failed = [ed runCommandLine:@"echo oops >&2; exit 3" intoConsole:NO];
        Check(@"Run reports failure", @"a non-zero status and stderr both come back",
              failed.exitStatus == 3 && [failed.output containsString:@"oops"]);

        // A command is nearly always meant relative to the file being edited.
        NppRunResult *where = [ed runCommandLine:@"pwd" intoConsole:NO];
        Check(@"Run working directory", @"the command runs in the document's own directory",
              [[where.output stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]].stringByResolvingSymlinksInPath
                  isEqualToString:dir.stringByResolvingSymlinksInPath]);

        [ed.console clear];
        NppRunResult *shown = [ed runCommandLine:@"echo visible" intoConsole:YES];
        NSString *console = ed.console.text;
        Check(@"Run console", @"the command and its output both reach the console",
              shown.exitStatus == 0 && [console containsString:@"> echo visible"] &&
              [console containsString:@"visible\n"]);

        [ed.console clear];
        [ed runCommandLine:@"exit 7" intoConsole:YES];
        Check(@"Run console reports status", @"a failure is written to the console, not just returned",
              [ed.console.text containsString:@"exit status 7"]);

        // The background path expands on the main thread and hands the result
        // to the worker; expanding a second time there would corrupt a command
        // whose own text happens to look like a variable.
        SetDoc(ed, @"$(FILE_NAME)\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        __block NppRunResult *async = nil;
        [ed runCommandLineInBackground:@"echo '$(CURRENT_LINESTR)'"
                            completion:^(NppRunResult *r) { async = r; }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!async && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        Check(@"Run in background", @"it completes, and substitution happens exactly once",
              async != nil && async.exitStatus == 0 &&
              [async.output isEqualToString:@"$(FILE_NAME)\n"]);

        // A command that leaves a child in the background is over when the shell is: the child
        // holds the pipe open, and waiting for its end would wait for the child.
        [ed.console clear];
        __block NppRunResult *leaving = nil;
        NSDate *leaveStart = [NSDate date];
        [ed runCommandLineInBackground:@"(sleep 4; echo late-output) & echo right-away"
                            completion:^(NppRunResult *r) { leaving = r; }];
        NppSettleUntil(^BOOL { return leaving != nil; }, 10);
        NSTimeInterval leaveTook = -[leaveStart timeIntervalSinceNow];
        NppSettleUntil(^BOOL { return [ed.console.text containsString:@"late-output"]; }, 10);
        Check(@"Run (a child left in the background)", @"the command is finished as soon as its shell is, with what it wrote; "
              @"what the child writes later still reaches the console",
              leaving != nil && leaveTook < 3 && leaving.exitStatus == 0 && [leaving.output isEqualToString:@"right-away\n"] &&
              [ed.console.text containsString:@"late-output"]);

        // Saved commands are keyed by name, so saving the same name again
        // replaces it rather than adding a duplicate.
        NSUInteger before = [ed savedCommands].count;
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make"]];
        [ed saveCommand:[NppSavedCommand commandWithName:@"Build" command:@"make -j8"]];
        NSArray<NppSavedCommand *> *saved = [ed savedCommands];
        NppSavedCommand *build = nil;
        for (NppSavedCommand *c in saved) if ([c.name isEqualToString:@"Build"]) build = c;
        BOOL replaced = saved.count == before + 1 && [build.command isEqualToString:@"make -j8"];
        [ed removeSavedCommandNamed:@"Build"];
        Check(@"Run saved commands", @"saving by name replaces, and removing takes it away",
              replaced && [ed savedCommands].count == before);

        NppSettleUntil(^BOOL { return longRun != nil; }, 45 + [longStart timeIntervalSinceNow]);
        Check(@"Run (no time limit)", @"a program running for longer than 30 s is left to finish",
              longRun != nil && !longRun.timedOut && longRun.exitStatus == 0 && [longRun.output isEqualToString:@"still-running\n"]);
        [[NSFileManager defaultManager] removeItemAtPath:runPath error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:plainPath error:NULL];
    }

    if (NppSectionWanted(@"MIME Tools")) { printf("\n== MIME Tools ==\n");
        // Quoted-printable: UTF-8 bytes escape as =XX, '=' itself must escape,
        // and encode/decode round-trips, soft breaks (=\r\n at column 76) included.
        NSString *qp = [EditorController mimeQuotedPrintableEncode:@"Ünïcödé = fun\n"];
        Check(@"MIME Quoted-printable encode", @"non-ASCII and '=' become =XX, the rest stays",
              [qp isEqualToString:@"=C3=9Cn=C3=AFc=C3=B6d=C3=A9 =3D fun\n"]);
        NSMutableString *longLine = [NSMutableString string];
        for (int i = 0; i < 120; ++i) [longLine appendString:@"x"];
        NSString *qpLong = [EditorController mimeQuotedPrintableEncode:longLine];
        NSArray *qpLines = [qpLong componentsSeparatedByString:@"\r\n"];
        BOOL qpWrapped = qpLines.count > 1;
        for (NSString *l in qpLines) qpWrapped = qpWrapped && l.length <= 76;
        Check(@"MIME Quoted-printable soft break", @"long lines wrap with =CRLF within 76 columns",
              qpWrapped && [[EditorController mimeQuotedPrintableDecode:qpLong] isEqualToString:longLine]);
        Check(@"MIME Quoted-printable decode", @"=XX and soft breaks come back; bad hex is refused",
              [[EditorController mimeQuotedPrintableDecode:qp] isEqualToString:@"Ünïcödé = fun\n"] &&
              [[EditorController mimeQuotedPrintableDecode:@"a=\nb=\r\nc"] isEqualToString:@"abc"] &&
              [EditorController mimeQuotedPrintableDecode:@"=ZZ"] == nil);

        // URL encoding in the plugin's three strengths (url.cpp).
        Check(@"MIME URL encode (RFC1738)", @"unsafe characters and non-ASCII encode, the RFC's allowed marks stay",
              [[EditorController mimeUrlEncode:@"a b&c(d)é" method:NppUrlEncodeRFC1738 byLine:NO]
               isEqualToString:@"a%20b%26c(d)%C3%A9"]);
        Check(@"MIME URL encode (Extended)", @"the common implementations' extra marks encode too",
              [[EditorController mimeUrlEncode:@"a(d)+x" method:NppUrlEncodeExtended byLine:NO]
               isEqualToString:@"a%28d%29%2Bx"]);
        Check(@"MIME URL encode (Full)", @"every byte becomes a triplet",
              [[EditorController mimeUrlEncode:@"Ab" method:NppUrlEncodeFull byLine:NO] isEqualToString:@"%41%62"]);
        Check(@"MIME URL encode by line", @"line breaks survive un-encoded",
              [[EditorController mimeUrlEncode:@"a b\nc d" method:NppUrlEncodeRFC1738 byLine:YES]
               isEqualToString:@"a%20b\nc%20d"]);
        Check(@"MIME URL decode", @"triplets decode; '+' and stray '%' pass through as written",
              [[EditorController mimeUrlDecode:@"a%20b%26c%C3%A9"] isEqualToString:@"a b&céé"] == NO &&
              [[EditorController mimeUrlDecode:@"a%20b%26c%C3%A9"] isEqualToString:@"a b&cé"] &&
              [[EditorController mimeUrlDecode:@"1+1%3D2 and 100%"] isEqualToString:@"1+1=2 and 100%"]);

        // SAML: the deflated+Base64+URL-encoded request the redirect binding
        // carries (vector made with zlib raw deflate), and a plain Base64 XML.
        NSString *redirect = @"sylOzM0psHIsLcnIC0otLE0tLlHwdLFVqjBUsstIzcnJt9HHVGEHAA%3D%3D";
        Check(@"MIME SAML decode", @"URL-decode, Base64 and raw inflate give the request back",
              [[EditorController mimeSamlDecode:redirect]
               isEqualToString:@"<samlp:AuthnRequest ID=\"x1\">hello</samlp:AuthnRequest>"] &&
              [[EditorController mimeSamlDecode:@"PD94bWwgdmVyc2lvbj0iMS4wIj8+"] hasPrefix:@"<?xml"] &&
              [EditorController mimeSamlDecode:@"zzz"] == nil);

        // Through the selection: encode in place, one undo step brings the text back.
        [ed newDocument];
        SetDoc(ed, @"foobar");
        [sci message:SCI_SETSEL wParam:0 lParam:6];
        BOOL did = [ed mimeTransformSelection:^NSString *(NSString *text) {
            return [EditorController mimeUrlEncode:text method:NppUrlEncodeFull byLine:NO];
        }];
        NSString *encoded = DocText(ed);
        [sci message:SCI_UNDO wParam:0 lParam:0];
        Check(@"MIME Tools on the selection", @"the selection is replaced in place and one undo returns it",
              did && [encoded isEqualToString:@"%66%6F%6F%62%61%72"] && [DocText(ed) isEqualToString:@"foobar"]);

        // Several selections, and a rectangular one: the text given is all of them, as
        // SCI_GETSELTEXT copies it (each range with a line end after it), however long.
        {
            NSMutableString *many = [NSMutableString string];
            for (int i = 0; i < 40; ++i) [many appendString:@"abc xyz\n"];
            SetDoc(ed, many);
            [sci message:SCI_SETSELECTION wParam:0 lParam:3];
            for (long i = 1; i < 40; ++i) [sci message:SCI_ADDSELECTION wParam:(uptr_t)(i * 8) lParam:i * 8 + 3];
            __block NSString *given = nil;
            [ed mimeTransformSelection:^NSString *(NSString *text) { given = text; return nil; }];
            long expectMulti = [sci message:SCI_GETSELTEXT wParam:0 lParam:0];
            [sci message:SCI_SETRECTANGULARSELECTIONANCHOR wParam:4];
            [sci message:SCI_SETRECTANGULARSELECTIONCARET wParam:39 * 8 + 7];
            __block NSString *givenRect = nil;
            [ed mimeTransformSelection:^NSString *(NSString *text) { givenRect = text; return nil; }];
            printf("    MIME selections: %lu of %ld, rectangle %lu\n", (unsigned long)given.length, expectMulti, (unsigned long)givenRect.length);
            Check(@"MIME Tools on several selections", @"every selected range is what the conversion is given, a rectangle's rows too",
                  given.length == 40 * 4 && [given hasPrefix:@"abc\nabc\n"] && (long)given.length == expectMulti &&
                  givenRect.length == 40 * 4 && [givenRect hasPrefix:@"xyz\nxyz\n"]);
        }
    }

    if (NppSectionWanted(@"Converter")) { printf("\n== Converter ==\n");
        // ascii2hex, with the plugin's three settings.
        Check(@"Converter ASCII -> HEX", @"bytes become pairs; space and case options hold",
              [[EditorController converterHexFromText:@"AB" insertSpace:NO uppercase:NO charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"4142"] &&
              [[EditorController converterHexFromText:@"AB" insertSpace:YES uppercase:NO charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"41 42 "] &&   // the plugin leaves the trailing space too
              [[EditorController converterHexFromText:@"j" insertSpace:NO uppercase:YES charactersPerLine:0 eol:@"\n"]
               isEqualToString:@"6A"]);
        Check(@"Converter ASCII -> HEX per line", @"a break lands after every N-th source byte",
              [[EditorController converterHexFromText:@"ABCD" insertSpace:YES uppercase:NO charactersPerLine:2 eol:@"\n"]
               isEqualToString:@"41 42\n43 44\n"]);

        // hex2Ascii: the format is read off the third character and must hold.
        Check(@"Converter HEX -> ASCII", @"plain and spaced input decode; UTF-8 comes back as text",
              [[EditorController converterTextFromHex:@"4142"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"41 42"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"41\n42"] isEqualToString:@"AB"] &&
              [[EditorController converterTextFromHex:@"D0AF"] isEqualToString:@"Я"]);
        Check(@"Converter HEX -> ASCII refusals", @"odd digits, stray characters and a broken format are refused",
              [EditorController converterTextFromHex:@"414"] == nil &&
              [EditorController converterTextFromHex:@"41 4243"] == nil &&
              [EditorController converterTextFromHex:@"4Z"] == nil &&
              [EditorController converterTextFromHex:@"4"] == nil);

        // The Conversion Panel's model.
        NSDictionary *fromHex = [EditorController converterValues:@"ff" fromField:@"hex"];
        NSDictionary *fromAscii = [EditorController converterValues:@"A" fromField:@"ascii"];
        Check(@"Conversion Panel values", @"one value fills every base and the character",
              [fromHex[@"dec"] isEqualToString:@"255"] && [fromHex[@"bin"] isEqualToString:@"11111111"] &&
              [fromHex[@"oct"] isEqualToString:@"377"] && [fromHex[@"ascii"] isEqualToString:@"ÿ"] &&
              [fromAscii[@"dec"] isEqualToString:@"65"] &&
              [[EditorController converterValues:@"1010" fromField:@"bin"][@"dec"] isEqualToString:@"10"] &&
              [EditorController converterValues:@"12a" fromField:@"dec"] == nil &&
              [[EditorController converterValues:@"" fromField:@"dec"][@"hex"] isEqualToString:@""]);

        // The panel itself: typing syncs the rows, Insert writes to the document.
        [app showConversionPanel:nil];
        NppConverterWindow *cw = [NppConverterWindow shared];
        [ed newDocument];
        SetDoc(ed, @"");
        cw.hex.stringValue = @"ff";
        [cw syncFrom:cw.hex];
        NSButton *fake = [[NSButton alloc] init];
        fake.tag = 1;   // the Decimal row
        [NSApp sendAction:@selector(insertRow:) to:cw from:fake];
        Check(@"Conversion Panel window", @"typing hex ff shows 255, and Insert writes it at the caret",
              [cw.dec.stringValue isEqualToString:@"255"] && [cw.bin.stringValue isEqualToString:@"11111111"] &&
              [DocText(ed) isEqualToString:@"255"]);
        [cw.panel orderOut:nil];
    }

    if (NppSectionWanted(@"Export")) { printf("\n== Export ==\n");
        NSError *err = nil;
        [ed openFileAtPath:TempFile(@"t_export.py", @"# comment <>&\nx = 1 # Я\n") error:&err];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];

        NSRange whole = [ed exportRange];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:9];
        NSRange part = [ed exportRange];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];
        Check(@"Export range", @"the selection when there is one, the whole document otherwise",
              whole.location == 0 && whole.length == (NSUInteger)[ed.sci message:SCI_GETLENGTH] &&
              part.location == 0 && part.length == 9);

        NSString *html = [ed exportHTMLInRange:whole];
        NSUInteger colourCount = [html componentsSeparatedByString:@"color:#"].count;
        Check(@"Export to HTML", @"a pre in the editor's colours, spans per style, markup escaped",
              [html containsString:@"<pre style="] &&
              [html containsString:@"&lt;&gt;&amp;"] &&
              [html containsString:@"</span>"] && colourCount > 2);
        Check(@"Export to HTML (UTF-8)", @"non-ASCII text stays itself, not one character per byte",
              [html containsString:@"# Я"] && ![html containsString:@"Ð"]);

        NSData *rtfData = [ed exportRTFInRange:whole];
        NSString *rtf = [[NSString alloc] initWithData:rtfData encoding:NSASCIIStringEncoding];
        Check(@"Export to RTF", @"a colour table, style runs, par lines and \\u for non-ASCII",
              [rtf hasPrefix:@"{\\rtf1"] && [rtf containsString:@"\\colortbl"] &&
              [rtf containsString:@"\\cf"] && [rtf containsString:@"\\par"] &&
              [rtf containsString:@"\\u1071?"]);
        NSAttributedString *readBack = [[NSAttributedString alloc] initWithRTF:rtfData
                                                            documentAttributes:nil];
        Check(@"Export RTF reads back", @"the system RTF reader returns the very text",
              [readBack.string containsString:@"# comment <>&"] &&
              [readBack.string containsString:@"x = 1 # Я"]);

        [ed exportToClipboardRTF:YES HTML:YES];
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        Check(@"Export to the clipboard", @"RTF, HTML and the plain text ride together",
              [pb dataForType:NSPasteboardTypeRTF].length > 0 &&
              [[pb stringForType:NSPasteboardTypeHTML] containsString:@"<pre"] &&
              [[pb stringForType:NSPasteboardTypeString] containsString:@"x = 1"]);

        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }

    if (NppSectionWanted(@"Spell check")) { printf("\n== Spell check ==\n");
        NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
        NSRange probe = [checker checkSpellingOfString:@"helo" startingAt:0 language:@"en"
                                                  wrap:NO inSpellDocumentWithTag:0 wordCount:NULL];
        if (probe.location != 0) {
            // No dictionaries to judge with (a stripped-down runner): the
            // machinery cannot be exercised honestly, and that is said aloud.
            printf("  note: the spelling engine offers no English here; spell checks not exercised\n");
        } else {
            NppPreferences *prefs = [NppPreferences shared];
            BOOL wasOn = prefs.spellCheckEnabled;
            NSString *wasLang = prefs.spellCheckLanguage;
            prefs.spellCheckEnabled = YES;
            prefs.spellCheckLanguage = @"en";

            [ed newDocument];
            SetDoc(ed, @"helo wrld\n");
            [ed spellCheckNow];
            Check(@"Spell check squiggles", @"misspelled words carry the indicator, in plain text everywhere",
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1] &&
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:6]);

            // Automatic language: the engine must work the language out by
            // itself. checkSpellingOfString:language:nil quietly kept the
            // checker's old language, so a foreign text went unchecked - the
            // very way the bug was reported.
            NSString *french = @"bonjur le monde sa marche tres bien";
            checker.automaticallyIdentifiesLanguages = YES;
            NSArray *frProbe = [checker checkString:french range:NSMakeRange(0, french.length)
                                              types:NSTextCheckingTypeSpelling options:nil
                             inSpellDocumentWithTag:0 orthography:NULL wordCount:NULL];
            if (frProbe.count) {
                prefs.spellCheckLanguage = @"";
                SetDoc(ed, @"bonjur le monde\n");
                [ed spellCheckNow];
                Check(@"Spell check automatic language", @"a French misspelling is found with no language chosen",
                      [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1]);
                prefs.spellCheckLanguage = @"en";
            } else {
                printf("  note: no French dictionary here; the automatic-language check not exercised\n");
            }

            NSError *err = nil;
            [ed openFileAtPath:TempFile(@"t_spell.py", @"wrld = 1  # helo wrld\n") error:&err];
            [ed spellCheckNow];
            Check(@"Spell check styles", @"in code only comments and strings are checked, identifiers are left alone",
                  ![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:1] &&
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:13]);
            [ed openFileAtPath:TempFile(@"t_spell2.py", @"s = 'speling'\nt = \"\"\"speling\"\"\"\n") error:&err];
            [ed spellCheckNow];
            Check(@"Spell check styles (Python)", @"single- and triple-quoted Python strings are checked too",
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:6] &&
                  [sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:21]);
            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];

            NSArray<NSMenuItem *> *offers = [ed spellingMenuItemsForPosition:13];
            BOOL hasIgnore = NO, hasLearn = NO;
            NSMenuItem *ignoreItem = nil;
            for (NSMenuItem *item in offers) {
                if (item.action == @selector(spellIgnoreWord:)) { hasIgnore = YES; ignoreItem = item; }
                if (item.action == @selector(spellLearnWord:)) hasLearn = YES;
            }
            Check(@"Spell check suggestions", @"the context menu gets guesses, Ignore and Learn for the word",
                  offers.count >= 4 && hasIgnore && hasLearn);

            // Ignore is session-wide and safe to fire; Learn would write into
            // the user's dictionary for good, so it is not.
            [NSApp sendAction:ignoreItem.action to:ignoreItem.target from:ignoreItem];
            Check(@"Spell check Ignore", @"an ignored word loses its squiggle",
                  ![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:13]);

            [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                      discardChanges:YES];
            prefs.spellCheckEnabled = wasOn;
            prefs.spellCheckLanguage = wasLang;
            [ed spellCheckNow];
        }
    }
}

/// == Markdown preview ==
void NppTestsMarkdown(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Markdown preview")) { printf("\n== Markdown preview ==\n");
        // The table pre-pass: GFM alignment, escaped pipes, fences left alone.
        NSString *table = @"| Name | N |\n|:-----|--:|\n| a\\|b | **1** |\n";
        NSString *asHTML = [MarkdownPanel tablesToHTML:table];
        Check(@"Markdown tables", @"the GFM table becomes HTML with alignment, escaped pipes and inline Markdown in cells",
              [asHTML containsString:@"<th style=\"text-align:left\">Name</th>"] &&
              [asHTML containsString:@"<td style=\"text-align:right\"><strong>1</strong></td>"] &&
              [asHTML containsString:@"a|b"]);
        NSString *fenced = @"```\n| not | a table |\n|---|---|\n```\n";
        Check(@"Markdown tables in fences", @"a table inside a code fence stays text",
              ![[MarkdownPanel tablesToHTML:fenced] containsString:@"<table>"]);

        // cmark proper, through the same door the panel uses.
        NSString *page = [MarkdownPanel htmlFromMarkdown:
            @"# Title\n\nSome **bold** and `code`.\n\n| A | B |\n|---|---|\n| 1 | 2 |\n"];
        Check(@"Markdown to HTML", @"headings, emphasis, code and the table all render",
              [page containsString:@"<h1>Title</h1>"] && [page containsString:@"<strong>bold</strong>"] &&
              [page containsString:@"<code>code</code>"] && [page containsString:@"<td>1</td>"]);

        // The panel itself: toggling shows it, a refresh renders the document.
        [ed newDocument];
        SetDoc(ed, @"# Hello\n\n- one\n- two\n");
        [app toggleMarkdownPreview:nil];
        MarkdownPanel *panel = [app valueForKey:@"markdownPanel"];
        [panel refresh];
        Check(@"Markdown preview panel", @"the panel shows and carries the rendered document",
              panel.visible && [panel.lastHTML containsString:@"<h1>Hello</h1>"] &&
              [panel.lastHTML containsString:@"<li>one</li>"]);
        // A document's relative image is drawn from beside it (and the page is drawn at all): the page
        // is loaded under the document's folder through the panel's own scheme, since WebKit gives a
        // page from a string no read access to file: URLs.
        NSString *mdFolder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_md_images"];
        [[NSFileManager defaultManager] removeItemAtPath:mdFolder error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:mdFolder withIntermediateDirectories:YES attributes:nil error:NULL];
        NSBitmapImageRep *red = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:120 pixelsHigh:120 bitsPerSample:8
                                  samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        for (NSInteger y = 0; y < 120; ++y) for (NSInteger x = 0; x < 120; ++x) { NSUInteger px[3] = {255, 0, 0}; [red setPixel:px atX:x y:y]; }
        [[red representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[mdFolder stringByAppendingPathComponent:@"pic.png"] atomically:YES];
        NSString *mdPath = [mdFolder stringByAppendingPathComponent:@"doc.md"];
        [@"<b>raw</b>\n\n![p](pic.png)\n" writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSInteger (^redPixels)(void) = ^NSInteger {
            __block NSImage *shot = nil;
            __block BOOL done = NO;
            [panel.webView takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *image, NSError *error) { shot = image; done = YES; }];
            NppSettleUntil(^BOOL { return done; }, 5);
            NSBitmapImageRep *bits = shot ? [[NSBitmapImageRep alloc] initWithData:shot.TIFFRepresentation] : nil;
            NSInteger count = 0;
            for (NSInteger y = 0; y < bits.pixelsHigh; y += 2) for (NSInteger x = 0; x < bits.pixelsWide; x += 2) {
                NSColor *c = [[bits colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
                if (c.redComponent > 0.8 && c.greenComponent < 0.25 && c.blueComponent < 0.25) count++;
            }
            return count;
        };
        [ed openFileAtPath:mdPath error:NULL];
        [panel refresh];
        __block NSInteger reds = 0;
        NppSettleUntil(^BOOL { return !panel.webView.isLoading && (reds = redPixels()) > 100; }, 8);
        Check(@"Markdown preview (relative image)", @"a picture beside the document, named relative to it, is drawn in the preview",
              reds > 100);

        // The document may carry raw HTML: an image from a server, a <meta refresh> to one. The preview
        // fetches nothing from the network (the server would learn the file was opened) and stays on
        // the document; a link clicked opens in the browser, as MarkdownViewer++ has it.
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address = {};
        address.sin_len = sizeof address; address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        socklen_t addressLength = sizeof address;
        BOOL listening = listener >= 0 && bind(listener, (struct sockaddr *)&address, sizeof address) == 0 && listen(listener, 8) == 0 &&
                         getsockname(listener, (struct sockaddr *)&address, &addressLength) == 0 && fcntl(listener, F_SETFL, O_NONBLOCK) == 0;
        int port = ntohs(address.sin_port);
        SetDoc(ed, [NSString stringWithFormat:@"# Remote\n\n<img src=\"http://127.0.0.1:%d/pixel.png\">\n\n"
                    @"<meta http-equiv=\"refresh\" content=\"0; url=http://127.0.0.1:%d/away\">\n", port, port]);
        [panel refresh];
        __block BOOL fetched = NO;
        NppSettleUntil(^BOOL {
            int connection = accept(listener, NULL, NULL);
            if (connection >= 0) { fetched = YES; close(connection); }
            return fetched;
        }, 3);
        NSString *shownURL = panel.webView.URL.absoluteString ?: @"";
        if (listener >= 0) close(listener);
        Check(@"Markdown preview (nothing remote)", @"an image from a server is not fetched and a <meta refresh> to one does not take the preview there",
              listening && port > 0 && !fetched && ![shownURL hasPrefix:@"http"] && [panel.lastHTML containsString:@"<h1>Remote</h1>"]);

        NSMutableArray<NSURL *> *opened = [NSMutableArray array];
        void (^openWas)(NSURL *) = panel.openLink;
        panel.openLink = ^(NSURL *url) { [opened addObject:url]; };
        id<WKNavigationDelegate> delegate = (id<WKNavigationDelegate>)panel;
        BOOL decides = [delegate respondsToSelector:@selector(webView:decidePolicyForNavigationAction:decisionHandler:)];
        NSInteger (^decide)(NSString *, WKNavigationType) = ^NSInteger(NSString *address, WKNavigationType type) {
            if (!decides) return -1;
            NppTestNavigation *action = [[NppTestNavigation alloc] init];
            action.request = [NSURLRequest requestWithURL:[NSURL URLWithString:address]];
            action.navigationType = type;
            action.targetFrame = [[NppTestFrame alloc] init];
            action.targetFrame.isMainFrame = YES;
            __block NSInteger policy = -1;
            [delegate webView:panel.webView decidePolicyForNavigationAction:(WKNavigationAction *)action
              decisionHandler:^(WKNavigationActionPolicy p) { policy = p; }];
            return policy;
        };
        NSString *here = panel.webView.URL.absoluteString ?: @"";           // doc.md's folder, through the preview's scheme
        NSInteger clickedWeb = decide(@"https://example.org/page", WKNavigationTypeLinkActivated);
        NSInteger clickedFile = decide(@"file:///etc/hosts", WKNavigationTypeLinkActivated);
        NSInteger refreshed = decide(@"https://example.org/refresh", WKNavigationTypeOther);
        NSInteger anchor = decide([here stringByAppendingString:@"#remote"], WKNavigationTypeLinkActivated);
        panel.openLink = openWas;
        Check(@"Markdown preview (links)", @"a clicked web link is cancelled in the preview and handed to the browser; a link to a local file "
              @"and a navigation the page starts by itself are cancelled and opened nowhere; a jump to an anchor of the page goes ahead",
              decides && [here hasPrefix:@"npp-preview://file/"] && clickedWeb == WKNavigationActionPolicyCancel && clickedFile == WKNavigationActionPolicyCancel &&
              refreshed == WKNavigationActionPolicyCancel && anchor == WKNavigationActionPolicyAllow &&
              opened.count == 1 && [opened.firstObject.absoluteString isEqualToString:@"https://example.org/page"]);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];   // doc.md, still in front
        [[NSFileManager defaultManager] removeItemAtPath:mdFolder error:NULL];
        [app toggleMarkdownPreview:nil];
        Check(@"Markdown preview toggles away", @"the second toggle hides the panel", !panel.visible);
    }
}

/// == Plugin host ==; == NppExec scripts ==
void NppTestsPluginHost(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Plugin host")) { printf("\n== Plugin host ==\n");
        // Build the sample plugin with the system compiler, in the Windows
        // plugins\Name\Name layout, and load it through the host.
        // Beside the build (macos/build/NotepadMac.app -> macos/plugin-sdk), so a checkout copied
        // elsewhere - a VM, another Mac - finds it; else where this file was compiled.
        NSString *sdk = [[NSBundle.mainBundle.bundlePath stringByDeletingLastPathComponent].stringByDeletingLastPathComponent
                         stringByAppendingPathComponent:@"plugin-sdk"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:sdk])
            sdk = [[[NSString stringWithUTF8String:__FILE__]
                     stringByDeletingLastPathComponent].stringByDeletingLastPathComponent
                    stringByAppendingPathComponent:@"plugin-sdk"];
        NSString *sample = [sdk stringByAppendingPathComponent:@"sample/hellomac.c"];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-plugin-test"];
        NSString *dir = [root stringByAppendingPathComponent:@"HelloMac"];
        [[NSFileManager defaultManager] removeItemAtPath:root error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                   attributes:nil error:NULL];
        NSString *dylib = [dir stringByAppendingPathComponent:@"HelloMac.dylib"];
        NSTask *cc = [[NSTask alloc] init];
        cc.executableURL = [NSURL fileURLWithPath:@"/usr/bin/clang"];
        cc.arguments = @[@"-dynamiclib", @"-o", dylib, sample];
        BOOL built = NO;
        if ([cc launchAndReturnError:NULL]) { [cc waitUntilExit]; built = cc.terminationStatus == 0; }

        NppPluginHost *host = [NppPluginHost shared];
        host.editor = ed;
        NSMenu *pluginsMenu = [[NSMenu alloc] initWithTitle:@"Plugins"];
        NSUInteger loadedCount = [host loadPluginsFromDirectory:root intoMenu:pluginsMenu];
        NppLoadedPlugin *plugin = host.plugins.lastObject;
        NSMenu *sub = pluginsMenu.itemArray.lastObject.submenu;
        Check(@"Plugin host (load)", @"the sample dylib builds, loads, and its commands become a submenu",
              built && loadedCount == 1 && [plugin.name isEqualToString:@"HelloMac"] &&
              plugin.commandCount == 3 && sub.numberOfItems == 3 &&
              [sub itemAtIndex:1].separatorItem);

        // A command runs and reaches the editor through send(): SCI_REPLACESEL.
        [ed newDocument];
        SetDoc(ed, @"");
        [NSApp sendAction:[sub itemAtIndex:0].action to:[sub itemAtIndex:0].target from:[sub itemAtIndex:0]];
        Check(@"Plugin host (a command edits)", @"the plugin's menu command writes into the document",
              [DocText(ed) isEqualToString:@"hello from the sample plugin"]);

        // The NPPM_* side and a notification: opening a file must both answer
        // NPPM_GETFILENAME and raise NPPN_FILEOPENED in the plugin.
        intptr_t openedBefore = [plugin sendMessage:1 wParam:NPPN_FILEOPENED lParam:0];
        NSError *err = nil;
        [ed openFileAtPath:TempFile(@"t_plugin.txt", @"plugin food\n") error:&err];
        [ed.sci message:SCI_SETSEL wParam:0 lParam:0];
        [NSApp sendAction:[sub itemAtIndex:2].action to:[sub itemAtIndex:2].target from:[sub itemAtIndex:2]];
        Check(@"Plugin host (NPPM and NPPN)", @"NPPM_GETFILENAME answers and NPPN_FILEOPENED arrived",
              [DocText(ed) hasPrefix:@"t_plugin.txt"] &&
              [plugin sendMessage:1 wParam:NPPN_FILEOPENED lParam:0] == openedBefore + 1);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }

    if (NppSectionWanted(@"NppExec scripts")) { printf("\n== NppExec scripts ==\n");
        NSString *execDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_exec"];
        [[NSFileManager defaultManager] removeItemAtPath:execDir error:NULL];
        [[NSFileManager defaultManager] createDirectoryAtPath:execDir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"alpha\n" writeToFile:[execDir stringByAppendingPathComponent:@"one.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"beta\n" writeToFile:[execDir stringByAppendingPathComponent:@"two.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

        // Variables, arithmetic, a loop by IF … GOTO, a block IF, and the shell.
        NppScriptEngine *engine = [[NppScriptEngine alloc] initWithEditor:ed];
        NSString *script = [NSString stringWithFormat:
            @"// counts to three\n"
            @"SET n = 0\n"
            @":again\n"
            @"SET n ~ $(n) + 1\n"
            @"ECHO pass $(n)\n"
            @"IF $(n) < 3 GOTO again\n"
            @"IF \"$(n)\" == \"3\"\n"
            @"  ECHO three\n"
            @"ELSE IF $(n) == 4\n"
            @"  ECHO four\n"
            @"ELSE\n"
            @"  ECHO other\n"
            @"ENDIF\n"
            @"SET half ~ 7 / 2\n"
            @"CD %@\n"
            @"ENV_SET GREETING = hello from env\n"
            @"/bin/echo \"$(SYS.GREETING)\"; exit 3\n"
            @"ECHO code=$(EXITCODE) out=$(OUTPUT)\n"
            @"ls *.txt\n"
            @"ECHO first=$(OUTPUT1) last=$(OUTPUTL)\n", execDir];
        BOOL ran = [engine runScript:script arguments:@[]];
        NSString *log = engine.log;
        BOOL flow = ran && [log containsString:@"pass 1\npass 2\npass 3\n"] && ![log containsString:@"pass 4"] &&
                    [log containsString:@"three\n"] && ![log containsString:@"four\n"] && ![log containsString:@"other\n"] &&
                    [[engine valueOfVariable:@"half"] isEqualToString:@"3.5"];
        BOOL shell = [log containsString:@"code=3 out=hello from env"] && [log containsString:@"first=one.txt last=two.txt"] &&
                     [log containsString:@"<<< Process finished. (Exit code 3)"] &&
                     [engine.directory isEqualToString:execDir.stringByStandardizingPath];
        printf("    exec flow=%d shell=%d\n", flow, shell);
        if (!(flow && shell)) printf("%s\n", log.UTF8String);
        Check(@"NppExec (script)", @"SET and SET ~, IF…GOTO and IF/ELSE IF/ELSE/ENDIF, CD, ENV_SET, $(OUTPUT) and $(EXITCODE)",
              flow && shell);
        [engine runScript:@"/usr/bin/printf 'no-newline|'\n" arguments:@[]];
        Check(@"NppExec (script)", @"output without a final newline: \"<<< Process finished\" still starts a line of its own",
              [[ed.console text] containsString:@"no-newline|\n<<< Process finished. (Exit code 0)"] &&
              [engine.log containsString:@"no-newline|\n<<< Process finished. (Exit code 0)"]);

        // The editor's commands: open by mask, switch, change, save, close.
        NSUInteger docsBefore = ed.documents.count;
        NppScriptEngine *editing = [[NppScriptEngine alloc] initWithEditor:ed];
        editing.directory = execDir;
        BOOL editOK = [editing runScript:@"NPP_OPEN *.txt\n"
                                         @"NPP_SWITCH one.txt\n"
                                         @"SET before = $(CURRENT_LINESTR)\n"
                                         @"SCI_SENDMSG 2013\n"            // SCI_SELECTALL
                                         @"SEL_SETTEXT+ gamma\\tdelta\\n\n"
                                         @"NPP_SAVE\n"
                                         @"NPP_SAVEAS copy.txt\n"
                                         @"NPP_CLOSE copy.txt\n"
                                         @"NPP_CLOSE two.txt\n"
                                         @"NPP_SENDMSG 1234\n"
                                 arguments:@[]];
        NSString *saved = [NSString stringWithContentsOfFile:[execDir stringByAppendingPathComponent:@"one.txt"] encoding:NSUTF8StringEncoding error:NULL];
        NSString *copy = [NSString stringWithContentsOfFile:[execDir stringByAppendingPathComponent:@"copy.txt"] encoding:NSUTF8StringEncoding error:NULL];
        BOOL edited = editOK && [saved isEqualToString:@"gamma\tdelta\n"] && [copy isEqualToString:saved] &&
                      [[editing valueOfVariable:@"before"] isEqualToString:@"alpha"] &&
                      ed.documents.count == docsBefore && [editing.log containsString:@"NPP_SENDMSG is not available on macOS"];
        printf("    exec edit=%d docs=%lu/%lu\n", edited, (unsigned long)ed.documents.count, (unsigned long)docsBefore);
        if (!edited) printf("%s\n", editing.log.UTF8String);
        Check(@"NppExec (editor commands)", @"NPP_OPEN with a mask, NPP_SWITCH, SEL_SETTEXT+, NPP_SAVE, NPP_SAVEAS, NPP_CLOSE",
              edited);

        // Saved scripts in npes_saved.txt, NPP_EXEC with arguments, INPUTBOX, NPP_MENUCOMMAND.
        NSString *savedText = @"::greet\nECHO hi $(ARGV[1]) of $(ARGC)\n\n::other\nECHO x\n";
        NSArray<NppSavedScript *> *parsed = [NppSavedScript scriptsFromSavedText:savedText];
        BOOL format = parsed.count == 2 && [parsed[0].name isEqualToString:@"greet"] &&
                      [parsed[0].text isEqualToString:@"ECHO hi $(ARGV[1]) of $(ARGC)"] &&
                      [[NppSavedScript savedTextForScripts:parsed] isEqualToString:@"::greet\nECHO hi $(ARGV[1]) of $(ARGC)\n::other\nECHO x\n"];
        NSUInteger scriptsBefore = [ed savedScripts].count;
        [ed saveScript:[NppSavedScript scriptNamed:@"t_greet" text:@"ECHO hi $(ARGV[1]) of $(ARGC)"]];
        [app rebuildExecMenu];
        BOOL listed = [app.execMenu itemWithTitle:@"t_greet"] != nil;
        NppScriptEngine *calling = [[NppScriptEngine alloc] initWithEditor:ed];
        calling.inputProvider = ^NSString *(NSString *prompt, NSString *initial) {
            return [prompt isEqualToString:@"Who?"] ? [initial stringByAppendingString:@" World"] : nil;
        };
        __block NSString *performed = nil;
        calling.menuCommandPerformer = ^BOOL(NSString *path) { performed = path; return [app performMenuCommandAtPath:@"Edit|Select All"]; };
        SetDoc(ed, @"abc");
        BOOL callOK = [calling runScript:@"INPUTBOX \"Who?\" : Hello\n"
                                         @"NPP_EXEC t_greet \"$(INPUT[2])\" two\n"
                                         @"ECHO argc now [$(ARGC)]\n"
                                         @"NPP_MENUCOMMAND Edit|Select All\n"
                               arguments:@[]];
        long selected = [ed.sci message:SCI_GETSELECTIONEND] - [ed.sci message:SCI_GETSELECTIONSTART];
        BOOL nested = callOK && [calling.log containsString:@"hi World of 2"] && [calling.log containsString:@"argc now [0]"] &&
                      [[calling valueOfVariable:@"INPUT"] isEqualToString:@"Hello World"] &&
                      [performed isEqualToString:@"Edit|Select All"] && selected == 3 &&
                      ![app performMenuCommandAtPath:@"Edit|No Such Command"];
        [ed removeScriptNamed:@"t_greet"];
        [app rebuildExecMenu];
        BOOL removed = [ed savedScripts].count == scriptsBefore && ![app.execMenu itemWithTitle:@"t_greet"];
        printf("    exec format=%d listed=%d nested=%d removed=%d\n", format, listed, nested, removed);
        if (!nested) printf("%s\n", calling.log.UTF8String);
        Check(@"NppExec (saved scripts)", @"npes_saved.txt's format, the menu of saved scripts, NPP_EXEC with arguments, INPUTBOX, NPP_MENUCOMMAND",
              format && listed && nested && removed);

        // NppExec's IF … THEN; a value that holds an operator; the author's own
        // variables as plain words, the document's as one quoted word; $(SYS.X) shown.
        NppScriptEngine *forms = [[NppScriptEngine alloc] initWithEditor:ed];
        forms.directory = execDir;
        SetDoc(ed, @"x; echo INJECTED");
        [ed.sci message:SCI_SELECTALL];
        BOOL formsOK = [forms runScript:@"SET n = 3\n"
                                        @"IF \"$(n)\" == \"3\" THEN\n  ECHO then-yes\nELSE\n  ECHO then-no\nENDIF\n"
                                        @"SET expr = a==b\n"
                                        @"IF \"$(expr)\" == \"a==b\" THEN\n  ECHO operator-inside\nENDIF\n"
                                        @"SET flags = a b\n"
                                        @"SET more = $(flags) tail\n"
                                        @"/usr/bin/printf '%s|' $(more)\n"
                                        @"ECHO plain=[$(OUTPUT)]\n"
                                        @"SET sel = $(SELECTED_TEXT)\n"
                                        @"/bin/echo $(sel)\n"
                                        @"ECHO doc=[$(OUTPUT)]\n"
                                        @"/bin/echo \"$(printf %s $(SELECTED_TEXT))\"\n"
                                        @"ECHO sub=[$(OUTPUT)]\n"
                                        @"ENV_SET T_EXEC_VAR = shown\n"
                                        @"SET $(SYS.T_EXEC_VAR)\n"
                                arguments:@[]];
        NSString *fl = forms.log;
        formsOK = formsOK && [fl containsString:@"then-yes"] && ![fl containsString:@"then-no"] &&
                  [fl containsString:@"operator-inside"] && [fl containsString:@"plain=[a|b|tail|]"] &&
                  [fl containsString:@"doc=[x; echo INJECTED]"] && [fl containsString:@"sub=[x; echo INJECTED]"] &&
                  [fl containsString:@"= shown"];
        if (!formsOK) printf("%s\n", fl.UTF8String);
        Check(@"NppExec (THEN, operators in values, quoting)",
              @"IF … THEN is read, a value holding == is not the comparison, SET words stay words, and text from the "
              @"document is one quoted word even inside the shell's $( )",
              formsOK);

        // A program may run longer than the Run dialog allows, and Stop ends it.
        NppScriptEngine *slow = [[NppScriptEngine alloc] initWithEditor:ed];
        NSDate *slowStart = [NSDate date];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ slow.cancelled = YES; });
        [slow runScript:@"/bin/sh -c \"/bin/sleep 20; true\"\nECHO not-reached\n" arguments:@[]];
        NSTimeInterval slowTook = -[slowStart timeIntervalSinceNow];
        printf("    exec stop took %.1fs\n%s", slowTook, slowTook < 5 ? "" : slow.log.UTF8String);
        Check(@"NppExec (stop)", @"stopping a script ends the program it is running, and nothing after it runs",
              slowTook < 5 && ![slow.log containsString:@"not-reached"]);

        // A program that leaves a child in the background: NppExec goes on when the program ends.
        NppScriptEngine *leaves = [[NppScriptEngine alloc] initWithEditor:ed];
        NSDate *leavesStart = [NSDate date];
        [leaves runScript:@"/bin/sh -c \"(/bin/sleep 5; echo late) & echo now\"\nECHO after-it\n" arguments:@[]];
        NSTimeInterval leavesTook = -[leavesStart timeIntervalSinceNow];
        Check(@"NppExec (a child left in the background)", @"the script goes on as soon as the program itself has ended, with its output and exit code",
              leavesTook < 3 && [leaves.log containsString:@"now"] && [leaves.log containsString:@"after-it"] &&
              [leaves.log containsString:@"Exit code 0"]);

        // EXIT ends the script it is in; the caller goes on. EXIT 1 ends them all.
        [ed saveScript:[NppSavedScript scriptNamed:@"t_inner" text:@"ECHO inner-start\nEXIT $(ARGV[1])\nECHO inner-not-reached"]];
        NppScriptEngine *exiting = [[NppScriptEngine alloc] initWithEditor:ed];
        [exiting runScript:@"NPP_EXEC t_inner 0\nECHO outer-goes-on\nNPP_EXEC t_inner 1\nECHO outer-not-reached\n" arguments:@[]];
        [ed removeScriptNamed:@"t_inner"];
        NSString *el = exiting.log;
        Check(@"NppExec (EXIT)", @"EXIT returns to the calling script, EXIT 1 ends the calling scripts too",
              [el containsString:@"outer-goes-on"] && ![el containsString:@"inner-not-reached"] && ![el containsString:@"outer-not-reached"] &&
              [el componentsSeparatedByString:@"inner-start"].count == 3);

        // A runaway loop is stopped rather than hanging the editor.
        NppScriptEngine *loop = [[NppScriptEngine alloc] initWithEditor:ed];
        loop.stepLimit = 500;
        BOOL stopped = ![loop runScript:@":top\nGOTO top\n" arguments:@[]] && [loop.log containsString:@"too many steps"];
        Check(@"NppExec (runaway)", @"an endless GOTO loop is stopped", stopped);

        // From the menu a script runs off the main thread and comes back to it
        // for the editor; the console fills while the app stays live.
        NSString *lastBefore = [[NSUserDefaults standardUserDefaults] stringForKey:@"NppMac.execLastScript"];
        SetDoc(ed, @"background");
        [[ed console] clear];
        [app executeScriptText:@"ECHO bg $(CURRENT_WORD)\nSLEEP 50\nNPP_MENUCOMMAND Edit|Select All"];
        NSDate *bgLimit = [NSDate dateWithTimeIntervalSinceNow:5];
        while ([app valueForKey:@"runningScript"] && [bgLimit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        long bgSelected = [ed.sci message:SCI_GETSELECTIONEND] - [ed.sci message:SCI_GETSELECTIONSTART];
        BOOL background = ![app valueForKey:@"runningScript"] && [[ed console].text containsString:@"bg background"] && bgSelected == 10;
        if (!background) printf("    bg running=%d selected=%ld console=[%s]\n", [app valueForKey:@"runningScript"] != nil, bgSelected, [ed console].text.UTF8String);
        [[NSUserDefaults standardUserDefaults] setObject:lastBefore ?: @"" forKey:@"NppMac.execLastScript"];
        [[ed console] toggle];
        Check(@"NppExec (background)", @"a script from the menu runs off the main thread and uses the editor through it", background);
        [[NSFileManager defaultManager] removeItemAtPath:execDir error:NULL];
    }
}
