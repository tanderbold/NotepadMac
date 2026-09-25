#import "NppRegex.h"
#include <dlfcn.h>
#include <string>
#include <vector>

// libpcre2 is on every macOS that matters, but there is no pcre2.h in the SDK,
// so the handful of entry points that are needed are declared here. They are
// the 8-bit variants, which is what the _8 suffix means.
typedef void *(*npp_pcre2_compile)(const uint8_t *pattern, size_t length, uint32_t options,
                                   int *errorcode, size_t *erroroffset, void *context);
typedef void *(*npp_pcre2_match_data_create_from_pattern)(const void *code, void *context);
typedef int (*npp_pcre2_match)(const void *code, const uint8_t *subject, size_t length,
                               size_t startoffset, uint32_t options,
                               void *matchData, void *context);
typedef size_t *(*npp_pcre2_get_ovector_pointer)(void *matchData);
typedef void (*npp_pcre2_match_data_free)(void *matchData);
typedef void (*npp_pcre2_code_free)(void *code);
typedef int (*npp_pcre2_get_error_message)(int errorcode, uint8_t *buffer, size_t length);
typedef int (*npp_pcre2_substring_number_from_name)(const void *code, const uint8_t *name);

// The option values are those of PCRE2 10.x. They are checked against the
// library's own behaviour by a test, rather than being trusted from memory.
static const uint32_t kDotAll = 0x00000020u;
static const uint32_t kMultiline = 0x00000400u;
static const uint32_t kUTF = 0x00080000u;
/// PCRE2_UCP: \w, \b, \d and the POSIX classes know every script, as Boost's do in
/// Notepad++ (wide characters) - "café" is a word, \w matches "я".
static const uint32_t kUCP = 0x00020000u;
/// PCRE2_ALT_CIRCUMFLEX: '^' also matches after a newline that ends the
/// subject, as Boost's match_start_line does ("a\n" has two line starts).
static const uint32_t kAltCircumflex = 0x00200000u;

static npp_pcre2_compile gCompile;
static npp_pcre2_match_data_create_from_pattern gMatchDataCreate;
static npp_pcre2_match gMatch;
static npp_pcre2_get_ovector_pointer gOvector;
static npp_pcre2_match_data_free gMatchDataFree;
static npp_pcre2_code_free gCodeFree;
static npp_pcre2_get_error_message gErrorMessage;
static npp_pcre2_substring_number_from_name gNumberFromName;
static BOOL gLoaded;

static void LoadPCRE2(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/usr/lib/libpcre2-8.dylib", RTLD_LAZY);
        if (!handle) return;
        gCompile = (npp_pcre2_compile)dlsym(handle, "pcre2_compile_8");
        gMatchDataCreate = (npp_pcre2_match_data_create_from_pattern)
            dlsym(handle, "pcre2_match_data_create_from_pattern_8");
        gMatch = (npp_pcre2_match)dlsym(handle, "pcre2_match_8");
        gOvector = (npp_pcre2_get_ovector_pointer)dlsym(handle, "pcre2_get_ovector_pointer_8");
        gMatchDataFree = (npp_pcre2_match_data_free)dlsym(handle, "pcre2_match_data_free_8");
        gCodeFree = (npp_pcre2_code_free)dlsym(handle, "pcre2_code_free_8");
        gErrorMessage = (npp_pcre2_get_error_message)dlsym(handle, "pcre2_get_error_message_8");
        gNumberFromName = (npp_pcre2_substring_number_from_name)dlsym(handle, "pcre2_substring_number_from_name_8");
        gLoaded = gCompile && gMatchDataCreate && gMatch && gOvector &&
                  gMatchDataFree && gCodeFree;
    });
}

@interface NppRegex ()
@property (nonatomic) void *code;
@end

@implementation NppRegex

+ (BOOL)available { LoadPCRE2(); return gLoaded; }

/// Boost refuses '^' and '$' in the middle of a CRLF (perl_matcher::
/// match_start_line / match_end_line check for '\r' before and '\n' at the
/// position); PCRE2 takes the LF there for a newline of its own. So every
/// anchor outside a class, an escape or a comment gets that same condition:
/// without it `$` matched twice at each CRLF and `\s+$` swallowed the CR.
/// The pattern is rewritten as UTF-8 bytes (every character that means
/// something here is ASCII), and `origin` keeps where each output byte came
/// from, so a compile error can still name an offset in what the user typed.
static const char kNotInsideCRLF[] = "(?!(?<=\\r)\\n))";

static std::string BoostLineAnchors(const std::string &in, std::vector<size_t> &origin) {
    std::string out;
    out.reserve(in.size() + 16);
    origin.clear();
    auto copy = [&](size_t from, size_t to) {
        for (size_t k = from; k < to && k < in.size(); ++k) { out += in[k]; origin.push_back(k); }
    };
    auto until = [&](size_t from, const char *what) {   // the index just past `what`, or the end
        size_t found = in.find(what, from);
        return found == std::string::npos ? in.size() : found + strlen(what);
    };
    const size_t n = in.size();
    size_t i = 0;
    while (i < n) {
        char c = in[i];
        if (c == '\\') {
            char e = i + 1 < n ? in[i + 1] : 0;
            size_t to = i + 2;
            if (e == 'Q') to = until(i + 2, "\\E");                       // \Q...\E is literal
            else if ((e == 'p' || e == 'P') && i + 2 < n && in[i + 2] == '{') to = until(i + 2, "}");   // \p{^Lu}
            else if (e == 'c') to = i + 3;                                  // \c^ is a control character
            copy(i, to); i = to; continue;
        }
        if (c == '[') {                                                     // a class: nothing in it is an anchor
            size_t j = i + 1;
            if (j < n && in[j] == '^') ++j;
            if (j < n && in[j] == ']') ++j;
            while (j < n && in[j] != ']') {
                if (in[j] == '\\') j = (j + 1 < n && in[j + 1] == 'Q') ? until(j + 2, "\\E") : j + 2;
                else if (in[j] == '[' && j + 1 < n && (in[j + 1] == ':' || in[j + 1] == '.' || in[j + 1] == '=')) {
                    char close[3] = {in[j + 1], ']', 0};
                    j = until(j + 2, close);
                } else ++j;
            }
            copy(i, j + 1); i = j + 1; continue;
        }
        if (c == '(' && i + 2 < n && in[i + 1] == '?' && in[i + 2] == '#') {   // (?#comment)
            size_t to = until(i, ")"); copy(i, to); i = to; continue;
        }
        if (c == '(' && i + 2 < n && in[i + 1] == '?' && in[i + 2] == '^') {   // (?^) resets options
            copy(i, i + 3); i += 3; continue;
        }
        if (c == '(' && i + 1 < n && in[i + 1] == '*') {                       // (*VERB:name)
            size_t to = until(i, ")"); copy(i, to); i = to; continue;
        }
        if (c == '^' || c == '$') {
            std::string anchor = std::string("(?:") + c + kNotInsideCRLF;
            for (char a : anchor) { out += a; origin.push_back(i); }
            ++i; continue;
        }
        copy(i, i + 1); ++i;
    }
    origin.push_back(n);
    return out;
}

/// Compiles, returning either the code or the reason it would not compile.
static void *CompilePattern(NSString *pattern, NSString **errorOut) {
    LoadPCRE2();
    if (!gLoaded) {
        if (errorOut) *errorOut = @"libpcre2 is not available";
        return NULL;
    }
    NSData *bytes = [pattern dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes) {
        if (errorOut) *errorOut = @"the pattern is not valid UTF-8";
        return NULL;
    }
    std::vector<size_t> origin;
    std::string rewritten = BoostLineAnchors(std::string((const char *)bytes.bytes, bytes.length), origin);
    // Scintilla searches with Boost, whose line separators (is_separator) are
    // \r\n, \r, \n, \f, U+0085, U+2028 and U+2029: '$' stands before each and
    // '.' does not swallow one. PCRE2 defaults to \n alone, which puts a stray
    // \r on the end of anything matched up to '$' in a CRLF file; (*ANY) is the
    // convention nearest Boost's (it adds only \v). The newline convention has
    // to be the first thing in the pattern.
    static const char kConvention[] = "(*ANY)";
    const size_t prefix = strlen(kConvention);
    rewritten.insert(0, kConvention);

    int errorCode = 0;
    size_t errorOffset = 0;
    // The same options upstream searches with: SCFIND_REGEXP_DOTMATCHESNL, and
    // '^' anchored per line. See functionParser.cpp.
    void *code = gCompile((const uint8_t *)rewritten.data(), rewritten.size(),
                          kMultiline | kDotAll | kUTF | kUCP | kAltCircumflex,
                          &errorCode, &errorOffset, NULL);
    if (!code && errorOut) {
        uint8_t message[256] = {0};
        if (gErrorMessage) gErrorMessage(errorCode, message, sizeof message);
        // Counted in the pattern as written, not as rewritten.
        size_t at = errorOffset >= prefix ? errorOffset - prefix : 0;
        size_t typed = at < origin.size() ? origin[at] : bytes.length;
        *errorOut = [NSString stringWithFormat:@"%s (at offset %zu)", message, typed];
    }
    return code;
}

+ (NSString *)compileErrorForPattern:(NSString *)pattern {
    NSString *error = nil;
    void *code = CompilePattern(pattern, &error);
    if (code) { gCodeFree(code); return nil; }
    return error ?: @"the pattern would not compile";
}

+ (instancetype)regexWithPattern:(NSString *)pattern {
    if (!pattern.length) return nil;

    // The catalogue runs the same few patterns against every document, and a
    // name pattern runs once per match, so compiling is worth doing once.
    static NSMutableDictionary<NSString *, id> *cache;
    static dispatch_once_t once;
    static NSLock *lock;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; lock = [NSLock new]; });

    [lock lock];
    id cached = cache[pattern];
    [lock unlock];
    if (cached) return cached == [NSNull null] ? nil : cached;

    void *code = CompilePattern(pattern, NULL);
    NppRegex *regex = nil;
    if (code) {
        regex = [[NppRegex alloc] init];
        regex.code = code;
    }
    [lock lock];
    cache[pattern] = regex ?: (id)[NSNull null];
    [lock unlock];
    return regex;
}

- (void)dealloc {
    // Instances live in the cache for the life of the process, so this runs only
    // if one is discarded; freeing is still the right thing to do.
    if (_code && gCodeFree) gCodeFree(_code);
}

/// Steps past one UTF-8 character, so an empty match cannot stall the loop and
/// cannot leave the offset inside a character.
static size_t NextCharacter(const uint8_t *bytes, size_t length, size_t from) {
    size_t i = from + 1;
    while (i < length && (bytes[i] & 0xC0) == 0x80) ++i;
    return i;
}

- (void)enumerateMatchesInData:(NSData *)data range:(NSRange)range
                    usingBlock:(void (^)(NSRange, BOOL *))block {
    if (!block) return;
    [self enumerateMatchesWithGroupsInData:data range:range
                                usingBlock:^(NSArray<NSValue *> *groups, BOOL *stop) {
        block(groups.firstObject.rangeValue, stop);
    }];
}

- (void)enumerateMatchesWithGroupsInData:(NSData *)data range:(NSRange)range
                              usingBlock:(void (^)(NSArray<NSValue *> *, BOOL *))block {
    [self enumerateMatchesWithGroupsInData:data range:range emptyMatches:NppEmptyMatchesAll usingBlock:block];
}

/// BoostRegexSearch::SearchParameters::nextCharacter with SCFIND_REGEXP_SKIPCRLFASONE,
/// which every search in FindReplaceDlg sets: a CRLF is stepped over whole.
static size_t NextCharacterSkippingCRLF(const uint8_t *bytes, size_t length, size_t from) {
    if (from + 1 < length && bytes[from] == '\r' && bytes[from + 1] == '\n') return from + 2;
    return NextCharacter(bytes, length, from);
}

- (void)enumerateMatchesWithGroupsInData:(NSData *)data range:(NSRange)range
                            emptyMatches:(NppEmptyMatches)empty
                              usingBlock:(void (^)(NSArray<NSValue *> *, BOOL *))block {
    if (!self.code || !data.length || !block) return;
    if (NSMaxRange(range) > data.length) return;

    void *matchData = gMatchDataCreate(self.code, NULL);
    if (!matchData) return;

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    size_t end = NSMaxRange(range);
    size_t at = range.location;
    BOOL stop = NO;
    // Whether this search goes on from where the last match ended, which is
    // what makes an empty match there no match (isContinuationSearch).
    BOOL continuation = NO;

    while (at <= end && !stop) {
        // The subject is cut at `end` so a match cannot run past the range it
        // was asked for -- which is how a class body is kept to itself.
        int rc = gMatch(self.code, bytes, end, at, 0, matchData, NULL);
        if (rc < 0) break;

        size_t *ovector = gOvector(matchData);
        size_t start = ovector[0], finish = ovector[1];
        if (start > end) break;

        if (empty != NppEmptyMatchesAll && finish == start) {
            // FindTextForward: an empty match is valid when empty matches are
            // allowed at all and it is not at the start of a continued search;
            // an invalid one sends the search on from the next character.
            BOOL valid = empty == NppEmptyMatchesNotAfterMatch && (!continuation || start > at);
            if (!valid) {
                size_t next = NextCharacterSkippingCRLF(bytes, data.length, start);
                if (next > end) break;
                // Still the same search, so an empty match from here on is
                // past its start and valid.
                at = next;
                continuation = NO;
                continue;
            }
        }

        // rc is the number of pairs the match filled in, so it counts the whole
        // match plus the groups that took part.
        NSMutableArray<NSValue *> *groups = [NSMutableArray arrayWithCapacity:(NSUInteger)rc];
        for (int g = 0; g < rc; ++g) {
            size_t from = ovector[2 * g], to = ovector[2 * g + 1];
            // PCRE2 marks a group that did not participate with ~0.
            if (from == (size_t)-1 || to == (size_t)-1 || to < from) {
                [groups addObject:[NSValue valueWithRange:NSMakeRange(NSNotFound, 0)]];
            } else {
                [groups addObject:[NSValue valueWithRange:NSMakeRange(from, to - from)]];
            }
        }

        block(groups, &stop);
        if (empty == NppEmptyMatchesAll) {
            at = (finish > start) ? finish : NextCharacter(bytes, end, start);
        } else {
            // processRange: the match that reaches the end of the range is the
            // last, so '$' there is not replaced again and again.
            if (finish == end) break;
            at = finish;
            continuation = YES;
        }
    }

    gMatchDataFree(matchData);
}

- (NSRange)firstNonEmptyMatchInData:(NSData *)data range:(NSRange)range {
    __block NSRange found = NSMakeRange(NSNotFound, 0);
    [self enumerateMatchesInData:data range:range usingBlock:^(NSRange m, BOOL *stop) {
        if (!m.length) return;
        found = m;
        *stop = YES;
    }];
    return found;
}

- (NSRange)firstMatchInData:(NSData *)data range:(NSRange)range {
    __block NSRange found = NSMakeRange(NSNotFound, 0);
    [self enumerateMatchesInData:data range:range usingBlock:^(NSRange m, BOOL *stop) {
        found = m;
        *stop = YES;
    }];
    return found;
}

- (NSInteger)groupNumberForName:(NSString *)name {
    if (!self.code || !gNumberFromName || !name.length) return -1;
    int n = gNumberFromName(self.code, (const uint8_t *)name.UTF8String);
    return n > 0 ? n : -1;
}

@end
