// Running external commands: the variables Notepad++ substitutes into a command
// line, a console the output streams into, and commands saved under a name.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// What a command left behind.
@interface NppRunResult : NSObject
@property (nonatomic, copy) NSString *output;   // stdout and stderr, interleaved as they arrived
@property (nonatomic) int exitStatus;           // -1 when the command could not be started
@property (nonatomic) BOOL timedOut;
@end

/// A command kept under a name, which earns its own entry in the Run menu.
@interface NppSavedCommand : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *command;
+ (instancetype)commandWithName:(NSString *)name command:(NSString *)command;
+ (instancetype)commandFromDictionary:(NSDictionary *)dictionary;
@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;
@end

/// Where output goes. A panel rather than a dialog, because a command that
/// takes a while should be readable while it runs.
@interface NppConsolePanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)show;
/// Shown, with the keyboard left where it was (a script's output).
- (void)showWithoutFocus;
- (void)appendText:(NSString *)text;
- (void)clear;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly, copy) NSString *text;
@end

@interface EditorController (RunCommands)

/// Substitutes $(FULL_CURRENT_PATH) and the rest. A name that is not one of
/// them is left in place, exactly as Notepad++ leaves it.
- (NSString *)expandRunVariables:(NSString *)source;
/// The same, asking `lookup` first (a script's own variables); unquoted when
/// the text is not for the shell.
- (NSString *)expandRunVariables:(NSString *)source
                          lookup:(nullable NSString *_Nullable (^)(NSString *name))lookup
                   quoteForShell:(BOOL)quote;
/// The value of one variable, or nil if there is no such variable.
- (nullable NSString *)runVariableNamed:(NSString *)name;

/// Runs a command line through the shell, in the current document's directory.
/// Blocks until it finishes; output reaches the console as it arrives.
- (NppRunResult *)runCommandLine:(NSString *)command intoConsole:(BOOL)intoConsole;
/// An expanded command in the given directory, with variables added to the
/// environment; safe off the main thread when the console is not asked for.
- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded directory:(nullable NSString *)directory
                             environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                             intoConsole:(BOOL)intoConsole;
/// The same with its own time limit (0: none) and a block asked five times a
/// second whether to stop the command.
- (NppRunResult *)runExpandedCommandLine:(NSString *)expanded directory:(nullable NSString *)directory
                             environment:(nullable NSDictionary<NSString *, NSString *> *)environment
                             intoConsole:(BOOL)intoConsole timeout:(NSTimeInterval)timeout
                                stopWhen:(nullable BOOL (^)(void))stopWhen;
/// The same, off the main thread, so the console fills while the app stays live.
- (void)runCommandLineInBackground:(NSString *)command
                        completion:(void (^_Nullable)(NppRunResult *))completion;

- (NppConsolePanel *)console;

// Saved commands
- (NSArray<NppSavedCommand *> *)savedCommands;
- (void)saveCommand:(NppSavedCommand *)command;
- (void)removeSavedCommandNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
