#import "CommandIDs.h"
#import "Localization.h"
#import <objc/runtime.h>

@interface NppLocalization ()
@property (nonatomic, readwrite, copy, nullable) NSString *languageFile;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *commands;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSString *> *tabCommands;
/// What the port says and Windows does not (its own panels and settings),
/// from macos/resources/nativeLang-extra/<the same file name>.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *extraStrings;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *menuNames;      // menuId / subMenuId -> text
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *englishMenuIds;  // english name -> menuId / subMenuId
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *strings;        // normalised english -> text
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *titles;         // dialog and tab titles
@end

/// The English an object showed before it was translated, so a language can
/// be changed back and forth and the originals are never lost.
static NSMapTable *gOriginals;

static NSMapTable *Originals(void) {
    if (!gOriginals) gOriginals = [NSMapTable weakToStrongObjectsMapTable];
    return gOriginals;
}

/// The English text of something shown. What the program itself has put
/// there since - a status line, a count, a toggled title - is neither the
/// English kept nor the translation last shown, and becomes the new English.
/// The same text, compared canonically: AppKit hands a title back composed
/// differently from how it was set (Tamil, Devanagari, Hangul with combining
/// marks), and a literal comparison would take the translation for a new
/// English text and keep it as such when English comes back.
static BOOL SameText(NSString *a, NSString *b) {
    if (!a || !b) return NO;
    // A menu title comes back with its no-break spaces (Tamil's file has them)
    // turned into plain ones and its format characters gone; the comparison
    // does the same to both sides, and composes them alike.
    NSString *(^bare)(NSString *) = ^NSString *(NSString *s) {
        s = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.controlCharacterSet] componentsJoinedByString:@""];
        s = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@" "];
        return [s precomposedStringWithCanonicalMapping];
    };
    return [bare(a) compare:bare(b)] == NSOrderedSame;
}

static NSString *Original(id object, NSString *key, NSString *now) {
    NSMutableDictionary *d = [Originals() objectForKey:object];
    if (!d) { d = [NSMutableDictionary dictionary]; [Originals() setObject:d forKey:object]; }
    NSString *shown = d[[key stringByAppendingString:@".shown"]];
    if (now && (!d[key] || (!SameText(now, d[key]) && !SameText(now, shown ?: @"")))) d[key] = now;
    return d[key] ?: now;
}

/// A value kept as it first was (a button's English width).
static NSString *FirstSeen(id object, NSString *key, NSString *now) {
    NSMutableDictionary *d = [Originals() objectForKey:object];
    if (!d) { d = [NSMutableDictionary dictionary]; [Originals() setObject:d forKey:object]; }
    if (!d[key] && now) d[key] = now;
    return d[key] ?: now;
}

static NSString *Shown(id object, NSString *key, NSString *text) {
    NSMutableDictionary *d = [Originals() objectForKey:object];
    if (text) d[[key stringByAppendingString:@".shown"]] = text;
    return text;
}

NSString *NppEnglishTitle(NSMenuItem *item) {
    NSDictionary *d = [Originals() objectForKey:item];
    NSString *now = item.title ?: @"";
    // A title the program changed since it was last translated is its own English.
    if (d[@"title"] && !SameText(now, d[@"title"]) && !SameText(now, d[@"title.shown"] ?: @"")) return now;
    return d[@"title"] ?: now;
}

NSString *NppEnglishMenuTitle(NSMenu *menu) {
    NSDictionary *d = [Originals() objectForKey:menu];
    return d[@"title"] ?: menu.title ?: @"";
}

NSString *NppL(NSString *english) { return [[NppLocalization shared] translate:english]; }

NSString *NppLMessage(NSString *english, NSString *string, NSInteger number) {
    return [[NppLocalization shared] message:english string:string number:number];
}

/// Upstream's strings carry & before the access key; && is a literal &.
static NSString *WithoutAccessKeys(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; ++i) {
        unichar c = [s characterAtIndex:i];
        if (c == '&') {
            if (i + 1 < s.length && [s characterAtIndex:i + 1] == '&') { [out appendString:@"&"]; ++i; }
            continue;
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}

/// The key an English string is looked up by: no access keys, no shortcut
/// after a tab, no trailing colon or ellipsis, case and spaces aside.
static NSString *Normalised(NSString *s) {
    NSString *t = WithoutAccessKeys(s ?: @"");
    NSRange tab = [t rangeOfString:@"\t"];
    if (tab.location != NSNotFound) t = [t substringToIndex:tab.location];
    // Line breaks and runs of blanks are one space to the lookup: a message is
    // the same message however its lines were broken.
    t = [[[t componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
          filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
    while ([t hasSuffix:@":"] || [t hasSuffix:@"…"] || [t hasSuffix:@"."]) {
        t = [[t substringToIndex:t.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return t.lowercaseString;
}

/// A push button keeps its English width, or grows to its translated title
/// when the room beside it is free; otherwise the title is cut on one line.
static void FitPushButton(NSButton *b) {
    NSString *w = FirstSeen(b, @"width", [NSString stringWithFormat:@"%g", b.frame.size.width]);
    NSRect frame = b.frame;
    frame.size.width = w.doubleValue;
    CGFloat wanted = ceil(b.cell.cellSize.width);
    b.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    b.cell.usesSingleLineMode = YES;
    if (wanted > frame.size.width) {
        NSRect grown = frame;
        grown.size.width = wanted;
        BOOL free = !b.superview || NSMaxX(grown) <= NSWidth(b.superview.bounds);
        for (NSView *other in b.superview.subviews) {
            if (other == b || other.hidden != b.hidden || !free) continue;   // views of one tab
            if (NSIntersectsRect(NSInsetRect(other.frame, 1, 1), grown) && !NSIntersectsRect(other.frame, frame)) free = NO;
        }
        if (free) frame = grown;
    }
    b.frame = frame;
}

/// A pull-down shows its first item as its title, and a title that does not
/// fit is cut with an ellipsis; a right-anchored one grows to the left instead,
/// and a label on its row that it would then cover gives up that much width.
static void FitPullDown(NSPopUpButton *popup) {
    if (!popup.superview || popup.translatesAutoresizingMaskIntoConstraints == NO) return;
    NSString *w = FirstSeen(popup, @"width", [NSString stringWithFormat:@"%g", popup.frame.size.width]);
    NSRect frame = popup.frame;
    CGFloat right = NSMaxX(frame);
    frame.size.width = w.doubleValue;
    CGFloat wanted = ceil(popup.cell.cellSize.width) + 2;
    if (wanted > frame.size.width) frame.size.width = MIN(wanted, NSWidth(popup.superview.bounds) - 12);
    frame.origin.x = (popup.autoresizingMask & NSViewMinXMargin) && !(popup.autoresizingMask & NSViewMaxXMargin) ? right - frame.size.width : frame.origin.x;
    for (NSView *other in popup.superview.subviews) {
        if (other == popup || other.hidden || ![other isKindOfClass:[NSTextField class]] || ((NSTextField *)other).editable) continue;
        if (!NSIntersectsRect(NSInsetRect(other.frame, 0, 1), frame) || NSMinX(other.frame) >= NSMinX(frame)) continue;
        NSRect shrunk = other.frame;
        shrunk.size.width = MAX(0, NSMinX(frame) - 4 - NSMinX(shrunk));
        other.frame = shrunk;
        ((NSTextField *)other).lineBreakMode = NSLineBreakByTruncatingTail;
    }
    popup.frame = frame;
}

/// A checkbox, radio button or label whose words no longer fit takes the
/// free room to its right, up to the next thing on its row or its parent's edge.
static void FitTitledControl(NSControl *c) {
    if (!c.superview || c.cell.wraps) return;
    if ([c isKindOfClass:[NSTextField class]] && ((NSTextField *)c).alignment != NSTextAlignmentLeft &&
        ((NSTextField *)c).alignment != NSTextAlignmentNatural) return;
    CGFloat needed = ceil(c.cell.cellSize.width) + 2;
    NSRect frame = c.frame;
    if (needed <= NSWidth(frame)) return;
    CGFloat limit = NSWidth(c.superview.bounds) - 8;
    for (NSView *other in c.superview.subviews) {
        if (other == c || other.hidden != c.hidden) continue;
        BOOL sameRow = NSMinY(other.frame) < NSMaxY(frame) - 2 && NSMaxY(other.frame) > NSMinY(frame) + 2;
        if (sameRow && NSMinX(other.frame) >= NSMinX(frame) + 8) limit = MIN(limit, NSMinX(other.frame) - 4);
    }
    CGFloat short_ = needed - (limit - NSMinX(frame));
    if (short_ > 0) {
        // Not enough room before the next thing on the row: the rest of the row
        // moves right, when the row as a whole still fits its parent.
        NSMutableArray<NSView *> *rest = [NSMutableArray array];
        CGFloat rowEnd = 0;
        for (NSView *other in c.superview.subviews) {
            if (other == c || other.hidden != c.hidden) continue;
            BOOL sameRow = NSMinY(other.frame) < NSMaxY(frame) - 2 && NSMaxY(other.frame) > NSMinY(frame) + 2;
            if (sameRow && NSMinX(other.frame) >= NSMinX(frame) + 8) { [rest addObject:other]; rowEnd = MAX(rowEnd, NSMaxX(other.frame)); }
        }
        if (rest.count && rowEnd + short_ <= NSWidth(c.superview.bounds) - 4) {
            for (NSView *other in rest) {
                NSRect r = other.frame;
                r.origin.x += short_;
                other.frame = r;
            }
            limit += short_;
        }
    }
    frame.size.width = MAX(NSWidth(frame), MIN(needed, limit - NSMinX(frame)));
    c.frame = frame;
}

/// Whether the port names a command as upstream's menu does (menu label, "&",
/// "..." and a shortcut in brackets aside).
static BOOL SameLabel(NSString *english, int identifier) {
    for (int i = 0; i < kNppMenuCommandIDCount; ++i) {
        if (kNppMenuCommandIDs[i].identifier != identifier) continue;
        NSString *label = @(kNppMenuCommandIDs[i].label);
        NSRange bracket = [label rangeOfString:@" ("];
        if (bracket.location != NSNotFound && [label hasSuffix:@")"]) label = [label substringToIndex:bracket.location];
        if ([Normalised(label) isEqualToString:Normalised(english)]) return YES;
    }
    return NO;
}

NSString *const NppUntranslatedIdentifier = @"NppUntranslated";

@implementation NppLocalization

+ (instancetype)shared {
    static NppLocalization *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppLocalization alloc] init]; });
    return shared;
}

+ (NSString *)directory { return [[NSBundle mainBundle] pathForResource:@"nativeLang" ofType:nil]; }

+ (NSDictionary<NSString *, NSString *> *)availableLanguages {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *file in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self directory] error:NULL]) {
        if (![file.pathExtension isEqualToString:@"xml"]) continue;
        // Only the <Native-Langue ...> tag is decoded: a fixed-length head can
        // end inside a multi-byte character, and then nothing decodes.
        NSData *data = [[NSFileHandle fileHandleForReadingAtPath:
                            [[self directory] stringByAppendingPathComponent:file]] readDataOfLength:4096];
        NSRange tag = data ? [data rangeOfData:[@"<Native-Langue" dataUsingEncoding:NSUTF8StringEncoding]
                                       options:0 range:NSMakeRange(0, data.length)] : NSMakeRange(NSNotFound, 0);
        NSString *head = @"";
        if (tag.location != NSNotFound) {
            NSRange close = [data rangeOfData:[@">" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                        range:NSMakeRange(tag.location, data.length - tag.location)];
            if (close.location != NSNotFound) {
                head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(tag.location, NSMaxRange(close) - tag.location)]
                                             encoding:NSUTF8StringEncoding] ?: @"";
            }
        }
        NSRange r = [head rangeOfString:@"name=\""];
        NSString *name = file.stringByDeletingPathExtension;
        if (r.location != NSNotFound) {
            NSRange end = [head rangeOfString:@"\"" options:0 range:NSMakeRange(NSMaxRange(r), head.length - NSMaxRange(r))];
            if (end.location != NSNotFound) name = [head substringWithRange:NSMakeRange(NSMaxRange(r), end.location - NSMaxRange(r))];
        }
        out[file] = name;
    }
    return out;
}

- (BOOL)active { return self.strings.count > 0; }

/// Every translatable value of a file, by where it is: the element path with
/// the attribute that tells siblings apart, then the attribute's name.
static NSDictionary<NSString *, NSString *> *Flatten(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    // Messages are written over several lines inside their attribute, and an
    // XML parser makes such line breaks spaces; written as &#x0A; they stay.
    NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (xml) {
        NSMutableString *kept = [NSMutableString stringWithCapacity:xml.length + 1024];
        BOOL inTag = NO, inValue = NO;
        NSUInteger n = xml.length;
        for (NSUInteger i = 0; i < n; ++i) {
            unichar c = [xml characterAtIndex:i];
            if (!inTag && c == '<') {
                if (i + 3 < n && [[xml substringWithRange:NSMakeRange(i, 4)] isEqualToString:@"<!--"]) {
                    NSRange end = [xml rangeOfString:@"-->" options:0 range:NSMakeRange(i, n - i)];
                    NSUInteger stop = end.location == NSNotFound ? n : NSMaxRange(end);
                    [kept appendString:[xml substringWithRange:NSMakeRange(i, stop - i)]];
                    i = stop - 1;
                    continue;
                }
                inTag = YES;
            } else if (inTag && c == '"') inValue = !inValue;
            else if (inTag && !inValue && c == '>') inTag = NO;
            if (inValue && c == '\r') continue;
            if (inValue && c == '\n') { [kept appendString:@"&#x0A;"]; continue; }
            [kept appendFormat:@"%C", c];
        }
        data = [kept dataUsingEncoding:NSUTF8StringEncoding];
    }
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:0 error:NULL] : nil;
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if (!doc) return out;
    NSArray *keys = @[@"id", @"menuId", @"subMenuId", @"CMID", @"CMDID", @"idName"];
    __block void (^walk)(NSXMLElement *, NSString *) = nil;
    void (^__block __weak weakWalk)(NSXMLElement *, NSString *);
    walk = ^(NSXMLElement *e, NSString *prefix) {
        NSString *ident = nil;
        for (NSString *k in keys) { NSString *v = [[e attributeForName:k] stringValue]; if (v) { ident = [NSString stringWithFormat:@"%@=%@", k, v]; break; } }
        NSString *here = [NSString stringWithFormat:@"%@/%@%@", prefix, e.name, ident ? [NSString stringWithFormat:@"[%@]", ident] : @""];
        for (NSXMLNode *a in e.attributes) {
            if ([keys containsObject:a.name] || [a.name isEqualToString:@"filename"] || [a.name isEqualToString:@"version"]) continue;
            out[[NSString stringWithFormat:@"%@@%@", here, a.name]] = a.stringValue ?: @"";
        }
        for (NSXMLNode *child in e.children) if ([child isKindOfClass:[NSXMLElement class]]) weakWalk((NSXMLElement *)child, here);
    };
    weakWalk = walk;
    NSXMLElement *root = [[doc rootElement] elementsForName:@"Native-Langue"].firstObject ?: doc.rootElement;
    walk(root, @"");
    return out;
}

- (BOOL)loadLanguageFile:(NSString *)fileName {
    self.commands = [NSMutableDictionary dictionary];
    self.tabCommands = [NSMutableDictionary dictionary];
    self.menuNames = [NSMutableDictionary dictionary];
    self.englishMenuIds = [NSMutableDictionary dictionary];
    self.strings = [NSMutableDictionary dictionary];
    self.titles = [NSMutableDictionary dictionary];
    self.languageFile = nil;
    if (!fileName.length || [fileName isEqualToString:@"english.xml"]) return YES;
    NSString *dir = [NppLocalization directory];
    NSString *path = [dir stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;
    NSDictionary *english = Flatten([dir stringByAppendingPathComponent:@"english.xml"]);
    NSDictionary *native = Flatten(path);
    // Dialog texts first: "Replace" is the dialog's button before it is the
    // menu's "Replace..." command.
    NSArray *ordered = [native.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        BOOL da = [a hasPrefix:@"/Native-Langue/Dialog/"], db = [b hasPrefix:@"/Native-Langue/Dialog/"];
        if (da != db) return da ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    for (NSString *key in ordered) {
        NSString *text = native[key];
        NSString *en = english[key];
        // Menu commands by id, menus and submenus by their upstream ids.
        NSRange cmd = [key rangeOfString:@"/Commands/Item[id="];
        if ([key hasPrefix:@"/Native-Langue/Menu/"] && cmd.location != NSNotFound && [key hasSuffix:@"@name"]) {
            NSString *idPart = [key substringFromIndex:NSMaxRange(cmd)];
            self.commands[@([idPart intValue])] = WithoutAccessKeys(text);
        }
        // The tab's own menu words some commands differently ("Close All BUT This"),
        // so its texts are kept apart from the main menu's.
        NSRange tab = [key rangeOfString:@"/TabBar/Item[CMDID="];
        if ([key hasPrefix:@"/Native-Langue/Menu/"] && tab.location != NSNotFound && [key hasSuffix:@"@name"]) {
            int identifier = [[key substringFromIndex:NSMaxRange(tab)] intValue];
            if (identifier > 100) self.tabCommands[@(identifier)] = WithoutAccessKeys(text);
        }
        for (NSString *kind in @[@"menuId=", @"subMenuId="]) {
            NSRange r = [key rangeOfString:kind];
            if ([key hasPrefix:@"/Native-Langue/Menu/Main/"] && r.location != NSNotFound && [key hasSuffix:@"@name"]) {
                NSString *ident = [key substringWithRange:NSMakeRange(NSMaxRange(r), [key rangeOfString:@"]" options:0 range:NSMakeRange(NSMaxRange(r), key.length - NSMaxRange(r))].location - NSMaxRange(r))];
                self.menuNames[ident] = WithoutAccessKeys(text);
                if (en.length) self.englishMenuIds[Normalised(en)] = ident;
            }
        }
        // A window's or a tab's name: "Replace" is "Замена" there, "Заменить" on a button.
        NSRange at = [key rangeOfString:@"@" options:NSBackwardsSearch];
        if ([key hasPrefix:@"/Native-Langue/Dialog/"] && at.location != NSNotFound
            && [[key substringFromIndex:at.location + 1] hasPrefix:@"title"]
            && en.length && text.length && !self.titles[Normalised(en)]) {
            self.titles[Normalised(en)] = text;
        }
        if (en.length && text.length && ![en isEqualToString:text] && !self.strings[Normalised(en)]) {
            self.strings[Normalised(en)] = text;
        }
    }
    self.extraStrings = [NSMutableDictionary dictionary];
    NSString *extraPath = [[[dir stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"nativeLang-extra"]
                           stringByAppendingPathComponent:fileName];
    NSData *extraData = [NSData dataWithContentsOfFile:extraPath];
    NSXMLDocument *extra = extraData ? [[NSXMLDocument alloc] initWithData:extraData options:0 error:NULL] : nil;
    for (NSXMLElement *item in [extra.rootElement elementsForName:@"Item"]) {
        NSString *en = [item attributeForName:@"english"].stringValue, *text = [item attributeForName:@"text"].stringValue;
        if (en.length && text.length) self.extraStrings[Normalised(en)] = text;
    }
    self.languageFile = fileName;
    return YES;
}

- (NSString *)commandName:(int)identifier { return self.commands[@(identifier)]; }
- (NSString *)tabCommandName:(int)identifier { return self.tabCommands[@(identifier)]; }

- (NSString *)translate:(NSString *)english {
    return [self translate:english hit:self.strings[Normalised(english ?: @"")]];
}

- (NSString *)message:(NSString *)english string:(NSString *)string number:(NSInteger)number {
    // Looked up with its placeholders in, filled in afterwards; line breaks are the translation's own.
    NSString *hit = self.strings.count ? (self.strings[Normalised(english ?: @"")] ?: self.extraStrings[Normalised(english ?: @"")]) : nil;
    NSString *text = hit ?: english ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"$STR_REPLACE$" withString:string ?: @""];
    return [text stringByReplacingOccurrencesOfString:@"$INT_REPLACE$" withString:[NSString stringWithFormat:@"%ld", (long)number]];
}

- (NSString *)translateTitle:(NSString *)english {
    NSString *key = Normalised(english ?: @"");
    return [self translate:english hit:self.titles[key] ?: self.strings[key]];
}

- (NSString *)translate:(NSString *)english hit:(NSString *)hit {
    if (!english.length) return @"";
    // "Group|Field": upstream puts the field's short name inside a titled box;
    // here they are one label, each part in its own translation.
    if ([english containsString:@"|"]) {
        NSRange firstLetter = [english rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet.invertedSet];
        NSString *indent = firstLetter.location == NSNotFound ? @"" : [english substringToIndex:firstLetter.location];
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *part in [[english substringFromIndex:indent.length] componentsSeparatedByString:@"|"]) {
            NSString *t = [self translate:part];
            while ([t hasSuffix:@":"] || [t hasSuffix:@" "]) t = [t substringToIndex:t.length - 1];
            if (t.length) [parts addObject:t];
        }
        return [indent stringByAppendingString:[parts componentsJoinedByString:@": "]];
    }
    if (!self.strings.count) return [english containsString:@"&&"] ? WithoutAccessKeys(english) : english;
    if (!hit) hit = self.extraStrings[Normalised(english)];
    if (!hit) return english;
    NSString *text = WithoutAccessKeys(hit);
    // Upstream breaks long button texts over two lines; a Mac button has one.
    text = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    NSRange tab = [text rangeOfString:@"\t"];
    if (tab.location != NSNotFound) text = [text substringToIndex:tab.location];
    // The English form's colon or ellipsis goes on the translation, and only then.
    NSString *trimmed = [english stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    BOOL englishColon = [trimmed hasSuffix:@":"];
    BOOL englishDots = [trimmed hasSuffix:@"…"] || [trimmed hasSuffix:@"..."];
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    while (!englishDots && ([text hasSuffix:@"…"] || [text hasSuffix:@"..."])) {
        text = [[text substringToIndex:text.length - ([text hasSuffix:@"…"] ? 1 : 3)]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    while (!englishColon && [text hasSuffix:@":"]) {
        text = [[text substringToIndex:text.length - 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    while ([text containsString:@"  "]) text = [text stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    // An indented label stays indented.
    NSRange lead = [english rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet.invertedSet];
    if (lead.location != NSNotFound && lead.location > 0) text = [[english substringToIndex:lead.location] stringByAppendingString:text];
    if ([trimmed hasSuffix:@":"] && ![text hasSuffix:@":"]) text = [text stringByAppendingString:@":"];
    if (([trimmed hasSuffix:@"…"] || [trimmed hasSuffix:@"..."]) && ![text hasSuffix:@"…"] && ![text hasSuffix:@"..."]) {
        text = [text stringByAppendingString:@"…"];
    }
    return text;
}

#pragma mark Menus

- (void)localizeMenu:(NSMenu *)menu identifiers:(NSDictionary<NSNumber *, NSMenuItem *> *)ids {
    NSMapTable *byItem = [NSMapTable weakToStrongObjectsMapTable];
    for (NSNumber *identifier in ids) [byItem setObject:identifier forKey:ids[identifier]];
    [self localizeMenu:menu byItem:byItem top:YES];
}

- (void)localizeMenu:(NSMenu *)menu byItem:(NSMapTable *)byItem top:(BOOL)top {
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        NSString *english = Original(item, @"title", item.title) ?: @"";
        NSString *text = nil;
        if (item.submenu) {
            NSString *englishMenu = Original(item.submenu, @"title", item.submenu.title) ?: @"";
            NSString *ident = self.englishMenuIds[Normalised(english)] ?: self.englishMenuIds[Normalised(englishMenu)];
            // The application menu keeps its name.
            if (top && menu.itemArray.firstObject == item) text = english;
            else if (ident) text = self.menuNames[ident];
            if (!text) text = [self translate:english];
            item.submenu.title = Shown(item.submenu, @"title", self.active ? text : englishMenu);
            [self localizeMenu:item.submenu byItem:byItem top:NO];
        } else {
            NSNumber *identifier = [byItem objectForKey:item];
            // "About NotepadMac" and its like are the port's own texts (nativeLang-extra):
            // upstream's translation of the same command names the Windows application.
            BOOL ownName = [english containsString:@"NotepadMac"];
            // The port's own wording for a command wins over upstream's translation of
            // upstream's wording: "Move to Trash" is nativeLang-extra's, not the text
            // upstream translates for "Move to Recycle Bin". An item of the port's own
            // (no command id: Selected Numbers > Count) is nativeLang-extra's first too,
            // before an upstream text that merely has the same English.
            NSString *extra = self.extraStrings[Normalised(english)];
            if (extra && (!identifier || !SameLabel(english, identifier.intValue))) ownName = YES;
            text = (identifier && !ownName) ? [self commandName:identifier.intValue] : nil;
            if (!text && extra && ownName) text = [self translate:english hit:extra];
            text = text ?: [self translate:english];
        }
        item.title = Shown(item, @"title", (self.active ? text : english) ?: @"");
    }
}

#pragma mark Windows

- (void)localizeWindow:(NSWindow *)window {
    if (!window) return;
    NSString *english = Original(window, @"title", window.title);
    window.title = Shown(window, @"title", [self translateTitle:english]);
    if (window.contentView) [self localizeView:window.contentView];
}

- (void)setTitle:(NSString *)english ofWindow:(NSWindow *)window {
    if (!window) return;
    NSMutableDictionary *d = [Originals() objectForKey:window];
    if (!d) { d = [NSMutableDictionary dictionary]; [Originals() setObject:d forKey:window]; }
    d[@"title"] = english;
    window.title = Shown(window, @"title", [self translateTitle:english]);
}

- (void)localizeView:(NSView *)view {
    if ([view isKindOfClass:[NSButton class]] && ![view isKindOfClass:[NSPopUpButton class]]) {
        // (A pop-up's setTitle: selects or adds an item; its items are done below.)
        NSButton *b = (NSButton *)view;
        if (b.title.length) {
            b.title = Shown(b, @"title", [self translate:Original(b, @"title", b.title)]);
            if (((NSButtonCell *)b.cell).showsStateBy & NSContentsCellMask) FitTitledControl(b);
            else if (b.bezelStyle == NSBezelStyleRounded) FitPushButton(b);
        }
    }
    if ([view.identifier isEqualToString:NppUntranslatedIdentifier]) {
        // left as it is
    } else if ([view isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *popup = (NSPopUpButton *)view;
        for (NSMenuItem *item in popup.itemArray) {
            item.title = Shown(item, @"title", [self translate:Original(item, @"title", item.title)]);
        }
        [popup synchronizeTitleAndSelectedItem];   // a pull-down shows its first item's title, kept by the cell
        if (popup.pullsDown) FitPullDown(popup);
    } else if ([view isKindOfClass:[NSSegmentedControl class]]) {
        NSSegmentedControl *s = (NSSegmentedControl *)view;
        for (NSInteger i = 0; i < s.segmentCount; ++i) {
            NSString *label = [s labelForSegment:i];
            if (label.length) [s setLabel:Shown(s, [NSString stringWithFormat:@"seg%ld", (long)i], [self translateTitle:Original(s, [NSString stringWithFormat:@"seg%ld", (long)i], label)]) forSegment:i];
        }
    } else if ([view isKindOfClass:[NSTextField class]] && ![view isKindOfClass:[NSComboBox class]]) {
        NSTextField *f = (NSTextField *)view;
        if (!f.editable && f.stringValue.length) f.stringValue = Shown(f, @"text", [self translate:Original(f, @"text", f.stringValue)]);
        if (!f.editable && !f.bezeled && f.stringValue.length) FitTitledControl(f);
        if (f.placeholderString.length) f.placeholderString = Shown(f, @"placeholder", [self translate:Original(f, @"placeholder", f.placeholderString)]);
    } else if ([view isKindOfClass:[NSMatrix class]]) {
        for (NSCell *cell in ((NSMatrix *)view).cells) {
            if (cell.title.length) cell.title = Shown(cell, @"title", [self translate:Original(cell, @"title", cell.title)]);
        }
    } else if ([view isKindOfClass:[NSTableView class]]) {
        NSTableView *table = (NSTableView *)view;
        for (NSTableColumn *c in table.tableColumns) {
            if (c.title.length) c.title = Shown(c, @"title", [self translate:Original(c, @"title", c.title)]);
        }
        [table.headerView setNeedsDisplay:YES];
        // Data sources translate what they return; a cell being edited is left to its editor.
        if (table.editedRow < 0) [table reloadData];
    } else if ([view isKindOfClass:[NSBox class]]) {
        NSBox *b = (NSBox *)view;
        if (b.title.length) b.title = Shown(b, @"title", [self translate:Original(b, @"title", b.title)]);
    }
    for (NSView *sub in view.subviews) [self localizeView:sub];
}

@end

#pragma mark - Message boxes

/// Alerts are translated as they are run, by their English text.
@implementation NSAlert (NppLocalization)

+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(runModal));
    Method replacement = class_getInstanceMethod(self, @selector(npp_runModal));
    method_exchangeImplementations(original, replacement);
    method_exchangeImplementations(class_getInstanceMethod(self, @selector(beginSheetModalForWindow:completionHandler:)),
                                   class_getInstanceMethod(self, @selector(npp_beginSheetModalForWindow:completionHandler:)));
}

/// The alert's words in the interface language: the title as a label, the
/// message with its own line breaks, the buttons by their names.
- (void)npp_localize {
    NppLocalization *l = [NppLocalization shared];
    if (!l.active) return;
    self.messageText = [l translate:self.messageText];
    self.informativeText = [l message:self.informativeText string:nil number:0];
    for (NSButton *b in self.buttons) b.title = [l translate:b.title];
}

- (NSModalResponse)npp_runModal {
    [self npp_localize];
    return [self npp_runModal];
}

- (void)npp_beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler {
    [self npp_localize];
    [self npp_beginSheetModalForWindow:window completionHandler:handler];
}

@end
