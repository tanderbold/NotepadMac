// MIME Tools, as the Windows plugin does it (mimeTools.cpp, b64.cpp, qp.cpp,
// url.cpp, saml.cpp). Everything works on the selection's UTF-8 bytes; what a
// decode produces is read back as UTF-8, or as Latin-1 when it is not UTF-8,
// so no byte is lost.
#import "MimeCommands.h"
#import "ScintillaView.h"
#import <zlib.h>

// b64.cpp: no padding unless asked; "with Unix EOL" wraps at 64 with '\n'.
static const NSUInteger kBase64WrapColumn = 64;
// qp.h: "It also limits line length to 76".
static const NSUInteger kQuotedPrintableLineMax = 76;

// url.cpp gReservedAscii: RFC1738's unsafe characters, always encoded.
static const char kUrlReserved[] = "<>\"#%{}|\\^~[]`;/?:@=& ";
// url.cpp gExtendedChar: allowed by the RFC but encoded by common implementations.
static const char kUrlExtended[] = "!*'()+$,";

static NSString *StringFromBytes(NSData *data) {
    NSString *utf8 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return utf8 ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/// Applies `piece` to every line, keeping the line breaks exactly as written.
static NSString *ByLine(NSString *text, NSString *(^piece)(NSString *)) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger len = text.length, start = 0, i = 0;
    while (i <= len) {
        unichar c = i < len ? [text characterAtIndex:i] : 0;
        if (i == len || c == '\n' || c == '\r') {
            NSString *made = piece([text substringWithRange:NSMakeRange(start, i - start)]);
            if (!made) return nil;
            [out appendString:made];
            if (i == len) break;
            if (c == '\r' && i + 1 < len && [text characterAtIndex:i + 1] == '\n') {
                [out appendString:@"\r\n"]; i += 2;
            } else {
                [out appendFormat:@"%C", c]; i += 1;
            }
            start = i;
        } else {
            ++i;
        }
    }
    return out;
}

@implementation EditorController (MimeCommands)

#pragma mark - Base64

+ (NSString *)mimeBase64Encode:(NSString *)text padded:(BOOL)padded wrapped:(BOOL)wrapped byLine:(BOOL)byLine {
    NSString *(^one)(NSString *) = ^NSString *(NSString *piece) {
        NSData *bytes = [piece dataUsingEncoding:NSUTF8StringEncoding];
        NSString *b64 = [bytes base64EncodedStringWithOptions:0];
        if (!padded && !wrapped) b64 = [b64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
        if (wrapped) {
            NSMutableString *broken = [NSMutableString string];
            for (NSUInteger i = 0; i < b64.length; i += kBase64WrapColumn) {
                if (i) [broken appendString:@"\n"];
                [broken appendString:[b64 substringWithRange:
                    NSMakeRange(i, MIN(kBase64WrapColumn, b64.length - i))]];
            }
            b64 = broken;
        }
        return b64;
    };
    return byLine ? ByLine(text, one) : one(text);
}

+ (NSString *)mimeBase64Decode:(NSString *)text strict:(BOOL)strict byLine:(BOOL)byLine {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *(^one)(NSString *) = ^NSString *(NSString *piece) {
        if (!piece.length) return @"";
        NSMutableString *clean = [NSMutableString stringWithCapacity:piece.length];
        for (NSUInteger i = 0; i < piece.length; ++i) {
            unichar c = [piece characterAtIndex:i];
            if ([space characterIsMember:c]) {
                // b64.cpp: whitespace stops a strict decode and is passed over otherwise.
                if (strict) return nil;
                continue;
            }
            BOOL b64Char = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                           (c >= '0' && c <= '9') || c == '+' || c == '/' || c == '=';
            if (!b64Char) return nil;
            [clean appendFormat:@"%C", c];
        }
        if (strict && clean.length % 4 != 0) return nil;
        while (clean.length % 4 != 0) [clean appendString:@"="];
        NSData *bytes = [[NSData alloc] initWithBase64EncodedString:clean options:0];
        return bytes ? StringFromBytes(bytes) : nil;
    };
    return byLine ? ByLine(text, one) : one(text);
}

#pragma mark - Quoted-printable

+ (NSString *)mimeQuotedPrintableEncode:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    static const char hex[] = "0123456789ABCDEF";
    NSMutableString *out = [NSMutableString string];
    NSUInteger lineLen = 0;
    for (NSUInteger i = 0; i < data.length; ++i) {
        uint8_t c = bytes[i];
        char piece[4]; NSUInteger n;
        // qp.cpp getQPChar: printable but '=', plus space, tab and CR, go through.
        if ((c != '=' && c > 32 && c < 127) || c == ' ' || c == '\t' || c == '\r') {
            piece[0] = (char)c; n = 1;
        } else if (c == '\n') {
            piece[0] = '\n'; n = 1;
        } else {
            piece[0] = '='; piece[1] = hex[c >> 4]; piece[2] = hex[c & 15]; n = 3;
        }
        if (c == '\n') {
            lineLen = 0;
        } else if (lineLen + n > kQuotedPrintableLineMax - 1) {
            [out appendString:@"=\r\n"];    // the soft break qp.cpp writes
            lineLen = n;
        } else {
            lineLen += n;
        }
        [out appendString:[[NSString alloc] initWithBytes:piece length:n encoding:NSASCIIStringEncoding]];
    }
    return out;
}

+ (NSString *)mimeQuotedPrintableDecode:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableData *out = [NSMutableData data];
    int hi = -1, digits = 0; BOOL escaped = NO;
    for (NSUInteger i = 0; i < data.length; ++i) {
        uint8_t c = bytes[i];
        if (!escaped) {
            if (c == '=') { escaped = YES; hi = 0; digits = 0; }
            else [out appendBytes:&c length:1];
            continue;
        }
        if (digits == 0 && (c == '\r' || c == '\n')) {
            // A soft line break: "=" at the end of the line, swallowed with its EOL.
            escaped = NO;
            if (c == '\r' && i + 1 < data.length && bytes[i + 1] == '\n') ++i;
            continue;
        }
        int v = c >= '0' && c <= '9' ? c - '0'
              : c >= 'A' && c <= 'F' ? c - 'A' + 10
              : c >= 'a' && c <= 'f' ? c - 'a' + 10 : -1;
        if (v < 0) return nil;
        hi = (hi << 4) | v;
        if (++digits == 2) {
            uint8_t b = (uint8_t)hi;
            [out appendBytes:&b length:1];
            escaped = NO;
        }
    }
    if (escaped) return nil;
    return StringFromBytes(out);
}

#pragma mark - URL

+ (NSString *)mimeUrlEncode:(NSString *)text method:(NppUrlEncodeMethod)method byLine:(BOOL)byLine {
    NSString *reserved = [NSString stringWithFormat:@"%s%s", kUrlReserved,
                          method == NppUrlEncodeExtended ? kUrlExtended : ""];
    NSString *(^one)(NSString *) = ^NSString *(NSString *piece) {
        NSData *data = [piece dataUsingEncoding:NSUTF8StringEncoding];
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        static const char hex[] = "0123456789ABCDEF";
        NSMutableString *out = [NSMutableString string];
        for (NSUInteger i = 0; i < data.length; ++i) {
            uint8_t c = bytes[i];
            // url.cpp AsciiToUrl: full encodes everything; the others encode
            // the reserved set and whatever is not printable ASCII.
            BOOL encode = method == NppUrlEncodeFull ||
                          [reserved rangeOfString:[NSString stringWithFormat:@"%c", c]].location != NSNotFound ||
                          c < 32 || c >= 127;
            if (encode) [out appendFormat:@"%%%c%c", hex[c >> 4], hex[c & 15]];
            else [out appendFormat:@"%c", c];
        }
        return out;
    };
    return byLine ? ByLine(text, one) : one(text);
}

+ (NSString *)mimeUrlDecode:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableData *out = [NSMutableData data];
    for (NSUInteger i = 0; i < data.length; ++i) {
        uint8_t c = bytes[i];
        // url.cpp UrlToAscii: only a %XX triplet decodes; anything else is
        // copied as it stands, '%' without two hex digits included.
        if (c == '%' && i + 2 < data.length && isxdigit(bytes[i + 1]) && isxdigit(bytes[i + 2])) {
            char h[3] = {(char)bytes[i + 1], (char)bytes[i + 2], 0};
            uint8_t b = (uint8_t)strtol(h, NULL, 16);
            [out appendBytes:&b length:1];
            i += 2;
        } else {
            [out appendBytes:&c length:1];
        }
    }
    return StringFromBytes(out);
}

#pragma mark - SAML

+ (NSString *)mimeSamlDecode:(NSString *)text {
    // saml.cpp: URL-decode, Base64-decode, and inflate unless it is already XML.
    NSString *urlDecoded = [self mimeUrlDecode:text];
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < urlDecoded.length; ++i) {
        unichar c = [urlDecoded characterAtIndex:i];
        if (![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c])
            [clean appendFormat:@"%C", c];
    }
    while (clean.length % 4 != 0) [clean appendString:@"="];
    NSData *packed = [[NSData alloc] initWithBase64EncodedString:clean options:0];
    if (packed.length < 10) return nil;
    const uint8_t *b = (const uint8_t *)packed.bytes;
    if (b[0] == '<') return StringFromBytes(packed);   // "<?xml" or "<saml": not deflated

    z_stream z = {};
    if (inflateInit2(&z, -15) != Z_OK) return nil;     // raw deflate, as the SAML binding uses
    NSMutableData *out = [NSMutableData data];
    uint8_t buf[16384];
    z.next_in = (Bytef *)packed.bytes;
    z.avail_in = (uInt)packed.length;
    int rc = Z_OK;
    do {
        z.next_out = buf;
        z.avail_out = sizeof(buf);
        rc = inflate(&z, Z_NO_FLUSH);
        if (rc != Z_OK && rc != Z_STREAM_END) { inflateEnd(&z); return nil; }
        [out appendBytes:buf length:sizeof(buf) - z.avail_out];
    } while (rc != Z_STREAM_END && z.avail_in > 0);
    inflateEnd(&z);
    return out.length ? StringFromBytes(out) : nil;
}

#pragma mark - The selection

- (BOOL)mimeTransformSelection:(NSString *(NS_NOESCAPE ^)(NSString *))transform {
    ScintillaView *sci = self.sci;
    long start = [sci message:SCI_GETSELECTIONSTART], end = [sci message:SCI_GETSELECTIONEND];
    if (start == end) { NppBeep(); return YES; }   // nothing selected: handled, nothing to report
    NSMutableData *raw = [NSMutableData dataWithLength:(NSUInteger)(end - start) + 1];
    [sci message:SCI_GETSELTEXT wParam:0 lParam:(sptr_t)raw.mutableBytes];
    NSString *selected = [[NSString alloc] initWithUTF8String:(const char *)raw.bytes] ?: @"";
    NSString *made = transform(selected);
    if (!made) return NO;
    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_REPLACESEL parameter:0 value:made];
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

@end
