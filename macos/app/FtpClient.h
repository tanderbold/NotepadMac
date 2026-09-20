// FTP transfers, the part NppFTP provides. Foundation dropped ftp:// support,
// so FTP and FTPS go through libcurl; SFTP goes through the system OpenSSH,
// because Apple's libcurl is built without libssh2.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppFtpProtocol) {
    NppFtpPlain = 0,   // ftp://
    NppFtpTLS,         // ftp:// with explicit TLS
    NppFtpSFTP,        // over SSH
};

/// One saved connection. The password is kept in the Keychain, not here.
@interface NppFtpProfile : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NppFtpProtocol protocol;
@property (nonatomic, copy) NSString *host;
@property (nonatomic) NSInteger port;           // 0 uses the protocol default
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *initialDirectory;

+ (instancetype)profileFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
/// "ftp://host:port/path" for this profile.
- (NSString *)urlForPath:(NSString *)path;
@end

/// One entry in a remote directory.
@interface NppFtpEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) BOOL isDirectory;
@property (nonatomic) long long size;
@end

@interface NppFtpClient : NSObject

/// Passwords live in the Keychain, keyed by profile.
+ (BOOL)storePassword:(NSString *)password forProfile:(NppFtpProfile *)profile;
+ (nullable NSString *)passwordForProfile:(NppFtpProfile *)profile;
+ (BOOL)removePasswordForProfile:(NppFtpProfile *)profile;

/// Parses a LIST response. Both the Unix and the DOS layouts appear in the wild.
+ (NSArray<NppFtpEntry *> *)parseListing:(NSString *)listing;

- (instancetype)initWithProfile:(NppFtpProfile *)profile;
@property (nonatomic, readonly) NppFtpProfile *profile;
@property (nonatomic, copy, nullable) NSString *lastError;
/// Set to use this password instead of looking one up in the Keychain. The
/// connection dialog passes it directly, and tests avoid the Keychain entirely.
@property (nonatomic, copy, nullable) NSString *password;

- (nullable NSArray<NppFtpEntry *> *)listDirectory:(NSString *)path;
- (nullable NSData *)downloadFileAtPath:(NSString *)path;
- (BOOL)uploadData:(NSData *)data toPath:(NSString *)path;
- (BOOL)deleteFileAtPath:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
