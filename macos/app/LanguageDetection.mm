#import "LanguageDetection.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import "LanguageModel.h"
#import <objc/runtime.h>

static inline BOOL NppIsDigit(unichar c) { return c >= '0' && c <= '9'; }

/// Only the beginning of a file is read: it is enough to tell what it is, and
/// a whole large file is not worth walking for the answer.
static const NSUInteger kSampleLimit = 64 * 1024;

/// What an interpreter on a shebang line is called here. The name of the
/// program is matched, not the path, so /usr/bin/env python3 works too.
static NSDictionary<NSString *, NSString *> *InterpreterNames(void) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sh": @"bash", @"bash": @"bash", @"zsh": @"bash", @"ksh": @"bash",
            @"dash": @"bash", @"ash": @"bash", @"fish": @"bash",
            @"python": @"python", @"python2": @"python", @"python3": @"python",
            @"perl": @"perl", @"ruby": @"ruby", @"php": @"php",
            @"node": @"javascript", @"nodejs": @"javascript", @"deno": @"javascript",
            @"lua": @"lua", @"tclsh": @"tcl", @"wish": @"tcl", @"expect": @"tcl",
            @"awk": @"nsis", @"gawk": @"nsis",     // awk has no lexer of its own
            @"r": @"r", @"rscript": @"r",
            @"pwsh": @"powershell", @"powershell": @"powershell",
            @"make": @"makefile", @"cmake": @"cmake",
            @"swift": @"swift", @"go": @"go", @"julia": @"julia",
            @"dmd": @"d", @"rdmd": @"d", @"ldc2": @"d",
            @"raku": @"raku", @"perl6": @"raku", @"groovy": @"java", @"scala": @"java",
        };
    });
    return names;
}

/// Names an editor modeline may use for a language that is called something
/// else in Notepad++'s own list.
static NSDictionary<NSString *, NSString *> *ModelineNames(void) {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"sh": @"bash", @"shell-script": @"bash", @"shell": @"bash",
            @"c++": @"cpp", @"csharp": @"cs", @"c#": @"cs",
            @"js": @"javascript", @"jsx": @"javascript", @"ts": @"typescript",
            @"make": @"makefile", @"conf": @"ini", @"cfg": @"ini",
            @"yml": @"yaml", @"md": @"markdown", @"text": @"normal",
        };
    });
    return names;
}

@implementation LanguageCatalog (Detection)

#pragma mark - The sample

- (NSString *)sampleOfContents:(NSString *)text {
    if (text.length <= kSampleLimit) return text;
    // Cut on a character boundary, which substringToIndex: already respects.
    return [text substringToIndex:kSampleLimit];
}

#pragma mark - What the text says outright

- (NppLanguage *)languageNamedForDetection:(NSString *)name {
    if (!name.length) return nil;
    NSString *lower = name.lowercaseString;
    NSString *mapped = ModelineNames()[lower] ?: lower;
    NppLanguage *language = [self languageNamed:mapped];
    return [language.name isEqualToString:@"normal"] ? nil : language;
}

- (NppLanguage *)languageFromShebang:(NSString *)line {
    if (![line hasPrefix:@"#!"]) return nil;
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSString *word in [[line substringFromIndex:2]
                            componentsSeparatedByCharactersInSet:
                                [NSCharacterSet whitespaceCharacterSet]]) {
        if (word.length) [words addObject:word];
    }
    if (!words.count) return nil;

    NSString *program = words.firstObject.lastPathComponent.lowercaseString;
    if ([program isEqualToString:@"env"] && words.count > 1) {
        // "env -S", "env VAR=value python" and the like: the interpreter is the
        // first word that is neither a switch nor an assignment.
        for (NSUInteger i = 1; i < words.count; ++i) {
            NSString *word = words[i];
            if ([word hasPrefix:@"-"] || [word containsString:@"="]) continue;
            program = word.lastPathComponent.lowercaseString;
            break;
        }
    }

    // python3.11 and the like: the version is not part of the name.
    NSString *trimmed = program;
    while (trimmed.length && (NppIsDigit([trimmed characterAtIndex:trimmed.length - 1]) ||
                              [trimmed hasSuffix:@"."])) {
        trimmed = [trimmed substringToIndex:trimmed.length - 1];
    }
    NSString *name = InterpreterNames()[program] ?: InterpreterNames()[trimmed];
    return name ? [self languageNamed:name] : nil;
}

- (NppLanguage *)languageFromModeline:(NSArray<NSString *> *)lines {
    // Emacs writes "-*- mode: python -*-" (or just "-*- python -*-") in the
    // first line; vim writes "vim: set ft=python:" in the first or last few.
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN((NSUInteger)2, lines.count); ++i) {
        [candidates addObject:lines[i]];
    }
    for (NSUInteger i = lines.count > 5 ? lines.count - 5 : 0; i < lines.count; ++i) {
        [candidates addObject:lines[i]];
    }

    for (NSString *line in candidates) {
        NSRange open = [line rangeOfString:@"-*-"];
        if (open.location != NSNotFound) {
            NSRange after = NSMakeRange(NSMaxRange(open), line.length - NSMaxRange(open));
            NSRange close = [line rangeOfString:@"-*-" options:0 range:after];
            if (close.location != NSNotFound) {
                NSString *body = [line substringWithRange:
                    NSMakeRange(after.location, close.location - after.location)];
                NSString *mode = body;
                NSRange marker = [body rangeOfString:@"mode:" options:NSCaseInsensitiveSearch];
                if (marker.location != NSNotFound) {
                    mode = [body substringFromIndex:NSMaxRange(marker)];
                }
                mode = [mode componentsSeparatedByString:@";"].firstObject;
                mode = [mode stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                NppLanguage *found = [self languageNamedForDetection:mode];
                if (found) return found;
            }
        }

        for (NSString *key in @[@"filetype=", @"ft=", @"syntax="]) {
            NSRange marker = [line rangeOfString:key options:NSCaseInsensitiveSearch];
            if (marker.location == NSNotFound) continue;
            NSString *rest = [line substringFromIndex:NSMaxRange(marker)];
            NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@" \t:;\"'"];
            NSRange end = [rest rangeOfCharacterFromSet:stop];
            NSString *mode = end.location == NSNotFound ? rest
                                                        : [rest substringToIndex:end.location];
            NppLanguage *found = [self languageNamedForDetection:mode];
            if (found) return found;
        }
    }
    return nil;
}

- (NppLanguage *)declaredLanguageInContents:(NSString *)text {
    NSString *sample = [self sampleOfContents:text];
    if (!sample.length) return nil;
    NSArray<NSString *> *lines = [sample componentsSeparatedByCharactersInSet:
                                  [NSCharacterSet newlineCharacterSet]];

    NppLanguage *shebang = [self languageFromShebang:lines.firstObject ?: @""];
    if (shebang) return shebang;

    NSString *head = [sample substringToIndex:MIN((NSUInteger)512, sample.length)];
    NSString *lead = [head stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([lead hasPrefix:@"<?php"]) return [self languageNamed:@"php"];
    if ([lead hasPrefix:@"<?xml"]) return [self languageNamed:@"xml"];
    if ([head rangeOfString:@"<!DOCTYPE html" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [head rangeOfString:@"<html" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return [self languageNamed:@"html"];
    }

    NppLanguage *modeline = [self languageFromModeline:lines];
    if (modeline) return modeline;

    // JSON is worth parsing for: nothing else both starts this way and holds
    // together as JSON, and the keyword scoring has nothing to go on in it.
    if ([lead hasPrefix:@"{"] || [lead hasPrefix:@"["]) {
        NSData *data = [sample dataUsingEncoding:NSUTF8StringEncoding];
        if (data && [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]) {
            return [self languageNamed:@"json"];
        }
    }
    return nil;
}

#pragma mark - The answer

- (NSArray<NppLanguage *> *)languagesMatchingContents:(NSString *)text {
    // What a file says about itself outright is taken as given. A shebang line
    // is not a guess, and no amount of training beats reading it.
    NppLanguage *declared = [self declaredLanguageInContents:text];
    if (declared) return @[declared];

    // Everything else is the trained model's to say: one language, a short
    // list, or nothing. There are no hand-written marks or keyword rules
    // beside it - what it gets wrong is put right in its training data.
    return [self languagesFromModelForContents:text] ?: @[];
}

/// What the trained model makes of the text, as the set it was fitted to
/// offer. nil when there is no model or the text is too little to judge.
- (NSArray<NppLanguage *> *)languagesFromModelForContents:(NSString *)text {
    NppLanguageModel *model = [NppLanguageModel sharedModel];
    if (!model) return nil;
    NSArray<NSString *> *offered = [model languagesOfferedForText:text];
    if (!offered) return nil;
    NSMutableArray<NppLanguage *> *fitting = [NSMutableArray array];
    for (NSString *name in offered) {
        NppLanguage *language = [self languageNamed:name];
        if (language && ![language.name isEqualToString:@"normal"]) [fitting addObject:language];
    }
    return fitting;
}


- (NppLanguage *)languageForContents:(NSString *)text {
    NSArray<NppLanguage *> *fitting = [self languagesMatchingContents:text];
    if (fitting.count != 1) return nil;
    return fitting.firstObject;
}

@end

@implementation EditorController (LanguageDetection)

// One key for both accessors. A static declared inside each of them is two
// variables at two addresses, and what the setter stored the getter could
// never find: the handler read back as nil, and no choice was ever shown.
static const char kLanguageChoiceHandlerKey = 0;

- (void (^)(NSArray<NppLanguage *> *))languageChoiceHandler {
    return objc_getAssociatedObject(self, &kLanguageChoiceHandlerKey);
}

- (void)setLanguageChoiceHandler:(void (^)(NSArray<NppLanguage *> *))handler {
    objc_setAssociatedObject(self, &kLanguageChoiceHandlerKey, handler, OBJC_ASSOCIATION_COPY);
}

/// Why nothing was suggested, or nil when something could be. One line in
/// the system log per decision: "nothing happened" is otherwise impossible
/// to tell apart from "nothing was asked".
- (NSString *)reasonNotToSuggestForDocument:(NppDocument *)doc {
    if (![NppPreferences shared].detectLanguageFromContent) return @"the setting is off";
    if (!doc) return @"no document";
    if (doc.languageChosenByUser) return @"the language was chosen by hand";
    // Only where the name has nothing to say. A file called script.py is that
    // language whatever its contents look like.
    if (doc.path.pathExtension.length) return @"the name has an extension";
    if (doc.language && ![doc.language.name isEqualToString:@"normal"]) {
        return [NSString stringWithFormat:@"the language is already %@", doc.language.name];
    }
    return nil;
}

- (NSArray<NppLanguage *> *)languagesSuggestedForCurrentDocument {
    NppDocument *doc = self.currentDocument;
    NSString *reason = [self reasonNotToSuggestForDocument:doc];
    if (reason) {
        NSLog(@"language detection: not asked, %@", reason);
        return @[];
    }
    NSArray<NppLanguage *> *fitting =
        [[LanguageCatalog sharedCatalog] languagesMatchingContents:[self.sci string] ?: @""];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NppLanguage *one in fitting) [names addObject:one.name];
    NSLog(@"language detection: %lu characters, offered [%@]",
          (unsigned long)[self.sci string].length, [names componentsJoinedByString:@", "]);
    return fitting;
}

- (NppLanguage *)detectLanguageOfCurrentDocumentOffering:
    (void (^)(NSArray<NppLanguage *> *))chooser {

    NSArray<NppLanguage *> *fitting = [self languagesSuggestedForCurrentDocument];
    if (!fitting.count) return nil;

    // One answer is an answer: it is applied without asking.
    if (fitting.count == 1) {
        [self setLanguageNamed:fitting.firstObject.name];
        return fitting.firstObject;
    }
    if (chooser) chooser(fitting);
    return nil;
}

@end
