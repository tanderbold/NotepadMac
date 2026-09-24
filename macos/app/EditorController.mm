#include <string>
#import "EditorController.h"
#import "Localization.h"
#import "NumberSetCommands.h"
#import "ProjectPanel.h"
#import "CharsetDetection.h"
#import "UserLanguages.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "EditorLook.h"
#import "DockingManager.h"
#import "ViewCommands.h"
#import "TagMatch.h"
#import "AdvancedEditCommands.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "WorkspacePanel.h"
#import "EncodingCommands.h"
#import "ToolsCommands.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "GitCommands.h"
#import "CompareCommands.h"
#import "TypingCommands.h"
#import <objc/runtime.h>
#import "TabBarView.h"
#import "SettingsCommands.h"
#import "PluginHost.h"
#import "SpellCheck.h"
#import "SearchCommands.h"
#import "LanguageDetection.h"
#include "ILexer.h"
#include "Lexilla.h"

/// Marker 1: bookmarks. Fold markers occupy 25-31, so this cannot collide.
#define NPPMAC_BOOKMARK_MARKER 1

NSString *const NppEditorDocumentsDidChangeNotification = @"NppEditorDocumentsDidChange";

@implementation NppDocument
@end

/// Document Map's view zone: the lines the editor shows, drawn over the map,
/// and the place the map is clicked or dragged in, which scrolls the editor.
@interface NppMapZoneView : NSView
@property (nonatomic) NSRect zone;
@property (nonatomic, strong) NSColor *colour;
@property (nonatomic, copy) void (^scrollTo)(CGFloat y);
@property (nonatomic, copy) void (^wheel)(NSEvent *event);
@end

@implementation NppMapZoneView
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return NSPointInRect([self convertPoint:point fromView:self.superview], self.bounds) ? self : nil; }
- (void)drawRect:(NSRect)dirty {
    if (NSIsEmptyRect(self.zone)) return;
    [[self.colour colorWithAlphaComponent:0.25] setFill];
    NSRectFillUsingOperation(self.zone, NSCompositingOperationSourceOver);
    [[self.colour colorWithAlphaComponent:0.7] setStroke];
    [NSBezierPath strokeRect:NSInsetRect(self.zone, 0.5, 0.5)];
}
- (void)mouseDown:(NSEvent *)e { if (self.scrollTo) self.scrollTo([self convertPoint:e.locationInWindow fromView:nil].y); }
- (void)mouseDragged:(NSEvent *)e { [self mouseDown:e]; }
- (void)scrollWheel:(NSEvent *)e { if (self.wheel) self.wheel(e); }
@end

/// ScintillaNotificationProtocol gives no sender, so the secondary pane gets its
/// own delegate object that tags the callback.
@interface NppSecondaryPaneDelegate : NSObject <ScintillaNotificationProtocol>
@property (nonatomic, weak) EditorController *owner;
@end

@implementation NppSecondaryPaneDelegate
- (void)notification:(SCNotification *)n {
    // Only a scroll of this pane is mirrored, and a zoom only when it zooms: every
    // SCN_UPDATEUI mirrored both ways kept the panes echoing each other (a freeze
    // with long lines, and the other pane's zoom undoing a Zoom In).
    if (n->nmhdr.code == SCN_UPDATEUI && (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL)))
        [self.owner mirrorScrollFromSecondary];
    if (n->nmhdr.code == SCN_ZOOM) [self.owner mirrorZoomFromSecondary];
    // The caret or the selection moved in this pane: the status bar says so (it follows the focused view).
    if (n->nmhdr.code == SCN_UPDATEUI && (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT))) [self.owner refreshChrome];
}
@end

/// The status bar's first field: the file's path, which a click copies to the
/// clipboard - the request came up because a path is what one most often
/// wants out of the status bar, and a label cannot be selected.
@interface NppStatusPathField : NSTextField
@property (nonatomic, copy) void (^onClick)(void);
@end
@implementation NppStatusPathField
- (void)mouseDown:(NSEvent *)event { if (self.onClick) self.onClick(); }
- (void)resetCursorRects { if (self.onClick) [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]]; }
@end

@interface EditorController () <ScintillaNotificationProtocol, WorkspacePanelDelegate, NppTabBarDelegate>
@property (nonatomic, strong) WorkspacePanel *workspace;
@property (nonatomic, strong) NSSplitView *split;
@property (nonatomic, strong) NSView *editorArea;
@property (nonatomic, strong) ScintillaView *secondaryView;
@property (nonatomic, strong) NSSplitView *editorSplit;
@property (nonatomic, strong) NSView *secondaryHost;     // the second pane and, above it, Compare's bar
@property (nonatomic, strong) id secondaryDelegate;
@property (nonatomic) BOOL syncV;
@property (nonatomic) BOOL syncH;
@property (nonatomic) BOOL syncZ;
@property (nonatomic, strong) ScintillaView *docMapView;
/// What the dock shows: the map sits in it and may be wider than it, so that
/// a wrapped map breaks its lines where the editor does (DocumentMap::wrapMap).
@property (nonatomic, strong) NSView *docMapHost;
@property (nonatomic, strong) NppMapZoneView *docMapZone;
@property (nonatomic, strong) NSPanel *peekPanel;
/// Distraction Free mode: the tabs and the status bar are put away.
@property (nonatomic) BOOL chromeHidden;
@property (nonatomic, strong) NSMutableArray<NppDocument *> *mru;
@property (nonatomic, strong) ScintillaView *peekView;
/// The document the other pane shows, so that closing it can move the pane off it.
@property (nonatomic, strong) NppDocument *secondaryDocument;
@property (nonatomic, strong) NSMutableArray<NppProjectPanel *> *projects;
@property (nonatomic) NSInteger activeProject;
@property (nonatomic, strong) ScintillaView *sciView;
@property (nonatomic, strong) NSView *container;
@property (nonatomic, strong) NppTabBarView *tabBar;
@property (nonatomic, strong) NSTextField *statusField;
@property (nonatomic, strong) NppStatusPathField *pathField;   // the path, left of the rest
@property (nonatomic, strong) NSTimer *copiedTimer;           // while "Copied" stands in for the path
@property (nonatomic, strong) NSMutableArray<NppDocument *> *docs;
@property (nonatomic) NSInteger currentIndex;
@end

@implementation EditorController

/// Scintilla wants 0xBBGGRR. Note setColorProperty: puts the colour in lParam,
/// which is wrong for messages like SCI_SETCARETLINEBACK that take it in wParam,
/// so every colour goes through message:wParam:lParam: explicitly.
/// Sniffs a BOM, then falls back to UTF-8 and finally Latin-1, which always
/// succeeds -- the same order of preference a plain-text editor should use.
static NSString *DecodeText(NSData *data, NSStringEncoding *outEnc, BOOL *outBOM) {
    const unsigned char *b = (const unsigned char *)data.bytes;
    NSUInteger n = data.length;

    if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
        *outEnc = NSUTF8StringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, n - 3)]
                                     encoding:NSUTF8StringEncoding];
    }
    if (n >= 2 && b[0] == 0xFF && b[1] == 0xFE) {
        *outEnc = NSUTF16LittleEndianStringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, n - 2)]
                                     encoding:NSUTF16LittleEndianStringEncoding];
    }
    if (n >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
        *outEnc = NSUTF16BigEndianStringEncoding; *outBOM = YES;
        return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, n - 2)]
                                     encoding:NSUTF16BigEndianStringEncoding];
    }

    *outBOM = NO;
    // UTF-16 without a mark gives itself away before anything is decoded.
    NSStringEncoding wide = [NppCharsetDetection utf16EncodingWithoutMarkForData:data];
    if (wide) {
        NSString *s = [[NSString alloc] initWithData:data encoding:wide];
        if (s) { *outEnc = wide; return s; }
    }
    // Seven-bit text is "ANSI" to upstream, and opens as UTF-8 only when new
    // documents are UTF-8 and "Apply to opened ANSI files" is on
    // (setLoadedBufferEncodingAndEol, uni7Bit). An empty file goes the same way.
    BOOL sevenBit = YES;
    for (NSUInteger i = 0; i < n && sevenBit; ++i) if (b[i] >= 0x80) sevenBit = NO;
    if (sevenBit) {
        NppPreferences *p = [NppPreferences shared];
        BOOL utf8 = [p.defaultEncoding hasPrefix:@"UTF-8"] && p.openAnsiAsUtf8;
        *outEnc = utf8 ? NSUTF8StringEncoding : NSISOLatin1StringEncoding;
        return [[NSString alloc] initWithData:data encoding:*outEnc];
    }
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s) { *outEnc = NSUTF8StringEncoding; return s; }
    // Not UTF-8: asked of uchardet, as Windows asks, before falling back to
    // Latin-1, which reads anything and understands nothing.
    if ([NppPreferences shared].autoDetectCharacterEncoding) {
        NSStringEncoding guessed = [NppCharsetDetection encodingGuessedForData:data];
        if (guessed) {
            NSString *s = [[NSString alloc] initWithData:data encoding:guessed];
            if (s) { *outEnc = guessed; return s; }
        }
    }
    *outEnc = NSISOLatin1StringEncoding;
    return [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

/// Files at least this big are not decoded into a string: the file is mapped
/// and its bytes go to Scintilla as they are (UTF-8) or converted piecewise.
static unsigned long long gStreamingThreshold = 64ULL * 1024 * 1024;

/// Whether bytes are well-formed UTF-8, checked in place.
static BOOL IsValidUTF8(const unsigned char *b, NSUInteger n) {
    NSUInteger i = 0;
    while (i < n) {
        unsigned char c = b[i];
        if (c < 0x80) { i++; continue; }
        NSUInteger need;
        unsigned int min, cp;
        if ((c & 0xE0) == 0xC0) { need = 1; min = 0x80; cp = c & 0x1F; }
        else if ((c & 0xF0) == 0xE0) { need = 2; min = 0x800; cp = c & 0x0F; }
        else if ((c & 0xF8) == 0xF0) { need = 3; min = 0x10000; cp = c & 0x07; }
        else return NO;
        if (i + need >= n) return NO;
        for (NSUInteger k = 1; k <= need; ++k) {
            unsigned char cc = b[i + k];
            if ((cc & 0xC0) != 0x80) return NO;
            cp = (cp << 6) | (cc & 0x3F);
        }
        if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return NO;
        i += need + 1;
    }
    return YES;
}

/// The UTF-8 a big file is added as, without a string in between: the mapped
/// bytes themselves (less a BOM) when they are UTF-8 or seven-bit, Latin-1
/// converted otherwise. Nil for UTF-16, which takes the ordinary path.
static NSData *DirectBytesForLargeFile(NSData *data, NSStringEncoding *outEnc, BOOL *outBOM) {
    const unsigned char *b = (const unsigned char *)data.bytes;
    NSUInteger n = data.length;
    *outBOM = NO;
    if (n >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) return nil;
    NSUInteger start = 0;
    if (n >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) { start = 3; *outBOM = YES; }
    if (*outBOM || IsValidUTF8(b, n)) {
        BOOL sevenBit = !*outBOM;
        for (NSUInteger i = start; i < n && sevenBit; ++i) if (b[i] >= 0x80) sevenBit = NO;
        NppPreferences *p = [NppPreferences shared];
        *outEnc = (sevenBit && !([p.defaultEncoding hasPrefix:@"UTF-8"] && p.openAnsiAsUtf8))
            ? NSISOLatin1StringEncoding : NSUTF8StringEncoding;
        // No copy: a sub-range of mapped data that starts at 0 is the data itself.
        return start ? [NSData dataWithBytesNoCopy:(void *)(b + start) length:n - start freeWhenDone:NO] : data;
    }
    // Not UTF-8: uchardet is asked, as for a file of any size - of the first
    // megabyte, which is what it needs - and the file is converted piece by
    // piece. A piece may end inside a character of two to four bytes; it is
    // then cut a little shorter, and what was left opens the next.
    if ([NppPreferences shared].autoDetectCharacterEncoding) {
        NSData *sample = n > (1 << 20) ? [NSData dataWithBytesNoCopy:(void *)b length:1 << 20 freeWhenDone:NO] : data;
        NSStringEncoding guessed = [NppCharsetDetection encodingGuessedForData:sample];
        if (guessed && guessed != NSISOLatin1StringEncoding && guessed != NSUTF8StringEncoding) {
            NSMutableData *converted = [NSMutableData dataWithCapacity:n + n / 2];
            const NSUInteger piece = 4 << 20;
            NSUInteger at = 0;
            BOOL ok = YES;
            while (at < n && ok) {
                NSUInteger want = MIN(piece, n - at);
                NSString *decoded = nil;
                for (NSUInteger shorter = 0; shorter <= 4 && shorter < want && !decoded; ++shorter) {
                    if (shorter && at + want == n) break;                  // the end of the file is not a cut
                    @autoreleasepool {
                        decoded = [[NSString alloc] initWithBytes:b + at length:want - shorter encoding:guessed];
                        if (decoded) {
                            [converted appendData:[decoded dataUsingEncoding:NSUTF8StringEncoding]];
                            at += want - shorter;
                        }
                    }
                }
                ok = decoded != nil;
            }
            if (ok) { *outEnc = guessed; return converted; }
        }
    }
    // ANSI, each byte its Latin-1 character.
    *outEnc = NSISOLatin1StringEncoding;
    NSMutableData *out = [NSMutableData dataWithCapacity:n + n / 8];
    unsigned char buffer[8192];
    NSUInteger used = 0;
    for (NSUInteger i = 0; i < n; ++i) {
        unsigned char c = b[i];
        if (c < 0x80) buffer[used++] = c;
        else { buffer[used++] = (unsigned char)(0xC0 | (c >> 6)); buffer[used++] = (unsigned char)(0x80 | (c & 0x3F)); }
        if (used >= sizeof(buffer) - 2) { [out appendBytes:buffer length:used]; used = 0; }
    }
    if (used) [out appendBytes:buffer length:used];
    return out;
}

/// DetectEOL over bytes.
static int DetectEOLBytes(NSData *data) {
    const unsigned char *b = (const unsigned char *)data.bytes;
    NSUInteger n = data.length;
    for (NSUInteger i = 0; i < n; ++i) {
        if (b[i] == '\n') return SC_EOL_LF;
        if (b[i] == '\r') return (i + 1 < n && b[i + 1] == '\n') ? SC_EOL_CRLF : SC_EOL_CR;
    }
    return SC_EOL_LF;
}

/// First line ending wins, matching how Notepad++ reports a file's EOL.
static int DetectEOL(NSString *text) {
    NSRange cr = [text rangeOfString:@"\r"];
    NSRange lf = [text rangeOfString:@"\n"];
    if (cr.location == NSNotFound) return SC_EOL_LF;   // no CR at all, incl. no line ending
    if (lf.location == NSNotFound) return SC_EOL_CR;
    if (lf.location < cr.location) return SC_EOL_LF;   // the first ending is a bare LF
    return (lf.location == cr.location + 1) ? SC_EOL_CRLF : SC_EOL_CR;
}

static NSData *EncodeText(NSString *text, NSStringEncoding enc, BOOL bom) {
    NSMutableData *out = [NSMutableData data];
    if (bom) {
        if (enc == NSUTF8StringEncoding) {
            const unsigned char b[] = {0xEF, 0xBB, 0xBF}; [out appendBytes:b length:3];
        } else if (enc == NSUTF16LittleEndianStringEncoding) {
            const unsigned char b[] = {0xFF, 0xFE}; [out appendBytes:b length:2];
        } else if (enc == NSUTF16BigEndianStringEncoding) {
            const unsigned char b[] = {0xFE, 0xFF}; [out appendBytes:b length:2];
        }
    }
    NSData *body = [text dataUsingEncoding:enc allowLossyConversion:YES];
    if (!body) return nil;
    [out appendData:body];
    return out;
}

static long SciColor(NSColor *c) {
    NSColor *d = [c colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    long r = (long)(d.redComponent * 255);
    long g = (long)(d.greenComponent * 255);
    long b = (long)(d.blueComponent * 255);
    return (b << 16) + (g << 8) + r;
}

- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self = [super init])) return nil;
    _docs = [NSMutableArray array];
    _currentIndex = -1;

    _container = [[NSView alloc] initWithFrame:frame];
    _container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat tabH = 28, statusH = 22;

    NSRect upper = NSMakeRect(0, statusH, NSWidth(frame), NSHeight(frame) - statusH);

    _editorArea = [[NSView alloc] initWithFrame:upper];
    _editorArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _tabBar = [[NppTabBarView alloc] initWithFrame:
               NSMakeRect(0, NSHeight(upper) - tabH, NSWidth(upper), tabH)];
    _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBar.tabDelegate = self;
    [_editorArea addSubview:_tabBar];

    NSRect editorRect = NSMakeRect(0, 0, NSWidth(upper), NSHeight(upper) - tabH);
    _sciView = [[ScintillaView alloc] initWithFrame:editorRect];
    _sciView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _sciView.delegate = self;

    _secondaryView = [[ScintillaView alloc] initWithFrame:editorRect];
    _secondaryDelegate = [[NppSecondaryPaneDelegate alloc] init];
    ((NppSecondaryPaneDelegate *)_secondaryDelegate).owner = self;
    _secondaryView.delegate = (id<ScintillaNotificationProtocol>)_secondaryDelegate;
    // The pane sits in a host of its own, so a bar can stand above it (Compare's).
    _secondaryHost = [[NSView alloc] initWithFrame:editorRect];
    _secondaryHost.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _secondaryView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _secondaryView.frame = _secondaryHost.bounds;
    [_secondaryHost addSubview:_secondaryView];

    _editorSplit = [[NSSplitView alloc] initWithFrame:editorRect];
    _editorSplit.vertical = YES;                   // side by side: NppGUI::_splitterPos = POS_VERTICAL
    _editorSplit.dividerStyle = NSSplitViewDividerStyleThin;
    _editorSplit.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_editorSplit addSubview:_sciView];
    [_editorArea addSubview:_editorSplit];

    _workspace = [[WorkspacePanel alloc] initWithFrame:NSMakeRect(0, 0, 220, NSHeight(upper))];
    _workspace.delegate = self;

    _projects = [NSMutableArray array];
    for (int i = 0; i < 3; ++i) {
        NppProjectPanel *p = [[NppProjectPanel alloc] initWithNumber:i + 1
                                                               frame:NSMakeRect(0, 0, 240, NSHeight(upper))];
        p.delegate = self;
        [_projects addObject:p];
    }

    _split = [[NSSplitView alloc] initWithFrame:upper];
    _split.vertical = YES;
    _split.dividerStyle = NSSplitViewDividerStyleThin;
    _split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_split addSubview:_editorArea];
    [_container addSubview:_split];
    // The panels dock around the editor, as upstream's DockingManager has them.
    NppDockingManager *dock = [NppDockingManager shared];
    [dock attachToSplit:_split center:_editorArea];
    [dock registerPanel:@"workspace" title:@"Folder as Workspace" view:_workspace.view defaultPlace:NppDockLeft];
    for (NSUInteger i = 0; i < _projects.count; ++i) {
        [dock registerPanel:[NSString stringWithFormat:@"project%lu", (unsigned long)i + 1]
                      title:[NSString stringWithFormat:@"Project Panel %lu", (unsigned long)i + 1]
                       view:_projects[i].view defaultPlace:NppDockLeft];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dockPanelVisibilityChanged:)
                                                 name:NppDockPanelVisibilityDidChangeNotification object:nil];

    _pathField = [[NppStatusPathField alloc] initWithFrame:NSMakeRect(6, 2, 200, statusH - 4)];
    _pathField.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    _pathField.bezeled = NO;
    _pathField.editable = NO;
    _pathField.selectable = NO;
    _pathField.drawsBackground = NO;
    _pathField.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathField.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _pathField.textColor = [NSColor secondaryLabelColor];
    __weak EditorController *weakSelf = self;
    _pathField.onClick = ^{ [weakSelf copyPathFromStatusBar]; };
    [_container addSubview:_pathField];

    _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(220, 2, NSWidth(frame) - 226, statusH - 4)];
    _statusField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    _statusField.bezeled = NO;
    _statusField.editable = NO;
    _statusField.selectable = NO;
    _statusField.drawsBackground = NO;
    _statusField.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _statusField.textColor = [NSColor secondaryLabelColor];
    [_container addSubview:_statusField];
    // The fields share the bar again whenever the window changes size (StatusBar::adjustParts on WM_SIZE).
    _container.postsFrameChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSViewFrameDidChangeNotification object:_container
                                                       queue:nil usingBlock:^(NSNotification *note) { [weakSelf layoutStatusFields]; }];

    [self configureEditorChrome];
    [self newDocument];
    [self installContextClickMonitor];
    return self;
}

- (ScintillaView *)sci { return self.sciView; }
- (NSView *)view { return self.container; }
- (NSArray<NppDocument *> *)documents { return self.docs; }

- (NppDocument *)currentDocument {
    if (self.currentIndex < 0 || self.currentIndex >= (NSInteger)self.docs.count) return nil;
    return self.docs[self.currentIndex];
}

#pragma mark - Editor chrome

- (void)configureEditorChrome {
    ScintillaView *sci = self.sciView;
    [sci message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
    [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:52];
    // Margin 1: bookmarks. Margin 2: folding.
    [sci message:SCI_SETMARGINTYPEN wParam:1 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:14];
    // Compare's whole-line markers (2-5, SC_MARK_BACKGROUND) are in this mask too: Scintilla
    // draws a background marker in the text only when some margin's mask has its bit
    // (ViewStyle::CalculateMarginWidthAndMask), and a background marker draws nothing in a margin.
    [sci message:SCI_SETMARGINMASKN wParam:1 lParam:(1 << NPPMAC_BOOKMARK_MARKER) | (1 << 0) | (0xF << 2)];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:1 lParam:1];
    [sci message:SCI_MARKERDEFINE wParam:NPPMAC_BOOKMARK_MARKER lParam:SC_MARK_BOOKMARK];

    [sci message:SCI_SETMARGINTYPEN wParam:2 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN wParam:2 lParam:(long)SC_MASK_FOLDERS];
    [sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:16];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
    [sci message:SCI_SETAUTOMATICFOLD wParam:(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE) lParam:0];
    for (int mk = SC_MARKNUM_FOLDEREND; mk <= SC_MARKNUM_FOLDEROPEN; ++mk) {
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)mk lParam:SC_MARK_BOXPLUS];
    }
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND lParam:SC_MARK_BOXPLUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
    [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
    [self applyDocumentSettings];
    [sci message:SCI_SETSCROLLWIDTHTRACKING wParam:1 lParam:0];
    [sci message:SCI_SETMULTIPLESELECTION wParam:1 lParam:0];
    [sci message:SCI_SETADDITIONALSELECTIONTYPING wParam:1 lParam:0];
}

/// Scintilla resets these when the document pointer changes, so they are
/// re-applied on every switch rather than only at startup.
/// The current line left alone, given the theme's background, or framed
/// (ScintillaEditView::setCurrentLineHiLiting). With "None" no colour is set:
/// in Scintilla 5 setting the caret-line colour turns the line on again.
- (void)applyCurrentLineLookToView:(ScintillaView *)sci {
    NppPreferences *prefs = [NppPreferences shared];
    if (prefs.currentLineHighlightMode == 0) {
        [sci message:SCI_SETCARETLINEVISIBLE wParam:0 lParam:0];
        return;
    }
    NppStyle *caretLine = [StyleCatalog sharedCatalog].globalStyles[@"Current line background colour"];
    if (caretLine.background) [sci message:SCI_SETCARETLINEBACK wParam:SciColor(caretLine.background) lParam:0];
    [sci message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
    [sci message:SCI_SETCARETLINEFRAME
           wParam:prefs.currentLineHighlightMode == 2
                  ? (uptr_t)MIN((NSInteger)6, MAX((NSInteger)1, prefs.currentLineFrameWidth)) : 0
           lParam:0];
}

- (void)applyDocumentSettings {
    ScintillaView *sci = self.sciView;
    // From the preferences, not literals: these live in the Scintilla
    // document, so whatever was applied to the last one is gone on a switch.
    NppPreferences *prefs = [NppPreferences shared];
    // The language's own indent settings when it has some, as upstream's
    // per-language Indent Settings.
    NSString *lang = self.currentDocument.language.name;
    NSInteger width = [prefs tabWidthForLanguage:lang];
    [sci message:SCI_SETTABWIDTH wParam:(uptr_t)width lParam:0];
    [sci message:SCI_SETINDENT wParam:(uptr_t)width lParam:0];
    [sci message:SCI_SETUSETABS wParam:(uptr_t)([prefs useSpacesForLanguage:lang] ? 0 : 1) lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES
           wParam:(uptr_t)(prefs.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
    [sci message:SCI_SETBACKSPACEUNINDENTS wParam:prefs.backspaceUnindents ? 1 : 0 lParam:0];
    [sci message:SCI_SETTABINDENTS wParam:1 lParam:0];
    // Change History powers Search > Change History; it is per document.
    // Change History must have a margin of its own. A marker that belongs to no
    // margin is drawn by Scintilla as a whole-line background instead, which
    // paints every saved line in the "saved" colour.
    long historyMask = (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) |
                       (1 << SC_MARKNUM_HISTORY_SAVED) |
                       (1 << SC_MARKNUM_HISTORY_MODIFIED) |
                       (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED);
    [sci message:SCI_SETMARGINS wParam:6 lParam:0];   // 0-3 as upstream; 4 the Git margin (GitCommands.mm), 5 Compare's revert margin
    [sci message:SCI_SETMARGINTYPEN wParam:3 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN wParam:3 lParam:historyMask];
    // Change History's modes (margin, text) are set by applyLook.
    [sci message:SCI_SETMARGINWIDTHN wParam:3 lParam:prefs.changeHistoryMargin ? 6 : 0];

    [self applyEditorPreferences];
}

/// The editor settings Notepad++ keeps outside a document: the vertical edge,
/// the caret, and how far the view and the caret may go past the text.
- (void)applyEditorPreferences {
    ScintillaView *sci = self.sciView;
    NppPreferences *prefs = [NppPreferences shared];
    [self applyStatusBarVisibility];
    [self applyLook];

    // A vertical edge can be a line or a change of background, and Notepad++
    // takes a list of columns rather than one.
    NSMutableArray<NSNumber *> *columns = [NSMutableArray array];
    for (NSString *piece in [(prefs.edgeColumns ?: @"") componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@" ,;\t"]]) {
        NSInteger column = piece.integerValue;
        if (column > 0) [columns addObject:@(column)];
    }

    [sci message:SCI_MULTIEDGECLEARALL wParam:0 lParam:0];
    if (prefs.edgeMode == 0 || !columns.count) {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_NONE lParam:0];
    } else if (prefs.edgeMode == 2) {
        // Background mode marks everything past the column and takes one column.
        [sci message:SCI_SETEDGEMODE wParam:EDGE_BACKGROUND lParam:0];
        [sci message:SCI_SETEDGECOLUMN wParam:(uptr_t)columns.firstObject.integerValue lParam:0];
    } else if (columns.count == 1) {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_LINE lParam:0];
        [sci message:SCI_SETEDGECOLUMN wParam:(uptr_t)columns.firstObject.integerValue lParam:0];
    } else {
        [sci message:SCI_SETEDGEMODE wParam:EDGE_MULTILINE lParam:0];
        long colour = [sci message:SCI_GETEDGECOLOUR];
        for (NSNumber *column in columns) {
            [sci message:SCI_MULTIEDGEADDLINE wParam:(uptr_t)column.integerValue lParam:colour];
        }
    }

    [sci message:SCI_SETCARETWIDTH wParam:(uptr_t)MAX((NSInteger)0, prefs.caretWidth) lParam:0];
    [sci message:SCI_SETCARETPERIOD wParam:(uptr_t)MAX((NSInteger)0, prefs.caretBlinkRate) lParam:0];

    // SCI_SETENDATLASTLINE is the other way round: setting it stops the view
    // scrolling past the end.
    [sci message:SCI_SETENDATLASTLINE wParam:prefs.scrollBeyondLastLine ? 0 : 1 lParam:0];
    [sci message:SCI_SETVIRTUALSPACEOPTIONS
           wParam:prefs.virtualSpace ? (SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE)
                                     : SCVS_RECTANGULARSELECTION
           lParam:0];

    [self applyCurrentLineLookToView:sci];

    // Margins the user can turn off. The line number margin has its own
    // setting elsewhere; these two are the bookmark and fold margins.
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:prefs.bookmarkMarginShow ? 14 : 0];
    // The fold margin's width goes with its style, in applyFoldMarkersTo:.
    [self applyFoldMarkersTo:sci];

    // How a wrapped line continues: plain, aligned with the line above, or a
    // level further in.
    long wrapIndent = prefs.lineWrapMethod == 2 ? SC_WRAPINDENT_INDENT
                    : prefs.lineWrapMethod == 0 ? SC_WRAPINDENT_FIXED
                                                : SC_WRAPINDENT_SAME;
    [sci message:SCI_SETWRAPINDENTMODE wParam:(uptr_t)wrapIndent lParam:0];

    // In Distraction Free mode the text takes the middle of the view: each
    // side gets the width divided by the chosen number of parts.
    long leftPad = MIN((NSInteger)9, MAX((NSInteger)0, prefs.paddingLeft));
    long rightPad = MIN((NSInteger)9, MAX((NSInteger)0, prefs.paddingRight));
    if (self.chromeHidden) {
        NSInteger parts = prefs.distractionFreeDivPart > 2 ? prefs.distractionFreeDivPart : 4;
        leftPad = rightPad = (long)(NSWidth(sci.bounds) / parts);
    }
    [sci message:SCI_SETMARGINLEFT wParam:0 lParam:leftPad];
    [sci message:SCI_SETMARGINRIGHT wParam:0 lParam:rightPad];

    [sci message:SCI_SETMOUSESELECTIONRECTANGULARSWITCH wParam:1 lParam:0];
    [sci message:SCI_SETDRAGDROPENABLED wParam:prefs.selectedTextDragDrop ? 1 : 0 lParam:0];
}

#pragma mark - Typing mode

- (BOOL)overtype {
    return [self.sciView message:SCI_GETOVERTYPE] != 0;
}

- (void)setOvertype:(BOOL)on {
    [self.sciView message:SCI_SETOVERTYPE wParam:on ? 1 : 0 lParam:0];
    [self refreshChrome];
}

- (void)toggleOvertype {
    [self setOvertype:![self overtype]];
}

#pragma mark - Documents

/// A path with its symlinks and "."/".." resolved, as realpath(3) gives it (NSString's own
/// resolving turns /private/var into /var); the path as given when it no longer exists.
NSString *NppCanonicalPath(NSString *path) {
    if (!path.length) return path;
    char resolved[PATH_MAX];
    if (realpath(path.fileSystemRepresentation, resolved)) return [NSString stringWithUTF8String:resolved] ?: path;
    return path.stringByStandardizingPath;
}

- (void)newDocument {
    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = [self createScintillaDocument:SC_DOCUMENTOPTION_DEFAULT];
    doc.displayName = @"new 1";
    doc.language = [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];
    doc.encoding = NSUTF8StringEncoding;
    doc.hasBOM = NO;
    doc.eolMode = SC_EOL_LF;      // macOS default; Notepad++ uses CRLF on Windows

    // FileManager::nextUntitledNewNumber: the lowest number no untitled tab has, so closing
    // "new 2" of three makes the next one "new 2" again, never a second "new 3".
    NSMutableIndexSet *used = [NSMutableIndexSet indexSet];
    for (NppDocument *d in self.docs) {
        if (d.path || ![d.displayName hasPrefix:@"new "]) continue;
        NSInteger k = [d.displayName substringFromIndex:4].integerValue;
        if (k > 0 && [[NSString stringWithFormat:@"new %ld", (long)k] isEqualToString:d.displayName]) [used addIndex:(NSUInteger)k];
    }
    NSInteger n = 1;
    while ([used containsIndex:(NSUInteger)n]) n++;
    doc.displayName = [NSString stringWithFormat:@"new %ld", (long)n];

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];
    [self applyNewDocumentDefaults];
}

#pragma mark - The text, by length

- (NSString *)documentText {
    long length = [self.sciView message:SCI_GETLENGTH wParam:0 lParam:0];
    if (length <= 0) return @"";
    std::string buffer((size_t)length + 1, '\0');
    [self.sciView message:SCI_GETTEXT wParam:(uptr_t)(length + 1) lParam:(sptr_t)&buffer[0]];
    NSString *text = [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)length
                                            encoding:NSUTF8StringEncoding];
    return text ?: ([self.sciView string] ?: @"");
}

+ (NSString *)textOfFileAtPath:(NSString *)path encoding:(NSStringEncoding *)encoding hasBOM:(BOOL *)hasBOM {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    NSStringEncoding used = NSUTF8StringEncoding;
    BOOL bom = NO;
    // A NUL in what is not UTF-16 means a binary file, which a search passes over.
    const unsigned char *b = (const unsigned char *)data.bytes;
    BOOL wide = data.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF));
    if (!wide && ![NppCharsetDetection utf16EncodingWithoutMarkForData:data] &&
        memchr(b, 0, MIN(data.length, (NSUInteger)8192))) return nil;
    NSString *text = DecodeText(data, &used, &bom);
    if (encoding) *encoding = used;
    if (hasBOM) *hasBOM = bom;
    return text;
}

+ (NSData *)dataForText:(NSString *)text encoding:(NSStringEncoding)encoding hasBOM:(BOOL)hasBOM {
    return EncodeText(text, encoding, hasBOM);
}

+ (void)setStreamingThreshold:(unsigned long long)bytes { gStreamingThreshold = bytes ?: 64ULL * 1024 * 1024; }

/// Adds UTF-8 bytes in pieces, with room made for all of them first.
- (void)setDocumentBytes:(NSData *)utf8 {
    ScintillaView *sci = self.sciView;
    BOOL readOnly = [sci message:SCI_GETREADONLY wParam:0 lParam:0] != 0;
    if (readOnly) [sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [sci message:SCI_CLEARALL wParam:0 lParam:0];
    [sci message:SCI_ALLOCATE wParam:(uptr_t)utf8.length lParam:0];
    const unsigned char *bytes = (const unsigned char *)utf8.bytes;
    const NSUInteger chunk = 16 * 1024 * 1024;
    for (NSUInteger at = 0; at < utf8.length; at += chunk) {
        NSUInteger len = MIN(chunk, utf8.length - at);
        [sci message:SCI_APPENDTEXT wParam:(uptr_t)len lParam:(sptr_t)(bytes + at)];
    }
    if (readOnly) [sci message:SCI_SETREADONLY wParam:1 lParam:0];
}

/// The file's own text is where change history starts, not a change: with
/// history on while it was loaded, every line was marked as a saved change
/// (the margin striped a file just opened, Go to Next Change stopped on every
/// line). Notepad++ loads a buffer before history is turned on for it; here
/// the history is turned off and on again once the text is in and the undo
/// buffer is empty, which is when Scintilla lets the mode change.
static void RestartChangeHistory(ScintillaView *sci) {
    long mode = [sci message:SCI_GETCHANGEHISTORY];
    if (!mode) return;
    [sci message:SCI_SETCHANGEHISTORY wParam:SC_CHANGE_HISTORY_DISABLED];
    [sci message:SCI_SETCHANGEHISTORY wParam:(uptr_t)mode];
}

- (void)setDocumentText:(NSString *)text {
    NSData *utf8 = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    // A read-only document takes no text; the flag is lifted for the
    // replacement (a reload, a reread in another code page) and put back.
    BOOL readOnly = [self.sciView message:SCI_GETREADONLY wParam:0 lParam:0] != 0;
    if (readOnly) [self.sciView message:SCI_SETREADONLY wParam:0 lParam:0];
    [self.sciView message:SCI_CLEARALL wParam:0 lParam:0];
    [self.sciView message:SCI_ADDTEXT wParam:(uptr_t)utf8.length lParam:(sptr_t)utf8.bytes];
    if (readOnly) [self.sciView message:SCI_SETREADONLY wParam:1 lParam:0];
}

- (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error {
    // Files with the extensions set in MISC. are a session or a workspace.
    NppPreferences *extPrefs = [NppPreferences shared];
    NSString *ext = path.pathExtension;
    NSString *(^bare)(NSString *) = ^NSString *(NSString *e) { return [e hasPrefix:@"."] ? [e substringFromIndex:1] : e; };
    if (ext.length && [ext caseInsensitiveCompare:bare(extPrefs.sessionFileExtension ?: @"")] == NSOrderedSame) {
        return [self loadSessionFrom:path error:error];
    }
    if (ext.length && [ext caseInsensitiveCompare:bare(extPrefs.workspaceFileExtension ?: @"")] == NSOrderedSame) {
        [self showProjectPanel:1];
        return [[self projectPanel:1] openWorkspace:path];
    }
    // Already open? Just focus it - under whatever spelling it was opened (/var and /private/var,
    // a "..", a symlinked folder): Notepad++ compares the full long path (FileManager::getBufferFromName).
    NSString *canonical = NppCanonicalPath(path);
    for (NSUInteger i = 0; i < self.docs.count; ++i) {
        NSString *other = self.docs[i].path;
        if (other && ([other isEqualToString:path] || [NppCanonicalPath(other) isEqualToString:canonical])) {
            [self selectDocumentAtIndex:(NSInteger)i];
            return YES;
        }
    }

    // Decided on the size on disk, before anything is read: a file too big to
    // hold is refused, and a large one is opened without styling from the
    // start rather than styled and then unstyled.
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]
                               fileSize];
    NppPreferences *prefs = [NppPreferences shared];
    BOOL huge = size >= 2ULL * 1024 * 1024 * 1024;
    // As upstream asks before a file of 2 GB or more, unless told not to.
    if (huge && !prefs.suppressHugeFileWarning && !getenv("NPPMAC_TEST")) {
        NSAlert *ask = [[NSAlert alloc] init];
        ask.messageText = @"Opening huge file warning";
        ask.informativeText = @"Opening a huge file of 2GB+ could take several minutes.\nDo you want to open it?";
        [ask addButtonWithTitle:@"Yes"];
        [ask addButtonWithTitle:@"No"];
        if ([ask runModal] != NSAlertFirstButtonReturn) {
            // The user said No: nothing went wrong, so no error for the caller to show
            // (AppKit's alert for NSUserCancelledError reads "The operation was cancelled.").
            if (error) *error = nil;
            return NO;
        }
    }
    BOOL large = huge || (prefs.largeFileRestrictionEnabled &&
                 size > (unsigned long long)prefs.largeFileThresholdMB * 1024 * 1024);

    // A big file is mapped rather than read, and not made into a string.
    BOOL stream = size >= gStreamingThreshold;
    NSData *data = [NSData dataWithContentsOfFile:path options:stream ? NSDataReadingMappedAlways : 0 error:error];
    if (!data) return NO;

    NSStringEncoding used = NSUTF8StringEncoding;
    BOOL bom = NO;
    NSData *direct = stream ? DirectBytesForLargeFile(data, &used, &bom) : nil;
    if (!direct && huge) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadTooLargeError
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"%@ is UTF-16 and too big to open (2 GB or more).",
                                                 path.lastPathComponent]}];
        return NO;
    }
    NSString *text = direct ? @"" : DecodeText(data, &used, &bom);
    if (!text) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSFileReadUnknownStringEncodingError
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Cannot decode %@", path.lastPathComponent]}];
        return NO;
    }

    NppDocument *doc = [[NppDocument alloc] init];
    doc.docPointer = [self createScintillaDocument:large ? (SC_DOCUMENTOPTION_STYLES_NONE | SC_DOCUMENTOPTION_TEXT_LARGE)
                                                         : SC_DOCUMENTOPTION_DEFAULT];
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];
    doc.encoding = used;
    doc.hasBOM = bom;
    doc.codepage = 0;
    doc.eolMode = direct ? DetectEOLBytes(direct) : DetectEOL(text);
    doc.fileModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL]
                                fileModificationDate];

    // loadBufferIntoView: the file takes the place of a lone clean untitled tab.
    NppDocument *lone = self.docs.count == 1 ? self.docs.firstObject : nil;
    if (lone && (lone.path || lone.modified || lone.isSearchResults || lone.pinned)) lone = nil;

    [self.docs addObject:doc];
    [self selectDocumentAtIndex:(NSInteger)self.docs.count - 1];
    if (lone) [self closeDocumentAtIndex:(NSInteger)[self.docs indexOfObject:lone] discardChanges:YES];

    if (direct) [self setDocumentBytes:direct];
    else [self setDocumentText:text];
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self applyPerformanceRestrictions];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_GOTOPOS wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    RestartChangeHistory(self.sciView);
    doc.modified = NO;

    [self applyLanguage];
    // A file that cannot be written is not edited until the user says so.
    if (![[NSFileManager defaultManager] isWritableFileAtPath:path]) {
        [self.sciView message:SCI_SETREADONLY wParam:1 lParam:0];
    }
    [self refreshChrome];
    // The recent list holds what was closed, not what is open, as on Windows.
    [self forgetRecentFile:path];
    [self rememberOpenDirectory:path];

    // A name with no extension says nothing, so the contents are asked instead.
    [self detectLanguageOfCurrentDocumentOffering:self.languageChoiceHandler];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppDocumentOpenedNotification object:self];
    return YES;
}

- (void)selectDocumentAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{ [self catchUpMonitoredDocument]; });
    if (!self.mru) self.mru = [NSMutableArray array];
    [self.mru removeObjectIdenticalTo:self.docs[(NSUInteger)index]];
    [self.mru insertObject:self.docs[(NSUInteger)index] atIndex:0];
    if (self.currentIndex >= 0 && self.currentIndex != index &&
        self.currentIndex < (NSInteger)self.docs.count) {
        [self rememberPreviousTab:self.docs[self.currentIndex]];   // backs Window > Recent Window
    }
    // Where the caret and the view are belongs to the document, as on
    // Windows: kept when it leaves the front, put back when it returns.
    if (self.currentIndex >= 0 && self.currentIndex != index &&
        self.currentIndex < (NSInteger)self.docs.count) {
        NppDocument *leaving = self.docs[self.currentIndex];
        leaving.caretPosition = [self.sciView message:SCI_GETCURRENTPOS];
        leaving.anchorPosition = [self.sciView message:SCI_GETANCHOR];
        leaving.firstVisibleLine = [self.sciView message:SCI_GETFIRSTVISIBLELINE];
        NSMutableArray *marks = [NSMutableArray array];
        long line = -1;
        while ((line = [self.sciView message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << 1)]) >= 0) {
            [marks addObject:@(line)];
        }
        leaving.bookmarkedLines = marks;
        leaving.foldedLines = [self currentFoldedLines];
        }
    BOOL switching = self.currentIndex != index;
    self.currentIndex = index;
    NppDocument *doc = self.docs[index];
    // Setting the pointer again, even to the same document, resets the
    // view's folds; the tab already in front keeps its own.
    if ((void *)[self.sciView message:SCI_GETDOCPOINTER] != doc.docPointer) {
        [self.sciView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    }
    if (switching) {
        [self.sciView message:SCI_SETSEL wParam:(uptr_t)doc.anchorPosition lParam:doc.caretPosition];
        [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)doc.firstVisibleLine lParam:0];
    }
    [self forgetAutoCloser];
    // The map mirrors whatever is in front, not whatever was when it opened.
    if ([self documentMapVisible]) {
        [self.docMapView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
        [self mirrorStylesToDocumentMap];
        [self updateDocumentMap];
    }
    [self applyDocumentSettings];
    [self applyLanguage];
    // Folds come back once the lexer has worked out the fold levels.
    if (switching && doc.foldedLines.count) [self foldLines:doc.foldedLines];
    [self refreshChrome];
    // The content view, not the ScintillaView around it: makeFirstResponder:
    // does not ask acceptsFirstResponder, and the wrapper would hold the
    // focus without taking a key.
    [self.window makeFirstResponder:self.sciView.content];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppBufferActivatedNotification object:self];
}

/// Documents are created in a scratch view that shows nothing, as upstream
/// creates them in its _pscratchTilla: SCI_CREATEDOCUMENT resets the folds of
/// the view it is sent to, which would unfold the document in front.
- (void *)createScintillaDocument:(long)options {
    static ScintillaView *scratch;
    if (!scratch) scratch = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    return (void *)[scratch message:SCI_CREATEDOCUMENT wParam:0 lParam:options];
}

- (NSArray<NSNumber *> *)currentFoldedLines {
    NSMutableArray *lines = [NSMutableArray array];
    long line = -1;
    while ((line = [self.sciView message:SCI_CONTRACTEDFOLDNEXT wParam:(uptr_t)(line + 1)]) >= 0) {
        [lines addObject:@(line)];
    }
    return lines;
}

- (void)foldLines:(NSArray<NSNumber *> *)lines {
    ScintillaView *sci = self.sciView;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    for (NSNumber *line in lines) {
        if (![line isKindOfClass:[NSNumber class]]) continue;
        if ([sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line.longValue] & SC_FOLDLEVELHEADERFLAG) {
            [sci message:SCI_FOLDLINE wParam:(uptr_t)line.longValue lParam:SC_FOLDACTION_CONTRACT];
        }
    }
}

#pragma mark - NppTabBarDelegate

- (void)tabBar:(NppTabBarView *)bar didSelectIndex:(NSInteger)index {
    [self selectDocumentAtIndex:index];
}

#pragma mark - Document Peeker

/// TCN_MOUSEHOVERING: with "Peek on tab" a small window shows the hovered
/// document; with "Peek on document map" the map shows it for as long as
/// the pointer stays. Hovering the tab in front, or leaving, puts things back.
- (void)tabBar:(NppTabBarView *)bar hoveredIndex:(NSInteger)index {
    NppPreferences *p = [NppPreferences shared];
    NppDocument *doc = (index >= 0 && index < (NSInteger)self.documents.count) ? self.documents[(NSUInteger)index] : nil;
    BOOL other = doc && doc != self.currentDocument;
    if (p.docPeekOnTab) {
        if (other) [self showPeekerForDocument:doc underRect:[bar convertRect:[bar frameOfTabAtIndex:index] toView:nil]];
        else [self hideDocumentPeeker];
    }
    if (p.docPeekOnMap && [self documentMapVisible]) {
        NppDocument *shown = other ? doc : self.currentDocument;
        [self.docMapView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)shown.docPointer];
        if (other) [self.docMapView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)MAX(0, doc.firstVisibleLine) lParam:0];
        else [self updateDocumentMap];
        self.docMapZone.hidden = other;
    }
}

- (void)showPeekerForDocument:(NppDocument *)doc underRect:(NSRect)rectInWindow {
    if (!self.peekPanel) {
        NSRect frame = NSMakeRect(0, 0, 420, 300);
        self.peekPanel = [[NSPanel alloc] initWithContentRect:frame
                                                    styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                      backing:NSBackingStoreBuffered defer:YES];
        self.peekPanel.floatingPanel = YES;
        self.peekPanel.hasShadow = YES;
        self.peekPanel.ignoresMouseEvents = YES;
        self.peekView = [[ScintillaView alloc] initWithFrame:frame];
        [self.peekView message:SCI_SETZOOM wParam:(uptr_t)-6 lParam:0];
        for (int m = 0; m < 5; ++m) [self.peekView message:SCI_SETMARGINWIDTHN wParam:(uptr_t)m lParam:0];
        [self.peekView message:SCI_SETHSCROLLBAR wParam:0 lParam:0];
        [self.peekView message:SCI_SETVSCROLLBAR wParam:0 lParam:0];
        self.peekPanel.contentView = self.peekView;
    }
    ScintillaView *peek = self.peekView, *sci = self.sciView;
    [peek message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    [peek message:SCI_SETREADONLY wParam:1 lParam:0];
    for (int st = 0; st <= STYLE_MAX; ++st) {
        [peek message:SCI_STYLESETFORE wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETFORE wParam:(uptr_t)st]];
        [peek message:SCI_STYLESETBACK wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETBACK wParam:(uptr_t)st]];
    }
    [peek message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)MAX(0, doc.firstVisibleLine) lParam:0];
    NSRect onScreen = self.window ? [self.window convertRectToScreen:rectInWindow] : rectInWindow;
    [self.peekPanel setFrameTopLeftPoint:NSMakePoint(NSMinX(onScreen), NSMinY(onScreen))];
    [self.peekPanel orderFront:nil];
}

- (void)hideDocumentPeeker {
    if (!self.peekPanel.isVisible) return;
    [self.peekPanel orderOut:nil];
    [self.peekView message:SCI_SETDOCPOINTER wParam:0 lParam:0];
}

- (BOOL)documentPeekerVisible { return self.peekPanel.isVisible; }

- (NSArray<NppDocument *> *)documentsInRecentOrder {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.mru) if ([self.docs indexOfObjectIdenticalTo:d] != NSNotFound) [out addObject:d];
    for (NppDocument *d in self.docs) if ([out indexOfObjectIdenticalTo:d] == NSNotFound) [out addObject:d];
    return out;
}

- (nullable void *)documentPeekerDocument {
    return self.peekPanel.isVisible ? (void *)[self.peekView message:SCI_GETDOCPOINTER] : NULL;
}

- (void)peekAtTabIndex:(NSInteger)index { [self tabBar:self.tabBar hoveredIndex:index]; }

- (NSMenu *)tabBar:(NppTabBarView *)bar menuForIndex:(NSInteger)index {
    [self selectDocumentAtIndex:index];
    return self.tabContextMenu ? self.tabContextMenu() : nil;
}

- (void)tabBar:(NppTabBarView *)bar didRequestCloseIndex:(NSInteger)index {
    [self selectDocumentAtIndex:index];
    [self closeCurrentDocument];
}

- (void)tabBar:(NppTabBarView *)bar didMoveIndex:(NSInteger)from toIndex:(NSInteger)to {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    if (from < 0 || to < 0 || from >= (NSInteger)docs.count || to >= (NSInteger)docs.count) return;
    NppDocument *moving = docs[(NSUInteger)from];
    if (moving.pinned != ((NppDocument *)docs[(NSUInteger)to]).pinned) return;   // the pinned run stays whole
    NppDocument *inFront = self.currentDocument;
    [docs removeObjectAtIndex:(NSUInteger)from];
    [docs insertObject:moving atIndex:(NSUInteger)to];
    // The indexes moved, the documents did not: the one in front keeps its
    // number updated, so that selecting the moved tab is a real switch from
    // it (or none at all when the moved tab is the one in front).
    self.currentIndex = inFront ? (NSInteger)[docs indexOfObject:inFront] : -1;
    [self selectDocumentAtIndex:to];
}

- (BOOL)saveCurrentDocument {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    if (!doc.path) return [self saveCurrentDocumentAs];
    return [self writeCurrentToPath:doc.path];
}

/// Notepad_plus::fileSaveAs: the panel starts in the document's own folder; an untitled one
/// where Open would start (Preferences > Default Directory).
- (NSURL *)saveDirectoryForDocument:(NppDocument *)doc {
    NSString *folder = doc.path ? doc.path.stringByDeletingLastPathComponent : [self defaultOpenDirectory];
    return folder.length ? [NSURL fileURLWithPath:folder isDirectory:YES] : nil;
}

- (BOOL)saveCurrentDocumentAs {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = doc.path.lastPathComponent ?: doc.displayName;
    panel.directoryURL = [self saveDirectoryForDocument:doc];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return NO;
    NSString *path = panel.URL.path;
    for (NppDocument *other in self.docs) {
        if (other != doc && [other.path isEqualToString:path]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"That file is open in another tab.";
            alert.informativeText = @"Close it first, or choose another name.";
            [alert runModal];
            return NO;
        }
    }
    return [self saveCurrentDocumentAsPath:path];
}

- (BOOL)saveCurrentDocumentAsPath:(NSString *)path {
    NppDocument *doc = self.currentDocument;
    if (!doc || !path.length) return NO;
    for (NppDocument *other in self.docs) {
        if (other != doc && [other.path isEqualToString:path]) return NO;   // open in another tab
    }
    if (![self writeCurrentToPath:path]) return NO;
    doc.path = path;
    doc.displayName = path.lastPathComponent;
    // Buffer::setFileName: a language set from the menu (_hasLangBeenSetFromMenu)
    // stays; one that came from the old name is worked out from the new one.
    if (!doc.languageChosenByUser) doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:path];
    [self applyLanguage];
    [self refreshChrome];
    return YES;
}

- (BOOL)writeCurrentToPath:(NSString *)path {
    NSError *err = nil;
    // Preserve what is on disk before overwriting it, if Backup asks for that.
    [self writeBackupForPath:path];
    NSString *text = [self documentText];
    NppDocument *doc = self.currentDocument;
    NSStringEncoding enc = doc.encoding ?: NSUTF8StringEncoding;
    NSData *data = doc.codepage
        ? [EditorController dataFromString:text codepage:doc.codepage]
        : EncodeText(text, enc, doc.hasBOM);
    // FileManager::saveBuffer writes the file it opened, in place: through a symlink to the file
    // it points at (the link stays a link), and into the same file, so its permissions, hard links
    // and tags stay. Only a file that is not there yet is written atomically.
    NSString *target = NppCanonicalPath(path);
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:target];
    if (!data || ![data writeToFile:target options:(exists ? 0 : NSDataWritingAtomic) error:&err]) {
        if (!err) err = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                        userInfo:@{NSLocalizedDescriptionKey:
                                            @"Cannot encode the document in the selected encoding."}];
        [[NSAlert alertWithError:err] runModal];
        return NO;
    }
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    self.currentDocument.modified = NO;
    self.currentDocument.encodingChanged = NO;
    self.currentDocument.fileModificationDate =
        [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileModificationDate];
    [self dropBackupOfDocument:self.currentDocument];
    [self refreshChrome];
    [[NSNotificationCenter defaultCenter] postNotificationName:NppDocumentSavedNotification object:self];
    return YES;
}

- (void)dropBackupOfDocument:(NppDocument *)doc {
    if (!doc.backupPath) return;
    [[NSFileManager defaultManager] removeItemAtPath:doc.backupPath error:NULL];
    doc.backupPath = nil;
}

#pragma mark - Files changed on disk

static BOOL gCheckingFilesOnDisk;

- (void)checkFilesOnDisk {
    NppPreferences *p = [NppPreferences shared];
    if (!p.fileAutoDetection) return;
    // Answering the question means leaving and returning to the
    // application, which asks again: not while a check is under way.
    if (gCheckingFilesOnDisk) return;
    gCheckingFilesOnDisk = YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    NppDocument *was = self.currentDocument;
    NppDocument *previous = [self previousTab];

    for (NppDocument *doc in [self.docs copy]) {
        if (!doc.path || ![self.docs containsObject:doc]) continue;
        NSDate *onDisk = [[fm attributesOfItemAtPath:doc.path error:NULL] fileModificationDate];

        if (!onDisk) {
            if (!doc.fileModificationDate) continue;      // already known to be gone, and kept
            // Gone. Kept as a modified document, or closed, as the user says.
            [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];
            NSInteger answer = self.scriptedCloseAnswer;
            if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertFirstButtonReturn;
            if (!answer) {
                NSAlert *ask = [[NSAlert alloc] init];
                // Upstream's words (DoCloseOrNot), so every translation has them.
                ask.messageText = NppL(@"Keep non existing file");
                ask.informativeText = NppLMessage(@"The file \"$STR_REPLACE$\" doesn't exist anymore.\nKeep this file in editor?", doc.displayName, 0);
                [ask addButtonWithTitle:@"Yes"];
                [ask addButtonWithTitle:@"No"];
                answer = [ask runModal];
            }
            if (answer == NSAlertFirstButtonReturn) {
                doc.modified = YES;
                doc.fileModificationDate = nil;
                [self refreshChrome];
            } else {
                NSString *gone = doc.path;
                [self closeDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc] discardChanges:YES];
                [self forgetRecentFile:gone];             // there is nothing to reopen
            }
            continue;
        }
        if (!doc.fileModificationDate || [onDisk compare:doc.fileModificationDate] == NSOrderedSame) continue;

        // Changed by another program. Reloaded, unless the user has edits and
        // wants to keep them; asked first unless the setting says not to.
        [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];
        NSInteger answer = self.scriptedCloseAnswer;
        if (!answer && p.fileAutoDetectionSilent && !doc.modified) answer = NSAlertFirstButtonReturn;
        if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertFirstButtonReturn;
        if (!answer) {
            NSAlert *ask = [[NSAlert alloc] init];
            // DoReloadOrNot and DoReloadOrNotAndLooseChange.
            ask.messageText = NppL(@"Reload");
            ask.informativeText = NppLMessage(doc.modified
                ? @"\"$STR_REPLACE$\"\n\nThis file has been modified by another program.\nDo you want to reload it and lose the changes made in Notepad++?"
                : @"\"$STR_REPLACE$\"\n\nThis file has been modified by another program.\nDo you want to reload it?", doc.path ?: doc.displayName, 0);
            [ask addButtonWithTitle:@"Yes"];
            [ask addButtonWithTitle:@"No"];
            answer = [ask runModal];
        }
        if (answer == NSAlertFirstButtonReturn) {
            [self reselectDocument:doc];                  // the alert may have moved the front
            if ([self reloadCurrentDocument:NULL] && p.fileAutoDetectionScrollToEnd) {
                [self.sciView message:SCI_DOCUMENTEND wParam:0 lParam:0];
            }
        }
        // Either way this version is the one known, so it is not asked about again.
        doc.fileModificationDate = onDisk;
    }
    [self reselectDocument:was];
    [self rememberPreviousTab:previous];
    gCheckingFilesOnDisk = NO;
}

- (BOOL)confirmClosingDocuments:(NSArray<NppDocument *> *)docs {
    NppDocument *was = self.currentDocument;
    // Selecting each document to ask about it must not become the tab that
    // Recent Window steps back to.
    NppDocument *previous = [self previousTab];
    for (NppDocument *doc in [docs copy]) {
        if (!doc.modified || ![self.docs containsObject:doc]) continue;
        [self selectDocumentAtIndex:(NSInteger)[self.docs indexOfObject:doc]];

        NSInteger answer = self.scriptedCloseAnswer;
        // The suite cannot answer a sheet; unless a test scripted the answer,
        // it does not save, which is what every test before this relied on.
        if (!answer && getenv("NPPMAC_TEST")) answer = NSAlertSecondButtonReturn;
        if (!answer) {
            NSAlert *alert = [[NSAlert alloc] init];
            // DoSaveOrNot: "Save file "x" ?" with Yes, No and Cancel.
            alert.messageText = NppL(@"Save");
            alert.informativeText = NppLMessage(@"Save file \"$STR_REPLACE$\" ?", doc.displayName, 0);
            [alert addButtonWithTitle:@"Yes"];
            [alert addButtonWithTitle:@"No"];
            [alert addButtonWithTitle:@"Cancel"];
            answer = [alert runModal];
        }
        if (answer == NSAlertThirdButtonReturn) {
            [self reselectDocument:was];
            [self rememberPreviousTab:previous];
            return NO;
        }
        if (answer == NSAlertFirstButtonReturn && ![self saveCurrentDocument]) {
            [self reselectDocument:was];
            [self rememberPreviousTab:previous];
            return NO;
        }
    }
    [self reselectDocument:was];
    [self rememberPreviousTab:previous];
    return YES;
}

- (void)closeCurrentDocument {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    if (![self confirmClosingDocuments:@[doc]]) return;
    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
}

- (void)closeDocumentAtIndex:(NSInteger)index discardChanges:(BOOL)discard {
    if (index < 0 || index >= (NSInteger)self.docs.count) return;
    NppDocument *doc = self.docs[index];
    if (!discard && doc.modified) return;
    [self compareDocumentWillClose:doc];
    NppDocument *inFront = self.currentDocument;
    // A closed document is no longer watched.
    if (doc.monitoring || doc.monitorSource) [self stopMonitoringDocument:doc];

    [self.docs removeObjectAtIndex:index];

    if (self.docs.count == 0) {
        if ([NppPreferences shared].exitOnClosingLastTab) {
            [NSApp terminate:nil];
            return;
        }
        self.currentIndex = -1;
        [self newDocument];                       // switches the view off the old doc
    } else if (inFront && inFront != doc && [self.docs containsObject:inFront]) {
        // Closing another tab leaves the one in front where it is; only its
        // number changed.
        self.currentIndex = (NSInteger)[self.docs indexOfObject:inFront];
        [self refreshChrome];
    } else {
        // The closed document was the one in front: nothing of it is worth
        // keeping, and the index no longer names it, so the neighbour is
        // entered as a fresh switch and gets its own caret back.
        self.currentIndex = -1;
        [self selectDocumentAtIndex:MIN(index, (NSInteger)self.docs.count - 1)];
    }
    if (doc.path) [self noteRecentFile:doc.path];
    [self dropBackupOfDocument:doc];
    // The other pane must not be left on a document about to go.
    if (self.secondaryDocument == doc) {
        NppDocument *front = self.currentDocument;
        if (front && [self secondaryViewVisible]) {
            [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)front.docPointer];
            self.secondaryDocument = front;
        } else {
            [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:0];
            self.secondaryDocument = nil;
        }
    }
    // Safe only once the view no longer points at it.
    [self.sciView message:SCI_RELEASEDOCUMENT wParam:0 lParam:(sptr_t)doc.docPointer];
}

#pragma mark - File commands

- (BOOL)reloadCurrentDocument:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"This document has never been saved."}];
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfFile:doc.path options:0 error:error];
    if (!data) return NO;

    NSStringEncoding enc = NSUTF8StringEncoding; BOOL bom = NO;
    // Read back the way it is being read: a code page the user chose stays.
    NSString *text = doc.codepage ? [EditorController stringFromData:data codepage:doc.codepage]
                                  : DecodeText(data, &enc, &bom);
    if (!text) return NO;

    long caret = [self.sciView message:SCI_GETCURRENTPOS];
    long firstLine = [self.sciView message:SCI_GETFIRSTVISIBLELINE];
    [self setDocumentText:text];
    if (!doc.codepage) {
        doc.encoding = enc;
        doc.hasBOM = bom;
    }
    doc.encodingChanged = NO;
    doc.eolMode = DetectEOL(text);
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)doc.eolMode lParam:0];
    [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    RestartChangeHistory(self.sciView);
    [self.sciView message:SCI_GOTOPOS
                   wParam:(uptr_t)MIN(caret, [self.sciView message:SCI_GETLENGTH]) lParam:0];
    [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)firstLine lParam:0];
    doc.fileModificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:NULL]
                                fileModificationDate];
    [self dropBackupOfDocument:doc];
    doc.modified = NO;
    [self refreshChrome];
    return YES;
}

- (BOOL)saveCopyOfCurrentTo:(NSString *)path error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    NSString *text = [self documentText];
    NSData *data = doc.codepage
        ? [EditorController dataFromString:text codepage:doc.codepage]
        : EncodeText(text, doc.encoding ?: NSUTF8StringEncoding, doc.hasBOM);
    if (!data) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSUInteger)saveAllDocuments {
    NSInteger restore = self.currentIndex;
    NSUInteger saved = 0;
    for (NSInteger i = 0; i < (NSInteger)self.docs.count; ++i) {
        NppDocument *d = self.docs[i];
        if (!d.modified) continue;
        if (!d.path && getenv("NPPMAC_TEST")) continue;  // the suite cannot answer a save panel
        [self selectDocumentAtIndex:i];
        // An untitled document is asked where to go, as Windows asks.
        if (d.path ? [self writeCurrentToPath:d.path] : [self saveCurrentDocumentAs]) saved++;
    }
    [self selectDocumentAtIndex:restore];
    return saved;
}

- (BOOL)renameCurrentTo:(NSString *)newPath error:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        // Nothing on disk to move: only the tab is renamed, as on Windows.
        doc.displayName = newPath.lastPathComponent;
        [self refreshChrome];
        return YES;
    }
    if (![[NSFileManager defaultManager] moveItemAtPath:doc.path toPath:newPath error:error]) return NO;
    doc.path = newPath;
    doc.displayName = newPath.lastPathComponent;
    // A language the user picked survives the rename; one worked out from the
    // old name is worked out again from the new one.
    if (!doc.languageChosenByUser) {
        doc.language = [[LanguageCatalog sharedCatalog] languageForFileName:newPath];
    }
    [self applyLanguage];
    [self refreshChrome];
    return YES;
}

/// macOS equivalent of Notepad++'s "Move to Recycle Bin".
- (BOOL)moveCurrentToTrash:(NSError **)error {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError
                                            userInfo:@{NSLocalizedDescriptionKey: @"This document has never been saved."}];
        return NO;
    }
    if (![[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:doc.path]
                                       resultingItemURL:nil error:error]) return NO;
    NSString *gone = doc.path;
    [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
    [self forgetRecentFile:gone];             // as Windows takes a deleted file off the list
    return YES;
}

- (void)closeAllDocuments {
    if (![self confirmClosingDocuments:self.docs]) return;
    while (self.docs.count > 1) [self closeDocumentAtIndex:0 discardChanges:YES];
    [self closeDocumentAtIndex:0 discardChanges:YES];   // last one is replaced by a fresh tab
}

- (void)closeAllButCurrent {
    if (![self confirmClosingDocuments:[self.docs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppDocument *d, NSDictionary *b) { return d != self.currentDocument; }]]]) return;
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (self.docs[i] != keep) [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToLeft {
    if (![self confirmClosingDocuments:[self.docs subarrayWithRange:NSMakeRange(0, (NSUInteger)MAX(0, self.currentIndex))]]) return;
    NppDocument *keep = self.currentDocument;
    for (NSInteger i = self.currentIndex - 1; i >= 0; --i) {
        [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

- (void)closeAllToRight {
    if (![self confirmClosingDocuments:(self.currentIndex + 1 < (NSInteger)self.docs.count ? [self.docs subarrayWithRange:NSMakeRange((NSUInteger)self.currentIndex + 1, self.docs.count - (NSUInteger)self.currentIndex - 1)] : @[])]) return;
    NppDocument *keep = self.currentDocument;
    // closeDocumentAtIndex: moves currentIndex, so the bound is captured first.
    NSInteger from = self.currentIndex;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i > from; --i) {
        [self closeDocumentAtIndex:i discardChanges:YES];
    }
    [self reselectDocument:keep];
}

/// closeDocumentAtIndex: re-selects a tab as a side effect, so the document the
/// caller meant to keep has to be put back in front afterwards.
- (void)reselectDocument:(NppDocument *)doc {
    NSUInteger idx = [self.docs indexOfObject:doc];
    if (idx != NSNotFound) [self selectDocumentAtIndex:(NSInteger)idx];
}

- (void)closeAllButPinned {
    if (![self confirmClosingDocuments:[self.docs filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppDocument *d, NSDictionary *b) { return !d.pinned; }]]]) return;
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (!self.docs[i].pinned) [self closeDocumentAtIndex:i discardChanges:YES];
    }
}

- (void)togglePinCurrent {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    doc.pinned = !doc.pinned;
    // Pinned tabs sit at the left, as on Windows: pinning moves the tab to the
    // end of that run, unpinning to just after it.
    [self.docs removeObject:doc];
    NSUInteger pinnedRun = 0;
    while (pinnedRun < self.docs.count && self.docs[pinnedRun].pinned) pinnedRun++;
    [self.docs insertObject:doc atIndex:pinnedRun];
    self.currentIndex = (NSInteger)pinnedRun;
    [self refreshChrome];
}

- (void)closeAllUnchanged {
    for (NSInteger i = (NSInteger)self.docs.count - 1; i >= 0; --i) {
        if (!self.docs[i].modified) [self closeDocumentAtIndex:i discardChanges:NO];
    }
}

- (NSPrintOperation *)printOperationForCurrentShowingPanel:(BOOL)showPanel {
    NppDocument *doc = self.currentDocument;
    if (!doc) return nil;
    NSTextView *page = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 540, 720)];
    page.string = [self documentText];
    page.font = [NSFont fontWithName:@"Menlo" size:10] ?: [NSFont userFixedPitchFontOfSize:10];

    NSPrintInfo *info = [NSPrintInfo sharedPrintInfo];
    info.horizontalPagination = NSPrintingPaginationModeFit;
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:page printInfo:info];
    op.showsPrintPanel = showPanel;
    op.showsProgressPanel = showPanel;
    op.jobTitle = doc.displayName;
    return op;
}

- (BOOL)printCurrentShowingPanel:(BOOL)showPanel {
    NSPrintOperation *op = [self printOperationForCurrentShowingPanel:showPanel];
    return op ? [op runOperation] : NO;
}

#pragma mark - Folder as Workspace

- (void)openFolderAsWorkspace:(NSString *)path {
    if (!path.length) {
        [[NppDockingManager shared] hidePanel:@"workspace"];
        [self.workspace setRootPath:nil];
        return;
    }
    // Opening a folder adds it to the panel's roots, as upstream's does.
    [self.workspace addRootPath:path];
    [[NppDockingManager shared] showPanel:@"workspace"];
}

- (NSArray<NSString *> *)workspaceRootPaths { return self.workspace.rootPaths; }

- (NSString *)workspaceCurrentFilePath { return self.currentDocument.path; }

- (void)workspaceWantsFindInFolder:(NSString *)path {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"NppFindInFolderRequested" object:path];
}

- (BOOL)workspaceVisible { return [[NppDockingManager shared] isPanelVisible:@"workspace"]; }

/// A panel closed from its dock: the editor's own record of it follows.
- (void)dockPanelVisibilityChanged:(NSNotification *)note {
    NSString *ident = note.object;
    NppDockingManager *dock = [NppDockingManager shared];
    if ([ident hasPrefix:@"project"] && ![dock isPanelVisible:ident] &&
        self.activeProject == [[ident substringFromIndex:7] integerValue]) {
        self.activeProject = 0;
        for (NSInteger i = 1; i <= 3; ++i) {
            if ([dock isPanelVisible:[NSString stringWithFormat:@"project%ld", (long)i]]) { self.activeProject = i; break; }
        }
    }
    if ([ident isEqualToString:@"workspace"] && ![dock isPanelVisible:ident]) [self.workspace setRootPath:nil];
}
- (NSString *)workspaceRootPath { return self.workspace.rootPath; }
- (NSArray<NSString *> *)workspaceTopLevelNames { return [self.workspace topLevelNames]; }

- (void)workspaceDidActivateFile:(NSString *)path {
    NSError *err = nil;
    if (![self openFileAtPath:path error:&err] && err) [[NSAlert alertWithError:err] runModal];
}

#pragma mark - Open Containing Folder

- (NSURL *)containingFolderURL {
    NSString *path = self.currentDocument.path;
    if (!path.length) return nil;
    return [NSURL fileURLWithPath:path.stringByDeletingLastPathComponent isDirectory:YES];
}

- (BOOL)revealInFinder {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    return YES;
}

/// Notepad++ offers "cmd" and "PowerShell" here; on macOS both mean Terminal.
- (BOOL)openContainingFolderInTerminal {
    NSURL *folder = self.containingFolderURL;
    if (!folder) return NO;
    NSURL *terminal = [[NSWorkspace sharedWorkspace]
        URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (!terminal) return NO;
    [[NSWorkspace sharedWorkspace] openURLs:@[folder]
                       withApplicationAtURL:terminal
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
    return YES;
}

- (BOOL)openInDefaultViewer {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    return [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

#pragma mark - Sessions

- (NSString *)defaultSessionPath {
    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                     stringByAppendingPathComponent:@"NotepadMac"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    // session.xml, as upstream names it. A session.json left by an earlier
    // build is read once in its place, and the next save writes the XML.
    NSString *xml = [dir stringByAppendingPathComponent:@"session.xml"];
    NSString *old = [dir stringByAppendingPathComponent:@"session.json"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:xml] && [[NSFileManager defaultManager] fileExistsAtPath:old]) {
        [[NSFileManager defaultManager] moveItemAtPath:old toPath:xml error:NULL];   // the loader reads either
    }
    return xml;
}

/// What the session keeps of a document beyond its path: where the caret and
/// the view were, its bookmarks, and the settings that are the user's rather
/// than the file's. The document in front is read live; the others were
/// recorded when they left the front.
- (NSMutableDictionary *)sessionEntryForDocument:(NppDocument *)d {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"language"] = d.language.name ?: @"normal";
    BOOL front = d == self.currentDocument;
    entry[@"caret"] = @(front ? [self.sciView message:SCI_GETCURRENTPOS] : d.caretPosition);
    entry[@"anchor"] = @(front ? [self.sciView message:SCI_GETANCHOR] : d.anchorPosition);
    entry[@"firstLine"] = @(front ? [self.sciView message:SCI_GETFIRSTVISIBLELINE] : d.firstVisibleLine);
    entry[@"pinned"] = @(d.pinned);
    entry[@"tabColour"] = @(d.tabColour);
    entry[@"monitoring"] = @(d.monitoring);
    entry[@"userReadOnly"] = @(d.userReadOnly);
    NSArray *folds = front ? [self currentFoldedLines] : d.foldedLines;
    if (folds.count) entry[@"folds"] = folds;
    entry[@"encoding"] = @(d.encoding);
    entry[@"bom"] = @(d.hasBOM);
    entry[@"codepage"] = @(d.codepage);
    entry[@"eol"] = @(d.eolMode);
    if (d.backupPath && [[NSFileManager defaultManager] fileExistsAtPath:d.backupPath]) {
        entry[@"backup"] = d.backupPath;
    }
    // Bookmarks are marker 1, wherever it sits; the document can be asked
    // without being shown by pointing a query at its pointer... but Scintilla
    // answers for the view's document only, so the others were recorded on
    // leaving the front.
    if (front) {
        NSMutableArray *marks = [NSMutableArray array];
        long line = -1;
        while ((line = [self.sciView message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << 1)]) >= 0) {
            [marks addObject:@(line)];
        }
        entry[@"bookmarks"] = marks;
        d.bookmarkedLines = marks;
    } else if (d.bookmarkedLines) {
        entry[@"bookmarks"] = d.bookmarkedLines;
    }
    return entry;
}

- (BOOL)saveSessionTo:(NSString *)path error:(NSError **)error {
    NSMutableArray *files = [NSMutableArray array];
    NSMutableArray *unsaved = [NSMutableArray array];
    for (NppDocument *d in self.docs) {
        NSMutableDictionary *entry = [self sessionEntryForDocument:d];
        if (d.path) {
            entry[@"path"] = d.path;
            [files addObject:entry];
        } else if (entry[@"backup"]) {
            // An untitled document survives only through its backup.
            entry[@"name"] = d.displayName ?: @"";
            [unsaved addObject:entry];
        }
    }
    // The active tab is named by path: an index would count the unsaved
    // tabs that are not in the list, and the tabs open before the load.
    NSMutableDictionary *session = [@{@"version": @2,
                              @"current": @(MAX(0, self.currentIndex)),
                              @"currentPath": self.currentDocument.path ?: @"",
                              @"files": files,
                              @"unsaved": unsaved} mutableCopy];
    // The second view and what it shows, as upstream's subView.
    if ([self secondaryViewVisible] && self.secondaryDocument.path) {
        session[@"secondary"] = @{@"path": self.secondaryDocument.path,
                                  @"firstLine": @([self.secondaryView message:SCI_GETFIRSTVISIBLELINE]),
                                  @"caret": @([self.secondaryView message:SCI_GETCURRENTPOS]),
                                  // Where the divider stands, as a share of the split.
                                  @"split": @([self splitExtent] > 0
                                      ? [self paneExtent:self.sciView] / [self splitExtent] : 0.5)};
    }
    // Folder as Workspace's roots, as upstream's FileBrowser section.
    if ([self workspaceVisible] && [self workspaceRootPaths].count) session[@"workspaceRoots"] = [self workspaceRootPaths];
    // Written as Notepad++ writes session.xml, so a session goes from one
    // system to the other; what only the port keeps rides in mac… attributes.
    NSData *xml = [[EditorController sessionXMLFromDictionary:session] XMLDataWithOptions:NSXMLNodePrettyPrint];
    if (!xml) return NO;
    return [xml writeToFile:path options:NSDataWritingAtomic error:error];
}

#pragma mark Session as upstream's XML

static NSString *YesNo(id value) { return [value boolValue] ? @"yes" : @"no"; }

/// The name a language has in the Language menu, which is what session.xml calls it by.
static NSString *SessionLanguageName(NSString *internal) { return [LanguageCatalog menuTitleForLanguage:internal ?: @"normal"]; }

static NSString *InternalLanguageName(NSString *sessionName) {
    if (!sessionName.length) return nil;
    for (NppLanguage *l in [LanguageCatalog sharedCatalog].allLanguages) {
        if ([[LanguageCatalog menuTitleForLanguage:l.name] caseInsensitiveCompare:sessionName] == NSOrderedSame ||
            [l.name caseInsensitiveCompare:sessionName] == NSOrderedSame) return l.name;
    }
    return nil;
}

+ (NSXMLElement *)sessionFileElement:(NSDictionary *)entry name:(NSString *)filename {
    NSXMLElement *file = [NSXMLElement elementWithName:@"File"];
    void (^set)(NSString *, NSString *) = ^(NSString *name, NSString *value) {
        [file addAttribute:[NSXMLNode attributeWithName:name stringValue:value ?: @""]];
    };
    long caret = [entry[@"caret"] longValue], anchor = entry[@"anchor"] ? [entry[@"anchor"] longValue] : caret;
    set(@"firstVisibleLine", [entry[@"firstLine"] ?: @0 stringValue]);
    set(@"xOffset", @"0");
    set(@"scrollWidth", @"1");
    set(@"startPos", @(anchor).stringValue);
    set(@"endPos", @(caret).stringValue);
    set(@"selMode", @"0");
    set(@"offset", @"0");
    set(@"wrapCount", @"1");
    set(@"lang", SessionLanguageName(entry[@"language"]));
    // -1: no code page of its own (UTF-8, UTF-16 or plain ANSI), else the code page's number.
    set(@"encoding", [entry[@"codepage"] intValue] ? [entry[@"codepage"] stringValue] : @"-1");
    set(@"userReadOnly", YesNo(entry[@"userReadOnly"]));
    set(@"filename", filename);
    set(@"backupFilePath", entry[@"backup"]);
    set(@"originalFileLastModifTimestamp", @"0");
    set(@"originalFileLastModifTimestampHigh", @"0");
    // Upstream counts tab colours from 0 with -1 for none; here 0 is none.
    set(@"tabColourId", @([entry[@"tabColour"] integerValue] - 1).stringValue);
    set(@"RTL", @"no");
    set(@"tabPinned", YesNo(entry[@"pinned"]));
    set(@"untitleTabRenamed", @"no");
    set(@"macLanguage", entry[@"language"]);
    set(@"macEncoding", [entry[@"encoding"] ?: @0 stringValue]);
    set(@"macBOM", YesNo(entry[@"bom"]));
    set(@"macEOL", [entry[@"eol"] ?: @0 stringValue]);
    set(@"macMonitoring", YesNo(entry[@"monitoring"]));
    for (NSString *kind in @[@"bookmarks", @"folds"]) {
        for (NSNumber *line in [entry[kind] isKindOfClass:[NSArray class]] ? entry[kind] : @[]) {
            NSXMLElement *mark = [NSXMLElement elementWithName:[kind isEqualToString:@"folds"] ? @"Fold" : @"Mark"];
            [mark addAttribute:[NSXMLNode attributeWithName:@"line" stringValue:line.stringValue]];
            [file addChild:mark];
        }
    }
    return file;
}

+ (NSXMLDocument *)sessionXMLFromDictionary:(NSDictionary *)session {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    NSXMLElement *node = [NSXMLElement elementWithName:@"Session"];
    NSXMLElement *main = [NSXMLElement elementWithName:@"mainView"], *sub = [NSXMLElement elementWithName:@"subView"];
    NSDictionary *secondary = [session[@"secondary"] isKindOfClass:[NSDictionary class]] ? session[@"secondary"] : nil;
    [node addAttribute:[NSXMLNode attributeWithName:@"activeView" stringValue:@"0"]];
    NSInteger active = 0, index = 0;
    for (NSDictionary *f in session[@"files"]) {
        if ([f[@"path"] isEqualToString:session[@"currentPath"] ?: @""]) active = index;
        [main addChild:[self sessionFileElement:f name:f[@"path"]]];
        index++;
    }
    // Untitled documents: by their tab's name, with the backup that holds their text.
    for (NSDictionary *u in session[@"unsaved"]) [main addChild:[self sessionFileElement:u name:u[@"name"]]];
    [main addAttribute:[NSXMLNode attributeWithName:@"activeIndex" stringValue:@(active).stringValue]];
    [sub addAttribute:[NSXMLNode attributeWithName:@"activeIndex" stringValue:@"0"]];
    if (secondary) {
        [sub addChild:[self sessionFileElement:@{@"caret": secondary[@"caret"] ?: @0, @"firstLine": secondary[@"firstLine"] ?: @0,
                                                  @"language": @""} name:secondary[@"path"]]];
        [sub addAttribute:[NSXMLNode attributeWithName:@"macSplit" stringValue:[secondary[@"split"] ?: @0.5 stringValue]]];
    }
    [node addChild:main];
    [node addChild:sub];
    NSArray *roots = [session[@"workspaceRoots"] isKindOfClass:[NSArray class]] ? session[@"workspaceRoots"] : @[];
    if (roots.count) {
        NSXMLElement *browser = [NSXMLElement elementWithName:@"FileBrowser"];
        [browser addAttribute:[NSXMLNode attributeWithName:@"latestSelectedItem" stringValue:@""]];
        for (NSString *folder in roots) {
            NSXMLElement *r = [NSXMLElement elementWithName:@"root"];
            [r addAttribute:[NSXMLNode attributeWithName:@"foldername" stringValue:folder]];
            [browser addChild:r];
        }
        [node addChild:browser];
    }
    [root addChild:node];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.version = @"1.0";
    doc.characterEncoding = @"UTF-8";
    return doc;
}

/// session.xml - Notepad++'s, or this port's - as the dictionary the loader works from.
+ (NSDictionary *)sessionDictionaryFromXML:(NSData *)data {
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
    NSXMLElement *node = [doc.rootElement.name isEqualToString:@"NotepadPlus"] ? [doc.rootElement elementsForName:@"Session"].firstObject : nil;
    if (!node) return nil;
    NSDictionary *(^entryOf)(NSXMLElement *) = ^NSDictionary *(NSXMLElement *file) {
        NSString *(^attr)(NSString *) = ^NSString *(NSString *name) { return [file attributeForName:name].stringValue; };
        NSMutableDictionary *e = [NSMutableDictionary dictionary];
        NSString *language = attr(@"macLanguage").length ? attr(@"macLanguage") : InternalLanguageName(attr(@"lang"));
        if (language.length) e[@"language"] = language;
        e[@"caret"] = @(attr(@"endPos").longLongValue);
        e[@"anchor"] = @(attr(@"startPos").longLongValue);
        e[@"firstLine"] = @(attr(@"firstVisibleLine").longLongValue);
        e[@"pinned"] = @([attr(@"tabPinned") isEqualToString:@"yes"]);
        e[@"userReadOnly"] = @([attr(@"userReadOnly") isEqualToString:@"yes"]);
        e[@"tabColour"] = @(attr(@"tabColourId").length ? MAX(0, attr(@"tabColourId").integerValue + 1) : 0);
        e[@"monitoring"] = @([attr(@"macMonitoring") isEqualToString:@"yes"]);
        if (attr(@"encoding").intValue > 0) e[@"codepage"] = @(attr(@"encoding").intValue);
        if (attr(@"backupFilePath").length) e[@"backup"] = attr(@"backupFilePath");
        NSMutableArray *marks = [NSMutableArray array], *folds = [NSMutableArray array];
        for (NSXMLElement *m in [file elementsForName:@"Mark"]) [marks addObject:@([m attributeForName:@"line"].stringValue.longLongValue)];
        for (NSXMLElement *m in [file elementsForName:@"Fold"]) [folds addObject:@([m attributeForName:@"line"].stringValue.longLongValue)];
        e[@"bookmarks"] = marks;
        if (folds.count) e[@"folds"] = folds;
        return e;
    };
    NSMutableArray *files = [NSMutableArray array], *unsaved = [NSMutableArray array];
    NSXMLElement *main = [node elementsForName:@"mainView"].firstObject, *sub = [node elementsForName:@"subView"].firstObject;
    NSInteger active = [main attributeForName:@"activeIndex"].stringValue.integerValue, index = 0;
    NSString *currentPath = @"";
    for (NSXMLElement *file in [main elementsForName:@"File"]) {
        NSString *name = [file attributeForName:@"filename"].stringValue ?: @"";
        NSMutableDictionary *e = [entryOf(file) mutableCopy];
        // A name that is not a path is an untitled tab, which lives in its backup.
        // (A Windows path is a path too; its file is simply not here, and is passed over when loading.)
        BOOL isPath = name.isAbsolutePath || [name hasPrefix:@"\\\\"] ||
                      (name.length > 2 && [name characterAtIndex:1] == ':' && ([name characterAtIndex:2] == '\\' || [name characterAtIndex:2] == '/'));
        if (isPath) { e[@"path"] = name; [files addObject:e]; if (index == active) currentPath = name; }
        else if (e[@"backup"]) { e[@"name"] = name; [unsaved addObject:e]; }
        index++;
    }
    NSMutableDictionary *session = [@{@"version": @3, @"files": files, @"unsaved": unsaved, @"currentPath": currentPath} mutableCopy];
    NSXMLElement *second = [sub elementsForName:@"File"].firstObject;
    NSString *secondPath = [second attributeForName:@"filename"].stringValue;
    if (secondPath.isAbsolutePath) {
        NSDictionary *e = entryOf(second);
        // Windows keeps a file in one view or the other; here the second view shows one of the open files.
        if (![[files valueForKey:@"path"] containsObject:secondPath]) {
            NSMutableDictionary *asFile = [e mutableCopy];
            asFile[@"path"] = secondPath;
            [files addObject:asFile];
        }
        session[@"secondary"] = @{@"path": secondPath, @"firstLine": e[@"firstLine"], @"caret": e[@"caret"],
                                  @"split": @([sub attributeForName:@"macSplit"].stringValue.doubleValue ?: 0.5)};
    }
    NSMutableArray *roots = [NSMutableArray array];
    for (NSXMLElement *r in [[node elementsForName:@"FileBrowser"].firstObject elementsForName:@"root"]) {
        NSString *folder = [r attributeForName:@"foldername"].stringValue;
        if (folder.length) [roots addObject:folder];
    }
    if (roots.count) session[@"workspaceRoots"] = roots;
    return session;
}

- (BOOL)loadSessionFrom:(NSString *)path error:(NSError **)error {
    NSData *json = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!json) return NO;
    // Notepad++'s session.xml (from Windows, or written here), or the JSON this port wrote before.
    NSDictionary *session = [EditorController sessionDictionaryFromXML:json]
        ?: [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (![session isKindOfClass:[NSDictionary class]]) return NO;

    NSArray *files = session[@"files"];
    if (![files isKindOfClass:[NSArray class]]) return NO;

    NSUInteger opened = 0;
    for (NSDictionary *f in files) {
        NSString *p = f[@"path"];
        if (![p isKindOfClass:[NSString class]]) continue;
        if (![[NSFileManager defaultManager] fileExistsAtPath:p]) continue;   // deleted since
        if ([self openFileAtPath:p error:NULL]) {
            opened++;
            [self applySessionEntry:f];
        }
    }
    // Untitled documents come back from their backups, still modified.
    NSArray *unsaved = session[@"unsaved"];
    if ([unsaved isKindOfClass:[NSArray class]]) {
        for (NSDictionary *u in unsaved) {
            NSString *backup = [u isKindOfClass:[NSDictionary class]] ? u[@"backup"] : nil;
            NSData *data = [backup isKindOfClass:[NSString class]] ? [NSData dataWithContentsOfFile:backup] : nil;
            if (!data) continue;
            [self newDocument];
            NSString *name = u[@"name"];
            if ([name isKindOfClass:[NSString class]] && name.length) self.currentDocument.displayName = name;
            [self applySessionEntry:u];
            [self restoreBackupData:data forDocument:self.currentDocument atPath:backup];
        }
    }
    NSString *currentPath = session[@"currentPath"];
    NSUInteger byPath = [currentPath isKindOfClass:[NSString class]] && currentPath.length
        ? [self.docs indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *stop) {
              return [d.path isEqualToString:currentPath];
          }]
        : NSNotFound;
    NSNumber *cur = session[@"current"];
    if (byPath != NSNotFound) {
        [self selectDocumentAtIndex:(NSInteger)byPath];
    } else if (![currentPath isKindOfClass:[NSString class]] && [cur isKindOfClass:[NSNumber class]]) {
        // A session written before the path was kept: the index is all there is.
        [self selectDocumentAtIndex:MIN(cur.integerValue, (NSInteger)self.docs.count - 1)];
    }
    // The second view comes back showing what it showed, and where.
    NSDictionary *secondary = session[@"secondary"];
    if ([secondary isKindOfClass:[NSDictionary class]] && [secondary[@"path"] isKindOfClass:[NSString class]]) {
        NppDocument *front = self.currentDocument;
        NSUInteger at = [self.docs indexOfObjectPassingTest:^BOOL(NppDocument *d, NSUInteger i, BOOL *stop) {
            return [d.path isEqualToString:secondary[@"path"]];
        }];
        if (at != NSNotFound) {
            [self selectDocumentAtIndex:(NSInteger)at];
            [self cloneCurrentToOtherView];
            // The caret first, without scrolling to it, then the scroll: GOTOPOS after the first
            // visible line brought an off-screen caret back into view and undid it.
            [self.secondaryView message:SCI_SETEMPTYSELECTION wParam:(uptr_t)[secondary[@"caret"] longValue] lParam:0];
            [self.secondaryView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)[secondary[@"firstLine"] longValue] lParam:0];
            double share = [secondary[@"split"] doubleValue];
            if (share > 0.05 && share < 0.95) {
                [self.editorSplit setPosition:[self splitExtent] * share ofDividerAtIndex:0];
            }
            NSUInteger back = front ? [self.docs indexOfObjectIdenticalTo:front] : NSNotFound;
            if (back != NSNotFound) [self selectDocumentAtIndex:(NSInteger)back];
        }
    }
    NSArray *roots = session[@"workspaceRoots"];
    if ([roots isKindOfClass:[NSArray class]]) {
        for (NSString *root in roots) {
            if ([root isKindOfClass:[NSString class]] && [[NSFileManager defaultManager] fileExistsAtPath:root]) {
                [self openFolderAsWorkspace:root];
            }
        }
    }
    // An untitled tab was active: it is not in the list, and an index over
    // the tabs of that time would land on the wrong file; the last one opened stays.
    return opened > 0 || files.count == 0;
}

/// Puts back what the session kept of a document, once it is in front.
- (void)applySessionEntry:(NSDictionary *)f {
    NppDocument *doc = self.currentDocument;
    NSString *lang = f[@"language"];
    if ([lang isKindOfClass:[NSString class]] && lang.length) [self setLanguageNamed:lang];
    if ([f[@"codepage"] isKindOfClass:[NSNumber class]] && [f[@"codepage"] unsignedIntValue] && doc.path) {
        [self reinterpretAsCodepage:[f[@"codepage"] unsignedIntValue]];
        doc.modified = NO;
        doc.encodingChanged = NO;
        [self.sciView message:SCI_SETSAVEPOINT wParam:0 lParam:0];
    }
    if ([f[@"pinned"] isKindOfClass:[NSNumber class]]) doc.pinned = [f[@"pinned"] boolValue];
    if ([f[@"tabColour"] isKindOfClass:[NSNumber class]]) doc.tabColour = [f[@"tabColour"] integerValue];
    if ([f[@"monitoring"] isKindOfClass:[NSNumber class]] && [f[@"monitoring"] boolValue]) [self setMonitoring:YES];
    if ([f[@"userReadOnly"] isKindOfClass:[NSNumber class]] && [f[@"userReadOnly"] boolValue] && !doc.monitoring) {
        [self.sciView message:SCI_SETREADONLY wParam:1 lParam:0];
        doc.userReadOnly = YES;
    }
    // A backup newer than the file is the unsaved text of the last session.
    NSString *backup = f[@"backup"];
    if ([backup isKindOfClass:[NSString class]] && doc.path) {
        NSDate *backupDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:backup error:NULL] fileModificationDate];
        NSData *data = backupDate && doc.fileModificationDate &&
                       [backupDate compare:doc.fileModificationDate] != NSOrderedAscending
            ? [NSData dataWithContentsOfFile:backup] : nil;
        if (data) [self restoreBackupData:data forDocument:doc atPath:backup];
        else [[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];
    }
    // The bookmarks go on once the text is final: replacing the text would
    // have swept them all onto the first line.
    NSArray *marks = f[@"bookmarks"];
    if ([marks isKindOfClass:[NSArray class]]) {
        for (NSNumber *line in marks) {
            if ([line isKindOfClass:[NSNumber class]]) {
                [self.sciView message:SCI_MARKERADD wParam:(uptr_t)line.longValue lParam:1];
            }
        }
    }
    NSArray *folds = f[@"folds"];
    if ([folds isKindOfClass:[NSArray class]] && folds.count) {
        [self foldLines:folds];
        doc.foldedLines = folds;
    }
    long caret = [f[@"caret"] isKindOfClass:[NSNumber class]] ? [f[@"caret"] longValue] : 0;
    long anchor = [f[@"anchor"] isKindOfClass:[NSNumber class]] ? [f[@"anchor"] longValue] : caret;
    long length = [self.sciView message:SCI_GETLENGTH];
    [self.sciView message:SCI_SETSEL wParam:(uptr_t)MIN(anchor, length) lParam:MIN(caret, length)];
    if ([f[@"firstLine"] isKindOfClass:[NSNumber class]]) {
        [self.sciView message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)[f[@"firstLine"] longValue] lParam:0];
    }
    [self refreshChrome];
}

/// The text of a backup goes into the document in front, which is then
/// modified, and the backup stays where it is until the document is saved.
- (void)restoreBackupData:(NSData *)data forDocument:(NppDocument *)doc atPath:(NSString *)backup {
    NSString *text = doc.codepage ? [EditorController stringFromData:data codepage:doc.codepage] : nil;
    if (!text) {
        NSStringEncoding enc = NSUTF8StringEncoding; BOOL bom = NO;
        text = DecodeText(data, &enc, &bom);
    }
    if (!text) return;
    [self setDocumentText:text];
    [self.sciView message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    doc.modified = YES;
    doc.backupPath = backup;
    [self refreshChrome];
}

#pragma mark - Language + theme

- (void)chooseLanguageNamed:(NSString *)langName {
    [self setLanguageNamed:langName];
    self.currentDocument.languageChosenByUser = YES;
}

- (void)setLanguageNamed:(NSString *)langName {
    NppLanguage *lang = [[LanguageCatalog sharedCatalog] languageNamed:langName];
    if (!lang) return;
    self.currentDocument.language = lang;
    [self applyLanguage];
    [self refreshChrome];
}

/// A language's word lists by Notepad++'s own numbering (instre1 0, instre2 1, type1 2 ...), with the
/// words the user added in the Style Configurator joined to them, list by list, as Notepad++ appends them.
- (NSDictionary<NSNumber *, NSString *> *)keywordSetsOfLanguage:(NppLanguage *)lang {
    NSMutableDictionary<NSNumber *, NSString *> *sets = [lang.keywordSets mutableCopy] ?: [NSMutableDictionary dictionary];
    if (!lang) return sets;
    for (NppStyle *s in [[StyleCatalog sharedCatalog] stylesForLexerName:lang.name]) {
        NSNumber *idx = s.keywordClass ? NppKeywordSetIndex(s.keywordClass) : nil;
        if (!idx || !s.userKeywords.length) continue;
        sets[idx] = sets[idx].length ? [NSString stringWithFormat:@"%@ %@", sets[idx], s.userKeywords] : s.userKeywords;
    }
    return sets;
}

- (void)applyLanguage {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    NppLanguage *lang = doc.language ?: [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];
    ScintillaView *sci = self.sciView;
    // A new lexer works the fold levels out again, which unfolds everything;
    // what was folded is folded again afterwards.
    NSArray *folds = [self currentFoldedLines];
    [self applyLanguageOfDocument:doc toView:sci];
    NppUserLanguage *udl = [[LanguageCatalog sharedCatalog] userLanguageNamed:lang.name];
    [self applyTheme];
    if (udl) [self applyUserLanguageStyles:udl];
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    if (folds.count) [self foldLines:folds];
    if ([self documentMapVisible]) { [self mirrorStylesToDocumentMap]; [self updateDocumentMap]; }
    [self applyWordCharacters];
    [self markClickableLinks];
}

/// The lexer, its properties and its word lists for a document's language,
/// given to a view: the front view for the document in front, or the second
/// pane for a text it shows on its own (Compare). Styles come separately
/// (applyThemeToView:forLanguage:). A user-defined language's lexer is
/// configured for the front view only (configureUserLexerFor:).
- (void)applyLanguageOfDocument:(NppDocument *)doc toView:(ScintillaView *)sci {
    if (!doc) return;
    NppLanguage *lang = doc.language ?: [[LanguageCatalog sharedCatalog] languageNamed:@"normal"];

    // Notepad++'s table names "phpscript" for PHP, but setXmlLexer gives a .php file the lexer of the page
    // it is - HTML with <?php ?> in it - as it does ASP and JSP; phpscript is for PHP with no page around it.
    NSString *lexerID = [lang.name isEqualToString:@"php"] ? @"hypertext" : (lang.lexerID ?: @"");
    void *lexer = CreateLexer(lexerID.UTF8String);
    [sci message:SCI_SETILEXER wParam:0 lParam:(sptr_t)lexer];
    // The null lexer colours nothing and leaves the fold levels alone, so what the language
    // before it styled and folded would stay; plain text has neither.
    if ([lexerID isEqualToString:@"null"]) [sci message:SCI_CLEARDOCUMENTSTYLE];
    [sci setLexerProperty:@"fold" value:@"1"];
    [sci setLexerProperty:@"fold.compact" value:@"0"];
    [sci setLexerProperty:@"fold.comment" value:@"1"];
    // What else ScintillaEditView.cpp gives each family of lexers. Without fold.html the hypertext
    // lexer works out no fold levels at all, and a page cannot be folded anywhere.
    if ([lexerID isEqualToString:@"hypertext"] || [lexerID isEqualToString:@"xml"]) {        // setXmlLexer
        [sci setLexerProperty:@"fold.html" value:@"1"];
        [sci setLexerProperty:@"fold.hypertext.comment" value:@"1"];
        if ([lang.name isEqualToString:@"xml"]) [sci setLexerProperty:@"lexer.xml.allow.scripts" value:@"0"];
        else [sci setLexerProperty:@"asp.default.language" value:@"2"];                       // setEmbeddedAspLexer: VBScript
    } else if ([lexerID isEqualToString:@"cpp"] || [lexerID isEqualToString:@"objc"]) {       // setCppLexer, setJsLexer, setTypeScriptLexer, setObjCLexer
        [sci setLexerProperty:@"fold.cpp.comment.explicit" value:@"0"];
        [sci setLexerProperty:@"fold.preprocessor" value:@"1"];
        // The symbols an #if asks about are mostly defined outside the file; guessing greys out live code.
        if (![lexerID isEqualToString:@"objc"]) [sci setLexerProperty:@"lexer.cpp.track.preprocessor" value:@"0"];
        // `raw strings` in Go and TypeScript, `template ${literals}` in JavaScript.
        if ([lang.name isEqualToString:@"go"] || [lang.name isEqualToString:@"typescript"]) [sci setLexerProperty:@"lexer.cpp.backquoted.strings" value:@"1"];
        if ([lang.name hasPrefix:@"javascript"]) [sci setLexerProperty:@"lexer.cpp.backquoted.strings" value:@"2"];
    } else if ([lexerID isEqualToString:@"json"]) {                                           // setJsonLexer
        [sci setLexerProperty:@"lexer.json.escape.sequence" value:@"1"];
        if ([lang.name isEqualToString:@"json5"]) [sci setLexerProperty:@"lexer.json.allow.comments" value:@"1"];
    }
    if ([lang.name isEqualToString:@"sql"]) {
        [sci setLexerProperty:@"sql.backslash.escapes" value:[NppPreferences shared].sqlBackslashEscape ? @"1" : @"0"];
    }

    NppUserLanguage *udl = [[LanguageCatalog sharedCatalog] userLanguageNamed:lang.name];
    if (udl) {
        [self configureUserLexerFor:udl];
    } else {
        // Which of the lexer's word lists each of Notepad++'s lists goes to. For most lexers they
        // are the same number; the ones ScintillaEditView.cpp has a function of their own for are not.
        NSDictionary<NSNumber *, NSString *> *sets = [self keywordSetsOfLanguage:lang];
        NSString *name = lang.name;
        NSMutableDictionary<NSNumber *, NSString *> *lists = [NSMutableDictionary dictionary];
        // The documentation-comment words every C-like lexer is given: C++'s "type2".
        NSString *doxygen = [self keywordSetsOfLanguage:[[LanguageCatalog sharedCatalog] languageNamed:@"cpp"]][@3];
        if ([@[@"c", @"cpp", @"java", @"rc", @"cs", @"actionscript", @"swift", @"go"] containsObject:name] ||
            ([name hasPrefix:@"javascript"] && [lexerID isEqualToString:@"cpp"])) {            // setCppLexer, setJsLexer
            lists[@0] = sets[@0]; lists[@1] = sets[@2]; lists[@3] = sets[@1];
            if (![name isEqualToString:@"rc"]) lists[@2] = doxygen;
        } else if ([name isEqualToString:@"typescript"]) {                                     // setTypeScriptLexer
            lists[@0] = sets[@0]; lists[@1] = sets[@2]; lists[@2] = doxygen;
        } else if ([name isEqualToString:@"objc"]) {                                           // setObjCLexer
            lists[@0] = sets[@0]; lists[@1] = sets[@2]; lists[@2] = doxygen; lists[@3] = sets[@1]; lists[@4] = sets[@3];
        } else if ([name isEqualToString:@"tcl"]) {                                            // setTclLexer
            lists[@0] = sets[@0]; lists[@1] = sets[@2]; lists[@2] = sets[@1];
            for (NSInteger k = 3; k <= 8; ++k) lists[@(k)] = sets[@(k)];
        } else if ([name isEqualToString:@"xml"]) {                                            // setXmlLexer: the DOCTYPE words
            lists[@5] = sets[@0];
        } else if ([lexerID isEqualToString:@"hypertext"]) {
            // setHTMLLexer and the three embedded ones: a page is HTML's tags, and the words of the
            // languages that may be written inside it, whichever of them the file is called after.
            LanguageCatalog *catalog = [LanguageCatalog sharedCatalog];
            NSDictionary<NSNumber *, NSString *> *html = [self keywordSetsOfLanguage:[catalog languageNamed:@"html"]];
            lists[@0] = html[@0]; lists[@5] = html[@1];
            lists[@1] = [self keywordSetsOfLanguage:[catalog languageNamed:@"javascript"]][@0];
            lists[@4] = [self keywordSetsOfLanguage:[catalog languageNamed:@"php"]][@0];
            lists[@2] = [self keywordSetsOfLanguage:[catalog languageNamed:@"asp"]][@0];
        } else {
            [lists addEntriesFromDictionary:sets];
        }
        for (NSNumber *idx in lists) {
            [sci setStringProperty:SCI_SETKEYWORDS parameter:idx.integerValue value:lists[idx]];
        }
    }

}

- (void)applyTheme {
    NppDocument *doc = self.currentDocument;
    [self applyThemeToView:self.sciView forLanguage:doc.language.name ?: @"normal"];
    // Style definitions live in the view, not in the shared document, so the
    // other pane needs its own set - for the language of the document *it*
    // shows - or a clone renders in Scintilla's bare black-on-white defaults.
    // Windows does the same per view in ScintillaEditView::defineDocType.
    if (self.secondaryDocument) {
        [self applyThemeToView:self.secondaryView
                   forLanguage:self.secondaryDocument.language.name ?: @"normal"];
    }
    [self applyLook];
}

- (void)applyThemeToView:(ScintillaView *)sci forLanguage:(NSString *)langName {
    StyleCatalog *styles = [StyleCatalog sharedCatalog];

    NppStyle *def = styles.globalStyles[@"Default Style"];
    NSString *fontName = def.fontName.length ? def.fontName : @"Menlo";
    // Courier New at size 10 is a Windows default; on macOS it reads far too small.
    int fontSize = (def.fontSize > 0) ? MAX(def.fontSize, 12) : 13;
    if ([fontName isEqualToString:@"Courier New"]) fontName = @"Menlo";
    // Editing 1's font, when the user chose one, over the theme's.
    NppPreferences *prefs = [NppPreferences shared];
    if (prefs.chosenFontName) fontName = prefs.chosenFontName;
    if (prefs.chosenFontSize > 0) fontSize = (int)prefs.chosenFontSize;

    [sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:NppAvailableFontName(fontName)];
    [sci message:SCI_STYLESETSIZE wParam:STYLE_DEFAULT lParam:fontSize];
    if (def.foreground) [sci message:SCI_STYLESETFORE wParam:STYLE_DEFAULT lParam:SciColor(def.foreground)];
    if (def.background) [sci message:SCI_STYLESETBACK wParam:STYLE_DEFAULT lParam:SciColor(def.background)];

    // Global override: each attribute ticked in the Style Configurator comes
    // from the "Global override" style and beats every other style's own.
    NSDictionary *goFlags = [NppPreferences shared].globalOverride;
    NppStyle *go = styles.globalStyles[@"Global override"];
    void (^applyOverride)(int) = ^(int styleID) {
        if (!go) return;
        if ([goFlags[@"fg"] boolValue] && go.foreground)
            [sci message:SCI_STYLESETFORE wParam:(uptr_t)styleID lParam:SciColor(go.foreground)];
        if ([goFlags[@"bg"] boolValue] && go.background)
            [sci message:SCI_STYLESETBACK wParam:(uptr_t)styleID lParam:SciColor(go.background)];
        if ([goFlags[@"font"] boolValue] && go.fontName.length) {
            NSString *face = [go.fontName isEqualToString:@"Courier New"] ? @"Menlo" : go.fontName;
            [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:NppAvailableFontName(face)];
        }
        if ([goFlags[@"fontSize"] boolValue] && go.fontSize > 0)
            [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:go.fontSize];
        if ([goFlags[@"bold"] boolValue])
            [sci message:SCI_STYLESETBOLD wParam:(uptr_t)styleID lParam:(go.fontStyle & 1) ? 1 : 0];
        if ([goFlags[@"italic"] boolValue])
            [sci message:SCI_STYLESETITALIC wParam:(uptr_t)styleID lParam:(go.fontStyle & 2) ? 1 : 0];
        if ([goFlags[@"underline"] boolValue])
            [sci message:SCI_STYLESETUNDERLINE wParam:(uptr_t)styleID lParam:(go.fontStyle & 4) ? 1 : 0];
    };
    applyOverride(STYLE_DEFAULT);
    [sci message:SCI_STYLECLEARALL wParam:0 lParam:0];   // propagate default to all styles first

    void (^applyStyle)(NppStyle *, int) = ^(NppStyle *s, int styleID) {
        if (s.foreground) [sci message:SCI_STYLESETFORE wParam:styleID lParam:SciColor(s.foreground)];
        if (s.background) [sci message:SCI_STYLESETBACK wParam:styleID lParam:SciColor(s.background)];
        if (s.fontStyle & 1) [sci message:SCI_STYLESETBOLD wParam:styleID lParam:1];
        if (s.fontStyle & 2) [sci message:SCI_STYLESETITALIC wParam:styleID lParam:1];
        if (s.fontStyle & 4) [sci message:SCI_STYLESETUNDERLINE wParam:styleID lParam:1];
        if (s.fontName.length) [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:NppAvailableFontName(s.fontName)];
        if (s.fontSize > 0) [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:s.fontSize];
    };

    // A page is lexed as HTML with JavaScript, PHP and ASP inside it, and is coloured with the styles of
    // all four - setXmlLexer's makeStyle for L_HTML, L_JS_EMBEDDED, L_PHP and L_ASP - whichever it is called after.
    NSArray<NSString *> *styleLanguages = @[langName ?: @""];
    if ([@[@"html", @"php", @"asp", @"jsp"] containsObject:langName ?: @""]) {
        styleLanguages = @[@"html", @"javascript", @"php", @"asp"];
        for (NSNumber *filled in @[@(SCE_HJ_DEFAULT), @(SCE_HJ_COMMENT), @(SCE_HJ_COMMENTDOC), @(SCE_HJ_TEMPLATELITERAL),
                                   @(SCE_HJA_TEMPLATELITERAL), @(SCE_HPHP_DEFAULT), @(SCE_HPHP_COMMENT), @(SCE_HBA_DEFAULT)])
            [sci message:SCI_STYLESETEOLFILLED wParam:(uptr_t)filled.intValue lParam:1];
    }
    for (NSString *styled in styleLanguages)
        for (NppStyle *s in [styles stylesForLexerName:styled]) applyStyle(s, s.styleID);

    // Anything chosen in the Style Configurator wins over the shipped theme.
    // Every attribute the upstream Style struct carries is honoured here.
    NSDictionary *overrides = [NppPreferences shared].styleOverrides;
    for (NSString *key in overrides) {
        NSArray *parts = [key componentsSeparatedByString:@"/"];
        if (parts.count != 2 || ![styleLanguages containsObject:parts[0]]) continue;
        int styleID = [parts[1] intValue];
        NSDictionary *attrs = [[NppPreferences shared] styleOverrideForLanguage:parts[0]
                                                                        styleID:styleID];
        if (!attrs.count) continue;

        NSColor *(^colourFrom)(NSString *) = ^NSColor *(NSString *hex) {
            unsigned int rgb = 0;
            if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
            return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                                       green:((rgb >> 8) & 0xFF) / 255.0
                                        blue:(rgb & 0xFF) / 255.0 alpha:1.0];
        };
        NSColor *fg = colourFrom(attrs[@"fg"]);
        NSColor *bg = colourFrom(attrs[@"bg"]);
        if (fg) [sci message:SCI_STYLESETFORE wParam:(uptr_t)styleID lParam:SciColor(fg)];
        if (bg) [sci message:SCI_STYLESETBACK wParam:(uptr_t)styleID lParam:SciColor(bg)];
        if (attrs[@"bold"])      [sci message:SCI_STYLESETBOLD wParam:(uptr_t)styleID
                                        lParam:[attrs[@"bold"] boolValue] ? 1 : 0];
        if (attrs[@"italic"])    [sci message:SCI_STYLESETITALIC wParam:(uptr_t)styleID
                                        lParam:[attrs[@"italic"] boolValue] ? 1 : 0];
        if (attrs[@"underline"]) [sci message:SCI_STYLESETUNDERLINE wParam:(uptr_t)styleID
                                        lParam:[attrs[@"underline"] boolValue] ? 1 : 0];
        if ([attrs[@"font"] length]) {
            [sci setStringProperty:SCI_STYLESETFONT parameter:styleID value:NppAvailableFontName(attrs[@"font"])];
        }
        if ([attrs[@"size"] intValue] > 0) {
            [sci message:SCI_STYLESETSIZE wParam:(uptr_t)styleID lParam:[attrs[@"size"] intValue]];
        }
    }

    for (NSString *styled in styleLanguages)
        for (NppStyle *s in [styles stylesForLexerName:styled]) applyOverride(s.styleID);

    NppStyle *lineNo = styles.globalStyles[@"Line number margin"];
    if (lineNo) applyStyle(lineNo, STYLE_LINENUMBER);
    NppStyle *indent = styles.globalStyles[@"Indent guideline style"];
    if (indent) applyStyle(indent, STYLE_INDENTGUIDE);
    NppStyle *brace = styles.globalStyles[@"Brace highlight style"];
    if (brace) applyStyle(brace, STYLE_BRACELIGHT);
    NppStyle *badBrace = styles.globalStyles[@"Bad brace colour"];
    if (badBrace) applyStyle(badBrace, STYLE_BRACEBAD);

    // These take the colour in wParam, so they cannot go through applyStyle.
    [self applyCurrentLineLookToView:sci];
    NppStyle *caret = styles.globalStyles[@"Caret colour"];
    if (caret.foreground) [sci message:SCI_SETCARETFORE wParam:SciColor(caret.foreground) lParam:0];
    NppStyle *sel = styles.globalStyles[@"Selected text colour"];
    if (sel.background) [sci message:SCI_SETSELBACK wParam:1 lParam:SciColor(sel.background)];
    NppStyle *ws = styles.globalStyles[@"White space symbol"];
    if (ws.foreground) [sci message:SCI_SETWHITESPACEFORE wParam:1 lParam:SciColor(ws.foreground)];

    // Change History markers, in the margin configured by applyDocumentSettings.
    struct { NSString *name; int marker; } history[] = {
        {@"Change History modified",        SC_MARKNUM_HISTORY_MODIFIED},
        {@"Change History saved",           SC_MARKNUM_HISTORY_SAVED},
        {@"Change History revert origin",   SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN},
        {@"Change History revert modified", SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED},
    };
    for (size_t i = 0; i < sizeof(history)/sizeof(history[0]); ++i) {
        NppStyle *hs = styles.globalStyles[history[i].name];
        [sci message:SCI_MARKERDEFINE wParam:(uptr_t)history[i].marker lParam:SC_MARK_LEFTRECT];
        if (hs.background) {
            [sci message:SCI_MARKERSETBACK wParam:(uptr_t)history[i].marker lParam:SciColor(hs.background)];
            [sci message:SCI_MARKERSETFORE wParam:(uptr_t)history[i].marker lParam:SciColor(hs.background)];
        }
    }
}

#pragma mark - Encoding + EOL

- (void)setEncoding:(NSStringEncoding)enc withBOM:(BOOL)bom {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    // The encoding it already has: nothing to change, nothing to save (Notepad++
    // leaves the buffer alone when the unicode mode is the same).
    if (!doc.codepage && doc.encoding == enc && doc.hasBOM == bom) return;
    doc.encoding = enc;
    doc.hasBOM = bom;
    // IDM_FORMAT_CONV2_*: a document in a character set leaves it (setEncoding(-1)),
    // so Save writes the new form, not the old code page (ENCODING-024).
    doc.codepage = 0;
    // Changing the encoding changes the bytes on disk, so the document is
    // dirty - and stays dirty however far the text is undone, which is why
    // the savepoint is left where it was.
    doc.encodingChanged = YES;
    doc.modified = YES;
    [self refreshChrome];
}

- (void)convertEOLTo:(int)eolMode {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    // IDM_FORMAT_TODOS/TOUNIX/TOMAC: a read-only buffer keeps its format.
    if ([self.sciView message:SCI_GETREADONLY]) return;
    [self.sciView message:SCI_SETEOLMODE wParam:(uptr_t)eolMode lParam:0];
    [self.sciView message:SCI_CONVERTEOLS wParam:(uptr_t)eolMode lParam:0];
    doc.eolMode = eolMode;
    [self refreshChrome];
}

- (NSString *)encodingDisplayName {
    NppDocument *doc = self.currentDocument;
    // A character set is named by its menu label, as setUniModeText takes the menu string.
    int charset = [self currentCharsetIndex];
    if (charset >= 0) return @(kNppCharsets[charset].label);
    // These strings match the Encoding menu labels used by Notepad++.
    switch (doc.encoding) {
        // setUniModeText: without a BOM the file is "UTF-16 Little/Big Endian" (ENCODING-028).
        case NSUTF16LittleEndianStringEncoding: return doc.hasBOM ? @"UTF-16 LE BOM" : @"UTF-16 Little Endian";
        case NSUTF16BigEndianStringEncoding:    return doc.hasBOM ? @"UTF-16 BE BOM" : @"UTF-16 Big Endian";
        case NSISOLatin1StringEncoding:         return @"ANSI";
        case NSUTF8StringEncoding:              if (!doc.codepage) return doc.hasBOM ? @"UTF-8-BOM" : @"UTF-8";
        default: break;
    }
    // A character set of Encoding > Character Sets goes by its menu label, as
    // Notepad_plus::setUniModeText takes the Encode-in item's string.
    for (int i = 0; i < kNppCharsetCount; ++i) {
        unsigned int cp = kNppCharsets[i].codepage;
        if (doc.codepage ? doc.codepage == cp : [EditorController encodingForCodepage:cp] == doc.encoding)
            return @(kNppCharsets[i].label);
    }
    return doc.hasBOM ? @"UTF-8-BOM" : @"UTF-8";
}

/// EncodingMapper's table (PowerEditor/src/EncodingMapper.cpp, `encodings`): the
/// names a detected character set goes by, per Windows code page - how
/// Notepad++ turns uchardet's answer into the code page it shows.
static const struct { unsigned int codepage; const char *aliases; } kEncodingAliases[] = {
    {1250, "windows-1250"},
    {1251, "windows-1251"},
    {1252, "windows-1252"},
    {1253, "windows-1253"},
    {1254, "windows-1254"},
    {1255, "windows-1255"},
    {1256, "windows-1256"},
    {1257, "windows-1257"},
    {1258, "windows-1258"},
    {28591, "latin1 ISO_8859-1 ISO-8859-1 CP819 IBM819 csISOLatin1 iso-ir-100 l1"},
    {28592, "latin2 ISO_8859-2 ISO-8859-2 csISOLatin2 iso-ir-101 l2"},
    {28593, "latin3 ISO_8859-3 ISO-8859-3 csISOLatin3 iso-ir-109 l3"},
    {28594, "latin4 ISO_8859-4 ISO-8859-4 csISOLatin4 iso-ir-110 l4"},
    {28595, "cyrillic ISO_8859-5 ISO-8859-5 csISOLatinCyrillic iso-ir-144"},
    {28596, "arabic ISO_8859-6 ISO-8859-6 csISOLatinArabic iso-ir-127 ASMO-708 ECMA-114"},
    {28597, "greek ISO_8859-7 ISO-8859-7 csISOLatinGreek greek8 iso-ir-126 ELOT_928 ECMA-118"},
    {28598, "hebrew ISO_8859-8 ISO-8859-8 csISOLatinHebrew iso-ir-138"},
    {28599, "latin5 ISO_8859-9 ISO-8859-9 csISOLatin5 iso-ir-148 l5"},
    {28603, "ISO_8859-13 ISO-8859-13"},
    {28604, "iso-celtic latin8 ISO_8859-14 ISO-8859-14 18 iso-ir-199"},
    {28605, "Latin-9 ISO_8859-15 ISO-8859-15"},
    {437, "IBM437 cp437 437 csPC8CodePage437"},
    {720, "IBM720 cp720 oem720 720"},
    {737, "IBM737 cp737 oem737 737"},
    {775, "IBM775 cp775 oem775 775"},
    {850, "IBM850 cp850 oem850 850"},
    {852, "IBM852 cp852 oem852 852"},
    {855, "IBM855 cp855 oem855 855 csIBM855"},
    {857, "IBM857 cp857 oem857 857"},
    {858, "IBM858 cp858 oem858 858"},
    {860, "IBM860 cp860 oem860 860"},
    {861, "IBM861 cp861 oem861 861"},
    {862, "IBM862 cp862 oem862 862"},
    {863, "IBM863 cp863 oem863 863"},
    {865, "IBM865 cp865 oem865 865"},
    {866, "IBM866 cp866 oem866 866"},
    {869, "IBM869 cp869 oem869 869"},
    {950, "big5 csBig5"},
    {936, "gb2312 gbk csGB2312 gb18030"},
    {932, "Shift_JIS MS_Kanji csShiftJIS csWindows31J"},
    {949, "windows-949 korean"},
    {51949, "euc-kr csEUCKR"},
    {874, "tis-620"},
    {10007, "x-mac-cyrillic xmaccyrillic"},
    {21866, "koi8_u"},
    {20866, "koi8_r csKOI8R"},
};

/// The Windows code page an encoding is, by its IANA name among the aliases above.
static unsigned int CodepageOfEncoding(NSStringEncoding encoding) {
    CFStringRef iana = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encoding));
    if (!iana) return 0;
    NSString *name = (__bridge NSString *)iana;
    for (const auto &row : kEncodingAliases)
        for (NSString *alias in [@(row.aliases) componentsSeparatedByString:@" "])
            if ([alias caseInsensitiveCompare:name] == NSOrderedSame) return row.codepage;
    return 0;
}

/// The row of kNppCharsets the document is held in: its code page, or for a set
/// found on opening, the one whose encoding it was read with; -1 for Unicode and ANSI.
- (int)currentCharsetIndex {
    NppDocument *doc = self.currentDocument;
    if (!doc) return -1;
    for (int i = 0; i < kNppCharsetCount; ++i)
        if (doc.codepage && kNppCharsets[i].codepage == doc.codepage) return i;
    if (doc.codepage || doc.encoding == NSUTF8StringEncoding || doc.encoding == NSISOLatin1StringEncoding ||
        doc.encoding == NSUTF16LittleEndianStringEncoding || doc.encoding == NSUTF16BigEndianStringEncoding ||
        doc.encoding == NSUnicodeStringEncoding || doc.encoding == 0) return -1;
    // A set found on opening is held as an NSStringEncoding; its Windows code page names the row
    // (the detector's Shift-JIS and the menu's are different constants for the same set).
    unsigned int windows = CodepageOfEncoding(doc.encoding);
    if (!windows) windows = (unsigned int)CFStringConvertEncodingToWindowsCodepage(CFStringConvertNSStringEncodingToEncoding(doc.encoding));
    for (int i = 0; i < kNppCharsetCount; ++i) {
        if (windows && kNppCharsets[i].codepage == windows) return i;
        if ([EditorController encodingForCodepage:kNppCharsets[i].codepage] == doc.encoding) return i;
    }
    return -1;
}

#pragma mark - Editing commands

/// Reads `len` bytes at `pos` as a string, for prefix tests.
- (NSString *)textAt:(long)pos length:(long)len {
    if (len <= 0) return @"";
    NSMutableString *out = [NSMutableString stringWithCapacity:(NSUInteger)len];
    long docLen = [self.sciView message:SCI_GETLENGTH];
    for (long i = 0; i < len && pos + i < docLen; ++i) {
        [out appendFormat:@"%c", (char)[self.sciView message:SCI_GETCHARAT wParam:(uptr_t)(pos + i)]];
    }
    return out;
}

- (void)toggleLineComment { [self lineComment:NO]; }
- (void)setLineComment     { [self lineComment:YES]; }

/// Notepad_plus::doBlockComment: IDM_EDIT_BLOCK_COMMENT toggles (comments unless
/// every non-blank line already is), IDM_EDIT_BLOCK_COMMENT_SET always adds one
/// level. A language with no line comment but a stream comment (HTML, XML) gets
/// each line wrapped in it (EDIT-056). The selection follows the text, so a
/// second toggle covers the same lines (EDIT-052).
- (void)lineComment:(BOOL)alwaysAdd {
    NppDocument *doc = self.currentDocument;
    NSString *token = doc.language.commentLine;
    NSString *open = doc.language.commentStart, *close = doc.language.commentEnd;
    BOOL wrap = !token.length;
    if (wrap && (!open.length || !close.length)) { NppBeep(); return; }
    NSString *prefix = wrap ? [open stringByAppendingString:@" "] : [token stringByAppendingString:@" "];
    NSString *suffix = wrap ? [@" " stringByAppendingString:close] : @"";

    ScintillaView *sci = self.sciView;
    long anchor = [sci message:SCI_GETANCHOR], caret = [sci message:SCI_GETCURRENTPOS];
    long selStart = MIN(anchor, caret), selEnd = MAX(anchor, caret);
    long firstLine = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selStart];
    long lastLine  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)selEnd];
    if (lastLine > firstLine && selEnd == [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)lastLine]) {
        lastLine--;   // a trailing selection edge at column 0 does not include that line
    }
    NSString *(^lineText)(long) = ^NSString *(long ln) {
        long a = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)ln];
        long b = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        return [self textAt:a length:b - a];
    };
    BOOL (^commented)(NSString *) = ^BOOL(NSString *t) {
        return wrap ? ([t hasPrefix:open] && [t hasSuffix:close] && t.length >= open.length + close.length)
                    : [t hasPrefix:token];
    };

    BOOL remove = NO;
    if (!alwaysAdd) {
        remove = YES;
        for (long ln = firstLine; ln <= lastLine && remove; ++ln) {
            NSString *t = lineText(ln);
            if (t.length && !commented(t)) remove = NO;
        }
    }

    long startDelta = 0, totalDelta = 0;
    [sci message:SCI_BEGINUNDOACTION];
    for (long ln = lastLine; ln >= firstLine; --ln) {      // bottom-up keeps positions valid
        long indent = [sci message:SCI_GETLINEINDENTPOSITION wParam:(uptr_t)ln];
        long end = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)ln];
        if (indent >= end) continue;
        long before = [sci message:SCI_GETLENGTH];
        if (remove) {
            NSString *t = lineText(ln);
            if (wrap) {
                long tail = (long)close.length + ([t hasSuffix:suffix] ? 1 : 0);
                [sci message:SCI_DELETERANGE wParam:(uptr_t)(end - tail) lParam:tail];
                long head = (long)open.length + ([t hasPrefix:prefix] ? 1 : 0);
                [sci message:SCI_DELETERANGE wParam:(uptr_t)indent lParam:head];
            } else {
                long head = (long)token.length + ([t hasPrefix:prefix] ? 1 : 0);
                [sci message:SCI_DELETERANGE wParam:(uptr_t)indent lParam:head];
            }
        } else {
            if (suffix.length) [sci setStringProperty:SCI_INSERTTEXT parameter:end value:suffix];
            [sci setStringProperty:SCI_INSERTTEXT parameter:indent value:prefix];
        }
        long delta = [sci message:SCI_GETLENGTH] - before;
        totalDelta += delta;
        if (ln == firstLine && selStart > indent) startDelta = delta;
    }
    [sci message:SCI_ENDUNDOACTION];
    if (selEnd > selStart) {
        long newStart = MAX(0, selStart + startDelta), newEnd = MAX(newStart, selEnd + totalDelta);
        if (anchor <= caret) [sci message:SCI_SETSEL wParam:(uptr_t)newStart lParam:newEnd];
        else [sci message:SCI_SETSEL wParam:(uptr_t)newEnd lParam:newStart];
    }
    [self refreshChrome];
}

- (void)toggleBlockComment {
    NppDocument *doc = self.currentDocument;
    NSString *open = doc.language.commentStart, *close = doc.language.commentEnd;
    if (!open.length || !close.length) { NppBeep(); return; }

    ScintillaView *sci = self.sciView;
    long selStart = [sci message:SCI_GETSELECTIONSTART];
    long selEnd   = [sci message:SCI_GETSELECTIONEND];
    if (selEnd == selStart) { NppBeep(); return; }

    [sci message:SCI_BEGINUNDOACTION];
    [sci setStringProperty:SCI_INSERTTEXT parameter:selEnd value:close];
    [sci setStringProperty:SCI_INSERTTEXT parameter:selStart value:open];
    [sci message:SCI_ENDUNDOACTION];
    [sci message:SCI_SETSEL wParam:(uptr_t)selStart
             lParam:selEnd + (long)open.length + (long)close.length];
    [self refreshChrome];
}

- (void)toggleBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long markers = [sci message:SCI_MARKERGET wParam:(uptr_t)line];
    if (markers & (1 << NPPMAC_BOOKMARK_MARKER)) {
        [sci message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
    } else {
        [sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
    }
}

- (void)nextBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long found = [sci message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) found = [sci message:SCI_MARKERNEXT wParam:0 lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) { NppBeep(); return; }
    [sci message:SCI_GOTOLINE wParam:(uptr_t)found lParam:0];
    [self refreshChrome];
}

- (void)previousBookmark {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    long found = [sci message:SCI_MARKERPREVIOUS wParam:(uptr_t)(line - 1) lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    if (found < 0) {
        found = [sci message:SCI_MARKERPREVIOUS
                       wParam:(uptr_t)[sci message:SCI_GETLINECOUNT] lParam:(1 << NPPMAC_BOOKMARK_MARKER)];
    }
    if (found < 0) { NppBeep(); return; }
    [sci message:SCI_GOTOLINE wParam:(uptr_t)found lParam:0];
    [self refreshChrome];
}

- (void)clearBookmarks {
    [self.sciView message:SCI_MARKERDELETEALL wParam:NPPMAC_BOOKMARK_MARKER lParam:0];
}

- (void)foldAll:(BOOL)fold {
    // Every level, not only the outermost (ScintillaEditView::foldAll): Unfold Level N after
    // Fold All then opens just that level's headers.
    [self.sciView message:SCI_FOLDALL
                   wParam:(uptr_t)((fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND) | SC_FOLDACTION_CONTRACT_EVERY_LEVEL)
                   lParam:0];
}

- (void)toggleFoldAtCursor {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    [sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
}

- (void)foldCurrent:(BOOL)fold {
    ScintillaView *sci = self.sciView;
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)[sci message:SCI_GETCURRENTPOS]];
    // Act on the enclosing fold point, which is what "current level" means.
    // A fold point itself, or the one the line is inside (foldCurrentPos).
    BOOL header = ([sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line] & SC_FOLDLEVELHEADERFLAG) != 0;
    long parent = header ? line : [sci message:SCI_GETFOLDPARENT wParam:(uptr_t)line];
    if (parent < 0) parent = line;
    // With "Make current level folding/unfolding commands toggleable" either
    // command folds an open level and opens a folded one.
    if ([NppPreferences shared].foldCommandsToggle) fold = [sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)parent] != 0;
    [sci message:SCI_FOLDLINE wParam:(uptr_t)parent
             lParam:(fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND)];
}

- (void)showAutoCompletion {
    // Word Completion: the document's words, a lone one typed straight in.
    [self showCompletion:NppCompletionKindWords autoInsert:YES];
}

/// Right-click menu, built from the commands listed in Preferences.
/// The commands of the popup menu, as contextMenu.xml has them now (it is
/// read each time, so an edit shows at the next right click) or, without
/// one, as Preferences lists them.
- (NSArray<NSMenuItem *> *)contextMenuItems {
    NSMenu *described = self.editorContextMenu ? self.editorContextMenu() : nil;
    if (described.numberOfItems) {
        NSArray *items = [described.itemArray copy];
        [described removeAllItems];
        return items;
    }
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    for (NSString *title in [NppPreferences shared].contextMenuCommands) {
        NSMenuItem *found = nil;
        NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
        while (queue.count && !found) {
            NSMenuItem *item = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (item.submenu) [queue addObjectsFromArray:item.submenu.itemArray];
            // The setting holds English titles; the menu may be showing another language.
            if (([NppEnglishTitle(item) isEqualToString:title] || [item.title isEqualToString:title]) && item.action) found = item;
        }
        if (!found) continue;
        NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:found.title
                                                      action:found.action keyEquivalent:@""];
        copy.target = found.target;
        copy.tag = found.tag;
        copy.representedObject = found.representedObject;
        [items addObject:copy];
    }
    return items;
}

- (void)rebuildContextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Context"];
    for (NSMenuItem *item in [self contextMenuItems]) [menu addItem:item];
    menu.delegate = (id<NSMenuDelegate>)self;
    self.sciView.menu = menu;
    self.secondaryView.menu = menu;
}

/// The results tab has the Search results panel's menu instead of the editor's.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.sciView.menu && menu != self.secondaryView.menu) return;
    [menu removeAllItems];
    if ([self showingSearchResults]) {
        struct { NSString *title; SEL action; } items[] = {
            {@"Fold all", @selector(resultsFoldAll:)}, {@"Unfold all", @selector(resultsUnfoldAll:)},
            {nil, NULL},
            {@"Copy Selected Line(s)", @selector(resultsCopyLines:)},
            {@"Copy Selected Pathname(s)", @selector(resultsCopyPaths:)},
            {@"Select all", @selector(resultsSelectAll:)},
            {@"Clear all", @selector(resultsClearAll:)},
            {@"Delete This Search", @selector(resultsDeleteSearch:)},
            {nil, NULL},
            {@"Open Selected Pathname(s)", @selector(resultsOpenPaths:)},
            {nil, NULL},
            {@"Purge for every search", @selector(resultsTogglePurge:)},
        };
        for (auto &it : items) {
            if (!it.title) { [menu addItem:[NSMenuItem separatorItem]]; continue; }
            NSMenuItem *item = [menu addItemWithTitle:it.title action:it.action keyEquivalent:@""];
            item.target = self;
            if (it.action == @selector(resultsTogglePurge:)) {
                item.state = [NppPreferences shared].searchResultsPurge ? NSControlStateValueOn : NSControlStateValueOff;
            }
        }
        return;
    }
    // A selected formula gets Calculate, a selected set of numbers its sum,
    // average... and sorting, on top.
    for (NSMenuItem *item in [self formulaMenuItems]) [menu addItem:item];
    for (NSMenuItem *item in [self numberSetMenuItems]) [menu addItem:item];
    // A misspelled word under the caret puts the engine's guesses on top,
    // the way every Mac text field does.
    for (NSMenuItem *item in [self spellingMenuItemsForPosition:
            (long)[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0]]) [menu addItem:item];
    for (NSMenuItem *item in [self contextMenuItems]) [menu addItem:item];
}

- (void)resultsFoldAll:(id)sender   { [self foldAllSearchResults:YES]; }
- (void)resultsUnfoldAll:(id)sender { [self foldAllSearchResults:NO]; }
- (void)resultsCopyLines:(id)sender { [self copySearchResultLines]; }
- (void)resultsCopyPaths:(id)sender { [self copySearchResultPaths]; }
- (void)resultsSelectAll:(id)sender { [self.sci message:SCI_SELECTALL]; }
- (void)resultsClearAll:(id)sender  { [self clearSearchResults]; }
- (void)resultsDeleteSearch:(id)sender { [self deleteSearchResultAtCaret]; }
- (void)resultsOpenPaths:(id)sender { [self openSearchResultPaths]; }
- (void)resultsTogglePurge:(id)sender {
    [NppPreferences shared].searchResultsPurge = ![NppPreferences shared].searchResultsPurge;
}

#pragma mark - Chrome refresh

- (void)refreshChrome {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:NppEditorDocumentsDidChangeNotification object:self];
    NSMutableArray *tabItems = [NSMutableArray arrayWithCapacity:self.docs.count];
    for (NppDocument *d in self.docs) {
        NppTabItem *item = [[NppTabItem alloc] init];
        item.title = [self untitledNameForDocument:d];
        item.modified = d.modified;
        item.pinned = d.pinned;
        item.colour = d.tabColour;
        [tabItems addObject:item];
    }
    self.tabBar.items = tabItems;
    if (self.currentIndex >= 0 && self.currentIndex < (NSInteger)self.docs.count) {
        self.tabBar.selectedIndex = self.currentIndex;
    }
    [self applyTabBarPreferences];

    NppDocument *doc = self.currentDocument;
    // The view with the focus, as upstream's status bar follows _pEditView.
    ScintillaView *sci = [self secondaryViewVisible] && [self otherViewHasFocus] ? self.secondaryView : self.sciView;
    long pos = [sci message:SCI_GETCURRENTPOS];
    long line = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)pos] + 1;
    long col = [sci message:SCI_GETCOLUMN wParam:(uptr_t)pos] + 1;
    long len = [sci message:SCI_GETLENGTH];
    long lines = [sci message:SCI_GETLINECOUNT];

    // The fields as Notepad++ fills them (Notepad_plus::setDisplayFormat, updateStatusBar), in
    // the interface language: its nativeLang files carry statusbar-length-lines, statusbar-Ln-Col,
    // statusbar-Pos, statusbar-Sel and the EOL names, looked up by their English text.
    // The translation's labels around the two placeholders, put back together with upstream's
    // four spaces between the pair: the loader folds runs of spaces in what it reads.
    NSString *(^fill)(NSString *, NSString *, NSString *) = ^NSString *(NSString *english, NSString *one, NSString *two) {
        NSString *t = NppL(english);
        NSRange r1 = [t rangeOfString:@"$STR_REPLACE1$"], r2 = [t rangeOfString:@"$STR_REPLACE2$"];
        if (r1.location == NSNotFound || r2.location == NSNotFound || r2.location < r1.location) return [NSString stringWithFormat:@"%@ %@", one, two];
        NSString *first = [t substringToIndex:r1.location];
        NSString *second = [[t substringWithRange:NSMakeRange(NSMaxRange(r1), r2.location - NSMaxRange(r1))]
                            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([second hasSuffix:@":"]) second = [second stringByAppendingString:@" "];
        return [NSString stringWithFormat:@"%@%@    %@%@", first, one, second, two];
    };
    // "Sel: " and "Pos: " end in a space the loader trims.
    NSString *(^label)(NSString *) = ^NSString *(NSString *english) {
        NSString *t = NppL(english);
        return [t hasSuffix:@" "] || [t hasSuffix:@":"] == NO ? t : [t stringByAppendingString:@" "];
    };
    NSString *lengthLines = fill(@"length: $STR_REPLACE1$    lines: $STR_REPLACE2$", [@(len) stringValue], [@(lines) stringValue]);
    NSString *lnCol = fill(@"Ln: $STR_REPLACE1$    Col: $STR_REPLACE2$", [@(line) stringValue], [@(col) stringValue]);
    NSString *selection;
    long selections = [sci message:SCI_GETSELECTIONS];
    if (selections == 1 && [sci message:SCI_GETSELECTIONEMPTY]) {
        selection = [label(@"Pos: ") stringByAppendingFormat:@"%ld", pos + 1];
    } else if (selections == 1) {
        long start = [sci message:SCI_GETSELECTIONSTART], end = [sci message:SCI_GETSELECTIONEND];
        long chars = [sci message:SCI_COUNTCHARACTERS wParam:(uptr_t)start lParam:end];
        long selLines = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)end] - [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)start] + 1;
        selection = [label(@"Sel: ") stringByAppendingFormat:@"%ld | %ld", chars, selLines];
    } else {
        long chars = 0;
        for (long i = 0; i < selections; ++i) {
            long a = [sci message:SCI_GETSELECTIONNSTART wParam:(uptr_t)i], b = [sci message:SCI_GETSELECTIONNEND wParam:(uptr_t)i];
            chars += [sci message:SCI_COUNTCHARACTERS wParam:(uptr_t)MIN(a, b) lParam:MAX(a, b)];
        }
        selection = [NppL(@"Sel") stringByAppendingFormat:@" %ld : %ld | %ld", selections, chars, selections];
    }
    // The EOL name is not translated upstream either (setDisplayFormat).
    NSString *eol = doc.eolMode == SC_EOL_CRLF ? @"Windows (CR LF)" : doc.eolMode == SC_EOL_CR ? @"Macintosh (CR)" : @"Unix (LF)";
    NSString *language = NppL([LanguageCatalog menuTitleForLanguage:doc.language.name ?: @"normal"]);
    // Notepad++ shows the typing mode in the status bar, and this is the only
    // place it is visible.
    NSString *typing = [self overtype] ? @"OVR" : @"INS";
    // The Git branch is the port's own field, after Notepad++'s, and only inside a repository.
    NSString *branch = [self gitStatusBarText];
    if (!self.copiedTimer) {
        self.pathField.stringValue = doc.path ?: @"(unsaved)";
        self.pathField.toolTip = doc.path ? NppL(@"Click to copy the full path") : nil;
    }
    [self layoutStatusFields];
    self.statusField.stringValue = [NSString stringWithFormat:
        @"%@    %@    %@    %@    %@    %@    %@%@",
        language, lengthLines, lnCol, selection, eol, [self encodingDisplayName], typing,
        branch.length ? [@"    " stringByAppendingString:branch] : @""];

    NSString *title = (doc.path && ![NppPreferences shared].titleBarFileNameOnly)
        ? [NSString stringWithFormat:@"%@ — %@", doc.displayName, doc.path.stringByDeletingLastPathComponent]
        : (doc.displayName ?: @"");
    if (self.titleSuffix.length) title = [title stringByAppendingFormat:@" - %@", self.titleSuffix];
    self.window.title = title;
    self.window.representedFilename = doc.path ?: @"";
    self.window.documentEdited = doc.modified;
    // The toolbar's Save, Undo, Cut... follow the document at once, as upstream's
    // enableCommand does on each change; AppKit would validate them only later, and the
    // buttons in the overflow (a narrow window) only when that menu opens.
    for (NSToolbarItem *item in self.window.toolbar.items) [item validate];
}

/// The Tab bar page of Preferences drives the bar's layout and behaviour.
- (void)applyTabBarPreferences {
    NppPreferences *p = [NppPreferences shared];
    self.tabBar.showCloseButtons = p.tabShowCloseButton;
    self.tabBar.closeButtonsOnInactiveTabs = p.tabCloseButtonOnInactive;
    self.tabBar.doubleClickCloses = p.tabDoubleClickCloses;
    self.tabBar.locked = p.tabBarLocked;
    self.tabBar.vertical = p.tabBarVertical;
    self.tabBar.multiLine = p.tabBarMultiLine;
    // Hidden too while the chrome is (distraction free) or the command line said -notabbar.
    self.tabBar.hidden = p.hideTabBar || self.chromeHidden || self.tabBarHiddenForLaunch;
    self.tabBar.drawActiveBar = p.tabDrawActiveBar;
    self.tabBar.colourInactiveTabs = p.tabColourInactive;
    self.tabBar.reduced = p.tabReduced;
    self.tabBar.maxLabelLength = p.tabMaxLabelLength;
    NSDictionary<NSString *, NppStyle *> *g = [StyleCatalog sharedCatalog].globalStyles;
    self.tabBar.activeBarColour = g[@"Active tab focused indicator"].foreground;
    self.tabBar.activeBarUnfocusedColour = g[@"Active tab unfocused indicator"].foreground;
    // The text and inactive colours are drawn on the system's tab
    // backgrounds, so they are taken only where they read on them: in dark
    // mode upstream draws its tabs in the dark palette instead.
    BOOL dark = [[self.tabBar.effectiveAppearance bestMatchFromAppearancesWithNames:
                  @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    self.tabBar.activeTextColour = dark ? nil : g[@"Active tab text"].foreground;
    self.tabBar.inactiveTextColour = dark ? [NSColor secondaryLabelColor] : g[@"Inactive tabs"].foreground;
    self.tabBar.inactiveBackColour = dark ? nil : g[@"Inactive tabs"].background;
    [self.tabBar setNeedsDisplay:YES];
    // A hidden tab bar gives its room to the editor, a shown one takes it back
    // (TabBarPlus::display / Notepad_plus::hideTabBar resize the edit view).
    // The split holding the panes is what gets the room: the panes inside it keep their divider.
    CGFloat tabH = self.tabBar.hidden ? 0 : NSHeight(self.tabBar.frame);
    NSRect edit = NSMakeRect(0, 0, NSWidth(self.editorArea.frame), NSHeight(self.editorArea.frame) - tabH);
    if (!NSEqualRects(self.editorSplit.frame, edit)) self.editorSplit.frame = edit;
}

/// The path field is as wide as its text, up to half the bar; the rest follows it.
- (void)layoutStatusFields {
    CGFloat total = NSWidth(self.container.frame);
    CGFloat wanted = ceil(self.pathField.cell.cellSize.width) + 4;
    CGFloat width = MIN(wanted, MAX(80, total * 0.5));
    self.pathField.frame = NSMakeRect(6, 2, width, NSHeight(self.pathField.frame));
    self.statusField.frame = NSMakeRect(6 + width + 12, 2, MAX(0, total - width - 24), NSHeight(self.statusField.frame));
}

/// A click on the path in the status bar: the full path goes to the clipboard,
/// and the field says so for a moment.
- (void)copyPathFromStatusBar {
    NSString *path = self.currentDocument.path;
    if (!path) { NppBeep(); return; }
    [self copyText:path];
}

- (void)copyText:(NSString *)text {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:text forType:NSPasteboardTypeString];
    [self flashStatus:[NSString stringWithFormat:@"✓ %@", NppLMessage(@"Copied: $STR_REPLACE$", text, 0)]];
}

- (void)flashStatus:(NSString *)message {
    [self.copiedTimer invalidate];
    self.pathField.stringValue = message;
    [self layoutStatusFields];
    __weak EditorController *weakSelf = self;
    self.copiedTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:NO block:^(NSTimer *t) {
        weakSelf.copiedTimer = nil;
        [weakSelf refreshChrome];
    }];
}

/// General > Status Bar > Hide.
- (void)applyStatusBarVisibility {
    BOOL hidden = [NppPreferences shared].statusBarHidden || self.chromeHidden;
    self.statusField.hidden = hidden;
    self.pathField.hidden = hidden;
    CGFloat statusH = hidden ? 0 : 22;
    self.split.frame = NSMakeRect(0, statusH, NSWidth(self.container.frame), NSHeight(self.container.frame) - statusH);
}

- (BOOL)statusBarVisible { return !self.statusField.hidden; }

- (void)setChromeVisible:(BOOL)visible {
    self.chromeHidden = !visible;
    self.tabBar.hidden = !visible || [NppPreferences shared].hideTabBar;
    self.statusField.hidden = !visible || [NppPreferences shared].statusBarHidden;
    NSRect upper = self.split.frame;
    CGFloat tabH = visible ? 28 : 0, statusH = self.statusField.hidden ? 0 : 22;
    self.split.frame = NSMakeRect(0, statusH, NSWidth(self.container.frame),
                                  NSHeight(self.container.frame) - statusH);
    self.sciView.frame = NSMakeRect(0, 0, NSWidth(self.editorArea.frame),
                                    NSHeight(self.editorArea.frame) - tabH);
    (void)upper;
    [self applyEditorPreferences];
    [self.container setNeedsDisplay:YES];
}

- (BOOL)chromeVisible { return !self.chromeHidden; }

/// -notabbar (Notepad++'s TabBarPlus hidden for this run): the tab bar only, the status bar stays;
/// the preference is left as it is.
- (void)hideTabBarForLaunch {
    self.tabBarHiddenForLaunch = YES;
    self.tabBar.hidden = YES;
    self.sciView.frame = NSMakeRect(0, 0, NSWidth(self.editorArea.frame), NSHeight(self.editorArea.frame));
    [self.container setNeedsDisplay:YES];
}

#pragma mark - Second editor pane

- (ScintillaView *)secondarySci { return self.secondaryView; }

- (BOOL)secondaryViewVisible { return self.secondaryHost.superview != nil; }

/// The split's length along its divider's travel, and a pane's: widths for views side by side.
- (CGFloat)splitExtent { return self.editorSplit.vertical ? NSWidth(self.editorSplit.frame) : NSHeight(self.editorSplit.frame); }
- (CGFloat)paneExtent:(NSView *)pane { return self.editorSplit.vertical ? NSWidth(pane.frame) : NSHeight(pane.frame); }
- (NppDocument *)documentInSecondaryView { return [self secondaryViewVisible] ? self.secondaryDocument : nil; }

- (void)setSecondaryViewVisible:(BOOL)visible {
    if (visible == [self secondaryViewVisible]) return;
    if (visible) {
        [self.editorSplit addSubview:self.secondaryHost];
        [self.editorSplit adjustSubviews];
        [self.editorSplit setPosition:[self splitExtent] / 2 ofDividerAtIndex:0];
    } else {
        [self.secondaryHost removeFromSuperview];
        [self.editorSplit adjustSubviews];
    }
}

- (void)focusOtherView {
    if (![self secondaryViewVisible]) { NppBeep(); return; }
    NSResponder *first = self.window.firstResponder;
    BOOL primaryFocused = !(first == self.secondaryView ||
                            [first isKindOfClass:[NSView class]] &&
                            [(NSView *)first isDescendantOf:self.secondaryView]);
    [self.window makeFirstResponder:primaryFocused ? self.secondaryView.content : self.sciView.content];
}

- (BOOL)otherViewHasFocus {
    NSResponder *first = self.window.firstResponder;
    if (![first isKindOfClass:[NSView class]]) return NO;
    return [(NSView *)first isDescendantOf:self.secondaryView];
}

- (BOOL)cloneCurrentToOtherView {
    NppDocument *doc = self.currentDocument;
    if (!doc) return NO;
    // A second view on the document expands the folds of the first; they are put back.
    NSArray *folds = [self currentFoldedLines];
    [self setSecondaryViewVisible:YES];
    // Sharing the document pointer is what makes it a clone: both panes edit
    // the same buffer, exactly as Notepad++'s Clone to Other View does.
    [self.secondaryView message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)doc.docPointer];
    self.secondaryDocument = doc;
    // The pane just received its first document: give it style definitions
    // (the applyTheme wrapper styles both panes once a secondary document is set).
    [self applyTheme];
    if (folds.count) [self foldLines:folds];
    return YES;
}

- (BOOL)restoreLastClosedFile {
    NSString *last = [self recentFiles].firstObject;
    if (!last.length) { NppBeep(); return NO; }
    return [self openFileAtPath:last error:NULL];
}

- (NSUInteger)openAllRecentFiles {
    NSUInteger opened = 0;
    for (NSString *path in [[self recentFiles] copy]) {
        if ([self openFileAtPath:path error:NULL]) opened++;
    }
    return opened;
}

- (BOOL)moveCurrentToOtherView {
    if (self.documents.count < 2) {
        // Moving the only tab away would leave the primary pane empty.
        if (![self cloneCurrentToOtherView]) return NO;
        return YES;
    }
    NppDocument *doc = self.currentDocument;
    if (![self cloneCurrentToOtherView]) return NO;
    NSInteger idx = [self.documents indexOfObject:doc];
    if (idx != NSNotFound) [self closeDocumentAtIndex:idx discardChanges:YES];
    return YES;
}

- (BOOL)syncVerticalScroll { return self.syncV; }
- (void)setSyncVerticalScroll:(BOOL)on { self.syncV = on; if (on) [self mirrorScrollToSecondary]; }
- (BOOL)syncHorizontalScroll { return self.syncH; }
- (void)setSyncHorizontalScroll:(BOOL)on { self.syncH = on; if (on) [self mirrorScrollToSecondary]; }
- (BOOL)syncZoom { return self.syncZ; }
- (void)setSyncZoom:(BOOL)on { self.syncZ = on; if (on) [self mirrorZoomToSecondary]; }

/// One pane's scroll (and zoom) put on the other, where it differs: setting the
/// same value again still sends SCN_UPDATEUI, which would echo back.
static void MirrorView(ScintillaView *from, ScintillaView *to, BOOL lines, BOOL columns, BOOL zoom) {
    if (lines) {
        long v = [from message:SCI_GETFIRSTVISIBLELINE];
        if ([to message:SCI_GETFIRSTVISIBLELINE] != v) [to message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)v lParam:0];
    }
    if (columns) {
        long v = [from message:SCI_GETXOFFSET];
        if ([to message:SCI_GETXOFFSET] != v) [to message:SCI_SETXOFFSET wParam:(uptr_t)v lParam:0];
    }
    if (zoom) {
        long v = [from message:SCI_GETZOOM];
        if ([to message:SCI_GETZOOM] != v) [to message:SCI_SETZOOM wParam:(uptr_t)v lParam:0];
    }
}

- (void)mirrorScrollToSecondary {
    if (![self secondaryViewVisible]) return;
    MirrorView(self.sciView, self.secondaryView, self.syncV, self.syncH, NO);
}

- (void)mirrorScrollFromSecondary {
    if (![self secondaryViewVisible]) return;
    MirrorView(self.secondaryView, self.sciView, self.syncV, self.syncH, NO);
}

- (void)mirrorZoomToSecondary {
    if ([self secondaryViewVisible] && self.syncZ) MirrorView(self.sciView, self.secondaryView, NO, NO, YES);
}

- (void)mirrorZoomFromSecondary {
    if ([self secondaryViewVisible] && self.syncZ) MirrorView(self.secondaryView, self.sciView, NO, NO, YES);
}

#pragma mark - Document Map

- (BOOL)documentMapVisible { return [[NppDockingManager shared] isPanelVisible:@"documentMap"]; }

- (void)setDocumentMapVisible:(BOOL)visible {
    if (visible == [self documentMapVisible]) return;
    if (!visible) {
        [[NppDockingManager shared] hidePanel:@"documentMap"];
        return;
    }
    if (!self.docMapView) {
        self.docMapView = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 120, 400)];
        // A shrunken, read-only, chrome-less mirror of the buffer.
        [self.docMapView message:SCI_SETZOOM wParam:(uptr_t)-8 lParam:0];
        [self.docMapView message:SCI_SETREADONLY wParam:1 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:0 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:1 lParam:0];
        [self.docMapView message:SCI_SETMARGINWIDTHN wParam:2 lParam:0];
        [self.docMapView message:SCI_SETHSCROLLBAR wParam:0 lParam:0];
        [self.docMapView message:SCI_SETVSCROLLBAR wParam:0 lParam:0];
        self.docMapHost = [[NSView alloc] initWithFrame:self.docMapView.frame];
        self.docMapHost.wantsLayer = YES;
        self.docMapHost.layer.masksToBounds = YES;
        self.docMapView.autoresizingMask = NSViewHeightSizable;
        [self.docMapHost addSubview:self.docMapView];
        // Docked, floated or resized: the map and its zone are worked out again.
        self.docMapHost.postsFrameChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentMapFrameChanged:)
                                                     name:NSViewFrameDidChangeNotification object:self.docMapHost];
    }
    [self.docMapView message:SCI_SETDOCPOINTER wParam:0
                      lParam:(sptr_t)self.currentDocument.docPointer];
    NppDockingManager *dock = [NppDockingManager shared];
    if (![dock hasPanel:@"documentMap"]) {
        [dock registerPanel:@"documentMap" title:@"Document Map" view:self.docMapHost defaultPlace:NppDockRight];
    }
    [dock showPanel:@"documentMap"];
    if (!self.docMapZone) {
        self.docMapZone = [[NppMapZoneView alloc] initWithFrame:self.docMapView.bounds];
        self.docMapZone.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        __weak __typeof(self) weakSelf = self;
        self.docMapZone.scrollTo = ^(CGFloat y) { [weakSelf scrollFromDocumentMapAtY:y]; };
        self.docMapZone.wheel = ^(NSEvent *e) { [weakSelf.sciView scrollWheel:e]; };
    }
    self.docMapZone.frame = self.docMapView.bounds;
    [self.docMapView addSubview:self.docMapZone positioned:NSWindowAbove relativeTo:nil];
    [self mirrorStylesToDocumentMap];
    [self.docMapView layoutSubtreeIfNeeded];
    [self updateDocumentMap];
}

/// Makes the map look like the editor: the same colours per style (the
/// styling itself is in the shared document) and the same wrapping.
- (void)mirrorStylesToDocumentMap {
    ScintillaView *map = self.docMapView, *sci = self.sciView;
    if (!map) return;
    for (int st = 0; st <= STYLE_MAX; ++st) {
        [map message:SCI_STYLESETFORE wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETFORE wParam:(uptr_t)st]];
        [map message:SCI_STYLESETBACK wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETBACK wParam:(uptr_t)st]];
        [map message:SCI_STYLESETBOLD wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETBOLD wParam:(uptr_t)st]];
        [map message:SCI_STYLESETITALIC wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETITALIC wParam:(uptr_t)st]];
        [map message:SCI_STYLESETSIZE wParam:(uptr_t)st lParam:[sci message:SCI_STYLEGETSIZE wParam:(uptr_t)st]];
    }
    [map message:SCI_SETWRAPMODE wParam:(uptr_t)[sci message:SCI_GETWRAPMODE] lParam:0];
    NppStyle *zone = [StyleCatalog sharedCatalog].globalStyles[@"Document map"];
    self.docMapZone.colour = zone.foreground ?: [NSColor systemOrangeColor];
}

/// DocumentMap::scrollMap and the view zone: the map follows the editor so
/// the zone is in sight, and the zone covers the lines the editor shows.
/// The map is as wide as its panel; wrapped, it is as wide as the editor's
/// text is in the map's own small characters, so both wrap at the same words.
- (void)layoutDocumentMap {
    ScintillaView *map = self.docMapView, *sci = self.sciView;
    if (!map || !self.docMapHost) return;
    CGFloat width = NSWidth(self.docMapHost.bounds);
    if ([sci message:SCI_GETWRAPMODE] != SC_WRAP_NONE) {
        // What the editor's text has: the visible part of its content view. The
        // number, bookmark and fold margins are a view of their own beside it,
        // so they are not in this width and are not taken off it.
        CGFloat text = NSWidth(sci.scrollView.contentView.bounds);
        text -= (CGFloat)([sci message:SCI_GETMARGINLEFT] + [sci message:SCI_GETMARGINRIGHT]);
        // Long and mixed: the widths come back as whole pixels, and the map's characters are under two wide.
        const char *probe = "The quick brown fox jumps over the lazy dog 0123456789 {}[]();,. int main(void) return value == other; "
                            "the quick brown fox jumps over the lazy dog 0123456789 {}[]();,. int main(void) return value == other;";
        // Better still, the document's own words: where glyph advances are rounded
        // to whole pixels, the ratio depends on which characters are measured.
        long firstLine = [sci message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)[sci message:SCI_GETFIRSTVISIBLELINE]];
        long from = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)firstLine];
        long to = MIN([sci message:SCI_GETLENGTH], from + 400);
        NSMutableData *own = [NSMutableData dataWithLength:(NSUInteger)MAX(0, to - from) + 1];
        if (to - from >= 120) {
            Sci_TextRangeFull range = {{(Sci_Position)from, (Sci_Position)to}, (char *)own.mutableBytes};
            [sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
            // One line of it: tabs and line ends measure differently from text.
            char *bytes = (char *)own.mutableBytes;
            for (long k = 0; k < to - from; ++k) if (bytes[k] == '\n' || bytes[k] == '\r' || bytes[k] == '\t') bytes[k] = ' ';
            // Not cut inside a UTF-8 character.
            long end = to - from;
            while (end > 0 && ((unsigned char)bytes[end - 1] & 0xC0) == 0x80) end--;
            if (end > 0 && ((unsigned char)bytes[end - 1] & 0x80)) end--;
            bytes[end] = 0;
            if (end >= 100) probe = bytes;
        }
        double inEditor = (double)[sci message:SCI_TEXTWIDTH wParam:STYLE_DEFAULT lParam:(sptr_t)probe];
        double inMap = (double)[map message:SCI_TEXTWIDTH wParam:STYLE_DEFAULT lParam:(sptr_t)probe];
        if (text > 0 && inEditor > 0 && inMap > 0) {
            width = ceil(text * inMap / inEditor) + (CGFloat)([map message:SCI_GETMARGINLEFT] + [map message:SCI_GETMARGINRIGHT]);
        }
        [map message:SCI_SETWRAPINDENTMODE wParam:(uptr_t)[sci message:SCI_GETWRAPINDENTMODE] lParam:0];
    }
    NSRect wanted = NSMakeRect(0, 0, MAX(1, width), NSHeight(self.docMapHost.bounds));
    if (!NSEqualRects(map.frame, wanted)) map.frame = wanted;
}

- (void)updateDocumentMap {
    if (![self documentMapVisible]) return;
    [self layoutDocumentMap];
    ScintillaView *map = self.docMapView, *sci = self.sciView;
    long first = [sci message:SCI_GETFIRSTVISIBLELINE];
    long onScreen = [sci message:SCI_LINESONSCREEN];
    long total = [sci message:SCI_GETLINECOUNT];
    long firstDoc = [sci message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)first];
    long lastDoc = [sci message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)(first + onScreen)];

    long mapOnScreen = [map message:SCI_LINESONSCREEN];
    long mapVisibleTotal = [map message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)total];
    long mainScrollable = MAX(1, [sci message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)total] - onScreen);
    long mapScrollable = MAX(0, mapVisibleTotal - mapOnScreen);
    long mapFirst = mapScrollable > 0 ? (long)((double)first / (double)mainScrollable * (double)mapScrollable) : 0;
    [map message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)MAX(0, MIN(mapFirst, mapScrollable)) lParam:0];

    long height = [map message:SCI_TEXTHEIGHT wParam:0];
    long topVisible = [map message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)firstDoc] - [map message:SCI_GETFIRSTVISIBLELINE];
    long bottomVisible = [map message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)MIN(lastDoc, total)] - [map message:SCI_GETFIRSTVISIBLELINE];
    self.docMapZone.zone = NSMakeRect(0, (CGFloat)(topVisible * height), NSWidth(self.docMapZone.bounds),
                                      (CGFloat)(MAX(1, bottomVisible - topVisible) * height));
    [self.docMapZone setNeedsDisplay:YES];
}

- (NSRect)documentMapZone { return self.docMapZone.zone; }

- (void)documentMapFrameChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateDocumentMap]; });
}

/// A click or drag at `y` in the map centres the editor on that line.
- (void)scrollFromDocumentMapAtY:(CGFloat)y {
    ScintillaView *map = self.docMapView, *sci = self.sciView;
    long height = MAX(1, [map message:SCI_TEXTHEIGHT wParam:0]);
    long mapVisible = [map message:SCI_GETFIRSTVISIBLELINE] + (long)(y / (CGFloat)height);
    long docLine = [map message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)MAX(0, mapVisible)];
    long onScreen = [sci message:SCI_LINESONSCREEN];
    long target = [sci message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)docLine] - onScreen / 2;
    [sci message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)MAX(0, target) lParam:0];
    [self updateDocumentMap];
}

#pragma mark - Project panels

- (NSInteger)activeProjectPanel { return self.activeProject; }

- (NppProjectPanel *)projectPanel:(NSInteger)index {
    if (index < 1 || index > 3) return nil;
    return self.projects[(NSUInteger)(index - 1)];
}

- (BOOL)confirmDiscardingProjectChanges {
    for (NppProjectPanel *p in self.projects) {
        if (![p confirmDiscardingChanges]) return NO;
    }
    return YES;
}

- (void)showProjectPanel:(NSInteger)index {
    if (index < 1 || index > 3) return;
    NppProjectPanel *panel = self.projects[(NSUInteger)(index - 1)];
    // The workspace the panel had last time comes back the first time it opens.
    if (!panel.workspacePath && !panel.root.children.count) {
        NSString *last = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"NppMac.projectWorkspaces"]
                         [[@(index) stringValue]];
        if (last.length && [[NSFileManager defaultManager] fileExistsAtPath:last]) [panel openWorkspace:last];
    }

    NSString *ident = [NSString stringWithFormat:@"project%ld", (long)index];
    NppDockingManager *dock = [NppDockingManager shared];
    if (self.activeProject == index && [dock isPanelVisible:ident]) {   // same panel again hides it
        self.activeProject = 0;
        [dock hidePanel:ident];
        return;
    }
    // Each project panel is a dockable panel of its own, as upstream's are;
    // several can be open, as tabs of one dock.
    self.activeProject = index;
    [dock showPanel:ident];
}

/// Notepad++ opens a second process; `open -n` is the macOS equivalent.
- (BOOL)openCurrentInNewInstanceMoving:(BOOL)closeHere {
    NppDocument *doc = self.currentDocument;
    if (!doc.path) { NppBeep(); return NO; }
    NSURL *bundle = [[NSBundle mainBundle] bundleURL];
    NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];
    config.createsNewApplicationInstance = YES;
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:doc.path]]
                       withApplicationAtURL:bundle
                              configuration:config
                          completionHandler:nil];
    if (closeHere) [self closeDocumentAtIndex:self.currentIndex discardChanges:YES];
    return YES;
}

#pragma mark - ScintillaNotificationProtocol

- (void)notification:(SCNotification *)n {
    switch (n->nmhdr.code) {
        case SCN_SAVEPOINTREACHED:
            self.currentDocument.modified = self.currentDocument.encodingChanged;
            [self refreshChrome];
            break;
        case SCN_SAVEPOINTLEFT:    self.currentDocument.modified = YES; [self refreshChrome]; break;
        case SCN_MARGINCLICK: {
            long line = [self.sciView message:SCI_LINEFROMPOSITION wParam:(uptr_t)n->position lParam:0];
            if (n->margin == 5) [self compareRevertChangeAtLine:line];          // Compare's revert margin
            else if (n->margin == 1) {                                           // the bookmark margin, as on Windows
                long has = [self.sciView message:SCI_MARKERGET wParam:(uptr_t)line lParam:0] & (1 << NPPMAC_BOOKMARK_MARKER);
                [self.sciView message:has ? SCI_MARKERDELETE : SCI_MARKERADD wParam:(uptr_t)line lParam:NPPMAC_BOOKMARK_MARKER];
            }
            break;
        }
        case SCN_ZOOM:
            [self mirrorZoomToSecondary];
            break;
        case SCN_UPDATEUI:
            [self refreshChrome];
            if (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_CONTENT)) [self updateDocumentMap];
            if (n->updated & SC_UPDATE_CONTENT) {
                [self gitScheduleMarkerRefresh];       // the git margin follows the text
                [self compareScheduleRefresh];         // and so does a comparison that is on
            }
            if (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_CONTENT)) [self updateLineNumberWidth];
            if (n->updated & (SC_UPDATE_V_SCROLL | SC_UPDATE_H_SCROLL)) [self mirrorScrollToSecondary];
            [self updateBraceMatch];
            if (n->updated & SC_UPDATE_SELECTION) [self updateSmartHighlight];
            if (n->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)) [self highlightMatchingTags];
            if (n->updated & (SC_UPDATE_CONTENT | SC_UPDATE_V_SCROLL)) [self scheduleSpellCheck];
            break;
        case SCN_CHARADDED:
            [self handleCharacterAdded:n->ch];
            break;
        case SCN_AUTOCSELECTION:
            // NppNotification's SCN_AUTOCSELECTION: with "Insert Selection: TAB" off, Tab
            // closes the list and is a Tab (SETTINGS-064).
            if (n->listCompletionMethod == SC_AC_TAB && ![NppPreferences shared].autoCompleteUseTab) {
                [self.sci message:SCI_AUTOCCANCEL];
                [self.sci message:SCI_TAB];
            }
            break;
        case SCN_CALLTIPCLICK:
            [self callTipClicked:(long)n->position];
            break;
        case SCN_INDICATORRELEASE:
            [self openLinkAtPosition:(long)n->position];
            break;
        case SCN_DOUBLECLICK:
            // In the results tab a double click means "take me there", the way
            // it does in Notepad++'s Search results panel. It waits for the
            // turn of the run loop after this one: Scintilla is in the middle
            // of the click, and switching the document under it leaves it
            // finishing the click on the file just opened, which puts the caret
            // back wherever the pointer happened to be.
            if (n->modifiers == SCMOD_CTRL && !self.currentDocument.isSearchResults) {
                // Cmd+double-click. After Scintilla has finished the click, which
                // selects the word under it once the notification returns.
                long at = (long)n->position;
                if (at < 0) at = [self.sci message:SCI_GETCURRENTPOS];
                dispatch_async(dispatch_get_main_queue(), ^{ [self selectBetweenDelimitersAt:at]; });
                break;
            }
            {
                dispatch_async(dispatch_get_main_queue(), ^{ [self openSearchResultAtCaret]; });
            }
            break;
        case SCN_MACRORECORD:
            [self recordMacroMessage:(int)n->message
                              wParam:(unsigned long)n->wParam
                              lParam:(long)n->lParam];
            break;
        default: break;
    }
}

@end
