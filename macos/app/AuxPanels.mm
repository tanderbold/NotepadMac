#import "DockingManager.h"
#import "NppPanel.h"
#import "AuxPanels.h"
#import "EditorController.h"
#import "ScintillaView.h"

#pragma mark - Character Panel

#include "AsciiHtmlTables.h"

/// A table that hands Return to its owner: Enter inserts the selected value.
@interface NppReturnTableView : NSTableView
@property (nonatomic, copy) void (^onReturn)(void);
@end

@implementation NppReturnTableView
- (void)keyDown:(NSEvent *)event {
    if (self.onReturn && ([event.characters isEqualToString:@"\r"] || [event.characters isEqualToString:@"\x03"])) {
        self.onReturn();
        return;
    }
    [super keyDown:event];
}
@end

/// Notepad++'s ASCII Codes Insertion Panel (AnsiCharPanel): the 256 byte
/// values, read in the document's code page, with their HTML forms.
@interface CharacterPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@end

@implementation CharacterPanel

static NSString *const kControlNames[33] = {
    @"NULL", @"SOH", @"STX", @"ETX", @"EOT", @"ENQ", @"ACK", @"BEL", @"BS", @"TAB", @"LF", @"VT", @"FF",
    @"CR", @"SO", @"SI", @"DLE", @"DC1", @"DC2", @"DC3", @"DC4", @"NAK", @"SYN", @"ETB", @"CAN", @"EM",
    @"SUB", @"ESC", @"FS", @"GS", @"RS", @"US", @"Space"};

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 520, 420);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"ASCII Codes Insertion Panel";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    NppReturnTableView *returnTable = [[NppReturnTableView alloc] initWithFrame:frame];
    __weak __typeof(self) weakSelf = self;
    returnTable.onReturn = ^{ [weakSelf insertRow:weakSelf.table.selectedRow]; };
    _table = returnTable;
    NSArray *columns = @[@[@"value", @"Value", @50], @[@"hex", @"Hex", @40], @[@"char", @"Character", @70],
                         @[@"name", @"HTML Name", @90], @[@"dec", @"HTML Decimal", @100], @[@"hexnum", @"HTML Hexadecimal", @120]];
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        col.editable = NO;
        [_table addTableColumn:col];
    }
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowActivated:);

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[NppDockingManager shared] registerPanel:@"characterPanel" title:@"ASCII Codes Insertion Panel" view:scroll defaultPlace:NppDockRight];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh:)
                                                 name:NppEditorDocumentsDidChangeNotification object:nil];
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)refresh:(NSNotification *)note { if ([[NppDockingManager shared] isPanelVisible:@"characterPanel"]) [self.table reloadData]; }

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"characterPanel"]; }
- (NSInteger)rowCount { return 256; }

- (void)toggle {
    if ([[NppDockingManager shared] isPanelVisible:@"characterPanel"]) { [[NppDockingManager shared] hidePanel:@"characterPanel"]; return; }
    [self.table reloadData];
    [[NppDockingManager shared] showPanel:@"characterPanel"];
}

/// The document's Windows code page: its own for an ANSI encoding, and for a
/// Unicode document the ANSI one Notepad++ would use, 1252.
- (unsigned int)codepage {
    NppDocument *doc = self.editor.currentDocument;
    if (doc.codepage) return doc.codepage;
    NSStringEncoding enc = doc.encoding ?: NSUTF8StringEncoding;
    if (enc == NSUTF8StringEncoding || enc == NSUnicodeStringEncoding || enc == NSUTF16LittleEndianStringEncoding ||
        enc == NSUTF16BigEndianStringEncoding || enc == NSUTF32StringEncoding) return 1252;
    UInt32 cp = CFStringConvertEncodingToWindowsCodepage(CFStringConvertNSStringEncodingToEncoding(enc));
    return cp == kCFStringEncodingInvalidId ? 1252 : cp;
}

- (NSString *)characterForValue:(NSInteger)value {
    if (value <= 32) return kControlNames[value];
    if (value == 127) return @"DEL";
    unsigned char byte = (unsigned char)value;
    CFStringEncoding cf = CFStringConvertWindowsCodepageToEncoding([self codepage]);
    NSStringEncoding enc = cf == kCFStringEncodingInvalidId ? NSWindowsCP1252StringEncoding
                                                            : CFStringConvertEncodingToNSStringEncoding(cf);
    return [[NSString alloc] initWithBytes:&byte length:1 encoding:enc] ?: @"";
}

- (NSString *)textOfColumn:(NSString *)identifier row:(NSInteger)row {
    if (row < 0 || row > 255) return @"";
    if ([identifier isEqualToString:@"value"]) return [NSString stringWithFormat:@"%ld", (long)row];
    if ([identifier isEqualToString:@"hex"]) return [NSString stringWithFormat:@"%02lX", (long)row];
    if ([identifier isEqualToString:@"char"]) return [self characterForValue:row];
    // The HTML columns are for code page 1252 only, as upstream has them.
    if ([self codepage] != 1252) return @"";
    if ([identifier isEqualToString:@"name"]) return kHtmlNames[row] ? @(kHtmlNames[row]) : @"";
    int number = ((row >= 32 && row <= 126 && row != 45) || row >= 160) ? (int)row : kHtmlNumbers[row];
    if (number < 0) return @"";
    if ([identifier isEqualToString:@"dec"]) return [NSString stringWithFormat:@"&#%d;", number];
    if ([identifier isEqualToString:@"hexnum"]) return [NSString stringWithFormat:@"&#x%x;", number];
    return @"";
}

- (void)insertText:(NSString *)text {
    if (!text.length) return;
    ScintillaView *sci = self.editor.sci;
    [sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    [self.editor refreshChrome];
}

/// The character itself, as insertChar puts it in: the byte read in the
/// document's code page.
- (BOOL)insertRow:(NSInteger)row {
    if (row < 0 || row >= self.rowCount) return NO;
    unsigned char byte = (unsigned char)row;
    NSString *text;
    if (row < 128) text = [[NSString alloc] initWithBytes:&byte length:1 encoding:NSASCIIStringEncoding];
    else {
        CFStringEncoding cf = CFStringConvertWindowsCodepageToEncoding([self codepage]);
        text = [[NSString alloc] initWithBytes:&byte length:1
                                      encoding:cf == kCFStringEncodingInvalidId ? NSWindowsCP1252StringEncoding
                                                                                : CFStringConvertEncodingToNSStringEncoding(cf)];
    }
    if (!text.length) return NO;
    [self insertText:text];
    return YES;
}

/// A double click on the Character column puts the character in; on any
/// other column, what that column shows (insertString).
- (BOOL)insertRow:(NSInteger)row column:(NSString *)identifier {
    if (!identifier || [identifier isEqualToString:@"char"]) return [self insertRow:row];
    NSString *text = [self textOfColumn:identifier row:row];
    if (!text.length) return NO;
    [self insertText:text];
    return YES;
}

- (void)rowActivated:(id)sender {
    NSInteger column = self.table.clickedColumn;
    NSString *identifier = column >= 0 ? self.table.tableColumns[(NSUInteger)column].identifier : nil;
    [self insertRow:self.table.clickedRow column:identifier];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return self.rowCount; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    return [self textOfColumn:col.identifier row:row];
}

@end

#pragma mark - Clipboard History

@interface ClipboardHistoryPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableArray<NSString *> *items;
@property (nonatomic, strong) NSTimer *poller;
@property (nonatomic) NSInteger lastChangeCount;
@end

@implementation ClipboardHistoryPanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _items = [NSMutableArray array];
    _lastChangeCount = [NSPasteboard generalPasteboard].changeCount;

    NSRect frame = NSMakeRect(0, 0, 320, 360);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Clipboard History";
    _panel.floatingPanel = YES;
    _panel.releasedWhenClosed = NO;

    _table = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"clip"];
    col.width = frame.size.width - 4;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowActivated:);

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [[NppDockingManager shared] registerPanel:@"clipboardHistory" title:@"Clipboard History" view:scroll defaultPlace:NppDockRight];
    return self;
}

- (void)dealloc { [_poller invalidate]; }

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"clipboardHistory"]; }
- (NSArray<NSString *> *)entries { return self.items; }

/// The pasteboard has no change notification, so it is polled while the panel
/// is open and captured explicitly after the editor's own copy commands.
- (void)capturePasteboard {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    self.lastChangeCount = pb.changeCount;
    NSString *text = [pb stringForType:NSPasteboardTypeString];
    if (!text.length) return;
    if (self.items.count && [self.items.firstObject isEqualToString:text]) return;
    [self.items removeObject:text];
    [self.items insertObject:text atIndex:0];
    while (self.items.count > 30) [self.items removeLastObject];
    [self.table reloadData];
}

- (void)toggle {
    if ([[NppDockingManager shared] isPanelVisible:@"clipboardHistory"]) {
        [self.poller invalidate];
        self.poller = nil;
        [[NppDockingManager shared] hidePanel:@"clipboardHistory"];
        return;
    }
    [self capturePasteboard];
    __weak ClipboardHistoryPanel *weakSelf = self;
    self.poller = [NSTimer scheduledTimerWithTimeInterval:0.75 repeats:YES block:^(NSTimer *t) {
        ClipboardHistoryPanel *me = weakSelf;
        if (!me) { [t invalidate]; return; }
        if ([NSPasteboard generalPasteboard].changeCount != me.lastChangeCount) [me capturePasteboard];
    }];
    [[NppDockingManager shared] showPanel:@"clipboardHistory"];
}

- (BOOL)pasteRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return NO;
    NSString *text = self.items[(NSUInteger)row];
    ScintillaView *sci = self.editor.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS
           wParam:(uptr_t)(pos + (long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) lParam:0];
    [self.editor refreshChrome];
    return YES;
}

- (void)rowActivated:(id)sender { [self pasteRow:self.table.clickedRow]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)self.items.count; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.items.count) return @"";
    NSString *text = self.items[(NSUInteger)row];
    NSString *oneLine = [[text componentsSeparatedByCharactersInSet:
                          [NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    return oneLine.length > 80 ? [[oneLine substringToIndex:77] stringByAppendingString:@"..."] : oneLine;
}

@end
