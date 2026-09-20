#import "CryptoTools.h"
#import "BlowfishTables.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <zlib.h>
#include <vector>
#include <string>
#include "argon2.h"
extern "C" {
#include "blake2/blake2.h"
}

#pragma mark - Settings

@implementation NppPasswordHashSettings

+ (instancetype)defaultsForKind:(NppPasswordHash)kind {
    NppPasswordHashSettings *s = [[NppPasswordHashSettings alloc] init];
    s.kind = kind;
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _bcryptCost = 12; _bcryptVersion = @"2b";
        _scryptLogN = 15; _scryptR = 8; _scryptP = 1;                  // what the scrypt paper calls interactive, doubled since
        _argon2Variant = NppArgon2id; _argon2Memory = 19456; _argon2Passes = 2; _argon2Lanes = 1;  // OWASP's minimum
        _pbkdf2Digest = @"SHA-256"; _pbkdf2Rounds = 600000;
        _keyLength = 32;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NppPasswordHashSettings *s = [[NppPasswordHashSettings alloc] init];
    s.kind = _kind; s.bcryptCost = _bcryptCost; s.bcryptVersion = _bcryptVersion;
    s.scryptLogN = _scryptLogN; s.scryptR = _scryptR; s.scryptP = _scryptP;
    s.argon2Variant = _argon2Variant; s.argon2Memory = _argon2Memory;
    s.argon2Passes = _argon2Passes; s.argon2Lanes = _argon2Lanes;
    s.pbkdf2Digest = _pbkdf2Digest; s.pbkdf2Rounds = _pbkdf2Rounds; s.keyLength = _keyLength;
    return s;
}

- (NSString *)problem {
    switch (_kind) {
        case NppPasswordHashBcrypt:
            if (_bcryptCost < 4 || _bcryptCost > 31) return @"The cost must be between 4 and 31.";
            if (![@[@"2a", @"2b", @"2y"] containsObject:_bcryptVersion ?: @""]) return @"The version must be 2a, 2b or 2y.";
            return nil;
        case NppPasswordHashScrypt:
            if (_scryptLogN < 1 || _scryptLogN > 24) return @"N must be between 2^1 and 2^24.";
            if (_scryptR < 1 || _scryptR > 64 || _scryptP < 1 || _scryptP > 64) return @"r and p must be between 1 and 64.";
            // 128 * r bytes for each of N blocks; past 2 GB the machine is better spent otherwise.
            if (((uint64_t)128 * (uint64_t)_scryptR) << _scryptLogN > ((uint64_t)2 << 30)) return @"These settings need more than 2 GB of memory.";
            break;
        case NppPasswordHashArgon2:
            if (_argon2Lanes < 1 || _argon2Lanes > 64) return @"The parallelism must be between 1 and 64.";
            if (_argon2Passes < 1 || _argon2Passes > 1000) return @"The iterations must be between 1 and 1000.";
            if (_argon2Memory < 8 * _argon2Lanes) return @"The memory must be at least 8 KiB for each lane.";
            if (_argon2Memory > 4 * 1024 * 1024) return @"These settings need more than 4 GB of memory.";
            break;
        case NppPasswordHashPBKDF2:
            if (![@[@"SHA-1", @"SHA-256", @"SHA-512"] containsObject:_pbkdf2Digest ?: @""]) return @"The digest must be SHA-1, SHA-256 or SHA-512.";
            if (_pbkdf2Rounds < 1 || _pbkdf2Rounds > 100000000) return @"The iterations must be between 1 and 100000000.";
            break;
    }
    if (_keyLength < 4 || _keyLength > 1024) return @"The hash length must be between 4 and 1024 bytes.";
    return nil;
}

@end

@implementation NppPasswordHashResult
@end

#pragma mark - Blowfish, as bcrypt drives it

namespace {

struct Blowfish {
    uint32_t P[18];
    uint32_t S[4][256];

    Blowfish() { memcpy(P, kBlowfishP, sizeof P); memcpy(S, kBlowfishS, sizeof S); }

    inline uint32_t f(uint32_t x) const {
        return ((S[0][x >> 24] + S[1][(x >> 16) & 0xff]) ^ S[2][(x >> 8) & 0xff]) + S[3][x & 0xff];
    }

    void encipher(uint32_t &left, uint32_t &right) const {
        uint32_t l = left ^ P[0], r = right;
        for (int i = 1; i <= 16; i += 2) {
            r ^= f(l) ^ P[i];
            l ^= f(r) ^ P[i + 1];
        }
        left = r ^ P[17];
        right = l;
    }

    /// The next four bytes of `data`, going round and round it.
    static uint32_t word(const uint8_t *data, size_t length, size_t &at) {
        uint32_t w = 0;
        for (int i = 0; i < 4; ++i) { w = (w << 8) | data[at]; at = (at + 1) % length; }
        return w;
    }

    void expand(const uint8_t *key, size_t keyLength) {
        size_t at = 0;
        for (int i = 0; i < 18; ++i) P[i] ^= word(key, keyLength, at);
        uint32_t l = 0, r = 0;
        for (int i = 0; i < 18; i += 2) { encipher(l, r); P[i] = l; P[i + 1] = r; }
        for (int box = 0; box < 4; ++box)
            for (int i = 0; i < 256; i += 2) { encipher(l, r); S[box][i] = l; S[box][i + 1] = r; }
    }

    void expand(const uint8_t *salt, size_t saltLength, const uint8_t *key, size_t keyLength) {
        size_t at = 0;
        for (int i = 0; i < 18; ++i) P[i] ^= word(key, keyLength, at);
        at = 0;
        uint32_t l = 0, r = 0;
        for (int i = 0; i < 18; i += 2) {
            l ^= word(salt, saltLength, at); r ^= word(salt, saltLength, at);
            encipher(l, r); P[i] = l; P[i + 1] = r;
        }
        for (int box = 0; box < 4; ++box)
            for (int i = 0; i < 256; i += 2) {
                l ^= word(salt, saltLength, at); r ^= word(salt, saltLength, at);
                encipher(l, r); S[box][i] = l; S[box][i + 1] = r;
            }
    }
};

// bcrypt has a Base64 of its own: another alphabet, and no padding.
const char kBcryptAlphabet[] = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
const char kBase64Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string Radix64(const uint8_t *data, size_t length, const char *alphabet) {
    std::string out;
    for (size_t i = 0; i < length; i += 3) {
        uint32_t chunk = (uint32_t)data[i] << 16;
        if (i + 1 < length) chunk |= (uint32_t)data[i + 1] << 8;
        if (i + 2 < length) chunk |= data[i + 2];
        out += alphabet[(chunk >> 18) & 63];
        out += alphabet[(chunk >> 12) & 63];
        if (i + 1 < length) out += alphabet[(chunk >> 6) & 63];
        if (i + 2 < length) out += alphabet[chunk & 63];
    }
    return out;
}

bool Unradix64(NSString *text, const char *alphabet, std::vector<uint8_t> &out) {
    uint32_t held = 0; int bits = 0;
    for (NSUInteger i = 0; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        const char *found = (c < 128 && c) ? strchr(alphabet, (char)c) : NULL;
        if (!found) return false;
        held = (held << 6) | (uint32_t)(found - alphabet); bits += 6;
        if (bits >= 8) { bits -= 8; out.push_back((uint8_t)(held >> bits)); held &= (1u << bits) - 1; }
    }
    return true;
}

/// The 23 bytes bcrypt keeps of its 24.
void BcryptRaw(const uint8_t *key, size_t keyLength, const uint8_t salt[16], int cost, uint8_t out[24]) {
    Blowfish state;
    state.expand(salt, 16, key, keyLength);
    for (uint64_t round = 0, rounds = (uint64_t)1 << cost; round < rounds; ++round) {
        state.expand(key, keyLength);
        state.expand(salt, 16);
    }
    uint32_t text[6];
    const uint8_t *magic = (const uint8_t *)"OrpheanBeholderScryDoubt";
    size_t at = 0;
    for (int i = 0; i < 6; ++i) text[i] = Blowfish::word(magic, 24, at);
    for (int pass = 0; pass < 64; ++pass)
        for (int i = 0; i < 6; i += 2) state.encipher(text[i], text[i + 1]);
    for (int i = 0; i < 6; ++i) {
        out[4 * i] = (uint8_t)(text[i] >> 24); out[4 * i + 1] = (uint8_t)(text[i] >> 16);
        out[4 * i + 2] = (uint8_t)(text[i] >> 8); out[4 * i + 3] = (uint8_t)text[i];
    }
}

#pragma mark - scrypt (RFC 7914) over CommonCrypto's PBKDF2

inline uint32_t Rotl(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }

void Salsa20_8(uint32_t B[16]) {
    uint32_t x[16];
    memcpy(x, B, sizeof x);
    for (int i = 0; i < 8; i += 2) {
#define QUARTER(a, b, c, d) x[b] ^= Rotl(x[a] + x[d], 7); x[c] ^= Rotl(x[b] + x[a], 9); \
                            x[d] ^= Rotl(x[c] + x[b], 13); x[a] ^= Rotl(x[d] + x[c], 18);
        QUARTER(0, 4, 8, 12)  QUARTER(5, 9, 13, 1)  QUARTER(10, 14, 2, 6)  QUARTER(15, 3, 7, 11)
        QUARTER(0, 1, 2, 3)   QUARTER(5, 6, 7, 4)   QUARTER(10, 11, 8, 9)  QUARTER(15, 12, 13, 14)
#undef QUARTER
    }
    for (int i = 0; i < 16; ++i) B[i] += x[i];
}

// Blocks are kept as little-endian words, which is what every Mac is, so the
// bytes PBKDF2 hands over are used as they lie.
void BlockMix(uint32_t *B, uint32_t *Y, size_t r) {
    uint32_t X[16];
    memcpy(X, &B[(2 * r - 1) * 16], sizeof X);
    for (size_t i = 0; i < 2 * r; ++i) {
        for (int k = 0; k < 16; ++k) X[k] ^= B[i * 16 + k];
        Salsa20_8(X);
        // Even blocks to the first half, odd ones to the second.
        memcpy(&Y[((i & 1) ? r + i / 2 : i / 2) * 16], X, sizeof X);
    }
    memcpy(B, Y, 2 * r * 16 * sizeof(uint32_t));
}

bool ROMix(uint32_t *B, size_t r, uint64_t N) {
    size_t words = 2 * r * 16;
    std::vector<uint32_t> V, Y(words);
    try { V.resize((size_t)N * words); } catch (...) { return false; }
    for (uint64_t i = 0; i < N; ++i) {
        memcpy(&V[(size_t)i * words], B, words * sizeof(uint32_t));
        BlockMix(B, Y.data(), r);
    }
    for (uint64_t i = 0; i < N; ++i) {
        uint64_t j = (((uint64_t)B[(2 * r - 1) * 16 + 1] << 32) | B[(2 * r - 1) * 16]) & (N - 1);
        const uint32_t *Vj = &V[(size_t)j * words];
        for (size_t k = 0; k < words; ++k) B[k] ^= Vj[k];
        BlockMix(B, Y.data(), r);
    }
    return true;
}

NSData *PBKDF2(NSData *password, NSData *salt, CCPseudoRandomAlgorithm prf, uint32_t rounds, size_t length) {
    NSMutableData *out = [NSMutableData dataWithLength:length];
    // CommonCrypto will not take a NULL password, and an empty one is as good a password as any.
    const char *bytes = password.length ? (const char *)password.bytes : "";
    int status = CCKeyDerivationPBKDF(kCCPBKDF2, bytes, password.length, (const uint8_t *)salt.bytes, salt.length,
                                      prf, rounds, (uint8_t *)out.mutableBytes, length);
    return status == kCCSuccess ? out : nil;
}

NSData *Scrypt(NSData *password, NSData *salt, int logN, size_t r, size_t p, size_t length) {
    size_t blockBytes = 128 * r;
    NSMutableData *B = [PBKDF2(password, salt, kCCPRFHmacAlgSHA256, 1, p * blockBytes) mutableCopy];
    if (!B) return nil;
    for (size_t lane = 0; lane < p; ++lane)
        if (!ROMix((uint32_t *)((uint8_t *)B.mutableBytes + lane * blockBytes), r, (uint64_t)1 << logN)) return nil;
    return PBKDF2(password, B, kCCPRFHmacAlgSHA256, 1, length);
}

#pragma mark - Keccak

void KeccakF(uint64_t A[25]) {
    static const uint64_t roundConstants[24] = {
        0x0000000000000001ULL, 0x0000000000008082ULL, 0x800000000000808aULL, 0x8000000080008000ULL,
        0x000000000000808bULL, 0x0000000080000001ULL, 0x8000000080008081ULL, 0x8000000000008009ULL,
        0x000000000000008aULL, 0x0000000000000088ULL, 0x0000000080008009ULL, 0x000000008000000aULL,
        0x000000008000808bULL, 0x800000000000008bULL, 0x8000000000008089ULL, 0x8000000000008003ULL,
        0x8000000000008002ULL, 0x8000000000000080ULL, 0x000000000000800aULL, 0x800000008000000aULL,
        0x8000000080008081ULL, 0x8000000000008080ULL, 0x0000000080000001ULL, 0x8000000080008008ULL};
    static const int rotations[24] = {1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44};
    static const int lanes[24] = {10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1};
    for (int round = 0; round < 24; ++round) {
        uint64_t C[5];
        for (int x = 0; x < 5; ++x) C[x] = A[x] ^ A[x + 5] ^ A[x + 10] ^ A[x + 15] ^ A[x + 20];
        for (int x = 0; x < 5; ++x) {
            uint64_t D = C[(x + 4) % 5] ^ ((C[(x + 1) % 5] << 1) | (C[(x + 1) % 5] >> 63));
            for (int y = 0; y < 25; y += 5) A[y + x] ^= D;
        }
        uint64_t carried = A[1];
        for (int i = 0; i < 24; ++i) {
            uint64_t next = A[lanes[i]];
            A[lanes[i]] = (carried << rotations[i]) | (carried >> (64 - rotations[i]));
            carried = next;
        }
        for (int y = 0; y < 25; y += 5) {
            uint64_t row[5];
            for (int x = 0; x < 5; ++x) row[x] = A[y + x];
            for (int x = 0; x < 5; ++x) A[y + x] = row[x] ^ (~row[(x + 1) % 5] & row[(x + 2) % 5]);
        }
        A[0] ^= roundConstants[round];
    }
}

#pragma mark - Base58 and Base32

const char kBase58Alphabet[] = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const char kBase32Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

NSData *DoubleSHA256(const uint8_t *bytes, size_t length) {
    uint8_t first[CC_SHA256_DIGEST_LENGTH], second[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)length, first);
    CC_SHA256(first, sizeof first, second);
    return [NSData dataWithBytes:second length:sizeof second];
}

NSString *Base58(const uint8_t *bytes, size_t length) {
    size_t zeros = 0;
    while (zeros < length && bytes[zeros] == 0) ++zeros;
    // The number, in base 58, least significant digit first.
    std::vector<uint8_t> digits;
    for (size_t i = zeros; i < length; ++i) {
        uint32_t carry = bytes[i];
        for (size_t k = 0; k < digits.size(); ++k) {
            carry += (uint32_t)digits[k] << 8;
            digits[k] = (uint8_t)(carry % 58); carry /= 58;
        }
        while (carry) { digits.push_back((uint8_t)(carry % 58)); carry /= 58; }
    }
    std::string out(zeros, '1');
    for (size_t k = digits.size(); k-- > 0;) out += kBase58Alphabet[digits[k]];
    return [NSString stringWithUTF8String:out.c_str()];
}

bool Unbase58(NSString *text, std::vector<uint8_t> &out) {
    size_t zeros = 0;
    NSUInteger n = text.length;
    while (zeros < n && [text characterAtIndex:zeros] == '1') ++zeros;
    std::vector<uint8_t> bytes;                 // least significant first
    for (NSUInteger i = zeros; i < n; ++i) {
        unichar c = [text characterAtIndex:i];
        const char *found = (c < 128 && c) ? strchr(kBase58Alphabet, (char)c) : NULL;
        if (!found) return false;
        uint32_t carry = (uint32_t)(found - kBase58Alphabet);
        for (size_t k = 0; k < bytes.size(); ++k) {
            carry += (uint32_t)bytes[k] * 58;
            bytes[k] = (uint8_t)carry; carry >>= 8;
        }
        while (carry) { bytes.push_back((uint8_t)carry); carry >>= 8; }
    }
    out.assign(zeros, 0);
    out.insert(out.end(), bytes.rbegin(), bytes.rend());
    return true;
}

NSString *WithoutWhitespace(NSString *text) {
    return [[text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
            componentsJoinedByString:@""];
}

bool SameBytes(NSData *a, NSData *b) {
    if (a.length != b.length) return false;
    const uint8_t *x = (const uint8_t *)a.bytes, *y = (const uint8_t *)b.bytes;
    uint8_t difference = 0;                     // every byte looked at, whatever the first ones say
    for (NSUInteger i = 0; i < a.length; ++i) difference |= x[i] ^ y[i];
    return difference == 0;
}

}  // namespace

@implementation NppCrypto

#pragma mark - Bytes as text

+ (NSString *)hexOfData:(NSData *)data {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; ++i) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

+ (NSData *)dataFromHex:(NSString *)hex {
    NSMutableData *data = [NSMutableData data];
    int high = -1;
    NSUInteger n = hex.length;
    for (NSUInteger i = 0; i < n; ++i) {
        unichar c = [hex characterAtIndex:i];
        int value;
        if (c >= '0' && c <= '9') value = c - '0';
        else if (c >= 'a' && c <= 'f') value = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') value = c - 'A' + 10;
        else {
            // Between bytes only: spaces, commas, colons, dashes - never inside one.
            if (high >= 0) return nil;
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == ',' || c == ':' || c == '-' || c == ';') continue;
            return nil;
        }
        // "0x" before a byte, as a C array has it.
        if (high < 0 && value == 0 && i + 1 < n && ([hex characterAtIndex:i + 1] | 0x20) == 'x') { ++i; continue; }
        if (high < 0) high = value;
        else { uint8_t byte = (uint8_t)(high << 4 | value); [data appendBytes:&byte length:1]; high = -1; }
    }
    return high < 0 ? data : nil;
}

+ (NSData *)randomBytes:(NSUInteger)count {
    NSMutableData *data = [NSMutableData dataWithLength:count];
    if (count && SecRandomCopyBytes(kSecRandomDefault, count, data.mutableBytes) != errSecSuccess) {
        // The system's generator failing is not something to paper over with a weaker one.
        [NSException raise:NSInternalInconsistencyException format:@"SecRandomCopyBytes failed"];
    }
    return data;
}

#pragma mark - Digests

+ (NSData *)sha3OfData:(NSData *)data bits:(NSInteger)bits {
    size_t outLength = (size_t)bits / 8, rate = 200 - 2 * outLength;
    uint64_t A[25] = {0};
    uint8_t *state = (uint8_t *)A;
    const uint8_t *in = (const uint8_t *)data.bytes;
    size_t left = data.length;
    while (left >= rate) {
        for (size_t i = 0; i < rate; ++i) state[i] ^= in[i];
        KeccakF(A); in += rate; left -= rate;
    }
    for (size_t i = 0; i < left; ++i) state[i] ^= in[i];
    state[left] ^= 0x06;
    state[rate - 1] ^= 0x80;
    KeccakF(A);
    return [NSData dataWithBytes:state length:outLength];
}

+ (NSData *)blake2bOfData:(NSData *)data {
    uint8_t out[64];
    blake2b(out, sizeof out, data.bytes, data.length, NULL, 0);
    return [NSData dataWithBytes:out length:sizeof out];
}

+ (uint32_t)crc32OfData:(NSData *)data {
    uLong crc = crc32(0L, Z_NULL, 0);
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger left = data.length;
    while (left) {                                  // zlib counts in 32 bits
        uInt piece = (uInt)MIN(left, (NSUInteger)1 << 30);
        crc = crc32(crc, bytes, piece); bytes += piece; left -= piece;
    }
    return (uint32_t)crc;
}

+ (NSData *)hmacOfData:(NSData *)data key:(NSData *)key digest:(NSString *)digest {
    NSDictionary<NSString *, NSArray<NSNumber *> *> *known = @{
        @"MD5": @[@(kCCHmacAlgMD5), @(CC_MD5_DIGEST_LENGTH)], @"SHA-1": @[@(kCCHmacAlgSHA1), @(CC_SHA1_DIGEST_LENGTH)],
        @"SHA-224": @[@(kCCHmacAlgSHA224), @(CC_SHA224_DIGEST_LENGTH)], @"SHA-256": @[@(kCCHmacAlgSHA256), @(CC_SHA256_DIGEST_LENGTH)],
        @"SHA-384": @[@(kCCHmacAlgSHA384), @(CC_SHA384_DIGEST_LENGTH)], @"SHA-512": @[@(kCCHmacAlgSHA512), @(CC_SHA512_DIGEST_LENGTH)]};
    NSArray<NSNumber *> *one = known[digest];
    if (!one) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:one[1].unsignedIntegerValue];
    CCHmac((CCHmacAlgorithm)one[0].unsignedIntValue, key.bytes, key.length, data.bytes, data.length, out.mutableBytes);
    return out;
}

#pragma mark - Password hashes

+ (NSUInteger)saltLengthForKind:(NppPasswordHash)kind { return 16; }

static NSString *Unpadded64(NSData *data, BOOL adapted) {
    NSString *text = [NSString stringWithUTF8String:
        Radix64((const uint8_t *)data.bytes, data.length, kBase64Alphabet).c_str()];
    return adapted ? [text stringByReplacingOccurrencesOfString:@"+" withString:@"."] : text;
}

static NSData *FromUnpadded64(NSString *text) {
    std::vector<uint8_t> bytes;
    if (!Unradix64([text stringByReplacingOccurrencesOfString:@"." withString:@"+"], kBase64Alphabet, bytes)) return nil;
    return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

+ (NppPasswordHashResult *)hashPassword:(NSData *)password salt:(NSData *)salt
                               settings:(NppPasswordHashSettings *)settings {
    if (!password || !salt || [settings problem]) return nil;
    NppPasswordHashResult *result = [[NppPasswordHashResult alloc] init];
    switch (settings.kind) {
        case NppPasswordHashBcrypt: {
            if (salt.length != 16) return nil;
            // The key is the password and the zero that ends it, and no more than 72 bytes of that.
            NSMutableData *key = [password mutableCopy];
            [key appendBytes:"" length:1];
            if (key.length > 72) key.length = 72;
            uint8_t raw[24];
            BcryptRaw((const uint8_t *)key.bytes, key.length, (const uint8_t *)salt.bytes, (int)settings.bcryptCost, raw);
            result.key = [NSData dataWithBytes:raw length:23];
            result.encoded = [NSString stringWithFormat:@"$%@$%02d$%s%s", settings.bcryptVersion, (int)settings.bcryptCost,
                              Radix64((const uint8_t *)salt.bytes, 16, kBcryptAlphabet).c_str(),
                              Radix64(raw, 23, kBcryptAlphabet).c_str()];
            return result;
        }
        case NppPasswordHashScrypt: {
            NSData *key = Scrypt(password, salt, (int)settings.scryptLogN, (size_t)settings.scryptR,
                                 (size_t)settings.scryptP, (size_t)settings.keyLength);
            if (!key) return nil;
            result.key = key;
            result.encoded = [NSString stringWithFormat:@"$scrypt$ln=%d,r=%d,p=%d$%@$%@", (int)settings.scryptLogN,
                              (int)settings.scryptR, (int)settings.scryptP, Unpadded64(salt, NO), Unpadded64(key, NO)];
            return result;
        }
        case NppPasswordHashArgon2: {
            if (salt.length < 8) return nil;
            argon2_type type = settings.argon2Variant == NppArgon2i ? Argon2_i
                             : settings.argon2Variant == NppArgon2d ? Argon2_d : Argon2_id;
            size_t encodedLength = argon2_encodedlen((uint32_t)settings.argon2Passes, (uint32_t)settings.argon2Memory,
                                                     (uint32_t)settings.argon2Lanes, (uint32_t)salt.length,
                                                     (uint32_t)settings.keyLength, type);
            NSMutableData *key = [NSMutableData dataWithLength:(NSUInteger)settings.keyLength];
            std::vector<char> encoded(encodedLength + 1);
            int status = argon2_hash((uint32_t)settings.argon2Passes, (uint32_t)settings.argon2Memory,
                                     (uint32_t)settings.argon2Lanes, password.bytes, password.length,
                                     salt.bytes, salt.length, key.mutableBytes, key.length,
                                     encoded.data(), encoded.size(), type, ARGON2_VERSION_13);
            if (status != ARGON2_OK) return nil;
            result.key = key;
            result.encoded = [NSString stringWithUTF8String:encoded.data()];
            return result;
        }
        case NppPasswordHashPBKDF2: {
            BOOL sha1 = [settings.pbkdf2Digest isEqualToString:@"SHA-1"], sha512 = [settings.pbkdf2Digest isEqualToString:@"SHA-512"];
            NSData *key = PBKDF2(password, salt, sha1 ? kCCPRFHmacAlgSHA1 : sha512 ? kCCPRFHmacAlgSHA512 : kCCPRFHmacAlgSHA256,
                                 (uint32_t)settings.pbkdf2Rounds, (size_t)settings.keyLength);
            if (!key) return nil;
            result.key = key;
            // As passlib writes it, which is what most things that read such a string expect.
            result.encoded = [NSString stringWithFormat:@"$pbkdf2%@$%d$%@$%@", sha1 ? @"" : sha512 ? @"-sha512" : @"-sha256",
                              (int)settings.pbkdf2Rounds, Unpadded64(salt, YES), Unpadded64(key, YES)];
            return result;
        }
    }
    return nil;
}

+ (NSNumber *)password:(NSData *)password matches:(NSString *)encoded {
    encoded = [encoded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *parts = [encoded componentsSeparatedByString:@"$"];
    if (parts.count < 4 || parts[0].length) return nil;
    NSString *scheme = parts[1];
    NppPasswordHashSettings *settings = [[NppPasswordHashSettings alloc] init];
    NSData *salt = nil, *expected = nil;

    if ([@[@"2a", @"2b", @"2y"] containsObject:scheme]) {
        if (parts.count != 4 || parts[3].length != 53) return nil;
        settings.kind = NppPasswordHashBcrypt;
        settings.bcryptVersion = scheme;
        settings.bcryptCost = parts[2].integerValue;
        std::vector<uint8_t> saltBytes;
        if (!Unradix64([parts[3] substringToIndex:22], kBcryptAlphabet, saltBytes) || saltBytes.size() < 16) return nil;
        salt = [NSData dataWithBytes:saltBytes.data() length:16];
        NppPasswordHashResult *made = [self hashPassword:password salt:salt settings:settings];
        if (!made) return nil;
        // Compared as the bytes both stand for: the last character of a salt has bits to spare.
        std::vector<uint8_t> theirs;
        if (!Unradix64([parts[3] substringFromIndex:22], kBcryptAlphabet, theirs) || theirs.size() < 23) return nil;
        return @(SameBytes(made.key, [NSData dataWithBytes:theirs.data() length:23]));
    }
    if ([scheme hasPrefix:@"argon2"]) {
        argon2_type type = [scheme isEqualToString:@"argon2i"] ? Argon2_i : [scheme isEqualToString:@"argon2d"] ? Argon2_d : Argon2_id;
        if (![@[@"argon2i", @"argon2d", @"argon2id"] containsObject:scheme]) return nil;
        int status = argon2_verify(encoded.UTF8String, password.bytes, password.length, type);
        if (status == ARGON2_OK) return @YES;
        return status == ARGON2_VERIFY_MISMATCH ? @NO : nil;
    }
    if ([scheme isEqualToString:@"scrypt"]) {
        if (parts.count != 5) return nil;
        settings.kind = NppPasswordHashScrypt;
        for (NSString *pair in [parts[2] componentsSeparatedByString:@","]) {
            NSArray<NSString *> *sides = [pair componentsSeparatedByString:@"="];
            if (sides.count != 2) return nil;
            if ([sides[0] isEqualToString:@"ln"]) settings.scryptLogN = sides[1].integerValue;
            else if ([sides[0] isEqualToString:@"r"]) settings.scryptR = sides[1].integerValue;
            else if ([sides[0] isEqualToString:@"p"]) settings.scryptP = sides[1].integerValue;
        }
        salt = FromUnpadded64(parts[3]); expected = FromUnpadded64(parts[4]);
    } else if ([scheme hasPrefix:@"pbkdf2"]) {
        if (parts.count != 5) return nil;
        settings.kind = NppPasswordHashPBKDF2;
        settings.pbkdf2Digest = [scheme isEqualToString:@"pbkdf2"] ? @"SHA-1"
                              : [scheme isEqualToString:@"pbkdf2-sha512"] ? @"SHA-512" : @"SHA-256";
        if (![@[@"pbkdf2", @"pbkdf2-sha256", @"pbkdf2-sha512"] containsObject:scheme]) return nil;
        settings.pbkdf2Rounds = parts[2].integerValue;
        salt = FromUnpadded64(parts[3]); expected = FromUnpadded64(parts[4]);
    } else {
        return nil;
    }
    if (!salt || !expected.length) return nil;
    settings.keyLength = (NSInteger)expected.length;
    NppPasswordHashResult *made = [self hashPassword:password salt:salt settings:settings];
    return made ? @(SameBytes(made.key, expected)) : nil;
}

#pragma mark - Base encodings

+ (NSString *)encode:(NSData *)data as:(NppBaseEncoding)encoding {
    switch (encoding) {
        case NppBase64: return [data base64EncodedStringWithOptions:0];
        case NppBase64URL: {
            NSString *text = [data base64EncodedStringWithOptions:0];
            text = [text stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
            return [text stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        }
        case NppBase58: return Base58((const uint8_t *)data.bytes, data.length);
        case NppBase58Check: {
            NSMutableData *checked = [data mutableCopy];
            [checked appendData:[DoubleSHA256((const uint8_t *)data.bytes, data.length) subdataWithRange:NSMakeRange(0, 4)]];
            return Base58((const uint8_t *)checked.bytes, checked.length);
        }
        case NppBase32: {
            const uint8_t *bytes = (const uint8_t *)data.bytes;
            NSMutableString *out = [NSMutableString string];
            uint32_t held = 0; int bits = 0;
            for (NSUInteger i = 0; i < data.length; ++i) {
                held = (held << 8) | bytes[i]; bits += 8;
                while (bits >= 5) { bits -= 5; [out appendFormat:@"%c", kBase32Alphabet[(held >> bits) & 31]]; }
                held &= (1u << bits) - 1;
            }
            if (bits) [out appendFormat:@"%c", kBase32Alphabet[(held << (5 - bits)) & 31]];
            while (out.length % 8) [out appendString:@"="];
            return out;
        }
    }
    return @"";
}

+ (NSData *)decode:(NSString *)text as:(NppBaseEncoding)encoding {
    text = WithoutWhitespace(text ?: @"");
    switch (encoding) {
        case NppBase64:
        case NppBase64URL: {
            // Either alphabet is read under either name, and padding may be left off: what is
            // pasted in is seldom as tidy as what is written out.
            NSString *plain = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                               stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
            while (plain.length && [plain hasSuffix:@"="]) plain = [plain substringToIndex:plain.length - 1];
            if (plain.length % 4 == 1) return nil;
            std::vector<uint8_t> bytes;
            if (!Unradix64(plain, kBase64Alphabet, bytes)) return nil;
            return [NSData dataWithBytes:bytes.data() length:bytes.size()];
        }
        case NppBase58:
        case NppBase58Check: {
            std::vector<uint8_t> bytes;
            if (!Unbase58(text, bytes)) return nil;
            if (encoding == NppBase58) return [NSData dataWithBytes:bytes.data() length:bytes.size()];
            if (bytes.size() < 4) return nil;
            NSData *payload = [NSData dataWithBytes:bytes.data() length:bytes.size() - 4];
            NSData *sum = [DoubleSHA256(bytes.data(), bytes.size() - 4) subdataWithRange:NSMakeRange(0, 4)];
            if (!SameBytes(sum, [NSData dataWithBytes:bytes.data() + bytes.size() - 4 length:4])) return nil;
            return payload;
        }
        case NppBase32: {
            NSString *plain = text.uppercaseString;
            while (plain.length && [plain hasSuffix:@"="]) plain = [plain substringToIndex:plain.length - 1];
            NSMutableData *out = [NSMutableData data];
            uint32_t held = 0; int bits = 0;
            for (NSUInteger i = 0; i < plain.length; ++i) {
                unichar c = [plain characterAtIndex:i];
                const char *found = (c < 128 && c) ? strchr(kBase32Alphabet, (char)c) : NULL;
                if (!found) return nil;
                held = (held << 5) | (uint32_t)(found - kBase32Alphabet); bits += 5;
                if (bits >= 8) { bits -= 8; uint8_t byte = (uint8_t)(held >> bits); [out appendBytes:&byte length:1]; held &= (1u << bits) - 1; }
            }
            return out;
        }
    }
    return nil;
}

#pragma mark - Passwords

static NSArray<NSString *> *CharactersOf(NSString *set) {
    // As the reader sees them: an emoji or an accented letter is one character to choose, not two.
    NSMutableArray<NSString *> *characters = [NSMutableArray array];
    [set enumerateSubstringsInRange:NSMakeRange(0, set.length) options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *piece, NSRange, NSRange, BOOL *) {
        if (piece && ![characters containsObject:piece]) [characters addObject:piece];
    }];
    return characters;
}

+ (NSString *)passwordOfLength:(NSUInteger)length fromSets:(NSArray<NSString *> *)sets
                   requireEach:(BOOL)requireEach random:(uint32_t (^)(uint32_t))random {
    if (!random) {
        random = ^uint32_t(uint32_t below) {
            if (below < 2) return 0;
            // Numbers past the last whole multiple are thrown away: taking them modulo
            // would make the first characters of the alphabet a little likelier than the rest.
            uint32_t limit = UINT32_MAX - (UINT32_MAX % below), value;
            do { [[NppCrypto randomBytes:sizeof value] getBytes:&value length:sizeof value]; } while (value >= limit);
            return value % below;
        };
    }
    NSMutableArray<NSArray<NSString *> *> *usable = [NSMutableArray array];
    NSMutableArray<NSString *> *all = [NSMutableArray array];
    for (NSString *set in sets) {
        NSMutableArray<NSString *> *fresh = [NSMutableArray array];
        for (NSString *character in CharactersOf(set))
            if (![all containsObject:character]) { [fresh addObject:character]; [all addObject:character]; }
        if (fresh.count) [usable addObject:fresh];
    }
    if (!all.count || !length) return nil;

    NSMutableArray<NSString *> *chosen = [NSMutableArray arrayWithCapacity:length];
    if (requireEach && usable.count <= length)
        for (NSArray<NSString *> *set in usable) [chosen addObject:set[random((uint32_t)set.count)]];
    while (chosen.count < length) [chosen addObject:all[random((uint32_t)all.count)]];
    // Shuffled, so that the ones put in first to satisfy each set are not always at the front.
    for (NSUInteger i = chosen.count - 1; i > 0; --i)
        [chosen exchangeObjectAtIndex:i withObjectAtIndex:random((uint32_t)i + 1)];
    return [chosen componentsJoinedByString:@""];
}

+ (NSString *)withoutLookalikes:(NSString *)set {
    NSCharacterSet *alike = [NSCharacterSet characterSetWithCharactersInString:@"O0oIl1|`'"];
    return [[set componentsSeparatedByCharactersInSet:alike] componentsJoinedByString:@""];
}

+ (double)entropyOfLength:(NSUInteger)length alphabetSize:(NSUInteger)size {
    return size > 1 ? (double)length * log2((double)size) : 0;
}

@end
