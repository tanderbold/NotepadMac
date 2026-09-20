// Notepad++ builds a regular-expression replacement with Boost's formatter in
// format_all mode (BoostRegExSearch.cxx, SubstituteByPosition). This is that
// formatter, rule for rule, so a replacement written for Windows gives the
// same text here: $&, $`, $', $$, $n, ${n}, $+, $+{name}, $MATCH and the other
// Perl names, \n (one digit), \0 octal, \xHH, \x{H...}, \cX, \a \e \f \n \r
// \t \v, \l \u \L \U \E, parentheses grouping and ?N...:... conditionals.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// `groups[0]` is the whole match; NSNull stands for a group that did not
/// take part. `prefix` runs from where the search started to the match, and
/// `suffix` from the match to the end of the text searched.
FOUNDATION_EXPORT NSString *NppBoostFormat(NSString *format, NSArray *groups,
                                           NSString *prefix, NSString *suffix,
                                           NSInteger lastClosedGroup,
                                           NSInteger (^_Nullable groupNamed)(NSString *name));

NS_ASSUME_NONNULL_END
