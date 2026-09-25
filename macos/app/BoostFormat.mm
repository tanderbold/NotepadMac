#import "BoostFormat.h"
#include <vector>

namespace {

struct Formatter {
    std::vector<unichar> fmt;
    size_t pos = 0, end = 0;
    enum State { None, Copy, NextLower, NextUpper, Lower, Upper };
    State state = Copy, restore = Copy;
    bool haveConditional = false;
    NSMutableString *out = nil;
    NSArray *groups = nil;
    // Read only when the format names them ($` $' $PREMATCH...): the text after
    // a match runs to the end of the document, and building it for every match
    // made Replace All quadratic in the number of matches.
    NSString *(^prefixOf)(void) = nil, *(^suffixOf)(void) = nil;
    NSString *prefix() const { return prefixOf ? prefixOf() : nil; }
    NSString *suffix() const { return suffixOf ? suffixOf() : nil; }
    NSInteger lastClosed = -1;
    NSInteger (^named)(NSString *) = nil;
    static const unsigned kMaxDepth = 200;

    static unichar Case(unichar c, bool upper) {
        NSString *one = [NSString stringWithCharacters:&c length:1];
        NSString *changed = upper ? one.uppercaseString : one.lowercaseString;
        return changed.length == 1 ? [changed characterAtIndex:0] : c;
    }

    void put(unichar c) {
        switch (state) {
            case None: return;
            case NextLower: c = Case(c, false); state = restore; break;
            case NextUpper: c = Case(c, true); state = restore; break;
            case Lower: c = Case(c, false); break;
            case Upper: c = Case(c, true); break;
            default: break;
        }
        [out appendFormat:@"%C", c];
    }
    void put(NSString *s) {
        if (![s isKindOfClass:[NSString class]]) return;
        for (NSUInteger i = 0; i < s.length; ++i) put([s characterAtIndex:i]);
    }
    NSString *group(NSInteger n) const {
        if (n < 0 || n >= (NSInteger)groups.count) return nil;
        id g = groups[(NSUInteger)n];
        return [g isKindOfClass:[NSString class]] ? g : nil;
    }
    bool matched(NSInteger n) const { return group(n) != nil; }

    static int Digit(unichar c, int radix) {
        int d = -1;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
        return (d >= 0 && d < radix) ? d : -1;
    }
    /// global_toi: as many digits as there are before `limit`, -1 for none.
    int toi(size_t &p, size_t limit, int radix) const {
        long value = -1;
        while (p < limit && Digit(fmt[p], radix) >= 0) {
            value = (value < 0 ? 0 : value) * radix + Digit(fmt[p], radix);
            if (value > INT_MAX / radix) break;
            ++p;
        }
        return (int)value;
    }
    bool matchesAt(size_t p, const char *word) const {
        size_t n = strlen(word);
        if (end - p < n) return false;
        for (size_t i = 0; i < n; ++i) if (fmt[p + i] != (unichar)word[i]) return false;
        return true;
    }

    void formatAll(unsigned depth) {
        while (pos != end) {
            unichar c = fmt[pos];
            switch (c) {
                case '\\': formatEscape(); break;
                case '(':
                    if (depth < kMaxDepth) {
                        ++pos;
                        bool had = haveConditional;
                        haveConditional = false;
                        formatUntilScopeEnd(depth);
                        haveConditional = had;
                        if (pos == end) return;
                        ++pos;                                   // the closing ')'
                        break;
                    }
                    put(c); ++pos; break;
                case ')': return;
                case ':':
                    if (haveConditional) return;
                    put(c); ++pos; break;
                case '?':
                    if (depth < kMaxDepth) { ++pos; formatConditional(depth); break; }
                    put(c); ++pos; break;
                case '$': formatPerl(); break;
                default: put(c); ++pos; break;
            }
        }
    }

    void formatUntilScopeEnd(unsigned depth) {
        do {
            formatAll(++depth);
            if (pos == end || fmt[pos] == ')') return;
            put(fmt[pos++]);
        } while (pos != end);
    }

    void formatPerl() {
        if (++pos == end) { --pos; put(fmt[pos]); ++pos; return; }   // a trailing '$'
        bool brace = false;
        size_t save = pos;
        switch (fmt[pos]) {
            case '&': ++pos; put(group(0)); return;
            case '`': ++pos; put(prefix()); return;
            case '\'': ++pos; put(suffix()); return;
            case '$': put(fmt[pos++]); return;
            case '+':
                if (++pos != end && fmt[pos] == '{') {
                    size_t base = ++pos;
                    while (pos != end && fmt[pos] != '}') ++pos;
                    if (pos != end) {
                        NSString *name = [NSString stringWithCharacters:&fmt[base] length:pos - base];
                        put(group(named ? named(name) : -1));
                        ++pos;
                        return;
                    }
                    pos = base - 1;
                }
                put(group(groups.count > 1 ? (NSInteger)groups.count - 1 : 1));
                return;
            case '{':
                brace = true;
                ++pos;
                [[fallthrough]];
            default: {
                int v = toi(pos, end, 10);
                if (v < 0 || (brace && (pos == end || fmt[pos] != '}'))) {
                    if (!perlVerb(brace)) {
                        pos = save - 1;                            // the '$' stays as it is
                        put(fmt[pos]);
                        ++pos;
                    }
                    return;
                }
                put(group(v));
                if (brace) ++pos;
            }
        }
    }

    bool perlVerb(bool brace) {
        if (pos == end) return false;
        if (brace && fmt[pos] == '^') ++pos;
        struct { const char *word; int what; } verbs[] = {
            {"MATCH", 0}, {"PREMATCH", 1}, {"POSTMATCH", 2}, {"LAST_PAREN_MATCH", 3},
            {"LAST_SUBMATCH_RESULT", 4}, {"^N", 4},
        };
        for (auto &verb : verbs) {
            if (!matchesAt(pos, verb.word)) continue;
            size_t n = strlen(verb.word);
            pos += n;
            if (brace) {
                if (pos != end && fmt[pos] == '}') ++pos;
                else { pos -= n; return false; }
            }
            switch (verb.what) {
                case 0: put(group(0)); break;
                case 1: put(prefix()); break;
                case 2: put(suffix()); break;
                case 3: put(group(groups.count > 1 ? (NSInteger)groups.count - 1 : 1)); break;
                default: put(group(lastClosed)); break;
            }
            return true;
        }
        return false;
    }

    void formatEscape() {
        if (++pos == end) { put('\\'); return; }
        unichar c = fmt[pos];
        switch (c) {
            case 'a': put('\a'); ++pos; return;
            case 'f': put('\f'); ++pos; return;
            case 'n': put('\n'); ++pos; return;
            case 'r': put('\r'); ++pos; return;
            case 't': put('\t'); ++pos; return;
            case 'v': put('\v'); ++pos; return;
            case 'e': put((unichar)27); ++pos; return;
            case 'x': {
                if (++pos == end) { put('x'); return; }
                if (fmt[pos] == '{') {
                    ++pos;
                    int v = toi(pos, end, 16);
                    if (v < 0) { put('x'); put('{'); return; }
                    if (pos == end || fmt[pos] != '}') {
                        --pos;
                        while (fmt[pos] != '\\') --pos;
                        ++pos;
                        put(fmt[pos++]);
                        return;
                    }
                    ++pos;
                    putCodePoint((UTF32Char)v);
                    return;
                }
                int v = toi(pos, std::min(end, pos + 2), 16);
                if (v < 0) { --pos; put(fmt[pos++]); return; }
                put((unichar)v);
                return;
            }
            case 'c':
                if (++pos == end) { --pos; put(fmt[pos++]); return; }
                put((unichar)(fmt[pos++] % 32));
                return;
            case 'l': ++pos; restore = state; state = NextLower; return;
            case 'L': ++pos; state = Lower; return;
            case 'u': ++pos; restore = state; state = NextUpper; return;
            case 'U': ++pos; state = Upper; return;
            case 'E': ++pos; state = Copy; return;
            default: break;
        }
        // \1 to \9, one digit only; \0 starts an octal escape.
        size_t p = pos;
        int v = toi(p, std::min(end, pos + 1), 10);
        if (v > 0) { pos = p; put(group(v)); return; }
        if (v == 0) {
            // \0 and up to three more octal digits, read from the 0.
            size_t q = pos;
            int octal = toi(q, std::min(end, pos + 4), 8);
            pos = q;
            put((unichar)octal);
            return;
        }
        put(fmt[pos++]);                                   // anything else as it is
    }

    void formatConditional(unsigned depth) {
        if (pos == end) { put('?'); return; }
        int v;
        if (fmt[pos] == '{') {
            size_t base = pos;
            ++pos;
            v = toi(pos, end, 10);
            if (v < 0) {
                while (pos != end && fmt[pos] != '}') ++pos;
                NSString *name = [NSString stringWithCharacters:&fmt[base + 1] length:pos - base - 1];
                v = named ? (int)named(name) : -1;
            }
            if (v < 0 || pos == end || fmt[pos] != '}') { pos = base; put('?'); return; }
            ++pos;
        } else {
            v = toi(pos, std::min(end, pos + 2), 10);
        }
        if (v < 0) { put('?'); return; }

        if (matched(v)) {
            haveConditional = true;
            formatAll(++depth);
            haveConditional = false;
            if (pos != end && fmt[pos] == ':') {
                ++pos;
                State saved = state;
                state = None;
                formatUntilScopeEnd(depth);
                state = saved;
            }
        } else {
            State saved = state;
            state = None;
            haveConditional = true;
            formatAll(++depth);
            haveConditional = false;
            state = saved;
            if (pos != end && fmt[pos] == ':') {
                ++pos;
                formatUntilScopeEnd(depth);
            }
        }
    }

    void putCodePoint(UTF32Char cp) {
        if (cp > 0xFFFF) {
            unichar pair[2];
            if (CFStringGetSurrogatePairForLongCharacter(cp, pair)) { put(pair[0]); put(pair[1]); }
            return;
        }
        put((unichar)cp);
    }
};

}  // namespace

NSString *NppBoostFormat(NSString *format, NSArray *groups, NSString *(^prefix)(void), NSString *(^suffix)(void),
                         NSInteger lastClosedGroup, NSInteger (^groupNamed)(NSString *)) {
    Formatter f;
    f.fmt.resize(format.length);
    if (format.length) [format getCharacters:f.fmt.data() range:NSMakeRange(0, format.length)];
    f.end = f.fmt.size();
    f.out = [NSMutableString string];
    f.groups = groups;
    f.prefixOf = prefix;
    f.suffixOf = suffix;
    f.lastClosed = lastClosedGroup;
    f.named = groupNamed;
    // format() is one format_all: a stray ')' ends the replacement there.
    f.formatAll(0);
    return f.out;
}
