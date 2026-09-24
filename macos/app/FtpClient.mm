#import "FtpClient.h"
#import <Security/Security.h>
#include <curl/curl.h>

#pragma mark - Profile

@implementation NppFtpProfile

+ (instancetype)profileFromDictionary:(NSDictionary *)dict {
    NppFtpProfile *p = [[NppFtpProfile alloc] init];
    p.name = dict[@"name"] ?: @"";
    p.protocol = (NppFtpProtocol)[dict[@"protocol"] integerValue];
    p.host = dict[@"host"] ?: @"";
    p.port = [dict[@"port"] integerValue];
    p.username = dict[@"username"] ?: @"";
    p.initialDirectory = dict[@"initialDirectory"] ?: @"/";
    return p;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{@"name": self.name ?: @"", @"protocol": @(self.protocol),
             @"host": self.host ?: @"", @"port": @(self.port),
             @"username": self.username ?: @"",
             @"initialDirectory": self.initialDirectory ?: @"/"};
}

- (NSInteger)effectivePort {
    if (self.port > 0) return self.port;
    return self.protocol == NppFtpSFTP ? 22 : 21;
}

- (NSString *)urlForPath:(NSString *)path {
    NSString *clean = path.length ? path : @"/";
    if (![clean hasPrefix:@"/"]) clean = [@"/" stringByAppendingString:clean];
    // Every character a URL reads - space, #, ?, % - is encoded, and an FTP
    // path is made absolute: in ftp://host/dir the dir is relative to the
    // login home, and only %2F in front of it means the root.
    NSString *encoded = [[clean substringFromIndex:1]
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]
        ?: [clean substringFromIndex:1];
    // libcurl takes ftp:// for both plain and TLS; TLS is requested separately.
    NSString *scheme = self.protocol == NppFtpSFTP ? @"sftp" : @"ftp";
    NSString *root = self.protocol == NppFtpSFTP ? @"/" : @"/%2F";
    return [NSString stringWithFormat:@"%@://%@:%ld%@%@",
            scheme, self.host ?: @"", (long)[self effectivePort], root, encoded];
}

@end

@implementation NppFtpEntry
@end

#pragma mark - Client

@interface NppFtpClient ()
@property (nonatomic, strong) NppFtpProfile *profileStorage;
@end

@implementation NppFtpClient

- (instancetype)initWithProfile:(NppFtpProfile *)profile {
    if (!(self = [super init])) return nil;
    _profileStorage = profile;
    return self;
}

- (NppFtpProfile *)profile { return self.profileStorage; }

#pragma mark - Keychain

+ (NSDictionary *)keychainQueryForProfile:(NppFtpProfile *)profile {
    return @{(__bridge id)kSecClass:        (__bridge id)kSecClassInternetPassword,
             (__bridge id)kSecAttrServer:   profile.host ?: @"",
             (__bridge id)kSecAttrAccount:  profile.username ?: @"",
             (__bridge id)kSecAttrPort:     @([profile respondsToSelector:@selector(port)] ? profile.port : 0),
             (__bridge id)kSecAttrProtocol: (__bridge id)(profile.protocol == NppFtpSFTP
                                                          ? kSecAttrProtocolSSH
                                                          : kSecAttrProtocolFTP)};
}

+ (BOOL)storePassword:(NSString *)password forProfile:(NppFtpProfile *)profile {
    if (!profile.host.length) return NO;
    [self removePasswordForProfile:profile];
    NSMutableDictionary *item = [[self keychainQueryForProfile:profile] mutableCopy];
    item[(__bridge id)kSecValueData] = [password dataUsingEncoding:NSUTF8StringEncoding];
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

+ (NSString *)passwordForProfile:(NppFtpProfile *)profile {
    NSMutableDictionary *query = [[self keychainQueryForProfile:profile] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

+ (BOOL)removePasswordForProfile:(NppFtpProfile *)profile {
    return SecItemDelete((__bridge CFDictionaryRef)[self keychainQueryForProfile:profile]) == errSecSuccess;
}

#pragma mark - Listing

/// Servers answer LIST in one of two layouts. The Unix one starts with a
/// permission string; the DOS one starts with a date and marks directories with
/// "<DIR>". Both appear in the wild, so both are handled.
+ (NSArray<NppFtpEntry *> *)parseListing:(NSString *)listing {
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *raw in [listing componentsSeparatedByCharactersInSet:
                           [NSCharacterSet newlineCharacterSet]]) {
        // sftp in batch mode echoes each command as "sftp> ..." - not an entry.
        if ([raw hasPrefix:@"sftp>"]) continue;
        NSString *line = [raw stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        if (line.length < 4) continue;

        NSMutableArray *fields = [NSMutableArray array];
        for (NSString *f in [line componentsSeparatedByCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]]) {
            if (f.length) [fields addObject:f];
        }
        if (fields.count < 4) continue;

        NppFtpEntry *entry = [[NppFtpEntry alloc] init];
        unichar first = [line characterAtIndex:0];

        if (first == 'd' || first == '-' || first == 'l') {
            // Unix: perms links owner group size month day time name
            if (fields.count < 9) continue;
            entry.isDirectory = (first == 'd');
            entry.size = [fields[4] longLongValue];
            NSArray *nameParts = [fields subarrayWithRange:NSMakeRange(8, fields.count - 8)];
            entry.name = [nameParts componentsJoinedByString:@" "];
            // A symlink is written "name -> target"; only the name is wanted.
            NSRange arrow = [entry.name rangeOfString:@" -> "];
            if (arrow.location != NSNotFound) entry.name = [entry.name substringToIndex:arrow.location];
        } else {
            // DOS: date time <DIR>|size name
            entry.isDirectory = [fields[2] isEqualToString:@"<DIR>"];
            entry.size = entry.isDirectory ? 0 : [fields[2] longLongValue];
            NSArray *nameParts = [fields subarrayWithRange:NSMakeRange(3, fields.count - 3)];
            entry.name = [nameParts componentsJoinedByString:@" "];
        }

        if (!entry.name.length) continue;
        if ([entry.name isEqualToString:@"."] || [entry.name isEqualToString:@".."]) continue;
        [entries addObject:entry];
    }
    return entries;
}

#pragma mark - Transfers

static size_t AppendToData(void *buffer, size_t size, size_t count, void *context) {
    NSMutableData *data = (__bridge NSMutableData *)context;
    [data appendBytes:buffer length:size * count];
    return size * count;
}

struct NppUploadSource { const uint8_t *bytes; size_t length; size_t offset; };

static size_t ReadFromData(void *buffer, size_t size, size_t count, void *context) {
    struct NppUploadSource *source = (struct NppUploadSource *)context;
    size_t wanted = size * count;
    size_t left = source->length - source->offset;
    size_t give = wanted < left ? wanted : left;
    if (give) {
        memcpy(buffer, source->bytes + source->offset, give);
        source->offset += give;
    }
    return give;
}

/// Shared setup: credentials, TLS and timeouts.
- (void)configure:(CURL *)curl forURL:(NSString *)url {
    curl_easy_setopt(curl, CURLOPT_URL, url.UTF8String);
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 15L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 120L);
    curl_easy_setopt(curl, CURLOPT_FTP_RESPONSE_TIMEOUT, 30L);

    NSString *password = self.password ?: [NppFtpClient passwordForProfile:self.profile] ?: @"";
    NSString *login = [NSString stringWithFormat:@"%@:%@", self.profile.username ?: @"", password];
    curl_easy_setopt(curl, CURLOPT_USERPWD, login.UTF8String);

    if (self.profile.protocol == NppFtpTLS) {
        // Explicit TLS: connect in the clear, then upgrade, which is what
        // "FTPS" means for the servers NppFTP talks to.
        curl_easy_setopt(curl, CURLOPT_USE_SSL, (long)CURLUSESSL_ALL);
    }
}

- (BOOL)isSFTP { return self.profile.protocol == NppFtpSFTP; }

/// Apple's libcurl has no libssh2, so SFTP goes through the system client.
- (nullable NSString *)runSFTPBatch:(NSString *)commands {
    NSString *script = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"nppmac_sftp_%@.txt", [NSUUID UUID].UUIDString]];
    if (![commands writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
        self.lastError = @"Cannot write the SFTP batch file.";
        return nil;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sftp"];
    // BatchMode means no password prompt: SFTP here relies on an SSH key, which
    // is how a non-interactive client has to work.
    // ConnectTimeout bounds the TCP connect and the SSH banner exchange: a port that
    // does not speak SSH (an FTP server answering "220 ...") otherwise keeps ssh
    // waiting for "SSH-" for ever, and the application with it. 15 s as curl's
    // CURLOPT_CONNECTTIMEOUT above; ServerAlive ends a connection that goes silent.
    task.arguments = @[@"-b", script,
                       @"-o", @"BatchMode=yes",
                       @"-o", @"StrictHostKeyChecking=accept-new",
                       @"-o", @"ConnectTimeout=15",
                       @"-o", @"ServerAliveInterval=15",
                       @"-o", @"ServerAliveCountMax=2",
                       @"-P", [@([self.profile respondsToSelector:@selector(port)]
                                 ? (self.profile.port > 0 ? self.profile.port : 22) : 22) stringValue],
                       [NSString stringWithFormat:@"%@@%@", self.profile.username ?: @"",
                        self.profile.host ?: @""]];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        self.lastError = launchError.localizedDescription;
        return nil;
    }
    // As with Run…, completion is awaited on a semaphore rather than by
    // spinning the run loop, which would re-enter AppKit.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) { dispatch_semaphore_signal(done); };
    // Whatever else keeps sftp from finishing, reading its output must not wait longer
    // than curl's CURLOPT_TIMEOUT: the batch is stopped, the pipe closes, the read returns.
    __weak NSTask *weakTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (weakTask.isRunning) [weakTask terminate];
    });
    NSData *out = [pipe.fileHandleForReading readDataToEndOfFile];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
    [[NSFileManager defaultManager] removeItemAtPath:script error:NULL];

    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus != 0) {
        self.lastError = text.length ? text : @"The SFTP command failed.";
        return nil;
    }
    return text;
}

- (NSArray<NppFtpEntry *> *)listDirectory:(NSString *)path {
    self.lastError = nil;
    if ([self isSFTP]) {
        NSString *out = [self runSFTPBatch:[NSString stringWithFormat:@"ls -l \"%@\"\n", path]];
        return out ? [NppFtpClient parseListing:out] : nil;
    }

    CURL *curl = curl_easy_init();
    if (!curl) { self.lastError = @"Cannot start a transfer."; return nil; }

    NSString *url = [self.profile urlForPath:path];
    if (![url hasSuffix:@"/"]) url = [url stringByAppendingString:@"/"];
    [self configure:curl forURL:url];

    NSMutableData *buffer = [NSMutableData data];
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AppendToData);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (__bridge void *)buffer);

    CURLcode code = curl_easy_perform(curl);
    curl_easy_cleanup(curl);
    if (code != CURLE_OK) { self.lastError = @(curl_easy_strerror(code)); return nil; }

    NSString *listing = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding]
                     ?: [[NSString alloc] initWithData:buffer encoding:NSISOLatin1StringEncoding];
    return [NppFtpClient parseListing:listing ?: @""];
}

- (NSData *)downloadFileAtPath:(NSString *)path {
    self.lastError = nil;
    if ([self isSFTP]) {
        NSString *local = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"nppmac_dl_%@", path.lastPathComponent]];
        NSString *out = [self runSFTPBatch:
            [NSString stringWithFormat:@"get \"%@\" \"%@\"\n", path, local]];
        if (!out) return nil;
        NSData *data = [NSData dataWithContentsOfFile:local];
        [[NSFileManager defaultManager] removeItemAtPath:local error:NULL];
        if (!data) self.lastError = @"The file did not arrive.";
        return data;
    }

    CURL *curl = curl_easy_init();
    if (!curl) { self.lastError = @"Cannot start a transfer."; return nil; }
    [self configure:curl forURL:[self.profile urlForPath:path]];

    NSMutableData *buffer = [NSMutableData data];
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AppendToData);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (__bridge void *)buffer);

    CURLcode code = curl_easy_perform(curl);
    curl_easy_cleanup(curl);
    if (code != CURLE_OK) { self.lastError = @(curl_easy_strerror(code)); return nil; }
    return buffer;
}

- (BOOL)uploadData:(NSData *)data toPath:(NSString *)path {
    self.lastError = nil;
    if ([self isSFTP]) {
        NSString *local = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"nppmac_ul_%@", path.lastPathComponent]];
        if (![data writeToFile:local atomically:YES]) {
            self.lastError = @"Cannot stage the file for upload.";
            return NO;
        }
        NSString *out = [self runSFTPBatch:
            [NSString stringWithFormat:@"put \"%@\" \"%@\"\n", local, path]];
        [[NSFileManager defaultManager] removeItemAtPath:local error:NULL];
        return out != nil;
    }

    CURL *curl = curl_easy_init();
    if (!curl) { self.lastError = @"Cannot start a transfer."; return NO; }
    [self configure:curl forURL:[self.profile urlForPath:path]];

    struct NppUploadSource source = {(const uint8_t *)data.bytes, data.length, 0};
    curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);
    curl_easy_setopt(curl, CURLOPT_READFUNCTION, ReadFromData);
    curl_easy_setopt(curl, CURLOPT_READDATA, &source);
    curl_easy_setopt(curl, CURLOPT_INFILESIZE_LARGE, (curl_off_t)data.length);
    // Create any missing directories, as an editor saving a path expects.
    curl_easy_setopt(curl, CURLOPT_FTP_CREATE_MISSING_DIRS, (long)CURLFTP_CREATE_DIR);

    CURLcode code = curl_easy_perform(curl);
    curl_easy_cleanup(curl);
    if (code != CURLE_OK) { self.lastError = @(curl_easy_strerror(code)); return NO; }
    return YES;
}

- (BOOL)deleteFileAtPath:(NSString *)path {
    self.lastError = nil;
    if ([self isSFTP]) {
        return [self runSFTPBatch:[NSString stringWithFormat:@"rm \"%@\"\n", path]] != nil;
    }

    CURL *curl = curl_easy_init();
    if (!curl) { self.lastError = @"Cannot start a transfer."; return NO; }
    // Deleting is a command sent against the containing directory.
    NSString *directory = path.stringByDeletingLastPathComponent;
    NSString *url = [self.profile urlForPath:directory];
    if (![url hasSuffix:@"/"]) url = [url stringByAppendingString:@"/"];
    [self configure:curl forURL:url];

    NSString *command = [NSString stringWithFormat:@"DELE %@", path.lastPathComponent];
    struct curl_slist *commands = curl_slist_append(NULL, command.UTF8String);
    curl_easy_setopt(curl, CURLOPT_POSTQUOTE, commands);
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);

    CURLcode code = curl_easy_perform(curl);
    curl_slist_free_all(commands);
    curl_easy_cleanup(curl);
    if (code != CURLE_OK) { self.lastError = @(curl_easy_strerror(code)); return NO; }
    return YES;
}

@end
