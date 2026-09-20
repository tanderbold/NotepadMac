// Highlight Matching Tags, as Notepad++'s XmlMatchedTagsHighlighter: in
// HTML, XML, PHP, ASP and JSP, the tag the caret is in and its partner are
// marked, and the attributes of the opening one when asked.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

#define NPPMAC_TAGMATCH_INDICATOR 15
#define NPPMAC_TAGATTR_INDICATOR 16

@interface EditorController (TagMatch)
/// Clears the marks and sets them for the caret; YES when a tag was matched.
- (BOOL)highlightMatchingTags;
/// Where the marks are now: {start, length} ranges of the tag and attribute indicators.
- (NSArray<NSValue *> *)rangesOfIndicator:(int)indicator;
@end

NS_ASSUME_NONNULL_END
