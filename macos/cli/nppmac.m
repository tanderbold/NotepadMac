/* nppmac - open files in NotepadMac from the terminal, the way `code` does
 * for VS Code. Ships inside the bundle (Contents/Helpers/nppmac); Tools >
 * Install Command Line Tool links it into /usr/local/bin.
 *
 *   nppmac                     open (or bring forward) the application
 *   nppmac file.txt notes.md   open files; a folder opens as a workspace
 *   nppmac +42 file.txt        open file.txt at line 42 (+N before the file)
 *   echo hi | nppmac -         read standard input into a new document
 *
 * A file that does not exist yet is created empty, as typing `nppmac new.txt`
 * means to start writing it. The application hears about files over a
 * distributed notification, so a running instance is reused.
 */
#import <Cocoa/Cocoa.h>

static NSString *const kBundleID = @"org.notepad-plus-plus.mac";
static NSString *const kNotification = @"org.notepad-plus-plus.mac.cli";

static void usage(void) {
    fprintf(stderr, "usage: nppmac [+N] [file|folder ...] [-]\n"
                    "  +N     open the file that follows at line N\n"
                    "  -      read standard input into a new document\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
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
        NSURL *app = [workspace URLForApplicationWithBundleIdentifier:kBundleID];
        if (!app) {
            /* Not registered with Launch Services: fall back to the bundle
             * this very tool ships in (Contents/Helpers/nppmac). */
            NSString *mine = NSProcessInfo.processInfo.arguments.firstObject.stringByStandardizingPath;
            NSString *bundle = mine.stringByDeletingLastPathComponent   /* Helpers  */
                                   .stringByDeletingLastPathComponent   /* Contents */
                                   .stringByDeletingLastPathComponent;  /* .app     */
            if ([bundle hasSuffix:@".app"]) app = [NSURL fileURLWithPath:bundle];
        }
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
                [NSRunningApplication runningApplicationsWithBundleIdentifier:kBundleID];
            if (running.count && running.firstObject.finishedLaunching) break;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        (void)launched;

        if (files.count) {
            [[NSDistributedNotificationCenter defaultCenter]
                postNotificationName:kNotification object:nil
                            userInfo:@{@"files": files} deliverImmediately:YES];
        }
    }
    return 0;
}
