#import "DockingManager.h"
#import "NppPanel.h"
#import "DocumentListPanel.h"
#import "Localization.h"
#import "EditorController.h"
#import "SettingsCommands.h"

@interface DocumentListPanel () <NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, copy, nullable) NSString *sortColumn;
@property (nonatomic) BOOL sortAscending;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTableColumn *> *columns;
@end

@implementation DocumentListPanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _columns = [NSMutableDictionary dictionary];

    NSRect frame = NSMakeRect(0, 0, 320, 360);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered
                                            defer:YES];
    _panel.title = @"Document List";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSDictionary *titles = @{@"name": @"Name", @"ext": @"Ext.", @"path": @"Path"};
    for (NSString *identifier in @[@"name", @"ext", @"path"]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:identifier];
        col.title = titles[identifier];
        col.width = [identifier isEqualToString:@"name"] ? 170 : [identifier isEqualToString:@"ext"] ? 50 : 200;
        col.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:identifier ascending:YES];
        col.editable = NO;
        [_table addTableColumn:col];
        _columns[identifier] = col;
    }
    _table.allowsMultipleSelection = YES;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.action = @selector(rowClicked:);
    _table.doubleAction = @selector(rowDoubleClicked:);
    _table.menu = [[NSMenu alloc] initWithTitle:@"Files"];
    _table.menu.delegate = self;
    // The header's own menu turns the optional columns on and off.
    _table.headerView.menu = [[NSMenu alloc] initWithTitle:@"Columns"];
    _table.headerView.menu.delegate = self;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[NppDockingManager shared] registerPanel:@"documentList" title:@"Document List" view:scroll defaultPlace:NppDockLeft];
    [self applyColumnVisibility];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentsChanged:)
                                                 name:NppEditorDocumentsDidChangeNotification
                                               object:nil];
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"documentList"]; }
- (NSInteger)rowCount { return self.table.numberOfRows; }

- (void)toggle {
    if ([[NppDockingManager shared] isPanelVisible:@"documentList"]) {
        [[NppDockingManager shared] hidePanel:@"documentList"];
    } else {
        [self.table reloadData];
        [[NppDockingManager shared] showPanel:@"documentList"];
    }
}

#pragma mark - Rows and columns

/// The documents, sorted as the header asks.
- (NSArray<NppDocument *> *)sortedDocuments {
    NSArray<NppDocument *> *docs = self.editor.documents;
    if (!self.sortColumn) return docs;
    NSString *column = self.sortColumn;
    BOOL ascending = self.sortAscending;
    return [docs sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NppDocument *a, NppDocument *b) {
        NSComparisonResult r = [[self textOfColumn:column document:a] localizedStandardCompare:[self textOfColumn:column document:b]];
        return ascending ? r : (NSComparisonResult)-r;
    }];
}

/// What the table shows, row by row: documents, and - with "Group by View"
/// on and both views in use - a heading (a string) above each view's files.
- (NSArray *)rows {
    NSArray<NppDocument *> *docs = [self sortedDocuments];
    NppDocument *second = [self.editor documentInSecondaryView];
    if (!second || ![NppPreferences shared].docListGroupByView) return docs;
    NSMutableArray *out = [NSMutableArray arrayWithObject:NppL(@"View 1")];
    [out addObjectsFromArray:docs];
    [out addObject:NppL(@"View 2")];
    [out addObject:second];
    return out;
}

- (BOOL)isGroupRow:(NSInteger)row {
    NSArray *rows = self.rows;
    return row >= 0 && row < (NSInteger)rows.count && [rows[(NSUInteger)row] isKindOfClass:[NSString class]];
}

- (void)setGroupByView:(BOOL)on {
    [NppPreferences shared].docListGroupByView = on;
    [self.table reloadData];
}

- (NSString *)textOfColumn:(NSString *)identifier document:(NppDocument *)d {
    if ([identifier isEqualToString:@"ext"]) return d.path ? d.path.pathExtension : @"";
    if ([identifier isEqualToString:@"path"]) return d.path ? d.path.stringByDeletingLastPathComponent : @"";
    // The name without its extension while the Ext. column shows it, as upstream.
    NSString *name = d.path ? d.path.lastPathComponent : d.displayName;
    if (d.path && [self.shownColumns containsObject:@"ext"] && d.path.pathExtension.length) {
        name = name.stringByDeletingPathExtension;
    }
    return name ?: @"";
}

- (NSString *)textOfColumn:(NSString *)identifier row:(NSInteger)row {
    NSArray *rows = self.rows;
    if (row < 0 || row >= (NSInteger)rows.count) return @"";
    if ([rows[(NSUInteger)row] isKindOfClass:[NSString class]]) return [identifier isEqualToString:@"name"] ? rows[(NSUInteger)row] : @"";
    return [self textOfColumn:identifier document:rows[(NSUInteger)row]];
}

- (NSArray<NSString *> *)shownColumns {
    NppPreferences *p = [NppPreferences shared];
    NSMutableArray *shown = [NSMutableArray arrayWithObject:@"name"];
    if (p.docListExtColumn) [shown addObject:@"ext"];
    if (p.docListPathColumn) [shown addObject:@"path"];
    return shown;
}

- (void)setColumn:(NSString *)identifier shown:(BOOL)shown {
    NppPreferences *p = [NppPreferences shared];
    if ([identifier isEqualToString:@"ext"]) p.docListExtColumn = shown;
    else if ([identifier isEqualToString:@"path"]) p.docListPathColumn = shown;
    // A column no longer there cannot be what the list is sorted by.
    if (!shown && [self.sortColumn isEqualToString:identifier]) [self sortByColumn:nil ascending:YES];
    [self applyColumnVisibility];
}

- (void)applyColumnVisibility {
    NSArray *shown = self.shownColumns;
    for (NSString *identifier in self.columns) self.columns[identifier].hidden = ![shown containsObject:identifier];
    [self.table reloadData];
}

- (void)sortByColumn:(NSString *)identifier ascending:(BOOL)ascending {
    self.sortColumn = identifier;
    self.sortAscending = ascending;
    self.table.sortDescriptors = identifier ? @[[NSSortDescriptor sortDescriptorWithKey:identifier ascending:ascending]] : @[];
    [self.table reloadData];
}

- (void)tableView:(NSTableView *)tv sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)old {
    NSSortDescriptor *d = tv.sortDescriptors.firstObject;
    self.sortColumn = d.key;
    self.sortAscending = d ? d.ascending : YES;
    [tv reloadData];
}

#pragma mark - Clicks

- (void)activateRow:(NSInteger)row {
    NSArray *rows = self.rows;
    if (row < 0 || row >= (NSInteger)rows.count || [self isGroupRow:row]) return;
    NSUInteger index = [self.editor.documents indexOfObjectIdenticalTo:rows[(NSUInteger)row]];
    if (index != NSNotFound) [self.editor selectDocumentAtIndex:(NSInteger)index];
}

/// A click brings the file to the front, unless it is extending a selection.
- (void)rowClicked:(id)sender {
    NSEventModifierFlags flags = NSApp.currentEvent.modifierFlags;
    if (flags & (NSEventModifierFlagShift | NSEventModifierFlagCommand)) return;
    [self activateRow:self.table.clickedRow];
}

/// A double click below the files opens a new one, as upstream.
- (void)rowDoubleClicked:(id)sender {
    if (self.table.clickedRow < 0) [self.editor newDocument];
}

#pragma mark - Menus

- (NSArray<NppDocument *> *)documentsInRows:(NSIndexSet *)rows {
    NSArray *all = self.rows;
    NSMutableArray *out = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < all.count && [all[i] isKindOfClass:[NppDocument class]] && ![out containsObject:all[i]]) [out addObject:all[i]];
    }];
    return out;
}

- (void)closeRows:(NSIndexSet *)rows {
    for (NppDocument *doc in [self documentsInRows:rows]) {
        NSUInteger index = [self.editor.documents indexOfObjectIdenticalTo:doc];
        if (index == NSNotFound) continue;
        [self.editor selectDocumentAtIndex:(NSInteger)index];
        [self.editor closeCurrentDocument];
    }
    [self.table reloadData];
}

- (void)saveRows:(NSIndexSet *)rows {
    NppDocument *front = self.editor.currentDocument;
    for (NppDocument *doc in [self documentsInRows:rows]) {
        NSUInteger index = [self.editor.documents indexOfObjectIdenticalTo:doc];
        if (index == NSNotFound || !doc.modified) continue;
        [self.editor selectDocumentAtIndex:(NSInteger)index];
        [self.editor saveCurrentDocument];
    }
    NSUInteger back = [self.editor.documents indexOfObjectIdenticalTo:front];
    if (back != NSNotFound) [self.editor selectDocumentAtIndex:(NSInteger)back];
    [self.table reloadData];
}

/// One file: its tab menu. Several: close or save them all.
- (NSMenu *)menuForSelectedRows:(NSIndexSet *)rows {
    if (rows.count == 1) {
        [self activateRow:(NSInteger)rows.firstIndex];
        return self.editor.tabContextMenu ? self.editor.tabContextMenu() : nil;
    }
    if (!rows.count) return nil;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Files"];
    NSMenuItem *close = [menu addItemWithTitle:@"Close Selected Files" action:@selector(closeSelected:) keyEquivalent:@""];
    NSMenuItem *save = [menu addItemWithTitle:@"Save Selected Files" action:@selector(saveSelected:) keyEquivalent:@""];
    close.target = save.target = self;
    return menu;
}

- (void)closeSelected:(id)sender { [self closeRows:self.table.selectedRowIndexes]; }
- (void)saveSelected:(id)sender { [self saveRows:self.table.selectedRowIndexes]; }
- (void)toggleColumn:(NSMenuItem *)item {
    [self setColumn:item.representedObject shown:![self.shownColumns containsObject:item.representedObject]];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    if (menu == self.table.headerView.menu) {
        for (NSArray *c in @[@[@"ext", @"Ext."], @[@"path", @"Path"]]) {
            NSMenuItem *item = [menu addItemWithTitle:c[1] action:@selector(toggleColumn:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = c[0];
            item.state = [self.shownColumns containsObject:c[0]] ? NSControlStateValueOn : NSControlStateValueOff;
        }
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *group = [menu addItemWithTitle:@"Group by View" action:@selector(toggleGroupByView:) keyEquivalent:@""];
        group.target = self;
        group.state = [NppPreferences shared].docListGroupByView ? NSControlStateValueOn : NSControlStateValueOff;
        return;
    }
    // A right click on a row outside the selection works on that row alone.
    NSInteger clicked = self.table.clickedRow;
    if (clicked < 0) return;
    if (![self.table.selectedRowIndexes containsIndex:(NSUInteger)clicked]) {
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)clicked] byExtendingSelection:NO];
    }
    NSMenu *built = [self menuForSelectedRows:self.table.selectedRowIndexes];
    for (NSMenuItem *item in built.itemArray.copy) {
        [built removeItem:item];
        [menu addItem:item];
    }
}

#pragma mark - Table

/// Keeps the table in step with the editor so its row count never goes stale.
- (void)documentsChanged:(NSNotification *)note { [self.table reloadData]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)self.rows.count;
}

- (BOOL)tableView:(NSTableView *)tv isGroupRow:(NSInteger)row { return [self isGroupRow:row]; }
- (BOOL)tableView:(NSTableView *)tv shouldSelectRow:(NSInteger)row { return ![self isGroupRow:row]; }

- (void)toggleGroupByView:(id)sender { [self setGroupByView:![NppPreferences shared].docListGroupByView]; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    // AppKit can ask for a row from a count it cached before tabs were closed,
    // so the index is checked rather than trusted.
    NSArray *rows = self.rows;
    if (row < 0 || row >= (NSInteger)rows.count) return @"";
    if ([rows[(NSUInteger)row] isKindOfClass:[NSString class]]) return (!col || [col.identifier isEqualToString:@"name"]) ? rows[(NSUInteger)row] : @"";
    NppDocument *d = rows[(NSUInteger)row];
    NSString *text = [self textOfColumn:col.identifier document:d];
    // Unsaved files stand out, as the red icon does upstream.
    if ([col.identifier isEqualToString:@"name"] && d.modified) {
        return [[NSAttributedString alloc] initWithString:text attributes:@{NSForegroundColorAttributeName: [NSColor systemRedColor]}];
    }
    return text;
}

@end
