// What the files of the built-in suite share: the headers they test, the counters and
// Check, the helpers every area uses, and the area functions NppMacRunTests (Tests.mm)
// calls in the suite's order. Each area file (Tests<Area>.mm) holds the sections of
// its area; the helpers are defined once, in Tests.mm.
#pragma once
#import "CharsetDetection.h"
#import "NumberSetCommands.h"
#import "AppDelegate.h"
#import "AppDelegate+Testing.h"
#import "EditorController.h"
#import "EditCommands.h"
#import "SearchCommands.h"
#import "ViewCommands.h"
#import "EncodingCommands.h"
#import "AdvancedEditCommands.h"
#import "AuxPanels.h"
#import "ToolsCommands.h"
#import "SettingsCommands.h"
#import "SettingsPanels.h"
#import "Toolbar.h"
#import "NppPanel.h"
#import "BackupAndPrint.h"
#import "BehaviourCommands.h"
#import "TypingCommands.h"
#import "TabBarView.h"
#import "JsonCommands.h"
#import "MimeCommands.h"
#import "PluginHost.h"
#import "ConverterCommands.h"
#import "ExportCommands.h"
#import "SpellCheck.h"
#import "MarkdownPanel.h"
#import "ImageCommands.h"
#import "AgentServer.h"
#import "GitCommands.h"
@interface NppStatusPathField : NSTextField
@end
#include <sys/socket.h>
#include <sys/un.h>
#import "CompareCommands.h"
#import "FtpCommands.h"
#import "XmlCommands.h"
#import "RunCommands.h"
#import "FunctionListPanel.h"
#import "FunctionListCatalog.h"
#import "NppRegex.h"
#import "ApiCatalog.h"
#import "FindCommands.h"
#import "LanguageCatalog.h"
#import "LanguageDetection.h"
#import "UserLanguages.h"
#import "UserLanguageDialog.h"
#import "ShortcutMapper.h"
#import "ProjectPanel.h"
#import "LanguageModel.h"
#import "StyleCatalog.h"
#import "StyleConfigurator.h"
#import "DocumentListPanel.h"
#import "WorkspacePanel.h"
#import "EditorLook.h"
#import "Localization.h"
#import "DockingManager.h"
#import "TagMatch.h"
#import "InfoWindows.h"
#import "UpdateChecker.h"
#import "ScriptCommands.h"
#import "ContextMenuFile.h"
#import "CryptoTools.h"
#import "ToolsWindows.h"
#import "ScintillaView.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"
#include "LangMap.h"

extern int gPass, gFail;
/// Every command a Check has named; the coverage meta-test compares it with implemented.txt.
extern NSMutableSet *gCovered;

/// Lets AppKit deliver what has been posted and the run loop turn over, which
/// is what work put off to the next turn needs before it has run.
void NppSettle(NSTimeInterval seconds);
/// The same, but only until what was expected has happened: waiting a fixed
/// time instead makes the test turn on how busy the machine is.
void NppSettleUntil(BOOL (^done)(void), NSTimeInterval limit);
void Check(NSString *command, NSString *name, BOOL ok);
/// NPPMAC_TEST_ONLY=Git,Agent runs only the sections whose heading contains one of the words.
BOOL NppSectionWanted(NSString *heading);
NSString *DocText(EditorController *ed);
void SetDoc(EditorController *ed, NSString *text);
NSString *TempFile(NSString *name, NSString *contents);

/// The alert hook of Localization.mm, named so the suite can call it.
@protocol NppAlertLocalizing
- (void)npp_localize;
@end

/// Reads back one attribute value, for the newline-preservation test.
@interface NppAttributeReader : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *value;
@end

// The areas, in the order NppMacRunTests calls them. An area whose sections are not
// together in that order has one function per run of them.
void NppTestsFiles(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsFiles.mm
void NppTestsEdit(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsEditing.mm
void NppTestsFindDialog(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSearch.mm
void NppTestsEditorSettings(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSettings.mm
void NppTestsSorting(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsEditing.mm
void NppTestsSearchModes(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSearch.mm
void NppTestsEditMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsEditing.mm
void NppTestsSearchMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSearch.mm
void NppTestsViewMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsView.mm
void NppTestsEncodingAndLanguage(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsLanguages.mm
void NppTestsToolsMenu(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsTools.mm
void NppTestsFolding(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsLanguages.mm
void NppTestsHttpMacroRunHelp(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsTools.mm
void NppTestsPreferences(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSettings.mm
void NppTestsFileMonitoring(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsFiles.mm
void NppTestsDocking(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsView.mm
void NppTestsSessionDepth(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsFiles.mm
void NppTestsLocalizationAndDefaults(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsSettings.mm
void NppTestsTabBar(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsView.mm
void NppTestsAccessibility(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsView.mm
void NppTestsUserLanguages(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsLanguages.mm
void NppTestsPluginCommands(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsPlugins.mm
void NppTestsFilesAsUpstream(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsFiles.mm
void NppTestsFontAndTabLayout(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsView.mm
void NppTestsSelectedNumbers(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsEditing.mm
void NppTestsMarkdown(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsPlugins.mm
void NppTestsMacExtras(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsTools.mm
void NppTestsPluginHost(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsPlugins.mm
void NppTestsGit(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsGit.mm
void NppTestsAgent(AppDelegate *app, EditorController *ed, ScintillaView *sci);   // TestsAgent.mm
