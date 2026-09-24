#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "EncodingCommands.h"
#import "ToolsCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import <objc/runtime.h>

/// A text view that paints the configured header and footer on each page.
@interface NppPrintView : NSTextView
@property (nonatomic, weak) EditorController *editor;
@end

@implementation NppPrintView

- (BOOL)isFlipped { return YES; }

/// Print formfeed as page break: a page ends after the line holding a form
/// feed, if there is one on it.
- (void)adjustPageHeightNew:(CGFloat *)newBottom top:(CGFloat)oldTop bottom:(CGFloat)oldBottom limit:(CGFloat)bottomLimit {
    [super adjustPageHeightNew:newBottom top:oldTop bottom:oldBottom limit:bottomLimit];
    if (![NppPreferences shared].printFormFeedPageBreak) return;
    NSString *text = self.string;
    NSLayoutManager *lm = self.layoutManager;
    NSRange search = NSMakeRange(0, text.length);
    while (YES) {
        NSRange ff = [text rangeOfString:@"\f" options:0 range:search];
        if (ff.location == NSNotFound) break;
        NSRange glyphs = [lm glyphRangeForCharacterRange:ff actualCharacterRange:NULL];
        NSRect line = [lm lineFragmentRectForGlyphAtIndex:glyphs.location effectiveRange:NULL];
        CGFloat y = NSMaxY(line) + self.textContainerOrigin.y;
        if (y > oldTop + 1 && y < *newBottom) { *newBottom = y; return; }
        if (y >= *newBottom) return;
        search = NSMakeRange(NSMaxRange(ff), text.length - NSMaxRange(ff));
    }
}

- (void)drawPageBorderWithSize:(NSSize)borderSize {
    NppPreferences *p = [NppPreferences shared];
    NSPrintOperation *op = [NSPrintOperation currentOperation];
    NSInteger page = op.currentPage;
    NSInteger total = op.pageRange.length ?: 1;

    // "Header font (blank for the editor's)": no name is the editor's font.
    NSString *headerName = p.printHeaderFontName.length ? p.printHeaderFontName : (p.fontName ?: @"Menlo");
    NSFont *font = [NSFont fontWithName:NppAvailableFontName(headerName) size:MAX(6, p.printHeaderFontSize)]
                ?: [NSFont systemFontOfSize:9];
    NSFontManager *fm = [NSFontManager sharedFontManager];
    if (p.printHeaderBold)   font = [fm convertFont:font toHaveTrait:NSBoldFontMask];
    if (p.printHeaderItalic) font = [fm convertFont:font toHaveTrait:NSItalicFontMask];
    NSDictionary *attrs = @{NSFontAttributeName: font,
                            NSForegroundColorAttributeName: [NSColor blackColor]};

    // The print operation clips to the page rectangle; drawing here is outside
    // the text area, in the margins the print info reserved.
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(NSMakeRect(0, 0, borderSize.width, borderSize.height));

    CGFloat top = p.printMarginTop / 2;
    CGFloat bottom = borderSize.height - p.printMarginBottom / 2 - font.pointSize;
    CGFloat left = p.printMarginLeft;
    CGFloat right = borderSize.width - p.printMarginRight;

    void (^drawRow)(NSString *, NSString *, NSString *, CGFloat) =
        ^(NSString *l, NSString *c, NSString *r, CGFloat y) {
        NSString *lt = [self.editor expandPrintTemplate:l page:page of:total];
        NSString *ct = [self.editor expandPrintTemplate:c page:page of:total];
        NSString *rt = [self.editor expandPrintTemplate:r page:page of:total];
        if (lt.length) [lt drawAtPoint:NSMakePoint(left, y) withAttributes:attrs];
        if (ct.length) {
            NSSize size = [ct sizeWithAttributes:attrs];
            [ct drawAtPoint:NSMakePoint((left + right - size.width) / 2, y) withAttributes:attrs];
        }
        if (rt.length) {
            NSSize size = [rt sizeWithAttributes:attrs];
            [rt drawAtPoint:NSMakePoint(right - size.width, y) withAttributes:attrs];
        }
    };

    drawRow(p.printHeaderLeft, p.printHeaderMiddle, p.printHeaderRight, top);
    drawRow(p.printFooterLeft, p.printFooterMiddle, p.printFooterRight, bottom);

    [NSGraphicsContext restoreGraphicsState];
}

@end

@implementation EditorController (BackupAndPrint)

#pragma mark - Backup

- (NSString *)backupDirectory {
    NppPreferences *p = [NppPreferences shared];
    NSString *dir = p.backupDirectory.length
        ? p.backupDirectory
        : [[self supportDirectory] stringByAppendingPathComponent:@"backup"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return dir;
}

- (NSString *)writeBackupForPath:(NSString *)path {
    // A large file is not copied about, as on Windows.
    if ([self largeFileRestrictionActive]) return nil;
    NppPreferences *p = [NppPreferences shared];
    if (p.backupMode == NppBackupNone || !path.length) return nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *existing = [NSData dataWithContentsOfFile:path];
    if (!existing) return nil;              // nothing on disk yet to preserve

    NSString *target;
    if (p.backupMode == NppBackupSimple) {
        // Beside the file, one rolling copy, as Notepad++'s simple mode does.
        target = [path stringByAppendingPathExtension:@"bak"];
    } else {
        NSDateFormatter *stamp = [[NSDateFormatter alloc] init];
        stamp.dateFormat = @"yyyy-MM-dd_HHmmss";
        stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        target = [[self backupDirectory] stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"%@.%@.bak", path.lastPathComponent,
                   [stamp stringFromDate:[NSDate date]]]];
        // Two saves within one second get two backups, not one over the other.
        NSString *stem = target.stringByDeletingPathExtension;
        for (NSUInteger n = 2; [fm fileExistsAtPath:target]; ++n) {
            target = [stem stringByAppendingFormat:@"-%lu.bak", (unsigned long)n];
        }
    }
    if (p.backupMode == NppBackupSimple) [fm removeItemAtPath:target error:NULL];
    return [existing writeToFile:target atomically:YES] ? target : nil;
}

- (NSArray<NSString *> *)backupsForPath:(NSString *)path {
    NSMutableArray *found = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *simple = [path stringByAppendingPathExtension:@"bak"];
    if ([fm fileExistsAtPath:simple]) [found addObject:simple];

    NSString *dir = [self backupDirectory];
    NSString *prefix = [path.lastPathComponent stringByAppendingString:@"."];
    for (NSString *name in [[fm contentsOfDirectoryAtPath:dir error:NULL]
                            sortedArrayUsingSelector:@selector(compare:)]) {
        if ([name hasPrefix:prefix] && [name hasSuffix:@".bak"]) {
            [found addObject:[dir stringByAppendingPathComponent:name]];
        }
    }
    return found;
}

#pragma mark - Autosave

static const char kAutosaveTimerKey = 0;

- (BOOL)autosaveRunning {
    return objc_getAssociatedObject(self, &kAutosaveTimerKey) != nil;
}

- (void)setAutosaveEnabled:(BOOL)enabled interval:(NSTimeInterval)seconds {
    NSTimer *existing = objc_getAssociatedObject(self, &kAutosaveTimerKey);
    [existing invalidate];
    objc_setAssociatedObject(self, &kAutosaveTimerKey, nil, OBJC_ASSOCIATION_RETAIN);
    if (!enabled) return;

    __weak EditorController *weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:MAX(5.0, seconds) repeats:YES
                                                      block:^(NSTimer *t) {
        EditorController *me = weakSelf;
        if (!me) { [t invalidate]; return; }
        [me runAutosavePass];
    }];
    objc_setAssociatedObject(self, &kAutosaveTimerKey, timer, OBJC_ASSOCIATION_RETAIN);
}

- (NSUInteger)runAutosavePass {
    // The periodic backup, as Windows keeps it: the unsaved text of every
    // modified document goes to its own file in the backup folder, and the
    // document's own file is never touched. The session lists the backups,
    // so the text comes back after a crash or a quit.
    NSInteger restore = [self.documents indexOfObject:self.currentDocument];
    NppDocument *previous = [self previousTab];
    NSUInteger written = 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [self backupDirectory];
    NSDateFormatter *stamp = [[NSDateFormatter alloc] init];
    stamp.dateFormat = @"yyyy-MM-dd_HHmmss";
    stamp.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    for (NSInteger i = 0; i < (NSInteger)self.documents.count; ++i) {
        NppDocument *d = self.documents[(NSUInteger)i];
        if (!d.modified) {
            [self dropBackupOfDocument:d];
            continue;
        }
        [self selectDocumentAtIndex:i];
        if ([self largeFileRestrictionActive]) continue;
        NSString *text = [self documentText];
        if (!d.path && !text.length) {
            [self dropBackupOfDocument:d];             // emptied: nothing left to keep
            continue;
        }
        if (!d.backupPath) {
            NSString *name = [NSString stringWithFormat:@"%@@%@", d.displayName ?: @"new",
                              [stamp stringFromDate:[NSDate date]]];
            NSString *target = [dir stringByAppendingPathComponent:name];
            for (NSUInteger n = 2; [fm fileExistsAtPath:target]; ++n) {
                target = [dir stringByAppendingPathComponent:[name stringByAppendingFormat:@"-%lu", (unsigned long)n]];
            }
            d.backupPath = target;
        }
        NSData *data = d.codepage
            ? [EditorController dataFromString:text codepage:d.codepage]
            : [text dataUsingEncoding:d.encoding ?: NSUTF8StringEncoding allowLossyConversion:YES];
        if (data && [data writeToFile:d.backupPath options:NSDataWritingAtomic error:NULL]) written++;
    }
    if (restore != NSNotFound) [self selectDocumentAtIndex:restore];
    [self rememberPreviousTab:previous];
    if (!self.sessionSavingDisabled) [self saveSessionTo:[self defaultSessionPath] error:NULL];
    return written;
}

#pragma mark - Print

/// The same $(...) names Notepad++ accepts in header and footer fields.
- (NSString *)expandPrintTemplate:(NSString *)tpl page:(NSInteger)page of:(NSInteger)pages {
    if (!tpl.length) return @"";
    NppDocument *doc = self.currentDocument;

    NSDateFormatter *date = [[NSDateFormatter alloc] init];
    date.dateStyle = NSDateFormatterShortStyle;
    date.timeStyle = NSDateFormatterNoStyle;
    NSDateFormatter *time = [[NSDateFormatter alloc] init];
    time.dateStyle = NSDateFormatterNoStyle;
    time.timeStyle = NSDateFormatterShortStyle;
    NSDate *now = [NSDate date];

    NSDateFormatter *longDate = [[NSDateFormatter alloc] init];
    longDate.dateStyle = NSDateFormatterLongStyle;
    longDate.timeStyle = NSDateFormatterNoStyle;

    NSDictionary *values = @{
        // The three names in Notepad++'s own default header and footer.
        @"$(SHORT_DATE)":        [date stringFromDate:now],
        @"$(LONG_DATE)":         [longDate stringFromDate:now],
        @"$(TIME)":              [time stringFromDate:now],
        @"$(FULL_CURRENT_PATH)": doc.path ?: doc.displayName ?: @"",
        @"$(CURRENT_DIRECTORY)": doc.path.stringByDeletingLastPathComponent ?: @"",
        @"$(FILE_NAME)":         doc.displayName ?: @"",
        @"$(NAME_PART)":         doc.displayName.stringByDeletingPathExtension ?: @"",
        @"$(EXT_PART)":          doc.displayName.pathExtension ?: @"",
        @"$(CURRENT_DATE)":      [date stringFromDate:now],
        @"$(CURRENT_TIME)":      [time stringFromDate:now],
        @"$(CURRENT_PRINTING_PAGE)": [@(page) stringValue],
        @"$(TOTAL_PRINTING_PAGE)":   [@(pages) stringValue],
    };
    NSMutableString *out = [tpl mutableCopy];
    for (NSString *token in values) {
        [out replaceOccurrencesOfString:token withString:values[token]
                                options:0 range:NSMakeRange(0, out.length)];
    }
    return out;
}

- (NSString *)textForPrinting {
    NSString *text = [self documentText];
    if (![NppPreferences shared].printLineNumbers) return text;

    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    NSUInteger width = [@(lines.count) stringValue].length;
    NSMutableArray *numbered = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSUInteger i = 0; i < lines.count; ++i) {
        [numbered addObject:[NSString stringWithFormat:@"%*lu  %@",
                             (int)width, (unsigned long)(i + 1), lines[i]]];
    }
    return [numbered componentsJoinedByString:@"\n"];
}

/// A Scintilla colour (0xBBGGRR) as sRGB.
static NSColor *PrintColour(long bgr) {
    return [NSColor colorWithSRGBRed:(bgr & 0xff) / 255.0 green:((bgr >> 8) & 0xff) / 255.0
                                blue:((bgr >> 16) & 0xff) / 255.0 alpha:1];
}

/// Scintilla's SC_PRINT_INVERTLIGHT: light colours come out dark and dark light.
static NSColor *InvertedLight(NSColor *c) {
    NSColor *rgb = [c colorUsingColorSpace:[NSColorSpace sRGBColorSpace]] ?: c;
    return [NSColor colorWithSRGBRed:1 - rgb.redComponent green:1 - rgb.greenComponent blue:1 - rgb.blueComponent alpha:1];
}

/// The document as the lexer styles it, in the print colour mode - what
/// upstream's Printer gets from SCI_SETPRINTCOLOURMODE + SCI_FORMATRANGEFULL:
/// every style's colours, bold, italic and underline; line numbers in the line
/// number style when "Print line number" is on.
- (NSAttributedString *)styledTextForPrintingWithFont:(NSFont *)base mode:(NSInteger)mode {
    ScintillaView *sci = self.sci;
    NSData *bytes = [[self documentText] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    long len = MIN((long)bytes.length, (long)[sci message:SCI_GETLENGTH]);
    const unsigned char *text = (const unsigned char *)bytes.bytes;
    NSMutableDictionary<NSNumber *, NSDictionary *> *cache = [NSMutableDictionary dictionary];
    NSColor *defaultBack = PrintColour([sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT]);
    NSDictionary *(^attributesOf)(int) = ^NSDictionary *(int style) {
        style = MAX(0, MIN(style, STYLE_MAX));
        NSDictionary *hit = cache[@(style)];
        if (hit) return hit;
        NSFontDescriptorSymbolicTraits traits = 0;
        if ([sci message:SCI_STYLEGETBOLD wParam:(uptr_t)style]) traits |= NSFontDescriptorTraitBold;
        if ([sci message:SCI_STYLEGETITALIC wParam:(uptr_t)style]) traits |= NSFontDescriptorTraitItalic;
        NSFont *font = traits ? ([NSFont fontWithDescriptor:[base.fontDescriptor fontDescriptorWithSymbolicTraits:traits]
                                                       size:base.pointSize] ?: base) : base;
        NSMutableDictionary *a = [@{NSFontAttributeName: font} mutableCopy];
        NSColor *fore = PrintColour([sci message:SCI_STYLEGETFORE wParam:(uptr_t)style]);
        NSColor *back = PrintColour([sci message:SCI_STYLEGETBACK wParam:(uptr_t)style]);
        switch (mode) {
            case NppPrintBlackOnWhite: fore = [NSColor blackColor]; back = nil; break;
            case NppPrintNoBackground: back = nil; break;
            case NppPrintInvert: fore = InvertedLight(fore); back = InvertedLight(back); break;
            default: break;
        }
        a[NSForegroundColorAttributeName] = fore;
        // A run's own background, where it differs from the page's.
        NSColor *page = mode == NppPrintInvert ? InvertedLight(defaultBack) : defaultBack;
        if (back && ![back isEqual:page]) a[NSBackgroundColorAttributeName] = back;
        if ([sci message:SCI_STYLEGETUNDERLINE wParam:(uptr_t)style]) a[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
        cache[@(style)] = a;
        return a;
    };

    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    BOOL numbers = [NppPreferences shared].printLineNumbers;
    long lines = [sci message:SCI_GETLINECOUNT];
    int width = (int)[@(lines) stringValue].length;
    long line = 0;
    BOOL atLineStart = YES;
    NSMutableData *run = [NSMutableData data];
    // __block: flush reads the run's current style (a copy would stay -1, and a style
    // getter given -1 would make Scintilla drop every style it holds).
    __block int runStyle = -1;
    void (^flush)(void) = ^{
        if (!run.length) return;
        NSString *t = [[NSString alloc] initWithData:run encoding:NSUTF8StringEncoding] ?: @"";
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:attributesOf(runStyle)]];
        run.length = 0;
    };
    for (long i = 0; i < len; ++i) {
        unsigned char ch = text[i];
        int style = (int)[sci message:SCI_GETSTYLEINDEXAT wParam:(uptr_t)i];
        if (atLineStart && numbers) {
            flush();
            NSString *n = [NSString stringWithFormat:@"%*ld  ", width, line + 1];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:n attributes:attributesOf(STYLE_LINENUMBER)]];
        }
        atLineStart = NO;
        if (style != runStyle) { flush(); runStyle = style; }
        [run appendBytes:&ch length:1];
        if (ch == '\n') { flush(); atLineStart = YES; ++line; }
    }
    flush();
    if (!len && numbers) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%*d  ", width, 1]
                                                                    attributes:attributesOf(STYLE_LINENUMBER)]];
    }
    return out;
}

- (NSPrintOperation *)printOperationShowingPanel:(BOOL)showPanel {
    NppDocument *doc = self.currentDocument;
    if (!doc) return nil;
    NppPreferences *p = [NppPreferences shared];
    NSFont *font = [NSFont fontWithName:NppAvailableFontName(p.fontName ?: @"Menlo") size:MAX(6, p.fontSize - 2)]
                ?: [NSFont userFixedPitchFontOfSize:10];
    NSAttributedString *styled = [self styledTextForPrintingWithFont:font mode:p.printColourMode];

    NppPrintView *page = [[NppPrintView alloc] initWithFrame:NSMakeRect(0, 0, 540, 720)];
    page.editor = self;
    page.font = font;

    // Colour mode (Scintilla's SC_PRINT_*): the page's own background here, each
    // style's colours in the text.
    NSColor *defaultBack = PrintColour([self.sci message:SCI_STYLEGETBACK wParam:STYLE_DEFAULT]);
    switch (p.printColourMode) {
        case NppPrintInvert:
            page.backgroundColor = [NSColor blackColor];
            page.drawsBackground = YES;
            break;
        case NppPrintWYSIWYG:
            page.backgroundColor = defaultBack;
            page.drawsBackground = YES;
            break;
        case NppPrintNoBackground:
        case NppPrintBlackOnWhite:
        default:
            page.backgroundColor = [NSColor whiteColor];
            page.drawsBackground = NO;
            break;
    }
    [page.textStorage setAttributedString:styled];

    NSPrintOperation *op = [NSPrintOperation printOperationWithView:page
                                                          printInfo:[self printInfoFromPreferences]];
    op.showsPrintPanel = showPanel;
    op.showsProgressPanel = showPanel;
    op.jobTitle = doc.displayName;
    return op;
}

- (NSPrintInfo *)printInfoFromPreferences {
    NppPreferences *p = [NppPreferences shared];
    NSPrintInfo *info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSPrintingPaginationModeFit;
    info.leftMargin = p.printMarginLeft;
    info.rightMargin = p.printMarginRight;
    info.topMargin = p.printMarginTop;
    info.bottomMargin = p.printMarginBottom;
    return info;
}

@end
