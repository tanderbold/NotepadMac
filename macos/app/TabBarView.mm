#import "TabBarView.h"

@implementation NppTabItem
@end

static const CGFloat kTabHeight = 26;
static const CGFloat kMinTabWidth = 90;
static const CGFloat kMaxTabWidth = 220;
static const CGFloat kCloseSize = 12;
static const CGFloat kPadding = 8;

@interface NppTabBarView ()
@property (nonatomic, strong) NSMutableArray<NSValue *> *tabFrames;
@property (nonatomic) NSInteger hoverIndex;
@property (nonatomic) NSInteger dragIndex;
@property (nonatomic) BOOL dragging;
@end

@implementation NppTabBarView

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _tabFrames = [NSMutableArray array];
    _selectedIndex = 0;
    _inFocusedView = YES;
    _hoverIndex = -1;
    _dragIndex = -1;
    _showCloseButtons = YES;
    _items = @[];
    // Its drawing stays inside it (see drawRect:).
    if ([self respondsToSelector:@selector(setClipsToBounds:)]) [self setValue:@YES forKey:@"clipsToBounds"];
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setItems:(NSArray<NppTabItem *> *)items {
    _items = [items copy];
    [self layoutTabs];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self setNeedsDisplay:YES];
}

- (void)setVertical:(BOOL)vertical   { _vertical = vertical; [self layoutTabs]; [self setNeedsDisplay:YES]; }
- (void)setMultiLine:(BOOL)multiLine { _multiLine = multiLine; [self layoutTabs]; [self setNeedsDisplay:YES]; }

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutTabs];
}

#pragma mark - Layout

/// Lays the tabs out and records each frame, which is what hit testing and the
/// tests both read.
- (void)layoutTabs {
    [self.tabFrames removeAllObjects];
    CGFloat available = self.vertical ? NSHeight(self.bounds) : NSWidth(self.bounds);
    if (available <= 0 || !self.items.count) return;

    if (self.vertical) {
        CGFloat width = MAX(kMinTabWidth, NSWidth(self.bounds));
        for (NSUInteger i = 0; i < self.items.count; ++i) {
            [self.tabFrames addObject:[NSValue valueWithRect:
                NSMakeRect(0, i * kTabHeight, width, kTabHeight)]];
        }
        return;
    }

    CGFloat width = MIN(kMaxTabWidth, MAX(kMinTabWidth, NSWidth(self.bounds) / (CGFloat)self.items.count));
    if (!self.multiLine) {
        // One row: the tabs share the width, down to a minimum.
        for (NSUInteger i = 0; i < self.items.count; ++i) {
            [self.tabFrames addObject:[NSValue valueWithRect:
                NSMakeRect(i * width, 0, width, kTabHeight)]];
        }
        return;
    }

    CGFloat x = 0, y = 0;
    width = MIN(kMaxTabWidth, MAX(kMinTabWidth, NSWidth(self.bounds) / 4));
    for (NSUInteger i = 0; i < self.items.count; ++i) {
        if (x + width > NSWidth(self.bounds) && x > 0) { x = 0; y += kTabHeight; }
        [self.tabFrames addObject:[NSValue valueWithRect:NSMakeRect(x, y, width, kTabHeight)]];
        x += width;
    }
}

- (CGFloat)requiredThickness {
    if (!self.items.count) return kTabHeight;
    if (self.vertical) return MAX(kMinTabWidth, NSWidth(self.bounds));
    CGFloat bottom = kTabHeight;
    for (NSValue *v in self.tabFrames) bottom = MAX(bottom, NSMaxY(v.rectValue));
    return bottom;
}

- (NSString *)displayTitleAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) return @"";
    NSString *title = self.items[(NSUInteger)index].title ?: @"";
    if (self.maxLabelLength > 0 && (NSInteger)title.length > self.maxLabelLength) {
        title = [[title substringToIndex:(NSUInteger)self.maxLabelLength] stringByAppendingString:@"…"];
    }
    return title;
}

- (NSRect)frameOfTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.tabFrames.count) return NSZeroRect;
    return self.tabFrames[(NSUInteger)index].rectValue;
}

- (NSInteger)indexOfTabAtPoint:(NSPoint)point {
    for (NSUInteger i = 0; i < self.tabFrames.count; ++i) {
        if (NSPointInRect(point, self.tabFrames[i].rectValue)) return (NSInteger)i;
    }
    return -1;
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSInteger index = [self indexOfTabAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (index < 0 || ![self.tabDelegate respondsToSelector:@selector(tabBar:menuForIndex:)]) return nil;
    return [self.tabDelegate tabBar:self menuForIndex:index];
}

- (NSRect)closeButtonRectForIndex:(NSInteger)index {
    NSRect tab = [self frameOfTabAtIndex:index];
    if (NSIsEmptyRect(tab)) return NSZeroRect;
    return NSMakeRect(NSMaxX(tab) - kCloseSize - 6,
                      NSMidY(tab) - kCloseSize / 2, kCloseSize, kCloseSize);
}

- (BOOL)point:(NSPoint)point isOnCloseButtonOfIndex:(NSInteger)index {
    if (![self closeButtonVisibleForIndex:index]) return NO;
    return NSPointInRect(point, [self closeButtonRectForIndex:index]);
}

- (BOOL)closeButtonVisibleForIndex:(NSInteger)index {
    if (!self.showCloseButtons) return NO;
    if (index == self.selectedIndex) return YES;
    return self.closeButtonsOnInactiveTabs || index == self.hoverIndex;
}

#pragma mark - Drawing

static NSColor *TabColour(NSInteger colour) {
    switch (colour) {
        case 1: return [NSColor systemRedColor];
        case 2: return [NSColor systemOrangeColor];
        case 3: return [NSColor systemYellowColor];
        case 4: return [NSColor systemGreenColor];
        case 5: return [NSColor systemBlueColor];
        default: return nil;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    // Only the bar's own rectangle: from the macOS 14 SDK on a view is not clipped to its bounds
    // and the rectangle to draw may reach past them - the second view's bar, above its pane in the
    // same host, painted the whole pane over.
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(NSIntersectionRect(dirtyRect, self.bounds));

    CGFloat fontSize = self.reduced ? 11 : 12.5;
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSize],
                            NSForegroundColorAttributeName: (self.colourInactiveTabs && self.inactiveTextColour)
                                ? self.inactiveTextColour : [NSColor labelColor]};
    NSDictionary *activeAttrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize],
                                  NSForegroundColorAttributeName: self.activeTextColour ?: [NSColor labelColor]};

    for (NSUInteger i = 0; i < self.items.count && i < self.tabFrames.count; ++i) {
        NppTabItem *item = self.items[i];
        NSRect tab = self.tabFrames[i].rectValue;
        BOOL active = (NSInteger)i == self.selectedIndex;

        NSColor *inactiveBack = (self.colourInactiveTabs && self.inactiveBackColour)
            ? [self.inactiveBackColour colorWithAlphaComponent:0.35] : [NSColor windowBackgroundColor];
        [(active ? [NSColor controlBackgroundColor] : inactiveBack) setFill];
        NSRectFillUsingOperation(tab, NSCompositingOperationSourceOver);
        // Draw a colored bar on active tab: the focused or unfocused colour.
        if (active && self.drawActiveBar) {
            NSColor *bar = self.window.isKeyWindow && self.inFocusedView ? (self.activeBarColour ?: [NSColor systemOrangeColor])
                                                   : (self.activeBarUnfocusedColour ?: [NSColor systemOrangeColor]);
            [bar setFill];
            NSRectFill(NSMakeRect(NSMinX(tab), self.isFlipped ? NSMinY(tab) : NSMaxY(tab) - 3, NSWidth(tab), 3));
        }
        [[NSColor separatorColor] setStroke];
        NSFrameRect(NSMakeRect(NSMaxX(tab) - 1, NSMinY(tab), 1, NSHeight(tab)));

        // A coloured bar along the active tab, as the Tab bar page offers.
        NSColor *colour = TabColour(item.colour);
        if (colour) {
            [colour setFill];
            NSRectFill(NSMakeRect(NSMinX(tab), NSMinY(tab), NSWidth(tab), active ? 3 : 2));
        }

        CGFloat textLeft = NSMinX(tab) + kPadding;
        if (item.pinned) {
            [@"📌" drawAtPoint:NSMakePoint(textLeft, NSMinY(tab) + 5)
                withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:9]}];
            textLeft += 14;
        }

        BOOL hasClose = [self closeButtonVisibleForIndex:(NSInteger)i];
        CGFloat textRight = NSMaxX(tab) - kPadding - (hasClose ? kCloseSize + 4 : 0);
        NSString *shown = [self displayTitleAtIndex:(NSInteger)i];
        NSString *title = item.modified ? [shown stringByAppendingString:@" •"] : shown;
        NSRect textRect = NSMakeRect(textLeft, NSMinY(tab) + 5,
                                     MAX(0, textRight - textLeft), NSHeight(tab) - 8);
        [title drawInRect:textRect withAttributes:(active ? activeAttrs : attrs)];

        if (hasClose) {
            NSRect close = [self closeButtonRectForIndex:(NSInteger)i];
            NSImage *x = [NSImage imageWithSystemSymbolName:@"xmark.circle.fill"
                                   accessibilityDescription:@"Close"];
            [x drawInRect:close fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                 fraction:((NSInteger)i == self.hoverIndex ? 0.9 : 0.45)];
        }
    }
}

#pragma mark - Mouse

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                       options:(NSTrackingMouseMoved |
                                                                NSTrackingMouseEnteredAndExited |
                                                                NSTrackingActiveInKeyWindow)
                                                         owner:self userInfo:nil]];
}

- (void)mouseMoved:(NSEvent *)event {
    NSInteger was = self.hoverIndex;
    self.hoverIndex = [self indexOfTabAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (was != self.hoverIndex) {
        [self setNeedsDisplay:YES];
        [self tellHover];
    }
}

- (void)mouseExited:(NSEvent *)event {
    self.hoverIndex = -1;
    [self setNeedsDisplay:YES];
    [self tellHover];
}

- (void)tellHover {
    if ([self.tabDelegate respondsToSelector:@selector(tabBar:hoveredIndex:)]) {
        [self.tabDelegate tabBar:self hoveredIndex:self.hoverIndex];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger index = [self indexOfTabAtPoint:p];
    if (index < 0) return;

    if ([self point:p isOnCloseButtonOfIndex:index]) {
        [self.tabDelegate tabBar:self didRequestCloseIndex:index];
        return;
    }
    if (event.clickCount == 2 && self.doubleClickCloses) {
        [self.tabDelegate tabBar:self didRequestCloseIndex:index];
        return;
    }
    self.dragIndex = index;
    self.dragging = NO;
    [self.tabDelegate tabBar:self didSelectIndex:index];
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.locked || self.dragIndex < 0) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger over = [self indexOfTabAtPoint:p];
    if (over < 0 || over == self.dragIndex) return;
    // Pinned tabs stay among themselves, as TabBarPlus::exchangeTabItemData
    // refuses a move across the edge of the pinned run.
    if (over < (NSInteger)self.items.count && self.dragIndex < (NSInteger)self.items.count &&
        self.items[(NSUInteger)over].pinned != self.items[(NSUInteger)self.dragIndex].pinned) return;

    [self.tabDelegate tabBar:self didMoveIndex:self.dragIndex toIndex:over];
    self.dragIndex = over;
    self.dragging = YES;
}

- (void)mouseUp:(NSEvent *)event {
    self.dragIndex = -1;
    self.dragging = NO;
}

@end
