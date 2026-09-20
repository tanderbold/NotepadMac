#import "ContextMenuFile.h"
#import "Localization.h"
#import "CommandIDs.h"

/// purgeMenuItemString: without the access key, the shortcut after a tab and
/// the dots of a dialog command; compared without regard to case.
static NSString *Purged(NSString *title) {
    NSString *t = [title ?: @"" stringByReplacingOccurrencesOfString:@"&" withString:@""];
    NSRange tab = [t rangeOfString:@"\t"];
    if (tab.location != NSNotFound) t = [t substringToIndex:tab.location];
    t = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    while ([t hasSuffix:@"…"] || [t hasSuffix:@"."]) t = [t substringToIndex:t.length - 1];
    return t.lowercaseString;
}

@implementation NppContextMenuFile

+ (NSString *)defaultContents {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"contextMenu" ofType:@"xml"];
    return (path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil) ?: @"";
}

/// A command anywhere under a top-level menu, by its English name.
+ (NSMenuItem *)itemNamed:(NSString *)itemName inMenuNamed:(NSString *)menuName of:(NSMenu *)mainMenu {
    NSString *wantMenu = Purged(menuName), *wantItem = Purged(itemName);
    for (NSMenuItem *top in mainMenu.itemArray) {
        if (!top.submenu) continue;
        if (![Purged(NppEnglishMenuTitle(top.submenu)) isEqualToString:wantMenu] && ![Purged(NppEnglishTitle(top)) isEqualToString:wantMenu]) continue;
        NSMutableArray<NSMenuItem *> *queue = [top.submenu.itemArray mutableCopy];
        while (queue.count) {
            NSMenuItem *item = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (item.submenu) { [queue addObjectsFromArray:item.submenu.itemArray]; continue; }
            if (item.action && [Purged(NppEnglishTitle(item)) isEqualToString:wantItem]) return item;
        }
    }
    return nil;
}

+ (NSMenu *)menuFromFile:(NSString *)path root:(NSString *)rootName mainMenu:(NSMenu *)mainMenu
             identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)identifiers {
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
    NSXMLElement *root = [doc.rootElement.name isEqualToString:@"NotepadPlus"] ? [doc.rootElement elementsForName:rootName].firstObject : nil;
    if (!root) return nil;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:rootName];
    NSMutableDictionary<NSString *, NSMenu *> *folders = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [root elementsForName:@"Item"]) {
        NSString *(^attr)(NSString *) = ^NSString *(NSString *name) { return [e attributeForName:name].stringValue; };
        NSString *folder = attr(@"FolderName");
        NSMenu *into = menu;
        if (folder.length) {
            into = folders[folder];
            if (!into) {
                // TranslateID names an entry of the language file; its English text is the FolderName.
                NSString *shown = attr(@"TranslateID").length ? NppL(folder) : folder;
                into = folders[folder] = [[NSMenu alloc] initWithTitle:shown];
                [menu addItemWithTitle:shown action:nil keyEquivalent:@""].submenu = into;
            }
        }
        NSMenuItem *found = nil;
        NSString *identifier = attr(@"id");
        if (identifier.length) {
            if (identifier.intValue == 0) {
                // No two separators in a row, none at the top: what is between may be missing here.
                if (into.numberOfItems && !into.itemArray.lastObject.isSeparatorItem) [into addItem:[NSMenuItem separatorItem]];
                continue;
            }
            found = identifiers[@(identifier.intValue)];
        } else if (attr(@"MenuEntryName").length && attr(@"MenuItemName").length) {
            found = [self itemNamed:attr(@"MenuItemName") inMenuNamed:attr(@"MenuEntryName") of:mainMenu];
            if (!found) {
                // Under the name upstream gives the command, when the port words it differently.
                NSString *wantItem = Purged(attr(@"MenuItemName")), *wantMenu = Purged(attr(@"MenuEntryName"));
                for (int i = 0; i < kNppMenuCommandIDCount && !found; ++i) {
                    NSString *top = [@(kNppMenuCommandIDs[i].path) componentsSeparatedByString:@"/"].firstObject;
                    if ([Purged(@(kNppMenuCommandIDs[i].label)) isEqualToString:wantItem] && [Purged(top) isEqualToString:wantMenu]) {
                        found = identifiers[@(kNppMenuCommandIDs[i].identifier)];
                    }
                }
            }
        } else if (attr(@"PluginEntryName").length && attr(@"PluginCommandItemName").length) {
            // The port's built-in stand-ins sit in the Plugins menu under their plugin's name.
            for (NSMenuItem *top in mainMenu.itemArray) {
                if (![Purged(NppEnglishMenuTitle(top.submenu)) isEqualToString:@"plugins"]) continue;
                for (NSMenuItem *plugin in top.submenu.itemArray) {
                    if (![Purged(NppEnglishTitle(plugin)) isEqualToString:Purged(attr(@"PluginEntryName"))]) continue;
                    for (NSMenuItem *command in plugin.submenu.itemArray) {
                        if ([Purged(NppEnglishTitle(command)) isEqualToString:Purged(attr(@"PluginCommandItemName"))]) found = command;
                    }
                }
            }
        }
        if (!found || !found.action) continue;
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:attr(@"ItemNameAs").length ? attr(@"ItemNameAs") : found.title
                                                      action:found.action keyEquivalent:@""];
        copy.target = found.target;
        copy.tag = found.tag;
        copy.representedObject = found.representedObject;
        [into addItem:copy];
    }
    // A folder nothing was found for, and separators left dangling, go.
    for (NSMenuItem *item in [menu.itemArray copy]) {
        if (item.submenu) {
            while (item.submenu.itemArray.lastObject.isSeparatorItem) [item.submenu removeItem:item.submenu.itemArray.lastObject];
            if (!item.submenu.numberOfItems) [menu removeItem:item];
        }
    }
    for (NSInteger i = menu.numberOfItems - 1; i > 0; --i) {
        if ([menu itemAtIndex:i].isSeparatorItem && [menu itemAtIndex:i - 1].isSeparatorItem) [menu removeItemAtIndex:i];
    }
    while (menu.itemArray.lastObject.isSeparatorItem) [menu removeItem:menu.itemArray.lastObject];
    while (menu.itemArray.firstObject.isSeparatorItem) [menu removeItemAtIndex:0];
    return menu;
}

@end
