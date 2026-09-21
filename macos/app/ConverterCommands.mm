// Converter, as the Windows plugin has it (npp-plugins/converter,
// PluginDefinition.cpp). ascii2Hex's three settings - a space between bytes,
// uppercase digits, a line break after so many bytes - live in the defaults
// (converterInsertSpace, converterUppercase, converterHexPerLine) instead of
// converter.ini.
#import "ConverterCommands.h"

@implementation EditorController (ConverterCommands)

+ (NSString *)converterHexFromText:(NSString *)text insertSpace:(BOOL)space
                         uppercase:(BOOL)upper charactersPerLine:(NSUInteger)perLine
                               eol:(NSString *)eol {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length * 3];
    NSUInteger k = 1;
    for (NSUInteger i = 0; i < data.length; ++i) {
        // The plugin's counter: the break lands after every perLine-th byte.
        BOOL lineEnd = NO;
        if (perLine) { if (k >= perLine) { lineEnd = YES; k = 1; } else ++k; }
        [out appendFormat:upper ? @"%02X" : @"%02x", bytes[i]];
        if (lineEnd) [out appendString:eol];
        else if (space) [out appendString:@" "];
    }
    return out;
}

+ (NSString *)converterTextFromHex:(NSString *)hex {
    NSData *data = [hex dataUsingEncoding:NSUTF8StringEncoding];
    const char *s = (const char *)data.bytes;
    NSUInteger len = data.length;
    if (len < 2) return nil;
    // HexString::toAscii reads the format off the third character and then
    // holds the text to it: spaces between every pair, or none at all.
    BOOL spaced = len >= 5 && s[2] == ' ';
    enum { stInit, stOne, stPair } state = stInit;
    NSMutableData *out = [NSMutableData data];
    int hi = 0;
    for (NSUInteger i = 0; i < len; ++i) {
        char c = s[i];
        int v = c >= '0' && c <= '9' ? c - '0'
              : c >= 'a' && c <= 'f' ? c - 'a' + 10
              : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (c == ' ') {
            if (!spaced || state != stPair) return nil;
            state = stInit;
        } else if (c == '\r' || c == '\n') {
            if (state == stOne) return nil;
            state = stInit;
        } else if (v >= 0) {
            if (state == stPair) {
                if (spaced) return nil;   // pairs must be separated once they were
                state = stInit;
            }
            if (state == stInit) { hi = v; state = stOne; }
            else {
                uint8_t b = (uint8_t)((hi << 4) | v);
                [out appendBytes:&b length:1];
                state = stPair;
            }
        } else {
            return nil;
        }
    }
    if (state == stOne || !out.length) return nil;
    NSString *utf8 = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    return utf8 ?: [[NSString alloc] initWithData:out encoding:NSISOLatin1StringEncoding];
}

+ (NSDictionary<NSString *, NSString *> *)converterValues:(NSString *)value fromField:(NSString *)field {
    if (!value.length) return @{@"ascii": @"", @"dec": @"", @"hex": @"", @"bin": @"", @"oct": @""};

    unsigned long long number = 0;
    if ([field isEqualToString:@"ascii"]) {
        // One character; its Unicode code point is the number (the Windows
        // panel stops at one ANSI byte, which this contains).
        if ([value rangeOfComposedCharacterSequenceAtIndex:0].length != value.length) return nil;
        number = [value characterAtIndex:0];
        if (CFStringIsSurrogateHighCharacter((UniChar)number) && value.length == 2) {
            number = CFStringGetLongCharacterForSurrogatePair(
                (UniChar)number, [value characterAtIndex:1]);
        }
    } else {
        int base = [field isEqualToString:@"dec"] ? 10
                 : [field isEqualToString:@"hex"] ? 16
                 : [field isEqualToString:@"oct"] ? 8
                 : [field isEqualToString:@"bin"] ? 2 : 0;
        if (!base) return nil;
        static NSString *const digits = @"0123456789abcdef";
        NSString *allowed = [digits substringToIndex:(NSUInteger)base];
        for (NSUInteger i = 0; i < value.length; ++i) {
            unichar c = (unichar)tolower([value characterAtIndex:i]);
            if ([allowed rangeOfString:[NSString stringWithFormat:@"%C", c]].location == NSNotFound)
                return nil;
        }
        errno = 0;
        number = strtoull(value.UTF8String, NULL, base);
        if (errno == ERANGE) return nil;
    }

    NSString *character = @"";
    if (number > 0 && number <= 0x10FFFF && !(number >= 0xD800 && number <= 0xDFFF)) {
        uint32_t cp = (uint32_t)number;
        character = [[NSString alloc] initWithBytes:&cp length:4 encoding:NSUTF32LittleEndianStringEncoding] ?: @"";
    }
    NSMutableString *binary = [NSMutableString string];
    for (int bit = 63; bit >= 0; --bit) {
        if (binary.length || (number >> bit) & 1 || bit == 0)
            [binary appendString:((number >> bit) & 1) ? @"1" : @"0"];
    }
    return @{@"ascii": character,
             @"dec": [NSString stringWithFormat:@"%llu", number],
             @"hex": [NSString stringWithFormat:@"%llx", number],
             @"bin": binary,
             @"oct": [NSString stringWithFormat:@"%llo", number]};
}

@end
