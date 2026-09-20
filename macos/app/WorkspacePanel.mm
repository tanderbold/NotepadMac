#import "WorkspacePanel.h"
#import "SettingsCommands.h"

@interface WSNode : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL isDirectory;
@property (nonatomic, strong, nullable) NSMutableArray<WSNode *> *children;
@end

@implementation WSNode
- (NSMutableArray<WSNode *> *)children {
    if (!_isDirectory) return nil;
    if (_children) return _children;                 // loaded lazily, as the tree expands
    _children = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:_path error:NULL]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;         // hidden entries stay hidden
        NSString *full = [_path stringByAppendingPathComponent:name];
        // Symbolic links only when MISC. allows them, as upstream.
        NSString *type = [fm attributesOfItemAtPath:full error:NULL][NSFileType];
        if ([type isEqualToString:NSFileTypeSymbolicLink] && ![NppPreferences shared].workspaceSymlinks) continue;
        BOOL dir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&dir]) continue;
        WSNode *n = [[WSNode alloc] init];
        n.path = full;
        n.isDirectory = dir;
        [_children addObject:n];
    }
    return _children;
}
@end

@interface WorkspacePanel () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@property (nonatomic, strong) NSScrollView *scroll;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSMutableArray<WSNode *> *roots;
@end

@implementation WorkspacePanel

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super init])) return nil;

    _outline = [[NSOutlineView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.title = @"Workspace";
    col.width = NSWidth(frame);
    [_outline addTableColumn:col];
    _outline.outlineTableColumn = col;
    _outline.headerView = nil;
    _outline.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    _outline.dataSource = self;
    _outline.delegate = self;
    _outline.target = self;
    _outline.doubleAction = @selector(rowDoubleClicked:);
    _outline.menu = [[NSMenu alloc] initWithTitle:@"Folder as Workspace"];
    _outline.menu.delegate = self;
    _roots = [NSMutableArray array];

    _scroll = [[NSScrollView alloc] initWithFrame:frame];
    _scroll.hasVerticalScroller = YES;
    _scroll.autohidesScrollers = YES;
    _scroll.documentView = _outline;
    _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    return self;
}

- (NSView *)view { return self.scroll; }
- (NSString *)rootPath { return self.roots.firstObject.path; }

- (NSArray<NSString *> *)rootPaths {
    NSMutableArray *out = [NSMutableArray array];
    for (WSNode *n in self.roots) [out addObject:n.path];
    return out;
}

- (void)setRootPath:(NSString *)path {
    [self.roots removeAllObjects];
    if (path.length) [self addRootPath:path];
    else [self.outline reloadData];
}

- (void)addRootPath:(NSString *)path {
    if (!path.length || [self.rootPaths containsObject:path]) return;
    WSNode *n = [[WSNode alloc] init];
    n.path = path;
    n.isDirectory = YES;
    [self.roots addObject:n];
    [self.outline reloadData];
    [self.outline expandItem:n];
}

- (void)removeRootPath:(NSString *)path {
    for (WSNode *n in [self.roots copy]) if ([n.path isEqualToString:path]) [self.roots removeObject:n];
    [self.outline reloadData];
}

- (NSArray<NSString *> *)topLevelNames {
    NSMutableArray *out = [NSMutableArray array];
    for (WSNode *root in self.roots) for (WSNode *n in root.children) [out addObject:n.path.lastPathComponent];
    return out;
}

- (BOOL)locateFile:(NSString *)path {
    for (WSNode *root in self.roots) {
        NSString *prefix = [root.path hasSuffix:@"/"] ? root.path : [root.path stringByAppendingString:@"/"];
        if (![path hasPrefix:prefix]) continue;
        WSNode *node = root;
        [self.outline expandItem:node];
        NSArray *parts = [[path substringFromIndex:prefix.length] pathComponents];
        for (NSString *part in parts) {
            WSNode *next = nil;
            for (WSNode *child in node.children) if ([child.path.lastPathComponent isEqualToString:part]) { next = child; break; }
            if (!next) return NO;
            node = next;
            if (node.isDirectory) [self.outline expandItem:node];
        }
        NSInteger row = [self.outline rowForItem:node];
        if (row < 0) return NO;
        [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.outline scrollRowToVisible:row];
        return YES;
    }
    return NO;
}

#pragma mark - The panel's menu (upstream's FileBrowser)

- (NSMenu *)menuForRow:(NSInteger)row {
    WSNode *n = row >= 0 ? [self.outline itemAtRow:row] : nil;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Folder as Workspace"];
    NSMenuItem *(^add)(NSString *, SEL) = ^NSMenuItem *(NSString *title, SEL action) {
        NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:@""];
        item.target = self;
        item.representedObject = n;
        return item;
    };
    BOOL isRoot = n && [self.roots containsObject:n];
    if (!n) {
        add(@"Add", @selector(menuAdd:));
        add(@"Remove All", @selector(menuRemoveAll:));
        return menu;
    }
    if (isRoot) {
        add(@"Remove", @selector(menuRemove:));
        add(@"Remove All", @selector(menuRemoveAll:));
        [menu addItem:[NSMenuItem separatorItem]];
        add(@"Add", @selector(menuAdd:));
        [menu addItem:[NSMenuItem separatorItem]];
    }
    if (n.isDirectory) {
        add(@"Copy path", @selector(menuCopyPath:));
        add(@"Find in Files...", @selector(menuFindInFiles:));
        add(@"Reveal in Finder", @selector(menuReveal:));
        add(@"Terminal here", @selector(menuTerminal:));
    } else {
        add(@"Open", @selector(menuOpen:));
        add(@"Copy path", @selector(menuCopyPath:));
        add(@"Copy file name", @selector(menuCopyName:));
        add(@"Run by system", @selector(menuRunBySystem:));
        add(@"Reveal in Finder", @selector(menuReveal:));
        add(@"Terminal here", @selector(menuTerminal:));
    }
    [menu addItem:[NSMenuItem separatorItem]];
    add(@"Unfold all", @selector(menuUnfoldAll:));
    add(@"Fold all", @selector(menuFoldAll:));
    add(@"Locate current file", @selector(menuLocate:));
    return menu;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSMenu *built = [self menuForRow:self.outline.clickedRow];
    for (NSMenuItem *item in built.itemArray.copy) { [built removeItem:item]; [menu addItem:item]; }
}

- (void)copy:(NSString *)text {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:text forType:NSPasteboardTypeString];
}

- (void)menuAdd:(NSMenuItem *)item {
    NSOpenPanel *chooser = [NSOpenPanel openPanel];
    chooser.canChooseDirectories = YES;
    chooser.canChooseFiles = NO;
    chooser.message = @"Select a folder to add in Folder as Workspace panel";
    if ([chooser runModal] == NSModalResponseOK && chooser.URL) [self addRootPath:chooser.URL.path];
}
- (void)menuRemove:(NSMenuItem *)item { [self removeRootPath:[item.representedObject path]]; }
- (void)menuRemoveAll:(NSMenuItem *)item { [self setRootPath:nil]; }
- (void)menuCopyPath:(NSMenuItem *)item { [self copy:[item.representedObject path]]; }
- (void)menuCopyName:(NSMenuItem *)item { [self copy:[[item.representedObject path] lastPathComponent]]; }
- (void)menuOpen:(NSMenuItem *)item { [self.delegate workspaceDidActivateFile:[item.representedObject path]]; }
- (void)menuRunBySystem:(NSMenuItem *)item {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[item.representedObject path]]];
}
- (void)menuReveal:(NSMenuItem *)item {
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:[item.representedObject path]]]];
}
- (void)menuTerminal:(NSMenuItem *)item {
    WSNode *n = item.representedObject;
    NSString *folder = n.isDirectory ? n.path : n.path.stringByDeletingLastPathComponent;
    NSURL *terminal = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (terminal) {
        [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:folder]] withApplicationAtURL:terminal
                                  configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    }
}
- (void)menuFindInFiles:(NSMenuItem *)item {
    if ([self.delegate respondsToSelector:@selector(workspaceWantsFindInFolder:)]) {
        [self.delegate workspaceWantsFindInFolder:[item.representedObject path]];
    }
}
- (void)menuUnfoldAll:(NSMenuItem *)item { for (WSNode *r in self.roots) [self.outline expandItem:r expandChildren:YES]; }
- (void)menuFoldAll:(NSMenuItem *)item { for (WSNode *r in self.roots) [self.outline collapseItem:r collapseChildren:YES]; }
- (void)menuLocate:(NSMenuItem *)item {
    if ([self.delegate respondsToSelector:@selector(workspaceCurrentFilePath)]) {
        NSString *path = [self.delegate workspaceCurrentFilePath];
        if (path) [self locateFile:path];
    }
}

- (void)rowDoubleClicked:(id)sender {
    WSNode *n = [self.outline itemAtRow:self.outline.clickedRow];
    if (!n) return;
    if (n.isDirectory) {
        if ([self.outline isItemExpanded:n]) [self.outline collapseItem:n];
        else [self.outline expandItem:n];
        return;
    }
    [self.delegate workspaceDidActivateFile:n.path];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)self.roots.count;    // the root folders themselves
    return (NSInteger)[(WSNode *)item children].count;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item {
    // AppKit can ask with a stale index; none is ever out of range here.
    if (!item) return index >= 0 && index < (NSInteger)self.roots.count ? self.roots[(NSUInteger)index] : [[WSNode alloc] init];
    NSArray *children = [(WSNode *)item children];
    return index >= 0 && index < (NSInteger)children.count ? children[(NSUInteger)index] : [[WSNode alloc] init];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [(WSNode *)item isDirectory];
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)col byItem:(id)item {
    return [(WSNode *)item path].lastPathComponent;
}

@end
