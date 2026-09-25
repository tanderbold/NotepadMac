// Built-in test suite: one or more cases per implemented Notepad++ command.
//
// This file is the driver: the shared helpers, the counters, the coverage
// meta-test and the summary. The sections live by area in Tests<Area>.mm
// (TestsFiles, TestsEditing, TestsSearch, ...), declared in TestSupport.h and
// called below in the suite's order.
//
// A meta-test cross-checks the suite against macos/implemented.txt, so a
// command cannot be declared implemented without a test covering it.
#import "Tests.h"
#import "TestSupport.h"

int gPass = 0, gFail = 0;
NSMutableSet *gCovered = nil;

/// Lets AppKit deliver what has been posted and the run loop turn over, which
/// is what work put off to the next turn needs before it has run.
void NppSettle(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *queued = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                                inMode:NSDefaultRunLoopMode dequeue:YES];
        if (queued) [NSApp sendEvent:queued];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

/// The same, but only until what was expected has happened: waiting a fixed
/// time instead makes the test turn on how busy the machine is.
void NppSettleUntil(BOOL (^done)(void), NSTimeInterval limit) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:limit];
    while ([until timeIntervalSinceNow] > 0 && !done()) {
        NSEvent *queued = [NSApp nextEventMatchingMask:NSEventMaskAny
                                             untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
                                                inMode:NSDefaultRunLoopMode dequeue:YES];
        if (queued) [NSApp sendEvent:queued];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

void Check(NSString *command, NSString *name, BOOL ok) {
    [gCovered addObject:command];
    if (ok) { gPass++; printf("  ok   %-28s %s\n", command.UTF8String, name.UTF8String); }
    else    { gFail++; printf("  FAIL %-28s %s\n", command.UTF8String, name.UTF8String); }
}

/// NPPMAC_TEST_ONLY=Git,Agent runs only the sections whose heading contains one of
/// the words (case aside); empty runs everything. For working on one area - the
/// whole suite is for before a commit.
BOOL NppSectionWanted(NSString *heading) {
    const char *only = getenv("NPPMAC_TEST_ONLY");
    if (!only || !*only) return YES;
    for (NSString *word in [@(only) componentsSeparatedByString:@","]) {
        NSString *w = [word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (w.length && [heading rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

/// The interface language the user had, put back when the process ends: the sections that
/// walk every language would otherwise leave theirs changed if a run stopped in the middle.
static NSString *gLanguageToRestore;
static void NppRestoreUserLanguage(void) {
    if (!gLanguageToRestore.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:gLanguageToRestore forKey:@"NppMac.localizationFile"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

NSString *DocText(EditorController *ed) { return [ed.sci string] ?: @""; }

void SetDoc(EditorController *ed, NSString *text) {
    [ed.sci setString:text];
    [ed.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
}

NSString *TempFile(NSString *name, NSString *contents) {
    NSString *p = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [contents writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return p;
}

@implementation NppAttributeReader
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element
  namespaceURI:(NSString *)ns qualifiedName:(NSString *)qn
    attributes:(NSDictionary<NSString *, NSString *> *)attrs {
    if (!self.value) self.value = attrs[@"b"];
}
@end

int NppMacRunTests(AppDelegate *app) {
    setvbuf(stdout, NULL, _IOLBF, 0);   // a run that stops then says where
    gPass = gFail = 0;
    gCovered = [NSMutableSet set];
    EditorController *ed = [app editor];
    ScintillaView *sci = ed.sci;
    // The suite reads the interface in English and switches languages where it tests them;
    // the user's own language is put back at the end (the CI runner has none set).
    NSString *userLanguage = [NppPreferences shared].localizationFile;
    if (userLanguage.length) {
        [NppPreferences shared].localizationFile = @"";
        [app applyLocalization];
        // The sections that walk the languages leave the setting behind if a run ends early;
        // this puts it back even then, so a suite run never changes the user's language.
        gLanguageToRestore = userLanguage;
        atexit(NppRestoreUserLanguage);
    }

    // The areas, in the suite's order; each runs the sections of its own that are wanted.
    NppTestsFiles(app, ed, sci);
    NppTestsEdit(app, ed, sci);
    NppTestsFindDialog(app, ed, sci);
    NppTestsEditorSettings(app, ed, sci);
    NppTestsSorting(app, ed, sci);
    NppTestsSearchModes(app, ed, sci);
    NppTestsEditMenu(app, ed, sci);
    NppTestsSearchMenu(app, ed, sci);
    NppTestsViewMenu(app, ed, sci);
    NppTestsEncodingAndLanguage(app, ed, sci);
    NppTestsToolsMenu(app, ed, sci);
    NppTestsFolding(app, ed, sci);
    NppTestsHttpMacroRunHelp(app, ed, sci);
    NppTestsPreferences(app, ed, sci);
    NppTestsFileMonitoring(app, ed, sci);
    NppTestsDocking(app, ed, sci);
    NppTestsSessionDepth(app, ed, sci);
    NppTestsLocalizationAndDefaults(app, ed, sci);
    NppTestsTabBar(app, ed, sci);
    NppTestsUserLanguages(app, ed, sci);
    NppTestsPluginCommands(app, ed, sci);
    NppTestsFilesAsUpstream(app, ed, sci);
    NppTestsFontAndTabLayout(app, ed, sci);
    NppTestsSelectedNumbers(app, ed, sci);
    NppTestsMarkdown(app, ed, sci);
    NppTestsMacExtras(app, ed, sci);
    NppTestsPluginHost(app, ed, sci);
    NppTestsGit(app, ed, sci);
    NppTestsAgent(app, ed, sci);

    // ---- meta-test: nothing may be declared implemented without a test
    // The coverage meta-test only means something over the whole suite.
    if (!getenv("NPPMAC_TEST_ONLY") || !*getenv("NPPMAC_TEST_ONLY")) { printf("\n== Coverage ==\n");
        NSString *listPath = [[NSBundle mainBundle] pathForResource:@"implemented" ofType:@"txt"];
        NSString *list = listPath ? [NSString stringWithContentsOfFile:listPath
                                                             encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSMutableArray *missing = [NSMutableArray array];
        NSUInteger declared = 0;
        for (NSString *raw in [(list ?: @"") componentsSeparatedByString:@"\n"]) {
            NSString *line = [[raw componentsSeparatedByString:@"#"].firstObject
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!line.length) continue;
            declared++;
            if (![gCovered containsObject:line]) [missing addObject:line];
        }
        if (!list) {
            gFail++;
            printf("  FAIL %-28s implemented.txt missing from the bundle\n", "COVERAGE");
        } else if (missing.count) {
            gFail++;
            printf("  FAIL %-28s %lu declared but untested: %s\n", "COVERAGE",
                   (unsigned long)missing.count,
                   [[missing componentsJoinedByString:@", "] UTF8String]);
        } else {
            gPass++;
            printf("  ok   %-28s all %lu declared commands have tests\n", "COVERAGE",
                   (unsigned long)declared);
        }
    }

    if (userLanguage.length) {
        [NppPreferences shared].localizationFile = userLanguage;
        [app applyLocalization];
        [[NSUserDefaults standardUserDefaults] synchronize];   // the process ends right after; the write must land
    }
    printf("\n%d passed, %d failed\n", gPass, gFail);
    return gFail;
}
