#import "InfoWindows.h"
#import "Localization.h"
#import "SettingsCommands.h"

NSString *const NppLicenceText =
    @"This program is free software; you can redistribute it and/or "
    @"modify it under the terms of the GNU General Public License "
    @"as published by the Free Software Foundation; either "
    @"version 3 of the License, or at your option any later version.\n\n"
    @"This program is distributed in the hope that it will be useful, "
    @"but WITHOUT ANY WARRANTY; without even the implied warranty of "
    @"MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the "
    @"GNU General Public License for more details. \n\n"
    @"You should have received a copy of the GNU General Public License "
    @"along with this program. If not, see <https://www.gnu.org/licenses/>.";

/// A label that opens its address, as upstream's URLCtrl does.
static NSButton *LinkButton(NSString *address, NSRect frame, id target) {
    NSButton *b = [[NSButton alloc] initWithFrame:frame];
    b.bordered = NO;
    b.attributedTitle = [[NSAttributedString alloc] initWithString:address attributes:@{
        NSForegroundColorAttributeName: [NSColor linkColor],
        NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
        NSFontAttributeName: [NSFont systemFontOfSize:NSFont.systemFontSize]}];
    b.toolTip = address;
    b.contentTintColor = [NSColor linkColor];   // a borderless button greys its title otherwise
    b.target = target;
    b.action = @selector(openLink:);
    b.identifier = address;
    return b;
}

static NSTextField *Label(NSString *text, NSRect frame, NSFont *font) {
    NSTextField *f = [NSTextField labelWithString:text];
    f.frame = frame;
    f.font = font;
    f.alignment = NSTextAlignmentCenter;
    return f;
}

@interface NppAboutWindow () <NSWindowDelegate>
@property (nonatomic, readwrite) NSPanel *panel;
@property (nonatomic, strong) NSImageView *icon;
@end

NSString *NppProjectAddress(NSString *path) {
    NSString *front = [@"https://github.com/" stringByAppendingString:[NppPreferences shared].updateRepository ?: @""];
    return path.length ? [NSString stringWithFormat:@"%@/%@", front, path] : front;
}

@implementation NppAboutWindow

+ (instancetype)shared {
    static NppAboutWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NppAboutWindow new]; });
    return s;
}

+ (NSString *)bitness {
#if defined(__arm64__)
    return @"(ARM 64-bit)";
#elif defined(__LP64__)
    return @"(64-bit)";
#else
    return @"(32-bit)";
#endif
}

+ (NSString *)versionLine {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return [NSString stringWithFormat:@"Notepad++ v%@   %@",
            info[@"NppUpstreamVersion"] ?: info[@"CFBundleShortVersionString"] ?: @"?", [self bitness]];
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 470)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                              backing:NSBackingStoreBuffered defer:YES];
    p.title = @"About Notepad++";
    p.releasedWhenClosed = NO;
    NSView *v = p.contentView;
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(180, 380, 80, 80)];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    [v addSubview:icon];
    self.icon = icon;
    [v addSubview:Label([NppAboutWindow versionLine], NSMakeRect(20, 350, 400, 22), [NSFont boldSystemFontOfSize:15])];
    [v addSubview:Label([NSString stringWithFormat:@"macOS port %@ (build %@)",
                         info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"],
                        NSMakeRect(20, 328, 400, 18), [NSFont systemFontOfSize:NSFont.smallSystemFontSize])];
    NSTextField *built = Label([NSString stringWithFormat:@"Build time: %@", info[@"NppBuildTime"] ?: @__DATE__ " - " __TIME__],
                               NSMakeRect(20, 306, 400, 18), [NSFont systemFontOfSize:NSFont.smallSystemFontSize]);
    built.textColor = [NSColor secondaryLabelColor];   // upstream greys it out
    [v addSubview:built];
    // Whose this is, and where to go with it: the port's own repository. Notepad++'s author is named
    // as the author of what this is a port of - credit, not a contact.
    [v addSubview:Label(@"An unofficial macOS port. Notepad++ is by Don HO.", NSMakeRect(20, 280, 400, 18), [NSFont systemFontOfSize:NSFont.systemFontSize])];
    [v addSubview:LinkButton(NppProjectAddress(@""), NSMakeRect(20, 256, 400, 20), self)];
    [v addSubview:LinkButton(NppProjectAddress(@"issues"), NSMakeRect(20, 234, 400, 20), self)];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 56, 400, 168)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *licence = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 385, 168)];
    licence.editable = NO;
    licence.string = NppLicenceText;
    licence.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    licence.textContainerInset = NSMakeSize(4, 4);
    licence.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = licence;
    [v addSubview:scroll];

    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:p action:@selector(performClose:)];
    ok.frame = NSMakeRect(170, 14, 100, 30);
    ok.keyEquivalent = @"\r";
    [v addSubview:ok];
    _panel = p;
    return p;
}

- (void)openLink:(NSButton *)sender {
    NSURL *url = [NSURL URLWithString:sender.identifier ?: @""];
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
}

/// Upstream's chameleon, in its dark-mode colours when the window is dark.
- (void)updateIcon {
    NSAppearanceName match = [self.panel.effectiveAppearance bestMatchFromAppearancesWithNames:
                                @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    NSString *name = [match isEqualToString:NSAppearanceNameDarkAqua] ? @"chameleon_dm" : @"chameleon";
    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"ico"];
    self.icon.image = (path ? [[NSImage alloc] initWithContentsOfFile:path] : nil) ?: NSApp.applicationIconImage;
}

- (void)show {
    NSPanel *p = self.panel;
    [self updateIcon];
    if (!p.isVisible) [p center];
    [[NppLocalization shared] localizeWindow:p];
    [p makeKeyAndOrderFront:nil];
}

@end

@interface NppDebugInfoWindow ()
@property (nonatomic, readwrite) NSPanel *panel;
@property (nonatomic, readwrite) NSTextView *textView;
@end

@implementation NppDebugInfoWindow

+ (instancetype)shared {
    static NppDebugInfoWindow *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NppDebugInfoWindow new]; });
    return s;
}

- (NSPanel *)panel {
    if (_panel) return _panel;
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 480)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered defer:YES];
    p.title = @"Debug Info";
    p.releasedWhenClosed = NO;
    p.minSize = NSMakeSize(400, 300);
    NSView *v = p.contentView;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 56, 528, 408)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 528, 408)];
    text.editable = NO;
    text.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    text.autoresizingMask = NSViewWidthSizable;
    // Lines stay whole, as in upstream's edit box; the view scrolls sideways.
    text.textContainer.widthTracksTextView = NO;
    text.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    text.horizontallyResizable = YES;
    scroll.documentView = text;
    [v addSubview:scroll];
    self.textView = text;

    NSButton *copy = [NSButton buttonWithTitle:@"Copy debug info to clipboard" target:self action:@selector(copyToClipboard:)];
    copy.frame = NSMakeRect(16, 14, 240, 30);
    copy.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [v addSubview:copy];
    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:p action:@selector(performClose:)];
    ok.frame = NSMakeRect(444, 14, 100, 30);
    ok.keyEquivalent = @"\r";
    ok.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [v addSubview:ok];
    _panel = p;
    return p;
}

- (void)showText:(NSString *)text {
    NSPanel *p = self.panel;
    self.textView.string = text ?: @"";
    if (!p.isVisible) [p center];
    [[NppLocalization shared] localizeWindow:p];
    [p makeKeyAndOrderFront:nil];
}

- (void)copyToClipboard:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:self.textView.string forType:NSPasteboardTypeString];
}

@end
