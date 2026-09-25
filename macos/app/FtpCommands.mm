#import "FtpCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

static const char kFtpClientKey = 0;
static char kFtpConnectErrorKey;
static const char kFtpDirectoryKey = 0;
static const char kFtpRemotePathsKey = 0;   // local temp path -> @[server, remote path]

@implementation EditorController (FtpCommands)

#pragma mark - Profiles

- (NSArray<NppFtpProfile *> *)ftpProfiles {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *dict in [NppPreferences shared].ftpProfiles ?: @[]) {
        [out addObject:[NppFtpProfile profileFromDictionary:dict]];
    }
    return out;
}

- (void)saveFtpProfile:(NppFtpProfile *)profile {
    if (!profile.name.length) return;
    NSMutableArray *stored = [([NppPreferences shared].ftpProfiles ?: @[]) mutableCopy];
    NSUInteger existing = NSNotFound;
    for (NSUInteger i = 0; i < stored.count; ++i) {
        if ([stored[i][@"name"] isEqualToString:profile.name]) { existing = i; break; }
    }
    if (existing == NSNotFound) [stored addObject:profile.dictionaryRepresentation];
    else stored[existing] = profile.dictionaryRepresentation;
    [NppPreferences shared].ftpProfiles = stored;
}

- (void)removeFtpProfileNamed:(NSString *)name {
    NSMutableArray *stored = [([NppPreferences shared].ftpProfiles ?: @[]) mutableCopy];
    NSUInteger found = NSNotFound;
    for (NSUInteger i = 0; i < stored.count; ++i) {
        if ([stored[i][@"name"] isEqualToString:name]) { found = i; break; }
    }
    if (found == NSNotFound) return;
    NppFtpProfile *profile = [NppFtpProfile profileFromDictionary:stored[found]];
    [NppFtpClient removePasswordForProfile:profile];   // the password goes with it
    [stored removeObjectAtIndex:found];
    [NppPreferences shared].ftpProfiles = stored;
}

- (NppFtpProfile *)ftpProfileNamed:(NSString *)name {
    for (NppFtpProfile *p in [self ftpProfiles]) {
        if ([p.name isEqualToString:name]) return p;
    }
    return nil;
}

#pragma mark - Connection

- (NppFtpClient *)ftpClient { return objc_getAssociatedObject(self, &kFtpClientKey); }
- (nullable NSString *)ftpConnectError { return objc_getAssociatedObject(self, &kFtpConnectErrorKey); }
- (BOOL)ftpConnected { return [self ftpClient] != nil; }

- (NSString *)ftpCurrentDirectory {
    return objc_getAssociatedObject(self, &kFtpDirectoryKey);
}

- (BOOL)connectToFtpProfile:(NppFtpProfile *)profile {
    return [self connectToFtpProfile:profile password:nil];
}

- (BOOL)connectToFtpProfile:(NppFtpProfile *)profile password:(NSString *)password {
    if (!profile.host.length) return NO;
    NppFtpClient *client = [[NppFtpClient alloc] initWithProfile:profile];
    client.password = password;
    NSString *start = profile.initialDirectory.length ? profile.initialDirectory : @"/";

    // Listing the starting directory is the connection test: a profile that
    // cannot list is not usable, and failing here is clearer than failing later.
    // The failed client's reason (curl's or sftp's message) is kept for the alert.
    if (![client listDirectory:start]) {
        objc_setAssociatedObject(self, &kFtpConnectErrorKey, client.lastError, OBJC_ASSOCIATION_COPY);
        return NO;
    }
    objc_setAssociatedObject(self, &kFtpConnectErrorKey, nil, OBJC_ASSOCIATION_COPY);

    objc_setAssociatedObject(self, &kFtpClientKey, client, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(self, &kFtpDirectoryKey, start, OBJC_ASSOCIATION_COPY);
    [self refreshChrome];
    return YES;
}

- (void)disconnectFtp {
    objc_setAssociatedObject(self, &kFtpClientKey, nil, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(self, &kFtpDirectoryKey, nil, OBJC_ASSOCIATION_COPY);
    [self refreshChrome];
}

- (NSArray<NppFtpEntry *> *)ftpListCurrentDirectory {
    NppFtpClient *client = [self ftpClient];
    if (!client) return nil;
    return [client listDirectory:[self ftpCurrentDirectory] ?: @"/"];
}

- (BOOL)ftpChangeDirectory:(NSString *)path {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;

    NSString *target = path;
    if ([path isEqualToString:@".."]) {
        target = [([self ftpCurrentDirectory] ?: @"/") stringByDeletingLastPathComponent];
        if (!target.length) target = @"/";
    } else if (![path hasPrefix:@"/"]) {
        target = [([self ftpCurrentDirectory] ?: @"/") stringByAppendingPathComponent:path];
    }
    if (![client listDirectory:target]) return NO;
    objc_setAssociatedObject(self, &kFtpDirectoryKey, target, OBJC_ASSOCIATION_COPY);
    return YES;
}

#pragma mark - Files

- (NSMutableDictionary *)remotePathMap {
    NSMutableDictionary *map = objc_getAssociatedObject(self, &kFtpRemotePathsKey);
    if (!map) {
        map = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &kFtpRemotePathsKey, map, OBJC_ASSOCIATION_RETAIN);
    }
    return map;
}

/// Which server a connection is: a file came from one account on one host, and belongs to it only.
static NSString *ServerOf(NppFtpProfile *profile) {
    return [NSString stringWithFormat:@"%ld://%@@%@:%ld", (long)profile.protocol, profile.username ?: @"",
            profile.host.lowercaseString ?: @"", (long)profile.port];
}

/// Where the document in front came from - on the server connected now. A file downloaded from
/// another server is, to this one, a local file like any other: NppFTP keeps a cache per profile
/// and finds a remote path only in the connected profile's (FTPSession::GetExternalPathFromLocal).
- (NSString *)remotePathForCurrentDocument {
    NSString *local = self.currentDocument.path;
    NSArray<NSString *> *known = local ? [self remotePathMap][local] : nil;
    NppFtpClient *client = [self ftpClient];
    if (known.count != 2 || !client || ![known[0] isEqualToString:ServerOf(client.profile)]) return nil;
    return known[1];
}

- (BOOL)openRemoteFileAtPath:(NSString *)path {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;

    NSString *remote = [path hasPrefix:@"/"]
        ? path
        : [([self ftpCurrentDirectory] ?: @"/") stringByAppendingPathComponent:path];

    NSData *data = [client downloadFileAtPath:remote];
    if (!data) return NO;

    // The file is edited locally and written back on save, so it needs a real
    // path on disk; the remote one is remembered alongside it.
    // Under the host and the whole remote path: two files called index.html
    // in two folders must not share one cache file, or one is saved over
    // the other on the server.
    NSString *host = [(client.profile.host ?: @"host") stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *cache = [[[self supportDirectory] stringByAppendingPathComponent:@"ftp-cache"]
                       stringByAppendingPathComponent:host];
    // Nothing the server names can climb out of the cache folder.
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in remote.pathComponents) {
        if (part.length && ![part isEqualToString:@"/"] && ![part isEqualToString:@".."] &&
            ![part isEqualToString:@"."]) [parts addObject:part];
    }
    NSString *local = [cache stringByAppendingPathComponent:[parts componentsJoinedByString:@"/"]];
    [[NSFileManager defaultManager] createDirectoryAtPath:local.stringByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:NULL];
    if (![data writeToFile:local atomically:YES]) return NO;

    if (![self openFileAtPath:local error:NULL]) return NO;
    [self remotePathMap][local] = @[ServerOf(client.profile), remote];
    [self refreshChrome];
    return YES;
}

- (BOOL)uploadCurrentDocument {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;

    NSString *remote = [self remotePathForCurrentDocument];
    if (!remote.length) {
        // A document that did not come from the server goes into the directory
        // being browsed, under its own name.
        NSString *name = self.currentDocument.displayName;
        if (!name.length) return NO;
        remote = [([self ftpCurrentDirectory] ?: @"/") stringByAppendingPathComponent:name];
    }

    // NppFTP uploads the file as it is on disk: a saved document goes byte for byte
    // (its BOM, its character set, its line endings); an unsaved one as Save would
    // write it - dataForText: puts the BOM back, which re-encoding the text dropped.
    NppDocument *doc = self.currentDocument;
    NSData *data = nil;
    if (doc.path && !doc.modified) data = [NSData dataWithContentsOfFile:doc.path];
    if (!data) data = [EditorController dataForText:[self documentText]
                                           encoding:doc.encoding ?: NSUTF8StringEncoding hasBOM:doc.hasBOM];
    if (!data) return NO;
    if (![client uploadData:data toPath:remote]) return NO;

    // A local file uploaded is remembered where it went; one from a server stays that server's.
    if (self.currentDocument.path && ![self remotePathMap][self.currentDocument.path])
        [self remotePathMap][self.currentDocument.path] = @[ServerOf(client.profile), remote];
    return YES;
}

@end
