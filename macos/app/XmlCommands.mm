#import "XmlCommands.h"
#import "ScintillaView.h"
#import "EditCommands.h"
#include <libxml/xmlschemas.h>
#include <libxml/parser.h>

@implementation NppXmlError
@end

/// Collects the line and column of the first parse failure. NSXMLDocument
/// reports a message but not a position; NSXMLParser reports both.
@interface NppXmlSyntaxProbe : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong, nullable) NppXmlError *failure;
@end

@implementation NppXmlSyntaxProbe
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    if (self.failure) return;                 // keep the first one
    NppXmlError *error = [[NppXmlError alloc] init];
    error.message = parseError.localizedDescription ?: @"The document is not well formed.";
    error.line = MAX((NSInteger)0, parser.lineNumber - 1);
    error.column = MAX((NSInteger)0, parser.columnNumber - 1);
    self.failure = error;
}
@end

@implementation EditorController (XmlCommands)

#pragma mark - Syntax

+ (NppXmlError *)checkXMLSyntax:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        NppXmlError *error = [[NppXmlError alloc] init];
        error.message = @"The text is not valid UTF-8.";
        error.line = error.column = -1;
        return error;
    }
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    NppXmlSyntaxProbe *probe = [[NppXmlSyntaxProbe alloc] init];
    parser.delegate = probe;
    if ([parser parse] && !probe.failure) return nil;

    if (probe.failure) return probe.failure;
    NppXmlError *error = [[NppXmlError alloc] init];
    error.message = parser.parserError.localizedDescription ?: @"The document is not well formed.";
    error.line = MAX((NSInteger)0, parser.lineNumber - 1);
    error.column = MAX((NSInteger)0, parser.columnNumber - 1);
    return error;
}

#pragma mark - Formatting

+ (NSXMLDocument *)documentFromText:(NSString *)text {
    // XML has no NUL character; a parser handed the text as a C string would stop there and
    // take the part before it for the document, which would then replace all of it.
    if (!text.length || [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 1)]].location != NSNotFound) return nil;
    NSError *error = nil;
    return [[NSXMLDocument alloc] initWithXMLString:text
                                            options:NSXMLNodePreserveCDATA
                                              error:&error];
}

+ (NSString *)prettyPrintXML:(NSString *)text style:(NppXmlPrettyStyle)style {
    NSXMLDocument *doc = [self documentFromText:text];
    if (!doc) return nil;

    NSString *pretty = [doc XMLStringWithOptions:NSXMLNodePrettyPrint | NSXMLNodePreserveCDATA];
    if (style != NppXmlPrettyAttributes) return pretty;

    // "Indent attributes" puts each attribute on its own line, lined up under
    // the element name, which is what the corresponding XML Tools command does.
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *line in [pretty componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (![trimmed hasPrefix:@"<"] || [trimmed hasPrefix:@"</"] || [trimmed hasPrefix:@"<?"]) {
            [out addObject:line];
            continue;
        }
        NSUInteger lead = 0;
        while (lead < line.length && [line characterAtIndex:lead] == ' ') lead++;
        NSString *indent = [line substringToIndex:lead];

        // Split on the spaces that separate attributes, leaving quoted values be.
        NSMutableArray *pieces = [NSMutableArray array];
        NSMutableString *piece = [NSMutableString string];
        BOOL inQuotes = NO;
        for (NSUInteger i = 0; i < trimmed.length; ++i) {
            unichar c = [trimmed characterAtIndex:i];
            if (c == '"') inQuotes = !inQuotes;
            if (c == ' ' && !inQuotes) { [pieces addObject:[piece copy]]; [piece setString:@""]; }
            else [piece appendFormat:@"%C", c];
        }
        if (piece.length) [pieces addObject:[piece copy]];

        if (pieces.count < 2) { [out addObject:line]; continue; }
        [out addObject:[indent stringByAppendingString:pieces.firstObject]];
        NSString *deeper = [indent stringByAppendingString:@"    "];
        for (NSUInteger i = 1; i < pieces.count; ++i) {
            [out addObject:[deeper stringByAppendingString:pieces[i]]];
        }
    }
    return [out componentsJoinedByString:@"\n"];
}

+ (NSString *)linearizeXML:(NSString *)text {
    NSXMLDocument *doc = [self documentFromText:text];
    if (!doc) return nil;
    NSString *compact = [doc XMLStringWithOptions:NSXMLNodeCompactEmptyElement | NSXMLNodePreserveCDATA];
    // Only the whitespace between one tag and the next goes: a line break
    // inside a text node or an attribute value is content, and XML Tools
    // leaves it alone.
    NSRegularExpression *between = [NSRegularExpression regularExpressionWithPattern:
        @">[ \\t]*\\r?\\n[ \\t\\r\\n]*<" options:0 error:NULL];
    // A CDATA section or a comment is content too: the joining is done
    // between them, never inside one.
    NSRegularExpression *opaque = [NSRegularExpression regularExpressionWithPattern:
        @"<!\\[CDATA\\[.*?\\]\\]>|<!--.*?-->" options:NSRegularExpressionDotMatchesLineSeparators error:NULL];
    NSMutableString *out = [NSMutableString string];
    __block NSUInteger at = 0;
    void (^join)(NSRange) = ^(NSRange range) {
        NSString *piece = [compact substringWithRange:range];
        [out appendString:[between stringByReplacingMatchesInString:piece options:0
                                                              range:NSMakeRange(0, piece.length) withTemplate:@"><"]];
    };
    [opaque enumerateMatchesInString:compact options:0 range:NSMakeRange(0, compact.length)
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        join(NSMakeRange(at, m.range.location - at));
        [out appendString:[compact substringWithRange:m.range]];
        at = NSMaxRange(m.range);
    }];
    join(NSMakeRange(at, compact.length - at));
    return out;
}

#pragma mark - XPath and XSL

+ (NSArray<NSString *> *)evaluateXPath:(NSString *)expression
                                onText:(NSString *)text
                                 error:(NSString **)error {
    NSXMLDocument *doc = [self documentFromText:text];
    if (!doc) {
        if (error) *error = @"The document is not well formed.";
        return nil;
    }
    NSError *xpathError = nil;
    NSArray *nodes = [doc nodesForXPath:expression error:&xpathError];
    if (!nodes) {
        if (error) *error = xpathError.localizedDescription ?: @"The expression could not be evaluated.";
        return nil;
    }
    NSMutableArray *results = [NSMutableArray array];
    for (NSXMLNode *node in nodes) {
        // Elements are shown as they are written; other nodes by their value.
        [results addObject:(node.kind == NSXMLElementKind
                            ? (node.XMLString ?: @"")
                            : (node.stringValue ?: @""))];
    }
    return results;
}

+ (NSString *)applyXSL:(NSString *)stylesheet toText:(NSString *)text error:(NSString **)error {
    NSXMLDocument *doc = [self documentFromText:text];
    if (!doc) {
        if (error) *error = @"The document is not well formed.";
        return nil;
    }
    NSError *xslError = nil;
    id result = [doc objectByApplyingXSLTString:stylesheet arguments:nil error:&xslError];
    if (!result) {
        if (error) *error = xslError.localizedDescription ?: @"The transformation failed.";
        return nil;
    }
    if ([result isKindOfClass:[NSXMLDocument class]]) {
        return [result XMLStringWithOptions:NSXMLNodePrettyPrint];
    }
    return [result description];
}

#pragma mark - Validation

+ (NppXmlError *)validateXMLAgainstInternalDTD:(NSString *)text {
    NSError *parseError = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:text
                                                          options:NSXMLDocumentValidate
                                                            error:&parseError];
    if (doc) return nil;
    NppXmlError *error = [[NppXmlError alloc] init];
    error.message = parseError.localizedDescription ?: @"The document does not match its DTD.";
    error.line = error.column = -1;
    return error;
}

/// libxml2 collects its complaints through a callback rather than returning
/// them, so they are gathered into this and read back afterwards.
struct NppSchemaErrors { NSMutableString *text; };

static void CollectSchemaError(void *context, const char *format, ...) {
    struct NppSchemaErrors *sink = (struct NppSchemaErrors *)context;
    if (!sink || !sink->text) return;
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    [sink->text appendString:@(buffer) ?: @""];
}

+ (NppXmlError *)validateXML:(NSString *)text againstSchema:(NSString *)schema {
    NppXmlError *error = [[NppXmlError alloc] init];
    error.line = error.column = -1;

    NSData *schemaData = [schema dataUsingEncoding:NSUTF8StringEncoding];
    NSData *docData = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!schemaData || !docData) { error.message = @"The text is not valid UTF-8."; return error; }

    struct NppSchemaErrors sink = {[NSMutableString string]};

    xmlSchemaParserCtxtPtr parserContext =
        xmlSchemaNewMemParserCtxt((const char *)schemaData.bytes, (int)schemaData.length);
    if (!parserContext) { error.message = @"The schema could not be read."; return error; }
    xmlSchemaSetParserErrors(parserContext, CollectSchemaError, CollectSchemaError, &sink);

    xmlSchemaPtr parsedSchema = xmlSchemaParse(parserContext);
    xmlSchemaFreeParserCtxt(parserContext);
    if (!parsedSchema) {
        error.message = sink.text.length ? sink.text : @"The schema is not valid.";
        return error;
    }

    xmlDocPtr document = xmlReadMemory((const char *)docData.bytes, (int)docData.length,
                                       NULL, "UTF-8", XML_PARSE_NOWARNING | XML_PARSE_NOERROR);
    if (!document) {
        xmlSchemaFree(parsedSchema);
        error.message = @"The document is not well formed.";
        return error;
    }

    xmlSchemaValidCtxtPtr validContext = xmlSchemaNewValidCtxt(parsedSchema);
    xmlSchemaSetValidErrors(validContext, CollectSchemaError, CollectSchemaError, &sink);
    int status = xmlSchemaValidateDoc(validContext, document);

    xmlSchemaFreeValidCtxt(validContext);
    xmlFreeDoc(document);
    xmlSchemaFree(parsedSchema);

    if (status == 0) return nil;
    error.message = sink.text.length ? sink.text : @"The document does not match the schema.";

    // libxml2 writes "file.xml:12: element x" style text; the line is worth having.
    NSRange colon = [error.message rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        NSScanner *scanner = [NSScanner scannerWithString:
                              [error.message substringFromIndex:colon.location + 1]];
        NSInteger line = 0;
        if ([scanner scanInteger:&line] && line > 0) error.line = line - 1;
    }
    return error;
}

#pragma mark - Escaping

+ (NSString *)escapeXMLCharacters:(NSString *)text {
    NSMutableString *out = [text mutableCopy];
    // The ampersand first, or the replacements would be escaped again.
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"'" withString:@"&apos;" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

+ (NSString *)unescapeXMLCharacters:(NSString *)text {
    NSMutableString *out = [text mutableCopy];
    [out replaceOccurrencesOfString:@"&lt;" withString:@"<" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"&gt;" withString:@">" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"&quot;" withString:@"\"" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"&apos;" withString:@"'" options:0 range:NSMakeRange(0, out.length)];
    // The ampersand last, mirroring the order used when escaping.
    [out replaceOccurrencesOfString:@"&amp;" withString:@"&" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

#pragma mark - Commands

- (BOOL)replaceDocumentWithXML:(NSString *)xml {
    if (!xml) { NppBeep(); return NO; }
    ScintillaView *sci = self.sci;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    [sci message:SCI_BEGINUNDOACTION];
    [sci setString:xml];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_GOTOLINE
           wParam:(uptr_t)MIN(line, [sci message:SCI_GETLINECOUNT] - 1) lParam:0];
    [self refreshChrome];
    return YES;
}

- (BOOL)prettyPrintXMLDocument:(NppXmlPrettyStyle)style {
    return [self replaceDocumentWithXML:
        [EditorController prettyPrintXML:[self documentTextIfUTF8] style:style]];
}

- (BOOL)linearizeXMLDocument {
    return [self replaceDocumentWithXML:
        [EditorController linearizeXML:[self documentTextIfUTF8]]];
}

- (NppXmlError *)checkXMLSyntaxOfDocument {
    NppXmlError *error = [EditorController checkXMLSyntax:[self documentTextIfUTF8]];
    if (error && error.line >= 0) {
        [self.sci message:SCI_GOTOLINE wParam:(uptr_t)error.line lParam:0];
        [self refreshChrome];
    }
    return error;
}

- (void)escapeSelectionForXML:(BOOL)escape {
    [self transformSelectedText:^NSString *(NSString *selected) {
        return escape ? [EditorController escapeXMLCharacters:selected]
                      : [EditorController unescapeXMLCharacters:selected];
    }];
}

/// Walks the text up to the caret, keeping a stack of open elements. A real
/// parser cannot be used here: the document is usually mid-edit and not well
/// formed, and the path is still wanted.
- (NSString *)xmlPathAtCaretWithPredicates:(BOOL)withPredicates {
    ScintillaView *sci = self.sci;
    NSString *text = [sci string] ?: @"";
    long caretByte = [sci message:SCI_GETCURRENTPOS];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)caretByte > data.length) return nil;
    NSString *before = [[NSString alloc] initWithData:
        [data subdataWithRange:NSMakeRange(0, (NSUInteger)caretByte)]
                                            encoding:NSUTF8StringEncoding] ?: @"";

    NSMutableArray<NSString *> *stack = [NSMutableArray array];
    NSMutableArray<NSMutableDictionary *> *counts = [NSMutableArray array];
    [counts addObject:[NSMutableDictionary dictionary]];

    NSUInteger i = 0;
    while (i < before.length) {
        if ([before characterAtIndex:i] != '<') { i++; continue; }
        NSUInteger end = i + 1;
        while (end < before.length && [before characterAtIndex:end] != '>') end++;
        if (end >= before.length) break;                 // a tag still being typed
        NSString *inner = [before substringWithRange:NSMakeRange(i + 1, end - i - 1)];
        i = end + 1;

        if ([inner hasPrefix:@"?"] || [inner hasPrefix:@"!"]) continue;   // declaration or comment
        if ([inner hasPrefix:@"/"]) {
            if (stack.count) { [stack removeLastObject]; [counts removeLastObject]; }
            continue;
        }
        BOOL selfClosing = [inner hasSuffix:@"/"];
        NSString *name = inner;
        NSRange space = [name rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (space.location != NSNotFound) name = [name substringToIndex:space.location];
        if ([name hasSuffix:@"/"]) name = [name substringToIndex:name.length - 1];
        if (!name.length) continue;

        NSMutableDictionary *siblings = counts.lastObject;
        NSInteger seen = [siblings[name] integerValue] + 1;
        siblings[name] = @(seen);

        if (selfClosing) continue;
        [stack addObject:withPredicates
            ? [NSString stringWithFormat:@"%@[%ld]", name, (long)seen] : name];
        [counts addObject:[NSMutableDictionary dictionary]];
    }

    if (!stack.count) return nil;
    return [@"/" stringByAppendingString:[stack componentsJoinedByString:@"/"]];
}

@end
