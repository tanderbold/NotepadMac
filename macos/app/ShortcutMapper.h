// Keyboard shortcuts as Notepad++ keeps them: the main menu, macros, Run
// commands, plugin commands and Scintilla commands, each assignable, checked
// for conflicts, and kept in shortcuts.xml in the Windows format - Ctrl
// there is Command here, Alt is Option, and the Control key, which Windows
// has no counterpart for, is an extra attribute Windows ignores.
#import <Cocoa/Cocoa.h>
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

/// A key and its modifiers.
@interface NppKeyCombo : NSObject <NSCopying>
/// Command, Option, Shift and Control only.
@property (nonatomic) NSEventModifierFlags modifiers;
/// The key as a menu key equivalent takes it: a lower-case letter, a digit
/// or punctuation, or a function-key character (NSF1FunctionKey, arrows...).
@property (nonatomic, copy) NSString *key;
+ (nullable instancetype)comboWithKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers;
/// "cmd+shift+k", the form the older preference used.
+ (nullable instancetype)comboFromSpec:(NSString *)spec;
+ (nullable instancetype)comboFromEvent:(NSEvent *)event;
/// From shortcuts.xml's Ctrl/Alt/Shift/Key (a Windows virtual-key code).
+ (nullable instancetype)comboWithWindowsCtrl:(BOOL)ctrl alt:(BOOL)alt shift:(BOOL)shift
                                   macControl:(BOOL)control virtualKey:(int)vk;
@property (nonatomic, readonly) int windowsVirtualKey;       // 0 when it has none
/// "⌃⌥⇧⌘K".
@property (nonatomic, readonly) NSString *displayString;
@property (nonatomic, readonly) NSString *spec;
/// Scintilla's key definition for SCI_ASSIGNCMDKEY: key | (SCMOD_* << 16).
@property (nonatomic, readonly) long scintillaKeyDefinition;
+ (nullable instancetype)comboFromScintillaKey:(int)key modifiers:(int)scmod;
@end

typedef NS_ENUM(NSInteger, NppShortcutCategory) {
    NppShortcutMainMenu, NppShortcutMacro, NppShortcutRunCommand, NppShortcutPlugin, NppShortcutScintilla,
};

/// One assignable command.
@interface NppShortcutCommand : NSObject
@property (nonatomic) NppShortcutCategory category;
@property (nonatomic, copy) NSString *name;
/// Where it lives: the menu path, the macro or command name, or the
/// Scintilla command's name.
@property (nonatomic, copy) NSString *detail;
/// Notepad++'s id: the menu command id, or the Scintilla message; 0 if none.
@property (nonatomic) int identifier;
/// What it is kept under when it has no id: the menu path and title.
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong, nullable) NppKeyCombo *combo;
/// Scintilla commands may have several keys; the first is `combo`.
@property (nonatomic, copy) NSArray<NppKeyCombo *> *extraCombos;
@end

/// Every command and its keys, applied to the menus and the editors.
@interface NppShortcutStore : NSObject
- (instancetype)initWithEditor:(EditorController *)editor;
/// Reads what the menus have now as their defaults. Called once, before
/// anything is applied.
- (void)captureMenuDefaults;
/// Reads shortcuts.xml (and the older preference) and applies it all.
- (void)load;
- (NSString *)path;
- (NSArray<NppShortcutCommand *> *)commandsInCategory:(NppShortcutCategory)category;
/// Assigns (nil clears) and writes shortcuts.xml.
- (void)setCombo:(nullable NppKeyCombo *)combo forCommand:(NppShortcutCommand *)command;
/// The other commands that already use the combination.
- (NSArray<NppShortcutCommand *> *)conflictsWith:(NppKeyCombo *)combo except:(nullable NppShortcutCommand *)command;
/// The keys again on menus that were rebuilt (macros, Run commands).
- (void)applyToMenus;
/// The Scintilla command keys on a view, as assigned.
- (void)applyScintillaKeysTo:(id)scintillaView;
- (BOOL)save;
/// The menu item behind each of Notepad++'s command ids the port has.
- (NSDictionary<NSNumber *, NSMenuItem *> *)menuItemsByIdentifier;
@end

@interface NppShortcutMapper : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
- (instancetype)initWithStore:(NppShortcutStore *)store editor:(EditorController *)editor;
- (void)toggle;
@property (nonatomic, readonly) BOOL visible;
@property (nonatomic) NppShortcutCategory category;
@property (nonatomic, copy) NSString *filter;
/// What the table shows now.
@property (nonatomic, readonly) NSArray<NppShortcutCommand *> *shownCommands;
@end

NS_ASSUME_NONNULL_END
