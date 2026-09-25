#import "NppPanel.h"
#import "RunCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>
#include <poll.h>

static const char kConsoleKey = 0;

/// Scintilla counts in UTF-8 bytes; NSString counts in UTF-16 units, so a range
/// from Scintilla has to be cut out of the bytes and rebuilt.
static NSString *SliceBytes(NSData *data, long start, long end) {
    if (start < 0) start = 0;
    if (end > (long)data.length) end = (long)data.length;
    if (end <= start) return @"";
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(start, end - start)]
                                 encoding:NSUTF8StringEncoding] ?: @"";
}

@implementation NppRunResult
@end

#pragma mark - Saved commands

@implementation NppSavedCommand

+ (instancetype)commandWithName:(NSString *)name command:(NSString *)command {
    NppSavedCommand *saved = [[NppSavedCommand alloc] init];
    saved.name = name;
    saved.command = command;
    return saved;
}

+ (instancetype)commandFromDictionary:(NSDictionary *)dictionary {
    return [self commandWithName:dictionary[@"name"] ?: @"" command:dictionary[@"command"] ?: @""];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{ @"name": self.name ?: @"", @"command": self.command ?: @"" };
}

@end

#pragma mark - Console

@interface NppConsolePanel ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextView *textView;
@property (nonatomic, weak) EditorController *editor;
@end

@implementation NppConsolePanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;

    NSRect frame = NSMakeRect(0, 0, 640, 260);
    _panel = [[NppPanel alloc] initWithContentRect:frame
                                        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow)
                                          backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Console";
    _panel.releasedWhenClosed = NO;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _textView = [[NSTextView alloc] initWithFrame:frame];
    _textView.editable = NO;
    _textView.richText = NO;
    _textView.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    // The system's dynamic colours, so the text is readable in dark mode too:
    // appended plain text would otherwise be drawn black on the dark background.
    _textView.textColor = [NSColor textColor];
    _textView.backgroundColor = [NSColor textBackgroundColor];
    _textView.insertionPointColor = [NSColor textColor];
    _textView.typingAttributes = @{NSFontAttributeName: _textView.font, NSForegroundColorAttributeName: [NSColor textColor]};
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.minSize = NSMakeSize(0, 0);
    _textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _textView.verticallyResizable = YES;
    _textView.horizontallyResizable = NO;
    _textView.textContainer.widthTracksTextView = YES;
    _textView.textContainer.containerSize = NSMakeSize(frame.size.width, FLT_MAX);

    scroll.documentView = _textView;
    _panel.contentView = scroll;
    return self;
}

- (BOOL)visible { return self.panel.isVisible; }
- (NSString *)text { return self.textView.string ?: @""; }

- (void)show { [self.panel makeKeyAndOrderFront:nil]; }
- (void)showWithoutFocus { [self.panel orderFront:nil]; }

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self show];
}

- (void)clear { self.textView.string = @""; }

- (void)appendText:(NSString *)text {
    if (!text.length) return;
    // The read loop can be on a background thread; the text storage cannot be.
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self appendText:text]; });
        return;
    }
    NSDictionary *attributes = @{NSFontAttributeName: self.textView.font ?: [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular],
                                 NSForegroundColorAttributeName: [NSColor textColor]};
    [self.textView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:attributes]];
    [self.textView scrollRangeToVisible:NSMakeRange(self.textView.string.length, 0)];
}

@end

#pragma mark - Commands

@interface EditorController (RunCommandsPrivate)
/// Runs a command line whose variables have already been substituted.
- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded intoConsole:(BOOL)intoConsole;
@end

@implementation EditorController (RunCommands)

- (NppConsolePanel *)console {
    NppConsolePanel *console = objc_getAssociatedObject(self, &kConsoleKey);
    if (!console) {
        console = [[NppConsolePanel alloc] initWithEditor:self];
        objc_setAssociatedObject(self, &kConsoleKey, console, OBJC_ASSOCIATION_RETAIN);
    }
    return console;
}

#pragma mark Variables

/// The word under the caret, or the selection when there is one -- which is what
/// Notepad++ means by CURRENT_WORD.
- (NSString *)runCurrentWord {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (a == b) {
        long pos = [sci message:SCI_GETCURRENTPOS];
        a = [sci message:SCI_WORDSTARTPOSITION wParam:(uptr_t)pos lParam:1];
        b = [sci message:SCI_WORDENDPOSITION wParam:(uptr_t)pos lParam:1];
    }
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, a, b);
}

- (NSString *)runCurrentLineText {
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos];
    long start = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line];
    long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line];
    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    return SliceBytes(data, start, end);
}

- (NSString *)runVariableNamed:(NSString *)name {
    // An unsaved document has no path; Notepad++ uses the tab's name there, and
    // the path-derived variables then follow from that name.
    NSString *full = self.currentDocument.path ?: (self.currentDocument.displayName ?: @"");

    if ([name isEqualToString:@"FULL_CURRENT_PATH"]) return full;
    if ([name isEqualToString:@"CURRENT_DIRECTORY"]) return [full stringByDeletingLastPathComponent];
    if ([name isEqualToString:@"FILE_NAME"]) return full.lastPathComponent;
    if ([name isEqualToString:@"NAME_PART"])
        return [full.lastPathComponent stringByDeletingPathExtension];
    if ([name isEqualToString:@"EXT_PART"]) {
        // PathFindExtension keeps the dot, and gives nothing at all when there
        // is no extension.
        NSString *ext = full.pathExtension;
        return ext.length ? [@"." stringByAppendingString:ext] : @"";
    }
    if ([name isEqualToString:@"CURRENT_WORD"]) return [self runCurrentWord];
    if ([name isEqualToString:@"CURRENT_LINESTR"]) return [self runCurrentLineText];
    if ([name isEqualToString:@"NPP_DIRECTORY"])
        return [[NSBundle mainBundle].bundlePath stringByDeletingLastPathComponent];
    if ([name isEqualToString:@"NPP_FULL_FILE_PATH"])
        return [NSBundle mainBundle].executablePath ?: @"";

    // Both of these are zero-based, as they are on Windows: they come straight
    // from Scintilla, which counts from zero, and are not the numbers shown in
    // the status bar.
    ScintillaView *sci = self.sci;
    long pos = [sci message:SCI_GETCURRENTPOS];
    if ([name isEqualToString:@"CURRENT_LINE"])
        return [NSString stringWithFormat:@"%ld", [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos]];
    if ([name isEqualToString:@"CURRENT_COLUMN"])
        return [NSString stringWithFormat:@"%ld", [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos]];

    return nil;
}

/// A value made safe for /bin/sh at the point it is spliced in. Windows
/// hands the command to ShellExecute, which reads none of it; here the shell
/// reads all of it, and a line of the document must not become a command.
/// Inside single quotes nothing is read but a quote; inside double quotes
/// only $, `, " and \ are; outside, a value with anything the shell would
/// read is single-quoted whole, and a plain path or number is left as it is.
typedef NS_ENUM(NSInteger, NppShellContext) { NppShellBare, NppShellInSingle, NppShellInDouble };

static NSString *QuotedForShell(NSString *value, NppShellContext context) {
    if (context == NppShellInSingle) {
        return [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
    }
    if (context == NppShellInDouble) {
        NSMutableString *out = [NSMutableString stringWithCapacity:value.length];
        for (NSUInteger i = 0; i < value.length; ++i) {
            unichar c = [value characterAtIndex:i];
            if (c == '$' || c == '`' || c == '"' || c == '\\') [out appendString:@"\\"];
            [out appendFormat:@"%C", c];
        }
        return out;
    }
    static NSCharacterSet *safe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        safe = [NSCharacterSet characterSetWithCharactersInString:
                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./:@%+=,-"];
    });
    if ([value rangeOfCharacterFromSet:safe.invertedSet].location == NSNotFound) return value;
    return [NSString stringWithFormat:@"'%@'",
            [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

- (NSString *)expandRunVariables:(NSString *)source {
    return [self expandRunVariables:source lookup:nil quoteForShell:YES];
}

- (NSString *)expandRunVariables:(NSString *)source lookup:(NSString *(^)(NSString *))lookup quoteForShell:(BOOL)quote {
    if (!source.length) return @"";
    NSMutableString *out = [NSMutableString string];
    NSUInteger length = source.length;
    NppShellContext context = NppShellBare;
    // Open command substitutions: [parentheses still open inside (-1 for backticks), the context outside].
    NSMutableArray<NSArray<NSNumber *> *> *substitutions = [NSMutableArray array];

    for (NSUInteger i = 0; i < length; ++i) {
        unichar c = [source characterAtIndex:i];
        // A quote is escaped by an odd run of backslashes before it, and
        // never inside single quotes, where a backslash is just a backslash.
        NSUInteger backslashes = 0;
        for (NSUInteger k = i; k > 0 && [source characterAtIndex:k - 1] == '\\'; --k) backslashes++;
        BOOL escaped = context != NppShellInSingle && (backslashes % 2) == 1;
        // Inside the shell's own $( ) or backticks the words are read afresh,
        // whatever quotes are open outside: a value spliced there is quoted
        // as a bare word, or a ';' in a file name would be a command.
        if (c == '`' && context != NppShellInSingle && !escaped) {
            if (substitutions.count && [substitutions.lastObject[0] intValue] == -1) {
                context = (NppShellContext)[substitutions.lastObject[1] integerValue];
                [substitutions removeLastObject];
            } else {
                [substitutions addObject:@[@(-1), @(context)]];
                context = NppShellBare;
            }
        } else if (substitutions.count && [substitutions.lastObject[0] intValue] >= 0 && context == NppShellBare && !escaped) {
            NSInteger depth = [substitutions.lastObject[0] integerValue];
            if (c == '(') substitutions[substitutions.count - 1] = @[@(depth + 1), substitutions.lastObject[1]];
            else if (c == ')') {
                if (depth > 0) substitutions[substitutions.count - 1] = @[@(depth - 1), substitutions.lastObject[1]];
                else {
                    context = (NppShellContext)[substitutions.lastObject[1] integerValue];
                    [substitutions removeLastObject];
                }
            }
        }
        if (c == '\'' && context != NppShellInDouble && !escaped) {
            context = context == NppShellInSingle ? NppShellBare : NppShellInSingle;
        } else if (c == '"' && context != NppShellInSingle && !escaped) {
            context = context == NppShellInDouble ? NppShellBare : NppShellInDouble;
        }
        if (c != '$' || i + 1 >= length || [source characterAtIndex:i + 1] != '(') {
            [out appendFormat:@"%C", c];
            continue;
        }

        NSRange close = [source rangeOfString:@")"
                                      options:0
                                        range:NSMakeRange(i + 2, length - i - 2)];
        if (close.location == NSNotFound) {
            // Nothing closes it, so it was never a variable. Emit the dollar and
            // carry on from the bracket, which is what Notepad++ does.
            [out appendString:@"$"];
            continue;
        }

        NSString *name = [source substringWithRange:NSMakeRange(i + 2, close.location - i - 2)];
        NSString *value = (lookup ? lookup(name) : nil) ?: [self runVariableNamed:name];
        if (!value) {
            // An unknown name is left exactly as it was written, rather than
            // being swallowed -- it may well be meant for the shell, whose
            // command substitution it then opens.
            if (context == NppShellInSingle) { [out appendString:@"$"]; continue; }
            [out appendString:@"$("];
            [substitutions addObject:@[@0, @(context)]];
            context = NppShellBare;
            i += 1;
            continue;
        }
        NSString *spliced = quote ? QuotedForShell(value, context) : value;
        if (quote) {
            // Inside `...` the outer shell reads the text first and does not respect
            // single quotes: a backquote would end the substitution, a backslash
            // escape the next character. Each backquote level gets its own escapes.
            for (NSArray<NSNumber *> *level in substitutions) {
                if ([level[0] intValue] != -1) continue;
                spliced = [[[spliced stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                            stringByReplacingOccurrencesOfString:@"`" withString:@"\\`"]
                           stringByReplacingOccurrencesOfString:@"$" withString:@"\\$"];
            }
        }
        [out appendString:spliced];
        i = close.location;
    }
    return out;
}

#pragma mark Running

- (NppRunResult *)runCommandLine:(NSString *)command intoConsole:(BOOL)intoConsole {
    return [self runExpandedCommandLine:[self expandRunVariables:command] intoConsole:intoConsole];
}

- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded intoConsole:(BOOL)intoConsole {
    // A command usually means something relative to the file being edited, so
    // that is where it runs.
    return [self runExpandedCommandLine:expanded directory:[self runVariableNamed:@"CURRENT_DIRECTORY"]
                            environment:nil intoConsole:intoConsole];
}

- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded directory:(NSString *)directory
                             environment:(NSDictionary<NSString *, NSString *> *)environment
                             intoConsole:(BOOL)intoConsole {
    return [self runExpandedCommandLine:expanded directory:directory environment:environment
                            intoConsole:intoConsole timeout:30 stopWhen:nil];
}

- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded directory:(NSString *)directory
                             environment:(NSDictionary<NSString *, NSString *> *)environment
                             intoConsole:(BOOL)intoConsole timeout:(NSTimeInterval)timeout
                                stopWhen:(BOOL (^)(void))stopWhen {
    NppRunResult *result = [[NppRunResult alloc] init];
    result.output = @"";
    result.exitStatus = -1;
    if (!expanded.length) return result;

    NppConsolePanel *console = intoConsole ? [self console] : nil;
    [console appendText:[NSString stringWithFormat:@"> %@\n", expanded]];

    // The command goes to the shell as a script file in UTF-8, not as an argument:
    // NSTask passes arguments through fileSystemRepresentation, which decomposes them
    // (é arrives as e + U+0301, and printf 'é' prints the pieces). ShellExecute on
    // Windows gets the text as written; so does /bin/sh here.
    NSString *script = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat:@"nppmac-run-%@.sh", [NSUUID UUID].UUIDString]];
    if (![expanded writeToFile:script atomically:NO encoding:NSUTF8StringEncoding error:NULL]) script = nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = script ? @[script] : @[@"-c", expanded];

    if (environment) {
        NSMutableDictionary *env = [[NSProcessInfo processInfo].environment mutableCopy];
        [env addEntriesFromDictionary:environment];
        task.environment = env;
    }
    BOOL isDirectory = NO;
    if (directory.length &&
        [[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] && isDirectory) {
        task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    }

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (script) [[NSFileManager defaultManager] removeItemAtPath:script error:NULL];
        NSString *message = [NSString stringWithFormat:@"%@\n",
                             error.localizedDescription ?: @"the command could not be started"];
        result.output = message;
        [console appendText:message];
        return result;
    }

    // Terminating the task is what a timeout or Stop means here: the shell's
    // end is what ends the read loop below. Its children would run on, so
    // ending a command means ending them first, deepest last.
    void (^endTask)(void) = ^{
        NSMutableArray<NSNumber *> *family = [NSMutableArray arrayWithObject:@(task.processIdentifier)];
        for (NSUInteger at = 0; at < family.count && family.count < 256; ++at) {
            NSTask *list = [[NSTask alloc] init];
            list.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pgrep"];
            list.arguments = @[@"-P", family[at].stringValue];
            NSPipe *found = [NSPipe pipe];
            list.standardOutput = found;
            if (![list launchAndReturnError:NULL]) break;
            NSData *data = [found.fileHandleForReading readDataToEndOfFile];
            [list waitUntilExit];
            for (NSString *pid in [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"]) {
                if (pid.intValue > 0) [family addObject:@(pid.intValue)];
            }
        }
        for (NSNumber *pid in family.reverseObjectEnumerator) if (pid.intValue != task.processIdentifier) kill(pid.intValue, SIGTERM);
        [task terminate];
    };
    __block BOOL timedOut = NO;
    if (timeout > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (task.isRunning) { timedOut = YES; endTask(); }
        });
    }
    // A build may take as long as it takes; what ends it early is being told to stop.
    dispatch_source_t watch = nil;
    if (stopWhen) {
        watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        dispatch_source_set_timer(watch, DISPATCH_TIME_NOW, (uint64_t)(0.2 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(watch, ^{ if (task.isRunning && stopWhen()) endTask(); });
        dispatch_resume(watch);
    }

    // Read chunk by chunk rather than to the end, so the console fills while the
    // command is still going. This waits on the pipe, never on the run loop --
    // spinning the run loop here would re-enter AppKit in the middle of a menu
    // command, which is not survivable.
    // The command is over when the shell is, as NppExec's CChildProcess ends when its
    // process does and ShellExecute leaves whatever the program started running: a
    // child left in the background (`server &`) keeps the pipe open, so the end of the
    // pipe cannot be what is waited for. What such a child still writes goes on
    // reaching the console, from a reader of its own, until it closes the pipe too.
    NSMutableData *collected = [NSMutableData data];
    NSFileHandle *handle = pipe.fileHandleForReading;
    int fd = handle.fileDescriptor;
    void (^deliver)(NSData *) = ^(NSData *chunk) {
        if (!console) return;
        NSString *piece = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        if (piece) [console appendText:piece];
    };
    BOOL open = YES;
    char buffer[65536];
    NSUInteger readsAfterExit = 0;
    while (open) {
        // Once the shell has gone, only what is already in the pipe is taken (and not
        // for ever, should a child keep writing): then the command is over.
        BOOL shellGone = !task.isRunning;
        struct pollfd ready = { fd, POLLIN, 0 };
        int got = poll(&ready, 1, shellGone ? 0 : 100);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) { if (shellGone) break; continue; }
        ssize_t n = read(fd, buffer, sizeof buffer);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { open = NO; break; }
        NSData *chunk = [NSData dataWithBytes:buffer length:(NSUInteger)n];
        [collected appendData:chunk];
        deliver(chunk);
        if (shellGone && ++readsAfterExit >= 64) break;
    }
    if (open) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            for (;;) {
                NSData *chunk = [handle availableData];
                if (!chunk.length) break;
                deliver(chunk);
            }
        });
    }

    [task waitUntilExit];   // the shell has ended by now, so this returns at once
    if (watch) dispatch_source_cancel(watch);
    if (script) [[NSFileManager defaultManager] removeItemAtPath:script error:NULL];
    result.output = [[NSString alloc] initWithData:collected encoding:NSUTF8StringEncoding] ?: @"";
    result.exitStatus = task.terminationStatus;
    result.timedOut = timedOut;

    if (console && result.exitStatus != 0) {
        [console appendText:[NSString stringWithFormat:@"(exit status %d%@)\n",
                             result.exitStatus, timedOut ? @", timed out" : @""]];
    }
    return result;
}

- (void)runCommandLineInBackground:(NSString *)command
                        completion:(void (^)(NppRunResult *))completion {
    // The variables have to be read on the main thread, where the editor lives;
    // only the running itself moves off it.
    NSString *expanded = [self expandRunVariables:command];
    NSString *directory = [self runVariableNamed:@"CURRENT_DIRECTORY"];
    (void)[self console];                               // a panel is made on the main thread
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // No time limit: Command::run hands the program to ShellExecute and leaves it
        // running - an interpreter on the file, an application, a server.
        NppRunResult *result = [self runExpandedCommandLine:expanded directory:directory environment:nil
                                                intoConsole:YES timeout:0 stopWhen:nil];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}

#pragma mark Saved commands

- (NSArray<NppSavedCommand *> *)savedCommands {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *dict in [NppPreferences shared].savedRunCommands ?: @[]) {
        [out addObject:[NppSavedCommand commandFromDictionary:dict]];
    }
    return out;
}

- (void)saveCommand:(NppSavedCommand *)command {
    if (!command.name.length) return;
    NSMutableArray *stored = [([NppPreferences shared].savedRunCommands ?: @[]) mutableCopy];
    NSUInteger existing = NSNotFound;
    for (NSUInteger i = 0; i < stored.count; ++i) {
        if ([stored[i][@"name"] isEqualToString:command.name]) { existing = i; break; }
    }
    if (existing == NSNotFound) [stored addObject:command.dictionaryRepresentation];
    else stored[existing] = command.dictionaryRepresentation;
    [NppPreferences shared].savedRunCommands = stored;
}

- (void)removeSavedCommandNamed:(NSString *)name {
    NSMutableArray *stored = [([NppPreferences shared].savedRunCommands ?: @[]) mutableCopy];
    for (NSUInteger i = 0; i < stored.count; ++i) {
        if ([stored[i][@"name"] isEqualToString:name]) {
            [stored removeObjectAtIndex:i];
            [NppPreferences shared].savedRunCommands = stored;
            return;
        }
    }
}

@end
