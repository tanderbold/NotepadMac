// Spell checking over Scintilla, the way DSpellCheck arranges it on Windows,
// with NSSpellChecker doing the looking-up: the visible lines are checked
// after every change or scroll (debounced), misspellings carry a squiggle
// indicator, and the context menu offers the engine's guesses.
#import "SpellCheck.h"
#import "SettingsCommands.h"
#import "StyleCatalog.h"
#import "LanguageCatalog.h"
#import "ScintillaView.h"

static NSInteger gSpellDocumentTag;

@implementation EditorController (SpellCheck)

- (void)scheduleSpellCheck {
    if (![NppPreferences shared].spellCheckEnabled) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(spellCheckNow) object:nil];
    [self performSelector:@selector(spellCheckNow) withObject:nil afterDelay:0.35];
}

/// The styles worth checking for the current language: comments and strings,
/// by their names in the theme - or nil for plain text, where every style is.
- (NSSet<NSNumber *> *)spellCheckedStyles {
    NppLanguage *lang = self.currentDocument.language;
    if (!lang || [lang.name isEqualToString:@"normal"] || [lang.name isEqualToString:@"txt"]) return nil;
    NSMutableSet *allowed = [NSMutableSet set];
    for (NppStyle *style in [[StyleCatalog sharedCatalog] stylesForLexerName:lang.name] ?: @[]) {
        NSString *name = style.name.uppercaseString;
        if ([name containsString:@"COMMENT"] || [name containsString:@"STRING"])
            [allowed addObject:@(style.styleID)];
    }
    return allowed;
}

- (NSString *)spellTextFrom:(long)start to:(long)end {
    if (end <= start) return @"";
    NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)(end - start) + 1];
    struct { struct { long cpMin, cpMax; } chrg; char *lpstrText; } tr;
    tr.chrg.cpMin = start;
    tr.chrg.cpMax = end;
    tr.lpstrText = (char *)buffer.mutableBytes;
    [self.sci message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&tr];
    return [NSString stringWithUTF8String:(const char *)buffer.bytes] ?: @"";
}

- (void)spellCheckNow {
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:NPPMAC_SPELL_INDICATOR lParam:0];
    [sci message:SCI_SETINDICATORVALUE wParam:1 lParam:0];   // what FILLRANGE writes; 0 writes nothing
    if (![NppPreferences shared].spellCheckEnabled) {
        [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:[sci message:SCI_GETLENGTH]];
        return;
    }
    [sci message:SCI_INDICSETSTYLE wParam:NPPMAC_SPELL_INDICATOR lParam:INDIC_SQUIGGLE];
    [sci message:SCI_INDICSETFORE wParam:NPPMAC_SPELL_INDICATOR lParam:0x0000FF];   // red, as everywhere
    [sci message:SCI_INDICSETUNDER wParam:NPPMAC_SPELL_INDICATOR lParam:1];

    NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
    if (!gSpellDocumentTag) gSpellDocumentTag = [NSSpellChecker uniqueSpellDocumentTag];
    NSString *language = [NppPreferences shared].spellCheckLanguage;
    checker.automaticallyIdentifiesLanguages = language.length == 0;
    if (language.length) [checker setLanguage:language];

    long firstVisible = [sci message:SCI_DOCLINEFROMVISIBLE
                              wParam:(uptr_t)[sci message:SCI_GETFIRSTVISIBLELINE] lParam:0];
    long lastVisible = [sci message:SCI_DOCLINEFROMVISIBLE
                             wParam:(uptr_t)([sci message:SCI_GETFIRSTVISIBLELINE] +
                                             [sci message:SCI_LINESONSCREEN] + 1) lParam:0];
    // Past the last line POSITIONFROMLINE answers -1, which a clear range
    // must never see.
    lastVisible = MIN(lastVisible, (long)[sci message:SCI_GETLINECOUNT wParam:0 lParam:0] - 1);
    NSSet<NSNumber *> *allowed = [self spellCheckedStyles];

    for (long line = firstVisible; line <= lastVisible; ++line) {
        long lineStart = [sci message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
        long lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
        if (lineStart < 0 || lineEnd <= lineStart) continue;
        [sci message:SCI_INDICATORCLEARRANGE wParam:(uptr_t)lineStart lParam:(sptr_t)(lineEnd - lineStart)];
        NSString *text = [self spellTextFrom:lineStart to:lineEnd];
        if (!text.length) continue;

        NSUInteger from = 0;
        while (from < text.length) {
            NSRange miss = [checker checkSpellingOfString:text startingAt:(NSInteger)from
                                                 language:language.length ? language : nil
                                                     wrap:NO inSpellDocumentWithTag:gSpellDocumentTag
                                                wordCount:NULL];
            if (miss.location == NSNotFound || miss.length == 0) break;
            long byteAt = lineStart +
                (long)strlen([text substringToIndex:miss.location].UTF8String ?: "");
            long byteLen = (long)strlen([text substringWithRange:miss].UTF8String ?: "");
            int style = (int)[sci message:SCI_GETSTYLEAT wParam:(uptr_t)byteAt lParam:0];
            if (!allowed || [allowed containsObject:@(style)]) {
                [sci message:SCI_INDICATORFILLRANGE wParam:(uptr_t)byteAt lParam:(sptr_t)byteLen];
            }
            from = NSMaxRange(miss);
        }
    }
}

#pragma mark - The context menu's offers

- (NSArray<NSMenuItem *> *)spellingMenuItemsForPosition:(long)position {
    ScintillaView *sci = self.sci;
    if (![NppPreferences shared].spellCheckEnabled) return @[];
    if (![sci message:SCI_INDICATORVALUEAT wParam:NPPMAC_SPELL_INDICATOR lParam:(sptr_t)position]) return @[];
    long start = [sci message:SCI_INDICATORSTART wParam:NPPMAC_SPELL_INDICATOR lParam:(sptr_t)position];
    long end = [sci message:SCI_INDICATOREND wParam:NPPMAC_SPELL_INDICATOR lParam:(sptr_t)position];
    NSString *word = [self spellTextFrom:start to:end];
    if (!word.length) return @[];

    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array];
    NSString *language = [NppPreferences shared].spellCheckLanguage;
    NSArray<NSString *> *guesses = [[NSSpellChecker sharedSpellChecker]
        guessesForWordRange:NSMakeRange(0, word.length) inString:word
                   language:language.length ? language : [NSSpellChecker sharedSpellChecker].language
     inSpellDocumentWithTag:gSpellDocumentTag] ?: @[];
    NSDictionary *place = @{@"start": @(start), @"end": @(end), @"word": word};
    for (NSString *guess in [guesses subarrayWithRange:NSMakeRange(0, MIN(guesses.count, 5u))]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:guess
                                                      action:@selector(spellReplaceWord:) keyEquivalent:@""];
        item.target = self;
        NSMutableDictionary *info = [place mutableCopy];
        info[@"guess"] = guess;
        item.representedObject = info;
        [items addObject:item];
    }
    if (!guesses.count) {
        NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No Guesses Found" action:NULL keyEquivalent:@""];
        none.enabled = NO;
        [items addObject:none];
    }
    NSMenuItem *ignore = [[NSMenuItem alloc] initWithTitle:@"Ignore Spelling"
                                                    action:@selector(spellIgnoreWord:) keyEquivalent:@""];
    ignore.target = self; ignore.representedObject = place;
    [items addObject:ignore];
    NSMenuItem *learn = [[NSMenuItem alloc] initWithTitle:@"Learn Spelling"
                                                   action:@selector(spellLearnWord:) keyEquivalent:@""];
    learn.target = self; learn.representedObject = place;
    [items addObject:learn];
    [items addObject:[NSMenuItem separatorItem]];
    return items;
}

- (void)spellReplaceWord:(NSMenuItem *)sender {
    NSDictionary *info = sender.representedObject;
    [self.sci message:SCI_SETSEL wParam:(uptr_t)[info[@"start"] longValue]
               lParam:(sptr_t)[info[@"end"] longValue]];
    [self.sci setStringProperty:SCI_REPLACESEL parameter:0 value:info[@"guess"]];
    [self spellCheckNow];
}

- (void)spellIgnoreWord:(NSMenuItem *)sender {
    [[NSSpellChecker sharedSpellChecker] ignoreWord:sender.representedObject[@"word"]
                             inSpellDocumentWithTag:gSpellDocumentTag];
    [self spellCheckNow];
}

- (void)spellLearnWord:(NSMenuItem *)sender {
    [[NSSpellChecker sharedSpellChecker] learnWord:sender.representedObject[@"word"]];
    [self spellCheckNow];
}

@end
