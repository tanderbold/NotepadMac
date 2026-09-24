#import "AuxPanels.h"
#import "EditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import "SettingsCommands.h"
#include <string>

#pragma mark - Byte/character bridging

// Scintilla positions are UTF-8 byte offsets; NSString indices are UTF-16.
// Everything below converts through NSData so the two never get mixed up.

static long Utf8Length(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

static NSString *StringFromBytes(NSData *data, long start, long end) {
    if (start < 0) start = 0;
    if (end > (long)data.length) end = (long)data.length;
    if (end <= start) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

/// Splits text into lines, each keeping its own line ending, so rebuilding the
/// document preserves mixed endings exactly.
static NSArray<NSString *> *SplitKeepingEndings(NSString *text) {
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger i = 0, n = text.length, lineStart = 0;
    while (i < n) {
        unichar c = [text characterAtIndex:i];
        if (c == '\r' || c == '\n') {
            NSUInteger end = i + 1;
            if (c == '\r' && end < n && [text characterAtIndex:end] == '\n') end++;
            [out addObject:[text substringWithRange:NSMakeRange(lineStart, end - lineStart)]];
            lineStart = end;
            i = end;
        } else {
            i++;
        }
    }
    if (lineStart < n) [out addObject:[text substringFromIndex:lineStart]];
    return out;
}

static NSString *LineBody(NSString *line) {
    NSUInteger n = line.length;
    while (n > 0) {
        unichar c = [line characterAtIndex:n - 1];
        if (c != '\r' && c != '\n') break;
        n--;
    }
    return [line substringToIndex:n];
}

static NSString *LineEnding(NSString *line) {
    return [line substringFromIndex:LineBody(line).length];
}

/// Notepad_plus::wsTabConvert, tab2Space, for one line's bytes (no line end):
/// each tab becomes the spaces up to the next tab stop.
static std::string TabsToSpaces(const std::string &source, long tabWidth) {
    std::string dest;
    long column = 0;
    for (char ch : source) {
        if (ch == '\t') {
            long insert = tabWidth - (column % tabWidth);
            dest.append((size_t)insert, ' ');
            column += insert;
        } else {
            dest.push_back(ch);
            if (((unsigned char)ch & 0xC0) != 0x80) ++column;   // count UTF-8 lead bytes only
        }
    }
    return dest;
}

/// Notepad_plus::wsTabConvert, space2TabAll / space2TabLeading, for one line:
/// spaces that reach a tab stop become a tab, a single space stays unless a
/// space or tab follows it, spaces before a tab are absorbed by it.
static std::string SpacesToTabs(const std::string &line, long tabWidth, bool onlyLeading) {
    std::string src = line;
    src.push_back('\0');   // upstream reads source[i + counter] up to the terminator
    std::string dest;
    long column = 0, tabStop = tabWidth - 1;
    bool nextChar = false, nonSpaceFound = false;
    int counter = 0;
    for (size_t i = 0; src[i] != '\0'; ++i) {
        if (!nonSpaceFound) {
            while (src[i + counter] == ' ') {
                if (column + counter == tabStop) {
                    tabStop += tabWidth;
                    if (counter >= 1) {
                        dest.push_back('\t');
                        i += counter;
                        column += counter + 1;
                        counter = 0;
                        nextChar = true;
                        break;
                    } else if (src[i + 1] == ' ' || src[i + 1] == '\t') {
                        dest.push_back('\t');
                        i++;
                        column += 1;
                        counter = 0;
                    } else {
                        dest.push_back(src[i]);
                        column += 1;
                        counter = 0;
                        nextChar = true;
                        break;
                    }
                } else {
                    ++counter;
                }
            }
            if (nextChar) { nextChar = false; continue; }
            if (src[i] == ' ' && src[i + counter] == '\t') {
                dest.push_back('\t');
                i += counter;
                column = tabStop + 1;
                tabStop += tabWidth;
                counter = 0;
                continue;
            }
        }
        if (onlyLeading && !nonSpaceFound) nonSpaceFound = true;
        if (src[i] == '\t') {
            dest.push_back(src[i]);
            column = tabStop + 1;
            tabStop += tabWidth;
            counter = 0;
        } else {
            dest.push_back(src[i]);
            counter = 0;
            if (((unsigned char)src[i] & 0xC0) != 0x80) {
                ++column;
                if (column > 0 && column % tabWidth == 0) tabStop += tabWidth;
            }
        }
    }
    return dest;
}

static NSString *ConvertLineBytes(NSString *line, std::string (^convert)(const std::string &)) {
    const char *utf8 = line.UTF8String ?: "";
    std::string out = convert(std::string(utf8));
    return [[NSString alloc] initWithBytes:out.data() length:out.size() encoding:NSUTF8StringEncoding] ?: line;
}

@implementation EditorController (EditCommands)

#pragma mark - Shared plumbing


/// Replaces the whole document in one undo step, restoring the caret line.
- (void)replaceDocumentText:(NSString *)text keepingLine:(long)line {
    ScintillaView *sci = self.sci;
    // An edit, not a reload: a read-only document is left alone, as Scintilla
    // leaves it alone for Notepad++'s commands (setDocumentText lifts the flag).
    if ([sci message:SCI_GETREADONLY]) { NppBeep(); return; }
    [sci message:SCI_BEGINUNDOACTION];
    [self setDocumentText:text];
    [sci message:SCI_ENDUNDOACTION];
    long last = [sci message:SCI_GETLINECOUNT] - 1;
    [sci message:SCI_GOTOLINE wParam:(uptr_t)MAX(0, MIN(line, last)) lParam:0];
    [self refreshChrome];
}

/// Inclusive line range covered by the selection, or the caret's line.
- (void)selectedFirstLine:(long *)first lastLine:(long *)last {
    ScintillaView *sci = self.sci;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    *first = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    *last  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (*last > *first && selEnd == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)*last]) (*last)--;
}

/// Rewrites the selected lines (or every line when nothing is selected).
- (void)transformSelectedLines:(NSArray<NSString *> *(^)(NSArray<NSString *> *bodies))transform {
    ScintillaView *sci = self.sci;
    BOOL hasSelection = [sci message:SCI_GETSELECTIONSTART] != [sci message:SCI_GETSELECTIONEND];
    NSArray *lines = SplitKeepingEndings(self.documentText);
    if (!lines.count) return;

    long first = 0, last = (long)lines.count - 1;
    if (hasSelection) [self selectedFirstLine:&first lastLine:&last];
    // A rectangle, or a caret in each of several lines, covers the lines from
    // its anchor to its caret, whatever the main selection's own ends are.
    if ([sci message:SCI_SELECTIONISRECTANGLE] || [sci message:SCI_GETSELECTIONMODE] == SC_SEL_THIN) {
        long a = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETRECTANGULARSELECTIONANCHOR]];
        long c = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETRECTANGULARSELECTIONCARET]];
        first = MIN(a, c);
        last = MAX(a, c);
    }
    first = MAX(0, MIN(first, (long)lines.count - 1));
    last  = MAX(first, MIN(last, (long)lines.count - 1));

    NSMutableArray *bodies = [NSMutableArray array];
    NSMutableArray *endings = [NSMutableArray array];
    for (long i = first; i <= last; ++i) {
        [bodies addObject:LineBody(lines[(NSUInteger)i])];
        [endings addObject:LineEnding(lines[(NSUInteger)i])];
    }

    NSArray *newBodies = transform(bodies);

    NSMutableArray *rebuilt = [NSMutableArray arrayWithArray:[lines subarrayWithRange:NSMakeRange(0, (NSUInteger)first)]];
    // Reuse the original endings positionally; the final line keeps whatever it had.
    NSString *fallback = endings.count ? endings.lastObject : @"";
    if (!fallback.length) {
        fallback = [self.currentDocument.eolMode == SC_EOL_CRLF ? @"\r\n"
                  : self.currentDocument.eolMode == SC_EOL_CR   ? @"\r" : @"\n" copy];
    }
    for (NSUInteger i = 0; i < newBodies.count; ++i) {
        // The tail is the last line written when the range reached the last
        // line of the file - judged by the output, since the transform may
        // have changed how many lines there are - and it keeps whatever
        // ending the file had, including none.
        BOOL isDocumentTail = i == newBodies.count - 1 && last == (long)lines.count - 1;
        NSString *ending;
        if (isDocumentTail) {
            ending = endings.lastObject ?: @"";
        } else {
            ending = i < endings.count ? endings[i] : fallback;
            if (!ending.length) ending = fallback;
        }
        [rebuilt addObject:[newBodies[i] stringByAppendingString:ending]];
    }
    if (last + 1 < (long)lines.count) {
        [rebuilt addObjectsFromArray:[lines subarrayWithRange:
            NSMakeRange((NSUInteger)(last + 1), lines.count - (NSUInteger)(last + 1))]];
    }

    [self replaceDocumentText:[rebuilt componentsJoinedByString:@""] keepingLine:first];
}

/// Rewrites the selected characters, or the whole document when nothing is selected.
- (void)transformSelectedText:(NSString *(^)(NSString *selected))transform {
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) { NppBeep(); return; }
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    NSString *whole = self.documentText;

    if (selStart == selEnd) {
        long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
        [self replaceDocumentText:transform(whole) keepingLine:line];
        return;
    }

    NSData *data = [whole dataUsingEncoding:NSUTF8StringEncoding];
    NSString *prefix = StringFromBytes(data, 0, selStart);
    NSString *middle = StringFromBytes(data, selStart, selEnd);
    NSString *suffix = StringFromBytes(data, selEnd, (long)data.length);
    NSString *replaced = transform(middle);

    [sci message:SCI_BEGINUNDOACTION];
    [self setDocumentText:[NSString stringWithFormat:@"%@%@%@", prefix, replaced, suffix]];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_SETSEL wParam:(uptr_t)selStart lParam:selStart + Utf8Length(replaced)];
    [self refreshChrome];
}

#pragma mark - Convert Case

static NSString *ApplyCase(NSString *s, NppCaseMode mode) {
    switch (mode) {
        case NppCaseUpper: return s.uppercaseString;
        case NppCaseLower: return s.lowercaseString;

        case NppCaseProperForce:
            return ApplyCase(s.lowercaseString, NppCaseProperBlend);
        case NppCaseProperBlend: {
            // Capitalise word starts, leave the rest of each word as the user
            // typed it. A word is letters, digits and apostrophes, as on
            // Windows: "don't" is one word and "3rd" starts with a digit.
            NSMutableString *out = [s mutableCopy];
            BOOL atStart = YES;
            for (NSUInteger i = 0; i < out.length; ++i) {
                unichar c = [out characterAtIndex:i];
                BOOL letter = [[NSCharacterSet letterCharacterSet] characterIsMember:c];
                BOOL isWord = letter || [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:c] ||
                              c == '\'';
                if (letter && atStart) {
                    [out replaceCharactersInRange:NSMakeRange(i, 1)
                                       withString:[[NSString stringWithCharacters:&c length:1] uppercaseString]];
                }
                atStart = !isWord;
            }
            return out;
        }

        case NppCaseSentenceForce:
        case NppCaseSentenceBlend: {
            BOOL force = (mode == NppCaseSentenceForce);
            NSMutableString *out = [(force ? s.lowercaseString : s) mutableCopy];
            // As on Windows: a sentence ends at . ! or ? followed by something
            // that is not a letter or digit, or at a blank line; a lone "i"
            // is "I".
            NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
            NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            BOOL newSentence = YES, terminator = NO;
            NSUInteger newlines = 0;
            for (NSUInteger i = 0; i < out.length; ++i) {
                unichar c = [out characterAtIndex:i];
                BOOL isAlnum = [alnum characterIsMember:c];
                // As Windows tests it: the stop has to be followed by
                // whitespace, and a lone i has whitespace (or an edge) on
                // both sides.
                if (terminator && [space characterIsMember:c]) newSentence = YES;
                terminator = NO;
                if (c == '\n') { if (++newlines >= 2) newSentence = YES; }
                else if (c != '\r') newlines = 0;
                if (c == '.' || c == '!' || c == '?') terminator = YES;
                if (isAlnum) {
                    BOOL lone = (c == 'i') &&
                        (i == 0 || [space characterIsMember:[out characterAtIndex:i - 1]]) &&
                        (i + 1 >= out.length || [space characterIsMember:[out characterAtIndex:i + 1]]);
                    if ((newSentence || lone) && [[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
                        [out replaceCharactersInRange:NSMakeRange(i, 1)
                                           withString:[[NSString stringWithCharacters:&c length:1] uppercaseString]];
                    }
                    newSentence = NO;
                }
            }
            return out;
        }

        case NppCaseInvert: {
            NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
            for (NSUInteger i = 0; i < s.length; ++i) {
                NSString *ch = [s substringWithRange:NSMakeRange(i, 1)];
                NSString *up = ch.uppercaseString;
                [out appendString:[ch isEqualToString:up] ? ch.lowercaseString : up];
            }
            return out;
        }

        case NppCaseRandom: {
            NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
            for (NSUInteger i = 0; i < s.length; ++i) {
                NSString *ch = [s substringWithRange:NSMakeRange(i, 1)];
                [out appendString:(arc4random_uniform(2) ? ch.uppercaseString : ch.lowercaseString)];
            }
            return out;
        }
    }
    return s;
}

// ScintillaEditView::convertSelectedTextTo: each piece of a multiple or
// rectangular selection is converted on its own; a single selection only
// when it holds something - with nothing selected nothing changes.
- (void)convertCase:(NppCaseMode)mode {
    ScintillaView *sci = self.sci;
    if ([sci message:SCI_GETREADONLY]) { NppBeep(); return; }
    long count = [sci message:SCI_GETSELECTIONS];
    if (count <= 1) {
        if ([sci message:SCI_GETSELECTIONSTART] == [sci message:SCI_GETSELECTIONEND]) return;
        [self transformSelectedText:^NSString *(NSString *sel) { return ApplyCase(sel, mode); }];
        return;
    }
    NSMutableArray<NSArray<NSNumber *> *> *pieces = [NSMutableArray array];
    for (long i = 0; i < count; ++i) {
        [pieces addObject:@[@([sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i]),
                            @([sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i]),
                            @([sci message:SCI_GETSELECTIONNANCHOR wParam:(uptr_t)i] > [sci message:SCI_GETSELECTIONNCARET wParam:(uptr_t)i])]];
    }
    [pieces sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    NSData *doc = [self.documentText dataUsingEncoding:NSUTF8StringEncoding];
    long delta = 0;
    NSMutableArray<NSArray<NSNumber *> *> *placed = [NSMutableArray array];
    [sci message:SCI_BEGINUNDOACTION];
    for (NSArray<NSNumber *> *piece in pieces) {
        long a = piece[0].longValue, b = piece[1].longValue;
        NSString *converted = ApplyCase(StringFromBytes(doc, a, b), mode);
        long newLength = Utf8Length(converted);
        if (b > a) {
            [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)(a + delta) lParam:b + delta];
            [sci setStringProperty:SCI_REPLACETARGET parameter:newLength value:converted];
        }
        [placed addObject:@[@(a + delta), @(a + delta + newLength), piece[2]]];
        delta += newLength - (b - a);
    }
    [sci message:SCI_ENDUNDOACTION];
    // The same pieces stay selected, each with its caret where it was.
    for (NSUInteger i = 0; i < placed.count; ++i) {
        long start = placed[i][0].longValue, end = placed[i][1].longValue;
        BOOL caretFirst = placed[i][2].boolValue;
        uptr_t caret = (uptr_t)(caretFirst ? start : end);
        sptr_t anchor = caretFirst ? end : start;
        [sci message:i == 0 ? SCI_SETSELECTION : SCI_ADDSELECTION wParam:caret lParam:anchor];
    }
    [self refreshChrome];
}

#pragma mark - Sorting

/// "Sort Lines As Integers" is not "read the line as a number" -- Notepad++
/// walks both lines in chunks, comparing a run of digits as a number and a run
/// of anything else as text, so item2 comes before item10. A '-' before a digit
/// is a minus sign, which is why 0-1-3 sorts as 0 then -1 then -3. Ported from
/// IntegerSorter in Sorters.h, including that.
static NSComparisonResult CompareNatural(NSString *a, NSString *b) {
    NSUInteger i = 0, j = 0;
    NSUInteger lenA = a.length, lenB = b.length;
    NSInteger result = 0;

    while (result == 0) {
        if (i >= lenA || j >= lenB) {
            NSString *restA = [a substringFromIndex:MIN(i, lenA)];
            NSString *restB = [b substringFromIndex:MIN(j, lenB)];
            NSComparisonResult tail = [restA compare:restB];
            result = (tail == NSOrderedAscending) ? -1 : (tail == NSOrderedDescending ? 1 : 0);
            break;
        }

        unichar ca = [a characterAtIndex:i], cb = [b characterAtIndex:j];
        BOOL numA = (ca >= '0' && ca <= '9');
        BOOL numB = (cb >= '0' && cb <= '9');
        NSInteger signA = 1, signB = 1;
        if (!numA && i + 1 < lenA) {
            unichar next = [a characterAtIndex:i + 1];
            numA = (ca == '-' && next >= '0' && next <= '9');
            signA = -1;
        }
        if (!numB && j + 1 < lenB) {
            unichar next = [b characterAtIndex:j + 1];
            numB = (cb == '-' && next >= '0' && next <= '9');
            signB = -1;
        }

        if (numA != numB) {
            // One is a number and the other is not: the characters decide.
            result = (NSInteger)ca - (NSInteger)cb;
            i++; j++;
        } else if (numA) {
            if (signA != signB) {
                result = (signA == 1) ? 1 : -1;
            } else {
                if (signA == -1) { i++; j++; }

                NSUInteger endA = i, endB = j;
                while (endA < lenA) {
                    unichar c = [a characterAtIndex:endA];
                    if (c < '0' || c > '9') break;
                    endA++;
                }
                while (endB < lenB) {
                    unichar c = [b characterAtIndex:endB];
                    if (c < '0' || c > '9') break;
                    endB++;
                }

                NSInteger zerosA = 0, zerosB = 0;
                while (i < lenA && [a characterAtIndex:i] == '0') { zerosA++; i++; }
                while (j < lenB && [b characterAtIndex:j] == '0') { zerosB++; j++; }

                NSUInteger digitsA = endA > i ? endA - i : 0;
                NSUInteger digitsB = endB > j ? endB - j : 0;
                if (digitsA > digitsB) {
                    result = 1 * signA;          // the longer number is the larger one
                } else if (digitsA < digitsB) {
                    result = -1 * signA;
                } else {
                    // Same length: digit by digit, because the numbers can be
                    // far longer than any integer type.
                    while (result == 0 && i < lenA && j < lenB) {
                        unichar da = [a characterAtIndex:i], db = [b characterAtIndex:j];
                        if (da < '0' || da > '9' || db < '0' || db > '9') break;
                        result = ((NSInteger)da - (NSInteger)db) * signA;
                        i++; j++;
                    }
                    if (result == 0) result = zerosB - zerosA;
                }
            }
        } else {
            // Both are text: compare up to the next digit or minus sign.
            if ([a characterAtIndex:i] == '-') i++;
            if ([b characterAtIndex:j] == '-') j++;
            NSCharacterSet *breakers = [NSCharacterSet characterSetWithCharactersInString:@"0123456789-"];
            NSRange restA = NSMakeRange(i, lenA - i);
            NSRange restB = NSMakeRange(j, lenB - j);
            NSUInteger endA = [a rangeOfCharacterFromSet:breakers options:0 range:restA].location;
            NSUInteger endB = [b rangeOfCharacterFromSet:breakers options:0 range:restB].location;
            if (endA == NSNotFound) endA = lenA;
            if (endB == NSNotFound) endB = lenB;
            NSComparisonResult chunk = [[a substringWithRange:NSMakeRange(i, endA - i)]
                                        compare:[b substringWithRange:NSMakeRange(j, endB - j)]];
            result = (chunk == NSOrderedAscending) ? -1 : (chunk == NSOrderedDescending ? 1 : 0);
            i = endA; j = endB;
        }
    }
    return result < 0 ? NSOrderedAscending : (result > 0 ? NSOrderedDescending : NSOrderedSame);
}

/// The leading run of characters a decimal sort is willing to read.
static NSString *TakeWhileAdmissable(NSString *input, NSString *admissable) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:admissable];
    NSUInteger stop = [input rangeOfCharacterFromSet:allowed.invertedSet].location;
    return stop == NSNotFound ? input : [input substringToIndex:stop];
}

/// Whether a prepared line carries nothing a number could be read from.
static BOOL PreparedLineIsEmpty(NSString *prepared) {
    return [prepared stringByTrimmingCharactersInSet:
            [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n"]].length == 0;
}

- (NSInteger)sortLines:(NppSortKey)key descending:(BOOL)descending {
    __block NSInteger failedLine = NSNotFound;

    // A rectangular selection sorts the lines by what is inside its columns,
    // as on Windows; the whole lines move.
    ScintillaView *view = self.sci;
    NSRange columns = NSMakeRange(NSNotFound, 0);
    // (A thin selection - a caret in each line - counts too, as NppCommands.cpp has it.)
    if ([view message:SCI_SELECTIONISRECTANGLE] || [view message:SCI_GETSELECTIONMODE] == SC_SEL_THIN) {
        // The offset inside the line, in bytes, as NppCommands.cpp takes it:
        // a display column would count a tab as several.
        long anchor = [view message:SCI_GETRECTANGULARSELECTIONANCHOR];
        long caret = [view message:SCI_GETRECTANGULARSELECTIONCARET];
        long a = anchor - [view message:SCI_POSITIONFROMLINE wParam:(uptr_t)[view message:SCI_LINEFROMPOSITION wParam:(uptr_t)anchor]]
               + [view message:SCI_GETRECTANGULARSELECTIONANCHORVIRTUALSPACE];
        long c = caret - [view message:SCI_POSITIONFROMLINE wParam:(uptr_t)[view message:SCI_LINEFROMPOSITION wParam:(uptr_t)caret]]
               + [view message:SCI_GETRECTANGULARSELECTIONCARETVIRTUALSPACE];
        columns = NSMakeRange((NSUInteger)MIN(a, c), (NSUInteger)labs(a - c));
    }
    NSString *(^keyOf)(NSString *) = ^NSString *(NSString *line) {
        if (columns.location == NSNotFound) return line;
        NSData *bytes = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (columns.location >= bytes.length) return @"";
        // A column of no width (a caret in each line) sorts on the rest of the
        // line from there, as Sorters.h's getSortKey does.
        NSUInteger end = columns.length ? MIN(bytes.length, NSMaxRange(columns)) : bytes.length;
        NSData *slice = [bytes subdataWithRange:NSMakeRange(columns.location, end - columns.location)];
        return [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding]
            ?: [[NSString alloc] initWithData:slice encoding:NSISOLatin1StringEncoding] ?: @"";
    };

    // The decimal sorts read each line as a number and refuse the whole sort if
    // one of them is not, naming the line -- that is what Notepad++ does, rather
    // than quietly leaving it where it was.
    if (key == NppSortDecimalComma || key == NppSortDecimalDot) {
        NSString *admissable = (key == NppSortDecimalComma)
            ? @" \t\r\n0123456789,-" : @" \t\r\n0123456789.-";
        [self transformSelectedLines:^NSArray *(NSArray *bodies) {
            NSMutableArray *empties = [NSMutableArray array];
            NSMutableArray *numbered = [NSMutableArray array];   // pairs of line and value
            for (NSUInteger i = 0; i < bodies.count; ++i) {
                NSString *prepared = TakeWhileAdmissable(keyOf(bodies[i]), admissable);
                if (key == NppSortDecimalComma) {
                    prepared = [prepared stringByReplacingOccurrencesOfString:@"," withString:@"."];
                }
                if (PreparedLineIsEmpty(prepared)) { [empties addObject:bodies[i]]; continue; }

                NSScanner *scanner = [NSScanner scannerWithString:prepared];
                scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
                double value = 0;
                if (![scanner scanDouble:&value]) {
                    if (failedLine == NSNotFound) failedLine = (NSInteger)i;
                    return bodies;                      // nothing is moved
                }
                [numbered addObject:@[bodies[i], @(value)]];
            }
            if (failedLine != NSNotFound) return bodies;

            // Stable either way, as std::stable_sort is: lines with the same
            // number keep their order, descending too.
            [numbered sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
                return descending ? [b[1] compare:a[1]] : [a[1] compare:b[1]];
            }];

            NSMutableArray *out = [NSMutableArray array];
            // Lines with no number go first ascending, last descending.
            if (!descending) [out addObjectsFromArray:empties];
            for (NSArray *pair in numbered) [out addObject:pair[0]];
            if (descending) [out addObjectsFromArray:empties];
            return out;
        }];
        return failedLine;
    }

    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        if (key == NppSortReverseOrder) {
            return bodies.reverseObjectEnumerator.allObjects;
        }
        if (key == NppSortRandom) {
            NSMutableArray *shuffled = [bodies mutableCopy];
            for (NSUInteger i = shuffled.count; i > 1; --i) {
                [shuffled exchangeObjectAtIndex:i - 1
                              withObjectAtIndex:arc4random_uniform((uint32_t)i)];
            }
            return shuffled;
        }

        NSArray *sorted = [bodies sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *wholeA, NSString *wholeB) {
            NSString *a = keyOf(descending ? wholeB : wholeA), *b = keyOf(descending ? wholeA : wholeB);
            switch (key) {
                case NppSortLexicographic:                return [a compare:b];
                case NppSortLexicographicCaseInsensitive: return [a caseInsensitiveCompare:b];
                case NppSortLocale:                       return [a localizedCompare:b];
                case NppSortInteger:                      return CompareNatural(a, b);
                case NppSortLength:
                    if (a.length != b.length) return a.length < b.length ? NSOrderedAscending : NSOrderedDescending;
                    return NSOrderedSame;
                default: return NSOrderedSame;
            }
        }];
        return sorted;
    }];
    return NSNotFound;
}

#pragma mark - Line operations

- (void)removeDuplicateLines:(BOOL)consecutiveOnly {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (NSString *line in bodies) {
            if (consecutiveOnly) {
                if (out.count && [out.lastObject isEqualToString:line]) continue;
            } else {
                if ([seen containsObject:line]) continue;
                [seen addObject:line];
            }
            [out addObject:line];
        }
        return out;
    }];
}

- (void)splitLines {
    // Notepad++ splits at the wrap width; without wrapping we split on spaces
    // so a long line becomes one word-run per line at the current edge column.
    long edge = [self.sci message:SCI_GETEDGECOLUMN];
    if (edge <= 0) edge = 80;
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            if ((long)line.length <= edge) { [out addObject:line]; continue; }
            NSMutableString *current = [NSMutableString string];
            for (NSString *word in [line componentsSeparatedByString:@" "]) {
                if (current.length && (long)(current.length + 1 + word.length) > edge) {
                    [out addObject:[current copy]];
                    [current setString:word];
                } else {
                    if (current.length) [current appendString:@" "];
                    [current appendString:word];
                }
            }
            if (current.length) [out addObject:[current copy]];
        }
        return out;
    }];
}

- (void)joinLines {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        return @[[bodies componentsJoinedByString:@" "]];
    }];
}

- (void)moveLine:(BOOL)up {
    [self.sci message:(up ? SCI_MOVESELECTEDLINESUP : SCI_MOVESELECTEDLINESDOWN)];
    [self refreshChrome];
}

- (void)removeEmptyLines:(BOOL)alsoBlankOnly {
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            NSString *probe = alsoBlankOnly
                ? [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
                : line;
            if (!probe.length) continue;
            [out addObject:line];
        }
        return out;
    }];
}

- (void)insertBlankLine:(BOOL)above {
    ScintillaView *sci = self.sci;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long pos = above ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line]
                     : [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSString *eol = self.currentDocument.eolMode == SC_EOL_CRLF ? @"\r\n"
                  : self.currentDocument.eolMode == SC_EOL_CR   ? @"\r" : @"\n";
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:eol];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOLINE wParam:(uptr_t)(above ? line : line + 1) lParam:0];
    [self refreshChrome];
}

#pragma mark - Blank operations

- (void)applyTrim:(NppTrimMode)mode {
    long tabWidth = [self.sci message:SCI_GETTABWIDTH];
    if (tabWidth <= 0) tabWidth = 4;
    if (mode == NppTabToSpace || mode == NppSpaceToTabAll || mode == NppSpaceToTabLeading) {
        // wsTabConvert: "block selection is not supported".
        long selMode = [self.sci message:SCI_GETSELECTIONMODE];
        if (selMode == SC_SEL_RECTANGLE || selMode == SC_SEL_THIN) return;
    }

    if (mode == NppTrimEOLToSpace || mode == NppTrimAll) {
        [self transformSelectedLines:^NSArray *(NSArray *bodies) {
            NSMutableArray *trimmed = [NSMutableArray array];
            for (NSString *line in bodies) {
                [trimmed addObject:(mode == NppTrimAll
                    ? [line stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t"]]
                    : line)];
            }
            return @[[trimmed componentsJoinedByString:@" "]];
        }];
        return;
    }

    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        // Tabs and spaces, as Windows trims: a no-break space is content.
        NSCharacterSet *ws = [NSCharacterSet characterSetWithCharactersInString:@" \t"];
        for (NSString *line in bodies) {
            NSString *r = line;
            switch (mode) {
                case NppTrimTrailing: {
                    NSUInteger n = r.length;
                    while (n > 0 && [ws characterIsMember:[r characterAtIndex:n - 1]]) n--;
                    r = [r substringToIndex:n];
                    break;
                }
                case NppTrimLeading: {
                    NSUInteger i = 0;
                    while (i < r.length && [ws characterIsMember:[r characterAtIndex:i]]) i++;
                    r = [r substringFromIndex:i];
                    break;
                }
                case NppTrimBoth:
                    r = [r stringByTrimmingCharactersInSet:ws];
                    break;
                case NppTabToSpace:
                    r = ConvertLineBytes(r, ^std::string(const std::string &b) { return TabsToSpaces(b, tabWidth); });
                    break;
                case NppSpaceToTabAll:
                case NppSpaceToTabLeading: {
                    bool leading = mode == NppSpaceToTabLeading;
                    r = ConvertLineBytes(r, ^std::string(const std::string &b) { return SpacesToTabs(b, tabWidth, leading); });
                    break;
                }
                default: break;
            }
            [out addObject:r];
        }
        return out;
    }];
}

#pragma mark - Indent, delete

/// Notepad++'s Increase/Decrease Line Indent shifts whole lines. SCI_TAB would
/// instead replace a within-line selection with a tab character.
/// IDM_EDIT_INS_TAB / IDM_EDIT_RMV_TAB: a multiple or multi-line selection is
/// Scintilla's Tab / Shift+Tab, which keeps the whole lines selected (setting
/// each line's indentation left the selection's end at a line start, so a
/// second Decrease missed a line: EDIT-026); a caret or a one-line selection
/// moves that line by a tab width and the selection with it (setLineIndent).
- (void)changeIndent:(BOOL)increase {
    ScintillaView *sci = self.sci;
    long selStart = [sci message:SCI_GETSELECTIONSTART], selEnd = [sci message:SCI_GETSELECTIONEND];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    long endLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if ([sci message:SCI_GETSELECTIONS] > 1 || line != endLine) {
        [sci message:increase ? SCI_TAB : SCI_BACKTAB];
        [self refreshChrome];
        return;
    }
    long delta = [sci message:SCI_GETTABWIDTH];
    if (delta <= 0) delta = 4;
    long current = [sci message:SCI_GETLINEINDENTATION wParam:(uptr_t)line];
    long target = MAX(0, current + (increase ? delta : -delta));
    long before = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)line];
    [sci message:SCI_SETLINEINDENTATION wParam:(uptr_t)line lParam:target];
    long after = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)line];
    long diff = after - before, lo = selStart, hi = selEnd;
    if (after > before) {
        if (lo >= before) lo += diff;
        if (hi >= before) hi += diff;
    } else if (after < before) {
        if (lo >= after) lo = lo >= before ? lo + diff : after;
        if (hi >= after) hi = hi >= before ? hi + diff : after;
    }
    [sci message:SCI_SETSEL wParam:(uptr_t)lo lParam:hi];
    [self refreshChrome];
}

- (void)deleteSelection {
    [self.sci message:SCI_CLEAR];
    [self refreshChrome];
}

#pragma mark - Clipboard

- (void)copyToClipboard:(NSString *)string {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:string ?: @"" forType:NSPasteboardTypeString];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppPasteboardWrittenNotification object:self];
}

- (NSString *)allDocumentNames {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.documents) [out addObject:d.displayName ?: @""];
    return [out componentsJoinedByString:@"\n"];
}

- (NSString *)allDocumentPaths {
    NSMutableArray *out = [NSMutableArray array];
    // IDM_EDIT_COPY_ALL_PATHS lists every tab: an untitled one by its name, which is
    // what getFullPathName holds for it.
    for (NppDocument *d in self.documents) [out addObject:d.path ?: (d.displayName ?: @"")];
    return [out componentsJoinedByString:@"\n"];
}

#pragma mark - Insert

- (void)insertDateTimeShort:(BOOL)shortForm {
    // As Windows writes it: the time (no seconds) and then the date, or the
    // other way round with "Reverse default date time order"; and it goes in
    // place of the selection.
    NSDateFormatter *dateOnly = [[NSDateFormatter alloc] init];
    dateOnly.dateStyle = shortForm ? NSDateFormatterShortStyle : NSDateFormatterLongStyle;
    dateOnly.timeStyle = NSDateFormatterNoStyle;
    NSDateFormatter *timeOnly = [[NSDateFormatter alloc] init];
    timeOnly.dateStyle = NSDateFormatterNoStyle;
    timeOnly.timeStyle = NSDateFormatterShortStyle;
    NSDate *now = [NSDate date];
    NSString *date = [dateOnly stringFromDate:now], *time = [timeOnly stringFromDate:now];
    NSString *stamp = [NppPreferences shared].reverseDateTimeOrder
        ? [NSString stringWithFormat:@"%@ %@", date, time]
        : [NSString stringWithFormat:@"%@ %@", time, date];
    [self replaceSelectionWith:stamp];
}

- (void)replaceSelectionWith:(NSString *)text {
    ScintillaView *sci = self.sci;
    long start = [sci message:SCI_GETSELECTIONSTART];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_REPLACESEL parameter:0 value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(start + Utf8Length(text)) lParam:0];
    [self refreshChrome];
}

- (void)insertCustomDateTime:(NSString *)format {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = format.length ? format : @"yyyy-MM-dd HH:mm:ss";
    [self replaceSelectionWith:[f stringFromDate:[NSDate date]]];
}

- (void)insertAtCaret:(NSString *)text {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:pos value:text];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)(pos + Utf8Length(text)) lParam:0];
    [self refreshChrome];
}

#pragma mark - Comments

- (void)uncommentLines {
    NSString *token = self.currentDocument.language.commentLine;
    if (!token.length) { NppBeep(); return; }
    [self transformSelectedLines:^NSArray *(NSArray *bodies) {
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *line in bodies) {
            NSUInteger i = 0;
            while (i < line.length &&
                   [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:i]]) i++;
            NSString *indent = [line substringToIndex:i];
            NSString *rest = [line substringFromIndex:i];
            if ([rest hasPrefix:token]) {
                rest = [rest substringFromIndex:token.length];
                if ([rest hasPrefix:@" "]) rest = [rest substringFromIndex:1];
            }
            [out addObject:[indent stringByAppendingString:rest]];
        }
        return out;
    }];
}

- (void)streamComment:(BOOL)comment {
    NSString *open = self.currentDocument.language.commentStart;
    NSString *close = self.currentDocument.language.commentEnd;
    if (!open.length || !close.length) { NppBeep(); return; }

    if (comment) { [self toggleBlockComment]; return; }

    [self transformSelectedText:^NSString *(NSString *sel) {
        NSString *r = sel;
        if ([r hasPrefix:open]) r = [r substringFromIndex:open.length];
        if ([r hasSuffix:close]) r = [r substringToIndex:r.length - close.length];
        return r;
    }];
}

#pragma mark - Read-only

- (void)setReadOnly:(BOOL)readOnly {
    [self.sci message:SCI_SETREADONLY wParam:(uptr_t)(readOnly ? 1 : 0) lParam:0];
    self.currentDocument.userReadOnly = readOnly;
    [self refreshChrome];
}

- (BOOL)isReadOnly { return [self.sci message:SCI_GETREADONLY] != 0; }

- (void)setReadOnlyForAllDocuments:(BOOL)readOnly {
    NSInteger restore = [self.documents indexOfObject:self.currentDocument];
    for (NSInteger i = 0; i < (NSInteger)self.documents.count; ++i) {
        [self selectDocumentAtIndex:i];
        [self setReadOnly:readOnly];
    }
    if (restore != NSNotFound) [self selectDocumentAtIndex:restore];
}

@end
