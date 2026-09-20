#import "ApiCatalog.h"

@implementation NppApiOverload
@end

@implementation NppApiEntry
@end

/// One parsed file.
@interface NppApiLanguage : NSObject
@property (nonatomic) BOOL ignoreCase;
@property (nonatomic, strong) NSMutableArray<NppApiEntry *> *entries;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *environment;
@end

@implementation NppApiLanguage
@end

@interface ApiCatalog () <NSXMLParserDelegate>
/// Lower-cased language name -> the file it is in. Filled at startup; the file
/// itself is read only when that language is first asked about, because the
/// whole set is a couple of megabytes and a session touches one or two of them.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *paths;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppApiLanguage *> *loaded;

// parse state
@property (nonatomic, strong, nullable) NppApiLanguage *current;
@property (nonatomic, strong, nullable) NppApiEntry *currentEntry;
@property (nonatomic, strong, nullable) NppApiOverload *currentOverload;
@property (nonatomic, strong, nullable) NSMutableArray<NppApiOverload *> *currentOverloads;
@property (nonatomic, strong, nullable) NSMutableArray<NSString *> *currentParams;
@end

@implementation ApiCatalog

+ (instancetype)sharedCatalog {
    static ApiCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[ApiCatalog alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _paths = [NSMutableDictionary dictionary];
    _loaded = [NSMutableDictionary dictionary];

    NSString *dir = [[NSBundle mainBundle] pathForResource:@"APIs" ofType:nil];
    if (!dir) return self;
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
        NSString *base = file.stringByDeletingPathExtension.lowercaseString;
        _paths[base] = [dir stringByAppendingPathComponent:file];
    }
    return self;
}

- (NSArray<NSString *> *)languages {
    return [self.paths.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

- (NppApiLanguage *)languageNamed:(NSString *)language {
    NSString *key = language.lowercaseString ?: @"";
    NppApiLanguage *already = self.loaded[key];
    if (already) return already;

    NSString *path = self.paths[key];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;

    NppApiLanguage *lang = [[NppApiLanguage alloc] init];
    // Upstream's default is to ignore case unless the file says otherwise.
    lang.ignoreCase = YES;
    lang.entries = [NSMutableArray array];
    lang.environment = [@{@"start": @"(", @"stop": @")", @"param": @",", @"terminal": @";",
                          @"wordChars": @""} mutableCopy];
    self.current = lang;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    [parser parse];
    self.current = nil;

    self.loaded[key] = lang;
    return lang;
}

- (BOOL)ignoreCaseForLanguage:(NSString *)language {
    NppApiLanguage *lang = [self languageNamed:language];
    return lang ? lang.ignoreCase : YES;
}

- (NSArray<NppApiEntry *> *)entriesForLanguage:(NSString *)language {
    return [self languageNamed:language].entries ?: @[];
}

- (NSArray<NSString *> *)completionsForLanguage:(NSString *)language prefix:(NSString *)prefix {
    NppApiLanguage *lang = [self languageNamed:language];
    if (!lang || !prefix.length) return @[];

    NSStringCompareOptions options = NSAnchoredSearch |
        (lang.ignoreCase ? NSCaseInsensitiveSearch : 0);
    NSMutableArray *out = [NSMutableArray array];
    for (NppApiEntry *entry in lang.entries) {
        if (entry.name.length <= prefix.length) continue;
        if ([entry.name rangeOfString:prefix options:options].location == NSNotFound) continue;
        [out addObject:entry.name];
    }
    return out;
}

- (NSArray<NSString *> *)callTipsForLanguage:(NSString *)language function:(NSString *)name {
    NppApiLanguage *lang = [self languageNamed:language];
    if (!lang || !name.length) return @[];

    NSStringCompareOptions options = lang.ignoreCase ? NSCaseInsensitiveSearch : 0;
    NSMutableArray *tips = [NSMutableArray array];
    for (NppApiEntry *entry in lang.entries) {
        if (!entry.isFunction || !entry.overloads.count) continue;
        if ([entry.name compare:name options:options] != NSOrderedSame) continue;
        for (NppApiOverload *overload in entry.overloads) {
            // The shape upstream shows: "retVal name (p1, p2)", and the
            // description on a line of its own when there is one.
            NSMutableString *tip = [NSMutableString string];
            if (overload.returnValue.length) [tip appendFormat:@"%@ ", overload.returnValue];
            [tip appendFormat:@"%@ (%@)", entry.name,
             [overload.params componentsJoinedByString:@", "]];
            if (overload.descr.length) [tip appendFormat:@"\n%@", overload.descr];
            [tips addObject:tip];
        }
    }
    return tips;
}

- (NSDictionary<NSString *, NSString *> *)callTipEnvironmentForLanguage:(NSString *)language {
    return [[self languageNamed:language].environment copy];
}

- (NppApiEntry *)functionNamed:(NSString *)name inLanguage:(NSString *)language {
    NppApiLanguage *lang = [self languageNamed:language];
    if (!lang || !name.length) return nil;
    NSStringCompareOptions options = lang.ignoreCase ? NSCaseInsensitiveSearch : 0;
    for (NppApiEntry *entry in lang.entries) {
        if ([entry.name compare:name options:options] != NSOrderedSame) continue;
        return (entry.isFunction && entry.overloads.count) ? entry : nil;
    }
    return nil;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {
    if (!self.current) return;

    if ([element isEqualToString:@"Environment"]) {
        NSString *value = attrs[@"ignoreCase"];
        if (value) self.current.ignoreCase = ![value.lowercaseString isEqualToString:@"no"];
        // Only the first character counts, as FunctionCallTip reads them.
        NSDictionary *keys = @{@"startFunc": @"start", @"stopFunc": @"stop",
                               @"paramSeparator": @"param", @"terminal": @"terminal"};
        for (NSString *attr in keys) {
            if ([attrs[attr] length]) self.current.environment[keys[attr]] = [attrs[attr] substringToIndex:1];
        }
        if (attrs[@"additionalWordChar"]) self.current.environment[@"wordChars"] = attrs[@"additionalWordChar"];
        return;
    }
    if ([element isEqualToString:@"KeyWord"]) {
        NppApiEntry *entry = [[NppApiEntry alloc] init];
        entry.name = attrs[@"name"] ?: @"";
        entry.isFunction = [attrs[@"func"].lowercaseString isEqualToString:@"yes"];
        entry.overloads = @[];
        self.currentEntry = entry;
        self.currentOverloads = [NSMutableArray array];
        return;
    }
    if ([element isEqualToString:@"Overload"]) {
        NppApiOverload *overload = [[NppApiOverload alloc] init];
        overload.returnValue = attrs[@"retVal"] ?: @"";
        overload.descr = attrs[@"descr"];
        self.currentOverload = overload;
        self.currentParams = [NSMutableArray array];
        return;
    }
    if ([element isEqualToString:@"Param"] && self.currentParams) {
        NSString *name = attrs[@"name"];
        if (name.length) [self.currentParams addObject:name];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([element isEqualToString:@"Overload"]) {
        self.currentOverload.params = self.currentParams ?: @[];
        if (self.currentOverload) [self.currentOverloads addObject:self.currentOverload];
        self.currentOverload = nil;
        self.currentParams = nil;
        return;
    }
    if ([element isEqualToString:@"KeyWord"]) {
        if (self.currentEntry.name.length) {
            self.currentEntry.overloads = self.currentOverloads ?: @[];
            [self.current.entries addObject:self.currentEntry];
        }
        self.currentEntry = nil;
        self.currentOverloads = nil;
    }
}

@end
