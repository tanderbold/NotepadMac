// JSON handling, in the shape JSON Viewer offers it: format, compact, sort,
// validate, and a tree of the document.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// Where a validation failure is, so it can be reported like upstream does.
@interface NppJsonError : NSObject
@property (nonatomic, copy) NSString *message;
@property (nonatomic) NSInteger line;      // zero-based, -1 when unknown
@property (nonatomic) NSInteger column;    // zero-based, -1 when unknown
@property (nonatomic) NSInteger offset;    // character offset, -1 when unknown
@end

@interface EditorController (JsonCommands)

/// nil when the text is valid JSON, otherwise where and why it is not.
+ (nullable NppJsonError *)validateJSON:(NSString *)text;
+ (nullable NSString *)formatJSON:(NSString *)text indent:(NSInteger)spaces sorted:(BOOL)sorted;
+ (nullable NSString *)compactJSON:(NSString *)text;

// The commands
- (BOOL)formatJSONDocument;
- (BOOL)compactJSONDocument;
- (BOOL)sortJSONDocument;
- (nullable NppJsonError *)validateJSONDocument;

/// A flattened tree of the document, one entry per node: "path" and "value".
- (NSArray<NSDictionary<NSString *, NSString *> *> *)jsonTree;

@end

NS_ASSUME_NONNULL_END
