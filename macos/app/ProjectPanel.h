// Notepad++'s Project Panel: a workspace of projects, each a tree of virtual
// folders and files that need not share a folder on disk, kept in an .xml
// workspace file of the Windows shape - file paths relative to the workspace
// file when they are below it. Three panels, each with its own workspace.
#import <Cocoa/Cocoa.h>
#import "WorkspacePanel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppProjectNodeKind) {
    NppProjectNodeWorkspace, NppProjectNodeProject, NppProjectNodeFolder, NppProjectNodeFile,
};

@interface NppProjectNode : NSObject
@property (nonatomic) NppProjectNodeKind kind;
@property (nonatomic, copy) NSString *name;
/// A file's absolute path; nil for the others.
@property (nonatomic, copy, nullable) NSString *path;
/// The path as the workspace file wrote it ("..\\lib\\x.cpp", "C:\\a\\b.h") and
/// what it resolved to; a file left alone is written back as it was read.
@property (nonatomic, copy, nullable) NSString *storedPath;
@property (nonatomic, copy, nullable) NSString *storedResolvedPath;
@property (nonatomic, strong) NSMutableArray<NppProjectNode *> *children;
@property (nonatomic, weak, nullable) NppProjectNode *parent;
@end

@interface NppProjectPanel : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@property (nonatomic, readonly) NSView *view;
@property (nonatomic, weak, nullable) id<WorkspacePanelDelegate> delegate;
/// 1, 2 or 3.
@property (nonatomic, readonly) NSInteger number;
@property (nonatomic, readonly) NppProjectNode *root;
/// The workspace file, or nil for one never saved.
@property (nonatomic, readonly, nullable) NSString *workspacePath;
@property (nonatomic, readonly) BOOL dirty;

- (instancetype)initWithNumber:(NSInteger)number frame:(NSRect)frame;

// The workspace
- (void)newWorkspace;
/// Asks to save a changed workspace first; NO when the user cancelled or
/// the file could not be read.
- (BOOL)openWorkspace:(NSString *)path;
- (BOOL)reloadWorkspace;
- (BOOL)saveWorkspace;
/// Writes to `path`; a copy leaves the panel on its current file.
- (BOOL)saveWorkspaceAs:(NSString *)path copy:(BOOL)copy;
/// Save, Don't Save or Cancel for a changed workspace; YES to go on.
- (BOOL)confirmDiscardingChanges;
/// What confirmDiscardingChanges: answers without asking (tests): 0 asks.
@property (nonatomic) NSInteger scriptedAnswer;

// The tree
- (NppProjectNode *)addProjectNamed:(NSString *)name;
- (nullable NppProjectNode *)addFolderNamed:(NSString *)name to:(NppProjectNode *)parent;
- (NSArray<NppProjectNode *> *)addFiles:(NSArray<NSString *> *)paths to:(NppProjectNode *)parent;
/// A folder on disk as virtual folders and files, recursively, as "Add Files
/// from Directory" does; hidden files and folders are left out.
- (nullable NppProjectNode *)addDirectory:(NSString *)directory to:(NppProjectNode *)parent;
- (BOOL)rename:(NppProjectNode *)node to:(NSString *)name;
- (void)remove:(NppProjectNode *)node;
- (BOOL)moveUp:(NppProjectNode *)node;
- (BOOL)moveDown:(NppProjectNode *)node;
- (BOOL)modifyFilePath:(NppProjectNode *)node to:(NSString *)path;
/// Every file of every project, in tree order.
- (NSArray<NSString *> *)allFilePaths;
@end

NS_ASSUME_NONNULL_END
