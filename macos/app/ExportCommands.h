// NppExport's job: the styled text - the selection when there is one, the
// whole document otherwise - as RTF and as HTML that keep the colours the
// editor shows, written to a file or put on the clipboard.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface EditorController (ExportCommands)

/// The exported range: the selection, or the whole document without one.
- (NSRange)exportRange;

/// Standalone HTML for the range: a <pre> with the editor's default colours
/// and a <span> per style run.
- (NSString *)exportHTMLInRange:(NSRange)range;

/// RTF for the range: font and colour tables from the styles the range uses.
- (NSData *)exportRTFInRange:(NSRange)range;

/// The clipboard, with RTF and/or HTML flavours (plain text rides along).
- (void)exportToClipboardRTF:(BOOL)rtf HTML:(BOOL)html;

@end

NS_ASSUME_NONNULL_END
