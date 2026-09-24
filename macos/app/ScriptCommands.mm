#import "ScriptCommands.h"
#import "RunCommands.h"
#import "SettingsCommands.h"
#import "ScintillaView.h"
#import "Scintilla.h"

#pragma mark - Saved scripts

@implementation NppSavedScript

+ (instancetype)scriptNamed:(NSString *)name text:(NSString *)text {
    NppSavedScript *s = [NppSavedScript new];
    s.name = name ?: @"";
    s.text = text ?: @"";
    return s;
}

+ (NSArray<NppSavedScript *> *)scriptsFromSavedText:(NSString *)text {
    NSMutableArray *out = [NSMutableArray array];
    __block NppSavedScript *current = nil;
    __block NSMutableArray *lines = nil;
    void (^finish)(void) = ^{
        if (!current) return;
        while (lines.count && ![[lines.lastObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] length]) {
            [lines removeLastObject];
        }
        current.text = [lines componentsJoinedByString:@"\n"];
        [out addObject:current];
    };
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        if ([raw hasPrefix:@"::"]) {
            finish();
            current = [NppSavedScript scriptNamed:[[raw substringFromIndex:2]
                          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] text:@""];
            lines = [NSMutableArray array];
        } else if (current) {
            [lines addObject:raw];
        }
    }
    finish();
    return out;
}

+ (NSString *)savedTextForScripts:(NSArray<NppSavedScript *> *)scripts {
    NSMutableString *out = [NSMutableString string];
    for (NppSavedScript *s in scripts) [out appendFormat:@"::%@\n%@\n", s.name, s.text];
    return out;
}

@end

#pragma mark - Engine

static void OnMain(dispatch_block_t block) {
    if (NSThread.isMainThread) block(); else dispatch_sync(dispatch_get_main_queue(), block);
}

static NSString *Trimmed(NSString *s) {
    return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

/// An argument written in quotes loses them, as NppExec reads it.
static NSString *Unquoted(NSString *s) {
    NSString *t = Trimmed(s);
    if (t.length >= 2 && [t hasPrefix:@"\""] && [t hasSuffix:@"\""]) return [t substringWithRange:NSMakeRange(1, t.length - 2)];
    return t;
}

/// "name" from "name", "$(name)" or " name ", upper-cased: NppExec's variables
/// are not case-sensitive.
static NSString *VariableKey(NSString *s) {
    NSString *t = Trimmed(s);
    if ([t hasPrefix:@"$("] && [t hasSuffix:@")"]) t = [t substringWithRange:NSMakeRange(2, t.length - 3)];
    return t.uppercaseString;
}

@interface NppScriptEngine ()
@property (nonatomic, weak) EditorController *editor;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *variables;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *environment;
/// Variables whose text is the script author's own (SET from literals and from
/// other such variables): they go into a command line as written, the way
/// NppExec substitutes, so "SET flags = -O2 -Wall" is two arguments. Anything
/// that came from the document, the clipboard, a program or the user is quoted.
@property (nonatomic, strong) NSMutableSet<NSString *> *plainVariables;
@property (nonatomic, strong) NSMutableString *output;
@property (nonatomic) NSUInteger steps;
@property (nonatomic) NSUInteger depth;
@property (nonatomic) BOOL exitRequested;
@property (nonatomic) BOOL exitEverything;      // EXIT 1 / EXIT -1: the calling scripts end too
@end

@implementation NppScriptEngine

- (instancetype)initWithEditor:(EditorController *)editor {
    if ((self = [super init])) {
        _editor = editor;
        _variables = [NSMutableDictionary dictionary];
        _environment = [NSMutableDictionary dictionary];
        _plainVariables = [NSMutableSet set];
        _output = [NSMutableString string];
        _stepLimit = 100000;
        __block NSString *dir = nil;
        OnMain(^{ dir = [editor runVariableNamed:@"CURRENT_DIRECTORY"]; });
        BOOL isDir = NO;
        _directory = dir.length && [[NSFileManager defaultManager] fileExistsAtPath:dir isDirectory:&isDir] && isDir
            ? dir : NSHomeDirectory();
    }
    return self;
}

- (NSString *)log {
    @synchronized (self) { return [self.output copy]; }
}

/// Into the log only: the console has it already.
- (void)record:(NSString *)text {
    NSString *line = [text hasSuffix:@"\n"] ? text : [text stringByAppendingString:@"\n"];
    @synchronized (self) { [self.output appendString:line]; }
}

- (void)print:(NSString *)text {
    NSString *line = [text hasSuffix:@"\n"] ? text : [text stringByAppendingString:@"\n"];
    @synchronized (self) { [self.output appendString:line]; }
    EditorController *editor = self.editor;
    OnMain(^{ [[editor console] appendText:line]; });
}

#pragma mark Variables

- (NSString *)valueOfVariable:(NSString *)rawName {
    NSString *name = VariableKey(rawName);
    NSString *mine = self.variables[name];
    if (mine) return mine;
    if ([name hasPrefix:@"SYS."]) {
        // The environment's names keep their case; "$(SYS.PATH)" and "SYS.PATH" both ask for PATH.
        NSString *written = Trimmed(rawName);
        if ([written hasPrefix:@"$("] && [written hasSuffix:@")"]) written = [written substringWithRange:NSMakeRange(2, written.length - 3)];
        NSString *key = [written substringFromIndex:4];
        return self.environment[key] ?: [NSProcessInfo processInfo].environment[key] ?: @"";
    }
    // $(#0) is the program, $(#N) the Nth open file.
    if ([name hasPrefix:@"#"]) {
        NSInteger n = [name substringFromIndex:1].integerValue;
        __block NSString *path = @"";
        EditorController *editor = self.editor;
        OnMain(^{
            if (n == 0) path = [NSBundle mainBundle].executablePath ?: @"";
            else if (n <= (NSInteger)editor.documents.count) {
                NppDocument *doc = editor.documents[(NSUInteger)n - 1];
                path = doc.path ?: doc.displayName ?: @"";
            }
        });
        return path;
    }
    __block NSString *value = nil;
    EditorController *editor = self.editor;
    OnMain(^{
        if ([name isEqualToString:@"SELECTED_TEXT"]) value = [editor.sci selectedString] ?: @"";
        else if ([name isEqualToString:@"CLIPBOARD_TEXT"]) value = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"";
        else if ([name isEqualToString:@"PLUGINS_CONFIG_DIR"]) value = [editor supportDirectory];
        else if ([name isEqualToString:@"CWD"]) value = self.directory;
        else value = [editor runVariableNamed:name];
    });
    return value;
}

/// $(…) in a line, by the script's variables first and then Notepad++'s;
/// quoted for the shell only when the line goes to the shell.
- (BOOL)isWrittenByTheAuthor:(NSString *)raw {
    NSRegularExpression *reference = [NSRegularExpression regularExpressionWithPattern:@"\\$\\(([^)]*)\\)" options:0 error:NULL];
    for (NSTextCheckingResult *m in [reference matchesInString:raw options:0 range:NSMakeRange(0, raw.length)]) {
        if (![self.plainVariables containsObject:VariableKey([raw substringWithRange:[m rangeAtIndex:1]])]) return NO;
    }
    return YES;
}

- (NSString *)expand:(NSString *)written forShell:(BOOL)shell {
    NSString *text = written;
    if (shell && self.plainVariables.count) {
        // The author's own variables first, as plain text.
        NSMutableString *filled = [text mutableCopy];
        for (NSUInteger pass = 0; pass < 8; ++pass) {
            BOOL changed = NO;
            for (NSString *key in self.plainVariables) {
                NSString *value = self.variables[key];
                if (!value) continue;
                NSRange r;
                NSString *token = [NSString stringWithFormat:@"$(%@)", key];
                while ((r = [filled rangeOfString:token options:NSCaseInsensitiveSearch]).location != NSNotFound) {
                    [filled replaceCharactersInRange:r withString:value];
                    changed = YES;
                }
            }
            if (!changed) break;
        }
        text = filled;
    }
    __block NSString *out = text;
    EditorController *editor = self.editor;
    NSString *(^lookup)(NSString *) = ^NSString *(NSString *name) {
        NSString *key = VariableKey(name);
        if (self.variables[key]) return self.variables[key];
        if ([key hasPrefix:@"SYS."] || [key hasPrefix:@"#"] || [key isEqualToString:@"SELECTED_TEXT"] ||
            [key isEqualToString:@"CLIPBOARD_TEXT"] || [key isEqualToString:@"PLUGINS_CONFIG_DIR"] || [key isEqualToString:@"CWD"]) {
            return [self valueOfVariable:name];
        }
        return nil;
    };
    OnMain(^{ out = [editor expandRunVariables:text lookup:lookup quoteForShell:shell]; });
    return out;
}

#pragma mark Running

- (BOOL)runScript:(NSString *)text arguments:(NSArray<NSString *> *)arguments {
    if (self.depth >= 16) { [self print:@"- NPP_EXEC: scripts call each other too deeply"]; return NO; }
    NSDictionary *savedArgs = [self argumentVariables];
    [self setArguments:arguments];
    self.depth++;
    BOOL ok = [self runLines:[text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]];
    self.depth--;
    // A plain EXIT ends the script it is in and the caller goes on (NppExec's "soft" exit).
    if (self.exitRequested && !self.exitEverything) self.exitRequested = NO;
    for (NSString *k in [self.variables.allKeys copy]) if ([k hasPrefix:@"ARGV"] || [k isEqualToString:@"ARGC"]) [self.variables removeObjectForKey:k];
    [self.variables addEntriesFromDictionary:savedArgs];
    if (self.depth == 0) self.exitRequested = self.exitEverything = NO;
    return ok;
}

- (NSDictionary *)argumentVariables {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in self.variables) if ([k hasPrefix:@"ARGV"] || [k isEqualToString:@"ARGC"]) d[k] = self.variables[k];
    return d;
}

- (void)setArguments:(NSArray<NSString *> *)arguments {
    for (NSString *k in [self.variables.allKeys copy]) if ([k hasPrefix:@"ARGV"] || [k isEqualToString:@"ARGC"]) [self.variables removeObjectForKey:k];
    self.variables[@"ARGC"] = [NSString stringWithFormat:@"%lu", (unsigned long)arguments.count];
    self.variables[@"ARGV"] = [arguments componentsJoinedByString:@" "];
    [arguments enumerateObjectsUsingBlock:^(NSString *a, NSUInteger i, BOOL *stop) {
        self.variables[[NSString stringWithFormat:@"ARGV[%lu]", (unsigned long)i + 1]] = a;
    }];
}

/// The first word, upper-cased, and the rest of a line.
static void Split(NSString *line, NSString **word, NSString **rest) {
    NSString *t = Trimmed(line);
    NSRange space = [t rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
    *word = (space.location == NSNotFound ? t : [t substringToIndex:space.location]).uppercaseString;
    *rest = space.location == NSNotFound ? @"" : Trimmed([t substringFromIndex:space.location]);
}

/// Whether an IF line is the block form (no GOTO on it).
static BOOL IsBlockIf(NSString *rest) {
    return [rest.uppercaseString rangeOfString:@" GOTO "].location == NSNotFound;
}

- (BOOL)runLines:(NSArray<NSString *> *)lines {
    // Labels are known before the first line runs, so GOTO can jump forward.
    NSMutableDictionary<NSString *, NSNumber *> *labels = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    NSMutableArray<NSString *> *rests = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger i, BOOL *stop) {
        NSString *w, *r;
        Split(line, &w, &r);
        [words addObject:w];
        [rests addObject:r];
        if ([w isEqualToString:@"LABEL"]) labels[Trimmed(r).uppercaseString] = @(i);
        else if ([w hasPrefix:@":"] && w.length > 1 && ![w hasPrefix:@"::"]) labels[[w substringFromIndex:1]] = @(i);
    }];

    NSUInteger i = 0;
    while (i < lines.count) {
        if (self.cancelled || self.exitRequested) return YES;
        if (++self.steps > self.stepLimit) { [self print:@"- the script was stopped: too many steps (an endless loop?)"]; return NO; }
        NSString *word = words[i], *rest = rests[i];
        NSUInteger next = i + 1;
        if (!word.length || [word hasPrefix:@"//"] || [word isEqualToString:@"LABEL"] || [word hasPrefix:@":"] ||
            [word isEqualToString:@"ENDIF"]) {
            i = next;
            continue;
        }
        if ([word isEqualToString:@"GOTO"]) {
            NSNumber *target = labels[Trimmed([self expand:rest forShell:NO]).uppercaseString];
            if (!target) { [self print:[NSString stringWithFormat:@"- GOTO: no label \"%@\"", rest]]; return NO; }
            i = target.unsignedIntegerValue + 1;
            continue;
        }
        if ([word isEqualToString:@"IF"] || [word isEqualToString:@"ELSE"]) {
            BOOL elseLine = [word isEqualToString:@"ELSE"];
            if (elseLine) {
                // Reached from the branch that ran: the rest of the IF is skipped.
                i = [self indexAfterEndIfFrom:i + 1 words:words rests:rests];
                continue;
            }
            NSString *condition = rest;
            NSString *label = nil;
            NSRange go = [rest.uppercaseString rangeOfString:@" GOTO " options:NSBackwardsSearch];
            if (go.location != NSNotFound) {
                condition = [rest substringToIndex:go.location];
                label = Trimmed([rest substringFromIndex:NSMaxRange(go)]);
            }
            NSNumber *truth = [self evaluateCondition:condition];
            if (!truth) return NO;
            if (label) {
                if (truth.boolValue) {
                    NSNumber *target = labels[[self expand:label forShell:NO].uppercaseString];
                    if (!target) { [self print:[NSString stringWithFormat:@"- IF: no label \"%@\"", label]]; return NO; }
                    i = target.unsignedIntegerValue + 1;
                } else {
                    i = next;
                }
                continue;
            }
            i = truth.boolValue ? next : [self indexOfNextBranchFrom:i + 1 words:words rests:rests];
            continue;
        }
        if (![self runCommand:word rest:rest line:lines[i]]) return NO;
        i = next;
    }
    return YES;
}

/// From a false IF: past the next ELSE (whose ELSE IF is weighed then), or
/// past the ENDIF, at this nesting.
- (NSUInteger)indexOfNextBranchFrom:(NSUInteger)start words:(NSArray *)words rests:(NSArray *)rests {
    NSInteger depth = 0;
    for (NSUInteger i = start; i < words.count; ++i) {
        NSString *w = words[i], *r = rests[i];
        if ([w isEqualToString:@"IF"] && IsBlockIf(r)) depth++;
        else if ([w isEqualToString:@"ENDIF"]) { if (depth == 0) return i + 1; depth--; }
        else if ([w isEqualToString:@"ELSE"] && depth == 0) {
            NSString *cw, *cr;
            Split(r, &cw, &cr);
            if ([cw isEqualToString:@"IF"]) {
                NSNumber *truth = [self evaluateCondition:cr];
                if (truth.boolValue) return i + 1;
                continue;
            }
            return i + 1;
        }
    }
    return words.count;
}

- (NSUInteger)indexAfterEndIfFrom:(NSUInteger)start words:(NSArray *)words rests:(NSArray *)rests {
    NSInteger depth = 0;
    for (NSUInteger i = start; i < words.count; ++i) {
        NSString *w = words[i], *r = rests[i];
        if ([w isEqualToString:@"IF"] && IsBlockIf(r)) depth++;
        else if ([w isEqualToString:@"ENDIF"]) { if (depth == 0) return i + 1; depth--; }
    }
    return words.count;
}

/// "a == b" and the rest of NppExec's comparisons; numbers compare as numbers.
- (NSNumber *)evaluateCondition:(NSString *)written {
    // NppExec's block form ends in THEN.
    NSString *condition = Trimmed(written);
    if (condition.length > 5 && [[condition substringFromIndex:condition.length - 5].uppercaseString isEqualToString:@" THEN"]) {
        condition = Trimmed([condition substringToIndex:condition.length - 5]);
    }
    // The operator is found in what was written, outside quotes and $( ),
    // and only then are the sides filled in: a value holding "==" or "<" is
    // not the comparison.
    NSRange found = NSMakeRange(NSNotFound, 0);
    BOOL quoted = NO;
    NSInteger variable = 0;
    for (NSUInteger i = 0; i < condition.length && found.location == NSNotFound; ++i) {
        unichar ch = [condition characterAtIndex:i];
        if (ch == '"') { quoted = !quoted; continue; }
        if (ch == '$' && i + 1 < condition.length && [condition characterAtIndex:i + 1] == '(') { variable++; i++; continue; }
        if (ch == ')' && variable > 0) { variable--; continue; }
        if (quoted || variable > 0) continue;
        for (NSString *op in @[@"==", @"!=", @"<>", @">=", @"<=", @"=", @">", @"<"]) {
            if (i + op.length <= condition.length && [[condition substringWithRange:NSMakeRange(i, op.length)] isEqualToString:op]) {
                found = NSMakeRange(i, op.length);
                break;
            }
        }
    }
    if (found.location != NSNotFound) {
        NSString *op = [condition substringWithRange:found];
        NSRange r = found;
        NSString *c = condition;
        NSString *a = Unquoted([self expand:[c substringToIndex:r.location] forShell:NO]);
        NSString *b = Unquoted([self expand:[c substringFromIndex:NSMaxRange(r)] forShell:NO]);
        NSScanner *sa = [NSScanner scannerWithString:a], *sb = [NSScanner scannerWithString:b];
        double x = 0, y = 0;
        NSComparisonResult order;
        if ([sa scanDouble:&x] && sa.atEnd && [sb scanDouble:&y] && sb.atEnd) {
            order = x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
        } else {
            order = [a compare:b];
        }
        BOOL t = [op isEqualToString:@"=="] || [op isEqualToString:@"="] ? order == NSOrderedSame
               : [op isEqualToString:@"!="] || [op isEqualToString:@"<>"] ? order != NSOrderedSame
               : [op isEqualToString:@">="] ? order != NSOrderedAscending
               : [op isEqualToString:@"<="] ? order != NSOrderedDescending
               : [op isEqualToString:@">"] ? order == NSOrderedDescending : order == NSOrderedAscending;
        return @(t);
    }
    [self print:[NSString stringWithFormat:@"- IF: no comparison in \"%@\"", condition]];
    return nil;
}

/// SET x ~ 2 * (3 + 4): arithmetic only, so nothing else can be evaluated.
- (NSString *)calculate:(NSString *)expression {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.+-*/() \t"];
    NSString *e = Trimmed(expression);
    if (!e.length || [e rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) return nil;
    @try {
        // Written as decimals so that 7 / 2 is 3.5, as NppExec's calculator gives.
        NSMutableString *decimal = [NSMutableString string];
        NSScanner *scan = [NSScanner scannerWithString:e];
        scan.charactersToBeSkipped = nil;
        NSCharacterSet *digits = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];
        while (!scan.atEnd) {
            NSString *number = nil, *other = nil;
            if ([scan scanCharactersFromSet:digits intoString:&number]) {
                [decimal appendString:[number containsString:@"."] ? number : [number stringByAppendingString:@".0"]];
            } else if ([scan scanUpToCharactersFromSet:digits intoString:&other]) {
                [decimal appendString:other];
            }
        }
        NSNumber *n = [[NSExpression expressionWithFormat:decimal] expressionValueWithObject:nil context:nil];
        if (![n isKindOfClass:[NSNumber class]]) return nil;
        double v = n.doubleValue;
        if (isnan(v) || isinf(v)) return nil;
        if (v == floor(v) && fabs(v) < 1e15) return [NSString stringWithFormat:@"%lld", (long long)v];
        return [NSString stringWithFormat:@"%.10g", v];
    } @catch (NSException *) {
        return nil;
    }
}

- (NSString *)absolutePath:(NSString *)path {
    NSString *p = [Unquoted(path) stringByExpandingTildeInPath];
    if (!p.length) return p;
    return p.isAbsolutePath ? p.stringByStandardizingPath : [self.directory stringByAppendingPathComponent:p].stringByStandardizingPath;
}

/// The open document a script names by its path or its file name.
- (NSInteger)indexOfDocumentNamed:(NSString *)name {
    NSString *full = [self absolutePath:name];
    __block NSInteger found = -1;
    EditorController *editor = self.editor;
    OnMain(^{
        [editor.documents enumerateObjectsUsingBlock:^(NppDocument *d, NSUInteger i, BOOL *stop) {
            // (A message to nil compares as the same, so an untitled tab is asked by its name only.)
            NSString *want = Unquoted(name);
            BOOL byPath = d.path && ([d.path isEqualToString:full] || [d.path.lastPathComponent caseInsensitiveCompare:want] == NSOrderedSame);
            BOOL byName = !d.path && d.displayName && [d.displayName caseInsensitiveCompare:want] == NSOrderedSame;
            if (byPath || byName) { found = (NSInteger)i; *stop = YES; }
        }];
    });
    return found;
}

- (BOOL)runCommand:(NSString *)word rest:(NSString *)rawRest line:(NSString *)line {
    EditorController *editor = self.editor;
    // Variables in the arguments are NppExec's, filled in as written; SET's name is not.
    NSString *rest = [word isEqualToString:@"SET"] || [word isEqualToString:@"UNSET"] ||
                     [word isEqualToString:@"ENV_SET"] || [word isEqualToString:@"ENV_UNSET"]
                     ? rawRest : [self expand:rawRest forShell:NO];

    if ([word isEqualToString:@"ECHO"]) { [self print:rest]; return YES; }
    if ([word isEqualToString:@"CLS"]) {
        @synchronized (self) { [self.output setString:@""]; }
        OnMain(^{ [[editor console] clear]; });
        return YES;
    }
    if ([word isEqualToString:@"EXIT"]) {
        self.exitRequested = YES;
        self.exitEverything = Trimmed(rest).integerValue != 0;
        return YES;
    }
    if ([word isEqualToString:@"CD"]) {
        if (!rest.length) { [self print:[NSString stringWithFormat:@"Current directory: %@", self.directory]]; return YES; }
        NSString *dir = [self absolutePath:rest];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:dir isDirectory:&isDir] || !isDir) {
            [self print:[NSString stringWithFormat:@"- CD: no such folder: %@", dir]];
            return NO;
        }
        self.directory = dir;
        [self print:[NSString stringWithFormat:@"CD: %@", dir]];
        return YES;
    }
    if ([word isEqualToString:@"SET"] || [word isEqualToString:@"ENV_SET"]) {
        BOOL env = [word isEqualToString:@"ENV_SET"];
        NSString *body = rawRest;
        if ([body.uppercaseString hasPrefix:@"LOCAL "]) body = [body substringFromIndex:6];
        NSRange eq = [body rangeOfString:@"="], calc = [body rangeOfString:@"~"];
        BOOL isCalc = calc.location != NSNotFound && (eq.location == NSNotFound || calc.location < eq.location);
        NSRange sep = isCalc ? calc : eq;
        if (sep.location == NSNotFound) {
            // SET alone lists the variables; SET name shows one.
            if (!Trimmed(body).length) {
                NSDictionary *all = env ? self.environment : self.variables;
                for (NSString *k in [all.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                    [self print:[NSString stringWithFormat:@"%@ = %@", env ? k : [NSString stringWithFormat:@"$(%@)", k], all[k]]];
                }
            } else {
                NSString *v = env ? (self.environment[Trimmed(body)] ?: NSProcessInfo.processInfo.environment[Trimmed(body)])
                                  : [self valueOfVariable:body];
                [self print:[NSString stringWithFormat:@"%@ = %@", Trimmed(body), v ?: @"(undefined)"]];
            }
            return YES;
        }
        NSString *name = [body substringToIndex:sep.location];
        NSString *value = [self expand:Trimmed([body substringFromIndex:NSMaxRange(sep)]) forShell:NO];
        if (isCalc) {
            NSString *result = [self calculate:value];
            if (!result) { [self print:[NSString stringWithFormat:@"- SET: cannot calculate \"%@\"", value]]; return NO; }
            value = result;
        }
        if (env) self.environment[Trimmed(name)] = value;
        else {
            self.variables[VariableKey(name)] = value;
            if (isCalc || [self isWrittenByTheAuthor:Trimmed([body substringFromIndex:NSMaxRange(sep)])]) [self.plainVariables addObject:VariableKey(name)];
            else [self.plainVariables removeObject:VariableKey(name)];
        }
        return YES;
    }
    if ([word isEqualToString:@"UNSET"]) {
        [self.variables removeObjectForKey:VariableKey(rawRest)];
        [self.plainVariables removeObject:VariableKey(rawRest)];
        return YES;
    }
    if ([word isEqualToString:@"ENV_UNSET"]) { [self.environment removeObjectForKey:Trimmed(rawRest)]; return YES; }
    if ([word isEqualToString:@"SLEEP"]) {
        NSScanner *scan = [NSScanner scannerWithString:rest];
        NSInteger ms = 0;
        [scan scanInteger:&ms];
        NSString *note = Unquoted([rest substringFromIndex:scan.scanLocation]);
        if (note.length) [self print:note];
        for (NSInteger waited = 0; waited < ms && !self.cancelled; waited += 20) usleep(20000);
        return YES;
    }
    if ([word isEqualToString:@"INPUTBOX"]) {
        // INPUTBOX "question" : default
        NSString *prompt = rest, *initial = @"";
        NSRange colon = [rest rangeOfString:@" : "];
        if (colon.location != NSNotFound) { prompt = [rest substringToIndex:colon.location]; initial = [rest substringFromIndex:NSMaxRange(colon)]; }
        prompt = Unquoted(prompt);
        initial = Unquoted(initial);
        __block NSString *answer = nil;
        NSString *_Nullable (^provider)(NSString *, NSString *) = self.inputProvider;
        OnMain(^{
            if (provider) { answer = provider(prompt, initial); return; }
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"NppExec";
            alert.informativeText = prompt;
            NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
            field.stringValue = initial;
            alert.accessoryView = field;
            [alert addButtonWithTitle:@"OK"];
            [alert addButtonWithTitle:@"Cancel"];
            alert.window.initialFirstResponder = field;
            if ([alert runModal] == NSAlertFirstButtonReturn) answer = field.stringValue;
        });
        if (!answer) { [self print:@"- INPUTBOX: cancelled"]; self.exitRequested = YES; return YES; }
        self.variables[@"INPUT"] = answer;
        NSArray *parts = [Trimmed(answer) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        [parts enumerateObjectsUsingBlock:^(NSString *p, NSUInteger i, BOOL *stop) {
            self.variables[[NSString stringWithFormat:@"INPUT[%lu]", (unsigned long)i + 1]] = p;
        }];
        return YES;
    }
    if ([word isEqualToString:@"NPP_OPEN"]) {
        NSString *pattern = [self absolutePath:rest];
        NSMutableArray *paths = [NSMutableArray array];
        if ([pattern rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?"]].location != NSNotFound) {
            NSString *dir = pattern.stringByDeletingLastPathComponent;
            NSPredicate *match = [NSPredicate predicateWithFormat:@"SELF LIKE[c] %@", pattern.lastPathComponent];
            for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]
                                    sortedArrayUsingSelector:@selector(compare:)]) {
                BOOL isDir = NO;
                NSString *full = [dir stringByAppendingPathComponent:f];
                if ([match evaluateWithObject:f] && [[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && !isDir) {
                    [paths addObject:full];
                }
            }
        } else {
            [paths addObject:pattern];
        }
        __block BOOL ok = paths.count > 0;
        for (NSString *path in paths) {
            OnMain(^{ ok = [editor openFileAtPath:path error:NULL] && ok; });
            [self print:[NSString stringWithFormat:@"NPP_OPEN: %@", path]];
        }
        if (!ok) [self print:[NSString stringWithFormat:@"- NPP_OPEN: cannot open %@", pattern]];
        return ok;
    }
    if ([word isEqualToString:@"NPP_SWITCH"] || [word isEqualToString:@"NPP_CLOSE"] || [word isEqualToString:@"NPP_SAVE"]) {
        NSInteger index = -1;
        if (rest.length) {
            index = [self indexOfDocumentNamed:rest];
            if (index < 0) { [self print:[NSString stringWithFormat:@"- %@: no open file \"%@\"", word, rest]]; return NO; }
        }
        __block BOOL ok = YES;
        __block NSString *name = @"";
        OnMain(^{
            if (index >= 0) [editor selectDocumentAtIndex:index];
            name = editor.currentDocument.path ?: editor.currentDocument.displayName ?: @"";
            if ([word isEqualToString:@"NPP_SAVE"]) {
                // An untitled document has nowhere to go without the panel.
                ok = editor.currentDocument.path ? [editor saveCurrentDocument] : NO;
            } else if ([word isEqualToString:@"NPP_CLOSE"]) {
                NSInteger current = (NSInteger)[editor.documents indexOfObject:editor.currentDocument];
                if (current >= 0 && current != NSNotFound) [editor closeDocumentAtIndex:current discardChanges:NO];
            }
        });
        [self print:[NSString stringWithFormat:@"%@: %@%@", word, name, ok ? @"" : @" - failed"]];
        return ok;
    }
    if ([word isEqualToString:@"NPP_SAVEAS"]) {
        NSString *path = [self absolutePath:rest];
        __block BOOL ok = NO;
        OnMain(^{ ok = [editor saveCurrentDocumentAsPath:path]; });
        [self print:[NSString stringWithFormat:@"NPP_SAVEAS: %@%@", path, ok ? @"" : @" - failed"]];
        return ok;
    }
    if ([word isEqualToString:@"NPP_SAVEALL"]) {
        OnMain(^{ [editor saveAllDocuments]; });
        [self print:@"NPP_SAVEALL"];
        return YES;
    }
    if ([word isEqualToString:@"NPP_RUN"]) {
        // ShellExecute's part: a file or an address opens in its application,
        // anything else starts and is left running.
        NSString *target = [self absolutePath:rest];
        NSURL *url = [NSURL URLWithString:Unquoted(rest)];
        if (url.scheme.length > 1 && ![url.scheme isEqualToString:@"file"]) {
            OnMain(^{ [[NSWorkspace sharedWorkspace] openURL:url]; });
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:target]) {
            OnMain(^{ [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:target]]; });
        } else {
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
            task.arguments = @[@"-c", [self expand:rawRest forShell:YES]];
            task.currentDirectoryURL = [NSURL fileURLWithPath:self.directory];
            [task launchAndReturnError:NULL];
        }
        [self print:[NSString stringWithFormat:@"NPP_RUN: %@", rest]];
        return YES;
    }
    if ([word isEqualToString:@"NPP_EXEC"]) {
        // NPP_EXEC "script name or file" arguments…
        NSString *nameOrPath = rest, *args = @"";
        if ([rest hasPrefix:@"\""]) {
            NSRange close = [rest rangeOfString:@"\"" options:0 range:NSMakeRange(1, rest.length - 1)];
            if (close.location != NSNotFound) { nameOrPath = [rest substringWithRange:NSMakeRange(1, close.location - 1)]; args = [rest substringFromIndex:close.location + 1]; }
        } else {
            NSRange space = [rest rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];
            if (space.location != NSNotFound) { nameOrPath = [rest substringToIndex:space.location]; args = [rest substringFromIndex:space.location]; }
        }
        __block NppSavedScript *saved = nil;
        OnMain(^{ saved = [editor savedScriptNamed:nameOrPath]; });
        NSString *text = saved.text ?: [NSString stringWithContentsOfFile:[self absolutePath:nameOrPath] encoding:NSUTF8StringEncoding error:NULL];
        if (!text) { [self print:[NSString stringWithFormat:@"- NPP_EXEC: no script \"%@\"", nameOrPath]]; return NO; }
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *a in [Trimmed(args) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if (a.length) [list addObject:Unquoted(a)];
        }
        return [self runScript:text arguments:list];
    }
    if ([word isEqualToString:@"NPP_MENUCOMMAND"]) {
        __block BOOL ok = NO;
        BOOL (^perform)(NSString *) = self.menuCommandPerformer;
        OnMain(^{ ok = perform ? perform(Unquoted(rest)) : NO; });
        [self print:[NSString stringWithFormat:@"NPP_MENUCOMMAND: %@%@", rest, ok ? @"" : @" - no such command"]];
        return ok;
    }
    if ([word isEqualToString:@"NPP_CONSOLE"]) {
        NSString *how = Trimmed(rest).uppercaseString;
        BOOL hide = [how isEqualToString:@"0"] || [how isEqualToString:@"-"] || [how isEqualToString:@"OFF"];
        OnMain(^{
            NppConsolePanel *console = [editor console];
            if (hide && console.visible) [console toggle];
            else if (!hide) [console showWithoutFocus];
        });
        return YES;
    }
    if ([word isEqualToString:@"SEL_SETTEXT"] || [word isEqualToString:@"SEL_SETTEXT+"]) {
        NSString *text = rest;
        if ([word hasSuffix:@"+"]) {
            text = [[[text stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"]
                     stringByReplacingOccurrencesOfString:@"\\t" withString:@"\t"]
                    stringByReplacingOccurrencesOfString:@"\\r" withString:@"\r"];
        }
        OnMain(^{ [editor.sci message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)text.UTF8String]; });
        return YES;
    }
    if ([word isEqualToString:@"SCI_SENDMSG"]) {
        // Numbers only: SCI_SENDMSG 2024 5 (SCI_GOTOLINE, line 5).
        NSArray *parts = [Trimmed(rest) componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSInteger msg = parts.count ? [parts[0] integerValue] : 0;
        if (msg < 2000) { [self print:@"- SCI_SENDMSG: give the message as a number (2000 and up)"]; return NO; }
        uptr_t w = parts.count > 1 ? (uptr_t)[parts[1] longLongValue] : 0;
        sptr_t l = parts.count > 2 ? (sptr_t)[parts[2] longLongValue] : 0;
        __block sptr_t result = 0;
        OnMain(^{ result = [editor.sci message:(unsigned int)msg wParam:w lParam:l]; });
        self.variables[@"MSG_RESULT"] = [NSString stringWithFormat:@"%ld", (long)result];
        return YES;
    }
    if ([word hasPrefix:@"NPP_"] || [word hasPrefix:@"NPE_"] || [word isEqualToString:@"NPP_SENDMSG"]) {
        [self print:[NSString stringWithFormat:@"- %@ is not available on macOS", word]];
        return YES;
    }

    // Anything else is a program, run to its end in the script's folder, its
    // output in the console and in $(OUTPUT), its status in $(EXITCODE).
    NSString *command = [self expand:Trimmed(line) forShell:YES];
    // The console shows the command and its output as it comes; the log gets
    // the same. No time limit - a build takes what it takes - but Stop ends it.
    [self record:[NSString stringWithFormat:@"%@\nProcess started >>>", command]];
    __weak NppScriptEngine *weakSelf = self;
    EditorController *owner = self.editor;
    OnMain(^{ (void)[owner console]; });                  // the panel is made on the main thread
    NppRunResult *result = [self.editor runExpandedCommandLine:command directory:self.directory
                                                   environment:self.environment intoConsole:YES timeout:0
                                                      stopWhen:^BOOL{ return weakSelf.cancelled; }];
    NSString *output = result.output ?: @"";
    if (output.length) [self record:output];
    // A program whose output does not end its last line (printf '%s|' ...) must not have
    // "<<< Process finished" run on after it: NppExec starts that message on a line of its own.
    BOOL openLine = output.length && ![output hasSuffix:@"\n"] && ![output hasSuffix:@"\r"];
    [self print:[NSString stringWithFormat:@"%@<<< Process finished. (Exit code %d)%@", openLine ? @"\n" : @"",
                 result.exitStatus, result.timedOut ? @" - timed out" : @""]];
    while ([output hasSuffix:@"\n"] || [output hasSuffix:@"\r"]) output = [output substringToIndex:output.length - 1];
    NSArray *outLines = [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    self.variables[@"OUTPUT"] = output;
    self.variables[@"OUTPUT1"] = outLines.firstObject ?: @"";
    self.variables[@"OUTPUTL"] = outLines.lastObject ?: @"";
    self.variables[@"EXITCODE"] = [NSString stringWithFormat:@"%d", result.exitStatus];
    return YES;
}

@end

#pragma mark - Saved scripts on disk

@implementation EditorController (ScriptCommands)

- (NSString *)savedScriptsPath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"npes_saved.txt"];
}

- (NSArray<NppSavedScript *> *)savedScripts {
    NSString *text = [NSString stringWithContentsOfFile:[self savedScriptsPath] encoding:NSUTF8StringEncoding error:NULL];
    return text ? [NppSavedScript scriptsFromSavedText:text] : @[];
}

- (void)writeScripts:(NSArray<NppSavedScript *> *)scripts {
    NSString *path = [self savedScriptsPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    [[NppSavedScript savedTextForScripts:scripts] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)saveScript:(NppSavedScript *)script {
    NSMutableArray *all = [[self savedScripts] mutableCopy];
    NSUInteger at = [all indexOfObjectPassingTest:^BOOL(NppSavedScript *s, NSUInteger i, BOOL *stop) {
        return [s.name isEqualToString:script.name];
    }];
    if (at == NSNotFound) [all addObject:script]; else all[at] = script;
    [self writeScripts:all];
}

- (void)removeScriptNamed:(NSString *)name {
    NSMutableArray *all = [[self savedScripts] mutableCopy];
    [all filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NppSavedScript *s, NSDictionary *b) {
        return ![s.name isEqualToString:name];
    }]];
    [self writeScripts:all];
}

- (NppSavedScript *)savedScriptNamed:(NSString *)name {
    for (NppSavedScript *s in [self savedScripts]) if ([s.name caseInsensitiveCompare:name] == NSOrderedSame) return s;
    return nil;
}

@end
