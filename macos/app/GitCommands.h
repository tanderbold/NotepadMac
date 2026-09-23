// Git from the editor: what the changed lines are, what the repository's
// state is, and the everyday operations - stage, unstage, discard, commit,
// branches, fetch/pull/push - without leaving for a terminal. Windows
// Notepad++ has no such thing built in (plugins tried); on a Mac, git is on
// every machine with the Command Line Tools, and that is what is driven here:
// the `git` executable, never a library of our own, so what the editor shows
// is what `git status` would say.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// One line of `git status --porcelain`: a path and its two status letters.
@interface NppGitFileStatus : NSObject
@property (nonatomic, copy) NSString *path;          // relative to the repository root
@property (nonatomic, copy, nullable) NSString *renamedFrom;
@property (nonatomic) unichar index;                 // the staged side: ' ' M A D R C or '?'
@property (nonatomic) unichar worktree;              // the unstaged side
@property (nonatomic, readonly) BOOL untracked;
@property (nonatomic, readonly) BOOL staged;         // something of it is in the index
@property (nonatomic, readonly) BOOL unstaged;       // something of it is only in the working tree
/// "M", "A", "D", "R", "??", as the porcelain writes it, for a list.
@property (nonatomic, readonly) NSString *shortStatus;
@end

@interface NppGit : NSObject
/// The git to run: the Command Line Tools' or Xcode's (only when xcode-select
/// says they are installed - /usr/bin/git without them opens Apple's install
/// dialog), else Homebrew's. nil when there is none.
+ (nullable NSString *)executable;
/// The root of the repository a path is in, or nil. Cached by folder.
+ (nullable NSString *)repositoryRootForPath:(NSString *)path;
+ (void)forgetRepositoryRoots;
/// Runs git with arguments in a folder, waiting for it. YES on exit status 0;
/// the outputs are what it wrote, decoded as UTF-8.
+ (BOOL)run:(NSArray<NSString *> *)arguments in:(NSString *)directory
     output:(NSString *_Nullable *_Nullable)output error:(NSString *_Nullable *_Nullable)error;
/// The same, off the main thread, streaming what git writes as it comes;
/// `finished` is called on the main thread. For fetch, pull and push.
+ (void)run:(NSArray<NSString *> *)arguments in:(NSString *)directory
     stream:(void (^)(NSString *text))stream finished:(void (^)(BOOL ok))finished;

+ (NSArray<NppGitFileStatus *> *)statusOfRepository:(NSString *)root;
+ (NSArray<NppGitFileStatus *> *)statusesFromPorcelain:(NSString *)porcelain;   // exposed for the suite
/// The branch checked out ("HEAD" when detached), and how far it is from its upstream.
+ (nullable NSString *)branchOfRepository:(NSString *)root ahead:(NSInteger *_Nullable)ahead behind:(NSInteger *_Nullable)behind;
+ (NSArray<NSString *> *)branchesOfRepository:(NSString *)root;
+ (nullable NSString *)headCommitOfRepository:(NSString *)root;
/// The file as HEAD has it; nil when HEAD has no such file.
+ (nullable NSString *)headContentsOfFile:(NSString *)relativePath inRepository:(NSString *)root;
@end

@interface EditorController (GitCommands)
/// Wires the refreshes up: documents opened, saved and activated, the app
/// coming to front. Called once when the editor is built.
- (void)gitInstall;
/// The repository the document in front is in, or nil.
- (nullable NSString *)gitRootOfCurrentDocument;
- (nullable NSString *)gitRootOfDocument:(NppDocument *)doc;
/// The document's path relative to its repository.
- (nullable NSString *)gitRelativePathOfDocument:(NppDocument *)doc;

/// Marks in the margin: the lines of the document in front that differ from
/// HEAD - added, changed, and where lines were removed - against the text
/// as it is now, unsaved edits included. Nothing outside a repository.
- (void)gitRefreshMarkers;
/// The same from what is cached about HEAD, running no git process: what the
/// refresh after typing does, so nothing waits and the margin never blinks.
- (void)gitRefreshMarkersCachedOnly:(BOOL)cachedOnly;
/// The same, a moment after typing stops.
- (void)gitScheduleMarkerRefresh;
/// The branch and its distance from upstream for the status bar: "main",
/// "main ↑2 ↓1"; empty outside a repository. Cached; gitRefreshState renews it.
- (NSString *)gitStatusBarText;
/// Renews what is cached about the current document's repository: branch,
/// HEAD, the status list of the panel, the markers.
- (void)gitRefreshState;

// The commands, each on the document in front. NO when it is not in a repository or git fails;
// the reason is in gitLastError.
@property (nonatomic, readonly, nullable) NSString *gitLastError;
- (BOOL)gitCompareWithHead;              // Compare: HEAD's version beside the document
/// The change the caret is on - a run of changed or added lines, or the place lines were
/// taken out - put back as HEAD has it, as one undo step. NO with the reason when the caret
/// is on no change.
- (BOOL)gitRevertChangeAtCaret;
- (BOOL)gitBlame;                        // a new read-only document with `git blame`
- (BOOL)gitFileHistory;                  // a new read-only document with the file's log
- (BOOL)gitStageCurrent;
- (BOOL)gitUnstageCurrent;
/// Asks first (an alert), unless gitAnswersWithoutAsking; then `git checkout -- file` and a reload.
- (BOOL)gitDiscardCurrent;
- (BOOL)gitStagePaths:(NSArray<NSString *> *)relativePaths;
- (BOOL)gitUnstagePaths:(NSArray<NSString *> *)relativePaths;
- (BOOL)gitDiscardPaths:(NSArray<NSString *> *)relativePaths;
/// Commits what is staged (after `git add -A` when stageAll); the new commit's hash in `commit`.
- (BOOL)gitCommitWithMessage:(NSString *)message stageAll:(BOOL)stageAll commit:(NSString *_Nullable *_Nullable)commit;
- (BOOL)gitCheckoutBranch:(NSString *)name;
- (BOOL)gitCreateBranch:(NSString *)name;
/// Fetch, pull, push: run in the background with their output in the console.
- (void)gitFetch;
- (void)gitPull;
- (void)gitPush;
/// What the alerts would ask, answered without asking: YES for "go ahead". For the suite.
@property (nonatomic) BOOL gitAnswersWithoutAsking;
/// The question the destructive commands put; YES to go ahead.
- (BOOL)gitAsk:(NSString *)question detail:(NSString *)detail button:(NSString *)button;
@end

/// The Git panel: the repository's changed files, with what is staged, and
/// the buttons for the everyday operations.
@interface NppGitPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)show;
@property (nonatomic, readonly) BOOL visible;
- (void)reload;
/// After the interface language changed.
- (void)relocalize;
@property (nonatomic, readonly) NSArray<NppGitFileStatus *> *rows;
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, readonly) NSTextField *branchLabel;
- (void)stageSelected:(nullable id)sender;
- (void)unstageSelected:(nullable id)sender;
- (void)discardSelected:(nullable id)sender;
@end

/// Commit: the message, what is staged, and the choice to stage everything first.
@interface NppCommitWindow : NSObject
+ (instancetype)shared;
- (void)showForEditor:(EditorController *)editor;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSTextView *message;
@property (nonatomic, readonly) NSButton *stageAll, *commitButton;
@property (nonatomic, readonly) NSTextField *stagedSummary, *messageLabel;
/// The commit as the button makes it; NO with the reason shown in the window.
- (BOOL)commit:(nullable id)sender;
- (void)cancel:(nullable id)sender;
/// What typing and the checkbox call: the summary and the button follow.
- (void)textDidChange:(nullable NSNotification *)note;
- (void)optionChanged:(nullable id)sender;
@property (nonatomic, readonly, nullable) NSString *lastCommit;
@end

@interface EditorController (GitPanel)
- (NppGitPanel *)gitPanel;
@end

NS_ASSUME_NONNULL_END
