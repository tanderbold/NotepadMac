// XML handling, the part XML Tools provides: pretty print, linearize, check
// syntax, validate against a schema, evaluate XPath, report the path at the
// caret, escape a selection and apply an XSL transformation.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppXmlPrettyStyle) {
    NppXmlPrettyDefault = 0,    // indent elements
    NppXmlPrettyAttributes,     // one attribute per line
    NppXmlPrettyIndentOnly,     // re-indent without moving anything else
};

/// Where a document is not well formed, or does not match its schema.
@interface NppXmlError : NSObject
@property (nonatomic, copy) NSString *message;
@property (nonatomic) NSInteger line;      // zero-based, -1 when unknown
@property (nonatomic) NSInteger column;    // zero-based, -1 when unknown
@end

@interface EditorController (XmlCommands)

+ (nullable NppXmlError *)checkXMLSyntax:(NSString *)text;
+ (nullable NSString *)prettyPrintXML:(NSString *)text style:(NppXmlPrettyStyle)style;
+ (nullable NSString *)linearizeXML:(NSString *)text;
+ (nullable NSArray<NSString *> *)evaluateXPath:(NSString *)expression
                                         onText:(NSString *)text
                                          error:(NSString *_Nullable *_Nullable)error;
+ (nullable NSString *)applyXSL:(NSString *)stylesheet toText:(NSString *)text
                          error:(NSString *_Nullable *_Nullable)error;
/// XSD validation, which NSXMLDocument cannot do; libxml2 is used for it.
+ (nullable NppXmlError *)validateXML:(NSString *)text againstSchema:(NSString *)schema;
/// DTD validation, which NSXMLDocument can do.
+ (nullable NppXmlError *)validateXMLAgainstInternalDTD:(NSString *)text;

+ (NSString *)escapeXMLCharacters:(NSString *)text;
+ (NSString *)unescapeXMLCharacters:(NSString *)text;

// The commands
- (BOOL)prettyPrintXMLDocument:(NppXmlPrettyStyle)style;
- (BOOL)linearizeXMLDocument;
- (nullable NppXmlError *)checkXMLSyntaxOfDocument;
- (void)escapeSelectionForXML:(BOOL)escape;
/// The element path at the caret, optionally with positional predicates.
- (nullable NSString *)xmlPathAtCaretWithPredicates:(BOOL)withPredicates;

@end

NS_ASSUME_NONNULL_END
