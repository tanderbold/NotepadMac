#import "ProjectPanel.h"
#import "Localization.h"
#import "SettingsCommands.h"

@implementation NppProjectNode
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _children = [NSMutableArray array];
    _name = @"";
    return self;
}
@end

static NppProjectNode *NewNode(NppProjectNodeKind kind, NSString *name, NppProjectNode *parent) {
    NppProjectNode *node = [[NppProjectNode alloc] init];
    node.kind = kind;
    node.name = name ?: @"";
    node.parent = parent;
    return node;
}

@interface NppProjectPanel ()
@property (nonatomic, strong) NSView *view;
@property (nonatomic, strong) NSOutlineView *outline;
@property (nonatomic, strong) NSTextField *title;
@property (nonatomic, strong, readwrite) NppProjectNode *root;
@property (nonatomic, copy, readwrite, nullable) NSString *workspacePath;
@property (nonatomic, readwrite) BOOL dirty;
@property (nonatomic, readwrite) NSInteger number;
@end

@implementation NppProjectPanel

- (instancetype)initWithNumber:(NSInteger)number frame:(NSRect)frame {
    if (!(self = [super init])) return nil;
    _number = number;
    _view = [[NSView alloc] initWithFrame:frame];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat w = NSWidth(frame), h = NSHeight(frame);
    _title = [NSTextField labelWithString:[NSString stringWithFormat:@"Project Panel %ld", (long)number]];
    _title.font = [NSFont boldSystemFontOfSize:11];
    _title.frame = NSMakeRect(6, h - 22, w - 90, 16);
    _title.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_view addSubview:_title];

    // The workspace menu, as the panel's own "Workspace" button on Windows.
    NSPopUpButton *workspace = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(w - 86, h - 26, 82, 22) pullsDown:YES];
    workspace.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    workspace.controlSize = NSControlSizeSmall;
    workspace.font = [NSFont systemFontOfSize:11];
    [workspace addItemWithTitle:@"Workspace"];
    NSArray *items = @[@[@"New Workspace", @"menuNewWorkspace:"], @[@"Open Workspace…", @"menuOpenWorkspace:"],
                       @[@"Reload Workspace", @"menuReloadWorkspace:"], @[@"Save", @"menuSaveWorkspace:"],
                       @[@"Save As…", @"menuSaveWorkspaceAs:"], @[@"Save a Copy As…", @"menuSaveWorkspaceCopy:"],
                       @[@"Add New Project", @"menuAddProject:"]];
    for (NSArray *i in items) {
        NSMenuItem *mi = [workspace.menu addItemWithTitle:i[0] action:NSSelectorFromString(i[1]) keyEquivalent:@""];
        mi.target = self;
    }
    [_view addSubview:workspace];

    _outline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, w, h - 30)];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    column.width = w - 20;
    [_outline addTableColumn:column];
    _outline.outlineTableColumn = column;
    _outline.headerView = nil;
    _outline.dataSource = self;
    _outline.delegate = self;
    _outline.target = self;
    _outline.doubleAction = @selector(activate:);
    _outline.menu = [[NSMenu alloc] init];
    _outline.menu.delegate = self;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, w, h - 30)];
    scroll.documentView = _outline;
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_view addSubview:scroll];

    [self newWorkspaceWithoutAsking];
    return self;
}

#pragma mark - The workspace

- (void)newWorkspaceWithoutAsking {
    self.root = NewNode(NppProjectNodeWorkspace, @"Workspace", nil);
    self.workspacePath = nil;
    self.dirty = NO;
    [self reloadView];
}

- (void)newWorkspace {
    if (![self confirmDiscardingChanges]) return;
    [self newWorkspaceWithoutAsking];
}

- (BOOL)confirmDiscardingChanges {
    if (!self.dirty) return YES;
    NSInteger answer = self.scriptedAnswer;
    if (!answer) {
        NSAlert *ask = [[NSAlert alloc] init];
        // ProjectPanelChanged: the panel's name as the title.
        ask.messageText = [NSString stringWithFormat:@"%@ %ld", NppL(@"Project Panel"), (long)self.number];
        ask.informativeText = @"The workspace was modified. Do you want to save it?";
        [ask addButtonWithTitle:@"Yes"];
        [ask addButtonWithTitle:@"No"];
        [ask addButtonWithTitle:@"Cancel"];
        answer = [ask runModal];
    }
    if (answer == NSAlertThirdButtonReturn) return NO;
    if (answer == NSAlertFirstButtonReturn) return [self saveWorkspace];
    return YES;
}

/// "C:\a\b.cpp" or "b\c.cpp" from Windows, and "/a/b" here: one shape.
static NSString *PortablePath(NSString *path) {
    return [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
}

- (NSString *)absolutePathFor:(NSString *)stored {
    NSString *path = PortablePath(stored);
    if (path.isAbsolutePath || !self.workspacePath) return path.stringByStandardizingPath;
    return [[self.workspacePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:path]
           .stringByStandardizingPath;
}

/// Relative to the workspace file when below its folder, as getRelativePath does.
- (NSString *)storedPathFor:(NSString *)absolute relativeTo:(NSString *)workspaceFile {
    NSString *folder = [workspaceFile stringByDeletingLastPathComponent];
    NSString *prefix = [folder hasSuffix:@"/"] ? folder : [folder stringByAppendingString:@"/"];
    return [absolute hasPrefix:prefix] ? [absolute substringFromIndex:prefix.length] : absolute;
}

- (void)buildNodesFrom:(NSXMLElement *)element into:(NppProjectNode *)parent {
    for (NSXMLNode *child in element.children) {
        if (child.kind != NSXMLElementKind) continue;
        NSXMLElement *e = (NSXMLElement *)child;
        NSString *name = [e attributeForName:@"name"].stringValue ?: @"";
        if ([e.name isEqualToString:@"Folder"]) {
            NppProjectNode *folder = NewNode(NppProjectNodeFolder, name, parent);
            [parent.children addObject:folder];
            [self buildNodesFrom:e into:folder];
        } else if ([e.name isEqualToString:@"File"] && name.length) {
            NppProjectNode *file = NewNode(NppProjectNodeFile, PortablePath(name).lastPathComponent, parent);
            file.path = [self absolutePathFor:name];
            file.storedPath = name;
            file.storedResolvedPath = file.path;
            [parent.children addObject:file];
        }
    }
}

- (BOOL)openWorkspace:(NSString *)path {
    if (![self confirmDiscardingChanges]) return NO;
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
    NSXMLElement *root = doc.rootElement;
    if (![root.name isEqualToString:@"NotepadPlus"] || ![root elementsForName:@"Project"].count) return NO;
    self.workspacePath = path;
    self.root = NewNode(NppProjectNodeWorkspace, path.lastPathComponent, nil);
    for (NSXMLElement *p in [root elementsForName:@"Project"]) {
        NppProjectNode *project = NewNode(NppProjectNodeProject, [p attributeForName:@"name"].stringValue ?: @"Project",
                                          self.root);
        [self.root.children addObject:project];
        [self buildNodesFrom:p into:project];
    }
    self.dirty = NO;
    [self remember];
    [self reloadView];
    [self.outline expandItem:self.root];
    return YES;
}

- (BOOL)reloadWorkspace {
    if (!self.workspacePath) return NO;
    NSString *path = self.workspacePath;
    self.dirty = NO;                                 // reloading is discarding, by the user's own choice
    return [self openWorkspace:path];
}

- (void)writeNode:(NppProjectNode *)node into:(NSXMLElement *)element relativeTo:(NSString *)file {
    for (NppProjectNode *child in node.children) {
        if (child.kind == NppProjectNodeFolder) {
            NSXMLElement *folder = [NSXMLElement elementWithName:@"Folder"];
            [folder addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:child.name]];
            [self writeNode:child into:folder relativeTo:file];
            [element addChild:folder];
        } else if (child.kind == NppProjectNodeFile) {
            NSXMLElement *leaf = [NSXMLElement elementWithName:@"File"];
            // Untouched since it was read, and written beside where it was read from: as it was.
            BOOL asRead = child.storedPath.length && [child.path isEqualToString:child.storedResolvedPath ?: @""] &&
                          [[file stringByDeletingLastPathComponent] isEqualToString:[self.workspacePath stringByDeletingLastPathComponent] ?: @""];
            [leaf addAttribute:[NSXMLNode attributeWithName:@"name"
                                                stringValue:asRead ? child.storedPath
                                                                   : [self storedPathFor:child.path relativeTo:file]]];
            [element addChild:leaf];
        }
    }
}

- (BOOL)writeTo:(NSString *)path {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    for (NppProjectNode *project in self.root.children) {
        NSXMLElement *p = [NSXMLElement elementWithName:@"Project"];
        [p addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:project.name]];
        [self writeNode:project into:p relativeTo:path];
        [root addChild:p];
    }
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.version = @"1.0";
    doc.characterEncoding = @"UTF-8";
    return [[doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
            writeToFile:path options:NSDataWritingAtomic error:NULL];
}

- (BOOL)saveWorkspace {
    if (!self.workspacePath) {
        NSSavePanel *save = [NSSavePanel savePanel];
        save.nameFieldStringValue = @"Workspace.xml";
        if ([save runModal] != NSModalResponseOK || !save.URL) return NO;
        return [self saveWorkspaceAs:save.URL.path copy:NO];
    }
    if (![self writeTo:self.workspacePath]) return NO;
    self.dirty = NO;
    [self reloadView];
    return YES;
}

- (BOOL)saveWorkspaceAs:(NSString *)path copy:(BOOL)copy {
    if (![self writeTo:path]) return NO;
    if (!copy) {
        self.workspacePath = path;
        self.root.name = path.lastPathComponent;
        self.dirty = NO;
        [self remember];
        [self reloadView];
    }
    return YES;
}

/// The workspace each panel had, for the next launch.
- (void)remember {
    NSMutableDictionary *all = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppMac.projectWorkspaces"]
                                mutableCopy] ?: [NSMutableDictionary dictionary];
    all[[@(self.number) stringValue]] = self.workspacePath ?: @"";
    [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"NppMac.projectWorkspaces"];
}

#pragma mark - The tree

- (void)changed {
    self.dirty = YES;
    [self reloadView];
}

- (NppProjectNode *)addProjectNamed:(NSString *)name {
    NppProjectNode *project = NewNode(NppProjectNodeProject, name.length ? name : @"Project Name", self.root);
    [self.root.children addObject:project];
    [self changed];
    [self.outline expandItem:self.root];
    return project;
}

- (NppProjectNode *)addFolderNamed:(NSString *)name to:(NppProjectNode *)parent {
    if (parent.kind != NppProjectNodeProject && parent.kind != NppProjectNodeFolder) return nil;
    NppProjectNode *folder = NewNode(NppProjectNodeFolder, name.length ? name : @"Folder Name", parent);
    [parent.children addObject:folder];
    [self changed];
    [self.outline expandItem:parent];
    return folder;
}

- (NSArray<NppProjectNode *> *)addFiles:(NSArray<NSString *> *)paths to:(NppProjectNode *)parent {
    if (parent.kind != NppProjectNodeProject && parent.kind != NppProjectNodeFolder) return @[];
    NSMutableArray *added = [NSMutableArray array];
    for (NSString *path in paths) {
        NppProjectNode *file = NewNode(NppProjectNodeFile, path.lastPathComponent, parent);
        file.path = path.stringByStandardizingPath;
        [parent.children addObject:file];
        [added addObject:file];
    }
    if (added.count) {
        [self changed];
        [self.outline expandItem:parent];
    }
    return added;
}

- (void)addContentsOf:(NSString *)directory to:(NppProjectNode *)node {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [[fm contentsOfDirectoryAtPath:directory error:NULL] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *full = [directory stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDirectory]) continue;
        if (isDirectory) {
            NppProjectNode *folder = NewNode(NppProjectNodeFolder, name, node);
            [node.children addObject:folder];
            [self addContentsOf:full to:folder];
        } else {
            NppProjectNode *file = NewNode(NppProjectNodeFile, name, node);
            file.path = full;
            [node.children addObject:file];
        }
    }
}

- (NppProjectNode *)addDirectory:(NSString *)directory to:(NppProjectNode *)parent {
    if (parent.kind != NppProjectNodeProject && parent.kind != NppProjectNodeFolder) return nil;
    NppProjectNode *folder = NewNode(NppProjectNodeFolder, directory.lastPathComponent, parent);
    [parent.children addObject:folder];
    [self addContentsOf:directory to:folder];
    [self changed];
    [self.outline expandItem:parent];
    return folder;
}

- (BOOL)rename:(NppProjectNode *)node to:(NSString *)name {
    if (!name.length || node.kind == NppProjectNodeWorkspace) return NO;
    // A file's label is the end of its path, and renaming the node renames
    // what it points at, as ProjectPanel.cpp's TVN_ENDLABELEDIT does (the file
    // on disk is left alone; a path that does not exist shows as missing).
    if (node.kind == NppProjectNodeFile && node.path.length) {
        NSRange old = [node.path rangeOfString:node.name options:NSBackwardsSearch];
        if (old.location != NSNotFound) node.path = [node.path stringByReplacingCharactersInRange:old withString:name];
    }
    node.name = name;
    [self changed];
    return YES;
}

- (void)remove:(NppProjectNode *)node {
    if (!node.parent) return;
    [node.parent.children removeObject:node];
    [self changed];
}

- (BOOL)moveBy:(NSInteger)step node:(NppProjectNode *)node {
    NSMutableArray *siblings = node.parent.children;
    NSInteger at = (NSInteger)[siblings indexOfObject:node];
    NSInteger to = at + step;
    if (!siblings || at == NSNotFound || to < 0 || to >= (NSInteger)siblings.count) return NO;
    [siblings exchangeObjectAtIndex:(NSUInteger)at withObjectAtIndex:(NSUInteger)to];
    [self changed];
    [self.outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)MAX(0, [self.outline rowForItem:node])]
              byExtendingSelection:NO];
    return YES;
}

- (BOOL)moveUp:(NppProjectNode *)node { return [self moveBy:-1 node:node]; }
- (BOOL)moveDown:(NppProjectNode *)node { return [self moveBy:1 node:node]; }

- (BOOL)modifyFilePath:(NppProjectNode *)node to:(NSString *)path {
    if (node.kind != NppProjectNodeFile || !path.length) return NO;
    node.path = path.stringByStandardizingPath;
    node.name = path.lastPathComponent;
    [self changed];
    return YES;
}

- (void)collectFiles:(NppProjectNode *)node into:(NSMutableArray *)out {
    for (NppProjectNode *child in node.children) {
        if (child.kind == NppProjectNodeFile && child.path) [out addObject:child.path];
        else [self collectFiles:child into:out];
    }
}

- (NSArray<NSString *> *)allFilePaths {
    NSMutableArray *out = [NSMutableArray array];
    [self collectFiles:self.root into:out];
    return out;
}

#pragma mark - The view

- (void)reloadView {
    NSString *where = self.workspacePath ? self.workspacePath.lastPathComponent : @"new workspace";
    self.title.stringValue = [NSString stringWithFormat:@"Project Panel %ld - %@%@", (long)self.number, where,
                              self.dirty ? @" *" : @""];
    [self.outline reloadData];
    [self.outline expandItem:self.root];
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    // No workspace yet: nothing at the top, rather than a nil row AppKit would reject.
    return item ? (NSInteger)[(NppProjectNode *)item children].count : (self.root ? 1 : 0);
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item {
    // AppKit can ask with a stale index while the tree changes under it.
    if (!item) return self.root ?: [[NppProjectNode alloc] init];
    NSArray *children = [(NppProjectNode *)item children];
    return index >= 0 && index < (NSInteger)children.count ? children[(NSUInteger)index] : [[NppProjectNode alloc] init];
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [(NppProjectNode *)item kind] != NppProjectNodeFile;
}

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)column item:(id)item {
    NppProjectNode *node = item;
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 18)];
        cell.identifier = @"cell";
        NSImageView *image = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 1, 16, 16)];
        NSTextField *text = [NSTextField labelWithString:@""];
        text.frame = NSMakeRect(20, 0, 180, 17);
        text.autoresizingMask = NSViewWidthSizable;
        text.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [cell addSubview:image];
        [cell addSubview:text];
        cell.imageView = image;
        cell.textField = text;
    }
    cell.textField.stringValue = node.name;
    BOOL missing = node.kind == NppProjectNodeFile && ![[NSFileManager defaultManager] fileExistsAtPath:node.path ?: @""];
    cell.textField.textColor = missing ? NSColor.disabledControlTextColor : NSColor.labelColor;
    cell.toolTip = node.path;
    NSImage *icon;
    switch (node.kind) {
        case NppProjectNodeWorkspace: icon = [NSImage imageWithSystemSymbolName:@"shippingbox" accessibilityDescription:nil]; break;
        case NppProjectNodeProject: icon = [NSImage imageWithSystemSymbolName:@"folder.badge.gearshape" accessibilityDescription:nil]; break;
        case NppProjectNodeFolder: icon = [NSImage imageNamed:NSImageNameFolder]; break;
        case NppProjectNodeFile: icon = missing ? [NSImage imageWithSystemSymbolName:@"questionmark.square.dashed" accessibilityDescription:nil]
                                                : [[NSWorkspace sharedWorkspace] iconForFile:node.path]; break;
    }
    cell.imageView.image = icon;
    return cell;
}

- (NppProjectNode *)clicked {
    NSInteger row = self.outline.clickedRow >= 0 ? self.outline.clickedRow : self.outline.selectedRow;
    return row >= 0 ? [self.outline itemAtRow:row] : self.root;
}

- (void)activate:(id)sender {
    NppProjectNode *node = [self clicked];
    if (node.kind == NppProjectNodeFile && node.path) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:node.path]) [self.delegate workspaceDidActivateFile:node.path];
        else NppBeep();
    }
}

#pragma mark - The context menus

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NppProjectNode *node = [self clicked];
    void (^add)(NSString *, SEL) = ^(NSString *title, SEL action) {
        NSMenuItem *mi = [menu addItemWithTitle:title action:action keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = node;
    };
    switch (node.kind) {
        case NppProjectNodeWorkspace:
            add(@"Add New Project", @selector(menuAddProject:));
            [menu addItem:[NSMenuItem separatorItem]];
            add(@"New Workspace", @selector(menuNewWorkspace:));
            add(@"Open Workspace…", @selector(menuOpenWorkspace:));
            add(@"Reload Workspace", @selector(menuReloadWorkspace:));
            add(@"Save", @selector(menuSaveWorkspace:));
            add(@"Save As…", @selector(menuSaveWorkspaceAs:));
            add(@"Save a Copy As…", @selector(menuSaveWorkspaceCopy:));
            break;
        case NppProjectNodeProject:
        case NppProjectNodeFolder:
            add(@"Rename…", @selector(menuRename:));
            add(@"Add Folder", @selector(menuAddFolder:));
            add(@"Add Files…", @selector(menuAddFiles:));
            add(@"Add Files from Directory…", @selector(menuAddDirectory:));
            add(@"Remove", @selector(menuRemove:));
            [menu addItem:[NSMenuItem separatorItem]];
            add(@"Move Up", @selector(menuMoveUp:));
            add(@"Move Down", @selector(menuMoveDown:));
            break;
        case NppProjectNodeFile:
            add(@"Open", @selector(activate:));
            add(@"Rename…", @selector(menuRename:));
            add(@"Remove", @selector(menuRemove:));
            add(@"Modify File Path…", @selector(menuModifyPath:));
            [menu addItem:[NSMenuItem separatorItem]];
            add(@"Move Up", @selector(menuMoveUp:));
            add(@"Move Down", @selector(menuMoveDown:));
            break;
    }
}

- (NppProjectNode *)nodeOf:(id)sender {
    id node = [sender respondsToSelector:@selector(representedObject)] ? [sender representedObject] : nil;
    return [node isKindOfClass:[NppProjectNode class]] ? node : [self clicked];
}

- (nullable NSString *)ask:(NSString *)message initial:(NSString *)initial {
    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = message;
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 22)];
    input.stringValue = initial ?: @"";
    ask.accessoryView = input;
    [ask addButtonWithTitle:@"OK"];
    [ask addButtonWithTitle:@"Cancel"];
    ask.window.initialFirstResponder = input;
    if ([ask runModal] != NSAlertFirstButtonReturn) return nil;
    return input.stringValue.length ? input.stringValue : nil;
}

- (void)menuNewWorkspace:(id)sender { [self newWorkspace]; }
- (void)menuOpenWorkspace:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowedFileTypes = @[@"xml", @"workspace"];
    if ([open runModal] != NSModalResponseOK || !open.URL) return;
    if (![self openWorkspace:open.URL.path]) NppBeep();
}
- (void)menuReloadWorkspace:(id)sender {
    if (self.dirty) {
        NSAlert *ask = [[NSAlert alloc] init];
        ask.messageText = @"Reload Workspace";       // ProjectPanelReloadDirty
        ask.informativeText = NppLMessage(@"The current workspace was modified. Reloading will discard all modifications.\nDo you want to continue?", nil, 0);
        [ask addButtonWithTitle:@"Yes"];
        [ask addButtonWithTitle:@"No"];
        if ([ask runModal] != NSAlertFirstButtonReturn) return;
    }
    if (![self reloadWorkspace]) NppBeep();
}
- (void)menuSaveWorkspace:(id)sender { [self saveWorkspace]; }
- (void)menuSaveWorkspaceAs:(id)sender {
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = self.workspacePath.lastPathComponent ?: @"Workspace.xml";
    if ([save runModal] == NSModalResponseOK && save.URL) [self saveWorkspaceAs:save.URL.path copy:NO];
}
- (void)menuSaveWorkspaceCopy:(id)sender {
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = @"Workspace copy.xml";
    if ([save runModal] == NSModalResponseOK && save.URL) [self saveWorkspaceAs:save.URL.path copy:YES];
}
- (void)menuAddProject:(id)sender {
    NSString *name = [self ask:@"Project name:" initial:@"Project Name"];
    if (name) [self addProjectNamed:name];
}
- (void)menuAddFolder:(id)sender {
    NSString *name = [self ask:@"Folder name:" initial:@"Folder Name"];
    if (name) [self addFolderNamed:name to:[self nodeOf:sender]];
}
- (void)menuAddFiles:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    if ([open runModal] != NSModalResponseOK) return;
    [self addFiles:[open.URLs valueForKey:@"path"] to:[self nodeOf:sender]];
}
- (void)menuAddDirectory:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.canChooseDirectories = YES;
    open.canChooseFiles = NO;
    if ([open runModal] != NSModalResponseOK || !open.URL) return;
    [self addDirectory:open.URL.path to:[self nodeOf:sender]];
}
- (void)menuRename:(id)sender {
    NppProjectNode *node = [self nodeOf:sender];
    NSString *name = [self ask:@"New name:" initial:node.name];
    if (name) [self rename:node to:name];
}
- (void)menuRemove:(id)sender {
    NppProjectNode *node = [self nodeOf:sender];
    if (node.kind != NppProjectNodeFile) {
        NSAlert *ask = [[NSAlert alloc] init];
        ask.messageText = @"Remove folder from project";   // ProjectPanelRemoveFolderFromProject
        ask.informativeText = NppLMessage(@"All the sub-items will be removed.\nAre you sure you want to remove this folder from the project?", nil, 0);
        [ask addButtonWithTitle:@"Yes"];
        [ask addButtonWithTitle:@"No"];
        if ([ask runModal] != NSAlertFirstButtonReturn) return;
    }
    [self remove:node];
}
- (void)menuMoveUp:(id)sender { [self moveUp:[self nodeOf:sender]]; }
- (void)menuMoveDown:(id)sender { [self moveDown:[self nodeOf:sender]]; }
- (void)menuModifyPath:(id)sender {
    NppProjectNode *node = [self nodeOf:sender];
    NSString *path = [self ask:@"File path:" initial:node.path];
    if (path) [self modifyFilePath:node to:path];
}

@end
