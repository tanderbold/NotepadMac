#import "Accessibility.h"

@implementation NppAXElement

+ (instancetype)elementInView:(NSView *)view role:(NSAccessibilityRole)role label:(NSString *)label {
    NppAXElement *e = [[self alloc] init];
    e.hostView = view;
    e.accessibilityRole = role;
    e.accessibilityLabel = label;
    e.accessibilityParent = view;
    return e;
}

- (NSRect)accessibilityFrame {
    NSView *view = self.hostView;
    return view.window ? NSAccessibilityFrameInView(view, self.rectInView) : NSZeroRect;
}

- (BOOL)isAccessibilityEnabled { return YES; }

- (BOOL)accessibilityPerformPress {
    if (!self.pressHandler) return NO;
    self.pressHandler();
    return YES;
}

- (BOOL)accessibilityPerformShowMenu {
    if (!self.showMenuHandler) return NO;
    self.showMenuHandler();
    return YES;
}

- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.pressHandler != nil;
    if (selector == @selector(accessibilityPerformShowMenu)) return self.showMenuHandler != nil;
    return [super isAccessibilitySelectorAllowed:selector];
}

@end

/// No letter or digit in it: a symbol, an arrow, nothing.
static BOOL NoWords(NSString *title) {
    return [title rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]].location == NSNotFound;
}

void NppAXLabelSymbolButtons(NSView *root) {
    if ([root isKindOfClass:[NSButton class]] && ![root isKindOfClass:[NSPopUpButton class]]) {
        NSButton *b = (NSButton *)root;
        // (A button's label is its title until it is given one.)
        BOOL ownLabel = b.accessibilityLabel.length && ![b.accessibilityLabel isEqual:b.title];
        if (b.toolTip.length && NoWords(b.title ?: @"") && !ownLabel) b.accessibilityLabel = b.toolTip;
    }
    for (NSView *sub in root.subviews) NppAXLabelSymbolButtons(sub);
}

/// A static label: not editable, not a field's box, with words in it.
static BOOL IsLabel(NSView *v) {
    if (![v isKindOfClass:[NSTextField class]] || [v isKindOfClass:[NSComboBox class]]) return NO;
    NSTextField *t = (NSTextField *)v;
    return !t.isEditable && !t.isBezeled && t.stringValue.length && !t.isHiddenOrHasHiddenAncestor;
}

/// A check box or radio button with words: what the control right of it on its row is about
/// (☐ Transparency ——○——), as a static text before it would be.
static BOOL IsTitledSwitch(NSView *v) {
    if (![v isKindOfClass:[NSButton class]] || [v isKindOfClass:[NSPopUpButton class]] || v.isHiddenOrHasHiddenAncestor) return NO;
    NSButton *b = (NSButton *)v;
    // (As Localization.mm tells a check box or radio button from a push button.)
    return (((NSButtonCell *)b.cell).showsStateBy & NSContentsCellMask) && b.title.length;
}

/// What a label is for: something one sets, which says nothing of its own.
static BOOL WantsLabel(NSView *v) {
    if (v.isHiddenOrHasHiddenAncestor) return NO;
    BOOL input = ([v isKindOfClass:[NSTextField class]] && [(NSTextField *)v isEditable]) ||
                 [v isKindOfClass:[NSPopUpButton class]] || [v isKindOfClass:[NSSlider class]] || [v isKindOfClass:[NSStepper class]] ||
                 [v isKindOfClass:[NSColorWell class]] || [v isKindOfClass:[NSComboBox class]] ||
                 ([v isKindOfClass:[NSTextView class]] && [(NSTextView *)v enclosingScrollView]);
    if (!input) return NO;
    return !v.accessibilityLabel.length && !v.accessibilityTitleUIElement;
}

/// The views a label is sought among and for; not inside tables (their cells are named by
/// row and column), editors or web views.
static void Collect(NSView *v, NSMutableArray *labels, NSMutableArray *switches, NSMutableArray *inputs, NSHashTable *taken) {
    if (v.isHidden) return;
    // A label a control already has (from an earlier pass) is not another's.
    id titled = v.accessibilityTitleUIElement;
    if (titled) [taken addObject:titled];
    if (IsLabel(v)) [labels addObject:v];
    else if (IsTitledSwitch(v)) [switches addObject:v];
    else if (WantsLabel(v)) [inputs addObject:v];
    if ([v isKindOfClass:[NSTableView class]] || [v isKindOfClass:[NSTextView class]] ||
        [v isKindOfClass:[NSControl class]] || [NSStringFromClass(v.class) hasPrefix:@"Scintilla"] ||
        [NSStringFromClass(v.class) hasPrefix:@"WK"]) return;
    for (NSView *sub in v.subviews) Collect(sub, labels, switches, inputs, taken);
}

void NppAXLinkLabels(NSView *root) {
    // (Outside a window too: the rectangles are then in the hierarchy's own top view.)
    NSMutableArray<NSView *> *labels = [NSMutableArray array], *switches = [NSMutableArray array], *inputs = [NSMutableArray array];
    NSHashTable<NSView *> *taken = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    Collect(root, labels, switches, inputs, taken);
    if (!inputs.count) return;
    NSUInteger plainLabels = labels.count;
    [labels addObjectsFromArray:switches];   // on a row only
    NSMutableArray<NSValue *> *labelRects = [NSMutableArray array];
    for (NSView *l in labels) [labelRects addObject:[NSValue valueWithRect:[l convertRect:l.bounds toView:nil]]];
    NSRect (^rectOf)(NSView *) = ^NSRect(NSView *input) {
        // A text view by the scroll view it is seen in; window coordinates: y up.
        NSView *seen = [input isKindOfClass:[NSTextView class]] ? [(NSTextView *)input enclosingScrollView] : input;
        return [seen convertRect:seen.bounds toView:nil];
    };
    // First the rows: a label on a control's row, to its left, is that control's.
    NSMapTable<NSView *, NSView *> *found = [NSMapTable strongToStrongObjectsMapTable];
    for (NSView *input in inputs) {
        NSRect c = rectOf(input);
        NSView *best = nil;
        CGFloat bestGap = CGFLOAT_MAX;
        for (NSUInteger i = 0; i < labels.count; ++i) {
            NSRect l = labelRects[i].rectValue;
            // (A label may run under the control's left edge: a caption as wide as its words, laid
            // out before the control was moved for it.)
            if (NSMinX(l) >= NSMinX(c) || NSMaxX(l) > NSMidX(c) || NSMidY(l) < NSMinY(c) - 2 || NSMidY(l) > NSMaxY(c) + 2) continue;
            CGFloat gap = MAX(0, NSMinX(c) - NSMaxX(l));
            if (gap < 240 && gap < bestGap) { best = labels[i]; bestGap = gap; }
        }
        if (best) { [found setObject:best forKey:input]; [taken addObject:best]; }
    }
    // Then a label just above a control, over its left part, that no row has taken.
    for (NSView *input in inputs) {
        if ([found objectForKey:input]) continue;
        NSRect c = rectOf(input);
        NSView *best = nil;
        CGFloat bestGap = CGFLOAT_MAX;
        for (NSUInteger i = 0; i < plainLabels; ++i) {
            if ([taken containsObject:labels[i]]) continue;
            NSRect l = labelRects[i].rectValue;
            // (A control put under a caption too long for its row is indented under it.)
            if (NSMinY(l) < NSMaxY(c) - 4 || NSMinX(l) < NSMinX(c) - 24 || NSMinX(l) > NSMidX(c)) continue;
            CGFloat gap = NSMinY(l) - NSMaxY(c);
            if (gap < 30 && gap < bestGap) { best = labels[i]; bestGap = gap; }
        }
        if (best) [found setObject:best forKey:input];
    }
    for (NSView *input in inputs) {
        NSView *label = [found objectForKey:input];
        if (label) input.accessibilityTitleUIElement = label;
        // A field no label stands by (a filter box, a search field): the words it shows while
        // empty are what it is for, and they go when something is typed - so they name it.
        else if ([input isKindOfClass:[NSTextField class]] && [(NSTextField *)input placeholderString].length)
            input.accessibilityLabel = [(NSTextField *)input placeholderString];
    }
}

/// The text views under a view that nothing names yet.
static void UnnamedTextViews(NSView *v, NSMutableArray *out) {
    if (v.isHidden) return;
    if ([v isKindOfClass:[NSTextView class]]) {
        NSTextView *t = (NSTextView *)v;
        if (t.enclosingScrollView && !t.accessibilityLabel.length && !t.accessibilityTitleUIElement) [out addObject:t];
        return;
    }
    if ([v isKindOfClass:[NSTableView class]] || [NSStringFromClass(v.class) hasPrefix:@"Scintilla"]) return;
    for (NSView *sub in v.subviews) UnnamedTextViews(sub, out);
}

void NppAXPrepareWindow(NSWindow *window) {
    NSView *root = window.contentView;
    if (!root) return;
    NppAXLabelSymbolButtons(root);
    NppAXLinkLabels(root);
    // The one text a window shows (About's licence, Debug Info, a script) is what the window
    // is called; with two or more, each needs words of its own.
    NSMutableArray *texts = [NSMutableArray array];
    UnnamedTextViews(root, texts);
    if (texts.count == 1 && window.title.length && ![window isKindOfClass:NSClassFromString(@"NppMainWindow")] && !window.toolbar)
        [texts.firstObject setAccessibilityLabel:window.title];
}
