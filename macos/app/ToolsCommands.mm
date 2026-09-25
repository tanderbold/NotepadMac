#import "ToolsCommands.h"
#import "EditCommands.h"
#import "FindCommands.h"
#import "InfoWindows.h"
#import "SettingsCommands.h"
#import "UpdateChecker.h"
#import "CryptoTools.h"
#import "ScintillaView.h"
#import "LanguageCatalog.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

@implementation EditorController (ToolsCommands)

#pragma mark - Hashes

+ (NSString *)nameOfDigest:(NppDigest)digest {
    switch (digest) {
        case NppDigestMD5:      return @"MD5";
        case NppDigestSHA1:     return @"SHA-1";
        case NppDigestSHA256:   return @"SHA-256";
        case NppDigestSHA512:   return @"SHA-512";
        case NppDigestSHA224:   return @"SHA-224";
        case NppDigestSHA384:   return @"SHA-384";
        case NppDigestSHA3_256: return @"SHA3-256";
        case NppDigestSHA3_512: return @"SHA3-512";
        case NppDigestBLAKE2b:  return @"BLAKE2b";
        case NppDigestCRC32:    return @"CRC-32";
        case NppDigestCount:    break;
    }
    return @"";
}

+ (NSString *)hashOfData:(NSData *)data digest:(NppDigest)digest {
    if (!data) return nil;
    // MD5 is offered because the Tools menu offers it. It is a checksum here,
    // not a security primitive, so the deprecation is silenced deliberately.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    unsigned char out[CC_SHA512_DIGEST_LENGTH];
    // CommonCrypto counts in 32 bits; a file past 4 GB is fed in pieces.
    #define NPP_DIGEST(CTX, INIT, UPDATE, FINAL, LENGTH) { \
        CTX ctx; INIT(&ctx); \
        const unsigned char *bytes = (const unsigned char *)data.bytes; NSUInteger left = data.length; \
        while (left) { CC_LONG piece = (CC_LONG)MIN(left, (NSUInteger)1 << 30); UPDATE(&ctx, bytes, piece); bytes += piece; left -= piece; } \
        FINAL(out, &ctx); size = LENGTH; }
    NSUInteger size = 0;
    switch (digest) {
        case NppDigestMD5:    NPP_DIGEST(CC_MD5_CTX, CC_MD5_Init, CC_MD5_Update, CC_MD5_Final, CC_MD5_DIGEST_LENGTH) break;
        case NppDigestSHA1:   NPP_DIGEST(CC_SHA1_CTX, CC_SHA1_Init, CC_SHA1_Update, CC_SHA1_Final, CC_SHA1_DIGEST_LENGTH) break;
        case NppDigestSHA224: NPP_DIGEST(CC_SHA256_CTX, CC_SHA224_Init, CC_SHA224_Update, CC_SHA224_Final, CC_SHA224_DIGEST_LENGTH) break;
        case NppDigestSHA256: NPP_DIGEST(CC_SHA256_CTX, CC_SHA256_Init, CC_SHA256_Update, CC_SHA256_Final, CC_SHA256_DIGEST_LENGTH) break;
        case NppDigestSHA384: NPP_DIGEST(CC_SHA512_CTX, CC_SHA384_Init, CC_SHA384_Update, CC_SHA384_Final, CC_SHA384_DIGEST_LENGTH) break;
        case NppDigestSHA512: NPP_DIGEST(CC_SHA512_CTX, CC_SHA512_Init, CC_SHA512_Update, CC_SHA512_Final, CC_SHA512_DIGEST_LENGTH) break;
        case NppDigestSHA3_256: return [NppCrypto hexOfData:[NppCrypto sha3OfData:data bits:256]];
        case NppDigestSHA3_512: return [NppCrypto hexOfData:[NppCrypto sha3OfData:data bits:512]];
        case NppDigestBLAKE2b:  return [NppCrypto hexOfData:[NppCrypto blake2bOfData:data]];
        case NppDigestCRC32:    return [NSString stringWithFormat:@"%08x", [NppCrypto crc32OfData:data]];
        case NppDigestCount:    return nil;
    }
    #undef NPP_DIGEST
#pragma clang diagnostic pop
    return [NppCrypto hexOfData:[NSData dataWithBytes:out length:size]];
}

+ (NSString *)hashOfText:(NSString *)text eachLine:(BOOL)eachLine digest:(NppDigest)digest {
    if (!eachLine) return [self hashOfData:[text dataUsingEncoding:NSUTF8StringEncoding] digest:digest];
    NSString *plain = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                       stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    // (A text that ends its last line has no empty line after it, as getline sees it upstream.)
    if ([plain hasSuffix:@"\n"]) plain = [plain substringToIndex:plain.length - 1];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (NSString *line in [plain componentsSeparatedByString:@"\n"])
        [lines addObject:line.length ? [self hashOfData:[line dataUsingEncoding:NSUTF8StringEncoding] digest:digest] : @""];
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)hashOfSelection:(NppDigest)digest {
    ScintillaView *sci = self.sci;
    long a = [sci message:SCI_GETSELECTIONSTART], b = [sci message:SCI_GETSELECTIONEND];
    NSData *doc = [([sci string] ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    NSData *slice = (b > a && (NSUInteger)b <= doc.length)
        ? [doc subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a))]
        : doc;                                   // no selection: hash the document
    return [EditorController hashOfData:slice digest:digest];
}

- (NSString *)hashOfFiles:(NSArray<NSString *> *)paths digest:(NppDigest)digest {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *path in paths) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        [lines addObject:[NSString stringWithFormat:@"%@  %@",
                          [EditorController hashOfData:data digest:digest], path]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - Macros

// Scintilla reports each recordable action through SCN_MACRORECORD; the steps
// are kept here and replayed verbatim.
static const char kMacroStepsKey = 0;
static const char kMacroRecordingKey = 0;
static const char kSavedMacrosKey = 0;

- (NSMutableArray *)macroSteps {
    NSMutableArray *steps = objc_getAssociatedObject(self, &kMacroStepsKey);
    if (!steps) {
        steps = [NSMutableArray array];
        objc_setAssociatedObject(self, &kMacroStepsKey, steps, OBJC_ASSOCIATION_RETAIN);
    }
    return steps;
}

static BOOL gPlayingMacro = NO;

- (BOOL)playingMacro { return gPlayingMacro; }

- (BOOL)recordingMacro {
    return [objc_getAssociatedObject(self, &kMacroRecordingKey) boolValue];
}

- (NSUInteger)recordedStepCount { return [self macroSteps].count; }

- (void)startRecordingMacro {
    [[self macroSteps] removeAllObjects];
    objc_setAssociatedObject(self, &kMacroRecordingKey, @YES, OBJC_ASSOCIATION_RETAIN);
    [self.sci message:SCI_STARTRECORD];
    [self refreshChrome];
}

- (void)stopRecordingMacro {
    [self.sci message:SCI_STOPRECORD];
    objc_setAssociatedObject(self, &kMacroRecordingKey, @NO, OBJC_ASSOCIATION_RETAIN);
    [self refreshChrome];
}

static const char kMacroSuspendedKey = 0;

/// A menu command that records as itself is about to run: what it does to
/// the text is its own business and is not recorded a second time.
- (void)beginRecordableMenuCommand {
    if (![self recordingMacro]) return;
    objc_setAssociatedObject(self, &kMacroSuspendedKey, @YES, OBJC_ASSOCIATION_RETAIN);
}

/// It has run: recorded by its id, as Notepad_plus::command records it (type 2).
- (void)endRecordableMenuCommand:(int)identifier {
    if (![objc_getAssociatedObject(self, &kMacroSuspendedKey) boolValue]) return;
    objc_setAssociatedObject(self, &kMacroSuspendedKey, @NO, OBJC_ASSOCIATION_RETAIN);
    if (![self recordingMacro] || identifier <= 0) return;
    [[self macroSteps] addObject:@{@"type": @2, @"msg": @0, @"w": @(identifier), @"l": @0, @"text": @""}];
}

/// A search run from the Find dialog while recording, as
/// FindReplaceDlg::saveInMacro writes it: the options, then what to do (type 3).
- (void)recordFindCommand:(int)command spec:(NppFindSpec *)spec markFlags:(long)markFlags global:(BOOL)global {
    objc_setAssociatedObject(self, &kMacroSuspendedKey, @NO, OBJC_ASSOCIATION_RETAIN);
    if (![self recordingMacro] || !spec.what.length) return;
    long flags = markFlags;
    if (spec.options & NppFindWholeWord) flags |= 1;
    if (spec.options & NppFindMatchCase) flags |= 2;
    if (spec.options & NppFindDotMatchesNewline) flags |= 1024;
    if (!global) {
        if (spec.options & NppFindInSelection) flags |= 128;
        if (spec.options & NppFindWrap) flags |= 256;
        if (!(spec.options & NppFindBackward)) flags |= 512;
    }
    long mode = spec.mode == NppSearchRegex ? 2 : spec.mode == NppSearchExtended ? 1 : 0;
    BOOL replaces = command == 1608 || command == 1609 || command == 1635;
    NSMutableArray *steps = [self macroSteps];
    [steps addObject:@{@"type": @3, @"msg": @1700, @"w": @0, @"l": @0, @"text": @""}];
    [steps addObject:@{@"type": @3, @"msg": @1601, @"w": @0, @"l": @0, @"text": spec.what}];
    [steps addObject:@{@"type": @3, @"msg": @1625, @"w": @0, @"l": @(mode), @"text": @""}];
    if (replaces) [steps addObject:@{@"type": @3, @"msg": @1602, @"w": @0, @"l": @0, @"text": spec.replacement ?: @""}];
    [steps addObject:@{@"type": @3, @"msg": @1702, @"w": @0, @"l": @(flags), @"text": @""}];
    [steps addObject:@{@"type": @3, @"msg": @1701, @"w": @0, @"l": @(command), @"text": @""}];
}

/// Called from the notification handler for each recorded action.
- (void)recordMacroMessage:(int)message wParam:(unsigned long)wParam lParam:(long)lParam {
    if (![self recordingMacro]) return;
    if ([objc_getAssociatedObject(self, &kMacroSuspendedKey) boolValue]) return;
    // Messages whose lParam is a string must have the text copied now; the
    // pointer Scintilla passes does not outlive the callback, so it is not kept
    // (recordedMacroStep: _sParameter, _lParameter = 0), an empty text included.
    NSString *text = @"";
    BOOL takesString = [EditorController macroMessageTakesString:message];
    if (takesString && lParam) {
        // Scintilla holds UTF-8 here; bytes that are not (a plugin's) keep one character each.
        const char *bytes = (const char *)lParam;
        text = [NSString stringWithUTF8String:bytes] ?: [NSString stringWithCString:bytes encoding:NSISOLatin1StringEncoding] ?: @"";
    }
    [[self macroSteps] addObject:@{@"msg": @(message),
                                   @"w": @(wParam),
                                   @"l": @(takesString ? 0 : lParam),
                                   @"text": text}];
}

+ (BOOL)macroMessageTakesString:(int)message {
    switch (message) {
        case SCI_REPLACESEL:
        case SCI_ADDTEXT:
        case SCI_INSERTTEXT:
        case SCI_APPENDTEXT:
        case SCI_SEARCHNEXT:
        case SCI_SEARCHPREV:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)playbackMacro:(NSUInteger)times {
    return [self playSteps:[[self macroSteps] copy] times:times];
}

- (BOOL)playSteps:(NSArray *)steps times:(NSUInteger)times {
    if (!steps.count || times == 0) { NppBeep(); return NO; }
    ScintillaView *sci = self.sci;
    [sci message:SCI_BEGINUNDOACTION];
    gPlayingMacro = YES;
    NSMutableDictionary *findState = [NSMutableDictionary dictionary];
    for (NSUInteger t = 0; t < times; ++t) {
        for (NSDictionary *step in steps) {
            // Steps read from a file are checked before they reach Scintilla.
            if (![step isKindOfClass:[NSDictionary class]] || ![step[@"msg"] isKindOfClass:[NSNumber class]]) continue;
            int msg = [step[@"msg"] intValue];
            NSString *text = step[@"text"];
            int type = [step[@"type"] intValue];
            if (type == 2) {
                // A menu command, by Notepad++'s id (recordable ones only get here).
                BOOL (^perform)(int) = self.menuCommandByIdentifier;
                if (perform) perform((int)[step[@"w"] longValue]);
                sci = self.sci;                                   // the command may have changed the view in front
                continue;
            }
            if (type == 3) {
                [self playFindStep:msg value:[step[@"l"] longValue] text:text ?: @"" into:findState];
                continue;
            }
            // recordedMacroStep::PlayBack: a string message is sent its stored text, never a
            // number that was a pointer (a macro saved before, with an address in lParam).
            if ([EditorController macroMessageTakesString:msg] || text.length) {
                [sci setStringProperty:msg parameter:[step[@"w"] longValue] value:[text isKindOfClass:[NSString class]] ? text : @""];
            } else {
                [sci message:msg wParam:(uptr_t)[step[@"w"] unsignedLongValue]
                      lParam:(sptr_t)[step[@"l"] longValue]];
            }
        }
    }
    gPlayingMacro = NO;
    [sci message:SCI_ENDUNDOACTION];
    [self refreshChrome];
    return YES;
}

static const char kMenuCommandKey = 0;
- (BOOL (^)(int))menuCommandByIdentifier { return objc_getAssociatedObject(self, &kMenuCommandKey); }
- (void)setMenuCommandByIdentifier:(BOOL (^)(int))block {
    objc_setAssociatedObject(self, &kMenuCommandKey, block, OBJC_ASSOCIATION_COPY);
}

/// One step of a recorded search, as FindReplaceDlg::execSavedCommand reads
/// them: the options gather until IDC_FRCOMMAND_EXEC says what to do.
- (void)playFindStep:(int)message value:(long)value text:(NSString *)text into:(NSMutableDictionary *)state {
    enum { FindWhat = 1601, ReplaceWith = 1602, SearchMode = 1625, Init = 1700, Exec = 1701, Booleans = 1702 };
    switch (message) {
        case Init: [state removeAllObjects]; return;
        case FindWhat: state[@"what"] = text; return;
        case ReplaceWith: state[@"with"] = text; return;
        case SearchMode: state[@"mode"] = @(value); return;
        case Booleans: state[@"flags"] = @(value); return;
        case Exec: break;
        default: return;
    }
    long flags = [state[@"flags"] longValue];
    NppFindOptions options = NppFindNone;
    if (flags & 1) options |= NppFindWholeWord;
    if (flags & 2) options |= NppFindMatchCase;
    if (flags & 128) options |= NppFindInSelection;
    if (flags & 256) options |= NppFindWrap;
    if (!(flags & 512)) options |= NppFindBackward;       // IDF_WHICH_DIRECTION set means down
    if (flags & 1024) options |= NppFindDotMatchesNewline;
    long mode = [state[@"mode"] longValue];
    NppFindSpec *spec = [NppFindSpec specFor:state[@"what"] ?: @""
                                        mode:mode == 2 ? NppSearchRegex : mode == 1 ? NppSearchExtended : NppSearchNormal
                                     options:options];
    spec.replacement = state[@"with"] ?: @"";
    if (!spec.what.length) return;
    switch (value) {
        case 1: [self findNext:spec]; break;                                     // IDOK
        case 1723: spec.options &= ~NppFindBackward; [self findNext:spec]; break; // IDC_FINDNEXT
        case 1721: spec.options |= NppFindBackward; [self findNext:spec]; break;  // IDC_FINDPREV
        case 1608: [self replaceCurrentThenFindNext:spec]; break;                 // IDREPLACE
        case 1609: [self replaceAll:spec]; break;                                 // IDREPLACEALL
        case 1614: [self countMatches:spec]; break;                               // IDCCOUNTALL
        case 1615:                                                                // IDCMARKALL
            [self markAll:spec purge:(flags & 4) != 0];
            if (flags & 16) {                                                     // "Bookmark line"
                for (NSValue *match in [self rangesOfMatches:spec]) {
                    long line = [self.sci message:SCI_LINEFROMPOSITION wParam:(uptr_t)match.rangeValue.location];
                    [self.sci message:SCI_MARKERADD wParam:(uptr_t)line lParam:1];
                }
            }
            break;
        case 1635: [self replaceAllInOpenDocuments:spec]; break;                  // IDC_REPLACE_OPENEDFILES
        default: break;                                   // Find All and Find in Files show results; not replayed
    }
}

- (NSString *)savedMacrosPath {
    return [self.defaultSessionPath.stringByDeletingLastPathComponent
            stringByAppendingPathComponent:@"macros.json"];
}

- (NSMutableDictionary *)savedMacros {
    NSMutableDictionary *saved = objc_getAssociatedObject(self, &kSavedMacrosKey);
    if (!saved) {
        // What was saved before this launch, read back: written and never
        // read, a saved macro lasted exactly one session.
        [self reloadSavedMacros];
        saved = objc_getAssociatedObject(self, &kSavedMacrosKey);
    }
    return saved;
}

- (void)reloadSavedMacros {
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    NSData *json = [NSData dataWithContentsOfFile:[self savedMacrosPath]];
    id parsed = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL] : nil;
    if ([parsed isKindOfClass:[NSDictionary class]]) {
        for (NSString *name in parsed) {
            if ([name isKindOfClass:[NSString class]] && [parsed[name] isKindOfClass:[NSArray class]]) {
                saved[name] = parsed[name];
            }
        }
    }
    objc_setAssociatedObject(self, &kSavedMacrosKey, saved, OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)saveRecordedMacroAs:(NSString *)name {
    if (!name.length || ![self macroSteps].count) { NppBeep(); return NO; }
    [self savedMacros][name] = [[self macroSteps] copy];

    // Persist alongside the session so macros survive a restart.
    NSString *path = [self savedMacrosPath];
    NSData *json = [NSJSONSerialization dataWithJSONObject:[self savedMacros]
                                                   options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:path options:NSDataWritingAtomic error:NULL];
    return YES;
}

- (NSArray<NSDictionary *> *)stepsOfSavedMacroNamed:(NSString *)name {
    id steps = [self savedMacros][name];
    return [steps isKindOfClass:[NSArray class]] ? steps : nil;
}

- (BOOL)playSavedMacroNamed:(NSString *)name {
    NSArray *steps = [self stepsOfSavedMacroNamed:name];
    if (!steps.count) { NppBeep(); return NO; }
    return [self playSteps:steps times:1];
}

- (void)writeSavedMacros {
    NSData *json = [NSJSONSerialization dataWithJSONObject:[self savedMacros]
                                                   options:NSJSONWritingPrettyPrinted error:NULL];
    [json writeToFile:[self savedMacrosPath] options:NSDataWritingAtomic error:NULL];
}

- (BOOL)removeSavedMacroNamed:(NSString *)name {
    if (![self savedMacros][name]) return NO;
    [[self savedMacros] removeObjectForKey:name];
    [self writeSavedMacros];
    return YES;
}

- (void)storeSavedMacro:(NSArray<NSDictionary *> *)steps named:(NSString *)name {
    if (!name.length || !steps) return;
    [self savedMacros][name] = [steps copy];
    [self writeSavedMacros];
}

- (NSArray<NSString *> *)savedMacroNames {
    return [[self savedMacros].allKeys sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Window

/// NumericStringEquivalence::numstrcmp (WindowsDlg.cpp): digits compare as numbers ("File2"
/// before "file10"), ASCII letters without case, anything else by its code.
static int NppNumStrCmp(NSString *a, NSString *b) {
    NSUInteger i = 0, j = 0, la = a.length, lb = b.length;
    for (;;) {
        if (i >= la || j >= lb) {
            if (i >= la && j >= lb) return 0;
            return i >= la ? -1 : 1;
        }
        unichar c1 = [a characterAtIndex:i], c2 = [b characterAtIndex:j];
        if (c1 >= '0' && c1 <= '9' && c2 >= '0' && c2 <= '9') {
            NSUInteger si = i, sj = j;
            unsigned long long v1 = 0, v2 = 0;
            while (i < la && [a characterAtIndex:i] >= '0' && [a characterAtIndex:i] <= '9') v1 = v1 * 10 + ([a characterAtIndex:i++] - '0');
            while (j < lb && [b characterAtIndex:j] >= '0' && [b characterAtIndex:j] <= '9') v2 = v2 * 10 + ([b characterAtIndex:j++] - '0');
            if (v1 != v2) return v1 < v2 ? -1 : 1;
            // Equal values: the one with more digits (leading zeros) second, as (p2-str2)-(p1-str1).
            NSInteger d = (NSInteger)(j - sj) - (NSInteger)(i - si);
            if (d) return d < 0 ? -1 : 1;
            continue;
        }
        if (c1 < 128 && c1 >= 'A' && c1 <= 'Z') c1 = c1 - 'A' + 'a';
        if (c2 < 128 && c2 >= 'A' && c2 <= 'Z') c2 = c2 - 'A' + 'a';
        if (c1 != c2) return c1 < c2 ? -1 : 1;
        ++i, ++j;
    }
}

- (void)sortTabsBy:(NppTabSort)key ascending:(BOOL)ascending {
    NSMutableArray *docs = (NSMutableArray *)self.documents;
    NppDocument *keep = self.currentDocument;

    // BufferEquivalent::compare: the column's order, and the full path name when that says
    // nothing - for an untitled document its name, "new 1". The keys are worked out once.
    NSMapTable<NppDocument *, id> *keys = [NSMapTable strongToStrongObjectsMapTable];
    ScintillaView *reader = nil;
    for (NppDocument *d in docs) {
        id k = nil;
        switch (key) {
            case NppTabSortName: k = d.displayName ?: @""; break;
            case NppTabSortPath: k = @""; break;
            case NppTabSortType: k = d.language.name ?: @""; break;
            case NppTabSortContentLength: {
                // docLength: the text as it is now, not the file on disk.
                long length = 0;
                if (d == self.currentDocument) length = [self.sci message:SCI_GETLENGTH];
                else if (d.docPointer) {
                    if (!reader) reader = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
                    [reader message:SCI_SETDOCPOINTER wParam:0 lParam:(sptr_t)d.docPointer];
                    length = [reader message:SCI_GETLENGTH];
                }
                k = @(length);
                break;
            }
            case NppTabSortModifiedTime:
                k = [NppFileAttributes(d.path) fileModificationDate] ?: [NSDate distantPast];
                break;
        }
        [keys setObject:k forKey:d];
    }
    if (reader) [reader message:SCI_SETDOCPOINTER wParam:0 lParam:0];

    NSComparisonResult (^full)(NppDocument *, NppDocument *) = ^NSComparisonResult(NppDocument *a, NppDocument *b) {
        return (NSComparisonResult)NppNumStrCmp(a.path ?: a.displayName ?: @"", b.path ?: b.displayName ?: @"");
    };
    [docs sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NppDocument *a, NppDocument *b) {
        // The main view's tabs are sorted; the second view's own documents stay after them.
        if (a.secondViewOnly != b.secondViewOnly) return a.secondViewOnly ? NSOrderedDescending : NSOrderedAscending;
        NSComparisonResult r = NSOrderedSame;
        id ka = [keys objectForKey:a], kb = [keys objectForKey:b];
        if (key == NppTabSortName || key == NppTabSortType) r = (NSComparisonResult)NppNumStrCmp(ka, kb);
        else if (key == NppTabSortContentLength || key == NppTabSortModifiedTime) r = [ka compare:kb];
        if (r == NSOrderedSame) r = full(a, b);
        return ascending ? r : (NSComparisonResult)(-(NSInteger)r);
    }];

    NSUInteger idx = [docs indexOfObject:keep];
    [self selectDocumentAtIndex:(idx == NSNotFound ? 0 : (NSInteger)idx)];
}

- (NSArray<NSString *> *)windowList {
    NSMutableArray *out = [NSMutableArray array];
    for (NppDocument *d in self.documents) [out addObject:d.path ?: d.displayName];
    return out;
}

/// Notepad++'s Recent Window steps back to the previously active tab.
static const char kPreviousTabKey = 0;

- (BOOL)activateRecentWindow {
    // A document rather than an index: tabs closed since it was remembered
    // would have shifted an index onto the wrong tab.
    NppDocument *prev = objc_getAssociatedObject(self, &kPreviousTabKey);
    NppDocument *current = self.currentDocument;
    NSUInteger where = prev ? [self.documents indexOfObject:prev] : NSNotFound;
    if (where == NSNotFound || prev == current) {
        NppBeep();
        return NO;
    }
    [self selectDocumentAtIndex:(NSInteger)where];
    objc_setAssociatedObject(self, &kPreviousTabKey, current, OBJC_ASSOCIATION_RETAIN);
    return YES;
}

- (NppDocument *)previousTab {
    return objc_getAssociatedObject(self, &kPreviousTabKey);
}

- (void)rememberPreviousTab:(NppDocument *)doc {
    objc_setAssociatedObject(self, &kPreviousTabKey, doc, OBJC_ASSOCIATION_RETAIN);
}

#pragma mark - Run

- (NSString *)runShellCommand:(NSString *)command {
    if (!command.length) return nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments = @[@"-c", command];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    // -waitUntilExit spins the run loop. On the main thread that re-enters
    // AppKit mid-command, which can raise inside a CATransaction observer and
    // abort the process, so completion is awaited on a semaphore instead.
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    task.terminationHandler = ^(NSTask *t) { dispatch_semaphore_signal(finished); };

    NSError *err = nil;
    if (![task launchAndReturnError:&err]) return nil;

    // readDataToEndOfFile blocks on the pipe, not on the run loop.
    NSData *out = [pipe.fileHandleForReading readDataToEndOfFile];
    dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    return [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"";
}

/// Notepad++ validates shortcuts.xml; here the equivalent is the app's own
/// keyboard shortcuts, checked for duplicates.
- (NSString *)validateShortcutsFile {
    NSMutableDictionary *seen = [NSMutableDictionary dictionary];
    NSMutableArray *clashes = [NSMutableArray array];
    NSUInteger counted = 0;

    NSMutableArray *queue = [NSMutableArray arrayWithArray:NSApp.mainMenu.itemArray];
    while (queue.count) {
        NSMenuItem *item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (item.submenu) [queue addObjectsFromArray:item.submenu.itemArray];
        if (!item.keyEquivalent.length) continue;
        // A hidden item that stands in for a visible one (the alternate Toggle Full
        // Screen) is the same command under the same key, not a second one.
        if (item.isHidden) continue;
        counted++;
        NSString *key = [NSString stringWithFormat:@"%lu-%@",
                         (unsigned long)item.keyEquivalentModifierMask, item.keyEquivalent];
        NSMenuItem *existing = seen[key];
        // The same command twice (an alternate item) is not a clash; two saved macros or
        // Run commands share the action and differ by what they carry.
        if (existing && existing.action == item.action && existing.tag == item.tag &&
            (existing.representedObject == item.representedObject || [existing.representedObject isEqual:item.representedObject]) &&
            [existing.title isEqualToString:item.title]) continue;
        if (existing) [clashes addObject:[NSString stringWithFormat:@"%@ clashes with %@ (%@)",
                                          item.title, existing.title, item.keyEquivalent]];
        else seen[key] = item;
    }
    if (!clashes.count) {
        return [NSString stringWithFormat:@"%lu shortcuts, no duplicates.", (unsigned long)counted];
    }
    return [NSString stringWithFormat:@"%lu shortcuts, %lu duplicate(s):\n%@",
            (unsigned long)counted, (unsigned long)clashes.count,
            [clashes componentsJoinedByString:@"\n"]];
}

#pragma mark - Help / info

/// Upstream's Debug Info fields in upstream's order, each read from what the
/// port has in its place (AboutDlg.cpp, DebugInfoDlg).
- (NSString *)debugInfo {
    NSProcessInfo *pi = [NSProcessInfo processInfo];
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NppPreferences *p = [NppPreferences shared];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"%@\n", [NppAboutWindow versionLine]];
    [s appendFormat:@"macOS port: %@ (build %@)\n", info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
    [s appendFormat:@"Build time: %@\n", info[@"NppBuildTime"] ?: @__DATE__ " - " __TIME__];
#if defined(__clang__)
    [s appendFormat:@"Built with: Clang %s\n", __clang_version__];
#else
    [s appendString:@"Built with: (unknown)\n"];
#endif
    NSString *(^dotted)(NSString *) = ^NSString *(NSString *digits) {
        // version.txt holds "566" for 5.6.6.
        NSString *d = [digits stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (d.length < 3) return d.length ? d : @"?";
        return [NSString stringWithFormat:@"%@.%@.%@", [d substringToIndex:1], [d substringWithRange:NSMakeRange(1, 1)], [d substringFromIndex:2]];
    };
    [s appendFormat:@"Scintilla/Lexilla included: %@/%@\n", dotted(info[@"NppScintillaVersion"] ?: @""), dotted(info[@"NppLexillaVersion"] ?: @"")];
    [s appendFormat:@"Path: %@\n", [NSBundle mainBundle].executablePath ?: pi.arguments.firstObject];
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *a in pi.arguments) [args addObject:[a containsString:@" "] ? [NSString stringWithFormat:@"\"%@\"", a] : a];
    [s appendFormat:@"Command Line: %@\n", [args componentsJoinedByString:@" "]];
    [s appendFormat:@"Admin mode: %@\n", geteuid() == 0 ? @"ON" : @"OFF"];
    [s appendFormat:@"Local Conf mode: %@\n", NppSettingsDirectoryOverridden() ? @"ON" : @"OFF"];
    [s appendFormat:@"Cloud Config: %@\n", p.settingsDirectory.length ? p.settingsDirectory : @"OFF"];
    NSString *updater = @[@"disabled", @"on startup", @"on exit"][(NSUInteger)MIN(MAX(p.autoUpdateMode, 0), 2)];
    [s appendFormat:@"Auto-updater: %@ (GitHub Releases of %@)\n", updater, p.updateRepository];
    [s appendFormat:@"Periodic Backup: %@\n", p.autosaveEnabled ? @"ON" : @"OFF"];
    [s appendString:@"Placeholders: OFF\n"];
    [s appendString:@"Scintilla Rendering Mode: Core Graphics\n"];
    NSString *instances = @[@"monoInst", @"multiInst", @"multiInstOnSession"][(NSUInteger)MIN(MAX(p.multiInstanceMode, 0), 2)];
    [s appendFormat:@"Multi-instance Mode: %@\n", instances];
    [s appendString:@"asNotepad: OFF\n"];
    NSMutableString *detect = [NSMutableString stringWithString:p.fileAutoDetection ? @"cdEnabledNew (for current file/tab only)" : @"cdDisabled"];
    if (p.fileAutoDetection && p.fileAutoDetectionSilent) [detect appendString:@" + cdAutoUpdate"];
    if (p.fileAutoDetection && p.fileAutoDetectionScrollToEnd) [detect appendString:@" + cdGo2end"];
    [s appendFormat:@"File Status Auto-Detection: %@\n", detect];
    [s appendFormat:@"Dark Mode: %@\n", [p.effectiveThemeName isEqualToString:p.darkThemeName] || (p.appearanceMode == 0 && p.systemIsDark) || p.appearanceMode == 2 ? @"ON" : @"OFF"];
    [s appendString:@"Display Info:"];
    NSScreen *main = NSScreen.screens.firstObject;
    if (main) {
        [s appendFormat:@"\n    primary monitor: %.0fx%.0f, scaling %.0f%%", main.frame.size.width * main.backingScaleFactor,
                        main.frame.size.height * main.backingScaleFactor, main.backingScaleFactor * 100];
    }
    [s appendFormat:@"\n    visible monitors count: %lu\n", (unsigned long)NSScreen.screens.count];
    NSOperatingSystemVersion v = pi.operatingSystemVersion;
#if defined(__arm64__)
    NSString *bits = @"ARM 64-bit";
#else
    NSString *bits = @"64-bit";
#endif
    [s appendFormat:@"OS Name: macOS (%@)\n", bits];
    [s appendFormat:@"OS Version: %ld.%ld.%ld\n", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
    NSRange build = [pi.operatingSystemVersionString rangeOfString:@"Build "];
    if (build.location != NSNotFound) {
        NSString *b = [pi.operatingSystemVersionString substringFromIndex:NSMaxRange(build)];
        [s appendFormat:@"OS Build: %@\n", [b stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@")"]]];
    }
    // The system's legacy 8-bit encoding, by its Windows code page number.
    CFStringEncoding system = CFStringGetSystemEncoding();
    [s appendFormat:@"Current ANSI codepage: %u\n", (unsigned)CFStringConvertEncodingToWindowsCodepage(system)];
    [s appendString:@"Plugins: none\n"];
    return s;
}

- (NSString *)commandLineArgumentsHelp {
    return @"NotepadMac accepts file paths as arguments:\n\n"
           @"    open -a NotepadMac file1.txt file2.txt\n"
           @"    open -a NotepadMac --args -n12 -c3 file.txt\n\n"
           @"The switches Notepad++ takes are taken here too:\n"
           @"    -n<line> -c<column> -p<position>   go there in the file opened last\n"
           @"    -l<language>       set the language of the files opened\n"
           @"    -udl=<name>        set a User Defined Language on the files opened\n"
           @"    -ro                open the files read-only\n"
           @"    -fullReadOnly      open every file read-only\n"
           @"    -fullReadOnlySavingForbidden   read-only, and saving refused\n"
           @"    -nosession         do not restore the last session\n"
           @"    -openSession       the files are session files to load\n"
           @"    -r                 a pattern (\"*.txt\") takes the files of the sub-folders too;\n"
           @"                       a folder always opens every file under it\n"
           @"    -openFoldersAsWorkspace   open the folders as the workspace\n"
           @"    -monitor           follow the file opened last as it grows\n"
           @"    -alwaysOnTop       keep the window above the others\n"
           @"    -notabbar          hide the tab bar\n"
           @"    -titleAdd=<text>   add text to the window title\n"
           @"    -settingsDir=<dir> read and write settings there for this launch\n"
           @"    -qt=<text> -qf=<file>   open a new document holding the text\n"
           @"    -qn=<name>         accepted (Notepad++'s easter eggs are not in this build)\n"
           @"    -notepadStyleCmdline    the rest of the line is one file name\n"
           @"    -z                 ignore the next argument\n"
           @"    -quickPrint        print the files given and quit\n"
           @"    -export=functionList   write each file's function list as JSON and quit\n"
           @"    -x<left> -y<top>   place the window there\n"
           @"    -multiInst -noPlugin -systemtray -loadingTime -pluginMessage=   accepted and ignored\n\n"
           @"Environment variables used by the build:\n"
           @"    NPPMAC_TEST=1        run the built-in test suite and exit\n"
           @"    NPPMAC_SELFTEST=1    print a short self-test and exit\n"
           @"    NPPMAC_SNAPSHOT=path render the window to a PNG and exit\n";
}

@end
