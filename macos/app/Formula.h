// A selected formula that ends with "=": "2 + 3 * 4 =", "(1,5 + 2) : 7 =",
// "sin 30° + ln e =", "2^10 = 1000" (an old result after the "=" is
// replaced). The context menu offers its value and writes it after the "=".
//
// Operations: + - * / : ^ (or **), mod, parentheses, unary minus, n!, the
// signs × ÷ · − √ ² ³, and percent as a calculator has it: 200 + 15% is
// 230, 200 * 15% is 30. A multiplication may be left out before a
// parenthesis, a function or a constant (2π, 3sin x).
// Functions, with or without parentheses around one argument:
//   sin cos tan (tg) cot (ctg) sec csc (cosec), asin (arcsin) acos (arccos)
//   atan (arctg, arctan) acot (arcctg), sinh (sh) cosh (ch) tanh (th)
//   coth (cth), asinh acosh atanh, sqrt cbrt exp ln log and lg (base 10)
//   log2, abs floor ceil round trunc sign (sgn), deg (radians to degrees),
//   rad (degrees to radians);
// with several, separated by ";" (or "," when the decimal separator is a
// point): log(x; base), root(x; n), pow(x; y), min, max, gcd (НОД), lcm (НОК).
// Constants: pi (π), e, tau (τ), phi (φ). Angles are in radians; ° after a
// number or parenthesis turns degrees into radians.
//
// + - * / and whole powers are decimal arithmetic; the functions work in
// double precision. The result is rounded to ten decimal places, so
// sin(180°) is 0. A comma is the decimal separator when the formula does
// not read with a point, and the result is written the same way.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppFormula : NSObject

/// The formula in a selection; nil unless the text is an expression with at
/// least one operation, function or constant, then "=", then at most an old
/// result and blanks.
+ (nullable instancetype)formulaFromText:(NSString *)text;

/// The value as it will be written; nil when it cannot be worked out.
@property (nonatomic, readonly, nullable) NSString *result;
/// Why not, in English for NppL(): "Division by zero" or "Cannot calculate".
@property (nonatomic, readonly, nullable) NSString *problem;
/// What of the text (UTF-16 range) the result replaces - just after the
/// "=": the blanks and old result there - and what goes in its place.
@property (nonatomic, readonly) NSRange replacedRange;
@property (nonatomic, readonly) NSString *replacement;

@end

NS_ASSUME_NONNULL_END
