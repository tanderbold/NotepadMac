#import "StyleCatalog.h"

@implementation NppStyle
@end

static NSString *gRequestedTheme = @"Default";
static NSString *gRequestedThemeFile = nil;
static NSString *gImportedThemesDirectory = nil;

@interface StyleCatalog () <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *loadedThemeName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NppStyle *> *> *byLexer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppStyle *> *globals;
@property (nonatomic, copy, nullable) NSString *currentLexer;
@property (nonatomic) BOOL inGlobals;
@property (nonatomic, strong) NSMutableArray<NppStyle *> *globalList;
@property (nonatomic, strong) NSMutableArray<NSString *> *lexerOrder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *lexerDescriptions;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSString *> *> *lexerExtensions;
@property (nonatomic, strong, nullable) NppStyle *currentStyle;
@property (nonatomic, strong, nullable) NSMutableString *currentText;
@end

@implementation StyleCatalog

static StyleCatalog *gShared = nil;

+ (instancetype)sharedCatalog {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gShared = [[StyleCatalog alloc] init]; });
    return gShared;
}

/// Imported themes are looked for here as well as in the bundle.
+ (void)setImportedThemesDirectory:(NSString *)dir { gImportedThemesDirectory = [dir copy]; }

+ (NSArray<NSString *> *)availableThemeNames {
    NSMutableArray *names = [NSMutableArray arrayWithObject:@"Default"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[[[NSBundle mainBundle] pathForResource:@"themes" ofType:nil] ?: @"",
                            gImportedThemesDirectory ?: @""]) {
        if (!dir.length) continue;
        for (NSString *file in [[fm contentsOfDirectoryAtPath:dir error:NULL]
                                sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
            NSString *name = file.stringByDeletingPathExtension;
            if (![names containsObject:name]) [names addObject:name];
        }
    }
    return names;
}

+ (NSString *)userPathForThemeNamed:(NSString *)name {
    if (!gImportedThemesDirectory.length) return nil;
    if (!name.length || [name isEqualToString:@"Default"]) {
        return [gImportedThemesDirectory.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"stylers.xml"];
    }
    return [gImportedThemesDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"xml"]];
}

+ (NSString *)pathForThemeNamed:(NSString *)name {
    // The user's own copy first, as Notepad++ reads the user's stylers.xml.
    NSString *user = [self userPathForThemeNamed:name];
    if (user && [[NSFileManager defaultManager] fileExistsAtPath:user]) return user;
    if (!name.length || [name isEqualToString:@"Default"]) {
        return [[NSBundle mainBundle] pathForResource:@"stylers.model" ofType:@"xml"];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in @[gImportedThemesDirectory ?: @"",
                            [[NSBundle mainBundle] pathForResource:@"themes" ofType:nil] ?: @""]) {
        if (!dir.length) continue;
        NSString *candidate = [dir stringByAppendingPathComponent:
                               [name stringByAppendingPathExtension:@"xml"]];
        if ([fm fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

+ (void)loadThemeFromFile:(NSString *)path named:(NSString *)name {
    gRequestedTheme = [name copy] ?: @"Default";
    gRequestedThemeFile = [path copy];
    [self sharedCatalog];
    gShared = [[StyleCatalog alloc] init];
    gRequestedThemeFile = nil;
}

+ (void)loadThemeNamed:(NSString *)name {
    gRequestedThemeFile = nil;
    gRequestedTheme = [name copy] ?: @"Default";
    [self sharedCatalog];                 // make sure the singleton exists
    gShared = [[StyleCatalog alloc] init];
}

- (NSString *)themeName { return self.loadedThemeName; }

/// "RRGGBB" -> NSColor. Notepad++ stores colours without a leading '#'.
static NSColor *ColorFromHex(NSString *hex) {
    if (hex.length != 6) return nil;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&v]) return nil;
    return [NSColor colorWithSRGBRed:((v >> 16) & 0xFF) / 255.0
                               green:((v >> 8) & 0xFF) / 255.0
                                blue:(v & 0xFF) / 255.0
                               alpha:1.0];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _byLexer = [NSMutableDictionary dictionary];
    _globals = [NSMutableDictionary dictionary];
    _globalList = [NSMutableArray array];
    _lexerOrder = [NSMutableArray array];
    _lexerDescriptions = [NSMutableDictionary dictionary];
    _lexerExtensions = [NSMutableDictionary dictionary];

    _loadedThemeName = gRequestedTheme ?: @"Default";
    NSString *path = gRequestedThemeFile ?: [StyleCatalog pathForThemeNamed:_loadedThemeName];
    if (!path) {                          // a theme was removed since it was chosen
        _loadedThemeName = @"Default";
        path = [StyleCatalog pathForThemeNamed:@"Default"];
    }
    if (path) {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[NSData dataWithContentsOfFile:path]];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"LexerType"]) {
        self.currentLexer = attrs[@"name"];
        if (self.currentLexer && !self.byLexer[self.currentLexer]) {
            self.byLexer[self.currentLexer] = [NSMutableArray array];
            [self.lexerOrder addObject:self.currentLexer];
            if (attrs[@"desc"]) self.lexerDescriptions[self.currentLexer] = attrs[@"desc"];
            NSMutableArray *exts = [NSMutableArray array];
            for (NSString *e in [attrs[@"ext"] ?: @"" componentsSeparatedByString:@" "]) {
                if (e.length) [exts addObject:e.lowercaseString];
            }
            self.lexerExtensions[self.currentLexer] = exts;
        }
        return;
    }
    if ([element isEqualToString:@"GlobalStyles"]) { self.inGlobals = YES; return; }

    BOOL isStyle = [element isEqualToString:@"WordsStyle"] || [element isEqualToString:@"WidgetStyle"];
    if (!isStyle) return;

    NSString *idStr = attrs[@"styleID"];
    if (!idStr.length) return;

    NppStyle *s = [[NppStyle alloc] init];
    s.styleID = idStr.intValue;
    s.foreground = ColorFromHex(attrs[@"fgColor"] ?: @"");
    s.background = ColorFromHex(attrs[@"bgColor"] ?: @"");
    s.fontStyle = (attrs[@"fontStyle"] ?: @"0").intValue;
    s.fontName = attrs[@"fontName"].length ? attrs[@"fontName"] : nil;
    s.fontSize = (attrs[@"fontSize"] ?: @"0").intValue;
    s.keywordClass = attrs[@"keywordClass"].length ? attrs[@"keywordClass"] : nil;
    s.name = attrs[@"name"];

    if (self.inGlobals) {
        if (s.name.length && !self.globals[s.name]) [self.globalList addObject:s];
        if (s.name.length) self.globals[s.name] = s;
    } else if (self.currentLexer) {
        [self.byLexer[self.currentLexer] addObject:s];
    }
    // The text inside a WordsStyle is the user's own keywords.
    self.currentStyle = s;
    self.currentText = [NSMutableString string];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    if (self.currentStyle) [self.currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([element isEqualToString:@"LexerType"]) self.currentLexer = nil;
    else if ([element isEqualToString:@"GlobalStyles"]) self.inGlobals = NO;
    else if (self.currentStyle && ([element isEqualToString:@"WordsStyle"] || [element isEqualToString:@"WidgetStyle"])) {
        NSString *text = [self.currentText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        self.currentStyle.userKeywords = text.length ? text : nil;
        self.currentStyle = nil;
        self.currentText = nil;
    }
}

- (NSArray<NppStyle *> *)orderedGlobalStyles { return self.globalList; }
- (NSArray<NSString *> *)lexerNames { return self.lexerOrder; }
- (NSString *)descriptionOfLexer:(NSString *)lexerName { return self.lexerDescriptions[lexerName]; }
- (NSArray<NSString *> *)userExtensionsForLexer:(NSString *)lexerName { return self.lexerExtensions[lexerName] ?: @[]; }

- (NSArray<NppStyle *> *)stylesForLexerName:(NSString *)lexerName {
    return self.byLexer[lexerName];
}

- (NSDictionary<NSString *, NppStyle *> *)globalStyles { return self.globals; }

@end
