// The regular expressions in Notepad++'s functionList files are PCRE, and they
// use PCRE features -- subroutine calls like (?&NAME), named groups written
// (?'NAME'...), \K, atomic groups -- that ICU, and therefore NSRegularExpression,
// has no equivalent for. macOS ships libpcre2, so the patterns can be run as
// written instead of being translated into something weaker.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Which empty matches a walk over the matches reports. Upstream's search asks
/// Scintilla for one match at a time with SCFIND_REGEXP_EMPTYMATCH_* flags
/// (FindReplaceDlg::processRange, BoostRegexSearch::FindTextForward); these
/// are those loops.
typedef NS_ENUM(NSInteger, NppEmptyMatches) {
    /// Every match, empty ones included, one search on from each: Find Next's
    /// list of candidates and the Function List.
    NppEmptyMatchesAll = 0,
    /// Replace All and Find All (EMPTYMATCH_NOTAFTERMATCH): an empty match
    /// right where the previous one ended is not one, and the walk ends with a
    /// match that reaches the end of the range.
    NppEmptyMatchesNotAfterMatch,
    /// Count and Mark (EMPTYMATCH_NONE): empty matches are never reported.
    NppEmptyMatchesNone,
};

@interface NppRegex : NSObject

/// Whether libpcre2 could be loaded. When it cannot, there is no second engine:
/// the Function List falls back to its own patterns instead.
+ (BOOL)available;

/// Compiles a pattern with the options upstream searches with. Results are
/// cached, because the same handful of patterns is used over and over.
+ (nullable instancetype)regexWithPattern:(NSString *)pattern;

/// The reason a pattern would not compile, for reporting rather than control
/// flow. Nil when it compiles.
+ (nullable NSString *)compileErrorForPattern:(NSString *)pattern;

/// Matching happens over UTF-8 bytes, which is what PCRE2 works in and what
/// Scintilla stores; every range here is a byte range into `data`.
- (void)enumerateMatchesInData:(NSData *)data range:(NSRange)range
                    usingBlock:(void (^)(NSRange match, BOOL *stop))block;

/// The same, with the capture groups: element 0 is the whole match, element n
/// the nth group. A group that did not take part has location NSNotFound.
/// Replacement needs these, for \1 and $1.
- (void)enumerateMatchesWithGroupsInData:(NSData *)data range:(NSRange)range
                              usingBlock:(void (^)(NSArray<NSValue *> *groups, BOOL *stop))block;
- (void)enumerateMatchesWithGroupsInData:(NSData *)data range:(NSRange)range
                            emptyMatches:(NppEmptyMatches)empty
                              usingBlock:(void (^)(NSArray<NSValue *> *groups, BOOL *stop))block;

/// The first match, or a range with location NSNotFound.
- (NSRange)firstMatchInData:(NSData *)data range:(NSRange)range;

/// The first match that is not empty. Narrowing a declaration down to its name
/// needs this: ini's name pattern is `[^[\]"]*`, which matches nothing at all
/// at the start of "[Section]" before it reaches the word.
- (NSRange)firstNonEmptyMatchInData:(NSData *)data range:(NSRange)range;

/// The number of the group a pattern named (?<name>...), or -1.
- (NSInteger)groupNumberForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
