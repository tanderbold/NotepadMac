#import "TypingCommands.h"
#import <objc/runtime.h>
#import "ApiCatalog.h"
#import "SettingsCommands.h"
#import "AdvancedEditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import "ToolsCommands.h"
#import "SciLexer.h"

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

@implementation EditorController (TypingCommands)

#pragma mark - Typing

/// The word being typed immediately before the caret.
- (NSString *)prefixBeforeCaret {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
    if (pos <= start) return @"";
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)pos > data.length) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(pos - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

/// Upstream matches case unless the language's API file says so, and in
/// plain text, where there is no file, it respects case (getWordArray).
- (BOOL)completionIgnoresCase {
    NSString *language = self.currentDocument.language.name ?: @"normal";
    if ([[ApiCatalog sharedCatalog] entriesForLanguage:language].count) {
        return [[ApiCatalog sharedCatalog] ignoreCaseForLanguage:language];
    }
    return ![language isEqualToString:@"normal"];
}

/// The language's names: its API file, or failing that its lexer keywords.
- (NSArray<NSString *> *)functionNames {
    NSString *language = self.currentDocument.language.name ?: @"";
    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    for (NppApiEntry *entry in [[ApiCatalog sharedCatalog] entriesForLanguage:language]) [names addObject:entry.name];
    if (!names.count) {
        for (NSString *set in self.currentDocument.language.keywordSets.allValues) {
            for (NSString *w in [set componentsSeparatedByString:@" "]) if (w.length) [names addObject:w];
        }
    }
    return names.array;
}

static BOOL StartsWith(NSString *word, NSString *prefix, BOOL ignoreCase) {
    if (word.length < prefix.length) return NO;
    return [word rangeOfString:prefix options:NSAnchoredSearch | (ignoreCase ? NSCaseInsensitiveSearch : 0)].location == 0;
}

/// Words of the document that begin with `prefix` and go on past it, less
/// `exclude` (the word being typed), as getWordArray finds them.
- (NSArray<NSString *> *)documentWordsWithPrefix:(NSString *)prefix excluding:(nullable NSString *)exclude {
    static NSCharacterSet *separators;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        separators = [NSCharacterSet characterSetWithCharactersInString:@" \t\n\r.,;:\"(){}=<>'+!?[]"];
    });
    BOOL ignoreCase = [self completionIgnoresCase];
    BOOL ignoreNumbers = [NppPreferences shared].autoCompleteIgnoreNumbers;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    for (NSString *w in [([self.sci string] ?: @"") componentsSeparatedByCharactersInSet:separators]) {
        if (w.length <= prefix.length || !StartsWith(w, prefix, ignoreCase)) continue;
        if (exclude && [w isEqualToString:exclude]) continue;
        if (ignoreNumbers && [w rangeOfCharacterFromSet:nonDigits].location == NSNotFound) continue;
        [found addObject:w];
    }
    return found.array;
}

- (NSArray<NSString *> *)completionCandidatesForPrefix:(NSString *)prefix {
    NppPreferences *p = [NppPreferences shared];
    if (!prefix.length) return @[];
    BOOL ignoreCase = [self completionIgnoresCase];
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    if (p.autoCompleteSource == NppCompletionWords || p.autoCompleteSource == NppCompletionBoth) {
        [found addObjectsFromArray:[self documentWordsWithPrefix:prefix excluding:nil]];
    }
    if (p.autoCompleteSource == NppCompletionFunctions || p.autoCompleteSource == NppCompletionBoth) {
        for (NSString *name in [self functionNames]) {
            if (name.length > prefix.length && StartsWith(name, prefix, ignoreCase)) [found addObject:name];
        }
    }
    return [self sortedForCompletion:found.array];
}

- (NSArray<NSString *> *)sortedForCompletion:(NSArray<NSString *> *)words {
    // Scintilla looks the typed text up in the list, so it has to be in the
    // order its own comparison expects.
    if ([self completionIgnoresCase]) {
        return [words sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            NSComparisonResult r = [a caseInsensitiveCompare:b];
            return r != NSOrderedSame ? r : [a compare:b options:NSLiteralSearch];
        }];
    }
    return [words sortedArrayUsingSelector:@selector(compare:)];
}

static const char kLastCompletionKey = 0;

- (NSArray<NSString *> *)lastCompletionList { return objc_getAssociatedObject(self, &kLastCompletionKey); }

- (BOOL)showCompletion:(NppCompletionKind)kind autoInsert:(BOOL)autoInsert {
    ScintillaView *sci = self.sci;
    long caret = [sci message:SCI_GETCURRENTPOS];
    long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)caret lParam:1];
    if (caret == start || caret - start >= 256) return NO;
    long end = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)caret lParam:1];
    NSString *prefix = [self prefixBeforeCaret];
    BOOL ignoreCase = [self completionIgnoresCase];

    NSArray<NSString *> *list;
    if (kind == NppCompletionKindFunctions) {
        // The whole list; Scintilla scrolls to what fits the typing.
        // Sorted, as AutoCompletion.cpp sorts its API list: Scintilla finds the
        // typed text by binary search, and the API files are not in order.
        list = [self sortedForCompletion:[NSOrderedSet orderedSetWithArray:[self functionNames]].array];
        if (!list.count) return NO;
    } else {
        NSMutableOrderedSet *words = [NSMutableOrderedSet orderedSet];
        if (kind == NppCompletionKindWords || kind == NppCompletionKindFunctionsAndWords) {
            NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
            NSString *whole = (end <= (long)doc.length)
                ? [[NSString alloc] initWithData:[doc subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]
                                        encoding:NSUTF8StringEncoding] : nil;
            [words addObjectsFromArray:[self documentWordsWithPrefix:prefix excluding:whole]];
        }
        if (kind == NppCompletionKindFunctionsBrief || kind == NppCompletionKindFunctionsAndWords) {
            for (NSString *name in [self functionNames]) {
                if (StartsWith(name, prefix, ignoreCase)) [words addObject:name];
            }
        }
        if (!words.count) return NO;
        // Word Completion with a single candidate just types it.
        if (kind == NppCompletionKindWords && autoInsert && words.count == 1) {
            NSString *word = words.firstObject;
            [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)start lParam:caret];
            [sci setStringProperty:SCI_REPLACETARGET parameter:-1 value:word];
            [sci message:SCI_GOTOPOS wParam:(uptr_t)(start + Utf8Len(word)) lParam:0];
            objc_setAssociatedObject(self, &kLastCompletionKey, @[word], OBJC_ASSOCIATION_RETAIN);
            return YES;
        }
        list = [self sortedForCompletion:words.array];
    }

    NppPreferences *p = [NppPreferences shared];
    [sci message:SCI_AUTOCSETSEPARATOR wParam:(uptr_t)'\n' lParam:0];
    [sci message:SCI_AUTOCSETIGNORECASE wParam:ignoreCase ? 1 : 0 lParam:0];
    [sci message:SCI_AUTOCSETCASEINSENSITIVEBEHAVIOUR
          wParam:ignoreCase ? SC_CASEINSENSITIVEBEHAVIOUR_IGNORECASE : SC_CASEINSENSITIVEBEHAVIOUR_RESPECTCASE lParam:0];
    // Tab and Enter are Scintilla's own completion keys; "Insert Selection: TAB"
    // off is handled at SCN_AUTOCSELECTION, as upstream does (a fill-up "\t" only
    // added a Tab after the word and left Tab completing anyway).
    [sci setStringProperty:SCI_AUTOCSETFILLUPS parameter:0 value:@""];
    (void)p;
    [sci setStringProperty:SCI_AUTOCSHOW parameter:caret - start value:[list componentsJoinedByString:@"\n"]];
    objc_setAssociatedObject(self, &kLastCompletionKey, list, OBJC_ASSOCIATION_RETAIN);
    return YES;
}

- (NSString *)autoInsertionForCharacter:(int)character {
    NppPreferences *p = [NppPreferences shared];
    switch (character) {
        case '(':  return p.autoInsertParenthesis ? @")" : nil;
        case '[':  return p.autoInsertBracket ? @"]" : nil;
        case '{':  return p.autoInsertBrace ? @"}" : nil;
        case '\'': return p.autoInsertSingleQuote ? @"'" : nil;
        case '"':  return p.autoInsertDoubleQuote ? @"\"" : nil;
        default:   return nil;
    }
}

/// Whether a closer may be put in after `character` was typed at caret-1,
/// as Notepad++ decides it: a bracket only before a blank, the end, or a
/// closer; a quote only between blanks or inside a fresh pair of brackets.
- (BOOL)autoCloseAllowedFor:(int)character {
    ScintillaView *sci = self.sci;
    long caret = [sci message:SCI_GETCURRENTPOS];
    int next = caret < [sci message:SCI_GETLENGTH] ? (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)caret lParam:0] : 0;
    int prev = caret >= 2 ? (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)(caret - 2) lParam:0] : 0;
    BOOL nextBlank = next == 0 || next == ' ' || next == '\t' || next == '\n' || next == '\r';
    BOOL prevBlank = prev == 0 || prev == ' ' || prev == '\t' || prev == '\n' || prev == '\r';
    BOOL nextCloser = next == ')' || next == ']' || next == '}';
    BOOL sandwiched = (prev == '(' && next == ')') || (prev == '[' && next == ']') || (prev == '{' && next == '}');
    if (character == '(' || character == '[' || character == '{') return nextBlank || nextCloser;
    // A quote: between blanks, inside a fresh pair, or against a bracket.
    return (prevBlank && nextBlank) || sandwiched ||
           ((prev == '(' || prev == '[' || prev == '{') && nextBlank) ||
           (prevBlank && nextCloser);
}

static const char kAutoCloseKey = 0;

- (void)forgetAutoCloser {
    objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
}

/// Typing the closer that was put in for you steps over it rather than
/// doubling it. Only the closer put in last is remembered, and only while
/// it is still where it was left.
- (BOOL)steppedOverAutoCloserFor:(int)character {
    ScintillaView *sci = self.sci;
    NSDictionary *tracked = objc_getAssociatedObject(self, &kAutoCloseKey);
    if (!tracked) return NO;
    long caret = [sci message:SCI_GETCURRENTPOS];
    long typedStart = [sci message:SCI_POSITIONBEFORE wParam:(uptr_t)caret lParam:0];
    long closerAt = [tracked[@"at"] longValue];
    int closer = [tracked[@"closer"] intValue];
    if (typedStart <= closerAt) closerAt += caret - typedStart;     // it moved along with the typing
    if (closerAt < caret || [sci message:SCI_GETCHARAT wParam:(uptr_t)closerAt lParam:0] != closer) {
        objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
        return NO;
    }
    if (closerAt == caret && character == closer) {
        [sci message:SCI_DELETERANGE wParam:(uptr_t)caret lParam:1];
        objc_setAssociatedObject(self, &kAutoCloseKey, nil, OBJC_ASSOCIATION_RETAIN);
        return YES;
    }
    objc_setAssociatedObject(self, &kAutoCloseKey, @{@"at": @(closerAt), @"closer": @(closer)},
                             OBJC_ASSOCIATION_RETAIN);
    return NO;
}

/// After ">" is typed, the element that was just opened, if any. Only in
/// HTML and XML, as on Windows, and never for an element that has no end.
- (NSString *)closeTagAtCaret {
    if (![NppPreferences shared].autoInsertCloseTag) return nil;
    NSString *language = self.currentDocument.language.name ?: @"";
    if (![language isEqualToString:@"html"] && ![language isEqualToString:@"xml"]) return nil;
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    NSString *text = [sci string] ?: @"";
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (pos <= 0 || (NSUInteger)pos > data.length) return nil;

    NSString *before = [[NSString alloc] initWithData:
        [data subdataWithRange:NSMakeRange(0, (NSUInteger)pos)] encoding:NSUTF8StringEncoding];
    if (![before hasSuffix:@">"]) return nil;

    NSRange open = [before rangeOfString:@"<" options:NSBackwardsSearch];
    if (open.location == NSNotFound) return nil;
    NSString *tag = [before substringWithRange:
        NSMakeRange(open.location + 1, before.length - open.location - 2)];
    if (![tag length] || [tag hasPrefix:@"/"] || [tag hasSuffix:@"/"]) return nil;

    // Only the element name, dropping any attributes.
    NSRange space = [tag rangeOfString:@" "];
    if (space.location != NSNotFound) tag = [tag substringToIndex:space.location];
    if (!tag.length) return nil;
    for (NSUInteger i = 0; i < tag.length; ++i) {
        unichar c = [tag characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '_' || c == ':';
        if (!ok) return nil;
    }
    static NSSet *voidElements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        voidElements = [NSSet setWithArray:@[@"area", @"base", @"br", @"col", @"embed", @"hr", @"img",
                                             @"input", @"link", @"meta", @"param", @"source",
                                             @"track", @"wbr"]];
    });
    if ([language isEqualToString:@"html"] && [voidElements containsObject:tag.lowercaseString]) return nil;
    return [NSString stringWithFormat:@"</%@>", tag];
}

/// The languages Notepad++'s advanced auto-indent treats as C-like.
static BOOL LanguageUsesBraces(NSString *name) {
    static NSSet *braced;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        braced = [NSSet setWithArray:@[@"c", @"cpp", @"java", @"cs", @"objc", @"php",
                                       @"javascript", @"javascript.js", @"jsp", @"css",
                                       @"perl", @"rust", @"powershell", @"json", @"json5",
                                       @"typescript", @"go", @"swift"]];
    });
    return [braced containsObject:(name ?: @"").lowercaseString];
}

/// Those of them with no one-line if/for/while without braces.
static BOOL LanguageAlwaysBraces(NSString *name) {
    return [@[@"perl", @"rust", @"powershell", @"json", @"json5"] containsObject:(name ?: @"").lowercaseString];
}

/// The text of a line, without its end of line.
- (NSString *)textOfLine:(long)line {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long b = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if (a < 0 || b < a || (NSUInteger)b > doc.length) return @"";
    return [[NSString alloc] initWithData:[doc subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

/// Whether the first match of `pattern` in the line runs to its end, which is
/// how Notepad++ tests a line with SCI_SEARCHINTARGET. Returns the match.
- (NSRange)line:(long)line matches:(NSString *)pattern toEnd:(BOOL)toEnd {
    NSString *text = [self textOfLine:line];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m || (toEnd && NSMaxRange(m.range) != text.length)) return NSMakeRange(NSNotFound, 0);
    return m.range;
}

/// isConditionExprLine: an if/for/while (...) or an else, with nothing after.
- (BOOL)isConditionLine:(long)line {
    if (line < 0 || line > [self.sci message:SCI_GETLINECOUNT]) return NO;
    return [self line:line matches:@"((else[ \\t]+)?if|for|while)[ \\t]*[(].*[)][ \\t]*|else[ \\t]*" toEnd:YES].location != NSNotFound;
}

/// findMachedBracePos, backwards.
- (long)openBraceBefore:(long)from {
    int balance = 0;
    for (long i = from; i >= 0; --i) {
        char c = (char)[self.sci message:SCI_GETCHARAT wParam:(uptr_t)i];
        if (c == '{') { if (balance == 0) return i; --balance; }
        else if (c == '}') ++balance;
    }
    return -1;
}

/// Notepad_plus::maintainIndentation, rule for rule.
- (void)maintainIndentationAfter:(int)character {
    NppPreferences *prefs = [NppPreferences shared];
    if (prefs.autoIndentMode == 0) return;

    ScintillaView *sci = self.sci;
    long eolMode = [sci message:SCI_GETEOLMODE];
    BOOL isNewline = (eolMode == SC_EOL_CR) ? (character == '\r') : (character == '\n');
    long caret = [sci message:SCI_GETCURRENTPOS];
    long current = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret];
    long previous = current - 1;
    long tabWidth = [sci message:SCI_GETTABWIDTH];
    long indent = 0;

    // Enter at the start of a line leaves the indentation alone.
    if (isNewline && previous >= 0 && [sci message:SCI_LINELENGTH wParam:(uptr_t)previous] == 0) return;

    // ScintillaEditView::setLineIndent: the selection moves with the indent.
    void (^setIndent)(long, long) = ^(long line, long amount) {
        long selStart = [sci message:SCI_GETSELECTIONSTART], selEnd = [sci message:SCI_GETSELECTIONEND];
        long before = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)line];
        [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)line lParam:MAX(0, amount)];
        long after = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)line];
        long diff = after - before;
        long (^shift)(long) = ^long(long pos) {
            if (after > before) return pos >= before ? pos + diff : pos;
            if (after < before && pos >= after) return pos >= before ? pos + diff : after;
            return pos;
        };
        [sci message:SCI_SETSEL wParam:(uptr_t)shift(selStart) lParam:shift(selEnd)];
    };
    long (^previousNonEmpty)(void) = ^long {
        long line = previous;
        while (line >= 0 && [sci message:SCI_LINELENGTH wParam:(uptr_t)line] == 0) line--;
        return line;
    };

    NSString *language = self.currentDocument.language.name;
    BOOL basic = prefs.autoIndentMode == 1 ||
                 (!LanguageUsesBraces(language) && ![language isEqualToString:@"python"]);
    if (basic) {
        if (!isNewline) return;
        long line = previousNonEmpty();
        if (line >= 0) indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
        if (indent > 0) setIndent(current, indent);
        return;
    }

    if ([language isEqualToString:@"python"]) {
        if (!isNewline) return;
        long line = previousNonEmpty();
        if (line >= 0) indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
        // A colon ending the line (a comment may follow), when it is code.
        NSRange colon = line >= 0 ? [self line:line matches:@":[ \\t]*(#|$)" toEnd:NO] : NSMakeRange(NSNotFound, 0);
        BOOL opens = NO;
        if (colon.location != NSNotFound) {
            long at = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line] +
                      Utf8Len([[self textOfLine:line] substringToIndex:colon.location]);
            [sci message:SCI_COLOURISE wParam:0 lParam:caret];
            opens = [sci message:SCI_GETSTYLEAT wParam:(uptr_t)at] == SCE_P_OPERATOR;
        }
        if (opens) setIndent(current, indent + tabWidth);
        else if (indent > 0) setIndent(current, indent);
        return;
    }

    // C-like.
    if (isNewline) {
        long line = previousNonEmpty();
        if (line >= 0) indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
        long beforeNewline = caret - (eolMode == SC_EOL_CRLF ? 3 : 2);
        unsigned char previousChar = beforeNewline >= 0
            ? (unsigned char)[sci message:SCI_GETCHARAT wParam:(uptr_t)beforeNewline] : 0;
        unsigned char nextChar = (unsigned char)[sci message:SCI_GETCHARAT wParam:(uptr_t)caret];

        if (previousChar == '{') {
            if (nextChar == '}') {
                NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
                [sci setStringProperty:SCI_INSERTTEXT parameter:caret value:eol];
                setIndent(current + 1, indent);
            }
            setIndent(current, indent + tabWidth);
        } else if (nextChar == '{') {
            setIndent(current, indent);
        } else if (LanguageAlwaysBraces(language)) {
            setIndent(current, indent);
        } else if ([self isConditionLine:line]) {
            setIndent(current, indent + tabWidth);        // the one statement an if governs
        } else if (indent > 0) {
            // After that one statement, back out again.
            setIndent(current, (line > 0 && [self isConditionLine:line - 1]) ? indent - tabWidth : indent);
        }
    } else if (character == '{') {
        // A brace alone on its line lines up with the line above, or one level
        // in when that line opened a block of its own.
        long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)current];
        for (long i = caret - 2; i > 0 && i >= lineStart; --i) {
            char c = (char)[sci message:SCI_GETCHARAT wParam:(uptr_t)i];
            if (c != ' ' && c != '\t') return;
        }
        long line = previousNonEmpty();
        if (line >= 0) {
            indent = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
            if ([self line:line matches:@"[ \\t]*\\{.*" toEnd:YES].location != NSNotFound) indent += tabWidth;
        }
        setIndent(current, indent);
    } else if (character == '}') {
        // A closing brace lines up with the line of its opening one.
        long from = caret > 0 ? caret - 1 : 0;
        long open = [self openBraceBefore:from - 1];
        if (open < 0) return;
        long openLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)open];
        if (openLine == current) return;
        setIndent(current, [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)openLine]);
    }
}

/// The user's own pairs from Preferences: a closer follows the opener when
/// the next character is blank. They are looked at before the built-in ones.
- (nullable NSString *)userPairCloserFor:(int)character {
    ScintillaView *sci = self.sci;
    long caret = [sci message:SCI_GETCURRENTPOS];
    int next = caret < [sci message:SCI_GETLENGTH] ? (int)[sci message:SCI_GETCHARAT wParam:(uptr_t)caret lParam:0] : 0;
    if (!(next == 0 || next == ' ' || next == '\t' || next == '\n' || next == '\r')) return nil;
    for (NSString *pair in [NppPreferences shared].userMatchedPairs) {
        if (pair.length == 2 && [pair characterAtIndex:0] == character) return [pair substringFromIndex:1];
    }
    return nil;
}

- (void)handleCharacterAdded:(int)character {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;

    // Prevent control character (C0 code) typing into document: upstream
    // drops the WM_CHAR; here the character just typed is taken out again.
    if (p.preventC0Typing && ((character >= 0 && character <= 31 && character != '\t' && character != '\n' &&
                               character != '\r') || character == 127)) {
        long caret = [sci message:SCI_GETCURRENTPOS];
        if (caret > 0) [sci message:SCI_DELETERANGE wParam:(uptr_t)(caret - 1) lParam:1];
        return;
    }

    // Nothing is added to what a macro records or plays back, as upstream.
    if ([self recordingMacro] || [self playingMacro]) return;

    // Indentation is carried over before anything else, so the line is already
    // in place when completion looks at it.
    [self maintainIndentationAfter:character];

    // Matched characters, but not in column mode or with several carets.
    if ([sci message:SCI_GETSELECTIONS] <= 1 && character < 128) {
        NSString *user = [self userPairCloserFor:character];
        if (user) {
            [sci setStringProperty:SCI_INSERTTEXT parameter:[sci message:SCI_GETCURRENTPOS] value:user];
        } else if (![self steppedOverAutoCloserFor:character]) {
            NSString *closing = [self autoInsertionForCharacter:character];
            if (closing && ![self autoCloseAllowedFor:character]) closing = nil;
            if (!closing && character == '>') closing = [self closeTagAtCaret];
            if (closing.length) {
                long pos = [sci message:SCI_GETCURRENTPOS];
                [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:closing];
                [sci message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];   // caret stays inside
                if (closing.length == 1) {
                    objc_setAssociatedObject(self, &kAutoCloseKey,
                                             @{@"at": @(pos), @"closer": @([closing characterAtIndex:0])},
                                             OBJC_ASSOCIATION_RETAIN);
                }
            }
        } else {
            return;                                   // stepped over a closer
        }
    }

    // The parameter hint follows the typing: "(" opens it, "," moves the
    // highlight, ")" closes it. Only when it has something does completion wait.
    if ((p.functionHintOnInput || [self apiCallTipVisible]) &&
        [self updateCallTipForCharacter:character force:NO]) return;

    if (!p.autoCompleteOnInput) return;
    // A full list already open filters itself as the typing goes on.
    if (!p.autoCompleteBriefList && [sci message:SCI_AUTOCACTIVE]) return;

    NSString *prefix = [self prefixBeforeCaret];
    if ((NSInteger)prefix.length < MAX(1, p.autoCompleteThreshold)) return;
    switch (p.autoCompleteSource) {
        case NppCompletionWords:
            [self showCompletion:NppCompletionKindWords autoInsert:NO];
            break;
        case NppCompletionFunctions:
            [self showCompletion:p.autoCompleteBriefList ? NppCompletionKindFunctionsBrief : NppCompletionKindFunctions
                      autoInsert:NO];
            break;
        default:
            [self showCompletion:NppCompletionKindFunctionsAndWords autoInsert:NO];
            break;
    }
}

#pragma mark - New documents

- (void)applyNewDocumentDefaults {
    NppPreferences *p = [NppPreferences shared];
    NppDocument *doc = self.currentDocument;
    if (!doc || doc.path) return;               // only untitled documents

    doc.eolMode = (int)p.defaultEOL;
    [self.sci message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];

    NSDictionary *encodings = @{@"ANSI": @(NSISOLatin1StringEncoding),
                                @"UTF-8": @(NSUTF8StringEncoding),
                                @"UTF-8-BOM": @(NSUTF8StringEncoding),
                                @"UTF-16 BE BOM": @(NSUTF16BigEndianStringEncoding),
                                @"UTF-16 LE BOM": @(NSUTF16LittleEndianStringEncoding)};
    NSNumber *enc = encodings[p.defaultEncoding ?: @"UTF-8"];
    doc.encoding = enc ? (NSStringEncoding)enc.unsignedIntegerValue : NSUTF8StringEncoding;
    doc.hasBOM = [p.defaultEncoding hasSuffix:@"BOM"];

    if (p.defaultLanguage.length) [self setLanguageNamed:p.defaultLanguage];
}

static const char kFirstLineNameKey = 0;

/// Notepad++ renames an untitled tab after its first line as the text changes
/// (Notepad_plus::updateTitle / the buffer's tab name), so the name stays on the
/// tab when another one comes to the front. The text is read from the view for
/// the document in front and the name kept with the document; a tab behind shows
/// the name it had when it was last in front (SETTINGS-045).
- (NSString *)untitledNameForDocument:(NppDocument *)doc {
    NppPreferences *p = [NppPreferences shared];
    if (!p.untitledFromFirstLine || doc.path) return doc.displayName;
    if (doc != self.currentDocument) return objc_getAssociatedObject(doc, &kFirstLineNameKey) ?: doc.displayName;

    NSString *text = [self.sci string] ?: @"";
    NSString *firstLine = [[text componentsSeparatedByCharactersInSet:
        [NSCharacterSet newlineCharacterSet]] firstObject] ?: @"";
    firstLine = [firstLine stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]];
    NSString *name = !firstLine.length ? nil : firstLine.length > 32 ? [firstLine substringToIndex:32] : firstLine;
    objc_setAssociatedObject(doc, &kFirstLineNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return name ?: doc.displayName;
}

#pragma mark - Recent files

- (void)noteRecentFile:(NSString *)path {
    if (!path.length) return;
    NppPreferences *p = [NppPreferences shared];
    NSMutableArray *list = [p.recentFiles mutableCopy] ?: [NSMutableArray array];
    [list removeObject:path];
    [list insertObject:path atIndex:0];
    while ((NSInteger)list.count > MAX(1, p.recentFilesMax)) [list removeLastObject];
    p.recentFiles = list;
}

- (NSArray<NSString *> *)recentFiles { return [NppPreferences shared].recentFiles ?: @[]; }

- (void)forgetRecentFile:(NSString *)path {
    NppPreferences *p = [NppPreferences shared];
    if (![p.recentFiles containsObject:path]) return;
    NSMutableArray *list = [p.recentFiles mutableCopy];
    [list removeObject:path];
    p.recentFiles = list;
}

- (void)clearRecentFiles { [NppPreferences shared].recentFiles = @[]; }

/// 0 shows the file name, 1 the full path, both clipped to the configured length.
- (NSString *)displayNameForRecentFile:(NSString *)path {
    NppPreferences *p = [NppPreferences shared];
    NSString *shown = p.recentFilesShowFullPath ? path : path.lastPathComponent;
    NSInteger limit = p.recentFilesMaxLength;
    if (limit > 3 && (NSInteger)shown.length > limit) {
        // Keep the tail, which is the part that identifies the file.
        shown = [@"…" stringByAppendingString:
                 [shown substringFromIndex:shown.length - (NSUInteger)limit + 1]];
    }
    return shown;
}

#pragma mark - Default directory

- (NSString *)defaultOpenDirectory {
    NppPreferences *p = [NppPreferences shared];
    switch (p.defaultDirectoryMode) {
        case 0: {                                // follow the current document
            NSString *path = self.currentDocument.path;
            if (path.length) return path.stringByDeletingLastPathComponent;
            break;
        }
        case 1:                                  // remember the last used one
            if (p.lastUsedDirectory.length) return p.lastUsedDirectory;
            break;
        default:                                 // a fixed folder
            if (p.fixedDirectory.length) return p.fixedDirectory;
            break;
    }
    return NSHomeDirectory();
}

- (void)rememberOpenDirectory:(NSString *)path {
    if ([NppPreferences shared].defaultDirectoryMode != 1 || !path.length) return;
    [NppPreferences shared].lastUsedDirectory = path.stringByDeletingLastPathComponent;
}

#pragma mark - Searching

- (NSString *)initialFindTerm {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];

    // Upstream fills the field only from a selection shorter than the limit.
    if (b > a && p.findFillWithSelection && (b - a) <= MAX(1, p.fillFindWhatThreshold)) {
        NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
        if ((NSUInteger)b <= data.length) {
            return [[NSString alloc] initWithData:
                [data subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))]
                                         encoding:NSUTF8StringEncoding] ?: @"";
        }
    }
    if (b == a && p.findSelectWordUnderCaret) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        long start = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        long end = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
        if (end > start) {
            NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
            if ((NSUInteger)end <= data.length) {
                return [[NSString alloc] initWithData:
                    [data subdataWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]
                                             encoding:NSUTF8StringEncoding] ?: @"";
            }
        }
    }
    return @"";
}

@end
