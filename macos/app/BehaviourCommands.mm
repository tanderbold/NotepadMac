#import "BehaviourCommands.h"
#include <string>
#import "SettingsCommands.h"
#import "SearchCommands.h"
#import "AdvancedEditCommands.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

static long Utf8Len(NSString *s) {
    return (long)[s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

@implementation EditorController (BehaviourCommands)

#pragma mark - Large file restriction

- (BOOL)largeFileRestrictionActive {
    NppPreferences *p = [NppPreferences shared];
    if (!p.largeFileRestrictionEnabled) return NO;
    long bytes = [self.sci message:SCI_GETLENGTH];
    return bytes > (long)p.largeFileThresholdMB * 1024 * 1024;
}

/// Notepad++ turns features off above a size threshold so large files stay
/// usable. The same switches are flipped here, and turned back on below it.
- (void)applyPerformanceRestrictions {
    NppPreferences *p = [NppPreferences shared];
    ScintillaView *sci = self.sci;
    BOOL restricted = [self largeFileRestrictionActive];

    if (restricted) {
        [sci message:SCI_SETILEXER wParam:0 lParam:0];          // no syntax highlighting
        if (p.largeFileDeactivateWordWrap) {
            [sci message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
        }
        [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_LINK_INDICATOR lParam:0];
        [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
    } else {
        [self applyLanguage];
    }
    [self refreshChrome];
}

/// Each feature asks whether it is allowed before doing work.
- (BOOL)featureAllowed:(NSString *)name {
    NppPreferences *p = [NppPreferences shared];
    if (![self largeFileRestrictionActive]) return YES;
    if ([name isEqualToString:@"autocompletion"]) return p.largeFileAllowAutoCompletion;
    if ([name isEqualToString:@"smartHighlight"]) return p.largeFileAllowSmartHighlighting;
    if ([name isEqualToString:@"braceMatch"])     return p.largeFileAllowBraceMatch;
    if ([name isEqualToString:@"links"])          return p.largeFileAllowClickableLinks;
    return YES;
}

#pragma mark - Clickable links

- (void)configureLinkIndicator {
    ScintillaView *sci = self.sci;
    NppPreferences *p = [NppPreferences shared];
    [sci message:SCI_INDICSETSTYLE wParam:NPPMAC_LINK_INDICATOR
           lParam:p.linksFullBox ? INDIC_ROUNDBOX : (p.linksNoUnderline ? INDIC_HIDDEN : INDIC_PLAIN)];
    [sci message:SCI_INDICSETFORE wParam:NPPMAC_LINK_INDICATOR lParam:0xFF0000];   // BGR blue
    [sci message:SCI_INDICSETALPHA wParam:NPPMAC_LINK_INDICATOR lParam:60];
    [sci message:SCI_INDICSETUNDER wParam:NPPMAC_LINK_INDICATOR lParam:1];
}

/// Schemes to recognise: the standard ones plus whatever the user added.
- (NSArray<NSString *> *)linkSchemes {
    NSMutableArray *schemes = [NSMutableArray arrayWithArray:@[@"https", @"http", @"ftp", @"mailto", @"file"]];
    for (NSString *extra in [[NppPreferences shared].linkCustomSchemes
                             componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@" ,;"]]) {
        NSString *t = [extra stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length && ![schemes containsObject:t]) [schemes addObject:t];
    }
    return schemes;
}

/// The characters a scheme can start with.
static BOOL UrlSchemeStartChar(unichar c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

/// What may stand immediately before a scheme. A letter, digit or underscore
/// may not, which is why "xhttp://y" is not a link.
///
/// Upstream tests only the ASCII ranges here, so "ähttp://test.com" and
/// "домhttp://test.com" come out as links; both sit in its own file of cases it
/// says could be handled better. Any letter counts here, which settles them.
static BOOL UrlSchemeDelimiter(unichar c) {
    if (c == '_') return NO;
    NSCharacterSet *wordLike = [NSCharacterSet alphanumericCharacterSet];
    return ![wordLike characterIsMember:c];
}

/// Whether the character belongs to the body of a URL rather than ending it.
static BOOL UrlTextChar(unichar c) {
    if (c <= ' ') return NO;
    switch (c) {
        case 0x00A0: case 0x2002: case 0x2003: case 0x3000: case 0x2004:
        case 0x2005: case 0x2006: case 0x2007: case 0x2008: case 0x2009:
        case 0x200A: case 0x202F: case 0x205F: case 0xFEFF: case 0x200B:
            return NO;                       // the spaces of other writing systems
        case '"': case '#': case '<': case '>': case '{': case '}': case '?':
        case 0x007F:
            return NO;
        default: return YES;
    }
}

static BOOL UrlQueryDelimiter(unichar c) {
    return c == '&' || c == '+' || c == '=' || c == ';';
}

/// Finds the next scheme at or after `start`. Returns NSNotFound when there is
/// none; otherwise the index where it begins, with its length in `schemeLength`.
static NSUInteger ScanToUrlStart(NSString *text, NSUInteger start,
                                 NSArray<NSString *> *schemes, NSUInteger *schemeLength) {
    NSUInteger length = text.length, p = start, p0 = 0;
    BOOL inScheme = NO;
    while (p < length) {
        unichar c = [text characterAtIndex:p];
        if (!inScheme) {
            if (UrlSchemeStartChar(c) &&
                (p == 0 || UrlSchemeDelimiter([text characterAtIndex:p - 1]))) {
                p0 = p;
                inScheme = YES;
            }
        } else {
            if (c == ':') {
                for (NSString *scheme in schemes) {
                    NSUInteger n = scheme.length;
                    if (p0 + n > length) continue;
                    if ([[text substringWithRange:NSMakeRange(p0, n)]
                         caseInsensitiveCompare:scheme] == NSOrderedSame) {
                        *schemeLength = p - p0 + 1;
                        return p0;
                    }
                }
            }
            if (!UrlSchemeStartChar(c)) inScheme = NO;
        }
        p++;
    }
    *schemeLength = 0;
    return NSNotFound;
}

/// Walks from the end of the scheme to the end of the URL, keeping a loose grip
/// on what a query may look like, as upstream does.
static NSUInteger ScanToUrlEnd(NSString *text, NSUInteger start) {
    enum { sHostAndPath, sQuery, sAfterDelimiter, sQuotes, sAfterQuotes, sFragment };
    NSInteger state = sHostAndPath;
    unichar closing = 0;
    NSUInteger p = start, length = text.length;
    while (p < length) {
        unichar c = [text characterAtIndex:p];
        switch (state) {
            case sHostAndPath:
                if (c == '?') state = sQuery;
                else if (c == '#') state = sFragment;
                else if (!UrlTextChar(c)) return p - start;
                break;
            case sQuery:
                if (c == '#') state = sFragment;
                else if (UrlQueryDelimiter(c)) state = sAfterDelimiter;
                else if (!UrlTextChar(c)) return p - start;
                break;
            case sAfterDelimiter:
                if (c == '\'' || c == '"' || c == '`') { closing = c; state = sQuotes; }
                else if (c == '(') { closing = ')'; state = sQuotes; }
                else if (c == '[') { closing = ']'; state = sQuotes; }
                else if (c == '{') { closing = '}'; state = sQuotes; }
                else if (UrlTextChar(c)) state = sQuery;
                else return p - start;
                break;
            case sQuotes:
                if (c < ' ') return p - start;
                if (c == closing) state = sAfterQuotes;
                break;
            case sAfterQuotes:
                if (UrlQueryDelimiter(c)) state = sAfterDelimiter;
                else return p - start;
                break;
            case sFragment:
                if (c != '?' && !UrlTextChar(c)) return p - start;
                break;
        }
        p++;
    }
    return p - start;
}

/// Drops one trailing character that punctuation left behind. Called until it
/// stops changing anything.
static BOOL TrimOneTrailingUrlChar(NSString *text, NSUInteger start, NSUInteger *length) {
    if (*length <= 1) return NO;
    NSUInteger last = start + *length - 1;
    unichar c = [text characterAtIndex:last];

    if ([@".,:;?!#" rangeOfString:[NSString stringWithCharacters:&c length:1]].location != NSNotFound) {
        (*length)--;
        return YES;
    }
    // A closing bracket only counts as part of the URL when it has an opening
    // one inside the URL to answer to.
    NSString *closers = @")]", *openers = @"([";
    NSRange which = [closers rangeOfString:[NSString stringWithCharacters:&c length:1]];
    if (which.location == NSNotFound) return NO;
    unichar opener = [openers characterAtIndex:which.location];
    // Walk back looking for the bracket this one would close. If one is found,
    // the pair belongs to the URL and nothing is trimmed.
    //
    // A count that does not come out at zero also stops the trim, so one
    // unmatched bracket is dropped and two are kept. That reads oddly, and it is
    // what an open issue complains about, but the corpus states it as a decision
    // -- "arbitrary parentheses in path: keep last closing parenthesis" -- so it
    // stays as upstream has it.
    NSInteger count = 0;
    for (NSInteger j = (NSInteger)last - 1; j >= (NSInteger)start; --j) {
        unichar d = [text characterAtIndex:(NSUInteger)j];
        if (d == c) count++;
        if (d == opener) {
            if (count > 0) count--;
            else return NO;
        }
    }
    if (count != 0) return NO;
    (*length)--;
    return YES;
}

/// Upstream hands the candidate to InternetCrackUrl to say whether it is a URL
/// at all. The nearest thing here is asking Foundation to parse it and insisting
/// on the parts that must be there.
static BOOL UrlLooksReal(NSString *candidate) {
    NSURL *url = [NSURL URLWithString:candidate];
    if (!url.scheme.length) return NO;
    NSRange sep = [candidate rangeOfString:@"://"];
    if (sep.location != NSNotFound) return url.host.length > 0;
    // mailto: and the like: something has to follow the colon.
    NSRange colon = [candidate rangeOfString:@":"];
    return colon.location != NSNotFound && colon.location + 1 < candidate.length;
}

- (NSUInteger)markClickableLinks {
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_LINK_INDICATOR lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];

    if (![NppPreferences shared].linksEnabled || ![self featureAllowed:@"links"]) return 0;
    [self configureLinkIndicator];

    NSString *text = [sci string] ?: @"";
    // The schemes upstream accepts are written with their separator, and it is
    // matched: "http://" only counts followed by the slashes.
    NSMutableArray *schemes = [NSMutableArray arrayWithArray:
        @[@"ftp://", @"http://", @"https://", @"mailto:", @"file://"]];
    for (NSString *extra in [[NppPreferences shared].linkCustomSchemes
                             componentsSeparatedByCharactersInSet:
                             [NSCharacterSet characterSetWithCharactersInString:@" ,;"]]) {
        NSString *trimmed = [extra stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length && ![schemes containsObject:trimmed]) [schemes addObject:trimmed];
    }

    NSUInteger count = 0, at = 0;
    while (at < text.length) {
        NSUInteger schemeLength = 0;
        NSUInteger begin = ScanToUrlStart(text, at, schemes, &schemeLength);
        if (begin == NSNotFound) break;

        NSUInteger length = ScanToUrlEnd(text, begin + schemeLength);
        if (!length) { at = begin + MAX((NSUInteger)1, schemeLength); continue; }
        length += schemeLength;

        NSString *candidate = [text substringWithRange:NSMakeRange(begin, length)];
        if (!UrlLooksReal(candidate)) { at = begin + length; continue; }

        // A URL wrapped in quotes or back-ticks keeps neither.
        if (begin > 0 && length > 1) {
            unichar before = [text characterAtIndex:begin - 1];
            unichar last = [text characterAtIndex:begin + length - 1];
            if ((before == '\'' && last == '\'') || (before == '`' && last == '`')) length--;
        }
        while (TrimOneTrailingUrlChar(text, begin, &length)) { }

        long startByte = Utf8Len([text substringToIndex:begin]);
        long byteLength = Utf8Len([text substringWithRange:NSMakeRange(begin, length)]);
        [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)startByte lParam:byteLength];
        count++;
        at = begin + length;
    }
    return count;
}

- (NSString *)linkAtPosition:(long)position {
    ScintillaView *sci = self.sci;
    if (![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_LINK_INDICATOR lParam:position]) return nil;
    long start = [sci message:SCI_INDICATORSTART wParam:NPPMAC_LINK_INDICATOR lParam:position];
    long end = [sci message:SCI_INDICATOREND wParam:NPPMAC_LINK_INDICATOR lParam:position];
    if (end <= start) return nil;

    NSData *data = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if ((NSUInteger)end > data.length) return nil;
    return [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange((NSUInteger)start,
                                                                            (NSUInteger)(end - start))]
                                 encoding:NSUTF8StringEncoding];
}

- (BOOL)openLinkAtPosition:(long)position {
    NSString *link = [self linkAtPosition:position];
    if (!link.length) return NO;
    NSURL *url = [NSURL URLWithString:link];
    if (!url.scheme) return NO;
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

#pragma mark - Brace match

- (void)updateBraceMatch {
    ScintillaView *sci = self.sci;
    if (![NppPreferences shared].braceMatchEnabled || ![self featureAllowed:@"braceMatch"]) {
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
        return;
    }
    long pos = [sci message:SCI_GETCURRENTPOS];
    long candidate = pos;
    long match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)candidate lParam:0];
    if (match < 0 && pos > 0) {
        candidate = pos - 1;
        match = [sci message:SCI_BRACEMATCH wParam:(uptr_t)candidate lParam:0];
    }
    if (match < 0) {
        [sci message:SCI_BRACEBADLIGHT wParam:(uptr_t)-1 lParam:0];
        return;
    }
    [sci message:SCI_BRACEHIGHLIGHT wParam:(uptr_t)candidate lParam:match];
}

#pragma mark - Right click and the selection

- (void)contextClickAtWindowPoint:(NSPoint)point window:(NSWindow *)window {
    if ([NppPreferences shared].rightClickKeepsSelection) return;
    for (ScintillaView *sci in @[self.sci, self.secondarySci ?: self.sci]) {
        NSView *content = sci.content;
        if (content.window != window) continue;
        NSPoint local = [content convertPoint:point fromView:nil];
        if (!NSPointInRect(local, content.visibleRect)) continue;
        // Scintilla's client coordinates: the visible part's origin is 0,0 (ScintillaCocoa::ConvertPoint),
        // and the margins, a ruler beside the text on Cocoa, count before it in what
        // SCI_POSITIONFROMPOINT takes.
        long margins = 0, count = [sci message:SCI_GETMARGINS];
        for (long k = 0; k < count; ++k) margins += [sci message:SCI_GETMARGINWIDTHN wParam:(uptr_t)k lParam:0];
        long x = (long)(local.x - content.visibleRect.origin.x) + margins, y = (long)(local.y - content.visibleRect.origin.y);
        // Upstream lets a click in the margins through.
        long marginX = [sci message:SCI_POINTXFROMPOSITION wParam:0 lParam:0] + [sci message:SCI_GETXOFFSET];
        if (x < marginX) return;
        long pos = [sci message:SCI_POSITIONFROMPOINT wParam:(uptr_t)x lParam:y];
        long start = [sci message:SCI_GETSELECTIONSTART], end = [sci message:SCI_GETSELECTIONEND];
        if (pos >= start && pos < end) return;   // inside the selection: kept, as Scintilla keeps it
        [sci message:SCI_SETEMPTYSELECTION wParam:(uptr_t)pos];
        return;
    }
}

- (void)installContextClickMonitor {
    __weak EditorController *weakSelf = self;
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown | NSEventMaskLeftMouseDown
                                          handler:^NSEvent *(NSEvent *event) {
        BOOL context = event.type == NSEventTypeRightMouseDown ||
                       (event.modifierFlags & NSEventModifierFlagControl);
        if (context && event.window) [weakSelf contextClickAtWindowPoint:event.locationInWindow window:event.window];
        return event;
    }];
}

#pragma mark - Smart highlighting

- (NSUInteger)updateSmartHighlight {
    ScintillaView *sci = self.sci;
    // Its own indicator, as Notepad++ reserves a Smart Highlighting style.
    NSInteger style = NPPMAC_SMART_STYLE;
    [self clearStyle:style];
    [self clearSmartHighlightInOtherView];
    if (![NppPreferences shared].smartHighlightEnabled ||
        ![self featureAllowed:@"smartHighlight"]) return 0;

    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    if (b <= a) return 0;                       // only a real selection highlights
    if (b - a > 100) return 0;                  // a whole-paragraph selection is not a token

    NppPreferences *p = [NppPreferences shared];
    // "Use Find dialog settings": the dialog's Match case and Whole word.
    BOOL matchCase = p.smartHighlightUseFindSettings ? p.findMatchCase : p.smartHighlightMatchCase;
    BOOL wholeWord = p.smartHighlightUseFindSettings ? p.findWholeWord : p.smartHighlightWholeWord;
    // The same indicator whatever the refinements: a multi-selection that is
    // then put back is no highlight at all.
    NSUInteger count = [self markAllOccurrencesOfSelection:style matchCase:matchCase wholeWord:wholeWord];
    if (p.smartHighlightOtherView && self.secondarySci) [self smartHighlightOtherViewMatchCase:matchCase wholeWord:wholeWord];
    return count;
}

/// "Highlight another view" off (or turned off): what it marked there goes
/// (SETTINGS-055); upstream's SmartHighlighter only marks the other view while
/// the option is on, and each pass starts by clearing it.
- (void)clearSmartHighlightInOtherView {
    ScintillaView *other = self.secondarySci;
    if (!other) return;
    [other message:SCI_SETINDICATORCURRENT wParam:(uptr_t)NPPMAC_SMART_INDICATOR];
    [other message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[other message:SCI_GETLENGTH]];
}

/// "Highlight another view": the same word marked in the second view, in
/// the same indicator and look.
- (NSUInteger)smartHighlightOtherViewMatchCase:(BOOL)matchCase wholeWord:(BOOL)wholeWord {
    ScintillaView *sci = self.sci, *other = self.secondarySci;
    int indicator = NPPMAC_SMART_INDICATOR;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    NSData *mine = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    if (b <= a || (NSUInteger)b > mine.length) return 0;
    NSData *word = [mine subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))];
    for (int prop : {SCI_INDICSETSTYLE, SCI_INDICSETFORE, SCI_INDICSETALPHA, SCI_INDICSETUNDER}) {
        [other message:(unsigned int)prop wParam:(uptr_t)indicator lParam:[sci message:(unsigned int)(prop + 1) wParam:(uptr_t)indicator]];
    }
    long length = [other message:SCI_GETLENGTH];
    [other message:SCI_SETINDICATORCURRENT wParam:(uptr_t)indicator lParam:0];
    [other message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
    NSUInteger found = 0;
    Sci_TextToFindFull search{};
    std::string needle((const char *)word.bytes, word.length);
    search.lpstrText = needle.c_str();
    search.chrg.cpMin = 0;
    search.chrg.cpMax = length;
    int flags = (matchCase ? SCFIND_MATCHCASE : 0) | (wholeWord ? SCFIND_WHOLEWORD : 0);
    while ([other message:SCI_FINDTEXTFULL wParam:(uptr_t)flags lParam:(sptr_t)&search] >= 0) {
        [other message:SCI_INDICATORFILLRANGE wParam:(uptr_t)search.chrgText.cpMin
                lParam:search.chrgText.cpMax - search.chrgText.cpMin];
        found++;
        search.chrg.cpMin = MAX(search.chrgText.cpMax, search.chrgText.cpMin + 1);
        if (search.chrg.cpMin >= length) break;
    }
    return found;
}

#pragma mark - Word characters and delimiters

- (void)applyWordCharacters {
    NppPreferences *p = [NppPreferences shared];
    if (!p.customWordCharsEnabled || !p.customWordChars.length) {
        // The classes live in the document; turning the setting off has to
        // put the defaults back, or the last custom set stays until relaunch.
        [self.sci message:SCI_SETCHARSDEFAULT wParam:0 lParam:0];
        return;
    }
    static const char *base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
    NSString *chars = [@(base) stringByAppendingString:p.customWordChars];
    [self.sci setStringProperty:SCI_SETWORDCHARS parameter:0 value:chars];
}

- (BOOL)selectBetweenDelimitersAt:(long)position {
    NppPreferences *p = [NppPreferences shared];
    NSString *open = p.delimiterOpen.length ? p.delimiterOpen : @"(";
    NSString *close = p.delimiterClose.length ? p.delimiterClose : @")";
    ScintillaView *sci = self.sci;

    NSString *text = [sci string] ?: @"";
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (position < 0 || (NSUInteger)position > data.length) return NO;

    unichar openChar = [open characterAtIndex:0];
    unichar closeChar = [close characterAtIndex:0];

    // Search outwards from the caret, in characters, then convert back to bytes.
    NSUInteger caretChar = [[[NSString alloc] initWithData:
        [data subdataWithRange:NSMakeRange(0, (NSUInteger)position)]
        encoding:NSUTF8StringEncoding] length];

    NSInteger from = -1, to = -1;
    for (NSInteger i = (NSInteger)caretChar - 1; i >= 0; --i) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == closeChar && i != (NSInteger)caretChar - 1) break;
        if (c == openChar) { from = i; break; }
        if (!p.delimiterMultiline && (c == '\n' || c == '\r')) break;
    }
    for (NSUInteger i = caretChar; i < text.length; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c == closeChar) { to = (NSInteger)i; break; }
        if (!p.delimiterMultiline && (c == '\n' || c == '\r')) break;
    }
    if (from < 0 || to < 0 || to <= from) { NppBeep(); return NO; }

    long byteFrom = Utf8Len([text substringToIndex:(NSUInteger)from + 1]);
    long byteTo = Utf8Len([text substringToIndex:(NSUInteger)to]);
    [sci message:SCI_SETSEL wParam:(uptr_t)byteFrom lParam:byteTo];
    [self refreshChrome];
    return YES;
}

#pragma mark - Multi-instance

- (BOOL)shouldOpenFilesInNewInstance {
    return [NppPreferences shared].multiInstanceMode == 1;
}

/// Notepad++ remembers which panels were open; the same set is stored here.
- (void)rememberPanelState {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    // The floating panels' entries, put there by the app, are kept.
    NSMutableDictionary *state = [p.panelState mutableCopy] ?: [NSMutableDictionary dictionary];
    state[@"workspace"] = @([self workspaceVisible] && [p keepsPanelState:@"workspace"]);
    state[@"documentMap"] = @([self documentMapVisible] && [p keepsPanelState:@"documentMap"]);
    state[@"projectPanel"] = @([p keepsPanelState:@"projectPanel"] ? [self activeProjectPanel] : 0);
    state[@"secondaryView"] = @([self secondaryViewVisible]);
    p.panelState = state;
}

- (void)restorePanelState {
    NppPreferences *p = [NppPreferences shared];
    if (!p.rememberPanelState) return;
    NSDictionary *state = p.panelState;
    if (!state.count) return;

    if ([state[@"workspace"] boolValue]) {
        NSURL *folder = [self containingFolderURL];
        if (folder) [self openFolderAsWorkspace:folder.path];
    }
    if ([state[@"documentMap"] boolValue]) [self setDocumentMapVisible:YES];
    NSInteger project = [state[@"projectPanel"] integerValue];
    if (project >= 1 && project <= 3) [self showProjectPanel:project];
    if ([state[@"secondaryView"] boolValue]) [self setSecondaryViewVisible:YES];
}

@end
