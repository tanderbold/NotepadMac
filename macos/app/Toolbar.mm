#import "Toolbar.h"
#import "SettingsCommands.h"

/// One button. The command is the Notepad++ menu id, which is what order.txt
/// names; the label and the selector are what macOS needs to build the item.
typedef struct {
    __unsafe_unretained NSString *command;       // IDM_... , as in order.txt
    __unsafe_unretained NSString *label;
    __unsafe_unretained NSString *selectorName;
    NSInteger tag;                               // for the commands that carry one
} NppToolbarSpec;

/// Every button Notepad++ puts on its toolbar, with the command each one sends
/// here. Which of them appear, and in what order, is decided by order.txt,
/// which is generated from the Notepad++ sources.
static NppToolbarSpec gSpecs[] = {
    {@"IDM_FILE_NEW",                    @"New",          @"newDocument:",           0},
    {@"IDM_FILE_OPEN",                   @"Open",         @"openDocument:",          0},
    {@"IDM_FILE_SAVE",                   @"Save",         @"saveDocument:",          0},
    {@"IDM_FILE_SAVEALL",                @"Save All",     @"saveAll:",               0},
    {@"IDM_FILE_CLOSE",                  @"Close",        @"closeTab:",              0},
    {@"IDM_FILE_CLOSEALL",               @"Close All",    @"closeAll:",              0},
    {@"IDM_FILE_PRINT",                  @"Print",        @"printDocument:",         0},
    {@"IDM_EDIT_CUT",                    @"Cut",          @"cutText:",               0},
    {@"IDM_EDIT_COPY",                   @"Copy",         @"copyText:",              0},
    {@"IDM_EDIT_PASTE",                  @"Paste",        @"pasteText:",             0},
    {@"IDM_EDIT_UNDO",                   @"Undo",         @"undo:",                  0},
    {@"IDM_EDIT_REDO",                   @"Redo",         @"redo:",                  0},
    {@"IDM_SEARCH_FIND",                 @"Find",         @"showFind:",              0},
    {@"IDM_SEARCH_REPLACE",              @"Replace",      @"showReplace:",           0},
    {@"IDM_VIEW_ZOOMIN",                 @"Zoom In",      @"zoomIn:",                0},
    {@"IDM_VIEW_ZOOMOUT",                @"Zoom Out",     @"zoomOut:",               0},
    {@"IDM_VIEW_SYNSCROLLV",             @"Sync Vertical",   @"toggleSyncV:",        0},
    {@"IDM_VIEW_SYNSCROLLH",             @"Sync Horizontal", @"toggleSyncH:",        0},
    {@"IDM_VIEW_WRAP",                   @"Word Wrap",    @"toggleWordWrap:",        0},
    {@"IDM_VIEW_ALL_CHARACTERS",         @"All Characters", @"toggleWhitespace:",    0},
    // Indent guide is one of the Show Symbol entries, which are told apart by
    // their tag rather than by having a selector each.
    {@"IDM_VIEW_INDENT_GUIDE",           @"Indent Guide", @"toggleSymbol:",          4},
    {@"IDM_LANG_USER_DLG",               @"User Language", @"defineUserLanguage:",   0},
    {@"IDM_VIEW_DOC_MAP",                @"Document Map", @"toggleDocumentMap:",     0},
    {@"IDM_VIEW_DOCLIST",                @"Document List", @"toggleDocumentList:",   0},
    {@"IDM_VIEW_FUNC_LIST",              @"Function List", @"toggleFunctionList:",   0},
    {@"IDM_VIEW_FILEBROWSER",            @"Folder as Workspace", @"toggleFileBrowser:", 0},
    {@"IDM_VIEW_MONITORING",             @"Monitoring",   @"toggleMonitoring:",      0},
    {@"IDM_MACRO_STARTRECORDINGMACRO",   @"Start Recording", @"macroStart:",         0},
    {@"IDM_MACRO_STOPRECORDINGMACRO",    @"Stop Recording",  @"macroStop:",          0},
    {@"IDM_MACRO_PLAYBACKRECORDEDMACRO", @"Play",         @"macroPlay:",             0},
    {@"IDM_MACRO_RUNMULTIMACRODLG",      @"Run Multiple", @"macroRunMultiple:",      0},
    {@"IDM_MACRO_SAVECURRENTMACRO",      @"Save Macro",   @"macroSave:",             0},
};

static const NSUInteger kSpecCount = sizeof(gSpecs) / sizeof(gSpecs[0]);

static NSString *IdentifierForCommand(NSString *command) {
    return [@"npp." stringByAppendingString:command];
}

#pragma mark - Item

/// Notepad++ ships a separate image for a button that is switched off, so the
/// item keeps both and picks between them when AppKit validates it.
@interface NppToolbarItem : NSToolbarItem
@property (nonatomic, strong) NSImage *enabledImage;
@property (nonatomic, strong) NSImage *disabledImage;
/// What the images were made from, so they can be made again when the button
/// changes state. Telling an image to draw itself again is not enough: the item
/// keeps what it was given, and giving it the same object back changes nothing.
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, copy) NSString *disabledIconName;
@property (nonatomic, copy) NSString *command;
@end

@implementation NppToolbarItem

- (void)validate {
    [super validate];
    NSImage *wanted = self.isEnabled ? self.enabledImage : self.disabledImage;
    if (wanted && self.image != wanted) self.image = wanted;
}

@end

#pragma mark - Toolbar

@interface NppToolbar ()
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, weak) id actionTarget;
@property (nonatomic, strong) NSToolbar *toolbar;
@property (nonatomic) NSInteger requestedDisplayMode;
@property (nonatomic) NSInteger requestedIconSize;
/// Buttons in the order Notepad++ arranges them; a separator is an empty entry.
@property (nonatomic, strong) NSArray<NSDictionary *> *order;
/// Commands drawn as active. Kept here rather than on the item so the image,
/// which decides its own colours at draw time, can ask about it.
@property (nonatomic, strong) NSMutableSet<NSString *> *activeCommands;
@end

@implementation NppToolbar

/// Reads order.txt: the buttons, in order, with the icon each one uses. Falls
/// back to the built-in list if the file is missing, so a stripped bundle still
/// has a toolbar.
- (NSArray<NSDictionary *> *)loadOrder {
    NSMutableArray *rows = [NSMutableArray array];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"order" ofType:@"txt"
                                                inDirectory:@"toolbar"];
    NSString *text = path ? [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding error:NULL] : nil;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        if ([line isEqualToString:@"-"]) { [rows addObject:@{}]; continue; }
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if (parts.count < 3) continue;
        [rows addObject:@{ @"command": parts[0], @"icon": parts[1], @"disabled": parts[2] }];
    }

    if (!rows.count) {
        for (NSUInteger i = 0; i < kSpecCount; ++i) {
            [rows addObject:@{ @"command": gSpecs[i].command }];
        }
    }
    return rows;
}

- (instancetype)initWithWindow:(NSWindow *)window target:(id)target {
    if (!(self = [super init])) return nil;
    _window = window;
    _actionTarget = target;
    _order = [self loadOrder];
    _activeCommands = [NSMutableSet set];

    _toolbar = [[NSToolbar alloc] initWithIdentifier:@"NppMacToolbar"];
    _toolbar.delegate = self;
    _toolbar.allowsUserCustomization = YES;
    _toolbar.autosavesConfiguration = YES;
    _toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = _toolbar;
    return self;
}

- (BOOL)visible { return self.window.toolbar != nil && self.toolbar.isVisible; }

- (void)setVisible:(BOOL)visible {
    // Keep the toolbar attached either way so its configuration survives.
    self.window.toolbar = self.toolbar;
    self.toolbar.visible = visible;
}

- (NSInteger)displayMode { return self.requestedDisplayMode; }
- (NSInteger)iconSize { return self.requestedIconSize; }
- (NSToolbarDisplayMode)effectiveDisplayMode { return self.toolbar.displayMode; }

- (void)setDisplayMode:(NSInteger)mode {
    self.requestedDisplayMode = mode;
    [self applyLayout];
}

- (void)setIconSize:(NSInteger)size {
    self.requestedIconSize = size;
    [self applyLayout];
}

/// The two settings are not independent on macOS: the compact toolbar style
/// draws icons only and ignores the display mode, so labels force the regular
/// style. Both are therefore applied together rather than one at a time.
- (void)applyLayout {
    BOOL wantsLabels = self.requestedDisplayMode != 0;
    self.window.toolbarStyle = (wantsLabels || self.requestedIconSize == 0)
        ? NSWindowToolbarStyleExpanded
        : NSWindowToolbarStyleUnifiedCompact;
    self.toolbar.displayMode = self.requestedDisplayMode == 0 ? NSToolbarDisplayModeIconOnly
                             : self.requestedDisplayMode == 2 ? NSToolbarDisplayModeLabelOnly
                                                              : NSToolbarDisplayModeIconAndLabel;
}

- (NSArray<NSString *> *)itemIdentifiers {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSToolbarItem *item in self.toolbar.items) [ids addObject:item.itemIdentifier];
    return ids;
}

- (SEL)actionForIdentifier:(NSString *)identifier {
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        if ([IdentifierForCommand(gSpecs[i].command) isEqualToString:identifier]) {
            return NSSelectorFromString(gSpecs[i].selectorName);
        }
    }
    return NULL;
}

#pragma mark - Images

/// Notepad++ has a light and a dark version of every icon. Rather than watching
/// for the appearance to change, the image decides which one to draw each time
/// it is drawn, which is also correct for a window that is not the active one.
- (BOOL)isActiveForCommand:(NSString *)command {
    return [self.activeCommands containsObject:command ?: @""];
}

- (void)reloadIcons {
    for (NSToolbarItem *item in self.toolbar.items) {
        if (![item isKindOfClass:NppToolbarItem.class]) continue;
        NppToolbarItem *button = (NppToolbarItem *)item;
        button.enabledImage = [self imageNamed:button.iconName ?: @"" label:button.label command:button.command];
        button.disabledImage = [self imageNamed:button.disabledIconName ?: @"" label:button.label
                                        command:button.command] ?: button.enabledImage;
        button.image = button.isEnabled ? button.enabledImage : button.disabledImage;
    }
}

- (void)setActive:(BOOL)active forCommand:(NSString *)command {
    if (!command.length) return;
    if (active) [self.activeCommands addObject:command];
    else [self.activeCommands removeObject:command];

    // The image draws itself from this state, so it only has to be told to
    // draw again.
    NSString *identifier = IdentifierForCommand(command);
    for (NSToolbarItem *item in self.toolbar.items) {
        if (![item.itemIdentifier isEqualToString:identifier]) continue;
        if (![item isKindOfClass:NppToolbarItem.class]) continue;
        NppToolbarItem *button = (NppToolbarItem *)item;

        // Built afresh, so the item is handed an image it has not seen before
        // and has to draw it.
        button.enabledImage = [self imageNamed:button.iconName ?: @"" label:button.label
                                       command:button.command];
        button.disabledImage = [self imageNamed:button.disabledIconName ?: @"" label:button.label
                                        command:button.command] ?: button.enabledImage;
        button.image = button.isEnabled ? button.enabledImage : button.disabledImage;
    }
}

/// The image a button is showing, drawn into a bitmap; used by tests to look at
/// what is on screen rather than at the flag behind it.
- (NSBitmapImageRep *)renderedImageForCommand:(NSString *)command {
    NSString *identifier = IdentifierForCommand(command);
    for (NSToolbarItem *item in self.toolbar.items) {
        if (![item.itemIdentifier isEqualToString:identifier]) continue;
        NSImage *image = item.image;
        if (!image) return nil;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)image.size.width
                          pixelsHigh:(NSInteger)image.size.height
                       bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                      colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:context];
        [image drawInRect:NSMakeRect(0, 0, image.size.width, image.size.height)];
        [NSGraphicsContext restoreGraphicsState];
        return rep;
    }
    return nil;
}

/// IconList::changeFluentIconColor: with complete colorization every opaque
/// pixel takes the colour; with partial only those in the icon's second
/// colour (within 3 per channel) do. A colour of nil leaves the icon alone.
static NSImage *Recoloured(NSImage *image, NSColor *colour, BOOL complete, BOOL dark) {
    if (!image || !colour) return image;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:(NSInteger)image.size.width pixelsHigh:(NSInteger)image.size.height bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [image drawInRect:NSMakeRect(0, 0, image.size.width, image.size.height)];
    [NSGraphicsContext restoreGraphicsState];
    NSColor *c = [colour colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    int nr = (int)lround(c.redComponent * 255), ng = (int)lround(c.greenComponent * 255), nb = (int)lround(c.blueComponent * 255);
    // g_cDefaultSecondaryDark / g_cDefaultSecondaryLight.
    int sr = dark ? 0x4C : 0x00, sg = dark ? 0xC2 : 0x78, sb = dark ? 0xFF : 0xD4;
    // The pixels are premultiplied, which is what a bitmap context draws into:
    // compared un-multiplied, written multiplied again. Rows are padded, so
    // each starts at its own offset.
    for (NSInteger row = 0; row < rep.pixelsHigh; ++row) {
        unsigned char *px = rep.bitmapData + row * rep.bytesPerRow;
        for (NSInteger col = 0; col < rep.pixelsWide; ++col, px += 4) {
            int a = px[3];
            if (a == 0) continue;
            int r = px[0] * 255 / a, g = px[1] * 255 / a, b = px[2] * 255 / a;
            if (!complete && !(abs(r - sr) <= 3 && abs(g - sg) <= 3 && abs(b - sb) <= 3)) continue;
            px[0] = (unsigned char)(nr * a / 255); px[1] = (unsigned char)(ng * a / 255); px[2] = (unsigned char)(nb * a / 255);
        }
    }
    NSImage *out = [[NSImage alloc] initWithSize:image.size];
    [out addRepresentation:rep];
    return out;
}

/// Preferences > Toolbar's colour choice, with upstream's values.
static NSColor *ToolbarColour(BOOL dark) {
    NppPreferences *p = [NppPreferences shared];
    switch (p.toolbarIconColour) {
        case 1: return [NSColor colorWithSRGBRed:0xE8/255.0 green:0x11/255.0 blue:0x23/255.0 alpha:1];
        case 2: return [NSColor colorWithSRGBRed:0x00 green:0x8B/255.0 blue:0x00 alpha:1];
        case 3: return [NSColor colorWithSRGBRed:0x00 green:0x78/255.0 blue:0xD4/255.0 alpha:1];
        case 4: return [NSColor colorWithSRGBRed:0xB1/255.0 green:0x46/255.0 blue:0xC2/255.0 alpha:1];
        case 5: return [NSColor colorWithSRGBRed:0x00 green:0xB7/255.0 blue:0xC3/255.0 alpha:1];
        case 6: return [NSColor colorWithSRGBRed:0x49/255.0 green:0x82/255.0 blue:0x05/255.0 alpha:1];
        case 7: return [NSColor colorWithSRGBRed:0xFF/255.0 green:0xB9/255.0 blue:0x00 alpha:1];
        case 8: return [NSColor controlAccentColor];
        case 9: {
            unsigned int rgb = 0;
            if (p.toolbarIconCustomColour.length == 6 &&
                [[NSScanner scannerWithString:p.toolbarIconCustomColour] scanHexInt:&rgb] && rgb) {
                return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                            blue:(rgb & 0xFF) / 255.0 alpha:1];
            }
            break;
        }
        default: break;
    }
    // Default: nothing, unless complete colorization asks for the main colour.
    if (p.toolbarColorizeComplete) {
        return dark ? [NSColor colorWithSRGBRed:0xDE/255.0 green:0xDE/255.0 blue:0xDE/255.0 alpha:1]
                    : [NSColor colorWithSRGBRed:0x21/255.0 green:0x21/255.0 blue:0x21/255.0 alpha:1];
    }
    return nil;
}

- (NSImage *)imageNamed:(NSString *)name label:(NSString *)label command:(NSString *)command {
    NSBundle *bundle = [NSBundle mainBundle];
    // Regular or filled Fluent icons, as the Toolbar page chooses.
    NSString *suffix = [NppPreferences shared].toolbarFilledIcons ? @"-filled" : @"";
    NSString *light = [bundle pathForResource:name ofType:@"png" inDirectory:[@"toolbar/light" stringByAppendingString:suffix]]
                   ?: [bundle pathForResource:name ofType:@"png" inDirectory:@"toolbar/light"];
    NSString *dark  = [bundle pathForResource:name ofType:@"png" inDirectory:[@"toolbar/dark" stringByAppendingString:suffix]]
                   ?: [bundle pathForResource:name ofType:@"png" inDirectory:@"toolbar/dark"];
    if (!light && !dark) return nil;

    BOOL complete = [NppPreferences shared].toolbarColorizeComplete;
    BOOL disabledIcon = [name hasSuffix:@"_dis"];
    NSImage *lightImage = light ? [[NSImage alloc] initWithContentsOfFile:light] : nil;
    NSImage *darkImage  = dark  ? [[NSImage alloc] initWithContentsOfFile:dark]  : nil;
    if (!disabledIcon) {
        lightImage = Recoloured(lightImage, ToolbarColour(NO), complete, NO);
        darkImage = Recoloured(darkImage, ToolbarColour(YES), complete, YES);
    }
    if (!lightImage && !darkImage) return nil;

    // The files hold the largest size Notepad++ ships, so drawing them into a
    // 24-point image keeps them sharp on a Retina display.
    __weak NppToolbar *weakSelf = self;
    NSImage *image = [NSImage imageWithSize:NSMakeSize(24, 24) flipped:NO
                             drawingHandler:^BOOL(NSRect rect) {
        NSAppearance *appearance = NSAppearance.currentDrawingAppearance ?: NSAppearance.currentAppearance;
        NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:
                                  @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        BOOL isDark = [match isEqualToString:NSAppearanceNameDarkAqua];
        NSImage *chosen = (isDark ? darkImage : lightImage) ?: (lightImage ?: darkImage);
        [chosen drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                  fraction:1.0];

        // An active button keeps its shape and takes the colour on top of it,
        // so the icon still reads as itself.
        if ([weakSelf isActiveForCommand:command]) {
            [[NSColor systemRedColor] set];
            NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
        }
        return YES;
    }];
    image.accessibilityDescription = label;
    return image;
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *row in self.order) {
        NSString *command = row[@"command"];
        if (!command) { [ids addObject:NSToolbarSpaceItemIdentifier]; continue; }
        if ([self specIndexForCommand:command] == NSNotFound) continue;
        [ids addObject:IdentifierForCommand(command)];
    }
    return ids;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        [ids addObject:IdentifierForCommand(gSpecs[i].command)];
    }
    [ids addObjectsFromArray:@[NSToolbarSpaceItemIdentifier,
                               NSToolbarFlexibleSpaceItemIdentifier,
                               NSToolbarSeparatorItemIdentifier]];
    return ids;
}

- (NSUInteger)specIndexForCommand:(NSString *)command {
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        if ([gSpecs[i].command isEqualToString:command]) return i;
    }
    return NSNotFound;
}

- (NSDictionary *)orderRowForCommand:(NSString *)command {
    for (NSDictionary *row in self.order) {
        if ([row[@"command"] isEqualToString:command]) return row;
    }
    return nil;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
 willBeInsertedIntoToolbar:(BOOL)flag {
    for (NSUInteger i = 0; i < kSpecCount; ++i) {
        if (![IdentifierForCommand(gSpecs[i].command) isEqualToString:identifier]) continue;

        NppToolbarItem *item = [[NppToolbarItem alloc] initWithItemIdentifier:identifier];
        item.label = gSpecs[i].label;
        item.paletteLabel = gSpecs[i].label;
        item.toolTip = gSpecs[i].label;
        item.tag = gSpecs[i].tag;
        item.target = self.actionTarget;
        item.action = NSSelectorFromString(gSpecs[i].selectorName);

        NSDictionary *row = [self orderRowForCommand:gSpecs[i].command];
        item.command = gSpecs[i].command;
        item.iconName = row[@"icon"];
        item.disabledIconName = row[@"disabled"];
        item.enabledImage = [self imageNamed:item.iconName ?: @"" label:gSpecs[i].label
                                    command:gSpecs[i].command];
        item.disabledImage = [self imageNamed:item.disabledIconName ?: @"" label:gSpecs[i].label
                                      command:gSpecs[i].command] ?: item.enabledImage;
        item.image = item.enabledImage ?: item.disabledImage;
        return item;
    }
    return nil;
}

@end
