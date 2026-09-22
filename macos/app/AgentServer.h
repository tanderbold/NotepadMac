// The editor as a set of tools for AI coding agents, spoken over the Model
// Context Protocol (MCP). The application listens on a Unix socket that only
// the user's own processes can open; `nppmac mcp` bridges an agent's stdio to
// it, so Claude Code, Cursor and the like are one line of configuration away
// from what the editor knows: which documents are open, unsaved text, the
// selection, the language a text is in, a lexer's tokens, Notepad++'s own
// searches, Compare, the Function List, uchardet, OCR and the spelling engine.
//
// Off by default: Preferences > MISC. turns it on. Windows Notepad++ has
// nothing of the kind; nothing here leaves the Mac.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

@interface NppAgentServer : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) EditorController *editor;

/// Where the socket is: ~/Library/Application Support/NotepadMac/agent.sock,
/// or what NPPMAC_AGENT_SOCKET names (the suite uses its own).
+ (NSString *)socketPath;

/// Listens, unless already listening or another instance is. NO with a log
/// line when the socket cannot be made.
- (BOOL)start;
- (void)stop;
@property (nonatomic, readonly) BOOL running;

/// The tools, as tools/list describes them.
- (NSArray<NSDictionary *> *)toolDescriptions;
/// One JSON-RPC message, answered on the calling thread, which must be the
/// main one. nil for a notification, which has no answer. The socket and the
/// suite both come through here.
- (nullable NSDictionary *)handleMessage:(NSDictionary *)message;
/// One tool, called directly: the result as the tool returns it, or an
/// NSError. For the suite.
- (nullable NSDictionary *)callTool:(NSString *)name arguments:(nullable NSDictionary *)arguments
                              error:(NSError *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
