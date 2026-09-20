// Reads Notepad++'s own functionList definitions rather than a hand-written
// pattern table, so the Function List recognises what upstream recognises.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One entry found in a document.
@interface NppFunctionEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *container;   // enclosing class, if any
@property (nonatomic) NSUInteger line;                       // zero-based
/// The row that heads a class, above its members; not a function itself.
@property (nonatomic) BOOL isClass;
@end

@interface FunctionListCatalog : NSObject
+ (instancetype)sharedCatalog;

/// Parser ids loaded from the bundled functionList folder.
@property (nonatomic, readonly) NSArray<NSString *> *parserIDs;
/// Languages and extensions that have a parser, from the association map.
- (nullable NSString *)parserIDForLanguage:(NSString *)language extension:(nullable NSString *)ext;
/// Entries found in `text` using the parser for that language.
- (NSArray<NppFunctionEntry *> *)entriesInText:(NSString *)text
                                   forLanguage:(NSString *)language
                                     extension:(nullable NSString *)ext;

/// Rewrites literal newlines inside attribute values as character references,
/// so a conformant XML parser does not fold them into spaces. Most of these
/// patterns are written with (?x), where losing the newlines would let the
/// first # comment swallow the rest of the pattern. Exposed to be tested.
+ (NSData *)dataPreservingAttributeNewlines:(NSData *)data;
@end

NS_ASSUME_NONNULL_END
