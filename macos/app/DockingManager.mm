#import "DockingManager.h"
#import "SettingsCommands.h"
#import "Localization.h"

NSNotificationName const NppDockPanelVisibilityDidChangeNotification = @"NppDockPanelVisibilityDidChange";

static const CGFloat kHeader = 22;

@interface NppDockPanelRecord : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSView *view;
@property (nonatomic) NppDockPlace place;
@property (nonatomic) NppDockPlace lastDockedPlace;
@property (nonatomic) BOOL visible;
@property (nonatomic) NSRect floatFrame;
/// Floating panels with the same group share one window, as tabs of it; a
/// panel floating alone is its own group.
@property (nonatomic, copy) NSString *floatGroup;
@end
@implementation NppDockPanelRecord
@end

@class NppDockContainerView;

@interface NppDockingManager () <NSWindowDelegate, NSSplitViewDelegate>
@property (nonatomic, weak) NSSplitView *split;
@property (nonatomic, strong) NSSplitView *centerSplit;
@property (nonatomic, weak) NSView *center;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppDockPanelRecord *> *records;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NppDockContainerView *> *containers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSPanel *> *floats;
@property (nonatomic, strong, nullable) NSWindow *dragPreview;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *floatFronts;   // group -> the tab in front
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *fronts;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *sizes;
@property (nonatomic) BOOL arranging;
/// The split view whose divider is being dragged: AppKit asks where it may go
/// (splitView:constrainSplitPosition:ofSubviewAt:) before each move, and the resize that follows is the user's.
@property (nonatomic, weak) NSSplitView *draggedSplit;
- (void)containerClickedPanel:(NSString *)identifier;
- (void)dragOfPanel:(NSString *)identifier endedAtScreenPoint:(NSPoint)point;
- (void)dragOfPanel:(NSString *)identifier movedToScreenPoint:(NSPoint)point;
- (void)endDragPreview;
- (NSMenu *)menuForPanel:(NSString *)identifier;
- (NSString *)titleOf:(NSString *)identifier;
@end

#pragma mark - Container

/// One container: the panels in it as tabs along the top, the one in front below.
@interface NppDockContainerView : NSView
@property (nonatomic) NppDockPlace place;
@property (nonatomic, weak) NppDockingManager *manager;
@property (nonatomic, copy) NSArray<NSString *> *panels;
@property (nonatomic, copy, nullable) NSString *front;
@property (nonatomic, copy, nullable) NSString *dragging;
@property (nonatomic) NSPoint dragStart;
@property (nonatomic) BOOL dragMoved;
@end

@implementation NppDockContainerView

- (BOOL)isFlipped { return YES; }

- (NSArray<NSValue *> *)tabRects {
    NSMutableArray *rects = [NSMutableArray array];
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:11]};
    // Each tab as wide as its title, all of them squeezed alike to leave
    // room for the close button when they do not fit.
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat total = 0;
    for (NSString *p in self.panels) {
        CGFloat w = MIN(180, [[self.manager titleOf:p] sizeWithAttributes:attrs].width + 18);
        [widths addObject:@(w)];
        total += w + 2;
    }
    CGFloat room = NSWidth(self.bounds) - 4 - 26;
    CGFloat scale = (total > room && total > 0) ? room / total : 1;
    CGFloat x = 4;
    for (NSNumber *w in widths) {
        CGFloat width = floor(w.doubleValue * scale);
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, 2, width, kHeader - 4)]];
        x += width + 2;
    }
    return rects;
}

- (NSRect)closeRect { return NSMakeRect(NSWidth(self.bounds) - 20, 4, 14, 14); }

- (void)drawRect:(NSRect)dirty {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0, kHeader - 1, NSWidth(self.bounds), 1));
    NSArray *rects = [self tabRects];
    for (NSUInteger i = 0; i < self.panels.count; ++i) {
        NSRect r = [rects[i] rectValue];
        BOOL front = [self.panels[i] isEqualToString:self.front];
        if (front) {
            [[NSColor controlBackgroundColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
        }
        NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
        para.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary *attrs = @{NSFontAttributeName: front ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:11],
                                NSForegroundColorAttributeName: front ? [NSColor labelColor] : [NSColor secondaryLabelColor],
                                NSParagraphStyleAttributeName: para};
        [[self.manager titleOf:self.panels[i]] drawInRect:NSInsetRect(r, 8, 2) withAttributes:attrs];
    }
    NSImage *x = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"];
    [x drawInRect:[self closeRect] fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.6];
}

- (nullable NSString *)panelAtPoint:(NSPoint)p {
    NSArray *rects = [self tabRects];
    for (NSUInteger i = 0; i < rects.count; ++i) if (NSPointInRect(p, [rects[i] rectValue])) return self.panels[i];
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, [self closeRect])) { if (self.front) [self.manager hidePanel:self.front]; return; }
    NSString *hit = [self panelAtPoint:p];
    if (!hit) return;
    if (event.clickCount == 2) {
        // A double click floats a docked panel and docks a floating one back.
        NppDockPlace now = [self.manager placeOfPanel:hit];
        [self.manager movePanel:hit to:now == NppDockFloating ? NppDockPlace(-1) : NppDockFloating];
        return;
    }
    [self.manager containerClickedPanel:hit];
    self.dragging = hit;
    self.dragStart = p;
    self.dragMoved = NO;
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (hypot(p.x - self.dragStart.x, p.y - self.dragStart.y) > 12) {
        self.dragMoved = YES;
        [[NSCursor closedHandCursor] set];
    }
    // Where it would land, shown while it is dragged, as upstream's gripper draws its rectangle.
    if (self.dragMoved) [self.manager dragOfPanel:self.dragging movedToScreenPoint:[self.window convertPointToScreen:event.locationInWindow]];
}

- (void)mouseUp:(NSEvent *)event {
    NSString *moved = self.dragMoved ? self.dragging : nil;
    self.dragging = nil;
    [self.manager endDragPreview];
    [[NSCursor arrowCursor] set];
    if (!moved) return;
    NSPoint screen = [self.window convertPointToScreen:event.locationInWindow];
    // Let go on its own tab strip: nothing to do.
    NSPoint local = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(local, NSMakeRect(0, 0, NSWidth(self.bounds), kHeader))) return;
    [self.manager dragOfPanel:moved endedAtScreenPoint:screen];
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSString *hit = [self panelAtPoint:[self convertPoint:event.locationInWindow fromView:nil]] ?: self.front;
    return hit ? [self.manager menuForPanel:hit] : nil;
}

@end

#pragma mark - Manager

@implementation NppDockingManager

+ (instancetype)shared {
    static NppDockingManager *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppDockingManager alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _records = [NSMutableDictionary dictionary];
    _order = [NSMutableArray array];
    _containers = [NSMutableDictionary dictionary];
    _floats = [NSMutableDictionary dictionary];
    _floatFronts = [NSMutableDictionary dictionary];
    _fronts = [NSMutableDictionary dictionary];
    _sizes = [@{@(NppDockLeft): @240, @(NppDockRight): @240, @(NppDockTop): @160, @(NppDockBottom): @200} mutableCopy];
    NSDictionary *stored = [NppPreferences shared].dockLayout[@"sizes"];
    for (NSString *key in stored) {
        if ([stored[key] doubleValue] >= 60) self.sizes[@(key.integerValue)] = stored[key];
    }
    return self;
}

- (void)attachToSplit:(NSSplitView *)split center:(NSView *)center {
    self.split = split;
    self.center = center;
    self.centerSplit = [[NSSplitView alloc] initWithFrame:center.frame];
    self.centerSplit.vertical = NO;
    self.centerSplit.dividerStyle = NSSplitViewDividerStyleThin;
    self.centerSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.centerSplit.delegate = self;
    split.delegate = self;
    NSMutableArray *subviews = [split.subviews mutableCopy];
    NSUInteger at = [subviews indexOfObjectIdenticalTo:center];
    if (at == NSNotFound) [subviews addObject:self.centerSplit];
    else subviews[at] = self.centerSplit;
    split.subviews = subviews;
    self.centerSplit.subviews = @[center];
    [self arrange];
}

/// A tab's title in the interface language: upstream names its panels in the
/// Dialog section, and the port's own are in nativeLang-extra.
/// After the interface language changed: the tabs and floating windows draw their titles again.
- (void)relocalize { [self arrange]; }

- (NSString *)titleOf:(NSString *)identifier {
    NSString *title = self.records[identifier].title ?: identifier;
    return [[NppLocalization shared] translateTitle:title];
}

- (void)registerPanel:(NSString *)identifier title:(NSString *)title view:(NSView *)view
         defaultPlace:(NppDockPlace)place {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) {
        r = [[NppDockPanelRecord alloc] init];
        r.identifier = identifier;
        NSDictionary *layout = [NppPreferences shared].dockLayout;
        NSNumber *remembered = layout[@"places"][identifier];
        r.place = remembered ? (NppDockPlace)remembered.integerValue : place;
        NSNumber *docked = layout[@"docked"][identifier];
        r.lastDockedPlace = docked ? (NppDockPlace)docked.integerValue : (place == NppDockFloating ? NppDockRight : place);
        NSString *frame = layout[@"floating"][identifier];
        r.floatFrame = frame ? NSRectFromString(frame) : NSMakeRect(200, 200, 300, 400);
        NSString *group = layout[@"groups"][identifier];
        r.floatGroup = [group isKindOfClass:[NSString class]] && group.length ? group : identifier;
        self.records[identifier] = r;
        [self.order addObject:identifier];
    }
    r.title = title;
    r.view = view;
}

- (BOOL)hasPanel:(NSString *)identifier { return self.records[identifier] != nil; }
- (BOOL)isPanelVisible:(NSString *)identifier { return self.records[identifier].visible; }
- (NppDockPlace)placeOfPanel:(NSString *)identifier { return self.records[identifier].place; }
- (CGFloat)sizeOfPlace:(NppDockPlace)place { return self.sizes[@(place)].doubleValue; }

- (NSArray<NSString *> *)panelsIn:(NppDockPlace)place {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        if (r.visible && r.place == place) [out addObject:ident];
    }
    return out;
}

- (NSString *)frontPanelIn:(NppDockPlace)place {
    NSArray *panels = [self panelsIn:place];
    NSString *front = self.fronts[@(place)];
    return [panels containsObject:front] ? front : panels.lastObject;
}

- (void)showPanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) return;
    BOOL was = r.visible;
    r.visible = YES;
    if (r.place != NppDockFloating) self.fronts[@(r.place)] = identifier;
    // A panel shown for the first time since the language changed was in no
    // window when the windows were localised; its controls are done now (back
    // to English too, when that is the language).
    if (r.view) [[NppLocalization shared] localizeView:r.view];
    [self arrange];
    if (!was) [[NSNotificationCenter defaultCenter] postNotificationName:NppDockPanelVisibilityDidChangeNotification object:identifier];
}

- (void)hidePanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r || !r.visible) return;
    r.visible = NO;
    [self arrange];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppDockPanelVisibilityDidChangeNotification object:identifier];
}

- (void)togglePanel:(NSString *)identifier {
    if ([self isPanelVisible:identifier]) [self hidePanel:identifier];
    else [self showPanel:identifier];
}

- (void)movePanel:(NSString *)identifier to:(NppDockPlace)place {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) return;
    // -1: back where it was last docked.
    if ((NSInteger)place < 0) place = r.lastDockedPlace;
    if (r.place == NppDockFloating) {
        NSPanel *window = self.floats[r.floatGroup];
        if (window) r.floatFrame = window.frame;
    }
    if (place == NppDockFloating && r.place != NppDockFloating) r.floatGroup = identifier;   // on its own, until dropped on another
    r.place = place;
    if (place != NppDockFloating) r.lastDockedPlace = place;
    r.visible = YES;
    if (place != NppDockFloating) self.fronts[@(place)] = identifier;
    [self arrange];
    [self saveLayout];
}

- (void)containerClickedPanel:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    if (!r) return;
    if (r.place == NppDockFloating) self.floatFronts[r.floatGroup] = identifier;
    else self.fronts[@(r.place)] = identifier;
    [self arrange];
    [self saveLayout];
}

- (NSArray<NSString *> *)panelsFloatingWith:(NSString *)identifier {
    NppDockPanelRecord *r = self.records[identifier];
    NSMutableArray *out = [NSMutableArray array];
    if (!r || r.place != NppDockFloating) return out;
    for (NSString *ident in self.order) {
        NppDockPanelRecord *o = self.records[ident];
        if (o.visible && o.place == NppDockFloating && [o.floatGroup isEqualToString:r.floatGroup]) [out addObject:ident];
    }
    return out;
}

- (void)floatPanel:(NSString *)identifier withPanel:(NSString *)other {
    NppDockPanelRecord *r = self.records[identifier], *o = self.records[other];
    if (!r || !o || r == o || o.place != NppDockFloating) return;
    r.place = NppDockFloating;
    r.floatGroup = o.floatGroup;
    r.visible = YES;
    self.floatFronts[o.floatGroup] = identifier;
    [self arrange];
    [self saveLayout];
}

/// The floating group whose window is under a point of the screen, if any.
- (nullable NSString *)floatGroupAtScreenPoint:(NSPoint)point excluding:(NSString *)identifier {
    for (NSString *group in self.floats) {
        NSPanel *window = self.floats[group];
        if (!window.isVisible || !NSPointInRect(point, window.frame)) continue;
        // The window it is already in is not somewhere else to go.
        if (self.records[identifier].place == NppDockFloating && [group isEqualToString:self.records[identifier].floatGroup]) continue;
        return group;
    }
    return nil;
}

- (void)restoreFronts {
    NSDictionary *fronts = [NppPreferences shared].dockLayout[@"fronts"];
    if (![fronts isKindOfClass:[NSDictionary class]]) return;
    for (NSString *placeKey in fronts) {
        NppDockPlace place = (NppDockPlace)placeKey.integerValue;
        NSString *identifier = fronts[placeKey];
        if ([[self panelsIn:place] containsObject:identifier]) self.fronts[@(place)] = identifier;
    }
    [self arrange];
}

- (NppDockPlace)placeForDropAtScreenPoint:(NSPoint)point {
    NSWindow *window = self.split.window;
    if (!window || !NSPointInRect(point, window.frame)) return NppDockFloating;
    NSRect f = window.frame;
    CGFloat fx = (point.x - NSMinX(f)) / MAX(1, NSWidth(f));
    CGFloat fy = (NSMaxY(f) - point.y) / MAX(1, NSHeight(f));   // from the top
    if (fx < 0.25) return NppDockLeft;
    if (fx > 0.75) return NppDockRight;
    if (fy < 0.25) return NppDockTop;
    if (fy > 0.75) return NppDockBottom;
    return NppDockFloating;
}

/// The rectangle, in screen coordinates, a panel dropped at `point` would
/// take: the container's share of the window, or the floating frame.
- (NSRect)previewRectForPanel:(NSString *)identifier atScreenPoint:(NSPoint)point {
    NSString *over = [self floatGroupAtScreenPoint:point excluding:identifier];
    if (over) return self.floats[over].frame;
    NppDockPlace place = [self placeForDropAtScreenPoint:point];
    NSWindow *window = self.split.window;
    NppDockPanelRecord *r = self.records[identifier];
    if (place == NppDockFloating || !window) {
        NSRect frame = r.floatFrame;
        frame.origin = NSMakePoint(point.x - 40, point.y - NSHeight(frame) + 10);
        return frame;
    }
    NSRect area = [window convertRectToScreen:[self.split convertRect:self.split.bounds toView:nil]];
    CGFloat size = [self sizeOfPlace:place] ?: (place == NppDockLeft || place == NppDockRight ? 220 : 160);
    switch (place) {
        case NppDockLeft:   return NSMakeRect(NSMinX(area), NSMinY(area), MIN(size, NSWidth(area)), NSHeight(area));
        case NppDockRight:  return NSMakeRect(NSMaxX(area) - MIN(size, NSWidth(area)), NSMinY(area), MIN(size, NSWidth(area)), NSHeight(area));
        case NppDockTop:    return NSMakeRect(NSMinX(area), NSMaxY(area) - MIN(size, NSHeight(area)), NSWidth(area), MIN(size, NSHeight(area)));
        default:            return NSMakeRect(NSMinX(area), NSMinY(area), NSWidth(area), MIN(size, NSHeight(area)));
    }
}

- (void)dragOfPanel:(NSString *)identifier movedToScreenPoint:(NSPoint)point {
    NSRect rect = [self previewRectForPanel:identifier atScreenPoint:point];
    if (!self.dragPreview) {
        NSWindow *w = [[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless
                                                    backing:NSBackingStoreBuffered defer:NO];
        w.opaque = NO;
        w.ignoresMouseEvents = YES;
        w.level = NSFloatingWindowLevel;
        w.releasedWhenClosed = NO;
        w.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.25];
        self.dragPreview = w;
    }
    [self.dragPreview setFrame:rect display:YES];
    [self.dragPreview orderFront:nil];
}

- (void)endDragPreview {
    [self.dragPreview orderOut:nil];
}

- (void)dragOfPanel:(NSString *)identifier endedAtScreenPoint:(NSPoint)point {
    // Let go over another floating window: a tab of that window.
    NSString *group = [self floatGroupAtScreenPoint:point excluding:identifier];
    if (group) {
        NSString *member = nil;
        for (NSString *ident in self.order) {
            NppDockPanelRecord *o = self.records[ident];
            if (o.visible && o.place == NppDockFloating && [o.floatGroup isEqualToString:group]) { member = ident; break; }
        }
        if (member) { [self floatPanel:identifier withPanel:member]; return; }
    }
    NppDockPlace place = [self placeForDropAtScreenPoint:point];
    if (place == NppDockFloating) {
        NppDockPanelRecord *r = self.records[identifier];
        NSRect frame = r.floatFrame;
        frame.origin = NSMakePoint(point.x - 40, point.y - NSHeight(frame) + 10);
        r.floatFrame = frame;
        if (r.place == NppDockFloating && [self panelsFloatingWith:identifier].count == 1) {
            [self.floats[r.floatGroup] setFrame:frame display:YES];
            [self saveLayout];
            return;
        }
        // Dragged out of a window it shared: a window of its own.
        if (r.place == NppDockFloating) { r.floatGroup = identifier; [self arrange]; [self saveLayout]; return; }
    }
    [self movePanel:identifier to:place];
}

- (NSMenu *)menuForPanel:(NSString *)identifier {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:[self titleOf:identifier]];
    NSArray *choices = @[@[@"Dock Left", @(NppDockLeft)], @[@"Dock Right", @(NppDockRight)],
                         @[@"Dock Top", @(NppDockTop)], @[@"Dock Bottom", @(NppDockBottom)],
                         @[@"Float", @(NppDockFloating)]];
    NppDockPlace now = [self placeOfPanel:identifier];
    for (NSArray *c in choices) {
        NSMenuItem *item = [menu addItemWithTitle:c[0] action:@selector(menuMove:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = @[identifier, c[1]];
        item.state = [c[1] integerValue] == now ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *close = [menu addItemWithTitle:@"Close" action:@selector(menuClose:) keyEquivalent:@""];
    close.target = self;
    close.representedObject = identifier;
    return menu;
}

- (void)menuMove:(NSMenuItem *)item { [self movePanel:item.representedObject[0] to:(NppDockPlace)[item.representedObject[1] integerValue]]; }
- (void)menuClose:(NSMenuItem *)item { [self hidePanel:item.representedObject]; }

#pragma mark Arranging

- (NppDockContainerView *)containerFor:(NppDockPlace)place {
    NppDockContainerView *c = self.containers[@(place)];
    if (!c) {
        c = [[NppDockContainerView alloc] initWithFrame:NSMakeRect(0, 0, 240, 240)];
        c.place = place;
        c.manager = self;
        self.containers[@(place)] = c;
    }
    return c;
}

/// Puts every shown panel in its container or window, the containers around
/// the editor, and each container at its remembered size.
- (void)arrange {
    if (!self.split || self.arranging) return;
    self.arranging = YES;
    for (NSNumber *placeKey in @[@(NppDockLeft), @(NppDockRight), @(NppDockTop), @(NppDockBottom)]) {
        NppDockPlace place = (NppDockPlace)placeKey.integerValue;
        NppDockContainerView *c = [self containerFor:place];
        NSArray *panels = [self panelsIn:place];
        NSString *front = [self frontPanelIn:place];
        c.panels = panels;
        c.front = front;
        // Only the panel in front is in the view tree, as a tab control shows it.
        for (NSView *sub in [c.subviews copy]) [sub removeFromSuperview];
        if (front) {
            NSView *v = self.records[front].view;
            [v removeFromSuperview];
            v.frame = NSMakeRect(0, kHeader, NSWidth(c.bounds), MAX(0, NSHeight(c.bounds) - kHeader));
            v.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [c addSubview:v];
        }
        [c setNeedsDisplay:YES];
    }
    // Floating windows: one for each group of floating panels, its members as tabs.
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *groups = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        if (!r.visible) { [r.view removeFromSuperview]; continue; }
        if (r.place != NppDockFloating) continue;
        NSString *group = r.floatGroup ?: ident;
        if (!groups[group]) { groups[group] = [NSMutableArray array]; [groupOrder addObject:group]; }
        [groups[group] addObject:ident];
    }
    for (NSString *group in [self.floats.allKeys copy]) {
        if (groups[group]) continue;
        NSPanel *window = self.floats[group];
        for (NSString *ident in self.order) {
            NppDockPanelRecord *r = self.records[ident];
            if ([r.floatGroup isEqualToString:group] && r.place == NppDockFloating) r.floatFrame = window.frame;
        }
        window.delegate = nil;
        [window orderOut:nil];
        [self.floats removeObjectForKey:group];
    }
    for (NSString *group in groupOrder) {
        NSArray<NSString *> *members = groups[group];
        NSString *front = [members containsObject:self.floatFronts[group] ?: @""] ? self.floatFronts[group] : members.lastObject;
        NppDockPanelRecord *shown = self.records[front];
        NSPanel *window = self.floats[group];
        if (!window) {
            NSRect frame = self.records[members.firstObject].floatFrame;
            window = [[NSPanel alloc] initWithContentRect:frame
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                  backing:NSBackingStoreBuffered defer:YES];
            window.releasedWhenClosed = NO;
            window.floatingPanel = YES;
            window.delegate = self;
            self.floats[group] = window;
            [window setFrame:frame display:NO];
        }
        window.title = [self titleOf:shown.identifier];
        NppDockContainerView *holder = [[NppDockContainerView alloc] initWithFrame:[window contentRectForFrameRect:window.frame]];
        holder.place = NppDockFloating;
        holder.manager = self;
        holder.panels = members;
        holder.front = front;
        for (NSString *ident in members) if (![ident isEqualToString:front]) [self.records[ident].view removeFromSuperview];
        [shown.view removeFromSuperview];
        shown.view.frame = NSMakeRect(0, kHeader, NSWidth(holder.bounds), MAX(0, NSHeight(holder.bounds) - kHeader));
        shown.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [holder addSubview:shown.view];
        holder.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        window.contentView = holder;
        [window orderFront:nil];
    }
    // The containers that have something, around the editor.
    NSMutableArray *row = [NSMutableArray array];
    if ([self panelsIn:NppDockLeft].count) [row addObject:[self containerFor:NppDockLeft]];
    [row addObject:self.centerSplit];
    if ([self panelsIn:NppDockRight].count) [row addObject:[self containerFor:NppDockRight]];
    NSMutableArray *column = [NSMutableArray array];
    if ([self panelsIn:NppDockTop].count) [column addObject:[self containerFor:NppDockTop]];
    if (self.center) [column addObject:self.center];
    if ([self panelsIn:NppDockBottom].count) [column addObject:[self containerFor:NppDockBottom]];
    // The split may hold other views the editor put there; they are kept, in front of the row.
    NSMutableArray *others = [NSMutableArray array];
    for (NSView *v in self.split.subviews) {
        if (v != self.centerSplit && ![self.containers.allValues containsObject:(NppDockContainerView *)v]) [others addObject:v];
    }
    NSArray *wantedRow = [others arrayByAddingObjectsFromArray:row];
    if (![self.split.subviews isEqualToArray:wantedRow]) self.split.subviews = wantedRow;
    if (![self.centerSplit.subviews isEqualToArray:column]) self.centerSplit.subviews = column;
    [self.split adjustSubviews];
    [self.centerSplit adjustSubviews];
    // Sizes: the side containers by width, the others by height.
    CGFloat width = NSWidth(self.split.bounds), height = NSHeight(self.centerSplit.bounds);
    NSUInteger leftIndex = [self.split.subviews indexOfObject:[self containerFor:NppDockLeft]];
    NSUInteger rightIndex = [self.split.subviews indexOfObject:[self containerFor:NppDockRight]];
    if (leftIndex != NSNotFound) [self.split setPosition:NSMinX(self.split.subviews[leftIndex].frame) + [self sizeOfPlace:NppDockLeft] ofDividerAtIndex:(NSInteger)leftIndex];
    if (rightIndex != NSNotFound && rightIndex > 0) [self.split setPosition:width - [self sizeOfPlace:NppDockRight] ofDividerAtIndex:(NSInteger)rightIndex - 1];
    NSUInteger topIndex = [self.centerSplit.subviews indexOfObject:[self containerFor:NppDockTop]];
    NSUInteger bottomIndex = [self.centerSplit.subviews indexOfObject:[self containerFor:NppDockBottom]];
    if (topIndex != NSNotFound) [self.centerSplit setPosition:[self sizeOfPlace:NppDockTop] ofDividerAtIndex:(NSInteger)topIndex];
    if (bottomIndex != NSNotFound && bottomIndex > 0) [self.centerSplit setPosition:height - [self sizeOfPlace:NppDockBottom] ofDividerAtIndex:(NSInteger)bottomIndex - 1];
    self.arranging = NO;
}

#pragma mark Remembering

- (void)saveLayout {
    // What is stored of panels not made yet this run (the Function List is registered when it is first
    // shown) is kept: saved at launch without them, their places were lost.
    NSDictionary *stored = [NppPreferences shared].dockLayout;
    NSMutableDictionary *(^kept)(NSString *) = ^NSMutableDictionary *(NSString *key) {
        id d = stored[key];
        return [d isKindOfClass:[NSDictionary class]] ? [d mutableCopy] : [NSMutableDictionary dictionary];
    };
    NSMutableDictionary *places = kept(@"places"), *docked = kept(@"docked");
    NSMutableDictionary *floating = kept(@"floating"), *sizes = [NSMutableDictionary dictionary];
    NSMutableDictionary *groupsOut = kept(@"groups");
    for (NSString *ident in self.order) {
        NppDockPanelRecord *r = self.records[ident];
        places[ident] = @(r.place);
        docked[ident] = @(r.lastDockedPlace);
        NSPanel *window = r.place == NppDockFloating ? self.floats[r.floatGroup ?: ident] : nil;
        floating[ident] = NSStringFromRect(window ? window.frame : r.floatFrame);
        groupsOut[ident] = r.floatGroup ?: ident;
    }
    for (NSNumber *place in self.sizes) sizes[place.stringValue] = self.sizes[place];
    // Which tab of each container is in front.
    NSMutableDictionary *fronts = [NSMutableDictionary dictionary];
    for (NSNumber *place in @[@(NppDockLeft), @(NppDockRight), @(NppDockTop), @(NppDockBottom)]) {
        NSString *front = [self frontPanelIn:(NppDockPlace)place.integerValue];
        if (front) fronts[place.stringValue] = front;
    }
    [NppPreferences shared].dockLayout = @{@"places": places, @"docked": docked, @"floating": floating, @"sizes": sizes,
                                           @"fronts": fronts, @"groups": groupsOut};
}

/// Asked only while the user drags a divider - never for a window resized or a layout pass.
- (CGFloat)splitView:(NSSplitView *)splitView constrainSplitPosition:(CGFloat)position ofSubviewAt:(NSInteger)index {
    self.draggedSplit = splitView;
    return position;
}

/// A divider dragged: the container's new size is kept. The window resized is not that: the
/// docks keep their size then and the editor takes the difference (splitView:shouldAdjustSizeOfSubview:).
/// Neither the event (NSApp.currentEvent is still the last click) nor the split view's size (AppKit
/// adjusts the subviews again after a resize, to whole pixels) tells the two apart; the drag's own
/// question does.
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    // The split view dragged in, not the one inside it that its move resizes.
    BOOL dragged = note.object == self.draggedSplit;
    if (dragged) self.draggedSplit = nil;
    if (self.arranging || !dragged) return;
    for (NSNumber *placeKey in @[@(NppDockLeft), @(NppDockRight), @(NppDockTop), @(NppDockBottom)]) {
        NppDockContainerView *c = self.containers[placeKey];
        if (!c.superview || c.hidden) continue;
        BOOL side = placeKey.integerValue == NppDockLeft || placeKey.integerValue == NppDockRight;
        CGFloat size = side ? NSWidth(c.frame) : NSHeight(c.frame);
        if (size >= 60) self.sizes[placeKey] = @(size);
    }
    [self saveLayout];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview { return NO; }

/// As Notepad++'s docks: a window made wider or narrower changes the editor, not the panels.
- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view {
    return ![self.containers.allValues containsObject:(NppDockContainerView *)view];
}

- (BOOL)windowShouldClose:(NSWindow *)window {
    for (NSString *group in [self.floats.allKeys copy]) {
        if (self.floats[group] != window) continue;
        // Its close box closes the window, and with it every panel it holds.
        for (NSString *ident in [self.order copy]) {
            NppDockPanelRecord *r = self.records[ident];
            if (r.visible && r.place == NppDockFloating && [r.floatGroup isEqualToString:group]) [self hidePanel:ident];
        }
        break;
    }
    return NO;
}

- (void)windowDidMove:(NSNotification *)note { [self saveLayout]; }
- (void)windowDidResize:(NSNotification *)note { [self saveLayout]; }

@end
