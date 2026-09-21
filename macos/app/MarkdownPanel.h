// "Markdown Preview": the current document rendered as Markdown in a docked
// panel, live as it is edited - MarkdownViewer++'s job. CommonMark is
// rendered by cmark (macos/third_party/cmark); GFM tables, which core
// CommonMark leaves out, are turned into HTML by a pre-pass here.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

@interface MarkdownPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)refresh;
@property (nonatomic, readonly) BOOL visible;
/// The page last given to the web view; what the tests read.
@property (nonatomic, readonly, nullable) NSString *lastHTML;

/// Markdown to an HTML fragment: the table pre-pass, then cmark.
+ (NSString *)htmlFromMarkdown:(NSString *)markdown;
/// The pre-pass alone: GFM tables become HTML tables (alignment kept, cell
/// text still rendered as Markdown); everything else is left as it stands.
+ (NSString *)tablesToHTML:(NSString *)markdown;
@end

NS_ASSUME_NONNULL_END
