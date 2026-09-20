#import "EditorLook.h"
#import "SettingsCommands.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#include "NpcTables.h"

static long Abgr(NSColor *colour, long fallback) {
    NSColor *c = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!c) return fallback | 0xFF000000L;
    return (long)lround(c.redComponent * 255) | ((long)lround(c.greenComponent * 255) << 8) |
           ((long)lround(c.blueComponent * 255) << 16) | 0xFF000000L;
}

@implementation EditorController (Look)

- (NSArray<ScintillaView *> *)lookViews {
    NSMutableArray *views = [NSMutableArray arrayWithObject:self.sci];
    if (self.secondarySci) [views addObject:self.secondarySci];
    return views;
}

- (void)applyLook {
    NppPreferences *p = [NppPreferences shared];
    NppStyle *selected = [StyleCatalog sharedCatalog].globalStyles[@"Selected text colour"];
    for (ScintillaView *sci in [self lookViews]) {
        // Enable smooth font.
        [sci message:SCI_SETFONTQUALITY wParam:p.smoothFont ? SC_EFF_QUALITY_LCD_OPTIMIZED : SC_EFF_QUALITY_DEFAULT lParam:0];
        // Apply custom color to selected text foreground.
        if (p.selectedTextCustomForeground && selected.foreground) {
            [sci message:SCI_SETSELFORE wParam:1 lParam:Abgr(selected.foreground, 0) & 0xFFFFFF];
        } else {
            [sci message:SCI_SETSELFORE wParam:0 lParam:0];
        }
        [sci message:SCI_SETMULTIPLESELECTION wParam:p.multiEditing ? 1 : 0 lParam:0];
        [sci message:SCI_SETCHANGEHISTORY
              wParam:(p.changeHistoryMargin || p.changeHistoryText)
                     ? (SC_CHANGE_HISTORY_ENABLED | (p.changeHistoryMargin ? SC_CHANGE_HISTORY_MARKERS : 0) |
                        (p.changeHistoryText ? SC_CHANGE_HISTORY_INDICATORS : 0))
                     : SC_CHANGE_HISTORY_DISABLED
              lParam:0];
        [sci message:SCI_SETMARGINWIDTHN wParam:3 lParam:p.changeHistoryMargin ? 6 : 0];
        [self applyFoldMarkersTo:sci];
        [self applySymbolRepresentationsTo:sci];
    }
    [self updateLineNumberWidth];
}

- (void)applyFoldMarkersTo:(ScintillaView *)sci {
    static const int kMarkers[5][7] = {
        {SC_MARKNUM_FOLDEROPEN, SC_MARKNUM_FOLDER, SC_MARKNUM_FOLDERSUB, SC_MARKNUM_FOLDERTAIL, SC_MARKNUM_FOLDEREND, SC_MARKNUM_FOLDEROPENMID, SC_MARKNUM_FOLDERMIDTAIL},
        {SC_MARK_MINUS, SC_MARK_PLUS, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY},
        {SC_MARK_ARROWDOWN, SC_MARK_ARROW, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY},
        {SC_MARK_CIRCLEMINUS, SC_MARK_CIRCLEPLUS, SC_MARK_VLINE, SC_MARK_LCORNERCURVE, SC_MARK_CIRCLEPLUSCONNECTED, SC_MARK_CIRCLEMINUSCONNECTED, SC_MARK_TCORNERCURVE},
        {SC_MARK_BOXMINUS, SC_MARK_BOXPLUS, SC_MARK_VLINE, SC_MARK_LCORNER, SC_MARK_BOXPLUSCONNECTED, SC_MARK_BOXMINUSCONNECTED, SC_MARK_TCORNER},
    };
    NppPreferences *p = [NppPreferences shared];
    // 0 simple, 1 arrow, 2 circle tree, 3 box tree, 4 none - upstream's order.
    NSInteger style = p.foldMarginStyle;
    StyleCatalog *styles = [StyleCatalog sharedCatalog];
    NppStyle *fold = styles.globalStyles[@"Fold"], *active = styles.globalStyles[@"Fold active"];
    // getFoldColor: the marker's outline is the style's background and its
    // fill the foreground, as upstream reads them.
    long fore = Abgr(fold.background, 0xFFFFFF) & 0xFFFFFF, back = Abgr(fold.foreground, 0x808080) & 0xFFFFFF;
    long highlight = Abgr(active.foreground, 0x0000FF) & 0xFFFFFF;
    for (int j = 0; j < 7; ++j) {
        int shape = (style >= 0 && style <= 3) ? kMarkers[style + 1][j] : kMarkers[4][j];
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)kMarkers[0][j] lParam:shape];
        [sci message:SCI_MARKERSETFORE wParam:(uptr_t)kMarkers[0][j] lParam:fore];
        [sci message:SCI_MARKERSETBACK wParam:(uptr_t)kMarkers[0][j] lParam:back];
        [sci message:SCI_MARKERSETBACKSELECTED wParam:(uptr_t)kMarkers[0][j] lParam:highlight];
    }
    [sci message:SCI_MARKERENABLEHIGHLIGHT wParam:1 lParam:0];
    // "None" hides the margin, as upstream's setMakerStyle does.
    [sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:(p.foldMarginShow && style != 4) ? 16 : 0];
}

- (void)applySymbolRepresentationsTo:(ScintillaView *)sci {
    NppPreferences *p = [NppPreferences shared];
    StyleCatalog *styles = [StyleCatalog sharedCatalog];
    long eolColour = Abgr(styles.globalStyles[@"EOL custom color"].foreground, 0xDADADA);
    long npcColour = Abgr(styles.globalStyles[@"Non-printing characters custom color"].foreground, 0xC0C0C0);
    [sci message:SCI_CLEARALLREPRESENTATIONS wParam:0 lParam:0];

    // setCRLF.
    long eolLook = p.eolPlainText ? SC_REPRESENTATION_PLAIN : SC_REPRESENTATION_BLOB;
    if (p.eolCustomColour) eolLook |= SC_REPRESENTATION_COLOUR;
    for (NSString *key in @[@"\r", @"\n"]) {
        [sci message:SCI_SETREPRESENTATIONCOLOUR wParam:(uptr_t)key.UTF8String lParam:eolColour];
        [sci message:SCI_SETREPRESENTATIONAPPEARANCE wParam:(uptr_t)key.UTF8String lParam:eolLook];
    }

    long npcLook = SC_REPRESENTATION_BLOB | (p.npcCustomColour ? SC_REPRESENTATION_COLOUR : 0);
    int mode = p.npcCodepoint ? 2 : 1;
    // showCcUniEol: C0, C1 and the Unicode line ends; hidden behind a
    // zero-width space when that view option is off.
    size_t ccCount = sizeof(kNppCcUniEolChars) / sizeof(kNppCcUniEolChars[0]);
    for (size_t i = 0; i < ccCount; ++i) {
        const char *key = kNppCcUniEolChars[i][0];
        if (!*key) continue;
        if (p.ccUniEolShow) {
            [sci setStringProperty:SCI_SETREPRESENTATION parameter:(long)key
                             value:@(kNppCcUniEolChars[i][p.npcIncludeCcUniEol ? mode : 1])];
            if (p.npcIncludeCcUniEol && p.npcCustomColour) {
                [sci message:SCI_SETREPRESENTATIONCOLOUR wParam:(uptr_t)key lParam:npcColour];
                [sci message:SCI_SETREPRESENTATIONAPPEARANCE wParam:(uptr_t)key lParam:npcLook];
            }
        } else {
            [sci setStringProperty:SCI_SETREPRESENTATION parameter:(long)key value:@"​"];
            [sci message:SCI_SETREPRESENTATIONAPPEARANCE wParam:(uptr_t)key lParam:SC_REPRESENTATION_PLAIN];
        }
    }
    // showNpc: the invisible Unicode characters, by abbreviation or code point.
    if (p.npcShow) {
        size_t n = sizeof(kNppNonPrintingChars) / sizeof(kNppNonPrintingChars[0]);
        for (size_t i = 0; i < n; ++i) {
            const char *key = kNppNonPrintingChars[i][0];
            [sci setStringProperty:SCI_SETREPRESENTATION parameter:(long)key value:@(kNppNonPrintingChars[i][mode])];
            if (p.npcCustomColour) {
                [sci message:SCI_SETREPRESENTATIONCOLOUR wParam:(uptr_t)key lParam:npcColour];
                [sci message:SCI_SETREPRESENTATIONAPPEARANCE wParam:(uptr_t)key lParam:npcLook];
            }
        }
    }
}

- (void)updateLineNumberWidth {
    NppPreferences *p = [NppPreferences shared];
    for (ScintillaView *sci in [self lookViews]) {
        if (!p.lineNumberShow) { [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:0]; continue; }
        long biggest;
        if (p.lineNumberDynamicWidth) {
            long lastShown = [sci message:SCI_GETFIRSTVISIBLELINE] + [sci message:SCI_LINESONSCREEN];
            biggest = [sci message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)lastShown] + 1;
        } else {
            biggest = [sci message:SCI_GETLINECOUNT];
        }
        // At least three digits, as upstream keeps.
        int digits = 3;
        for (long n = biggest; n >= 1000; n /= 10) digits++;
        NSString *sample = [@"_" stringByPaddingToLength:(NSUInteger)digits + 1 withString:@"9" startingAtIndex:0];
        long width = [sci message:SCI_TEXTWIDTH wParam:STYLE_LINENUMBER lParam:(sptr_t)sample.UTF8String] + 8;
        if ([sci message:SCI_GETMARGINWIDTHN wParam:0] != width) [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:width];
    }
}

@end
