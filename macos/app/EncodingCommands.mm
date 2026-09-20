#import "EncodingCommands.h"
#import "ScintillaView.h"
#include "CodePageTables.h"

const NppCharset kNppCharsets[] = {
    // Arabic
    {"IDM_FORMAT_ISO_8859_6",     "Arabic",            "ISO 8859-6",            28596},
    {"IDM_FORMAT_DOS_720",        "Arabic",            "OEM 720",                 720},
    {"IDM_FORMAT_WIN_1256",       "Arabic",            "Windows-1256",           1256},
    // Baltic
    {"IDM_FORMAT_ISO_8859_4",     "Baltic",            "ISO 8859-4",            28594},
    {"IDM_FORMAT_ISO_8859_13",    "Baltic",            "ISO 8859-13",           28603},
    {"IDM_FORMAT_DOS_775",        "Baltic",            "OEM 775",                 775},
    {"IDM_FORMAT_WIN_1257",       "Baltic",            "Windows-1257",           1257},
    // Celtic
    {"IDM_FORMAT_ISO_8859_14",    "Celtic",            "ISO 8859-14",           28604},
    // Central European
    {"IDM_FORMAT_DOS_852",        "Central European",  "OEM 852",                 852},
    {"IDM_FORMAT_WIN_1250",       "Central European",  "Windows-1250",           1250},
    // Chinese
    {"IDM_FORMAT_BIG5",           "Chinese",           "Big5 (Traditional)",      950},
    {"IDM_FORMAT_GB2312",         "Chinese",           "GB2312 (Simplified)",     936},
    // Cyrillic
    {"IDM_FORMAT_ISO_8859_5",     "Cyrillic",          "ISO 8859-5",            28595},
    {"IDM_FORMAT_KOI8R_CYRILLIC", "Cyrillic",          "KOI8-R",                20866},
    {"IDM_FORMAT_KOI8U_CYRILLIC", "Cyrillic",          "KOI8-U",                21866},
    {"IDM_FORMAT_MAC_CYRILLIC",   "Cyrillic",          "Macintosh",             10007},
    {"IDM_FORMAT_DOS_855",        "Cyrillic",          "OEM 855",                 855},
    {"IDM_FORMAT_DOS_866",        "Cyrillic",          "OEM 866",                 866},
    {"IDM_FORMAT_WIN_1251",       "Cyrillic",          "Windows-1251",           1251},
    // Eastern European
    {"IDM_FORMAT_ISO_8859_2",     "Eastern European",  "ISO 8859-2",            28592},
    // Greek
    {"IDM_FORMAT_ISO_8859_7",     "Greek",             "ISO 8859-7",            28597},
    {"IDM_FORMAT_DOS_737",        "Greek",             "OEM 737",                 737},
    {"IDM_FORMAT_DOS_869",        "Greek",             "OEM 869",                 869},
    {"IDM_FORMAT_WIN_1253",       "Greek",             "Windows-1253",           1253},
    // Hebrew
    {"IDM_FORMAT_ISO_8859_8",     "Hebrew",            "ISO 8859-8",            28598},
    {"IDM_FORMAT_DOS_862",        "Hebrew",            "OEM 862",                 862},
    {"IDM_FORMAT_WIN_1255",       "Hebrew",            "Windows-1255",           1255},
    // Japanese
    {"IDM_FORMAT_SHIFT_JIS",      "Japanese",          "Shift-JIS",               932},
    // Korean
    {"IDM_FORMAT_KOREAN_WIN",     "Korean",            "Windows 949",             949},
    {"IDM_FORMAT_EUC_KR",         "Korean",            "EUC-KR",                51949},
    // North European
    {"IDM_FORMAT_DOS_861",        "North European",    "OEM 861 : Icelandic",     861},
    {"IDM_FORMAT_DOS_865",        "North European",    "OEM 865 : Nordic",        865},
    // Thai
    {"IDM_FORMAT_TIS_620",        "Thai",              "TIS-620",                 874},
    // Turkish
    {"IDM_FORMAT_ISO_8859_3",     "Turkish",           "ISO 8859-3",            28593},
    {"IDM_FORMAT_ISO_8859_9",     "Turkish",           "ISO 8859-9",            28599},
    {"IDM_FORMAT_DOS_857",        "Turkish",           "OEM 857",                 857},
    {"IDM_FORMAT_WIN_1254",       "Turkish",           "Windows-1254",           1254},
    // Vietnamese
    {"IDM_FORMAT_WIN_1258",       "Vietnamese",        "Windows-1258",           1258},
    // Western European
    {"IDM_FORMAT_ISO_8859_1",     "Western European",  "ISO 8859-1",            28591},
    {"IDM_FORMAT_ISO_8859_15",    "Western European",  "ISO 8859-15",           28605},
    {"IDM_FORMAT_DOS_850",        "Western European",  "OEM 850",                 850},
    {"IDM_FORMAT_DOS_858",        "Western European",  "OEM 858",                 858},
    {"IDM_FORMAT_DOS_860",        "Western European",  "OEM 860 : Portuguese",    860},
    {"IDM_FORMAT_DOS_863",        "Western European",  "OEM 863 : French",        863},
    {"IDM_FORMAT_DOS_437",        "Western European",  "OEM-US : CP437",          437},
    {"IDM_FORMAT_WIN_1252",       "Western European",  "Windows-1252",           1252},
};

const int kNppCharsetCount = (int)(sizeof(kNppCharsets) / sizeof(kNppCharsets[0]));

@implementation EditorController (EncodingCommands)

/// The table for a code page, or NULL when there is none and the system
/// converter has to be used instead.
static const uint16_t *TableForCodepage(unsigned int codepage) {
    for (int i = 0; i < kNppCodePageTableCount; ++i) {
        if (kNppCodePageTables[i].codepage == codepage) return kNppCodePageTables[i].high;
    }
    return NULL;
}

+ (NSStringEncoding)encodingForCodepage:(unsigned int)codepage {
    CFStringEncoding cf = CFStringConvertWindowsCodepageToEncoding(codepage);
    if (cf == kCFStringEncodingInvalidId) {
        // A few sets have no Windows code page on this platform; name them directly.
        switch (codepage) {
            case 28604: cf = kCFStringEncodingISOLatin8; break;    // ISO 8859-14
            case 28603: cf = kCFStringEncodingISOLatin7; break;    // ISO 8859-13
            case 51949: cf = kCFStringEncodingEUC_KR;   break;
            default: return 0;
        }
    }
    NSStringEncoding enc = CFStringConvertEncodingToNSStringEncoding(cf);
    return enc == kCFStringEncodingInvalidId ? 0 : enc;
}

+ (BOOL)supportsCodepage:(unsigned int)codepage {
    if (TableForCodepage(codepage)) return YES;
    return [self encodingForCodepage:codepage] != 0;
}

/// macOS has converters for most of these code pages, but they do not always
/// agree with Windows, and Notepad++ is Windows. Its Icelandic table is another
/// code page's outright -- sixty-seven of a hundred and twenty-eight bytes wrong
/// -- its Arabic one has eight letters missing, and a scattering of others
/// differ in one or two bytes. Where a generated table exists it is used, so the
/// bytes mean here what they mean there. Bytes below 0x80 are ASCII in every one
/// of these code pages.
static NSString *DecodeWithTable(NSData *data, const uint16_t *high) {
    if (!data) return nil;
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *out = [NSMutableString stringWithCapacity:data.length];
    for (NSUInteger i = 0; i < data.length; ++i) {
        uint16_t value = bytes[i] < 0x80 ? bytes[i] : high[bytes[i] - 0x80];
        // A byte the code page does not define is shown as the replacement
        // character rather than dropped, so the text keeps its length.
        unichar c = (value == 0xFFFF) ? 0xFFFD : (unichar)value;
        [out appendString:[NSString stringWithCharacters:&c length:1]];
    }
    return out;
}

static NSData *EncodeWithTable(NSString *text, const uint16_t *high) {
    if (!text) return nil;
    NSMutableData *out = [NSMutableData dataWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        unsigned char b = '?';
        if (c < 0x80) {
            b = (unsigned char)c;
        } else {
            for (int h = 0; h < 128; ++h) {
                if (high[h] == c) { b = (unsigned char)(0x80 + h); break; }
            }
        }
        [out appendBytes:&b length:1];
    }
    return out;
}

+ (NSString *)stringFromData:(NSData *)data codepage:(unsigned int)codepage {
    const uint16_t *table = TableForCodepage(codepage);
    if (table) return DecodeWithTable(data, table);
    NSStringEncoding enc = [self encodingForCodepage:codepage];
    if (!enc || !data) return nil;
    return [[NSString alloc] initWithData:data encoding:enc];
}

+ (NSData *)dataFromString:(NSString *)string codepage:(unsigned int)codepage {
    const uint16_t *table = TableForCodepage(codepage);
    if (table) return EncodeWithTable(string, table);
    NSStringEncoding enc = [self encodingForCodepage:codepage];
    if (!enc || !string) return nil;
    return [string dataUsingEncoding:enc allowLossyConversion:YES];
}

- (BOOL)reinterpretAsCodepage:(unsigned int)codepage {
    if (![EditorController supportsCodepage:codepage]) { NppBeep(); return NO; }
    NSStringEncoding target = [EditorController encodingForCodepage:codepage];

    NppDocument *doc = self.currentDocument;
    NSString *text = [self documentText];
    // Recover the bytes as they stand, then read them through the new charset.
    NSData *bytes = doc.codepage
        ? [EditorController dataFromString:text codepage:doc.codepage]
        : [text dataUsingEncoding:doc.encoding ?: NSUTF8StringEncoding allowLossyConversion:YES];
    NSString *reread = [EditorController stringFromData:bytes codepage:codepage];
    if (!reread) { NppBeep(); return NO; }

    [self.sci message:SCI_BEGINUNDOACTION];
    [self setDocumentText:reread];
    [self.sci message:SCI_ENDUNDOACTION];
    doc.encoding = target ?: NSUTF8StringEncoding;
    doc.codepage = codepage;
    doc.hasBOM = NO;
    doc.encodingChanged = YES;      // undo may reach the savepoint; the code page still differs
    doc.modified = YES;
    [self refreshChrome];
    return YES;
}

- (BOOL)convertToCodepage:(unsigned int)codepage {
    if (![EditorController supportsCodepage:codepage]) { NppBeep(); return NO; }
    NSStringEncoding target = [EditorController encodingForCodepage:codepage];
    if (!target) {                                   // code-page-only charset
        self.currentDocument.codepage = codepage;
        self.currentDocument.encodingChanged = YES;
        self.currentDocument.modified = YES;
        [self refreshChrome];
        return YES;
    }
    // The text is unchanged; only the encoding it will be written in changes.
    if (![[self documentText] canBeConvertedToEncoding:target]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Some characters cannot be represented in this encoding.";
        alert.informativeText = @"Converting will replace them.";
        [alert addButtonWithTitle:@"Convert"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return NO;
    }
    [self setEncoding:target withBOM:NO];
    return YES;
}

@end
