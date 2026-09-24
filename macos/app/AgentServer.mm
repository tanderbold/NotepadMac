#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#import "AgentServer.h"
#import "TypingCommands.h"
#import "AppDelegate+Testing.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#import "CommandIDs.h"
#import "LanguageCatalog.h"
#import "LanguageDetection.h"
#import "LanguageModel.h"
#import "StyleCatalog.h"
#import "FunctionListCatalog.h"
#import "FindCommands.h"
#import "SearchCommands.h"
#import "CompareCommands.h"
#import "CharsetDetection.h"
#import "ImageCommands.h"
#import "ToolsCommands.h"
#import "NppRegex.h"
#import "SettingsCommands.h"

// What FindCommands.mm keeps to itself and a search from here needs: the
// engine built for a spec (with its flags), and the matches in the document
// in front.
@interface EditorController (FindCommandsForAgents)
- (nullable NppRegex *)regexFor:(NppFindSpec *)spec;
- (NSArray<NSValue *> *)rangesOfMatches:(NppFindSpec *)spec;
@end

static NSString *const kProtocolVersion = @"2025-06-18";
static NSString *const kErrorDomain = @"NppAgentServer";
/// Text handed back in one answer stops here; an agent asks for a line range
/// for more. Well past what any context window takes, still short of a
/// mapped 300 MB log.
static const NSUInteger kMostTextInAnswer = 1000000;
static const NSUInteger kMostMatches = 500;
static const NSUInteger kMostTokens = 4000;

static NSError *Fail(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static NSError *Fail(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: text}];
}

/// A tool's answer made safe for NSJSONSerialization, which raises (and so
/// takes the application down) on NaN, infinities and non-JSON objects.
static id JSONSafe(id value) {
    if (!value || value == [NSNull null] || [value isKindOfClass:[NSString class]]) return value ?: [NSNull null];
    if ([value isKindOfClass:[NSNumber class]]) return isfinite([value doubleValue]) ? value : [NSNull null];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:[value count]];
        for (id v in value) [a addObject:JSONSafe(v)];
        return a;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[value count]];
        for (id k in value) d[[k description]] = JSONSafe(value[k]);
        return d;
    }
    return [value description];
}

#pragma mark - Scintilla helpers

static long Msg(ScintillaView *sci, unsigned int message, uptr_t w = 0, sptr_t l = 0) {
    return (long)[sci message:message wParam:w lParam:l];
}

/// The bytes between two positions, as text.
static NSString *TextBetween(ScintillaView *sci, long start, long end) {
    if (end <= start) return @"";
    std::string buffer((size_t)(end - start) + 1, '\0');
    Sci_TextRangeFull range;
    range.chrg.cpMin = start;
    range.chrg.cpMax = end;
    range.lpstrText = &buffer[0];
    Msg(sci, SCI_GETTEXTRANGEFULL, 0, (sptr_t)&range);
    return [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)(end - start)
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

/// Columns are counted in characters, one-based, as the status bar shows
/// them; positions are Scintilla's bytes. SCI_POSITIONAFTER walks UTF-8.
static long ColumnOfPosition(ScintillaView *sci, long pos) {
    long line = Msg(sci, SCI_LINEFROMPOSITION, (uptr_t)pos);
    long p = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)line), col = 1;
    while (p < pos) { p = Msg(sci, SCI_POSITIONAFTER, (uptr_t)p); col++; }
    return col;
}

static long PositionOfLineColumn(ScintillaView *sci, long line, long column) {
    long lines = Msg(sci, SCI_GETLINECOUNT);
    if (line < 0) line = 0;
    if (line >= lines) return Msg(sci, SCI_GETLENGTH);
    long p = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)line), end = Msg(sci, SCI_GETLINEENDPOSITION, (uptr_t)line);
    for (long col = 1; col < column && p < end; ++col) p = Msg(sci, SCI_POSITIONAFTER, (uptr_t)p);
    return p;
}

static NSDictionary *Place(ScintillaView *sci, long pos) {
    long line = Msg(sci, SCI_LINEFROMPOSITION, (uptr_t)pos);
    return @{@"line": @(line + 1), @"column": @(ColumnOfPosition(sci, pos)), @"position": @(pos)};
}

static NSString *EOLName(int mode) {
    return mode == SC_EOL_CRLF ? @"CRLF" : mode == SC_EOL_CR ? @"CR" : @"LF";
}

static NSString *EncodingName(NppDocument *doc) {
    if (doc.codepage) return [NSString stringWithFormat:@"cp%u", doc.codepage];
    CFStringRef iana = CFStringConvertEncodingToIANACharSetName(
        CFStringConvertNSStringEncodingToEncoding(doc.encoding));
    NSString *name = iana ? [(__bridge NSString *)iana uppercaseString] : @"UTF-8";
    if ([name isEqualToString:@"UTF-8"] && doc.hasBOM) name = @"UTF-8-BOM";
    return name;
}

#pragma mark - Parameters

static id Param(NSDictionary *args, NSString *key) {
    id v = args[key];
    return v == [NSNull null] ? nil : v;
}
static NSString *StringParam(NSDictionary *args, NSString *key) {
    id v = Param(args, key);
    return [v isKindOfClass:[NSString class]] ? v : ([v isKindOfClass:[NSNumber class]] ? [v stringValue] : nil);
}
static BOOL BoolParam(NSDictionary *args, NSString *key, BOOL fallback) {
    id v = Param(args, key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : fallback;
}
static long LongParam(NSDictionary *args, NSString *key, long fallback) {
    id v = Param(args, key);
    return [v isKindOfClass:[NSNumber class]] ? [v longValue] : fallback;
}

/// A JSON schema for one tool, written once here rather than by hand in each.
static NSDictionary *Schema(NSDictionary<NSString *, NSDictionary *> *properties, NSArray<NSString *> *required) {
    return @{@"type": @"object", @"properties": properties, @"required": required ?: @[],
             @"additionalProperties": @NO};
}
static NSDictionary *Prop(NSString *type, NSString *description) {
    return @{@"type": type, @"description": description};
}
static NSDictionary *DocumentProp(void) {
    return @{@"type": @[@"string", @"integer"],
             @"description": @"Which document: omit for the one in front, or an index from list_documents, a full path, or a file name / tab title."};
}

#pragma mark - The server

BOOL NppE2EEnabled(void);   // E2EHooks.mm

@interface NppAgentServer (E2E)
- (void)registerE2ETools;
@end

@interface NppAgentServer ()
@property (nonatomic) int listenFD;
@property (nonatomic, strong) dispatch_source_t acceptSource;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) ScintillaView *hiddenView;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *tools;   // name -> description
@property (nonatomic, copy) NSArray<NSString *> *toolOrder;
@end

typedef NSDictionary *_Nullable (^NppToolBlock)(NSDictionary *args, NSError **error);

@implementation NppAgentServer {
    NSMutableDictionary<NSString *, NppToolBlock> *_handlers;
}

+ (instancetype)shared {
    static NppAgentServer *one;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ one = [[NppAgentServer alloc] init]; });
    return one;
}

+ (NSString *)socketPath {
    NSString *given = NSProcessInfo.processInfo.environment[@"NPPMAC_AGENT_SOCKET"];
    if (given.length) return given;
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                         stringByAppendingPathComponent:@"NotepadMac"];
    return [support stringByAppendingPathComponent:@"agent.sock"];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _listenFD = -1;
    _queue = dispatch_queue_create("org.notepad-plus-plus.mac.agent", DISPATCH_QUEUE_CONCURRENT);
    _handlers = [NSMutableDictionary dictionary];
    [self registerTools];
    [self registerE2ETools];   // only under NPPMAC_E2E=1 (E2EHooks.mm)
    return self;
}

- (BOOL)running { return self.listenFD >= 0; }

#pragma mark Socket

- (BOOL)start {
    if (self.running) return YES;
    NSString *path = [[self class] socketPath];
    struct sockaddr_un addr;
    memset(&addr, 0, sizeof addr);
    addr.sun_family = AF_UNIX;
    if (strlen(path.fileSystemRepresentation) >= sizeof addr.sun_path) {
        NSLog(@"Agent interface: the socket path is too long: %@", path);
        return NO;
    }
    strlcpy(addr.sun_path, path.fileSystemRepresentation, sizeof addr.sun_path);

    // Another instance of the application already serving keeps its socket;
    // a socket file left behind by a crash is replaced.
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        BOOL alive = connect(probe, (struct sockaddr *)&addr, sizeof addr) == 0;
        close(probe);
        if (alive) { NSLog(@"Agent interface: another NotepadMac is serving %@", path); return NO; }
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
                               withIntermediateDirectories:YES
                                                attributes:@{NSFilePosixPermissions: @0700} error:NULL];
    unlink(addr.sun_path);

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    mode_t was = umask(0177);   // the socket is made 0600: the user's processes only
    int bound = bind(fd, (struct sockaddr *)&addr, sizeof addr);
    umask(was);
    if (bound != 0 || listen(fd, 8) != 0) {
        NSLog(@"Agent interface: cannot listen on %@: %s", path, strerror(errno));
        close(fd);
        return NO;
    }
    chmod(addr.sun_path, 0600);
    self.listenFD = fd;

    __weak NppAgentServer *weakSelf = self;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.queue);
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        // A client that goes away before its answer is written must cost a
        // failed write, not a SIGPIPE that kills the whole editor.
        int one = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        dispatch_async(weakSelf.queue, ^{ [weakSelf serveClient:client]; });
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    self.acceptSource = source;
    return YES;
}

- (void)stop {
    if (!self.running) return;
    dispatch_source_cancel(self.acceptSource);
    self.acceptSource = nil;
    self.listenFD = -1;
    unlink([[self class] socketPath].fileSystemRepresentation);
}

/// One connection: a JSON-RPC message per line in, one per line out. Each
/// message is handled on the main thread, where the editor lives; the
/// connection waits for it, which is what the agent expects anyway.
- (void)serveClient:(int)client {
    std::string pending;
    char chunk[65536];
    for (;;) {
        ssize_t got = read(client, chunk, sizeof chunk);
        if (got <= 0) break;
        pending.append(chunk, (size_t)got);
        size_t nl;
        while ((nl = pending.find('\n')) != std::string::npos) {
            std::string line = pending.substr(0, nl);
            pending.erase(0, nl + 1);
            if (line.empty()) continue;
            NSData *data = [NSData dataWithBytes:line.data() length:line.size()];
            id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            __block NSDictionary *reply = nil;
            if ([message isKindOfClass:[NSDictionary class]]) {
                if (NppE2EEnabled()) {
                    // Under the end-to-end suite a request is also served while
                    // a modal runs (the main queue is busy with it then), so a
                    // test can drive an open alert from a second connection.
                    // A timer in the common modes, not a run loop block: when a
                    // request's own block opened the modal, the modal's run loop
                    // runs inside that block, and CFRunLoop does not run the
                    // queued blocks again until it returns - every later request
                    // waited for the alert. Timers fire in the nested loop.
                    dispatch_semaphore_t done = dispatch_semaphore_create(0);
                    NSTimer *serve = [NSTimer timerWithTimeInterval:0 repeats:NO block:^(NSTimer *t) {
                        reply = [self handleMessage:message];
                        dispatch_semaphore_signal(done);
                    }];
                    [[NSRunLoop mainRunLoop] addTimer:serve forMode:NSRunLoopCommonModes];
                    CFRunLoopWakeUp(CFRunLoopGetMain());
                    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
                } else {
                    dispatch_sync(dispatch_get_main_queue(), ^{ reply = [self handleMessage:message]; });
                }
            } else {
                reply = @{@"jsonrpc": @"2.0", @"id": [NSNull null],
                          @"error": @{@"code": @-32700, @"message": @"Parse error"}};
            }
            if (!reply) continue;
            NSMutableData *out = nil;
            @try {
                out = [[NSJSONSerialization dataWithJSONObject:reply options:0 error:NULL] mutableCopy];
            } @catch (NSException *e) {
                NSLog(@"agent: reply not encodable as JSON: %@", e.reason);
                id identifier = [reply[@"id"] isKindOfClass:[NSString class]] || [reply[@"id"] isKindOfClass:[NSNumber class]] ? reply[@"id"] : [NSNull null];
                out = [[NSJSONSerialization dataWithJSONObject:@{@"jsonrpc": @"2.0", @"id": identifier,
                                                                 @"error": @{@"code": @-32603, @"message": @"Internal error: the answer could not be encoded"}}
                                                       options:0 error:NULL] mutableCopy];
            }
            if (!out) continue;
            [out appendBytes:"\n" length:1];
            const char *bytes = (const char *)out.bytes;
            size_t left = out.length;
            while (left) {
                ssize_t wrote = write(client, bytes, left);
                if (wrote <= 0) { left = 0; break; }
                bytes += wrote;
                left -= (size_t)wrote;
            }
        }
    }
    close(client);
}

#pragma mark JSON-RPC

static NSDictionary *RPCError(id identifier, NSInteger code, NSString *message) {
    return @{@"jsonrpc": @"2.0", @"id": identifier ?: [NSNull null],
             @"error": @{@"code": @(code), @"message": message}};
}

- (NSDictionary *)handleMessage:(NSDictionary *)message {
    id identifier = message[@"id"];
    NSString *method = [message[@"method"] isKindOfClass:[NSString class]] ? message[@"method"] : nil;
    NSDictionary *params = [message[@"params"] isKindOfClass:[NSDictionary class]] ? message[@"params"] : @{};
    if (!method) {
        // A response to something the server never asked; nothing to say.
        if (!identifier || message[@"result"] || message[@"error"]) return nil;
        return RPCError(identifier, -32600, @"Invalid Request");
    }
    if ([method hasPrefix:@"notifications/"]) return nil;
    id result = nil;
    if ([method isEqualToString:@"initialize"]) {
        NSString *asked = params[@"protocolVersion"];
        NSArray *known = @[@"2024-11-05", @"2025-03-26", @"2025-06-18"];
        NSString *version = [asked isKindOfClass:[NSString class]] && [known containsObject:asked] ? asked : kProtocolVersion;
        NSString *app = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
        result = @{
            @"protocolVersion": version,
            @"capabilities": @{@"tools": @{@"listChanged": @NO}},
            @"serverInfo": @{@"name": @"NotepadMac", @"title": @"NotepadMac (Notepad++ for macOS)", @"version": app},
            @"instructions":
                @"NotepadMac is the user's text editor, a native macOS port of Notepad++. These tools read and change "
                @"what is open in it - including unsaved text - and use the editor's own engines: the language model "
                @"that tells a text's language, the Lexilla lexers (tokens as the editor colours them), Notepad++'s "
                @"search (Boost regular expressions), the Function List parsers, Compare, uchardet for character sets, "
                @"the system OCR and spelling engines. Lines and columns are one-based; columns count characters. "
                @"Edits go into the editor's buffer with undo; the user saves, unless save_document is asked for. "
                @"Prefer editing an open document over rewriting its file on disk: the user may have unsaved changes."
        };
    } else if ([method isEqualToString:@"ping"]) {
        result = @{};
    } else if ([method isEqualToString:@"tools/list"]) {
        result = @{@"tools": [self toolDescriptions]};
    } else if ([method isEqualToString:@"tools/call"]) {
        NSString *name = [params[@"name"] isKindOfClass:[NSString class]] ? params[@"name"] : @"";
        NSDictionary *args = [params[@"arguments"] isKindOfClass:[NSDictionary class]] ? params[@"arguments"] : @{};
        if (!_handlers[name]) return RPCError(identifier, -32602, [NSString stringWithFormat:@"Unknown tool: %@", name]);
        NSError *error = nil;
        NSDictionary *answer = [self callTool:name arguments:args error:&error];
        if (!answer) {
            result = @{@"content": @[@{@"type": @"text", @"text": error.localizedDescription ?: @"failed"}],
                       @"isError": @YES};
        } else {
            answer = JSONSafe(answer);
            NSData *json = [NSJSONSerialization dataWithJSONObject:answer
                                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                             error:NULL];
            NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{}";
            result = @{@"content": @[@{@"type": @"text", @"text": text}],
                       @"structuredContent": answer, @"isError": @NO};
        }
    } else {
        return RPCError(identifier, -32601, [NSString stringWithFormat:@"Method not found: %@", method]);
    }
    if (!identifier) return nil;
    return @{@"jsonrpc": @"2.0", @"id": identifier, @"result": result};
}

- (NSArray<NSDictionary *> *)toolDescriptions {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in self.toolOrder) [out addObject:self.tools[name]];
    return out;
}

- (NSDictionary *)callTool:(NSString *)name arguments:(NSDictionary *)arguments error:(NSError **)error {
    NppToolBlock handler = _handlers[name];
    if (!handler) { if (error) *error = Fail(@"Unknown tool: %@", name); return nil; }
    if (!self.editor) { if (error) *error = Fail(@"The editor is not up yet"); return nil; }
    NSError *inner = nil;
    NSDictionary *answer = nil;
    @try {
        answer = handler(arguments ?: @{}, &inner);
    } @catch (NSException *e) {
        inner = Fail(@"%@", e.reason ?: e.name);
    }
    if (!answer && !inner) inner = Fail(@"%@ failed", name);
    if (error) *error = inner;
    return answer;
}

- (void)addTool:(NSString *)name description:(NSString *)description schema:(NSDictionary *)schema
        handler:(NppToolBlock)handler {
    NSMutableDictionary *tools = [self.tools mutableCopy] ?: [NSMutableDictionary dictionary];
    tools[name] = @{@"name": name, @"description": description, @"inputSchema": schema};
    self.tools = tools;
    self.toolOrder = [(self.toolOrder ?: @[]) arrayByAddingObject:name];
    _handlers[name] = [handler copy];
}

#pragma mark - Documents

- (NSArray<NppDocument *> *)documents {
    NSMutableArray *docs = [NSMutableArray array];
    for (NppDocument *d in self.editor.documents) if (!d.isSearchResults) [docs addObject:d];
    return docs;
}

/// The document a parameter names; the one in front without one.
- (NppDocument *)documentFor:(id)spec error:(NSError **)error {
    EditorController *ed = self.editor;
    if (!spec || spec == [NSNull null] || ([spec isKindOfClass:[NSString class]] && ![spec length])) {
        if (!ed.currentDocument && error) *error = Fail(@"No document is open");
        return ed.currentDocument;
    }
    if ([spec isKindOfClass:[NSNumber class]] ||
        ([spec isKindOfClass:[NSString class]] && [(NSString *)spec rangeOfCharacterFromSet:
            [NSCharacterSet.decimalDigitCharacterSet invertedSet]].location == NSNotFound)) {
        NSInteger index = [spec integerValue];
        if (index < 0 || index >= (NSInteger)ed.documents.count) {
            if (error) *error = Fail(@"No document at index %ld (list_documents shows %lu)", (long)index, (unsigned long)ed.documents.count);
            return nil;
        }
        return ed.documents[(NSUInteger)index];
    }
    if (![spec isKindOfClass:[NSString class]]) { if (error) *error = Fail(@"document must be an index, a path or a name"); return nil; }
    NSString *want = [(NSString *)spec stringByStandardizingPath];
    for (NppDocument *d in self.documents) if (d.path && [d.path isEqualToString:want]) return d;
    for (NppDocument *d in self.documents) {
        if ([d.displayName isEqualToString:spec] || [d.path.lastPathComponent isEqualToString:spec]) return d;
    }
    if ([spec isEqualToString:@"current"]) return ed.currentDocument;
    if (error) *error = Fail(@"No open document is %@", spec);
    return nil;
}

/// Reads a document through a view of its own, so the one in front is not
/// disturbed: a Scintilla document carries its text, its styling and its
/// lexer, and any view can look at it.
- (void)readDocument:(NppDocument *)doc using:(void (^)(ScintillaView *sci))block {
    EditorController *ed = self.editor;
    if (doc == ed.currentDocument) { block(ed.sci); return; }
    if (!self.hiddenView) self.hiddenView = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    Msg(self.hiddenView, SCI_SETDOCPOINTER, 0, (sptr_t)doc.docPointer);
    block(self.hiddenView);
    Msg(self.hiddenView, SCI_SETDOCPOINTER, 0, 0);
}

/// Changes go through the view in front, which is what keeps the modified
/// flag, the bookmarks and the fold state of a document; the tab is put
/// back afterwards and the recent order is kept, as a search across open
/// documents does it.
- (void)withDocumentInFront:(NppDocument *)doc do:(void (^)(ScintillaView *sci))block {
    EditorController *ed = self.editor;
    NppDocument *front = ed.currentDocument;
    if (doc == front) { block(ed.sci); return; }
    NSUInteger index = [ed.documents indexOfObjectIdenticalTo:doc];
    if (index == NSNotFound) return;
    NSArray *recent = [ed documentsInRecentOrder];
    NppDocument *previous = [ed previousTab];
    [ed selectDocumentAtIndex:(NSInteger)index];
    block(ed.sci);
    NSUInteger back = front ? [ed.documents indexOfObjectIdenticalTo:front] : NSNotFound;
    if (back != NSNotFound) [ed selectDocumentAtIndex:(NSInteger)back];
    [ed setValue:[recent mutableCopy] forKey:@"mru"];
    if (previous) [ed rememberPreviousTab:previous];
}

- (NSDictionary *)infoOf:(NppDocument *)doc {
    EditorController *ed = self.editor;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"index"] = @([ed.documents indexOfObjectIdenticalTo:doc]);
    info[@"title"] = [self.editor untitledNameForDocument:doc] ?: @"";   // the tab's title, a first-line name included
    info[@"path"] = doc.path ?: [NSNull null];
    info[@"language"] = doc.language.name ?: @"normal";
    info[@"language_title"] = [LanguageCatalog menuTitleForLanguage:doc.language.name ?: @"normal"];
    info[@"modified"] = @(doc.modified);
    info[@"current"] = @(doc == ed.currentDocument);
    info[@"encoding"] = EncodingName(doc);
    info[@"eol"] = EOLName(doc.eolMode);
    info[@"read_only"] = @(doc.userReadOnly || doc.monitoring);
    if (doc.pinned) info[@"pinned"] = @YES;
    if ([ed documentInSecondaryView] == doc) info[@"in_second_view"] = @YES;
    [self readDocument:doc using:^(ScintillaView *sci) {
        info[@"lines"] = @(Msg(sci, SCI_GETLINECOUNT));
        info[@"bytes"] = @(Msg(sci, SCI_GETLENGTH));
    }];
    return info;
}

#pragma mark - Tools

- (void)registerTools {
    __weak NppAgentServer *weakSelf = self;
    #define ED weakSelf.editor
    #define DOC_OR_FAIL(args) NppDocument *doc = [weakSelf documentFor:Param(args, @"document") error:error]; if (!doc) return nil;

    [self addTool:@"list_documents"
      description:@"The documents open in the editor: index, title, path (null for a new document), language, whether "
                  @"modified (unsaved changes), encoding, line endings, size, which one is in front. Also the Folder as "
                  @"Workspace roots."
           schema:Schema(@{}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSMutableArray *docs = [NSMutableArray array];
        for (NppDocument *d in [weakSelf documents]) [docs addObject:[weakSelf infoOf:d]];
        return @{@"documents": docs, @"workspace_roots": [ED workspaceRootPaths] ?: @[]};
    }];

    [self addTool:@"get_document"
      description:@"The text of an open document as it is in the editor now, unsaved changes included. Give first_line "
                  @"and last_line (one-based, inclusive) for a part of a long file; without them the whole text comes "
                  @"back, cut at a million characters with truncated=true."
           schema:Schema(@{@"document": DocumentProp(),
                           @"first_line": Prop(@"integer", @"First line to return, one-based."),
                           @"last_line": Prop(@"integer", @"Last line to return, inclusive.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        NSMutableDictionary *out = [[weakSelf infoOf:doc] mutableCopy];
        [weakSelf readDocument:doc using:^(ScintillaView *sci) {
            long lines = Msg(sci, SCI_GETLINECOUNT);
            long first = LongParam(args, @"first_line", 1), last = LongParam(args, @"last_line", lines);
            if (first < 1) first = 1;
            if (last > lines) last = lines;
            if (last < first) last = first;
            long start = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)(first - 1));
            long end = last >= lines ? Msg(sci, SCI_GETLENGTH) : Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)last);
            BOOL truncated = NO;
            if ((NSUInteger)(end - start) > kMostTextInAnswer) {
                end = start + (long)kMostTextInAnswer;
                // Not in the middle of a character.
                end = Msg(sci, SCI_POSITIONBEFORE, (uptr_t)Msg(sci, SCI_POSITIONAFTER, (uptr_t)end));
                last = Msg(sci, SCI_LINEFROMPOSITION, (uptr_t)end) + 1;
                truncated = YES;
            }
            out[@"text"] = TextBetween(sci, start, end);
            out[@"first_line"] = @(first);
            out[@"last_line"] = @(last);
            out[@"truncated"] = @(truncated);
        }];
        return out;
    }];

    [self addTool:@"get_selection"
      description:@"What the user has selected in the document in front: the text, where it starts and ends (line, "
                  @"column, byte position), the caret, how many selections there are (column mode makes several), and "
                  @"the first visible line. Empty text means a caret without a selection."
           schema:Schema(@{}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        EditorController *ed = ED;
        if (!ed.currentDocument) { *error = Fail(@"No document is open"); return nil; }
        ScintillaView *sci = ed.sci;
        long start = Msg(sci, SCI_GETSELECTIONSTART), end = Msg(sci, SCI_GETSELECTIONEND);
        long caret = Msg(sci, SCI_GETCURRENTPOS);
        return @{@"document": [weakSelf infoOf:ed.currentDocument],
                 @"text": TextBetween(sci, start, end),
                 @"start": Place(sci, start), @"end": Place(sci, end), @"caret": Place(sci, caret),
                 @"selections": @(Msg(sci, SCI_GETSELECTIONS)),
                 @"rectangular": @(Msg(sci, SCI_SELECTIONISRECTANGLE) != 0),
                 @"first_visible_line": @(Msg(sci, SCI_GETFIRSTVISIBLELINE) + 1)};
    }];

    [self addTool:@"open_document"
      description:@"Opens a file in a tab (an already open file is brought to front), or makes a new document from "
                  @"text - for showing the user something, or to have the editor's lexer, search and function list "
                  @"work on a text. Give language (a Notepad++ language name such as cpp, python, json, or a User "
                  @"Defined Language's name) for a text; a file gets its language from its name. line moves the caret "
                  @"there. Returns the document's info, including its index."
           schema:Schema(@{@"path": Prop(@"string", @"A file to open; it must exist."),
                           @"text": Prop(@"string", @"Text for a new document, instead of a path."),
                           @"title": Prop(@"string", @"Tab title for a new document."),
                           @"language": Prop(@"string", @"Language name for a new document (see detect_language / list of Notepad++ languages)."),
                           @"line": Prop(@"integer", @"Line to put the caret on, one-based.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        EditorController *ed = ED;
        NSString *path = StringParam(args, @"path"), *text = Param(args, @"text");
        if (path.length) {
            path = path.stringByExpandingTildeInPath.stringByStandardizingPath;
            BOOL dir = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir]) { *error = Fail(@"No such file: %@", path); return nil; }
            if (dir) { [ed openFolderAsWorkspace:path]; return @{@"workspace_roots": [ed workspaceRootPaths] ?: @[]}; }
            NSError *why = nil;
            if (![ed openFileAtPath:path error:&why]) { *error = Fail(@"Cannot open %@: %@", path, why.localizedDescription ?: @"unknown reason"); return nil; }
        } else if ([text isKindOfClass:[NSString class]]) {
            // Everything that can be refused is refused before a tab appears.
            NSString *language = StringParam(args, @"language");
            if (language.length && ![[LanguageCatalog sharedCatalog] languageNamed:language]) { *error = Fail(@"No language named %@", language); return nil; }
            [ed newDocument];
            [ed setDocumentText:text];
            Msg(ed.sci, SCI_EMPTYUNDOBUFFER);
            Msg(ed.sci, SCI_SETSAVEPOINT);
            NSString *title = StringParam(args, @"title");
            if (title.length) { ed.currentDocument.displayName = title; [ed refreshChrome]; }
            if (language.length) {
                [ed chooseLanguageNamed:language];
            } else {
                [ed detectLanguageOfCurrentDocumentOffering:nil];
            }
        } else {
            *error = Fail(@"Give a path or a text");
            return nil;
        }
        long line = LongParam(args, @"line", 0);
        if (line > 0) {
            Msg(ed.sci, SCI_GOTOLINE, (uptr_t)(line - 1));
            Msg(ed.sci, SCI_VERTICALCENTRECARET);
        }
        return [weakSelf infoOf:ed.currentDocument];
    }];

    [self addTool:@"close_document"
      description:@"Closes a document's tab. A document with unsaved changes is left open unless discard_changes is "
                  @"true - closing the user's work is theirs to decide."
           schema:Schema(@{@"document": DocumentProp(),
                           @"discard_changes": Prop(@"boolean", @"Close even with unsaved changes, losing them.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        EditorController *ed = ED;
        BOOL discard = BoolParam(args, @"discard_changes", NO);
        if (doc.modified && !discard) { *error = Fail(@"%@ has unsaved changes; pass discard_changes to close it anyway", doc.displayName); return nil; }
        NSUInteger index = [ed.documents indexOfObjectIdenticalTo:doc];
        [ed closeDocumentAtIndex:(NSInteger)index discardChanges:discard];
        return @{@"closed": @([ed.documents indexOfObjectIdenticalTo:doc] == NSNotFound), @"open_documents": @([weakSelf documents].count)};
    }];

    [self addTool:@"go_to"
      description:@"Brings a document to front and puts the caret at a line (and column), centred on screen; with "
                  @"end_line/end_column the range is selected instead. Use it to show the user the place you are "
                  @"talking about. activate_app brings the editor window forward over other applications."
           schema:Schema(@{@"document": DocumentProp(),
                           @"line": Prop(@"integer", @"Line, one-based."),
                           @"column": Prop(@"integer", @"Column, one-based, in characters; 1 without it."),
                           @"end_line": Prop(@"integer", @"To select a range: its last line."),
                           @"end_column": Prop(@"integer", @"Column the selection ends before (exclusive); end of end_line without it."),
                           @"activate_app": Prop(@"boolean", @"Bring NotepadMac in front of other applications.")}, @[@"line"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        EditorController *ed = ED;
        NSUInteger index = [ed.documents indexOfObjectIdenticalTo:doc];
        if (doc != ed.currentDocument) [ed selectDocumentAtIndex:(NSInteger)index];
        ScintillaView *sci = ed.sci;
        long lines = Msg(sci, SCI_GETLINECOUNT);
        long line = LongParam(args, @"line", 1);
        if (line < 1 || line > lines) { *error = Fail(@"Line %ld is outside 1..%ld", line, lines); return nil; }
        long from = PositionOfLineColumn(sci, line - 1, LongParam(args, @"column", 1));
        long endLine = LongParam(args, @"end_line", 0);
        if (endLine > 0) {
            if (endLine > lines) endLine = lines;
            long endColumn = LongParam(args, @"end_column", 0);
            long to = endColumn > 0 ? PositionOfLineColumn(sci, endLine - 1, endColumn)
                                    : Msg(sci, SCI_GETLINEENDPOSITION, (uptr_t)(endLine - 1));
            Msg(sci, SCI_SETSEL, (uptr_t)from, to);
        } else {
            Msg(sci, SCI_GOTOPOS, (uptr_t)from);
        }
        // Up and Down go from this column now, not from where the caret was last put by hand
        // (SCI_GOTOPOS / SCI_SETSEL keep Scintilla's remembered x).
        Msg(sci, SCI_CHOOSECARETX);
        Msg(sci, SCI_VERTICALCENTRECARET);
        [ed.window makeFirstResponder:sci.content];   // the text view itself takes keys, not its wrapper
        if (BoolParam(args, @"activate_app", NO)) [NSApp activateIgnoringOtherApps:YES];
        return @{@"document": [weakSelf infoOf:doc],
                 @"start": Place(sci, Msg(sci, SCI_GETSELECTIONSTART)),
                 @"end": Place(sci, Msg(sci, SCI_GETSELECTIONEND))};
    }];

    [self addTool:@"edit_document"
      description:@"Changes an open document in the editor, as one undoable step. Either text replaces the whole "
                  @"document, or edits lists replacements: each has start_line, end_line and a text; with start_column "
                  @"and end_column (one-based characters, end exclusive) it replaces that range; without columns it "
                  @"replaces the whole lines start_line..end_line including their line endings, so the text should end "
                  @"with a newline (empty text deletes the lines). Edits must not overlap. The document is left "
                  @"modified; the user saves, or call save_document."
           schema:Schema(@{@"document": DocumentProp(),
                           @"text": Prop(@"string", @"The whole new text of the document."),
                           @"edits": @{@"type": @"array", @"description": @"Replacements, any order.",
                                       @"items": Schema(@{@"start_line": Prop(@"integer", @"One-based."),
                                                          @"start_column": Prop(@"integer", @"One-based; with end_column."),
                                                          @"end_line": Prop(@"integer", @"One-based, inclusive without columns."),
                                                          @"end_column": Prop(@"integer", @"Exclusive; with start_column."),
                                                          @"text": Prop(@"string", @"Replacement.")},
                                                        @[@"start_line", @"end_line", @"text"])}}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        NSString *whole = Param(args, @"text");
        NSArray *edits = Param(args, @"edits");
        if (![whole isKindOfClass:[NSString class]] && ![edits isKindOfClass:[NSArray class]]) { *error = Fail(@"Give text or edits"); return nil; }
        if (doc.userReadOnly || doc.monitoring) { *error = Fail(@"%@ is read-only", doc.displayName); return nil; }
        __block NSError *failed = nil;
        __block long applied = 0;
        [weakSelf withDocumentInFront:doc do:^(ScintillaView *sci) {
            if ([whole isKindOfClass:[NSString class]]) {
                NSData *utf8 = [whole dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
                Msg(sci, SCI_BEGINUNDOACTION);
                Msg(sci, SCI_SETTARGETRANGE, 0, Msg(sci, SCI_GETLENGTH));
                Msg(sci, SCI_REPLACETARGET, (uptr_t)utf8.length, (sptr_t)utf8.bytes);
                Msg(sci, SCI_ENDUNDOACTION);
                applied = 1;
                return;
            }
            // Work out every range first, from the unchanged text, then apply
            // from the end backwards so earlier positions stay true.
            long lines = Msg(sci, SCI_GETLINECOUNT);
            NSMutableArray<NSDictionary *> *ranges = [NSMutableArray array];
            for (id e in edits) {
                if (![e isKindOfClass:[NSDictionary class]]) { failed = Fail(@"Each edit must be an object"); return; }
                long sl = LongParam(e, @"start_line", 0), el = LongParam(e, @"end_line", 0);
                NSString *t = Param(e, @"text");
                if (![t isKindOfClass:[NSString class]]) { failed = Fail(@"An edit has no text"); return; }
                if (sl < 1 || el < sl || sl > lines) { failed = Fail(@"Edit lines %ld..%ld are outside 1..%ld", sl, el, lines); return; }
                long sc = LongParam(e, @"start_column", 0), ec = LongParam(e, @"end_column", 0);
                long from, to;
                if (sc > 0 || ec > 0) {
                    from = PositionOfLineColumn(sci, sl - 1, sc > 0 ? sc : 1);
                    to = ec > 0 ? PositionOfLineColumn(sci, el - 1, ec) : Msg(sci, SCI_GETLINEENDPOSITION, (uptr_t)(el - 1));
                } else {
                    from = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)(sl - 1));
                    to = el >= lines ? Msg(sci, SCI_GETLENGTH) : Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)el);
                }
                if (to < from) { failed = Fail(@"An edit ends before it starts (line %ld)", sl); return; }
                [ranges addObject:@{@"from": @(from), @"to": @(to), @"text": t}];
            }
            [ranges sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [b[@"from"] compare:a[@"from"]];
            }];
            for (NSUInteger i = 1; i < ranges.count; ++i) {
                if ([ranges[i][@"to"] longValue] > [ranges[i - 1][@"from"] longValue]) { failed = Fail(@"Edits overlap"); return; }
            }
            Msg(sci, SCI_BEGINUNDOACTION);
            for (NSDictionary *r in ranges) {
                NSData *utf8 = [r[@"text"] dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
                Msg(sci, SCI_SETTARGETRANGE, (uptr_t)[r[@"from"] longValue], [r[@"to"] longValue]);
                Msg(sci, SCI_REPLACETARGET, (uptr_t)utf8.length, (sptr_t)utf8.bytes);
                applied++;
            }
            Msg(sci, SCI_ENDUNDOACTION);
        }];
        if (failed) { *error = failed; return nil; }
        [ED refreshChrome];
        return @{@"applied": @(applied), @"document": [weakSelf infoOf:doc]};
    }];

    [self addTool:@"save_document"
      description:@"Saves an open document to its file, in its own encoding and line endings. A new document that has "
                  @"no file yet cannot be saved here: ask the user, who chooses where."
           schema:Schema(@{@"document": DocumentProp()}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        if (!doc.path) { *error = Fail(@"%@ has no file yet; the user chooses where it goes (File > Save As)", doc.displayName); return nil; }
        __block BOOL saved = NO;
        [weakSelf withDocumentInFront:doc do:^(ScintillaView *sci) { saved = [ED saveCurrentDocument]; }];
        if (!saved) { *error = Fail(@"Could not save %@", doc.path); return nil; }
        return @{@"saved": @YES, @"path": doc.path, @"document": [weakSelf infoOf:doc]};
    }];

    [self addTool:@"bookmarks"
      description:@"The bookmarked lines of a document, after adding or removing some. Bookmarks are the editor's "
                  @"blue marks in the margin: put them on the lines you want the user to look at; they step through "
                  @"them with F2, and Search > Bookmark can cut, copy or delete the marked lines."
           schema:Schema(@{@"document": DocumentProp(),
                           @"add": @{@"type": @"array", @"items": @{@"type": @"integer"}, @"description": @"Lines to bookmark, one-based."},
                           @"remove": @{@"type": @"array", @"items": @{@"type": @"integer"}, @"description": @"Lines to unmark."},
                           @"clear": Prop(@"boolean", @"Remove every bookmark first.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        NSMutableArray *lines = [NSMutableArray array];
        [weakSelf withDocumentInFront:doc do:^(ScintillaView *sci) {
            const int marker = 1;   // NPPMAC_BOOKMARK_MARKER
            long count = Msg(sci, SCI_GETLINECOUNT);
            if (BoolParam(args, @"clear", NO)) Msg(sci, SCI_MARKERDELETEALL, (uptr_t)marker);
            for (id n in ([Param(args, @"remove") isKindOfClass:[NSArray class]] ? Param(args, @"remove") : @[])) {
                long line = [n longValue];
                if (line >= 1 && line <= count) Msg(sci, SCI_MARKERDELETE, (uptr_t)(line - 1), marker);
            }
            for (id n in ([Param(args, @"add") isKindOfClass:[NSArray class]] ? Param(args, @"add") : @[])) {
                long line = [n longValue];
                if (line >= 1 && line <= count && !(Msg(sci, SCI_MARKERGET, (uptr_t)(line - 1)) & (1 << marker)))
                    Msg(sci, SCI_MARKERADD, (uptr_t)(line - 1), marker);
            }
            long line = -1;
            while ((line = Msg(sci, SCI_MARKERNEXT, (uptr_t)(line + 1), 1 << marker)) >= 0) [lines addObject:@(line + 1)];
        }];
        return @{@"bookmarked_lines": lines, @"document": [weakSelf infoOf:doc]};
    }];

    [self addTool:@"list_commands"
      description:@"The editor's menu commands - all 579 of Notepad++'s - by their upstream id name (IDM_EDIT_UPPERCASE), "
                  @"menu path and label, filtered by a query. Any of them runs through run_command: case conversion, "
                  @"line operations, sorting, trimming, comment toggling, encoding and EOL conversion, folding, "
                  @"JSON/XML formatting, hashes, Base64, the Compare and Function List panels, and the rest."
           schema:Schema(@{@"query": Prop(@"string", @"Words to look for in the name, path or label (case-insensitive); empty for all."),
                           @"limit": Prop(@"integer", @"At most this many, 100 without it.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *query = [StringParam(args, @"query") ?: @"" lowercaseString];
        NSArray *words = [[query componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
                          filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
        long limit = LongParam(args, @"limit", 100);
        NSMutableArray *out = [NSMutableArray array];
        long total = 0;
        for (int i = 0; i < kNppMenuCommandIDCount; ++i) {
            const NppMenuCommandID *c = &kNppMenuCommandIDs[i];
            NSString *hay = [[NSString stringWithFormat:@"%s %s %s", c->name, c->path, c->label] lowercaseString];
            BOOL hit = YES;
            for (NSString *w in words) if (![hay containsString:w]) { hit = NO; break; }
            if (!hit) continue;
            total++;
            if ((long)out.count < limit) {
                [out addObject:@{@"id": @(c->identifier), @"name": @(c->name), @"menu": @(c->path), @"label": @(c->label)}];
            }
        }
        return @{@"commands": out, @"total": @(total)};
    }];

    [self addTool:@"run_command"
      description:@"Runs one menu command on the document in front, as the user would from the menu: by its "
                  @"Notepad++ id name (IDM_EDIT_UPPERCASE), its number, or its menu path with | between levels "
                  @"(\"Edit|Line Operations|Sort Lines Lexicographically Ascending\"). Commands work on the "
                  @"selection or the document as they do in Notepad++; select first with go_to when needed. Commands "
                  @"that open a dialog show it to the user. Returns whether it ran; a disabled command does not."
           schema:Schema(@{@"command": @{@"type": @[@"string", @"integer"], @"description": @"IDM_* name, id number or menu path."}}, @[@"command"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        id spec = Param(args, @"command");
        NSString *name = StringParam(args, @"command") ?: @"";
        AppDelegate *app = (AppDelegate *)NSApp.delegate;
        int identifier = 0;
        if ([spec isKindOfClass:[NSNumber class]]) identifier = [spec intValue];
        else if ([name hasPrefix:@"IDM_"]) {
            for (int i = 0; i < kNppMenuCommandIDCount; ++i) if (!strcmp(kNppMenuCommandIDs[i].name, name.UTF8String)) { identifier = kNppMenuCommandIDs[i].identifier; break; }
            if (!identifier) { *error = Fail(@"No command named %@", name); return nil; }
        } else if (name.length) {
            BOOL ran = [app performMenuCommandAtPath:name];
            return @{@"ran": @(ran), @"command": name};
        } else {
            *error = Fail(@"Give a command");
            return nil;
        }
        // What an agent must not do for the user: quit, or throw a file away.
        static NSSet<NSNumber *> *kept;
        if (!kept) kept = [NSSet setWithArray:@[@41011 /* IDM_FILE_EXIT */, @41016 /* IDM_FILE_DELETE */]];
        if ([kept containsObject:@(identifier)]) { *error = Fail(@"Command %d is left to the user", identifier); return nil; }
        NSMenuItem *item = [app.shortcutStore menuItemsByIdentifier][@(identifier)];
        if (!item) { *error = Fail(@"Command %d is not in this build's menus", identifier); return nil; }
        [item.menu update];
        if (!item.isEnabled) return @{@"ran": @NO, @"enabled": @NO, @"command": @(identifier), @"label": item.title ?: @""};
        BOOL ran = (!item.target && [app.window.firstResponder tryToPerform:item.action with:item]) ||
                   [NSApp sendAction:item.action to:item.target from:item];
        [ED refreshChrome];
        return @{@"ran": @(ran), @"enabled": @YES, @"command": @(identifier), @"label": item.title ?: @""};
    }];

    [self addTool:@"detect_language"
      description:@"Which language a text is in, by the editor's own means: first what the text declares (a shebang, "
                  @"<?xml, a doctype, a modeline, JSON that parses), then a model trained on real code that gives "
                  @"every language a likelihood. Returns the declared language if any, the languages the editor would "
                  @"offer (one means it is sure), and the top guesses with confidence. With filename, also what the "
                  @"name alone would give. Language names are Notepad++'s (cpp, python, objc, ...)."
           schema:Schema(@{@"text": Prop(@"string", @"The text to judge; the first part of a long one is enough."),
                           @"filename": Prop(@"string", @"A file name, to see what its extension would give.")}, @[@"text"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *text = Param(args, @"text");
        if (![text isKindOfClass:[NSString class]]) { *error = Fail(@"Give a text"); return nil; }
        LanguageCatalog *catalog = [LanguageCatalog sharedCatalog];
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NppLanguage *declared = [catalog declaredLanguageInContents:text];
        out[@"declared"] = declared.name ?: [NSNull null];
        NSMutableArray *offered = [NSMutableArray array];
        for (NppLanguage *l in [catalog languagesMatchingContents:text]) [offered addObject:l.name];
        out[@"offered"] = offered;
        NSMutableArray *guesses = [NSMutableArray array];
        NSArray<NppLanguageGuess *> *all = [[NppLanguageModel sharedModel] guessesForText:text];
        for (NppLanguageGuess *g in all) {
            if (guesses.count >= 5) break;
            [guesses addObject:@{@"language": g.name, @"title": [LanguageCatalog menuTitleForLanguage:g.name],
                                 @"confidence": @(round(g.confidence * 1000) / 1000)}];
        }
        out[@"guesses"] = guesses;
        NSString *filename = StringParam(args, @"filename");
        if (filename.length) out[@"by_filename"] = [catalog languageForFileName:filename].name ?: @"normal";
        return out;
    }];

    [self addTool:@"tokens"
      description:@"The document as its lexer colours it: runs of text with their style names (COMMENT, KEYWORD, "
                  @"STRING, NUMBER, IDENTIFIER...), exactly what the user sees highlighted, from Notepad++'s own "
                  @"language and style definitions including User Defined Languages. Use it to check how the editor "
                  @"reads a file - an unclosed string or comment shows at once - or to see what a UDL you are writing "
                  @"does. Each token is [line, column, style, text]; whitespace-only runs are left out. Also the fold "
                  @"levels when include_folds is set: [line, level, is_header]."
           schema:Schema(@{@"document": DocumentProp(),
                           @"first_line": Prop(@"integer", @"First line, one-based."),
                           @"last_line": Prop(@"integer", @"Last line, inclusive."),
                           @"include_folds": Prop(@"boolean", @"Also return the fold level of each line.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        DOC_OR_FAIL(args)
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        NSString *lexerName = doc.language.name ?: @"normal";
        NSMutableDictionary<NSNumber *, NSString *> *names = [NSMutableDictionary dictionary];
        for (NppStyle *s in [[StyleCatalog sharedCatalog] stylesForLexerName:lexerName] ?: @[]) {
            if (s.name.length && !names[@(s.styleID)]) names[@(s.styleID)] = s.name;
        }
        [weakSelf readDocument:doc using:^(ScintillaView *sci) {
            long lines = Msg(sci, SCI_GETLINECOUNT);
            long first = MAX(1L, LongParam(args, @"first_line", 1)), last = MIN(lines, LongParam(args, @"last_line", lines));
            if (last < first) last = first;
            long start = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)(first - 1));
            long end = last >= lines ? Msg(sci, SCI_GETLENGTH) : Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)last);
            Msg(sci, SCI_COLOURISE, 0, end);
            std::string cells((size_t)(end - start) * 2 + 2, '\0');
            Sci_TextRangeFull range;
            range.chrg.cpMin = start;
            range.chrg.cpMax = end;
            range.lpstrText = &cells[0];
            Msg(sci, SCI_GETSTYLEDTEXTFULL, 0, (sptr_t)&range);
            NSMutableArray *tokens = [NSMutableArray array];
            BOOL truncated = NO;
            long i = 0, n = end - start;
            NSCharacterSet *blank = NSCharacterSet.whitespaceAndNewlineCharacterSet;
            while (i < n) {
                unsigned char style = (unsigned char)cells[(size_t)i * 2 + 1];
                long j = i;
                // A run of one style, stopped at a line ending so a token never spans lines.
                while (j < n && (unsigned char)cells[(size_t)j * 2 + 1] == style && cells[(size_t)j * 2] != '\n' && cells[(size_t)j * 2] != '\r') j++;
                if (j == i) { i++; continue; }
                std::string bytes;
                for (long k = i; k < j; ++k) bytes.push_back(cells[(size_t)k * 2]);
                NSString *text = [[NSString alloc] initWithBytes:bytes.data() length:bytes.size() encoding:NSUTF8StringEncoding];
                if (text && [text stringByTrimmingCharactersInSet:blank].length) {
                    if (tokens.count >= kMostTokens) { truncated = YES; break; }
                    long pos = start + i;
                    NSString *name = names[@(style)] ?: (style == 0 ? @"DEFAULT" : [NSString stringWithFormat:@"STYLE_%d", style]);
                    [tokens addObject:@[@(Msg(sci, SCI_LINEFROMPOSITION, (uptr_t)pos) + 1), @(ColumnOfPosition(sci, pos)), name, text]];
                }
                i = j;
            }
            out[@"tokens"] = tokens;
            out[@"truncated"] = @(truncated);
            out[@"first_line"] = @(first);
            out[@"last_line"] = @(last);
            if (BoolParam(args, @"include_folds", NO)) {
                NSMutableArray *folds = [NSMutableArray array];
                for (long line = first - 1; line < last; ++line) {
                    long level = Msg(sci, SCI_GETFOLDLEVEL, (uptr_t)line);
                    [folds addObject:@[@(line + 1), @((level & SC_FOLDLEVELNUMBERMASK) - SC_FOLDLEVELBASE), @((level & SC_FOLDLEVELHEADERFLAG) != 0)]];
                }
                out[@"folds"] = folds;
            }
        }];
        out[@"language"] = lexerName;
        out[@"lexer"] = doc.language.lexerID ?: @"null";
        out[@"document"] = [weakSelf infoOf:doc];
        return out;
    }];

    [self addTool:@"function_list"
      description:@"The functions, methods and classes of a document, found with Notepad++'s own Function List "
                  @"parsers (the functionList/*.xml definitions, run as written): name, enclosing class if any, and "
                  @"line. Either an open document or a text with its language."
           schema:Schema(@{@"document": DocumentProp(),
                           @"text": Prop(@"string", @"A text instead of a document; needs language."),
                           @"language": Prop(@"string", @"Notepad++ language name of the text.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *text = Param(args, @"text");
        NSString *language = StringParam(args, @"language"), *ext = nil;
        NSDictionary *info = nil;
        if ([text isKindOfClass:[NSString class]]) {
            if (!language.length) { *error = Fail(@"A text needs its language"); return nil; }
        } else {
            DOC_OR_FAIL(args)
            __block NSString *whole = @"";
            [weakSelf readDocument:doc using:^(ScintillaView *sci) { whole = TextBetween(sci, 0, Msg(sci, SCI_GETLENGTH)); }];
            text = whole;
            language = doc.language.name ?: @"normal";
            ext = doc.path.pathExtension;
            info = [weakSelf infoOf:doc];
        }
        FunctionListCatalog *catalog = [FunctionListCatalog sharedCatalog];
        NSString *parser = [catalog parserIDForLanguage:language extension:ext];
        NSMutableArray *entries = [NSMutableArray array];
        for (NppFunctionEntry *e in [catalog entriesInText:text forLanguage:language extension:ext]) {
            [entries addObject:@{@"name": e.name ?: @"", @"container": e.container ?: [NSNull null],
                                 @"line": @(e.line + 1), @"is_class": @(e.isClass)}];
        }
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:@{@"entries": entries, @"language": language,
                                                                                    @"parser": parser ?: [NSNull null]}];
        if (info) out[@"document"] = info;
        return out;
    }];

    NSDictionary *findProps = @{
        @"what": Prop(@"string", @"What to look for."),
        @"mode": @{@"type": @"string", @"enum": @[@"normal", @"extended", @"regex"],
                   @"description": @"normal: the text as typed; extended: \\n \\t \\xHH escapes; regex: a regular expression in Notepad++'s (Boost) syntax. normal without it."},
        @"match_case": Prop(@"boolean", @"Case-sensitive; off without it."),
        @"whole_word": Prop(@"boolean", @"Whole words only (normal and extended modes)."),
        @"dot_matches_newline": Prop(@"boolean", @"regex: . may match a line ending."),
    };
    NSMutableDictionary *findSchema = [findProps mutableCopy];
    findSchema[@"document"] = DocumentProp();
    findSchema[@"folder"] = Prop(@"string", @"Find in Files: search this folder instead of a document.");
    findSchema[@"filters"] = Prop(@"string", @"Find in Files: file patterns as Notepad++ takes them, e.g. \"*.cpp *.h\"; \"!\\\\build\" keeps a folder out. All files without it.");
    findSchema[@"recursive"] = Prop(@"boolean", @"Find in Files: subfolders too; on without it.");
    findSchema[@"show_results"] = Prop(@"boolean", @"Also show the hits in the editor's Search results panel.");
    findSchema[@"limit"] = Prop(@"integer", @"At most this many matches from a document, 500 without it.");
    [self addTool:@"find"
      description:@"Notepad++'s search, so the result is exactly what the user gets from Find: normal, extended or "
                  @"regular-expression mode with Boost syntax (look-around, \\K, named groups, (?i)), match case, "
                  @"whole word. In a document: every match with line, column and the line's text. In a folder (Find "
                  @"in Files): the report Notepad++ writes, file by file. A pattern that does not compile comes back "
                  @"as an error with the engine's reason - use this to check an expression before giving it to the "
                  @"user. show_results puts the hits in the editor's Search results panel for the user."
           schema:Schema(findSchema, @[@"what"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *what = StringParam(args, @"what");
        if (!what.length) { *error = Fail(@"Give what to look for"); return nil; }
        NSString *mode = StringParam(args, @"mode") ?: @"normal";
        NppSearchMode m = [mode isEqualToString:@"regex"] ? NppSearchRegex : [mode isEqualToString:@"extended"] ? NppSearchExtended : NppSearchNormal;
        NppFindOptions options = NppFindNone;
        if (BoolParam(args, @"match_case", NO)) options |= NppFindMatchCase;
        if (BoolParam(args, @"whole_word", NO)) options |= NppFindWholeWord;
        if (BoolParam(args, @"dot_matches_newline", NO)) options |= NppFindDotMatchesNewline;
        NppFindSpec *spec = [NppFindSpec specFor:what mode:m options:options];
        EditorController *ed = ED;
        if (![ed regexFor:spec]) {
            NSString *why = m == NppSearchRegex ? [NppRegex compileErrorForPattern:what] : nil;
            *error = Fail(@"The expression does not compile%@%@", why ? @": " : @"", why ?: @"");
            return nil;
        }
        NSString *folder = StringParam(args, @"folder");
        if (folder.length) {
            folder = folder.stringByExpandingTildeInPath.stringByStandardizingPath;
            BOOL dir = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:folder isDirectory:&dir] || !dir) { *error = Fail(@"No such folder: %@", folder); return nil; }
            NSString *report = nil;
            NSUInteger hits = [ed findInFiles:spec folder:folder filters:StringParam(args, @"filters")
                                    recursive:BoolParam(args, @"recursive", YES) includeHidden:NO report:&report];
            if (BoolParam(args, @"show_results", NO) && report) [ed showSearchResults:report];
            return @{@"hits": @(hits), @"folder": folder, @"report": report ?: @""};
        }
        DOC_OR_FAIL(args)
        long limit = LongParam(args, @"limit", (long)kMostMatches);
        NSMutableArray *matches = [NSMutableArray array];
        __block NSUInteger total = 0;
        __block NSString *report = nil;
        [weakSelf withDocumentInFront:doc do:^(ScintillaView *sci) {
            NSArray<NSValue *> *ranges = [ed rangesOfMatches:spec];
            total = ranges.count;
            for (NSValue *v in ranges) {
                if ((long)matches.count >= limit) break;
                NSRange r = v.rangeValue;
                long line = Msg(sci, SCI_LINEFROMPOSITION, (uptr_t)r.location);
                long lineStart = Msg(sci, SCI_POSITIONFROMLINE, (uptr_t)line), lineEnd = Msg(sci, SCI_GETLINEENDPOSITION, (uptr_t)line);
                [matches addObject:@{@"line": @(line + 1), @"column": @(ColumnOfPosition(sci, (long)r.location)),
                                     @"position": @(r.location), @"length": @(r.length),
                                     @"match": TextBetween(sci, (long)r.location, (long)(r.location + r.length)),
                                     @"line_text": TextBetween(sci, lineStart, lineEnd)}];
            }
            if (BoolParam(args, @"show_results", NO)) report = [ed findAllReport:spec hits:NULL];
        }];
        if (report) [ed showSearchResults:report];
        return @{@"hits": @(total), @"matches": matches, @"truncated": @(total > matches.count), @"document": [weakSelf infoOf:doc]};
    }];

    NSMutableDictionary *replaceSchema = [findProps mutableCopy];
    replaceSchema[@"document"] = DocumentProp();
    replaceSchema[@"replacement"] = Prop(@"string", @"The replacement; in regex mode $1 or \\1 stand for groups, as in Notepad++.");
    [self addTool:@"replace"
      description:@"Replace All in an open document with Notepad++'s engine and replacement syntax ($1, \\1, \\n, "
                  @"\\t, case changes \\U \\L in regex mode), as one undoable step. Returns how many were replaced. "
                  @"The document is left modified for the user to save."
           schema:Schema(replaceSchema, @[@"what", @"replacement"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *what = StringParam(args, @"what"), *replacement = Param(args, @"replacement");
        if (!what.length || ![replacement isKindOfClass:[NSString class]]) { *error = Fail(@"Give what and replacement"); return nil; }
        DOC_OR_FAIL(args)
        if (doc.userReadOnly || doc.monitoring) { *error = Fail(@"%@ is read-only", doc.displayName); return nil; }
        NSString *mode = StringParam(args, @"mode") ?: @"normal";
        NppSearchMode m = [mode isEqualToString:@"regex"] ? NppSearchRegex : [mode isEqualToString:@"extended"] ? NppSearchExtended : NppSearchNormal;
        NppFindOptions options = NppFindNone;
        if (BoolParam(args, @"match_case", NO)) options |= NppFindMatchCase;
        if (BoolParam(args, @"whole_word", NO)) options |= NppFindWholeWord;
        if (BoolParam(args, @"dot_matches_newline", NO)) options |= NppFindDotMatchesNewline;
        NppFindSpec *spec = [NppFindSpec specFor:what mode:m options:options];
        spec.replacement = replacement;
        EditorController *ed = ED;
        if (![ed regexFor:spec]) {
            NSString *why = m == NppSearchRegex ? [NppRegex compileErrorForPattern:what] : nil;
            *error = Fail(@"The expression does not compile%@%@", why ? @": " : @"", why ?: @"");
            return nil;
        }
        __block NSUInteger replaced = 0;
        [weakSelf withDocumentInFront:doc do:^(ScintillaView *sci) { replaced = [ed replaceAll:spec]; }];
        [ed refreshChrome];
        return @{@"replaced": @(replaced), @"document": [weakSelf infoOf:doc]};
    }];

    NSDictionary *sideProp = Schema(@{@"document": DocumentProp(),
                                      @"path": Prop(@"string", @"A file on disk."),
                                      @"text": Prop(@"string", @"A text.")}, @[]);
    [self addTool:@"compare"
      description:@"Compares two texts line by line as the editor's Compare does (Myers' algorithm): each side is an "
                  @"open document, a file or a text. Returns the counts and the differing runs with their lines. With "
                  @"show, both sides are opened side by side in the editor with the differences marked, for the user "
                  @"to review - the way to present a proposed change (only for documents or files)."
           schema:Schema(@{@"left": sideProp, @"right": sideProp,
                           @"ignore_case": Prop(@"boolean", @""), @"ignore_spaces": Prop(@"boolean", @""),
                           @"ignore_empty_lines": Prop(@"boolean", @""),
                           @"show": Prop(@"boolean", @"Show the comparison in the editor."),
                           @"limit": Prop(@"integer", @"At most this many differing runs, 200 without it.")}, @[@"left", @"right"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        EditorController *ed = ED;
        NSDictionary *sides[2] = {Param(args, @"left"), Param(args, @"right")};
        NSString *texts[2];
        NppDocument *docs[2] = {nil, nil};
        for (int s = 0; s < 2; ++s) {
            NSDictionary *side = sides[s];
            if (![side isKindOfClass:[NSDictionary class]]) { *error = Fail(@"left and right must be objects"); return nil; }
            NSString *text = Param(side, @"text"), *path = StringParam(side, @"path");
            if ([text isKindOfClass:[NSString class]]) {
                texts[s] = text;
            } else if (path.length) {
                path = path.stringByExpandingTildeInPath.stringByStandardizingPath;
                NSString *read = [EditorController textOfFileAtPath:path encoding:NULL hasBOM:NULL];
                if (!read) { *error = Fail(@"Cannot read %@", path); return nil; }
                texts[s] = read;
                if (BoolParam(args, @"show", NO)) {
                    if (![ed openFileAtPath:path error:NULL]) { *error = Fail(@"Cannot open %@", path); return nil; }
                    docs[s] = ed.currentDocument;
                }
            } else {
                NppDocument *doc = [weakSelf documentFor:Param(side, @"document") error:error];
                if (!doc) return nil;
                __block NSString *whole = @"";
                [weakSelf readDocument:doc using:^(ScintillaView *sci) { whole = TextBetween(sci, 0, Msg(sci, SCI_GETLENGTH)); }];
                texts[s] = whole;
                docs[s] = doc;
            }
        }
        NSArray<NSString *> *oldLines = [EditorController linesForComparison:texts[0]];
        NSArray<NSString *> *newLines = [EditorController linesForComparison:texts[1]];
        BOOL ignoreCase = BoolParam(args, @"ignore_case", NO), ignoreSpaces = BoolParam(args, @"ignore_spaces", NO);
        BOOL ignoreEmpty = BoolParam(args, @"ignore_empty_lines", NO);
        NSArray<NppDiffLine *> *diff = [EditorController diffBetween:oldLines and:newLines
                                                          ignoreCase:ignoreCase ignoreSpaces:ignoreSpaces ignoreEmptyLines:ignoreEmpty];
        long added = 0, removed = 0, changed = 0;
        NSMutableArray *hunks = [NSMutableArray array];
        long limit = LongParam(args, @"limit", 200);
        NSMutableDictionary *hunk = nil;
        BOOL truncated = NO;
        for (NppDiffLine *d in diff) {
            if (d.kind == NppDiffSame) { hunk = nil; continue; }
            if (d.kind == NppDiffAdded) added++; else if (d.kind == NppDiffRemoved) removed++; else changed++;
            if (!hunk) {
                if ((long)hunks.count >= limit) { truncated = YES; continue; }
                hunk = [NSMutableDictionary dictionaryWithDictionary:@{@"old_lines": [NSMutableArray array], @"new_lines": [NSMutableArray array],
                                                                       @"old_start": @(d.oldLine >= 0 ? d.oldLine + 1 : 0), @"new_start": @(d.newLine >= 0 ? d.newLine + 1 : 0)}];
                [hunks addObject:hunk];
            }
            if (d.oldLine >= 0 && d.oldLine < (NSInteger)oldLines.count) [hunk[@"old_lines"] addObject:oldLines[(NSUInteger)d.oldLine]];
            if (d.newLine >= 0 && d.newLine < (NSInteger)newLines.count) [hunk[@"new_lines"] addObject:newLines[(NSUInteger)d.newLine]];
            if (d.oldLine >= 0 && ![hunk[@"old_start"] longValue]) hunk[@"old_start"] = @(d.oldLine + 1);
            if (d.newLine >= 0 && ![hunk[@"new_start"] longValue]) hunk[@"new_start"] = @(d.newLine + 1);
        }
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:@{
            @"same": @(added + removed + changed == 0), @"added": @(added), @"removed": @(removed), @"changed": @(changed),
            @"hunks": hunks, @"truncated": @(truncated)}];
        if (BoolParam(args, @"show", NO)) {
            if (!docs[0] || !docs[1]) { out[@"shown"] = @NO; out[@"note"] = @"Only documents or files can be shown; texts are compared here only."; return out; }
            ed.compareIgnoreCase = ignoreCase;
            ed.compareIgnoreSpaces = ignoreSpaces;
            ed.compareIgnoreEmptyLines = ignoreEmpty;
            [weakSelf withDocumentInFront:docs[0] do:^(ScintillaView *sci) { [ed setFirstToCompare]; }];
            [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:docs[1]]];
            out[@"shown"] = @([ed compareWithFirst]);
            out[@"summary"] = [ed compareSummary] ?: @"";
        }
        return out;
    }];

    [self addTool:@"file_encoding"
      description:@"How the editor would read a file: its byte-order mark, the character set uchardet finds when "
                  @"there is none (the same detector Notepad++ ships, over its 46 sets), UTF-16 without a mark, the "
                  @"line endings, line count, and a preview of the decoded text. For files that are not UTF-8 - "
                  @"Windows-1251, Shift_JIS, KOI8-R - before reading them yourself."
           schema:Schema(@{@"path": Prop(@"string", @"The file."),
                           @"preview_chars": Prop(@"integer", @"Characters of decoded text to return, 400 without it.")}, @[@"path"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *path = StringParam(args, @"path").stringByExpandingTildeInPath.stringByStandardizingPath;
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL] : nil;
        if (!data) { *error = Fail(@"Cannot read %@", path ?: @"(no path)"); return nil; }
        const unsigned char *b = (const unsigned char *)data.bytes;
        NSString *bom = @"none";
        if (data.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) bom = @"UTF-8";
        else if (data.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) bom = @"UTF-16 LE";
        else if (data.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) bom = @"UTF-16 BE";
        NSData *head = data.length > 1 << 20 ? [data subdataWithRange:NSMakeRange(0, 1 << 20)] : data;
        NSString *charset = [NppCharsetDetection charsetNameForData:head];
        NSStringEncoding utf16 = [NppCharsetDetection utf16EncodingWithoutMarkForData:head];
        NSStringEncoding used = 0;
        BOOL hasBOM = NO;
        NSString *text = [EditorController textOfFileAtPath:path encoding:&used hasBOM:&hasBOM];
        long crlf = 0, lf = 0, cr = 0;
        if (text) {
            NSUInteger n = MIN(text.length, (NSUInteger)(1 << 20));
            for (NSUInteger i = 0; i < n; ++i) {
                unichar c = [text characterAtIndex:i];
                if (c == '\r') { if (i + 1 < n && [text characterAtIndex:i + 1] == '\n') { crlf++; i++; } else cr++; }
                else if (c == '\n') lf++;
            }
        }
        NSString *eol = crlf > lf && crlf > cr ? @"CRLF" : cr > lf && cr > crlf ? @"CR" : (lf || crlf || cr) ? @"LF" : @"none";
        BOOL mixed = (crlf > 0) + (lf > 0) + (cr > 0) > 1;
        CFStringRef iana = used ? CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(used)) : NULL;
        long preview = LongParam(args, @"preview_chars", 400);
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        out[@"path"] = path;
        out[@"bytes"] = @(data.length);
        out[@"bom"] = bom;
        out[@"binary"] = @(text == nil);
        out[@"encoding"] = iana ? [(__bridge NSString *)iana uppercaseString] : (text ? @"UTF-8" : [NSNull null]);
        out[@"charset_detected"] = charset ?: [NSNull null];
        out[@"utf16_without_bom"] = utf16 == NSUTF16LittleEndianStringEncoding ? @"UTF-16 LE" : utf16 == NSUTF16BigEndianStringEncoding ? @"UTF-16 BE" : [NSNull null];
        out[@"eol"] = eol;
        out[@"mixed_eol"] = @(mixed);
        out[@"lines"] = text ? @(lf + crlf + cr + (text.length && ![text hasSuffix:@"\n"] && ![text hasSuffix:@"\r"] ? 1 : 0)) : @0;
        if (text && preview > 0) out[@"preview"] = text.length > (NSUInteger)preview ? [text substringToIndex:(NSUInteger)preview] : text;
        return out;
    }];

    [self addTool:@"ocr"
      description:@"The text in an image (PNG, JPEG, HEIC, TIFF...) or a PDF, recognised by macOS's own engine "
                  @"(Vision), in reading order; a PDF page by page. For screenshots, scans and photos of text."
           schema:Schema(@{@"path": Prop(@"string", @"The image or PDF file.")}, @[@"path"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *path = StringParam(args, @"path").stringByExpandingTildeInPath.stringByStandardizingPath;
        if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) { *error = Fail(@"No such file: %@", path ?: @""); return nil; }
        NSString *text = [EditorController textRecognizedInFileAt:path];
        return @{@"path": path, @"text": text ?: @"", @"found": @(text.length > 0)};
    }];

    [self addTool:@"read_qr"
      description:@"The contents of every QR code in an image, top to bottom, read by macOS's detector."
           schema:Schema(@{@"path": Prop(@"string", @"The image file.")}, @[@"path"])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *path = StringParam(args, @"path").stringByExpandingTildeInPath.stringByStandardizingPath;
        NSImage *image = path.length ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
        if (!image) { *error = Fail(@"Not an image: %@", path ?: @""); return nil; }
        NSString *text = [EditorController textFromQRCodesInImage:image];
        return @{@"path": path, @"text": text ?: @"", @"found": @(text != nil)};
    }];

    [self addTool:@"spell_check"
      description:@"Misspelled words in a text or an open document, with suggestions, from macOS's spelling engine "
                  @"and its dictionaries - the one the editor squiggles with. The language is detected unless given "
                  @"(en, en_GB, de, fr, ru...). The whole text is checked, code included; for prose, comments and "
                  @"strings."
           schema:Schema(@{@"document": DocumentProp(),
                           @"text": Prop(@"string", @"A text instead of a document."),
                           @"language": Prop(@"string", @"Spelling language, e.g. en_US, de, ru; detected without it."),
                           @"limit": Prop(@"integer", @"At most this many words, 200 without it.")}, @[])
          handler:^NSDictionary *(NSDictionary *args, NSError **error) {
        NSString *text = Param(args, @"text");
        NSDictionary *info = nil;
        if (![text isKindOfClass:[NSString class]]) {
            DOC_OR_FAIL(args)
            __block NSString *whole = @"";
            [weakSelf readDocument:doc using:^(ScintillaView *sci) { whole = TextBetween(sci, 0, Msg(sci, SCI_GETLENGTH)); }];
            text = whole;
            info = [weakSelf infoOf:doc];
        }
        NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
        NSString *language = StringParam(args, @"language");
        NSString *before = checker.language;
        BOOL automatic = checker.automaticallyIdentifiesLanguages;
        if (language.length) {
            if (![checker setLanguage:language]) { *error = Fail(@"The spelling engine has no language %@ (it has: %@)", language, [checker.availableLanguages componentsJoinedByString:@", "]); return nil; }
            checker.automaticallyIdentifiesLanguages = NO;
        } else {
            checker.automaticallyIdentifiesLanguages = YES;
        }
        NSInteger tag = [NSSpellChecker uniqueSpellDocumentTag];
        NSOrthography *orthography = nil;
        NSArray<NSTextCheckingResult *> *results = [checker checkString:text range:NSMakeRange(0, text.length)
                                                                  types:NSTextCheckingTypeSpelling | NSTextCheckingTypeOrthography
                                                                options:nil inSpellDocumentWithTag:tag
                                                            orthography:&orthography wordCount:NULL];
        long limit = LongParam(args, @"limit", 200);
        NSMutableArray *words = [NSMutableArray array];
        NSString *used = language.length ? language : (orthography.dominantLanguage ?: checker.language);
        long line = 1;
        NSUInteger scanned = 0;
        for (NSTextCheckingResult *r in results) {
            if (r.resultType != NSTextCheckingTypeSpelling) continue;
            if ((long)words.count >= limit) break;
            NSRange range = r.range;
            for (; scanned < range.location; ++scanned) if ([text characterAtIndex:scanned] == '\n') line++;
            NSUInteger lineStart = [text rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, range.location)].location;
            lineStart = lineStart == NSNotFound ? 0 : lineStart + 1;
            NSString *word = [text substringWithRange:range];
            NSArray *guesses = [checker guessesForWordRange:range inString:text language:used inSpellDocumentWithTag:tag] ?: @[];
            [words addObject:@{@"word": word, @"line": @(line), @"column": @(range.location - lineStart + 1),
                               @"suggestions": guesses.count > 5 ? [guesses subarrayWithRange:NSMakeRange(0, 5)] : guesses}];
        }
        [checker closeSpellDocumentWithTag:tag];
        checker.automaticallyIdentifiesLanguages = automatic;
        if (language.length && before.length) [checker setLanguage:before];
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:@{@"misspelled": words, @"language": used ?: @"", @"truncated": @((long)words.count >= limit)}];
        if (info) out[@"document"] = info;
        return out;
    }];
    #undef ED
    #undef DOC_OR_FAIL
}

@end
