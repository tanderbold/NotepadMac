// Notepad++ ships a list of functions for each language it knows, in
// PowerEditor/installer/APIs. They carry the names to complete, and for a
// function the return type, the parameters and a description -- which is what a
// call tip is made of. Without them, completion can only offer the words already
// in the document and the lexer's keywords, and a call tip has nothing to say.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One way a function can be called.
@interface NppApiOverload : NSObject
@property (nonatomic, copy) NSString *returnValue;
@property (nonatomic, copy, nullable) NSString *descr;
@property (nonatomic, strong) NSArray<NSString *> *params;
@end

@interface NppApiEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isFunction;
@property (nonatomic, strong) NSArray<NppApiOverload *> *overloads;
@end

@interface ApiCatalog : NSObject
+ (instancetype)sharedCatalog;

/// The languages a file is shipped for, by the name the file carries.
@property (nonatomic, readonly) NSArray<NSString *> *languages;

/// Whether this language's list is matched without regard to case; the file
/// says so, and upstream's default is that it is.
- (BOOL)ignoreCaseForLanguage:(NSString *)language;

/// Every name the language offers, in the order the file lists them.
- (NSArray<NppApiEntry *> *)entriesForLanguage:(NSString *)language;

/// Names starting with `prefix`, for the completion list.
- (NSArray<NSString *> *)completionsForLanguage:(NSString *)language
                                         prefix:(NSString *)prefix;

/// One line per overload, in the shape Notepad++ shows: the return value, the
/// name, the parameters, and the description on a line of its own.
- (NSArray<NSString *> *)callTipsForLanguage:(NSString *)language
                                    function:(NSString *)name;

/// The file's <Environment>: "start", "stop", "param" and "terminal" (one
/// character each) and "wordChars", with upstream's defaults for what it
/// leaves out. nil when no file is shipped for the language.
- (nullable NSDictionary<NSString *, NSString *> *)callTipEnvironmentForLanguage:(NSString *)language;
/// The first entry named `name`, when it is a function; nil when there is
/// none or the first entry of that name is not one (loadFunction gives up).
- (nullable NppApiEntry *)functionNamed:(NSString *)name inLanguage:(NSString *)language;

@end

NS_ASSUME_NONNULL_END
