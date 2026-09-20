// Character Panel and Clipboard History: the two remaining Edit-menu panels.
#import <Cocoa/Cocoa.h>
@class EditorController;

NS_ASSUME_NONNULL_BEGIN

/// Notepad++'s ASCII Codes Insertion Panel: 0-255 in the document's code
/// page with Value, Hex, Character and the HTML forms; a double click puts in
/// the character, or the text of the column clicked.
@interface CharacterPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSInteger rowCount;
/// Inserts the character of byte value `row`.
- (BOOL)insertRow:(NSInteger)row;
/// What a double click on that cell puts in.
- (BOOL)insertRow:(NSInteger)row column:(nullable NSString *)identifier;
/// value, hex, char, name, dec or hexnum.
- (NSString *)textOfColumn:(NSString *)identifier row:(NSInteger)row;
@end

/// Keeps what has been on the pasteboard; double-click pastes an entry back.
@interface ClipboardHistoryPanel : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
- (void)capturePasteboard;               // records the current pasteboard text
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic, readonly) NSArray<NSString *> *entries;
- (BOOL)pasteRow:(NSInteger)row;
@end

NS_ASSUME_NONNULL_END
