#import "FunctionListCatalog.h"
#import "NppRegex.h"

@interface NSString (NppPrefixAt)
- (BOOL)hasPrefixAtIndex:(NSUInteger)index string:(NSString *)prefix;
@end

@implementation NSString (NppPrefixAt)
- (BOOL)hasPrefixAtIndex:(NSUInteger)index string:(NSString *)prefix {
    if (index + prefix.length > self.length) return NO;
    return [[self substringWithRange:NSMakeRange(index, prefix.length)] isEqualToString:prefix];
}
@end

@implementation NppFunctionEntry
@end

/// One <parser> from a functionList file.
@interface NppFunctionParser : NSObject
@property (nonatomic, copy) NSString *parserID;
@property (nonatomic, copy, nullable) NSString *commentExpr;       // <parser commentExpr>
@property (nonatomic, copy, nullable) NSString *functionExpr;      // <function mainExpr>
@property (nonatomic, copy, nullable) NSString *classRangeExpr;    // <classRange mainExpr>
@property (nonatomic, copy, nullable) NSString *classOpenSymbol;   // <classRange openSymbole>
@property (nonatomic, copy, nullable) NSString *classCloseSymbol;  // <classRange closeSymbole>
@property (nonatomic, copy, nullable) NSString *classFunctionExpr;
// Upstream lists several name patterns and uses the first that matches, so the
// order matters and all of them have to be kept.
@property (nonatomic, strong) NSMutableArray<NSString *> *functionNameExprs;
@property (nonatomic, strong) NSMutableArray<NSString *> *classNameExprs;
@property (nonatomic, strong) NSMutableArray<NSString *> *classFunctionNameExprs;
/// <className> written inside a plain <function>: the container is read out of
/// the function's own match, which is how "NppParameters::load" is filed under
/// NppParameters without there being a class body anywhere in the file.
@property (nonatomic, strong) NSMutableArray<NSString *> *functionClassNameExprs;
@end

@implementation NppFunctionParser
- (instancetype)init {
    if (!(self = [super init])) return nil;
    _functionNameExprs = [NSMutableArray array];
    _classNameExprs = [NSMutableArray array];
    _classFunctionNameExprs = [NSMutableArray array];
    _functionClassNameExprs = [NSMutableArray array];
    return self;
}
@end
@interface FunctionListCatalog () <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NppFunctionParser *> *parsers;
/// "language:python" or "ext:py" -> parser id
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *associations;
/// The file a parser came from: upstream's association map keys on file names
/// ("cpp.xml"), while each file's parser carries its own id ("cplusplus_syntax").
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *parserIDByFile;
@property (nonatomic, copy, nullable) NSString *currentFileBase;

// parse state
@property (nonatomic, strong, nullable) NppFunctionParser *current;
@property (nonatomic) BOOL inClassRange;
@property (nonatomic) BOOL inClassName;
@property (nonatomic) BOOL inFunctionName;
@property (nonatomic) BOOL inFunction;
@end

@implementation FunctionListCatalog

+ (instancetype)sharedCatalog {
    static FunctionListCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[FunctionListCatalog alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _parsers = [NSMutableDictionary dictionary];
    _associations = [NSMutableDictionary dictionary];
    _parserIDByFile = [NSMutableDictionary dictionary];

    // Upstream's definitions first, then the corrections, which replace a
    // parser of the same id. What each correction changes, and why, is written
    // at the top of its file.
    for (NSString *folder in @[@"functionList", @"functionListCorrections"]) {
        NSString *dir = [[NSBundle mainBundle] pathForResource:folder ofType:nil];
        if (!dir) continue;
        NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
                          sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *file in files) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
            NSData *data = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:file]];
            if (!data) continue;
            data = [FunctionListCatalog dataPreservingAttributeNewlines:data];
            self.currentFileBase = file.stringByDeletingPathExtension.lowercaseString;
            NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
            parser.delegate = self;
            [parser parse];
        }
    }
    return self;
}

/// XML says a newline inside an attribute value is the same as a space, and
/// NSXMLParser obeys that. Most of these patterns are written with (?x), where
/// a # comment runs to the end of the line -- so once the newlines are gone the
/// first comment swallows the whole pattern and it matches nothing. Notepad++
/// does not hit this because its own XML reader leaves the newlines alone.
///
/// Turning each newline into a character reference before parsing gets them
/// back: a parser must expand &#10; to a newline and must not then fold it into
/// a space, because only literal whitespace is normalised.
+ (NSData *)dataPreservingAttributeNewlines:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length) return data;

    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    BOOL inTag = NO;
    unichar quote = 0;
    NSUInteger i = 0, length = text.length;

    while (i < length) {
        // Comments, CDATA and processing instructions are copied across
        // untouched. Stepping through them character by character would be
        // wrong: an apostrophe in a comment -- "the file's end", which nppexec
        // has -- would look like the start of an attribute value, and the rest
        // of the file would be read as one.
        if (!quote) {
            NSString *skipTo = nil;
            if ([text hasPrefixAtIndex:i string:@"<!--"]) skipTo = @"-->";
            else if ([text hasPrefixAtIndex:i string:@"<![CDATA["]) skipTo = @"]]>";
            else if ([text hasPrefixAtIndex:i string:@"<?"]) skipTo = @"?>";
            if (skipTo) {
                NSRange end = [text rangeOfString:skipTo
                                          options:0
                                            range:NSMakeRange(i, length - i)];
                NSUInteger stop = (end.location == NSNotFound) ? length : NSMaxRange(end);
                [out appendString:[text substringWithRange:NSMakeRange(i, stop - i)]];
                i = stop;
                inTag = NO;
                continue;
            }
        }

        unichar c = [text characterAtIndex:i];
        if (quote) {
            if (c == quote) quote = 0;
            else if (c == '\n') { [out appendString:@"&#10;"]; ++i; continue; }
            else if (c == '\r') { [out appendString:@"&#13;"]; ++i; continue; }
        } else if (inTag && (c == '"' || c == '\'')) {
            quote = c;
        } else if (c == '<') {
            inTag = YES;
        } else if (c == '>') {
            inTag = NO;
        }
        [out appendFormat:@"%C", c];
        ++i;
    }
    return [out dataUsingEncoding:NSUTF8StringEncoding] ?: data;
}

- (NSArray<NSString *> *)parserIDs {
    return [self.parsers.allKeys sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {

    if ([element isEqualToString:@"parser"]) {
        NppFunctionParser *p = [[NppFunctionParser alloc] init];
        p.parserID = attrs[@"id"] ?: @"";
        p.commentExpr = attrs[@"commentExpr"];
        self.current = p;
        self.inClassRange = self.inClassName = self.inFunctionName = NO;
        return;
    }
    if ([element isEqualToString:@"association"]) {
        NSString *target = attrs[@"id"] ?: @"";
        if (attrs[@"langID"]) {
            // langID is a numeric LangType; the language name is the useful key,
            // so the file's own name is used as a fallback association.
            self.associations[[@"lang:" stringByAppendingString:attrs[@"langID"]]] = target;
        }
        if (attrs[@"userDefinedLangName"]) {
            self.associations[[@"language:" stringByAppendingString:
                               attrs[@"userDefinedLangName"].lowercaseString]] = target;
        }
        if (attrs[@"ext"]) {
            NSString *ext = attrs[@"ext"];
            if ([ext hasPrefix:@"."]) ext = [ext substringFromIndex:1];
            self.associations[[@"ext:" stringByAppendingString:ext.lowercaseString]] = target;
        }
        return;
    }
    if (!self.current) return;

    if ([element isEqualToString:@"classRange"]) {
        self.inClassRange = YES;
        self.current.classRangeExpr = attrs[@"mainExpr"];
        // Upstream spells these "openSymbole"/"closeSymbole".
        self.current.classOpenSymbol = attrs[@"openSymbole"];
        self.current.classCloseSymbol = attrs[@"closeSymbole"];
    } else if ([element isEqualToString:@"className"]) {
        self.inClassName = YES;
    } else if ([element isEqualToString:@"functionName"]) {
        self.inFunctionName = YES;
    } else if ([element isEqualToString:@"function"]) {
        self.inFunction = YES;
        if (self.inClassRange) self.current.classFunctionExpr = attrs[@"mainExpr"];
        else self.current.functionExpr = attrs[@"mainExpr"];
    } else if ([element isEqualToString:@"nameExpr"] ||
               [element isEqualToString:@"funcNameExpr"]) {
        // The two spellings mean the same thing; which list an entry belongs to
        // is decided by the element it sits inside, not by its own name. Most
        // of upstream's files use <nameExpr> inside <functionName>.
        NSString *expr = attrs[@"expr"];
        if (!expr.length) return;
        if (self.inClassName) {
            // Inside a classRange it names the class; inside a plain function it
            // names the container that function belongs to.
            if (self.inClassRange) [self.current.classNameExprs addObject:expr];
            else [self.current.functionClassNameExprs addObject:expr];
        }
        else if (self.inFunctionName) {
            if (self.inClassRange) [self.current.classFunctionNameExprs addObject:expr];
            else [self.current.functionNameExprs addObject:expr];
        }
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn {
    if ([element isEqualToString:@"parser"]) {
        if (self.current.parserID.length) {
            self.parsers[self.current.parserID] = self.current;
            if (self.currentFileBase.length && !self.parserIDByFile[self.currentFileBase]) {
                self.parserIDByFile[self.currentFileBase] = self.current.parserID;
            }
        }
        self.current = nil;
    } else if ([element isEqualToString:@"function"]) {
        self.inFunction = NO;
    } else if ([element isEqualToString:@"classRange"]) {
        self.inClassRange = NO;
    } else if ([element isEqualToString:@"className"]) {
        self.inClassName = NO;
    } else if ([element isEqualToString:@"functionName"]) {
        self.inFunctionName = NO;
    }
}

#pragma mark - Lookup

/// An association names the file a parser lives in, not the parser itself:
/// overrideMap.xml says userDefinedLangName="NppExec" is served by nppexec.xml.
/// Resolve the file name to the id of the parser inside it.
- (NSString *)parserIDForTarget:(NSString *)target {
    if (!target.length) return nil;
    NSString *base = target.stringByDeletingPathExtension.lowercaseString;
    return self.parserIDByFile[base] ?: (self.parsers[target] ? target : nil);
}

- (NSString *)parserIDForLanguage:(NSString *)language extension:(NSString *)ext {
    if (ext.length) {
        NSString *byExt = [self parserIDForTarget:
                           self.associations[[@"ext:" stringByAppendingString:ext.lowercaseString]]];
        if (byExt) return byExt;
    }
    NSString *byName = [self parserIDForTarget:
                        self.associations[[@"language:" stringByAppendingString:
                                           language.lowercaseString]]];
    if (byName) return byName;

    // Upstream names each file after its language, so that is the reliable key.
    NSString *byFile = self.parserIDByFile[language.lowercaseString];
    if (byFile) return byFile;
    if (ext.length) {
        NSString *byExtFile = self.parserIDByFile[ext.lowercaseString];
        if (byExtFile) return byExtFile;
    }

    // Upstream names most parsers "<language>_syntax" or "<language>_function".
    for (NSString *suffix in @[@"_syntax", @"_function", @""]) {
        NSString *candidate = [language.lowercaseString stringByAppendingString:suffix];
        if (self.parsers[candidate]) return candidate;
    }
    return nil;
}

/// Narrows a run of bytes down to a name. The patterns are applied one after
/// another, each searching inside what the one before it found -- not as
/// alternatives. That is how upstream reaches "Thing" from "class Thing".
static NSRange NarrowToName(NSData *data, NSRange body, NSArray<NSString *> *exprs);

/// Blanks out whatever `commentExpr` matches, keeping the length the same so
/// every offset -- and so every line number -- still points where it did.
static NSData *DataWithoutComments(NSData *data, NSString *commentExpr);

/// The line a byte offset falls on, counting from zero.
static NSUInteger LineAtByte(NSData *data, NSUInteger offset) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger line = 0;
    for (NSUInteger i = 0; i < offset && i < data.length; ++i) {
        if (bytes[i] == '\n') line++;
        else if (bytes[i] == '\r' && (i + 1 >= data.length || bytes[i + 1] != '\n')) line++;
    }
    return line;
}

/// Upstream searches with SCFIND_REGEXP | SCFIND_POSIX | SCFIND_REGEXP_DOTMATCHESNL
/// and no SCFIND_MATCHCASE, so every one of these patterns is matched without
/// regard to case. That is not incidental: the patterns opt back in where they
/// need to, with (?-i:...) -- c.xml guards its keyword list that way, and
/// hollywood.xml writes "function" in lower case for a language that spells it
/// Function. A pattern compiled case-sensitively finds nothing there.
static NppRegex *FunctionListRegex(NSString *pattern) {
    if (!pattern.length) return nil;
    return [NppRegex regexWithPattern:[@"(?i)" stringByAppendingString:pattern]];
}

static NSString *StringFromBytes(NSData *data, NSRange range) {
    if (range.location == NSNotFound || !range.length) return @"";
    if (NSMaxRange(range) > data.length) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:range]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSArray<NppFunctionEntry *> *)entriesInText:(NSString *)text
                                   forLanguage:(NSString *)language
                                     extension:(NSString *)ext {
    NSString *parserID = [self parserIDForLanguage:language extension:ext];
    NppFunctionParser *p = parserID ? self.parsers[parserID] : nil;
    if (!p || !text.length || !NppRegex.available) return @[];

    // Everything below works in UTF-8 bytes, which is what PCRE2 matches in and
    // what Scintilla stores, so no offset ever has to be translated.
    NSData *whole = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!whole.length) return @[];

    // Matching runs against a copy with the comments blanked out, so a function
    // mentioned in a comment is not reported.
    NSData *subject = DataWithoutComments(whole, p.commentExpr);
    NSRange all = NSMakeRange(0, subject.length);
    NSMutableArray *entries = [NSMutableArray array];

    void (^collect)(NSString *, NSArray<NSString *> *, NSRange, NSString *) =
        ^(NSString *mainExpr, NSArray<NSString *> *nameExprs, NSRange range, NSString *container) {
        NppRegex *re = FunctionListRegex(mainExpr);
        if (!re) return;
        [re enumerateMatchesInData:subject range:range usingBlock:^(NSRange m, BOOL *stop) {
            // A match that runs to the very end of the range it was looked for
            // in is dropped, and the search stops there. funcParse does the same
            // -- "if (targetStart + foundTextLen == end) break" -- which is what
            // keeps a trailing word from being reported as a declaration.
            if (NSMaxRange(m) == NSMaxRange(range)) { *stop = YES; return; }
            NSRange named = NarrowToName(subject, m, nameExprs);
            if (named.location == NSNotFound) return;      // nothing to call it
            // The name is whatever the pattern narrowed to, not a tidied
            // version of it: upstream keeps the trailing space in a CSS
            // selector, and the tests say so.
            NSString *name = StringFromBytes(subject, named);
            if (![name stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]].length) name = @"";
            if (!name.length) return;

            NSString *owner = container;
            if (!owner.length && p.functionClassNameExprs.count) {
                NSRange named = NarrowToName(subject, m, p.functionClassNameExprs);
                if (named.location != NSNotFound) {
                    owner = [StringFromBytes(subject, named)
                             stringByTrimmingCharactersInSet:
                                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
            }

            NppFunctionEntry *entry = [[NppFunctionEntry alloc] init];
            entry.name = name;
            entry.container = owner;
            entry.line = LineAtByte(subject, m.location);
            [entries addObject:entry];
        }];
    };

    // Classes first, so their members are attributed to them and are not then
    // reported a second time by the plain function pass.
    NSMutableArray<NSValue *> *classBodies = [NSMutableArray array];
    if (p.classRangeExpr.length) {
        NppRegex *re = FunctionListRegex(p.classRangeExpr);
        if (re) {
            [re enumerateMatchesInData:subject range:all usingBlock:^(NSRange header, BOOL *stop) {
                NSRange named = NarrowToName(subject, header, p.classNameExprs);
                if (named.location == NSNotFound) return;   // not a class after all
                NSString *className = [StringFromBytes(subject, named)
                                       stringByTrimmingCharactersInSet:
                                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (!className.length) return;

                // The pattern stops at the opening brace. The body runs to the
                // brace that closes it, which has to be found by counting --
                // that is what openSymbole and closeSymbole are for.
                NSRange body = [FunctionListCatalog bodyRangeFrom:header
                                                           inData:subject
                                                             open:p.classOpenSymbol
                                                            close:p.classCloseSymbol];

                // A class is only worth a row when something was found inside
                // it: Notepad++ lists a class as the parent of its methods and
                // says nothing at all about one that has none.
                NSUInteger before = entries.count;
                if (p.classFunctionExpr.length) {
                    collect(p.classFunctionExpr, p.classFunctionNameExprs, body, className);
                }
                if (entries.count > before) {
                    NppFunctionEntry *entry = [[NppFunctionEntry alloc] init];
                    entry.name = className;
                    entry.line = LineAtByte(subject, header.location);
                    entry.isClass = YES;
                    [entries insertObject:entry atIndex:before];
                }
                [classBodies addObject:[NSValue valueWithRange:body]];
            }];
        }
    }

    if (p.functionExpr.length) {
        // What a class body already covered has been reported under its class,
        // so the plain pass runs over the gaps between them.
        NSUInteger cursor = 0;
        NSMutableArray<NSValue *> *gaps = [NSMutableArray array];
        for (NSValue *v in classBodies) {
            NSRange b = v.rangeValue;
            if (b.location > cursor) {
                [gaps addObject:[NSValue valueWithRange:NSMakeRange(cursor, b.location - cursor)]];
            }
            cursor = MAX(cursor, NSMaxRange(b));
        }
        if (cursor < subject.length) {
            [gaps addObject:[NSValue valueWithRange:
                             NSMakeRange(cursor, subject.length - cursor)]];
        }
        for (NSValue *v in gaps) collect(p.functionExpr, p.functionNameExprs, v.rangeValue, nil);
    }

    [entries sortUsingComparator:^NSComparisonResult(NppFunctionEntry *a, NppFunctionEntry *b) {
        if (a.line == b.line) return NSOrderedSame;
        return a.line < b.line ? NSOrderedAscending : NSOrderedDescending;
    }];
    return entries;
}

/// Where a class body ends: from the opening symbol the pattern stopped at,
/// forward until the symbols balance.
+ (NSRange)bodyRangeFrom:(NSRange)header inData:(NSData *)data
                    open:(NSString *)openExpr close:(NSString *)closeExpr {
    NppRegex *open = openExpr.length ? FunctionListRegex(openExpr) : nil;
    NppRegex *close = closeExpr.length ? FunctionListRegex(closeExpr) : nil;
    if (!open || !close) return header;

    NSUInteger from = NSMaxRange(header);
    if (from >= data.length) return header;
    NSRange rest = NSMakeRange(from, data.length - from);

    NSMutableArray<NSValue *> *opens = [NSMutableArray array];
    NSMutableArray<NSValue *> *closes = [NSMutableArray array];
    [open enumerateMatchesInData:data range:rest usingBlock:^(NSRange m, BOOL *s) {
        [opens addObject:[NSValue valueWithRange:m]];
    }];
    [close enumerateMatchesInData:data range:rest usingBlock:^(NSRange m, BOOL *s) {
        [closes addObject:[NSValue valueWithRange:m]];
    }];

    // The header already consumed one opening symbol, so the count starts at 1.
    NSInteger depth = 1;
    NSUInteger oi = 0;
    for (NSUInteger ci = 0; ci < closes.count; ++ci) {
        NSUInteger closeAt = closes[ci].rangeValue.location;
        while (oi < opens.count && opens[oi].rangeValue.location < closeAt) { depth++; oi++; }
        depth--;
        if (depth == 0) {
            NSUInteger end = NSMaxRange(closes[ci].rangeValue);
            return NSMakeRange(header.location, end - header.location);
        }
    }
    // Unbalanced, which a document being edited often is: take the rest.
    return NSMakeRange(header.location, data.length - header.location);
}

static NSRange NarrowToName(NSData *data, NSRange body, NSArray<NSString *> *exprs) {
    if (!exprs.count) return body;
    NSRange current = body;
    for (NSString *expr in exprs) {
        NppRegex *re = FunctionListRegex(expr);
        if (!re) continue;
        // An empty match is no use as a name, and taking it would drop the
        // entry altogether; what is wanted is the first real one.
        NSRange found = [re firstNonEmptyMatchInData:data range:current];
        // A step that matches nothing means there is no name here at all.
        // parseSubLevel returns an empty string in that case, and the caller
        // decides what to do about it.
        if (found.location == NSNotFound) return NSMakeRange(NSNotFound, 0);
        current = found;
    }
    return current;
}

static NSData *DataWithoutComments(NSData *data, NSString *commentExpr) {
    if (!commentExpr.length) return data;
    NppRegex *re = FunctionListRegex(commentExpr);
    // Upstream ships at least one commentExpr that does not compile at all
    // (fortran77's is cut off mid-pattern); that is not a reason to give up on
    // the rest of the parser.
    if (!re) return data;

    NSMutableData *out = [data mutableCopy];
    uint8_t *bytes = (uint8_t *)out.mutableBytes;
    [re enumerateMatchesInData:data range:NSMakeRange(0, data.length)
                    usingBlock:^(NSRange m, BOOL *stop) {
        for (NSUInteger i = m.location; i < NSMaxRange(m); ++i) {
            // Newlines stay, so line numbers do not shift.
            if (bytes[i] != '\n' && bytes[i] != '\r') bytes[i] = ' ';
        }
    }];
    return out;
}

@end
