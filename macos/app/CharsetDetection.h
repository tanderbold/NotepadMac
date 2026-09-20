// Working out a file's character set when nothing says it: no byte-order
// mark, and not valid UTF-8. Notepad++ ships uchardet for this (the same
// statistical detector Mozilla wrote for its browser), and so does this
// build: the sources under PowerEditor/src/uchardet are compiled in as they
// are. This is the whole of what is asked of it.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppCharsetDetection : NSObject

/// The IANA name uchardet gives the bytes, or nil when it has nothing to
/// say - pure ASCII, or too little to judge. TIS-620 is never reported, as
/// on Windows: the detector calls too much UTF-8 by that name.
+ (nullable NSString *)charsetNameForData:(NSData *)data;

/// The NSStringEncoding for what uchardet says, or 0 when it says nothing or
/// names a set this platform cannot read.
+ (NSStringEncoding)encodingGuessedForData:(NSData *)data;

/// UTF-16 without a byte-order mark shows itself in its NUL bytes: text that
/// is mostly ASCII has a zero every other byte. 0 when the bytes are not that.
+ (NSStringEncoding)utf16EncodingWithoutMarkForData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
