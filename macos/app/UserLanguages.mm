#import "UserLanguages.h"
#import "ScintillaView.h"
#import "SettingsCommands.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include <objc/runtime.h>

@implementation NppUserLanguage

/// The names a <Keywords> element may carry, in every version of the file
/// (UserDefineDialog.h's keywordNameMapper), to the SCE_USER_KWLIST index.
static NSDictionary<NSString *, NSNumber *> *KeywordListIndexes(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"Comments": @(SCE_USER_KWLIST_COMMENTS),
            @"Numbers, prefix1": @(SCE_USER_KWLIST_NUMBER_PREFIX1),
            @"Numbers, prefix2": @(SCE_USER_KWLIST_NUMBER_PREFIX2),
            @"Numbers, prefixes": @(SCE_USER_KWLIST_NUMBER_PREFIX2),
            @"Numbers, extras1": @(SCE_USER_KWLIST_NUMBER_EXTRAS1),
            @"Numbers, extras2": @(SCE_USER_KWLIST_NUMBER_EXTRAS2),
            @"Numbers, extras with prefixes": @(SCE_USER_KWLIST_NUMBER_EXTRAS2),
            @"Numbers, suffix1": @(SCE_USER_KWLIST_NUMBER_SUFFIX1),
            @"Numbers, suffix2": @(SCE_USER_KWLIST_NUMBER_SUFFIX2),
            @"Numbers, suffixes": @(SCE_USER_KWLIST_NUMBER_SUFFIX2),
            @"Numbers, range": @(SCE_USER_KWLIST_NUMBER_RANGE),
            @"Numbers, additional": @(SCE_USER_KWLIST_NUMBER_RANGE),
            @"Operators": @(SCE_USER_KWLIST_OPERATORS1),
            @"Operators1": @(SCE_USER_KWLIST_OPERATORS1),
            @"Operators2": @(SCE_USER_KWLIST_OPERATORS2),
            @"Folder+": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN),
            @"Folder-": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE),
            @"Folders in code1, open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN),
            @"Folders in code1, middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE),
            @"Folders in code1, close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE),
            @"Folders in code2, open": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_OPEN),
            @"Folders in code2, middle": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_MIDDLE),
            @"Folders in code2, close": @(SCE_USER_KWLIST_FOLDERS_IN_CODE2_CLOSE),
            @"Folders in comment, open": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_OPEN),
            @"Folders in comment, middle": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_MIDDLE),
            @"Folders in comment, close": @(SCE_USER_KWLIST_FOLDERS_IN_COMMENT_CLOSE),
            @"Words1": @(SCE_USER_KWLIST_KEYWORDS1), @"Words2": @(SCE_USER_KWLIST_KEYWORDS2),
            @"Words3": @(SCE_USER_KWLIST_KEYWORDS3), @"Words4": @(SCE_USER_KWLIST_KEYWORDS4),
            @"Keywords1": @(SCE_USER_KWLIST_KEYWORDS1), @"Keywords2": @(SCE_USER_KWLIST_KEYWORDS2),
            @"Keywords3": @(SCE_USER_KWLIST_KEYWORDS3), @"Keywords4": @(SCE_USER_KWLIST_KEYWORDS4),
            @"Keywords5": @(SCE_USER_KWLIST_KEYWORDS5), @"Keywords6": @(SCE_USER_KWLIST_KEYWORDS6),
            @"Keywords7": @(SCE_USER_KWLIST_KEYWORDS7), @"Keywords8": @(SCE_USER_KWLIST_KEYWORDS8),
            @"Delimiters": @(SCE_USER_KWLIST_DELIMITERS),
        };
    });
    return map;
}

/// A <WordsStyle name="..."> to its SCE_USER_STYLE id (styleIdMapper).
static NSDictionary<NSString *, NSNumber *> *StyleIndexes(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"DEFAULT": @(SCE_USER_STYLE_DEFAULT), @"COMMENTS": @(SCE_USER_STYLE_COMMENT),
            @"LINE COMMENTS": @(SCE_USER_STYLE_COMMENTLINE), @"NUMBERS": @(SCE_USER_STYLE_NUMBER),
            @"KEYWORDS1": @(SCE_USER_STYLE_KEYWORD1), @"KEYWORDS2": @(SCE_USER_STYLE_KEYWORD2),
            @"KEYWORDS3": @(SCE_USER_STYLE_KEYWORD3), @"KEYWORDS4": @(SCE_USER_STYLE_KEYWORD4),
            @"KEYWORDS5": @(SCE_USER_STYLE_KEYWORD5), @"KEYWORDS6": @(SCE_USER_STYLE_KEYWORD6),
            @"KEYWORDS7": @(SCE_USER_STYLE_KEYWORD7), @"KEYWORDS8": @(SCE_USER_STYLE_KEYWORD8),
            @"OPERATORS": @(SCE_USER_STYLE_OPERATOR),
            @"FOLDER IN CODE1": @(SCE_USER_STYLE_FOLDER_IN_CODE1),
            @"FOLDER IN CODE2": @(SCE_USER_STYLE_FOLDER_IN_CODE2),
            @"FOLDER IN COMMENT": @(SCE_USER_STYLE_FOLDER_IN_COMMENT),
            @"DELIMITERS1": @(SCE_USER_STYLE_DELIMITER1), @"DELIMITERS2": @(SCE_USER_STYLE_DELIMITER2),
            @"DELIMITERS3": @(SCE_USER_STYLE_DELIMITER3), @"DELIMITERS4": @(SCE_USER_STYLE_DELIMITER4),
            @"DELIMITERS5": @(SCE_USER_STYLE_DELIMITER5), @"DELIMITERS6": @(SCE_USER_STYLE_DELIMITER6),
            @"DELIMITERS7": @(SCE_USER_STYLE_DELIMITER7), @"DELIMITERS8": @(SCE_USER_STYLE_DELIMITER8),
            // The names files written before version 2.0 use.
            @"COMMENT": @(SCE_USER_STYLE_COMMENT), @"COMMENT LINE": @(SCE_USER_STYLE_COMMENTLINE),
            @"NUMBER": @(SCE_USER_STYLE_NUMBER), @"OPERATOR": @(SCE_USER_STYLE_OPERATOR),
            @"KEYWORD1": @(SCE_USER_STYLE_KEYWORD1), @"KEYWORD2": @(SCE_USER_STYLE_KEYWORD2),
            @"KEYWORD3": @(SCE_USER_STYLE_KEYWORD3), @"KEYWORD4": @(SCE_USER_STYLE_KEYWORD4),
            @"FOLDEROPEN": @(SCE_USER_STYLE_FOLDER_IN_CODE1), @"FOLDERCLOSE": @(SCE_USER_STYLE_FOLDER_IN_CODE1),
            @"DELIMINER1": @(SCE_USER_STYLE_DELIMITER1), @"DELIMINER2": @(SCE_USER_STYLE_DELIMITER2),
            @"DELIMINER3": @(SCE_USER_STYLE_DELIMITER3),
        };
    });
    return map;
}

static BOOL YesAttribute(NSXMLElement *element, NSString *name) {
    NSString *value = [element attributeForName:name].stringValue;
    return [value isEqualToString:@"yes"] || [value isEqualToString:@"1"] || [value isEqualToString:@"true"];
}

- (id)copyWithZone:(NSZone *)zone {
    NppUserLanguage *copy = [[NppUserLanguage allocWithZone:zone] init];
    copy.name = self.name; copy.extensions = self.extensions;
    copy.caseIgnored = self.caseIgnored; copy.allowFoldOfComments = self.allowFoldOfComments;
    copy.foldCompact = self.foldCompact; copy.forcePureLC = self.forcePureLC;
    copy.decimalSeparator = self.decimalSeparator; copy.prefixes = self.prefixes;
    copy.keywordLists = self.keywordLists; copy.styles = self.styles;
    copy.identifier = self.identifier; copy.darkModeTheme = self.darkModeTheme;
    copy.sourcePath = self.sourcePath;
    return copy;
}

+ (NSArray<NSString *> *)keywordListNames {
    return @[@"Comments", @"Numbers, prefix1", @"Numbers, prefix2", @"Numbers, extras1",
             @"Numbers, extras2", @"Numbers, suffix1", @"Numbers, suffix2", @"Numbers, range",
             @"Operators1", @"Operators2",
             @"Folders in code1, open", @"Folders in code1, middle", @"Folders in code1, close",
             @"Folders in code2, open", @"Folders in code2, middle", @"Folders in code2, close",
             @"Folders in comment, open", @"Folders in comment, middle", @"Folders in comment, close",
             @"Keywords1", @"Keywords2", @"Keywords3", @"Keywords4",
             @"Keywords5", @"Keywords6", @"Keywords7", @"Keywords8", @"Delimiters"];
}

+ (NSArray<NSString *> *)styleNames {
    return @[@"DEFAULT", @"COMMENTS", @"LINE COMMENTS", @"NUMBERS",
             @"KEYWORDS1", @"KEYWORDS2", @"KEYWORDS3", @"KEYWORDS4",
             @"KEYWORDS5", @"KEYWORDS6", @"KEYWORDS7", @"KEYWORDS8",
             @"OPERATORS", @"FOLDER IN CODE1", @"FOLDER IN CODE2", @"FOLDER IN COMMENT",
             @"DELIMITERS1", @"DELIMITERS2", @"DELIMITERS3", @"DELIMITERS4",
             @"DELIMITERS5", @"DELIMITERS6", @"DELIMITERS7", @"DELIMITERS8"];
}

+ (instancetype)emptyLanguageNamed:(NSString *)name {
    NppUserLanguage *udl = [[NppUserLanguage alloc] init];
    udl.name = name;
    udl.extensions = @[];
    NSMutableArray *prefixes = [NSMutableArray array];
    for (int i = 0; i < 8; ++i) [prefixes addObject:@NO];
    udl.prefixes = prefixes;
    NSMutableArray *lists = [NSMutableArray array];
    for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) [lists addObject:@""];
    // The empty shapes Windows writes for a new language.
    lists[SCE_USER_KWLIST_COMMENTS] = @"00 01 02 03 04";
    lists[SCE_USER_KWLIST_DELIMITERS] = @"00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23";
    udl.keywordLists = lists;
    NSMutableDictionary *styles = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < [self styleNames].count; ++i) {
        styles[@(i)] = @{@"fgColor": @"000000", @"bgColor": @"FFFFFF", @"fontStyle": @"0", @"nesting": @"0"};
    }
    udl.styles = styles;
    return udl;
}

/// A field as the dialog shows it, from the prefixed list: every token that
/// starts with the code, and a ((group)) whole (CommentStyleDialog::retrieve).
+ (NSString *)fieldForCode:(int)code inList:(NSString *)list {
    NSString *prefix = [NSString stringWithFormat:@"%02d", code];
    unichar p0 = [prefix characterAtIndex:0], p1 = [prefix characterAtIndex:1];
    NSUInteger n = list.length;
    unichar (^at)(NSInteger) = ^unichar(NSInteger i) {
        return (i >= 0 && (NSUInteger)i < n) ? [list characterAtIndex:(NSUInteger)i] : 0;
    };
    NSMutableString *out = [NSMutableString string];
    BOOL copying = NO, inGroup = NO;
    for (NSInteger i = 0; (NSUInteger)i < n; ++i) {
        unichar c = at(i);
        if ((i == 0 || at(i - 1) == ' ') && c == p0 && at(i + 1) == p1) {
            if (out.length) [out appendString:@" "];
            copying = YES;
            ++i;
            continue;
        }
        if (c == '(' && at(i + 1) == '(' && !inGroup && copying) inGroup = YES;
        if (c != ')' && at(i - 1) == ')' && at(i - 2) == ')' && inGroup) inGroup = NO;
        if (c == ' ' && copying) copying = NO;
        if (copying || inGroup) [out appendFormat:@"%C", c];
    }
    return out;
}

/// The prefixed list from the fields, in code order: each space-separated
/// token of field k becomes "kk<token>", a ((group)) staying one token
/// (convertTo).
+ (NSString *)listFromFields:(NSArray<NSString *> *)fields {
    NSMutableString *dest = [NSMutableString string];
    for (NSUInteger code = 0; code < fields.count; ++code) {
        NSString *prefix = [NSString stringWithFormat:@"%02lu", (unsigned long)code];
        NSString *text = fields[code];
        NSUInteger n = text.length;
        unichar (^at)(NSInteger) = ^unichar(NSInteger i) {
            return (i >= 0 && (NSUInteger)i < n) ? [text characterAtIndex:(NSUInteger)i] : 0;
        };
        if (dest.length) [dest appendString:@" "];
        [dest appendString:prefix];
        BOOL inGroup = NO;
        for (NSInteger i = 0; (NSUInteger)i < n; ++i) {
            if (i == 0 && at(i) == '(' && at(i + 1) == '(') {
                inGroup = YES;
            } else if (at(i) == ' ' && at(i + 1) == '(' && at(i + 2) == '(') {
                inGroup = YES;
                [dest appendFormat:@" %@", prefix];
                ++i;
            }
            if (inGroup && at(i - 1) == ')' && at(i - 2) == ')') inGroup = NO;
            if (at(i) == ' ') {
                if (at(i + 1) != ' ' && at(i + 1) != 0) {
                    [dest appendString:@" "];
                    if (!inGroup) [dest appendString:prefix];
                }
            } else {
                [dest appendFormat:@"%C", at(i)];
            }
        }
    }
    return dest;
}

- (NSXMLElement *)xmlElement {
    NSXMLElement *lang = [NSXMLElement elementWithName:@"UserLang"];
    [lang addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:self.name ?: @""]];
    [lang addAttribute:[NSXMLNode attributeWithName:@"ext"
                                        stringValue:[self.extensions componentsJoinedByString:@" "] ?: @""]];
    if (self.darkModeTheme) [lang addAttribute:[NSXMLNode attributeWithName:@"darkModeTheme" stringValue:@"yes"]];
    [lang addAttribute:[NSXMLNode attributeWithName:@"udlVersion" stringValue:@"2.1"]];

    NSXMLElement *settings = [NSXMLElement elementWithName:@"Settings"];
    NSXMLElement *global = [NSXMLElement elementWithName:@"Global"];
    NSString *(^yn)(BOOL) = ^NSString *(BOOL b) { return b ? @"yes" : @"no"; };
    [global addAttribute:[NSXMLNode attributeWithName:@"caseIgnored" stringValue:yn(self.caseIgnored)]];
    [global addAttribute:[NSXMLNode attributeWithName:@"allowFoldOfComments" stringValue:yn(self.allowFoldOfComments)]];
    [global addAttribute:[NSXMLNode attributeWithName:@"foldCompact" stringValue:yn(self.foldCompact)]];
    [global addAttribute:[NSXMLNode attributeWithName:@"forcePureLC" stringValue:[@(self.forcePureLC) stringValue]]];
    [global addAttribute:[NSXMLNode attributeWithName:@"decimalSeparator" stringValue:[@(self.decimalSeparator) stringValue]]];
    [settings addChild:global];
    NSXMLElement *prefix = [NSXMLElement elementWithName:@"Prefix"];
    for (int i = 0; i < 8; ++i) {
        BOOL on = i < (int)self.prefixes.count && [self.prefixes[i] boolValue];
        [prefix addAttribute:[NSXMLNode attributeWithName:[NSString stringWithFormat:@"Keywords%d", i + 1]
                                              stringValue:yn(on)]];
    }
    [settings addChild:prefix];
    [lang addChild:settings];

    NSXMLElement *lists = [NSXMLElement elementWithName:@"KeywordLists"];
    NSArray *names = [NppUserLanguage keywordListNames];
    for (NSUInteger i = 0; i < names.count; ++i) {
        NSXMLElement *keywords = [NSXMLElement elementWithName:@"Keywords"
                                                   stringValue:i < self.keywordLists.count ? self.keywordLists[i] : @""];
        [keywords addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:names[i]]];
        [lists addChild:keywords];
    }
    [lang addChild:lists];

    NSXMLElement *styles = [NSXMLElement elementWithName:@"Styles"];
    NSArray *styleNames = [NppUserLanguage styleNames];
    for (NSUInteger i = 0; i < styleNames.count; ++i) {
        NSDictionary *attrs = self.styles[@(i)] ?: @{};
        NSXMLElement *style = [NSXMLElement elementWithName:@"WordsStyle"];
        [style addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:styleNames[i]]];
        [style addAttribute:[NSXMLNode attributeWithName:@"fgColor" stringValue:attrs[@"fgColor"] ?: @"000000"]];
        [style addAttribute:[NSXMLNode attributeWithName:@"bgColor" stringValue:attrs[@"bgColor"] ?: @"FFFFFF"]];
        if ([attrs[@"colorStyle"] length]) {
            [style addAttribute:[NSXMLNode attributeWithName:@"colorStyle" stringValue:attrs[@"colorStyle"]]];
        }
        if ([attrs[@"fontName"] length]) {
            [style addAttribute:[NSXMLNode attributeWithName:@"fontName" stringValue:attrs[@"fontName"]]];
        }
        [style addAttribute:[NSXMLNode attributeWithName:@"fontStyle" stringValue:attrs[@"fontStyle"] ?: @"0"]];
        if (attrs[@"fontSize"]) {
            [style addAttribute:[NSXMLNode attributeWithName:@"fontSize" stringValue:attrs[@"fontSize"]]];
        }
        [style addAttribute:[NSXMLNode attributeWithName:@"nesting" stringValue:attrs[@"nesting"] ?: @"0"]];
        [styles addChild:style];
    }
    [lang addChild:styles];
    return lang;
}

+ (BOOL)writeLanguages:(NSArray<NppUserLanguage *> *)languages toFile:(NSString *)path {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    for (NppUserLanguage *udl in languages) [root addChild:[udl xmlElement]];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.version = @"1.0";
    doc.characterEncoding = @"UTF-8";
    NSData *data = [doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    return [data writeToFile:path options:NSDataWritingAtomic error:NULL];
}

+ (NSArray<NppUserLanguage *> *)languagesInFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return @[];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
    NSMutableArray *languages = [NSMutableArray array];
    for (NSXMLElement *userLang in [doc.rootElement elementsForName:@"UserLang"]) {
        NSString *name = [userLang attributeForName:@"name"].stringValue;
        if (!name.length) continue;
        NppUserLanguage *udl = [[NppUserLanguage alloc] init];
        udl.name = name;
        udl.sourcePath = path;
        udl.darkModeTheme = YesAttribute(userLang, @"darkModeTheme");
        NSString *udlVersion = [userLang attributeForName:@"udlVersion"].stringValue ?: @"";
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *e in [[userLang attributeForName:@"ext"].stringValue ?: @"" componentsSeparatedByString:@" "]) {
            if (e.length) [exts addObject:e.lowercaseString];
        }
        udl.extensions = exts;

        NSMutableArray *prefixes = [NSMutableArray arrayWithCapacity:8];
        for (int i = 0; i < 8; ++i) [prefixes addObject:@NO];
        NSXMLElement *settings = [userLang elementsForName:@"Settings"].firstObject;
        NSXMLElement *global = [settings elementsForName:@"Global"].firstObject;
        if (global) {
            udl.caseIgnored = YesAttribute(global, @"caseIgnored");
            udl.allowFoldOfComments = YesAttribute(global, @"allowFoldOfComments");
            udl.foldCompact = YesAttribute(global, @"foldCompact");
            udl.forcePureLC = [global attributeForName:@"forcePureLC"].stringValue.intValue;
            udl.decimalSeparator = [global attributeForName:@"decimalSeparator"].stringValue.intValue;
        }
        NSXMLElement *prefix = [settings elementsForName:@"Prefix"].firstObject;
        if (prefix) {
            for (int i = 0; i < 8; ++i) {
                NSString *key = [NSString stringWithFormat:@"Keywords%d", i + 1];
                NSString *old = [NSString stringWithFormat:@"words%d", i + 1];
                prefixes[i] = @(YesAttribute(prefix, key) || YesAttribute(prefix, old));
            }
        }
        udl.prefixes = prefixes;

        NSMutableArray *lists = [NSMutableArray arrayWithCapacity:SCE_USER_KWLIST_TOTAL];
        for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) [lists addObject:@""];
        NSXMLElement *keywordLists = [userLang elementsForName:@"KeywordLists"].firstObject;
        for (NSXMLElement *keywords in [keywordLists elementsForName:@"Keywords"]) {
            NSString *listName = [keywords attributeForName:@"name"].stringValue ?: @"";
            NSString *value = keywords.stringValue ?: @"";
            // Files written before 2.0 packed the delimiters into one string
            // and numbered the comment markers 0, 1, 2; both are rewritten
            // into the 2.x shape, as feedUserKeywordList does.
            if (!udlVersion.length && [listName isEqualToString:@"Delimiters"] && value.length >= 6) {
                unichar k[6];
                for (int i = 0; i < 6; ++i) k[i] = [value characterAtIndex:(NSUInteger)i];
                NSMutableString *temp = [NSMutableString stringWithString:@"00"];
                if (k[0] != '0') [temp appendFormat:@"%C", k[0]];
                [temp appendString:@" 01 02"];
                if (k[3] != '0') [temp appendFormat:@"%C", k[3]];
                [temp appendString:@" 03"];
                if (k[1] != '0') [temp appendFormat:@"%C", k[1]];
                [temp appendString:@" 04 05"];
                if (k[4] != '0') [temp appendFormat:@"%C", k[4]];
                [temp appendString:@" 06"];
                if (k[2] != '0') [temp appendFormat:@"%C", k[2]];
                [temp appendString:@" 07 08"];
                if (k[5] != '0') [temp appendFormat:@"%C", k[5]];
                [temp appendString:@" 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23"];
                lists[SCE_USER_KWLIST_DELIMITERS] = temp;
                continue;
            }
            if ([listName isEqualToString:@"Comment"]) {
                NSMutableString *temp = [NSMutableString stringWithFormat:@" %@", value];
                [temp replaceOccurrencesOfString:@" 0" withString:@" 00" options:0 range:NSMakeRange(0, temp.length)];
                [temp replaceOccurrencesOfString:@" 1" withString:@" 03" options:0 range:NSMakeRange(0, temp.length)];
                [temp replaceOccurrencesOfString:@" 2" withString:@" 04" options:0 range:NSMakeRange(0, temp.length)];
                lists[SCE_USER_KWLIST_COMMENTS] = [temp stringByTrimmingCharactersInSet:
                                                  [NSCharacterSet whitespaceCharacterSet]];
                continue;
            }
            NSNumber *index = KeywordListIndexes()[listName];
            if (index) lists[index.unsignedIntegerValue] = value;
        }
        udl.keywordLists = lists;

        NSMutableDictionary *styles = [NSMutableDictionary dictionary];
        NSXMLElement *styleRoot = [userLang elementsForName:@"Styles"].firstObject;
        for (NSXMLElement *style in [styleRoot elementsForName:@"WordsStyle"]) {
            NSNumber *styleID = StyleIndexes()[[style attributeForName:@"name"].stringValue ?: @""];
            if (!styleID) continue;
            NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
            for (NSString *key in @[@"fgColor", @"bgColor", @"colorStyle", @"fontName", @"fontStyle", @"fontSize", @"nesting"]) {
                NSString *value = [style attributeForName:key].stringValue;
                if (value.length) attrs[key] = value;
            }
            styles[styleID] = attrs;
        }
        udl.styles = styles;
        [languages addObject:udl];
    }
    return languages;
}

@end

#pragma mark - The catalog

static const char kUserDefinitionKey = 0;
static const char kUserLanguagesKey = 0;
static const char kUserDirectoryKey = 0;

@implementation LanguageCatalog (UserLanguages)

NSString *const NppUserLanguagesDidChangeNotification = @"NppUserLanguagesDidChangeNotification";

+ (NSString *)bundledUserLanguagesDirectory {
    return [[NSBundle mainBundle] pathForResource:@"userDefineLangs" ofType:nil];
}

- (NSArray<NppUserLanguage *> *)reloadUserLanguagesFromDirectory:(NSString *)directory {
    NSMutableArray<NppUserLanguage *> *found = [NSMutableArray array];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    [files addObject:[directory stringByAppendingPathComponent:@"userDefineLang.xml"]];
    NSString *folder = [directory stringByAppendingPathComponent:@"userDefineLangs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableSet *userFileNames = [NSMutableSet set];
    for (NSString *name in [[fm contentsOfDirectoryAtPath:folder error:NULL]
                            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if ([name.pathExtension caseInsensitiveCompare:@"xml"] == NSOrderedSame) {
            [files addObject:[folder stringByAppendingPathComponent:name]];
            [userFileNames addObject:name.lowercaseString];
        }
    }
    // The ones Notepad++ ships, unless the user has a file of the same name
    // (an edited or removed copy of a shipped one).
    NSString *bundled = [LanguageCatalog bundledUserLanguagesDirectory] ?: @"";
    for (NSString *name in [[fm contentsOfDirectoryAtPath:bundled error:NULL]
                            sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if ([name.pathExtension caseInsensitiveCompare:@"xml"] != NSOrderedSame) continue;
        if ([userFileNames containsObject:name.lowercaseString]) continue;
        [files addObject:[bundled stringByAppendingPathComponent:name]];
    }
    for (NSString *path in files) [found addObjectsFromArray:[NppUserLanguage languagesInFile:path]];
    int identifier = 0;
    for (NppUserLanguage *udl in found) udl.identifier = ++identifier;

    NSMutableArray<NppLanguage *> *entries = [NSMutableArray array];
    for (NppUserLanguage *udl in found) {
        NppLanguage *lang = [[NppLanguage alloc] init];
        lang.name = udl.name;
        lang.lexerID = @"user";
        lang.extensions = udl.extensions;
        lang.keywordSets = @{};
        // The comment tokens, for comment toggling: the first block pair and
        // the first line marker of the Comments list, when written in the
        // 2.x shape "00# 01 02 03/* 04*/".
        for (NSString *piece in [udl.keywordLists[SCE_USER_KWLIST_COMMENTS] componentsSeparatedByString:@" "]) {
            if (piece.length <= 2) continue;
            NSString *code = [piece substringToIndex:2], *token = [piece substringFromIndex:2];
            if ([code isEqualToString:@"00"] && !lang.commentLine) lang.commentLine = token;
            if ([code isEqualToString:@"03"] && !lang.commentStart) lang.commentStart = token;
            if ([code isEqualToString:@"04"] && !lang.commentEnd) lang.commentEnd = token;
        }
        lang.darkModeTheme = udl.darkModeTheme;
        objc_setAssociatedObject(lang, &kUserDefinitionKey, udl, OBJC_ASSOCIATION_RETAIN);
        [entries addObject:lang];
    }
    [self registerUserLanguages:entries];
    objc_setAssociatedObject(self, &kUserLanguagesKey, found, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(self, &kUserDirectoryKey, directory, OBJC_ASSOCIATION_RETAIN);
    [[NSNotificationCenter defaultCenter] postNotificationName:NppUserLanguagesDidChangeNotification object:self];
    return found;
}

- (NSArray<NppUserLanguage *> *)allUserLanguages {
    return objc_getAssociatedObject(self, &kUserLanguagesKey) ?: @[];
}

#pragma mark Keeping them

- (NSString *)defaultUserLanguageFileIn:(NSString *)directory {
    return [directory stringByAppendingPathComponent:@"userDefineLang.xml"];
}

/// Where a language is written: its own file, unless that file is one the
/// application ships - then a copy of it in the user's folder, which from
/// then on shadows the shipped one.
- (NSString *)writableFileFor:(NppUserLanguage *)udl directory:(NSString *)directory {
    NSString *source = udl.sourcePath;
    if (!source.length) return [self defaultUserLanguageFileIn:directory];
    NSString *bundled = [LanguageCatalog bundledUserLanguagesDirectory];
    if (bundled.length && [source hasPrefix:[bundled stringByAppendingString:@"/"]]) {
        return [[directory stringByAppendingPathComponent:@"userDefineLangs"]
                stringByAppendingPathComponent:source.lastPathComponent];
    }
    return source;
}

/// Every language read from `file` (as currently known), with `replace`
/// applied to it: returns the list to write back.
- (NSMutableArray<NppUserLanguage *> *)languagesOfFile:(NSString *)file directory:(NSString *)directory {
    NSMutableArray *out = [NSMutableArray array];
    for (NppUserLanguage *u in [self allUserLanguages]) {
        if ([[self writableFileFor:u directory:directory] isEqualToString:file]) [out addObject:[u copy]];
    }
    return out;
}

- (BOOL)nameTaken:(NSString *)name except:(nullable NppUserLanguage *)udl {
    for (NppUserLanguage *u in [self allUserLanguages]) {
        if (u != udl && [u.name isEqualToString:name]) return YES;
    }
    return NO;
}

- (BOOL)writeFile:(NSString *)file languages:(NSArray<NppUserLanguage *> *)languages directory:(NSString *)directory {
    if (![NppUserLanguage writeLanguages:languages toFile:file]) return NO;
    [self reloadUserLanguagesFromDirectory:directory];
    return YES;
}

- (BOOL)saveUserLanguage:(NppUserLanguage *)udl directory:(NSString *)directory {
    NSString *file = [self writableFileFor:udl directory:directory];
    NSMutableArray *languages = [self languagesOfFile:file directory:directory];
    NSUInteger at = [languages indexOfObjectPassingTest:^BOOL(NppUserLanguage *u, NSUInteger i, BOOL *stop) {
        return [u.name isEqualToString:udl.name];
    }];
    if (at == NSNotFound) {
        if ([self nameTaken:udl.name except:nil]) return NO;
        [languages addObject:udl];
    } else {
        languages[at] = udl;
    }
    return [self writeFile:file languages:languages directory:directory];
}

- (BOOL)saveUserLanguage:(NppUserLanguage *)udl asName:(NSString *)name directory:(NSString *)directory {
    if (!name.length || [self nameTaken:name except:nil]) return NO;
    NppUserLanguage *copy = [udl copy];
    copy.name = name;
    copy.sourcePath = nil;
    NSString *file = [self defaultUserLanguageFileIn:directory];
    NSMutableArray *languages = [self languagesOfFile:file directory:directory];
    [languages addObject:copy];
    return [self writeFile:file languages:languages directory:directory];
}

- (BOOL)renameUserLanguage:(NppUserLanguage *)udl to:(NSString *)name directory:(NSString *)directory {
    if (!name.length || [self nameTaken:name except:udl]) return NO;
    NSString *file = [self writableFileFor:udl directory:directory];
    NSMutableArray *languages = [self languagesOfFile:file directory:directory];
    for (NppUserLanguage *u in languages) {
        if ([u.name isEqualToString:udl.name]) u.name = name;
    }
    return [self writeFile:file languages:languages directory:directory];
}

- (BOOL)removeUserLanguage:(NppUserLanguage *)udl directory:(NSString *)directory {
    NSString *file = [self writableFileFor:udl directory:directory];
    NSMutableArray *languages = [self languagesOfFile:file directory:directory];
    NSUInteger before = languages.count;
    [languages filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppUserLanguage *u, NSDictionary *b) {
        return ![u.name isEqualToString:udl.name];
    }]];
    if (languages.count == before) return NO;
    // A file of the user's own that is left empty goes; the default file and
    // a copy shadowing a shipped one stay, empty, so nothing comes back.
    NSString *bundled = [LanguageCatalog bundledUserLanguagesDirectory];
    BOOL shadowsShipped = bundled.length && [[NSFileManager defaultManager] fileExistsAtPath:
        [bundled stringByAppendingPathComponent:file.lastPathComponent]];
    if (!languages.count && ![file isEqualToString:[self defaultUserLanguageFileIn:directory]] && !shadowsShipped) {
        [[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
        [self reloadUserLanguagesFromDirectory:directory];
        return YES;
    }
    return [self writeFile:file languages:languages directory:directory];
}

- (NSArray<NSString *> *)importUserLanguagesFromFile:(NSString *)path directory:(NSString *)directory {
    NSString *file = [self defaultUserLanguageFileIn:directory];
    NSMutableArray *languages = [self languagesOfFile:file directory:directory];
    NSMutableArray *added = [NSMutableArray array];
    for (NppUserLanguage *u in [NppUserLanguage languagesInFile:path]) {
        if ([self nameTaken:u.name except:nil] || [added containsObject:u.name]) continue;
        u.sourcePath = nil;
        [languages addObject:u];
        [added addObject:u.name];
    }
    if (added.count && ![self writeFile:file languages:languages directory:directory]) return @[];
    return added;
}

- (BOOL)exportUserLanguage:(NppUserLanguage *)udl toFile:(NSString *)path {
    return [NppUserLanguage writeLanguages:@[udl] toFile:path];
}

- (NppUserLanguage *)userLanguageNamed:(NSString *)name {
    NppLanguage *lang = [self languageNamed:name];
    return lang ? objc_getAssociatedObject(lang, &kUserDefinitionKey) : nil;
}

@end

#pragma mark - Driving the lexer

@implementation EditorController (UserLanguages)

/// A keyword list the way setUserLexer hands it to SCI_SETKEYWORDS: quoted
/// phrases become one word with \v (double quotes) or \b (single quotes)
/// standing for the spaces inside, and \" \' \\ are unescaped.
static NSString *KeywordListForScintilla(NSString *list) {
    const char *in = list.UTF8String ?: "";
    size_t len = strlen(in);
    std::string out;
    out.reserve(len);
    bool inDouble = false, inSingle = false, nonWSFound = false;
    for (size_t j = 0; j < len; ++j) {
        char c = in[j];
        if (!inSingle && c == '"') { inDouble = !inDouble; continue; }
        if (!inDouble && c == '\'') { inSingle = !inSingle; continue; }
        if (c == '\\' && (in[j + 1] == '"' || in[j + 1] == '\'' || in[j + 1] == '\\')) {
            ++j;
            out.push_back(in[j]);
            continue;
        }
        if (inDouble || inSingle) {
            if (c > ' ') {
                out.push_back(c);
                nonWSFound = true;
            } else if (nonWSFound && in[j - 1] != '"' && in[j + 1] != '"' && in[j + 1] > ' ') {
                out.push_back(inDouble ? '\v' : '\b');
            }
        } else {
            out.push_back(c);
        }
    }
    return @(out.c_str());
}

- (void)configureUserLexerFor:(NppUserLanguage *)udl {
    ScintillaView *sci = self.sci;
    [sci setLexerProperty:@"fold" value:@"1"];
    [sci setLexerProperty:@"userDefine.isCaseIgnored" value:udl.caseIgnored ? @"1" : @"0"];
    [sci setLexerProperty:@"userDefine.allowFoldOfComments" value:udl.allowFoldOfComments ? @"1" : @"0"];
    [sci setLexerProperty:@"userDefine.foldCompact" value:udl.foldCompact ? @"1" : @"0"];
    for (int i = 0; i < 8; ++i) {
        [sci setLexerProperty:[NSString stringWithFormat:@"userDefine.prefixKeywords%d", i + 1]
                        value:[udl.prefixes[i] boolValue] ? @"1" : @"0"];
    }

    // The lists that are properties (setLexerMapper) and the ones that are
    // keyword sets, numbered in the order they come.
    NSDictionary<NSNumber *, NSString *> *properties = @{
        @(SCE_USER_KWLIST_COMMENTS): @"userDefine.comments",
        @(SCE_USER_KWLIST_DELIMITERS): @"userDefine.delimiters",
        @(SCE_USER_KWLIST_OPERATORS1): @"userDefine.operators1",
        @(SCE_USER_KWLIST_NUMBER_PREFIX1): @"userDefine.numberPrefix1",
        @(SCE_USER_KWLIST_NUMBER_PREFIX2): @"userDefine.numberPrefix2",
        @(SCE_USER_KWLIST_NUMBER_EXTRAS1): @"userDefine.numberExtras1",
        @(SCE_USER_KWLIST_NUMBER_EXTRAS2): @"userDefine.numberExtras2",
        @(SCE_USER_KWLIST_NUMBER_SUFFIX1): @"userDefine.numberSuffix1",
        @(SCE_USER_KWLIST_NUMBER_SUFFIX2): @"userDefine.numberSuffix2",
        @(SCE_USER_KWLIST_NUMBER_RANGE): @"userDefine.numberRange",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_OPEN): @"userDefine.foldersInCode1Open",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_MIDDLE): @"userDefine.foldersInCode1Middle",
        @(SCE_USER_KWLIST_FOLDERS_IN_CODE1_CLOSE): @"userDefine.foldersInCode1Close",
    };
    int keywordSet = 0;
    for (int i = 0; i < SCE_USER_KWLIST_TOTAL; ++i) {
        NSString *list = i < (int)udl.keywordLists.count ? udl.keywordLists[i] : @"";
        NSString *property = properties[@(i)];
        if (property) {
            [sci setLexerProperty:property value:list];
        } else {
            [sci setStringProperty:SCI_SETKEYWORDS parameter:keywordSet++ value:KeywordListForScintilla(list)];
        }
    }
    [sci setLexerProperty:@"userDefine.forcePureLC" value:[@(udl.forcePureLC) stringValue]];
    [sci setLexerProperty:@"userDefine.decimalSeparator" value:[@(udl.decimalSeparator) stringValue]];
    // Read back with atoi by the lexer, which keys its parsed keyword tables
    // on them: small numbers, never pointers.
    [sci setLexerProperty:@"userDefine.udlName" value:[@(udl.identifier) stringValue]];
    [sci setLexerProperty:@"userDefine.currentBufferID"
                    value:[@((int)(((uintptr_t)self.currentDocument.docPointer >> 4) & 0x7FFFFFFF)) stringValue]];
    for (NSNumber *styleID in udl.styles) {
        NSString *nesting = udl.styles[styleID][@"nesting"];
        if (nesting.length) {
            [sci setLexerProperty:[NSString stringWithFormat:@"userDefine.nesting.%02d", styleID.intValue]
                            value:nesting];
        }
    }
}

static NSColor *ColourFromHex(NSString *hex) {
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}

static long SciColourOf(NSColor *c) {
    NSColor *d = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    return ((long)(d.blueComponent * 255) << 16) + ((long)(d.greenComponent * 255) << 8) + (long)(d.redComponent * 255);
}

- (void)applyUserLanguageStyles:(NppUserLanguage *)udl {
    ScintillaView *sci = self.sci;
    for (NSNumber *styleID in udl.styles) {
        NSDictionary *attrs = udl.styles[styleID];
        uptr_t id = (uptr_t)styleID.intValue;
        NSColor *fg = ColourFromHex(attrs[@"fgColor"]), *bg = ColourFromHex(attrs[@"bgColor"]);
        // colorStyle says which colours are the style's own; a transparent one
        // is left as the default style has it (setSpecialStyle).
        int colorStyle = attrs[@"colorStyle"] ? [attrs[@"colorStyle"] intValue] : 3;
        if (fg && (colorStyle & 1)) [sci message:SCI_STYLESETFORE wParam:id lParam:SciColourOf(fg)];
        if (bg && (colorStyle & 2)) [sci message:SCI_STYLESETBACK wParam:id lParam:SciColourOf(bg)];
        int fontStyle = [attrs[@"fontStyle"] intValue];
        if (fontStyle & 1) [sci message:SCI_STYLESETBOLD wParam:id lParam:1];
        if (fontStyle & 2) [sci message:SCI_STYLESETITALIC wParam:id lParam:1];
        if (fontStyle & 4) [sci message:SCI_STYLESETUNDERLINE wParam:id lParam:1];
        if ([attrs[@"fontName"] length]) [sci setStringProperty:SCI_STYLESETFONT parameter:(long)id value:NppAvailableFontName(attrs[@"fontName"])];
        if ([attrs[@"fontSize"] intValue] > 0) [sci message:SCI_STYLESETSIZE wParam:id lParam:[attrs[@"fontSize"] intValue]];
    }
}

@end
