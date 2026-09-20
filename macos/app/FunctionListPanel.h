// "Function List": the declarations found in the current document, in a panel.
// The patterns are Notepad++'s own, read from the bundled functionList files.
// A small built-in table covers the languages whose upstream pattern uses PCRE
// features ICU has no equivalent for.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

@interface FunctionListPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)reload;
@property (nonatomic, readonly) BOOL visible;
/// Names found in the current document; exposed for tests.
- (NSArray<NSString *> *)functionNames;
/// FunctionListPanel::serialize, for -export=functionList: the document's
/// functions as {"leaves":[...],"nodes":[{"leaves":[...],"name":class}],"root":name},
/// written to <file>.result.json (or `path`). NO when there is no file.
+ (BOOL)exportFunctionListOf:(EditorController *)editor to:(nullable NSString *)path;
@end

NS_ASSUME_NONNULL_END
