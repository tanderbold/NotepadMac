#import "TagMatch.h"
#import "SettingsCommands.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"
#import "SciLexer.h"
#import "LanguageCatalog.h"
#include <string>
#include <vector>
#include <utility>

namespace {

struct FindResult { long start = -1, end = -1; bool success = false; };
struct TagsPos { long tagOpenStart = -1, tagNameEnd = -1, tagOpenEnd = -1, tagCloseStart = -1, tagCloseEnd = -1; };

bool IsWhitespace(long c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r'; }

/// XmlMatchedTagsHighlighter, over a ScintillaView.
struct Matcher {
    ScintillaView *sci;
    bool matchCase;

    long charAt(long p) { return (long)(unsigned char)[sci message:SCI_GETCHARAT wParam:(uptr_t)p]; }
    long styleAt(long p) { return [sci message:SCI_GETSTYLEAT wParam:(uptr_t)p]; }
    bool quotedOrComment(long s) { return s == SCE_H_DOUBLESTRING || s == SCE_H_SINGLESTRING || s == SCE_H_COMMENT; }

    FindResult findText(const char *text, long start, long end) {
        FindResult r;
        Sci_TextToFindFull search{};
        search.lpstrText = text;
        search.chrg.cpMin = start;
        search.chrg.cpMax = end;
        long hit = [sci message:SCI_FINDTEXTFULL wParam:matchCase ? SCFIND_MATCHCASE : 0 lParam:(sptr_t)&search];
        if (hit == -1) return r;
        r.success = true;
        r.start = search.chrgText.cpMin;
        r.end = search.chrgText.cpMax;
        return r;
    }

    long findCloseAngle(long startPosition, long endPosition) {
        if (startPosition > endPosition) std::swap(startPosition, endPosition);
        FindResult closeAngle;
        do {
            closeAngle = findText(">", startPosition, endPosition);
            if (closeAngle.success) {
                if (!quotedOrComment(styleAt(closeAngle.start))) return closeAngle.start;
                startPosition = closeAngle.end;
            }
        } while (closeAngle.success);
        return -1;
    }

    FindResult findOpenTag(const std::string &tagName, long start, long end) {
        std::string search = "<" + tagName;
        FindResult found, result;
        long searchStart = start;
        bool forward = start < end;
        do {
            result = findText(search.c_str(), searchStart, end);
            if (result.success) {
                long next = charAt(result.end);
                long st = styleAt(result.start);
                if (st != SCE_H_CDATA && !quotedOrComment(st)) {
                    if (next == '>') { found.end = result.end; found.success = true; }
                    else if (IsWhitespace(next)) {
                        long close = findCloseAngle(result.end, forward ? end : start);
                        if (close != -1 && charAt(close - 1) != '/') { found.end = close; found.success = true; }
                    }
                }
            }
            searchStart = forward ? result.end + 1 : result.start - 1;
        } while (result.success && !found.success);
        found.start = result.start;
        return found;
    }

    FindResult findCloseTag(const std::string &tagName, long start, long end) {
        std::string search = "</" + tagName;
        FindResult found, result;
        long searchStart = start;
        bool forward = start < end;
        bool valid;
        do {
            valid = false;
            result = findText(search.c_str(), searchStart, end);
            if (result.success) {
                long next = charAt(result.end);
                long st = styleAt(result.start);
                searchStart = forward ? result.end + 1 : result.start - 1;
                if (st != SCE_H_CDATA && !quotedOrComment(st)) {
                    if (next == '>') {
                        valid = true;
                        found.start = result.start; found.end = result.end; found.success = true;
                    } else if (IsWhitespace(next)) {
                        long ws = result.end;
                        do { ++ws; next = charAt(ws); } while (IsWhitespace(next));
                        if (next == '>') {
                            valid = true;
                            found.start = result.start; found.end = ws; found.success = true;
                        }
                    }
                }
            }
        } while (result.success && !valid);
        return found;
    }

    std::string tagNameAt(long position, long docLength) {
        std::string name;
        long next = charAt(position);
        while (position < docLength && !IsWhitespace(next) && next != '/' && next != '>' && next != '"' && next != '\'') {
            name.push_back((char)next);
            next = charAt(++position);
        }
        return name;
    }

    bool matchedTagsPos(TagsPos &tags) {
        bool tagFound = false;
        long caret = [sci message:SCI_GETCURRENTPOS];
        long searchStart = caret, st;
        FindResult openFound;
        do {
            openFound = findText("<", searchStart, 0);
            st = styleAt(openFound.start);
            searchStart = openFound.start - 1;
        } while (openFound.success && quotedOrComment(st) && searchStart > 0);
        if (!openFound.success || st == SCE_H_CDATA) return false;

        FindResult closeFound;
        searchStart = openFound.start;
        do {
            closeFound = findText(">", searchStart, caret);
            st = styleAt(closeFound.start);
            searchStart = closeFound.end;
        } while (closeFound.success && quotedOrComment(st) && searchStart <= caret);
        if (closeFound.success) return false;

        long docLength = [sci message:SCI_GETLENGTH];
        if (charAt(openFound.start + 1) == '/') {
            // In a closing tag.
            tags.tagCloseStart = openFound.start;
            FindResult endClose = findText(">", caret, docLength);
            if (endClose.success) tags.tagCloseEnd = endClose.end;
            std::string tagName = tagNameAt(openFound.start + 2, docLength);
            if (tagName.empty()) return false;
            long currentEnd = tags.tagCloseStart, openRemaining = 1;
            FindResult nextOpen;
            do {
                nextOpen = findOpenTag(tagName, currentEnd, 0);
                if (nextOpen.success) {
                    --openRemaining;
                    long currentStart = nextOpen.end, closesFound = 0;
                    bool forward = currentStart < currentEnd;
                    FindResult between;
                    do {
                        between = findCloseTag(tagName, currentStart, currentEnd);
                        if (between.success) {
                            ++closesFound;
                            currentStart = forward ? between.end : between.start - 1;
                        }
                    } while (between.success);
                    if (closesFound == 0 && openRemaining == 0) {
                        tags.tagOpenStart = nextOpen.start;
                        tags.tagOpenEnd = nextOpen.end + 1;
                        tags.tagNameEnd = nextOpen.start + (long)tagName.size() + 1;
                        tagFound = true;
                    } else {
                        openRemaining += closesFound;
                        currentEnd = nextOpen.start;
                    }
                }
            } while (!tagFound && openRemaining > 0 && nextOpen.success);
            return tagFound;
        }

        // In an opening tag.
        long position = openFound.start + 1;
        tags.tagOpenStart = openFound.start;
        std::string tagName = tagNameAt(position, docLength);
        if (tagName.empty()) return false;
        position += (long)tagName.size();
        tags.tagNameEnd = openFound.start + (long)tagName.size() + 1;
        long closeAngle = findCloseAngle(position, docLength);
        if (closeAngle == -1) return false;
        tags.tagOpenEnd = closeAngle + 1;
        if (charAt(closeAngle - 1) == '/') {
            tags.tagCloseStart = tags.tagCloseEnd = -1;      // self-closing
            return true;
        }
        long currentStart = tags.tagOpenEnd, closeRemaining = 1;
        FindResult nextClose;
        do {
            nextClose = findCloseTag(tagName, currentStart, docLength);
            if (nextClose.success) {
                --closeRemaining;
                long currentEnd = nextClose.start, opensFound = 0;
                FindResult between;
                do {
                    between = findOpenTag(tagName, currentStart, currentEnd);
                    if (between.success) { ++opensFound; currentStart = between.end; }
                } while (between.success);
                if (opensFound == 0 && closeRemaining == 0) {
                    tags.tagCloseStart = nextClose.start;
                    tags.tagCloseEnd = nextClose.end + 1;
                    tagFound = true;
                } else {
                    closeRemaining += opensFound;
                    currentStart = nextClose.end;
                }
            }
        } while (!tagFound && closeRemaining > 0 && nextClose.success);
        return tagFound;
    }

    /// getAttributesPos: the attribute="value" pairs between two positions.
    std::vector<std::pair<long, long>> attributes(long start, long end) {
        std::vector<std::pair<long, long>> out;
        enum { invalid, key, preAssign, assign, string, singleString, value, valid } state = invalid;
        long startPos = -1, i = 0, len = end - start + 1;
        int oneMore = 1;
        for (; i < len; ++i) {
            long c = charAt(start + i);
            switch (c) {
                case ' ': case '\t': case '\n': case '\r':
                    if (state == key) state = preAssign;
                    else if (state == value) { state = valid; oneMore = 0; }
                    break;
                case '=':
                    if (state == key || state == preAssign) state = assign;
                    else if (state == assign || state == value) state = invalid;
                    break;
                case '"':
                    if (state == string) { state = valid; oneMore = 1; }
                    else if (state == key || state == preAssign || state == value) state = invalid;
                    else if (state == assign) state = string;
                    break;
                case '\'':
                    if (state == singleString) { state = valid; oneMore = 1; }
                    else if (state == key || state == preAssign || state == value) state = invalid;
                    else if (state == assign) state = singleString;
                    break;
                default:
                    if (state == invalid) { state = key; startPos = i; }
                    else if (state == preAssign) state = invalid;
                    else if (state == assign) state = value;
            }
            if (state == valid) {
                out.emplace_back(start + startPos, start + i + oneMore);
                state = invalid;
            }
        }
        if (state == value) out.emplace_back(start + startPos, start + i - 1);
        return out;
    }
};

}  // namespace

static long Bgr(NSColor *c, long fallback) {
    NSColor *s = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!s) return fallback;
    return lround(s.redComponent * 255) | (lround(s.greenComponent * 255) << 8) | (lround(s.blueComponent * 255) << 16);
}

@implementation EditorController (TagMatch)

- (BOOL)highlightMatchingTags {
    ScintillaView *sci = self.sci;
    long length = [sci message:SCI_GETLENGTH];
    for (int ind : {NPPMAC_TAGMATCH_INDICATOR, NPPMAC_TAGATTR_INDICATOR}) {
        [sci message:SCI_SETINDICATORCURRENT wParam:(uptr_t)ind lParam:0];
        [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
    }
    NppPreferences *p = [NppPreferences shared];
    NSString *lang = self.currentDocument.language.name ?: @"";
    if (!p.highlightMatchingTags) return NO;
    if (![@[@"xml", @"html", @"php", @"asp", @"jsp"] containsObject:lang]) return NO;

    Matcher m{sci, [lang isEqualToString:@"xml"] ||
                   ([lang isEqualToString:@"html"] && [self.currentDocument.path.pathExtension.lowercaseString isEqualToString:@"xhtml"])};
    // Inside a code block of PHP, ASP or JSP there is no markup to match.
    if (![lang isEqualToString:@"xml"] && ![lang isEqualToString:@"html"]) {
        const char *begin = [lang isEqualToString:@"php"] ? "<?" : "<%";
        const char *end = [lang isEqualToString:@"php"] ? "?>" : "%>";
        long caret = [sci message:SCI_GETCURRENTPOS] + 1;
        FindResult startFound = m.findText(begin, caret, 0), endFound = m.findText(end, caret, 0);
        if (startFound.success && (!endFound.success || endFound.start <= startFound.end)) return NO;
    }

    long targetStart = [sci message:SCI_GETTARGETSTART], targetEnd = [sci message:SCI_GETTARGETEND];
    long flags = [sci message:SCI_GETSEARCHFLAGS];
    // Styles are what tell markup from strings and comments.
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    TagsPos tags;
    BOOL found = m.matchedTagsPos(tags);
    if (found) {
        StyleCatalog *styles = [StyleCatalog sharedCatalog];
        int indicators[2] = {NPPMAC_TAGMATCH_INDICATOR, NPPMAC_TAGATTR_INDICATOR};
        NSString *names[2] = {@"Tags match highlighting", @"Tags attribute"};
        long fallbacks[2] = {0xFF0080, 0x00FFFF};
        for (int i = 0; i < 2; ++i) {
            [sci message:SCI_INDICSETSTYLE wParam:(uptr_t)indicators[i] lParam:INDIC_ROUNDBOX];
            [sci message:SCI_INDICSETALPHA wParam:(uptr_t)indicators[i] lParam:100];
            [sci message:SCI_INDICSETUNDER wParam:(uptr_t)indicators[i] lParam:1];
            [sci message:SCI_INDICSETFORE wParam:(uptr_t)indicators[i]
                  lParam:Bgr(styles.globalStyles[names[i]].background, fallbacks[i])];
        }
        [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_TAGMATCH_INDICATOR lParam:0];
        long openTagTail = 2;
        if (tags.tagCloseStart != -1 && tags.tagCloseEnd != -1) {
            [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)tags.tagCloseStart lParam:tags.tagCloseEnd - tags.tagCloseStart];
            openTagTail = 1;
        }
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)tags.tagOpenStart lParam:tags.tagNameEnd - tags.tagOpenStart];
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)(tags.tagOpenEnd - openTagTail) lParam:openTagTail];
        if (p.highlightTagAttributes) {
            [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_TAGATTR_INDICATOR lParam:0];
            for (auto &a : m.attributes(tags.tagNameEnd, tags.tagOpenEnd - openTagTail)) {
                [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)a.first lParam:a.second - a.first];
            }
        }
    }
    [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)targetStart lParam:targetEnd];
    [sci message:SCI_SETSEARCHFLAGS wParam:(uptr_t)flags lParam:0];
    return found;
}

- (NSArray<NSValue *> *)rangesOfIndicator:(int)indicator {
    ScintillaView *sci = self.sci;
    NSMutableArray *out = [NSMutableArray array];
    long length = [sci message:SCI_GETLENGTH], pos = 0;
    while (pos < length) {
        long end = [sci message:SCI_INDICATOREND wParam:(uptr_t)indicator lParam:pos];
        if ([sci message:SCI_INDICATORVALUEAT wParam:(uptr_t)indicator lParam:pos]) {
            [out addObject:[NSValue valueWithRange:NSMakeRange((NSUInteger)pos, (NSUInteger)(end - pos))]];
        }
        if (end <= pos) break;
        pos = end;
    }
    return out;
}

@end
