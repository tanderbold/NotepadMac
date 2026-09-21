// The plugin host: dlopen each library in the plugins folder, hand it the
// send() bridge, put its commands into the Plugins menu, and pass along the
// application's notifications - PluginsManager.cpp's job, done with dlfcn.
#import "PluginHost.h"
#import "EditorController.h"
#import "ScintillaView.h"
#import <dlfcn.h>

NSNotificationName const NppDocumentOpenedNotification = @"NppDocumentOpenedNotification";
NSNotificationName const NppDocumentSavedNotification = @"NppDocumentSavedNotification";
NSNotificationName const NppBufferActivatedNotification = @"NppBufferActivatedNotification";

// The handles a plugin gets are sentinels, not objects: everything routes
// through the shared host, so a stale handle can never dangle.
static char gNppSentinel, gSciSentinel;

typedef void (*NppSetInfoFn)(NppMacData);
typedef const char *(*NppGetNameFn)(void);
typedef NppMacFuncItem *(*NppGetFuncsFn)(int *);
typedef void (*NppBeNotifiedFn)(const NppMacNotification *);
typedef intptr_t (*NppMessageProcFn)(uint32_t, uintptr_t, intptr_t);

@interface NppLoadedPlugin () {
    @public
    void *_handle;
    NppMacFuncItem *_items;
    int _itemCount;
    NppBeNotifiedFn _beNotified;
    NppMessageProcFn _messageProc;
}
@property (nonatomic, readwrite) NSString *name;
@property (nonatomic, readwrite) NSString *path;
@end

@implementation NppLoadedPlugin
- (NSInteger)commandCount { return _itemCount; }
- (intptr_t)sendMessage:(uint32_t)message wParam:(uintptr_t)wParam lParam:(intptr_t)lParam {
    return _messageProc ? _messageProc(message, wParam, lParam) : 0;
}
@end

@interface NppPluginHost ()
@property (nonatomic) NSMutableArray<NppLoadedPlugin *> *loaded;
@end

/// Writes UTF-8 into the caller's buffer the way the Windows messages fill
/// wchar_t buffers: lParam null answers the size a buffer needs.
static intptr_t CopyOut(NSString *string, uintptr_t size, intptr_t buffer) {
    const char *utf8 = string.UTF8String ?: "";
    if (!buffer) return (intptr_t)strlen(utf8) + 1;
    if (!size) return 0;
    strlcpy((char *)buffer, utf8, size);
    return (intptr_t)strlen((char *)buffer);
}

static intptr_t PluginSend(NppMacHandle target, uint32_t message, uintptr_t wParam, intptr_t lParam) {
    NppPluginHost *host = [NppPluginHost shared];
    if (target == &gSciSentinel) {
        return [host.editor.sci message:message wParam:wParam lParam:lParam];
    }
    EditorController *ed = host.editor;
    switch (message) {
        case NPPM_GETCURRENTSCINTILLA:
            if (lParam) *(intptr_t *)lParam = 0;
            return 0;
        case NPPM_GETNPPVERSION:
            return ((intptr_t)8 << 16) | 908;   // the Notepad++ this port is written against
        case NPPM_GETFULLCURRENTPATH:
            return CopyOut(ed.currentDocument.path ?: ed.currentDocument.displayName ?: @"", wParam, lParam);
        case NPPM_GETFILENAME:
            return CopyOut(ed.currentDocument.path.lastPathComponent ?: ed.currentDocument.displayName ?: @"",
                           wParam, lParam);
        case NPPM_GETCURRENTDIRECTORY:
            return CopyOut(ed.currentDocument.path.stringByDeletingLastPathComponent ?: @"", wParam, lParam);
        case NPPM_GETPLUGINSCONFIGDIR: {
            NSString *dir = [[host pluginsDirectory] stringByAppendingPathComponent:@"Config"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                       attributes:nil error:NULL];
            return CopyOut(dir, wParam, lParam);
        }
        case NPPM_DOOPEN:
            return lParam && [ed openFileAtPath:@((const char *)lParam) error:NULL] ? 1 : 0;
        case NPPM_SAVECURRENTFILE:
            return [ed saveCurrentDocument] ? 1 : 0;
    }
    return 0;
}

@implementation NppPluginHost

+ (NppPluginHost *)shared {
    static NppPluginHost *host;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ host = [[NppPluginHost alloc] init]; });
    return host;
}

- (instancetype)init {
    if ((self = [super init])) {
        _loaded = [NSMutableArray array];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(fileOpened:) name:NppDocumentOpenedNotification object:nil];
        [nc addObserver:self selector:@selector(fileSaved:) name:NppDocumentSavedNotification object:nil];
        [nc addObserver:self selector:@selector(bufferActivated:) name:NppBufferActivatedNotification object:nil];
    }
    return self;
}

- (void)fileOpened:(NSNotification *)n      { [self notifyPlugins:NPPN_FILEOPENED]; }
- (void)fileSaved:(NSNotification *)n       { [self notifyPlugins:NPPN_FILESAVED]; }
- (void)bufferActivated:(NSNotification *)n { [self notifyPlugins:NPPN_BUFFERACTIVATED]; }

- (NSArray<NppLoadedPlugin *> *)plugins { return self.loaded; }

- (NSString *)pluginsDirectory {
    NSString *dir = [self.editor.defaultSessionPath.stringByDeletingLastPathComponent
                     stringByAppendingPathComponent:@"plugins"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return dir;
}

- (NSUInteger)loadPluginsFromDirectory:(NSString *)dir intoMenu:(NSMenu *)menu {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *libraries = [NSMutableArray array];
    for (NSString *entry in [[fm contentsOfDirectoryAtPath:dir error:NULL]
                             sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *path = [dir stringByAppendingPathComponent:entry];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:&isDir];
        if (isDir) {
            // Windows' layout: plugins\Name\Name.dll.
            NSString *inside = [path stringByAppendingPathComponent:
                                [entry stringByAppendingPathExtension:@"dylib"]];
            if ([fm fileExistsAtPath:inside]) [libraries addObject:inside];
        } else if ([entry.pathExtension isEqualToString:@"dylib"]) {
            [libraries addObject:path];
        }
    }

    NSUInteger before = self.loaded.count;
    for (NSString *library in libraries) {
        NppLoadedPlugin *plugin = [self loadPluginAt:library];
        if (!plugin) continue;
        [self.loaded addObject:plugin];
        if (self.loaded.count == before + 1) [menu addItem:[NSMenuItem separatorItem]];
        NSMenu *sub = [[NSMenu alloc] initWithTitle:plugin.name];
        for (int i = 0; i < plugin->_itemCount; ++i) {
            NppMacFuncItem *item = &plugin->_items[i];
            if (!item->pFunc) { [sub addItem:[NSMenuItem separatorItem]]; continue; }
            NSMenuItem *mi = [[NSMenuItem alloc]
                initWithTitle:[NSString stringWithUTF8String:item->itemName] ?: @"?"
                       action:@selector(invokePluginItem:) keyEquivalent:@""];
            mi.target = self;
            mi.representedObject = [NSValue valueWithPointer:(void *)item->pFunc];
            [sub addItem:mi];
        }
        [menu addItemWithTitle:plugin.name action:nil keyEquivalent:@""].submenu = sub;
    }
    return self.loaded.count - before;
}

- (NppLoadedPlugin *)loadPluginAt:(NSString *)library {
    void *handle = dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        NSLog(@"plugin %@: %s", library.lastPathComponent, dlerror());
        return nil;
    }
    NppSetInfoFn setInfo = (NppSetInfoFn)dlsym(handle, "nppmac_setInfo");
    NppGetNameFn getName = (NppGetNameFn)dlsym(handle, "nppmac_getName");
    NppGetFuncsFn getFuncs = (NppGetFuncsFn)dlsym(handle, "nppmac_getFuncsArray");
    if (!setInfo || !getName || !getFuncs) {
        NSLog(@"plugin %@: does not export nppmac_setInfo/getName/getFuncsArray",
              library.lastPathComponent);
        dlclose(handle);
        return nil;
    }

    NppLoadedPlugin *plugin = [[NppLoadedPlugin alloc] init];
    plugin->_handle = handle;
    plugin->_beNotified = (NppBeNotifiedFn)dlsym(handle, "nppmac_beNotified");
    plugin->_messageProc = (NppMessageProcFn)dlsym(handle, "nppmac_messageProc");
    plugin.path = library;

    NppMacData data = { &gNppSentinel, &gSciSentinel, PluginSend };
    setInfo(data);
    const char *name = getName();
    plugin.name = name ? [NSString stringWithUTF8String:name] : nil;
    if (!plugin.name.length) plugin.name = library.lastPathComponent.stringByDeletingPathExtension;
    plugin->_items = getFuncs(&plugin->_itemCount);
    if (!plugin->_items || plugin->_itemCount <= 0) {
        NSLog(@"plugin %@: empty command list", plugin.name);
        dlclose(handle);
        return nil;
    }
    return plugin;
}

- (void)invokePluginItem:(NSMenuItem *)sender {
    NppMacPluginFunc fn = (NppMacPluginFunc)[(NSValue *)sender.representedObject pointerValue];
    if (fn) fn();
}

- (void)notifyPlugins:(uint32_t)code {
    NppMacNotification note = { code, 0, &gNppSentinel };
    for (NppLoadedPlugin *plugin in self.loaded) {
        if (plugin->_beNotified) plugin->_beNotified(&note);
    }
}

@end
