// Scripts in the manner of the NppExec plugin: lines of commands, run one
// after another, with NppExec's own commands for the editor and its $(…)
// variables, and anything else run through the shell.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// A script kept under a name, as NppExec keeps them in npes_saved.txt.
@interface NppSavedScript : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *text;
+ (instancetype)scriptNamed:(NSString *)name text:(NSString *)text;
/// npes_saved.txt: each script is "::name" and then its lines.
+ (NSArray<NppSavedScript *> *)scriptsFromSavedText:(NSString *)text;
+ (NSString *)savedTextForScripts:(NSArray<NppSavedScript *> *)scripts;
@end

@interface NppScriptEngine : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
/// Runs a script to its end, an EXIT or an error, on the calling thread; the
/// editor is only touched on the main thread. Returns NO on an error.
- (BOOL)runScript:(NSString *)text arguments:(NSArray<NSString *> *)arguments;
/// Where commands run: the current file's folder until CD moves it.
@property (nonatomic, copy, nullable) NSString *directory;
/// All the script printed, as the console shows it.
@property (nonatomic, readonly) NSString *log;
/// A variable's value by NppExec's rules ($(name) without the $( )).
- (nullable NSString *)valueOfVariable:(NSString *)name;
/// INPUTBOX's question; the default asks in a dialog.
@property (nonatomic, copy, nullable) NSString *_Nullable (^inputProvider)(NSString *prompt, NSString *initial);
/// NPP_MENUCOMMAND: performs a menu command by its path ("Edit|Undo").
@property (nonatomic, copy, nullable) BOOL (^menuCommandPerformer)(NSString *path);
/// Steps a script may take before it is stopped as a runaway loop.
@property (nonatomic) NSUInteger stepLimit;
/// Set from another thread to stop the script after the current command.
@property (atomic) BOOL cancelled;
@end

@interface EditorController (ScriptCommands)
/// npes_saved.txt in the settings folder.
- (NSString *)savedScriptsPath;
- (NSArray<NppSavedScript *> *)savedScripts;
- (void)saveScript:(NppSavedScript *)script;
- (void)removeScriptNamed:(NSString *)name;
- (nullable NppSavedScript *)savedScriptNamed:(NSString *)name;
@end

NS_ASSUME_NONNULL_END
