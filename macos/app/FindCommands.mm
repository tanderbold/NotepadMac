#import "FindCommands.h"
#include <atomic>
#include <memory>
#import "SettingsCommands.h"
#import "ToolsCommands.h"
#import "BoostFormat.h"
#import "SearchCommands.h"
#import "NppRegex.h"
#import "ScintillaView.h"

@implementation NppFindSpec

+ (instancetype)specFor:(NSString *)what mode:(NppSearchMode)mode options:(NppFindOptions)options {
    NppFindSpec *spec = [[NppFindSpec alloc] init];
    spec.what = what;
    spec.mode = mode;
    spec.options = options;
    return spec;
}


@end

@implementation NppFileSearch {
    BOOL _cancelled;
}

- (BOOL)cancelled {
    @synchronized (self) { return _cancelled; }
}

- (void)cancel {
    @synchronized (self) { _cancelled = YES; }
}

@end

@implementation EditorController (FindCommands)

+ (NSArray<NSString *> *)linesOfText:(NSString *)text {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSCharacterSet *ends = [NSCharacterSet characterSetWithCharactersInString:@"\r\n"];
    NSUInteger start = 0, length = text.length;
    while (YES) {
        NSRange found = [text rangeOfCharacterFromSet:ends options:0
                                                range:NSMakeRange(start, length - start)];
        if (found.location == NSNotFound) {
            [lines addObject:[text substringFromIndex:start]];
            break;
        }
        [lines addObject:[text substringWithRange:NSMakeRange(start, found.location - start)]];
        NSUInteger next = NSMaxRange(found);
        if ([text characterAtIndex:found.location] == '\r' && next < length &&
            [text characterAtIndex:next] == '\n') {
            next++;                                  // CRLF ends one line, not two
        }
        start = next;
        if (start == length) { [lines addObject:@""]; break; }
    }
    return lines;
}

+ (NSString *)singleReportLine:(NSString *)text {
    if (!text || [text rangeOfString:@"\r"].location == NSNotFound) return text ?: @"";
    return [text stringByReplacingOccurrencesOfString:@"\r" withString:@""];
}

#pragma mark - Extended escapes

+ (NSString *)convertExtendedToString:(NSString *)query {
    if (!query.length) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:query.length];

    NSUInteger i = 0, length = query.length;
    while (i < length) {
        unichar c = [query characterAtIndex:i];
        if (c != '\\' || i + 1 >= length) {
            [out appendFormat:@"%C", c];
            ++i;
            continue;
        }

        unichar escape = [query characterAtIndex:i + 1];
        unichar simple = 0;
        switch (escape) {
            case 'r':  simple = '\r'; break;
            case 'n':  simple = '\n'; break;
            case 't':  simple = '\t'; break;
            case '0':  simple = 0;    break;
            case '\\': simple = '\\'; break;
            default:   simple = 0xFFFF; break;
        }
        if (simple != 0xFFFF) {
            [out appendFormat:@"%C", simple];
            i += 2;
            continue;
        }

        // The numeric forms, each with the digit count upstream fixes for it.
        NSInteger digits = 0, base = 0;
        switch (escape) {
            case 'b': digits = 8; base = 2;  break;
            case 'o': digits = 3; base = 8;  break;
            case 'd': digits = 3; base = 10; break;
            case 'x': digits = 2; base = 16; break;
            case 'u': digits = 4; base = 16; break;
            default: break;
        }
        BOOL converted = NO;
        if (digits && i + 2 + digits <= length) {
            NSString *text = [query substringWithRange:NSMakeRange(i + 2, digits)];
            NSInteger value = 0;
            BOOL valid = YES;
            for (NSUInteger d = 0; d < text.length; ++d) {
                unichar ch = [text characterAtIndex:d];
                NSInteger digit = -1;
                if (ch >= '0' && ch <= '9') digit = ch - '0';
                else if (ch >= 'a' && ch <= 'f') digit = ch - 'a' + 10;
                else if (ch >= 'A' && ch <= 'F') digit = ch - 'A' + 10;
                if (digit < 0 || digit >= base) { valid = NO; break; }
                value = value * base + digit;
            }
            if (valid) {
                [out appendFormat:@"%C", (unichar)value];
                i += 2 + digits;
                converted = YES;
            }
        }
        if (converted) continue;

        // Not a sequence after all: upstream keeps the backslash and the letter.
        [out appendFormat:@"\\%C", escape];
        i += 2;
    }
    return out;
}

#pragma mark - Pattern

/// Turns the spec into one PCRE pattern, so normal, extended and regular
/// expression searching all go down the same path.
- (BOOL)patternIsValid:(NppFindSpec *)spec {
    return !spec.what.length || [self regexFor:spec] != nil;
}

- (nullable NppRegex *)regexFor:(NppFindSpec *)spec {
    if (!spec.what.length) return nil;

    NSString *body;
    if (spec.mode == NppSearchRegex) {
        body = spec.what;
    } else {
        NSString *literal = spec.mode == NppSearchExtended
            ? [EditorController convertExtendedToString:spec.what]
            : spec.what;
        // \Q...\E would be simpler but cannot carry a \E in the text, so every
        // character that means something to the engine is escaped instead.
        NSMutableString *quoted = [NSMutableString stringWithCapacity:literal.length * 2];
        NSCharacterSet *meta = [NSCharacterSet characterSetWithCharactersInString:
                                @"\\^$.|?*+()[]{}"];
        for (NSUInteger i = 0; i < literal.length; ++i) {
            unichar c = [literal characterAtIndex:i];
            if ([meta characterIsMember:c]) [quoted appendString:@"\\"];
            [quoted appendFormat:@"%C", c];
        }
        body = quoted;
    }

    // Whole word is for the literal modes; in a regular expression it would
    // rewrite what the user wrote, and Notepad++ greys it out there.
    if ((spec.options & NppFindWholeWord) && spec.mode != NppSearchRegex) {
        body = [NSString stringWithFormat:@"\\b(?:%@)\\b", body];
    }
    // What a pattern says with (*UTF), (*UCP) and the like has to stay at
    // the very start, ahead of the flags put in here.
    NSString *verbs = @"";
    NSRange leading = [body rangeOfString:@"^(?:\\(\\*[^)]*\\))+" options:NSRegularExpressionSearch];
    if (leading.location == 0 && spec.mode == NppSearchRegex) {
        verbs = [body substringToIndex:leading.length];
        body = [body substringFromIndex:leading.length];
    }
    NSMutableString *flags = [NSMutableString string];
    if (!(spec.options & NppFindMatchCase)) [flags appendString:@"i"];
    // Whether '.' may cross a line ending is the dialog's box, off by
    // default as on Windows; the engine's own default is overridden here.
    [flags appendString:(spec.options & NppFindDotMatchesNewline) ? @"s" : @"-s"];
    body = [NSString stringWithFormat:@"%@(?%@)%@", verbs, flags, body];
    return [NppRegex regexWithPattern:body];
}

/// The part of the document a search may look at.
- (NSRange)searchRangeFor:(NppFindSpec *)spec inData:(NSData *)data {
    if (!(spec.options & NppFindInSelection)) return NSMakeRange(0, data.length);
    long from = [self.sci message:SCI_GETSELECTIONSTART];
    long to = [self.sci message:SCI_GETSELECTIONEND];
    if (to <= from) return NSMakeRange(0, data.length);
    return NSMakeRange((NSUInteger)from, (NSUInteger)(to - from));
}

- (NSData *)documentBytes {
    return [[self documentText] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
}

#pragma mark - Matches

- (NSArray<NSValue *> *)rangesOfMatches:(NppFindSpec *)spec {
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return @[];
    NSData *data = [self documentBytes];
    NSMutableArray *out = [NSMutableArray array];
    [regex enumerateMatchesInData:data range:[self searchRangeFor:spec inData:data]
                       usingBlock:^(NSRange m, BOOL *stop) {
        [out addObject:[NSValue valueWithRange:m]];
    }];
    return out;
}

- (NSUInteger)countMatches:(NppFindSpec *)spec {
    return [self rangesOfMatches:spec].count;
}

- (BOOL)findNext:(NppFindSpec *)spec {
    NSArray<NSValue *> *matches = [self rangesOfMatches:spec];
    if (!matches.count) return NO;

    ScintillaView *sci = self.sci;
    BOOL backward = (spec.options & NppFindBackward) != 0;
    NSUInteger selStart = (NSUInteger)[sci message:SCI_GETSELECTIONSTART];
    NSUInteger selEnd = (NSUInteger)[sci message:SCI_GETSELECTIONEND];
    NSUInteger caret = backward ? selStart : (NSUInteger)[sci message:SCI_GETCURRENTPOS];
    // The match that is already selected is not the next one. Without this
    // an empty match - '$', '\b', a lookaround - sits at the caret and is
    // found again and again.
    NSRange selection = NSMakeRange(selStart, selEnd - selStart);

    NSValue *chosen = nil;
    if (backward) {
        for (NSValue *v in matches) {
            if (NSMaxRange(v.rangeValue) <= caret && !NSEqualRanges(v.rangeValue, selection)) chosen = v;
        }
        if (!chosen && (spec.options & NppFindWrap)) chosen = matches.lastObject;
    } else {
        for (NSValue *v in matches) {
            if (v.rangeValue.location >= caret && !NSEqualRanges(v.rangeValue, selection)) { chosen = v; break; }
        }
        if (!chosen && (spec.options & NppFindWrap)) chosen = matches.firstObject;
    }
    if (!chosen) return NO;

    NSRange found = chosen.rangeValue;
    [sci message:SCI_SETSEL wParam:(uptr_t)found.location lParam:(sptr_t)NSMaxRange(found)];
    return YES;
}

- (NSUInteger)markAll:(NppFindSpec *)spec { return [self markAll:spec purge:YES]; }

- (NSUInteger)markAll:(NppFindSpec *)spec purge:(BOOL)purge {
    NSArray<NSValue *> *matches = [self rangesOfMatches:spec];
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_FIND_MARK_INDICATOR];
    // Without "Purge for each search" the marks of earlier searches stay.
    if (purge) [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:(sptr_t)[sci message:SCI_GETLENGTH]];
    for (NSValue *v in matches) {
        NSRange r = v.rangeValue;
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)r.location lParam:(sptr_t)r.length];
    }
    return matches.count;
}

#pragma mark - Replacing

/// Builds the replacement for one match. Outside regular expressions the
/// text is taken as it is, after Extended mode has had its say. In a regular
/// expression it is read by Boost's formatter, as Notepad++ reads it.
- (NSString *)replacementFor:(NppFindSpec *)spec
                      groups:(NSArray<NSValue *> *)groups
                        data:(NSData *)data {
    return [self replacementFor:spec groups:groups data:data regex:nil
                     prefixFrom:0 suffixTo:data.length];
}

- (NSString *)replacementFor:(NppFindSpec *)spec
                      groups:(NSArray<NSValue *> *)groups
                        data:(NSData *)data
                       regex:(nullable NppRegex *)regex
                  prefixFrom:(NSUInteger)prefixFrom
                    suffixTo:(NSUInteger)suffixTo {
    NSString *template_ = spec.replacement ?: @"";
    if (spec.mode == NppSearchExtended) {
        template_ = [EditorController convertExtendedToString:template_];
    }
    if (spec.mode != NppSearchRegex) return template_;

    // Boost's formatter in format_all mode, as SubstituteByPosition calls it.
    NSString *(^bytes)(NSUInteger, NSUInteger) = ^NSString *(NSUInteger from, NSUInteger to) {
        if (from == NSNotFound || to < from || to > data.length) return @"";
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(from, to - from)]
                                     encoding:NSUTF8StringEncoding] ?: @"";
    };
    NSMutableArray *texts = [NSMutableArray arrayWithCapacity:groups.count];
    NSInteger lastClosed = -1;
    NSUInteger lastEnd = 0;
    for (NSUInteger g = 0; g < groups.count; ++g) {
        NSRange r = groups[g].rangeValue;
        if (r.location == NSNotFound) { [texts addObject:[NSNull null]]; continue; }
        [texts addObject:bytes(r.location, NSMaxRange(r))];
        // The group that closed last: the one ending furthest on, the outer
        // of two that end together.
        if (g > 0 && (lastClosed < 0 || NSMaxRange(r) > lastEnd)) { lastClosed = (NSInteger)g; lastEnd = NSMaxRange(r); }
    }
    NSRange whole = groups.firstObject.rangeValue;
    NSString *prefix = bytes(MIN(prefixFrom, whole.location), whole.location);
    NSString *suffix = bytes(NSMaxRange(whole), MAX(suffixTo, NSMaxRange(whole)));
    NSInteger (^named)(NSString *) = nil;
    if (regex) named = ^NSInteger(NSString *name) { return [regex groupNumberForName:name]; };
    return NppBoostFormat(template_, texts, prefix, suffix, lastClosed, named);
}

- (NSUInteger)replaceAll:(NppFindSpec *)spec {
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    NSData *data = [self documentBytes];
    NSRange scope = [self searchRangeFor:spec inData:data];

    // Collected first and applied from the end, so replacing does not move the
    // matches still to be replaced.
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    __block NSUInteger previousEnd = scope.location;
    [regex enumerateMatchesWithGroupsInData:data range:scope
                                 usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
        [ranges addObject:groups.firstObject];
        [texts addObject:[self replacementFor:spec groups:groups data:data regex:regex
                                   prefixFrom:previousEnd suffixTo:NSMaxRange(scope)]];
        previousEnd = NSMaxRange(groups.firstObject.rangeValue);
    }];
    if (!ranges.count) return 0;

    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; --i) {
        NSRange r = ranges[(NSUInteger)i].rangeValue;
        [sci message:SCI_SETTARGETSTART wParam:(uptr_t)r.location];
        [sci message:SCI_SETTARGETEND wParam:(uptr_t)NSMaxRange(r)];
        // By length: a replacement holding \0 must not end at it.
        NSString *text = texts[(NSUInteger)i];
        [sci setStringProperty:SCI_REPLACETARGET
                     parameter:(long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] value:text];
    }
    [sci message:SCI_ENDUNDOACTION];
    return ranges.count;
}

- (BOOL)replaceCurrentThenFindNext:(NppFindSpec *)spec {
    ScintillaView *sci = self.sci;
    long from = [sci message:SCI_GETSELECTIONSTART];
    long to = [sci message:SCI_GETSELECTIONEND];

    if (to > from) {
        // Replace only if what is selected is itself a match, so pressing
        // Replace on an arbitrary selection cannot damage it.
        NppRegex *regex = [self regexFor:spec];
        NSData *data = [self documentBytes];
        __block BOOL exact = NO;
        __block NSArray<NSValue *> *matched = nil;
        // Matched over the rest of the document, not the selection alone: a
        // pattern that looks past its match - foo(?=bar) - has to be able to.
        [regex enumerateMatchesWithGroupsInData:data
                                          range:NSMakeRange((NSUInteger)from, data.length - (NSUInteger)from)
                                     usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
            NSRange r = groups.firstObject.rangeValue;
            if (r.location == (NSUInteger)from && NSMaxRange(r) == (NSUInteger)to) {
                exact = YES;
                matched = groups;
            }
            *stop = YES;
        }];
        if (exact) {
            NSString *text = [self replacementFor:spec groups:matched data:data regex:regex
                                       prefixFrom:(NSUInteger)from suffixTo:data.length];
            [sci message:SCI_SETTARGETSTART wParam:(uptr_t)from];
            [sci message:SCI_SETTARGETEND wParam:(uptr_t)to];
            [sci setStringProperty:SCI_REPLACETARGET
                         parameter:(long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] value:text];
            [sci message:SCI_GOTOPOS wParam:(uptr_t)(from + (long)[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding])];
            // Searching > "Replace: Don't move to the following occurrence": the caret
            // stays after the replacement (FindReplaceDlg::processReplace,
            // _replaceStopsWithoutFindingNext).
            if ([NppPreferences shared].replaceStaysOnOccurrence) return YES;
        }
    }
    return [self findNext:spec];
}



#pragma mark - Across files

/// The filter split into what to take, what to leave out, and which folders
/// to stay out of: "*.cpp *.h !*.min.js !\\build", as Notepad++ reads it.
static void SplitFilters(NSString *filters, NSMutableArray *include, NSMutableArray *exclude,
                         NSMutableArray *excludeFolders) {
    NSString *trimmed = [(filters ?: @"") stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *pattern in [trimmed componentsSeparatedByCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@" ,;"]]) {
        if (!pattern.length) continue;
        if ([pattern hasPrefix:@"!\\"] || [pattern hasPrefix:@"!/"]) {
            if (pattern.length > 2) [excludeFolders addObject:[pattern substringFromIndex:2]];
        } else if ([pattern hasPrefix:@"!"]) {
            if (pattern.length > 1) [exclude addObject:[pattern substringFromIndex:1]];
        } else {
            [include addObject:pattern];
        }
    }
}

static BOOL GlobMatches(NSString *pattern, NSString *name) {
    // Notepad++ takes shell patterns here, and so does this.
    return [[NSPredicate predicateWithFormat:@"SELF LIKE[c] %@", pattern] evaluateWithObject:name];
}

+ (BOOL)name:(NSString *)name matchesFilters:(NSString *)filters {
    NSMutableArray *include = [NSMutableArray array], *exclude = [NSMutableArray array],
                   *folders = [NSMutableArray array];
    SplitFilters(filters, include, exclude, folders);
    for (NSString *pattern in exclude) {
        if (GlobMatches(pattern, name)) return NO;
    }
    if (!include.count) return YES;                  // nothing asked for means every file
    for (NSString *pattern in include) {
        if (GlobMatches(pattern, name)) return YES;
    }
    return NO;
}

+ (BOOL)relativePath:(NSString *)relative isInFolderExcludedByFilters:(NSString *)filters {
    NSMutableArray *include = [NSMutableArray array], *exclude = [NSMutableArray array],
                   *folders = [NSMutableArray array];
    SplitFilters(filters, include, exclude, folders);
    if (!folders.count) return NO;
    NSArray<NSString *> *components = relative.pathComponents;
    for (NSUInteger i = 0; i + 1 < components.count; ++i) {
        for (NSString *pattern in folders) {
            if (GlobMatches(pattern, components[i])) return YES;
        }
    }
    return NO;
}

/// Walks the folder, handing each file that passes the filter to `visit`.
- (void)walkFolder:(NSString *)folder
           filters:(NSString *)filters
         recursive:(BOOL)recursive
     includeHidden:(BOOL)includeHidden
             visit:(void (^)(NSString *path, NSString *contents))visit {
    [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
              search:nil visit:^(NSString *path, NSString *contents, NSUInteger scanned) {
        visit(path, contents);
    }];
}

/// The same walk, stoppable, and counting how many files it has been through so
/// the caller can say how far along it is.
- (void)walkFolder:(NSString *)folder
           filters:(NSString *)filters
         recursive:(BOOL)recursive
     includeHidden:(BOOL)includeHidden
            search:(NppFileSearch *)search
             visit:(void (^)(NSString *path, NSString *contents, NSUInteger scanned))visit {
    NSFileManager *files = [NSFileManager defaultManager];
    NSDirectoryEnumerator *walker = [files enumeratorAtPath:folder];
    NSUInteger scanned = 0;
    for (NSString *relative in walker) {
        if (search.cancelled) return;
        if (!recursive && relative.pathComponents.count > 1) continue;

        BOOL hidden = NO;
        for (NSString *component in relative.pathComponents) {
            if ([component hasPrefix:@"."]) { hidden = YES; break; }
        }
        if (hidden && !includeHidden) continue;

        NSString *full = [folder stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        if (![files fileExistsAtPath:full isDirectory:&isDirectory]) continue;
        if (isDirectory) {
            // A folder the filter leaves out is not walked at all; that, not
            // the filtering of its files one by one, is what makes
            // "!\node_modules" worth having.
            if ([EditorController relativePath:[relative stringByAppendingPathComponent:@"x"]
                       isInFolderExcludedByFilters:filters]) [walker skipDescendants];
            continue;
        }
        if ([EditorController relativePath:relative isInFolderExcludedByFilters:filters]) continue;
        if (![EditorController name:relative.lastPathComponent matchesFilters:filters]) continue;

        NSString *contents = [EditorController textOfFileAtPath:full encoding:NULL hasBOM:NULL];
        if (!contents) continue;                     // binary
        visit(full, contents, ++scanned);
    }
}

- (NSUInteger)findInFiles:(NppFindSpec *)spec
                   folder:(NSString *)folder
                  filters:(NSString *)filters
                recursive:(BOOL)recursive
            includeHidden:(BOOL)includeHidden
                   report:(NSString **)report {
    if (!spec.what.length || !folder.length) return 0;
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    NSMutableString *text = [NSMutableString stringWithFormat:@"Search \"%@\" in %@\n\n",
                             spec.what, folder];
    __block NSUInteger hits = 0, matchedFiles = 0;

    [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
               visit:^(NSString *path, NSString *contents) {
        NSArray *lines = [EditorController linesOfText:contents];
        NSMutableString *block = [NSMutableString string];
        NSUInteger inFile = 0;
        for (NSUInteger i = 0; i < lines.count; ++i) {
            NSData *line = [lines[i] dataUsingEncoding:NSUTF8StringEncoding];
            if (!line.length) continue;
            if ([regex firstMatchInData:line range:NSMakeRange(0, line.length)].location == NSNotFound) {
                continue;
            }
            inFile++;
            [block appendFormat:@"\tLine %lu: %@\n", (unsigned long)(i + 1),
                                [EditorController singleReportLine:lines[i]]];
        }
        if (!inFile) return;
        matchedFiles++;
        hits += inFile;
        [text appendFormat:@"%@ (%lu hit%@)\n%@\n", path, (unsigned long)inFile,
                           inFile == 1 ? @"" : @"s", block];
    }];

    [text appendFormat:@"\n%lu hit%@ in %lu file%@\n", (unsigned long)hits,
                       hits == 1 ? @"" : @"s", (unsigned long)matchedFiles,
                       matchedFiles == 1 ? @"" : @"s"];
    if (report) *report = text;
    return hits;
}

/// Rewrites one file, returning how many matches went with it. Shared by the
/// blocking Replace in Files and the one that runs in the background.
- (NSUInteger)replaceEveryMatch:(NppFindSpec *)spec
                          regex:(NppRegex *)regex
                   inFileAtPath:(NSString *)path
                       contents:(NSString *)contents
                    cancelledBy:(NppFileSearch *)search {
    NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];
    if (!data.length) return 0;

    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    __block NSUInteger previousEnd = 0;
    [regex enumerateMatchesWithGroupsInData:data range:NSMakeRange(0, data.length)
                                 usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
        if (search.cancelled) { *stop = YES; return; }
        [ranges addObject:groups.firstObject];
        [texts addObject:[self replacementFor:spec groups:groups data:data regex:regex
                                   prefixFrom:previousEnd suffixTo:data.length]];
        previousEnd = NSMaxRange(groups.firstObject.rangeValue);
    }];
    if (!ranges.count || search.cancelled) return 0;

    // Applied from the end, so a replacement cannot move the ones still to
    // be made.
    NSMutableData *updated = [data mutableCopy];
    for (NSInteger i = (NSInteger)ranges.count - 1; i >= 0; --i) {
        NSRange range = ranges[(NSUInteger)i].rangeValue;
        NSData *piece = [texts[(NSUInteger)i] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        [updated replaceBytesInRange:range withBytes:piece.bytes length:piece.length];
    }
    // Back in the encoding the file was read in, with its BOM if it had one.
    NSStringEncoding encoding = NSUTF8StringEncoding;
    BOOL bom = NO;
    [EditorController textOfFileAtPath:path encoding:&encoding hasBOM:&bom];
    NSData *written = updated;
    if (encoding != NSUTF8StringEncoding || bom) {
        NSString *text = [[NSString alloc] initWithData:updated encoding:NSUTF8StringEncoding];
        written = text && [text canBeConvertedToEncoding:encoding] ? [EditorController dataForText:text encoding:encoding hasBOM:bom] : nil;
        if (!written.length) return 0;               // a replacement the encoding cannot hold leaves the file alone
    }
    return [written writeToFile:path atomically:YES] ? ranges.count : 0;
}

- (NSUInteger)replaceInFiles:(NppFindSpec *)spec
                      folder:(NSString *)folder
                     filters:(NSString *)filters
                   recursive:(BOOL)recursive
               includeHidden:(BOOL)includeHidden
                changedFiles:(NSUInteger *)changedFiles {
    if (!spec.what.length || !folder.length) return 0;
    NppRegex *regex = [self regexFor:spec];
    if (!regex) return 0;

    __block NSUInteger replaced = 0, touched = 0;
    [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
               visit:^(NSString *path, NSString *contents) {
        NSUInteger inFile = [self replaceEveryMatch:spec regex:regex inFileAtPath:path
                                           contents:contents cancelledBy:nil];
        if (inFile) { replaced += inFile; touched++; }
    }];

    if (changedFiles) *changedFiles = touched;
    return replaced;
}

#pragma mark - Across files, without holding on to the window

/// The lines of one file that match, as the report writes them; how many.
- (NSUInteger)appendMatchesOf:(NppRegex *)regex inFile:(NSString *)path contents:(NSString *)contents
                        search:(NppFileSearch *)search to:(NSMutableString *)report {
    NSArray<NSString *> *lines = [EditorController linesOfText:contents];
    NSMutableString *block = [NSMutableString string];
    NSUInteger inFile = 0;
    for (NSUInteger i = 0; i < lines.count; ++i) {
        if (search.cancelled) return 0;
        NSData *line = [lines[i] dataUsingEncoding:NSUTF8StringEncoding];
        if (!line.length) continue;
        NSRange found = [regex firstMatchInData:line range:NSMakeRange(0, line.length)];
        if (found.location == NSNotFound) continue;
        inFile++;
        // A file with CR or mixed line ends leaves carriage returns in
        // what was read; written out as they are they would each start
        // a fresh line in the report, and every line below would then
        // stand for something other than what it says.
        [block appendFormat:@"\tLine %lu: %@\n", (unsigned long)(i + 1),
                            [EditorController singleReportLine:lines[i]]];
    }
    if (inFile) {
        [report appendFormat:@"%@ (%lu hit%@)\n%@\n", path, (unsigned long)inFile,
                             inFile == 1 ? @"" : @"s", block];
    }
    return inFile;
}

/// Runs a search over files handed out by `walk`, in the background.
- (NppFileSearch *)searchInBackground:(NppFindSpec *)spec
                                title:(NSString *)title
                                 walk:(void (^)(NppFileSearch *, void (^)(NSString *, NSString *, NSUInteger)))walk
                             progress:(void (^)(NSUInteger, NSUInteger, NSString *))progress
                           completion:(void (^)(NSUInteger, NSString *, BOOL))completion {
    NppFileSearch *search = [[NppFileSearch alloc] init];
    NppRegex *regex = [self regexFor:spec];
    if (!spec.what.length || !regex) {
        // After the caller has taken the search back: called at once, the
        // completion's "search over" came before the caller stored the search
        // as running, and the Find window believed one ran for good (SEARCH-063).
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(0, @"", NO); });
        return search;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *report = [NSMutableString stringWithFormat:@"Search \"%@\" (%@)\n\n", spec.what, title];
        __block NSUInteger hits = 0, matchedFiles = 0;
        // Progress at most four times a second, and never a second one queued
        // behind the first: sent for every file with a hit, each with the
        // whole report so far, the main thread spent the search re-rendering
        // the results and the window (Stop included) froze (SEARCH-067/068).
        // Upstream's FindInFiles progress window is refreshed the same way,
        // on a timer, not per file.
        __block CFAbsoluteTime lastPost = 0;
        std::shared_ptr<std::atomic<bool>> pending = std::make_shared<std::atomic<bool>>(false);
        walk(search, ^(NSString *path, NSString *contents, NSUInteger scanned) {
            NSUInteger inFile = [self appendMatchesOf:regex inFile:path contents:contents search:search to:report];
            if (inFile) { matchedFiles++; hits += inFile; }
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (progress && now - lastPost >= 0.25 && !pending->exchange(true)) {
                lastPost = now;
                NSString *snapshot = [report copy];
                NSUInteger hitsSoFar = hits;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!search.cancelled) progress(scanned, hitsSoFar, snapshot);
                    pending->store(false);
                });
            }
        });
        BOOL stopped = search.cancelled;
        [report appendFormat:@"\n%lu hit%@ in %lu file%@%@\n", (unsigned long)hits,
                             hits == 1 ? @"" : @"s", (unsigned long)matchedFiles,
                             matchedFiles == 1 ? @"" : @"s", stopped ? @" - search stopped" : @""];
        NSString *finished = [report copy];
        NSUInteger total = hits;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(total, finished, stopped);
        });
    });
    return search;
}

- (NppFileSearch *)findInFilesInBackground:(NppFindSpec *)spec
                                    folder:(NSString *)folder
                                   filters:(NSString *)filters
                                 recursive:(BOOL)recursive
                             includeHidden:(BOOL)includeHidden
                                  progress:(void (^)(NSUInteger, NSUInteger, NSString *))progress
                                completion:(void (^)(NSUInteger, NSString *, BOOL))completion {
    if (!folder.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(0, @"", NO); });
        return [[NppFileSearch alloc] init];
    }
    return [self searchInBackground:spec title:folder
                               walk:^(NppFileSearch *search, void (^visit)(NSString *, NSString *, NSUInteger)) {
        [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
                  search:search visit:visit];
    } progress:progress completion:completion];
}

- (NppFileSearch *)findInFilesInBackground:(NppFindSpec *)spec
                                     paths:(NSArray<NSString *> *)paths
                                     title:(NSString *)title
                                   filters:(NSString *)filters
                                  progress:(void (^)(NSUInteger, NSUInteger, NSString *))progress
                                completion:(void (^)(NSUInteger, NSString *, BOOL))completion {
    // A file listed twice - in two folders of a project, in two projects -
    // is searched once.
    NSArray *files = [[NSOrderedSet orderedSetWithArray:paths] array];
    return [self searchInBackground:spec title:title
                               walk:^(NppFileSearch *search, void (^visit)(NSString *, NSString *, NSUInteger)) {
        NSUInteger scanned = 0;
        for (NSString *path in files) {
            if (search.cancelled) return;
            if (![EditorController name:path.lastPathComponent matchesFilters:filters]) continue;
            NSString *contents = [EditorController textOfFileAtPath:path encoding:NULL hasBOM:NULL];
            if (!contents) continue;
            visit(path, contents, ++scanned);
        }
    } progress:progress completion:completion];
}

- (NppFileSearch *)replaceInBackground:(NppFindSpec *)spec
                                  walk:(void (^)(NppFileSearch *, void (^)(NSString *, NSString *, NSUInteger)))walk
                              progress:(void (^)(NSUInteger, NSUInteger))progress
                            completion:(void (^)(NSUInteger, NSUInteger, BOOL))completion {
    NppFileSearch *search = [[NppFileSearch alloc] init];
    NppRegex *regex = [self regexFor:spec];
    if (!spec.what.length || !regex) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(0, 0, NO); });
        return search;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __block NSUInteger replaced = 0, touched = 0;
        __block CFAbsoluteTime lastPost = 0;
        walk(search, ^(NSString *path, NSString *contents, NSUInteger scanned) {
            NSUInteger inFile = [self replaceEveryMatch:spec regex:regex inFileAtPath:path
                                               contents:contents cancelledBy:search];
            if (inFile) { replaced += inFile; touched++; }
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (progress && now - lastPost >= 0.25) {
                lastPost = now;
                NSUInteger replacedSoFar = replaced;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!search.cancelled) progress(scanned, replacedSoFar);
                });
            }
        });
        BOOL stopped = search.cancelled;
        NSUInteger total = replaced, files = touched;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(total, files, stopped);
        });
    });
    return search;
}

- (NppFileSearch *)replaceInFilesInBackground:(NppFindSpec *)spec
                                       folder:(NSString *)folder
                                      filters:(NSString *)filters
                                    recursive:(BOOL)recursive
                                includeHidden:(BOOL)includeHidden
                                     progress:(void (^)(NSUInteger, NSUInteger))progress
                                   completion:(void (^)(NSUInteger, NSUInteger, BOOL))completion {
    if (!folder.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(0, 0, NO); });
        return [[NppFileSearch alloc] init];
    }
    return [self replaceInBackground:spec walk:^(NppFileSearch *search, void (^visit)(NSString *, NSString *, NSUInteger)) {
        [self walkFolder:folder filters:filters recursive:recursive includeHidden:includeHidden
                  search:search visit:visit];
    } progress:progress completion:completion];
}

- (NppFileSearch *)replaceInFilesInBackground:(NppFindSpec *)spec
                                        paths:(NSArray<NSString *> *)paths
                                      filters:(NSString *)filters
                                     progress:(void (^)(NSUInteger, NSUInteger))progress
                                   completion:(void (^)(NSUInteger, NSUInteger, BOOL))completion {
    NSArray *files = [[NSOrderedSet orderedSetWithArray:paths] array];
    return [self replaceInBackground:spec walk:^(NppFileSearch *search, void (^visit)(NSString *, NSString *, NSUInteger)) {
        NSUInteger scanned = 0;
        for (NSString *path in files) {
            if (search.cancelled) return;
            if (![EditorController name:path.lastPathComponent matchesFilters:filters]) continue;
            NSString *contents = [EditorController textOfFileAtPath:path encoding:NULL hasBOM:NULL];
            if (!contents) continue;
            visit(path, contents, ++scanned);
        }
    } progress:progress completion:completion];
}

#pragma mark - Every open document

/// The hit lines of a document, each line once however many matches it has,
/// as Notepad++'s Find All lists them.
- (NSString *)reportLinesForMatches:(NSArray<NSValue *> *)matches {
    ScintillaView *sci = self.sci;
    NSData *bytes = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableString *block = [NSMutableString string];
    long lastLine = -1;
    for (NSValue *match in matches) {
        long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)match.rangeValue.location];
        if (line == lastLine) continue;
        lastLine = line;
        long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
        NSString *text = (end > start && (NSUInteger)end <= bytes.length)
            ? [[NSString alloc] initWithData:[bytes subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]
                                    encoding:NSUTF8StringEncoding] : @"";
        [block appendFormat:@"\tLine %ld: %@\n", line + 1, [EditorController singleReportLine:text ?: @""]];
    }
    return block;
}

- (NSString *)findAllReport:(NppFindSpec *)spec hits:(NSUInteger *)hits {
    NSArray<NSValue *> *matches = [self rangesOfMatches:spec];
    NSString *path = self.currentDocument.path ?: self.currentDocument.displayName;
    NSMutableString *report = [NSMutableString stringWithFormat:@"Search \"%@\" in %@\n\n", spec.what, path];
    [report appendString:[self reportLinesForMatches:matches]];
    [report appendFormat:@"\n%lu hit%@\n", (unsigned long)matches.count, matches.count == 1 ? @"" : @"s"];
    if (hits) *hits = matches.count;
    return report;
}

/// Runs `body` with each open document in front in turn - not the results
/// tab - and puts back the one that was in front.
- (void)forEachOpenDocument:(void (^)(NppDocument *doc))body {
    NppDocument *front = self.currentDocument;
    // A search is not a visit: the Ctrl+Tab order and Recent Window stay the user's.
    NSArray<NppDocument *> *recent = [self documentsInRecentOrder];
    NppDocument *previous = [self previousTab];
    NSArray<NppDocument *> *docs = [self.documents copy];
    for (NppDocument *doc in docs) {
        if (doc.isSearchResults) continue;
        NSUInteger index = [self.documents indexOfObjectIdenticalTo:doc];
        if (index == NSNotFound) continue;
        [self selectDocumentAtIndex:(NSInteger)index];
        body(doc);
    }
    NSUInteger back = front ? [self.documents indexOfObjectIdenticalTo:front] : NSNotFound;
    if (back != NSNotFound) [self selectDocumentAtIndex:(NSInteger)back];
    [self setValue:[recent mutableCopy] forKey:@"mru"];
    if (previous) [self rememberPreviousTab:previous];
}

- (NSString *)findAllInOpenDocuments:(NppFindSpec *)spec hits:(NSUInteger *)hits {
    NppFindSpec *whole = [NppFindSpec specFor:spec.what mode:spec.mode options:spec.options & ~NppFindInSelection];
    __block NSUInteger total = 0, files = 0, searched = 0;
    NSMutableString *body = [NSMutableString string];
    [self forEachOpenDocument:^(NppDocument *doc) {
        searched++;
        NSArray<NSValue *> *matches = [self rangesOfMatches:whole];
        if (!matches.count) return;
        total += matches.count;
        files++;
        [body appendFormat:@"%@ (%lu hit%@)\n%@", doc.path ?: doc.displayName, (unsigned long)matches.count,
                           matches.count == 1 ? @"" : @"s", [self reportLinesForMatches:matches]];
    }];
    if (hits) *hits = total;
    return [NSString stringWithFormat:@"Search \"%@\" (%lu hit%@ in %lu file%@ of %lu searched)\n%@",
            spec.what, (unsigned long)total, total == 1 ? @"" : @"s", (unsigned long)files,
            files == 1 ? @"" : @"s", (unsigned long)searched, body];
}

- (NSUInteger)replaceAllInOpenDocuments:(NppFindSpec *)spec {
    NppFindSpec *whole = [NppFindSpec specFor:spec.what mode:spec.mode options:spec.options & ~NppFindInSelection];
    whole.replacement = spec.replacement;
    __block NSUInteger total = 0;
    [self forEachOpenDocument:^(NppDocument *doc) {
        total += [self replaceAll:whole];
    }];
    return total;
}

@end
