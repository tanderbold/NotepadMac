// The User Defined Language dialog, as Notepad++ has it: a language picked at
// the top with Create New, Save As, Rename, Remove, Import and Export, and
// four pages - Folder & Default, Keywords Lists, Comment & Number, Operators
// & Delimiters - each group with its own style. Every change is written to
// the language's file at once and shown on the document in front, as on
// Windows.
#import <Cocoa/Cocoa.h>
#import "EditorController.h"
#import "UserLanguages.h"

NS_ASSUME_NONNULL_BEGIN

@interface NppUserLanguageDialog : NSObject <NSTextFieldDelegate, NSTextViewDelegate, NSWindowDelegate>

- (instancetype)initWithEditor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;

/// The language being edited, or nil when there is none.
@property (nonatomic, readonly, nullable) NppUserLanguage *current;
- (void)selectLanguageNamed:(NSString *)name;

// What the buttons do, without asking; for the menus and the suite.
- (BOOL)createLanguageNamed:(NSString *)name;
- (BOOL)saveCurrentAs:(NSString *)name;
- (BOOL)renameCurrentTo:(NSString *)name;
- (BOOL)removeCurrent;
- (NSArray<NSString *> *)importFromFile:(NSString *)path;
- (BOOL)exportCurrentToFile:(NSString *)path;

/// A control by the name it is kept under ("ext", "keywords3", "prefix3",
/// "commentLineOpen", "delimiter2Close", ...), for the suite.
- (nullable NSControl *)controlNamed:(NSString *)name;
- (nullable NSTextView *)textViewNamed:(NSString *)name;
/// Reads every control into the language, writes it, and shows it.
- (void)commit;
/// Sets a style's attributes, as the style editor does when it closes.
- (void)setStyle:(int)styleID attributes:(NSDictionary *)attributes;

@end

NS_ASSUME_NONNULL_END
