#import "FtpCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

static const char kFtpClientKey = 0;
static const char kFtpDirectoryKey = 0;
static const char kFtpRemotePathsKey = 0;   // local temp path -> remote path

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
    if (![client listDirectory:start]) return NO;

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

- (NSString *)remotePathForCurrentDocument {
    NSString *local = self.currentDocument.path;
    return local ? [self remotePathMap][local] : nil;
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
    [self remotePathMap][local] = remote;
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

    NSString *text = [self documentText];
    NSData *data = [text dataUsingEncoding:self.currentDocument.encoding ?: NSUTF8StringEncoding
                      allowLossyConversion:YES];
    if (!data) return NO;
    if (![client uploadData:data toPath:remote]) return NO;

    if (self.currentDocument.path) [self remotePathMap][self.currentDocument.path] = remote;
    return YES;
}

@end
