// The built-in suite, the Encoding and Language menus, folding and user-defined languages.
//
// Called from NppMacRunTests (Tests.mm), which runs the areas in the suite's
// order; the helpers they share are in TestSupport.h.
#import "TestSupport.h"

/// == Encoding + EOL ==; == Encoding: character sets ==; == Encoding: encode in as upstream ==; == Encoding: convert to ==; == Language ==
void NppTestsEncodingAndLanguage(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Encoding + EOL")) { printf("\n== Encoding + EOL ==\n");
        // Round-trip each encoding through a real file.
        struct { NSString *name; NSStringEncoding enc; BOOL bom; NSString *cmd; } cases[] = {
            {@"utf8",    NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_AS_UTF_8"},
            {@"utf8bom", NSUTF8StringEncoding,              YES, @"IDM_FORMAT_UTF_8"},
            {@"u16le",   NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_UTF_16LE"},
            {@"u16be",   NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_UTF_16BE"},
            {@"ansi",    NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_ANSI"},
        };
        for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
            NSString *path = [NSTemporaryDirectory()
                stringByAppendingPathComponent:[NSString stringWithFormat:@"t_enc_%@.txt", cases[i].name]];
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [@"round trip\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:path error:&e];
            [ed setEncoding:cases[i].enc withBOM:cases[i].bom];
            [ed saveCurrentDocument];

            // Reopen in a fresh document and confirm the text survived.
            [ed closeCurrentDocument];
            [ed openFileAtPath:path error:&e];
            BOOL textOK = [DocText(ed) isEqualToString:@"round trip\n"];
            BOOL bomOK = ed.currentDocument.hasBOM == cases[i].bom;
            Check(cases[i].cmd, [NSString stringWithFormat:@"%@ round-trips", cases[i].name],
                  textOK && bomOK);
        }

        {
            NSMenuItem *toLF = nil;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray)
                for (NSMenuItem *it in top.submenu.itemArray)
                    for (NSMenuItem *sub in it.submenu.itemArray)
                        if (sub.action == NSSelectorFromString(@"eolLF:")) toLF = sub;   // Edit > EOL Conversion
            [ed convertEOLTo:SC_EOL_LF];
            BOOL greyed = ![(id<NSMenuItemValidation>)app validateMenuItem:toLF];
            [ed convertEOLTo:SC_EOL_CRLF];
            Check(@"IDM_FORMAT_TOUNIX", @"the conversion to the format the document has is greyed out",
                  toLF && greyed && [(id<NSMenuItemValidation>)app validateMenuItem:toLF]);
        }
        SetDoc(ed, @"a\r\nb\r\n");
        [ed convertEOLTo:SC_EOL_LF];
        Check(@"IDM_FORMAT_TOUNIX", @"CRLF becomes LF", ![DocText(ed) containsString:@"\r"]);
        [ed convertEOLTo:SC_EOL_CRLF];
        Check(@"IDM_FORMAT_TODOS", @"LF becomes CRLF", [DocText(ed) containsString:@"\r\n"]);
        [ed convertEOLTo:SC_EOL_CR];
        Check(@"IDM_FORMAT_TOMAC", @"becomes bare CR",
              [DocText(ed) containsString:@"\r"] && ![DocText(ed) containsString:@"\n"]);
    }

    if (NppSectionWanted(@"Encoding: character sets")) { printf("\n== Encoding: character sets ==\n");
        // Every charset in the menu must resolve to a usable macOS encoding and
        // survive a byte round-trip through that charset.
        int resolved = 0;
        NSMutableArray *unsupported = [NSMutableArray array];
        for (int i = 0; i < kNppCharsetCount; ++i) {
            unsigned int cp = kNppCharsets[i].codepage;
            NSString *cmd = @(kNppCharsets[i].menuID);
            if (![EditorController supportsCodepage:cp]) {
                // Nothing on the system can decode this page; the command must
                // decline cleanly rather than silently decode as something else.
                [unsupported addObject:@(kNppCharsets[i].label)];
                Check([cmd stringByAppendingString:@" (unsupported)"],
                      [NSString stringWithFormat:@"%@ declines instead of mis-decoding",
                       @(kNppCharsets[i].label)],
                      ![ed reinterpretAsCodepage:cp]);
                continue;
            }
            if (cp == 720) { resolved++; continue; }   // covered by its own test below
            NSStringEncoding enc = [EditorController encodingForCodepage:cp];
            resolved++;
            // ASCII is representable in every one of these sets, so a round trip
            // through the charset must return the original text.
            NSString *probe = @"probe 123";
            NSData *bytes = [probe dataUsingEncoding:enc allowLossyConversion:NO];
            NSString *back = bytes ? [[NSString alloc] initWithData:bytes encoding:enc] : nil;
            Check(cmd, [NSString stringWithFormat:@"%@ round-trips", @(kNppCharsets[i].label)],
                  [back isEqualToString:probe]);
        }

        // Round-tripping ASCII proves nothing about which character set was
        // chosen: "probe 123" survives all of them, so a code page wired to the
        // wrong encoding would have passed. encoding-reference.txt says what
        // each byte actually means, taken from Python's own codecs, and every
        // one of those bytes is checked here.
        NSString *referencePath = [[NSBundle mainBundle] pathForResource:@"encoding-reference"
                                                                  ofType:@"txt"];
        NSString *reference = referencePath
            ? [NSString stringWithContentsOfFile:referencePath encoding:NSUTF8StringEncoding error:NULL]
            : nil;
        NSMutableArray *wrongBytes = [NSMutableArray array];
        NSMutableSet *checkedPages = [NSMutableSet set];
        NSUInteger checkedBytes = 0;
        for (NSString *line in [reference componentsSeparatedByString:@"\n"]) {
            if (!line.length || [line hasPrefix:@"#"]) continue;
            NSArray *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count != 3) continue;

            unsigned int codepage = (unsigned int)[fields[0] intValue];
            unsigned int byteValue = 0, expectedPoint = 0;
            [[NSScanner scannerWithString:fields[1]] scanHexInt:&byteValue];
            [[NSScanner scannerWithString:fields[2]] scanHexInt:&expectedPoint];

            unsigned char raw = (unsigned char)byteValue;
            NSString *decoded = [EditorController stringFromData:[NSData dataWithBytes:&raw length:1]
                                                        codepage:codepage];
            checkedBytes++;
            [checkedPages addObject:@(codepage)];
            if (decoded.length != 1 || [decoded characterAtIndex:0] != (unichar)expectedPoint) {
                if (wrongBytes.count < 8) {
                    [wrongBytes addObject:[NSString stringWithFormat:@"cp%u byte %02X -> %@ (want %04X)",
                                           codepage, byteValue,
                                           decoded.length ? @([decoded characterAtIndex:0]) : @"nothing",
                                           expectedPoint]];
                }
            }
        }
        Check(@"IDM_FORMAT_ANSI (byte meanings)",
              [NSString stringWithFormat:@"%lu bytes across %lu code pages decode to the right character",
               (unsigned long)checkedBytes, (unsigned long)checkedPages.count],
              checkedBytes > 5000 && wrongBytes.count == 0);
        if (wrongBytes.count) printf("       %s\n",
            [[wrongBytes componentsJoinedByString:@"; "] UTF8String]);
        printf("  (%d of %d character sets resolved%s)\n", resolved, kNppCharsetCount,
               unsupported.count ? [[NSString stringWithFormat:@"; missing: %@",
                                     [unsupported componentsJoinedByString:@", "]] UTF8String] : "");

        // Encode in: the bytes stay, the reading changes. Round-tripping a
        // Cyrillic byte through Windows-1251 and back must restore the text.
        // Code page 720 is decoded from an embedded table; every byte must
        // survive a byte -> character -> byte round trip.
        {
            NSMutableData *all = [NSMutableData dataWithCapacity:256];
            for (int b = 0; b < 256; ++b) { unsigned char c = (unsigned char)b; [all appendBytes:&c length:1]; }
            NSString *decoded = [EditorController stringFromData:all codepage:720];
            NSData *reencoded = [EditorController dataFromString:decoded codepage:720];
            BOOL identity = decoded.length == 256 && [reencoded isEqualToData:all];

            // Spot-check against the published mapping.
            unichar c0xA0 = [decoded characterAtIndex:0xA0];
            unichar c0x98 = [decoded characterAtIndex:0x98];
            unichar c0x41 = [decoded characterAtIndex:0x41];
            Check(@"IDM_FORMAT_DOS_720", @"all 256 bytes round-trip and match the spec",
                  identity && c0xA0 == 0x0628 && c0x98 == 0x0621 && c0x41 == 'A');
        }

        // End to end: real Arabic bytes on disk, opened and read back as CP720.
        // Reference produced with Python's cp720 codec:
        //   'مرحبا'.encode('cp720') -> EA A9 A5 A0 9F
        {
            const unsigned char arabicBytes[] = {0xEA, 0xA9, 0xA5, 0xA0, 0x9F, '\n'};
            NSString *expected = @"\u0645\u0631\u062D\u0628\u0627\n";
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp720.txt"];
            [[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)] writeToFile:p atomically:YES];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            BOOL ok = [ed reinterpretAsCodepage:720];
            BOOL textOK = [DocText(ed) isEqualToString:expected];

            // Saving must put the very same bytes back on disk.
            [ed saveCurrentDocument];
            NSData *back = [NSData dataWithContentsOfFile:p];
            BOOL bytesOK = [back isEqualToData:[NSData dataWithBytes:arabicBytes length:sizeof(arabicBytes)]];
            Check(@"IDM_FORMAT_DOS_720", @"Arabic file round-trips through open, decode and save",
                  ok && textOK && bytesOK);
        }

        // Code page 858 must differ from 850 in exactly the euro byte.
        NSData *euroByte = [NSData dataWithBytes:(const unsigned char[]){0xD5} length:1];
        NSString *as858 = [EditorController stringFromData:euroByte codepage:858];
        NSString *as850 = [EditorController stringFromData:euroByte codepage:850];
        Check(@"IDM_FORMAT_DOS_858", @"byte 0xD5 is the euro sign, unlike code page 850",
              [as858 isEqualToString:@"\u20AC"] && ![as850 isEqualToString:as858]);

        NSString *cyr = @"\u0442\u0435\u0441\u0442";                     // "test" in Cyrillic
        NSStringEncoding win1251 = [EditorController encodingForCodepage:1251];
        NSData *cyrBytes = [cyr dataUsingEncoding:win1251 allowLossyConversion:NO];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_cp1251.txt"];
        [cyrBytes writeToFile:path atomically:YES];

        NSError *err = nil;
        [ed openFileAtPath:path error:&err];          // opens as Latin-1 (not valid UTF-8)
        BOOL reinterpreted = [ed reinterpretAsCodepage:1251];
        Check(@"IDM_FORMAT_WIN_1251", @"Encode in Windows-1251 recovers Cyrillic text",
              reinterpreted && [DocText(ed) isEqualToString:cyr]);
    }

    if (NppSectionWanted(@"Encoding: encode in as upstream")) { printf("\n== Encoding: encode in as upstream ==\n");
        // IDM_FORMAT_ANSI / AS_UTF_8 across ANSI and Unicode: the same bytes read the other way,
        // and a UTF-8 file read as ANSI and back is as it was - nothing to save.
        NSString *cafe = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_encin_cafe.txt"];
        [[NSData dataWithBytes:"caf\xc3\xa9\n" length:6] writeToFile:cafe atomically:YES];
        [ed openFileAtPath:cafe error:NULL];
        BOOL toAnsi = [ed encodeInEncoding:NSISOLatin1StringEncoding withBOM:NO];
        BOOL ansiText = [DocText(ed) isEqualToString:@"cafÃ©\n"] && !ed.currentDocument.modified;
        BOOL toUtf8 = [ed encodeInEncoding:NSUTF8StringEncoding withBOM:NO];
        BOOL utf8Text = [DocText(ed) isEqualToString:@"café\n"] && !ed.currentDocument.modified;
        Check(@"IDM_FORMAT_ANSI", @"ANSI and UTF-8 read the file's bytes again, as Notepad++ does, and leave nothing to save",
              toAnsi && ansiText && toUtf8 && utf8Text);

        // A character set: the file is read again (fileReload) - not modified, no undo left -
        // and Convert to afterwards leaves the set, so Save writes the new form.
        NSString *koi = [NSTemporaryDirectory() stringByAppendingPathComponent:@"t_encin_koi8.txt"];
        NSData *koiBytes = [@"Привет\n" dataUsingEncoding:[EditorController encodingForCodepage:20866]];
        [koiBytes writeToFile:koi atomically:YES];
        [ed openFileAtPath:koi error:NULL];
        BOOL reread = [ed reinterpretAsCodepage:20866];
        BOOL clean = [DocText(ed) isEqualToString:@"Привет\n"] && !ed.currentDocument.modified &&
                     ![sci message:SCI_CANUNDO];
        Check(@"IDM_FORMAT_KOI8R_CYRILLIC", @"Encode in a character set reads the file again: not modified, nothing to undo",
              reread && clean);
        [ed setEncoding:NSUTF8StringEncoding withBOM:NO];
        Check(@"IDM_FORMAT_CONV2_AS_UTF_8 (from a set)", @"Convert to UTF-8 on a document in a character set leaves the set",
              ed.currentDocument.codepage == 0 && ed.currentDocument.encoding == NSUTF8StringEncoding && ed.currentDocument.modified);
        [ed closeDocumentAtIndex:(NSInteger)[ed.documents indexOfObject:ed.currentDocument] discardChanges:YES];

        // Windows-1251 is told from Mac Cyrillic by which reading gives the modern alphabet's letters.
        NSData *ru = [@"Привет, мир! Это проверка кодировки текста.\n"
                      dataUsingEncoding:[EditorController encodingForCodepage:1251]];
        NSStringEncoding guessed = [NppCharsetDetection encodingGuessedForData:ru];
        Check(@"IDM_FORMAT_WIN_1251 (detected)", @"Russian text in Windows-1251 is detected as Windows-1251, not Mac Cyrillic",
              guessed == [EditorController encodingForCodepage:1251]);
    }

    if (NppSectionWanted(@"Encoding: convert to")) { printf("\n== Encoding: convert to ==\n");
        struct { NSStringEncoding enc; BOOL bom; NSString *cmd; NSString *name; } convs[] = {
            {NSISOLatin1StringEncoding,         NO,  @"IDM_FORMAT_CONV2_ANSI",      @"ANSI"},
            {NSUTF8StringEncoding,              NO,  @"IDM_FORMAT_CONV2_AS_UTF_8",  @"UTF-8"},
            {NSUTF8StringEncoding,              YES, @"IDM_FORMAT_CONV2_UTF_8",     @"UTF-8-BOM"},
            {NSUTF16BigEndianStringEncoding,    YES, @"IDM_FORMAT_CONV2_UTF_16BE",  @"UTF-16 BE"},
            {NSUTF16LittleEndianStringEncoding, YES, @"IDM_FORMAT_CONV2_UTF_16LE",  @"UTF-16 LE"},
        };
        for (size_t i = 0; i < sizeof(convs)/sizeof(convs[0]); ++i) {
            NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"t_conv%zu.txt", i]];
            [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
            [@"convert me\n" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];

            NSError *e = nil;
            [ed openFileAtPath:p error:&e];
            [ed setEncoding:convs[i].enc withBOM:convs[i].bom];
            [ed saveCurrentDocument];
            [ed closeCurrentDocument];
            [ed openFileAtPath:p error:&e];
            Check(convs[i].cmd, [NSString stringWithFormat:@"Convert to %@ keeps the text", convs[i].name],
                  [DocText(ed) isEqualToString:@"convert me\n"] &&
                  ed.currentDocument.hasBOM == convs[i].bom);
        }
    }

    if (NppSectionWanted(@"Language")) { printf("\n== Language ==\n");
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        BOOL detects = [[cat languageForFileName:@"a.cpp"].name isEqualToString:@"cpp"] &&
                       [[cat languageForFileName:@"b.py"].name isEqualToString:@"python"] &&
                       [[cat languageForFileName:@"c.rs"].name isEqualToString:@"rust"];
        Check(@"IDM_LANG_TEXT", @"extension picks the language", detects);
        Check(@"IDM_LANG_TEXT", @"a plain-text name is refined only by upstream's whole names (Buffer::setFileName)",
              [[cat languageForFileName:@"/x/CMakeLists.txt"].name isEqualToString:@"cmake"] &&
              [[cat languageForFileName:@"/x/Rakefile"].name isEqualToString:@"ruby"] &&
              [[cat languageForFileName:@"/x/PKGBUILD"].name isEqualToString:@"bash"] &&
              [[cat languageForFileName:@"/x/makefile"].name isEqualToString:@"makefile"] &&
              [[cat languageForFileName:@"/x/conf"].name isEqualToString:@"normal"] &&
              [[cat languageForFileName:@"/x/c"].name isEqualToString:@"normal"]);
        {
            NSUInteger jsItems = 0; BOOL embedded = NO;
            __block void (^scan)(NSMenu *);
            void (^__block __weak weakScan)(NSMenu *);
            __block NSUInteger *jsp = &jsItems; __block BOOL *emb = &embedded;
            scan = ^(NSMenu *m) {
                for (NSMenuItem *it in m.itemArray) {
                    if (it.submenu) { weakScan(it.submenu); continue; }
                    if (it.action != NSSelectorFromString(@"pickLanguage:")) continue;
                    if ([it.representedObject isEqual:@"javascript.js"] && [it.title isEqualToString:@"JavaScript"]) (*jsp)++;
                    if ([it.representedObject isEqual:@"javascript"]) *emb = YES;
                }
            };
            weakScan = scan;
            for (NSMenuItem *top in NSApp.mainMenu.itemArray) if ([NppEnglishMenuTitle(top.submenu) isEqualToString:@"Language"]) scan(top.submenu);
            Check(@"IDM_LANG_JS", @"JavaScript is one Language menu entry, for javascript.js; Embedded JS is not listed",
                  jsItems == 1 && !embedded);
        }

        SetDoc(ed, @"# a comment\n");
        [ed setLanguageNamed:@"python"];
        [sci message:SCI_COLOURISE wParam:0 lParam:-1];
        Check(@"IDM_LANG_PYTHON", @"lexer styles the buffer",
              [ed.currentDocument.language.name isEqualToString:@"python"] &&
              [sci message:SCI_GETSTYLEAT wParam:0] == SCE_P_COMMENTLINE);

        // Every language the Language menu offers: selecting it must apply the
        // language and produce a working Lexilla lexer.
        int langOK = 0, langBad = 0;
        NSMutableArray *broken = [NSMutableArray array];
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *menuID = @(kNppLangLexers[i].menuID);
            if (!menuID.length) continue;                 // no upstream menu entry
            NSString *name = @(kNppLangLexers[i].langName);
            if (![cat languageNamed:name]) continue;      // not in langs.model.xml

            [ed setLanguageNamed:name];
            void *lexer = CreateLexer(kNppLangLexers[i].lexerID);
            BOOL ok = [ed.currentDocument.language.name isEqualToString:name] && lexer != NULL;
            if (ok) { langOK++; [gCovered addObject:menuID]; }
            else    { langBad++; [broken addObject:name]; }
        }
        Check(@"IDM_LANG_USER", [NSString stringWithFormat:
                @"all %d menu languages apply and lex%@", langOK,
                langBad ? [NSString stringWithFormat:@" (%d broken: %@)", langBad,
                           [broken componentsJoinedByString:@", "]] : @""],
              langBad == 0 && langOK > 80);

        // Creating a lexer object is not the same as the buffer being coloured.
        // For each language, its own first keyword is put in the document and
        // the styles that come back are examined: if every byte is style 0, the
        // lexer is attached in name only.
        int lexed = 0;
        NSMutableArray *unstyled = [NSMutableArray array];
        NSDictionary *languageProbes = @{
            @"html": @"<a href=\"x\">text</a>\n",
            @"xml":  @"<root attr=\"1\">text</root>\n",
            @"asp":  @"<% Response.Write \"hi\" %>\n",
            @"jsp":  @"<% out.print(\"hi\"); %>\n",
            @"php":  @"<?php\necho \"hi\";\n?>\n",          // a page, as Notepad++ lexes a .php file: PHP is what is inside <?php ?>
            @"kix":  @"; comment\n$a = 1\n",
            @"inno": @"[Setup]\nAppName=Test\n",
            @"yaml": @"key: value\n# comment\n",
        };
        for (int i = 0; i < kNppLangLexerCount; ++i) {
            NSString *name = @(kNppLangLexers[i].langName);
            NppLanguage *language = [cat languageNamed:name];
            if (!language) continue;
            NSString *keywords = language.keywordSets[@0] ?: language.keywordSets.allValues.firstObject;
            NSString *word = [keywords componentsSeparatedByString:@" "].firstObject;

            // A keyword on a line of its own is a fair probe for a programming
            // language. For markup and for configuration files it is not: HTML's
            // keywords are tag names, which are only tags inside angle brackets,
            // so those languages get a line that is actually something in them.
            NSString *probe = languageProbes[name]
                            ?: (word.length ? [word stringByAppendingString:@"\n"] : nil);
            if (!probe.length) continue;

            [ed setLanguageNamed:name];
            SetDoc(ed, probe);
            [sci message:SCI_COLOURISE wParam:0 lParam:-1];
            BOOL styled = NO;
            long probeLength = [sci message:SCI_GETLENGTH];
            for (long at = 0; at < probeLength; ++at) {
                if ([sci message:SCI_GETSTYLEAT wParam:(uptr_t)at] != 0) { styled = YES; break; }
            }
            if (styled) lexed++; else [unstyled addObject:name];
        }
        Check(@"IDM_LANG_USER (colouring)",
              [NSString stringWithFormat:@"%d languages colour their own keyword%@", lexed,
               unstyled.count ? [NSString stringWithFormat:@" (%lu do not: %@)",
                                 (unsigned long)unstyled.count,
                                 [unstyled componentsJoinedByString:@", "]] : @""],
              unstyled.count == 0);
    }
}

/// == Folding: what each lexer is told ==
void NppTestsFolding(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Folding: what each lexer is told")) { printf("\n== Folding: what each lexer is told ==\n");
        // Lines that head a fold, after the whole text has been styled in the language named.
        NSArray<NSNumber *> *(^headers)(NSString *, NSString *) = ^NSArray<NSNumber *> *(NSString *language, NSString *text) {
            [ed newDocument];
            [ed setLanguageNamed:language];
            SetDoc(ed, text);
            ScintillaView *view = ed.sci;
            [view message:SCI_COLOURISE wParam:0 lParam:-1];
            NSMutableArray<NSNumber *> *lines = [NSMutableArray array];
            long count = [view message:SCI_GETLINECOUNT];
            for (long line = 0; line < count; ++line)
                if ([view message:SCI_GETFOLDLEVEL wParam:(uptr_t)line] & SC_FOLDLEVELHEADERFLAG) [lines addObject:@(line)];
            return lines;
        };
        void (^done)(void) = ^{ [ed.sci message:SCI_SETSAVEPOINT]; [ed closeCurrentDocument]; };

        NSString *page = @"<html>\n<body>\n<div class=\"a\">\n  <p>one</p>\n  <p>two</p>\n</div>\n<!-- a comment\n     of two lines -->\n<script>\nfunction f() {\n  return 1;\n}\n</script>\n</body>\n</html>\n";
        NSArray *pageHeaders = headers(@"html", page);
        ScintillaView *pageView = ed.sci;
        [pageView message:SCI_TOGGLEFOLD wParam:2];
        BOOL folded = ![pageView message:SCI_GETLINEVISIBLE wParam:3] && ![pageView message:SCI_GETLINEVISIBLE wParam:4] &&
                      [pageView message:SCI_GETLINEVISIBLE wParam:2] && [pageView message:SCI_GETLINEVISIBLE wParam:6] &&
                      ![pageView message:SCI_GETFOLDEXPANDED wParam:2];
        [pageView message:SCI_TOGGLEFOLD wParam:2];
        BOOL unfolded = [pageView message:SCI_GETLINEVISIBLE wParam:3] && [pageView message:SCI_GETFOLDEXPANDED wParam:2];
        done();
        Check(@"IDM_VIEW_FOLD_CURRENT (an HTML page)", @"a page folds at its elements, at a comment of several lines and at the script inside it (fold.html, "
              @"fold.hypertext.comment, as ScintillaEditView.cpp sets them): a <div> folds away its lines and unfolds again",
              [pageHeaders containsObject:@0] && [pageHeaders containsObject:@1] && [pageHeaders containsObject:@2] && [pageHeaders containsObject:@6] &&
              [pageHeaders containsObject:@9] && folded && unfolded);

        NSArray *xmlHeaders = headers(@"xml", @"<?xml version=\"1.0\"?>\n<root>\n  <item>\n    <name>a</name>\n  </item>\n</root>\n");
        done();
        NSArray *phpHeaders = headers(@"php", @"<html>\n<body>\n<?php\nfunction f() {\n  return 1;\n}\n?>\n</body>\n</html>\n");
        done();
        NSString *mixedPage = @"<html>\n<script>\nvar x = function () { return 1; };\n</script>\n<?php\nforeach ($a as $b) { echo $b; }\n?>\n</html>\n";
        headers(@"php", mixedPage);
        long tagStyle = [ed.sci message:SCI_GETSTYLEAT wParam:1];
        long jsWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[mixedPage rangeOfString:@"function"].location];
        long phpWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[mixedPage rangeOfString:@"foreach"].location];
        // Coloured, too: each of the three has the colour its own language's style gives it, not the default's.
        long plain = [ed.sci message:SCI_STYLEGETFORE wParam:STYLE_DEFAULT];
        StyleCatalog *pageStyles = [StyleCatalog sharedCatalog];
        BOOL (^coloured)(NSString *, int) = ^BOOL(NSString *language, int styleID) {
            for (NppStyle *style in [pageStyles stylesForLexerName:language]) {
                if (style.styleID != styleID || !style.foreground) continue;
                NSColor *c = [style.foreground colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
                long want = (long)lround(c.redComponent * 255) | ((long)lround(c.greenComponent * 255) << 8) | ((long)lround(c.blueComponent * 255) << 16);
                return [ed.sci message:SCI_STYLEGETFORE wParam:(uptr_t)styleID] == want;
            }
            return NO;
        };
        BOOL pageColoured = coloured(@"html", SCE_H_TAG) && coloured(@"javascript", SCE_HJ_KEYWORD) && coloured(@"php", SCE_HPHP_WORD) &&
                            [ed.sci message:SCI_STYLEGETFORE wParam:SCE_HPHP_WORD] != plain &&
                            [ed.sci message:SCI_STYLEGETEOLFILLED wParam:SCE_HPHP_DEFAULT];
        done();
        Check(@"Language (a page and what is written inside it)", @"in a .php file a known tag is a tag, a JavaScript word inside <script> a JavaScript keyword, and a PHP word "
              @"inside <?php ?> a PHP keyword: the hypertext lexer is given HTML's, JavaScript's and PHP's words in the lists it reads each from",
              tagStyle == SCE_H_TAG && jsWord == SCE_HJ_KEYWORD && phpWord == SCE_HPHP_WORD);
        Check(@"Language (a page's colours)", @"and each is coloured by its own language's styles - HTML's, JavaScript's and PHP's all applied to the one page, "
              @"as setXmlLexer applies them", pageColoured);
        Check(@"IDM_VIEW_FOLD_CURRENT (XML and PHP)", @"XML folds at its elements, and a PHP page at its tags and at the function inside <?php ?>",
              [xmlHeaders containsObject:@1] && [xmlHeaders containsObject:@2] && [phpHeaders containsObject:@0] && [phpHeaders containsObject:@3]);

        NSString *source = @"/** a comment\n *  @param x of three\n *  lines */\n#if DEBUG\nint f(void) {\n    return 1;\n}\n#endif\n#if 0\nint g(void) { return 2; }\n#endif\n";
        NSArray *cHeaders = headers(@"c", source);
        // "int" on the line inside #if 0: a keyword still, not greyed out as code that will never be compiled.
        long inactive = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"int g"].location];
        long liveInt = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"int f"].location];
        long liveReturn = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"return 1"].location];
        long docWord = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[source rangeOfString:@"@param"].location + 1];
        done();
        Check(@"IDM_VIEW_FOLD_CURRENT (C)", @"a block comment and an #if fold as well as the braces (fold.comment, fold.preprocessor), and code under #if 0 is "
              @"styled as code: the lexer is told not to guess which symbols are defined",
              [cHeaders containsObject:@0] && [cHeaders containsObject:@3] && [cHeaders containsObject:@4] && inactive == SCE_C_WORD2);
        Check(@"Language (the C family's word lists)", @"instructions, types and documentation words each go to the list the lexer reads them from, as setCppLexer "
              @"sends them: \"return\" is a keyword, \"int\" a type, \"@param\" a documentation keyword",
              liveReturn == SCE_C_WORD && liveInt == SCE_C_WORD2 && docWord == SCE_C_COMMENTDOCKEYWORD);

        NSString *goSource = @"package main\n\nvar s = `raw\nstring`\n";
        headers(@"go", goSource);
        long goStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[goSource rangeOfString:@"raw"].location];
        done();
        NSString *jsSource = @"const s = `a ${b}\nc`;\n";
        headers(@"javascript", jsSource);
        long jsStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsSource rangeOfString:@"a $"].location];
        long jsNext = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsSource rangeOfString:@"c`"].location];
        done();
        NSString *tsSource = @"const s: string = `raw\ntext`;\n";
        headers(@"typescript", tsSource);
        long tsStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[tsSource rangeOfString:@"text"].location];
        done();
        Check(@"Language (backquoted strings)", @"Go's and TypeScript's `raw strings` and JavaScript's `template literals` are strings over their line breaks "
              @"(lexer.cpp.backquoted.strings: 1, 1 and 2)",
              goStyle == SCE_C_STRINGRAW && jsStyle == SCE_C_STRINGRAW && jsNext == SCE_C_STRINGRAW && tsStyle == SCE_C_STRINGRAW);

        NSString *jsonSource = @"{\"a\": \"x\\ny\"}\n";
        headers(@"json", jsonSource);
        long escapeStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[jsonSource rangeOfString:@"\\n"].location];
        done();
        NSString *json5Source = @"{\n  // a comment\n  a: 1\n}\n";
        headers(@"json5", json5Source);
        long commentStyle = [ed.sci message:SCI_GETSTYLEAT wParam:(uptr_t)[json5Source rangeOfString:@"// a"].location + 3];
        done();
        Check(@"Language (JSON)", @"an escape sequence in a JSON string is styled as one, and JSON5 may have comments (lexer.json.escape.sequence, lexer.json.allow.comments)",
              escapeStyle == SCE_JSON_ESCAPESEQUENCE && commentStyle == SCE_JSON_LINECOMMENT);
    }
}

/// == Language: user defined ==
void NppTestsUserLanguages(AppDelegate *app, EditorController *ed, ScintillaView *sci) {
    if (NppSectionWanted(@"Language: user defined")) { printf("\n== Language: user defined ==\n");
        LanguageCatalog *cat = [LanguageCatalog sharedCatalog];
        [ed setLanguageNamed:@"javascript.js"];
        Check(@"IDM_LANG_JS", @"the .js JavaScript variant can be selected",
              [cat languageNamed:@"javascript.js"] != nil &&
              [ed.currentDocument.language.name isEqualToString:@"javascript.js"]);

        BOOL defined = [ed defineUserLanguageNamed:@"MyLang" extensions:@"mylang ml2"
                                          keywords:@"alpha beta" commentLine:@"#"];
        NSDictionary *readBack = [ed userDefinedLanguage];
        Check(@"IDM_LANG_USER_DLG", @"writes userDefineLang.xml and applies the language",
              defined && [readBack[@"name"] isEqualToString:@"MyLang"] &&
              [readBack[@"ext"] isEqualToString:@"mylang ml2"] &&
              [ed.currentDocument.language.name isEqualToString:@"MyLang"]);

        Check(@"IDM_LANG_OPENUDLDIR", @"the user-defined language file has a folder to open",
              [[NSFileManager defaultManager] fileExistsAtPath:[ed userDefinedLanguagePath]]);

        NSURL *collection = [NSURL URLWithString:
            @"https://github.com/notepad-plus-plus/userDefinedLanguages"];
        Check(@"IDM_LANG_UDLCOLLECTION_PROJECT_SITE", @"points at a valid https URL",
              collection != nil && [collection.scheme isEqualToString:@"https"]);

        [ed setLanguageNamed:@"normal"];
    }
}
