#import "NppPanel.h"
#import "SettingsPanels.h"
#import "Localization.h"
#import "SettingsCommands.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#import "Toolbar.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"

#pragma mark - Preferences

/// Preferences > Language: languages shown in the menu and those left out,
/// moved between the two lists as upstream's "->" and "<-" do.
@interface NppLanguageListsView : NSView <NSTableViewDataSource>
@property (nonatomic, strong) NSMutableArray<NSString *> *shown;
@property (nonatomic, strong) NSMutableArray<NSString *> *hiddenLanguages;
@property (nonatomic, strong) NSTableView *shownTable, *hiddenTable;
- (instancetype)initWithFrame:(NSRect)frame hidden:(NSArray<NSString *> *)hiddenNames;
- (void)hideSelected:(nullable id)sender;
- (void)showSelected:(nullable id)sender;
@end

@implementation NppLanguageListsView
- (instancetype)initWithFrame:(NSRect)frame hidden:(NSArray<NSString *> *)hiddenNames {
    if (!(self = [super initWithFrame:frame])) return nil;
    _hiddenLanguages = [hiddenNames mutableCopy] ?: [NSMutableArray array];
    _shown = [NSMutableArray array];
    for (NppLanguage *l in [LanguageCatalog sharedCatalog].allLanguages) {
        if (!l.userDefined && ![_hiddenLanguages containsObject:l.name]) [_shown addObject:l.name];
    }
    [_shown sortUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
        return [[LanguageCatalog menuTitleForLanguage:x] caseInsensitiveCompare:[LanguageCatalog menuTitleForLanguage:y]];
    }];
    CGFloat w = (NSWidth(frame) - 60) / 2, h = NSHeight(frame) - 20;
    NSTableView *(^list)(CGFloat, NSString *) = ^NSTableView *(CGFloat x, NSString *title) {
        NSTextField *label = [NSTextField labelWithString:title];
        label.frame = NSMakeRect(x, h + 2, w, 18);
        [self addSubview:label];
        NSTableView *t = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"lang"];
        c.width = w - 4;
        [t addTableColumn:c];
        t.headerView = nil;
        t.allowsMultipleSelection = YES;
        t.dataSource = self;
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, 0, w, h)];
        sv.hasVerticalScroller = YES;
        sv.borderType = NSBezelBorder;
        sv.documentView = t;
        [self addSubview:sv];
        return t;
    };
    _shownTable = list(0, @"Available items");
    _hiddenTable = list(w + 60, @"Disabled items");
    NSButton *right = [NSButton buttonWithTitle:@"→" target:self action:@selector(hideSelected:)];
    right.frame = NSMakeRect(w + 10, h / 2 + 4, 40, 26);
    NSButton *left = [NSButton buttonWithTitle:@"←" target:self action:@selector(showSelected:)];
    left.frame = NSMakeRect(w + 10, h / 2 - 28, 40, 26);
    [self addSubview:right];
    [self addSubview:left];
    return self;
}
- (void)move:(NSTableView *)from source:(NSMutableArray *)src to:(NSMutableArray *)dst {
    NSArray *picked = [src objectsAtIndexes:[from.selectedRowIndexes indexesPassingTest:^BOOL(NSUInteger i, BOOL *st) { return i < src.count; }]];
    [src removeObjectsInArray:picked];
    [dst addObjectsFromArray:picked];
    [dst sortUsingComparator:^NSComparisonResult(NSString *x, NSString *y) {
        return [[LanguageCatalog menuTitleForLanguage:x] caseInsensitiveCompare:[LanguageCatalog menuTitleForLanguage:y]];
    }];
    [self.shownTable reloadData];
    [self.hiddenTable reloadData];
}
- (void)hideSelected:(id)sender { [self move:self.shownTable source:self.shown to:self.hiddenLanguages]; }
- (void)showSelected:(id)sender { [self move:self.hiddenTable source:self.hiddenLanguages to:self.shown]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)(tv == self.shownTable ? self.shown : self.hiddenLanguages).count; }
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row {
    NSArray *a = tv == self.shownTable ? self.shown : self.hiddenLanguages;
    return row >= 0 && row < (NSInteger)a.count ? [LanguageCatalog menuTitleForLanguage:a[(NSUInteger)row]] : @"";
}
@end

/// Preferences > Indentation: the indent settings of one language at a time,
/// "[Default]" first, as upstream's list of languages does.
@interface NppLanguageIndentView : NSView
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *draft;
@property (nonatomic, strong) NSPopUpButton *language;
@property (nonatomic, strong) NSButton *useDefault;
@property (nonatomic, strong) NSTextField *size;
@property (nonatomic, strong) NSPopUpButton *using_;
- (instancetype)initWithFrame:(NSRect)frame settings:(NSDictionary *)settings;
@end

@implementation NppLanguageIndentView
- (instancetype)initWithFrame:(NSRect)frame settings:(NSDictionary *)settings {
    if (!(self = [super initWithFrame:frame])) return nil;
    _draft = [settings mutableCopy] ?: [NSMutableDictionary dictionary];
    NSTextField *label = [NSTextField labelWithString:@"Indent Settings for"];
    label.frame = NSMakeRect(0, 64, 190, 20);
    [self addSubview:label];
    _language = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 60, 220, 26)];
    NSMutableArray *names = [NSMutableArray array];
    for (NppLanguage *l in [LanguageCatalog sharedCatalog].allLanguages) if (!l.userDefined) [names addObject:l.name];
    [names sortUsingSelector:@selector(caseInsensitiveCompare:)];
    [_language addItemsWithTitles:names];
    _language.target = self;
    _language.action = @selector(languageChosen:);
    [self addSubview:_language];
    _useDefault = [NSButton checkboxWithTitle:@"Use default value" target:self action:@selector(changed:)];
    _useDefault.frame = NSMakeRect(0, 34, 200, 20);
    [self addSubview:_useDefault];
    NSTextField *sizeLabel = [NSTextField labelWithString:@"Indent size:"];
    sizeLabel.frame = NSMakeRect(200, 34, 80, 20);
    [self addSubview:sizeLabel];
    _size = [[NSTextField alloc] initWithFrame:NSMakeRect(280, 32, 40, 22)];
    _size.target = self;
    _size.action = @selector(changed:);
    [self addSubview:_size];
    _using_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(200, 0, 220, 26)];
    [_using_ addItemsWithTitles:@[@"Tab character", @"Space character(s)"]];
    _using_.target = self;
    _using_.action = @selector(changed:);
    [self addSubview:_using_];
    [self languageChosen:nil];
    return self;
}
- (void)languageChosen:(id)sender {
    NSDictionary *own = self.draft[self.language.titleOfSelectedItem];
    NppPreferences *p = [NppPreferences shared];
    self.useDefault.state = own ? NSControlStateValueOff : NSControlStateValueOn;
    self.size.stringValue = [@(own ? [own[@"size"] integerValue] : p.tabWidth) stringValue];
    [self.using_ selectItemAtIndex:(own ? [own[@"spaces"] boolValue] : p.useSpaces) ? 1 : 0];
    self.size.enabled = self.using_.enabled = !own ? NO : YES;
}
- (void)changed:(id)sender {
    NSString *lang = self.language.titleOfSelectedItem;
    if (self.useDefault.state == NSControlStateValueOn) {
        [self.draft removeObjectForKey:lang];
    } else {
        self.draft[lang] = @{@"size": @(MAX(1, self.size.integerValue)), @"spaces": @(self.using_.indexOfSelectedItem == 1)};
    }
    self.size.enabled = self.using_.enabled = self.useDefault.state != NSControlStateValueOn;
}
@end

/// A few radio buttons standing where a pop-up would: asked for its choice the same way.
@interface NppRadioGroup : NSObject
@property (nonatomic, copy) NSArray<NSButton *> *buttons;
- (NSInteger)indexOfSelectedItem;
- (void)selectItemAtIndex:(NSInteger)index;
- (void)chosen:(id)sender;
@end

@implementation NppRadioGroup
- (NSInteger)indexOfSelectedItem {
    for (NSUInteger i = 0; i < self.buttons.count; ++i) if (self.buttons[i].state == NSControlStateValueOn) return (NSInteger)i;
    return -1;
}
- (void)selectItemAtIndex:(NSInteger)index {
    for (NSUInteger i = 0; i < self.buttons.count; ++i) self.buttons[i].state = (NSInteger)i == index ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)chosen:(id)sender {
    for (NSButton *b in self.buttons) b.state = b == sender ? NSControlStateValueOn : NSControlStateValueOff;
}
@end

@interface PreferencesWindow () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableDictionary *controls;
/// Notepad++ lists its categories down the left and shows one page at a time;
/// this keeps the pages in that order, by the names it gives them.
@property (nonatomic, strong) NSMutableArray<NSString *> *pageNames;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSView *> *pages;
@property (nonatomic, strong) NSTableView *categories;
@property (nonatomic, strong) NSView *pageHost;
@property (nonatomic, strong) NSScrollView *pageScroller;
@property (nonatomic, copy, nullable) NSString *lastPrintField;
@property (nonatomic, copy) NSArray<NSString *> *localizationFiles;
@end

@implementation PreferencesWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _controls = [NSMutableDictionary dictionary];
    _pageNames = [NSMutableArray array];
    _pages = [NSMutableDictionary dictionary];

    NSRect frame = NSMakeRect(0, 0, 820, 560);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable |
                                                   NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Preferences";
    _panel.releasedWhenClosed = NO;

    // A plain NSView paints nothing, which leaves white behind the buttons and,
    // in dark mode, white labels on it. This follows the appearance instead.
    NSVisualEffectView *content = [[NSVisualEffectView alloc] initWithFrame:frame];
    content.material = NSVisualEffectMaterialWindowBackground;
    content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    content.state = NSVisualEffectStateActive;

    // The category list, down the left as Notepad++ has it.
    NSScrollView *listScroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 52, 220, 508)];
    listScroller.hasVerticalScroller = YES;
    listScroller.autoresizingMask = NSViewHeightSizable;
    _categories = [[NSTableView alloc] initWithFrame:listScroller.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"page"];
    column.width = 200;
    [_categories addTableColumn:column];
    _categories.headerView = nil;
    _categories.dataSource = self;
    _categories.delegate = self;
    _categories.rowHeight = 22;
    listScroller.documentView = _categories;
    [content addSubview:listScroller];

    // The page itself, scrolling in case a page is taller than the window.
    _pageScroller = [[NSScrollView alloc] initWithFrame:NSMakeRect(220, 52, 600, 508)];
    _pageScroller.hasVerticalScroller = YES;
    // The scroller paints the standard background. Leaving it transparent shows
    // white behind the page, and in dark mode the labels are white too.
    _pageScroller.drawsBackground = YES;
    _pageScroller.backgroundColor = NSColor.windowBackgroundColor;
    _pageScroller.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_pageScroller];

    [self buildPages];

    NSButton *apply = [[NSButton alloc] initWithFrame:NSMakeRect(700, 12, 100, 28)];
    apply.title = @"Apply";
    apply.bezelStyle = NSBezelStyleRounded;
    apply.target = self;
    apply.action = @selector(apply:);
    apply.keyEquivalent = @"\r";              // Enter applies
    apply.autoresizingMask = NSViewMinXMargin;
    [content addSubview:apply];

    // Cancel: close without keeping what was changed; the pages are built
    // again from the settings, so nothing half-edited survives to the next time.
    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(480, 12, 100, 28)];
    cancel.title = @"Cancel";
    cancel.bezelStyle = NSBezelStyleRounded;
    cancel.target = self;
    cancel.action = @selector(cancel:);
    cancel.keyEquivalent = @"\033";
    cancel.autoresizingMask = NSViewMinXMargin;
    [content addSubview:cancel];

    NSButton *reset = [[NSButton alloc] initWithFrame:NSMakeRect(590, 12, 100, 28)];
    reset.title = @"Reset";
    reset.bezelStyle = NSBezelStyleRounded;
    reset.target = self;
    reset.action = @selector(resetAll:);
    reset.autoresizingMask = NSViewMinXMargin;
    [content addSubview:reset];

    _panel.contentView = content;
    [_categories selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self showPageAtIndex:0];
    return self;
}

#pragma mark - Pages

/// Starts a page and returns the y to begin laying out at. Pages are tall
/// enough for their contents; the scroller deals with the rest.
- (CGFloat)beginPage:(NSString *)name {
    NSView *page = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 520)];
    [self.pageNames addObject:name];
    self.pages[name] = page;
    return 480;
}

- (NSView *)page:(NSString *)name { return self.pages[name]; }

/// Sizes the page to what was actually put on it, so short pages do not scroll.
- (void)endPage:(NSString *)name atY:(CGFloat)y {
    NSView *page = self.pages[name];
    CGFloat used = 500 - y;
    CGFloat height = MAX((CGFloat)500, used + 40);
    NSRect frame = page.frame;
    // Everything was laid out from the top of a 520-tall page, so when the page
    // grows the contents have to move with it.
    CGFloat shift = height - NSHeight(frame);
    if (shift != 0) {
        for (NSView *child in page.subviews) {
            NSRect r = child.frame;
            r.origin.y += shift;
            child.frame = r;
        }
    }
    frame.size.height = height;
    page.frame = frame;
    // In the interface language first, then made to fit: a translation is
    // often longer than the English it stands for.
    // (Always: a label written "Group|Field" is put together there even in English.)
    [[NppLocalization shared] localizeView:page];
    [self fitTextsOfPage:page];
}

/// The width a label or a checkbox needs for its whole title on one line.
static CGFloat NeededWidth(NSControl *control) {
    // (cellSizeForBounds: gives nonsense for unbounded bounds; cellSize is the size unconstrained.)
    return ceil(control.cell.cellSize.width) + 2;
}

/// Nothing on a page is cut short or ends in an ellipsis: a title that does
/// not fit its control is given the room beside it, and when that is not
/// enough it goes onto more lines and what lies below moves down.
- (void)fitTextsOfPage:(NSView *)page {
    const CGFloat rightEdge = NSWidth(page.bounds) - 12;
    NSArray<NSView *> *fromTheTop = [page.subviews sortedArrayUsingComparator:^NSComparisonResult(NSView *a, NSView *b) {
        return NSMaxY(a.frame) > NSMaxY(b.frame) ? NSOrderedAscending : NSMaxY(a.frame) < NSMaxY(b.frame) ? NSOrderedDescending : NSOrderedSame;
    }];
    CGFloat grownBy = 0;
    for (NSView *view in fromTheTop) {
        BOOL label = [view isKindOfClass:[NSTextField class]] && !((NSTextField *)view).editable && !((NSTextField *)view).bezeled;
        // (Checkboxes and radio buttons: the buttons that show their state in their image.)
        BOOL toggle = [view isKindOfClass:[NSButton class]] && ![view isKindOfClass:[NSPopUpButton class]] &&
                      (((NSButtonCell *)((NSButton *)view).cell).showsStateBy & NSContentsCellMask) && ((NSButton *)view).title.length;
        BOOL field = [view isKindOfClass:[NSTextField class]] && ((NSTextField *)view).editable &&
                     ![view isKindOfClass:[NSComboBox class]];
        BOOL popup = [view isKindOfClass:[NSPopUpButton class]];
        if (!label && !toggle && !popup && !field) continue;
        NSControl *control = (NSControl *)view;
        NSRect frame = control.frame;
        // The room to the right: up to the next thing on the same row, or the page's edge.
        CGFloat limit = rightEdge;
        for (NSView *other in page.subviews) {
            if (other == view || other.hidden) continue;
            BOOL sameRow = NSMinY(other.frame) < NSMaxY(frame) - 2 && NSMaxY(other.frame) > NSMinY(frame) + 2;
            if (sameRow && NSMinX(other.frame) >= NSMinX(frame) + 8) limit = MIN(limit, NSMinX(other.frame) - 6);
        }
        CGFloat room = MAX(40, limit - NSMinX(frame));
        if (field) {
            // What is in it should be readable without scrolling, where there is room.
            CGFloat wanted = NeededWidth((NSControl *)view) + 16;
            if (wanted > NSWidth(frame)) { frame.size.width = MIN(wanted, room); view.frame = frame; }
            continue;
        }
        if (popup) {
            // As wide as its longest item, within the room there is.
            NSPopUpButton *p = (NSPopUpButton *)view;
            NSInteger chosen = p.indexOfSelectedItem;
            CGFloat widest = NSWidth(frame);
            for (NSInteger i = 0; i < p.numberOfItems; ++i) {
                [p selectItemAtIndex:i];
                widest = MAX(widest, NeededWidth(p));
            }
            [p selectItemAtIndex:chosen];
            if (widest > room && NSMinX(frame) > 60) {
                // Too long to sit beside its caption: a row of its own below it.
                CGFloat drop = 30;
                CGFloat wasBottom = NSMinY(frame);
                for (NSView *below in page.subviews) {
                    if (below == view) continue;
                    if (NSMaxY(below.frame) <= wasBottom + 2) {
                        NSRect r = below.frame;
                        r.origin.y -= drop;
                        below.frame = r;
                    }
                }
                frame.origin.x = 36;
                frame.origin.y -= drop;
                room = rightEdge - 36;
                grownBy += drop;
            }
            frame.size.width = MIN(widest, room);
            control.frame = frame;
            continue;
        }
        CGFloat needed = NeededWidth(control);
        if (needed <= NSWidth(frame)) continue;
        if (needed <= room) { frame.size.width = needed; control.frame = frame; continue; }
        // More lines.
        control.cell.wraps = YES;
        control.cell.lineBreakMode = NSLineBreakByWordWrapping;
        if (label) { ((NSTextField *)control).maximumNumberOfLines = 0; control.cell.truncatesLastVisibleLine = NO; }
        frame.size.width = room;
        CGFloat tall = ceil([control.cell cellSizeForBounds:NSMakeRect(0, 0, room, 10000)].height);
        CGFloat more = MAX(0, tall - NSHeight(frame));
        frame.size.height += more;
        frame.origin.y -= more;
        control.frame = frame;
        if (more <= 0) continue;
        CGFloat wasBottom = NSMinY(frame) + more;
        for (NSView *below in page.subviews) {
            if (below == view) continue;
            if (NSMaxY(below.frame) <= wasBottom + 2) {
                NSRect r = below.frame;
                r.origin.y -= more;
                below.frame = r;
            }
        }
        grownBy += more;
    }
    if (grownBy > 0) {
        for (NSView *child in page.subviews) {
            NSRect r = child.frame;
            r.origin.y += grownBy;
            child.frame = r;
        }
        NSRect f = page.frame;
        f.size.height += grownBy;
        page.frame = f;
    }
}

- (void)showPageAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.pageNames.count) return;
    NSView *page = self.pages[self.pageNames[(NSUInteger)index]];
    self.pageScroller.documentView = page;
    // The list shows which page this is, however it was reached.
    if (self.categories.selectedRow != index) {
        [self.categories selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] byExtendingSelection:NO];
    }
    [self.pageScroller.contentView scrollToPoint:
        NSMakePoint(0, MAX((CGFloat)0, NSHeight(page.frame) - NSHeight(self.pageScroller.bounds)))];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.pageNames.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column
            row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.pageNames.count) return @"";
    // Shown in the interface language; kept in English for the page lookups.
    return [[NppLocalization shared] translateTitle:self.pageNames[(NSUInteger)row]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self showPageAtIndex:self.categories.selectedRow];
}

/// Every page, with the names and the grouping Notepad++ uses.
- (void)buildPages {
    NppPreferences *p = [NppPreferences shared];
    NSView *v; CGFloat y;

    y = [self beginPage:@"General"]; v = [self page:@"General"];
    // Localization: upstream's translations, by the names they give themselves.
    NSDictionary<NSString *, NSString *> *languages = [NppLocalization availableLanguages];
    NSArray *files = [languages.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [languages[a] localizedCaseInsensitiveCompare:languages[b]];
    }];
    NSMutableArray *names = [NSMutableArray array];
    // NSPopUpButton drops repeated titles, which would shift every index after
    // it (english.xml and english_customizable.xml both say "English").
    NSCountedSet *seen = [[NSCountedSet alloc] initWithArray:languages.allValues];
    for (NSString *f in files) {
        NSString *name = languages[f];
        [names addObject:[seen countForObject:name] > 1
            ? [NSString stringWithFormat:@"%@ (%@)", name, f.stringByDeletingPathExtension] : name];
    }
    NSUInteger chosen = [files indexOfObject:p.localizationFile.length ? p.localizationFile : @"english.xml"];
    y = [self addPopup:@"Localization" key:@"localizationFile" items:names
              selected:chosen == NSNotFound ? 0 : (NSInteger)chosen to:v atY:y];
    self.localizationFiles = files;
    y = [self addCheckbox:@"Remember current session for next launch" key:@"restoreSession"
                       on:p.restoreSession to:v atY:y];
    y = [self addCheckbox:@"Remember which panels were open" key:@"rememberPanelState"
                       on:p.rememberPanelState to:v atY:y];
    for (NSArray *panel in @[@[@"clipboardHistory", @"Clipboard History"], @[@"documentList", @"Document List"],
                             @[@"characterPanel", @"Character Panel"], @[@"workspace", @"Folder as Workspace"],
                             @[@"projectPanel", @"Project Panels"], @[@"documentMap", @"Document Map"],
                             @[@"functionList", @"Function List"]]) {
        y = [self addCheckbox:[@"    " stringByAppendingString:panel[1]] key:[@"panelKeep." stringByAppendingString:panel[0]]
                           on:[p keepsPanelState:panel[0]] to:v atY:y];
    }
    // Radio buttons, as upstream has them: the third choice is a sentence, and a
    // sentence can go onto a second line where a pop-up could only cut it short.
    y = [self addRadios:@"Multi-instance settings *" key:@"multiInstanceMode"
                  items:@[@"Default (mono-instance)", @"Always in multi-instance mode",
                          @"Open session in a new instance (and save session automatically on exit)"]
               selected:p.multiInstanceMode to:v atY:y];
    y = [self addCheckbox:@"File Status Auto-Detection"
                      key:@"fileAutoDetection" on:p.fileAutoDetection to:v atY:y];
    y = [self addCheckbox:@"    Update silently" key:@"fileAutoDetectionSilent"
                       on:p.fileAutoDetectionSilent to:v atY:y];
    y = [self addCheckbox:@"    Scroll to the last line after update" key:@"fileAutoDetectionScrollToEnd"
                       on:p.fileAutoDetectionScrollToEnd to:v atY:y];
    y = [self addCheckbox:@"Autodetect character encoding"
                      key:@"autoDetectCharacterEncoding" on:p.autoDetectCharacterEncoding to:v atY:y];
    y = [self addCheckbox:@"Status Bar|Hide" key:@"statusBarHidden" on:p.statusBarHidden to:v atY:y];
    [self endPage:@"General" atY:y];

    y = [self beginPage:@"Toolbar"]; v = [self page:@"Toolbar"];
    y = [self addCheckbox:@"Show the toolbar" key:@"showToolbar" on:p.showToolbar to:v atY:y];
    y = [self addPopup:@"Toolbar buttons" key:@"toolbarDisplayMode"
                 items:@[@"Icons only", @"Icons and labels", @"Labels only"]
              selected:p.toolbarDisplayMode to:v atY:y];
    y = [self addPopup:@"Toolbar size" key:@"toolbarIconSize" items:@[@"Regular", @"Small"]
              selected:p.toolbarIconSize to:v atY:y];
    y = [self addPopup:@"Icons" key:@"toolbarFilledIcons" items:@[@"Fluent UI", @"Filled Fluent UI"]
              selected:p.toolbarFilledIcons ? 1 : 0 to:v atY:y];
    y = [self addPopup:@"Color choice" key:@"toolbarIconColour"
                 items:@[@"Default", @"Red", @"Green", @"Blue", @"Purple", @"Cyan", @"Olive", @"Yellow",
                         @"System Accent", @"Custom"]
              selected:p.toolbarIconColour to:v atY:y];
    y = [self addField:@"Color choice|Custom" key:@"toolbarIconCustomColour" value:p.toolbarIconCustomColour to:v atY:y];
    y = [self addPopup:@"Colorization" key:@"toolbarColorizeComplete" items:@[@"Partial", @"Complete"]
              selected:p.toolbarColorizeComplete ? 1 : 0 to:v atY:y];
    [self endPage:@"Toolbar" atY:y];

    y = [self beginPage:@"Editing 1"]; v = [self page:@"Editing 1"];
    y = [self addField:@"Font name:" key:@"fontName" value:p.fontName to:v atY:y];
    y = [self addField:@"Font size" key:@"fontSize"
                  value:[@(p.fontSize) stringValue] to:v atY:y];
    y = [self addPopup:@"Caret Settings|Width:" key:@"caretWidth"
                 items:@[@"Hidden", @"1 pixel", @"2 pixels", @"3 pixels"]
              selected:p.caretWidth to:v atY:y];
    y = [self addField:@"Caret Settings|Blink rate:" key:@"caretBlinkRate"
                  value:[@(p.caretBlinkRate) stringValue] to:v atY:y];
    y = [self addPopup:@"Current Line Indicator" key:@"currentLineHighlightMode"
                 items:@[@"None", @"Highlight Background", @"Frame"]
              selected:p.currentLineHighlightMode to:v atY:y];
    y = [self addField:@"Frame|Width:" key:@"currentLineFrameWidth"
                  value:[@(p.currentLineFrameWidth) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Enable scrolling beyond last line" key:@"scrollBeyondLastLine"
                       on:p.scrollBeyondLastLine to:v atY:y];
    y = [self addCheckbox:@"Enable virtual space" key:@"virtualSpace"
                       on:p.virtualSpace to:v atY:y];
    y = [self addCheckbox:@"Enable Copy/Cut Line without selection"
                      key:@"lineCopyCutWithoutSelection"
                       on:p.lineCopyCutWithoutSelection to:v atY:y];
    y = [self addCheckbox:@"Selected text can be dragged" key:@"selectedTextDragDrop"
                       on:p.selectedTextDragDrop to:v atY:y];
    y = [self addCheckbox:@"Keep selection when right-click outside of selection" key:@"rightClickKeepsSelection"
                       on:p.rightClickKeepsSelection to:v atY:y];
    [self endPage:@"Editing 1" atY:y];

    y = [self beginPage:@"Editing 2"]; v = [self page:@"Editing 2"];
    y = [self addCheckbox:@"Word wrap" key:@"wordWrap" on:p.wordWrap to:v atY:y];
    y = [self addPopup:@"Line Wrap" key:@"lineWrapMethod"
                 items:@[@"Default", @"Aligned", @"Indent"]
              selected:p.lineWrapMethod to:v atY:y];
    y = [self addCheckbox:@"Show Space and Tab" key:@"showWhitespace"
                       on:p.showWhitespace to:v atY:y];
    y = [self addCheckbox:@"Show Indent Guide" key:@"showIndentGuides"
                       on:p.showIndentGuides to:v atY:y];
    y = [self addCheckbox:@"Enable smooth font" key:@"smoothFont" on:p.smoothFont to:v atY:y];
    y = [self addCheckbox:@"Apply custom color to selected text foreground" key:@"selectedTextCustomForeground"
                       on:p.selectedTextCustomForeground to:v atY:y];
    y = [self addCheckbox:@"Enable Multi-Editing (Cmd+click/selection)" key:@"multiEditing" on:p.multiEditing to:v atY:y];
    y = [self addCheckbox:@"Make current level folding/unfolding commands toggleable" key:@"foldCommandsToggle"
                       on:p.foldCommandsToggle to:v atY:y];
    y = [self addPopup:@"EOL (CRLF)" key:@"eolPlainText" items:@[@"Default", @"Plain Text"]
              selected:p.eolPlainText ? 1 : 0 to:v atY:y];
    y = [self addCheckbox:@"    EOL (CRLF)|Custom Color" key:@"eolCustomColour" on:p.eolCustomColour to:v atY:y];
    y = [self addPopup:@"Non-Printing Characters" key:@"npcCodepoint" items:@[@"Abbreviation", @"Codepoint"]
              selected:p.npcCodepoint ? 1 : 0 to:v atY:y];
    y = [self addCheckbox:@"    Non-Printing Characters|Custom Color" key:@"npcCustomColour" on:p.npcCustomColour to:v atY:y];
    y = [self addCheckbox:@"    Apply Appearance settings to C0, C1 && Unicode EOL" key:@"npcIncludeCcUniEol"
                       on:p.npcIncludeCcUniEol to:v atY:y];
    y = [self addCheckbox:@"Prevent control character (C0 code) typing into document" key:@"preventC0Typing"
                       on:p.preventC0Typing to:v atY:y];
    [self endPage:@"Editing 2" atY:y];

    y = [self beginPage:@"Dark Mode"]; v = [self page:@"Dark Mode"];
    y = [self addPopup:@"Appearance" key:@"appearanceMode"
                 items:@[@"Follow the system", @"Light mode", @"Dark mode"]
              selected:p.appearanceMode to:v atY:y];
    NSArray *themes = [StyleCatalog availableThemeNames];
    y = [self addPopup:@"Light theme" key:@"lightThemeName" items:themes
              selected:[themes indexOfObject:p.lightThemeName ?: @"Default"] to:v atY:y];
    y = [self addPopup:@"Dark theme" key:@"darkThemeName" items:themes
              selected:[themes indexOfObject:p.darkThemeName ?: @"DarkModeDefault"] to:v atY:y];
    [self endPage:@"Dark Mode" atY:y];

    y = [self beginPage:@"Margins/Border/Edge"]; v = [self page:@"Margins/Border/Edge"];
    y = [self addCheckbox:@"Display bookmark" key:@"bookmarkMarginShow"
                       on:p.bookmarkMarginShow to:v atY:y];
    y = [self addCheckbox:@"Show the fold margin" key:@"foldMarginShow"
                       on:p.foldMarginShow to:v atY:y];
    y = [self addField:@"Padding|Left" key:@"paddingLeft"
                  value:[@(p.paddingLeft) stringValue] to:v atY:y];
    y = [self addField:@"Padding|Right" key:@"paddingRight"
                  value:[@(p.paddingRight) stringValue] to:v atY:y];
    y = [self addPopup:@"Vertical Edge Settings" key:@"edgeMode"
                 items:@[@"None", @"A line", @"Background mode"]
              selected:p.edgeMode to:v atY:y];
    y = [self addField:@"Columns (space separated)" key:@"edgeColumns"
                  value:p.edgeColumns to:v atY:y];
    y = [self addPopup:@"Fold Margin Style" key:@"foldMarginStyle"
                 items:@[@"Simple", @"Arrow", @"Circle tree", @"Box tree", @"None"]
              selected:p.foldMarginStyle to:v atY:y];
    y = [self addCheckbox:@"Line Number|Display" key:@"lineNumberShow" on:p.lineNumberShow to:v atY:y];
    y = [self addPopup:@"    Width" key:@"lineNumberDynamicWidth" items:@[@"Constant width", @"Dynamic width"]
              selected:p.lineNumberDynamicWidth ? 1 : 0 to:v atY:y];
    y = [self addCheckbox:@"Change History|Show in the margin" key:@"changeHistoryMargin"
                       on:p.changeHistoryMargin to:v atY:y];
    y = [self addCheckbox:@"Change History|Show in the text" key:@"changeHistoryText" on:p.changeHistoryText to:v atY:y];
    y = [self addPopup:@"Distraction Free" key:@"distractionFreeDivPart"
                 items:@[@"3 parts", @"4 parts", @"5 parts", @"6 parts", @"7 parts", @"8 parts", @"9 parts"]
              selected:MIN(6, MAX(0, p.distractionFreeDivPart - 3)) to:v atY:y];
    [self endPage:@"Margins/Border/Edge" atY:y];

    y = [self beginPage:@"New Document"]; v = [self page:@"New Document"];
    y = [self addField:@"Encoding" key:@"defaultEncoding"
                  value:p.defaultEncoding to:v atY:y];
    y = [self addCheckbox:@"    Apply to opened ANSI files" key:@"openAnsiAsUtf8" on:p.openAnsiAsUtf8 to:v atY:y];
    y = [self addCheckbox:@"Work the language out from the contents when the name does not say"
                      key:@"detectLanguageFromContent"
                       on:p.detectLanguageFromContent to:v atY:y];
    y = [self addPopup:@"Format (Line ending)" key:@"defaultEOL"
                 items:@[@"Windows (CR LF)", @"Macintosh (CR)", @"Unix (LF)"]
              selected:p.defaultEOL to:v atY:y];
    y = [self addField:@"Default language:" key:@"defaultLanguage"
                 value:p.defaultLanguage ?: @"" to:v atY:y];
    y = [self addCheckbox:@"Always open a new document in addition at startup" key:@"openNewDocumentAtStartup"
                       on:p.openNewDocumentAtStartup to:v atY:y];
    y = [self addCheckbox:@"Use the first line of document as untitled tab name" key:@"untitledFromFirstLine"
                       on:p.untitledFromFirstLine to:v atY:y];
    [self endPage:@"New Document" atY:y];

    y = [self beginPage:@"Indentation"]; v = [self page:@"Indentation"];
    y = [self addField:@"Indent size:" key:@"tabWidth"
                  value:[@(p.tabWidth) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Indent using:|Space character(s)" key:@"useSpaces"
                       on:p.useSpaces to:v atY:y];
    y = [self addPopup:@"Auto-indent" key:@"autoIndentMode"
                 items:@[@"None", @"Auto-indent|Basic",
                         @"Auto-indent|Advanced"]
              selected:p.autoIndentMode to:v atY:y];
    y = [self addCheckbox:@"Backspace key unindents instead of removing single space" key:@"backspaceUnindents"
                       on:p.backspaceUnindents to:v atY:y];
    NppLanguageIndentView *perLanguage = [[NppLanguageIndentView alloc] initWithFrame:NSMakeRect(20, y - 70, 440, 90)
                                                                            settings:p.languageIndent];
    [v addSubview:perLanguage];
    self.controls[@"languageIndent"] = perLanguage;
    y -= 100;
    [self endPage:@"Indentation" atY:y];

    y = [self beginPage:@"Language"]; v = [self page:@"Language"];
    NppLanguageListsView *lists = [[NppLanguageListsView alloc] initWithFrame:NSMakeRect(20, y - 250, 440, 270)
                                                                      hidden:p.languageMenuHidden];
    [v addSubview:lists];
    self.controls[@"languageMenuHidden"] = lists;
    y -= 280;
    y = [self addCheckbox:@"Make language menu compact" key:@"languageMenuCompact" on:p.languageMenuCompact to:v atY:y];
    y = [self addCheckbox:@"Treat backslash as escape character for SQL" key:@"sqlBackslashEscape"
                       on:p.sqlBackslashEscape to:v atY:y];
    [self endPage:@"Language" atY:y];

    y = [self beginPage:@"Highlighting"]; v = [self page:@"Highlighting"];
    y = [self addCheckbox:@"Highlight matching braces" key:@"braceMatchEnabled"
                       on:p.braceMatchEnabled to:v atY:y];
    y = [self addCheckbox:@"Smart highlighting" key:@"smartHighlightEnabled"
                       on:p.smartHighlightEnabled to:v atY:y];
    y = [self addCheckbox:@"Smart Highlighting|Match case" key:@"smartHighlightMatchCase"
                       on:p.smartHighlightMatchCase to:v atY:y];
    y = [self addCheckbox:@"Smart Highlighting|Match whole word only" key:@"smartHighlightWholeWord"
                       on:p.smartHighlightWholeWord to:v atY:y];
    y = [self addCheckbox:@"Style All Occurrences of Token|Match case" key:@"markAllCaseSensitive"
                       on:p.markAllCaseSensitive to:v atY:y];
    y = [self addCheckbox:@"Style All Occurrences of Token|Match whole word only" key:@"markAllWordOnly"
                       on:p.markAllWordOnly to:v atY:y];
    y = [self addCheckbox:@"Smart Highlighting|Use Find dialog settings" key:@"smartHighlightUseFindSettings"
                       on:p.smartHighlightUseFindSettings to:v atY:y];
    y = [self addCheckbox:@"Smart Highlighting|Highlight another view" key:@"smartHighlightOtherView"
                       on:p.smartHighlightOtherView to:v atY:y];
    y = [self addCheckbox:@"Highlight Matching Tags" key:@"highlightMatchingTags" on:p.highlightMatchingTags to:v atY:y];
    y = [self addCheckbox:@"    Highlight tag attributes" key:@"highlightTagAttributes" on:p.highlightTagAttributes to:v atY:y];
    y = [self addCheckbox:@"    Highlight comment/php/asp zone" key:@"highlightNonHtmlZone" on:p.highlightNonHtmlZone to:v atY:y];
    [self endPage:@"Highlighting" atY:y];

    y = [self beginPage:@"Print"]; v = [self page:@"Print"];
    y = [self addCheckbox:@"Print line number" key:@"printLineNumbers"
                       on:p.printLineNumbers to:v atY:y];
    y = [self addPopup:@"Color Options" key:@"printColourMode"
                 items:@[@"WYSIWYG", @"Invert", @"Black on white", @"No background color"]
              selected:p.printColourMode to:v atY:y];
    y = [self addField:@"Header|Left part" key:@"printHeaderLeft"
                  value:p.printHeaderLeft to:v atY:y];
    y = [self addField:@"Header|Right part" key:@"printHeaderRight"
                  value:p.printHeaderRight to:v atY:y];
    y = [self addField:@"Footer|Middle part" key:@"printFooterMiddle"
                  value:p.printFooterMiddle to:v atY:y];
    y = [self addField:@"Header|Middle part" key:@"printHeaderMiddle" value:p.printHeaderMiddle ?: @"" to:v atY:y];
    y = [self addField:@"Footer|Left part" key:@"printFooterLeft" value:p.printFooterLeft ?: @"" to:v atY:y];
    y = [self addField:@"Footer|Right part" key:@"printFooterRight" value:p.printFooterRight ?: @"" to:v atY:y];
    y = [self addField:@"Header font (blank for the editor's)" key:@"printHeaderFontName"
                 value:p.printHeaderFontName ?: @"" to:v atY:y];
    y = [self addField:@"Header font size" key:@"printHeaderFontSize"
                 value:[@(p.printHeaderFontSize) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Header and Footer|Bold" key:@"printHeaderBold" on:p.printHeaderBold to:v atY:y];
    y = [self addCheckbox:@"Header and Footer|Italic" key:@"printHeaderItalic" on:p.printHeaderItalic to:v atY:y];
    y = [self addField:@"Margins: left, top, right, bottom (points)" key:@"printMargins"
                 value:[NSString stringWithFormat:@"%.0f %.0f %.0f %.0f", p.printMarginLeft, p.printMarginTop,
                        p.printMarginRight, p.printMarginBottom] to:v atY:y];
    y = [self addCheckbox:@"Print formfeed as page break" key:@"printFormFeedPageBreak" on:p.printFormFeedPageBreak to:v atY:y];
    y = [self addPopup:@"Variable" key:@"printVariable"
                 items:@[@"Full file name path", @"File name", @"File directory", @"Page", @"Short date format",
                         @"Long date format", @"Time"]
              selected:0 to:v atY:y];
    NSButton *addVariable = [NSButton buttonWithTitle:@"Add" target:self action:@selector(addPrintVariable:)];
    addVariable.frame = NSMakeRect(450, y + 28, 60, 26);
    [v addSubview:addVariable];
    for (NSString *key in @[@"printHeaderLeft", @"printHeaderMiddle", @"printHeaderRight",
                            @"printFooterLeft", @"printFooterMiddle", @"printFooterRight"]) {
        [(NSTextField *)self.controls[key] setDelegate:(id<NSTextFieldDelegate>)self];
    }
    [self endPage:@"Print" atY:y];

    y = [self beginPage:@"Backup"]; v = [self page:@"Backup"];
    y = [self addPopup:@"Backup on save" key:@"backupMode"
                 items:@[@"None", @"Simple backup", @"Verbose backup"]
              selected:p.backupMode to:v atY:y];
    y = [self addField:@"Custom Backup Directory" key:@"backupDirectory"
                  value:p.backupDirectory to:v atY:y];
    y = [self addCheckbox:@"Enable session snapshot and periodic backup"
                      key:@"autosaveEnabled" on:p.autosaveEnabled to:v atY:y];
    y = [self addField:@"Trigger backup on modification in every|seconds" key:@"autosaveInterval"
                  value:[@(p.autosaveInterval) stringValue] to:v atY:y];
    [self endPage:@"Backup" atY:y];

    y = [self beginPage:@"Auto-Completion"]; v = [self page:@"Auto-Completion"];
    y = [self addCheckbox:@"Enable auto-completion on each input" key:@"autoCompleteOnInput"
                       on:p.autoCompleteOnInput to:v atY:y];
    y = [self addPopup:@"Auto-Completion" key:@"autoCompleteSource"
                 items:@[@"Function completion", @"Word completion", @"Function and word completion"]
              selected:p.autoCompleteSource to:v atY:y];
    y = [self addField:@"Characters before it opens" key:@"autoCompleteThreshold"
                  value:[@(p.autoCompleteThreshold) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Make auto-completion list brief" key:@"autoCompleteBriefList"
                       on:p.autoCompleteBriefList to:v atY:y];
    y = [self addCheckbox:@"Ignore numbers" key:@"autoCompleteIgnoreNumbers"
                       on:p.autoCompleteIgnoreNumbers to:v atY:y];
    y = [self addCheckbox:@"Insert Selection|TAB" key:@"autoCompleteUseTab"
                       on:p.autoCompleteUseTab to:v atY:y];
    y = [self addCheckbox:@"Function parameters hint on input" key:@"functionHintOnInput"
                       on:p.functionHintOnInput to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|( )" key:@"autoInsertParenthesis"
                       on:p.autoInsertParenthesis to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|[ ]" key:@"autoInsertBracket"
                       on:p.autoInsertBracket to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|{ }" key:@"autoInsertBrace"
                       on:p.autoInsertBrace to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|' '" key:@"autoInsertSingleQuote"
                       on:p.autoInsertSingleQuote to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|\" \"" key:@"autoInsertDoubleQuote"
                       on:p.autoInsertDoubleQuote to:v atY:y];
    y = [self addCheckbox:@"Auto-Insert|html/xml close tag" key:@"autoInsertCloseTag"
                       on:p.autoInsertCloseTag to:v atY:y];
    for (NSInteger i = 0; i < 3; ++i) {
        NSArray *pairs = p.userMatchedPairs ?: @[];
        y = [self addField:[NSString stringWithFormat:@"Matched pair %ld:", (long)i + 1]
                       key:[NSString stringWithFormat:@"userMatchedPair%ld", (long)i]
                     value:(NSUInteger)i < pairs.count ? pairs[(NSUInteger)i] : @"" to:v atY:y];
    }
    [self endPage:@"Auto-Completion" atY:y];

    y = [self beginPage:@"Multi-Instance & Date"]; v = [self page:@"Multi-Instance & Date"];
    y = [self addCheckbox:@"Reverse default date time order (short && long formats)" key:@"reverseDateTimeOrder"
                       on:p.reverseDateTimeOrder to:v atY:y];
    y = [self addField:@"Custom format" key:@"customDateFormat" value:p.customDateFormat to:v atY:y];
    NSTextField *preview = [NSTextField labelWithString:@""];
    preview.frame = NSMakeRect(280, y, 280, 18);
    preview.textColor = [NSColor secondaryLabelColor];
    [v addSubview:preview];
    self.controls[@"customDatePreview"] = preview;
    [self updateDatePreview];
    [(NSTextField *)self.controls[@"customDateFormat"] setDelegate:(id<NSTextFieldDelegate>)self];
    y -= 26;
    [self endPage:@"Multi-Instance & Date" atY:y];

    y = [self beginPage:@"Delimiter"]; v = [self page:@"Delimiter"];
    y = [self addCheckbox:@"Add characters to the word list" key:@"customWordCharsEnabled"
                       on:p.customWordCharsEnabled to:v atY:y];
    y = [self addField:@"Word character list" key:@"customWordChars"
                  value:p.customWordChars to:v atY:y];
    y = [self addField:@"Delimiter|Open" key:@"delimiterOpen"
                  value:p.delimiterOpen to:v atY:y];
    y = [self addField:@"Delimiter|Close" key:@"delimiterClose"
                  value:p.delimiterClose to:v atY:y];
    y = [self addCheckbox:@"Allow on several lines" key:@"delimiterMultiline"
                       on:p.delimiterMultiline to:v atY:y];
    [self endPage:@"Delimiter" atY:y];

    y = [self beginPage:@"Performance"]; v = [self page:@"Performance"];
    y = [self addCheckbox:@"Enable Large File Restriction (no syntax highlighting)"
                      key:@"largeFileRestrictionEnabled"
                       on:p.largeFileRestrictionEnabled to:v atY:y];
    y = [self addField:@"Define Large File Size:" key:@"largeFileThresholdMB"
                  value:[@(p.largeFileThresholdMB) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Allow Brace Match" key:@"largeFileAllowBraceMatch"
                       on:p.largeFileAllowBraceMatch to:v atY:y];
    y = [self addCheckbox:@"Allow URL Clickable Link"
                      key:@"largeFileAllowClickableLinks"
                       on:p.largeFileAllowClickableLinks to:v atY:y];
    y = [self addCheckbox:@"Deactivate Word Wrap globally" key:@"largeFileDeactivateWordWrap"
                       on:p.largeFileDeactivateWordWrap to:v atY:y];
    y = [self addCheckbox:@"Allow Auto-Completion" key:@"largeFileAllowAutoCompletion"
                       on:p.largeFileAllowAutoCompletion to:v atY:y];
    y = [self addCheckbox:@"Allow Smart Highlighting" key:@"largeFileAllowSmartHighlighting"
                       on:p.largeFileAllowSmartHighlighting to:v atY:y];
    y = [self addCheckbox:@"Suppress warning when opening ≥2GB files" key:@"suppressHugeFileWarning"
                       on:p.suppressHugeFileWarning to:v atY:y];
    [self endPage:@"Performance" atY:y];

    y = [self beginPage:@"Tab Bar"]; v = [self page:@"Tab Bar"];
    y = [self addCheckbox:@"Tab Bar|Hide" key:@"hideTabBar" on:p.hideTabBar to:v atY:y];
    y = [self addCheckbox:@"Lock (no drag and drop)" key:@"tabBarLocked" on:p.tabBarLocked to:v atY:y];
    y = [self addCheckbox:@"Vertical" key:@"tabBarVertical" on:p.tabBarVertical to:v atY:y];
    y = [self addCheckbox:@"Multi-line" key:@"tabBarMultiLine" on:p.tabBarMultiLine to:v atY:y];
    y = [self addCheckbox:@"Show close button" key:@"tabShowCloseButton" on:p.tabShowCloseButton to:v atY:y];
    y = [self addCheckbox:@"Show buttons on inactive tabs" key:@"tabCloseButtonOnInactive"
                       on:p.tabCloseButtonOnInactive to:v atY:y];
    y = [self addCheckbox:@"Double click to close document" key:@"tabDoubleClickCloses" on:p.tabDoubleClickCloses to:v atY:y];
    y = [self addCheckbox:@"Enable pin tab feature" key:@"tabPinFeatureEnabled" on:p.tabPinFeatureEnabled to:v atY:y];
    y = [self addCheckbox:@"Exit on close the last tab" key:@"exitOnClosingLastTab" on:p.exitOnClosingLastTab to:v atY:y];
    y = [self addCheckbox:@"Reduce" key:@"tabReduced" on:p.tabReduced to:v atY:y];
    y = [self addCheckbox:@"Change inactive tab color" key:@"tabColourInactive" on:p.tabColourInactive to:v atY:y];
    y = [self addCheckbox:@"Draw a colored bar on active tab" key:@"tabDrawActiveBar" on:p.tabDrawActiveBar to:v atY:y];
    y = [self addField:@"Max. tab label length:" key:@"tabMaxLabelLength"
                  value:[@(p.tabMaxLabelLength) stringValue] to:v atY:y];
    [self endPage:@"Tab Bar" atY:y];

    y = [self beginPage:@"Recent Files History"]; v = [self page:@"Recent Files History"];
    y = [self addField:@"Max. number of entries:" key:@"recentFilesMax" value:[@(p.recentFilesMax) stringValue] to:v atY:y];
    y = [self addCheckbox:@"Full File Name Path" key:@"recentFilesShowFullPath" on:p.recentFilesShowFullPath to:v atY:y];
    y = [self addField:@"Customize Maximum Length:" key:@"recentFilesMaxLength"
                 value:[@(p.recentFilesMaxLength) stringValue] to:v atY:y];
    [self endPage:@"Recent Files History" atY:y];

    y = [self beginPage:@"Default Directory"]; v = [self page:@"Default Directory"];
    y = [self addPopup:@"Default Open/Save file Directory" key:@"defaultDirectoryMode"
                 items:@[@"Follow current document", @"Remember last used directory", @"A fixed folder"]
              selected:p.defaultDirectoryMode to:v atY:y];
    y = [self addField:@"Fixed folder" key:@"fixedDirectory" value:p.fixedDirectory ?: @"" to:v atY:y];
    [self endPage:@"Default Directory" atY:y];

    y = [self beginPage:@"Searching"]; v = [self page:@"Searching"];
    y = [self addCheckbox:@"Fill Find Field with Selected Text" key:@"findFillWithSelection" on:p.findFillWithSelection to:v atY:y];
    y = [self addCheckbox:@"Select Word Under Caret when Nothing Selected" key:@"findSelectWordUnderCaret" on:p.findSelectWordUnderCaret to:v atY:y];
    y = [self addCheckbox:@"Replace: Don't move to the following occurrence" key:@"replaceStaysOnOccurrence"
                       on:p.replaceStaysOnOccurrence to:v atY:y];
    y = [self addCheckbox:@"Confirm Replace All" key:@"confirmReplaceAll" on:p.confirmReplaceAll to:v atY:y];
    y = [self addCheckbox:@"Compare: ignore case" key:@"compareIgnoreCase" on:p.compareIgnoreCase to:v atY:y];
    y = [self addCheckbox:@"Compare: ignore spaces" key:@"compareIgnoreSpaces" on:p.compareIgnoreSpaces to:v atY:y];
    y = [self addCheckbox:@"Compare: ignore empty lines" key:@"compareIgnoreEmptyLines" on:p.compareIgnoreEmptyLines to:v atY:y];
    y = [self addCheckbox:@"Enable fullbox mode" key:@"linksFullBox" on:p.linksFullBox to:v atY:y];
    y = [self addCheckbox:@"Find dialog remains open after search that outputs to results window" key:@"findDialogStaysOpen"
                       on:p.findDialogStaysOpen to:v atY:y];
    y = [self addCheckbox:@"Confirm Replace All in All Opened Documents" key:@"confirmReplaceAllOpenDocs"
                       on:p.confirmReplaceAllOpenDocs to:v atY:y];
    y = [self addCheckbox:@"Fill Find in Files Directory Field Based On Active Document" key:@"fillDirectoryFromActiveDocument"
                       on:p.fillDirectoryFromActiveDocument to:v atY:y];
    y = [self addField:@"Minimum Size for Auto-Checking \"In selection\"" key:@"inSelectionThreshold"
                  value:[@(p.inSelectionThreshold) stringValue] to:v atY:y];
    y = [self addField:@"Max Characters to Auto-Fill Find Field" key:@"fillFindWhatThreshold"
                  value:[@(p.fillFindWhatThreshold) stringValue] to:v atY:y];
    [self endPage:@"Searching" atY:y];

    y = [self beginPage:@"Cloud & Link"]; v = [self page:@"Cloud & Link"];
    y = [self addCheckbox:@"Clickable Link Settings|Enable" key:@"linksEnabled" on:p.linksEnabled to:v atY:y];
    y = [self addCheckbox:@"No underline" key:@"linksNoUnderline"
                       on:p.linksNoUnderline to:v atY:y];
    y = [self addField:@"URI customized schemes:" key:@"linkCustomSchemes"
                  value:p.linkCustomSchemes to:v atY:y];
    y = [self addField:@"Set your cloud location path here:" key:@"settingsDirectory"
                  value:p.settingsDirectory to:v atY:y];
    [self endPage:@"Cloud & Link" atY:y];

    y = [self beginPage:@"MISC."]; v = [self page:@"MISC."];
    y = [self addCheckbox:@"Document Peeker|Peek on tab" key:@"docPeekOnTab" on:p.docPeekOnTab to:v atY:y];
    y = [self addCheckbox:@"Document Peeker|Peek on document map" key:@"docPeekOnMap" on:p.docPeekOnMap to:v atY:y];
    y = [self addCheckbox:@"Document Switcher (Ctrl+TAB)|Enable" key:@"docSwitcherEnabled" on:p.docSwitcherEnabled to:v atY:y];
    y = [self addCheckbox:@"    Enable MRU behaviour" key:@"docSwitcherMRU" on:p.docSwitcherMRU to:v atY:y];
    y = [self addCheckbox:@"Show only filename in title bar" key:@"titleBarFileNameOnly" on:p.titleBarFileNameOnly to:v atY:y];
    y = [self addCheckbox:@"Enable Save All confirm dialog" key:@"confirmSaveAll" on:p.confirmSaveAll to:v atY:y];
    y = [self addCheckbox:@"Mute all sounds" key:@"muteSounds" on:p.muteSounds to:v atY:y];
    y = [self addCheckbox:@"Allow loading symlinks in Folder as Workspace panel" key:@"workspaceSymlinks"
                       on:p.workspaceSymlinks to:v atY:y];
    // The port's own: the MCP socket that nppmac mcp bridges agents to.
    y = [self addCheckbox:@"Let AI agents drive the editor (MCP)" key:@"agentServer"
                       on:p.agentServer to:v atY:y];
    y = [self addCheckbox:@"Git: mark lines changed since the last commit in the margin" key:@"gitMarginMarks"
                       on:p.gitMarginMarks to:v atY:y];
    y = [self addField:@"Session file ext." key:@"sessionFileExtension" value:p.sessionFileExtension to:v atY:y];
    y = [self addField:@"Workspace file ext." key:@"workspaceFileExtension" value:p.workspaceFileExtension to:v atY:y];
    y = [self addPopup:@"Auto-updater:" key:@"autoUpdateMode"
                 items:@[@"Disable", @"Enable on Notepad++ startup", @"Enable on Notepad++ exit"]
              selected:p.autoUpdateMode to:v atY:y];
    y = [self addField:@"Releases repository" key:@"updateRepository" value:p.updateRepository to:v atY:y];
    [self endPage:@"MISC." atY:y];

    y = [self beginPage:@"Search Engine"]; v = [self page:@"Search Engine"];
    y = [self addPopup:@"Search Engine (for command \"Search on Internet\")" key:@"searchEngine"
                 items:@[@"DuckDuckGo", @"Google", @"Bing", @"Yahoo!", @"Set your search engine here:"]
              selected:p.searchEngine to:v atY:y];
    y = [self addField:@"Set your search engine here:" key:@"searchEngineCustom" value:p.searchEngineCustom to:v atY:y];
    NSTextField *example = [NSTextField labelWithString:@"Example: https://www.google.com/search?q=$(CURRENT_WORD)"];
    example.frame = NSMakeRect(20, y, 440, 18);
    example.textColor = [NSColor secondaryLabelColor];
    [v addSubview:example];
    y -= 26;
    [self endPage:@"Search Engine" atY:y];
}

/// Print's Variable list and Add: the chosen variable goes into the header or
/// footer field that last had the caret.
- (void)addPrintVariable:(id)sender {
    NSArray *variables = @[@"$(FULL_CURRENT_PATH)", @"$(FILE_NAME)", @"$(CURRENT_DIRECTORY)", @"$(CURRENT_PRINTING_PAGE)",
                           @"$(SHORT_DATE)", @"$(LONG_DATE)", @"$(TIME)"];
    NSInteger index = [self.controls[@"printVariable"] indexOfSelectedItem];
    if (index < 0 || index >= (NSInteger)variables.count) return;
    NSString *variable = variables[(NSUInteger)index];
    NSTextField *target = nil;
    for (NSString *key in @[@"printHeaderLeft", @"printHeaderMiddle", @"printHeaderRight",
                            @"printFooterLeft", @"printFooterMiddle", @"printFooterRight"]) {
        NSTextField *field = self.controls[key];
        if (field && (field.currentEditor || [self.lastPrintField isEqualToString:key])) { target = field; break; }
    }
    if (!target) target = self.controls[@"printHeaderMiddle"];
    NSText *editor = target.currentEditor;
    if (editor) [editor insertText:variable];
    else target.stringValue = [target.stringValue stringByAppendingString:variable];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == self.controls[@"customDateFormat"]) [self updateDatePreview];
}

- (void)controlTextDidBeginEditing:(NSNotification *)note {
    for (NSString *key in @[@"printHeaderLeft", @"printHeaderMiddle", @"printHeaderRight",
                            @"printFooterLeft", @"printFooterMiddle", @"printFooterRight"]) {
        if (note.object == self.controls[key]) self.lastPrintField = key;
    }
}

/// Upstream shows what the custom format gives beside it.
- (void)updateDatePreview {
    NSString *picture = [self.controls[@"customDateFormat"] stringValue] ?: @"";
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = [NppPreferences dateFormatFromWindowsPicture:picture];
    [self.controls[@"customDatePreview"] setStringValue:[f stringFromDate:[NSDate date]] ?: @""];
}

- (CGFloat)addField:(NSString *)label key:(NSString *)key value:(NSString *)value
                 to:(NSView *)content atY:(CGFloat)y {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(20, y, 250, 20);
    [content addSubview:caption];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(280, y - 2, 180, 22)];
    field.stringValue = value ?: @"";
    [content addSubview:field];
    self.controls[key] = field;
    return y - 30;
}

- (CGFloat)addPopup:(NSString *)label key:(NSString *)key items:(NSArray<NSString *> *)items
           selected:(NSInteger)selected to:(NSView *)content atY:(CGFloat)y {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(20, y, 250, 20);
    [content addSubview:caption];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(280, y - 4, 220, 26)];
    [popup addItemsWithTitles:items];
    if (selected >= 0 && selected < (NSInteger)items.count) [popup selectItemAtIndex:selected];
    [content addSubview:popup];
    self.controls[key] = popup;
    return y - 32;
}

- (CGFloat)addRadios:(NSString *)label key:(NSString *)key items:(NSArray<NSString *> *)items
            selected:(NSInteger)selected to:(NSView *)content atY:(CGFloat)y {
    NSTextField *caption = [NSTextField labelWithString:label];
    caption.frame = NSMakeRect(20, y, 380, 20);
    [content addSubview:caption];
    y -= 26;
    NppRadioGroup *group = [[NppRadioGroup alloc] init];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; ++i) {
        NSButton *radio = [NSButton radioButtonWithTitle:items[i] target:group action:@selector(chosen:)];
        radio.frame = NSMakeRect(36, y, 380, 20);
        radio.state = (NSInteger)i == selected ? NSControlStateValueOn : NSControlStateValueOff;
        [content addSubview:radio];
        [buttons addObject:radio];
        y -= 24;
    }
    group.buttons = buttons;
    self.controls[key] = group;
    return y - 6;
}

- (CGFloat)addCheckbox:(NSString *)label key:(NSString *)key on:(BOOL)on
                    to:(NSView *)content atY:(CGFloat)y {
    NSButton *box = [NSButton checkboxWithTitle:label target:nil action:nil];
    box.frame = NSMakeRect(20, y, 380, 20);
    box.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    [content addSubview:box];
    self.controls[key] = box;
    return y - 28;
}

- (NSArray<NSString *> *)categoryNames { return [self.pageNames copy]; }
- (BOOL)hasControlForKey:(NSString *)key { return self.controls[key] != nil; }

- (BOOL)visible { return self.panel.isVisible; }

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    // Settings change outside this window too (View > Word wrap, "Always yes"
    // in Save All): the controls take today's values, or Apply writes old ones back.
    [self rebuildPages];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)apply:(id)sender {
    NppPreferences *p = [NppPreferences shared];
    BOOL (^on)(NSString *) = ^BOOL(NSString *key) { return [self.controls[key] state] == NSControlStateValueOn; };
    NSString *(^text)(NSString *) = ^NSString *(NSString *key) { return [self.controls[key] stringValue] ?: @""; };
    p.defaultEOL = [self.controls[@"defaultEOL"] indexOfSelectedItem];
    p.defaultLanguage = text(@"defaultLanguage");
    p.openNewDocumentAtStartup = on(@"openNewDocumentAtStartup");
    p.untitledFromFirstLine = on(@"untitledFromFirstLine");
    // The port's own boxes on New Document and MISC.: Apply stores them like the rest.
    if (self.controls[@"detectLanguageFromContent"]) p.detectLanguageFromContent = on(@"detectLanguageFromContent");
    if (self.controls[@"gitMarginMarks"]) p.gitMarginMarks = on(@"gitMarginMarks");
    if (self.controls[@"agentServer"]) p.agentServer = on(@"agentServer");
    p.printHeaderMiddle = text(@"printHeaderMiddle");
    p.printFooterLeft = text(@"printFooterLeft");
    p.printFooterRight = text(@"printFooterRight");
    p.printHeaderFontName = text(@"printHeaderFontName");
    p.printHeaderFontSize = text(@"printHeaderFontSize").integerValue;
    p.printHeaderBold = on(@"printHeaderBold");
    p.printHeaderItalic = on(@"printHeaderItalic");
    NSArray *margins = [text(@"printMargins") componentsSeparatedByCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *numbers = [NSMutableArray array];
    for (NSString *m in margins) if (m.length) [numbers addObject:@(m.doubleValue)];
    if (numbers.count == 4) {
        p.printMarginLeft = [numbers[0] doubleValue]; p.printMarginTop = [numbers[1] doubleValue];
        p.printMarginRight = [numbers[2] doubleValue]; p.printMarginBottom = [numbers[3] doubleValue];
    }
    p.largeFileDeactivateWordWrap = on(@"largeFileDeactivateWordWrap");
    p.largeFileAllowAutoCompletion = on(@"largeFileAllowAutoCompletion");
    p.largeFileAllowSmartHighlighting = on(@"largeFileAllowSmartHighlighting");
    p.suppressHugeFileWarning = on(@"suppressHugeFileWarning");
    p.hideTabBar = on(@"hideTabBar");
    p.tabBarLocked = on(@"tabBarLocked");
    p.tabBarVertical = on(@"tabBarVertical");
    p.tabBarMultiLine = on(@"tabBarMultiLine");
    p.tabShowCloseButton = on(@"tabShowCloseButton");
    p.tabCloseButtonOnInactive = on(@"tabCloseButtonOnInactive");
    p.tabDoubleClickCloses = on(@"tabDoubleClickCloses");
    p.tabPinFeatureEnabled = on(@"tabPinFeatureEnabled");
    p.exitOnClosingLastTab = on(@"exitOnClosingLastTab");
    p.recentFilesMax = MAX(1, text(@"recentFilesMax").integerValue);
    p.recentFilesShowFullPath = on(@"recentFilesShowFullPath");
    p.recentFilesMaxLength = MAX(0, text(@"recentFilesMaxLength").integerValue);
    p.defaultDirectoryMode = [self.controls[@"defaultDirectoryMode"] indexOfSelectedItem];
    p.fixedDirectory = text(@"fixedDirectory");
    p.findFillWithSelection = on(@"findFillWithSelection");
    p.findSelectWordUnderCaret = on(@"findSelectWordUnderCaret");
    p.replaceStaysOnOccurrence = on(@"replaceStaysOnOccurrence");
    p.confirmReplaceAll = on(@"confirmReplaceAll");
    p.compareIgnoreCase = on(@"compareIgnoreCase");
    p.compareIgnoreSpaces = on(@"compareIgnoreSpaces");
    p.compareIgnoreEmptyLines = on(@"compareIgnoreEmptyLines");
    p.linksFullBox = on(@"linksFullBox");
    // Stored only when changed: a stored font is the user's choice, which then
    // wins over the theme's Default Style font (see -chosenFontName).
    NSString *fontName = [self.controls[@"fontName"] stringValue];
    NSInteger fontSize = [[self.controls[@"fontSize"] stringValue] integerValue];
    if (fontName && ![fontName isEqualToString:p.fontName ?: @""]) p.fontName = fontName;
    if (fontSize > 0 && fontSize != p.fontSize) p.fontSize = fontSize;
    p.tabWidth = MAX(1, [[self.controls[@"tabWidth"] stringValue] integerValue]);
    p.useSpaces = [self.controls[@"useSpaces"] state] == NSControlStateValueOn;
    p.wordWrap = [self.controls[@"wordWrap"] state] == NSControlStateValueOn;
    p.showWhitespace = [self.controls[@"showWhitespace"] state] == NSControlStateValueOn;
    p.showIndentGuides = [self.controls[@"showIndentGuides"] state] == NSControlStateValueOn;
    p.restoreSession = [self.controls[@"restoreSession"] state] == NSControlStateValueOn;
    p.defaultEncoding = [self.controls[@"defaultEncoding"] stringValue];
    p.appearanceMode = [self.controls[@"appearanceMode"] indexOfSelectedItem];
    p.lightThemeName = [self.controls[@"lightThemeName"] titleOfSelectedItem];
    p.darkThemeName = [self.controls[@"darkThemeName"] titleOfSelectedItem];
    p.showToolbar = [self.controls[@"showToolbar"] state] == NSControlStateValueOn;
    p.toolbarDisplayMode = [self.controls[@"toolbarDisplayMode"] indexOfSelectedItem];
    p.toolbarIconSize = [self.controls[@"toolbarIconSize"] indexOfSelectedItem];
    p.tabReduced = on(@"tabReduced");
    p.tabColourInactive = on(@"tabColourInactive");
    p.tabDrawActiveBar = on(@"tabDrawActiveBar");
    p.tabMaxLabelLength = MAX(0, text(@"tabMaxLabelLength").integerValue);
    p.toolbarFilledIcons = [self.controls[@"toolbarFilledIcons"] indexOfSelectedItem] == 1;
    p.toolbarIconColour = [self.controls[@"toolbarIconColour"] indexOfSelectedItem];
    p.toolbarIconCustomColour = text(@"toolbarIconCustomColour");
    p.toolbarColorizeComplete = [self.controls[@"toolbarColorizeComplete"] indexOfSelectedItem] == 1;
    p.backupMode = [self.controls[@"backupMode"] indexOfSelectedItem];
    p.backupDirectory = [self.controls[@"backupDirectory"] stringValue];
    p.autosaveEnabled = [self.controls[@"autosaveEnabled"] state] == NSControlStateValueOn;
    p.fileAutoDetection = [self.controls[@"fileAutoDetection"] state] == NSControlStateValueOn;
    p.fileAutoDetectionSilent = [self.controls[@"fileAutoDetectionSilent"] state] == NSControlStateValueOn;
    p.fileAutoDetectionScrollToEnd = [self.controls[@"fileAutoDetectionScrollToEnd"] state] == NSControlStateValueOn;
    p.autoDetectCharacterEncoding = [self.controls[@"autoDetectCharacterEncoding"] state] == NSControlStateValueOn;
    p.autosaveInterval = MAX(5, [[self.controls[@"autosaveInterval"] stringValue] integerValue]);
    p.printLineNumbers = [self.controls[@"printLineNumbers"] state] == NSControlStateValueOn;
    p.printColourMode = [self.controls[@"printColourMode"] indexOfSelectedItem];
    p.printHeaderLeft = [self.controls[@"printHeaderLeft"] stringValue];
    p.printHeaderRight = [self.controls[@"printHeaderRight"] stringValue];
    p.printFooterMiddle = [self.controls[@"printFooterMiddle"] stringValue];
    p.largeFileRestrictionEnabled = [self.controls[@"largeFileRestrictionEnabled"] state] == NSControlStateValueOn;
    p.largeFileThresholdMB = MAX(1, MIN(2046, [[self.controls[@"largeFileThresholdMB"] stringValue] integerValue]));
    p.largeFileAllowBraceMatch = [self.controls[@"largeFileAllowBraceMatch"] state] == NSControlStateValueOn;
    p.largeFileAllowClickableLinks = [self.controls[@"largeFileAllowClickableLinks"] state] == NSControlStateValueOn;
    p.linksEnabled = [self.controls[@"linksEnabled"] state] == NSControlStateValueOn;
    p.linksNoUnderline = [self.controls[@"linksNoUnderline"] state] == NSControlStateValueOn;
    p.linkCustomSchemes = [self.controls[@"linkCustomSchemes"] stringValue];
    p.braceMatchEnabled = [self.controls[@"braceMatchEnabled"] state] == NSControlStateValueOn;
    p.smartHighlightEnabled = [self.controls[@"smartHighlightEnabled"] state] == NSControlStateValueOn;
    p.customWordCharsEnabled = [self.controls[@"customWordCharsEnabled"] state] == NSControlStateValueOn;
    p.customWordChars = [self.controls[@"customWordChars"] stringValue];
    p.delimiterOpen = [self.controls[@"delimiterOpen"] stringValue];
    p.delimiterClose = [self.controls[@"delimiterClose"] stringValue];
    p.delimiterMultiline = [self.controls[@"delimiterMultiline"] state] == NSControlStateValueOn;
    p.multiInstanceMode = [self.controls[@"multiInstanceMode"] indexOfSelectedItem];
    p.autoUpdateMode = MAX(0, [self.controls[@"autoUpdateMode"] indexOfSelectedItem]);
    NSString *repository = [[self.controls[@"updateRepository"] stringValue]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([repository componentsSeparatedByString:@"/"].count == 2) p.updateRepository = repository;
    p.reverseDateTimeOrder = [self.controls[@"reverseDateTimeOrder"] state] == NSControlStateValueOn;
    p.rememberPanelState = [self.controls[@"rememberPanelState"] state] == NSControlStateValueOn;
    p.settingsDirectory = [self.controls[@"settingsDirectory"] stringValue];

    // The settings the Windows version has that this one had no controls for.
    p.caretWidth = [self.controls[@"caretWidth"] indexOfSelectedItem];
    p.caretBlinkRate = MAX(0, [[self.controls[@"caretBlinkRate"] stringValue] integerValue]);
    p.currentLineHighlightMode = [self.controls[@"currentLineHighlightMode"] indexOfSelectedItem];
    p.currentLineFrameWidth = MIN(6, MAX(1, [[self.controls[@"currentLineFrameWidth"] stringValue] integerValue]));
    p.scrollBeyondLastLine = [self.controls[@"scrollBeyondLastLine"] state] == NSControlStateValueOn;
    p.virtualSpace = [self.controls[@"virtualSpace"] state] == NSControlStateValueOn;
    p.lineCopyCutWithoutSelection = [self.controls[@"lineCopyCutWithoutSelection"] state] == NSControlStateValueOn;
    p.selectedTextDragDrop = [self.controls[@"selectedTextDragDrop"] state] == NSControlStateValueOn;
    p.rightClickKeepsSelection = [self.controls[@"rightClickKeepsSelection"] state] == NSControlStateValueOn;
    p.lineWrapMethod = [self.controls[@"lineWrapMethod"] indexOfSelectedItem];
    p.bookmarkMarginShow = [self.controls[@"bookmarkMarginShow"] state] == NSControlStateValueOn;
    p.foldMarginShow = [self.controls[@"foldMarginShow"] state] == NSControlStateValueOn;
    p.paddingLeft = MIN(9, MAX(0, [[self.controls[@"paddingLeft"] stringValue] integerValue]));
    p.paddingRight = MIN(9, MAX(0, [[self.controls[@"paddingRight"] stringValue] integerValue]));
    p.edgeMode = [self.controls[@"edgeMode"] indexOfSelectedItem];
    p.edgeColumns = [self.controls[@"edgeColumns"] stringValue];
    p.autoIndentMode = [self.controls[@"autoIndentMode"] indexOfSelectedItem];
    p.smartHighlightMatchCase = [self.controls[@"smartHighlightMatchCase"] state] == NSControlStateValueOn;
    p.smartHighlightWholeWord = [self.controls[@"smartHighlightWholeWord"] state] == NSControlStateValueOn;
    p.markAllCaseSensitive = [self.controls[@"markAllCaseSensitive"] state] == NSControlStateValueOn;
    p.markAllWordOnly = [self.controls[@"markAllWordOnly"] state] == NSControlStateValueOn;
    p.autoCompleteOnInput = [self.controls[@"autoCompleteOnInput"] state] == NSControlStateValueOn;
    p.autoCompleteSource = [self.controls[@"autoCompleteSource"] indexOfSelectedItem];
    p.autoCompleteThreshold = MAX(1, [[self.controls[@"autoCompleteThreshold"] stringValue] integerValue]);
    p.autoCompleteBriefList = [self.controls[@"autoCompleteBriefList"] state] == NSControlStateValueOn;
    p.autoCompleteIgnoreNumbers = [self.controls[@"autoCompleteIgnoreNumbers"] state] == NSControlStateValueOn;
    p.autoCompleteUseTab = [self.controls[@"autoCompleteUseTab"] state] == NSControlStateValueOn;
    p.functionHintOnInput = [self.controls[@"functionHintOnInput"] state] == NSControlStateValueOn;
    p.autoInsertParenthesis = [self.controls[@"autoInsertParenthesis"] state] == NSControlStateValueOn;
    p.autoInsertBracket = [self.controls[@"autoInsertBracket"] state] == NSControlStateValueOn;
    p.autoInsertBrace = [self.controls[@"autoInsertBrace"] state] == NSControlStateValueOn;
    p.autoInsertSingleQuote = [self.controls[@"autoInsertSingleQuote"] state] == NSControlStateValueOn;
    p.autoInsertDoubleQuote = [self.controls[@"autoInsertDoubleQuote"] state] == NSControlStateValueOn;
    p.autoInsertCloseTag = [self.controls[@"autoInsertCloseTag"] state] == NSControlStateValueOn;
    p.statusBarHidden = on(@"statusBarHidden");
    NSInteger languageIndex = [self.controls[@"localizationFile"] indexOfSelectedItem];
    if (languageIndex >= 0 && languageIndex < (NSInteger)self.localizationFiles.count) {
        NSString *file = self.localizationFiles[(NSUInteger)languageIndex];
        p.localizationFile = [file isEqualToString:@"english.xml"] ? @"" : file;
    }
    p.openAnsiAsUtf8 = on(@"openAnsiAsUtf8");
    NSMutableDictionary *keep = [NSMutableDictionary dictionary];
    for (NSString *key in self.controls) {
        if ([key hasPrefix:@"panelKeep."]) keep[[key substringFromIndex:10]] = @(on(key));
    }
    p.panelStateKeep = keep;
    p.distractionFreeDivPart = [self.controls[@"distractionFreeDivPart"] indexOfSelectedItem] + 3;
    p.smartHighlightUseFindSettings = on(@"smartHighlightUseFindSettings");
    p.smartHighlightOtherView = on(@"smartHighlightOtherView");
    p.highlightMatchingTags = on(@"highlightMatchingTags");
    p.highlightTagAttributes = on(@"highlightTagAttributes");
    p.highlightNonHtmlZone = on(@"highlightNonHtmlZone");
    p.printFormFeedPageBreak = on(@"printFormFeedPageBreak");
    p.customDateFormat = text(@"customDateFormat");
    p.findDialogStaysOpen = on(@"findDialogStaysOpen");
    p.confirmReplaceAllOpenDocs = on(@"confirmReplaceAllOpenDocs");
    p.fillDirectoryFromActiveDocument = on(@"fillDirectoryFromActiveDocument");
    p.inSelectionThreshold = MAX(1, text(@"inSelectionThreshold").integerValue);
    p.fillFindWhatThreshold = MAX(1, text(@"fillFindWhatThreshold").integerValue);
    p.smoothFont = on(@"smoothFont");
    p.selectedTextCustomForeground = on(@"selectedTextCustomForeground");
    p.multiEditing = on(@"multiEditing");
    p.foldCommandsToggle = on(@"foldCommandsToggle");
    p.eolPlainText = [self.controls[@"eolPlainText"] indexOfSelectedItem] == 1;
    p.eolCustomColour = on(@"eolCustomColour");
    p.npcCodepoint = [self.controls[@"npcCodepoint"] indexOfSelectedItem] == 1;
    p.npcCustomColour = on(@"npcCustomColour");
    p.npcIncludeCcUniEol = on(@"npcIncludeCcUniEol");
    p.preventC0Typing = on(@"preventC0Typing");
    p.foldMarginStyle = [self.controls[@"foldMarginStyle"] indexOfSelectedItem];
    p.lineNumberShow = on(@"lineNumberShow");
    p.lineNumberDynamicWidth = [self.controls[@"lineNumberDynamicWidth"] indexOfSelectedItem] == 1;
    p.changeHistoryMargin = on(@"changeHistoryMargin");
    p.changeHistoryText = on(@"changeHistoryText");
    p.backspaceUnindents = on(@"backspaceUnindents");
    p.languageIndent = [(NppLanguageIndentView *)self.controls[@"languageIndent"] draft];
    p.languageMenuHidden = [(NppLanguageListsView *)self.controls[@"languageMenuHidden"] hiddenLanguages];
    p.languageMenuCompact = on(@"languageMenuCompact");
    p.sqlBackslashEscape = on(@"sqlBackslashEscape");
    p.docSwitcherEnabled = on(@"docSwitcherEnabled");
    p.docSwitcherMRU = on(@"docSwitcherMRU");
    p.titleBarFileNameOnly = on(@"titleBarFileNameOnly");
    p.confirmSaveAll = on(@"confirmSaveAll");
    p.muteSounds = on(@"muteSounds");
    p.workspaceSymlinks = on(@"workspaceSymlinks");
    p.sessionFileExtension = text(@"sessionFileExtension");
    p.workspaceFileExtension = text(@"workspaceFileExtension");
    p.searchEngine = [self.controls[@"searchEngine"] indexOfSelectedItem];
    p.searchEngineCustom = text(@"searchEngineCustom");
    p.docPeekOnTab = [self.controls[@"docPeekOnTab"] state] == NSControlStateValueOn;
    p.docPeekOnMap = [self.controls[@"docPeekOnMap"] state] == NSControlStateValueOn;
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSInteger i = 0; i < 3; ++i) {
        NSString *pair = [[self.controls[[NSString stringWithFormat:@"userMatchedPair%ld", (long)i]] stringValue]
                          stringByReplacingOccurrencesOfString:@" " withString:@""];
        // Two plain characters, neither a letter nor a digit, as upstream allows.
        if (pair.length == 2 && [pair characterAtIndex:0] < 128 && [pair characterAtIndex:1] < 128 &&
            [pair rangeOfCharacterFromSet:[NSCharacterSet alphanumericCharacterSet]].location == NSNotFound) {
            [pairs addObject:pair];
        }
    }
    p.userMatchedPairs = pairs;
    [self.editor applyEditorPreferences];
    [self.editor setAutosaveEnabled:p.autosaveEnabled interval:p.autosaveInterval];
    [self.editor applyWordCharacters];
    [self.editor applyPerformanceRestrictions];
    [self.editor markClickableLinks];
    [p applyToEditor:self.editor];
    // The toolbar lives on the window, so the delegate applies those three.
    if ([NSApp.delegate respondsToSelector:@selector(applyToolbarPreferences)]) {
        [NSApp.delegate performSelector:@selector(applyToolbarPreferences)];
    }
    if ([NSApp.delegate respondsToSelector:@selector(applyLocalization)]) {
        [NSApp.delegate performSelector:@selector(applyLocalization)];
    }
    if ([NSApp.delegate respondsToSelector:@selector(rebuildLanguageMenu)]) {
        [NSApp.delegate performSelector:@selector(rebuildLanguageMenu)];
    }
    [self.editor applyLanguage];
    [self.editor refreshChrome];
}

- (void)cancel:(id)sender {
    [self rebuildPages];
    [self.panel orderOut:nil];
}

- (void)resetAll:(id)sender {
    [[NppPreferences shared] reset];
    [[NppPreferences shared] applyToEditor:self.editor];
    [self rebuildPages];
    [self.panel orderOut:nil];
}

/// The controls are built once with the values of the moment; after a reset
/// they have to be built again, or the next Apply writes the old values back.
- (void)rebuildPages {
    NSInteger shown = self.categories.selectedRow;
    for (NSView *page in self.pages.allValues) [page removeFromSuperview];
    [self.pageNames removeAllObjects];
    [self.pages removeAllObjects];
    [self.controls removeAllObjects];
    [self buildPages];
    [self.categories reloadData];
    [self showPageAtIndex:MAX(0, shown)];
}

@end


#pragma mark - Shortcut Mapper


