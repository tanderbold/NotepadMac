#import "NumberSet.h"

/// A piece cut into separator, number, separator, number, ..., separator:
/// even places are separators (the first and last may be empty), odd places numbers.
static NSArray<NSString *> *SplitPiece(NSString *text, NSCharacterSet *separators) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *run = [NSMutableString string];
    BOOL inSeparator = YES;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        BOOL isSeparator = [separators characterIsMember:c];
        if (isSeparator != inSeparator) {
            [parts addObject:[run copy]];
            [run setString:@""];
            inSeparator = isSeparator;
        }
        [run appendFormat:@"%C", c];
    }
    [parts addObject:[run copy]];
    if (!inSeparator) [parts addObject:@""];
    return parts;
}

static NSUInteger Marks(NSString *separator) {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < separator.length; ++i) {
        unichar c = [separator characterAtIndex:i];
        if (c == ',' || c == ';') ++n;
    }
    return n;
}

@implementation NppNumberSet {
    NSArray<NSArray<NSString *> *> *_parts;   // per piece, as SplitPiece cuts it
    NSArray<NSString *> *_numbers;            // every number as written, in order
    NSArray<NSDecimalNumber *> *_values;
    BOOL _decimalComma;
}

/// The pieces read one way (decimal comma or not); nil when they do not read that way.
+ (nullable instancetype)readPieces:(NSArray<NSString *> *)pieces decimalComma:(BOOL)decimalComma {
    NSMutableCharacterSet *separators = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [separators addCharactersInString:decimalComma ? @";" : @",;"];
    NSString *pattern = decimalComma ? @"^[+\\-\\x{2212}]?[0-9]+(?:,[0-9]+)?$"
                                     : @"^[+\\-\\x{2212}]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+\\-]?[0-9]+)?$";
    NSRegularExpression *number = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
    NSDictionary *pointLocale = @{NSLocaleDecimalSeparator: @"."};

    NSMutableArray *allParts = [NSMutableArray array];
    NSMutableArray<NSString *> *numbers = [NSMutableArray array];
    NSMutableArray<NSDecimalNumber *> *values = [NSMutableArray array];
    BOOL sawComma = NO;
    for (NSString *piece in pieces) {
        NSArray<NSString *> *parts = SplitPiece(piece, separators);
        for (NSUInteger i = 0; i < parts.count; ++i) {
            NSString *part = parts[i];
            if (i % 2 == 0) {
                // A comma or semicolon only between two numbers, and one at most.
                BOOL edge = i == 0 || i == parts.count - 1;
                if (Marks(part) > (edge ? 0u : 1u)) return nil;
                continue;
            }
            if (![number firstMatchInString:part options:0 range:NSMakeRange(0, part.length)]) return nil;
            NSString *plain = [part stringByReplacingOccurrencesOfString:@"−" withString:@"-"];
            if ([plain hasPrefix:@"+"]) plain = [plain substringFromIndex:1];
            if (decimalComma) {
                sawComma = sawComma || [plain containsString:@","];
                plain = [plain stringByReplacingOccurrencesOfString:@"," withString:@"."];
            }
            NSDecimalNumber *value = [NSDecimalNumber decimalNumberWithString:plain locale:pointLocale];
            if (!value || [value isEqualToNumber:[NSDecimalNumber notANumber]]) return nil;
            [numbers addObject:part];
            [values addObject:value];
        }
        [allParts addObject:parts];
    }
    if (numbers.count < 2 || (decimalComma && !sawComma)) return nil;

    NppNumberSet *set = [[self alloc] init];
    set->_parts = allParts;
    set->_numbers = numbers;
    set->_values = values;
    set->_decimalComma = decimalComma;
    return [set computeSummary] ? set : nil;
}

+ (nullable instancetype)setFromPieces:(NSArray<NSString *> *)pieces {
    return [self readPieces:pieces decimalComma:YES] ?: [self readPieces:pieces decimalComma:NO];
}

- (NSString *)written:(NSDecimalNumber *)value {
    return [value descriptionWithLocale:@{NSLocaleDecimalSeparator: _decimalComma ? @"," : @"."}];
}

/// NO when the numbers are too big to add up (NSDecimalNumber's range).
- (BOOL)computeSummary {
    @try {
        NSDecimalNumber *sum = [NSDecimalNumber zero];
        NSUInteger low = 0, high = 0;
        for (NSUInteger i = 0; i < _values.count; ++i) {
            sum = [sum decimalNumberByAdding:_values[i]];
            if ([_values[i] compare:_values[low]] == NSOrderedAscending) low = i;
            if ([_values[i] compare:_values[high]] == NSOrderedDescending) high = i;
        }
        NSDecimalNumberHandler *tenPlaces =
            [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:10
                                                        raiseOnExactness:NO raiseOnOverflow:YES
                                                        raiseOnUnderflow:NO raiseOnDivideByZero:YES];
        NSDecimalNumber *count = [NSDecimalNumber decimalNumberWithMantissa:_values.count exponent:0 isNegative:NO];
        _count = _values.count;
        _sum = [self written:sum];
        _average = [self written:[sum decimalNumberByDividingBy:count withBehavior:tenPlaces]];
        // The extremes as they are written in the text.
        _minimum = _numbers[low];
        _maximum = _numbers[high];
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

- (NSArray<NSString *> *)piecesSortedAscending:(BOOL)ascending {
    NSMutableArray<NSNumber *> *order = [NSMutableArray arrayWithCapacity:_values.count];
    for (NSUInteger i = 0; i < _values.count; ++i) [order addObject:@(i)];
    NSArray<NSDecimalNumber *> *values = _values;
    [order sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSComparisonResult r = [values[a.unsignedIntegerValue] compare:values[b.unsignedIntegerValue]];
        return ascending ? r : (NSComparisonResult)-r;
    }];
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:_parts.count];
    NSUInteger next = 0;
    for (NSArray<NSString *> *parts in _parts) {
        NSMutableString *piece = [NSMutableString string];
        for (NSUInteger i = 0; i < parts.count; ++i) {
            [piece appendString:i % 2 == 0 ? parts[i] : _numbers[order[next++].unsignedIntegerValue]];
        }
        [out addObject:piece];
    }
    return out;
}

@end
