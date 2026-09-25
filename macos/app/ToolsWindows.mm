#import "ToolsWindows.h"
#import "ConverterCommands.h"
#import "ImageCommands.h"
#import "Localization.h"
#import "JsonCommands.h"

#pragma mark - What the four windows are built from

// Everything here is laid out by constraints, so a control is as wide as its
// text in whatever language it is shown: nothing is cut, and nothing is
// measured by hand.

static NSTextField *Label(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

/// A label that may run to several lines: for what is said about the input, which can be a sentence.
static NSTextField *Note(void) {
    NSTextField *note = [NSTextField wrappingLabelWithString:@""];
    note.translatesAutoresizingMaskIntoConstraints = NO;
    note.selectable = NO;
    [note setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return note;
}

static NSButton *Button(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return button;
}

static NSButton *Checkbox(NSString *title, id target, SEL action) {
    NSButton *box = [NSButton checkboxWithTitle:title target:target action:action];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    [box setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return box;
}

static NSTextField *Field(NSString *value, CGFloat width, id delegate) {
    NSTextField *field = [NSTextField textFieldWithString:value];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.delegate = delegate;
    field.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    if (width > 0) [field.widthAnchor constraintGreaterThanOrEqualToConstant:width].active = YES;
    return field;
}

/// A field that shows a result: to be selected and copied, not typed into.
static NSTextField *ResultField(void) {
    NSTextField *field = Field(@"", 520, nil);
    field.editable = NO;
    field.selectable = YES;
    field.lineBreakMode = NSLineBreakByTruncatingMiddle;
    // As wide as the window lets it be, not as its contents are long: an Argon2 string would double the window.
    [field setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return field;
}

static NSPopUpButton *Popup(NSArray<NSString *> *titles, id target, SEL action) {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    [popup addItemsWithTitles:titles];
    popup.target = target; popup.action = action;
    return popup;
}

static NSScrollView *TextArea(BOOL editable, id delegate, CGFloat height, NSTextView *__strong *view) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 460, height)];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 460, height)];
    text.minSize = NSMakeSize(0, height);
    text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    text.verticallyResizable = YES;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.widthTracksTextView = YES;
    text.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    text.editable = editable;
    text.richText = NO;
    text.allowsUndo = editable;
    text.automaticQuoteSubstitutionEnabled = NO;       // what is hashed is what was typed
    text.automaticDashSubstitutionEnabled = NO;
    text.automaticTextReplacementEnabled = NO;
    text.automaticSpellingCorrectionEnabled = NO;
    text.delegate = delegate;
    scroll.documentView = text;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:height].active = YES;
    [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:460].active = YES;
    [scroll setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    *view = text;
    return scroll;
}

static NSStackView *Row(NSArray<NSView *> *views) {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeFirstBaseline;
    row.spacing = 8;
    return row;
}

/// Takes what room a row has left, pushing what follows it to the far side.
static NSView *Spring(void) {
    NSView *spring = [[NSView alloc] init];
    spring.translatesAutoresizingMaskIntoConstraints = NO;
    [spring setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spring;
}

static NSPanel *PanelHolding(NSArray<NSView *> *rows, NSString *title, NSString *autosaveName) {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 300)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                  backing:NSBackingStoreBuffered defer:YES];
    panel.title = title;
    panel.releasedWhenClosed = NO;
    panel.floatingPanel = NO;
    panel.hidesOnDeactivate = NO;
    NSStackView *column = [NSStackView stackViewWithViews:rows];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    column.orientation = NSUserInterfaceLayoutOrientationVertical;
    column.alignment = NSLayoutAttributeLeading;
    column.spacing = 10;
    column.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    // Every row the whole width: a text area is only as wide as the window because of this.
    for (NSView *row in rows) [row.widthAnchor constraintEqualToAnchor:column.widthAnchor constant:-32].active = YES;
    NSView *content = panel.contentView;
    [content addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
    (void)autosaveName;
    return panel;
}

/// In the language chosen, and no smaller than its texts in that language need.
static void Present(NSPanel *panel) {
    [[NppLocalization shared] localizeWindow:panel];
    [panel.contentView layoutSubtreeIfNeeded];
    NSSize least = [panel.contentView fittingSize];
    panel.contentMinSize = least;
    NSSize now = [panel.contentView frame].size;
    if (now.width < least.width || now.height < least.height)
        [panel setContentSize:NSMakeSize(MAX(now.width, least.width), MAX(now.height, least.height))];
    if (!panel.isVisible) [panel center];
    [panel makeKeyAndOrderFront:nil];
}

static void CopyText(NSString *text) {
    if (!text.length) { NSBeep(); return; }
    NSPasteboard *board = [NSPasteboard generalPasteboard];
    [board clearContents];
    [board setString:text forType:NSPasteboardTypeString];
}

/// A translated sentence with the name of an algorithm in it. The translators had "SHA-256" to
/// work with, and kept it as it is; the digests upstream has no dialog for borrow its wording.
static NSString *Naming(NSString *englishWithSHA256, NSString *name) {
    NSString *translated = NppL(englishWithSHA256);
    if (![translated containsString:@"SHA-256"]) translated = englishWithSHA256;
    return [translated stringByReplacingOccurrencesOfString:@"SHA-256" withString:name];
}

#pragma mark - Digests

@interface NppDigestWindow () <NSTextViewDelegate, NSTextFieldDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NppDigest digest;
@property (nonatomic) BOOL fromFiles;
@property (nonatomic) NSTextView *input, *result;
@property (nonatomic) NSButton *eachLine, *chooseFiles, *clipboardButton;
@property (nonatomic) NSTextField *hmacKey, *hmacLabel;
@property (nonatomic) NSView *inputArea, *hmacRow;
@end

@implementation NppDigestWindow

+ (instancetype)shared {
    static NppDigestWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppDigestWindow alloc] init]; });
    return one;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    NSTextView *input, *result;
    self.inputArea = TextArea(YES, self, 110, &input);
    NSScrollView *resultArea = TextArea(NO, nil, 90, &result);
    self.input = input; self.result = result;
    self.chooseFiles = Button(@"Choose files to generate SHA-256...", self, @selector(choose:));
    self.eachLine = Checkbox(@"Treat each line as a separate string", self, @selector(refresh));
    self.hmacLabel = Label(@"HMAC key (optional):");
    self.hmacKey = Field(@"", 220, self);
    self.hmacRow = Row(@[self.hmacLabel, self.hmacKey]);
    self.clipboardButton = Button(@"Copy to Clipboard", self, @selector(copyResult:));
    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    NSStackView *buttons = Row(@[Spring(), self.clipboardButton, close]);
    _panel = PanelHolding(@[self.chooseFiles, self.inputArea, self.eachLine, self.hmacRow, resultArea, buttons],
                          @"Generate SHA-256 digest", @"NppDigestWindow");
    return _panel;
}

- (void)showForDigest:(NppDigest)digest fromFiles:(BOOL)fromFiles {
    NSPanel *panel = self.panel;
    self.digest = digest;
    self.fromFiles = fromFiles;
    NSString *name = [EditorController nameOfDigest:digest];
    self.chooseFiles.hidden = !fromFiles;
    self.inputArea.hidden = self.eachLine.hidden = fromFiles;
    // HMAC is defined here over the digests CommonCrypto computes it for, and is of a text, not of files.
    BOOL keyed = !fromFiles && [NppCrypto hmacOfData:[NSData data] key:[NSData data] digest:name] != nil;
    self.hmacRow.hidden = !keyed;
    if (fromFiles) self.result.string = @"";
    Present(panel);
    // After the window's own texts are translated: these two name the digest, which the translator's sentence is made to do.
    panel.title = Naming(fromFiles ? @"Generate SHA-256 digest from files" : @"Generate SHA-256 digest", name);
    self.chooseFiles.title = Naming(@"Choose files to generate SHA-256...", name);
    if (!fromFiles) { [self refresh]; [panel makeFirstResponder:self.input]; }
}

- (void)textDidChange:(NSNotification *)note { [self refresh]; }
- (void)controlTextDidChange:(NSNotification *)note { [self refresh]; }

- (void)refresh {
    if (self.fromFiles) return;
    NSString *text = self.input.string ?: @"";
    NSString *key = self.hmacRow.hidden ? @"" : self.hmacKey.stringValue;
    if (!text.length) { self.result.string = @""; return; }
    if (!key.length) {
        self.result.string = [EditorController hashOfText:text eachLine:self.eachLine.state == NSControlStateValueOn digest:self.digest] ?: @"";
        return;
    }
    NSString *name = [EditorController nameOfDigest:self.digest];
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSString *(^keyed)(NSString *) = ^NSString *(NSString *piece) {
        return piece.length ? [NppCrypto hexOfData:[NppCrypto hmacOfData:[piece dataUsingEncoding:NSUTF8StringEncoding] key:keyData digest:name]] : @"";
    };
    if (self.eachLine.state != NSControlStateValueOn) { self.result.string = keyed(text); return; }
    NSString *plain = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if ([plain hasSuffix:@"\n"]) plain = [plain substringToIndex:plain.length - 1];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [plain componentsSeparatedByString:@"\n"]) [lines addObject:keyed(line)];
    self.result.string = [lines componentsJoinedByString:@"\n"];
}

- (void)choose:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    if ([open runModal] != NSModalResponseOK) return;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in open.URLs) [paths addObject:url.path];
    [self digestFiles:paths];
}

- (void)digestFiles:(NSArray<NSString *> *)paths {
    // As upstream writes them: the digest, two spaces, and the file's name - what md5sum and shasum check against.
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
        if (!data) continue;
        [lines addObject:[NSString stringWithFormat:@"%@  %@", [EditorController hashOfData:data digest:self.digest], path.lastPathComponent]];
    }
    NSString *already = self.result.string;
    NSString *more = [lines componentsJoinedByString:@"\n"];
    self.result.string = already.length && more.length ? [NSString stringWithFormat:@"%@\n%@", already, more] : (more.length ? more : already);
}

- (void)copyResult:(id)sender { CopyText(self.result.string); }
- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end

#pragma mark - Password hashes

@interface NppPasswordHashWindow () <NSTextViewDelegate, NSTextFieldDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NppPasswordHash kind;
@property (nonatomic) BOOL fromFiles;
@property (nonatomic) NSTextView *input, *result;
@property (nonatomic) NSButton *eachLine, *chooseFiles, *clipboardButton, *bareKey, *verifyButton;
@property (nonatomic) NSTextField *salt, *toVerify, *verdict, *problem;
@property (nonatomic) NSDictionary<NSString *, NSControl *> *fields;
@property (nonatomic) NSDictionary<NSString *, NSArray<NSView *> *> *rowsByField;
@property (nonatomic) NSGridView *grid;
@property (nonatomic) NSView *inputArea;
@property (nonatomic) NSProgressIndicator *spinner;
@property (nonatomic) NSUInteger generation;
@property (nonatomic, copy) NSArray<NSString *> *files;
@end

// Which rows each kind shows, in the order they stand in the window.
static NSArray<NSString *> *FieldsOfKind(NppPasswordHash kind) {
    switch (kind) {
        case NppPasswordHashBcrypt: return @[@"bcryptCost", @"bcryptVersion"];
        case NppPasswordHashScrypt: return @[@"scryptLogN", @"scryptR", @"scryptP", @"keyLength"];
        case NppPasswordHashArgon2: return @[@"argon2Variant", @"argon2Memory", @"argon2Passes", @"argon2Lanes", @"keyLength"];
        case NppPasswordHashPBKDF2: return @[@"pbkdf2Digest", @"pbkdf2Rounds", @"keyLength"];
    }
    return @[];
}

static NSString *NameOfKind(NppPasswordHash kind) {
    return @[@"bcrypt", @"scrypt", @"Argon2", @"PBKDF2"][(NSUInteger)kind];
}

@implementation NppPasswordHashWindow

+ (instancetype)shared {
    static NppPasswordHashWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppPasswordHashWindow alloc] init]; });
    return one;
}

+ (NSString *)defaultHashOf:(NSData *)password kind:(NppPasswordHash)kind {
    return [NppCrypto hashPassword:password salt:[NppCrypto randomBytes:[NppCrypto saltLengthForKind:kind]]
                          settings:[NppPasswordHashSettings defaultsForKind:kind]].encoded;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    // The settings first, since they are what such a hash has that a digest has not; below them the digests' window as it is.
    NppPasswordHashSettings *defaults = [[NppPasswordHashSettings alloc] init];
    NSMutableDictionary<NSString *, NSControl *> *fields = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSArray<NSView *> *> *rowsByField = [NSMutableDictionary dictionary];
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    struct { NSString *name, *label; NSArray<NSString *> *choices; NSInteger value; } described[] = {
        {@"bcryptCost",    @"Cost (4-31):", nil, defaults.bcryptCost},
        {@"bcryptVersion", @"Version:", @[@"2b", @"2a", @"2y"], 0},
        {@"scryptLogN",    @"N, as a power of 2:", nil, defaults.scryptLogN},
        {@"scryptR",       @"Block size (r):", nil, defaults.scryptR},
        {@"scryptP",       @"Parallelism (p):", nil, defaults.scryptP},
        {@"argon2Variant", @"Variant:", @[@"Argon2id", @"Argon2i", @"Argon2d"], 0},
        {@"argon2Memory",  @"Memory (KiB):", nil, defaults.argon2Memory},
        {@"argon2Passes",  @"Iterations:", nil, defaults.argon2Passes},
        {@"argon2Lanes",   @"Parallelism:", nil, defaults.argon2Lanes},
        {@"pbkdf2Digest",  @"Digest:", @[@"SHA-256", @"SHA-512", @"SHA-1"], 0},
        {@"pbkdf2Rounds",  @"Iterations:", nil, defaults.pbkdf2Rounds},
        {@"keyLength",     @"Hash length (bytes):", nil, defaults.keyLength},
    };
    for (size_t i = 0; i < sizeof(described)/sizeof(described[0]); ++i) {
        NSControl *control = described[i].choices ? (NSControl *)Popup(described[i].choices, self, @selector(refresh))
                                                  : (NSControl *)Field([NSString stringWithFormat:@"%ld", (long)described[i].value], 90, self);
        if (!described[i].choices) [control.widthAnchor constraintEqualToConstant:90].active = YES;
        fields[described[i].name] = control;
        NSArray<NSView *> *row = @[Label(described[i].label), control];
        rowsByField[described[i].name] = row;
        [rows addObject:row];
    }
    self.fields = fields;
    self.rowsByField = rowsByField;
    self.salt = Field(@"", 300, self);
    self.salt.placeholderString = @"Empty: a random salt each time";
    [rows addObject:@[Label(@"Salt (hexadecimal):"), Row(@[self.salt, Button(@"Random", self, @selector(newSalt:))])]];

    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.rowSpacing = 8; grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    for (NSString *name in fields) [grid cellForView:fields[name]].xPlacement = NSGridCellPlacementLeading;
    self.grid = grid;

    NSTextView *input, *result;
    self.inputArea = TextArea(YES, self, 90, &input);
    NSScrollView *resultArea = TextArea(NO, nil, 90, &result);
    self.input = input; self.result = result;
    self.chooseFiles = Button(@"Choose files to generate SHA-256...", self, @selector(choose:));
    self.eachLine = Checkbox(@"Treat each line as a separate string", self, @selector(refresh));
    self.bareKey = Checkbox(@"Show the bare key in hexadecimal", self, @selector(refresh));
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.problem = Note();
    self.problem.textColor = [NSColor systemRedColor];

    self.toVerify = Field(@"", 300, self);
    self.verifyButton = Button(@"Verify", self, @selector(verify:));
    self.verdict = Note();
    self.clipboardButton = Button(@"Copy to Clipboard", self, @selector(copyResult:));
    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    _panel = PanelHolding(@[grid, self.chooseFiles, self.inputArea, self.eachLine, Row(@[self.bareKey, Spring(), self.spinner]),
                            self.problem, resultArea,
                            Row(@[Label(@"Hash to check the password against:"), self.toVerify, self.verifyButton]), self.verdict,
                            Row(@[Spring(), self.clipboardButton, close])],
                          @"Generate SHA-256 digest", @"NppPasswordHashWindow");
    return _panel;
}

- (void)showForKind:(NppPasswordHash)kind fromFiles:(BOOL)fromFiles {
    NSPanel *panel = self.panel;
    self.kind = kind;
    self.fromFiles = fromFiles;
    self.files = @[];
    NSArray<NSString *> *shown = FieldsOfKind(kind);
    for (NSString *name in self.rowsByField)
        [self.grid cellForView:self.rowsByField[name].firstObject].row.hidden = ![shown containsObject:name];
    self.chooseFiles.hidden = !fromFiles;
    self.inputArea.hidden = self.eachLine.hidden = fromFiles;
    self.verdict.stringValue = @"";
    if (fromFiles) self.result.string = @"";
    Present(panel);
    panel.title = Naming(fromFiles ? @"Generate SHA-256 digest from files" : @"Generate SHA-256 digest", NameOfKind(kind));
    self.chooseFiles.title = Naming(@"Choose files to generate SHA-256...", NameOfKind(kind));
    // The rows differ from kind to kind, and so does the height the window needs.
    [panel.contentView layoutSubtreeIfNeeded];
    NSSize least = [panel.contentView fittingSize];
    panel.contentMinSize = least;
    [panel setContentSize:NSMakeSize(MAX(NSWidth(panel.contentView.frame), least.width), least.height)];
    if (!fromFiles) { [self refresh]; [panel makeFirstResponder:self.input]; }
}

- (NSArray<NSString *> *)visibleFieldNames { return FieldsOfKind(self.kind); }

- (NppPasswordHashSettings *)settings {
    NppPasswordHashSettings *s = [[NppPasswordHashSettings alloc] init];
    s.kind = self.kind;
    NSInteger (^number)(NSString *) = ^NSInteger(NSString *name) { return [(NSTextField *)self.fields[name] integerValue]; };
    NSString *(^choice)(NSString *) = ^NSString *(NSString *name) { return [(NSPopUpButton *)self.fields[name] titleOfSelectedItem]; };
    s.bcryptCost = number(@"bcryptCost"); s.bcryptVersion = choice(@"bcryptVersion");
    s.scryptLogN = number(@"scryptLogN"); s.scryptR = number(@"scryptR"); s.scryptP = number(@"scryptP");
    NSString *variant = choice(@"argon2Variant");
    s.argon2Variant = [variant isEqualToString:@"Argon2i"] ? NppArgon2i : [variant isEqualToString:@"Argon2d"] ? NppArgon2d : NppArgon2id;
    s.argon2Memory = number(@"argon2Memory"); s.argon2Passes = number(@"argon2Passes"); s.argon2Lanes = number(@"argon2Lanes");
    s.pbkdf2Digest = choice(@"pbkdf2Digest"); s.pbkdf2Rounds = number(@"pbkdf2Rounds");
    s.keyLength = number(@"keyLength");
    return s;
}

/// What stands in the way of a hash, translated; nil when nothing does.
- (NSString *)whatIsWrong {
    NppPasswordHashSettings *settings = [self settings];
    NSString *wrong = [settings problem];
    if (wrong) return NppL(wrong);
    if (!self.salt.stringValue.length) return nil;
    NSData *salt = [NppCrypto dataFromHex:self.salt.stringValue];
    if (!salt) return NppL(@"The salt is not valid hexadecimal.");
    if (settings.kind == NppPasswordHashBcrypt && salt.length != 16) return NppL(@"bcrypt takes a salt of exactly 16 bytes.");
    if (settings.kind == NppPasswordHashArgon2 && salt.length < 8) return NppL(@"Argon2 takes a salt of at least 8 bytes.");
    return nil;
}

- (void)newSalt:(id)sender {
    self.salt.stringValue = [NppCrypto hexOfData:[NppCrypto randomBytes:[NppCrypto saltLengthForKind:self.kind]]];
    [self refresh];
}

- (void)textDidChange:(NSNotification *)note { [self refresh]; }
- (void)controlTextDidChange:(NSNotification *)note { if (note.object != self.toVerify) [self refresh]; }

/// What is to be hashed, as the digests' window would take it: the text, or its lines, or the files' contents.
- (NSArray<NSData *> *)pieces {
    if (self.fromFiles) {
        NSMutableArray<NSData *> *contents = [NSMutableArray array];
        for (NSString *path in self.files) [contents addObject:[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL] ?: [NSData data]];
        return contents;
    }
    NSString *text = self.input.string ?: @"";
    if (!text.length) return @[];
    if (self.eachLine.state != NSControlStateValueOn) return @[[text dataUsingEncoding:NSUTF8StringEncoding]];
    NSString *plain = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if ([plain hasSuffix:@"\n"]) plain = [plain substringToIndex:plain.length - 1];
    NSMutableArray<NSData *> *lines = [NSMutableArray array];
    for (NSString *line in [plain componentsSeparatedByString:@"\n"]) [lines addObject:[line dataUsingEncoding:NSUTF8StringEncoding]];
    return lines;
}

/// The work itself, fit to run anywhere: nothing of the window is touched. `stillWanted` is asked between
/// pieces, so that a result nobody is waiting for any more is not worked out to the end.
static NSString *ResultFor(NSArray<NSData *> *pieces, NSArray<NSString *> *names, NSData *salt, NppPasswordHashSettings *settings,
                           BOOL bareKey, BOOL emptyStaysEmpty, BOOL (^stillWanted)(void)) {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i < pieces.count; ++i) {
        if (!stillWanted()) return nil;
        NSString *line = @"";
        if (pieces[i].length || !emptyStaysEmpty) {
            NSData *itsSalt = salt ?: [NppCrypto randomBytes:[NppCrypto saltLengthForKind:settings.kind]];
            NppPasswordHashResult *hash = [NppCrypto hashPassword:pieces[i] salt:itsSalt settings:settings];
            if (!hash) return nil;
            line = bareKey ? [NppCrypto hexOfData:hash.key] : hash.encoded;
        }
        [lines addObject:names ? [NSString stringWithFormat:@"%@  %@", line, names[i]] : line];
    }
    return [lines componentsJoinedByString:@"\n"];
}

/// Everything the work needs, read from the controls; nil (and the reason shown) when there is something wrong with them.
- (NSString *(^)(BOOL (^)(void)))work {
    NSString *wrong = [self whatIsWrong];
    self.problem.stringValue = wrong ?: @"";
    NSArray<NSData *> *pieces = [self pieces];
    if (!wrong && self.kind == NppPasswordHashBcrypt) {
        for (NSData *piece in pieces) if (piece.length > 72) self.problem.stringValue = NppL(@"bcrypt reads only the first 72 bytes.");
    }
    if (wrong) return nil;
    NSMutableArray<NSString *> *names = nil;
    if (self.fromFiles) {
        names = [NSMutableArray array];
        for (NSString *path in self.files) [names addObject:path.lastPathComponent];
    }
    NSData *salt = self.salt.stringValue.length ? [NppCrypto dataFromHex:self.salt.stringValue] : nil;
    NppPasswordHashSettings *settings = [self settings];
    BOOL bareKey = self.bareKey.state == NSControlStateValueOn, perLine = !self.fromFiles && self.eachLine.state == NSControlStateValueOn;
    return ^NSString *(BOOL (^stillWanted)(void)) { return ResultFor(pieces, names, salt, settings, bareKey, perLine, stillWanted); };
}

- (void)show:(NSString *)result {
    self.result.string = result ?: @"";
    if (!result && !self.problem.stringValue.length) self.problem.stringValue = NppL(@"The hash could not be generated with these settings.");
}

- (void)refreshAndWait {
    ++self.generation;
    [self.spinner stopAnimation:nil];
    NSString *(^work)(BOOL (^)(void)) = [self work];
    if (!work) { self.result.string = @""; return; }
    [self show:work(^BOOL { return YES; })];
}

// A strong setting is meant to take a good part of a second, and typing is not to wait for it:
// the work is done elsewhere, and only the last thing asked for is shown.
- (void)refresh {
    NSUInteger mine = ++self.generation;
    NSString *(^work)(BOOL (^)(void)) = [self work];
    if (!work) { self.result.string = @""; [self.spinner stopAnimation:nil]; return; }
    [self.spinner startAnimation:nil];
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *result = work(^BOOL { return weakSelf.generation == mine; });
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.generation != mine) return;
            [weakSelf.spinner stopAnimation:nil];
            [weakSelf show:result];
        });
    });
}

- (void)choose:(id)sender {
    NSOpenPanel *open = [NSOpenPanel openPanel];
    open.allowsMultipleSelection = YES;
    if ([open runModal] != NSModalResponseOK) return;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *url in open.URLs) [paths addObject:url.path];
    self.files = [self.files arrayByAddingObjectsFromArray:paths];
    [self refresh];
}

- (void)hashFilesAndWait:(NSArray<NSString *> *)paths {
    self.files = [self.files ?: @[] arrayByAddingObjectsFromArray:paths];
    [self refreshAndWait];
}

- (void)showVerdict:(NSNumber *)matches {
    self.verdict.textColor = matches.boolValue ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    self.verdict.stringValue = !matches ? NppL(@"This is not a bcrypt, scrypt, Argon2 or PBKDF2 hash.")
                             : matches.boolValue ? NppL(@"The password matches the hash.") : NppL(@"The password does not match the hash.");
}

- (void)verifyAndWait {
    [self showVerdict:[NppCrypto password:[self.input.string dataUsingEncoding:NSUTF8StringEncoding] matches:self.toVerify.stringValue]];
}

- (void)verify:(id)sender {
    NSData *password = [self.input.string dataUsingEncoding:NSUTF8StringEncoding];
    NSString *encoded = self.toVerify.stringValue;
    self.verifyButton.enabled = NO;
    [self.spinner startAnimation:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSNumber *matches = [NppCrypto password:password matches:encoded];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.spinner stopAnimation:nil];
            self.verifyButton.enabled = YES;
            [self showVerdict:matches];
        });
    });
}

- (void)copyResult:(id)sender { CopyText(self.result.string); }
- (void)close:(id)sender { ++self.generation; [self.panel orderOut:nil]; }

@end

#pragma mark - Base64, Base58, Base32

@interface NppBaseWindow () <NSTextViewDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NppBaseEncoding plain;
@property (nonatomic) NSButton *variant;
@property (nonatomic) NSSegmentedControl *direction;
@property (nonatomic) NSButton *inputIsText, *inputIsHex;
@property (nonatomic) NSTextView *input, *output, *outputBytes;
@property (nonatomic) NSTextField *problem, *outputLabel, *bytesLabel, *inputKindLabel;
@property (nonatomic) NSView *kindRow, *bytesArea, *bytesHeader;
@end

@implementation NppBaseWindow

+ (instancetype)shared {
    static NppBaseWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppBaseWindow alloc] init]; });
    return one;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    self.variant = Checkbox(@"Base64 (URL-safe)", self, @selector(refresh));
    self.direction = [NSSegmentedControl segmentedControlWithLabels:@[@"Encode", @"Decode"] trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self action:@selector(refresh)];
    self.direction.translatesAutoresizingMaskIntoConstraints = NO;
    self.direction.selectedSegment = 0;
    self.inputKindLabel = Label(@"The input is:");
    self.inputIsText = [NSButton radioButtonWithTitle:@"Text" target:self action:@selector(inputKind:)];
    self.inputIsHex = [NSButton radioButtonWithTitle:@"Bytes in hexadecimal" target:self action:@selector(inputKind:)];
    for (NSButton *radio in @[self.inputIsText, self.inputIsHex]) {
        radio.translatesAutoresizingMaskIntoConstraints = NO;
        [radio setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    self.inputIsText.state = NSControlStateValueOn;
    self.kindRow = Row(@[self.inputKindLabel, self.inputIsText, self.inputIsHex]);

    NSTextView *input, *output, *bytes;
    NSScrollView *inputArea = TextArea(YES, self, 90, &input);
    NSScrollView *outputArea = TextArea(NO, nil, 70, &output);
    self.bytesArea = TextArea(NO, nil, 50, &bytes);
    self.input = input; self.output = output; self.outputBytes = bytes;
    self.outputLabel = Label(@"Result:");
    self.bytesLabel = Label(@"Bytes in hexadecimal:");
    self.problem = Note();
    self.problem.textColor = [NSColor systemRedColor];
    self.bytesHeader = Row(@[self.bytesLabel, Spring(), Button(@"Copy", self, @selector(copyBytes:))]);

    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    _panel = PanelHolding(@[Row(@[self.direction, Spring(), self.variant]), self.kindRow, Label(@"Input:"), inputArea, self.problem,
                            Row(@[self.outputLabel, Spring(), Button(@"Copy", self, @selector(copyOutput:))]), outputArea,
                            self.bytesHeader, self.bytesArea, Row(@[Spring(), close])],
                          @"Base64", @"NppBaseWindow");
    return _panel;
}

- (void)showForEncoding:(NppBaseEncoding)encoding {
    NSPanel *panel = self.panel;
    // The window is for the encoding its menu item named, and offers no other; a variant of it is a box to tick.
    NppBaseEncoding plain = encoding == NppBase64URL ? NppBase64 : encoding == NppBase58Check ? NppBase58 : encoding;
    if (plain != self.plain) self.variant.state = NSControlStateValueOff;
    if (encoding != plain) self.variant.state = NSControlStateValueOn;
    self.plain = plain;
    self.variant.hidden = plain == NppBase32;
    self.variant.title = plain == NppBase58 ? @"Base58Check" : @"Base64 (URL-safe)";
    Present(panel);
    panel.title = plain == NppBase64 ? @"Base64" : plain == NppBase58 ? @"Base58" : @"Base32";
    [self refresh];
    [panel makeFirstResponder:self.input];
}

- (NppBaseEncoding)encoding {
    BOOL ticked = !self.variant.hidden && self.variant.state == NSControlStateValueOn;
    if (self.plain == NppBase64) return ticked ? NppBase64URL : NppBase64;
    if (self.plain == NppBase58) return ticked ? NppBase58Check : NppBase58;
    return self.plain;
}

- (void)inputKind:(NSButton *)sender {
    // Two radio buttons in a stack are not a group of their own accord.
    self.inputIsText.state = sender == self.inputIsText ? NSControlStateValueOn : NSControlStateValueOff;
    self.inputIsHex.state = sender == self.inputIsHex ? NSControlStateValueOn : NSControlStateValueOff;
    [self refresh];
}

- (void)textDidChange:(NSNotification *)note { [self refresh]; }

- (void)refresh {
    NppBaseEncoding encoding = self.encoding;
    BOOL decoding = self.direction.selectedSegment == 1;
    NSString *name = @[@"Base64", @"Base64", @"Base58", @"Base58Check", @"Base32"][(NSUInteger)encoding];
    self.kindRow.hidden = decoding;
    self.bytesArea.hidden = self.bytesHeader.hidden = !decoding;
    self.outputLabel.stringValue = NppL(decoding ? @"Text:" : @"Result:");
    self.problem.stringValue = self.output.string = self.outputBytes.string = @"";
    NSString *text = self.input.string ?: @"";
    if (!text.length) return;

    if (!decoding) {
        NSData *data = self.inputIsHex.state == NSControlStateValueOn ? [NppCrypto dataFromHex:text] : [text dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) { self.problem.stringValue = NppL(@"The input is not bytes written in hexadecimal."); return; }
        self.output.string = [NppCrypto encode:data as:encoding];
        return;
    }
    NSData *data = [NppCrypto decode:text as:encoding];
    if (!data) { self.problem.stringValue = NppLMessage(@"The input is not valid $STR_REPLACE$.", name, 0); return; }
    self.outputBytes.string = [NppCrypto hexOfData:data];
    NSString *asText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (asText) self.output.string = asText;
    else self.problem.stringValue = NppL(@"The decoded bytes are not UTF-8 text; they are shown in hexadecimal only.");
}

- (void)copyOutput:(id)sender { CopyText(self.output.string); }
- (void)copyBytes:(id)sender { CopyText(self.outputBytes.string); }
- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end

#pragma mark - Passwords

static NSString *const kPasswordSettingsKey = @"NppPasswordGenerator";
static NSString *const kDefaultSymbols = @"!@#$%^&*()-_=+[]{};:,.<>?/~";

@interface NppPasswordWindow () <NSTextFieldDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NSTextField *length, *howMany, *symbols, *entropy;
@property (nonatomic) NSButton *upper, *lower, *digits, *useSymbols, *noLookalikes, *requireEach;
@property (nonatomic) NSTextView *result, *hashes;
@property (nonatomic) NSPopUpButton *hashKind;
@property (nonatomic) NSView *hashArea;
@property (nonatomic, copy) NSArray<NSString *> *hashKindNames;
@property (nonatomic) NSButton *hashesToClipboard;
@property (nonatomic) NSProgressIndicator *spinner;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) NSStepper *lengthStepper;
@end

@implementation NppPasswordWindow

+ (instancetype)shared {
    static NppPasswordWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppPasswordWindow alloc] init]; });
    return one;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPasswordSettingsKey] ?: @{};
    BOOL (^on)(NSString *, BOOL) = ^BOOL(NSString *key, BOOL otherwise) { return saved[key] ? [saved[key] boolValue] : otherwise; };

    self.length = Field([NSString stringWithFormat:@"%ld", (long)(saved[@"length"] ? [saved[@"length"] integerValue] : 20)], 60, self);
    self.lengthStepper = [[NSStepper alloc] init];
    self.lengthStepper.translatesAutoresizingMaskIntoConstraints = NO;
    self.lengthStepper.minValue = 1; self.lengthStepper.maxValue = 1024; self.lengthStepper.valueWraps = NO;
    self.lengthStepper.integerValue = self.length.integerValue;
    self.lengthStepper.target = self; self.lengthStepper.action = @selector(stepped:);
    self.howMany = Field([NSString stringWithFormat:@"%ld", (long)(saved[@"count"] ? [saved[@"count"] integerValue] : 1)], 60, self);

    for (NSTextField *number in @[self.length, self.howMany]) [number.widthAnchor constraintEqualToConstant:60].active = YES;
    self.upper = Checkbox(@"Uppercase letters (A-Z)", self, @selector(changed:));
    self.lower = Checkbox(@"Lowercase letters (a-z)", self, @selector(changed:));
    self.digits = Checkbox(@"Digits (0-9)", self, @selector(changed:));
    self.useSymbols = Checkbox(@"Symbols:", self, @selector(changed:));
    self.symbols = Field(saved[@"symbols"] ?: kDefaultSymbols, 260, self);
    self.noLookalikes = Checkbox(@"Leave out characters that look alike (O 0 o I l 1)", self, @selector(changed:));
    self.requireEach = Checkbox(@"At least one character of each kind", self, @selector(changed:));
    self.upper.state = on(@"upper", YES); self.lower.state = on(@"lower", YES); self.digits.state = on(@"digits", YES);
    self.useSymbols.state = on(@"useSymbols", YES); self.noLookalikes.state = on(@"noLookalikes", NO); self.requireEach.state = on(@"requireEach", YES);

    self.entropy = Label(@"");
    self.entropy.textColor = [NSColor secondaryLabelColor];
    NSTextView *result;
    NSScrollView *resultArea = TextArea(NO, nil, 80, &result);
    self.result = result;
    NSButton *generate = Button(@"Generate", self, @selector(generate:));
    generate.keyEquivalent = @"\r";
    // A hash of each password, of the kind chosen and with that kind's default settings: what one
    // stores where the password is to be checked. The four password hashes first, then the digests.
    NSMutableArray<NSString *> *kinds = [NSMutableArray arrayWithObjects:@"None", @"bcrypt", @"scrypt", @"Argon2", @"PBKDF2", nil];
    for (NSInteger d = 0; d < NppDigestCount; ++d) [kinds addObject:[EditorController nameOfDigest:(NppDigest)d]];
    self.hashKindNames = kinds;
    self.hashKind = Popup(kinds, self, @selector(hashKindChanged:));
    NSUInteger savedKind = [kinds indexOfObject:saved[@"hash"] ?: @"None"];
    [self.hashKind selectItemAtIndex:savedKind == NSNotFound ? 0 : (NSInteger)savedKind];
    NSTextView *hashes;
    self.hashArea = TextArea(NO, nil, 60, &hashes);
    self.hashes = hashes;
    self.hashesToClipboard = Button(@"Copy", self, @selector(copyHashes:));
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.hashArea.hidden = self.hashesToClipboard.hidden = self.hashKind.indexOfSelectedItem == 0;
    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";

    _panel = PanelHolding(@[Row(@[Label(@"Length:"), self.length, self.lengthStepper, Spring(), Label(@"Number of passwords:"), self.howMany]),
                            self.upper, self.lower, self.digits, Row(@[self.useSymbols, self.symbols]), self.noLookalikes, self.requireEach,
                            Row(@[generate, self.entropy]), resultArea,
                            Row(@[Label(@"Hash:"), self.hashKind, self.spinner, Spring(), self.hashesToClipboard]), self.hashArea,
                            Row(@[Spring(), Button(@"Copy to Clipboard", self, @selector(copyResult:)),
                                  Button(@"Insert into Document", self, @selector(insert:)), close])],
                          @"Password Generator", @"NppPasswordWindow");
    return _panel;
}

- (void)show {
    NSPanel *panel = self.panel;
    Present(panel);
    if (!self.result.string.length) [self generate:nil];
}

- (NSArray<NSString *> *)chosenSets {
    NSMutableArray<NSString *> *sets = [NSMutableArray array];
    if (self.upper.state == NSControlStateValueOn) [sets addObject:@"ABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    if (self.lower.state == NSControlStateValueOn) [sets addObject:@"abcdefghijklmnopqrstuvwxyz"];
    if (self.digits.state == NSControlStateValueOn) [sets addObject:@"0123456789"];
    if (self.useSymbols.state == NSControlStateValueOn) {
        // Spaces in the field are how one types the list, not characters meant for the password.
        [sets addObject:[self.symbols.stringValue stringByReplacingOccurrencesOfString:@" " withString:@""]];
    }
    if (self.noLookalikes.state != NSControlStateValueOn) return sets;
    NSMutableArray<NSString *> *plain = [NSMutableArray array];
    for (NSString *set in sets) [plain addObject:[NppCrypto withoutLookalikes:set]];
    return plain;
}

- (void)stepped:(id)sender { self.length.integerValue = self.lengthStepper.integerValue; [self generate:nil]; }
- (void)changed:(id)sender { [self generate:nil]; }
- (void)controlTextDidChange:(NSNotification *)note { [self generate:nil]; }

- (void)generate:(id)sender {
    [self makePasswords];
    [self hashPasswordsWaiting:NO];
}

- (void)makePasswords {
    NSInteger length = MIN(MAX(self.length.integerValue, 1), 1024), count = MIN(MAX(self.howMany.integerValue, 1), 1000);
    self.lengthStepper.integerValue = length;
    NSArray<NSString *> *sets = [self chosenSets];
    NSMutableArray<NSString *> *made = [NSMutableArray array];
    for (NSInteger i = 0; i < count; ++i) {
        NSString *one = [NppCrypto passwordOfLength:(NSUInteger)length fromSets:sets requireEach:self.requireEach.state == NSControlStateValueOn random:nil];
        if (one) [made addObject:one];
    }
    self.result.string = [made componentsJoinedByString:@"\n"];
    NSMutableSet<NSString *> *alphabet = [NSMutableSet set];
    for (NSString *set in sets)
        [set enumerateSubstringsInRange:NSMakeRange(0, set.length) options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *piece, NSRange, NSRange, BOOL *) { if (piece) [alphabet addObject:piece]; }];
    self.entropy.stringValue = made.count
        ? NppLMessage(@"Entropy: about $INT_REPLACE$ bits", nil, (NSInteger)floor([NppCrypto entropyOfLength:(NSUInteger)length alphabetSize:alphabet.count]))
        : NppL(@"Choose at least one kind of character.");
    [self rememberSettings];
}

- (void)rememberSettings {
    NSInteger length = MIN(MAX(self.length.integerValue, 1), 1024), count = MIN(MAX(self.howMany.integerValue, 1), 1000);
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"length": @(length), @"count": @(count), @"symbols": self.symbols.stringValue ?: @"",
        @"hash": self.hashKindNames[(NSUInteger)MAX(self.hashKind.indexOfSelectedItem, 0)],      // in English, whatever the pop-up shows
        @"upper": @(self.upper.state == NSControlStateValueOn), @"lower": @(self.lower.state == NSControlStateValueOn),
        @"digits": @(self.digits.state == NSControlStateValueOn), @"useSymbols": @(self.useSymbols.state == NSControlStateValueOn),
        @"noLookalikes": @(self.noLookalikes.state == NSControlStateValueOn), @"requireEach": @(self.requireEach.state == NSControlStateValueOn),
    } forKey:kPasswordSettingsKey];
}

- (void)hashKindChanged:(id)sender {
    BOOL none = self.hashKind.indexOfSelectedItem == 0;
    self.hashArea.hidden = self.hashesToClipboard.hidden = none;
    [self rememberSettings];
    [_panel.contentView layoutSubtreeIfNeeded];
    NSSize least = [_panel.contentView fittingSize];
    _panel.contentMinSize = least;
    if (NSHeight(_panel.contentView.frame) < least.height || none)
        [_panel setContentSize:NSMakeSize(MAX(NSWidth(_panel.contentView.frame), least.width), least.height)];
    [self hashPasswordsWaiting:NO];
}

/// The hash of one password, of the kind the pop-up names.
static NSString *HashOfKind(NSString *password, NSInteger chosen) {
    NSData *data = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (chosen >= 1 && chosen <= 4) return [NppPasswordHashWindow defaultHashOf:data kind:(NppPasswordHash)(chosen - 1)] ?: @"";
    return [EditorController hashOfData:data digest:(NppDigest)(chosen - 5)] ?: @"";
}

- (void)hashPasswordsWaiting:(BOOL)wait {
    NSUInteger mine = ++self.generation;
    NSInteger chosen = self.hashKind.indexOfSelectedItem;
    NSString *passwords = self.result.string;
    self.hashes.string = @"";
    if (chosen <= 0 || !passwords.length) { [self.spinner stopAnimation:nil]; return; }
    NSArray<NSString *> *each = [passwords componentsSeparatedByString:@"\n"];
    __weak __typeof__(self) weakSelf = self;
    NSString *(^work)(void) = ^NSString *{
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (NSString *password in each) {
            if (weakSelf.generation != mine) return nil;
            [lines addObject:HashOfKind(password, chosen)];
        }
        return [lines componentsJoinedByString:@"\n"];
    };
    if (wait) { self.hashes.string = work() ?: @""; return; }
    [self.spinner startAnimation:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *result = work();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.generation != mine) return;
            [weakSelf.spinner stopAnimation:nil];
            weakSelf.hashes.string = result ?: @"";
        });
    });
}

- (void)generateAndWait {
    [self makePasswords];
    [self hashPasswordsWaiting:YES];
}

- (void)copyHashes:(id)sender { CopyText(self.hashes.string); }
- (void)copyResult:(id)sender { CopyText(self.result.string); }

- (void)insert:(id)sender {
    if (!self.result.string.length || !self.insertIntoDocument) { NSBeep(); return; }
    self.insertIntoDocument(self.result.string);
}

- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end

#pragma mark - HTTP Request

static NSString *const kHttpRequestKey = @"NppHttpRequest";

@interface NppHttpWindow () <NSTextFieldDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NSPopUpButton *method, *contentType;
@property (nonatomic) NSTextField *address, *username, *password, *timeout, *status, *hint;
@property (nonatomic) NSSegmentedControl *section, *answerSection;
@property (nonatomic) NSTextView *parameters, *headers, *body, *answer;
@property (nonatomic) NSButton *followRedirects, *allowInvalidCertificates, *sendButton, *formatJSON;
@property (nonatomic) NSArray<NSView *> *sectionViews;
@property (nonatomic) NSProgressIndicator *spinner;
@property (nonatomic) NppHttpResponse *response;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL sending;
@end

@implementation NppHttpWindow

+ (instancetype)shared {
    static NppHttpWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppHttpWindow alloc] init]; });
    return one;
}

/// JSON with a line to each member and two spaces to each level, the members in the order they came and
/// every value spelt as it was - a server's 1.0 stays 1.0, its keys stay where it put them. Only the
/// white space between tokens is changed. nil when the text is not JSON.
static NSString *LaidOutJSON(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || ![NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:NULL]) return nil;
    NSMutableString *out = [NSMutableString stringWithCapacity:json.length * 2];
    NSUInteger n = json.length;
    __block NSUInteger depth = 0;
    void (^newline)(void) = ^{ [out appendString:@"\n"]; for (NSUInteger k = 0; k < depth; ++k) [out appendString:@"  "]; };
    for (NSUInteger i = 0; i < n; ++i) {
        unichar c = [json characterAtIndex:i];
        if (c == '"') {
            NSUInteger end = i + 1;
            while (end < n && [json characterAtIndex:end] != '"') end += [json characterAtIndex:end] == '\\' ? 2 : 1;
            [out appendString:[json substringWithRange:NSMakeRange(i, MIN(end + 1, n) - i)]];
            i = end;
        } else if (c == '{' || c == '[') {
            // An empty object or array stays on its line.
            NSUInteger next = i + 1;
            while (next < n && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[json characterAtIndex:next]]) ++next;
            if (next < n && [json characterAtIndex:next] == (c == '{' ? '}' : ']')) { [out appendFormat:@"%C%C", c, [json characterAtIndex:next]]; i = next; continue; }
            [out appendFormat:@"%C", c]; ++depth; newline();
        } else if (c == '}' || c == ']') {
            if (depth) --depth;
            newline(); [out appendFormat:@"%C", c];
        } else if (c == ',') { [out appendString:@","]; newline(); }
        else if (c == ':') [out appendString:@": "];
        else if (c != ' ' && c != '\t' && c != '\n' && c != '\r') [out appendFormat:@"%C", c];
    }
    return out;
}

static NSSegmentedControl *Segments(NSArray<NSString *> *labels, id target, SEL action) {
    NSSegmentedControl *segments = [NSSegmentedControl segmentedControlWithLabels:labels trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                           target:target action:action];
    segments.translatesAutoresizingMaskIntoConstraints = NO;
    segments.segmentDistribution = NSSegmentDistributionFit;
    segments.selectedSegment = 0;
    [segments setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return segments;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    self.method = Popup(@[@"GET", @"POST", @"PUT", @"PATCH", @"DELETE", @"HEAD", @"OPTIONS"], nil, NULL);
    self.address = Field(@"", 380, self);
    self.address.placeholderString = @"https://example.com/path";
    self.sendButton = Button(@"Send", self, @selector(send:));
    self.sendButton.keyEquivalent = @"\r";
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;

    self.section = Segments(@[@"Parameters", @"Headers", @"Body", @"Options"], self, @selector(sectionChanged:));
    self.hint = Note();
    self.hint.textColor = [NSColor secondaryLabelColor];
    NSTextView *parameters, *headers, *body, *answer;
    NSScrollView *parametersArea = TextArea(YES, nil, 110, &parameters), *headersArea = TextArea(YES, nil, 110, &headers);
    NSScrollView *bodyArea = TextArea(YES, nil, 80, &body);
    self.parameters = parameters; self.headers = headers; self.body = body;

    self.contentType = Popup(@[@"None", @"application/json", @"application/x-www-form-urlencoded", @"text/plain", @"application/xml"], nil, NULL);
    NSStackView *bodySection = [NSStackView stackViewWithViews:@[bodyArea, Row(@[Label(@"Content type:"), self.contentType, Spring()])]];
    bodySection.orientation = NSUserInterfaceLayoutOrientationVertical;
    bodySection.alignment = NSLayoutAttributeLeading;
    bodySection.translatesAutoresizingMaskIntoConstraints = NO;
    [bodyArea.widthAnchor constraintEqualToAnchor:bodySection.widthAnchor].active = YES;

    self.username = Field(@"", 200, nil);
    self.password = [[NSSecureTextField alloc] init];
    self.password.translatesAutoresizingMaskIntoConstraints = NO;
    [self.password.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    self.timeout = Field(@"30", 0, nil);
    [self.timeout.widthAnchor constraintEqualToConstant:60].active = YES;
    self.followRedirects = Checkbox(@"Follow redirects", nil, NULL);
    self.followRedirects.state = NSControlStateValueOn;
    self.allowInvalidCertificates = Checkbox(@"Allow invalid certificates", nil, NULL);
    NSGridView *options = [NSGridView gridViewWithViews:@[@[Label(@"User name:"), self.username],
                                                          @[Label(@"Password:"), self.password],
                                                          @[Label(@"Timeout (seconds):"), self.timeout],
                                                          @[[[NSView alloc] init], self.followRedirects],
                                                          @[[[NSView alloc] init], self.allowInvalidCertificates]]];
    options.translatesAutoresizingMaskIntoConstraints = NO;
    options.rowSpacing = 8; options.columnSpacing = 8;
    options.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [options columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [options columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    NSStackView *optionsSection = Row(@[options, Spring()]);
    optionsSection.alignment = NSLayoutAttributeTop;
    self.sectionViews = @[parametersArea, headersArea, bodySection, optionsSection];

    self.status = Note();
    self.status.selectable = YES;
    self.answerSection = Segments(@[@"Body", @"Headers"], self, @selector(answerSectionChanged:));
    self.formatJSON = Checkbox(@"Format JSON", self, @selector(answerSectionChanged:));
    self.formatJSON.state = NSControlStateValueOn;
    NSScrollView *answerArea = TextArea(NO, nil, 160, &answer);
    self.answer = answer;

    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    _panel = PanelHolding(@[Row(@[self.method, self.address, self.sendButton, self.spinner]),
                            self.section, self.hint, parametersArea, headersArea, bodySection, optionsSection,
                            self.status, Row(@[self.answerSection, self.formatJSON, Spring(), Button(@"Copy", self, @selector(copyAnswer:))]), answerArea,
                            Row(@[Button(@"Paste curl Command", self, @selector(pasteCurlCommand:)), Button(@"Copy as curl", self, @selector(copyAsCurl:)),
                                  Spring(), Button(@"Open in New Document", self, @selector(openAnswer:)), close])],
                          @"HTTP Request", @"NppHttpWindow");
    [self.address setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    // The request as it was left the last time, the password excepted.
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kHttpRequestKey];
    if (saved) {
        [self.method selectItemWithTitle:saved[@"method"] ?: @"GET"];
        if (self.method.indexOfSelectedItem < 0) [self.method selectItemAtIndex:0];
        self.address.stringValue = saved[@"address"] ?: @"";
        self.parameters.string = saved[@"parameters"] ?: @""; self.headers.string = saved[@"headers"] ?: @""; self.body.string = saved[@"body"] ?: @"";
        self.username.stringValue = saved[@"username"] ?: @"";
        self.timeout.stringValue = saved[@"timeout"] ?: @"30";
        self.followRedirects.state = saved[@"followRedirects"] ? [saved[@"followRedirects"] boolValue] : YES;
        self.allowInvalidCertificates.state = [saved[@"allowInvalidCertificates"] boolValue];
        NSInteger type = [saved[@"contentType"] integerValue];
        [self.contentType selectItemAtIndex:type >= 0 && type < self.contentType.numberOfItems ? type : 0];
    }
    [self sectionChanged:nil];
    return _panel;
}

- (void)show {
    NSPanel *panel = self.panel;
    Present(panel);
    [self sectionChanged:nil];
    [panel makeFirstResponder:self.address];
}

- (void)sectionChanged:(id)sender {
    NSInteger chosen = self.section.selectedSegment;
    for (NSUInteger i = 0; i < self.sectionViews.count; ++i) self.sectionViews[i].hidden = (NSInteger)i != chosen;
    self.hint.stringValue = chosen == 0 ? NppL(@"One to a line: name=value. They are added to the address, encoded.")
                          : chosen == 1 ? NppL(@"One to a line: Name: value")
                          : chosen == 2 ? NppL(@"Sent as it is written, in UTF-8.") : @"";
    self.hint.hidden = chosen == 3;
}

#pragma mark The request

- (NppHttpRequest *)request {
    NppHttpRequest *request = [[NppHttpRequest alloc] init];
    // The method is the item's title: the pop-up's titles are not translated, and a pasted
    // curl command can add a method the list does not have (PROPFIND, MKCOL...).
    request.method = self.method.titleOfSelectedItem.length ? self.method.titleOfSelectedItem : @"GET";
    request.address = self.address.stringValue;
    request.parameters = [NppHttpPair pairsFromText:self.parameters.string separator:@"="];
    NSMutableArray<NppHttpPair *> *headers = [[NppHttpPair pairsFromText:self.headers.string separator:@":"] mutableCopy];
    NSString *body = self.body.string;
    if (body.length) {
        request.body = [body dataUsingEncoding:NSUTF8StringEncoding];
        // The pop-up's content type, unless the headers name one themselves.
        BOOL named = NO;
        for (NppHttpPair *header in headers) if ([header.name caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) named = YES;
        NSArray<NSString *> *types = @[@"", @"application/json", @"application/x-www-form-urlencoded", @"text/plain", @"application/xml"];
        NSString *type = types[(NSUInteger)MAX(self.contentType.indexOfSelectedItem, 0)];
        if (!named && type.length) [headers addObject:[NppHttpPair pairWithName:@"Content-Type" value:type]];
    }
    request.headers = headers;
    request.username = self.username.stringValue; request.password = self.password.stringValue;
    request.followRedirects = self.followRedirects.state == NSControlStateValueOn;
    request.allowInvalidCertificates = self.allowInvalidCertificates.state == NSControlStateValueOn;
    request.timeout = MAX(0, self.timeout.doubleValue);
    return request;
}

- (void)showRequest:(NppHttpRequest *)request {
    (void)self.panel;
    [self.method selectItemWithTitle:request.method.uppercaseString];
    if (self.method.indexOfSelectedItem < 0) { [self.method addItemWithTitle:request.method.uppercaseString]; [self.method selectItemWithTitle:request.method.uppercaseString]; }
    self.address.stringValue = request.address ?: @"";
    self.parameters.string = [NppHttpPair textFromPairs:request.parameters separator:@"="];
    self.headers.string = [NppHttpPair textFromPairs:request.headers separator:@":"];
    self.body.string = request.body ? ([[NSString alloc] initWithData:request.body encoding:NSUTF8StringEncoding] ?: @"") : @"";
    [self.contentType selectItemAtIndex:0];
    self.username.stringValue = request.username ?: @""; self.password.stringValue = request.password ?: @"";
    self.followRedirects.state = request.followRedirects; self.allowInvalidCertificates.state = request.allowInvalidCertificates;
    self.timeout.stringValue = [NSString stringWithFormat:@"%ld", (long)request.timeout];
}

- (void)remember {
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"method": [self request].method, @"address": self.address.stringValue ?: @"", @"parameters": self.parameters.string ?: @"",
        @"headers": self.headers.string ?: @"", @"body": self.body.string ?: @"", @"username": self.username.stringValue ?: @"",
        @"timeout": self.timeout.stringValue ?: @"30", @"followRedirects": @(self.followRedirects.state == NSControlStateValueOn),
        @"allowInvalidCertificates": @(self.allowInvalidCertificates.state == NSControlStateValueOn),
        @"contentType": @(self.contentType.indexOfSelectedItem)} forKey:kHttpRequestKey];
}

#pragma mark Sending

- (void)showResponse:(NppHttpResponse *)response {
    self.response = response;
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (response.statusLine.length) [parts addObject:response.statusLine];
    if (response.error.length) [parts addObject:response.error];
    if (response.status) {
        [parts addObject:[NSString stringWithFormat:@"%.0f ms", response.elapsed * 1000]];
        [parts addObject:[NSByteCountFormatter stringFromByteCount:(long long)response.body.length countStyle:NSByteCountFormatterCountStyleFile]];
        if (response.redirects > 0 && response.finalAddress.length) [parts addObject:[@"→ " stringByAppendingString:response.finalAddress]];
    }
    self.status.stringValue = [parts componentsJoinedByString:@"  ·  "];
    self.status.textColor = response.error.length || response.status >= 400 ? [NSColor systemRedColor]
                          : response.status >= 300 ? [NSColor systemOrangeColor] : [NSColor systemGreenColor];
    [self answerSectionChanged:nil];
}

- (void)answerSectionChanged:(id)sender {
    NppHttpResponse *response = self.response;
    if (!response) { self.answer.string = @""; return; }
    if (self.answerSection.selectedSegment == 1) { self.answer.string = [response headerText]; return; }
    NSString *text = [response text];
    if (text && self.formatJSON.state == NSControlStateValueOn &&
        [[response valueOfHeader:@"Content-Type"].lowercaseString containsString:@"json"]) {
        // JSON mostly comes as one long line; laid out, it can be read. What is not JSON after all is shown as it came.
        text = LaidOutJSON(text) ?: text;
    }
    if (text) { self.answer.string = text; return; }
    // No text in any encoding it names: said so, and the beginning of it shown as bytes.
    NSData *head = [response.body subdataWithRange:NSMakeRange(0, MIN(response.body.length, (NSUInteger)2048))];
    self.answer.string = [NSString stringWithFormat:@"%@\n\n%@", NppLMessage(@"The answer is not text: $INT_REPLACE$ bytes.", nil, (NSInteger)response.body.length),
                          [NppCrypto hexOfData:head]];
}

- (void)sendAndWait {
    ++self.generation;
    [self remember];
    [self showResponse:[NppHttpClient send:[self request] cancelled:nil]];
}

- (void)setSending:(BOOL)sending {
    _sending = sending;
    self.sendButton.title = NppL(sending ? @"Cancel" : @"Send");
    if (sending) [self.spinner startAnimation:nil]; else [self.spinner stopAnimation:nil];
}

- (void)send:(id)sender {
    if (self.sending) { ++self.generation; self.sending = NO; return; }        // pressed again: given up
    NppHttpRequest *request = [self request];
    if (![request url]) {
        NppHttpResponse *none = [[NppHttpResponse alloc] init];
        none.error = NppL(@"The address is not an http or https address.");
        [self showResponse:none];
        NSBeep();
        return;
    }
    [self remember];
    NSUInteger mine = ++self.generation;
    self.sending = YES;
    self.status.stringValue = @"";
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NppHttpResponse *response = [NppHttpClient send:request cancelled:^BOOL { return weakSelf.generation != mine; }];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.generation != mine) return;
            weakSelf.sending = NO;
            [weakSelf showResponse:response];
        });
    });
}

#pragma mark curl, the clipboard, the editor

- (BOOL)pasteCurlCommand:(id)sender {
    NSString *command = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    NSString *why = nil;
    NppHttpRequest *request = [NppHttpRequest requestFromCurlCommand:command ?: @"" error:&why];
    if (!request) {
        self.status.textColor = [NSColor systemRedColor];
        self.status.stringValue = NppL(why ?: @"This is not a curl command.");
        NSBeep();
        return NO;
    }
    [self showRequest:request];
    self.status.stringValue = @"";
    return YES;
}

- (void)copyAsCurl:(id)sender { CopyText([[self request] curlCommand]); }
- (void)copyAnswer:(id)sender { CopyText(self.answer.string); }

- (void)openAnswer:(id)sender {
    // As it is shown: laid out when that is ticked.
    NSString *text = [self.response text] ? (self.answerSection.selectedSegment == 0 ? self.answer.string : [self.response text]) : nil;
    if (!text.length || !self.openInNewDocument) { NSBeep(); return; }
    self.openInNewDocument(text, [self.response valueOfHeader:@"Content-Type"] ?: @"");
}

- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end


#pragma mark - The Conversion Panel

// The Converter plugin's panel (conversionPanel.cpp): five rows for one
// value. The model - which texts a typed value spreads into the others -
// is EditorController (ConverterCommands), so it is tested apart from the
// controls.
@interface NppConverterWindow () <NSTextFieldDelegate>
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NSTextField *ascii, *dec, *hex, *bin, *oct;
@property (nonatomic) BOOL filling;   // the sync writes fields; their delegate must not re-enter
@end

@implementation NppConverterWindow

+ (instancetype)shared {
    static NppConverterWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppConverterWindow alloc] init]; });
    return one;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    NSMutableArray<NSView *> *rows = [NSMutableArray array];
    struct { NSString *label; NSString *key; } lines[] = {
        {@"Character:", @"ascii"}, {@"Decimal:", @"dec"}, {@"Hexadecimal:", @"hex"},
        {@"Binary:", @"bin"}, {@"Octal:", @"oct"},
    };
    for (size_t i = 0; i < sizeof(lines)/sizeof(lines[0]); ++i) {
        NSTextField *field = Field(@"", 220, self);
        [field setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        field.identifier = lines[i].key;
        NSTextField *label = Label(lines[i].label);
        [label.widthAnchor constraintGreaterThanOrEqualToConstant:96].active = YES;
        NSButton *copy = Button(@"Copy", self, @selector(copyRow:));
        NSButton *put = Button(@"Insert", self, @selector(insertRow:));
        copy.tag = put.tag = (NSInteger)i;
        [rows addObject:Row(@[label, field, copy, put])];
        switch (i) {
            case 0: _ascii = field; break;
            case 1: _dec = field; break;
            case 2: _hex = field; break;
            case 3: _bin = field; break;
            case 4: _oct = field; break;
        }
    }
    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    [rows addObject:Row(@[Spring(), close])];
    _panel = PanelHolding(rows, @"Conversion Panel", @"NppConverterWindow");
    return _panel;
}

- (void)show {
    NSPanel *panel = self.panel;
    Present(panel);
    [panel makeFirstResponder:self.dec];
}

- (NSTextField *)fieldAt:(NSInteger)index {
    NSTextField *fields[] = {self.ascii, self.dec, self.hex, self.bin, self.oct};
    return index >= 0 && index < 5 ? fields[index] : nil;
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (self.filling) return;
    [self syncFrom:note.object];
}

- (void)syncFrom:(NSTextField *)field {
    NSDictionary *values = [EditorController converterValues:field.stringValue
                                                   fromField:field.identifier];
    self.filling = YES;
    // The plugin paints a value it cannot read red; a readable one fills the rest.
    field.backgroundColor = values ? [NSColor textBackgroundColor]
                                   : [[NSColor systemRedColor] colorWithAlphaComponent:0.3];
    if (values) {
        for (NSTextField *other in @[self.ascii, self.dec, self.hex, self.bin, self.oct]) {
            other.backgroundColor = [NSColor textBackgroundColor];
            if (other != field) other.stringValue = values[other.identifier] ?: @"";
        }
    }
    self.filling = NO;
}

- (void)copyRow:(NSButton *)sender { CopyText([self fieldAt:sender.tag].stringValue); }

- (void)insertRow:(NSButton *)sender {
    NSString *text = [self fieldAt:sender.tag].stringValue;
    if (text.length && self.insert) self.insert(text);
}

- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end


#pragma mark - QR code

@interface NppQrWindow ()
@property (nonatomic) NSPanel *panel;
@property (nonatomic) NSImageView *imageView;
@property (nonatomic) NSTextField *caption;
@property (nonatomic, copy) NSString *text;
@end

@implementation NppQrWindow

+ (instancetype)shared {
    static NppQrWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppQrWindow alloc] init]; });
    return one;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    _imageView = [[NSImageView alloc] init];
    _imageView.translatesAutoresizingMaskIntoConstraints = NO;
    _imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [_imageView.widthAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
    [_imageView.heightAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
    _caption = Note();
    _caption.maximumNumberOfLines = 3;
    NSButton *close = Button(@"Close", self, @selector(close:));
    close.keyEquivalent = @"\033";
    _panel = PanelHolding(@[_imageView, _caption,
                            Row(@[Button(@"Copy Image", self, @selector(copyImage:)),
                                  Button(@"Save…", self, @selector(saveImage:)), Spring(), close])],
                          @"QR Code", @"NppQrWindow");
    return _panel;
}

- (void)showForText:(NSString *)text {
    NSPanel *panel = self.panel;
    self.text = text;
    self.imageView.image = [EditorController qrImageFromText:text side:520];
    self.caption.stringValue = text.length > 200 ? [[text substringToIndex:200] stringByAppendingString:@"…"] : text;
    Present(panel);
}

- (void)copyImage:(id)sender {
    if (!self.imageView.image) return;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[self.imageView.image]];
}

- (void)saveImage:(id)sender {
    if (!self.imageView.image) return;
    NSSavePanel *save = [NSSavePanel savePanel];
    save.nameFieldStringValue = @"qr-code.png";
    if ([save runModal] != NSModalResponseOK || !save.URL) return;
    CGImageRef cg = [self.imageView.image CGImageForProposedRect:NULL context:nil hints:nil];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToURL:save.URL atomically:YES];
}

- (void)close:(id)sender { [self.panel orderOut:nil]; }

@end
