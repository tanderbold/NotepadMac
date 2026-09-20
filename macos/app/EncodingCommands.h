// Encoding menu: the character sets Notepad++ offers, mapped onto macOS text
// encodings, plus "Encode in" (reinterpret the bytes) versus "Convert to"
// (re-encode the text) -- the distinction Notepad++ draws.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    const char *menuID;     // IDM_FORMAT_*
    const char *group;      // submenu, "" for the top level
    const char *label;      // menu title
    unsigned int codepage;  // Windows code page
} NppCharset;

/// Every character set in the Encoding menu, in menu order.
extern const NppCharset kNppCharsets[];
extern const int kNppCharsetCount;

@interface EditorController (EncodingCommands)

/// NSStringEncoding for a Windows code page, or 0 when unsupported here.
/// Code page 858 has no macOS encoding of its own; see +stringFromData:codepage:.
+ (NSStringEncoding)encodingForCodepage:(unsigned int)codepage;
+ (BOOL)supportsCodepage:(unsigned int)codepage;
+ (nullable NSString *)stringFromData:(NSData *)data codepage:(unsigned int)codepage;
+ (nullable NSData *)dataFromString:(NSString *)string codepage:(unsigned int)codepage;

/// "Encode in X": keep the bytes, read them again through another charset.
- (BOOL)reinterpretAsCodepage:(unsigned int)codepage;
/// "Convert to X": keep the text, write it out in another charset.
- (BOOL)convertToCodepage:(unsigned int)codepage;

@end

NS_ASSUME_NONNULL_END
