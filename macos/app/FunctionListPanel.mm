#import "DockingManager.h"
#import "NppPanel.h"
#import "FunctionListPanel.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import "FunctionListCatalog.h"

@interface FunctionListPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;   // name + line
/// What the list was parsed for: the document, its language and whether it had unsaved changes.
@property (nonatomic, weak) id parsedDocument;
@property (nonatomic, copy) NSString *parsedLanguage;
@property (nonatomic) BOOL parsedModified;
@end

@implementation FunctionListPanel

/// One pattern per language family. Capture group 1 is the name.
static NSString *PatternForLanguage(NSString *lang) {
    static NSDictionary *patterns;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        patterns = @{
            @"python":     @"^\\s*(?:async\\s+)?def\\s+(\\w+)\\s*\\(",
            @"ruby":       @"^\\s*def\\s+([\\w.]+)",
            @"javascript": @"(?:function\\s+(\\w+)\\s*\\()|(?:(\\w+)\\s*[:=]\\s*(?:async\\s*)?function)",
            @"typescript": @"(?:function\\s+(\\w+)\\s*\\()|(?:(\\w+)\\s*[:=]\\s*(?:async\\s*)?function)",
            @"php":        @"function\\s+(\\w+)\\s*\\(",
            @"lua":        @"function\\s+([\\w.:]+)\\s*\\(",
            @"rust":       @"^\\s*(?:pub\\s+)?fn\\s+(\\w+)",
            @"go":         @"^\\s*func\\s+(?:\\([^)]*\\)\\s*)?(\\w+)",
            @"java":       @"(?:public|private|protected|static|final|\\s)+[\\w<>\\[\\]]+\\s+(\\w+)\\s*\\([^)]*\\)\\s*\\{",
            @"cs":         @"(?:public|private|protected|internal|static|\\s)+[\\w<>\\[\\]]+\\s+(\\w+)\\s*\\([^)]*\\)",
            @"cpp":        @"^[\\w:<>~&*\\s]+?\\b(\\w+)\\s*\\([^;]*\\)\\s*(?:const\\s*)?\\{",
            @"c":          @"^[\\w:<>~&*\\s]+?\\b(\\w+)\\s*\\([^;]*\\)\\s*\\{",
            @"objc":       @"^[-+]\\s*\\([^)]*\\)\\s*(\\w+)",
            @"bash":       @"^\\s*(?:function\\s+)?(\\w+)\\s*\\(\\)\\s*\\{",
            @"perl":       @"^\\s*sub\\s+(\\w+)",
            @"sql":        @"(?:CREATE|ALTER)\\s+(?:OR\\s+REPLACE\\s+)?(?:FUNCTION|PROCEDURE)\\s+([\\w.]+)",
        };
    });
    return patterns[lang ?: @""] ?: @"^[\\w:<>~&*\\s]+?\\b(\\w+)\\s*\\([^;]*\\)\\s*\\{";
}

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _entries = @[];

    NSRect frame = NSMakeRect(0, 0, 260, 400);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Function List";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"fn"];
    col.width = frame.size.width - 4;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowActivated:);
    // Parsed again when another document comes to the front, its language changes or it is saved
    // (Notepad_plus::notifyBufferActivated, BufferChangeLanguage, doSave) - not on every keystroke.
    __weak FunctionListPanel *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:NppEditorDocumentsDidChangeNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) { [weakSelf followEditor]; }];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[NppDockingManager shared] registerPanel:@"functionList" title:@"Function List" view:scroll defaultPlace:NppDockRight];
    return self;
}

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"functionList"]; }

- (void)followEditor {
    if (![self visible]) return;
    NppDocument *doc = self.editor.currentDocument;
    NSString *lang = doc.language.name ?: @"";
    BOOL saved = self.parsedModified && !doc.modified && doc == self.parsedDocument;
    if (doc != self.parsedDocument || ![lang isEqualToString:self.parsedLanguage ?: @""] || saved) [self reload];
    else self.parsedModified = doc.modified;
}

- (void)reload {
    self.parsedDocument = self.editor.currentDocument;
    self.parsedLanguage = self.editor.currentDocument.language.name ?: @"";
    self.parsedModified = self.editor.currentDocument.modified;
    NSString *text = [self.editor.sci string] ?: @"";
    NSString *lang = self.editor.currentDocument.language.name;

    // Notepad++'s own parser for this language, when it has one.
    NSString *ext = self.editor.currentDocument.path.pathExtension;
    NSArray<NppFunctionEntry *> *upstream =
        [[FunctionListCatalog sharedCatalog] entriesInText:text forLanguage:lang ?: @"" extension:ext];
    if (upstream.count) {
        NSMutableArray *found = [NSMutableArray array];
        for (NppFunctionEntry *e in upstream) {
            NSString *shown = e.container.length
                ? [NSString stringWithFormat:@"%@::%@", e.container, e.name] : e.name;
            [found addObject:@{@"name": shown, @"line": @(e.line)}];
        }
        self.entries = found;
        [self.table reloadData];
        return;
    }

    // Languages upstream has no parser for still get the built-in patterns.
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:PatternForLanguage(lang)
                             options:NSRegularExpressionAnchorsMatchLines error:NULL];
    NSMutableArray *found = [NSMutableArray array];
    if (re) {
        NSArray *lines = [text componentsSeparatedByString:@"\n"];
        for (NSUInteger i = 0; i < lines.count; ++i) {
            NSString *line = lines[i];
            NSTextCheckingResult *m = [re firstMatchInString:line options:0
                                                       range:NSMakeRange(0, line.length)];
            if (!m) continue;
            NSString *name = nil;
            for (NSUInteger g = 1; g < m.numberOfRanges; ++g) {
                NSRange r = [m rangeAtIndex:g];
                if (r.location != NSNotFound && r.length) { name = [line substringWithRange:r]; break; }
            }
            if (name.length) [found addObject:@{@"name": name, @"line": @(i)}];
        }
    }
    self.entries = found;
    [self.table reloadData];
}

- (NSArray<NSString *> *)functionNames {
    [self reload];
    NSMutableArray *names = [NSMutableArray array];
    for (NSDictionary *e in self.entries) [names addObject:e[@"name"]];
    return names;
}

- (void)toggle {
    if ([[NppDockingManager shared] isPanelVisible:@"functionList"]) { [[NppDockingManager shared] hidePanel:@"functionList"]; return; }
    [self reload];
    [[NppDockingManager shared] showPanel:@"functionList"];
}

- (void)rowActivated:(id)sender {
    NSInteger row = self.table.clickedRow;
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    long line = [self.entries[(NSUInteger)row][@"line"] longValue];
    [self.editor.sci message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
    // Typing goes on in the editor (NM_DBLCLK posts SCEN_SETFOCUS to the edit view).
    [self.editor.sci.window makeFirstResponder:self.editor.sci.content];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.entries.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.entries.count) return @"";
    NSDictionary *e = self.entries[(NSUInteger)row];
    return [NSString stringWithFormat:@"%@  (line %ld)", e[@"name"], [e[@"line"] longValue] + 1];
}

+ (BOOL)exportFunctionListOf:(EditorController *)editor to:(NSString *)path {
    NppDocument *doc = editor.currentDocument;
    NSString *target = path;
    if (!target.length) {
        if (!doc.path.length || ![[NSFileManager defaultManager] fileExistsAtPath:doc.path]) return NO;
        target = [doc.path stringByAppendingString:@".result.json"];
    }
    NSArray<NppFunctionEntry *> *entries =
        [[FunctionListCatalog sharedCatalog] entriesInText:[editor.sci string] ?: @""
                                               forLanguage:doc.language.name ?: @"" extension:doc.path.pathExtension];
    NSMutableArray *leaves = [NSMutableArray array];
    NSMutableArray<NSMutableDictionary *> *nodes = [NSMutableArray array];
    for (NppFunctionEntry *e in entries) {
        if (e.isClass) continue;                      // a class is its node, not a leaf
        if (!e.container.length) { [leaves addObject:e.name]; continue; }
        NSMutableDictionary *node = nil;
        for (NSMutableDictionary *n in nodes) if ([n[@"name"] isEqualToString:e.container]) { node = n; break; }
        if (!node) {
            node = [@{@"leaves": [NSMutableArray array], @"name": e.container} mutableCopy];
            [nodes addObject:node];
        }
        [node[@"leaves"] addObject:e.name];
    }
    NSMutableDictionary *json = [NSMutableDictionary dictionary];
    json[@"root"] = doc.path.lastPathComponent ?: doc.displayName ?: @"";
    if (leaves.count) json[@"leaves"] = leaves;
    if (nodes.count) json[@"nodes"] = nodes;
    // nlohmann::json writes keys in order and compactly, and so does this.
    NSData *data = [NSJSONSerialization dataWithJSONObject:json
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:NULL];
    return [data writeToFile:target atomically:YES];
}

@end
