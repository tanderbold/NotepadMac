#import "ViewCommands.h"
#import "EditorLook.h"
#import "SettingsCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

@implementation EditorController (ViewCommands)

#pragma mark - Tabs

- (BOOL)selectTabNumber:(NSInteger)oneBased {
    NSInteger idx = oneBased - 1;
    if (idx < 0 || idx >= (NSInteger)self.mainViewDocuments.count) { NppBeep(); return NO; }
    [self selectDocumentAtIndex:idx];
    return YES;
}

- (void)goToFirstTab { [self selectDocumentAtIndex:0]; }
// The main view's tabs: the second view's own come after them in documents.
- (void)goToLastTab  { [self selectDocumentAtIndex:(NSInteger)self.mainViewDocuments.count - 1]; }

- (void)goToNextTab {
    NSInteger n = (NSInteger)self.mainViewDocuments.count;
    if (n < 2) return;
    NSInteger cur = [self.documents indexOfObject:self.currentDocument];
    [self selectDocumentAtIndex:(cur + 1) % n];
}

- (void)goToPreviousTab {
    NSInteger n = (NSInteger)self.mainViewDocuments.count;
    if (n < 2) return;
    NSInteger cur = [self.documents indexOfObject:self.currentDocument];
    [self selectDocumentAtIndex:(cur - 1 + n) % n];
}

/// The run of tabs a document may move within: pinned tabs stay first, as a group
/// of their own, and an unpinned tab never goes in among them (Notepad++'s
/// tab bar keeps the pinned tabs on the left).
- (NSRange)tabRunOfDocument:(NppDocument *)doc {
    NSUInteger pinned = 0, tabs = self.mainViewDocuments.count;   // the main view's tabs
    for (NppDocument *d in self.mainViewDocuments) { if (!d.pinned) break; ++pinned; }
    if (doc.secondViewOnly) return NSMakeRange(0, 0);
    return doc.pinned ? NSMakeRange(0, pinned) : NSMakeRange(pinned, tabs - pinned);
}

- (BOOL)moveCurrentTab:(BOOL)forward {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NSInteger from = [docs indexOfObject:self.currentDocument];
    NSInteger to = from + (forward ? 1 : -1);
    NSRange run = [self tabRunOfDocument:self.currentDocument];
    if (from == NSNotFound || to < (NSInteger)run.location || to >= (NSInteger)NSMaxRange(run)) { NppBeep(); return NO; }
    [docs exchangeObjectAtIndex:(NSUInteger)from withObjectAtIndex:(NSUInteger)to];
    [self selectDocumentAtIndex:to];
    return YES;
}

- (void)moveCurrentTabToEnd:(BOOL)end {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NppDocument *doc = self.currentDocument;
    NSInteger from = [docs indexOfObject:doc];
    NSRange run = [self tabRunOfDocument:doc];
    if (from == NSNotFound || !run.length) return;
    [docs removeObjectAtIndex:(NSUInteger)from];
    NSInteger to = end ? (NSInteger)NSMaxRange(run) - 1 : (NSInteger)run.location;
    [docs insertObject:doc atIndex:(NSUInteger)to];
    [self selectDocumentAtIndex:to];
}

- (void)setTabColour:(NSInteger)colour {
    self.currentDocument.tabColour = colour;
    [self refreshChrome];
}

#pragma mark - Fold levels

/// Contracts or expands every fold header whose level equals `level`.
- (void)applyFoldLevel:(NSInteger)level expanded:(BOOL)expanded {
    ScintillaView *sci = self.sci;
    [sci message:SCI_COLOURISE wParam:0 lParam:-1];
    long total = [sci message:SCI_GETLINECOUNT];
    for (long line = 0; line < total; ++line) {
        long fold = [sci message:SCI_GETFOLDLEVEL wParam:(uptr_t)line];
        if (!(fold & SC_FOLDLEVELHEADERFLAG)) continue;
        long depth = (fold & SC_FOLDLEVELNUMBERMASK) - SC_FOLDLEVELBASE;
        if (depth != level - 1) continue;
        BOOL isExpanded = [sci message:SCI_GETFOLDEXPANDED wParam:(uptr_t)line] != 0;
        if (isExpanded != expanded) [sci message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
    }
    [self refreshChrome];
}

- (void)foldToLevel:(NSInteger)level   { [self applyFoldLevel:level expanded:NO]; }
- (void)unfoldToLevel:(NSInteger)level { [self applyFoldLevel:level expanded:YES]; }

#pragma mark - Symbols

- (BOOL)symbolVisible:(NppSymbol)symbol {
    ScintillaView *sci = self.sci;
    switch (symbol) {
        case NppSymbolWhitespace:  return [sci message:SCI_GETVIEWWS] != SCWS_INVISIBLE;
        case NppSymbolEOL:         return [sci message:SCI_GETVIEWEOL] != 0;
        case NppSymbolNonPrinting: return [NppPreferences shared].npcShow;
        case NppSymbolControlAndUnicodeEOL: return [NppPreferences shared].ccUniEolShow;
        case NppSymbolIndentGuide: return [sci message:SCI_GETINDENTATIONGUIDES] != SC_IV_NONE;
        case NppSymbolWrap:        return [sci message:SCI_GETWRAPVISUALFLAGS] != SC_WRAPVISUALFLAG_NONE;
        case NppSymbolAll:
            return [self symbolVisible:NppSymbolWhitespace] && [self symbolVisible:NppSymbolEOL] &&
                   [self symbolVisible:NppSymbolNonPrinting] && [self symbolVisible:NppSymbolControlAndUnicodeEOL];
    }
    return NO;
}

- (void)applySymbolsToView:(ScintillaView *)sci {
    NppPreferences *p = [NppPreferences shared];
    [sci message:SCI_SETVIEWWS wParam:(uptr_t)(p.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
    [sci message:SCI_SETVIEWEOL wParam:p.showEOL ? 1 : 0 lParam:0];
    [sci message:SCI_SETINDENTATIONGUIDES wParam:(uptr_t)(p.showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
    [sci message:SCI_SETWRAPVISUALFLAGS
           wParam:(uptr_t)(p.showWrapSymbol ? SC_WRAPVISUALFLAG_END : SC_WRAPVISUALFLAG_NONE) lParam:0];
    [self applySymbolRepresentationsTo:sci];
}

- (void)toggleSymbol:(NppSymbol)symbol {
    // The preference first, so that nothing applied later puts the old state
    // back, then both views (Notepad_plus::command IDM_VIEW_* sets both).
    NppPreferences *p = [NppPreferences shared];
    BOOL on = [self symbolVisible:symbol];
    switch (symbol) {
        case NppSymbolWhitespace:           p.showWhitespace = !on; break;
        case NppSymbolEOL:                  p.showEOL = !on; break;
        case NppSymbolNonPrinting:          p.npcShow = !on; break;
        case NppSymbolControlAndUnicodeEOL: p.ccUniEolShow = !on; break;
        case NppSymbolIndentGuide:          p.showIndentGuides = !on; break;
        case NppSymbolWrap:                 p.showWrapSymbol = !on; break;
        case NppSymbolAll:
            // IDM_VIEW_ALL_CHARACTERS: the four invisible-character symbols together.
            p.showWhitespace = p.showEOL = p.npcShow = p.ccUniEolShow = !on;
            break;
    }
    [self applySymbolsToView:self.sci];
    if (self.secondarySci) [self applySymbolsToView:self.secondarySci];
    [self refreshChrome];
}

#pragma mark - Hide lines

- (BOOL)hideSelectedLines {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    long first = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)a];
    long last  = [sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)b];
    if (last < first) return NO;
    [sci message:SCI_HIDELINES wParam:(uptr_t)first lParam:last];
    [self refreshChrome];
    return YES;
}

- (void)showAllHiddenLines {
    ScintillaView *sci = self.sci;
    // The last line is inclusive: Scintilla refuses a range that ends past the document
    // (ContractionState::SetVisible), and nothing was shown again.
    [sci message:SCI_SHOWLINES wParam:0 lParam:[sci message:SCI_GETLINECOUNT] - 1];
    [self refreshChrome];
}

#pragma mark - Text direction

- (void)setTextDirectionRTL:(BOOL)rtl {
    [self.sci message:SCI_SETBIDIRECTIONAL
               wParam:(uptr_t)(rtl ? SC_BIDIRECTIONAL_R2L : SC_BIDIRECTIONAL_L2R) lParam:0];
    [self refreshChrome];
}

- (BOOL)textDirectionIsRTL {
    return [self.sci message:SCI_GETBIDIRECTIONAL] == SC_BIDIRECTIONAL_R2L;
}

#pragma mark - Summary

- (NSDictionary<NSString *, NSNumber *> *)documentSummary {
    ScintillaView *sci = self.sci;
    NSString *text = [sci string] ?: @"";
    // A word is a run of anything that is not one of these, which is the set
    // Notepad_plus::wordCount searches with. Splitting on every non-alphanumeric
    // instead, as this did, counts foo_bar as two words and a_b#c as three.
    NSUInteger words = 0;
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSCharacterSet *sep = [NSCharacterSet characterSetWithCharactersInString:
                           @" \t\\.,;:!?()+\r\n-*/=][{}&~\"'`|@$%<>^"];
    while (!scanner.isAtEnd) {
        if ([scanner scanUpToCharactersFromSet:sep intoString:NULL]) words++;
        [scanner scanCharactersFromSet:sep intoString:NULL];
    }
    return @{@"characters": @(text.length),
             @"bytes":      @([sci message:SCI_GETLENGTH]),
             @"lines":      @([sci message:SCI_GETLINECOUNT]),
             @"words":      @(words),
             @"selected":   @([sci message:SCI_GETSELECTIONEND] - [sci message:SCI_GETSELECTIONSTART])};
}

#pragma mark - External viewers

- (BOOL)openCurrentInBrowserBundleID:(NSString *)bundleID {
    NSString *path = self.currentDocument.path;
    if (!path.length) return NO;
    NSURL *app = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bundleID];
    if (!app) return NO;
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:path]]
                       withApplicationAtURL:app
                              configuration:[NSWorkspaceOpenConfiguration configuration]
                          completionHandler:nil];
    return YES;
}

#pragma mark - Monitoring (tail -f)

- (BOOL)monitoringEnabled { return self.currentDocument.monitoring; }

/// IDM_VIEW_MONITORING for the document in front: refused for a file with
/// unsaved changes or none on disk, as upstream refuses it.
- (void)setMonitoring:(BOOL)on {
    NppDocument *doc = self.currentDocument;
    if (!doc) return;
    if (!on) { [self stopMonitoringDocument:doc]; [self refreshChrome]; return; }
    if (doc.monitoring) return;
    if (!doc.path.length || ![[NSFileManager defaultManager] fileExistsAtPath:doc.path] || doc.modified) { NppBeep(); return; }
    [self startMonitoringDocument:doc];
    [self refreshChrome];
}

- (void)startMonitoringDocument:(NppDocument *)doc {
    int fd = open(doc.path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) { NppBeep(); return; }
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
        dispatch_get_main_queue());
    __weak EditorController *weakSelf = self;
    __weak NppDocument *weakDoc = doc;
    dispatch_source_set_event_handler(src, ^{
        EditorController *me = weakSelf;
        NppDocument *watched = weakDoc;
        if (!me || !watched) return;
        if (dispatch_source_get_data(src) & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) {
            // A log that is rotated is moved away and made again under the
            // same name: the name is what is followed, so it is waited for.
            [me awaitMonitoredFileOf:watched];
            return;
        }
        [me monitoredDocumentChanged:watched];
    });
    dispatch_source_set_cancel_handler(src, ^{ close(fd); });
    dispatch_resume(src);
    doc.monitorSource = src;
    doc.monitoring = YES;
    // The user's read-only, as upstream sets it while monitoring.
    if (doc == self.currentDocument) [self.sci message:SCI_SETREADONLY wParam:1 lParam:0];
}

- (void)awaitMonitoredFileOf:(NppDocument *)doc {
    if (doc.monitorSource) dispatch_source_cancel((dispatch_source_t)doc.monitorSource);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                              (uint64_t)(0.5 * NSEC_PER_SEC), (uint64_t)(0.1 * NSEC_PER_SEC));
    __weak EditorController *weakSelf = self;
    __weak NppDocument *weakDoc = doc;
    dispatch_source_set_event_handler(timer, ^{
        EditorController *me = weakSelf;
        NppDocument *watched = weakDoc;
        if (!me || !watched || !watched.monitoring) { dispatch_source_cancel(timer); return; }
        if (![[NSFileManager defaultManager] fileExistsAtPath:watched.path]) return;
        dispatch_source_cancel(timer);
        watched.monitorSource = nil;
        [me startMonitoringDocument:watched];
        [me monitoredDocumentChanged:watched];
    });
    dispatch_resume(timer);
    doc.monitorSource = timer;
}

- (void)stopMonitoringDocument:(NppDocument *)doc {
    if (doc.monitorSource) dispatch_source_cancel((dispatch_source_t)doc.monitorSource);
    doc.monitorSource = nil;
    doc.monitorReloadPending = NO;
    if (!doc.monitoring) return;
    doc.monitoring = NO;
    if (doc == self.currentDocument) {
        BOOL writable = !doc.path || [[NSFileManager defaultManager] isWritableFileAtPath:doc.path];
        [self.sci message:SCI_SETREADONLY wParam:writable ? 0 : 1 lParam:0];
    }
}

/// The file grew or changed: reloaded at once when in front, and followed to
/// its end; otherwise when it next comes to the front.
- (void)monitoredDocumentChanged:(NppDocument *)doc {
    if (doc != self.currentDocument) { doc.monitorReloadPending = YES; return; }
    doc.monitorReloadPending = NO;
    [self.sci message:SCI_SETREADONLY wParam:0 lParam:0];
    [self reloadCurrentDocument:NULL];
    [self.sci message:SCI_SETREADONLY wParam:1 lParam:0];
    [self.sci message:SCI_DOCUMENTEND];
}

- (void)catchUpMonitoredDocument {
    NppDocument *doc = self.currentDocument;
    if (doc.monitoring && doc.monitorReloadPending) [self monitoredDocumentChanged:doc];
}

@end
