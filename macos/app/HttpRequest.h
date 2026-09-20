// Tools > HTTP Request: a request as curl would send it - method, address,
// query parameters, headers, body, a name and password - sent with libcurl,
// and the answer as it came: the status line, the headers in their order, the
// body. A request can be written out as a curl command and read from one.
// No windows here; ToolsWindows has the one that drives this.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A name and a value, in the order they were given: headers and parameters may repeat, and their order is kept.
@interface NppHttpPair : NSObject
@property (nonatomic, copy) NSString *name, *value;
+ (instancetype)pairWithName:(NSString *)name value:(NSString *)value;
/// One to a line: "Name: value" (or "name=value" with `separator` "="). Empty lines and lines that
/// begin with # are passed over; a line without the separator is a name with an empty value.
+ (NSArray<NppHttpPair *> *)pairsFromText:(NSString *)text separator:(NSString *)separator;
+ (NSString *)textFromPairs:(NSArray<NppHttpPair *> *)pairs separator:(NSString *)separator;
@end

@interface NppHttpRequest : NSObject <NSCopying>
@property (nonatomic, copy) NSString *method;                       // "GET"
@property (nonatomic, copy) NSString *address;                      // as typed; "example.com/x" is taken for http://
@property (nonatomic, copy) NSArray<NppHttpPair *> *parameters;     // added to the address's query, percent-encoded
@property (nonatomic, copy) NSArray<NppHttpPair *> *headers;
@property (nonatomic, copy, nullable) NSData *body;
@property (nonatomic, copy) NSString *username, *password;          // Basic authentication when a name is given
@property (nonatomic) BOOL followRedirects;                         // YES
@property (nonatomic) BOOL allowInvalidCertificates;                // NO; curl's -k
@property (nonatomic) NSTimeInterval timeout;                       // 30 seconds; 0 for none
/// The address with the parameters in its query; nil when it is no http or https address.
- (nullable NSURL *)url;
/// The request as a command for curl, quoted for a POSIX shell, one option to a line.
- (NSString *)curlCommand;
/// A curl command read back: -X, -H, -d / --data / --data-raw / --data-binary / --data-urlencode / --json,
/// -u, -k, -L, -I, -G, -A, -e, -b, --url, -m, --compressed; quotes, backslashes and line continuations
/// as a shell reads them. nil (and why) when it is not a curl command or has no address.
+ (nullable instancetype)requestFromCurlCommand:(NSString *)command error:(NSString *_Nullable *_Nullable)error;
@end

@interface NppHttpResponse : NSObject
@property (nonatomic) NSInteger status;                              // 0 when there was no answer
@property (nonatomic, copy) NSString *statusLine;                    // "HTTP/1.1 200 OK"
@property (nonatomic, copy) NSArray<NppHttpPair *> *headers;         // of the last answer, when redirects were followed
@property (nonatomic, copy) NSData *body;
@property (nonatomic, copy, nullable) NSString *error;               // what went wrong, in libcurl's words
@property (nonatomic, copy, nullable) NSString *finalAddress;
@property (nonatomic) NSTimeInterval elapsed;
@property (nonatomic) NSInteger redirects;
- (nullable NSString *)valueOfHeader:(NSString *)name;
/// The body as text: in the charset the Content-Type names, else UTF-8, else nil - it is no text.
- (nullable NSString *)text;
/// The headers as they came, status line first.
- (NSString *)headerText;
@end

@interface NppHttpClient : NSObject
/// Sends and waits. `cancelled` is asked while waiting; when it answers YES the transfer is given up.
+ (NppHttpResponse *)send:(NppHttpRequest *)request cancelled:(nullable BOOL (^)(void))cancelled;
@end

NS_ASSUME_NONNULL_END
