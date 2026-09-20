// What the Tools menu works things out with: password hashes (bcrypt, scrypt,
// Argon2, PBKDF2), the digests CommonCrypto has no function for (SHA-3,
// BLAKE2b, CRC-32), HMAC, Base64 / Base58 / Base32 both ways, bytes written as
// hexadecimal, and passwords made from the system's random generator.
// No windows here: everything is a function of its arguments, so the tests can
// hold it against the published vectors.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppPasswordHash) {
    NppPasswordHashBcrypt, NppPasswordHashScrypt, NppPasswordHashArgon2, NppPasswordHashPBKDF2,
};

typedef NS_ENUM(NSInteger, NppArgon2Variant) { NppArgon2id, NppArgon2i, NppArgon2d };

typedef NS_ENUM(NSInteger, NppBaseEncoding) { NppBase64, NppBase64URL, NppBase58, NppBase58Check, NppBase32 };

/// What a password hash is made with. Only the fields of the chosen kind are read.
@interface NppPasswordHashSettings : NSObject <NSCopying>
@property (nonatomic) NppPasswordHash kind;
/// bcrypt: 4...31, the work doubling with each step; and "2a", "2b" or "2y".
@property (nonatomic) NSInteger bcryptCost;
@property (nonatomic, copy) NSString *bcryptVersion;
/// scrypt: N = 2^logN, block size r, parallelism p.
@property (nonatomic) NSInteger scryptLogN, scryptR, scryptP;
/// Argon2: memory in KiB, passes, lanes.
@property (nonatomic) NppArgon2Variant argon2Variant;
@property (nonatomic) NSInteger argon2Memory, argon2Passes, argon2Lanes;
/// PBKDF2: "SHA-1", "SHA-256" or "SHA-512", and the number of rounds.
@property (nonatomic, copy) NSString *pbkdf2Digest;
@property (nonatomic) NSInteger pbkdf2Rounds;
/// Bytes of key wanted (bcrypt's is fixed and ignores this).
@property (nonatomic) NSInteger keyLength;
/// The defaults of each kind, as its own documentation recommends them today.
+ (instancetype)defaultsForKind:(NppPasswordHash)kind;
/// nil when the settings can be worked with, otherwise what is wrong (in English; translate to show).
- (nullable NSString *)problem;
@end

/// A password hash: the string to store, and the bare key inside it.
@interface NppPasswordHashResult : NSObject
@property (nonatomic, copy) NSString *encoded;
@property (nonatomic, copy) NSData *key;
@end

@interface NppCrypto : NSObject

// Bytes as text
+ (NSString *)hexOfData:(NSData *)data;
/// "48656c6c6f", "48 65 6C", "0x48, 0x65", "48:65:6c" - nil when it is not whole bytes of hexadecimal.
+ (nullable NSData *)dataFromHex:(NSString *)hex;
/// Random bytes from the system's generator.
+ (NSData *)randomBytes:(NSUInteger)count;

// Digests beyond CommonCrypto's
+ (NSData *)sha3OfData:(NSData *)data bits:(NSInteger)bits;      // 224, 256, 384, 512
+ (NSData *)blake2bOfData:(NSData *)data;                         // 64 bytes
+ (uint32_t)crc32OfData:(NSData *)data;
/// digest: "MD5", "SHA-1", "SHA-224", "SHA-256", "SHA-384", "SHA-512".
+ (nullable NSData *)hmacOfData:(NSData *)data key:(NSData *)key digest:(NSString *)digest;

// Password hashes
+ (nullable NppPasswordHashResult *)hashPassword:(NSData *)password salt:(NSData *)salt
                                        settings:(NppPasswordHashSettings *)settings;
/// Whether `password` is what `encoded` was made from. Any of the forms hashPassword: writes:
/// $2a$/$2b$/$2y$, $argon2id$/$argon2i$/$argon2d$, $scrypt$ln=..., $pbkdf2-sha256$...
/// nil when the string is none of them.
+ (nullable NSNumber *)password:(NSData *)password matches:(NSString *)encoded;
/// The bytes of salt a kind takes by custom: 16, which bcrypt requires.
+ (NSUInteger)saltLengthForKind:(NppPasswordHash)kind;

// Base encodings
+ (NSString *)encode:(NSData *)data as:(NppBaseEncoding)encoding;
/// nil when the text is not that encoding (or a Base58Check checksum does not hold).
+ (nullable NSData *)decode:(NSString *)text as:(NppBaseEncoding)encoding;

// Passwords
/// `length` characters drawn evenly from the sets put together. With `requireEach`, at least one
/// from every set (when there is room). `random` answers a number below its argument; nil for the
/// system's generator. nil when there is nothing to draw from.
+ (nullable NSString *)passwordOfLength:(NSUInteger)length fromSets:(NSArray<NSString *> *)sets
                            requireEach:(BOOL)requireEach random:(nullable uint32_t (^)(uint32_t below))random;
/// Characters easily taken for one another - O and 0, l and 1 and I and | - removed from a set.
+ (NSString *)withoutLookalikes:(NSString *)set;
/// The bits of entropy in a password of that length over that many characters.
+ (double)entropyOfLength:(NSUInteger)length alphabetSize:(NSUInteger)size;

@end

NS_ASSUME_NONNULL_END
