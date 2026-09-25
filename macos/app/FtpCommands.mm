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

/// The transfers of the menu's commands run here, one after another: a server
/// that is slow to answer (15 s to connect, 120 s for a transfer) must not stop
/// the editor. What they change in the editor is done back on the main thread.
static dispatch_queue_t FtpQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("org.notepad-plus-plus.mac.ftp", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static void OffMainThread(id (^work)(void), void (^done)(id result)) {
    dispatch_async(FtpQueue(), ^{
        id result = work();
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    });
}

- (NppFtpClient *)makeFtpClientFor:(NppFtpProfile *)profile password:(NSString *)password {
    NppFtpClient *client = [[NppFtpClient alloc] initWithProfile:profile];
    client.password = password;
    return client;
}

static NSString *FtpStartDirectory(NppFtpProfile *profile) {
    return profile.initialDirectory.length ? profile.initialDirectory : @"/";
}

/// Listing the starting directory is the connection test: a profile that
/// cannot list is not usable, and failing here is clearer than failing later.
/// The failed client's reason (curl's or sftp's message) is kept for the alert.
- (BOOL)finishFtpConnect:(NppFtpClient *)client listing:(NSArray *)entries {
    if (!entries) {
        objc_setAssociatedObject(self, &kFtpConnectErrorKey, client.lastError, OBJC_ASSOCIATION_COPY);
        return NO;
    }
    objc_setAssociatedObject(self, &kFtpConnectErrorKey, nil, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(self, &kFtpClientKey, client, OBJC_ASSOCIATION_RETAIN);
    objc_setAssociatedObject(self, &kFtpDirectoryKey, FtpStartDirectory(client.profile), OBJC_ASSOCIATION_COPY);
    [self refreshChrome];
    return YES;
}

- (BOOL)connectToFtpProfile:(NppFtpProfile *)profile password:(NSString *)password {
    if (!profile.host.length) return NO;
    NppFtpClient *client = [self makeFtpClientFor:profile password:password];
    return [self finishFtpConnect:client listing:[client listDirectory:FtpStartDirectory(profile)]];
}

- (void)connectToFtpProfile:(NppFtpProfile *)profile password:(NSString *)password
                 completion:(void (^)(BOOL connected, NSArray<NppFtpEntry *> *entries))completion {
    if (!profile.host.length) { completion(NO, nil); return; }
    NppFtpClient *client = [self makeFtpClientFor:profile password:password];
    NSString *start = FtpStartDirectory(profile);
    OffMainThread(^id { return [client listDirectory:start]; }, ^(NSArray *entries) {
        completion([self finishFtpConnect:client listing:entries], entries);
    });
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

- (void)ftpListCurrentDirectoryCompletion:(void (^)(NSArray<NppFtpEntry *> *entries))completion {
    NppFtpClient *client = [self ftpClient];
    if (!client) { completion(nil); return; }
    NSString *directory = [self ftpCurrentDirectory] ?: @"/";
    OffMainThread(^id { return [client listDirectory:directory]; }, ^(NSArray *entries) { completion(entries); });
}

- (NSString *)ftpTargetDirectory:(NSString *)path {
    if ([path isEqualToString:@".."]) {
        NSString *target = [([self ftpCurrentDirectory] ?: @"/") stringByDeletingLastPathComponent];
        return target.length ? target : @"/";
    }
    return [path hasPrefix:@"/"] ? path : [([self ftpCurrentDirectory] ?: @"/") stringByAppendingPathComponent:path];
}

- (BOOL)ftpChangeDirectory:(NSString *)path {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;
    NSString *target = [self ftpTargetDirectory:path];
    if (![client listDirectory:target]) return NO;
    objc_setAssociatedObject(self, &kFtpDirectoryKey, target, OBJC_ASSOCIATION_COPY);
    return YES;
}

- (void)ftpChangeDirectory:(NSString *)path completion:(void (^)(NSArray<NppFtpEntry *> *entries))completion {
    NppFtpClient *client = [self ftpClient];
    if (!client) { completion(nil); return; }
    NSString *target = [self ftpTargetDirectory:path];
    // The listing that tests the directory is the one shown: no second one.
    OffMainThread(^id { return [client listDirectory:target]; }, ^(NSArray *entries) {
        if (entries && [self ftpClient] == client) {
            objc_setAssociatedObject(self, &kFtpDirectoryKey, target, OBJC_ASSOCIATION_COPY);
        }
        completion([self ftpClient] == client ? entries : nil);
    });
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

- (NSString *)ftpRemotePathFor:(NSString *)path {
    return [path hasPrefix:@"/"] ? path : [([self ftpCurrentDirectory] ?: @"/") stringByAppendingPathComponent:path];
}

/// A downloaded file into a tab.
- (BOOL)openDownloaded:(NSData *)data from:(NSString *)remote client:(NppFtpClient *)client {
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

- (BOOL)openRemoteFileAtPath:(NSString *)path {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;
    NSString *remote = [self ftpRemotePathFor:path];
    return [self openDownloaded:[client downloadFileAtPath:remote] from:remote client:client];
}

- (void)openRemoteFileAtPath:(NSString *)path completion:(void (^)(BOOL opened))completion {
    NppFtpClient *client = [self ftpClient];
    if (!client) { completion(NO); return; }
    NSString *remote = [self ftpRemotePathFor:path];
    OffMainThread(^id { return [client downloadFileAtPath:remote]; }, ^(NSData *data) {
        completion([self openDownloaded:data from:remote client:client]);
    });
}

/// Where the current document goes and what is sent, or NO.
- (BOOL)uploadOfCurrentDocument:(NSString **)remoteOut data:(NSData **)dataOut {
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
    *remoteOut = remote;
    *dataOut = data;
    return YES;
}

- (BOOL)uploadCurrentDocument {
    NppFtpClient *client = [self ftpClient];
    if (!client) return NO;
    NSString *remote = nil;
    NSData *data = nil;
    if (![self uploadOfCurrentDocument:&remote data:&data]) return NO;
    if (![client uploadData:data toPath:remote]) return NO;
    [self rememberUploadOf:self.currentDocument.path to:remote on:client];
    return YES;
}

/// A local file uploaded is remembered where it went; one from a server stays that server's.
- (void)rememberUploadOf:(NSString *)local to:(NSString *)remote on:(NppFtpClient *)client {
    if (local && ![self remotePathMap][local]) [self remotePathMap][local] = @[ServerOf(client.profile), remote];
}

- (void)uploadCurrentDocumentCompletion:(void (^)(BOOL uploaded, NSString *remote))completion {
    NppFtpClient *client = [self ftpClient];
    NSString *remote = nil;
    NSData *data = nil;
    if (!client || ![self uploadOfCurrentDocument:&remote data:&data]) { completion(NO, nil); return; }
    NSString *local = self.currentDocument.path;   // the document sent, whichever is in front later
    OffMainThread(^id { return @([client uploadData:data toPath:remote]); }, ^(NSNumber *ok) {
        if (ok.boolValue) [self rememberUploadOf:local to:remote on:client];
        completion(ok.boolValue, local ? remote : nil);   // what remotePathForCurrentDocument said after it
    });
}

@end
