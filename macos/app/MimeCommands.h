// The selection conversions the MIME Tools plugin offers on Windows: Base64
// in its seven flavours, Quoted-printable, URL encoding in three strengths,
// and SAML decode. Each follows mimeTools.cpp and its helpers.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppUrlEncodeMethod) {
    NppUrlEncodeRFC1738,   // the RFC's unsafe characters and non-printables
    NppUrlEncodeExtended,  // those plus !*'()+$, - what most implementations do
    NppUrlEncodeFull,      // every byte
};

@interface EditorController (MimeCommands)

// The conversions themselves, on text; nil where the input cannot be decoded.
+ (NSString *)mimeBase64Encode:(NSString *)text padded:(BOOL)padded wrapped:(BOOL)wrapped byLine:(BOOL)byLine;
+ (nullable NSString *)mimeBase64Decode:(NSString *)text strict:(BOOL)strict byLine:(BOOL)byLine;
+ (NSString *)mimeQuotedPrintableEncode:(NSString *)text;
+ (nullable NSString *)mimeQuotedPrintableDecode:(NSString *)text;
+ (NSString *)mimeUrlEncode:(NSString *)text method:(NppUrlEncodeMethod)method byLine:(BOOL)byLine;
+ (NSString *)mimeUrlDecode:(NSString *)text;
+ (nullable NSString *)mimeSamlDecode:(NSString *)text;

/// Runs one conversion over the selection, in one undo action. An empty
/// selection beeps and counts as handled; NO only means the conversion
/// returned nil - input the caller should report as undecodable.
- (BOOL)mimeTransformSelection:(NSString *_Nullable (NS_NOESCAPE ^)(NSString *))transform;

@end

NS_ASSUME_NONNULL_END
