#import "UserLanguageDialog.h"
#import "NppPanel.h"
#import "SettingsCommands.h"
#import "LanguageCatalog.h"
#include "SciLexer.h"

// Field order inside the prefixed lists, as UserDefineDialog.cpp has it.
static NSArray<NSString *> *CommentFieldNames(void) {
    return @[@"commentLineOpen", @"commentLineContinue", @"commentLineClose", @"commentOpen", @"commentClose"];
}
static NSArray<NSString *> *DelimiterFieldNames(void) {
    NSMutableArray *names = [NSMutableArray array];
    for (int d = 1; d <= 8; ++d) {
        [names addObject:[NSString stringWithFormat:@"delimiter%dOpen", d]];
        [names addObject:[NSString stringWithFormat:@"delimiter%dEscape", d]];
        [names addObject:[NSString stringWithFormat:@"delimiter%dClose", d]];
    }
    return names;
}
/// The lists that are plain text fields, by name.
static NSDictionary<NSString *, NSNumber *> *PlainFieldLists(void) {
    return @{
        @"numberPrefix1": @(SCE_USER_KWLIST_NUMBER_PREFIX1), @"numberPrefix2": @(SCE_USER_KWLIST_NUMBER_PREFIX2),
        @"numberExtras1": @(SCE_USER_KWLIST_NUMBER_EXTRAS1), @"numberExtras2": @(SCE_USER_KWLIST_NUMBER_EXTRAS2),
        @"numberSuffix1": @(SCE_USER_KWLIST_NUMBER_SUFFIX1), @"numberSuffix2": @(SCE_USER_KWLIST_NUMBER_SUFFIX2),
        @"numberRange": @(SCE_USER_KWLIST_NUMBER_RANGE),
        @"operators1": @(SCE_USER_KWLIST_OPERATORS1), @"operators2": @(SCE_USER_KWLIST_OPERATORS2),
        @"code1Open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN), @"code1Middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE),
        @"code1Close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE),
        @"code2Open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_OPEN), @"code2Middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_MIDDLE),
        @"code2Close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_CLOSE),
        @"commentFoldOpen": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_OPEN),
        @"commentFoldMiddle": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_MIDDLE),
        @"commentFoldClose": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_CLOSE),
    };
}

static NSString *HexOf(NSColor *colour) {
    NSColor *c = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return [NSString stringWithFormat:@"%02X%02X%02X", (int)lround(c.redComponent * 255),
            (int)lround(c.greenComponent * 255), (int)lround(c.blueComponent * 255)];
}
static NSColor *ColourOf(NSString *hex, NSColor *fallback) {
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return fallback;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1];
}

@interface NppUserLanguageDialog ()
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NppPanel *panel;
@property (nonatomic, strong) NSPopUpButton *languagePicker;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSControl *> *controls;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSTextView *> *textViews;
@property (nonatomic, strong, readwrite, nullable) NppUserLanguage *current;
@property (nonatomic) BOOL loading;
@property (nonatomic, strong) NSArray<NSView *> *editables;
@end

@implementation NppUserLanguageDialog

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _controls = [NSMutableDictionary dictionary];
    _textViews = [NSMutableDictionary dictionary];
    [self build];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languagesChanged:)
                                                 name:NppUserLanguagesDidChangeNotification object:nil];
    [self refillPicker];
    NppUserLanguage *first = [[LanguageCatalog sharedCatalog] allUserLanguages].firstObject;
    // The language of the document in front, when it is a user one.
    NppUserLanguage *front = editor.currentDocument.language.name
        ? [[LanguageCatalog sharedCatalog] userLanguageNamed:editor.currentDocument.language.name] : nil;
    [self selectLanguageNamed:(front ?: first).name ?: @""];
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (BOOL)visible { return self.panel.isVisible; }

- (void)toggle {
    if (self.panel.isVisible) { [self commit]; [self.panel orderOut:nil]; return; }
    [self refillPicker];
    [self selectLanguageNamed:self.current.name ?: @""];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)note { [self commit]; }

- (NSString *)directory { return [self.editor supportDirectory]; }

#pragma mark - Building the window

- (NSTextField *)label:(NSString *)text at:(NSPoint)p width:(CGFloat)w in:(NSView *)v {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = NSMakeRect(p.x, p.y, w, 18);
    [v addSubview:label];
    return label;
}

- (NSTextField *)field:(NSString *)name at:(NSRect)r in:(NSView *)v {
    NSTextField *field = [[NSTextField alloc] initWithFrame:r];
    field.delegate = self;
    field.font = [NSFont userFixedPitchFontOfSize:11];
    [v addSubview:field];
    self.controls[name] = field;
    return field;
}

- (NSButton *)check:(NSString *)title name:(NSString *)name at:(NSPoint)p in:(NSView *)v {
    NSButton *box = [NSButton checkboxWithTitle:title target:self action:@selector(changed:)];
    [box sizeToFit];
    box.frameOrigin = p;
    [v addSubview:box];
    self.controls[name] = box;
    return box;
}

- (NSButton *)styler:(int)styleID at:(NSPoint)p in:(NSView *)v {
    NSButton *button = [NSButton buttonWithTitle:@"Styler" target:self action:@selector(editStyle:)];
    button.tag = styleID;
    button.frame = NSMakeRect(p.x, p.y - 4, 74, 26);
    [v addSubview:button];
    return button;
}

- (NSTextView *)textArea:(NSString *)name frame:(NSRect)r in:(NSView *)v {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:r];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
    text.font = [NSFont userFixedPitchFontOfSize:11];
    text.richText = NO;
    text.automaticQuoteSubstitutionEnabled = NO;
    text.automaticDashSubstitutionEnabled = NO;
    text.automaticTextReplacementEnabled = NO;
    text.delegate = self;
    text.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = text;
    [v addSubview:scroll];
    self.textViews[name] = text;
    return text;
}

/// Three fields in a row - open, middle or escape, close - under a title.
- (CGFloat)triple:(NSString *)title names:(NSArray<NSString *> *)names labels:(NSArray<NSString *> *)labels
            style:(int)styleID y:(CGFloat)y in:(NSView *)v {
    [self label:title at:NSMakePoint(16, y) width:420 in:v];
    if (styleID >= 0) [self styler:styleID at:NSMakePoint(700, y) in:v];
    y -= 24;
    for (NSUInteger i = 0; i < names.count; ++i) {
        CGFloat x = 16 + (CGFloat)i * 260;
        // (Room for the label in a longer language: "Середина:", "Schließen:".)
        [self label:labels[i] at:NSMakePoint(x, y + 3) width:84 in:v];
        [self field:names[i] at:NSMakeRect(x + 86, y, 164, 22) in:v];
    }
    return y - 36;
}

- (void)build {
    self.panel = [[NppPanel alloc] initWithContentRect:NSMakeRect(0, 0, 800, 620)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                       NSWindowStyleMaskResizable
                                               backing:NSBackingStoreBuffered defer:YES];
    self.panel.title = @"User Defined Language";
    self.panel.releasedWhenClosed = NO;
    self.panel.delegate = self;
    NSView *content = self.panel.contentView;

    // The language, and what can be done with it.
    [self label:@"User language:" at:NSMakePoint(16, 588) width:100 in:content];
    self.languagePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(116, 582, 250, 26)];
    self.languagePicker.target = self;
    self.languagePicker.action = @selector(pickLanguage:);
    [content addSubview:self.languagePicker];
    NSArray *buttons = @[@[@"Create New…", @"createNew:"], @[@"Save As…", @"saveAs:"],
                         @[@"Rename…", @"rename:"], @[@"Remove", @"remove:"],
                         @[@"Import…", @"import:"], @[@"Export…", @"export:"]];
    CGFloat x = 374;
    for (NSArray *b in buttons) {
        NSButton *button = [NSButton buttonWithTitle:b[0] target:self action:NSSelectorFromString(b[1])];
        [button sizeToFit];
        button.frameOrigin = NSMakePoint(x, 582);
        [content addSubview:button];
        x += NSWidth(button.frame) + 2;
    }
    [self label:@"Ext.:" at:NSMakePoint(16, 556) width:40 in:content];
    [self field:@"ext" at:NSMakeRect(56, 552, 250, 22) in:content];
    [self check:@"Ignore case" name:@"caseIgnored" at:NSMakePoint(320, 552) in:content];
    [self check:@"Dark mode variant" name:@"darkModeTheme" at:NSMakePoint(440, 552) in:content];

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(8, 8, 784, 536)];
    [content addSubview:tabs];
    NSView *(^page)(NSString *) = ^NSView *(NSString *title) {
        NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:title];
        item.label = title;
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 770, 500)];
        item.view = view;
        [tabs addTabViewItem:item];
        return view;
    };

    // Folder & Default
    NSView *v = page(@"Folder & Default");
    CGFloat y = 460;
    [self label:@"Default style" at:NSMakePoint(16, y) width:300 in:v];
    [self styler:SCE_USER_STYLE_DEFAULT at:NSMakePoint(700, y) in:v];
    y -= 30;
    [self check:@"Fold compact (fold empty lines too)" name:@"foldCompact" at:NSMakePoint(16, y) in:v];
    y -= 40;
    y = [self triple:@"Folding in code 1 style:" names:@[@"code1Open", @"code1Middle", @"code1Close"]
              labels:@[@"Open:", @"Middle:", @"Close:"] style:SCE_USER_STYLE_FOLDER_IN_CODE1 y:y in:v];
    y = [self triple:@"Folding in code 2 style (separators needed):" names:@[@"code2Open", @"code2Middle", @"code2Close"]
              labels:@[@"Open:", @"Middle:", @"Close:"] style:SCE_USER_STYLE_FOLDER_IN_CODE2 y:y in:v];
    [self triple:@"Folding in comment style:" names:@[@"commentFoldOpen", @"commentFoldMiddle", @"commentFoldClose"]
              labels:@[@"Open:", @"Middle:", @"Close:"] style:SCE_USER_STYLE_FOLDER_IN_COMMENT y:y in:v];

    // Keywords Lists: eight groups, two columns.
    v = page(@"Keywords Lists");
    for (int g = 0; g < 8; ++g) {
        CGFloat gx = (g % 2) ? 392 : 12;
        CGFloat gy = 470 - (CGFloat)(g / 2) * 120;
        [self label:[NSString stringWithFormat:@"%d%@ group", g + 1,
                     g == 0 ? @"st" : g == 1 ? @"nd" : g == 2 ? @"rd" : @"th"]
                 at:NSMakePoint(gx, gy) width:90 in:v];
        [self check:@"Prefix mode" name:[NSString stringWithFormat:@"prefix%d", g + 1]
                 at:NSMakePoint(gx + 96, gy - 2) in:v];
        [self styler:SCE_USER_STYLE_KEYWORD1 + g at:NSMakePoint(gx + 290, gy) in:v];
        [self textArea:[NSString stringWithFormat:@"keywords%d", g + 1]
                 frame:NSMakeRect(gx, gy - 92, 366, 86) in:v];
    }

    // Comment & Number
    v = page(@"Comment & Number");
    y = 460;
    y = [self triple:@"Comment line style:" names:@[@"commentLineOpen", @"commentLineContinue", @"commentLineClose"]
              labels:@[@"Open:", @"Continue:", @"Close:"] style:SCE_USER_STYLE_COMMENTLINE y:y in:v];
    [self label:@"Comment line position:" at:NSMakePoint(16, y + 6) width:160 in:v];
    NSArray *positions = @[@"Allow anywhere", @"Force at beginning of line", @"Allow preceding whitespace"];
    for (NSUInteger i = 0; i < positions.count; ++i) {
        NSButton *radio = [NSButton radioButtonWithTitle:positions[i] target:self action:@selector(changed:)];
        [radio sizeToFit];
        radio.frameOrigin = NSMakePoint(180 + (CGFloat)i * 190, y + 4);
        radio.tag = (NSInteger)i;
        [v addSubview:radio];
        self.controls[[NSString stringWithFormat:@"forcePureLC%lu", (unsigned long)i]] = radio;
    }
    y -= 28;
    [self check:@"Allow folding of comments" name:@"allowFoldOfComments" at:NSMakePoint(16, y) in:v];
    y -= 36;
    [self label:@"Comment style:" at:NSMakePoint(16, y) width:300 in:v];
    [self styler:SCE_USER_STYLE_COMMENT at:NSMakePoint(700, y) in:v];
    y -= 24;
    [self label:@"Open:" at:NSMakePoint(16, y + 3) width:60 in:v];
    [self field:@"commentOpen" at:NSMakeRect(76, y, 190, 22) in:v];
    [self label:@"Close:" at:NSMakePoint(276, y + 3) width:60 in:v];
    [self field:@"commentClose" at:NSMakeRect(336, y, 190, 22) in:v];
    y -= 44;
    [self label:@"Number style:" at:NSMakePoint(16, y) width:300 in:v];
    [self styler:SCE_USER_STYLE_NUMBER at:NSMakePoint(700, y) in:v];
    y -= 26;
    NSArray *numberFields = @[@[@"Prefix 1:", @"numberPrefix1"], @[@"Prefix 2:", @"numberPrefix2"],
                              @[@"Extras 1:", @"numberExtras1"], @[@"Extras 2:", @"numberExtras2"],
                              @[@"Suffix 1:", @"numberSuffix1"], @[@"Suffix 2:", @"numberSuffix2"],
                              @[@"Range:", @"numberRange"]];
    for (NSUInteger i = 0; i < numberFields.count; ++i) {
        CGFloat fx = 16 + (CGFloat)(i % 2) * 380;
        CGFloat fy = y - (CGFloat)(i / 2) * 28;
        [self label:numberFields[i][0] at:NSMakePoint(fx, fy + 3) width:70 in:v];
        [self field:numberFields[i][1] at:NSMakeRect(fx + 70, fy, 290, 22) in:v];
    }
    y -= 4 * 28 + 8;
    [self label:@"Decimal separator:" at:NSMakePoint(16, y + 2) width:130 in:v];
    NSArray *separators = @[@"Dot", @"Comma", @"Both"];
    for (NSUInteger i = 0; i < separators.count; ++i) {
        NSButton *radio = [NSButton radioButtonWithTitle:separators[i] target:self action:@selector(changed:)];
        [radio sizeToFit];
        radio.frameOrigin = NSMakePoint(150 + (CGFloat)i * 90, y);
        [v addSubview:radio];
        self.controls[[NSString stringWithFormat:@"decimalSeparator%lu", (unsigned long)i]] = radio;
    }

    // Operators & Delimiters
    v = page(@"Operators & Delimiters");
    y = 470;
    [self label:@"Operators style" at:NSMakePoint(16, y) width:200 in:v];
    [self styler:SCE_USER_STYLE_OPERATOR at:NSMakePoint(700, y) in:v];
    y -= 26;
    [self label:@"Operators 1:" at:NSMakePoint(16, y + 3) width:90 in:v];
    [self field:@"operators1" at:NSMakeRect(106, y, 580, 22) in:v];
    y -= 28;
    [self label:@"Operators 2 (separators required):" at:NSMakePoint(16, y + 3) width:230 in:v];
    [self field:@"operators2" at:NSMakeRect(246, y, 440, 22) in:v];
    y -= 34;
    for (int d = 1; d <= 8; ++d) {
        [self label:[NSString stringWithFormat:@"Delimiter %d", d] at:NSMakePoint(16, y + 3) width:80 in:v];
        NSArray *parts = @[@"Open", @"Escape", @"Close"];
        for (NSUInteger i = 0; i < parts.count; ++i) {
            CGFloat fx = 96 + (CGFloat)i * 200;
            [self field:[NSString stringWithFormat:@"delimiter%d%@", d, parts[i]]
                     at:NSMakeRect(fx, y, 190, 22) in:v];
            ((NSTextField *)self.controls[[NSString stringWithFormat:@"delimiter%d%@", d, parts[i]]]).placeholderString = parts[i];
        }
        [self styler:SCE_USER_STYLE_DELIMITER1 + d - 1 at:NSMakePoint(700, y + 4) in:v];
        y -= 32;
    }
}

#pragma mark - Controls and the language

- (NSControl *)controlNamed:(NSString *)name { return self.controls[name]; }
- (NSTextView *)textViewNamed:(NSString *)name { return self.textViews[name]; }

- (void)refillPicker {
    NSString *selected = self.current.name;
    [self.languagePicker removeAllItems];
    for (NppUserLanguage *udl in [[LanguageCatalog sharedCatalog] allUserLanguages]) {
        [self.languagePicker addItemWithTitle:udl.name];
    }
    if (selected && [self.languagePicker itemWithTitle:selected]) [self.languagePicker selectItemWithTitle:selected];
}

- (void)languagesChanged:(NSNotification *)note {
    if (self.loading) return;
    [self refillPicker];
}

- (void)selectLanguageNamed:(NSString *)name {
    NppUserLanguage *found = name.length ? [[LanguageCatalog sharedCatalog] userLanguageNamed:name] : nil;
    self.current = [found copy];
    if (found && [self.languagePicker itemWithTitle:found.name]) [self.languagePicker selectItemWithTitle:found.name];
    [self load];
}

- (void)pickLanguage:(id)sender {
    [self commit];
    [self selectLanguageNamed:self.languagePicker.titleOfSelectedItem ?: @""];
}

/// The language into the controls.
- (void)load {
    self.loading = YES;
    NppUserLanguage *udl = self.current;
    BOOL has = udl != nil;
    for (NSControl *c in self.controls.allValues) c.enabled = has;
    for (NSTextView *t in self.textViews.allValues) t.editable = has;

    void (^setText)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
        ((NSTextField *)self.controls[name]).stringValue = value ?: @"";
    };
    void (^setOn)(NSString *, BOOL) = ^(NSString *name, BOOL on) {
        ((NSButton *)self.controls[name]).state = on ? NSControlStateValueOn : NSControlStateValueOff;
    };
    setText(@"ext", [udl.extensions componentsJoinedByString:@" "]);
    setOn(@"caseIgnored", udl.caseIgnored);
    setOn(@"darkModeTheme", udl.darkModeTheme);
    setOn(@"foldCompact", udl.foldCompact);
    setOn(@"allowFoldOfComments", udl.allowFoldOfComments);
    for (int i = 0; i < 3; ++i) {
        setOn([NSString stringWithFormat:@"forcePureLC%d", i], has && udl.forcePureLC == i);
        setOn([NSString stringWithFormat:@"decimalSeparator%d", i], has && udl.decimalSeparator == i);
    }
    NSDictionary *plain = PlainFieldLists();
    for (NSString *name in plain) {
        NSUInteger index = [plain[name] unsignedIntegerValue];
        setText(name, index < udl.keywordLists.count ? udl.keywordLists[index] : @"");
    }
    for (int g = 0; g < 8; ++g) {
        NSUInteger index = SCE_USER_KWLIST_KEYWORDS1 + (NSUInteger)g;
        self.textViews[[NSString stringWithFormat:@"keywords%d", g + 1]].string =
            index < udl.keywordLists.count ? udl.keywordLists[index] : @"";
        setOn([NSString stringWithFormat:@"prefix%d", g + 1],
              g < (int)udl.prefixes.count && [udl.prefixes[(NSUInteger)g] boolValue]);
    }
    NSString *comments = udl.keywordLists.count > SCE_USER_KWLIST_COMMENTS ? udl.keywordLists[SCE_USER_KWLIST_COMMENTS] : @"";
    NSArray *commentNames = CommentFieldNames();
    for (NSUInteger i = 0; i < commentNames.count; ++i) {
        setText(commentNames[i], [NppUserLanguage fieldForCode:(int)i inList:comments]);
    }
    NSString *delimiters = udl.keywordLists.count > SCE_USER_KWLIST_DELIMITERS ? udl.keywordLists[SCE_USER_KWLIST_DELIMITERS] : @"";
    NSArray *delimiterNames = DelimiterFieldNames();
    for (NSUInteger i = 0; i < delimiterNames.count; ++i) {
        setText(delimiterNames[i], [NppUserLanguage fieldForCode:(int)i inList:delimiters]);
    }
    self.loading = NO;
}

/// The controls into the language.
- (void)readControls {
    NppUserLanguage *udl = self.current;
    if (!udl) return;
    NSString *(^text)(NSString *) = ^NSString *(NSString *name) {
        return ((NSTextField *)self.controls[name]).stringValue ?: @"";
    };
    BOOL (^on)(NSString *) = ^BOOL(NSString *name) {
        return ((NSButton *)self.controls[name]).state == NSControlStateValueOn;
    };
    NSMutableArray *exts = [NSMutableArray array];
    for (NSString *e in [text(@"ext") componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (e.length) [exts addObject:e];
    }
    udl.extensions = exts;
    udl.caseIgnored = on(@"caseIgnored");
    udl.darkModeTheme = on(@"darkModeTheme");
    udl.foldCompact = on(@"foldCompact");
    udl.allowFoldOfComments = on(@"allowFoldOfComments");
    for (int i = 0; i < 3; ++i) {
        if (on([NSString stringWithFormat:@"forcePureLC%d", i])) udl.forcePureLC = i;
        if (on([NSString stringWithFormat:@"decimalSeparator%d", i])) udl.decimalSeparator = i;
    }
    NSMutableArray *lists = [udl.keywordLists mutableCopy] ?: [NSMutableArray array];
    while (lists.count < SCE_USER_KWLIST_TOTAL) [lists addObject:@""];
    NSDictionary *plain = PlainFieldLists();
    for (NSString *name in plain) lists[[plain[name] unsignedIntegerValue]] = text(name);
    NSMutableArray *prefixes = [NSMutableArray array];
    for (int g = 0; g < 8; ++g) {
        lists[SCE_USER_KWLIST_KEYWORDS1 + (NSUInteger)g] =
            self.textViews[[NSString stringWithFormat:@"keywords%d", g + 1]].string ?: @"";
        [prefixes addObject:@(on([NSString stringWithFormat:@"prefix%d", g + 1]))];
    }
    udl.prefixes = prefixes;
    NSMutableArray *commentFields = [NSMutableArray array];
    for (NSString *name in CommentFieldNames()) [commentFields addObject:text(name)];
    lists[SCE_USER_KWLIST_COMMENTS] = [NppUserLanguage listFromFields:commentFields];
    NSMutableArray *delimiterFields = [NSMutableArray array];
    for (NSString *name in DelimiterFieldNames()) [delimiterFields addObject:text(name)];
    lists[SCE_USER_KWLIST_DELIMITERS] = [NppUserLanguage listFromFields:delimiterFields];
    udl.keywordLists = lists;
}

- (void)commit {
    if (self.loading || !self.current) return;
    [self readControls];
    self.loading = YES;
    [[LanguageCatalog sharedCatalog] saveUserLanguage:self.current directory:[self directory]];
    self.loading = NO;
    NppUserLanguage *saved = [[LanguageCatalog sharedCatalog] userLanguageNamed:self.current.name];
    if (saved) self.current = [saved copy];
    [self showOnDocuments];
}

/// Every document in this language shows the change; the one in front at once.
- (void)showOnDocuments {
    EditorController *ed = self.editor;
    NppLanguage *lang = [[LanguageCatalog sharedCatalog] languageNamed:self.current.name ?: @""];
    for (NppDocument *doc in ed.documents) {
        if (lang && [doc.language.name isEqualToString:lang.name]) doc.language = lang;
    }
    if (lang && [ed.currentDocument.language.name isEqualToString:lang.name]) [ed applyLanguage];
}

- (void)changed:(id)sender { [self commit]; }
- (void)controlTextDidEndEditing:(NSNotification *)note { [self commit]; }
- (void)textDidEndEditing:(NSNotification *)note { [self commit]; }

/// While typing, as on Windows, where every keystroke re-styles the document:
/// here a moment after the last one, since each commit also writes the file.
- (void)commitSoon {
    if (self.loading) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commit) object:nil];
    [self performSelector:@selector(commit) withObject:nil afterDelay:0.35];
}
- (void)controlTextDidChange:(NSNotification *)note { [self commitSoon]; }
- (void)textDidChange:(NSNotification *)note { [self commitSoon]; }

- (void)setStyle:(int)styleID attributes:(NSDictionary *)attributes {
    if (!self.current) return;
    [self readControls];
    NSMutableDictionary *styles = [self.current.styles mutableCopy] ?: [NSMutableDictionary dictionary];
    styles[@(styleID)] = [attributes copy];
    self.current.styles = styles;
    self.loading = YES;
    [[LanguageCatalog sharedCatalog] saveUserLanguage:self.current directory:[self directory]];
    self.loading = NO;
    [self showOnDocuments];
}

#pragma mark - The style of a group

- (void)editStyle:(NSButton *)sender {
    if (!self.current) { NppBeep(); return; }
    int styleID = (int)sender.tag;
    NSDictionary *attrs = self.current.styles[@(styleID)] ?: @{};
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, styleID == SCE_USER_STYLE_DEFAULT ? 150 : 376)];
    CGFloat top = NSHeight(view.frame) - 26;

    NSColorWell *fg = [[NSColorWell alloc] initWithFrame:NSMakeRect(110, top - 2, 44, 24)];
    fg.color = ColourOf(attrs[@"fgColor"], NSColor.blackColor);
    NSColorWell *bg = [[NSColorWell alloc] initWithFrame:NSMakeRect(300, top - 2, 44, 24)];
    bg.color = ColourOf(attrs[@"bgColor"], NSColor.whiteColor);
    [self label:@"Foreground:" at:NSMakePoint(10, top + 2) width:95 in:view];
    [self label:@"Background:" at:NSMakePoint(200, top + 2) width:95 in:view];
    [view addSubview:fg]; [view addSubview:bg];
    // "Transparent": the colour is not set, and what lies under shows (colorStyle's two bits).
    int colorStyle = attrs[@"colorStyle"] ? [attrs[@"colorStyle"] intValue] : 3;
    NSButton *fgClear = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    NSButton *bgClear = [NSButton checkboxWithTitle:@"" target:nil action:nil];
    fgClear.toolTip = bgClear.toolTip = @"Transparent";
    fgClear.state = (colorStyle & 1) ? NSControlStateValueOff : NSControlStateValueOn;
    bgClear.state = (colorStyle & 2) ? NSControlStateValueOff : NSControlStateValueOn;
    fgClear.frame = NSMakeRect(160, top, 22, 20);
    bgClear.frame = NSMakeRect(350, top, 22, 20);
    [view addSubview:fgClear]; [view addSubview:bgClear];

    int fontStyle = [attrs[@"fontStyle"] intValue];
    NSButton *bold = [NSButton checkboxWithTitle:@"Bold" target:nil action:nil];
    NSButton *italic = [NSButton checkboxWithTitle:@"Italic" target:nil action:nil];
    NSButton *underline = [NSButton checkboxWithTitle:@"Underline" target:nil action:nil];
    bold.state = (fontStyle & 1) ? NSControlStateValueOn : NSControlStateValueOff;
    italic.state = (fontStyle & 2) ? NSControlStateValueOn : NSControlStateValueOff;
    underline.state = (fontStyle & 4) ? NSControlStateValueOn : NSControlStateValueOff;
    bold.frame = NSMakeRect(10, top - 34, 80, 20);
    italic.frame = NSMakeRect(100, top - 34, 80, 20);
    underline.frame = NSMakeRect(190, top - 34, 100, 20);
    [view addSubview:bold]; [view addSubview:italic]; [view addSubview:underline];

    NSPopUpButton *font = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(60, top - 68, 220, 26)];
    [font addItemWithTitle:@"(default)"];
    [font addItemsWithTitles:[[NSFontManager sharedFontManager].availableFontFamilies
                              sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];
    if ([attrs[@"fontName"] length] && [font itemWithTitle:attrs[@"fontName"]]) [font selectItemWithTitle:attrs[@"fontName"]];
    [self label:@"Font:" at:NSMakePoint(10, top - 64) width:48 in:view];
    [view addSubview:font];
    NSTextField *size = [[NSTextField alloc] initWithFrame:NSMakeRect(340, top - 66, 50, 22)];
    size.stringValue = attrs[@"fontSize"] ?: @"";
    [self label:@"Size:" at:NSMakePoint(290, top - 64) width:48 in:view];
    [view addSubview:size];

    // What may sit inside this style: delimiters and comments only, as on Windows.
    NSMutableArray<NSButton *> *nestBoxes = [NSMutableArray array];
    if (styleID != SCE_USER_STYLE_DEFAULT) {
        NSArray *nestNames = @[@"Delimiter 1", @"Delimiter 2", @"Delimiter 3", @"Delimiter 4",
                               @"Delimiter 5", @"Delimiter 6", @"Delimiter 7", @"Delimiter 8",
                               @"Comment", @"Comment line", @"Keyword 1", @"Keyword 2", @"Keyword 3",
                               @"Keyword 4", @"Keyword 5", @"Keyword 6", @"Keyword 7", @"Keyword 8",
                               @"Operators 1", @"Operators 2", @"Numbers",
                               @"Code 2 open", @"Code 2 middle", @"Code 2 close",
                               @"Comment open", @"Comment middle", @"Comment close"];
        // The bit of each, SCE_USER_MASK_NESTING_*.
        NSArray *nestBits = @[@0x1, @0x2, @0x4, @0x8, @0x10, @0x20, @0x40, @0x80, @0x100, @0x200,
                              @0x400, @0x800, @0x1000, @0x2000, @0x4000, @0x8000, @0x10000, @0x20000,
                              @0x1000000, @0x2000000, @0x4000000,
                              @0x40000, @0x80000, @0x100000, @0x200000, @0x400000, @0x800000];
        BOOL nestable = styleID == SCE_USER_STYLE_COMMENT || styleID == SCE_USER_STYLE_COMMENTLINE ||
                        (styleID >= SCE_USER_STYLE_DELIMITER1 && styleID <= SCE_USER_STYLE_DELIMITER8);
        int nesting = [attrs[@"nesting"] intValue];
        [self label:@"Nesting:" at:NSMakePoint(10, top - 100) width:100 in:view];
        for (NSUInteger i = 0; i < nestNames.count; ++i) {
            NSButton *box = [NSButton checkboxWithTitle:nestNames[i] target:nil action:nil];
            box.frame = NSMakeRect(10 + (CGFloat)(i % 3) * 135, top - 124 - (CGFloat)(i / 3) * 22, 130, 20);
            box.tag = [nestBits[i] integerValue];
            box.state = (nesting & box.tag) ? NSControlStateValueOn : NSControlStateValueOff;
            box.enabled = nestable;
            [view addSubview:box];
            [nestBoxes addObject:box];
        }
    }

    NSAlert *sheet = [[NSAlert alloc] init];
    sheet.messageText = [NSString stringWithFormat:@"Style: %@", [NppUserLanguage styleNames][(NSUInteger)styleID]];
    sheet.accessoryView = view;
    [sheet addButtonWithTitle:@"OK"];
    [sheet addButtonWithTitle:@"Cancel"];
    [sheet beginSheetModalForWindow:self.panel completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        NSMutableDictionary *out = [attrs mutableCopy];
        out[@"fgColor"] = HexOf(fg.color);
        out[@"bgColor"] = HexOf(bg.color);
        out[@"colorStyle"] = [@((fgClear.state == NSControlStateValueOn ? 0 : 1) | (bgClear.state == NSControlStateValueOn ? 0 : 2)) stringValue];
        int styleBits = (bold.state == NSControlStateValueOn ? 1 : 0) |
                        (italic.state == NSControlStateValueOn ? 2 : 0) |
                        (underline.state == NSControlStateValueOn ? 4 : 0);
        out[@"fontStyle"] = [@(styleBits) stringValue];
        if (font.indexOfSelectedItem > 0) out[@"fontName"] = font.titleOfSelectedItem;
        else [out removeObjectForKey:@"fontName"];
        if (size.integerValue > 0) out[@"fontSize"] = [@(size.integerValue) stringValue];
        else [out removeObjectForKey:@"fontSize"];
        if (nestBoxes.count) {
            // Bits with no box of their own stay as the file had them.
            int shown = 0;
            for (NSButton *box in nestBoxes) shown |= (int)box.tag;
            int nesting = [attrs[@"nesting"] intValue] & ~shown;
            for (NSButton *box in nestBoxes) if (box.state == NSControlStateValueOn) nesting |= (int)box.tag;
            out[@"nesting"] = [@(nesting) stringValue];
        }
        [self setStyle:styleID attributes:out];
    }];
}

#pragma mark - Create, keep, remove, move in and out

- (nullable NSString *)askName:(NSString *)message initial:(NSString *)initial {
    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = message;
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 22)];
    input.stringValue = initial ?: @"";
    ask.accessoryView = input;
    [ask addButtonWithTitle:@"OK"];
    [ask addButtonWithTitle:@"Cancel"];
    ask.window.initialFirstResponder = input;
    if ([ask runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return name.length ? name : nil;
}

- (void)refuse:(NSString *)why {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = why;
    [alert beginSheetModalForWindow:self.panel completionHandler:nil];
}

- (BOOL)createLanguageNamed:(NSString *)name {
    [self commit];
    NppUserLanguage *udl = [NppUserLanguage emptyLanguageNamed:name];
    if (![[LanguageCatalog sharedCatalog] saveUserLanguage:udl directory:[self directory]]) return NO;
    [self refillPicker];
    [self selectLanguageNamed:name];
    return YES;
}

- (BOOL)saveCurrentAs:(NSString *)name {
    if (!self.current) return NO;
    [self commit];
    if (![[LanguageCatalog sharedCatalog] saveUserLanguage:self.current asName:name directory:[self directory]]) return NO;
    [self refillPicker];
    [self selectLanguageNamed:name];
    return YES;
}

- (BOOL)renameCurrentTo:(NSString *)name {
    if (!self.current) return NO;
    [self commit];
    NSString *old = self.current.name;
    if (![[LanguageCatalog sharedCatalog] renameUserLanguage:self.current to:name directory:[self directory]]) return NO;
    NppLanguage *renamed = [[LanguageCatalog sharedCatalog] languageNamed:name];
    for (NppDocument *doc in self.editor.documents) {
        if ([doc.language.name isEqualToString:old]) doc.language = renamed;
    }
    [self refillPicker];
    [self selectLanguageNamed:name];
    [self.editor refreshChrome];
    return YES;
}

- (BOOL)removeCurrent {
    if (!self.current) return NO;
    NSString *old = self.current.name;
    if (![[LanguageCatalog sharedCatalog] removeUserLanguage:self.current directory:[self directory]]) return NO;
    // Documents in the language go back to plain text, as on Windows.
    NppLanguage *normal = [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];
    for (NppDocument *doc in self.editor.documents) {
        if ([doc.language.name isEqualToString:old]) doc.language = normal;
    }
    if ([self.editor.currentDocument.language.name isEqualToString:@"normal"]) [self.editor applyLanguage];
    [self refillPicker];
    [self selectLanguageNamed:[[LanguageCatalog sharedCatalog] allUserLanguages].firstObject.name ?: @""];
    [self.editor refreshChrome];
    return YES;
}

- (NSArray<NSString *> *)importFromFile:(NSString *)path {
    [self commit];
    NSArray *added = [[LanguageCatalog sharedCatalog] importUserLanguagesFromFile:path directory:[self directory]];
    [self refillPicker];
    if (added.count) [self selectLanguageNamed:added.firstObject];
    return added;
}

- (BOOL)exportCurrentToFile:(NSString *)path {
    if (!self.current) return NO;
    [self commit];
    return [[LanguageCatalog sharedCatalog] exportUserLanguage:self.current toFile:path];
}

- (void)createNew:(id)sender {
    NSString *name = [self askName:@"Name of the new language:" initial:@""];
    if (name && ![self createLanguageNamed:name]) [self refuse:@"That name is taken."];
}

- (void)saveAs:(id)sender {
    if (!self.current) { NppBeep(); return; }
    NSString *name = [self askName:@"Save the language as:" initial:self.current.name];
    if (name && ![self saveCurrentAs:name]) [self refuse:@"That name is taken."];
}

- (void)rename:(id)sender {
    if (!self.current) { NppBeep(); return; }
    NSString *name = [self askName:@"New name:" initial:self.current.name];
    if (name && ![self renameCurrentTo:name]) [self refuse:@"That name is taken."];
}

- (void)remove:(id)sender {
    if (!self.current) { NppBeep(); return; }
    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = @"Remove the current language";    // UDLRemoveCurrentLang
    ask.informativeText = @"Are you sure?";
    [ask addButtonWithTitle:@"Yes"];
    [ask addButtonWithTitle:@"No"];
    if ([ask runModal] == NSAlertFirstButtonReturn) [self removeCurrent];
}

- (void)import:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowedFileTypes = @[@"xml"];
    if ([open runModal] != NSModalResponseOK || !open.URL) return;
    NSArray *added = [self importFromFile:open.URL.path];
    if (!added.count) [self refuse:@"Nothing was imported: the file holds no language, or only names already taken."];
}

- (void)export:(id)sender {
    if (!self.current) { NppBeep(); return; }
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = [self.current.name stringByAppendingPathExtension:@"xml"];
    if ([save runModal] != NSModalResponseOK || !save.URL) return;
    if (![self exportCurrentToFile:save.URL.path]) [self refuse:@"The file could not be written."];
}

@end
