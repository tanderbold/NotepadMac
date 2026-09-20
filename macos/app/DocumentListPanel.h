// "Document List": a floating panel listing the open tabs, the macOS stand-in
// for Notepad++'s docked Document List (VerticalFileSwitcher): Name, Ext. and
// Path columns, sorting by a column, the tab menu on a file and a column menu
// on the header.
#import <Cocoa/Cocoa.h>
@class EditorController, NppDocument;

NS_ASSUME_NONNULL_BEGIN

@interface DocumentListPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSInteger rowCount;

// What the list does, here so the suite can drive it.
/// The documents in the order the rows show them.
@property (nonatomic, readonly) NSArray<NppDocument *> *rows;
/// Column identifiers shown: "name" always, "ext" and "path" as set.
@property (nonatomic, readonly) NSArray<NSString *> *shownColumns;
- (void)setColumn:(NSString *)identifier shown:(BOOL)shown;
/// Sorts by a column, as clicking its header does; nil restores tab order.
- (void)sortByColumn:(nullable NSString *)identifier ascending:(BOOL)ascending;
- (NSString *)textOfColumn:(NSString *)identifier row:(NSInteger)row;
/// A click on a row brings its document to the front.
- (void)activateRow:(NSInteger)row;
/// The right-click menu for the rows selected.
- (nullable NSMenu *)menuForSelectedRows:(NSIndexSet *)rows;
- (void)closeRows:(NSIndexSet *)rows;
- (void)saveRows:(NSIndexSet *)rows;
/// "Group by View", from the header's menu: a heading above each view's files while both views are in use.
- (void)setGroupByView:(BOOL)on;
- (BOOL)isGroupRow:(NSInteger)row;
/// The documents among some rows; headings are none.
- (NSArray<NppDocument *> *)documentsInRows:(NSIndexSet *)rows;
@end

NS_ASSUME_NONNULL_END
