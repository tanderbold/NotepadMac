/* nppmac - open files in NotepadMac from the terminal, the way `code` does
 * for VS Code. Ships inside the bundle (Contents/Helpers/nppmac); Tools >
 * Install Command Line Tool links it into /usr/local/bin.
 *
 *   nppmac                     open (or bring forward) the application
 *   nppmac file.txt notes.md   open files; a folder opens as a workspace
 *   nppmac +42 file.txt        open file.txt at line 42 (+N before the file)
 *   echo hi | nppmac -         read standard input into a new document
 *   nppmac mcp                 serve the editor to an AI agent over MCP (stdio)
 *
 * A file that does not exist yet is created empty, as typing `nppmac new.txt`
 * means to start writing it. The application hears about files over a
 * distributed notification, so a running instance is reused.
 */
#import <Cocoa/Cocoa.h>
#include <sys/socket.h>
#include <sys/un.h>

static NSString *const kDefaultBundleID = @"org.notepad-plus-plus.mac";

/* The application this tool ships in (Contents/Helpers/nppmac, reached
 * through the /usr/local/bin symlink too), or nil when it runs on its own. */
static NSURL *enclosingApplication(void) {
    NSString *mine = NSProcessInfo.processInfo.arguments.firstObject;
    if (!mine.isAbsolutePath) {
        /* Found through PATH: where the shell found it. */
        for (NSString *dir in [NSProcessInfo.processInfo.environment[@"PATH"] componentsSeparatedByString:@":"]) {
            NSString *candidate = [dir stringByAppendingPathComponent:mine];
            if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) { mine = candidate; break; }
        }
    }
    NSString *bundle = mine.stringByResolvingSymlinksInPath
                           .stringByDeletingLastPathComponent   /* Helpers  */
                           .stringByDeletingLastPathComponent   /* Contents */
                           .stringByDeletingLastPathComponent;  /* .app     */
    return [bundle hasSuffix:@".app"] ? [NSURL fileURLWithPath:bundle] : nil;
}

/* That application's bundle id - a copy under another id (the end-to-end
 * suite's) is then driven by its own nppmac only - or the usual one. */
static NSString *bundleID(void) {
    NSURL *app = enclosingApplication();
    NSString *identifier = app ? [NSBundle bundleWithURL:app].bundleIdentifier : nil;
    return identifier.length ? identifier : kDefaultBundleID;
}

static void usage(void) {
    fprintf(stderr, "usage: nppmac [+N] [file|folder ...] [-]\n"
                    "       nppmac mcp\n"
                    "  +N     open the file that follows at line N\n"
                    "  -      read standard input into a new document\n"
                    "  mcp    speak the Model Context Protocol on stdin/stdout for an AI agent,\n"
                    "         bridged to the running application (Preferences > MISC. turns the\n"
                    "         agent interface on). Claude Code: claude mcp add notepadmac -- nppmac mcp\n");
}

/// The application's socket, the same path AgentServer.mm listens on.
static NSString *agentSocketPath(void) {
    NSString *given = NSProcessInfo.processInfo.environment[@"NPPMAC_AGENT_SOCKET"];
    if (given.length) return given;
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                         stringByAppendingPathComponent:@"NotepadMac"];
    return [support stringByAppendingPathComponent:@"agent.sock"];
}

static int connectToAgentSocket(void) {
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    const char *path = agentSocketPath().fileSystemRepresentation;
    if (strlen(path) >= sizeof addr.sun_path) return -1;
    strlcpy(addr.sun_path, path, sizeof addr.sun_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) { close(fd); return -1; }
    return fd;
}

/// Starts the application (or finds it running) and waits for its socket.
static NSURL *applicationURL(void);
static int connectLaunchingIfNeeded(void) {
    int fd = connectToAgentSocket();
    if (fd >= 0) return fd;
    NSURL *app = applicationURL();
    if (app) {
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        config.activates = NO;
        [[NSWorkspace sharedWorkspace] openApplicationAtURL:app configuration:config completionHandler:nil];
    }
    for (int tick = 0; tick < 150 && fd < 0; ++tick) {   // up to fifteen seconds
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        fd = connectToAgentSocket();
    }
    return fd;
}

/// One JSON-RPC line, written out as a whole.
static void writeAll(int fd, NSData *data) {
    const char *bytes = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t wrote = write(fd, bytes, left);
        if (wrote <= 0) return;
        bytes += wrote;
        left -= (size_t)wrote;
    }
}

/// The answer to a request the application cannot take: what to do about it,
/// so `claude mcp list` shows the reason rather than "failed to connect".
static void answerUnavailable(NSString *line) {
    id message = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    id identifier = [message isKindOfClass:[NSDictionary class]] ? message[@"id"] : nil;
    if (!identifier) return;   // a notification has no answer
    NSDictionary *reply = @{@"jsonrpc": @"2.0", @"id": identifier,
        @"error": @{@"code": @-32000,
                    @"message": @"NotepadMac's agent interface is off or the application is not running. "
                                @"Open NotepadMac, turn on Preferences > MISC. > \"Let AI agents drive the editor\", and try again."}};
    NSMutableData *out = [[NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL] mutableCopy];
    [out appendBytes:"\n" length:1];
    writeAll(STDOUT_FILENO, out);
}

/// `nppmac mcp`: stdin to the socket, the socket to stdout, line by line. The
/// application speaks the protocol itself; this is the pipe an agent can run.
static int serveMCP(void) {
    int sock = connectLaunchingIfNeeded();
    NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
    if (sock >= 0) {
        // Everything the application answers goes straight out.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            char chunk[65536];
            for (;;) {
                ssize_t got = read(sock, chunk, sizeof chunk);
                if (got <= 0) break;
                writeAll(STDOUT_FILENO, [NSData dataWithBytes:chunk length:(NSUInteger)got]);
            }
            exit(0);   // the application went away; so does the bridge
        });
    }
    NSMutableData *pending = [NSMutableData data];
    for (;;) {
        NSData *chunk = [input availableData];
        if (!chunk.length) break;   // the agent closed its end
        [pending appendData:chunk];
        for (;;) {
            NSRange nl = [pending rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, pending.length)];
            if (nl.location == NSNotFound) break;
            NSData *line = [pending subdataWithRange:NSMakeRange(0, nl.location + 1)];
            [pending replaceBytesInRange:NSMakeRange(0, nl.location + 1) withBytes:NULL length:0];
            if (line.length <= 1) continue;
            if (sock >= 0) {
                writeAll(sock, line);
            } else {
                answerUnavailable([[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding] ?: @"");
            }
        }
    }
    /* A last line without its newline is still a message. */
    if (pending.length) {
        [pending appendBytes:"\n" length:1];
        if (sock >= 0) writeAll(sock, pending);
        else answerUnavailable([[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding] ?: @"");
    }
    if (sock >= 0) {
        /* The agent has said everything; the answers may still be on their
         * way. Close only our sending half: the application answers what it
         * has, closes, and the reader above ends the process. */
        shutdown(sock, SHUT_WR);
        for (;;) pause();
    }
    return 0;
}

static NSURL *applicationURL(void) {
    /* The bundle this very tool ships in first; Launch Services for a copy
     * of the tool that lives on its own. */
    return enclosingApplication() ?: [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:kDefaultBundleID];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc >= 2 && !strcmp(argv[1], "mcp")) return serveMCP();
        NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
        long pendingLine = 0;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *cwd = fm.currentDirectoryPath;

        for (int i = 1; i < argc; ++i) {
            NSString *arg = @(argv[i]);
            if ([arg isEqualToString:@"-h"] || [arg isEqualToString:@"--help"]) { usage(); return 0; }
            if ([arg hasPrefix:@"+"] && arg.length > 1 &&
                [arg substringFromIndex:1].integerValue > 0) {
                pendingLine = [arg substringFromIndex:1].integerValue;
                continue;
            }
            NSString *path;
            if ([arg isEqualToString:@"-"]) {
                NSData *piped = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
                path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"nppmac-stdin-%d.txt", getpid()]];
                [piped writeToFile:path atomically:YES];
            } else {
                path = arg.isAbsolutePath ? arg : [cwd stringByAppendingPathComponent:arg];
                path = path.stringByStandardizingPath;
                BOOL isDirectory = NO;
                if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) {
                    /* `nppmac new.txt` means to start writing it. */
                    if (![fm createFileAtPath:path contents:[NSData data] attributes:nil]) {
                        fprintf(stderr, "nppmac: cannot create %s\n", path.UTF8String);
                        continue;
                    }
                }
            }
            [files addObject:@{@"path": path, @"line": @(pendingLine)}];
            pendingLine = 0;
        }

        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSURL *app = applicationURL();
        if (!app) { fprintf(stderr, "nppmac: NotepadMac.app not found\n"); return 1; }

        __block BOOL launched = NO;
        NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
        config.activates = YES;
        [workspace openApplicationAtURL:app configuration:config
                      completionHandler:^(NSRunningApplication *running, NSError *error) {
            launched = running != nil;
        }];

        /* The notification only lands once the application listens; wait for
         * it to have finished launching, up to ten seconds. */
        for (int tick = 0; tick < 100; ++tick) {
            NSArray<NSRunningApplication *> *running =
                [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID()];
            if (running.count && running.firstObject.finishedLaunching) break;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        (void)launched;

        if (files.count) {
            [[NSDistributedNotificationCenter defaultCenter]
                postNotificationName:[bundleID() stringByAppendingString:@".cli"] object:nil
                            userInfo:@{@"files": files} deliverImmediately:YES];
        }
    }
    return 0;
}
