#import "Formula.h"
#include <cmath>
#include <vector>

static NSDecimalNumber *Decimal(double d) {
    return [NSDecimalNumber decimalNumberWithDecimal:[@(d) decimalValue]];
}

static NSDecimalNumber *Rounded(NSDecimalNumber *v, short scale) {
    NSDecimalNumberHandler *h =
        [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:scale raiseOnExactness:NO
                                                     raiseOnOverflow:YES raiseOnUnderflow:NO raiseOnDivideByZero:YES];
    return [v decimalNumberByRoundingAccordingToBehavior:h];
}

static BOOL IsWhole(NSDecimalNumber *v) { return [Rounded(v, 0) compare:v] == NSOrderedSame; }
static BOOL IsZero(NSDecimalNumber *v) { return [v compare:NSDecimalNumber.zero] == NSOrderedSame; }
static BOOL IsNegative(NSDecimalNumber *v) { return [v compare:NSDecimalNumber.zero] == NSOrderedAscending; }

/// Divisions keep twenty places; the result is rounded to ten at the end.
static NSDecimalNumber *Divide(NSDecimalNumber *a, NSDecimalNumber *b) {
    NSDecimalNumberHandler *h =
        [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:20 raiseOnExactness:NO
                                                     raiseOnOverflow:YES raiseOnUnderflow:NO raiseOnDivideByZero:YES];
    return [a decimalNumberByDividingBy:b withBehavior:h];
}

namespace {

struct Value {
    NSDecimalNumber *number = NSDecimalNumber.zero;
    bool percent = false;   // "15%" as it stands, for "200 + 15%"
};

/// Recursive descent over the text before the "=": expression, term, unary,
/// power, postfix, primary, lowest binding first.
struct Parser {
    NSString *text;
    bool comma;                 // the decimal separator is a comma
    NSUInteger i = 0;
    bool bad = false;           // not a formula at all
    NSString *problem = nil;    // a formula whose value cannot be worked out
    int operations = 0;

    unichar at(NSUInteger k) const { return k < text.length ? [text characterAtIndex:k] : 0; }
    void skip() {
        while (i < text.length && [NSCharacterSet.whitespaceAndNewlineCharacterSet characterIsMember:at(i)]) ++i;
    }
    unichar peek() { skip(); return at(i); }
    bool take(unichar c) { if (peek() == c) { ++i; return true; } return false; }
    static bool letter(unichar c) { return c && [NSCharacterSet.letterCharacterSet characterIsMember:c]; }
    static bool digit(unichar c) { return c >= '0' && c <= '9'; }
    unichar separator() const { return comma ? ',' : '.'; }

    Value fail() { bad = true; return Value(); }
    NSDecimalNumber *trouble(NSString *why) { if (!problem) problem = why; return NSDecimalNumber.zero; }
    NSDecimalNumber *fromDouble(double d) { return std::isfinite(d) ? Decimal(d) : trouble(@"Cannot calculate"); }

    /// The word at the caret, lower-cased, without taking it; log2 and log10 whole.
    NSString *word(NSUInteger *end) {
        skip();
        NSUInteger k = i;
        while (letter(at(k))) ++k;
        NSString *w = [[text substringWithRange:NSMakeRange(i, k - i)] lowercaseString];
        if ([w isEqualToString:@"log"] && at(k) == '2' && !digit(at(k + 1))) { w = @"log2"; ++k; }
        else if ([w isEqualToString:@"log"] && at(k) == '1' && at(k + 1) == '0' && !digit(at(k + 2))) { w = @"log10"; k += 2; }
        *end = k;
        return w;
    }

    Value expression() {
        Value left = term();
        for (;;) {
            if (bad) return left;
            unichar c = peek();
            bool plus = c == '+', minus = c == '-' || c == 0x2212;
            if (!plus && !minus) return left;
            ++i; ++operations;
            Value right = term();
            if (bad) return left;
            // A calculator's percent: 200 + 15% is 200 plus 15% of 200.
            NSDecimalNumber *r = right.percent ? [left.number decimalNumberByMultiplyingBy:right.number] : right.number;
            left.number = plus ? [left.number decimalNumberByAdding:r] : [left.number decimalNumberBySubtracting:r];
            left.percent = false;
        }
    }

    Value term() {
        Value left = unary();
        for (;;) {
            if (bad) return left;
            unichar c = peek();
            NSUInteger end = 0;
            enum { None, Times, Over, Mod, Implied } op = None;
            if (c == '*' || c == 0xD7 || c == 0xB7 || c == 0x22C5) op = Times;
            else if (c == '/' || c == ':' || c == 0xF7) op = Over;
            else if (letter(c) && [word(&end) isEqualToString:@"mod"]) op = Mod;
            else if (c == '(' || letter(c) || c == 0x221A) op = Implied;   // 2π, 3sin x, 2(1 + 1)
            if (op == None) return left;
            if (op == Mod) i = end; else if (op != Implied) ++i;
            ++operations;
            Value right = unary();
            if (bad) return left;
            NSDecimalNumber *a = left.number, *b = right.number;
            if (op == Times || op == Implied) left.number = [a decimalNumberByMultiplyingBy:b];
            else if (IsZero(b)) left.number = trouble(@"Division by zero");
            else if (op == Over) left.number = Divide(a, b);
            else {
                NSDecimalNumber *q = Divide(a, b);
                NSDecimalNumberHandler *down =
                    [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundDown scale:0 raiseOnExactness:NO
                                                                 raiseOnOverflow:YES raiseOnUnderflow:NO raiseOnDivideByZero:YES];
                q = [q decimalNumberByRoundingAccordingToBehavior:down];
                left.number = [a decimalNumberBySubtracting:[b decimalNumberByMultiplyingBy:q]];
            }
            left.percent = false;
        }
    }

    Value unary() {
        unichar c = peek();
        if (c == '-' || c == 0x2212) {
            ++i;
            Value v = unary();
            v.number = [v.number decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
            return v;
        }
        if (c == '+') { ++i; return unary(); }
        return power();
    }

    NSDecimalNumber *raise(NSDecimalNumber *base, NSDecimalNumber *exponent) {
        if (IsWhole(exponent) && std::fabs(exponent.doubleValue) <= 9999) {
            int n = exponent.intValue;
            if (n >= 0) return [base decimalNumberByRaisingToPower:(NSUInteger)n];
            if (IsZero(base)) return trouble(@"Division by zero");
            return Divide(NSDecimalNumber.one, [base decimalNumberByRaisingToPower:(NSUInteger)-n]);
        }
        return fromDouble(std::pow(base.doubleValue, exponent.doubleValue));
    }

    Value power() {
        Value base = postfix();
        if (bad) return base;
        unichar c = peek();
        if (c == '^' || (c == '*' && at(i + 1) == '*')) {
            i += c == '^' ? 1 : 2;
            ++operations;
            Value exponent = unary();   // right to left: 2^3^2 is 2^9
            if (bad) return base;
            base.number = raise(base.number, exponent.number);
            base.percent = false;
        }
        return base;
    }

    Value postfix() {
        Value v = primary();
        for (;;) {
            if (bad) return v;
            unichar c = peek();
            if (c == '!') {
                ++i; ++operations;
                if (IsNegative(v.number) || !IsWhole(v.number) || v.number.doubleValue > 1000) {
                    v.number = trouble(@"Cannot calculate");
                } else {
                    NSDecimalNumber *f = NSDecimalNumber.one;
                    for (int k = 2; k <= v.number.intValue; ++k)
                        f = [f decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)k exponent:0 isNegative:NO]];
                    v.number = f;
                }
            } else if (c == 0xB0) {
                ++i; ++operations;
                v.number = fromDouble(v.number.doubleValue * M_PI / 180);
            } else if (c == 0xB2 || c == 0xB3) {
                ++i; ++operations;
                v.number = [v.number decimalNumberByRaisingToPower:c == 0xB2 ? 2 : 3];
            } else if (c == '%') {
                ++i; ++operations;
                v.number = Divide(v.number, [NSDecimalNumber decimalNumberWithMantissa:100 exponent:0 isNegative:NO]);
                v.percent = true;
                continue;
            } else {
                return v;
            }
            v.percent = false;
        }
    }

    NSDecimalNumber *number() {
        NSMutableString *s = [NSMutableString string];
        while (digit(at(i))) [s appendFormat:@"%C", at(i++)];
        if (at(i) == separator() && digit(at(i + 1))) {
            [s appendString:@"."];
            ++i;
            while (digit(at(i))) [s appendFormat:@"%C", at(i++)];
        }
        // 1e5, 2.5E-3; a lone "e" after a number is the constant (2e = 2·e).
        unichar e = at(i);
        if ((e == 'e' || e == 'E') && (digit(at(i + 1)) || ((at(i + 1) == '+' || at(i + 1) == '-') && digit(at(i + 2))))) {
            [s appendString:@"e"];
            ++i;
            if (at(i) == '+' || at(i) == '-') [s appendFormat:@"%C", at(i++)];
            while (digit(at(i))) [s appendFormat:@"%C", at(i++)];
        }
        NSDecimalNumber *n = [NSDecimalNumber decimalNumberWithString:s locale:@{NSLocaleDecimalSeparator: @"."}];
        if (!n || [n isEqualToNumber:NSDecimalNumber.notANumber]) { bad = true; return NSDecimalNumber.zero; }
        return n;
    }

    std::vector<Value> arguments() {
        std::vector<Value> args;
        if (take('(')) {
            args.push_back(expression());
            while (!bad && (take(';') || (!comma && take(',')))) args.push_back(expression());
            if (!take(')')) bad = true;
        } else {
            args.push_back(unary());   // sin 30°
        }
        return args;
    }

    Value call(NSString *name) {
        static NSDictionary<NSString *, NSString *> *aliases = @{
            @"tg": @"tan", @"ctg": @"cot", @"cosec": @"csc", @"arcsin": @"asin", @"arccos": @"acos",
            @"arctg": @"atan", @"arctan": @"atan", @"arcctg": @"acot", @"arccot": @"acot",
            @"sh": @"sinh", @"ch": @"cosh", @"th": @"tanh", @"cth": @"coth",
            @"lg": @"log", @"log10": @"log", @"sgn": @"sign", @"нод": @"gcd", @"нок": @"lcm",
        };
        NSString *f = aliases[name] ?: name;
        static NSSet<NSString *> *one = [NSSet setWithArray:@[
            @"sin", @"cos", @"tan", @"cot", @"sec", @"csc", @"asin", @"acos", @"atan", @"acot",
            @"sinh", @"cosh", @"tanh", @"coth", @"asinh", @"acosh", @"atanh", @"sqrt", @"cbrt", @"exp",
            @"ln", @"log", @"log2", @"abs", @"floor", @"ceil", @"round", @"trunc", @"sign", @"deg", @"rad"]];
        static NSSet<NSString *> *several = [NSSet setWithArray:@[@"log", @"root", @"pow", @"min", @"max", @"gcd", @"lcm"]];
        if (![one containsObject:f] && ![several containsObject:f]) return fail();
        ++operations;
        std::vector<Value> args = arguments();
        if (bad) return Value();
        size_t n = args.size();
        NSDecimalNumber *a = args[0].number, *b = n > 1 ? args[1].number : nil;
        double x = a.doubleValue;
        Value out;
        if (n == 1 && [one containsObject:f]) {
            if ([f isEqualToString:@"abs"]) out.number = IsNegative(a) ? [NSDecimalNumber.zero decimalNumberBySubtracting:a] : a;
            else if ([f isEqualToString:@"sign"]) out.number = [NSDecimalNumber decimalNumberWithMantissa:IsZero(a) ? 0 : 1 exponent:0 isNegative:IsNegative(a)];
            else if ([f isEqualToString:@"sqrt"] && IsNegative(a)) out.number = trouble(@"Cannot calculate");
            else {
                double r =
                    [f isEqualToString:@"sin"] ? std::sin(x) : [f isEqualToString:@"cos"] ? std::cos(x) :
                    [f isEqualToString:@"tan"] ? std::tan(x) : [f isEqualToString:@"cot"] ? 1 / std::tan(x) :
                    [f isEqualToString:@"sec"] ? 1 / std::cos(x) : [f isEqualToString:@"csc"] ? 1 / std::sin(x) :
                    [f isEqualToString:@"asin"] ? std::asin(x) : [f isEqualToString:@"acos"] ? std::acos(x) :
                    [f isEqualToString:@"atan"] ? std::atan(x) : [f isEqualToString:@"acot"] ? M_PI / 2 - std::atan(x) :
                    [f isEqualToString:@"sinh"] ? std::sinh(x) : [f isEqualToString:@"cosh"] ? std::cosh(x) :
                    [f isEqualToString:@"tanh"] ? std::tanh(x) : [f isEqualToString:@"coth"] ? 1 / std::tanh(x) :
                    [f isEqualToString:@"asinh"] ? std::asinh(x) : [f isEqualToString:@"acosh"] ? std::acosh(x) :
                    [f isEqualToString:@"atanh"] ? std::atanh(x) : [f isEqualToString:@"sqrt"] ? std::sqrt(x) :
                    [f isEqualToString:@"cbrt"] ? std::cbrt(x) : [f isEqualToString:@"exp"] ? std::exp(x) :
                    [f isEqualToString:@"ln"] ? std::log(x) : [f isEqualToString:@"log"] ? std::log10(x) :
                    [f isEqualToString:@"log2"] ? std::log2(x) : [f isEqualToString:@"floor"] ? std::floor(x) :
                    [f isEqualToString:@"ceil"] ? std::ceil(x) : [f isEqualToString:@"round"] ? std::round(x) :
                    [f isEqualToString:@"trunc"] ? std::trunc(x) : [f isEqualToString:@"deg"] ? x * 180 / M_PI :
                    x * M_PI / 180;   // rad
                out.number = fromDouble(r);
            }
        } else if (n >= 1 && ([f isEqualToString:@"min"] || [f isEqualToString:@"max"])) {
            BOOL low = [f isEqualToString:@"min"];
            out.number = a;
            for (const Value &v : args)
                if ([v.number compare:out.number] == (low ? NSOrderedAscending : NSOrderedDescending)) out.number = v.number;
        } else if (n == 2 && [f isEqualToString:@"log"]) {
            out.number = fromDouble(std::log(x) / std::log(b.doubleValue));
        } else if (n == 2 && [f isEqualToString:@"pow"]) {
            out.number = raise(a, b);
        } else if (n == 2 && [f isEqualToString:@"root"]) {
            double k = b.doubleValue;
            // An odd root of a negative number is real: root(-8; 3) is -2.
            bool odd = IsWhole(b) && std::fmod(std::fabs(k), 2) == 1;
            out.number = IsZero(b) ? trouble(@"Division by zero")
                       : fromDouble(x < 0 && odd ? -std::pow(-x, 1 / k) : std::pow(x, 1 / k));
        } else if (n >= 2 && ([f isEqualToString:@"gcd"] || [f isEqualToString:@"lcm"])) {
            BOOL gcd = [f isEqualToString:@"gcd"];
            long long acc = 0;
            for (const Value &v : args) {
                if (!IsWhole(v.number) || std::fabs(v.number.doubleValue) > 1e15) { out.number = trouble(@"Cannot calculate"); return out; }
                long long m = std::llabs(v.number.longLongValue);
                if (&v == &args[0]) { acc = m; continue; }
                long long p = acc, q = m;
                while (q) { long long t = p % q; p = q; q = t; }
                acc = gcd ? p : (p ? acc / p * m : 0);
            }
            out.number = [NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)acc exponent:0 isNegative:NO];
        } else {
            return fail();
        }
        return out;
    }

    Value primary() {
        unichar c = peek();
        if (digit(c) || (c == separator() && digit(at(i + 1)))) {
            Value v;
            v.number = number();
            return v;
        }
        if (c == '(') {
            ++i;
            Value v = expression();
            if (!take(')')) return fail();
            v.percent = false;
            return v;
        }
        if (c == 0x221A) {   // √16, √(9 + 7)
            ++i; ++operations;
            Value v = power();
            if (bad) return v;
            v.number = IsNegative(v.number) ? trouble(@"Cannot calculate") : fromDouble(std::sqrt(v.number.doubleValue));
            v.percent = false;
            return v;
        }
        if (letter(c)) {
            NSUInteger end = 0;
            NSString *w = word(&end);
            static NSDictionary<NSString *, NSString *> *constants = @{
                @"pi": @"3.14159265358979323846264338327950288", @"π": @"3.14159265358979323846264338327950288",
                @"e": @"2.71828182845904523536028747135266250",
                @"tau": @"6.28318530717958647692528676655900577", @"τ": @"6.28318530717958647692528676655900577",
                @"phi": @"1.61803398874989484820458683436563812", @"φ": @"1.61803398874989484820458683436563812",
            };
            if (constants[w]) {
                i = end; ++operations;
                Value v;
                v.number = [NSDecimalNumber decimalNumberWithString:constants[w] locale:@{NSLocaleDecimalSeparator: @"."}];
                return v;
            }
            i = end;
            return call(w);
        }
        return fail();
    }
};

}  // namespace

@implementation NppFormula

+ (nullable instancetype)formulaFromText:(NSString *)text {
    // Expression, "=", blanks, an old result perhaps, then only white space.
    static NSRegularExpression *shape = [NSRegularExpression regularExpressionWithPattern:
        @"^([\\s\\S]*)=([ \\t]*)([+\\-\\x{2212}]?[0-9]+(?:[.,][0-9]+)?(?:[eE][+\\-]?[0-9]+)?)?\\s*$" options:0 error:NULL];
    NSTextCheckingResult *m = [shape firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!m) return nil;
    NSRange expressionRange = [m rangeAtIndex:1];
    NSString *expression = [text substringWithRange:expressionRange];
    if (![expression stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return nil;

    for (int pass = 0; pass < 2; ++pass) {
        Parser p;
        p.text = expression;
        p.comma = pass == 1;
        Value v;
        @try {
            v = p.expression();
            p.skip();
            if (p.i < expression.length) p.bad = true;
        } @catch (NSException *) {
            // NSDecimalNumber's range (about 1e165) overflowed.
            if (!p.bad) p.problem = p.problem ?: @"Cannot calculate";
        }
        if (p.bad || p.operations == 0) continue;

        NppFormula *f = [[self alloc] init];
        if (p.problem) {
            f->_problem = p.problem;
        } else {
            @try {
                f->_result = [Rounded(v.number, 10) descriptionWithLocale:@{NSLocaleDecimalSeparator: p.comma ? @"," : @"."}];
            } @catch (NSException *) {
                f->_problem = @"Cannot calculate";
            }
        }
        NSRange blanks = [m rangeAtIndex:2], old = [m rangeAtIndex:3];
        NSUInteger start = NSMaxRange(expressionRange) + 1;
        NSUInteger end = old.location != NSNotFound ? NSMaxRange(old) : NSMaxRange(blanks);
        f->_replacedRange = NSMakeRange(start, end - start);
        unichar before = expressionRange.length ? [text characterAtIndex:NSMaxRange(expressionRange) - 1] : 0;
        BOOL spaced = blanks.length > 0 || before == ' ' || before == '\t';
        f->_replacement = f->_result ? [(spaced ? @" " : @"") stringByAppendingString:f->_result] : @"";
        return f;
    }
    return nil;
}

@end
