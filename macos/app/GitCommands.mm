#import <objc/runtime.h>
#include <atomic>
#import "GitCommands.h"
#import "CompareCommands.h"
#import "EditCommands.h"
#import "RunCommands.h"
#import "DockingManager.h"
#import "NppPanel.h"
#import "Localization.h"
#import "SettingsCommands.h"
#import "PluginHost.h"
#import "ScintillaView.h"
#include "SciLexer.h"

#pragma mark - What is drawn

// Markers 6-8 in a margin of their own (4), after the bookmark (1), Compare
// (2-5) and Change History's (Scintilla's own numbers): a bar for lines
// added or changed since HEAD, and a small arrow where lines were taken out.
#define NPPMAC_GIT_MARKER_ADDED    6
#define NPPMAC_GIT_MARKER_CHANGED  7
#define NPPMAC_GIT_MARKER_REMOVED  8
#define NPPMAC_GIT_MARGIN          4
static const long kGitMarkerMask = (1 << NPPMAC_GIT_MARKER_ADDED) | (1 << NPPMAC_GIT_MARKER_CHANGED) | (1 << NPPMAC_GIT_MARKER_REMOVED);
/// Past this the text is not diffed as one types; on open and save it still is.
static const long kMostBytesDiffedLive = 2 * 1024 * 1024;

#pragma mark - NppGitFileStatus

@implementation NppGitFileStatus
- (BOOL)untracked { return self.index == '?'; }
- (BOOL)staged { return self.index != ' ' && self.index != '?' && self.index != '!'; }
- (BOOL)unstaged { return self.worktree != ' ' && self.worktree != '?' && self.worktree != '!'; }
- (NSString *)shortStatus {
    if (self.untracked) return @"??";
    NSMutableString *s = [NSMutableString string];
    if (self.index != ' ') [s appendFormat:@"%C", self.index];
    if (self.worktree != ' ') [s appendFormat:@"%C", self.worktree];
    return s;
}
@end

#pragma mark - NppGit: the executable

@implementation NppGit

+ (NSString *)executable {
    static NSString *found;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        // xcode-select -p answers without any dialog; /usr/bin/git without the
        // tools would put up Apple's "install the command line developer tools".
        NSTask *which = [[NSTask alloc] init];
        which.executableURL = [NSURL fileURLWithPath:@"/usr/bin/xcode-select"];
        which.arguments = @[@"-p"];
        NSPipe *out = [NSPipe pipe];
        which.standardOutput = out;
        which.standardError = [NSPipe pipe];
        NSString *developer = nil;
        if ([which launchAndReturnError:NULL]) {
            NSData *data = [out.fileHandleForReading readDataToEndOfFile];
            [which waitUntilExit];
            if (which.terminationStatus == 0) {
                developer = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }
        NSMutableArray *candidates = [NSMutableArray array];
        if (developer.length) {
            [candidates addObject:[developer stringByAppendingPathComponent:@"usr/bin/git"]];
            [candidates addObject:@"/usr/bin/git"];
        }
        [candidates addObjectsFromArray:@[@"/opt/homebrew/bin/git", @"/usr/local/bin/git"]];
        for (NSString *path in candidates) if ([fm isExecutableFileAtPath:path]) { found = path; break; }
    });
    return found;
}

static std::atomic<NSUInteger> gRunsOnMainThread{0};

+ (NSUInteger)runsOnMainThread { return gRunsOnMainThread; }

+ (BOOL)run:(NSArray<NSString *> *)arguments in:(NSString *)directory output:(NSString **)output error:(NSString **)error {
    NSString *git = [self executable];
    if (!git) { if (error) *error = @"Git is not installed"; return NO; }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:git];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"GIT_TERMINAL_PROMPT"] = @"0";   // fail, never hang on a prompt no one can see
    // No optional locks (git status refreshing the index): the refresh in the
    // background must not hold index.lock while a command the user gave runs.
    env[@"GIT_OPTIONAL_LOCKS"] = @"0";
    env[@"LC_ALL"] = @"en_US.UTF-8";
    env[@"GIT_PAGER"] = @"cat";
    task.environment = env;
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = err;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    // Waited for with a semaphore, not waitUntilExit: that runs the run loop, and
    // what was queued for the main thread - a fetch's finished:, an agent's
    // request, the marker timer - ran in the middle of this command.
    dispatch_semaphore_t exited = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) { dispatch_semaphore_signal(exited); };
    NSError *launch = nil;
    if (![task launchAndReturnError:&launch]) { if (error) *error = launch.localizedDescription; return NO; }
    if ([NSThread isMainThread]) gRunsOnMainThread++;
    // Both pipes drained before waiting, or a chatty git fills one and stalls.
    __block NSData *outData = nil, *errData = nil;
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ outData = [out.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ errData = [err.fileHandleForReading readDataToEndOfFile]; });
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_wait(exited, DISPATCH_TIME_FOREVER);
    if (output) *output = [[NSString alloc] initWithData:outData ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
    NSString *errText = [[NSString alloc] initWithData:errData ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @"";
    if (error) *error = [errText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return task.terminationStatus == 0;
}

+ (void)run:(NSArray<NSString *> *)arguments in:(NSString *)directory
     stream:(void (^)(NSString *))stream finished:(void (^)(BOOL))finished {
    NSString *git = [self executable];
    if (!git) { stream(@"Git is not installed\n"); finished(NO); return; }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:git];
    task.arguments = arguments;
    task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"GIT_TERMINAL_PROMPT"] = @"0";
    env[@"LC_ALL"] = @"en_US.UTF-8";
    env[@"GIT_PAGER"] = @"cat";
    task.environment = env;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;   // git talks on stderr; the console wants it all in order
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSError *launch = nil;
    if (![task launchAndReturnError:&launch]) { stream([launch.localizedDescription stringByAppendingString:@"\n"]); finished(NO); return; }
    // Read to the end on a thread of its own - a blocking read is the one way
    // that never loses the tail - then wait for the exit status.
    NSFileHandle *reader = pipe.fileHandleForReading;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (;;) {
            NSData *data = [reader availableData];
            if (!data.length) break;
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            dispatch_async(dispatch_get_main_queue(), ^{ stream(text); });
        }
        [task waitUntilExit];
        BOOL ok = task.terminationStatus == 0;
        dispatch_async(dispatch_get_main_queue(), ^{ finished(ok); });
    });
}

#pragma mark Repositories

static NSMutableDictionary<NSString *, id> *gRoots;   // folder -> root, or NSNull for "none"

+ (NSString *)repositoryRootForPath:(NSString *)path {
    if (!path.length || ![self executable]) return nil;
    BOOL isDir = NO;
    NSString *folder = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir ? path : path.stringByDeletingLastPathComponent;
    // Asked from the main thread and from the background refresh alike.
    id cached = nil;
    @synchronized ([NppGit class]) {
        if (!gRoots) gRoots = [NSMutableDictionary dictionary];
        cached = gRoots[folder];
    }
    if (cached) return cached == [NSNull null] ? nil : cached;
    NSString *out = nil;
    NSString *root = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:folder] &&
        [self run:@[@"rev-parse", @"--show-toplevel"] in:folder output:&out error:NULL]) {
        root = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!root.length) root = nil;
    }
    @synchronized ([NppGit class]) { gRoots[folder] = root ?: [NSNull null]; }
    return root;
}

+ (BOOL)cachedRootForPath:(NSString *)path root:(NSString **)root {
    NSString *folder = path.stringByDeletingLastPathComponent;
    id cached = nil;
    @synchronized ([NppGit class]) { cached = gRoots[folder] ?: gRoots[path]; }
    if (!cached) return NO;
    *root = cached == [NSNull null] ? nil : cached;
    return YES;
}

+ (void)forgetRepositoryRoots { @synchronized ([NppGit class]) { [gRoots removeAllObjects]; } }

+ (NSArray<NppGitFileStatus *> *)statusesFromPorcelain:(NSString *)porcelain {
    NSMutableArray *out = [NSMutableArray array];
    // -z: entries end with NUL; a rename carries the old name as the next entry.
    NSArray *parts = [porcelain componentsSeparatedByString:@"\0"];
    for (NSUInteger i = 0; i < parts.count; ++i) {
        NSString *entry = parts[i];
        if (entry.length < 4) continue;
        NppGitFileStatus *s = [[NppGitFileStatus alloc] init];
        s.index = [entry characterAtIndex:0];
        s.worktree = [entry characterAtIndex:1];
        s.path = [entry substringFromIndex:3];
        if ((s.index == 'R' || s.index == 'C' || s.worktree == 'R' || s.worktree == 'C') && i + 1 < parts.count) {
            s.renamedFrom = parts[++i];
        }
        if (s.index == '!' ) continue;   // ignored files are not asked for, but just in case
        [out addObject:s];
    }
    return out;
}

+ (NSArray<NppGitFileStatus *> *)statusOfRepository:(NSString *)root {
    NSString *out = nil;
    if (![self run:@[@"status", @"--porcelain=v1", @"-z", @"--untracked-files=all"] in:root output:&out error:NULL]) return @[];
    return [self statusesFromPorcelain:out];
}

+ (NSString *)branchOfRepository:(NSString *)root ahead:(NSInteger *)ahead behind:(NSInteger *)behind {
    if (ahead) *ahead = 0;
    if (behind) *behind = 0;
    NSString *out = nil;
    if (![self run:@[@"status", @"--porcelain=v2", @"--branch", @"--untracked-files=no"] in:root output:&out error:NULL]) return nil;
    NSString *branch = nil;
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"# branch.head "]) branch = [line substringFromIndex:14];
        else if ([line hasPrefix:@"# branch.ab "]) {
            // "# branch.ab +2 -1"
            NSArray *ab = [[line substringFromIndex:12] componentsSeparatedByString:@" "];
            if (ab.count == 2) {
                if (ahead) *ahead = [[ab[0] substringFromIndex:1] integerValue];
                if (behind) *behind = [[ab[1] substringFromIndex:1] integerValue];
            }
        }
    }
    if ([branch isEqualToString:@"(detached)"]) branch = @"HEAD";
    return branch;
}

+ (NSArray<NSString *> *)branchesOfRepository:(NSString *)root {
    NSString *out = nil;
    if (![self run:@[@"branch", @"--list", @"--format=%(refname:short)"] in:root output:&out error:NULL]) return @[];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) if (line.length) [names addObject:line];
    return names;
}

+ (NSString *)headCommitOfRepository:(NSString *)root {
    NSString *out = nil;
    if (![self run:@[@"rev-parse", @"--verify", @"-q", @"HEAD"] in:root output:&out error:NULL]) return nil;
    NSString *sha = [out stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return sha.length ? sha : nil;
}

+ (NSString *)headContentsOfFile:(NSString *)relativePath inRepository:(NSString *)root {
    NSString *out = nil;
    if (![self run:@[@"show", [NSString stringWithFormat:@"HEAD:%@", relativePath]] in:root output:&out error:NULL]) return nil;
    return out;
}

@end

#pragma mark - The editor's side

static char kGitHeadTextKey, kGitHeadCommitKey, kGitRootKey, kGitStatusTextKey, kGitLastErrorKey, kGitAnswersKey, kGitPanelKey, kGitTimerKey, kGitInstalledKey;

@implementation EditorController (GitCommands)

- (NSString *)gitLastError { return objc_getAssociatedObject(self, &kGitLastErrorKey); }
- (void)setGitLastError:(NSString *)error { objc_setAssociatedObject(self, &kGitLastErrorKey, error, OBJC_ASSOCIATION_COPY); }
- (BOOL)gitAnswersWithoutAsking { return [objc_getAssociatedObject(self, &kGitAnswersKey) boolValue]; }
- (void)setGitAnswersWithoutAsking:(BOOL)yes { objc_setAssociatedObject(self, &kGitAnswersKey, @(yes), OBJC_ASSOCIATION_RETAIN); }

- (void)gitInstall {
    if (objc_getAssociatedObject(self, &kGitInstalledKey)) return;
    objc_setAssociatedObject(self, &kGitInstalledKey, @YES, OBJC_ASSOCIATION_RETAIN);
    for (ScintillaView *sci in @[self.mainSci, self.secondarySci]) {
        // Full-width bars, where Change History's margin beside this one draws
        // narrow ones, and Compare's own words for the three ideas - green for
        // added, amber for changed, red for gone - so the git margin, the
        // comparison and the agent's answers all say the same thing the same way.
        [sci message:SCI_MARKERDEFINE wParam:NPPMAC_GIT_MARKER_ADDED lParam:SC_MARK_FULLRECT];
        [sci message:SCI_MARKERDEFINE wParam:NPPMAC_GIT_MARKER_CHANGED lParam:SC_MARK_FULLRECT];
        [sci message:SCI_MARKERDEFINE wParam:NPPMAC_GIT_MARKER_REMOVED lParam:SC_MARK_SHORTARROW];
        [sci message:SCI_MARKERSETBACK wParam:NPPMAC_GIT_MARKER_ADDED lParam:0x50B050];      // BGR: green
        [sci message:SCI_MARKERSETFORE wParam:NPPMAC_GIT_MARKER_ADDED lParam:0x50B050];
        [sci message:SCI_MARKERSETBACK wParam:NPPMAC_GIT_MARKER_CHANGED lParam:0x30A0E0];    // amber
        [sci message:SCI_MARKERSETFORE wParam:NPPMAC_GIT_MARKER_CHANGED lParam:0x30A0E0];
        [sci message:SCI_MARKERSETBACK wParam:NPPMAC_GIT_MARKER_REMOVED lParam:0x3030E0];    // red
        [sci message:SCI_MARKERSETFORE wParam:NPPMAC_GIT_MARKER_REMOVED lParam:0x3030E0];
        [sci message:SCI_SETMARGINTYPEN wParam:NPPMAC_GIT_MARGIN lParam:SC_MARGIN_SYMBOL];
        [sci message:SCI_SETMARGINMASKN wParam:NPPMAC_GIT_MARGIN lParam:kGitMarkerMask];
        [sci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_GIT_MARGIN lParam:0];
        [sci message:SCI_SETMARGINSENSITIVEN wParam:NPPMAC_GIT_MARGIN lParam:0];
    }
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[NppDocumentOpenedNotification, NppDocumentSavedNotification, NppBufferActivatedNotification]) {
        [nc addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
            [self gitRefreshStateInBackground];
        }];
    }
    [nc addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        // Something may have been committed or pulled in a terminal meanwhile.
        [NppGit forgetRepositoryRoots];
        [self gitRefreshStateInBackground];
    }];
}

- (NSString *)gitRootOfDocument:(NppDocument *)doc {
    return doc.path ? [NppGit repositoryRootForPath:doc.path] : nil;
}
- (NSString *)gitRootOfCurrentDocument { return [self gitRootOfDocument:self.currentDocument]; }

static NSString *GitRelativePath(NSString *documentPath, NSString *root) {
    if (!root || !documentPath) return nil;
    // The repository root git reports has symlinks resolved; the document's path may not.
    NSString *path = documentPath.stringByResolvingSymlinksInPath;
    NSString *base = [root.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    if (![path hasPrefix:base]) {
        base = [root stringByAppendingString:@"/"];
        path = documentPath;
        if (![path hasPrefix:base]) return nil;
    }
    return [path substringFromIndex:base.length];
}

- (NSString *)gitRelativePathOfDocument:(NppDocument *)doc {
    return GitRelativePath(doc.path, [self gitRootOfDocument:doc]);
}

#pragma mark Markers

/// HEAD's text of the document in front, fetched again only when HEAD moved.
/// `cachedOnly`: what is known already, with no git run - for the refresh
/// after typing, which must not wait on a process (waiting spins the run
/// loop, and the margin would be drawn empty in between).
- (NSString *)gitHeadTextOfCurrentDocumentInRoot:(NSString *)root cachedOnly:(BOOL)cachedOnly {
    NppDocument *doc = self.currentDocument;
    NSString *known = objc_getAssociatedObject(doc, &kGitHeadCommitKey);
    if (cachedOnly && known) {
        id text = objc_getAssociatedObject(doc, &kGitHeadTextKey);
        return text == [NSNull null] ? nil : text;
    }
    NSString *head = [NppGit headCommitOfRepository:root] ?: @"";
    if ([known isEqualToString:head]) {
        id text = objc_getAssociatedObject(doc, &kGitHeadTextKey);
        return text == [NSNull null] ? nil : text;
    }
    NSString *relative = [self gitRelativePathOfDocument:doc];
    NSString *text = relative ? [NppGit headContentsOfFile:relative inRepository:root] : nil;
    objc_setAssociatedObject(doc, &kGitHeadCommitKey, head, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(doc, &kGitHeadTextKey, text ?: [NSNull null], OBJC_ASSOCIATION_RETAIN);
    return text;
}

- (void)gitRefreshMarkers { [self gitRefreshMarkersCachedOnly:NO]; }

- (void)gitRefreshMarkersCachedOnly:(BOOL)cachedOnly {
    ScintillaView *sci = self.sci;
    NSString *root = [NppPreferences shared].gitMarginMarks ? [self gitRootOfCurrentDocument] : nil;
    [sci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_GIT_MARGIN lParam:root ? 6 : 0];
    if (!root) {
        [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_ADDED lParam:0];
        [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_CHANGED lParam:0];
        [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_REMOVED lParam:0];
        return;
    }
    // Everything that can take time - git, the diff - comes first; the markers
    // are then replaced in one go, with no chance of a redraw in between.
    NSString *head = [self gitHeadTextOfCurrentDocumentInRoot:root cachedOnly:cachedOnly];
    NSArray<NSString *> *now = [EditorController linesForComparison:[self documentText]];
    NSArray<NppDiffLine *> *diff;
    if (head) {
        diff = [EditorController diffBetween:[EditorController linesForComparison:head] and:now
                                  ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
    } else {
        // Not in HEAD: every line is new.
        NSMutableArray *all = [NSMutableArray array];
        for (NSUInteger i = 0; i < now.count; ++i) {
            NppDiffLine *d = [[NppDiffLine alloc] init];
            d.kind = NppDiffAdded; d.oldLine = -1; d.newLine = (NSInteger)i;
            [all addObject:d];
        }
        diff = all;
    }
    BOOL removedPending = NO;
    long lines = [sci message:SCI_GETLINECOUNT];
    [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_ADDED lParam:0];
    [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_CHANGED lParam:0];
    [sci message:SCI_MARKERDELETEALL wParam:NPPMAC_GIT_MARKER_REMOVED lParam:0];
    for (NppDiffLine *d in diff) {
        if (d.kind == NppDiffRemoved) { removedPending = YES; continue; }
        if (d.newLine < 0 || d.newLine >= lines) continue;
        if (d.kind == NppDiffAdded) [sci message:SCI_MARKERADD wParam:(uptr_t)d.newLine lParam:NPPMAC_GIT_MARKER_ADDED];
        else if (d.kind == NppDiffChanged) [sci message:SCI_MARKERADD wParam:(uptr_t)d.newLine lParam:NPPMAC_GIT_MARKER_CHANGED];
        if (removedPending) {
            [sci message:SCI_MARKERADD wParam:(uptr_t)d.newLine lParam:NPPMAC_GIT_MARKER_REMOVED];
            removedPending = NO;
        }
    }
    if (removedPending && lines > 0) [sci message:SCI_MARKERADD wParam:(uptr_t)(lines - 1) lParam:NPPMAC_GIT_MARKER_REMOVED];
}

- (void)gitScheduleMarkerRefresh {
    if (![self gitRootOfCurrentDocument]) return;
    if ([self.sci message:SCI_GETLENGTH] > kMostBytesDiffedLive) return;
    NSTimer *pending = objc_getAssociatedObject(self, &kGitTimerKey);
    [pending invalidate];
    __weak EditorController *weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:NO block:^(NSTimer *t) {
        // Judged again when it fires: the document in front may be another by
        // then, one too big to be diffed while typing.
        if ([weakSelf.sci message:SCI_GETLENGTH] > kMostBytesDiffedLive) return;
        [weakSelf gitRefreshMarkersCachedOnly:YES];
    }];
    objc_setAssociatedObject(self, &kGitTimerKey, timer, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark State

- (NSString *)gitStatusBarText { return objc_getAssociatedObject(self, &kGitStatusTextKey) ?: @""; }

/// Bumped by every refresh, so a background one that a later refresh overtook is dropped.
static NSUInteger gGitRefreshGeneration;

/// gitRefreshState for opening, saving, switching tabs and coming to front: the
/// git runs (rev-parse, status, show) go to a queue of their own, since in a large
/// repository they take long enough to stall every tab switch, and the result is
/// applied if that document is still in front and no later refresh came first.
- (void)gitRefreshStateInBackground {
    NppDocument *doc = self.currentDocument;
    NSString *path = doc.path;
    // A document known to be in no repository needs no git at all: its state
    // (nothing in the status bar, no margin) is shown at once, not after the
    // previous tab's branch lingered.
    NSString *knownRoot = nil;
    BOOL rootKnown = path && [NppGit cachedRootForPath:path root:&knownRoot];
    if (!path || (rootKnown && !knownRoot)) { [self gitRefreshState]; return; }
    NSUInteger generation = ++gGitRefreshGeneration;
    NSString *known = objc_getAssociatedObject(doc, &kGitHeadCommitKey);
    BOOL marks = [NppPreferences shared].gitMarginMarks;
    ScintillaView *sci = self.sci;
    // The margin a repository's document has is there at once (its markers are the
    // document's own and came with it); only what git has to say comes later.
    if (knownRoot && marks) [sci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_GIT_MARGIN lParam:6];
    // Whether the text changed while git ran: the markers are then left to the
    // refresh typing schedules, as they would have been had they been made first.
    NSArray *(^textState)(void) = ^NSArray *{
        return @[@([sci message:SCI_GETLENGTH]), @([sci message:SCI_GETUNDOACTIONS]), @([sci message:SCI_GETUNDOCURRENT])];
    };
    NSArray *textBefore = textState();
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("org.notepad-plus-plus.mac.git", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        NSString *root = path ? [NppGit repositoryRootForPath:path] : nil;
        NSString *text = @"";
        if (root) {
            NSInteger ahead = 0, behind = 0;
            NSString *branch = [NppGit branchOfRepository:root ahead:&ahead behind:&behind];
            if (branch.length) {
                NSMutableString *s = [NSMutableString stringWithFormat:@"⎇ %@", branch];
                if (ahead) [s appendFormat:@" ↑%ld", (long)ahead];
                if (behind) [s appendFormat:@" ↓%ld", (long)behind];
                text = s;
            }
        }
        // HEAD's text as gitHeadTextOfCurrentDocumentInRoot fetches it: again only when HEAD moved.
        NSString *head = nil, *headText = nil;
        BOOL fetched = NO;
        if (root && marks) {
            head = [NppGit headCommitOfRepository:root] ?: @"";
            if (![known isEqualToString:head]) {
                NSString *relative = GitRelativePath(path, root);
                headText = relative ? [NppGit headContentsOfFile:relative inRepository:root] : nil;
                fetched = YES;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != gGitRefreshGeneration || self.currentDocument != doc) return;
            if (fetched) {
                objc_setAssociatedObject(doc, &kGitHeadCommitKey, head, OBJC_ASSOCIATION_COPY);
                objc_setAssociatedObject(doc, &kGitHeadTextKey, headText ?: [NSNull null], OBJC_ASSOCIATION_RETAIN);
            }
            objc_setAssociatedObject(self, &kGitStatusTextKey, text, OBJC_ASSOCIATION_COPY);
            objc_setAssociatedObject(self, &kGitRootKey, root, OBJC_ASSOCIATION_COPY);
            if ([textState() isEqualToArray:textBefore]) [self gitRefreshMarkersCachedOnly:YES];   // HEAD's text is known now: no git run
            else {
                [sci message:SCI_SETMARGINWIDTHN wParam:NPPMAC_GIT_MARGIN lParam:root && marks ? 6 : 0];
                [self gitScheduleMarkerRefresh];   // not for a big file: it is diffed on save
            }
            [self refreshChrome];
            NppGitPanel *panel = objc_getAssociatedObject(self, &kGitPanelKey);
            if (panel.visible) [panel reload];
        });
    });
}

- (void)gitRefreshState {
    ++gGitRefreshGeneration;
    NSString *root = [self gitRootOfCurrentDocument];
    NSString *text = @"";
    if (root) {
        NSInteger ahead = 0, behind = 0;
        NSString *branch = [NppGit branchOfRepository:root ahead:&ahead behind:&behind];
        if (branch.length) {
            NSMutableString *s = [NSMutableString stringWithFormat:@"⎇ %@", branch];
            if (ahead) [s appendFormat:@" ↑%ld", (long)ahead];
            if (behind) [s appendFormat:@" ↓%ld", (long)behind];
            text = s;
        }
    }
    objc_setAssociatedObject(self, &kGitStatusTextKey, text, OBJC_ASSOCIATION_COPY);
    objc_setAssociatedObject(self, &kGitRootKey, root, OBJC_ASSOCIATION_COPY);
    [self gitRefreshMarkers];
    [self refreshChrome];
    NppGitPanel *panel = objc_getAssociatedObject(self, &kGitPanelKey);
    if (panel.visible) [panel reload];
}

#pragma mark Commands

- (BOOL)gitFailWithoutRepository {
    if (![NppGit executable]) { self.gitLastError = NppL(@"Git is not installed (xcode-select --install)"); NppBeep(); return YES; }
    if (![self gitRootOfCurrentDocument]) { self.gitLastError = NppL(@"The file is not in a Git repository"); NppBeep(); return YES; }
    return NO;
}

/// A new read-only document beside the current one, for blame and history.
- (void)gitShowText:(NSString *)text titled:(NSString *)title {
    [self newDocument];
    [self setDocumentText:text];
    [self.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.displayName = title;
    [self setReadOnly:YES];
    [self refreshChrome];
}

- (BOOL)gitCompareWithHead {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *root = [self gitRootOfCurrentDocument];
    NSString *head = [self gitHeadTextOfCurrentDocumentInRoot:root cachedOnly:NO];
    if (!head) { self.gitLastError = NppL(@"The file is not in HEAD yet"); NppBeep(); return NO; }
    // Compare takes a file; HEAD's text is written beside the temporary files under the document's name.
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"NotepadMac-git-HEAD"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"HEAD %@", self.currentDocument.displayName]];
    if (![head writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL]) { self.gitLastError = @"Cannot write the temporary file"; return NO; }
    return [self compareWithFileAtPath:path];
}

- (BOOL)gitRevertChangeAtCaret {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *root = [self gitRootOfCurrentDocument];
    NSString *head = [self gitHeadTextOfCurrentDocumentInRoot:root cachedOnly:NO];
    if (!head) { self.gitLastError = NppL(@"The file is not in HEAD yet"); NppBeep(); return NO; }
    ScintillaView *sci = self.sci;
    NSArray<NSString *> *old = [EditorController linesForComparison:head];
    NSArray<NSString *> *now = [EditorController linesForComparison:[self documentText]];
    NSArray<NppDiffLine *> *diff = [EditorController diffBetween:old and:now ignoreCase:NO ignoreSpaces:NO ignoreEmptyLines:NO];
    long caretLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS] lParam:0];
    long lineCount = [sci message:SCI_GETLINECOUNT];

    // The runs of the diff: each a stretch of lines that differ, with the new-side lines it
    // covers and the old-side lines that stood there. A pure removal covers no new line; it
    // sits before the next unchanged line, where the margin shows its mark.
    NSInteger newFirst = -1, newLast = -1, oldFirst = -1, oldLast = -1, anchor = -1;
    BOOL found = NO;
    NSUInteger i = 0;
    while (i < diff.count && !found) {
        if (diff[i].kind == NppDiffSame) { i++; continue; }
        newFirst = newLast = oldFirst = oldLast = -1;
        NSUInteger j = i;
        for (; j < diff.count && diff[j].kind != NppDiffSame; ++j) {
            NppDiffLine *d = diff[j];
            if (d.newLine >= 0) { if (newFirst < 0) newFirst = d.newLine; newLast = d.newLine; }
            if (d.oldLine >= 0) { if (oldFirst < 0) oldFirst = d.oldLine; oldLast = d.oldLine; }
        }
        anchor = j < diff.count ? diff[j].newLine : (NSInteger)now.count - 1;
        if (newFirst >= 0 ? (caretLine >= newFirst && caretLine <= newLast) : caretLine == anchor) found = YES;
        i = j;
    }
    if (!found) { self.gitLastError = NppL(@"The caret is on no change since the last commit"); NppBeep(); return NO; }

    NSString *eol = self.currentDocument.eolMode == SC_EOL_CRLF ? @"\r\n" : self.currentDocument.eolMode == SC_EOL_CR ? @"\r" : @"\n";
    NSMutableString *replacement = [NSMutableString string];
    for (NSInteger k = oldFirst; oldFirst >= 0 && k <= oldLast; ++k) [replacement appendFormat:@"%@%@", old[(NSUInteger)k], eol];
    long from, to;
    if (newFirst >= 0) {
        from = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)newFirst lParam:0];
        // Through the ending of the last changed line; at the very end of the text there may be none.
        BOOL endingKept = newLast + 1 < lineCount;
        to = endingKept ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)(newLast + 1) lParam:0] : [sci message:SCI_GETLENGTH wParam:0 lParam:0];
        if (!endingKept && [replacement hasSuffix:eol]) [replacement deleteCharactersInRange:NSMakeRange(replacement.length - eol.length, eol.length)];
    } else {
        from = to = anchor < lineCount ? [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)anchor lParam:0] : [sci message:SCI_GETLENGTH wParam:0 lParam:0];
    }
    NSData *utf8 = [replacement dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
    [sci message:SCI_SETTARGETRANGE wParam:(uptr_t)from lParam:to];
    [sci message:SCI_REPLACETARGET wParam:(uptr_t)utf8.length lParam:(sptr_t)utf8.bytes];
    [sci message:SCI_ENDUNDOACTION wParam:0 lParam:0];
    [sci message:SCI_GOTOPOS wParam:(uptr_t)from lParam:0];
    [self gitRefreshMarkersCachedOnly:YES];
    [self refreshChrome];
    return YES;
}

- (BOOL)gitBlame {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *root = [self gitRootOfCurrentDocument], *relative = [self gitRelativePathOfDocument:self.currentDocument];
    NSString *out = nil, *err = nil;
    if (![NppGit run:@[@"blame", @"--date=short", @"--", relative] in:root output:&out error:&err]) { self.gitLastError = err; NppBeep(); return NO; }
    [self gitShowText:out titled:[NSString stringWithFormat:@"%@ (blame)", relative.lastPathComponent]];
    return YES;
}

- (BOOL)gitFileHistory {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *root = [self gitRootOfCurrentDocument], *relative = [self gitRelativePathOfDocument:self.currentDocument];
    NSString *out = nil, *err = nil;
    if (![NppGit run:@[@"log", @"--follow", @"--date=short", @"--format=%h  %ad  %an%n    %s%n", @"--", relative]
                 in:root output:&out error:&err]) { self.gitLastError = err; NppBeep(); return NO; }
    if (!out.length) out = [NppL(@"The file is not in HEAD yet") stringByAppendingString:@"\n"];
    [self gitShowText:out titled:[NSString stringWithFormat:@"%@ (history)", relative.lastPathComponent]];
    return YES;
}

- (BOOL)gitRun:(NSArray<NSString *> *)arguments {
    NSString *root = [self gitRootOfCurrentDocument];
    NSString *err = nil;
    BOOL ok = [NppGit run:arguments in:root output:NULL error:&err];
    if (!ok) { self.gitLastError = err.length ? err : @"git failed"; NppBeep(); }
    [self gitRefreshState];
    return ok;
}

- (BOOL)gitStagePaths:(NSArray<NSString *> *)relativePaths {
    if ([self gitFailWithoutRepository] || !relativePaths.count) return NO;
    return [self gitRun:[@[@"add", @"-A", @"--"] arrayByAddingObjectsFromArray:relativePaths]];
}

- (BOOL)gitUnstagePaths:(NSArray<NSString *> *)relativePaths {
    if ([self gitFailWithoutRepository] || !relativePaths.count) return NO;
    // `reset` needs a HEAD to reset to; before the first commit, `rm --cached` takes a file out of the index.
    NSString *root = [self gitRootOfCurrentDocument];
    if ([NppGit headCommitOfRepository:root]) return [self gitRun:[@[@"reset", @"-q", @"HEAD", @"--"] arrayByAddingObjectsFromArray:relativePaths]];
    return [self gitRun:[@[@"rm", @"-r", @"-q", @"--cached", @"--"] arrayByAddingObjectsFromArray:relativePaths]];
}

- (BOOL)gitDiscardPaths:(NSArray<NSString *> *)relativePaths {
    if ([self gitFailWithoutRepository] || !relativePaths.count) return NO;
    NSString *root = [self gitRootOfCurrentDocument];
    // Tracked files go back to the index's version; untracked ones are removed, as "discard" means for them.
    NSMutableArray *tracked = [NSMutableArray array], *untracked = [NSMutableArray array];
    NSArray *statuses = [NppGit statusOfRepository:root];
    for (NSString *p in relativePaths) {
        BOOL isUntracked = NO;
        for (NppGitFileStatus *s in statuses) if ([s.path isEqualToString:p] && s.untracked) isUntracked = YES;
        [isUntracked ? untracked : tracked addObject:p];
    }
    BOOL ok = YES;
    if (tracked.count) ok = [self gitRun:[@[@"checkout", @"--"] arrayByAddingObjectsFromArray:tracked]] && ok;
    if (untracked.count) ok = [self gitRun:[@[@"clean", @"-f", @"-q", @"--"] arrayByAddingObjectsFromArray:untracked]] && ok;
    // A discarded file that is open is read back, or the tab would keep the old text.
    for (NSString *p in relativePaths) {
        NSString *full = [root stringByAppendingPathComponent:p];
        for (NppDocument *d in self.documents) {
            if ([d.path isEqualToString:full] || [d.path.stringByResolvingSymlinksInPath isEqualToString:full.stringByResolvingSymlinksInPath]) {
                NSUInteger index = [self.documents indexOfObjectIdenticalTo:d];
                if (d == self.currentDocument) [self reloadCurrentDocument:NULL];
                else { NppDocument *front = self.currentDocument; [self selectDocumentAtIndex:(NSInteger)index]; [self reloadCurrentDocument:NULL];
                       [self selectDocumentAtIndex:(NSInteger)[self.documents indexOfObjectIdenticalTo:front]]; }
            }
        }
    }
    [self gitRefreshState];
    return ok;
}

- (BOOL)gitAsk:(NSString *)question detail:(NSString *)detail button:(NSString *)button {
    if (self.gitAnswersWithoutAsking) return YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = question;
    alert.informativeText = detail;
    [alert addButtonWithTitle:button];
    [alert addButtonWithTitle:NppL(@"Cancel")];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (BOOL)gitStageCurrent {
    if ([self gitFailWithoutRepository]) return NO;
    if (self.currentDocument.modified && !self.gitAnswersWithoutAsking) {
        // What is staged is what is on disk; an unsaved document would stage the old text.
        if (![self gitAsk:NppL(@"Save the file before staging it?") detail:@"" button:NppL(@"Save")]) return NO;
    }
    if (self.currentDocument.modified && ![self saveCurrentDocument]) return NO;
    return [self gitStagePaths:@[[self gitRelativePathOfDocument:self.currentDocument]]];
}

- (BOOL)gitUnstageCurrent {
    if ([self gitFailWithoutRepository]) return NO;
    return [self gitUnstagePaths:@[[self gitRelativePathOfDocument:self.currentDocument]]];
}

- (BOOL)gitDiscardCurrent {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *name = self.currentDocument.displayName;
    if (![self gitAsk:NppLMessage(@"Discard the changes in \"$STR_REPLACE$\"?", name, 0)
               detail:NppL(@"The file goes back to the last committed version. This cannot be undone.")
               button:NppL(@"Discard")]) return NO;
    return [self gitDiscardPaths:@[[self gitRelativePathOfDocument:self.currentDocument]]];
}

- (BOOL)gitCommitWithMessage:(NSString *)message stageAll:(BOOL)stageAll commit:(NSString **)commit {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *root = [self gitRootOfCurrentDocument];
    NSString *trimmed = [message stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) { self.gitLastError = NppL(@"A commit needs a message"); return NO; }
    NSString *err = nil;
    if (stageAll && ![NppGit run:@[@"add", @"-A"] in:root output:NULL error:&err]) { self.gitLastError = err; return NO; }
    BOOL anyStaged = NO;
    for (NppGitFileStatus *s in [NppGit statusOfRepository:root]) if (s.staged) anyStaged = YES;
    if (!anyStaged) { self.gitLastError = NppL(@"Nothing is staged to commit"); return NO; }
    if (![NppGit run:@[@"commit", @"-q", @"-m", trimmed] in:root output:NULL error:&err]) {
        self.gitLastError = err.length ? err : @"git commit failed";
        [self gitRefreshState];
        return NO;
    }
    if (commit) *commit = [NppGit headCommitOfRepository:root];
    // HEAD moved: every open document of this repository is diffed against it again.
    for (NppDocument *d in self.documents) objc_setAssociatedObject(d, &kGitHeadCommitKey, nil, OBJC_ASSOCIATION_COPY);
    [self gitRefreshState];
    return YES;
}

- (BOOL)gitCheckoutBranch:(NSString *)name {
    if ([self gitFailWithoutRepository]) return NO;
    BOOL ok = [self gitRun:@[@"checkout", @"-q", name]];
    if (ok) { [self checkFilesOnDisk]; for (NppDocument *d in self.documents) objc_setAssociatedObject(d, &kGitHeadCommitKey, nil, OBJC_ASSOCIATION_COPY); [self gitRefreshState]; }
    return ok;
}

- (BOOL)gitCreateBranch:(NSString *)name {
    if ([self gitFailWithoutRepository]) return NO;
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) { self.gitLastError = NppL(@"A branch needs a name"); return NO; }
    return [self gitRun:@[@"checkout", @"-q", @"-b", trimmed]];
}

- (void)gitRunInConsole:(NSArray<NSString *> *)arguments {
    if ([self gitFailWithoutRepository]) { [self.console showWithoutFocus]; [self.console appendText:[self.gitLastError stringByAppendingString:@"\n"]]; return; }
    NSString *root = [self gitRootOfCurrentDocument];
    [self.console showWithoutFocus];
    [self.console appendText:[NSString stringWithFormat:@"$ git %@\n", [arguments componentsJoinedByString:@" "]]];
    __weak EditorController *weakSelf = self;
    [NppGit run:arguments in:root stream:^(NSString *text) {
        [weakSelf.console appendText:text];
    } finished:^(BOOL ok) {
        [weakSelf.console appendText:ok ? @"- done\n" : @"- git failed\n"];
        [NppGit forgetRepositoryRoots];
        for (NppDocument *d in weakSelf.documents) objc_setAssociatedObject(d, &kGitHeadCommitKey, nil, OBJC_ASSOCIATION_COPY);
        [weakSelf checkFilesOnDisk];
        [weakSelf gitRefreshState];
    }];
}

- (void)gitFetch { [self gitRunInConsole:@[@"fetch", @"--all", @"--prune"]]; }
- (void)gitPull { [self gitRunInConsole:@[@"pull"]]; }
- (void)gitPush { [self gitRunInConsole:@[@"push"]]; }

@end

#pragma mark - The panel

/// A row of buttons that wraps: a panel is narrow, and a language's words are
/// as long as they are. Laid out by hand from the buttons' own sizes; its
/// height follows the number of rows that took.
@interface NppButtonFlow : NSView
@property (nonatomic, copy) NSArray<NSView *> *items;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@end

@implementation NppButtonFlow
- (BOOL)isFlipped { return YES; }
- (void)setItems:(NSArray<NSView *> *)items {
    for (NSView *v in _items) [v removeFromSuperview];
    _items = [items copy];
    for (NSView *v in items) { v.translatesAutoresizingMaskIntoConstraints = YES; [self addSubview:v]; }
    [self setNeedsLayout:YES];
}
- (void)layout {
    [super layout];
    const CGFloat gap = 6, rowGap = 4, width = NSWidth(self.bounds);
    CGFloat x = 0, y = 0, rowHeight = 0;
    for (NSView *v in self.items) {
        NSSize size = v.fittingSize;
        if (x > 0 && x + size.width > width) { x = 0; y += rowHeight + rowGap; rowHeight = 0; }
        v.frame = NSMakeRect(x, y, size.width, size.height);
        x += size.width + gap;
        rowHeight = MAX(rowHeight, size.height);
    }
    CGFloat height = self.items.count ? y + rowHeight : 0;
    if (self.heightConstraint && fabs(self.heightConstraint.constant - height) > 0.5) {
        self.heightConstraint.constant = height;
        [self.superview setNeedsLayout:YES];
    }
}
- (void)setFrameSize:(NSSize)size { [super setFrameSize:size]; [self setNeedsLayout:YES]; }
@end

@interface NppGitPanel () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTextField *branchLabel;
@property (nonatomic, strong) NppButtonFlow *buttons;   // their English titles are their identifiers, for relocalize
@property (nonatomic, copy) NSArray<NppGitFileStatus *> *rows;
@property (nonatomic, copy) NSString *root;
@end

@implementation NppGitPanel

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _rows = @[];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 400)];
    content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // A row of buttons above the list that wraps when the panel is narrow or the language long.
    NppButtonFlow *buttons = [[NppButtonFlow alloc] initWithFrame:NSMakeRect(0, 0, 348, 28)];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *(^button)(NSString *, SEL) = ^NSButton *(NSString *title, SEL action) {
        NSButton *b = [NSButton buttonWithTitle:NppL(title) target:self action:action];
        b.identifier = title;
        return b;
    };
    buttons.items = @[button(@"Stage", @selector(stageSelected:)), button(@"Unstage", @selector(unstageSelected:)),
                      button(@"Discard", @selector(discardSelected:)), button(@"Commit", @selector(commitPressed:)),
                      button(@"Refresh", @selector(refreshPressed:))];
    buttons.heightConstraint = [buttons.heightAnchor constraintEqualToConstant:28];
    buttons.heightConstraint.active = YES;
    _buttons = buttons;

    _branchLabel = [NSTextField labelWithString:@""];
    _branchLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _branchLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _branchLabel.textColor = [NSColor secondaryLabelColor];
    _branchLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 360, 300)];
    NSDictionary *titles = @{@"staged": @"Staged", @"status": @"Status", @"file": @"File"};
    for (NSString *identifier in @[@"staged", @"status", @"file"]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:identifier];
        col.title = NppL(titles[identifier]);
        col.minWidth = 36;
        col.editable = NO;
        [_table addTableColumn:col];
    }
    // A panel narrower or wider than the table was made: the file column gives or takes the difference,
    // the two narrow ones keep their headings' width.
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    [self fitColumns];
    _table.allowsMultipleSelection = YES;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(rowDoubleClicked:);
    _table.usesAlternatingRowBackgroundColors = YES;
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.documentView = _table;
    // The file column reaches the panel's edge whatever the panel's width (the dock's divider, a
    // floating window resized): a table only adjusts its columns when told.
    scroll.contentView.postsFrameChangedNotifications = YES;
    __weak NSTableView *weakTable = _table;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification object:scroll.contentView
                                                       queue:nil usingBlock:^(NSNotification *n) { [weakTable sizeLastColumnToFit]; }];

    [content addSubview:buttons];
    [content addSubview:_branchLabel];
    [content addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [buttons.topAnchor constraintEqualToAnchor:content.topAnchor constant:6],
        [buttons.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:6],
        [buttons.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-6],
        [_branchLabel.topAnchor constraintEqualToAnchor:buttons.bottomAnchor constant:4],
        [_branchLabel.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8],
        [_branchLabel.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8],
        [scroll.topAnchor constraintEqualToAnchor:_branchLabel.bottomAnchor constant:4],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];
    [[NppDockingManager shared] registerPanel:@"git" title:@"Git" view:content defaultPlace:NppDockRight];
    return self;
}

/// The two narrow columns are as wide as their headings, in whatever language; the file column takes the rest.
- (void)fitColumns {
    for (NSTableColumn *col in self.table.tableColumns) {
        if ([col.identifier isEqualToString:@"file"]) { col.width = 230; continue; }
        col.width = MAX(36, ceil(col.headerCell.cellSize.width) + 12);
    }
    [self.table sizeLastColumnToFit];
}

/// The interface language changed: the buttons and columns say it in the new one.
- (void)relocalize {
    for (NSView *v in self.buttons.items) {
        if ([v isKindOfClass:[NSButton class]] && v.identifier.length) { ((NSButton *)v).title = NppL(v.identifier); [(NSButton *)v sizeToFit]; }
    }
    [self.buttons setNeedsLayout:YES];
    NSDictionary *titles = @{@"staged": @"Staged", @"status": @"Status", @"file": @"File"};
    for (NSTableColumn *col in self.table.tableColumns) col.title = NppL(titles[col.identifier] ?: col.identifier);
    [self fitColumns];
    [self reload];
}

- (BOOL)visible { return [[NppDockingManager shared] isPanelVisible:@"git"]; }
- (void)show { [self reload]; [[NppDockingManager shared] showPanel:@"git"]; }
- (void)toggle {
    if (self.visible) [[NppDockingManager shared] hidePanel:@"git"];
    else [self show];
}

- (void)reload {
    EditorController *ed = self.editor;
    self.root = [ed gitRootOfCurrentDocument];
    if (!self.root) {
        self.rows = @[];
        self.branchLabel.stringValue = ![NppGit executable] ? NppL(@"Git is not installed (xcode-select --install)")
                                     : ed.currentDocument.path ? NppL(@"The file is not in a Git repository") : @"";
        [self.table reloadData];
        return;
    }
    NSArray<NppGitFileStatus *> *statuses = [NppGit statusOfRepository:self.root];
    self.rows = [statuses sortedArrayUsingComparator:^NSComparisonResult(NppGitFileStatus *a, NppGitFileStatus *b) {
        // Staged first, then changed, then untracked; by path within.
        int ra = a.staged ? 0 : a.untracked ? 2 : 1, rb = b.staged ? 0 : b.untracked ? 2 : 1;
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        return [a.path compare:b.path];
    }];
    NSInteger ahead = 0, behind = 0;
    NSString *branch = [NppGit branchOfRepository:self.root ahead:&ahead behind:&behind] ?: @"";
    NSMutableString *label = [NSMutableString stringWithFormat:@"%@  ·  %@", branch, self.root.lastPathComponent];
    if (ahead) [label appendFormat:@"  ↑%ld", (long)ahead];
    if (behind) [label appendFormat:@"  ↓%ld", (long)behind];
    NSUInteger staged = 0;
    for (NppGitFileStatus *s in self.rows) if (s.staged) staged++;
    if (self.rows.count) [label appendFormat:@"  ·  %@", NppLMessage(@"$INT_REPLACE$ changed", nil, (NSInteger)self.rows.count)];
    if (staged) [label appendFormat:@", %@", NppLMessage(@"$INT_REPLACE$ staged", nil, (NSInteger)staged)];
    self.branchLabel.stringValue = label;
    [self.table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)self.rows.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = column.identifier;
        cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    NppGitFileStatus *s = self.rows[(NSUInteger)row];
    if ([column.identifier isEqualToString:@"staged"]) cell.stringValue = s.staged ? @"✓" : @"";
    else if ([column.identifier isEqualToString:@"status"]) cell.stringValue = s.shortStatus;
    else cell.stringValue = s.renamedFrom ? [NSString stringWithFormat:@"%@ ← %@", s.path, s.renamedFrom] : s.path;
    cell.alignment = [column.identifier isEqualToString:@"file"] ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    // A path that does not fit keeps its file name and loses its folders.
    cell.lineBreakMode = [column.identifier isEqualToString:@"file"] ? NSLineBreakByTruncatingHead : NSLineBreakByTruncatingMiddle;
    return cell;
}

- (NSArray<NSString *> *)selectedPaths {
    NSMutableArray *paths = [NSMutableArray array];
    [self.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) {
        if (i < self.rows.count) [paths addObject:self.rows[i].path];
    }];
    return paths;
}

- (void)stageSelected:(id)sender { [self.editor gitStagePaths:[self selectedPaths]]; [self reload]; }
- (void)unstageSelected:(id)sender { [self.editor gitUnstagePaths:[self selectedPaths]]; [self reload]; }
- (void)discardSelected:(id)sender {
    NSArray *paths = [self selectedPaths];
    if (!paths.count) { NppBeep(); return; }
    EditorController *ed = self.editor;
    NSString *what = paths.count == 1 ? paths[0] : [NSString stringWithFormat:@"%lu files", (unsigned long)paths.count];
    if (![ed gitAsk:NppLMessage(@"Discard the changes in \"$STR_REPLACE$\"?", what, 0)
              detail:NppL(@"The file goes back to the last committed version. This cannot be undone.")
              button:NppL(@"Discard")]) return;
    [ed gitDiscardPaths:paths];
    [self reload];
}
- (void)commitPressed:(id)sender { [[NppCommitWindow shared] showForEditor:self.editor]; }
- (void)refreshPressed:(id)sender { [NppGit forgetRepositoryRoots]; [self.editor gitRefreshState]; [self reload]; }

- (void)rowDoubleClicked:(id)sender {
    NSInteger row = self.table.clickedRow;
    if (row < 0 || row >= (NSInteger)self.rows.count) return;
    NSString *full = [self.root stringByAppendingPathComponent:self.rows[(NSUInteger)row].path];
    if ([[NSFileManager defaultManager] fileExistsAtPath:full]) [self.editor openFileAtPath:full error:NULL];
}

@end

@implementation EditorController (GitPanel)
- (NppGitPanel *)gitPanel {
    NppGitPanel *panel = objc_getAssociatedObject(self, &kGitPanelKey);
    if (!panel) {
        panel = [[NppGitPanel alloc] initWithEditor:self];
        objc_setAssociatedObject(self, &kGitPanelKey, panel, OBJC_ASSOCIATION_RETAIN);
    }
    return panel;
}
@end

#pragma mark - The commit window

@interface NppCommitWindow () <NSTextViewDelegate>
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, strong) NSTextView *message;
@property (nonatomic, strong) NSButton *stageAll, *commitButton;
@property (nonatomic, strong) NSTextField *stagedSummary, *problem, *messageLabel;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, copy) NSString *lastCommit;
@end

@implementation NppCommitWindow

+ (instancetype)shared {
    static NppCommitWindow *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppCommitWindow alloc] init]; });
    return one;
}

- (void)build {
    if (self.panel) return;
    NSPanel *panel = [[NppPanel alloc] initWithContentRect:NSMakeRect(0, 0, 520, 320)
                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                 backing:NSBackingStoreBuffered defer:YES];
    panel.title = NppL(@"Commit");
    panel.releasedWhenClosed = NO;
    NSView *content = panel.contentView;

    NSTextField *label = [NSTextField labelWithString:NppL(@"Commit message")];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    _messageLabel = label;
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 480, 120)];
    text.minSize = NSMakeSize(0, 120);
    text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    text.verticallyResizable = YES;
    text.horizontallyResizable = NO;
    text.autoresizingMask = NSViewWidthSizable;
    text.textContainer.widthTracksTextView = YES;
    text.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    text.richText = NO;
    text.automaticQuoteSubstitutionEnabled = NO;
    text.delegate = self;
    scroll.documentView = text;
    _message = text;

    _stagedSummary = [NSTextField wrappingLabelWithString:@""];
    _stagedSummary.translatesAutoresizingMaskIntoConstraints = NO;
    _stagedSummary.selectable = NO;
    _stagedSummary.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    _stagedSummary.textColor = [NSColor secondaryLabelColor];
    [_stagedSummary setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    _stageAll = [NSButton checkboxWithTitle:NppL(@"Stage all changes first") target:self action:@selector(optionChanged:)];
    _stageAll.translatesAutoresizingMaskIntoConstraints = NO;
    _problem = [NSTextField wrappingLabelWithString:@""];
    _problem.translatesAutoresizingMaskIntoConstraints = NO;
    _problem.selectable = NO;
    _problem.textColor = [NSColor systemRedColor];
    _problem.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    [_problem setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    _commitButton = [NSButton buttonWithTitle:NppL(@"Commit") target:self action:@selector(commit:)];
    _commitButton.translatesAutoresizingMaskIntoConstraints = NO;
    _commitButton.keyEquivalent = @"\r";
    _commitButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [_commitButton setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSButton *cancel = [NSButton buttonWithTitle:NppL(@"Cancel") target:self action:@selector(cancel:)];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    cancel.keyEquivalent = @"\033";
    [cancel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    for (NSView *v in @[label, scroll, _stagedSummary, _stageAll, _problem, _commitButton, cancel]) [content addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
        [label.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [scroll.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:6],
        [scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120],
        [_stagedSummary.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:8],
        [_stagedSummary.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_stagedSummary.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_stageAll.topAnchor constraintEqualToAnchor:_stagedSummary.bottomAnchor constant:8],
        [_stageAll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_problem.topAnchor constraintEqualToAnchor:_stageAll.bottomAnchor constant:6],
        [_problem.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [_problem.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_commitButton.topAnchor constraintEqualToAnchor:_problem.bottomAnchor constant:12],
        [_commitButton.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [_commitButton.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-14],
        [cancel.trailingAnchor constraintEqualToAnchor:_commitButton.leadingAnchor constant:-8],
        [cancel.centerYAnchor constraintEqualToAnchor:_commitButton.centerYAnchor],
        [content.widthAnchor constraintGreaterThanOrEqualToConstant:420],
    ]];
    self.panel = panel;
}

- (void)refreshSummary {
    EditorController *ed = self.editor;
    NSString *root = [ed gitRootOfCurrentDocument];
    if (!root) {
        // Nothing to commit here, however much of a message is typed: the window keeps saying why.
        self.stagedSummary.stringValue = [NppGit executable] ? NppL(@"The file is not in a Git repository") : NppL(@"Git is not installed (xcode-select --install)");
        self.commitButton.enabled = NO;
        return;
    }
    NSUInteger staged = 0, changed = 0;
    NSMutableArray *names = [NSMutableArray array];
    for (NppGitFileStatus *s in root ? [NppGit statusOfRepository:root] : @[]) {
        if (s.staged) { staged++; if (names.count < 8) [names addObject:s.path]; }
        else changed++;
    }
    NSMutableString *summary = [NSMutableString string];
    if (self.stageAll.state == NSControlStateValueOn) {
        [summary appendString:NppLMessage(@"$INT_REPLACE$ files will be staged and committed", nil, (NSInteger)(staged + changed))];
    } else {
        [summary appendString:NppLMessage(@"$INT_REPLACE$ files staged", nil, (NSInteger)staged)];
        if (names.count) [summary appendFormat:@": %@%@", [names componentsJoinedByString:@", "], staged > names.count ? @"…" : @""];
        if (changed) [summary appendFormat:@"  ·  %@", NppLMessage(@"$INT_REPLACE$ not staged", nil, (NSInteger)changed)];
    }
    self.stagedSummary.stringValue = summary;
    self.commitButton.enabled = (self.stageAll.state == NSControlStateValueOn ? staged + changed : staged) > 0 &&
        [self.message.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

- (void)showForEditor:(EditorController *)editor {
    self.editor = editor;
    [self build];
    self.problem.stringValue = @"";
    self.lastCommit = nil;
    [self refreshSummary];
    [self.panel center];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.message];
}

- (void)textDidChange:(NSNotification *)note { [self refreshSummary]; }
- (void)optionChanged:(id)sender { [self refreshSummary]; }
- (void)cancel:(id)sender { [self.panel orderOut:nil]; }

- (BOOL)commit:(id)sender {
    EditorController *ed = self.editor;
    NSString *sha = nil;
    if (![ed gitCommitWithMessage:self.message.string stageAll:self.stageAll.state == NSControlStateValueOn commit:&sha]) {
        self.problem.stringValue = ed.gitLastError ?: @"git commit failed";
        [self refreshSummary];
        return NO;
    }
    self.lastCommit = sha;
    self.message.string = @"";
    self.stageAll.state = NSControlStateValueOff;
    [self.panel orderOut:nil];
    NSString *shortSha = sha.length > 7 ? [sha substringToIndex:7] : sha ?: @"";
    [ed.console appendText:[NSString stringWithFormat:@"[git] %@ %@\n", NppLMessage(@"Committed $STR_REPLACE$", shortSha, 0), @""]];
    return YES;
}

@end
