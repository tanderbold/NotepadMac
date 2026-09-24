// NppExport (chcg/NPP_ExportPlugin), natively: the styled bytes come out of
// the document with SCI_GETSTYLEDTEXTFULL, the colours and faces of each
// style out of the view, and the result is standalone HTML or RTF. As the
// plugin does, a selection exports alone and an empty one means the document.
#import "ExportCommands.h"
#import "ScintillaView.h"

typedef struct { long fore, back; BOOL bold, italic, underline; NSString *font; long size; } RunStyle;

static NSString *HexColour(long bgr) {
    return [NSString stringWithFormat:@"#%02lx%02lx%02lx", bgr & 0xFF, (bgr >> 8) & 0xFF, (bgr >> 16) & 0xFF];
}

@implementation EditorController (ExportCommands)

- (NSRange)exportRange {
    long start = [self.sci message:SCI_GETSELECTIONSTART], end = [self.sci message:SCI_GETSELECTIONEND];
    if (start == end) { start = 0; end = [self.sci message:SCI_GETLENGTH]; }
    return NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
}

/// Byte+style pairs for the range, exactly what the buffer holds.
- (NSData *)styledBytesInRange:(NSRange)range {
    NSMutableData *buffer = [NSMutableData dataWithLength:range.length * 2 + 2];
    struct { struct { long cpMin, cpMax; } chrg; char *lpstrText; } tr;
    tr.chrg.cpMin = (long)range.location;
    tr.chrg.cpMax = (long)NSMaxRange(range);
    tr.lpstrText = (char *)buffer.mutableBytes;
    [self.sci message:SCI_GETSTYLEDTEXTFULL wParam:0 lParam:(sptr_t)&tr];
    return buffer;
}

- (RunStyle)styleNumber:(int)styleID {
    ScintillaView *sci = self.sci;
    char face[256] = "";
    [sci message:SCI_STYLEGETFONT wParam:(uptr_t)styleID lParam:(sptr_t)face];
    return (RunStyle){
        .fore = [sci message:SCI_STYLEGETFORE wParam:(uptr_t)styleID lParam:0],
        .back = [sci message:SCI_STYLEGETBACK wParam:(uptr_t)styleID lParam:0],
        .bold = [sci message:SCI_STYLEGETBOLD wParam:(uptr_t)styleID lParam:0] != 0,
        .italic = [sci message:SCI_STYLEGETITALIC wParam:(uptr_t)styleID lParam:0] != 0,
        .underline = [sci message:SCI_STYLEGETUNDERLINE wParam:(uptr_t)styleID lParam:0] != 0,
        .font = [NSString stringWithUTF8String:face] ?: @"Menlo",
        .size = [sci message:SCI_STYLEGETSIZE wParam:(uptr_t)styleID lParam:0],
    };
}

- (NSString *)exportHTMLInRange:(NSRange)range {
    NSData *styled = [self styledBytesInRange:range];
    const uint8_t *bytes = (const uint8_t *)styled.bytes;
    RunStyle base = [self styleNumber:STYLE_DEFAULT];

    NSMutableString *body = [NSMutableString string];
    // The text is UTF-8 bytes: a run's bytes are gathered and decoded whole, so a
    // character of several bytes (Я) stays one character (NppExport writes UTF-8 too).
    NSMutableData *pending = [NSMutableData data];
    void (^flush)(void) = ^{
        if (!pending.length) return;
        NSString *chunk = [[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding]
                       ?: [[NSString alloc] initWithData:pending encoding:NSISOLatin1StringEncoding];
        [body appendString:chunk ?: @""];
        pending.length = 0;
    };
    int runStyle = -1;
    for (NSUInteger i = 0; i + 1 < styled.length && i / 2 < range.length; i += 2) {
        int style = bytes[i + 1];
        // A style change inside a multi-byte character would split it: it waits for the character's end.
        BOOL continuation = (bytes[i] & 0xC0) == 0x80;
        if (style != runStyle && !continuation) {
            flush();
            if (runStyle >= 0) [body appendString:@"</span>"];
            RunStyle s = [self styleNumber:style];
            NSMutableString *css = [NSMutableString string];
            [css appendFormat:@"color:%@;", HexColour(s.fore)];
            if (s.back != base.back) [css appendFormat:@"background:%@;", HexColour(s.back)];
            if (s.bold) [css appendString:@"font-weight:bold;"];
            if (s.italic) [css appendString:@"font-style:italic;"];
            if (s.underline) [css appendString:@"text-decoration:underline;"];
            if (![s.font isEqualToString:base.font]) [css appendFormat:@"font-family:'%@',monospace;", s.font];
            if (s.size != base.size) [css appendFormat:@"font-size:%ldpt;", s.size];
            [body appendFormat:@"<span style=\"%@\">", css];
            runStyle = style;
        }
        uint8_t c = bytes[i];
        if (c == '&') [pending appendBytes:"&amp;" length:5];
        else if (c == '<') [pending appendBytes:"&lt;" length:4];
        else if (c == '>') [pending appendBytes:"&gt;" length:4];
        else [pending appendBytes:&c length:1];
    }
    flush();
    if (runStyle >= 0) [body appendString:@"</span>"];

    long tabs = [self.sci message:SCI_GETTABWIDTH wParam:0 lParam:0];
    return [NSString stringWithFormat:
        @"<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        @"<title>%@</title>\n</head>\n<body>\n"
        @"<pre style=\"font-family:'%@',monospace;font-size:%ldpt;color:%@;background:%@;tab-size:%ld;\">"
        @"%@</pre>\n</body>\n</html>\n",
        self.currentDocument.displayName ?: @"Exported text",
        base.font, base.size, HexColour(base.fore), HexColour(base.back), tabs, body];
}

- (NSData *)exportRTFInRange:(NSRange)range {
    NSData *styled = [self styledBytesInRange:range];
    const uint8_t *bytes = (const uint8_t *)styled.bytes;
    RunStyle base = [self styleNumber:STYLE_DEFAULT];

    // The tables collect what the range actually uses, in first-seen order.
    NSMutableArray<NSString *> *fonts = [NSMutableArray arrayWithObject:base.font];
    NSMutableArray<NSNumber *> *colours = [NSMutableArray arrayWithObjects:@(base.fore), @(base.back), nil];
    NSInteger (^fontIndex)(NSString *) = ^NSInteger(NSString *f) {
        NSUInteger at = [fonts indexOfObject:f];
        if (at == NSNotFound) { [fonts addObject:f]; return (NSInteger)fonts.count - 1; }
        return (NSInteger)at;
    };
    NSInteger (^colourIndex)(long) = ^NSInteger(long c) {
        NSUInteger at = [colours indexOfObject:@(c)];
        if (at == NSNotFound) { [colours addObject:@(c)]; return (NSInteger)colours.count - 1; }
        return (NSInteger)at;
    };

    NSMutableString *body = [NSMutableString string];
    int runStyle = -1;
    for (NSUInteger i = 0; i + 1 < styled.length && i / 2 < range.length; i += 2) {
        int style = bytes[i + 1];
        if (style != runStyle) {
            RunStyle s = [self styleNumber:style];
            [body appendFormat:@"\n\\pard\\plain\\f%ld\\fs%ld\\cf%ld\\highlight%ld%@%@%@ ",
             (long)fontIndex(s.font), s.size * 2, (long)colourIndex(s.fore),
             s.back == base.back ? 1L : (long)colourIndex(s.back),
             s.bold ? @"\\b" : @"", s.italic ? @"\\i" : @"", s.underline ? @"\\ul" : @""];
            runStyle = style;
        }
        uint8_t c = bytes[i];
        if (c == '\\') [body appendString:@"\\\\"];
        else if (c == '{') [body appendString:@"\\{"];
        else if (c == '}') [body appendString:@"\\}"];
        else if (c == '\n') [body appendString:@"\\par "];
        else if (c == '\r') { /* the \n of a CRLF writes the \par */
            if (!(i + 2 < styled.length && bytes[i + 2] == '\n')) [body appendString:@"\\par "];
        }
        else if (c == '\t') [body appendString:@"\\tab "];
        else if (c < 0x80) [body appendFormat:@"%c", c];
        else {
            // A multi-byte UTF-8 character: its bytes share one style, so it
            // can be gathered whole and written as RTF's \uN (surrogates for
            // the astral planes), which every reader understands.
            int extra = (c & 0xE0) == 0xC0 ? 1 : (c & 0xF0) == 0xE0 ? 2 : 3;
            uint32_t cp = c & (0x3F >> extra);
            for (int k = 0; k < extra && i + 2 < styled.length; ++k) {
                i += 2;
                cp = (cp << 6) | (bytes[i] & 0x3F);
            }
            if (cp >= 0x10000) {
                uint32_t v = cp - 0x10000;
                [body appendFormat:@"\\u%d?\\u%d?", (int)(int16_t)(0xD800 + (v >> 10)),
                                                    (int)(int16_t)(0xDC00 + (v & 0x3FF))];
            } else {
                [body appendFormat:@"\\u%d?", (int)(int16_t)cp];
            }
        }
    }

    NSMutableString *fontTable = [NSMutableString stringWithString:@"{\\fonttbl"];
    for (NSUInteger i = 0; i < fonts.count; ++i)
        [fontTable appendFormat:@"{\\f%lu\\fmodern %@;}", (unsigned long)i, fonts[i]];
    [fontTable appendString:@"}"];
    NSMutableString *colourTable = [NSMutableString stringWithString:@"{\\colortbl"];
    for (NSNumber *c in colours) {
        long v = c.longValue;
        [colourTable appendFormat:@"\\red%ld\\green%ld\\blue%ld;", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF];
    }
    [colourTable appendString:@"}"];

    NSString *rtf = [NSString stringWithFormat:@"{\\rtf1\\ansi\\uc1\\deff0%@%@%@\n}\n",
                     fontTable, colourTable, body];
    return [rtf dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
}

- (void)exportToClipboardRTF:(BOOL)rtf HTML:(BOOL)html {
    NSRange range = [self exportRange];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    NSMutableArray *types = [NSMutableArray arrayWithObject:NSPasteboardTypeString];
    if (rtf) [types addObject:NSPasteboardTypeRTF];
    if (html) [types addObject:NSPasteboardTypeHTML];
    [pb declareTypes:types owner:nil];
    NSData *textBytes = [self styledBytesInRange:range];
    NSMutableData *plain = [NSMutableData dataWithCapacity:range.length];
    const uint8_t *b = (const uint8_t *)textBytes.bytes;
    for (NSUInteger i = 0; i + 1 < textBytes.length && i / 2 < range.length; i += 2)
        [plain appendBytes:&b[i] length:1];
    [pb setString:[[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] ?: @""
          forType:NSPasteboardTypeString];
    if (rtf) [pb setData:[self exportRTFInRange:range] forType:NSPasteboardTypeRTF];
    if (html) [pb setString:[self exportHTMLInRange:range] forType:NSPasteboardTypeHTML];
}

@end
