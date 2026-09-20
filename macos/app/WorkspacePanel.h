// "Folder as Workspace": a file tree beside the editor, the macOS stand-in for
// Notepad++'s docked Folder as Workspace panel.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol WorkspacePanelDelegate <NSObject>
- (void)workspaceDidActivateFile:(NSString *)path;
@optional
/// "Find in Files..." on a folder.
- (void)workspaceWantsFindInFolder:(NSString *)path;
/// "Locate current file": the document in front.
- (nullable NSString *)workspaceCurrentFilePath;
@end

@interface WorkspacePanel : NSObject
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<WorkspacePanelDelegate> delegate;
/// The first root folder.
@property (nonatomic, readonly, nullable) NSString *rootPath;
/// Every root folder, as upstream's panel holds several.
@property (nonatomic, readonly) NSArray<NSString *> *rootPaths;

- (instancetype)initWithFrame:(NSRect)frame;
/// Replaces every root with this one (nil for none).
- (void)setRootPath:(nullable NSString *)path;
/// Adds a root folder, unless it is there already.
- (void)addRootPath:(NSString *)path;
- (void)removeRootPath:(NSString *)path;
/// Files and folders directly inside the roots; used by tests.
- (NSArray<NSString *> *)topLevelNames;
/// Shows and selects a file, opening the folders on the way; NO when it is under no root.
- (BOOL)locateFile:(NSString *)path;
/// The right-click menu for a row: a root, a folder or a file.
- (nullable NSMenu *)menuForRow:(NSInteger)row;
@end

NS_ASSUME_NONNULL_END
