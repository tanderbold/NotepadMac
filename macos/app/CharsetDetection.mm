#import "CharsetDetection.h"
#include "uchardet.h"

@implementation NppCharsetDetection

+ (NSString *)charsetNameForData:(NSData *)data {
    if (data.length < 2) return nil;
    uchardet_t detector = uchardet_new();
    if (!detector) return nil;
    // The first part of a file says what the whole is; a large file is not
    // walked to the end for it.
    NSUInteger length = MIN(data.length, (NSUInteger)(1024 * 1024));
    uchardet_handle_data(detector, (const char *)data.bytes, length);
    uchardet_data_end(detector);
    const char *charset = uchardet_get_charset(detector);
    NSString *name = charset && *charset ? @(charset) : nil;
    uchardet_delete(detector);
    if (!name.length) return nil;
    if ([name caseInsensitiveCompare:@"ASCII"] == NSOrderedSame) return nil;
    if ([name caseInsensitiveCompare:@"TIS-620"] == NSOrderedSame) return nil;
    return name;
}

static NSStringEncoding EncodingNamed(NSString *name) {
    CFStringEncoding cf = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)name);
    return cf == kCFStringEncodingInvalidId ? 0 : CFStringConvertEncodingToNSStringEncoding(cf);
}

/// How much like text the bytes read in an encoding: the share of the
/// non-ASCII characters that are letters. The right Cyrillic code page
/// turns nearly all of them into letters; the wrong one turns the capitals
/// and the punctuation into symbols.
static double LetterShare(NSData *data, NSStringEncoding encoding) {
    NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
    if (!text) return -1;
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSUInteger nonAscii = 0, lettersSeen = 0;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c < 128) continue;
        nonAscii++;
        if ([letters characterIsMember:c]) lettersSeen++;
    }
    return nonAscii ? (double)lettersSeen / (double)nonAscii : 0;
}

+ (NSStringEncoding)encodingGuessedForData:(NSData *)data {
    NSString *name = [self charsetNameForData:data];
    if (!name) return 0;
    NSStringEncoding guessed = EncodingNamed(name);
    if (!guessed) return 0;

    // uchardet tells the Cyrillic code pages apart badly - Windows-1251 text
    // is often called Mac Cyrillic - so among them the one that reads most
    // like text wins, with the detector's own answer as the first candidate.
    NSString *lower = name.lowercaseString;
    BOOL cyrillic = [lower containsString:@"cyrillic"] || [lower containsString:@"1251"] ||
                    [lower containsString:@"koi8"] || [lower containsString:@"8859-5"] ||
                    [lower containsString:@"866"] || [lower containsString:@"855"];
    if (!cyrillic) return guessed;
    NSStringEncoding best = guessed;
    double bestShare = LetterShare(data, guessed);
    for (NSString *candidate in @[@"windows-1251", @"KOI8-R", @"ISO-8859-5", @"IBM866"]) {
        NSStringEncoding encoding = EncodingNamed(candidate);
        if (!encoding || encoding == guessed) continue;
        double share = LetterShare(data, encoding);
        if (share > bestShare + 1e-9) { best = encoding; bestShare = share; }
    }
    return best;
}

+ (NSStringEncoding)utf16EncodingWithoutMarkForData:(NSData *)data {
    NSUInteger length = MIN(data.length, (NSUInteger)4096);
    if (length < 4 || (length & 1)) length &= ~(NSUInteger)1;
    if (length < 4) return 0;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger zeroEven = 0, zeroOdd = 0;
    for (NSUInteger i = 0; i < length; i += 2) {
        if (bytes[i] == 0) zeroEven++;
        if (bytes[i + 1] == 0) zeroOdd++;
    }
    NSUInteger pairs = length / 2;
    // Most high bytes zero and hardly any low bytes zero: little-endian
    // ASCII-heavy text; the other way round: big-endian.
    if (zeroOdd * 10 >= pairs * 6 && zeroEven * 10 <= pairs) return NSUTF16LittleEndianStringEncoding;
    if (zeroEven * 10 >= pairs * 6 && zeroOdd * 10 <= pairs) return NSUTF16BigEndianStringEncoding;
    return 0;
}

@end
