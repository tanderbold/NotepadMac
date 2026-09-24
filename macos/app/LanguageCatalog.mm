#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#include "LangMap.h"
#include "CommandIDs.h"

@implementation NppLanguage
@end

@interface LanguageCatalog () <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray<NppLanguage *> *languages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppLanguage *> *byName;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppLanguage *> *byExtension;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NppLanguage *> *builtInByExtension;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, NppLanguage *> *builtInByName;
@property (nonatomic, strong, readwrite) NSArray<NppLanguage *> *userLanguages;
/// extension -> the user languages claiming it, in the order they were read.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NppLanguage *> *> *userByExtension;
// parse state
@property (nonatomic, strong, nullable) NppLanguage *current;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, NSString *> *currentKeywords;
@property (nonatomic, strong, nullable) NSNumber *currentKeywordIndex;
@property (nonatomic, strong, nullable) NSMutableString *currentText;
@end

@implementation LanguageCatalog

+ (instancetype)sharedCatalog {
    static LanguageCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[LanguageCatalog alloc] init]; });
    return shared;
}

/// Notepad++'s LANG_INDEX_* order (see MISC/Common/NppConstants.h).
NSNumber *NppKeywordSetIndex(NSString *attrName) {
    static NSDictionary<NSString *, NSNumber *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"instre1": @0, @"instre2": @1,
                @"type1": @2, @"type2": @3, @"type3": @4, @"type4": @5,
                @"type5": @6, @"type6": @7, @"type7": @8};
    });
    return map[attrName];
}

static NSString *LexerIDForLanguage(NSString *langName) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:kNppLangLexerCount];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            m[@(kNppLangLexers[i].langName)] = @(kNppLangLexers[i].lexerID);
        }
        map = m;
    });
    return map[langName] ?: @"null";
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _languages = [NSMutableArray array];
    _byName = [NSMutableDictionary dictionary];
    _byExtension = [NSMutableDictionary dictionary];

    NSString *path = [[NSBundle mainBundle] pathForResource:@"langs.model" ofType:@"xml"];
    _sourcePath = path ?: @"";
    if (path) {
        NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[NSData dataWithContentsOfFile:path]];
        parser.delegate = self;
        [parser parse];
    }
    return self;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"Language"]) {
        NppLanguage *lang = [[NppLanguage alloc] init];
        lang.name = attrs[@"name"] ?: @"";
        lang.lexerID = LexerIDForLanguage(lang.name);
        lang.commentLine = attrs[@"commentLine"];
        lang.commentStart = attrs[@"commentStart"];
        lang.commentEnd = attrs[@"commentEnd"];

        NSString *ext = attrs[@"ext"] ?: @"";
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *e in [ext componentsSeparatedByString:@" "]) {
            if (e.length) [exts addObject:e.lowercaseString];
        }
        lang.extensions = exts;

        self.current = lang;
        self.currentKeywords = [NSMutableDictionary dictionary];

    } else if ([element isEqualToString:@"Keywords"] && self.current) {
        self.currentKeywordIndex = NppKeywordSetIndex(attrs[@"name"] ?: @"");
        self.currentText = self.currentKeywordIndex ? [NSMutableString string] : nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentText appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {

    if ([element isEqualToString:@"Keywords"]) {
        if (self.currentKeywordIndex && self.currentText.length) {
            // Scintilla wants a single-space-separated list; the XML wraps lines.
            NSArray *words = [self.currentText componentsSeparatedByCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSMutableArray *clean = [NSMutableArray array];
            for (NSString *w in words) if (w.length) [clean addObject:w];
            if (clean.count) {
                self.currentKeywords[self.currentKeywordIndex] = [clean componentsJoinedByString:@" "];
            }
        }
        self.currentKeywordIndex = nil;
        self.currentText = nil;

    } else if ([element isEqualToString:@"Language"] && self.current) {
        self.current.keywordSets = self.currentKeywords ?: @{};
        [self.languages addObject:self.current];
        if (self.current.name.length) self.byName[self.current.name] = self.current;
        for (NSString *e in self.current.extensions) {
            // Where two languages claim the same extension, Notepad++ walks its
            // list from the end (Parameters.cpp, getLangFromExt), so the last
            // definition wins: .tex belongs to tex, not to latex.
            self.byExtension[e] = self.current;
        }
        self.current = nil;
        self.currentKeywords = nil;
    }
}

#pragma mark - Lookup

- (NSArray<NppLanguage *> *)allLanguages { return self.languages; }

- (void)registerUserLanguages:(NSArray<NppLanguage *> *)languages {
    if (!self.builtInByExtension) self.builtInByExtension = [self.byExtension copy];
    if (!self.builtInByName) self.builtInByName = [self.byName copy];
    for (NppLanguage *old in self.userLanguages) [self.languages removeObject:old];
    // Both tables start again from the built-in ones, so that a user language
    // that took a built-in's name, or its extension, gives it back when it
    // goes. Among user languages the first to claim an extension keeps it,
    // as getUserDefinedLangNameFromExt finds it.
    self.byExtension = [self.builtInByExtension mutableCopy];
    self.byName = [self.builtInByName mutableCopy];
    self.userLanguages = [languages copy];
    NSMutableSet *claimed = [NSMutableSet set];
    self.userByExtension = [NSMutableDictionary dictionary];
    for (NppLanguage *lang in languages) {
        lang.userDefined = YES;
        [self.languages addObject:lang];
        self.byName[lang.name] = lang;
        for (NSString *ext in lang.extensions) {
            NSString *key = ext.lowercaseString;
            if (!self.userByExtension[key]) self.userByExtension[key] = [NSMutableArray array];
            [self.userByExtension[key] addObject:lang];
            if ([claimed containsObject:key]) continue;
            [claimed addObject:key];
            self.byExtension[key] = lang;
        }
    }
}

/// Among the user languages claiming an extension, the first made for the
/// current mode; failing that, the first of any (getUserDefinedLangNameFromExt).
- (NppLanguage *)userLanguageForExtension:(NSString *)key {
    NSArray<NppLanguage *> *candidates = self.userByExtension[key];
    for (NppLanguage *lang in candidates) {
        if (lang.darkModeTheme == self.darkMode) return lang;
    }
    return candidates.firstObject;
}

/// Extensions given to a language in the Style Configurator come before the
/// built-in ones, as NppParameters::getLangFromExt checks them first.
- (NppLanguage *)stylerLanguageForExtension:(NSString *)ext {
    StyleCatalog *styles = [StyleCatalog sharedCatalog];
    for (NSString *lexer in styles.lexerNames) {
        if (![[styles userExtensionsForLexer:lexer] containsObject:ext]) continue;
        NppLanguage *lang = self.builtInByName ? self.builtInByName[lexer] : self.byName[lexer];
        if (lang) return lang;
    }
    return nil;
}

- (NppLanguage *)languageNamed:(NSString *)name {
    NppLanguage *found = self.byName[name];
    if (found || ![name isEqualToString:@"udf"]) return found;
    // Language > User-Defined (IDM_LANG_USER, L_USER): the user-defined lexer with no
    // definition of its own; langs.model.xml has no entry for it.
    static NppLanguage *plain;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [[NppLanguage alloc] init];
        plain.name = @"udf";
        plain.lexerID = @"user";
        plain.keywordSets = @{};
        plain.extensions = @[];
    });
    return plain;
}

- (NppLanguage *)languageForFileName:(NSString *)fileName {
    NSString *ext = fileName.pathExtension.lowercaseString;
    NppLanguage *lang = ext.length ? ([self userLanguageForExtension:ext] ?: [self stylerLanguageForExtension:ext]
                                      ?: self.byExtension[ext]) : nil;
    if (!lang || [lang.name isEqualToString:@"normal"]) {
        // Buffer::setFileName: what the extension leaves as plain text is refined by a
        // few whole names, and only by those - a file called "conf" or "c" is not a
        // file with that extension, so its modeline or contents can still decide.
        static NSDictionary<NSString *, NSString *> *wholeNames;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            wholeNames = @{@"makefile": @"makefile", @"gnumakefile": @"makefile", @"cmakelists.txt": @"cmake",
                           @"sconstruct": @"python", @"sconscript": @"python", @"wscript": @"python",
                           @"rakefile": @"ruby", @"vagrantfile": @"ruby",
                           @"crontab": @"bash", @"pkgbuild": @"bash", @"apkbuild": @"bash"};
        });
        NSString *whole = wholeNames[fileName.lastPathComponent.lowercaseString];
        if (whole && self.byName[whole]) lang = self.byName[whole];
    }
    return lang ?: self.byName[@"normal"];
}

+ (BOOL)languageHasMenuEntry:(NSString *)name {
    for (int i = 0; i < kNppLangLexerCount; ++i) {
        if (!strcmp(kNppLangLexers[i].langName, name.UTF8String)) return kNppLangLexers[i].menuID && *kNppLangLexers[i].menuID;
    }
    return YES;   // a language langs.model.xml has and the table does not: listed
}

/// The title upstream's Language menu gives a language: "C++", "None
/// (Normal Text)"; the langs.model.xml name when it has no menu entry.
+ (NSString *)menuTitleForLanguage:(NSString *)name {
    static NSDictionary<NSString *, NSString *> *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            if (!kNppLangLexers[i].menuID || !*kNppLangLexers[i].menuID) continue;
            for (int j = 0; j < kNppMenuCommandIDCount; ++j) {
                if (!strcmp(kNppMenuCommandIDs[j].name, kNppLangLexers[i].menuID)) {
                    m[@(kNppLangLexers[i].langName)] = @(kNppMenuCommandIDs[j].label);
                    break;
                }
            }
        }
        titles = m;
    });
    return titles[name] ?: name;
}


@end
