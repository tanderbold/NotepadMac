// The windows of the Tools menu: digests of a text or of files (as Notepad++'s
// own dialogs are), password hashes, Base64 / Base58 / Base32 both ways, and
// the password generator. What they work out is in CryptoTools; here are only
// the controls, which the tests drive as a user would.
#import <Cocoa/Cocoa.h>
#import "ToolsCommands.h"
#import "CryptoTools.h"
#import "HttpRequest.h"

NS_ASSUME_NONNULL_BEGIN

/// "Generate SHA-256 digest" and "Generate SHA-256 digest from files".
@interface NppDigestWindow : NSObject
+ (instancetype)shared;
- (void)showForDigest:(NppDigest)digest fromFiles:(BOOL)fromFiles;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NppDigest digest;
@property (nonatomic, readonly) NSTextView *input, *result;
@property (nonatomic, readonly) NSButton *eachLine, *chooseFiles, *clipboardButton;
/// The key of an HMAC; empty for a plain digest. Hidden for the digests HMAC is not defined over here.
@property (nonatomic, readonly) NSTextField *hmacKey;
/// What the controls say now, worked out again: every change to them calls it.
- (void)refresh;
/// As choosing them in the open panel does.
- (void)digestFiles:(NSArray<NSString *> *)paths;
@end

/// bcrypt, scrypt, Argon2 and PBKDF2, in the digests' window - the text, each line on its own if wanted, the
/// result, from files too - with what such a hash needs besides: its settings, a salt, and a password checked against a hash.
@interface NppPasswordHashWindow : NSObject
+ (instancetype)shared;
- (void)showForKind:(NppPasswordHash)kind fromFiles:(BOOL)fromFiles;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NppPasswordHash kind;
@property (nonatomic, readonly) NSTextView *input, *result;
@property (nonatomic, readonly) NSButton *eachLine, *chooseFiles, *clipboardButton;
/// Ticked, the result is the bare key in hexadecimal and not the string one stores.
@property (nonatomic, readonly) NSButton *bareKey;
/// In hexadecimal. Empty, every hash is given a random salt of its own.
@property (nonatomic, readonly) NSTextField *salt;
@property (nonatomic, readonly) NSTextField *toVerify, *verdict, *problem;
/// The settings' fields by name: bcryptCost, bcryptVersion (a pop-up), scryptLogN, scryptR, scryptP,
/// argon2Variant (a pop-up), argon2Memory, argon2Passes, argon2Lanes, pbkdf2Digest (a pop-up), pbkdf2Rounds, keyLength.
@property (nonatomic, readonly) NSDictionary<NSString *, NSControl *> *fields;
/// The rows shown for the kind the window is open for.
- (NSArray<NSString *> *)visibleFieldNames;
- (NppPasswordHashSettings *)settings;
- (void)newSalt:(nullable id)sender;
/// Works the result out again, off the main thread, once typing pauses; one job at a time.
- (void)refresh;
/// Works the result out again. Typing does this off the main thread; this waits for it.
- (void)refreshAndWait;
/// How many key derivations typing has started (for the suite).
@property (nonatomic, readonly) NSUInteger jobsStarted;
- (void)hashFilesAndWait:(NSArray<NSString *> *)paths;
- (void)verifyAndWait;
/// A hash with the kind's default settings and a random salt: what "into clipboard" and the password generator give.
+ (nullable NSString *)defaultHashOf:(NSData *)password kind:(NppPasswordHash)kind;
@end

/// One encoding to a window: Base64, Base58 or Base32, as the menu item said.
@interface NppBaseWindow : NSObject
+ (instancetype)shared;
/// NppBase64, NppBase58 or NppBase32; their variants are the window's checkbox.
- (void)showForEncoding:(NppBaseEncoding)encoding;
@property (nonatomic, readonly) NSPanel *panel;
/// What is encoded to now: the window's encoding, or its variant when the box is ticked.
@property (nonatomic, readonly) NppBaseEncoding encoding;
/// "Base64 (URL-safe)" or "Base58Check"; hidden for Base32, which has no variant here.
@property (nonatomic, readonly) NSButton *variant;
/// Encode / Decode, and - when encoding - whether the input is text or bytes written in hexadecimal.
@property (nonatomic, readonly) NSSegmentedControl *direction;
@property (nonatomic, readonly) NSButton *inputIsText, *inputIsHex;
@property (nonatomic, readonly) NSTextView *input, *output, *outputBytes;
@property (nonatomic, readonly) NSTextField *problem, *outputLabel, *bytesLabel;
- (void)refresh;
@end

@interface NppPasswordWindow : NSObject
+ (instancetype)shared;
- (void)show;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSTextField *length, *howMany, *symbols, *entropy;
@property (nonatomic, readonly) NSButton *upper, *lower, *digits, *useSymbols, *noLookalikes, *requireEach;
@property (nonatomic, readonly) NSTextView *result;
/// "None", the four password hashes, then the digests: the hash of each password, with the kind's default settings.
@property (nonatomic, readonly) NSPopUpButton *hashKind;
@property (nonatomic, readonly) NSTextView *hashes;
/// Waits for the hashes, which the window works out off the main thread.
- (void)generateAndWait;
/// The sets the ticked boxes stand for, look-alikes taken out when that is asked.
- (NSArray<NSString *> *)chosenSets;
- (void)generate:(nullable id)sender;
/// Puts the result where the caret is; set by the application.
@property (nonatomic, copy, nullable) void (^insertIntoDocument)(NSString *text);
- (void)insert:(nullable id)sender;
@end

/// Tools > HTTP Request: what one would give curl - a method, an address, parameters, headers, a body,
/// a name and password - sent, and the answer shown: its status, its headers, its body.
@interface NppHttpWindow : NSObject
+ (instancetype)shared;
- (void)show;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSPopUpButton *method, *contentType;
@property (nonatomic, readonly) NSTextField *address, *username, *password, *timeout, *status, *hint;
/// Parameters | Headers | Body | Options - one of them in view at a time - and Body | Headers of the answer.
@property (nonatomic, readonly) NSSegmentedControl *section, *answerSection;
@property (nonatomic, readonly) NSTextView *parameters, *headers, *body, *answer;
@property (nonatomic, readonly) NSButton *followRedirects, *allowInvalidCertificates, *sendButton;
/// Ticked (as it is to begin with), an answer that says it is JSON is shown laid out.
@property (nonatomic, readonly) NSButton *formatJSON;
/// The request the controls describe, and the controls set from a request.
- (NppHttpRequest *)request;
- (void)showRequest:(NppHttpRequest *)request;
@property (nonatomic, readonly, nullable) NppHttpResponse *response;
/// The button sends off the main thread (and, pressed again, cancels); this sends and waits.
- (void)sendAndWait;
- (void)send:(nullable id)sender;
- (void)sectionChanged:(nullable id)sender;
- (void)answerSectionChanged:(nullable id)sender;
/// The clipboard's curl command into the controls; NO (and the reason in `status`) when it is none.
- (BOOL)pasteCurlCommand:(nullable id)sender;
- (void)copyAsCurl:(nullable id)sender;
/// Opens the answer's body as a new document; `contentType` is the answer's. Set by the application.
@property (nonatomic, copy, nullable) void (^openInNewDocument)(NSString *text, NSString *contentType);
- (void)openAnswer:(nullable id)sender;
@end

/// The Converter plugin's Conversion Panel: one value as a character and in
/// decimal, hexadecimal, binary and octal, each row typed into or copied or
/// inserted; typing in any row fills the others.
@interface NppConverterWindow : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSTextField *ascii, *dec, *hex, *bin, *oct;
/// Inserts a row's text at the caret. Set by the application.
@property (nonatomic, copy, nullable) void (^insert)(NSString *);
- (void)show;
/// What typing into a row does: the row's value spread over the other rows,
/// or the row marked wrong. The tests call it as the delegate does.
- (void)syncFrom:(NSTextField *)field;
@end

/// The selection as a QR code: the picture, Copy Image and Save.
@interface NppQrWindow : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSImageView *imageView;
- (void)showForText:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
