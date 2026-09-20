// contextMenu.xml and tabContextMenu.xml, as Notepad++ reads them
// (NppParameters::getContextMenuFromXmlTree): the commands of a popup menu,
// named by menu and item in English or by command id, grouped into submenus
// by FolderName, renamed by ItemNameAs, separated by id="0".
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NppContextMenuFile : NSObject
/// Upstream's default contextMenu.xml, which a new settings folder starts with.
+ (NSString *)defaultContents;
/// The menu a file describes under `root` ("ScintillaContextMenu" or
/// "TabContextMenu"), its items copies of the main menu's; nil when the file
/// is missing, is not XML or has no such root. A command this build does
/// not have is left out, as upstream leaves out what it cannot find.
+ (nullable NSMenu *)menuFromFile:(NSString *)path root:(NSString *)root mainMenu:(NSMenu *)mainMenu
                      identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)identifiers;
@end

NS_ASSUME_NONNULL_END
