// Loads third-party plugins - .dylib files speaking the C interface in
// macos/plugin-sdk/NotepadMacPlugin.h - and gives each a submenu of the
// Plugins menu, the way PluginsManager does on Windows.
#import <Cocoa/Cocoa.h>
#import "../plugin-sdk/NotepadMacPlugin.h"

@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// Posted by the editor where the host turns them into NPPN_* notifications.
FOUNDATION_EXPORT NSNotificationName const NppDocumentOpenedNotification;
FOUNDATION_EXPORT NSNotificationName const NppDocumentSavedNotification;
FOUNDATION_EXPORT NSNotificationName const NppBufferActivatedNotification;

@interface NppLoadedPlugin : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSInteger commandCount;
/// The plugin's nppmac_messageProc, 0 when it exports none.
- (intptr_t)sendMessage:(uint32_t)message wParam:(uintptr_t)wParam lParam:(intptr_t)lParam;
@end

@interface NppPluginHost : NSObject

+ (NppPluginHost *)shared;

@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, readonly) NSArray<NppLoadedPlugin *> *plugins;

/// The folder plugins are read from (created on first ask):
/// …/Application Support/NotepadMac/plugins
- (NSString *)pluginsDirectory;

/// Loads every plugin under `dir` (Name/Name.dylib or a flat .dylib) and
/// appends one submenu per plugin to `menu`, after a separator when any
/// loaded. Returns how many loaded; what would not load is logged and skipped.
- (NSUInteger)loadPluginsFromDirectory:(NSString *)dir intoMenu:(NSMenu *)menu;

/// Sends one NPPN_* notification to every loaded plugin that listens.
- (void)notifyPlugins:(uint32_t)code;

@end

NS_ASSUME_NONNULL_END
