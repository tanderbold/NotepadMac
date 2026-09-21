// What a Mac can read out of pictures: text (Vision's recognizer) and QR
// codes, both ways - none of it exists on Windows, all of it is asked for.
// "Paste Image as Text" runs OCR over the clipboard's image; the Tools menu
// makes a QR code of the selection and reads QR codes back out of an image.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (ImageCommands)

/// The clipboard's image, from image data or from an image file's URL.
+ (nullable NSImage *)clipboardImage;

/// The image's text in reading order, recognized by the system engine;
/// nil when nothing legible is found.
+ (nullable NSString *)textRecognizedInImage:(NSImage *)image;

/// The text as a QR code (error correction M), drawn crisp at `side` pixels;
/// nil when the text does not fit a QR code (~3 KB is the format's end).
+ (nullable NSImage *)qrImageFromText:(NSString *)text side:(CGFloat)side;

/// Every QR code found in the image, top to bottom, joined with newlines;
/// nil when the image carries none.
+ (nullable NSString *)textFromQRCodesInImage:(NSImage *)image;

/// The file's text: an image, or a PDF page by page (rendered at reading
/// resolution, pages joined by blank lines). nil when nothing is legible.
+ (nullable NSString *)textRecognizedInFileAt:(NSString *)path;

/// Edit > Paste Image as Text. NO means: no image, or no text in it.
- (BOOL)pasteImageAsText;

/// Tools > Read QR Code from Clipboard. NO means: no image, or no code in it.
- (BOOL)insertTextFromClipboardQR;

@end

NS_ASSUME_NONNULL_END
