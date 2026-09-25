// The built-in suite, the Tools menu (hashes, encodings, passwords, HTTP), Macro, Window, Run and Help, and the Mac extras.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Tools: hashes ==; == Tools: the digests the port adds ==; == Tools: password hashes ==; == Tools: Base64, Base58, Base32 and bytes in hexadecimal ==; == Tools: passwords ==; == Tools: the menu and its windows ==
void NppTestsToolsMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Tools: hashes")) { printf("\n== Tools: hashes ==\n");
        // Reference values for "abc" from the published test vectors.
        struct { NppDigest d; NSString *want; NSString *gen; NSString *files; NSString *clip; } hashes[] = {
            {NppDigestMD5,    @"900150983cd24fb0d6963f7d28e17f72",
             @"IDM_TOOL_MD5_GENERATE", @"IDM_TOOL_MD5_GENERATEFROMFILE", @"IDM_TOOL_MD5_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA1,   @"a9993e364706816aba3e25717850c26c9cd0d89d",
             @"IDM_TOOL_SHA1_GENERATE", @"IDM_TOOL_SHA1_GENERATEFROMFILE", @"IDM_TOOL_SHA1_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA256, @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
             @"IDM_TOOL_SHA256_GENERATE", @"IDM_TOOL_SHA256_GENERATEFROMFILE", @"IDM_TOOL_SHA256_GENERATEINTOCLIPBOARD"},
            {NppDigestSHA512, @"ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                               "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
             @"IDM_TOOL_SHA512_GENERATE", @"IDM_TOOL_SHA512_GENERATEFROMFILE", @"IDM_TOOL_SHA512_GENERATEINTOCLIPBOARD"},
        };
        NSString *abcPath = TempFile(@"t_hash.txt", @"abc");
        for (size_t i = 0; i < sizeof(hashes)/sizeof(hashes[0]); ++i) {
            NSString *got = [EditorController hashOfData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]
                                                  digest:hashes[i].d];
            Check(hashes[i].gen, [NSString stringWithFormat:@"%@(\"abc\") matches the test vector",
                                  [EditorController nameOfDigest:hashes[i].d]],
                  [got isEqualToString:hashes[i].want]);

            NSString *fromFile = [ed hashOfFiles:@[abcPath] digest:hashes[i].d];
            Check(hashes[i].files, @"hashes a file's contents",
                  [fromFile hasPrefix:hashes[i].want] && [fromFile hasSuffix:abcPath]);

            SetDoc(ed, @"abc");
            [sci message:SCI_SETSEL wParam:0 lParam:3];
            [ed copyToClipboard:[ed hashOfSelection:hashes[i].d]];
            Check(hashes[i].clip, @"puts the selection hash on the clipboard",
                  [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString]
                      isEqualToString:hashes[i].want]);
        }

        // The selection's hash is of its bytes as they are: a NUL earlier in the document, or bytes
        // that are not UTF-8, change nothing about the selected "abc".
        void (^bytesInto)(const char *, size_t) = ^(const char *bytes, size_t length) {
            [sci message:SCI_CLEARALL];
            [sci message:SCI_APPENDTEXT wParam:length lParam:(sptr_t)bytes];
        };
        [ed newDocument];
        bytesInto("a\0babc", 6);
        [sci message:SCI_SETSEL wParam:3 lParam:6];
        NSString *afterNul = [ed hashOfSelection:NppDigestMD5];
        bytesInto("\xFF\xFE" "abc", 5);
        [sci message:SCI_SETSEL wParam:2 lParam:5];
        NSString *afterBinary = [ed hashOfSelection:NppDigestMD5];
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:ed.currentDocument] discardChanges:YES];
        Check(@"IDM_TOOL_MD5_GENERATEINTOCLIPBOARD (the bytes selected)", @"the hash of a selected abc is abc's after a NUL and after bytes that are not UTF-8",
              [afterNul isEqualToString:@"900150983cd24fb0d6963f7d28e17f72"] && [afterBinary isEqualToString:@"900150983cd24fb0d6963f7d28e17f72"]);
    }

    if (NppSectionWanted(@"Tools: the digests the port adds")) { printf("\n== Tools: the digests the port adds ==\n");
        NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
        struct { NppDigest d; NSString *want; } more[] = {
            {NppDigestSHA224,   @"23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"},
            {NppDigestSHA384,   @"cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
                                 "8086072ba1e7cc2358baeca134c825a7"},
            {NppDigestSHA3_256, @"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"},
            {NppDigestSHA3_512, @"b751850b1a57168a5693cd924b6b096e08f621827444f70d884f5d0240d2712e"
                                 "10e116e9192af3c91a7ec57647e3934057340b4cf408d5a56592f8274eec53f0"},
            {NppDigestBLAKE2b,  @"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
                                 "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"},
        };
        BOOL allRight = YES;
        for (size_t i = 0; i < sizeof(more)/sizeof(more[0]); ++i) {
            NSString *got = [EditorController hashOfData:abc digest:more[i].d];
            if (![got isEqualToString:more[i].want]) {
                allRight = NO;
                printf("    %s: %s\n", [EditorController nameOfDigest:more[i].d].UTF8String, got.UTF8String);
            }
        }
        Check(@"Tools > Hashes (SHA-224, SHA-384, SHA3-256, SHA3-512, BLAKE2b)",
              @"each gives the published digest of \"abc\"", allRight);

        // Two hundred bytes is more than one block of SHA3-256's 136, so the
        // absorbing loop is gone round, not only the padding.
        NSData *long3 = [[@"" stringByPaddingToLength:200 withString:@"a" startingAtIndex:0] dataUsingEncoding:NSUTF8StringEncoding];
        Check(@"Tools > Hashes (SHA-3 over more than a block)", @"a text longer than the sponge's rate is absorbed block by block",
              [[EditorController hashOfData:long3 digest:NppDigestSHA3_256]
                  isEqualToString:@"cce34485baf2bf2aca99b94833892a4f52896d3d153f7b840cc4f9fe695f1387"]);

        Check(@"Tools > Hashes (CRC-32)", @"the check value of \"123456789\" is cbf43926",
              [[EditorController hashOfData:[@"123456789" dataUsingEncoding:NSUTF8StringEncoding] digest:NppDigestCRC32]
                  isEqualToString:@"cbf43926"]);

        NSData *mac = [NppCrypto hmacOfData:[@"The quick brown fox jumps over the lazy dog" dataUsingEncoding:NSUTF8StringEncoding]
                                        key:[@"key" dataUsingEncoding:NSUTF8StringEncoding] digest:@"SHA-256"];
        Check(@"Tools > Hashes (HMAC)", @"HMAC-SHA-256 with a key gives the well-known value, and an unknown digest gives nothing",
              [[NppCrypto hexOfData:mac] isEqualToString:@"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"] &&
              [NppCrypto hmacOfData:abc key:abc digest:@"SHA-999"] == nil);

        // "Treat each line as a separate string", as upstream's dialog has it:
        // a digest per line, an empty line left empty, either kind of line end.
        NSString *md5abc = @"900150983cd24fb0d6963f7d28e17f72", *md5x = @"9dd4e461268c8034f5c8564e155c67a6";
        NSString *perLine = [EditorController hashOfText:@"abc\r\n\nx\n" eachLine:YES digest:NppDigestMD5];
        NSString *whole = [EditorController hashOfText:@"abc" eachLine:NO digest:NppDigestMD5];
        Check(@"Tools > Hashes (each line as a separate string)",
              @"one digest for each line, empty lines kept empty; unticked, one digest for all of it",
              [perLine isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", md5abc, md5x]] && [whole isEqualToString:md5abc]);
    }

    if (NppSectionWanted(@"Tools: password hashes")) { printf("\n== Tools: password hashes ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };

        // bcrypt, against the vectors of its reference implementations. The
        // salt is given here as it is written in the hash, and read back.
        struct { NSString *password, *version; int cost; NSString *want; } crypts[] = {
            {@"U*U", @"2a", 5, @"$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW"},
            {@"", @"2a", 6, @"$2a$06$DCq7YPn5Rq63x1Lad4cll.TV4S6ytwfsfvkgY8jIucDrjc8deX1s."},
            {@"пароль", @"2b", 6, @"$2b$06$abcdefghijklmnopqrstuu0RbYLPpyLm/x71XGmlHQAdqmD5AbL2G"},
        };
        BOOL bcryptRight = YES;
        for (size_t i = 0; i < sizeof(crypts)/sizeof(crypts[0]); ++i) {
            BOOL matches = [[NppCrypto password:utf8(crypts[i].password) matches:crypts[i].want] boolValue];
            BOOL refuses = ![[NppCrypto password:utf8([crypts[i].password stringByAppendingString:@"x"]) matches:crypts[i].want] boolValue];
            if (!matches || !refuses) { bcryptRight = NO; printf("    bcrypt vector %zu: matches %d refuses %d\n", i, matches, refuses); }
        }
        NppPasswordHashSettings *bcrypt = [NppPasswordHashSettings defaultsForKind:NppPasswordHashBcrypt];
        bcrypt.bcryptCost = 5; bcrypt.bcryptVersion = @"2y";
        NSData *salt16 = [NppCrypto dataFromHex:@"000102030405060708090a0b0c0d0e0f"];
        NppPasswordHashResult *made = [NppCrypto hashPassword:utf8(@"correct horse") salt:salt16 settings:bcrypt];
        Check(@"Tools > Hashes > bcrypt", @"the reference vectors verify (an empty password and a Cyrillic one among them), "
              @"a wrong password does not, and a hash made here is $2y$05$, 60 characters, and verifies",
              bcryptRight && [made.encoded hasPrefix:@"$2y$05$"] && made.encoded.length == 60 && made.key.length == 23 &&
              [[NppCrypto password:utf8(@"correct horse") matches:made.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"correct horsf") matches:made.encoded] boolValue]);

        // Past 72 bytes bcrypt reads no further: that is the algorithm, and what every other implementation does.
        NSString *long72 = [@"" stringByPaddingToLength:72 withString:@"0123456789" startingAtIndex:0];
        NppPasswordHashResult *a72 = [NppCrypto hashPassword:utf8(long72) salt:salt16 settings:bcrypt];
        NppPasswordHashResult *b72 = [NppCrypto hashPassword:utf8([long72 stringByAppendingString:@"tail"]) salt:salt16 settings:bcrypt];
        bcrypt.bcryptCost = 3;
        Check(@"Tools > Hashes > bcrypt (limits)", @"only the first 72 bytes count; a cost below 4 or a salt that is not 16 bytes is refused",
              [a72.encoded isEqualToString:b72.encoded] && [bcrypt problem] != nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:salt16 settings:bcrypt] == nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"short") settings:[NppPasswordHashSettings defaultsForKind:NppPasswordHashBcrypt]] == nil);

        // scrypt: two of RFC 7914's vectors, one with sixteen lanes and one with a large N.
        NppPasswordHashSettings *scrypt = [NppPasswordHashSettings defaultsForKind:NppPasswordHashScrypt];
        scrypt.scryptLogN = 10; scrypt.scryptR = 8; scrypt.scryptP = 16; scrypt.keyLength = 64;
        NppPasswordHashResult *s1 = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"NaCl") settings:scrypt];
        scrypt.scryptLogN = 14; scrypt.scryptP = 1; scrypt.keyLength = 32;
        NppPasswordHashResult *s2 = [NppCrypto hashPassword:utf8(@"pleaseletmein") salt:utf8(@"SodiumChloride") settings:scrypt];
        Check(@"Tools > Hashes > scrypt", @"RFC 7914's vectors come out, and the string written for one verifies against its password only",
              [[NppCrypto hexOfData:s1.key] isEqualToString:@"fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162"
                                                             "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"] &&
              [[NppCrypto hexOfData:s2.key] isEqualToString:@"7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2"] &&
              [s2.encoded hasPrefix:@"$scrypt$ln=14,r=8,p=1$U29kaXVtQ2hsb3JpZGU$"] &&
              [[NppCrypto password:utf8(@"pleaseletmein") matches:s2.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"pleaseletmeout") matches:s2.encoded] boolValue]);
        scrypt.scryptLogN = 24; scrypt.scryptR = 64;
        Check(@"Tools > Hashes > scrypt (limits)", @"settings that would need more than 2 GB are refused rather than tried",
              [scrypt problem] != nil && [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"saltsalt") settings:scrypt] == nil);

        // Argon2, all three variants, against the reference implementation's own output.
        struct { NppArgon2Variant v; NSString *want; } argons[] = {
            {NppArgon2id, @"$argon2id$v=19$m=64,t=2,p=2$c29tZXNhbHQ$lDh0Fd+4TtGXdGWh6GJgc630K9Turh+qHdTiOh/2hZ8"},
            {NppArgon2i,  @"$argon2i$v=19$m=64,t=2,p=2$c29tZXNhbHQ$u3EC2QpYDSqhwag4F/JKsYx8yBDM0sKg0MgMlK0pkWc"},
            {NppArgon2d,  @"$argon2d$v=19$m=64,t=2,p=2$c29tZXNhbHQ$1q8bgD0xYiK3sMCt/uIryr7jP0g04fs9QOITesC7M88"},
        };
        BOOL argonRight = YES;
        for (size_t i = 0; i < 3; ++i) {
            NppPasswordHashSettings *argon = [NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2];
            argon.argon2Variant = argons[i].v; argon.argon2Memory = 64; argon.argon2Passes = 2; argon.argon2Lanes = 2; argon.keyLength = 32;
            NppPasswordHashResult *got = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"somesalt") settings:argon];
            if (![got.encoded isEqualToString:argons[i].want] || got.key.length != 32 ||
                ![[NppCrypto password:utf8(@"password") matches:argons[i].want] boolValue] ||
                [[NppCrypto password:utf8(@"Password") matches:argons[i].want] boolValue]) {
                argonRight = NO; printf("    argon2 variant %zu: %s\n", i, got.encoded.UTF8String);
            }
        }
        NppPasswordHashSettings *thin = [NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2];
        thin.argon2Memory = 8; thin.argon2Lanes = 4;
        Check(@"Tools > Hashes > Argon2", @"argon2id, argon2i and argon2d give the reference implementation's strings and verify; "
              @"too little memory for the lanes, or a salt under 8 bytes, is refused",
              argonRight && [thin problem] != nil &&
              [NppCrypto hashPassword:utf8(@"x") salt:utf8(@"short") settings:[NppPasswordHashSettings defaultsForKind:NppPasswordHashArgon2]] == nil);

        NppPasswordHashSettings *pbkdf2 = [NppPasswordHashSettings defaultsForKind:NppPasswordHashPBKDF2];
        pbkdf2.pbkdf2Rounds = 4096; pbkdf2.keyLength = 32;
        NppPasswordHashResult *derived = [NppCrypto hashPassword:utf8(@"password") salt:utf8(@"salt") settings:pbkdf2];
        Check(@"Tools > Hashes > PBKDF2", @"PBKDF2-HMAC-SHA-256 of \"password\" and \"salt\" over 4096 rounds is the known key, and its string verifies",
              [[NppCrypto hexOfData:derived.key] isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"] &&
              [derived.encoded hasPrefix:@"$pbkdf2-sha256$4096$c2FsdA$"] &&
              [[NppCrypto password:utf8(@"password") matches:derived.encoded] boolValue] &&
              ![[NppCrypto password:utf8(@"passwor") matches:derived.encoded] boolValue]);

        Check(@"Tools > Hashes (what is not a hash)", @"a string of no known scheme is said to be none, rather than a mismatch",
              [NppCrypto password:utf8(@"x") matches:@"5f4dcc3b5aa765d61d8327deb882cf99"] == nil &&
              [NppCrypto password:utf8(@"x") matches:@"$9z$12$whatever"] == nil &&
              [NppCrypto password:utf8(@"x") matches:@"$2b$12$tooshort"] == nil);
    }

    if (NppSectionWanted(@"Tools: Base64, Base58, Base32 and bytes in hexadecimal")) { printf("\n== Tools: Base64, Base58, Base32 and bytes in hexadecimal ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
        NSData *(^hex)(NSString *) = ^NSData *(NSString *text) { return [NppCrypto dataFromHex:text]; };

        Check(@"Tools > Base (bytes written as hexadecimal)",
              @"plain, spaced, with 0x and commas, with colons, in either case; half a byte or a stray letter is refused",
              [hex(@"48656c6c6f") isEqualToData:utf8(@"Hello")] && [hex(@"48 65 6C 6c 6F") isEqualToData:utf8(@"Hello")] &&
              [hex(@"0x48, 0x65, 0X6c,0x6c ,0x6f") isEqualToData:utf8(@"Hello")] && [hex(@"48:65:6c:6c:6f\n") isEqualToData:utf8(@"Hello")] &&
              hex(@"").length == 0 && hex(@"") != nil && hex(@"486") == nil && hex(@"4 8") == nil && hex(@"48 6g") == nil &&
              [[NppCrypto hexOfData:utf8(@"Hello")] isEqualToString:@"48656c6c6f"]);

        Check(@"Tools > Base > Base64", @"a Cyrillic string there and back; the URL alphabet; unpadded and wrapped input is read; rubbish is not",
              [[NppCrypto encode:utf8(@"Привет") as:NppBase64] isEqualToString:@"0J/RgNC40LLQtdGC"] &&
              [[NppCrypto decode:@"0J/RgNC40LLQtdGC" as:NppBase64] isEqualToData:utf8(@"Привет")] &&
              [[NppCrypto encode:hex(@"fbff") as:NppBase64URL] isEqualToString:@"-_8="] &&
              [[NppCrypto encode:hex(@"fbff") as:NppBase64] isEqualToString:@"+/8="] &&
              [[NppCrypto decode:@"-_8" as:NppBase64] isEqualToData:hex(@"fbff")] &&
              [[NppCrypto decode:@"SGVs\r\nbG8=\n" as:NppBase64] isEqualToData:utf8(@"Hello")] &&
              [NppCrypto decode:@"SGVsbG8*" as:NppBase64] == nil && [NppCrypto decode:@"SGVsb" as:NppBase64] == nil);

        Check(@"Tools > Base > Base58", @"Bitcoin's alphabet: leading zero bytes become 1s and come back, a text goes there and back, "
              @"and the letters the alphabet leaves out (0, O, I, l) are refused",
              [[NppCrypto encode:utf8(@"Hello World!") as:NppBase58] isEqualToString:@"2NEpo7TZRRrLZSi2U"] &&
              [[NppCrypto decode:@"2NEpo7TZRRrLZSi2U" as:NppBase58] isEqualToData:utf8(@"Hello World!")] &&
              [[NppCrypto encode:hex(@"0000287fb4cd") as:NppBase58] isEqualToString:@"11233QC4"] &&
              [[NppCrypto decode:@"11233QC4" as:NppBase58] isEqualToData:hex(@"0000287fb4cd")] &&
              [[NppCrypto encode:[NSData data] as:NppBase58] isEqualToString:@""] &&
              [NppCrypto decode:@"2NEpo7TZRRrLZSi20" as:NppBase58] == nil && [NppCrypto decode:@"Il" as:NppBase58] == nil);

        Check(@"Tools > Base > Base58Check", @"a Bitcoin address is its version and hash with four bytes of checksum; one wrong character and it is refused",
              [[NppCrypto encode:hex(@"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31") as:NppBase58Check]
                  isEqualToString:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs"] &&
              [[NppCrypto decode:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs" as:NppBase58Check]
                  isEqualToData:hex(@"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31")] &&
              [NppCrypto decode:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAt" as:NppBase58Check] == nil);

        Check(@"Tools > Base > Base32", @"RFC 4648's vectors there and back, lower case and unpadded input read too",
              [[NppCrypto encode:utf8(@"foobar") as:NppBase32] isEqualToString:@"MZXW6YTBOI======"] &&
              [[NppCrypto encode:utf8(@"fo") as:NppBase32] isEqualToString:@"MZXQ===="] &&
              [[NppCrypto decode:@"MZXW6YTBOI======" as:NppBase32] isEqualToData:utf8(@"foobar")] &&
              [[NppCrypto decode:@"mzxw6ytboi" as:NppBase32] isEqualToData:utf8(@"foobar")] &&
              [NppCrypto decode:@"MZXW1" as:NppBase32] == nil);
    }

    if (NppSectionWanted(@"Tools: passwords")) { printf("\n== Tools: passwords ==\n");
        NSString *upper = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ", *lower = @"abcdefghijklmnopqrstuvwxyz", *digits = @"0123456789", *marks = @"!@#$%^&*";
        NSCharacterSet *(^setOf)(NSString *) = ^NSCharacterSet *(NSString *text) { return [NSCharacterSet characterSetWithCharactersInString:text]; };
        BOOL lengthsRight = YES, everySetSeen = YES, onlyFromSets = YES;
        NSCharacterSet *allowed = setOf([@[upper, lower, digits, marks] componentsJoinedByString:@""]);
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        for (int i = 0; i < 200; ++i) {
            NSString *one = [NppCrypto passwordOfLength:12 fromSets:@[upper, lower, digits, marks] requireEach:YES random:nil];
            [seen addObject:one ?: @""];
            if (one.length != 12) lengthsRight = NO;
            if ([one rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) onlyFromSets = NO;
            for (NSString *set in @[upper, lower, digits, marks])
                if ([one rangeOfCharacterFromSet:setOf(set)].location == NSNotFound) everySetSeen = NO;
        }
        Check(@"Tools > Password (made from the chosen sets)",
              @"two hundred passwords of twelve: each twelve long, from the chosen characters only, with one of every set in each, and no two alike",
              lengthsRight && onlyFromSets && everySetSeen && seen.count == 200);

        // Over many draws every character of the alphabet turns up, and none much more than its share.
        NSCountedSet<NSString *> *tally = [NSCountedSet set];
        NSString *many = [NppCrypto passwordOfLength:20000 fromSets:@[digits] requireEach:NO random:nil];
        for (NSUInteger i = 0; i < many.length; ++i) [tally addObject:[many substringWithRange:NSMakeRange(i, 1)]];
        NSUInteger least = NSUIntegerMax, most = 0;
        for (NSString *digit in tally) { least = MIN(least, [tally countForObject:digit]); most = MAX(most, [tally countForObject:digit]); }
        Check(@"Tools > Password (drawn evenly)", @"of 20000 digits each of the ten turns up about 2000 times",
              tally.count == 10 && least > 1700 && most < 2300);

        // With the draws dictated, the result is known exactly: what the generator asks for and in what order.
        __block NSMutableArray<NSNumber *> *asked = [NSMutableArray array];
        NSString *fixed = [NppCrypto passwordOfLength:4 fromSets:@[@"ab", @"12"] requireEach:YES
                                               random:^uint32_t(uint32_t below) { [asked addObject:@(below)]; return 0; }];
        Check(@"Tools > Password (how it draws)", @"one from each set first, the rest from all of them, then a shuffle - and nothing but the generator decides",
              [asked isEqualToArray:@[@2, @2, @4, @4, @4, @3, @2]] && fixed.length == 4 &&
              [[fixed stringByTrimmingCharactersInSet:setOf(@"ab12")] isEqualToString:@""]);

        NSString *emoji = [NppCrypto passwordOfLength:6 fromSets:@[@"😀é"] requireEach:NO random:nil];
        __block NSUInteger pieces = 0;
        [emoji enumerateSubstringsInRange:NSMakeRange(0, emoji.length) options:NSStringEnumerationByComposedCharacterSequences
                               usingBlock:^(NSString *, NSRange, NSRange, BOOL *) { pieces++; }];
        Check(@"Tools > Password (edges)", @"nothing to draw from gives nothing; a set repeated counts once; an emoji is one character; "
              @"more sets than characters still gives the length asked for; look-alikes can be left out",
              [NppCrypto passwordOfLength:8 fromSets:@[] requireEach:YES random:nil] == nil &&
              [NppCrypto passwordOfLength:8 fromSets:@[@""] requireEach:YES random:nil] == nil &&
              [NppCrypto passwordOfLength:0 fromSets:@[digits] requireEach:NO random:nil] == nil &&
              [[NppCrypto passwordOfLength:5 fromSets:@[@"x", @"x", @"xx"] requireEach:YES random:nil] isEqualToString:@"xxxxx"] &&
              pieces == 6 &&
              [NppCrypto passwordOfLength:2 fromSets:@[upper, lower, digits, marks] requireEach:YES random:nil].length == 2 &&
              [[NppCrypto withoutLookalikes:@"ABCO0oIl1|xyz"] isEqualToString:@"ABCxyz"]);

        Check(@"Tools > Password (entropy)", @"sixteen characters out of 62 is a little over 95 bits",
              fabs([NppCrypto entropyOfLength:16 alphabetSize:62] - 95.27) < 0.01 && [NppCrypto entropyOfLength:16 alphabetSize:1] == 0);
    }

    if (NppSectionWanted(@"Tools: the menu and its windows")) { printf("\n== Tools: the menu and its windows ==\n");
        NppPreferences *tp = [NppPreferences shared];
        NSString *languageBefore = tp.localizationFile;
        tp.localizationFile = @"";
        [app applyLocalization];
        NSDictionary *passwordSettingsBefore = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"];

        NSMenu *tools = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) if ([NppEnglishMenuTitle(top.submenu) isEqualToString:@"Tools"]) tools = top.submenu;
        NSMenu *(^submenu)(NSMenu *, NSString *) = ^NSMenu *(NSMenu *menu, NSString *title) {
            for (NSMenuItem *item in menu.itemArray) if ([NppEnglishTitle(item) isEqualToString:title]) return item.submenu;
            return nil;
        };
        NSMenu *hashes = submenu(tools, @"Hashes"), *base = submenu(tools, @"Base");
        NSMutableArray<NSString *> *hashTitles = [NSMutableArray array], *baseTitles = [NSMutableArray array];
        for (NSMenuItem *item in hashes.itemArray) [hashTitles addObject:item.isSeparatorItem ? @"-" : NppEnglishTitle(item)];
        for (NSMenuItem *item in base.itemArray) [baseTitles addObject:NppEnglishTitle(item)];
        BOOL threeEach = YES;
        for (NSMenuItem *item in hashes.itemArray) if (item.submenu && item.submenu.numberOfItems != 3) threeEach = NO;
        // Every hash, old or new, has the same three commands under the same names.
        BOOL threeAlike = YES;
        NSMutableArray<NSString *> *md5Titles = [NSMutableArray array];
        for (NSMenuItem *item in submenu(hashes, @"MD5").itemArray) [md5Titles addObject:NppEnglishTitle(item)];
        for (NSMenuItem *item in hashes.itemArray) {
            if (!item.submenu) continue;
            NSMutableArray<NSString *> *titles = [NSMutableArray array];
            for (NSMenuItem *command in item.submenu.itemArray) [titles addObject:NppEnglishTitle(command)];
            if (![titles isEqualToArray:md5Titles]) threeAlike = NO;
        }
        Check(@"Tools (the menu)", @"Hashes holds Notepad++'s four digests first, the port's six, then bcrypt, scrypt, Argon2 and PBKDF2, every one with the digests' three commands; "
              @"Base holds Base64, Base58 and Base32; and Password Generator and HTTP Request follow - named whole, with no ellipsis to be taken for a name cut short",
              [hashTitles isEqualToArray:@[@"MD5", @"SHA-1", @"SHA-256", @"SHA-512", @"SHA-224", @"SHA-384", @"SHA3-256", @"SHA3-512",
                                           @"BLAKE2b", @"CRC-32", @"-", @"bcrypt", @"scrypt", @"Argon2", @"PBKDF2"]] && threeEach && threeAlike &&
              [baseTitles isEqualToArray:@[@"Base64…", @"Base58…", @"Base32…"]] &&
              [NppEnglishTitle(tools.itemArray[2]) isEqualToString:@"Password Generator"] &&
              [NppEnglishTitle(tools.itemArray[3]) isEqualToString:@"HTTP Request"] &&
              [NppEnglishTitle(tools.itemArray[5]) isEqualToString:@"QR Code from Selection"] &&
              [NppEnglishTitle(tools.itemArray[6]) isEqualToString:@"Read QR Code from Clipboard"] &&
              [NppEnglishTitle(tools.itemArray[8]) isEqualToString:@"Install Command Line Tool"] &&
              tools.numberOfItems == 9);

        // Notepad++'s ids still find its own digests one level further down, and the
        // port's digests are not taken for them because they too say "Generate…".
        NSDictionary<NSNumber *, NSMenuItem *> *byID = [app.shortcutStore menuItemsByIdentifier];
        NSMenu *sha1 = submenu(hashes, @"SHA-1"), *sha224 = submenu(hashes, @"SHA-224");
        BOOL portsHaveNone = YES;
        for (NSNumber *identifier in byID) if (byID[identifier].menu == sha224 || byID[identifier].menu == base) portsHaveNone = NO;
        Check(@"Tools (Notepad++'s command ids)", @"IDM_TOOL_SHA1_GENERATE and its two neighbours are the items under Hashes > SHA-1, "
              @"MD5's are MD5's, and SHA-224's items carry no id of Notepad++'s",
              byID[@48507] == sha1.itemArray[0] && byID[@48508] == sha1.itemArray[1] && byID[@48509] == sha1.itemArray[2] &&
              byID[@48501] == submenu(hashes, @"MD5").itemArray[0] && byID[@48512] == submenu(hashes, @"SHA-512").itemArray[2] && portsHaveNone);

        // The digest window, as upstream's: it answers as one types.
        NppDigestWindow *dw = [NppDigestWindow shared];
        [dw showForDigest:NppDigestSHA256 fromFiles:NO];
        dw.eachLine.state = NSControlStateValueOff; dw.hmacKey.stringValue = @"";
        dw.input.string = @"abc"; [dw refresh];
        NSString *sha256abc = @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        BOOL whole = [dw.result.string isEqualToString:sha256abc];
        dw.input.string = @"abc\n\nabc"; dw.eachLine.state = NSControlStateValueOn; [dw refresh];
        BOOL perLine = [dw.result.string isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", sha256abc, sha256abc]];
        dw.eachLine.state = NSControlStateValueOff;
        dw.input.string = @"The quick brown fox jumps over the lazy dog"; dw.hmacKey.stringValue = @"key"; [dw refresh];
        BOOL keyed = [dw.result.string isEqualToString:@"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"] && !dw.hmacKey.superview.hidden;
        dw.input.string = @""; [dw refresh];
        BOOL emptied = dw.result.string.length == 0;
        [dw.clipboardButton performClick:nil];
        dw.hmacKey.stringValue = @"";
        Check(@"IDM_TOOL_SHA256_GENERATE (the window)", @"the digest follows the text as it is typed: of all of it, of each line, "
              @"as an HMAC when a key is given, and nothing for nothing; its title names the digest",
              whole && perLine && keyed && emptied && [dw.panel.title isEqualToString:@"Generate SHA-256 digest"] && dw.chooseFiles.hidden);

        [dw showForDigest:NppDigestSHA3_256 fromFiles:NO];
        dw.input.string = @"abc"; [dw refresh];
        Check(@"Tools > Hashes > SHA3-256 (the window)", @"a digest the port adds is shown in the same window under its own name, without the HMAC key it has none for",
              [dw.result.string isEqualToString:@"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"] &&
              [dw.panel.title isEqualToString:@"Generate SHA3-256 digest"] && dw.hmacKey.superview.hidden);

        NSString *fileA = TempFile(@"t_digest_a.txt", @"abc"), *fileB = TempFile(@"t_digest_b.txt", @"123456789");
        [dw showForDigest:NppDigestCRC32 fromFiles:YES];
        [dw digestFiles:@[fileA, fileB]];
        [dw.clipboardButton performClick:nil];
        Check(@"IDM_TOOL_SHA256_GENERATEFROMFILE (the window)", @"from files: a line for each file, digest and name as shasum writes them, and Copy to Clipboard takes them",
              [dw.result.string isEqualToString:@"352441c2  t_digest_a.txt\ncbf43926  t_digest_b.txt"] && !dw.chooseFiles.hidden &&
              [dw.chooseFiles.title isEqualToString:@"Choose files to generate CRC-32..."] && dw.input.enclosingScrollView.hidden &&
              [dw.panel.title isEqualToString:@"Generate CRC-32 digest from files"] &&
              [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:dw.result.string]);
        [dw.panel orderOut:nil];

        // Password hashes: the digests' window, with each kind's own settings above it and no others.
        NppPasswordHashWindow *hw = [NppPasswordHashWindow shared];
        [hw showForKind:NppPasswordHashBcrypt fromFiles:NO];
        NSArray *bcryptRows = [hw visibleFieldNames];
        BOOL bcryptShown = !hw.fields[@"bcryptCost"].isHiddenOrHasHiddenAncestor && hw.fields[@"argon2Memory"].isHiddenOrHasHiddenAncestor &&
                           hw.fields[@"keyLength"].isHiddenOrHasHiddenAncestor && [hw.panel.title isEqualToString:@"Generate bcrypt digest"];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        BOOL argonShown = hw.fields[@"bcryptCost"].isHiddenOrHasHiddenAncestor && !hw.fields[@"argon2Memory"].isHiddenOrHasHiddenAncestor &&
                          !hw.fields[@"keyLength"].isHiddenOrHasHiddenAncestor && [hw.panel.title isEqualToString:@"Generate Argon2 digest"];
        Check(@"Tools > Hashes (settings of each kind)", @"bcrypt shows its cost and version, Argon2 its variant, memory, iterations, parallelism and hash length - "
              @"each only its own, in a window named after it, with the digests' input, per-line box and result below",
              [bcryptRows isEqualToArray:@[@"bcryptCost", @"bcryptVersion"]] && bcryptShown && argonShown &&
              [[hw visibleFieldNames] isEqualToArray:@[@"argon2Variant", @"argon2Memory", @"argon2Passes", @"argon2Lanes", @"keyLength"]] &&
              hw.kind == NppPasswordHashArgon2 && !hw.input.isHiddenOrHasHiddenAncestor && !hw.eachLine.isHiddenOrHasHiddenAncestor &&
              !hw.result.isHiddenOrHasHiddenAncestor && hw.chooseFiles.hidden);

        [hw showForKind:NppPasswordHashBcrypt fromFiles:NO];
        hw.eachLine.state = hw.bareKey.state = NSControlStateValueOff;
        hw.input.string = @"U*U";
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"5"];
        [(NSPopUpButton *)hw.fields[@"bcryptVersion"] selectItemWithTitle:@"2a"];
        // The salt of the reference vector "CCCCCCCCCCCCCCCCCCCCC." as bytes.
        hw.salt.stringValue = @"10 41 04 10 41 04 10 41 04 10 41 04 10 41 04 10";
        [hw refreshAndWait];
        NSString *vectorHash = @"$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW";
        BOOL vector = [hw.result.string isEqualToString:vectorHash];
        hw.bareKey.state = NSControlStateValueOn; [hw refreshAndWait];
        BOOL bare = hw.result.string.length == 46 && [NppCrypto dataFromHex:hw.result.string] != nil;
        hw.bareKey.state = NSControlStateValueOff;
        hw.input.string = @"U*U\n\nU*U\n"; hw.eachLine.state = NSControlStateValueOn; [hw refreshAndWait];
        BOOL hashPerLine = [hw.result.string isEqualToString:[NSString stringWithFormat:@"%@\n\n%@", vectorHash, vectorHash]];
        hw.eachLine.state = NSControlStateValueOff; hw.input.string = @"U*U";
        hw.toVerify.stringValue = vectorHash; [hw verifyAndWait];
        BOOL matches = [hw.verdict.stringValue isEqualToString:@"The password matches the hash."];
        hw.input.string = @"U*V"; [hw verifyAndWait];
        BOOL differs = [hw.verdict.stringValue isEqualToString:@"The password does not match the hash."];
        hw.toVerify.stringValue = @"5f4dcc3b5aa765d61d8327deb882cf99"; [hw verifyAndWait];
        BOOL unknown = [hw.verdict.stringValue isEqualToString:@"This is not a bcrypt, scrypt, Argon2 or PBKDF2 hash."];
        Check(@"Tools > Hashes > bcrypt > Generate…", @"with the vector's text, cost, version and salt the result is the vector's hash - or its bare key, "
              @"or a hash for each line; Verify says the text matches, that another does not, and that an MD5 is no such hash",
              vector && bare && hashPerLine && matches && differs && unknown);

        // No salt given: each hash gets one of its own, so the same text twice is two different strings, both of which verify.
        hw.salt.stringValue = @""; hw.input.string = @"same\nsame"; hw.eachLine.state = NSControlStateValueOn; [hw refreshAndWait];
        NSArray<NSString *> *two = [hw.result.string componentsSeparatedByString:@"\n"];
        BOOL salted = two.count == 2 && ![two[0] isEqualToString:two[1]] && [two[0] hasPrefix:@"$2a$05$"] &&
                      [[NppCrypto password:[@"same" dataUsingEncoding:NSUTF8StringEncoding] matches:two[0]] boolValue] &&
                      [[NppCrypto password:[@"same" dataUsingEncoding:NSUTF8StringEncoding] matches:two[1]] boolValue];
        hw.eachLine.state = NSControlStateValueOff;
        hw.input.string = [@"" stringByPaddingToLength:80 withString:@"x" startingAtIndex:0]; [hw refreshAndWait];
        BOOL warned = [hw.problem.stringValue isEqualToString:@"bcrypt reads only the first 72 bytes."] && hw.result.string.length == 60;
        hw.input.string = @"x";
        hw.salt.stringValue = @"0102"; [hw refreshAndWait];
        BOOL shortSalt = [hw.problem.stringValue isEqualToString:@"bcrypt takes a salt of exactly 16 bytes."] && !hw.result.string.length;
        hw.salt.stringValue = @"xyz"; [hw refreshAndWait];
        BOOL badSalt = [hw.problem.stringValue isEqualToString:@"The salt is not valid hexadecimal."] && !hw.result.string.length;
        [hw newSalt:nil];
        NSString *salt1 = hw.salt.stringValue; [hw newSalt:nil];
        BOOL fresh = salt1.length == 32 && hw.salt.stringValue.length == 32 && ![salt1 isEqualToString:hw.salt.stringValue];
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"40"]; [hw refreshAndWait];
        BOOL badCost = [hw.problem.stringValue isEqualToString:@"The cost must be between 4 and 31."] && !hw.result.string.length;
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"5"]; hw.salt.stringValue = @"";
        Check(@"Tools > Hashes (salts, and what the window refuses)", @"without a salt every hash gets a random one and still verifies; past 72 bytes bcrypt says it reads no further; "
              @"a salt of the wrong length, one that is not hexadecimal and a cost out of range are said in words and no hash shown; Random gives sixteen new bytes",
              salted && warned && shortSalt && badSalt && fresh && badCost);

        [hw showForKind:NppPasswordHashScrypt fromFiles:NO];
        hw.input.string = @"pleaseletmein"; hw.bareKey.state = NSControlStateValueOn;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"SodiumChloride" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"scryptLogN"] setStringValue:@"14"];
        [hw refreshAndWait];
        BOOL scryptRight = [hw.result.string isEqualToString:@"7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2"];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        hw.input.string = @"password"; hw.bareKey.state = NSControlStateValueOff;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"somesalt" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"argon2Memory"] setStringValue:@"64"];
        [(NSTextField *)hw.fields[@"argon2Lanes"] setStringValue:@"2"];
        [(NSPopUpButton *)hw.fields[@"argon2Variant"] selectItemWithTitle:@"Argon2i"];
        [hw refreshAndWait];
        BOOL argonRight = [hw.result.string isEqualToString:@"$argon2i$v=19$m=64,t=2,p=2$c29tZXNhbHQ$u3EC2QpYDSqhwag4F/JKsYx8yBDM0sKg0MgMlK0pkWc"];
        [hw showForKind:NppPasswordHashPBKDF2 fromFiles:NO];
        hw.bareKey.state = NSControlStateValueOn;
        hw.salt.stringValue = [NppCrypto hexOfData:[@"salt" dataUsingEncoding:NSUTF8StringEncoding]];
        [(NSTextField *)hw.fields[@"pbkdf2Rounds"] setStringValue:@"4096"];
        [hw refreshAndWait];
        BOOL pbkdfRight = [hw.result.string isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"];
        Check(@"Tools > Hashes > scrypt, Argon2, PBKDF2 > Generate…", @"each, given a published vector's text, salt and settings through its fields, shows the vector's result",
              scryptRight && argonRight && pbkdfRight);

        // From files, as the digests have it: a line for each file, and the file's contents are what is hashed.
        [hw showForKind:NppPasswordHashPBKDF2 fromFiles:YES];
        hw.bareKey.state = NSControlStateValueOn;
        [hw hashFilesAndWait:@[TempFile(@"t_kdf_a.txt", @"password")]];
        BOOL fromFile = [hw.result.string isEqualToString:@"c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a  t_kdf_a.txt"] &&
                        !hw.chooseFiles.hidden && hw.input.isHiddenOrHasHiddenAncestor && hw.eachLine.hidden &&
                        [hw.chooseFiles.title isEqualToString:@"Choose files to generate PBKDF2..."] &&
                        [hw.panel.title isEqualToString:@"Generate PBKDF2 digest from files"];
        [hw hashFilesAndWait:@[TempFile(@"t_kdf_b.txt", @"other")]];
        BOOL twoFiles = [hw.result.string componentsSeparatedByString:@"\n"].count == 2 && [hw.result.string hasSuffix:@"  t_kdf_b.txt"];
        [hw.clipboardButton performClick:nil];
        Check(@"Tools > Hashes > PBKDF2 > Generate from files…", @"the contents of each chosen file are hashed, a line each with the file's name, and Copy to Clipboard takes them",
              fromFile && twoFiles && [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:hw.result.string]);
        hw.bareKey.state = NSControlStateValueOff; hw.salt.stringValue = @"";
        [(NSTextField *)hw.fields[@"argon2Memory"] setStringValue:@"19456"]; [(NSTextField *)hw.fields[@"argon2Lanes"] setStringValue:@"1"];
        [(NSTextField *)hw.fields[@"pbkdf2Rounds"] setStringValue:@"600000"]; [(NSTextField *)hw.fields[@"scryptLogN"] setStringValue:@"15"];
        [(NSTextField *)hw.fields[@"bcryptCost"] setStringValue:@"12"];
        [(NSPopUpButton *)hw.fields[@"argon2Variant"] selectItemAtIndex:0]; [(NSPopUpButton *)hw.fields[@"bcryptVersion"] selectItemAtIndex:0];
        [hw.panel orderOut:nil];

        // Into the clipboard: the selection, hashed with the kind's defaults and a salt of its own.
        SetDoc(ed, @"user: hunter2 end");
        [sci message:SCI_SETSEL wParam:6 lParam:13];
        NSMenu *argonMenu = submenu(hashes, @"Argon2");
        [NSApp sendAction:argonMenu.itemArray[2].action to:argonMenu.itemArray[2].target from:argonMenu.itemArray[2]];
        NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
        Check(@"Tools > Hashes > Argon2 > Generate from selection into clipboard", @"the clipboard holds an argon2id string with the default settings that the selected text verifies against",
              [clip hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"] &&
              [[NppCrypto password:[@"hunter2" dataUsingEncoding:NSUTF8StringEncoding] matches:clip] boolValue] &&
              ![[NppCrypto password:[@"hunter3" dataUsingEncoding:NSUTF8StringEncoding] matches:clip] boolValue]);

        // Base: a string or bytes in, the encoding out - and back, as text and as bytes.
        NppBaseWindow *bw = [NppBaseWindow shared];
        [bw showForEncoding:NppBase64];
        bw.direction.selectedSegment = 0; [bw.inputIsText performClick:nil]; bw.variant.state = NSControlStateValueOff;
        bw.input.string = @"Привет"; [bw refresh];
        BOOL onlyItsOwn = [bw.panel.title isEqualToString:@"Base64"] && [bw.variant.title isEqualToString:@"Base64 (URL-safe)"] && !bw.variant.hidden;
        for (NSView *v in bw.variant.superview.subviews) if ([v isKindOfClass:[NSPopUpButton class]]) onlyItsOwn = NO;
        BOOL fromText = [bw.output.string isEqualToString:@"0J/RgNC40LLQtdGC"] && bw.outputBytes.enclosingScrollView.hidden && !bw.inputIsHex.superview.hidden &&
                        [bw.outputLabel.stringValue isEqualToString:@"Result:"];
        [bw.inputIsHex performClick:nil];
        bw.input.string = @"fb ff"; [bw refresh];
        BOOL fromHex = [bw.output.string isEqualToString:@"+/8="] && bw.inputIsText.state == NSControlStateValueOff;
        [bw.variant performClick:nil];
        BOOL urlSafe = [bw.output.string isEqualToString:@"-_8="] && bw.encoding == NppBase64URL;
        [bw.variant performClick:nil];
        bw.input.string = @"fb f"; [bw refresh];
        BOOL badHex = !bw.output.string.length && [bw.problem.stringValue isEqualToString:@"The input is not bytes written in hexadecimal."];
        Check(@"Tools > Base > Base64 (encoding)", @"a text is encoded as its UTF-8 bytes, bytes given in hexadecimal as themselves, in the URL alphabet when that is chosen; "
              @"half a byte is said to be wrong; and the window is Base64's alone, with no choice of another encoding in it",
              fromText && fromHex && urlSafe && badHex && onlyItsOwn);

        [bw showForEncoding:NppBase58];
        bw.direction.selectedSegment = 1;
        bw.input.string = @"2NEpo7TZRRrLZSi2U"; [bw refresh];
        BOOL back = [bw.output.string isEqualToString:@"Hello World!"] && [bw.outputBytes.string isEqualToString:@"48656c6c6f20576f726c6421"] &&
                    !bw.outputBytes.enclosingScrollView.hidden && bw.inputIsHex.superview.hidden && [bw.outputLabel.stringValue isEqualToString:@"Text:"];
        bw.input.string = @"2NEpo7TZRRrLZSi20"; [bw refresh];
        BOOL refused = !bw.output.string.length && !bw.outputBytes.string.length && [bw.problem.stringValue isEqualToString:@"The input is not valid Base58."];
        BOOL base58Window = [bw.panel.title isEqualToString:@"Base58"] && [bw.variant.title isEqualToString:@"Base58Check"];
        bw.direction.selectedSegment = 0; [bw.inputIsHex performClick:nil];
        bw.input.string = @"00f54a5851e9372b87810a8e60cdd2e7cfd80b6e31"; [bw.variant performClick:nil];
        BOOL checked = [bw.output.string isEqualToString:@"1PMycacnJaSqwwJqjawXBErnLsZ7RkXUAs"] && bw.encoding == NppBase58Check;
        [bw.variant performClick:nil]; [bw.inputIsText performClick:nil];
        [bw showForEncoding:NppBase32];
        bw.input.string = @"foobar"; [bw refresh];
        BOOL base32Window = [bw.panel.title isEqualToString:@"Base32"] && bw.variant.hidden && [bw.output.string isEqualToString:@"MZXW6YTBOI======"];
        [bw showForEncoding:NppBase64];
        bw.direction.selectedSegment = 1;
        bw.input.string = @"//8="; [bw refresh];
        BOOL bytesOnly = !bw.output.string.length && [bw.outputBytes.string isEqualToString:@"ffff"] &&
                         [bw.problem.stringValue hasPrefix:@"The decoded bytes are not UTF-8 text"];
        Check(@"Tools > Base > Base58 (decoding)", @"decoding gives the text and its bytes in hexadecimal; a character outside the alphabet is refused by name; "
              @"bytes that are no text are shown as bytes only; Base58's box adds the checksum of an address, and Base32's window has no box",
              back && refused && bytesOnly && base58Window && checked && base32Window);

        // What is selected in the editor is what the window opens with.
        SetDoc(ed, @"see SGVsbG8= here");
        [sci message:SCI_SETSEL wParam:4 lParam:12];
        [NSApp sendAction:NSSelectorFromString(@"showBase:") to:app from:base.itemArray[0]];
        bw.direction.selectedSegment = 1; [bw refresh];
        Check(@"Tools > Base (opens with the selection)", @"the selected text is the input", [bw.input.string isEqualToString:@"SGVsbG8="] && [bw.output.string isEqualToString:@"Hello"]);
        bw.direction.selectedSegment = 0; bw.input.string = @"";
        [bw.panel orderOut:nil];

        // The password generator.
        NppPasswordWindow *pw = [NppPasswordWindow shared];
        [NSApp sendAction:NSSelectorFromString(@"showPasswordGenerator:") to:app from:nil];
        pw.upper.state = pw.lower.state = pw.digits.state = NSControlStateValueOn;
        pw.useSymbols.state = pw.noLookalikes.state = NSControlStateValueOff; pw.requireEach.state = NSControlStateValueOn;
        pw.length.stringValue = @"24"; pw.howMany.stringValue = @"5";
        [pw generate:nil];
        NSArray<NSString *> *five = [pw.result.string componentsSeparatedByString:@"\n"];
        NSCharacterSet *alnum = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"];
        BOOL shaped = five.count == 5 && [NSSet setWithArray:five].count == 5;
        for (NSString *one in five) if (one.length != 24 || [one rangeOfCharacterFromSet:alnum.invertedSet].location != NSNotFound) shaped = NO;
        BOOL entropy = [pw.entropy.stringValue isEqualToString:@"Entropy: about 142 bits"];      // 24 * log2(62)
        pw.upper.state = pw.lower.state = NSControlStateValueOff; pw.useSymbols.state = NSControlStateValueOn;
        pw.symbols.stringValue = @"# $ %"; pw.howMany.stringValue = @"1"; pw.length.stringValue = @"40";
        [pw generate:nil];
        NSString *custom = pw.result.string;
        BOOL ownSymbols = custom.length == 40 && [custom rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789#$%"].invertedSet].location == NSNotFound &&
                          [custom rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"#$%"]].location != NSNotFound;
        pw.noLookalikes.state = NSControlStateValueOn; [pw generate:nil];
        BOOL plain = [[pw chosenSets] isEqualToArray:@[@"23456789", @"#$%"]] && [pw.result.string rangeOfString:@"0"].location == NSNotFound &&
                     [pw.result.string rangeOfString:@"1"].location == NSNotFound;
        pw.digits.state = pw.useSymbols.state = NSControlStateValueOff; [pw generate:nil];
        BOOL nothing = !pw.result.string.length && [pw.entropy.stringValue isEqualToString:@"Choose at least one kind of character."];
        Check(@"Tools > Password", @"five passwords of 24 letters and digits, all different, about 142 bits each; the symbols are the ones typed in; "
              @"look-alikes can be left out; with no kind of character chosen it says so",
              shaped && entropy && ownSymbols && plain && nothing);

        // A hash of each password, of the kind chosen, with that kind's default settings.
        pw.digits.state = NSControlStateValueOn; pw.length.stringValue = @"16"; pw.howMany.stringValue = @"2";
        NSMutableArray<NSString *> *kindTitles = [NSMutableArray array];
        for (NSMenuItem *item in pw.hashKind.itemArray) [kindTitles addObject:item.title];
        [pw.hashKind selectItemWithTitle:@"None"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        BOOL noneShown = !pw.hashes.string.length && pw.hashes.enclosingScrollView.hidden;
        [pw.hashKind selectItemWithTitle:@"SHA-256"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        NSArray<NSString *> *made = [pw.result.string componentsSeparatedByString:@"\n"], *digests = [pw.hashes.string componentsSeparatedByString:@"\n"];
        BOOL digested = made.count == 2 && digests.count == 2 && !pw.hashes.enclosingScrollView.hidden;
        for (NSUInteger i = 0; digested && i < 2; ++i)
            digested = [digests[i] isEqualToString:[EditorController hashOfData:[made[i] dataUsingEncoding:NSUTF8StringEncoding] digest:NppDigestSHA256]];
        [pw.hashKind selectItemWithTitle:@"Argon2"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        [pw generateAndWait];
        made = [pw.result.string componentsSeparatedByString:@"\n"];
        NSArray<NSString *> *argons = [pw.hashes.string componentsSeparatedByString:@"\n"];
        BOOL argoned = made.count == 2 && argons.count == 2;
        for (NSUInteger i = 0; argoned && i < 2; ++i)
            argoned = [argons[i] hasPrefix:@"$argon2id$v=19$m=19456,t=2,p=1$"] && [[NppCrypto password:[made[i] dataUsingEncoding:NSUTF8StringEncoding] matches:argons[i]] boolValue];
        BOOL keptKind = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"][@"hash"] isEqualToString:@"Argon2"];
        [pw.hashKind selectItemWithTitle:@"None"]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        Check(@"Tools > Password (with its hash)", @"the kinds are None, the four password hashes and the ten digests; SHA-256 gives each password's digest, "
              @"Argon2 a default-settings string each password verifies against; None shows nothing; the choice is remembered",
              kindTitles.count == 15 && [[kindTitles subarrayWithRange:NSMakeRange(0, 6)] isEqualToArray:@[@"None", @"bcrypt", @"scrypt", @"Argon2", @"PBKDF2", @"MD5"]] &&
              noneShown && digested && argoned && keptKind);

        pw.howMany.stringValue = @"1"; pw.length.stringValue = @"12"; [pw generate:nil];
        NSDictionary *kept = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppPasswordGenerator"];
        SetDoc(ed, @"password=");
        [sci message:SCI_GOTOPOS wParam:9];
        [pw insert:nil];
        NSString *inserted = [sci string];
        [pw.result.window makeFirstResponder:nil];
        Check(@"Tools > Password (kept and used)", @"the settings are remembered for the next time, and Insert into Document puts the password at the caret",
              [kept[@"length"] integerValue] == 12 && [kept[@"digits"] boolValue] && ![kept[@"upper"] boolValue] && [kept[@"symbols"] isEqualToString:@"# $ %"] &&
              inserted.length == 9 + 12 && [inserted hasPrefix:@"password="] && [[inserted substringFromIndex:9] isEqualToString:pw.result.string]);

        // In another language: the windows' own texts are translated, and every one of them fits.
        tp.localizationFile = @"russian.xml";
        [app applyLocalization];
        NSString *(^cutIn)(NSWindow *) = ^NSString *(NSWindow *window) {
            [window.contentView layoutSubtreeIfNeeded];
            NSMutableArray<NSString *> *bad = [NSMutableArray array];
            NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:window.contentView];
            while (queue.count) {
                NSView *v = queue.firstObject; [queue removeObjectAtIndex:0];
                if (v.hidden) continue;
                [queue addObjectsFromArray:v.subviews];
                BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).selectable;
                BOOL isButton = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]];
                if (!isLabel && !isButton) continue;
                NSControl *c = (NSControl *)v;
                NSString *text = isLabel ? c.stringValue : ((NSButton *)c).title;
                if (!text.length) continue;
                NSSize need = c.cell.wraps ? [c.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(c.frame), 10000)] : c.cell.cellSize;
                if (c.cell.wraps) need.width = 0;
                NSRect inWindow = [v convertRect:v.bounds toView:nil];
                if (need.width > NSWidth(c.frame) + 1.5 || need.height > NSHeight(c.frame) + 1.5 ||
                    NSMaxX(inWindow) > NSWidth(window.contentView.frame) + 0.5 || NSMinX(inWindow) < -0.5)
                    [bad addObject:[NSString stringWithFormat:@"\"%@\" needs %.0fx%.0f, has %.0fx%.0f", text, need.width, need.height, NSWidth(c.frame), NSHeight(c.frame)]];
            }
            return [bad componentsJoinedByString:@"; "];
        };
        [dw showForDigest:NppDigestSHA384 fromFiles:NO];
        [hw showForKind:NppPasswordHashArgon2 fromFiles:NO];
        hw.toVerify.stringValue = @"x"; [hw verifyAndWait];
        [bw showForEncoding:NppBase58]; bw.direction.selectedSegment = 1; bw.input.string = @"0"; [bw refresh];
        [pw show]; [pw.hashKind selectItemAtIndex:5]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind]; [pw generateAndWait];
        NSString *cut = [@[cutIn(dw.panel), cutIn(hw.panel), cutIn(bw.panel), cutIn(pw.panel)] componentsJoinedByString:@""];
        if (cut.length) printf("    cut in Russian: %s\n", cut.UTF8String);
        NSString *hashesTitle = nil;
        for (NSMenuItem *item in tools.itemArray) if (item.submenu == hashes) hashesTitle = item.title;
        printf("    l10n tools 2: %s | %s | %s | %s\n", hw.panel.title.UTF8String, hw.bareKey.title.UTF8String, hw.salt.placeholderString.UTF8String, [pw.hashKind itemAtIndex:0].title.UTF8String);
        printf("    l10n tools: %s | %s | %s | %s | %s | %s\n", dw.panel.title.UTF8String, dw.eachLine.title.UTF8String, hw.verdict.stringValue.UTF8String,
               bw.problem.stringValue.UTF8String, pw.entropy.stringValue.UTF8String, hashesTitle.UTF8String);
        Check(@"Tools (in another language)", @"in Russian the menu, the windows' titles, labels, buttons and messages are Russian - the digest's name and the "
              @"placeholders filled in - and no text is cut",
              !cut.length && [hashesTitle isEqualToString:@"Хеши"] && [dw.panel.title containsString:@"SHA-384"] && ![dw.panel.title containsString:@"Generate"] &&
              ![dw.eachLine.title containsString:@"Treat"] && [hw.verdict.stringValue isEqualToString:@"Это не хеш bcrypt, scrypt, Argon2 или PBKDF2."] &&
              [hw.panel.title containsString:@"Argon2"] && ![hw.panel.title containsString:@"Generate"] && [hw.bareKey.title isEqualToString:@"Показать сам ключ в шестнадцатеричном виде"] &&
              [hw.salt.placeholderString isEqualToString:@"Пусто: каждый раз случайная соль"] && ![[pw.hashKind itemAtIndex:0].title isEqualToString:@"None"] && [[pw.hashKind itemAtIndex:1].title isEqualToString:@"bcrypt"] && [bw.problem.stringValue isEqualToString:@"Ввод не является корректным Base58."] &&
              [bw.outputLabel.stringValue isEqualToString:@"Текст:"] && [pw.panel.title isEqualToString:@"Генератор паролей"] &&
              [pw.upper.title isEqualToString:@"Заглавные буквы (A-Z)"] && [pw.entropy.stringValue hasPrefix:@"Энтропия: около "] &&
              [pw.entropy.stringValue hasSuffix:@" бит"]);

        [pw.hashKind selectItemAtIndex:0]; [NSApp sendAction:pw.hashKind.action to:pw.hashKind.target from:pw.hashKind];
        for (NSPanel *panel in @[dw.panel, hw.panel, bw.panel, pw.panel]) [panel orderOut:nil];
        bw.input.string = @""; hw.toVerify.stringValue = @""; hw.input.string = @"";
        if (passwordSettingsBefore) [[NSUserDefaults standardUserDefaults] setObject:passwordSettingsBefore forKey:@"NppPasswordGenerator"];
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppPasswordGenerator"];
        tp.localizationFile = languageBefore ?: @"";
        [app applyLocalization];
    }
}

/// == Tools: HTTP Request ==; == Macro ==; == Window ==; == Run and Help ==
void NppTestsHttpMacroRunHelp(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Tools: HTTP Request")) { printf("\n== Tools: HTTP Request ==\n");
        NSData *(^utf8)(NSString *) = ^NSData *(NSString *text) { return [text dataUsingEncoding:NSUTF8StringEncoding]; };
        NSString *(^named)(NSArray<NppHttpPair *> *, NSString *) = ^NSString *(NSArray<NppHttpPair *> *pairs, NSString *name) {
            for (NppHttpPair *pair in pairs) if ([pair.name caseInsensitiveCompare:name] == NSOrderedSame) return pair.value;
            return nil;
        };

        NSPasteboard *board = [NSPasteboard generalPasteboard];
        // What is typed, a pair to a line.
        NSArray<NppHttpPair *> *typed = [NppHttpPair pairsFromText:@"Accept: application/json\n\n# a note\n  X-Token :  a:b  \nFlag\n" separator:@":"];
        Check(@"Tools > HTTP Request (pairs)", @"\"Name: value\" lines become pairs in their order: blank lines and # lines passed over, "
              @"spaces trimmed, only the first colon dividing, a bare name given an empty value - and they are written back the same",
              typed.count == 3 && [typed[0].name isEqualToString:@"Accept"] && [typed[0].value isEqualToString:@"application/json"] &&
              [typed[1].name isEqualToString:@"X-Token"] && [typed[1].value isEqualToString:@"a:b"] &&
              [typed[2].name isEqualToString:@"Flag"] && typed[2].value.length == 0 &&
              [[NppHttpPair textFromPairs:typed separator:@":"] isEqualToString:@"Accept: application/json\nX-Token: a:b\nFlag: "] &&
              [[NppHttpPair textFromPairs:[NppHttpPair pairsFromText:@"a=1\nb = x=y" separator:@"="] separator:@"="] isEqualToString:@"a=1\nb=x=y"]);

        NppHttpRequest *built = [[NppHttpRequest alloc] init];
        built.address = @"example.com/search?q=1";
        built.parameters = @[[NppHttpPair pairWithName:@"name" value:@"Иван & co"], [NppHttpPair pairWithName:@"a b" value:@"1+1=2"]];
        NSString *withQuery = [built url].absoluteString;
        built.address = @"https://example.com/a path/файл"; built.parameters = @[];
        NSString *spaced = [built url].absoluteString;
        NppHttpRequest *bad = [[NppHttpRequest alloc] init];
        BOOL refused = [bad url] == nil;
        bad.address = @"file:///etc/passwd"; refused = refused && [bad url] == nil;
        bad.address = @"ftp://example.com/x"; refused = refused && [bad url] == nil;
        Check(@"Tools > HTTP Request (the address)", @"an address without a scheme is http; parameters join its query percent-encoded; a space and Cyrillic in the "
              @"path are encoded; nothing, file: and ftp: are no address to send to",
              [withQuery isEqualToString:@"http://example.com/search?q=1&name=%D0%98%D0%B2%D0%B0%D0%BD%20%26%20co&a%20b=1%2B1%3D2"] &&
              [spaced isEqualToString:@"https://example.com/a%20path/%D1%84%D0%B0%D0%B9%D0%BB"] && refused);

        // A request written out for curl, and read back from that.
        NppHttpRequest *out = [[NppHttpRequest alloc] init];
        out.method = @"PUT"; out.address = @"https://api.example.com/items/7";
        out.headers = @[[NppHttpPair pairWithName:@"Content-Type" value:@"application/json"], [NppHttpPair pairWithName:@"X-Note" value:@"it's"]];
        out.body = utf8(@"{\"name\": \"O'Brien\",\n \"n\": 1}");
        out.username = @"igor"; out.password = @"p:w d"; out.allowInvalidCertificates = YES; out.timeout = 5;
        NSString *command = [out curlCommand];
        NSString *why = nil;
        NppHttpRequest *back = [NppHttpRequest requestFromCurlCommand:command error:&why];
        Check(@"Tools > HTTP Request (Copy as curl)", @"the command names the method, quotes every value for the shell - an apostrophe and a line break among them - "
              @"and, read back, is the same request",
              [command hasPrefix:@"curl -X PUT 'https://api.example.com/items/7' \\\n  -H 'Content-Type: application/json' \\\n  -H 'X-Note: it'\\''s' \\\n  -u 'igor:p:w d'"] &&
              [command hasSuffix:@"-L -k -m 5"] && back != nil && [back.method isEqualToString:@"PUT"] &&
              [back.address isEqualToString:out.address] && [back.body isEqualToData:out.body] && back.headers.count == 2 &&
              [named(back.headers, @"X-Note") isEqualToString:@"it's"] && [back.username isEqualToString:@"igor"] &&
              [back.password isEqualToString:@"p:w d"] && back.allowInvalidCertificates && back.followRedirects && back.timeout == 5);

        // Commands as they are found in the wild.
        NppHttpRequest *chrome = [NppHttpRequest requestFromCurlCommand:
            @"curl 'https://example.com/api/login' \\\n  -H 'accept: */*' \\\n  -H \"x-q: say \\\"hi\\\" $HOME\" \\\n"
            @"  --data-raw $'{\"text\":\"line1\\nline2 \\u0416 it\\'s\"}' \\\n  --compressed -o /dev/null" error:NULL];
        NppHttpRequest *terse = [NppHttpRequest requestFromCurlCommand:@"curl -sSLkX DELETE -uadmin:secret -m10 http://localhost:8080/x" error:NULL];
        NppHttpRequest *asQuery = [NppHttpRequest requestFromCurlCommand:@"curl -G --data-urlencode 'q=a b&c' -d page=2 --url example.com/find -I" error:NULL];
        NppHttpRequest *json = [NppHttpRequest requestFromCurlCommand:@"/usr/bin/curl --json '{\"a\":1}' --oauth2-bearer tok -A agent/1 -e http://from -b 'sid=9' https://example.com/j" error:NULL];
        NppHttpRequest *form = [NppHttpRequest requestFromCurlCommand:@"curl -d a=1 -d b=2 --header='X-A: 1' https://example.com/f" error:NULL];
        Check(@"Tools > HTTP Request (Paste curl Command: a browser's)", @"quotes of both kinds, a continued line, bash's $'…' with \\n, \\u and \\' in it; the body makes it a POST; "
              @"--compressed and -o with its file are passed over; curl follows no redirects unless told to",
              [chrome.address isEqualToString:@"https://example.com/api/login"] && [chrome.method isEqualToString:@"POST"] &&
              [chrome.body isEqualToData:utf8(@"{\"text\":\"line1\nline2 Ж it's\"}")] && chrome.headers.count == 2 &&
              [named(chrome.headers, @"x-q") isEqualToString:@"say \"hi\" $HOME"] && !chrome.followRedirects);
        Check(@"Tools > HTTP Request (Paste curl Command: options)", @"short options run together with a value at the end (-sSLkX DELETE), a value stuck to its letter (-uadmin:secret, -m10); "
              @"-G with --data-urlencode puts the data in the address; -I is HEAD; --json, --oauth2-bearer, -A, -e, -b become the headers they stand for; several -d are joined with &",
              [terse.method isEqualToString:@"DELETE"] && terse.followRedirects && terse.allowInvalidCertificates && [terse.username isEqualToString:@"admin"] &&
              [terse.password isEqualToString:@"secret"] && terse.timeout == 10 && [terse.address isEqualToString:@"http://localhost:8080/x"] &&
              [asQuery.address isEqualToString:@"example.com/find?q=a%20b%26c&page=2"] && [asQuery.method isEqualToString:@"HEAD"] && asQuery.body == nil &&
              [json.method isEqualToString:@"POST"] && [named(json.headers, @"Content-Type") isEqualToString:@"application/json"] &&
              [named(json.headers, @"Accept") isEqualToString:@"application/json"] && [named(json.headers, @"Authorization") isEqualToString:@"Bearer tok"] &&
              [named(json.headers, @"User-Agent") isEqualToString:@"agent/1"] && [named(json.headers, @"Referer") isEqualToString:@"http://from"] &&
              [named(json.headers, @"Cookie") isEqualToString:@"sid=9"] && [json.body isEqualToData:utf8(@"{\"a\":1}")] &&
              [form.body isEqualToData:utf8(@"a=1&b=2")] && [named(form.headers, @"X-A") isEqualToString:@"1"]);

        NSString *notCurl = nil, *noAddress = nil, *fromFile = nil, *aForm = nil, *notWeb = nil;
        BOOL allRefused = ![NppHttpRequest requestFromCurlCommand:@"wget http://example.com" error:&notCurl] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -X POST -H 'A: b'" error:&noAddress] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -d @secrets.txt http://example.com" error:&fromFile] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl -F file=@a.png http://example.com" error:&aForm] &&
                          ![NppHttpRequest requestFromCurlCommand:@"curl file:///etc/passwd" error:&notWeb];
        Check(@"Tools > HTTP Request (Paste curl Command: what is refused)", @"what is not a curl command, one with no address, one that reads its data or a form from a file, "
              @"and one whose address is not the web's - each refused with its reason",
              allRefused && [notCurl isEqualToString:@"This is not a curl command."] && [noAddress isEqualToString:@"The command has no address."] &&
              [fromFile hasPrefix:@"The command reads its data from a file"] && [aForm hasPrefix:@"Forms and uploads"] && [notWeb containsString:@"not an http or https address"]);

        // End to end against a real server, started for this test, which says back what it was asked.
        NSString *script = [[NSBundle mainBundle] pathForResource:@"test-http-server" ofType:@"py"];
        NSTask *server = nil;
        NSInteger port = 0;
        if (script) {
            server = [[NSTask alloc] init];
            server.executableURL = [NSURL fileURLWithPath:@"/usr/bin/python3"];
            server.arguments = @[script];
            NSPipe *serverOut = [NSPipe pipe];
            server.standardOutput = serverOut;
            if ([server launchAndReturnError:NULL]) {
                NSString *text = [[NSString alloc] initWithData:[serverOut.fileHandleForReading availableData] encoding:NSUTF8StringEncoding];
                NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:NULL];
                [scanner scanInteger:&port];
            }
        }
        if (port <= 0) {
            Check(@"Tools > HTTP Request (sending)", @"the test server could not be started", NO);
        } else {
            NSString *base = [NSString stringWithFormat:@"http://127.0.0.1:%ld", (long)port];
            NSDictionary *(^echoed)(NppHttpResponse *) = ^NSDictionary *(NppHttpResponse *response) {
                return response.body.length ? [NSJSONSerialization JSONObjectWithData:response.body options:0 error:NULL] : nil;
            };

            NppHttpRequest *get = [[NppHttpRequest alloc] init];
            get.address = [base stringByAppendingString:@"/echo?fixed=1"];
            get.parameters = @[[NppHttpPair pairWithName:@"q" value:@"a b&c"], [NppHttpPair pairWithName:@"имя" value:@"Жук"]];
            get.headers = @[[NppHttpPair pairWithName:@"X-Custom" value:@"42"], [NppHttpPair pairWithName:@"Accept" value:@"application/json"]];
            NppHttpResponse *got = [NppHttpClient send:get cancelled:nil];
            NSDictionary *saw = echoed(got);
            NSArray *wantQuery = @[@[@"fixed", @"1"], @[@"q", @"a b&c"], @[@"имя", @"Жук"]];
            Check(@"Tools > HTTP Request (GET)", @"the server sees the method, the address's own query with the parameters after it - decoded back to what was typed - and the headers given; "
                  @"the answer has its status line, its headers in their order, and the time it took",
                  got.error == nil && got.status == 200 && [got.statusLine hasPrefix:@"HTTP/1."] && [got.statusLine hasSuffix:@"200 OK"] &&
                  [saw[@"method"] isEqualToString:@"GET"] && [saw[@"query"] isEqualToArray:wantQuery] &&
                  [saw[@"headers"][@"x-custom"] isEqualToString:@"42"] && [saw[@"headers"][@"accept"] isEqualToString:@"application/json"] &&
                  [saw[@"headers"][@"user-agent"] hasPrefix:@"NotepadMac/"] && [[got valueOfHeader:@"x-test-server"] isEqualToString:@"notepad"] &&
                  [[got valueOfHeader:@"Content-Type"] isEqualToString:@"application/json"] && got.elapsed > 0 && got.redirects == 0 &&
                  [[got headerText] hasPrefix:got.statusLine] && [[got headerText] containsString:@"\nX-Test-Server: notepad"]);

            BOOL bodies = YES;
            for (NSString *method in @[@"POST", @"PUT", @"PATCH", @"DELETE"]) {
                NppHttpRequest *post = [[NppHttpRequest alloc] init];
                post.method = method; post.address = [base stringByAppendingString:@"/echo"];
                post.headers = @[[NppHttpPair pairWithName:@"Content-Type" value:@"application/json; charset=utf-8"]];
                post.body = utf8(@"{\"имя\": \"Жук\", \"n\": [1, 2]}\n");
                NSDictionary *sawPost = echoed([NppHttpClient send:post cancelled:nil]);
                if (![sawPost[@"method"] isEqualToString:method] || ![sawPost[@"body"] isEqualToString:@"{\"имя\": \"Жук\", \"n\": [1, 2]}\n"] ||
                    ![sawPost[@"headers"][@"content-type"] isEqualToString:@"application/json; charset=utf-8"] ||
                    [sawPost[@"headers"][@"content-length"] integerValue] != (NSInteger)post.body.length) {
                    bodies = NO; printf("    %s: %s\n", method.UTF8String, sawPost.description.UTF8String);
                }
            }
            Check(@"Tools > HTTP Request (POST, PUT, PATCH, DELETE)", @"each reaches the server under its own name with the body byte for byte and the content type given", bodies);

            NppHttpRequest *auth = [[NppHttpRequest alloc] init];
            auth.address = [base stringByAppendingString:@"/echo"]; auth.username = @"igor"; auth.password = @"pa:ss word";
            NSDictionary *sawAuth = echoed([NppHttpClient send:auth cancelled:nil]);
            NSString *wantAuth = [@"Basic " stringByAppendingString:[utf8(@"igor:pa:ss word") base64EncodedStringWithOptions:0]];
            NppHttpRequest *head = [[NppHttpRequest alloc] init];
            head.method = @"HEAD"; head.address = [base stringByAppendingString:@"/echo"];
            NppHttpResponse *headed = [NppHttpClient send:head cancelled:nil];
            NppHttpRequest *options = [[NppHttpRequest alloc] init];
            options.method = @"OPTIONS"; options.address = [base stringByAppendingString:@"/echo"];
            Check(@"Tools > HTTP Request (a name and password, HEAD, OPTIONS)", @"the name and password go as Basic authentication; HEAD brings the headers and no body; OPTIONS arrives as OPTIONS",
                  [sawAuth[@"headers"][@"authorization"] isEqualToString:wantAuth] &&
                  headed.status == 200 && headed.body.length == 0 && [headed valueOfHeader:@"Content-Length"].integerValue > 0 && headed.error == nil &&
                  [echoed([NppHttpClient send:options cancelled:nil])[@"method"] isEqualToString:@"OPTIONS"]);

            NppHttpRequest *moved = [[NppHttpRequest alloc] init];
            moved.address = [base stringByAppendingString:@"/redirect"];
            NppHttpResponse *followed = [NppHttpClient send:moved cancelled:nil];
            moved.followRedirects = NO;
            NppHttpResponse *stayed = [NppHttpClient send:moved cancelled:nil];
            NppHttpRequest *missing = [[NppHttpRequest alloc] init];
            missing.address = [base stringByAppendingString:@"/status/404"];
            NppHttpResponse *notFound = [NppHttpClient send:missing cancelled:nil];
            missing.address = [base stringByAppendingString:@"/status/500"];
            Check(@"Tools > HTTP Request (redirects and statuses)", @"a redirect is followed to its end - the last answer's headers, the address arrived at, one redirect counted - or, unticked, "
                  @"shown as the 302 it is with its Location; 404 and 500 are answers, not errors",
                  followed.status == 200 && followed.redirects == 1 && [followed.finalAddress hasSuffix:@"/echo?redirected=1"] &&
                  [echoed(followed)[@"query"] isEqualToArray:@[@[@"redirected", @"1"]]] && [followed valueOfHeader:@"Location"] == nil &&
                  stayed.status == 302 && [[stayed valueOfHeader:@"Location"] isEqualToString:@"/echo?redirected=1"] && [[stayed text] isEqualToString:@"moved"] &&
                  notFound.status == 404 && notFound.error == nil && [[notFound text] isEqualToString:@"status 404"] &&
                  [NppHttpClient send:missing cancelled:nil].status == 500);

            NppHttpRequest *other = [[NppHttpRequest alloc] init];
            other.address = [base stringByAppendingString:@"/latin1"];
            NSString *latin = [[NppHttpClient send:other cancelled:nil] text];
            other.address = [base stringByAppendingString:@"/binary"];
            NppHttpResponse *binary = [NppHttpClient send:other cancelled:nil];
            other.address = [base stringByAppendingString:@"/gzip"];
            NSString *unpacked = [[NppHttpClient send:other cancelled:nil] text];
            Check(@"Tools > HTTP Request (what the body is)", @"a body is read in the charset its Content-Type names; bytes that are no text are said to be none and kept as bytes; "
                  @"a gzip-encoded body is unpacked",
                  [latin isEqualToString:@"café crème"] && [binary text] == nil && binary.body.length == 4 && [unpacked isEqualToString:@"unpacked text"]);

            NppHttpRequest *slow = [[NppHttpRequest alloc] init];
            slow.address = [base stringByAppendingString:@"/slow"]; slow.timeout = 0.5;
            NSDate *began = [NSDate date];
            NppHttpResponse *timedOut = [NppHttpClient send:slow cancelled:nil];
            NSTimeInterval waited = -began.timeIntervalSinceNow;
            slow.timeout = 30;
            began = [NSDate date];
            __block int asked = 0;
            NppHttpResponse *givenUp = [NppHttpClient send:slow cancelled:^BOOL { return ++asked > 2; }];
            NSTimeInterval untilGivenUp = -began.timeIntervalSinceNow;
            NppHttpRequest *nobody = [[NppHttpRequest alloc] init];
            nobody.address = @"http://127.0.0.1:1/"; nobody.timeout = 5;
            NppHttpResponse *unreachable = [NppHttpClient send:nobody cancelled:nil];
            Check(@"Tools > HTTP Request (what goes wrong)", @"a server slower than the timeout is given up on at the timeout, with the reason; a request cancelled stops at once; "
                  @"a port nobody listens on is an error in words and no status",
                  timedOut.status == 0 && timedOut.error.length > 0 && waited < 2.5 &&
                  [givenUp.error isEqualToString:@"Cancelled."] && untilGivenUp < 2.5 &&
                  unreachable.status == 0 && unreachable.error.length > 0 && unreachable.body.length == 0);

            // The window: what is typed into it is what is sent, and the answer is shown.
            NppPreferences *hp = [NppPreferences shared];
            NSString *languageBefore = hp.localizationFile;
            hp.localizationFile = @"";
            [app applyLocalization];
            NSDictionary *savedBefore = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppHttpRequest"];
            NSMenu *tools = nil;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) if ([NppEnglishMenuTitle(top.submenu) isEqualToString:@"Tools"]) tools = top.submenu;
            NSMenuItem *httpItem = nil;
            for (NSMenuItem *item in tools.itemArray) if ([NppEnglishTitle(item) isEqualToString:@"HTTP Request"]) httpItem = item;
            [NSApp sendAction:httpItem.action to:httpItem.target from:httpItem];
            NppHttpWindow *hw = [NppHttpWindow shared];
            BOOL opened = httpItem != nil && hw.panel.isVisible && [hw.panel.title isEqualToString:@"HTTP Request"];

            [hw.method selectItemWithTitle:@"POST"];
            hw.address.stringValue = [NSString stringWithFormat:@"127.0.0.1:%ld/echo", (long)port];
            hw.parameters.string = @"page=2\nq=two words";
            hw.headers.string = @"X-From: window\n# not sent\nAccept: */*";
            hw.body.string = @"{\"ok\":true}";
            [hw.contentType selectItemWithTitle:@"application/json"];
            hw.username.stringValue = @""; hw.password.stringValue = @""; hw.timeout.stringValue = @"10";
            hw.followRedirects.state = NSControlStateValueOn; hw.allowInvalidCertificates.state = NSControlStateValueOff;
            hw.formatJSON.state = NSControlStateValueOff; hw.answerSection.selectedSegment = 0;
            [hw sendAndWait];
            NSDictionary *sawWindow = [NSJSONSerialization JSONObjectWithData:utf8(hw.answer.string) options:0 error:NULL];
            NSArray *windowQuery = @[@[@"page", @"2"], @[@"q", @"two words"]];
            BOOL sent = [sawWindow[@"method"] isEqualToString:@"POST"] && [sawWindow[@"query"] isEqualToArray:windowQuery] &&
                        [sawWindow[@"headers"][@"x-from"] isEqualToString:@"window"] && [sawWindow[@"headers"][@"content-type"] isEqualToString:@"application/json"] &&
                        [sawWindow[@"body"] isEqualToString:@"{\"ok\":true}"] && sawWindow[@"headers"][@"# not sent"] == nil;
            BOOL statusShown = [hw.status.stringValue hasPrefix:@"HTTP/1."] && [hw.status.stringValue containsString:@"200 OK"] && [hw.status.stringValue containsString:@" ms"];
            NSString *oneLine = [hw.answer.string copy];      // (a text view's string is its live store)
            hw.formatJSON.state = NSControlStateValueOn; [hw answerSectionChanged:nil];
            // (Laid out means white space only: taken out again, it is the answer as it came.)
            BOOL laidOut = [hw.answer.string hasPrefix:@"{\n  \"method\": \"POST\",\n  \"path\": \"/echo\",\n  \"query\": [\n    [\n      \"page\",\n      \"2\"\n    ],"] &&
                           ![oneLine containsString:@"\n"] &&
                           [[NSJSONSerialization JSONObjectWithData:utf8(hw.answer.string) options:0 error:NULL] isEqual:sawWindow];
            hw.answerSection.selectedSegment = 1; [hw answerSectionChanged:nil];
            BOOL headersShown = [hw.answer.string hasPrefix:@"HTTP/1."] && [hw.answer.string containsString:@"X-Test-Server: notepad"];
            hw.answerSection.selectedSegment = 0; [hw answerSectionChanged:nil];
            Check(@"Tools > HTTP Request (the window)", @"the menu item opens it; method, address, parameters, headers (a # line left out), body and its content type are what the server sees; "
                  @"the status line, time and size are shown; the JSON answer is laid out when that is ticked; Headers shows the answer's headers",
                  opened && sent && statusShown && laidOut && headersShown);

            // A header's own Content-Type wins over the pop-up's; with no body the pop-up adds nothing.
            hw.headers.string = @"content-type: text/csv";
            BOOL ownType = [hw request].headers.count == 1 && [[hw request].headers[0].value isEqualToString:@"text/csv"];
            hw.headers.string = @""; hw.body.string = @"";
            BOOL noType = [hw request].headers.count == 0 && [hw request].body == nil;
            Check(@"Tools > HTTP Request (the content type)", @"a Content-Type among the headers is the one sent, not the pop-up's; without a body none is added", ownType && noType);

            // Sections: one in view at a time, each with its hint.
            BOOL sections = YES;
            for (NSInteger i = 0; i < 4; ++i) {
                hw.section.selectedSegment = i; [hw sectionChanged:nil];
                NSArray<NSView *> *areas = @[hw.parameters.enclosingScrollView, hw.headers.enclosingScrollView, hw.body.enclosingScrollView, hw.username];
                for (NSInteger k = 0; k < 4; ++k) if (areas[(NSUInteger)k].isHiddenOrHasHiddenAncestor != (k != i)) sections = NO;
                if ((i == 3) != hw.hint.hidden) sections = NO;
            }
            hw.section.selectedSegment = 0; [hw sectionChanged:nil];
            Check(@"Tools > HTTP Request (sections)", @"Parameters, Headers, Body and Options are shown one at a time, the first three with a line on how to write them", sections);

            // curl both ways through the clipboard.
            [board clearContents];
            [board setString:[NSString stringWithFormat:@"curl -X PATCH '%@/echo?x=1' -H 'X-Pasted: yes' -u me:pw --data-raw 'a=1' -k", base] forType:NSPasteboardTypeString];
            BOOL pasted = [hw pasteCurlCommand:nil];
            BOOL filled = [hw.method.titleOfSelectedItem isEqualToString:@"PATCH"] && [hw.address.stringValue hasSuffix:@"/echo?x=1"] &&
                          [hw.headers.string isEqualToString:@"X-Pasted: yes"] && [hw.body.string isEqualToString:@"a=1"] &&
                          [hw.username.stringValue isEqualToString:@"me"] && [hw.password.stringValue isEqualToString:@"pw"] &&
                          hw.allowInvalidCertificates.state == NSControlStateValueOn && hw.followRedirects.state == NSControlStateValueOff;
            [hw sendAndWait];
            NSDictionary *sawPasted = [NSJSONSerialization JSONObjectWithData:hw.response.body options:0 error:NULL];
            [hw copyAsCurl:nil];
            NSString *copied = [board stringForType:NSPasteboardTypeString];
            [board clearContents];
            [board setString:@"ls -la" forType:NSPasteboardTypeString];
            BOOL notPasted = ![hw pasteCurlCommand:nil] && [hw.status.stringValue isEqualToString:@"This is not a curl command."] &&
                             [hw.method.titleOfSelectedItem isEqualToString:@"PATCH"];
            Check(@"Tools > HTTP Request (curl through the clipboard)", @"Paste curl Command fills the controls from the command, and what is then sent is that request; "
                  @"Copy as curl writes them out again; something else on the clipboard is refused in words and changes nothing",
                  pasted && filled && [sawPasted[@"method"] isEqualToString:@"PATCH"] && [sawPasted[@"headers"][@"x-pasted"] isEqualToString:@"yes"] &&
                  [sawPasted[@"body"] isEqualToString:@"a=1"] && [sawPasted[@"headers"][@"authorization"] hasPrefix:@"Basic "] &&
                  [copied hasPrefix:@"curl -X PATCH 'http://127.0.0.1:"] && [copied containsString:@"-H 'X-Pasted: yes'"] && [copied containsString:@"-u 'me:pw'"] &&
                  [copied containsString:@"--data-raw 'a=1'"] && [copied hasSuffix:@"-k"] && notPasted);

            // A method the pop-up does not list (WebDAV's PROPFIND) is added to it by the paste,
            // and is the one sent and copied out again.
            [board clearContents];
            [board setString:[NSString stringWithFormat:@"curl -X PROPFIND '%@/echo'", base] forType:NSPasteboardTypeString];
            BOOL pastedOther = [hw pasteCurlCommand:nil] && [hw.method.titleOfSelectedItem isEqualToString:@"PROPFIND"];
            NSString *otherMethod = nil, *otherCopied = nil;
            @try {
                otherMethod = [hw request].method;
                [hw copyAsCurl:nil];
                otherCopied = [board stringForType:NSPasteboardTypeString];
            } @catch (NSException *e) { printf("    PROPFIND: %s\n", e.reason.UTF8String); }
            [hw.method selectItemWithTitle:@"GET"];
            Check(@"Tools > HTTP Request (a method of its own)", @"a pasted method the pop-up does not list is added, selected, and is the request's method",
                  pastedOther && [otherMethod isEqualToString:@"PROPFIND"] && [otherCopied hasPrefix:@"curl -X PROPFIND "]);

            // The answer into the editor, in the language its content type names.
            NSUInteger tabsBefore = ed.documents.count;
            hw.formatJSON.state = NSControlStateValueOn; [hw answerSectionChanged:nil];
            [hw openAnswer:nil];
            Check(@"Tools > HTTP Request (Open in New Document)", @"the answer's body becomes a new document, laid out as it was shown, and a JSON answer is given the JSON language",
                  ed.documents.count == tabsBefore + 1 && [DocText(ed) isEqualToString:hw.answer.string] && [DocText(ed) containsString:@"\"method\": \"PATCH\""] &&
                  [ed.currentDocument.language.name isEqualToString:@"json"]);
            [sci message:SCI_SETSAVEPOINT];
            [ed closeCurrentDocument];

            NSDictionary *kept = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppHttpRequest"];
            hw.address.stringValue = @"mailto:someone"; hw.password.stringValue = @"";
            [hw send:nil];
            Check(@"Tools > HTTP Request (kept, and what is not sent)", @"the request is remembered for the next time - its password excepted; an address that is not the web's is said so and nothing is sent",
                  [kept[@"method"] isEqualToString:@"PATCH"] && [kept[@"address"] hasSuffix:@"/echo?x=1"] && [kept[@"headers"] isEqualToString:@"X-Pasted: yes"] &&
                  [kept[@"username"] isEqualToString:@"me"] && kept[@"password"] == nil &&
                  [hw.status.stringValue isEqualToString:@"The address is not an http or https address."] && hw.response.status == 0);

            // A binary answer in the window: said to be no text, its beginning as bytes.
            hw.address.stringValue = [base stringByAppendingString:@"/binary"]; [hw.method selectItemWithTitle:@"GET"]; hw.body.string = @""; hw.headers.string = @"";
            hw.username.stringValue = @"";
            [hw sendAndWait];
            Check(@"Tools > HTTP Request (an answer that is no text)", @"four bytes that are no text are said to be four bytes, and shown in hexadecimal",
                  [hw.answer.string isEqualToString:@"The answer is not text: 4 bytes.\n\nfffe00c3"]);

            // In another language, with every text in view.
            hp.localizationFile = @"russian.xml";
            [app applyLocalization];
            [hw show];
            NSString *(^cutIn)(NSWindow *) = ^NSString *(NSWindow *window) {
                [window.contentView layoutSubtreeIfNeeded];
                NSMutableArray<NSString *> *cut = [NSMutableArray array];
                NSMutableArray<NSView *> *queue = [NSMutableArray arrayWithObject:window.contentView];
                while (queue.count) {
                    NSView *v = queue.firstObject; [queue removeObjectAtIndex:0];
                    if (v.hidden) continue;
                    [queue addObjectsFromArray:v.subviews];
                    BOOL isLabel = [v isKindOfClass:[NSTextField class]] && !((NSTextField *)v).editable && !((NSTextField *)v).selectable;
                    BOOL isButton = [v isKindOfClass:[NSButton class]] && ![v isKindOfClass:[NSPopUpButton class]];
                    BOOL isSegments = [v isKindOfClass:[NSSegmentedControl class]];
                    if (!isLabel && !isButton && !isSegments) continue;
                    NSControl *c = (NSControl *)v;
                    NSString *text = isLabel ? c.stringValue : isButton ? ((NSButton *)c).title : [(NSSegmentedControl *)c labelForSegment:0];
                    if (!text.length) continue;
                    NSSize need = c.cell.wraps ? [c.cell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(c.frame), 10000)] : c.cell.cellSize;
                    if (c.cell.wraps) need.width = 0;
                    NSRect inWindow = [v convertRect:v.bounds toView:nil];
                    if (need.width > NSWidth(c.frame) + 1.5 || need.height > NSHeight(c.frame) + 1.5 ||
                        NSMaxX(inWindow) > NSWidth(window.contentView.frame) + 0.5 || NSMinX(inWindow) < -0.5)
                        [cut addObject:[NSString stringWithFormat:@"\"%@\" needs %.0fx%.0f, has %.0fx%.0f", text, need.width, need.height, NSWidth(c.frame), NSHeight(c.frame)]];
                }
                return [cut componentsJoinedByString:@"; "];
            };
            NSMutableString *cut = [NSMutableString string];
            for (NSInteger i = 0; i < 4; ++i) { hw.section.selectedSegment = i; [hw sectionChanged:nil]; [cut appendString:cutIn(hw.panel)]; }
            if (cut.length) printf("    cut in Russian: %s\n", cut.UTF8String);
            hw.section.selectedSegment = 1; [hw sectionChanged:nil];
            printf("    l10n http: %s | %s | %s | %s | %s | %s\n", hw.panel.title.UTF8String, hw.sendButton.title.UTF8String, [hw.section labelForSegment:1].UTF8String,
                   hw.hint.stringValue.UTF8String, hw.followRedirects.title.UTF8String, httpItem.title.UTF8String);
            Check(@"Tools > HTTP Request (in another language)", @"in Russian the menu item, the window's title, sections, labels, hints and buttons are Russian, and no text is cut in any section",
                  !cut.length && [httpItem.title isEqualToString:@"HTTP-запрос"] && [hw.panel.title isEqualToString:@"HTTP-запрос"] &&
                  [hw.sendButton.title isEqualToString:@"Отправить"] && [[hw.section labelForSegment:1] isEqualToString:@"Заголовки"] &&
                  [hw.hint.stringValue isEqualToString:@"По одному в строке: Имя: значение"] && [hw.followRedirects.title isEqualToString:@"Следовать перенаправлениям"]);

            hw.section.selectedSegment = 0; [hw sectionChanged:nil];
            [hw.panel orderOut:nil];
            if (savedBefore) [[NSUserDefaults standardUserDefaults] setObject:savedBefore forKey:@"NppHttpRequest"];
            else [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NppHttpRequest"];
            hp.localizationFile = languageBefore ?: @"";
            [app applyLocalization];

            NppHttpRequest *quit = [[NppHttpRequest alloc] init];
            quit.address = [base stringByAppendingString:@"/quit"]; quit.timeout = 3;
            [NppHttpClient send:quit cancelled:nil];
        }
        if (server.isRunning) [server terminate];
    }

    if (NppSectionWanted(@"Macro")) { printf("\n== Macro ==\n");
        SetDoc(ed, @"");
        // checkMacroState: Start / Stop / Playback follow the recording.
        NSMenuItem *startItem = nil, *stopItem = nil, *playItem = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray)
            for (NSMenuItem *it in top.submenu.itemArray) {
                if (it.action == NSSelectorFromString(@"macroStart:")) startItem = it;
                if (it.action == NSSelectorFromString(@"macroStop:")) stopItem = it;
                if (it.action == NSSelectorFromString(@"macroPlay:")) playItem = it;
            }
        id<NSMenuItemValidation> validator = (id<NSMenuItemValidation>)app;
        BOOL idleState = [validator validateMenuItem:startItem] && ![validator validateMenuItem:stopItem] &&
                         ([ed recordedStepCount] > 0) == [validator validateMenuItem:playItem];
        [ed startRecordingMacro];
        BOOL recordingState = ![validator validateMenuItem:startItem] && [validator validateMenuItem:stopItem] &&
                              ![validator validateMenuItem:playItem];
        [ed stopRecordingMacro];
        Check(@"IDM_MACRO_STARTRECORDINGMACRO", @"Start, Stop and Playback are enabled as the recording state says",
              startItem && stopItem && playItem && idleState && recordingState);
        [ed startRecordingMacro];
        BOOL recording = [ed recordingMacro];
        // Drive a couple of recordable actions through Scintilla.
        [sci message:SCI_BEGINUNDOACTION];
        [sci setStringProperty:SCI_REPLACESEL parameter:0 value:@"x"];
        [sci message:SCI_ENDUNDOACTION];
        [ed stopRecordingMacro];
        NSUInteger steps = [ed recordedStepCount];
        Check(@"IDM_MACRO_STARTRECORDINGMACRO", @"records while recording is on",
              recording && steps > 0);
        Check(@"IDM_MACRO_STOPRECORDINGMACRO", @"stops recording", ![ed recordingMacro]);

        NSString *before = DocText(ed);
        BOOL played = [ed playbackMacro:1];
        Check(@"IDM_MACRO_PLAYBACKRECORDEDMACRO", @"replays the recorded steps",
              played && DocText(ed).length > before.length);

        NSUInteger lengthBefore = DocText(ed).length;
        [ed playbackMacro:3];
        Check(@"IDM_MACRO_RUNMULTIMACRODLG", @"replays the requested number of times",
              DocText(ed).length == lengthBefore + 3);

        BOOL saved = [ed saveRecordedMacroAs:@"test macro"];
        Check(@"IDM_MACRO_SAVECURRENTMACRO", @"stores the macro under a name",
              saved && [[ed savedMacroNames] containsObject:@"test macro"]);

        // A string step keeps its text, never the pointer it came with (recordedMacroStep:
        // mtUseSParameter): an empty text, and bytes that are not UTF-8 (what a plugin may send).
        {
            SetDoc(ed, @"abcd");
            [sci message:SCI_SETSEL wParam:0 lParam:2];
            char *bytes = (char *)calloc(8, 1);
            bytes[0] = (char)0xE9;
            [ed startRecordingMacro];
            [sci message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
            [sci setStringProperty:SCI_REPLACESEL parameter:0 value:@""];
            [ed stopRecordingMacro];
            BOOL noPointer = [ed recordedStepCount] == 2;
            for (NSDictionary *step in [[ed valueForKey:@"macroSteps"] copy]) {
                if ([step[@"msg"] intValue] == SCI_REPLACESEL && [step[@"l"] longValue] != 0) noPointer = NO;
            }
            strcpy(bytes, "ZZ");                      // the memory the pointer named now says something else
            SetDoc(ed, @"abcd");
            [sci message:SCI_SETSEL wParam:0 lParam:2];
            [ed playbackMacro:1];
            NSString *replayed = DocText(ed);
            free(bytes);
            printf("    string steps: pointer kept %d, replayed \"%s\"\n", !noPointer, replayed.UTF8String);
            Check(@"IDM_MACRO_PLAYBACKRECORDEDMACRO (string steps)",
                  @"a recorded string message replays its own text, empty or not UTF-8, never the address it was recorded from",
                  noPointer && [replayed isEqualToString:@"\u00E9cd"]);
        }
    }

    if (NppSectionWanted(@"Window")) { printf("\n== Window ==\n");
        NSError *err = nil;
        [ed closeAllDocuments];
        // Names, extensions and sizes all differ, so each sort key is distinguishable.
        [ed openFileAtPath:TempFile(@"w_charlie.txt", @"ccc\n") error:&err];
        [ed openFileAtPath:TempFile(@"w_alpha.md",    @"a\n")   error:&err];
        [ed openFileAtPath:TempFile(@"w_bravo.py",    @"bb\n")  error:&err];

        struct { NppTabSort key; BOOL asc; NSString *cmd; } sorts[] = {
            {NppTabSortName,          YES, @"IDM_WINDOW_SORT_FN_ASC"},
            {NppTabSortName,          NO,  @"IDM_WINDOW_SORT_FN_DSC"},
            {NppTabSortPath,          YES, @"IDM_WINDOW_SORT_FP_ASC"},
            {NppTabSortPath,          NO,  @"IDM_WINDOW_SORT_FP_DSC"},
            {NppTabSortType,          YES, @"IDM_WINDOW_SORT_FT_ASC"},
            {NppTabSortType,          NO,  @"IDM_WINDOW_SORT_FT_DSC"},
            {NppTabSortContentLength, YES, @"IDM_WINDOW_SORT_FS_ASC"},
            {NppTabSortContentLength, NO,  @"IDM_WINDOW_SORT_FS_DSC"},
            {NppTabSortModifiedTime,  YES, @"IDM_WINDOW_SORT_FD_ASC"},
            {NppTabSortModifiedTime,  NO,  @"IDM_WINDOW_SORT_FD_DSC"},
        };
        for (size_t i = 0; i < sizeof(sorts)/sizeof(sorts[0]); ++i) {
            [ed sortTabsBy:sorts[i].key ascending:sorts[i].asc];
            NSMutableArray *names = [NSMutableArray array], *languages = [NSMutableArray array];
            for (NppDocument *d in ed.documents) if (d.path) { [names addObject:d.displayName]; [languages addObject:d.language.name ?: @""]; }

            BOOL ordered = YES;
            for (NSUInteger n = 1; n < names.count; ++n) {
                NSComparisonResult r;
                switch (sorts[i].key) {
                    case NppTabSortType:   // the language's name, as WindowsDlg's BufferEquivalent
                        r = [languages[n - 1] caseInsensitiveCompare:languages[n]];
                        break;
                    case NppTabSortContentLength: {
                        NSString *a = names[n - 1], *b = names[n];
                        unsigned long long sa = [a hasSuffix:@".md"] ? 2 : ([a hasSuffix:@".py"] ? 3 : 4);
                        unsigned long long sb = [b hasSuffix:@".md"] ? 2 : ([b hasSuffix:@".py"] ? 3 : 4);
                        r = sa == sb ? NSOrderedSame : (sa < sb ? NSOrderedAscending : NSOrderedDescending);
                        break;
                    }
                    case NppTabSortModifiedTime:
                        r = NSOrderedSame;      // all written within the same moment
                        break;
                    default:
                        r = [names[n - 1] compare:names[n]];
                        break;
                }
                if (r == NSOrderedSame) continue;
                if (sorts[i].asc ? (r == NSOrderedDescending) : (r == NSOrderedAscending)) ordered = NO;
            }
            Check(sorts[i].cmd, @"orders the tabs by that key", ordered && names.count == 3);
        }

        Check(@"IDM_WINDOW_WINDOWS", @"lists every open document",
              [ed windowList].count == ed.documents.count);

        [ed selectDocumentAtIndex:0];
        [ed selectDocumentAtIndex:2];
        BOOL recent = [ed activateRecentWindow];
        Check(@"IDM_WINDOW_MRU_FIRST", @"returns to the previously active tab",
              recent && [ed.documents indexOfObject:ed.currentDocument] == 0);
        Check(@"IDM_DROPLIST_LIST", @"the droplist offers the same window list",
              [ed windowList].count == ed.documents.count);
    }

    if (NppSectionWanted(@"Run and Help")) { printf("\n== Run and Help ==\n");
        // Regression: this used to wait with -waitUntilExit, which spins the run
        // loop on the main thread and could abort inside AppKit. Repeating the
        // call makes that crash reproducible rather than occasional.
        BOOL allOK = YES;
        for (int i = 0; i < 8 && allOK; ++i) {
            NSString *out = [ed runShellCommand:@"printf ran-ok"];
            allOK = [out isEqualToString:@"ran-ok"];
        }
        Check(@"IDM_EXECUTE", @"runs a command and returns its output, repeatedly", allOK);

        NSString *report = [ed validateShortcutsFile];
        Check(@"IDM_EXECUTE_VALIDATE_SHORTCUTSXML", @"reports on the menu shortcuts",
              [report containsString:@"shortcuts"]);
        Check(@"IDM_EXECUTE_VALIDATE_SHORTCUTSXML (clean)", @"a clean profile has no duplicates (the hidden alternate Full Screen is not one)",
              [report containsString:@"no duplicates"]);
        Check(@"IDM_EXECUTE_VALIDATE_SHORTCUTSXML (menu)", @"the command has its menu item, by id",
              [app.shortcutStore menuItemsByIdentifier][@49001] != nil);

        // The command line reaches the shell as written: é precomposed, not e + U+0301.
        NSString *bytes = [ed runCommandLine:@"printf %s 'é' | od -An -tx1 | tr -d ' \\n'" intoConsole:NO].output;
        Check(@"IDM_EXECUTE (UTF-8)", @"a non-ASCII command reaches the shell precomposed (NFC)",
              [bytes isEqualToString:@"c3a9"]);

        // A document line with backquotes stays text inside `...` (it used to run).
        SetDoc(ed, @"x`printf INJ`y\n");
        [sci message:SCI_GOTOPOS wParam:0 lParam:0];
        NSString *quoted = [ed runCommandLine:@"printf %s \"`printf %s $(CURRENT_LINESTR)`\"" intoConsole:NO].output;
        Check(@"IDM_EXECUTE (backquotes)", @"$(CURRENT_LINESTR) inside backquotes is text, not a command",
              [quoted isEqualToString:@"x`printf INJ`y"]);

        NSString *dbg = [ed debugInfo];
        BOOL fields = YES;
        for (NSString *field in @[@"Notepad++ v", @"Build time: ", @"Built with: Clang ", @"Scintilla/Lexilla included: 5.",
                                  @"Path: ", @"Command Line: ", @"Admin mode: OFF", @"Local Conf mode: ", @"Cloud Config: ",
                                  @"Periodic Backup: ", @"Multi-instance Mode: ", @"File Status Auto-Detection: ",
                                  @"Dark Mode: ", @"Display Info:", @"primary monitor: ", @"OS Name: macOS", @"OS Version: ",
                                  @"OS Build: ", @"Current ANSI codepage: ", @"Plugins: none"]) {
            if (![dbg containsString:field]) { fields = NO; printf("    debug info lacks %s\n", field.UTF8String); }
        }
        NppDebugInfoWindow *dw = [NppDebugInfoWindow shared];
        [dw showText:dbg];
        [dw copyToClipboard:nil];
        BOOL copied = [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:dbg];
        [dw.panel orderOut:nil];
        Check(@"IDM_DEBUGINFO", @"upstream's fields, in a window that copies them to the clipboard",
              fields && copied && [dbg rangeOfString:@"Build time"].location < [dbg rangeOfString:@"OS Name"].location);

        // The updater: versions, GitHub's answer, the proxy and the schedule.
        BOOL versions = [NppUpdateChecker compareVersion:@"v8.9.8" to:@"8.9.7"] == NSOrderedDescending &&
                        [NppUpdateChecker compareVersion:@"8.10" to:@"8.9.8"] == NSOrderedDescending &&
                        [NppUpdateChecker compareVersion:@"8.9" to:@"8.9.0"] == NSOrderedSame &&
                        [NppUpdateChecker compareVersion:@"8.9.8-mac1" to:@"8.9.8-mac2"] == NSOrderedAscending;
        NSData *json = [@"{\"tag_name\":\"v9.1.2\",\"name\":\"Notepad++ 9.1.2 for macOS\","
                        @"\"html_url\":\"https://github.com/o/r/releases/tag/v9.1.2\",\"body\":\"notes\"}"
                        dataUsingEncoding:NSUTF8StringEncoding];
        NppRelease *rel = [NppUpdateChecker releaseFromJSON:json];
        BOOL parsed = [rel.version isEqualToString:@"9.1.2"] && [rel.name hasSuffix:@"macOS"] &&
                      [rel.pageURL.host isEqualToString:@"github.com"] &&
                      ![NppUpdateChecker releaseFromJSON:[@"{\"message\":\"Not Found\"}" dataUsingEncoding:NSUTF8StringEncoding]];
        NSDictionary *proxy = [NppUpdateChecker proxyDictionaryFor:@"http://proxy.example:8080/"];
        BOOL proxied = [proxy[@"HTTPSProxy"] isEqualToString:@"proxy.example"] && [proxy[@"HTTPSPort"] intValue] == 8080 &&
                       [NppUpdateChecker proxyDictionaryFor:@""].count == 0;
        NppPreferences *up = [NppPreferences shared];
        NSString *nextBefore = up.nextUpdateDate;
        NSInteger intervalBefore = up.updateIntervalDays;
        up.nextUpdateDate = @"";
        up.updateIntervalDays = 15;
        BOOL firstDue = [app takeScheduledUpdateCheck];
        NSString *next = up.nextUpdateDate;
        BOOL thenWaits = ![app takeScheduledUpdateCheck];
        NSDate *in15 = [NSDate dateWithTimeIntervalSinceNow:15 * 86400 + 3600];
        BOOL schedule = firstDue && thenWaits && next.length == 8 &&
                        [NppUpdateChecker isDueOn:in15 next:next] && ![NppUpdateChecker isDueOn:[NSDate date] next:next] &&
                        ![app automaticUpdateCheckAllowed];
        up.nextUpdateDate = nextBefore ?: @"";
        up.updateIntervalDays = intervalBefore;
        // A fetch, from a file standing in for api.github.com.
        NSString *answer = TempFile(@"t_release.json", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
        NppUpdateChecker.latestReleaseURLOverride = [NSURL fileURLWithPath:answer];
        __block NppRelease *fetched = nil;
        __block BOOL fetchDone = NO;
        [NppUpdateChecker fetchLatest:^(NppRelease *r, NSError *e) { fetched = r; fetchDone = YES; }];
        NSDate *fetchLimit = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!fetchDone && [fetchLimit timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        NppUpdateChecker.latestReleaseURLOverride = nil;
        BOOL fetchedOK = [fetched.version isEqualToString:@"9.1.2"] &&
                         [NppUpdateChecker compareVersion:fetched.version to:[NppUpdateChecker currentVersion]] == NSOrderedDescending &&
                         [[NppUpdateChecker latestReleaseURL].absoluteString hasPrefix:@"https://api.github.com/repos/"];
        printf("    update: versions=%d parsed=%d proxy=%d schedule=%d fetch=%d current=%s\n", versions, parsed, proxied,
               schedule, fetchedOK, [NppUpdateChecker currentVersion].UTF8String);
        Check(@"IDM_UPDATE_NPP", @"asks GitHub Releases through the proxy, compares versions and keeps upstream's interval",
              versions && parsed && proxied && schedule && fetchedOK);

        Check(@"IDM_CMDLINEARGUMENTS", @"documents the accepted arguments",
              [[ed commandLineArgumentsHelp] containsString:@"NPPMAC_TEST"]);

        // Opening browsers from a test would be rude; what is looked at is where each command would go.
        // The port is released and supported from its own repository - the one Check for Updates asks -
        // so Home, Project Page and Forum lead there, and nothing leads to Notepad++'s site or forum.
        NSString *repository = [@"https://github.com/" stringByAppendingString:[NppPreferences shared].updateRepository];
        NSDictionary *links = @{@"IDM_HOMESWEETHOME": [repository stringByAppendingString:@"#readme"],
                                @"IDM_PROJECTPAGE":   repository,
                                @"IDM_ONLINEDOCUMENT":@"https://npp-user-manual.org/",
                                @"IDM_FORUM":         [repository stringByAppendingString:@"/discussions"]};
        NSDictionary<NSNumber *, NSMenuItem *> *helpItems = [app.shortcutStore menuItemsByIdentifier];
        NSDictionary *helpIDs = @{@"IDM_HOMESWEETHOME": @47001, @"IDM_PROJECTPAGE": @47002, @"IDM_ONLINEDOCUMENT": @47003, @"IDM_FORUM": @47004};
        for (NSString *cmd in links) {
            NSURL *u = [NSURL URLWithString:links[cmd]];
            NSMenuItem *item = helpItems[helpIDs[cmd]];
            Check(cmd, @"leads to this port's own repository (the manual, to the manual), over https",
                  u != nil && [u.scheme isEqualToString:@"https"] && u.host.length > 0 &&
                  [item.representedObject isEqualToString:links[cmd]]);
        }
        BOOL noneUpstream = YES;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![NppEnglishMenuTitle(top.submenu) isEqualToString:@"Help"] && ![NppEnglishMenuTitle(top.submenu) isEqualToString:@"?"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                NSString *to = [mi.representedObject isKindOfClass:[NSString class]] ? mi.representedObject : @"";
                if ([to containsString:@"notepad-plus-plus.org"] || [to containsString:@"github.com/notepad-plus-plus/"]) noneUpstream = NO;
            }
        }
        Check(@"Help (whose it is)", @"no command of the Help menu sends a user of the Mac version to Notepad++'s site, forum or repository", noneUpstream);

        [[NSUserDefaults standardUserDefaults] setObject:@"proxy.example:8080" forKey:@"NppMacUpdaterProxy"];
        Check(@"IDM_CONFUPDATERPROXY", @"remembers the proxy setting",
              [[[NSUserDefaults standardUserDefaults] stringForKey:@"NppMacUpdaterProxy"]
                  isEqualToString:@"proxy.example:8080"]);

        NSMenuItem *about = nil;
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
            if (![top.submenu.title isEqualToString:@"Help"]) continue;
            for (NSMenuItem *mi in top.submenu.itemArray) {
                if ([mi.title hasPrefix:@"About"]) about = mi;
            }
        }
        NppAboutWindow *aw = [NppAboutWindow shared];
        [aw show];
        BOOL versionShown = NO, licenceShown = NO, homeLink = NO, issuesLink = NO, upstreamLink = NO;
        NSMutableArray *views = [NSMutableArray arrayWithObject:aw.panel.contentView];
        while (views.count) {
            NSView *view = views.lastObject; [views removeLastObject];
            [views addObjectsFromArray:view.subviews];
            if ([view isKindOfClass:[NSTextField class]] && [((NSTextField *)view).stringValue isEqualToString:[NppAboutWindow versionLine]]) versionShown = YES;
            if ([view isKindOfClass:[NSTextView class]] && [((NSTextView *)view).string isEqualToString:NppLicenceText]) licenceShown = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier isEqualToString:NppProjectAddress(@"")]) homeLink = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier isEqualToString:NppProjectAddress(@"issues")]) issuesLink = YES;
            if ([view isKindOfClass:[NSButton class]] && [view.identifier containsString:@"notepad-plus-plus.org"]) upstreamLink = YES;
        }
        BOOL shown = aw.panel.isVisible;
        [aw.panel orderOut:nil];
        Check(@"IDM_ABOUT", @"upstream's About box: version and bitness, build time and the licence - with this port's own repository "
              @"and its Issues where upstream has its site, and no link to Notepad++'s",
              about != nil && about.action == @selector(showAbout:) && shown && versionShown && licenceShown && homeLink && issuesLink && !upstreamLink &&
              [[NppAboutWindow versionLine] containsString:[NppAboutWindow bitness]]);

        NSString *pluginDir = [ed.defaultSessionPath.stringByDeletingLastPathComponent
                               stringByAppendingPathComponent:@"plugins"];
        [[NSFileManager defaultManager] createDirectoryAtPath:pluginDir
                                  withIntermediateDirectories:YES attributes:nil error:NULL];
        Check(@"IDM_SETTING_OPENPLUGINSDIR", @"has a plugins folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:pluginDir]);
    }
}

/// == Mac extras: OCR, QR, the command line ==
void NppTestsMacExtras(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Mac extras: OCR, QR, the command line")) { printf("\n== Mac extras: OCR, QR, the command line ==\n");
        // OCR over a picture drawn right here: big black words on white.
        NSImage *picture = [[NSImage alloc] initWithSize:NSMakeSize(640, 140)];
        [picture lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 140));
        [@"HELLO OCR 42" drawAtPoint:NSMakePoint(24, 36) withAttributes:
            @{NSFontAttributeName: [NSFont boldSystemFontOfSize:56],
              NSForegroundColorAttributeName: [NSColor blackColor]}];
        [picture unlockFocus];
        NSString *seen = [EditorController textRecognizedInImage:picture];
        Check(@"OCR reads a picture", @"the system engine returns the words drawn into the image",
              [seen containsString:@"HELLO"] && [seen containsString:@"42"]);

        // The same engine over files: a PNG written to disk, and a PDF drawn
        // right here, page rendered and read back.
        NSString *pngPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ocr.png"];
        CGImageRef pictureCG = [picture CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *pictureRep = [[NSBitmapImageRep alloc] initWithCGImage:pictureCG];
        [[pictureRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
            writeToFile:pngPath atomically:YES];
        NSString *fromPNG = [EditorController textRecognizedInFileAt:pngPath];

        NSString *pdfPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_ocr.pdf"];
        NSMutableData *pdfData = [NSMutableData data];
        CGRect page = CGRectMake(0, 0, 612, 200);
        CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData((__bridge CFMutableDataRef)pdfData);
        CGContextRef pdfCtx = CGPDFContextCreate(consumer, &page, NULL);
        CGDataConsumerRelease(consumer);
        CGPDFContextBeginPage(pdfCtx, NULL);
        NSGraphicsContext *old = NSGraphicsContext.currentContext;
        NSGraphicsContext.currentContext =
            [NSGraphicsContext graphicsContextWithCGContext:pdfCtx flipped:NO];
        [@"PDF PAGE WORDS 7" drawAtPoint:NSMakePoint(40, 80) withAttributes:
            @{NSFontAttributeName: [NSFont boldSystemFontOfSize:40],
              NSForegroundColorAttributeName: [NSColor blackColor]}];
        NSGraphicsContext.currentContext = old;
        CGPDFContextEndPage(pdfCtx);
        CGPDFContextClose(pdfCtx);
        CGContextRelease(pdfCtx);
        [pdfData writeToFile:pdfPath atomically:YES];
        NSString *fromPDF = [EditorController textRecognizedInFileAt:pdfPath];
        Check(@"Recognize Text in File", @"a PNG on disk and a rendered PDF page both give their words back",
              [fromPNG containsString:@"HELLO"] &&
              [fromPDF containsString:@"PDF"] && [fromPDF containsString:@"7"]);

        // Paste Image as Text: through the clipboard, into the document.
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb writeObjects:@[picture]];
        [ed newDocument];
        SetDoc(ed, @"");
        BOOL pasted = [ed pasteImageAsText];
        Check(@"Paste Image as Text", @"the clipboard's image lands as its words",
              pasted && [DocText(ed) containsString:@"HELLO"]);

        // QR both ways: the selection becomes a code, the code reads back.
        NSString *payload = @"https://github.com/tanderbold/NotepadMac?ref=qr&n=42";
        NSImage *qr = [EditorController qrImageFromText:payload side:300];
        Check(@"QR generation", @"the selection becomes a rendered code (software Core Image, so headless too)",
              qr != nil && qr.size.width >= 250);   // 300 asked, whole-module scaling lands just under
        Check(@"QR round trip", @"the code made from a text answers that very text",
              qr && [[EditorController textFromQRCodesInImage:qr] isEqualToString:payload]);
        NSMutableString *tooLong = [NSMutableString string];
        for (int i = 0; i < 4000; ++i) [tooLong appendString:@"x"];
        Check(@"QR refuses what cannot fit", @"a text past the format's end answers nil",
              [EditorController qrImageFromText:tooLong side:300] == nil);

        [pb clearContents];
        [pb writeObjects:@[qr]];
        SetDoc(ed, @"");
        BOOL read = [ed insertTextFromClipboardQR];
        Check(@"Read QR Code from Clipboard", @"the clipboard's code lands as its text",
              read && [DocText(ed) isEqualToString:payload]);

        // The command line tool: shipped, and its ask is honoured with a line.
        NSString *helper = [[NSBundle mainBundle].bundlePath
                            stringByAppendingPathComponent:@"Contents/Helpers/nppmac"];
        NSTask *help = [[NSTask alloc] init];
        help.executableURL = [NSURL fileURLWithPath:helper];
        help.arguments = @[@"--help"];
        help.standardError = [NSPipe pipe];
        BOOL ran = [help launchAndReturnError:NULL];
        [help waitUntilExit];
        NSString *cliFile = TempFile(@"t_cli.txt", @"one\ntwo\nthree\nfour\nfive\n");
        [app cliRequest:[NSNotification notificationWithName:@"org.notepad-plus-plus.mac.cli" object:nil
            userInfo:@{@"files": @[@{@"path": cliFile, @"line": @4}]}]];
        long cliLine = [ed.sci message:SCI_LINEFROMPOSITION
                                wParam:(uptr_t)[ed.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
        Check(@"nppmac asks, the app answers", @"the helper ships and its request opens the file at the line",
              ran && help.terminationStatus == 0 &&
              [ed.currentDocument.path isEqualToString:cliFile] && cliLine == 3);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument]
                  discardChanges:YES];
    }
}
