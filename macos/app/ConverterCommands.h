// The Converter plugin's conversions (npp-plugins/converter): the selection's
// bytes to hexadecimal and back, and the value arithmetic behind the
// Conversion Panel. The windows are in ToolsWindows.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (ConverterCommands)

/// ascii2hex: every UTF-8 byte as two hex digits, optionally space-separated,
/// optionally broken after every `perLine` source bytes with `eol`.
+ (NSString *)converterHexFromText:(NSString *)text insertSpace:(BOOL)space
                         uppercase:(BOOL)upper charactersPerLine:(NSUInteger)perLine
                               eol:(NSString *)eol;

/// HexString::toAscii: pairs of hex digits, space-separated throughout or not
/// at all (read off the third character), line breaks only between pairs.
/// nil when the text does not conform.
+ (nullable NSString *)converterTextFromHex:(NSString *)hex;

/// The Conversion Panel's model: `value` as typed into `field` (one of
/// "ascii", "dec", "hex", "bin", "oct"), answered as every field's text.
/// An empty value empties every field; nil when the value does not parse.
+ (nullable NSDictionary<NSString *, NSString *> *)converterValues:(NSString *)value
                                                         fromField:(NSString *)field;

@end

NS_ASSUME_NONNULL_END
