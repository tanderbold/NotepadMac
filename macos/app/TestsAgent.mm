// The built-in suite, the agent interface (MCP).
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Agent interface (MCP) ==
void NppTestsAgent(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Agent interface (MCP)")) { printf("\n== Agent interface (MCP) ==\n");
        NppAgentServer *agent = [NppAgentServer shared];
        agent.editor = ed;
        NSDictionary *(^rpc)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *method, NSDictionary *params) {
            return [agent handleMessage:@{@"jsonrpc": @"2.0", @"id": @1, @"method": method, @"params": params ?: @{}}];
        };
        NSDictionary *(^tool)(NSString *, NSDictionary *) = ^NSDictionary *(NSString *name, NSDictionary *args) {
            NSError *error = nil;
            NSDictionary *out = [agent callTool:name arguments:args error:&error];
            return out ?: @{@"error": error.localizedDescription ?: @"?"};
        };
        NSUInteger before = ed.documents.count;

        // The protocol: initialize answers with a version and the server's name; the tool list is complete.
        NSDictionary *init = rpc(@"initialize", @{@"protocolVersion": @"2025-03-26", @"capabilities": @{}});
        NSArray *tools = rpc(@"tools/list", nil)[@"result"][@"tools"];
        NSMutableSet *names = [NSMutableSet set];
        BOOL described = tools.count > 0;
        for (NSDictionary *t in tools) {
            [names addObject:t[@"name"]];
            if (![t[@"description"] length] || ![t[@"inputSchema"] isKindOfClass:[NSDictionary class]]) described = NO;
        }
        NSSet *expected = [NSSet setWithArray:@[@"list_documents", @"get_document", @"get_selection", @"open_document", @"close_document",
            @"go_to", @"edit_document", @"save_document", @"bookmarks", @"list_commands", @"run_command", @"detect_language", @"tokens",
            @"function_list", @"find", @"replace", @"compare", @"file_encoding", @"ocr", @"read_qr", @"spell_check"]];
        Check(@"Agent (protocol)", @"initialize names the server and the protocol version asked for; ping answers; every tool is described",
              [init[@"result"][@"protocolVersion"] isEqualToString:@"2025-03-26"] &&
              [init[@"result"][@"serverInfo"][@"name"] isEqualToString:@"NotepadMac"] &&
              [rpc(@"ping", nil)[@"result"] isKindOfClass:[NSDictionary class]] &&
              [names isEqualToSet:expected] && described &&
              [rpc(@"nothing/here", nil)[@"error"][@"code"] integerValue] == -32601 &&
              [agent handleMessage:@{@"jsonrpc": @"2.0", @"method": @"notifications/initialized"}] == nil);

        // A document from text, with its language: the lexer's tokens are what the editor colours.
        NSDictionary *opened = tool(@"open_document", @{@"text": @"int main() { return 0; } // hi\n", @"language": @"cpp", @"title": @"agent.cpp"});
        NSArray *tokens = tool(@"tokens", @{@"include_folds": @YES})[@"tokens"];
        NSMutableArray *styles = [NSMutableArray array];
        for (NSArray *t in tokens) [styles addObject:[NSString stringWithFormat:@"%@:%@", t[2], t[3]]];
        Check(@"Agent (open_document, tokens)", @"a text opens as a C++ document and its tokens carry Notepad++'s style names",
              [opened[@"language"] isEqualToString:@"cpp"] && [ed.currentDocument.displayName isEqualToString:@"agent.cpp"] &&
              [styles containsObject:@"TYPE WORD:int"] && [styles containsObject:@"INSTRUCTION WORD:return"] &&
              [styles containsObject:@"COMMENT LINE:// hi"] && [styles containsObject:@"NUMBER:0"]);

        // Edits: several at once, applied as one undo step, on a document that is not in front.
        NSString *sample = TempFile(@"t_agent.txt", @"one\ntwo\nthree\n");
        tool(@"open_document", @{@"path": sample});
        NppDocument *sampleDoc = ed.currentDocument;
        [ed selectDocumentAtIndex:[opened[@"index"] integerValue]];   // agent.cpp in front, the file behind
        NSDictionary *edited = tool(@"edit_document", @{@"document": @"t_agent.txt", @"edits": @[
            @{@"start_line": @2, @"end_line": @2, @"text": @"TWO\n"},
            @{@"start_line": @1, @"start_column": @1, @"end_line": @1, @"end_column": @2, @"text": @"O"}]});
        NSString *afterEdit = tool(@"get_document", @{@"document": sample})[@"text"];
        BOOL frontKept = ed.currentDocument != sampleDoc;
        BOOL markedModified = sampleDoc.modified;   // undo below returns it to its save point
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:sampleDoc]];
        [ed.sci message:SCI_UNDO wParam:0 lParam:0];
        NSString *afterUndo = DocText(ed);
        Check(@"Agent (edit_document)", @"two edits land bottom-up as one undo step, the tab in front stays, the document is marked modified",
              [edited[@"applied"] integerValue] == 2 && [afterEdit isEqualToString:@"One\nTWO\nthree\n"] && frontKept &&
              markedModified && !sampleDoc.modified && [afterUndo isEqualToString:@"one\ntwo\nthree\n"]);
        tool(@"edit_document", @{@"document": sample, @"text": @"one\ntwo\nthree\n"});
        NSString *partial = tool(@"get_document", @{@"document": sample, @"first_line": @2, @"last_line": @2})[@"text"];
        NSDictionary *overlap = tool(@"edit_document", @{@"document": sample, @"edits": @[
            @{@"start_line": @1, @"end_line": @2, @"text": @""}, @{@"start_line": @2, @"end_line": @3, @"text": @""}]});
        Check(@"Agent (get_document)", @"a line range comes back alone; overlapping edits are refused whole",
              [partial isEqualToString:@"two\n"] && overlap[@"error"] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\n"]);

        // Search with Notepad++'s engine: regex hits with their place; a bad pattern names its fault; replace with $1.
        NSDictionary *found = tool(@"find", @{@"what": @"t.o", @"mode": @"regex", @"document": sample});
        NSDictionary *bad = tool(@"find", @{@"what": @"(", @"mode": @"regex", @"document": sample});
        NSDictionary *replaced = tool(@"replace", @{@"what": @"(t)hree", @"replacement": @"$1HREE", @"mode": @"regex", @"document": sample});
        Check(@"Agent (find, replace)", @"a regex finds 'two' at line 2, an unbalanced one is refused with the reason, $1 works in replace",
              [found[@"hits"] integerValue] == 1 && [found[@"matches"][0][@"line"] integerValue] == 2 &&
              [found[@"matches"][0][@"match"] isEqualToString:@"two"] &&
              [bad[@"error"] containsString:@"parenthesis"] &&
              [replaced[@"replaced"] integerValue] == 1 && [DocText(ed) isEqualToString:@"one\ntwo\ntHREE\n"]);
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_folder"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[folder stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"alpha\nbeta\n" writeToFile:[folder stringByAppendingPathComponent:@"a.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        [@"beta gamma\n" writeToFile:[folder stringByAppendingPathComponent:@"sub/b.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *inFiles = tool(@"find", @{@"what": @"beta", @"folder": folder, @"filters": @"*.txt"});
        NSDictionary *inAll = tool(@"find", @{@"what": @"beta", @"folder": folder});
        Check(@"Agent (find in files)", @"a folder search honours the filter and returns Notepad++'s report",
              [inFiles[@"hits"] integerValue] == 1 && [inAll[@"hits"] integerValue] == 2 &&
              [inFiles[@"report"] containsString:@"a.txt (1 hit)"] && [inFiles[@"report"] containsString:@"Line 2: beta"]);

        // The editor's judgement of a text: the model, and the Function List parsers as written.
        NSDictionary *detected = tool(@"detect_language", @{@"text": @"def f(x):\n    return [i * 2 for i in range(x)]\n\nimport os\n", @"filename": @"x.py"});
        NSDictionary *functions = tool(@"function_list", @{@"text": @"class A:\n    def m(self):\n        pass\ndef g():\n    pass\n", @"language": @"python"});
        NSArray *entries = functions[@"entries"];
        Check(@"Agent (detect_language, function_list)", @"Python is the first guess of a Python snippet and what x.py would give; the parser finds the class, its method and the function",
              [detected[@"guesses"][0][@"language"] isEqualToString:@"python"] && [detected[@"by_filename"] isEqualToString:@"python"] &&
              entries.count == 3 && [entries[0][@"name"] isEqualToString:@"A"] && [entries[0][@"is_class"] boolValue] &&
              [entries[1][@"container"] isEqualToString:@"A"] && [entries[1][@"line"] integerValue] == 2 &&
              [entries[2][@"name"] isEqualToString:@"g()"]);

        // Compare: the counts and the differing runs; a Windows-1251 file with CRLF is read as the editor reads it.
        NSDictionary *compared = tool(@"compare", @{@"left": @{@"text": @"a\nb\nc\n"}, @"right": @{@"text": @"a\nB\nc\nd\n"}});
        NSData *cyrillic = [@"Привет\r\nмир\r\n" dataUsingEncoding:NSWindowsCP1251StringEncoding];
        NSString *cp1251 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_1251.txt"];
        [cyrillic writeToFile:cp1251 atomically:YES];
        NSDictionary *encoding = tool(@"file_encoding", @{@"path": cp1251});
        Check(@"Agent (compare, file_encoding)", @"one changed and one added line, in two runs; the 1251 file is detected with CRLF endings and decoded for the preview",
              [compared[@"changed"] integerValue] == 1 && [compared[@"added"] integerValue] == 1 && [compared[@"hunks"] count] == 2 &&
              [compared[@"hunks"][0][@"new_lines"][0] isEqualToString:@"B"] &&
              [[encoding[@"charset_detected"] uppercaseString] containsString:@"1251"] && [encoding[@"eol"] isEqualToString:@"CRLF"] &&
              [encoding[@"lines"] integerValue] == 2 && [encoding[@"preview"] hasPrefix:@"Привет"]);

        // Marks and places for the user: bookmarks, a selection put where the agent says, and what the selection is.
        NSDictionary *marks = tool(@"bookmarks", @{@"document": sample, @"add": @[@1, @3]});
        NSDictionary *went = tool(@"go_to", @{@"document": sample, @"line": @3, @"column": @2, @"end_line": @3});
        NSDictionary *selection = tool(@"get_selection", nil);
        Check(@"Agent (bookmarks, go_to, get_selection)", @"lines 1 and 3 are bookmarked; go_to selects from line 3 column 2 to its end, and get_selection reports it",
              [marks[@"bookmarked_lines"] isEqualToArray:@[@1, @3]] && ed.currentDocument == sampleDoc &&
              [went[@"start"][@"column"] integerValue] == 2 && [selection[@"text"] isEqualToString:@"HREE"] &&
              [selection[@"start"][@"line"] integerValue] == 3 && [selection[@"end"][@"column"] integerValue] == 6);

        // Menu commands by name: the list finds them, run_command runs them on the selection; quitting is refused.
        NSDictionary *listed = tool(@"list_commands", @{@"query": @"lowercase"});
        tool(@"go_to", @{@"document": sample, @"line": @3, @"column": @1, @"end_line": @3});
        NSDictionary *ran = tool(@"run_command", @{@"command": @"IDM_EDIT_LOWERCASE"});
        NSDictionary *byPath = tool(@"run_command", @{@"command": @"Edit|Line Operations|Sort Lines Lexicographically Ascending"});
        NSDictionary *refused = tool(@"run_command", @{@"command": @"IDM_FILE_EXIT"});
        printf("DEBUG agent commands: listed=%s ran=%s text=[%s] byPath=%s refused=%s\n", [listed description].UTF8String, [ran description].UTF8String, DocText(ed).UTF8String, [byPath description].UTF8String, [refused description].UTF8String);
        Check(@"Agent (list_commands, run_command)", @"lowercase is found by a word of its label, runs on the selection, sort runs by menu path, exit is refused",
              [listed[@"commands"] count] >= 1 && [listed[@"commands"][0][@"name"] isEqualToString:@"IDM_EDIT_LOWERCASE"] &&
              [ran[@"ran"] boolValue] && [DocText(ed) isEqualToString:@"one\ntwo\nthree\n"] &&
              [byPath[@"ran"] boolValue] && refused[@"error"] != nil);

        // The spelling engine, with suggestions.
        NSDictionary *spelled = tool(@"spell_check", @{@"text": @"This is a smiple sentense.", @"language": @"en"});
        NSArray *words = spelled[@"misspelled"];
        Check(@"Agent (spell_check)", @"the two misspelled words come back in order with their places and the right first suggestions",
              words.count == 2 && [words[0][@"word"] isEqualToString:@"smiple"] && [words[0][@"column"] integerValue] == 11 &&
              [words[0][@"suggestions"] containsObject:@"simple"] && [words[1][@"suggestions"] containsObject:@"sentence"]);

        // Closing: a modified document is kept unless the agent says to discard it.
        tool(@"edit_document", @{@"document": sample, @"edits": @[@{@"start_line": @1, @"end_line": @1, @"text": @"ONE\n"}]});
        NSDictionary *kept = tool(@"close_document", @{@"document": sample});
        NSDictionary *closedText = tool(@"close_document", @{@"document": @"agent.cpp"});
        NSDictionary *discarded = tool(@"close_document", @{@"document": sample, @"discard_changes": @YES});
        Check(@"Agent (close_document)", @"a modified document stays unless discard_changes; an unmodified one closes; the suite is back where it started",
              kept[@"error"] != nil && [closedText[@"closed"] boolValue] && [discarded[@"closed"] boolValue] && ed.documents.count == before);


        // Saving: to the document's own file, in place; a document without a file is the user's Save As.
        NSString *savePath = TempFile(@"t_agent_save.txt", @"before\n");
        tool(@"open_document", @{@"path": savePath});
        NppDocument *saveDoc = ed.currentDocument;
        tool(@"open_document", @{@"text": @"scratch\n", @"title": @"scratch.txt"});
        tool(@"edit_document", @{@"document": savePath, @"text": @"after\n"});
        NSDictionary *saved = tool(@"save_document", @{@"document": savePath});
        NSString *onDisk = [NSString stringWithContentsOfFile:savePath encoding:NSUTF8StringEncoding error:NULL];
        NSDictionary *noFile = tool(@"save_document", @{@"document": @"scratch.txt"});
        Check(@"Agent (save_document)", @"a document that is not in front is written to its file and is clean; one without a file is refused with a pointer to Save As",
              [saved[@"saved"] boolValue] && [onDisk isEqualToString:@"after\n"] && !saveDoc.modified && ed.currentDocument != saveDoc &&
              [noFile[@"error"] containsString:@"Save As"]);
        tool(@"close_document", @{@"document": savePath});
        tool(@"close_document", @{@"document": @"scratch.txt", @"discard_changes": @YES});

        // What is refused, and why: a read-only document, a missing file, an unknown language, a line past the end, an unknown command.
        NSString *roPath = TempFile(@"t_agent_ro.txt", @"locked\n");
        tool(@"open_document", @{@"path": roPath});
        ed.currentDocument.userReadOnly = YES;
        NSDictionary *roEdit = tool(@"edit_document", @{@"edits": @[@{@"start_line": @1, @"end_line": @1, @"text": @"x\n"}]});
        NSDictionary *roReplace = tool(@"replace", @{@"what": @"locked", @"replacement": @"open"});
        ed.currentDocument.userReadOnly = NO;
        NSDictionary *missing = tool(@"open_document", @{@"path": @"/nowhere/t_agent_missing.txt"});
        NSDictionary *noLang = tool(@"open_document", @{@"text": @"x", @"language": @"klingon"});
        NSDictionary *pastEnd = tool(@"go_to", @{@"line": @99});
        NSDictionary *noCommand = tool(@"run_command", @{@"command": @"IDM_NOTHING_OF_THE_KIND"});
        NSDictionary *noArgs = tool(@"edit_document", @{});
        BOOL noStrayTab = ed.documents.count == before + 1;   // the refused language opened nothing
        Check(@"Agent (refusals)", @"read-only, a missing file, an unknown language (without a stray tab), a line past the end, an unknown command and an edit with nothing in it are each refused with a reason",
              noStrayTab &&
              [roEdit[@"error"] containsString:@"read-only"] && [roReplace[@"error"] containsString:@"read-only"] &&
              [DocText(ed) isEqualToString:@"locked\n"] &&
              [missing[@"error"] containsString:@"No such file"] && [noLang[@"error"] containsString:@"klingon"] &&
              [pastEnd[@"error"] containsString:@"outside"] && [noCommand[@"error"] containsString:@"IDM_NOTHING_OF_THE_KIND"] &&
              [noArgs[@"error"] containsString:@"text or edits"]);
        tool(@"close_document", @{@"document": roPath, @"discard_changes": @YES});

        // Tokens of a document that is not in front, read through the hidden view, with fold levels; a long answer is cut and says so.
        tool(@"open_document", @{@"text": @"void f() {\n  if (x) {\n    y();\n  }\n}\n", @"language": @"cpp", @"title": @"folds.cpp"});
        tool(@"open_document", @{@"text": @"front\n", @"title": @"front.txt"});
        NSDictionary *foldTokens = tool(@"tokens", @{@"document": @"folds.cpp", @"include_folds": @YES, @"first_line": @2, @"last_line": @3});
        NSArray *folds = foldTokens[@"folds"];
        NSMutableString *big = [NSMutableString string];
        for (int i = 0; i < 20000; ++i) [big appendString:@"0123456789012345678901234567890123456789012345678901234567890123456789012345678\n"];   // 80 bytes a line, 1.6 MB
        tool(@"open_document", @{@"text": big, @"title": @"big.txt"});
        NSDictionary *cut = tool(@"get_document", @{@"document": @"big.txt"});
        NSDictionary *range = tool(@"get_document", @{@"document": @"big.txt", @"first_line": @19999, @"last_line": @30000});
        Check(@"Agent (tokens of a background document, truncation)", @"lines 2-3 of a document behind another come with their tokens and fold levels, the front tab untouched; a 1.6 MB text is cut at a million characters and says so, a line range past the end is clipped",
              [ed.currentDocument.displayName isEqualToString:@"big.txt"] &&
              [foldTokens[@"first_line"] integerValue] == 2 && [foldTokens[@"tokens"] count] >= 4 &&
              [[foldTokens[@"tokens"] firstObject][0] integerValue] == 2 && [[foldTokens[@"tokens"] firstObject][2] isEqualToString:@"INSTRUCTION WORD"] &&
              folds.count == 2 && [folds[0][1] integerValue] == 1 && [folds[0][2] boolValue] && [folds[1][1] integerValue] == 2 &&
              [cut[@"truncated"] boolValue] && [cut[@"text"] length] <= 1000000 && [cut[@"last_line"] integerValue] < 20000 &&
              ![range[@"truncated"] boolValue] && [range[@"first_line"] integerValue] == 19999 && [range[@"last_line"] integerValue] == 20001 &&
              [range[@"text"] hasPrefix:@"0123456789"]);
        tool(@"close_document", @{@"document": @"big.txt", @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"front.txt", @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"folds.cpp", @"discard_changes": @YES});

        // Search modes: extended escapes, whole word and match case, the limit, the results panel; replace in normal mode.
        NSString *modes = TempFile(@"t_agent_modes.txt", @"Cat cat catalog\ncat\tcat\nconcat\n");
        tool(@"open_document", @{@"path": modes});
        NSDictionary *extended = tool(@"find", @{@"what": @"cat\\tcat", @"mode": @"extended"});
        NSDictionary *whole = tool(@"find", @{@"what": @"cat", @"whole_word": @YES, @"match_case": @YES});
        NSDictionary *limited = tool(@"find", @{@"what": @"cat", @"limit": @2, @"show_results": @YES});
        BOOL resultsShown = NO;
        for (NppDocument *d in ed.documents) if (d.isSearchResults) resultsShown = YES;
        NSDictionary *plainReplace = tool(@"replace", @{@"what": @"cat", @"replacement": @"dog", @"whole_word": @YES, @"match_case": @YES, @"document": modes});
        NSDictionary *nothing = tool(@"replace", @{@"what": @"zebra", @"replacement": @"x", @"document": modes});
        NSString *modesText = tool(@"get_document", @{@"document": modes})[@"text"];
        BOOL modesDoc = YES;
        Check(@"Agent (find modes, replace)", @"\\t in extended mode finds the tabbed pair; whole word + match case finds 3 of the 6; a limit of 2 says truncated and the results panel opens; the plain replace changes those 3 and a miss changes none",
              [extended[@"hits"] integerValue] == 1 && [extended[@"matches"][0][@"line"] integerValue] == 2 &&
              [whole[@"hits"] integerValue] == 3 && [limited[@"hits"] integerValue] == 6 && [limited[@"matches"] count] == 2 && [limited[@"truncated"] boolValue] &&
              resultsShown && modesDoc &&
              [plainReplace[@"replaced"] integerValue] == 3 && [nothing[@"replaced"] integerValue] == 0 &&
              [modesText isEqualToString:@"Cat dog catalog\ndog\tdog\nconcat\n"]);
        NSDictionary *listedDocs = tool(@"list_documents", nil);
        BOOL resultsHidden = YES;
        for (NSDictionary *d in listedDocs[@"documents"]) if ([d[@"title"] containsString:@"Search results"]) resultsHidden = NO;
        Check(@"Agent (list_documents)", @"the Search results tab is not listed as a document; the count and the modified flag are the editor's",
              resultsHidden && [listedDocs[@"documents"] count] == before + 1 && [listedDocs[@"workspace_roots"] isKindOfClass:[NSArray class]]);   // + the modes file, still open
        tool(@"close_document", @{@"document": modes, @"discard_changes": @YES});

        // Compare shown to the user: both files open, the Compare view active; ignore options honoured.
        NSString *leftPath = TempFile(@"t_agent_left.txt", @"same\nold line\n\nTail\n");
        NSString *rightPath = TempFile(@"t_agent_right.txt", @"same\nnew line\ntail\n");
        NSDictionary *shown = tool(@"compare", @{@"left": @{@"path": leftPath}, @"right": @{@"path": rightPath}, @"show": @YES,
                                                 @"ignore_case": @YES, @"ignore_empty_lines": @YES});
        BOOL comparing = [ed compareActive];
        NSDictionary *textsOnly = tool(@"compare", @{@"left": @{@"text": @"a\n"}, @"right": @{@"text": @"a\n"}, @"show": @YES});
        [ed clearAllCompares];
        Check(@"Agent (compare shown)", @"two files open side by side in the Compare view with one changed line (case and empty lines ignored); two texts cannot be shown and say so",
              [shown[@"shown"] boolValue] && comparing && [shown[@"changed"] integerValue] == 1 && [shown[@"added"] integerValue] == 0 &&
              [shown[@"removed"] integerValue] == 0 && [textsOnly[@"same"] boolValue] && ![textsOnly[@"shown"] boolValue] && textsOnly[@"note"] != nil);
        tool(@"close_document", @{@"document": leftPath, @"discard_changes": @YES});
        tool(@"close_document", @{@"document": rightPath, @"discard_changes": @YES});

        // Declared languages, the picture readers, and encodings with a mark or none.
        NSDictionary *shebang = tool(@"detect_language", @{@"text": @"#!/usr/bin/env perl\nprint 1;\n"});
        NSImage *qrPicture = [EditorController qrImageFromText:@"https://tanderbold.github.io/NotepadMac/" side:300];
        NSString *qrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_qr.png"];
        [[[[NSBitmapImageRep alloc] initWithData:qrPicture.TIFFRepresentation] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:qrPath atomically:YES];
        NSDictionary *qrRead = tool(@"read_qr", @{@"path": qrPath});
        NSImage *ocrPicture = [[NSImage alloc] initWithSize:NSMakeSize(640, 140)];
        [ocrPicture lockFocus];
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, 640, 140));
        [@"AGENT OCR 7" drawAtPoint:NSMakePoint(24, 36) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:56], NSForegroundColorAttributeName: [NSColor blackColor]}];
        [ocrPicture unlockFocus];
        NSString *ocrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_ocr.png"];
        [[[[NSBitmapImageRep alloc] initWithData:ocrPicture.TIFFRepresentation] representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:ocrPath atomically:YES];
        NSDictionary *ocrRead = tool(@"ocr", @{@"path": ocrPath});
        NSDictionary *noPicture = tool(@"read_qr", @{@"path": sample});
        NSString *bomPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_bom.txt"];
        NSMutableData *bomData = [NSMutableData dataWithBytes:"\xEF\xBB\xBF" length:3];
        [bomData appendData:[@"x\ny" dataUsingEncoding:NSUTF8StringEncoding]];
        [bomData writeToFile:bomPath atomically:YES];
        NSString *u16Path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_u16.txt"];
        [[@"hello\r\nworld" dataUsingEncoding:NSUTF16LittleEndianStringEncoding] writeToFile:u16Path atomically:YES];
        NSString *binPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent_bin.dat"];
        unsigned char zeros[64] = {0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3, 0xFF, 0xFE};
        [[NSData dataWithBytes:zeros length:sizeof zeros] writeToFile:binPath atomically:YES];
        NSDictionary *bomInfo = tool(@"file_encoding", @{@"path": bomPath, @"preview_chars": @1});
        NSDictionary *u16Info = tool(@"file_encoding", @{@"path": u16Path});
        NSDictionary *binInfo = tool(@"file_encoding", @{@"path": binPath});
        Check(@"Agent (detect_language declared, ocr, read_qr, file_encoding marks)", @"a shebang is the declared language; the QR picture and the OCR picture read back; a text file is no QR; the BOM, UTF-16 without a mark and a binary file are told apart",
              [shebang[@"declared"] isEqualToString:@"perl"] && [shebang[@"offered"] isEqualToArray:@[@"perl"]] &&
              [qrRead[@"text"] isEqualToString:@"https://tanderbold.github.io/NotepadMac/"] &&
              [[ocrRead[@"text"] uppercaseString] containsString:@"AGENT OCR 7"] &&
              ![noPicture[@"found"] boolValue] && noPicture[@"error"] != nil &&
              [bomInfo[@"bom"] isEqualToString:@"UTF-8"] && [bomInfo[@"encoding"] isEqualToString:@"UTF-8"] && [bomInfo[@"preview"] isEqualToString:@"x"] &&
              [bomInfo[@"lines"] integerValue] == 2 &&
              [u16Info[@"utf16_without_bom"] isEqualToString:@"UTF-16 LE"] && [u16Info[@"eol"] isEqualToString:@"CRLF"] && [u16Info[@"preview"] hasPrefix:@"hello"] &&
              [binInfo[@"binary"] boolValue]);

        // Spelling of a document, and a language the engine does not have.
        tool(@"open_document", @{@"text": @"# a coment\nx = 1\n", @"title": @"spell.py", @"language": @"python"});
        NSDictionary *docSpelled = tool(@"spell_check", @{@"language": @"en"});
        NSDictionary *noSuchLanguage = tool(@"spell_check", @{@"text": @"x", @"language": @"xx_NOWHERE"});
        tool(@"close_document", @{@"document": @"spell.py", @"discard_changes": @YES});
        Check(@"Agent (spell_check of a document)", @"the document in front is checked, the misspelling placed on its line; a language the engine lacks is refused with the list it has",
              [docSpelled[@"misspelled"] count] == 1 && [docSpelled[@"misspelled"][0][@"word"] isEqualToString:@"coment"] &&
              [docSpelled[@"misspelled"][0][@"line"] integerValue] == 1 && docSpelled[@"document"] != nil &&
              [noSuchLanguage[@"error"] containsString:@"xx_NOWHERE"]);

        // Bookmarks on a document behind another survive the switch, and remove/clear work.
        NSString *marksPath = TempFile(@"t_agent_marks.txt", @"a\nb\nc\nd\n");
        tool(@"open_document", @{@"path": marksPath});
        NppDocument *marksDoc = ed.currentDocument;
        tool(@"open_document", @{@"text": @"cover\n", @"title": @"cover.txt"});
        tool(@"bookmarks", @{@"document": marksPath, @"add": @[@2, @4, @9]});
        NSDictionary *removedOne = tool(@"bookmarks", @{@"document": marksPath, @"remove": @[@2]});
        BOOL recorded = [marksDoc.bookmarkedLines isEqualToArray:@[@3]];   // zero-based, as the session keeps them
        [ed selectDocumentAtIndex:(NSInteger)[ed.documents indexOfObjectIdenticalTo:marksDoc]];
        long markerOnFour = [ed.sci message:SCI_MARKERGET wParam:3 lParam:0] & (1 << 1);
        NSDictionary *cleared = tool(@"bookmarks", @{@"document": marksPath, @"clear": @YES, @"add": @[@1]});
        Check(@"Agent (bookmarks behind, remove, clear)", @"marks set on a document behind another are recorded and shown when it comes to front; a line past the end is ignored; remove and clear do what they say",
              [removedOne[@"bookmarked_lines"] isEqualToArray:@[@4]] && recorded && markerOnFour &&
              [cleared[@"bookmarked_lines"] isEqualToArray:@[@1]]);
        tool(@"close_document", @{@"document": marksPath, @"discard_changes": @YES});
        tool(@"close_document", @{@"document": @"cover.txt", @"discard_changes": @YES});

        // A disabled command reports so instead of pretending; the protocol wraps a tool's failure as an error result, not a protocol error.
        [ed.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
        NSDictionary *redo = tool(@"run_command", @{@"command": @"IDM_EDIT_REDO"});
        NSDictionary *wrapped = rpc(@"tools/call", @{@"name": @"get_document", @"arguments": @{@"document": @"no-such-document.txt"}});
        NSDictionary *good = rpc(@"tools/call", @{@"name": @"list_documents", @"arguments": @{}});
        Check(@"Agent (disabled command, error results)", @"Redo with nothing to redo answers ran=false, enabled=false; a failing tool is an isError result with the reason as text; a good one carries text and structured content",
              ![redo[@"ran"] boolValue] && ![redo[@"enabled"] boolValue] &&
              [wrapped[@"result"][@"isError"] boolValue] && [wrapped[@"result"][@"content"][0][@"text"] containsString:@"no-such-document.txt"] &&
              ![good[@"result"][@"isError"] boolValue] && [good[@"result"][@"content"][0][@"type"] isEqualToString:@"text"] &&
              [good[@"result"][@"structuredContent"][@"documents"] isKindOfClass:[NSArray class]] &&
              [agent handleMessage:@{@"jsonrpc": @"2.0", @"method": @"tools/list"}] == nil);
        // Off by default; on, the socket is the user's alone and answers a line with a line - through nppmac mcp too.
        NppPreferences *ap = [NppPreferences shared];
        BOOL wasOn = ap.agentServer;
        BOOL offByDefault = !ap.agentServer && !agent.running;
        NSString *sock = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent.sock"];
        setenv("NPPMAC_AGENT_SOCKET", sock.fileSystemRepresentation, 1);
        BOOL started = [agent start];
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:sock error:NULL];
        NSString *helper = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Contents/Helpers/nppmac"];
        NSTask *bridge = [[NSTask alloc] init];
        bridge.executableURL = [NSURL fileURLWithPath:helper];
        bridge.arguments = @[@"mcp"];
        NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
        env[@"NPPMAC_AGENT_SOCKET"] = sock;
        bridge.environment = env;
        NSPipe *toBridge = [NSPipe pipe], *fromBridge = [NSPipe pipe];
        bridge.standardInput = toBridge;
        bridge.standardOutput = fromBridge;
        bridge.standardError = [NSPipe pipe];
        __block NSMutableData *answered = [NSMutableData data];
        fromBridge.fileHandleForReading.readabilityHandler = ^(NSFileHandle *h) {
            NSData *d = h.availableData;
            @synchronized (answered) { [answered appendData:d]; }
        };
        BOOL launched = [bridge launchAndReturnError:NULL];
        [toBridge.fileHandleForWriting writeData:[@"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{}}}\n"
                                                  @"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n"
                                                  @"{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"list_documents\",\"arguments\":{}}}\n"
                                                  dataUsingEncoding:NSUTF8StringEncoding]];
        NppSettleUntil(^BOOL{
            @synchronized (answered) { return [[[NSString alloc] initWithData:answered encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"].count >= 3; }
        }, 10);
        [toBridge.fileHandleForWriting closeFile];
        fromBridge.fileHandleForReading.readabilityHandler = nil;
        NSArray *lines = [[[NSString alloc] initWithData:answered encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
        NSDictionary *first = lines.count > 0 ? [NSJSONSerialization JSONObjectWithData:[lines[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        NSDictionary *second = lines.count > 1 ? [NSJSONSerialization JSONObjectWithData:[lines[1] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        NppSettleUntil(^BOOL{ return !bridge.isRunning; }, 5);
        [agent stop];
        BOOL gone = ![[NSFileManager defaultManager] fileExistsAtPath:sock];
        unsetenv("NPPMAC_AGENT_SOCKET");
        ap.agentServer = wasOn;
        Check(@"Agent (socket, nppmac mcp)", @"off by default; started, the socket is mode 0600, nppmac mcp relays initialize and a tool call and ends with its input; stopped, the socket file is gone",
              offByDefault && started && launched && [attrs[NSFilePosixPermissions] integerValue] == 0600 &&
              [first[@"id"] integerValue] == 7 && [first[@"result"][@"serverInfo"][@"name"] isEqualToString:@"NotepadMac"] &&
              [second[@"id"] integerValue] == 8 && [second[@"result"][@"structuredContent"][@"documents"] isKindOfClass:[NSArray class]] &&
              !bridge.isRunning && gone);

        // The socket: a stale file is replaced, a second start is a no-op, a socket another process holds is left alone;
        // the preference starts and stops it; a broken line answers a parse error; two connections take turns.
        NSString *sock2 = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_agent2.sock"];
        setenv("NPPMAC_AGENT_SOCKET", sock2.fileSystemRepresentation, 1);
        [@"stale" writeToFile:sock2 atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        BOOL replacedStale = [agent start] && [agent start] && [[[NSFileManager defaultManager] attributesOfItemAtPath:sock2 error:NULL][NSFileType] isEqualToString:NSFileTypeSocket];
        NSString *(^ask)(NSString *) = ^NSString *(NSString *line) {
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            struct sockaddr_un addr; memset(&addr, 0, sizeof addr); addr.sun_family = AF_UNIX;
            strlcpy(addr.sun_path, sock2.fileSystemRepresentation, sizeof addr.sun_path);
            if (connect(fd, (struct sockaddr *)&addr, sizeof addr) != 0) { close(fd); return @"connect failed"; }
            __block NSMutableString *got = [NSMutableString string];
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                write(fd, line.UTF8String, strlen(line.UTF8String));
                char buf[65536];
                for (;;) {
                    ssize_t n = read(fd, buf, sizeof buf);
                    if (n <= 0) break;
                    [got appendString:[[NSString alloc] initWithBytes:buf length:(NSUInteger)n encoding:NSUTF8StringEncoding] ?: @""];
                    if ([got hasSuffix:@"\n"]) break;
                }
                close(fd);
                dispatch_semaphore_signal(done);
            });
            NppSettleUntil(^BOOL{ return dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) == 0; }, 10);
            return got;
        };
        NSString *parseError = ask(@"{not json\n");
        NSString *pingBack = ask(@"{\"jsonrpc\":\"2.0\",\"id\":\"p\",\"method\":\"ping\"}\n");
        NSString *secondConnection = ask(@"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"get_selection\",\"arguments\":{}}}\n");
        [agent stop];
        // Another process's socket: a listener of our own stands in for a second NotepadMac.
        int holder = socket(AF_UNIX, SOCK_STREAM, 0);
        struct sockaddr_un held; memset(&held, 0, sizeof held); held.sun_family = AF_UNIX;
        strlcpy(held.sun_path, sock2.fileSystemRepresentation, sizeof held.sun_path);
        unlink(held.sun_path);
        BOOL holding = bind(holder, (struct sockaddr *)&held, sizeof held) == 0 && listen(holder, 1) == 0;
        BOOL leftAlone = ![agent start] && !agent.running;
        close(holder);
        unlink(held.sun_path);
        // The preference, applied the way the Preferences window applies it.
        ap.agentServer = YES;
        [ap applyToEditor:ed];
        BOOL onByPreference = agent.running;
        ap.agentServer = NO;
        [ap applyToEditor:ed];
        BOOL offByPreference = !agent.running && ![[NSFileManager defaultManager] fileExistsAtPath:sock2];
        ap.agentServer = wasOn;
        unsetenv("NPPMAC_AGENT_SOCKET");
        Check(@"Agent (socket life)", @"a stale socket file is replaced and a second start is harmless; a broken line gets a parse error and the next connection is served; a socket another process holds is left alone; the MISC. setting starts and stops the listener and removes the file",
              replacedStale && [parseError containsString:@"-32700"] && [pingBack containsString:@"\"id\":\"p\""] &&
              [secondConnection containsString:@"structuredContent"] && holding && leftAlone && onByPreference && offByPreference);
    }
}
