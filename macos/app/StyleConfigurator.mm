#import "Localization.h"
#import "StyleConfigurator.h"
#import "NppPanel.h"
#import "SettingsCommands.h"
#import "EditorController.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"

NSString *const NppGlobalStylesName = @"Global Styles";

static NSString *HexOf(NSColor *colour) {
    NSColor *c = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return [NSString stringWithFormat:@"%02X%02X%02X", (int)lround(c.redComponent * 255),
            (int)lround(c.greenComponent * 255), (int)lround(c.blueComponent * 255)];
}

static NSColor *ColourOf(NSString *hex) {
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

/// The labels Notepad++ gives the seven Global override switches.
static NSArray<NSArray<NSString *> *> *OverrideFlags(void) {
    return @[@[@"fg", @"Enable global foreground colour"], @[@"bg", @"Enable global background colour"],
             @[@"font", @"Enable global font"], @[@"fontSize", @"Enable global font size"],
             @[@"bold", @"Enable global bold font style"], @[@"italic", @"Enable global italic font style"],
             @[@"underline", @"Enable global underline font style"]];
}

@interface StyleConfiguratorWindow () <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate,
                                       NSTextViewDelegate, NSTextFieldDelegate>
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSPopUpButton *themePicker;
@property (nonatomic, strong) NSTableView *languageTable;
@property (nonatomic, strong) NSTableView *styleTable;
@property (nonatomic, strong) NSColorWell *foregroundWell;
@property (nonatomic, strong) NSColorWell *backgroundWell;
@property (nonatomic, strong) NSPopUpButton *fontPicker;
@property (nonatomic, strong) NSPopUpButton *sizePicker;
@property (nonatomic, strong) NSButton *boldBox, *italicBox, *underlineBox;
@property (nonatomic, strong) NSButton *fontPanelButton;
@property (nonatomic, strong) NSView *overrideGroup;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSButton *> *overrideBoxes;
@property (nonatomic, strong) NSView *extensionGroup;
@property (nonatomic, strong) NSTextField *defaultExtLabel;
@property (nonatomic, strong) NSTextField *userExtField;
@property (nonatomic, strong) NSView *keywordGroup;
@property (nonatomic, strong) NSTextView *defaultKeywordsView;
@property (nonatomic, strong) NSTextView *userKeywordsView;
@property (nonatomic, strong) NSTextField *descriptionLabel;
@property (nonatomic, strong) NSButton *transparencyBox;
@property (nonatomic, strong) NSSlider *transparencySlider;

// The working copy.
@property (nonatomic, readwrite, copy) NSString *themeName;
@property (nonatomic, strong) NSXMLDocument *document;
@property (nonatomic, strong) NSArray<NSXMLElement *> *lexers;       // row 0 is the global styles
@property (nonatomic, strong) NSArray<NSXMLElement *> *styles;       // of the selected language
@property (nonatomic, readwrite) BOOL dirty;
@property (nonatomic, assign) BOOL updating;

// What Cancel puts back.
@property (nonatomic, copy) NSString *originalThemeName;
@property (nonatomic, copy, nullable) NSString *originalLightTheme;
@property (nonatomic, copy, nullable) NSString *originalDarkTheme;
@property (nonatomic, copy) NSDictionary *originalOverride;
@end

@implementation StyleConfiguratorWindow

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _overrideBoxes = [NSMutableDictionary dictionary];
    [self buildWindow];
    return self;
}

#pragma mark - Window

static NSTextField *Label(NSString *text, NSRect frame) {
    NSTextField *l = [NSTextField labelWithString:text];
    l.frame = frame;
    return l;
}

static NSTableView *ListTable(NSRect frame, NSView *content, id owner) {
    NSTableView *t = [[NSTableView alloc] initWithFrame:frame];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    col.width = NSWidth(frame) - 4;
    [t addTableColumn:col];
    t.headerView = nil;
    t.dataSource = owner;
    t.delegate = owner;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = t;
    scroll.autoresizingMask = NSViewHeightSizable;
    [content addSubview:scroll];
    return t;
}

static NSTextView *KeywordView(NSRect frame, NSView *parent, BOOL editable) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(frame) - 4, NSHeight(frame))];
    tv.editable = editable;
    tv.richText = NO;
    tv.font = [NSFont userFixedPitchFontOfSize:11];
    tv.automaticQuoteSubstitutionEnabled = NO;
    tv.automaticSpellingCorrectionEnabled = NO;
    tv.verticallyResizable = YES;
    tv.textContainer.widthTracksTextView = YES;
    if (!editable) tv.backgroundColor = [NSColor controlBackgroundColor];
    scroll.documentView = tv;
    [parent addSubview:scroll];
    return tv;
}

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 820, 540);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Style Configurator";
    _panel.releasedWhenClosed = NO;
    _panel.delegate = self;
    // A panel's own content view paints nothing, and in dark mode its labels
    // would be white on white; this one follows the appearance.
    NSVisualEffectView *content = [[NSVisualEffectView alloc] initWithFrame:frame];
    content.material = NSVisualEffectMaterialWindowBackground;
    content.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    content.state = NSVisualEffectStateActive;
    CGFloat top = NSHeight(frame);

    [content addSubview:Label(@"Select theme:", NSMakeRect(20, top - 38, 90, 18))];
    _themePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(112, top - 42, 220, 26)];
    _themePicker.target = self;
    _themePicker.action = @selector(themeChosen:);
    [content addSubview:_themePicker];

    [content addSubview:Label(@"Language:", NSMakeRect(20, top - 70, 120, 18))];
    _languageTable = ListTable(NSMakeRect(20, 60, 170, top - 136), content, self);
    [content addSubview:Label(@"Style:", NSMakeRect(200, top - 70, 120, 18))];
    _styleTable = ListTable(NSMakeRect(200, 60, 200, top - 136), content, self);

    // Colours and font.
    CGFloat x = 420;
    _descriptionLabel = Label(@"", NSMakeRect(x, top - 70, 380, 18));
    _descriptionLabel.font = [NSFont boldSystemFontOfSize:12];
    [content addSubview:_descriptionLabel];

    [content addSubview:Label(@"Foreground color", NSMakeRect(x, top - 100, 120, 18))];
    _foregroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 124, top - 104, 48, 26)];
    _foregroundWell.target = self;
    _foregroundWell.action = @selector(colourChanged:);
    [content addSubview:_foregroundWell];
    [content addSubview:Label(@"Background color", NSMakeRect(x + 190, top - 100, 124, 18))];
    _backgroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 316, top - 104, 48, 26)];
    _backgroundWell.target = self;
    _backgroundWell.action = @selector(colourChanged:);
    [content addSubview:_backgroundWell];

    [content addSubview:Label(@"Font name:", NSMakeRect(x, top - 134, 74, 18))];
    _fontPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 76, top - 138, 160, 26)];
    [_fontPicker addItemWithTitle:@""];
    [_fontPicker addItemsWithTitles:[[[NSFontManager sharedFontManager] availableFontFamilies]
                                     sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
    _fontPicker.target = self;
    _fontPicker.action = @selector(fontChanged:);
    [content addSubview:_fontPicker];
    [content addSubview:Label(@"Size:", NSMakeRect(x + 244, top - 134, 34, 18))];
    _sizePicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 280, top - 138, 70, 26)];
    [_sizePicker addItemWithTitle:@""];
    for (NSNumber *n in @[@5, @6, @7, @8, @9, @10, @11, @12, @14, @16, @18, @20, @22, @24, @26, @28]) {
        [_sizePicker addItemWithTitle:n.stringValue];
    }
    _sizePicker.target = self;
    _sizePicker.action = @selector(fontChanged:);
    [content addSubview:_sizePicker];

    _boldBox = [NSButton checkboxWithTitle:@"Bold" target:self action:@selector(fontChanged:)];
    _boldBox.frame = NSMakeRect(x, top - 166, 70, 20);
    _italicBox = [NSButton checkboxWithTitle:@"Italic" target:self action:@selector(fontChanged:)];
    _italicBox.frame = NSMakeRect(x + 80, top - 166, 70, 20);
    _underlineBox = [NSButton checkboxWithTitle:@"Underline" target:self action:@selector(fontChanged:)];
    _underlineBox.frame = NSMakeRect(x + 160, top - 166, 100, 20);
    for (NSButton *b in @[_boldBox, _italicBox, _underlineBox]) [content addSubview:b];
    // The system's font panel, for choosing by sight; what is chosen there
    // lands in the same attributes the pop-ups write.
    _fontPanelButton = [NSButton buttonWithTitle:@"Fonts…" target:self action:@selector(showFontPanel:)];
    _fontPanelButton.frame = NSMakeRect(x - 4, top - 202, 110, 28);      // a row of its own: translated, the three boxes need theirs
    [content addSubview:_fontPanelButton];

    // Only for the Global override style.
    _overrideGroup = [[NSView alloc] initWithFrame:NSMakeRect(x, 60, 380, top - 272)];
    CGFloat oy = NSHeight(_overrideGroup.frame) - 24;
    for (NSArray<NSString *> *flag in OverrideFlags()) {
        NSButton *b = [NSButton checkboxWithTitle:flag[1] target:self action:@selector(overrideToggled:)];
        b.frame = NSMakeRect(0, oy, 360, 20);
        b.identifier = flag[0];
        [_overrideGroup addSubview:b];
        _overrideBoxes[flag[0]] = b;
        oy -= 24;
    }
    [content addSubview:_overrideGroup];

    // Only for languages.
    _extensionGroup = [[NSView alloc] initWithFrame:NSMakeRect(x, top - 264, 380, 56)];   // below the Fonts… row
    [_extensionGroup addSubview:Label(@"Default ext.:", NSMakeRect(0, 32, 118, 18))];
    _defaultExtLabel = Label(@"", NSMakeRect(122, 32, 258, 18));
    _defaultExtLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_extensionGroup addSubview:_defaultExtLabel];
    [_extensionGroup addSubview:Label(@"User ext.:", NSMakeRect(0, 4, 118, 18))];
    _userExtField = [[NSTextField alloc] initWithFrame:NSMakeRect(122, 2, 200, 22)];
    _userExtField.placeholderString = @"ext1 ext2";
    _userExtField.delegate = self;
    [_extensionGroup addSubview:_userExtField];
    [content addSubview:_extensionGroup];

    // Only for styles with a keyword class.
    _keywordGroup = [[NSView alloc] initWithFrame:NSMakeRect(x, 60, 380, top - 332)];
    CGFloat kh = (NSHeight(_keywordGroup.frame) - 44) / 2;
    [_keywordGroup addSubview:Label(@"Default keywords", NSMakeRect(0, NSHeight(_keywordGroup.frame) - 18, 200, 18))];
    _defaultKeywordsView = KeywordView(NSMakeRect(0, kh + 22, 380, kh), _keywordGroup, NO);
    [_keywordGroup addSubview:Label(@"User-defined keywords", NSMakeRect(0, kh + 2, 200, 18))];
    _userKeywordsView = KeywordView(NSMakeRect(0, 0, 380, kh), _keywordGroup, YES);
    _userKeywordsView.delegate = self;
    [content addSubview:_keywordGroup];

    // Bottom row.
    _transparencyBox = [NSButton checkboxWithTitle:@"Transparency" target:self action:@selector(transparencyChanged:)];
    _transparencyBox.frame = NSMakeRect(20, 20, 110, 20);
    [content addSubview:_transparencyBox];
    _transparencySlider = [NSSlider sliderWithValue:0.8 minValue:0.2 maxValue:1.0
                                             target:self action:@selector(transparencyChanged:)];
    _transparencySlider.frame = NSMakeRect(132, 18, 140, 24);
    [content addSubview:_transparencySlider];

    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.frame = NSMakeRect(NSWidth(frame) - 240, 14, 100, 30);
    cancel.keyEquivalent = @"\033";
    [content addSubview:cancel];
    NSButton *save = [NSButton buttonWithTitle:@"Save && Close" target:self action:@selector(saveAndClose:)];
    save.frame = NSMakeRect(NSWidth(frame) - 130, 14, 110, 30);
    save.keyEquivalent = @"\r";
    [content addSubview:save];
    // Upstream's "&&" is Windows' escaped ampersand: the localiser shows "Save & Close" (or the
    // translation), in English too, and keeps the English text to look it up again.
    [[NppLocalization shared] localizeView:save];

    _panel.contentView = content;
}

- (BOOL)visible { return self.panel.isVisible; }
- (NSInteger)styleCount { return (NSInteger)self.styles.count; }

- (void)toggle {
    if (self.panel.isVisible) { [self cancel:nil]; return; }
    [self show];
}

- (void)show {
    if (self.panel.isVisible) { [self.panel makeKeyAndOrderFront:nil]; return; }
    NppPreferences *p = [NppPreferences shared];
    self.originalThemeName = [p effectiveThemeName];
    self.originalLightTheme = p.lightThemeName;
    self.originalDarkTheme = p.darkThemeName;
    self.originalOverride = p.globalOverride ?: @{};

    [self.themePicker removeAllItems];
    [self.themePicker addItemsWithTitles:[StyleCatalog availableThemeNames]];
    [self loadTheme:self.originalThemeName];
    [self.themePicker selectItemWithTitle:self.themeName];

    // Open on the current document's language, as Notepad++ does.
    NSString *current = self.editor.currentDocument.language.name;
    if (!current || ![self selectLanguage:current]) [self selectLanguage:NppGlobalStylesName];
    [self.panel center];
    [self.panel makeKeyAndOrderFront:nil];
}

#pragma mark - The working copy

- (void)loadTheme:(NSString *)name {
    NSString *path = [StyleCatalog pathForThemeNamed:name];
    NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:NULL] : nil;
    if (!doc) {
        name = @"Default";
        doc = [[NSXMLDocument alloc] initWithData:[NSData dataWithContentsOfFile:[StyleCatalog pathForThemeNamed:name]]
                                          options:NSXMLNodePreserveWhitespace error:NULL];
    }
    self.themeName = name;
    self.document = doc;
    self.dirty = NO;
    [self mergeLegacyOverrides];

    NSMutableArray *lexers = [NSMutableArray array];
    NSXMLElement *globals = [[doc nodesForXPath:@"/NotepadPlus/GlobalStyles" error:NULL] firstObject];
    if (!globals) {
        globals = [NSXMLElement elementWithName:@"GlobalStyles"];
        [doc.rootElement addChild:globals];
    }
    [lexers addObject:(NSXMLElement *)globals];
    [lexers addObjectsFromArray:[doc nodesForXPath:@"/NotepadPlus/LexerStyles/LexerType" error:NULL] ?: @[]];
    self.lexers = lexers;
    self.styles = @[];
    [self.languageTable reloadData];
    [self.styleTable reloadData];
}

/// Colours chosen in the earlier, overrides-only configurator become part of
/// the theme the first time it is edited; Save & Close then drops them.
- (void)mergeLegacyOverrides {
    NSDictionary *legacy = [NppPreferences shared].styleOverrides;
    for (NSString *key in legacy) {
        NSArray *parts = [key componentsSeparatedByString:@"/"];
        if (parts.count != 2) continue;
        NSDictionary *attrs = [[NppPreferences shared] styleOverrideForLanguage:parts[0] styleID:[parts[1] intValue]];
        NSString *xpath = [NSString stringWithFormat:@"/NotepadPlus/LexerStyles/LexerType[@name='%@']/WordsStyle[@styleID='%d']",
                           parts[0], [parts[1] intValue]];
        NSXMLElement *e = [[self.document nodesForXPath:xpath error:NULL] firstObject];
        if (!e || !attrs.count) continue;
        if (attrs[@"fg"]) [self set:attrs[@"fg"] attribute:@"fgColor" on:e];
        if (attrs[@"bg"]) [self set:attrs[@"bg"] attribute:@"bgColor" on:e];
        if ([attrs[@"font"] length]) [self set:attrs[@"font"] attribute:@"fontName" on:e];
        if ([attrs[@"size"] intValue] > 0) [self set:[attrs[@"size"] stringValue] attribute:@"fontSize" on:e];
        if (attrs[@"bold"] || attrs[@"italic"] || attrs[@"underline"]) {
            int bits = ([attrs[@"bold"] boolValue] ? 1 : 0) | ([attrs[@"italic"] boolValue] ? 2 : 0) |
                       ([attrs[@"underline"] boolValue] ? 4 : 0);
            [self set:[@(bits) stringValue] attribute:@"fontStyle" on:e];
        }
    }
}

- (void)set:(NSString *)value attribute:(NSString *)name on:(NSXMLElement *)e {
    NSXMLNode *attr = [e attributeForName:name];
    if (attr) attr.stringValue = value ?: @"";
    else [e addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
}

- (nullable NSXMLElement *)selectedLexer {
    NSInteger row = self.languageTable.selectedRow;
    return (row >= 0 && row < (NSInteger)self.lexers.count) ? self.lexers[(NSUInteger)row] : nil;
}

- (BOOL)globalsSelected { return self.languageTable.selectedRow == 0; }

- (nullable NSXMLElement *)selectedStyle {
    NSInteger row = self.styleTable.selectedRow;
    return (row >= 0 && row < (NSInteger)self.styles.count) ? self.styles[(NSUInteger)row] : nil;
}

/// Writes the working copy where the catalogue can read it, and re-renders.
- (void)preview {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"nppmac-style-preview-%d.xml", getpid()]];
    [[self.document XMLDataWithOptions:NSXMLNodePreserveWhitespace] writeToFile:tmp atomically:YES];
    [StyleCatalog loadThemeFromFile:tmp named:self.themeName];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    [self.editor applyLanguage];
}

- (void)schedulePreview {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];
    [self performSelector:@selector(preview) withObject:nil afterDelay:0.4];
}

#pragma mark - Selection

- (BOOL)selectLanguage:(NSString *)lexerName {
    NSUInteger index = NSNotFound;
    if ([lexerName isEqualToString:NppGlobalStylesName]) index = 0;
    else {
        for (NSUInteger i = 1; i < self.lexers.count; ++i) {
            if ([[[self.lexers[i] attributeForName:@"name"] stringValue] isEqualToString:lexerName]) { index = i; break; }
        }
    }
    if (index == NSNotFound) return NO;
    [self.languageTable selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [self.languageTable scrollRowToVisible:(NSInteger)index];
    [self languageSelected];
    return YES;
}

- (BOOL)selectStyleNamed:(NSString *)name {
    for (NSUInteger i = 0; i < self.styles.count; ++i) {
        if ([[[self.styles[i] attributeForName:@"name"] stringValue] isEqualToString:name]) {
            [self.styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self.styleTable scrollRowToVisible:(NSInteger)i];
            [self styleSelected];
            return YES;
        }
    }
    return NO;
}

- (void)languageSelected {
    NSXMLElement *lexer = [self selectedLexer];
    NSString *childName = [self globalsSelected] ? @"WidgetStyle" : @"WordsStyle";
    self.styles = lexer ? [lexer elementsForName:childName] : @[];
    [self.styleTable reloadData];
    if (self.styles.count) {
        [self.styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self.styleTable scrollRowToVisible:0];
    }
    [self styleSelected];
}

/// Loads the selected style into the controls, and shows the groups that apply.
- (void)styleSelected {
    self.updating = YES;
    NSXMLElement *e = [self selectedStyle];
    BOOL globals = [self globalsSelected];
    NSXMLElement *lexer = [self selectedLexer];
    NSString *lexerName = [[lexer attributeForName:@"name"] stringValue];

    NSString *(^attr)(NSString *) = ^NSString *(NSString *n) { return [[e attributeForName:n] stringValue]; };
    BOOL isWords = [e.name isEqualToString:@"WordsStyle"];
    BOOL hasFg = e && (isWords || attr(@"fgColor"));
    BOOL hasBg = e && (isWords || attr(@"bgColor"));
    BOOL hasFont = e && (isWords || attr(@"fontName") || attr(@"fontStyle"));

    self.descriptionLabel.stringValue = e ? (attr(@"name") ?: @"") : @"";
    self.foregroundWell.enabled = hasFg;
    self.backgroundWell.enabled = hasBg;
    self.foregroundWell.color = ColourOf(attr(@"fgColor")) ?: [NSColor textColor];
    self.backgroundWell.color = ColourOf(attr(@"bgColor")) ?: [NSColor textBackgroundColor];
    for (NSControl *c in @[self.fontPicker, self.sizePicker, self.boldBox, self.italicBox, self.underlineBox, self.fontPanelButton]) {
        c.enabled = hasFont;
    }
    NSString *font = attr(@"fontName") ?: @"";
    if (font.length && ![self.fontPicker itemWithTitle:font]) [self.fontPicker addItemWithTitle:font];
    [self.fontPicker selectItemWithTitle:font];
    NSString *size = attr(@"fontSize") ?: @"";
    if (size.length && ![self.sizePicker itemWithTitle:size]) [self.sizePicker addItemWithTitle:size];
    [self.sizePicker selectItemWithTitle:size];
    int bits = attr(@"fontStyle").intValue;
    self.boldBox.state = (bits & 1) ? NSControlStateValueOn : NSControlStateValueOff;
    self.italicBox.state = (bits & 2) ? NSControlStateValueOn : NSControlStateValueOff;
    self.underlineBox.state = (bits & 4) ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL isOverride = globals && [attr(@"name") isEqualToString:@"Global override"];
    self.overrideGroup.hidden = !isOverride;
    NSDictionary *flags = [NppPreferences shared].globalOverride;
    for (NSString *key in self.overrideBoxes) {
        self.overrideBoxes[key].state = [flags[key] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }

    self.extensionGroup.hidden = globals || !lexer;
    NppLanguage *lang = lexerName ? [[LanguageCatalog sharedCatalog] languageNamed:lexerName] : nil;
    self.defaultExtLabel.stringValue = [lang.extensions componentsJoinedByString:@" "] ?: @"";
    self.userExtField.stringValue = [[lexer attributeForName:@"ext"] stringValue] ?: @"";

    NSString *keywordClass = attr(@"keywordClass");
    NSNumber *setIndex = keywordClass.length ? NppKeywordSetIndex(keywordClass) : nil;
    self.keywordGroup.hidden = globals || !setIndex;
    self.defaultKeywordsView.string = (setIndex ? lang.keywordSets[setIndex] : nil) ?: @"";
    self.userKeywordsView.string = [e.stringValue stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    self.updating = NO;
}

#pragma mark - Edits

- (void)setValue:(NSString *)value ofAttribute:(NSString *)attribute {
    NSXMLElement *e = [self selectedStyle];
    if (!e) return;
    if ([[[e attributeForName:attribute] stringValue] ?: @"" isEqualToString:value ?: @""]) return;
    [self set:value attribute:attribute on:e];
    self.dirty = YES;
    [self.styleTable reloadData];
    [self preview];
}

- (void)colourChanged:(NSColorWell *)sender {
    if (self.updating) return;
    [self setValue:HexOf(sender.color) ofAttribute:(sender == self.foregroundWell) ? @"fgColor" : @"bgColor"];
}

- (void)fontChanged:(id)sender {
    if (self.updating) return;
    if (sender == self.fontPicker) {
        [self setValue:self.fontPicker.titleOfSelectedItem ofAttribute:@"fontName"];
    } else if (sender == self.sizePicker) {
        [self setValue:self.sizePicker.titleOfSelectedItem ofAttribute:@"fontSize"];
    } else {
        int bits = (self.boldBox.state == NSControlStateValueOn ? 1 : 0) |
                   (self.italicBox.state == NSControlStateValueOn ? 2 : 0) |
                   (self.underlineBox.state == NSControlStateValueOn ? 4 : 0);
        [self setValue:[@(bits) stringValue] ofAttribute:@"fontStyle"];
    }
}

- (void)showFontPanel:(id)sender {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSString *family = self.fontPicker.titleOfSelectedItem;
    CGFloat size = self.sizePicker.titleOfSelectedItem.doubleValue ?: 12;
    NSFont *font = (family.length ? [manager fontWithFamily:family traits:0 weight:5 size:size] : nil)
                   ?: [NSFont userFixedPitchFontOfSize:size];
    if (self.boldBox.state == NSControlStateValueOn) font = [manager convertFont:font toHaveTrait:NSBoldFontMask];
    if (self.italicBox.state == NSControlStateValueOn) font = [manager convertFont:font toHaveTrait:NSItalicFontMask];
    manager.target = self;
    [manager setSelectedFont:font isMultiple:NO];
    [self.panel makeFirstResponder:nil];
    [manager orderFrontFontPanel:self];
}

/// NSFontPanel's message, sent up the responder chain and to the manager's target.
- (void)changeFont:(NSFontManager *)sender {
    NSFont *current = [sender selectedFont] ?: [NSFont userFixedPitchFontOfSize:12];
    [self applyChosenFont:[sender convertFont:current]];
}

- (void)applyChosenFont:(NSFont *)font {
    if (!font) return;
    NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
    [self setValue:font.familyName ofAttribute:@"fontName"];
    [self setValue:[@((int)lround(font.pointSize)) stringValue] ofAttribute:@"fontSize"];
    int bits = ((traits & NSBoldFontMask) ? 1 : 0) | ((traits & NSItalicFontMask) ? 2 : 0) |
               (self.underlineBox.state == NSControlStateValueOn ? 4 : 0);
    [self setValue:[@(bits) stringValue] ofAttribute:@"fontStyle"];
    [self styleSelected];                 // the controls show what was chosen
}

- (void)setUserExtensions:(NSString *)extensions {
    NSXMLElement *lexer = [self selectedLexer];
    if (!lexer || [self globalsSelected]) return;
    NSString *clean = [[[extensions componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
                       componentsJoinedByString:@" "];
    if ([[[lexer attributeForName:@"ext"] stringValue] ?: @"" isEqualToString:clean]) return;
    [self set:clean attribute:@"ext" on:lexer];
    self.dirty = YES;
    [self preview];
}

- (void)setUserKeywords:(NSString *)keywords {
    NSXMLElement *e = [self selectedStyle];
    if (!e || [self globalsSelected]) return;
    // Nothing but the words: any whitespace the file had inside is replaced.
    NSString *clean = [[[keywords componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
                        filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
                       componentsJoinedByString:@" "];
    if ([[e.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            isEqualToString:clean]) return;
    [e setChildren:nil];
    if (clean.length) [e addChild:[NSXMLNode textWithStringValue:clean]];
    self.dirty = YES;
    [self preview];
}

- (void)setGlobalOverride:(NSString *)flag enabled:(BOOL)on {
    NSMutableDictionary *flags = [[NppPreferences shared].globalOverride mutableCopy] ?: [NSMutableDictionary dictionary];
    flags[flag] = @(on);
    [NppPreferences shared].globalOverride = flags;
    self.dirty = YES;
    [self.editor applyLanguage];
}

- (void)overrideToggled:(NSButton *)sender {
    if (self.updating) return;
    [self setGlobalOverride:sender.identifier enabled:sender.state == NSControlStateValueOn];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object != self.userExtField || self.updating) return;
    // Stored as typed; previewed once typing pauses.
    NSXMLElement *lexer = [self selectedLexer];
    if (!lexer || [self globalsSelected]) return;
    [self set:self.userExtField.stringValue attribute:@"ext" on:lexer];
    self.dirty = YES;
    [self schedulePreview];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    if (note.object == self.userExtField && !self.updating) [self setUserExtensions:self.userExtField.stringValue];
}

- (void)textDidChange:(NSNotification *)note {
    if (note.object != self.userKeywordsView || self.updating) return;
    NSXMLElement *e = [self selectedStyle];
    if (!e) return;
    [e setChildren:nil];
    if (self.userKeywordsView.string.length) [e addChild:[NSXMLNode textWithStringValue:self.userKeywordsView.string]];
    self.dirty = YES;
    [self schedulePreview];
}

- (void)transparencyChanged:(id)sender {
    BOOL on = self.transparencyBox.state == NSControlStateValueOn;
    self.panel.alphaValue = on ? self.transparencySlider.doubleValue : 1.0;
}

#pragma mark - Theme, save, cancel

- (void)selectThemeNamed:(NSString *)name {
    if (![[StyleCatalog availableThemeNames] containsObject:name]) return;
    NSString *lexer = nil;
    if (self.languageTable.selectedRow > 0) lexer = [[[self selectedLexer] attributeForName:@"name"] stringValue];
    [self loadTheme:name];
    [self.themePicker selectItemWithTitle:self.themeName];
    // Choosing a theme here chooses it for the appearance in use.
    NppPreferences *p = [NppPreferences shared];
    (void)[p effectiveThemeName];                 // settles which appearance is in use
    BOOL dark = [LanguageCatalog sharedCatalog].darkMode;
    if (dark) p.darkThemeName = self.themeName; else p.lightThemeName = self.themeName;
    [StyleCatalog loadThemeNamed:self.themeName];
    [self.editor applyLanguage];
    if (!lexer || ![self selectLanguage:lexer]) [self selectLanguage:NppGlobalStylesName];
}

- (void)themeChosen:(id)sender { [self selectThemeNamed:self.themePicker.titleOfSelectedItem]; }

- (void)saveAndClose:(id)sender {
    [self commitPendingText];
    if (self.dirty) {
        NSString *path = [StyleCatalog userPathForThemeNamed:self.themeName];
        if (path) {
            [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                                      withIntermediateDirectories:YES attributes:nil error:NULL];
            [[self.document XMLDataWithOptions:NSXMLNodePreserveWhitespace] writeToFile:path atomically:YES];
            // Its colours now live in the theme itself.
            [NppPreferences shared].styleOverrides = @{};
        }
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];
    [StyleCatalog loadThemeNamed:self.themeName];
    [self.editor applyLanguage];
    self.dirty = NO;
    [self.panel orderOut:nil];
}

- (void)cancel:(id)sender {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(preview) object:nil];
    NppPreferences *p = [NppPreferences shared];
    p.lightThemeName = self.originalLightTheme;
    p.darkThemeName = self.originalDarkTheme;
    p.globalOverride = self.originalOverride ?: @{};
    [StyleCatalog loadThemeNamed:self.originalThemeName ?: [p effectiveThemeName]];
    [self.editor applyLanguage];
    self.dirty = NO;
    [self.panel orderOut:nil];
}

/// A field still being edited has not sent its end-of-editing yet.
- (void)commitPendingText {
    if (self.panel.firstResponder == self.userKeywordsView) [self setUserKeywords:self.userKeywordsView.string];
    NSText *editor = self.userExtField.currentEditor;
    if (editor) [self setUserExtensions:self.userExtField.stringValue];
}

- (BOOL)windowShouldClose:(NSWindow *)window {
    [self cancel:nil];
    return NO;
}

#pragma mark - Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)(tv == self.languageTable ? self.lexers.count : self.styles.count);
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if (tv == self.languageTable) {
        if (row == 0) return NppGlobalStylesName;
        if (row < 0 || row >= (NSInteger)self.lexers.count) return @"";
        NSXMLElement *e = self.lexers[(NSUInteger)row];
        return [[e attributeForName:@"desc"] stringValue] ?: [[e attributeForName:@"name"] stringValue] ?: @"";
    }
    if (row < 0 || row >= (NSInteger)self.styles.count) return @"";
    return [[self.styles[(NSUInteger)row] attributeForName:@"name"] stringValue] ?: @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if (self.updating) return;
    [self commitPendingText];
    if (note.object == self.languageTable) [self languageSelected];
    else [self styleSelected];
}

@end
