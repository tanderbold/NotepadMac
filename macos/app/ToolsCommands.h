// Tools, Macro, Window, Run and Help commands.
#import "EditorController.h"
#import "FindCommands.h"

NS_ASSUME_NONNULL_BEGIN

/// The first four are Notepad++'s own, in its menu's order; the rest are the port's.
typedef NS_ENUM(NSInteger, NppDigest) {
    NppDigestMD5, NppDigestSHA1, NppDigestSHA256, NppDigestSHA512,
    NppDigestSHA224, NppDigestSHA384, NppDigestSHA3_256, NppDigestSHA3_512, NppDigestBLAKE2b, NppDigestCRC32,
    NppDigestCount,
};

typedef NS_ENUM(NSInteger, NppTabSort) {
    NppTabSortName, NppTabSortPath, NppTabSortType,
    NppTabSortContentLength, NppTabSortModifiedTime,
};

@interface EditorController (ToolsCommands)

// Hashes
+ (NSString *)hashOfData:(NSData *)data digest:(NppDigest)digest;
/// Of a text as the dialog takes it: the whole of it, or each line on its own
/// (an empty line giving an empty line), as "Treat each line as a separate string" has it.
+ (NSString *)hashOfText:(NSString *)text eachLine:(BOOL)eachLine digest:(NppDigest)digest;
+ (NSString *)nameOfDigest:(NppDigest)digest;
- (NSString *)hashOfSelection:(NppDigest)digest;
- (NSString *)hashOfFiles:(NSArray<NSString *> *)paths digest:(NppDigest)digest;

// Macros
- (void)startRecordingMacro;
- (void)stopRecordingMacro;
- (BOOL)recordingMacro;
/// True while a macro is being played back.
- (BOOL)playingMacro;
- (NSUInteger)recordedStepCount;
- (BOOL)playbackMacro:(NSUInteger)times;
- (BOOL)saveRecordedMacroAs:(NSString *)name;
- (NSArray<NSString *> *)savedMacroNames;
/// Plays a saved macro, as the Macro menu entry does.
- (BOOL)playSavedMacroNamed:(NSString *)name;
- (BOOL)removeSavedMacroNamed:(NSString *)name;
/// The steps of a saved macro: {msg, w, l, text?} each; nil when there is none.
- (nullable NSArray<NSDictionary *> *)stepsOfSavedMacroNamed:(NSString *)name;
/// Keeps steps under a name, written to macros.json.
- (void)storeSavedMacro:(NSArray<NSDictionary *> *)steps named:(NSString *)name;

/// Reads the saved macros back from macros.json, replacing what is held.
- (void)reloadSavedMacros;
/// Called from the notification handler for each recorded Scintilla action.
- (void)recordMacroMessage:(int)message wParam:(unsigned long)wParam lParam:(long)lParam;
/// Around a menu command that a macro records by its id rather than by what it sends to Scintilla.
- (void)beginRecordableMenuCommand;
- (void)endRecordableMenuCommand:(int)identifier;
/// After a search from the Find dialog (begun with beginRecordableMenuCommand):
/// its six steps of type 3, `command` being IDOK, IDREPLACE, IDREPLACEALL and so on.
- (void)recordFindCommand:(int)command spec:(NppFindSpec *)spec markFlags:(long)markFlags global:(BOOL)global;
/// Performs a menu command by Notepad++'s id, for macro steps of type 2; set by the application.
@property (nonatomic, copy, nullable) BOOL (^menuCommandByIdentifier)(int identifier);
- (void)rememberPreviousTab:(NppDocument *)doc;

/// The tab Recent Window would step back to, or nil.
- (nullable NppDocument *)previousTab;

// Window
- (void)sortTabsBy:(NppTabSort)key ascending:(BOOL)ascending;
- (NSArray<NSString *> *)windowList;
- (BOOL)activateRecentWindow;

// Run
- (nullable NSString *)runShellCommand:(NSString *)command;
- (NSString *)validateShortcutsFile;

// Help / info
- (NSString *)debugInfo;
- (NSString *)commandLineArgumentsHelp;

@end

NS_ASSUME_NONNULL_END
