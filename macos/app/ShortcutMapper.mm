#import "ShortcutMapper.h"
#import <objc/runtime.h>
#import "Localization.h"
#import "NppPanel.h"
#import "ScintillaView.h"
#import "SettingsCommands.h"
#import "ToolsCommands.h"
#import "RunCommands.h"
#import "CommandIDs.h"
#import "LangMap.h"
#include "Scintilla.h"

#pragma mark - A key and its modifiers

static const NSEventModifierFlags kComboMask = NSEventModifierFlagCommand | NSEventModifierFlagOption |
                                               NSEventModifierFlagShift | NSEventModifierFlagControl;

/// Windows virtual-key codes against the key as AppKit names it.
static NSDictionary<NSString *, NSNumber *> *KeysToVirtualKeys(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (unichar c = 'a'; c <= 'z'; ++c) m[[NSString stringWithCharacters:&c length:1]] = @(c - 'a' + 65);
        for (unichar c = '0'; c <= '9'; ++c) m[[NSString stringWithCharacters:&c length:1]] = @(c);
        for (int i = 0; i < 24; ++i) {
            unichar f = (unichar)(NSF1FunctionKey + i);
            m[[NSString stringWithCharacters:&f length:1]] = @(112 + i);
        }
        unichar specials[][2] = {
            {NSLeftArrowFunctionKey, 37}, {NSUpArrowFunctionKey, 38}, {NSRightArrowFunctionKey, 39},
            {NSDownArrowFunctionKey, 40}, {NSHomeFunctionKey, 36}, {NSEndFunctionKey, 35},
            {NSPageUpFunctionKey, 33}, {NSPageDownFunctionKey, 34}, {NSDeleteFunctionKey, 46},
            {NSInsertFunctionKey, 45}, {'\b', 8}, {'\r', 13}, {'\t', 9}, {0x1b, 27}, {' ', 32},
            {';', 186}, {'=', 187}, {',', 188}, {'-', 189}, {'.', 190}, {'/', 191}, {'`', 192},
            {'[', 219}, {'\\', 220}, {']', 221}, {'\'', 222}, {'+', 107}, {'*', 106},
        };
        for (size_t i = 0; i < sizeof(specials) / sizeof(specials[0]); ++i) {
            m[[NSString stringWithCharacters:&specials[i][0] length:1]] = @(specials[i][1]);
        }
        map = m;
    });
    return map;
}

static NSString *KeyForVirtualKey(int vk) {
    if (vk >= 96 && vk <= 105) vk = '0' + (vk - 96);                 // the numeric pad's digits
    if (vk == 109) vk = 189;                                          // VK_SUBTRACT
    if (vk == 111) vk = 191;                                          // VK_DIVIDE
    for (NSString *key in KeysToVirtualKeys()) {
        if ([KeysToVirtualKeys()[key] intValue] == vk) return key;
    }
    return nil;
}

/// What Shift makes of a key on a US layout, for Scintilla, which is handed
/// the character as typed.
static unichar Shifted(unichar c) {
    const char *plain = "1234567890-=[]\\;',./`", *shifted = "!@#$%^&*()_+{}|:\"<>?~";
    const char *at = strchr(plain, (char)c);
    return (c < 128 && at) ? (unichar)shifted[at - plain] : c;
}


/// The US layout's shifted characters, as a key equivalent spells Shift with them.
static NSDictionary<NSString *, NSString *> *ShiftedCharacters(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{@"1": @"!", @"2": @"@", @"3": @"#", @"4": @"$", @"5": @"%", @"6": @"^", @"7": @"&", @"8": @"*",
                @"9": @"(", @"0": @")", @"-": @"_", @"=": @"+", @"[": @"{", @"]": @"}", @"\\": @"|", @";": @":",
                @"'": @"\"", @",": @"<", @".": @">", @"/": @"?", @"`": @"~"};
    });
    return map;
}

NSString *NppShiftedCharacter(NSString *key) {
    if (key.length != 1) return nil;
    unichar c = [key characterAtIndex:0];
    return (c >= 'a' && c <= 'z') ? key.uppercaseString : ShiftedCharacters()[key];
}

void NppSetMenuKey(NSMenuItem *item, NSString *key, NSEventModifierFlags modifiers) {
    NSString *k = key ?: @"";
    NSEventModifierFlags m = modifiers;
    if ((m & NSEventModifierFlagShift) && k.length == 1) {
        unichar c = [k characterAtIndex:0];
        NSString *shifted = (c >= 'a' && c <= 'z') ? k.uppercaseString : ShiftedCharacters()[k];
        if (shifted) { k = shifted; m &= ~NSEventModifierFlagShift; }
    }
    item.keyEquivalent = k;
    item.keyEquivalentModifierMask = k.length ? m : 0;
}

NSString *NppMenuItemKey(NSMenuItem *item, NSEventModifierFlags *modifiers) {
    NSString *k = item.keyEquivalent ?: @"";
    NSEventModifierFlags m = item.keyEquivalentModifierMask;
    if (k.length == 1) {
        unichar c = [k characterAtIndex:0];
        if (c >= 'A' && c <= 'Z') { k = k.lowercaseString; m |= NSEventModifierFlagShift; }
        else if (c != '+') {   // Notepad++ names "+" itself (Ctrl++, Zoom In): Shift+= and "+" are one key press here
            for (NSString *plain in ShiftedCharacters()) {
                if ([ShiftedCharacters()[plain] isEqualToString:k]) { k = plain; m |= NSEventModifierFlagShift; break; }
            }
        }
    }
    if (modifiers) *modifiers = m;
    return k;
}

@implementation NppKeyCombo

+ (instancetype)comboWithKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers {
    if (!key.length) return nil;
    NppKeyCombo *combo = [[NppKeyCombo alloc] init];
    unichar c = [key characterAtIndex:0];
    if (c >= 'A' && c <= 'Z') {                     // an upper-case key equivalent means Shift
        c = (unichar)(c + 32);
        modifiers |= NSEventModifierFlagShift;
    }
    if (c == 0x7f) c = '\b';                         // the Delete key as events give it
    if (c == 3 || c == '\n') c = '\r';
    combo.key = [NSString stringWithCharacters:&c length:1];
    combo.modifiers = modifiers & kComboMask;
    return combo;
}

+ (instancetype)comboFromSpec:(NSString *)spec {
    NSEventModifierFlags mask = 0;
    NSString *key = @"";
    for (NSString *part in [spec.lowercaseString componentsSeparatedByString:@"+"]) {
        if ([part isEqualToString:@"cmd"]) mask |= NSEventModifierFlagCommand;
        else if ([part isEqualToString:@"shift"]) mask |= NSEventModifierFlagShift;
        else if ([part isEqualToString:@"opt"] || [part isEqualToString:@"alt"]) mask |= NSEventModifierFlagOption;
        else if ([part isEqualToString:@"ctrl"]) mask |= NSEventModifierFlagControl;
        else if (part.length) key = part;
    }
    return [self comboWithKey:key modifiers:mask];
}

+ (instancetype)comboFromEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) return nil;
    // The key without its modifiers, so Shift+1 is 1 with Shift, not "!".
    NSString *key = [event charactersByApplyingModifiers:0];
    if (!key.length) key = event.charactersIgnoringModifiers;
    if (!key.length) return nil;
    return [self comboWithKey:[key substringToIndex:1] modifiers:event.modifierFlags];
}

+ (instancetype)comboWithWindowsCtrl:(BOOL)ctrl alt:(BOOL)alt shift:(BOOL)shift
                          macControl:(BOOL)control virtualKey:(int)vk {
    NSString *key = vk > 0 ? KeyForVirtualKey(vk) : nil;
    if (!key) return nil;
    NSEventModifierFlags m = (ctrl ? NSEventModifierFlagCommand : 0) | (alt ? NSEventModifierFlagOption : 0) |
                             (shift ? NSEventModifierFlagShift : 0) | (control ? NSEventModifierFlagControl : 0);
    return [self comboWithKey:key modifiers:m];
}

- (int)windowsVirtualKey { return [KeysToVirtualKeys()[self.key ?: @""] intValue]; }

- (id)copyWithZone:(NSZone *)zone {
    return [NppKeyCombo comboWithKey:self.key modifiers:self.modifiers];
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[NppKeyCombo class]]) return NO;
    NppKeyCombo *o = other;
    return [o.key isEqualToString:self.key] && o.modifiers == self.modifiers;
}

- (NSUInteger)hash { return self.key.hash ^ (NSUInteger)self.modifiers; }

- (NSString *)keyName {
    unichar c = [self.key characterAtIndex:0];
    if (c >= NSF1FunctionKey && c <= NSF35FunctionKey) return [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1];
    switch (c) {
        case NSLeftArrowFunctionKey: return @"←";
        case NSRightArrowFunctionKey: return @"→";
        case NSUpArrowFunctionKey: return @"↑";
        case NSDownArrowFunctionKey: return @"↓";
        case NSHomeFunctionKey: return @"Home";
        case NSEndFunctionKey: return @"End";
        case NSPageUpFunctionKey: return @"PgUp";
        case NSPageDownFunctionKey: return @"PgDn";
        case NSDeleteFunctionKey: return @"⌦";
        case NSInsertFunctionKey: return @"Ins";
        case '\b': return @"⌫";
        case '\r': return @"↩";
        case '\t': return @"⇥";
        case 0x1b: return @"⎋";
        case ' ': return @"Space";
        default: return self.key.uppercaseString;
    }
}

- (NSString *)displayString {
    NSMutableString *s = [NSMutableString string];
    if (self.modifiers & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (self.modifiers & NSEventModifierFlagOption) [s appendString:@"⌥"];
    if (self.modifiers & NSEventModifierFlagShift) [s appendString:@"⇧"];
    if (self.modifiers & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    [s appendString:[self keyName]];
    return s;
}

- (NSString *)spec {
    NSMutableString *s = [NSMutableString string];
    if (self.modifiers & NSEventModifierFlagControl) [s appendString:@"ctrl+"];
    if (self.modifiers & NSEventModifierFlagOption) [s appendString:@"opt+"];
    if (self.modifiers & NSEventModifierFlagShift) [s appendString:@"shift+"];
    if (self.modifiers & NSEventModifierFlagCommand) [s appendString:@"cmd+"];
    [s appendString:self.key];
    return s;
}

- (long)scintillaKeyDefinition {
    unichar c = [self.key characterAtIndex:0];
    long key;
    switch (c) {
        case NSDownArrowFunctionKey: key = SCK_DOWN; break;
        case NSUpArrowFunctionKey: key = SCK_UP; break;
        case NSLeftArrowFunctionKey: key = SCK_LEFT; break;
        case NSRightArrowFunctionKey: key = SCK_RIGHT; break;
        case NSHomeFunctionKey: key = SCK_HOME; break;
        case NSEndFunctionKey: key = SCK_END; break;
        case NSPageUpFunctionKey: key = SCK_PRIOR; break;
        case NSPageDownFunctionKey: key = SCK_NEXT; break;
        case NSDeleteFunctionKey: key = SCK_DELETE; break;
        case NSInsertFunctionKey: key = SCK_INSERT; break;
        case '\b': key = SCK_BACK; break;
        case '\r': key = SCK_RETURN; break;
        case '\t': key = SCK_TAB; break;
        case 0x1b: key = SCK_ESCAPE; break;
        default: {
            BOOL shift = (self.modifiers & NSEventModifierFlagShift) != 0;
            unichar k = c;
            if (shift && k >= 'a' && k <= 'z') k = (unichar)(k - 32);
            else if (shift) k = Shifted(k);
            key = k;
        }
    }
    long mods = 0;
    if (self.modifiers & NSEventModifierFlagShift) mods |= SCMOD_SHIFT;
    if (self.modifiers & NSEventModifierFlagCommand) mods |= SCMOD_CTRL;     // Command, on macOS
    if (self.modifiers & NSEventModifierFlagOption) mods |= SCMOD_ALT;
    if (self.modifiers & NSEventModifierFlagControl) mods |= SCMOD_META;     // Control, on macOS
    return key | (mods << 16);
}

+ (instancetype)comboFromScintillaKey:(int)key modifiers:(int)scmod {
    unichar c;
    switch (key) {
        case SCK_DOWN: c = NSDownArrowFunctionKey; break;
        case SCK_UP: c = NSUpArrowFunctionKey; break;
        case SCK_LEFT: c = NSLeftArrowFunctionKey; break;
        case SCK_RIGHT: c = NSRightArrowFunctionKey; break;
        case SCK_HOME: c = NSHomeFunctionKey; break;
        case SCK_END: c = NSEndFunctionKey; break;
        case SCK_PRIOR: c = NSPageUpFunctionKey; break;
        case SCK_NEXT: c = NSPageDownFunctionKey; break;
        case SCK_DELETE: c = NSDeleteFunctionKey; break;
        case SCK_INSERT: c = NSInsertFunctionKey; break;
        case SCK_BACK: c = '\b'; break;
        case SCK_RETURN: c = '\r'; break;
        case SCK_TAB: c = '\t'; break;
        case SCK_ESCAPE: c = 0x1b; break;
        case SCK_ADD: c = '+'; break;
        case SCK_SUBTRACT: c = '-'; break;
        case SCK_DIVIDE: c = '/'; break;
        default: c = (unichar)key;
    }
    NSEventModifierFlags m = 0;
    if (scmod & SCMOD_SHIFT) m |= NSEventModifierFlagShift;
    if (scmod & SCMOD_CTRL) m |= NSEventModifierFlagCommand;
    if (scmod & SCMOD_ALT) m |= NSEventModifierFlagOption;
    if (scmod & SCMOD_META) m |= NSEventModifierFlagControl;
    // Shifted punctuation back to its key.
    const char *plain = "1234567890-=[]\\;',./`", *shifted = "!@#$%^&*()_+{}|:\"<>?~";
    const char *at = c < 128 ? strchr(shifted, (char)c) : NULL;
    if (at && c) c = (unichar)plain[at - shifted];
    return [self comboWithKey:[NSString stringWithCharacters:&c length:1] modifiers:m];
}

@end

@implementation NppShortcutCommand
@end

#pragma mark - The store

/// The menu titles of the port against the Windows ones where they differ.
static NSString *WindowsTopMenu(NSString *top) {
    if ([top isEqualToString:@"Help"]) return @"?";
    return top;
}

static NSString *NormalisedLabel(NSString *label) {
    NSString *s = [[label stringByReplacingOccurrencesOfString:@"&" withString:@""] lowercaseString];
    s = [s stringByReplacingOccurrencesOfString:@"…" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"..." withString:@""];
    NSArray *words = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
            componentsJoinedByString:@" "];
}

static NSString *XMLYesNo(BOOL b) { return b ? @"yes" : @"no"; }

/// Menu path and title in the port -> Notepad++'s command, where the port
/// words it differently (Finder for Explorer, Trash for the Recycle Bin...).
static NSDictionary<NSString *, NSString *> *PortRenamedCommands(void) {
    return @{
        @"File/Close Tab": @"IDM_FILE_CLOSE", @"File/Move to Trash": @"IDM_FILE_DELETE",
        @"Run/Validate shortcuts": @"IDM_EXECUTE_VALIDATE_SHORTCUTSXML",
        @"File/Restore Last Closed File": @"IDM_FILE_RESTORELASTCLOSEDFILE",
        @"File/Open Recent/Open All Recent Files": @"IDM_OPEN_ALL_RECENT_FILE",
        @"File/Open Recent/Clear Menu": @"IDM_CLEAN_RECENT_FILE_LIST",
        @"File/Open Containing Folder/Finder": @"IDM_FILE_OPEN_FOLDER",
        @"File/Open Containing Folder/Terminal": @"IDM_FILE_OPEN_CMD",
        @"File/Open Containing Folder/PowerShell": @"IDM_FILE_OPEN_POWERSHELL",
        @"Edit/Duplicate Line": @"IDM_EDIT_DUP_LINE", @"Edit/Toggle Line Comment": @"IDM_EDIT_BLOCK_COMMENT",
        @"Edit/Line Operations/Sort Lines Lex. Ignoring Case Ascending": @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_ASCENDING",
        @"Edit/Line Operations/Sort Lines Lex. Ignoring Case Descending": @"IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_DESCENDING",
        @"Edit/On Selection/Open Containing Folder in Finder": @"IDM_EDIT_OPENSELECTEDFILEFOLDERINEXPLORER",   // Explorer on Windows (EDIT-083)
        @"Edit/On Selection/Redact Selection": @"IDM_EDIT_REDACT_SELECTION",
        @"View/Zoom/Zoom In": @"IDM_VIEW_ZOOMIN", @"View/Zoom/Zoom Out": @"IDM_VIEW_ZOOMOUT",
        @"View/Zoom/Actual Size": @"IDM_VIEW_ZOOMRESTORE", @"View/Show Whitespace": @"IDM_VIEW_TAB_SPACE",
        @"View/Zoom/Synchronize Across Views": @"IDM_VIEW_ZOOM_SYNC",
        @"View/View Current File in/Safari": @"IDM_VIEW_IN_IE",   // the system browser, as IE was Windows's
        @"Edit/EOL Conversion/Classic Mac (CR)": @"IDM_FORMAT_TOMAC",
        @"Settings/Settings…": @"IDM_SETTING_PREFERENCE",
        @"Help/Check for Updates": @"IDM_UPDATE_NPP", @"Help/About NotepadMac": @"IDM_ABOUT",
        @"NotepadMac/About NotepadMac": @"IDM_ABOUT", @"NotepadMac/Quit NotepadMac": @"IDM_FILE_EXIT",
        @"File/Pin Tab": @"IDM_PINTAB",
        @"Edit/Read-Only/Read-Only Attribute on Disk": @"IDM_EDIT_TOGGLESYSTEMREADONLY",
        @"Window/Recent Window": @"IDM_WINDOW_MRU_FIRST",
        @"Window/Open Documents": @"IDM_DROPLIST_LIST",
    };
}

/// A language's menu command, by the name the port lists it under.
static NSString *LanguageCommand(NSString *name) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (size_t i = 0; i < sizeof(kNppLangLexers) / sizeof(kNppLangLexers[0]); ++i) {
            if (kNppLangLexers[i].menuID) m[@(kNppLangLexers[i].langName)] = @(kNppLangLexers[i].menuID);
        }
        map = m;
    });
    return map[name];
}

@interface NppShortcutStore ()
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *menuDefaults;       // key -> combo or NSNull
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *menuOverrides;      // key -> combo or NSNull
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *macroCombos;        // name -> combo
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *runCombos;          // name -> combo
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray *> *scintillaOverrides;
@property (nonatomic, strong) NSMutableArray<NSXMLElement *> *keptInternal;            // ids the port has no command for
@property (nonatomic, strong, nullable) NSXMLElement *keptPluginCommands;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<NppKeyCombo *> *> *scintillaDefaults;
@end

@implementation NppShortcutStore

- (instancetype)initWithEditor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _editor = editor;
    _menuDefaults = [NSMutableDictionary dictionary];
    _menuOverrides = [NSMutableDictionary dictionary];
    _macroCombos = [NSMutableDictionary dictionary];
    _runCombos = [NSMutableDictionary dictionary];
    _scintillaOverrides = [NSMutableDictionary dictionary];
    _keptInternal = [NSMutableArray array];
    _scintillaDefaults = [NSMutableDictionary dictionary];
    for (int i = 0; i < kNppScintillaMacDefaultCount; ++i) {
        NppKeyCombo *combo = [NppKeyCombo comboFromScintillaKey:kNppScintillaMacDefaults[i].key
                                                     modifiers:kNppScintillaMacDefaults[i].modifiers];
        NSNumber *msg = @(kNppScintillaMacDefaults[i].message);
        if (!combo) continue;
        if (!_scintillaDefaults[msg]) _scintillaDefaults[msg] = [NSMutableArray array];
        [_scintillaDefaults[msg] addObject:combo];
    }
    return self;
}

- (NSString *)path {
    return [[self.editor supportDirectory] stringByAppendingPathComponent:@"shortcuts.xml"];
}

#pragma mark Walking the menus

/// Every leaf of the main menu that is a command, with its path.
- (void)walkMenu:(NSMenu *)menu path:(NSArray<NSString *> *)path
           block:(void (^)(NSMenuItem *item, NSArray<NSString *> *path))block {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        if (item.submenu) {
            if (item.submenu == NSApp.servicesMenu) continue;
            // A menu-bar item has no title of its own; its menu has.
            // English titles: a translated menu is still found by what it was.
            NSString *title = NppEnglishMenuTitle(item.submenu).length ? NppEnglishMenuTitle(item.submenu) : NppEnglishTitle(item);
            [self walkMenu:item.submenu path:[path arrayByAddingObject:title] block:block];
            continue;
        }
        if (!item.action || !NppEnglishTitle(item).length) continue;
        block(item, path);
    }
}

static BOOL IsListedElsewhere(NSMenuItem *item) {
    SEL a = item.action;
    return a == NSSelectorFromString(@"openRecentFile:") || a == NSSelectorFromString(@"runSavedCommand:") ||
           a == NSSelectorFromString(@"playSavedMacro:") || a == @selector(makeKeyAndOrderFront:);
}

static NSString *MenuKey(NSMenuItem *item, NSArray<NSString *> *path) {
    return [[path arrayByAddingObject:NppEnglishTitle(item)] componentsJoinedByString:@"/"];
}

- (NSDictionary<NSNumber *, NSMenuItem *> *)menuItemsByIdentifier {
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    [self walkMenu:NSApp.mainMenu path:@[] block:^(NSMenuItem *item, NSArray<NSString *> *path) {
        if (!item.action) return;
        int identifier = [self identifierForItem:item path:path];
        if (identifier > 0 && !found[@(identifier)]) found[@(identifier)] = item;
    }];
    return found;
}

- (void)captureMenuDefaults {
    [self walkMenu:NSApp.mainMenu path:@[] block:^(NSMenuItem *item, NSArray<NSString *> *path) {
        if (IsListedElsewhere(item)) return;
        NSEventModifierFlags mods = 0;
        NSString *k = NppMenuItemKey(item, &mods);
        NppKeyCombo *combo = k.length ? [NppKeyCombo comboWithKey:k modifiers:mods] : nil;
        self.menuDefaults[MenuKey(item, path)] = combo ?: [NSNull null];
    }];
}

/// Notepad++'s id of a menu command, by its menu and label.
- (int)identifierForItem:(NSMenuItem *)item path:(NSArray<NSString *> *)path {
    static NSDictionary<NSString *, NSNumber *> *byTopAndLabel;
    static NSDictionary<NSString *, NSArray *> *byLabel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *a = [NSMutableDictionary dictionary], *b = [NSMutableDictionary dictionary];
        for (int i = 0; i < kNppMenuCommandIDCount; ++i) {
            NSArray *parts = [@(kNppMenuCommandIDs[i].path) componentsSeparatedByString:@"/"];
            NSString *top = parts.firstObject ?: @"";
            NSString *label = NormalisedLabel(@(kNppMenuCommandIDs[i].label));
            // By the whole path first - a label such as "Using 1st Style"
            // recurs under several submenus - then by the menu alone.
            NSMutableArray *whole = [NSMutableArray array];
            for (NSString *p in parts) [whole addObject:NormalisedLabel(p)];
            [whole addObject:label];
            a[[whole componentsJoinedByString:@"/"]] = @(kNppMenuCommandIDs[i].identifier);
            NSString *byTop = [NSString stringWithFormat:@"%@/%@", NormalisedLabel(top), label];
            if (!a[byTop]) a[byTop] = @(kNppMenuCommandIDs[i].identifier);
            NSMutableArray *list = b[label] ?: [NSMutableArray array];
            [list addObject:@(kNppMenuCommandIDs[i].identifier)];
            b[label] = list;
        }
        byTopAndLabel = a;
        byLabel = b;
    });
    // Tools: Notepad++ has its four digests at the top of the menu; here they
    // are gathered under Hashes with the ones the port adds. A digest upstream
    // has is found by its path without that level, and nothing else in Tools
    // is Notepad++'s - least of all by a label ("Generate...") that each digest has.
    if (path.count >= 2 && [path[0] isEqualToString:@"Tools"]) {
        if (![path[1] isEqualToString:@"Hashes"] || path.count != 3) return 0;
        NSString *exact = [NSString stringWithFormat:@"tools/%@/%@", NormalisedLabel(path[2]), NormalisedLabel(NppEnglishTitle(item))];
        return [byTopAndLabel[exact] intValue];
    }
    if (path.count == 1 && [path[0] isEqualToString:@"Tools"]) return 0;
    NSString *label = NormalisedLabel(NppEnglishTitle(item));
    NSMutableArray *whole = [NSMutableArray array];
    for (NSUInteger i = 0; i < path.count; ++i) {
        [whole addObject:NormalisedLabel(i == 0 ? WindowsTopMenu(path[i]) : path[i])];
    }
    [whole addObject:label];
    NSNumber *found = byTopAndLabel[[whole componentsJoinedByString:@"/"]];
    if (found) return found.intValue;
    NSString *top = NormalisedLabel(WindowsTopMenu(path.firstObject ?: @""));
    found = byTopAndLabel[[NSString stringWithFormat:@"%@/%@", top, label]];
    if (found) return found.intValue;
    NSArray *candidates = byLabel[label];
    if (candidates.count == 1) return [candidates.firstObject intValue];
    // Commands the port names in its own words, and the languages, which
    // it lists under Notepad++'s internal names.
    NSString *idm = PortRenamedCommands()[[[path arrayByAddingObject:NppEnglishTitle(item)] componentsJoinedByString:@"/"]];
    if (!idm && [path.firstObject isEqualToString:@"Language"] && path.count == 1) idm = LanguageCommand(NppEnglishTitle(item));
    if (idm) {
        for (int i = 0; i < kNppMenuCommandIDCount; ++i) {
            if (strcmp(kNppMenuCommandIDs[i].name, idm.UTF8String) == 0) return kNppMenuCommandIDs[i].identifier;
        }
    }
    return 0;
}

#pragma mark The commands

- (NSArray<NppShortcutCommand *> *)commandsInCategory:(NppShortcutCategory)category {
    NSMutableArray *out = [NSMutableArray array];
    switch (category) {
        case NppShortcutMainMenu: {
            [self walkMenu:NSApp.mainMenu path:@[] block:^(NSMenuItem *item, NSArray<NSString *> *path) {
                if (IsListedElsewhere(item)) return;
                NppShortcutCommand *c = [[NppShortcutCommand alloc] init];
                c.category = NppShortcutMainMenu;
                c.name = item.title;
                c.detail = [path componentsJoinedByString:@" › "];
                c.key = MenuKey(item, path);
                c.identifier = [self identifierForItem:item path:path];
                NSEventModifierFlags mods = 0;
                NSString *k = NppMenuItemKey(item, &mods);
                c.combo = k.length ? [NppKeyCombo comboWithKey:k modifiers:mods] : nil;
                c.extraCombos = @[];
                [out addObject:c];
            }];
            break;
        }
        case NppShortcutMacro: {
            for (NSString *name in [self.editor savedMacroNames]) {
                NppShortcutCommand *c = [[NppShortcutCommand alloc] init];
                c.category = NppShortcutMacro;
                c.name = name; c.detail = @"Macro"; c.key = name;
                id combo = self.macroCombos[name];
                c.combo = [combo isKindOfClass:[NppKeyCombo class]] ? combo : nil;
                c.extraCombos = @[];
                [out addObject:c];
            }
            break;
        }
        case NppShortcutRunCommand: {
            for (NppSavedCommand *saved in [self.editor savedCommands]) {
                NppShortcutCommand *c = [[NppShortcutCommand alloc] init];
                c.category = NppShortcutRunCommand;
                c.name = saved.name; c.detail = saved.command; c.key = saved.name;
                id combo = self.runCombos[saved.name];
                c.combo = [combo isKindOfClass:[NppKeyCombo class]] ? combo : nil;
                c.extraCombos = @[];
                [out addObject:c];
            }
            break;
        }
        case NppShortcutPlugin:
            break;                                   // no plugins are loaded on macOS
        case NppShortcutScintilla: {
            for (int i = 0; i < kNppScintillaKeyDefinitionCount; ++i) {
                const NppScintillaKeyDefinition *d = &kNppScintillaKeyDefinitions[i];
                if (!d->name[0]) continue;           // an extra key of the command above
                NppShortcutCommand *c = [[NppShortcutCommand alloc] init];
                c.category = NppShortcutScintilla;
                c.name = @(d->name); c.detail = @"Scintilla"; c.identifier = d->message; c.key = c.name;
                NSArray *combos = [self scintillaCombosFor:d->message];
                c.combo = combos.firstObject;
                c.extraCombos = combos.count > 1 ? [combos subarrayWithRange:NSMakeRange(1, combos.count - 1)] : @[];
                [out addObject:c];
            }
            break;
        }
    }
    return out;
}

- (NSArray<NppKeyCombo *> *)scintillaCombosFor:(int)message {
    NSArray *over = self.scintillaOverrides[@(message)];
    return over ?: (self.scintillaDefaults[@(message)] ?: @[]);
}

#pragma mark Assigning

- (void)setCombo:(NppKeyCombo *)combo forCommand:(NppShortcutCommand *)command {
    switch (command.category) {
        case NppShortcutMainMenu: {
            id def = self.menuDefaults[command.key];
            NppKeyCombo *defCombo = [def isKindOfClass:[NppKeyCombo class]] ? def : nil;
            if ((!combo && !defCombo) || (combo && [combo isEqual:defCombo])) [self.menuOverrides removeObjectForKey:command.key];
            else self.menuOverrides[command.key] = combo ?: [NSNull null];
            break;
        }
        case NppShortcutMacro:
            if (combo) self.macroCombos[command.key] = combo; else [self.macroCombos removeObjectForKey:command.key];
            break;
        case NppShortcutRunCommand:
            if (combo) self.runCombos[command.key] = combo; else [self.runCombos removeObjectForKey:command.key];
            break;
        case NppShortcutPlugin:
            return;
        case NppShortcutScintilla: {
            NSMutableArray *combos = [NSMutableArray array];
            if (combo) [combos addObject:combo];
            // The extra keys stay, unless the new one is among them.
            for (NppKeyCombo *extra in command.extraCombos) if (![extra isEqual:combo]) [combos addObject:extra];
            self.scintillaOverrides[@(command.identifier)] = combos;
            break;
        }
    }
    command.combo = combo;
    [self applyToMenus];
    [self applyScintillaKeysTo:self.editor.mainSci];
    if (self.editor.secondarySci) [self applyScintillaKeysTo:self.editor.secondarySci];
    [self save];
}

- (NSArray<NppShortcutCommand *> *)conflictsWith:(NppKeyCombo *)combo except:(NppShortcutCommand *)command {
    if (!combo) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSInteger cat = NppShortcutMainMenu; cat <= NppShortcutScintilla; ++cat) {
        for (NppShortcutCommand *other in [self commandsInCategory:(NppShortcutCategory)cat]) {
            if (command && other.category == command.category && [other.key isEqualToString:command.key]) continue;
            BOOL clash = [other.combo isEqual:combo];
            for (NppKeyCombo *extra in other.extraCombos) if ([extra isEqual:combo]) clash = YES;
            if (clash) [out addObject:other];
        }
    }
    return out;
}

#pragma mark Applying

- (void)applyToMenus {
    [self walkMenu:NSApp.mainMenu path:@[] block:^(NSMenuItem *item, NSArray<NSString *> *path) {
        NppKeyCombo *combo = nil;
        BOOL decided = NO;
        if (item.action == NSSelectorFromString(@"playSavedMacro:")) {
            id c = self.macroCombos[item.representedObject ?: item.title];
            combo = [c isKindOfClass:[NppKeyCombo class]] ? c : nil;
            decided = YES;
        } else if (item.action == NSSelectorFromString(@"runSavedCommand:")) {
            id c = self.runCombos[NppEnglishTitle(item)];
            combo = [c isKindOfClass:[NppKeyCombo class]] ? c : nil;
            decided = YES;
        } else if (!IsListedElsewhere(item)) {
            NSString *key = MenuKey(item, path);
            id over = self.menuOverrides[key];
            if (over) {
                combo = [over isKindOfClass:[NppKeyCombo class]] ? over : nil;
                decided = YES;
            } else if (self.menuDefaults[key]) {
                id def = self.menuDefaults[key];
                combo = [def isKindOfClass:[NppKeyCombo class]] ? def : nil;
                decided = YES;
            }
        }
        if (!decided) return;
        NppSetMenuKey(item, combo.key ?: @"", combo ? combo.modifiers : 0);
    }];
}

- (void)applyScintillaKeysTo:(id)view {
    ScintillaView *sci = view;
    if (!sci) return;
    // What an earlier call gave this view goes first: a key that was
    // reassigned or cleared since must stop working now, not at the next launch.
    static const char kAppliedKey = 0;
    for (NSNumber *definition in objc_getAssociatedObject(sci, &kAppliedKey) ?: @[]) {
        [sci message:SCI_CLEARCMDKEY wParam:(uptr_t)definition.longValue lParam:0];
    }
    // A key taken from another command's defaults and now given up goes back to it.
    NSSet<NSNumber *> *cleared = [NSSet setWithArray:objc_getAssociatedObject(sci, &kAppliedKey) ?: @[]];
    for (NSNumber *message in self.scintillaDefaults) {
        if (self.scintillaOverrides[message]) continue;
        for (NppKeyCombo *combo in self.scintillaDefaults[message]) {
            if ([cleared containsObject:@(combo.scintillaKeyDefinition)]) {
                [sci message:SCI_ASSIGNCMDKEY wParam:(uptr_t)combo.scintillaKeyDefinition lParam:message.intValue];
            }
        }
    }
    NSMutableArray<NSNumber *> *applied = [NSMutableArray array];
    for (NSNumber *message in self.scintillaOverrides) {
        for (NppKeyCombo *combo in self.scintillaOverrides[message]) [applied addObject:@(combo.scintillaKeyDefinition)];
    }
    objc_setAssociatedObject(sci, &kAppliedKey, applied, OBJC_ASSOCIATION_RETAIN);
    for (NSNumber *message in self.scintillaOverrides) {
        for (NppKeyCombo *old in self.scintillaDefaults[message] ?: @[]) {
            [sci message:SCI_CLEARCMDKEY wParam:(uptr_t)old.scintillaKeyDefinition lParam:0];
        }
    }
    for (NSNumber *message in self.scintillaOverrides) {
        for (NppKeyCombo *combo in self.scintillaOverrides[message]) {
            [sci message:SCI_ASSIGNCMDKEY wParam:(uptr_t)combo.scintillaKeyDefinition lParam:message.intValue];
        }
    }
}

#pragma mark shortcuts.xml

static NppKeyCombo *ComboFromElement(NSXMLElement *e) {
    BOOL (^yes)(NSString *) = ^BOOL(NSString *name) {
        return [[e attributeForName:name].stringValue isEqualToString:@"yes"];
    };
    return [NppKeyCombo comboWithWindowsCtrl:yes(@"Ctrl") alt:yes(@"Alt") shift:yes(@"Shift")
                                  macControl:yes(@"MacCtrl") virtualKey:[e attributeForName:@"Key"].stringValue.intValue];
}

static void AddComboAttributes(NSXMLElement *e, NppKeyCombo *combo) {
    [e addAttribute:[NSXMLNode attributeWithName:@"Ctrl" stringValue:XMLYesNo(combo.modifiers & NSEventModifierFlagCommand)]];
    [e addAttribute:[NSXMLNode attributeWithName:@"Alt" stringValue:XMLYesNo(combo.modifiers & NSEventModifierFlagOption)]];
    [e addAttribute:[NSXMLNode attributeWithName:@"Shift" stringValue:XMLYesNo(combo.modifiers & NSEventModifierFlagShift)]];
    [e addAttribute:[NSXMLNode attributeWithName:@"Key" stringValue:[@(combo ? combo.windowsVirtualKey : 0) stringValue]]];
    if (combo.modifiers & NSEventModifierFlagControl) {
        [e addAttribute:[NSXMLNode attributeWithName:@"MacCtrl" stringValue:@"yes"]];
    }
}

- (void)load {
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:[NSData dataWithContentsOfFile:[self path]] ?: [NSData data]
                                                     options:0 error:NULL];
    NSXMLElement *root = doc.rootElement;
    NSDictionary *menuByID = [self menuCommandsByIdentifier];

    for (NSXMLElement *s in [[root elementsForName:@"InternalCommands"].firstObject elementsForName:@"Shortcut"]) {
        int identifier = [s attributeForName:@"id"].stringValue.intValue;
        NppShortcutCommand *c = menuByID[@(identifier)];
        if (!c) { [self.keptInternal addObject:[s copy]]; continue; }
        self.menuOverrides[c.key] = ComboFromElement(s) ?: [NSNull null];
    }
    for (NSXMLElement *s in [[root elementsForName:@"MacOSCommands"].firstObject elementsForName:@"Shortcut"]) {
        NSString *key = [s attributeForName:@"path"].stringValue;
        if (key.length) self.menuOverrides[key] = ComboFromElement(s) ?: [NSNull null];
    }
    __block BOOL imported = NO;
    for (NSXMLElement *m in [[root elementsForName:@"Macros"].firstObject elementsForName:@"Macro"]) {
        NSString *name = [m attributeForName:@"name"].stringValue;
        if (!name.length) continue;
        NppKeyCombo *combo = ComboFromElement(m);
        if (combo) self.macroCombos[name] = combo;
        if (![self.editor stepsOfSavedMacroNamed:name]) {
            // A macro written on Windows, every kind of step: Scintilla
            // messages (0, 1), menu commands (2) and the Find dialog's (3).
            NSMutableArray *steps = [NSMutableArray array];
            for (NSXMLElement *a in [m elementsForName:@"Action"]) {
                int type = [a attributeForName:@"type"].stringValue.intValue;
                if (type < 0 || type > 3) continue;
                NSMutableDictionary *step = [@{@"msg": @([a attributeForName:@"message"].stringValue.intValue),
                                               @"w": @([a attributeForName:@"wParam"].stringValue.longLongValue),
                                               @"l": @([a attributeForName:@"lParam"].stringValue.longLongValue)} mutableCopy];
                NSString *text = [a attributeForName:@"sParam"].stringValue;
                if (type >= 2) { step[@"type"] = @(type); step[@"text"] = text ?: @""; }
                else if (type == 1 && text.length) step[@"text"] = text;
                [steps addObject:step];
            }
            if (steps.count) { [self.editor storeSavedMacro:steps named:name]; imported = YES; }
        }
    }
    for (NSXMLElement *c in [[root elementsForName:@"UserDefinedCommands"].firstObject elementsForName:@"Command"]) {
        NSString *name = [c attributeForName:@"name"].stringValue;
        if (!name.length) continue;
        NppKeyCombo *combo = ComboFromElement(c);
        if (combo) self.runCombos[name] = combo;
        BOOL known = NO;
        for (NppSavedCommand *s in [self.editor savedCommands]) if ([s.name isEqualToString:name]) known = YES;
        if (!known && c.stringValue.length) {
            NppSavedCommand *saved = [[NppSavedCommand alloc] init];
            saved.name = name;
            saved.command = c.stringValue;
            [self.editor saveCommand:saved];
            imported = YES;
        }
    }
    // The Macro and Run menus were built before this file was read: a macro or a
    // command taken over from it shows at once, not from the next launch (SETTINGS-106).
    if (imported) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NppSavedCommandsDidChange" object:self];
        });
    }
    self.keptPluginCommands = [[root elementsForName:@"PluginCommands"].firstObject copy];
    for (NSXMLElement *k in [[root elementsForName:@"ScintillaKeys"].firstObject elementsForName:@"ScintKey"]) {
        int message = [k attributeForName:@"ScintID"].stringValue.intValue;
        if (!message) continue;
        NSMutableArray *combos = [NSMutableArray array];
        NppKeyCombo *first = ComboFromElement(k);
        if (first) [combos addObject:first];
        for (NSXMLElement *next in [k elementsForName:@"NextKey"]) {
            NppKeyCombo *combo = ComboFromElement(next);
            if (combo) [combos addObject:combo];
        }
        self.scintillaOverrides[@(message)] = combos;
    }

    // The older preference: a title and "cmd+shift+k", carried over once.
    if (!doc) {
        NSDictionary *legacy = [NppPreferences shared].shortcutOverrides;
        if (legacy.count) {
            for (NppShortcutCommand *c in [self commandsInCategory:NppShortcutMainMenu]) {
                NSString *spec = legacy[c.name];
                if (spec) self.menuOverrides[c.key] = [NppKeyCombo comboFromSpec:spec] ?: [NSNull null];
            }
            [self save];
        }
    }
    [self applyToMenus];
    [self applyScintillaKeysTo:self.editor.mainSci];
    if (self.editor.secondarySci) [self applyScintillaKeysTo:self.editor.secondarySci];
}

- (NSDictionary<NSNumber *, NppShortcutCommand *> *)menuCommandsByIdentifier {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NppShortcutCommand *c in [self commandsInCategory:NppShortcutMainMenu]) {
        if (c.identifier && !out[@(c.identifier)]) out[@(c.identifier)] = c;
    }
    return out;
}

- (BOOL)save {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];

    NSXMLElement *internal = [NSXMLElement elementWithName:@"InternalCommands"];
    NSXMLElement *mac = [NSXMLElement elementWithName:@"MacOSCommands"];
    for (NppShortcutCommand *c in [self commandsInCategory:NppShortcutMainMenu]) {
        id over = self.menuOverrides[c.key];
        if (!over) continue;
        NppKeyCombo *combo = [over isKindOfClass:[NppKeyCombo class]] ? over : nil;
        NSXMLElement *s = [NSXMLElement elementWithName:@"Shortcut"];
        if (c.identifier) {
            [s addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:[@(c.identifier) stringValue]]];
            AddComboAttributes(s, combo);
            [internal addChild:s];
        } else {
            [s addAttribute:[NSXMLNode attributeWithName:@"path" stringValue:c.key]];
            AddComboAttributes(s, combo);
            [mac addChild:s];
        }
    }
    for (NSXMLElement *kept in self.keptInternal) [internal addChild:[kept copy]];
    [root addChild:internal];

    NSXMLElement *macros = [NSXMLElement elementWithName:@"Macros"];
    for (NSString *name in [self.editor savedMacroNames]) {
        NSXMLElement *m = [NSXMLElement elementWithName:@"Macro"];
        [m addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:name]];
        id combo = self.macroCombos[name];
        AddComboAttributes(m, [combo isKindOfClass:[NppKeyCombo class]] ? combo : nil);
        for (NSDictionary *step in [self.editor stepsOfSavedMacroNamed:name] ?: @[]) {
            if (![step isKindOfClass:[NSDictionary class]]) continue;
            NSXMLElement *a = [NSXMLElement elementWithName:@"Action"];
            NSString *text = step[@"text"];
            int type = [step[@"type"] intValue];
            if (type >= 2) {
                // Menu commands and Find steps go back as they came.
                [a addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:@(type).stringValue]];
                [a addAttribute:[NSXMLNode attributeWithName:@"message" stringValue:[step[@"msg"] description]]];
                [a addAttribute:[NSXMLNode attributeWithName:@"wParam" stringValue:[step[@"w"] ?: @0 description]]];
                [a addAttribute:[NSXMLNode attributeWithName:@"lParam" stringValue:[step[@"l"] ?: @0 description]]];
                [a addAttribute:[NSXMLNode attributeWithName:@"sParam" stringValue:text ?: @""]];
                [m addChild:a];
                continue;
            }
            [a addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:text.length ? @"1" : @"0"]];
            [a addAttribute:[NSXMLNode attributeWithName:@"message" stringValue:[step[@"msg"] description]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"wParam" stringValue:[step[@"w"] ?: @0 description]]];
            // A text step's lParam was a pointer when it was recorded; Windows
            // writes 0 there and carries the text in sParam.
            [a addAttribute:[NSXMLNode attributeWithName:@"lParam"
                                             stringValue:text.length ? @"0" : [step[@"l"] ?: @0 description]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"sParam" stringValue:text ?: @""]];
            [m addChild:a];
        }
        [macros addChild:m];
    }
    [root addChild:macros];

    NSXMLElement *commands = [NSXMLElement elementWithName:@"UserDefinedCommands"];
    for (NppSavedCommand *saved in [self.editor savedCommands]) {
        NSXMLElement *c = [NSXMLElement elementWithName:@"Command" stringValue:saved.command ?: @""];
        [c addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:saved.name]];
        id combo = self.runCombos[saved.name];
        AddComboAttributes(c, [combo isKindOfClass:[NppKeyCombo class]] ? combo : nil);
        [commands addChild:c];
    }
    [root addChild:commands];
    [root addChild:self.keptPluginCommands ? [self.keptPluginCommands copy] : [NSXMLElement elementWithName:@"PluginCommands"]];

    NSXMLElement *scintilla = [NSXMLElement elementWithName:@"ScintillaKeys"];
    for (NSNumber *message in [self.scintillaOverrides.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray<NppKeyCombo *> *combos = self.scintillaOverrides[message];
        int menuCommand = 0;
        for (int i = 0; i < kNppScintillaKeyDefinitionCount; ++i) {
            if (kNppScintillaKeyDefinitions[i].message == message.intValue && kNppScintillaKeyDefinitions[i].name[0]) {
                menuCommand = kNppScintillaKeyDefinitions[i].menuCommand;
                break;
            }
        }
        NSXMLElement *k = [NSXMLElement elementWithName:@"ScintKey"];
        [k addAttribute:[NSXMLNode attributeWithName:@"ScintID" stringValue:message.stringValue]];
        [k addAttribute:[NSXMLNode attributeWithName:@"menuCmdID" stringValue:[@(menuCommand) stringValue]]];
        AddComboAttributes(k, combos.firstObject);
        for (NSUInteger i = 1; i < combos.count; ++i) {
            NSXMLElement *next = [NSXMLElement elementWithName:@"NextKey"];
            AddComboAttributes(next, combos[i]);
            [k addChild:next];
        }
        [scintilla addChild:k];
    }
    [root addChild:scintilla];
    if (mac.childCount) [root addChild:mac];

    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.version = @"1.0";
    doc.characterEncoding = @"UTF-8";
    return [[doc XMLDataWithOptions:NSXMLNodePrettyPrint | NSXMLNodeCompactEmptyElement]
            writeToFile:[self path] options:NSDataWritingAtomic error:NULL];
}

@end

#pragma mark - The window

@interface NppShortcutMapper ()
@property (nonatomic, strong) NppShortcutStore *store;
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NppPanel *panel;
@property (nonatomic, strong) NSSegmentedControl *tabs;
@property (nonatomic, strong) NSSearchField *search;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, strong) NSTextField *conflictLine;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, strong, readwrite) NSArray<NppShortcutCommand *> *shownCommands;
@property (nonatomic, strong) NSSet<NSString *> *conflicting;
@end

@implementation NppShortcutMapper

- (instancetype)initWithStore:(NppShortcutStore *)store editor:(EditorController *)editor {
    if (!(self = [super init])) return nil;
    _store = store;
    _editor = editor;
    _filter = @"";
    _panel = [[NppPanel alloc] initWithContentRect:NSMakeRect(0, 0, 760, 520)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered defer:YES];
    _panel.title = @"Shortcut Mapper";
    _panel.releasedWhenClosed = NO;
    NSView *content = _panel.contentView;

    _tabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Main menu", @"Macros", @"Run commands",
                                                             @"Plugin commands", @"Scintilla commands"]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                    target:self action:@selector(tabChanged:)];
    _tabs.frame = NSMakeRect(16, 484, 560, 24);
    _tabs.selectedSegment = 0;
    _tabs.autoresizingMask = NSViewMinYMargin;
    [content addSubview:_tabs];

    _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(584, 484, 160, 24)];
    _search.placeholderString = @"Filter";
    _search.delegate = self;
    _search.autoresizingMask = NSViewMinYMargin | NSViewMinXMargin;
    [content addSubview:_search];

    _table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 728, 400)];
    NSArray *columns = @[@[@"name", @"Name", @320], @[@"shortcut", @"Shortcut", @150], @[@"detail", @"Where", @240]];
    for (NSArray *c in columns) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [_table addTableColumn:col];
    }
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(modify:);
    _table.usesAlternatingRowBackgroundColors = YES;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 76, 728, 400)];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:scroll];

    _conflictLine = [NSTextField labelWithString:@""];
    _conflictLine.frame = NSMakeRect(16, 48, 728, 20);
    _conflictLine.textColor = NSColor.systemRedColor;
    [content addSubview:_conflictLine];

    CGFloat x = 16;
    for (NSArray *b in @[@[@"Modify…", @"modify:"], @[@"Clear", @"clear:"], @[@"Delete", @"deleteCommand:"]]) {
        NSButton *button = [NSButton buttonWithTitle:b[0] target:self action:NSSelectorFromString(b[1])];
        button.frame = NSMakeRect(x, 12, 100, 28);
        [content addSubview:button];
        if ([b[0] isEqualToString:@"Delete"]) _deleteButton = button;
        x += 106;
    }
    NSButton *close = [NSButton buttonWithTitle:@"Close" target:_panel action:@selector(orderOut:)];
    close.frame = NSMakeRect(644, 12, 100, 28);
    close.autoresizingMask = NSViewMinXMargin;
    [content addSubview:close];
    [self reload];
    return self;
}

- (BOOL)visible { return self.panel.isVisible; }

- (void)toggle {
    if (self.panel.isVisible) { [self.panel orderOut:nil]; return; }
    [self reload];
    [self.panel makeKeyAndOrderFront:nil];
}

- (void)setCategory:(NppShortcutCategory)category {
    _category = category;
    self.tabs.selectedSegment = category;
    [self reload];
}

- (void)setFilter:(NSString *)filter {
    _filter = [filter copy] ?: @"";
    self.search.stringValue = _filter;
    [self reload];
}

- (void)tabChanged:(id)sender { _category = (NppShortcutCategory)self.tabs.selectedSegment; [self reload]; }
- (void)controlTextDidChange:(NSNotification *)note { _filter = self.search.stringValue ?: @""; [self reload]; }

- (void)reload {
    NSArray *all = [self.store commandsInCategory:self.category];
    NSString *f = self.filter.lowercaseString;
    if (f.length) {
        all = [all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppShortcutCommand *c, NSDictionary *b) {
            return [c.name.lowercaseString containsString:f] || [c.detail.lowercaseString containsString:f] ||
                   [c.combo.displayString.lowercaseString containsString:f];
        }]];
    }
    self.shownCommands = all;
    // Conflicts are marked in the table, as the Windows mapper marks them.
    NSMutableDictionary<NppKeyCombo *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    NSMutableArray *everything = [NSMutableArray array];
    for (NSInteger cat = NppShortcutMainMenu; cat <= NppShortcutScintilla; ++cat) {
        [everything addObjectsFromArray:[self.store commandsInCategory:(NppShortcutCategory)cat]];
    }
    for (NppShortcutCommand *c in everything) {
        if (c.combo) counts[c.combo] = @(counts[c.combo].intValue + 1);
    }
    NSMutableSet *clashing = [NSMutableSet set];
    for (NppShortcutCommand *c in everything) {
        if (c.combo && counts[c.combo].intValue > 1) [clashing addObject:[NSString stringWithFormat:@"%ld/%@", (long)c.category, c.key]];
    }
    self.conflicting = clashing;
    self.deleteButton.enabled = self.category == NppShortcutMacro || self.category == NppShortcutRunCommand;
    self.conflictLine.stringValue = self.category == NppShortcutPlugin
        ? @"Plugins are not loaded on macOS; their commands have nothing to be assigned to." : @"";
    [self.table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)self.shownCommands.count; }

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.shownCommands.count) return @"";
    NppShortcutCommand *c = self.shownCommands[(NSUInteger)row];
    if ([column.identifier isEqualToString:@"name"]) return c.name;
    if ([column.identifier isEqualToString:@"detail"]) {
        // The menu path, shown in the interface language; the application's own
        // menu has no title of its own and goes by the program's name.
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *part in [c.detail componentsSeparatedByString:@" › "]) {
            if ([part isEqualToString:@"NSMenuItem"]) [parts addObject:[NSProcessInfo processInfo].processName];
            else [parts addObject:NppL(part)];
        }
        return [parts componentsJoinedByString:@" › "];
    }
    NSMutableArray *parts = [NSMutableArray array];
    if (c.combo) [parts addObject:c.combo.displayString];
    for (NppKeyCombo *extra in c.extraCombos) [parts addObject:extra.displayString];
    return [parts componentsJoinedByString:@"  "];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (![cell respondsToSelector:@selector(setTextColor:)] || row >= (NSInteger)self.shownCommands.count) return;
    NppShortcutCommand *c = self.shownCommands[(NSUInteger)row];
    BOOL clash = [self.conflicting containsObject:[NSString stringWithFormat:@"%ld/%@", (long)c.category, c.key]];
    [cell setTextColor:clash ? NSColor.systemRedColor : NSColor.labelColor];
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    NppShortcutCommand *c = [self selected];
    if (!c || !c.combo) { if (self.category != NppShortcutPlugin) self.conflictLine.stringValue = @""; return; }
    NSArray *others = [self.store conflictsWith:c.combo except:c];
    self.conflictLine.stringValue = others.count
        ? [NSString stringWithFormat:@"%@ is also used by: %@", c.combo.displayString,
           [[others valueForKey:@"name"] componentsJoinedByString:@", "]] : @"";
}

- (NppShortcutCommand *)selected {
    NSInteger row = self.table.selectedRow;
    if (row < 0) row = self.table.clickedRow;
    return (row >= 0 && row < (NSInteger)self.shownCommands.count) ? self.shownCommands[(NSUInteger)row] : nil;
}

/// Asks for a key by having it pressed, shows what else uses it, and assigns.
- (void)modify:(id)sender {
    NppShortcutCommand *command = [self selected];
    if (!command || command.category == NppShortcutPlugin) { NppBeep(); return; }
    NSAlert *ask = [[NSAlert alloc] init];
    ask.messageText = [NSString stringWithFormat:@"Shortcut for \"%@\"", command.name];
    ask.informativeText = @"Press the keys.";
    NSTextField *shown = [NSTextField labelWithString:command.combo.displayString ?: @"(none)"];
    shown.font = [NSFont systemFontOfSize:22];
    shown.frame = NSMakeRect(0, 22, 320, 30);
    NSTextField *warning = [NSTextField labelWithString:@""];
    warning.textColor = NSColor.systemRedColor;
    warning.frame = NSMakeRect(0, 0, 320, 18);
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 56)];
    [box addSubview:shown];
    [box addSubview:warning];
    ask.accessoryView = box;
    [ask addButtonWithTitle:@"OK"];
    [ask addButtonWithTitle:@"Cancel"];
    [ask addButtonWithTitle:@"Remove"];
    __block NppKeyCombo *captured = command.combo;
    id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        NppKeyCombo *combo = [NppKeyCombo comboFromEvent:event];
        // Return and Escape alone answer the sheet; with a modifier they are keys.
        if (!combo || ((event.keyCode == 36 || event.keyCode == 53) && !(event.modifierFlags & kComboMask))) return event;
        captured = combo;
        shown.stringValue = combo.displayString;
        NSArray *others = [self.store conflictsWith:combo except:command];
        warning.stringValue = others.count
            ? [NSString stringWithFormat:@"Used by: %@", [[others valueForKey:@"name"] componentsJoinedByString:@", "]] : @"";
        return nil;
    }];
    NSModalResponse r = [ask runModal];
    [NSEvent removeMonitor:monitor];
    if (r == NSAlertSecondButtonReturn) return;
    NppKeyCombo *chosen = r == NSAlertThirdButtonReturn ? nil : captured;
    NSArray *others = chosen ? [self.store conflictsWith:chosen except:command] : @[];
    if (others.count) {
        NSAlert *clash = [[NSAlert alloc] init];
        clash.messageText = [NSString stringWithFormat:@"%@ is already used by %@.", chosen.displayString,
                             [[others valueForKey:@"name"] componentsJoinedByString:@", "]];
        [clash addButtonWithTitle:@"Take it from them"];
        [clash addButtonWithTitle:@"Share it"];
        [clash addButtonWithTitle:@"Cancel"];
        NSModalResponse answer = [clash runModal];
        if (answer == NSAlertThirdButtonReturn) return;
        if (answer == NSAlertFirstButtonReturn) {
            for (NppShortcutCommand *other in others) {
                if (other.category == NppShortcutScintilla) {
                    NSMutableArray *kept = [NSMutableArray array];
                    if (other.combo && ![other.combo isEqual:chosen]) [kept addObject:other.combo];
                    for (NppKeyCombo *e in other.extraCombos) if (![e isEqual:chosen]) [kept addObject:e];
                    other.extraCombos = kept.count > 1 ? [kept subarrayWithRange:NSMakeRange(1, kept.count - 1)] : @[];
                    [self.store setCombo:kept.firstObject forCommand:other];
                } else {
                    [self.store setCombo:nil forCommand:other];
                }
            }
        }
    }
    [self.store setCombo:chosen forCommand:command];
    [self reload];
}

- (void)clear:(id)sender {
    NppShortcutCommand *command = [self selected];
    if (!command || command.category == NppShortcutPlugin) { NppBeep(); return; }
    if (command.category == NppShortcutScintilla) command.extraCombos = @[];
    [self.store setCombo:nil forCommand:command];
    [self reload];
}

- (void)deleteCommand:(id)sender {
    NppShortcutCommand *command = [self selected];
    if (!command) { NppBeep(); return; }
    if (command.category == NppShortcutMacro) [self.editor removeSavedMacroNamed:command.key];
    else if (command.category == NppShortcutRunCommand) [self.editor removeSavedCommandNamed:command.key];
    else { NppBeep(); return; }
    [self.store setCombo:nil forCommand:command];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NppSavedCommandsDidChange" object:self];
    [self reload];
}

@end
