#import "SettingsCommands.h"
#import "ViewCommands.h"
#import "AgentServer.h"
#import "GitCommands.h"
#import "UserLanguages.h"
#import "LanguageCatalog.h"
#import "StyleCatalog.h"
#import "ScintillaView.h"

static NSString *const kDefaultsPrefix = @"NppMac.";

static NSString *Key(NSString *name) { return [kDefaultsPrefix stringByAppendingString:name]; }

@implementation NppPreferences

+ (instancetype)shared {
    static NppPreferences *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[NppPreferences alloc] init]; });
    return shared;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    // Defaults chosen to match what the editor already did before it had settings.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        Key(@"gitMarginMarks"):  @YES,
        Key(@"fontName"):        @"Menlo",
        Key(@"fontSize"):        @13,
        Key(@"tabWidth"):        @4,
        Key(@"useSpaces"):       @NO,
        Key(@"wordWrap"):        @NO,
        Key(@"showWhitespace"):  @NO,
        Key(@"showIndentGuides"):@YES,
        Key(@"showEOL"): @NO, Key(@"showWrapSymbol"): @NO,
        Key(@"restoreSession"):  @YES,   // NppGUI::_rememberLastSession = true
        Key(@"detectLanguageFromContent"): @YES,
        Key(@"defaultEOL"):      @(SC_EOL_LF),
        Key(@"defaultEncoding"): @"UTF-8",
        Key(@"appearanceMode"):  @0,
        Key(@"showToolbar"):     @YES,
        Key(@"toolbarDisplayMode"): @0,
        Key(@"toolbarIconSize"): @1,
        Key(@"backupMode"):      @0,
        Key(@"backupDirectory"): @"",
        Key(@"autosaveEnabled"): @NO,
        Key(@"fileAutoDetection"): @YES,
        Key(@"autoDetectCharacterEncoding"): @YES,
        Key(@"fileAutoDetectionSilent"): @NO,
        Key(@"fileAutoDetectionScrollToEnd"): @NO,
        Key(@"autosaveInterval"): @60,
        Key(@"printLineNumbers"): @NO,
        Key(@"printColourMode"): @2,
        Key(@"printMarginLeft"): @36.0,
        Key(@"printMarginRight"): @36.0,
        Key(@"printMarginTop"): @36.0,
        Key(@"printMarginBottom"): @36.0,
        Key(@"printHeaderLeft"): @"$(FULL_CURRENT_PATH)",
        Key(@"printHeaderMiddle"): @"",
        Key(@"printHeaderRight"): @"$(CURRENT_DATE)",
        Key(@"printFooterLeft"): @"",
        Key(@"printFooterMiddle"): @"Page $(CURRENT_PRINTING_PAGE) of $(TOTAL_PRINTING_PAGE)",
        Key(@"printFooterRight"): @"",
        Key(@"printHeaderFontName"): @"Helvetica",
        Key(@"printHeaderFontSize"): @9,
        Key(@"printHeaderBold"): @NO,
        Key(@"printHeaderItalic"): @NO,
        Key(@"largeFileRestrictionEnabled"): @YES,
        Key(@"largeFileThresholdMB"): @200,
        Key(@"largeFileDeactivateWordWrap"): @YES,
        Key(@"largeFileAllowAutoCompletion"): @NO,
        Key(@"largeFileAllowSmartHighlighting"): @NO,
        Key(@"largeFileAllowBraceMatch"): @NO,
        Key(@"largeFileAllowClickableLinks"): @NO,
        Key(@"suppressHugeFileWarning"): @NO,
        Key(@"linksEnabled"): @YES,
        Key(@"linksNoUnderline"): @NO,
        Key(@"linksFullBox"): @NO,
        Key(@"linkCustomSchemes"): @"",
        Key(@"braceMatchEnabled"): @YES,
        Key(@"smartHighlightEnabled"): @YES,
        Key(@"customWordCharsEnabled"): @NO,
        Key(@"customWordChars"): @"",
        Key(@"delimiterOpen"): @"(",
        Key(@"delimiterClose"): @")",
        Key(@"delimiterMultiline"): @NO,
        Key(@"multiInstanceMode"): @0,
        Key(@"reverseDateTimeOrder"): @NO,
        Key(@"rememberPanelState"): @NO,
        Key(@"panelState"): @{},
        Key(@"settingsDirectory"): @"",
        Key(@"compareIgnoreCase"): @NO,
        Key(@"compareIgnoreSpaces"): @NO,
        Key(@"compareIgnoreEmptyLines"): @NO,
        Key(@"compareDetectMoves"): @YES,
        Key(@"compareCharDiffs"): @YES,
        Key(@"jsonIndent"): @4,
        Key(@"ftpProfiles"): @[],
        Key(@"savedRunCommands"): @[],
        Key(@"edgeMode"): @0,
        Key(@"edgeColumns"): @"80",
        Key(@"caretWidth"): @1,
        Key(@"caretBlinkRate"): @530,          // the Windows default
        Key(@"scrollBeyondLastLine"): @YES,
        Key(@"virtualSpace"): @NO,
        // These defaults are Notepad++'s own, from ScintillaViewParams.
        Key(@"autoIndentMode"): @2,            // Notepad++ defaults to advanced
        Key(@"markAllCaseSensitive"): @NO,
        Key(@"markAllWordOnly"): @YES,
        Key(@"lineCopyCutWithoutSelection"): @YES,
        Key(@"currentLineHighlightMode"): @1,
        Key(@"currentLineFrameWidth"): @1,
        Key(@"foldMarginShow"): @YES,
        Key(@"bookmarkMarginShow"): @YES,
        Key(@"lineWrapMethod"): @1,            // aligned
        Key(@"paddingLeft"): @0,
        Key(@"paddingRight"): @0,
        Key(@"rightClickKeepsSelection"): @NO,
        Key(@"selectedTextDragDrop"): @YES,
        Key(@"autoCompleteOnInput"): @YES,
        Key(@"autoCompleteSource"): @2,
        Key(@"autoCompleteThreshold"): @1,
        Key(@"autoCompleteBriefList"): @NO,
        Key(@"autoCompleteIgnoreNumbers"): @YES,
        Key(@"autoCompleteUseTab"): @YES,
        Key(@"functionHintOnInput"): @YES,
        Key(@"autoInsertParenthesis"): @NO,
        Key(@"autoInsertBracket"): @NO,
        Key(@"autoInsertBrace"): @NO,
        Key(@"autoInsertSingleQuote"): @NO,
        Key(@"autoInsertDoubleQuote"): @NO,
        Key(@"autoInsertCloseTag"): @NO,
        Key(@"defaultLanguage"): @"",
        Key(@"openNewDocumentAtStartup"): @NO,   // NewDocDefaultSettings::_addNewDocumentOnStartup
        Key(@"untitledFromFirstLine"): @NO,
        Key(@"hideTabBar"): @NO,
        Key(@"tabDoubleClickCloses"): @NO,
        Key(@"exitOnClosingLastTab"): @NO,
        Key(@"tabShowCloseButton"): @NO,
        Key(@"tabPinFeatureEnabled"): @YES,
        Key(@"tabCloseButtonOnInactive"): @NO,
        Key(@"tabBarLocked"): @NO,
        Key(@"tabBarVertical"): @NO,
        Key(@"tabBarMultiLine"): @NO,
        Key(@"recentFiles"): @[],
        Key(@"recentFilesMax"): @10,
        Key(@"recentFilesShowFullPath"): @NO,
        Key(@"recentFilesMaxLength"): @60,
        Key(@"defaultDirectoryMode"): @0,
        Key(@"lastUsedDirectory"): @"",
        Key(@"fixedDirectory"): @"",
        Key(@"findFillWithSelection"): @YES,
        Key(@"findSelectWordUnderCaret"): @YES,
        Key(@"replaceStaysOnOccurrence"): @NO,
        Key(@"confirmReplaceAll"): @NO,    // off: Replace All does not ask, as upstream's does not
        Key(@"smartHighlightMatchCase"): @NO,
        Key(@"smartHighlightWholeWord"): @YES,
        Key(@"lightThemeName"):  @"Default",
        Key(@"darkThemeName"):   @"DarkModeDefault",
        Key(@"styleOverrides"):  @{},
        Key(@"globalOverride"):  @{},
        Key(@"userMatchedPairs"): @[],
        Key(@"findHistory"): @[], Key(@"replaceHistory"): @[],
        Key(@"filterHistory"): @[], Key(@"directoryHistory"): @[],
        Key(@"findTransparencyMode"): @1, Key(@"findTransparencyLevel"): @150,
        Key(@"searchResultsPurge"): @NO,
        Key(@"docListExtColumn"): @YES, Key(@"docListGroupByView"): @YES, Key(@"docListPathColumn"): @NO,
        Key(@"docPeekOnTab"): @NO, Key(@"docPeekOnMap"): @NO,
        Key(@"docSwitcherEnabled"): @YES, Key(@"docSwitcherMRU"): @YES,
        Key(@"titleBarFileNameOnly"): @NO, Key(@"confirmSaveAll"): @YES, Key(@"muteSounds"): @NO,
        Key(@"sessionFileExtension"): @"", Key(@"workspaceFileExtension"): @"",
        Key(@"workspaceSymlinks"): @NO, Key(@"searchEngine"): @1, Key(@"searchEngineCustom"): @"",
        Key(@"languageMenuHidden"): @[], Key(@"languageMenuCompact"): @YES, Key(@"sqlBackslashEscape"): @YES,
        Key(@"languageIndent"): @{}, Key(@"backspaceUnindents"): @NO, Key(@"statusBarHidden"): @NO,
        Key(@"smoothFont"): @NO, Key(@"selectedTextCustomForeground"): @NO, Key(@"multiEditing"): @YES,
        Key(@"preventC0Typing"): @YES, Key(@"foldCommandsToggle"): @NO, Key(@"eolPlainText"): @NO,
        Key(@"eolCustomColour"): @NO, Key(@"npcShow"): @NO, Key(@"ccUniEolShow"): @YES, Key(@"npcCodepoint"): @NO,
        Key(@"npcCustomColour"): @NO, Key(@"npcIncludeCcUniEol"): @NO, Key(@"foldMarginStyle"): @3,
        Key(@"lineNumberShow"): @YES, Key(@"lineNumberDynamicWidth"): @YES,
        Key(@"changeHistoryMargin"): @YES, Key(@"changeHistoryText"): @NO,
        Key(@"highlightMatchingTags"): @YES, Key(@"highlightTagAttributes"): @YES, Key(@"highlightNonHtmlZone"): @NO,
        Key(@"smartHighlightUseFindSettings"): @NO, Key(@"smartHighlightOtherView"): @NO,
        Key(@"customDateFormat"): @"yyyy-MM-dd HH:mm:ss", Key(@"printFormFeedPageBreak"): @NO,
        Key(@"findDialogStaysOpen"): @NO, Key(@"confirmReplaceAllOpenDocs"): @YES, Key(@"inSelectionThreshold"): @1024,
        Key(@"fillFindWhatThreshold"): @1024, Key(@"fillDirectoryFromActiveDocument"): @NO,
        Key(@"findMatchCase"): @NO, Key(@"findWholeWord"): @NO, Key(@"findWrap"): @YES, Key(@"findMode"): @0,
        Key(@"toolbarFilledIcons"): @NO, Key(@"toolbarIconColour"): @0, Key(@"toolbarIconCustomColour"): @"",
        Key(@"toolbarColorizeComplete"): @NO,
        Key(@"tabDrawActiveBar"): @YES, Key(@"tabColourInactive"): @YES, Key(@"tabReduced"): @YES, Key(@"tabMaxLabelLength"): @0,
        Key(@"panelStateKeep"): @{}, Key(@"distractionFreeDivPart"): @4, Key(@"openAnsiAsUtf8"): @YES, Key(@"dockLayout"): @{}, Key(@"localizationFile"): @"",
        Key(@"autoUpdateMode"): @1, Key(@"updateIntervalDays"): @15, Key(@"nextUpdateDate"): @"",
        Key(@"updateRepository"): @"tanderbold/NotepadMac",
        Key(@"spellCheckLanguage"): @"",
        Key(@"shortcutOverrides"): @{},
        Key(@"contextMenuCommands"): @[@"Cut", @"Copy", @"Paste", @"Select All",
                                       @"Toggle Line Comment", @"Go to Matching Brace"],
    }];
    return self;
}

#define NPP_PREF_OBJ(getter, setter, type, key)                                   \
- (type *)getter { return [[NSUserDefaults standardUserDefaults] objectForKey:Key(key)]; } \
- (void)setter:(type *)value {                                                    \
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:Key(key)];       \
}

#define NPP_PREF_INT(getter, setter, key)                                         \
- (NSInteger)getter { return [[NSUserDefaults standardUserDefaults] integerForKey:Key(key)]; } \
- (void)setter:(NSInteger)value {                                                 \
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:Key(key)];      \
}

#define NPP_PREF_BOOL(getter, setter, key)                                        \
- (BOOL)getter { return [[NSUserDefaults standardUserDefaults] boolForKey:Key(key)]; }  \
- (void)setter:(BOOL)value {                                                      \
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:Key(key)];         \
}

NPP_PREF_OBJ(fontName, setFontName, NSString, @"fontName")

/// A value set for this key by the user - in the application's preferences or
/// on the command line - rather than the registered default.
static id NppChosenValue(NSString *name) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id v = [d volatileDomainForName:NSArgumentDomain][Key(name)];
    NSString *domain = NSBundle.mainBundle.bundleIdentifier;
    return v ?: (domain ? [d persistentDomainForName:domain][Key(name)] : nil);
}
- (nullable NSString *)chosenFontName {
    id v = NppChosenValue(@"fontName");
    return [v isKindOfClass:[NSString class]] && [v length] ? v : nil;
}
- (NSInteger)chosenFontSize {
    id v = NppChosenValue(@"fontSize");
    return [v respondsToSelector:@selector(integerValue)] ? MAX(0, [v integerValue]) : 0;
}
NPP_PREF_OBJ(defaultEncoding, setDefaultEncoding, NSString, @"defaultEncoding")
NPP_PREF_OBJ(lightThemeName, setLightThemeName, NSString, @"lightThemeName")
NPP_PREF_OBJ(darkThemeName, setDarkThemeName, NSString, @"darkThemeName")
NPP_PREF_OBJ(backupDirectory, setBackupDirectory, NSString, @"backupDirectory")
NPP_PREF_OBJ(printHeaderLeft, setPrintHeaderLeft, NSString, @"printHeaderLeft")
NPP_PREF_OBJ(printHeaderMiddle, setPrintHeaderMiddle, NSString, @"printHeaderMiddle")
NPP_PREF_OBJ(printHeaderRight, setPrintHeaderRight, NSString, @"printHeaderRight")
NPP_PREF_OBJ(printFooterLeft, setPrintFooterLeft, NSString, @"printFooterLeft")
NPP_PREF_OBJ(printFooterMiddle, setPrintFooterMiddle, NSString, @"printFooterMiddle")
NPP_PREF_OBJ(printFooterRight, setPrintFooterRight, NSString, @"printFooterRight")
NPP_PREF_OBJ(printHeaderFontName, setPrintHeaderFontName, NSString, @"printHeaderFontName")
NPP_PREF_OBJ(linkCustomSchemes, setLinkCustomSchemes, NSString, @"linkCustomSchemes")
NPP_PREF_OBJ(customWordChars, setCustomWordChars, NSString, @"customWordChars")
NPP_PREF_OBJ(delimiterOpen, setDelimiterOpen, NSString, @"delimiterOpen")
NPP_PREF_OBJ(delimiterClose, setDelimiterClose, NSString, @"delimiterClose")
NPP_PREF_OBJ(settingsDirectory, setSettingsDirectory, NSString, @"settingsDirectory")
NPP_PREF_OBJ(panelState, setPanelState, NSDictionary, @"panelState")
NPP_PREF_OBJ(defaultLanguage, setDefaultLanguage, NSString, @"defaultLanguage")
NPP_PREF_OBJ(recentFiles, setRecentFiles, NSArray, @"recentFiles")
NPP_PREF_OBJ(lastUsedDirectory, setLastUsedDirectory, NSString, @"lastUsedDirectory")
NPP_PREF_OBJ(fixedDirectory, setFixedDirectory, NSString, @"fixedDirectory")
NPP_PREF_OBJ(ftpProfiles, setFtpProfiles, NSArray, @"ftpProfiles")
NPP_PREF_OBJ(savedRunCommands, setSavedRunCommands, NSArray, @"savedRunCommands")
NPP_PREF_INT(edgeMode, setEdgeMode, @"edgeMode")
NPP_PREF_OBJ(edgeColumns, setEdgeColumns, NSString, @"edgeColumns")
NPP_PREF_INT(caretWidth, setCaretWidth, @"caretWidth")
NPP_PREF_INT(caretBlinkRate, setCaretBlinkRate, @"caretBlinkRate")
NPP_PREF_BOOL(scrollBeyondLastLine, setScrollBeyondLastLine, @"scrollBeyondLastLine")
NPP_PREF_BOOL(virtualSpace, setVirtualSpace, @"virtualSpace")
NPP_PREF_INT(autoIndentMode, setAutoIndentMode, @"autoIndentMode")
NPP_PREF_BOOL(markAllCaseSensitive, setMarkAllCaseSensitive, @"markAllCaseSensitive")
NPP_PREF_BOOL(markAllWordOnly, setMarkAllWordOnly, @"markAllWordOnly")
NPP_PREF_BOOL(lineCopyCutWithoutSelection, setLineCopyCutWithoutSelection, @"lineCopyCutWithoutSelection")
NPP_PREF_INT(currentLineHighlightMode, setCurrentLineHighlightMode, @"currentLineHighlightMode")
NPP_PREF_INT(currentLineFrameWidth, setCurrentLineFrameWidth, @"currentLineFrameWidth")
NPP_PREF_BOOL(foldMarginShow, setFoldMarginShow, @"foldMarginShow")
NPP_PREF_BOOL(bookmarkMarginShow, setBookmarkMarginShow, @"bookmarkMarginShow")
NPP_PREF_INT(lineWrapMethod, setLineWrapMethod, @"lineWrapMethod")
NPP_PREF_INT(paddingLeft, setPaddingLeft, @"paddingLeft")
NPP_PREF_INT(paddingRight, setPaddingRight, @"paddingRight")
NPP_PREF_BOOL(rightClickKeepsSelection, setRightClickKeepsSelection, @"rightClickKeepsSelection")
NPP_PREF_BOOL(selectedTextDragDrop, setSelectedTextDragDrop, @"selectedTextDragDrop")
NPP_PREF_OBJ(styleOverrides, setStyleOverrides, NSDictionary, @"styleOverrides")
NPP_PREF_OBJ(globalOverride, setGlobalOverride, NSDictionary, @"globalOverride")
NPP_PREF_OBJ(userMatchedPairs, setUserMatchedPairs, NSArray, @"userMatchedPairs")
NPP_PREF_OBJ(findHistory, setFindHistory, NSArray, @"findHistory")
NPP_PREF_OBJ(replaceHistory, setReplaceHistory, NSArray, @"replaceHistory")
NPP_PREF_OBJ(filterHistory, setFilterHistory, NSArray, @"filterHistory")
NPP_PREF_OBJ(directoryHistory, setDirectoryHistory, NSArray, @"directoryHistory")
NPP_PREF_INT(findTransparencyMode, setFindTransparencyMode, @"findTransparencyMode")
NPP_PREF_INT(findTransparencyLevel, setFindTransparencyLevel, @"findTransparencyLevel")
NPP_PREF_BOOL(searchResultsPurge, setSearchResultsPurge, @"searchResultsPurge")
NPP_PREF_BOOL(docListExtColumn, setDocListExtColumn, @"docListExtColumn")
NPP_PREF_BOOL(docListGroupByView, setDocListGroupByView, @"docListGroupByView")
NPP_PREF_BOOL(docListPathColumn, setDocListPathColumn, @"docListPathColumn")
NPP_PREF_BOOL(docPeekOnTab, setDocPeekOnTab, @"docPeekOnTab")
NPP_PREF_BOOL(docPeekOnMap, setDocPeekOnMap, @"docPeekOnMap")
NPP_PREF_BOOL(docSwitcherEnabled, setDocSwitcherEnabled, @"docSwitcherEnabled")
NPP_PREF_BOOL(docSwitcherMRU, setDocSwitcherMRU, @"docSwitcherMRU")
NPP_PREF_BOOL(titleBarFileNameOnly, setTitleBarFileNameOnly, @"titleBarFileNameOnly")
NPP_PREF_BOOL(confirmSaveAll, setConfirmSaveAll, @"confirmSaveAll")
NPP_PREF_BOOL(muteSounds, setMuteSounds, @"muteSounds")
NPP_PREF_OBJ(sessionFileExtension, setSessionFileExtension, NSString, @"sessionFileExtension")
NPP_PREF_OBJ(workspaceFileExtension, setWorkspaceFileExtension, NSString, @"workspaceFileExtension")
NPP_PREF_BOOL(workspaceSymlinks, setWorkspaceSymlinks, @"workspaceSymlinks")
NPP_PREF_BOOL(agentServer, setAgentServer, @"agentServer")
NPP_PREF_BOOL(gitMarginMarks, setGitMarginMarks, @"gitMarginMarks")
NPP_PREF_INT(searchEngine, setSearchEngine, @"searchEngine")
NPP_PREF_OBJ(searchEngineCustom, setSearchEngineCustom, NSString, @"searchEngineCustom")
NPP_PREF_OBJ(languageMenuHidden, setLanguageMenuHidden, NSArray, @"languageMenuHidden")
NPP_PREF_BOOL(languageMenuCompact, setLanguageMenuCompact, @"languageMenuCompact")
NPP_PREF_BOOL(sqlBackslashEscape, setSqlBackslashEscape, @"sqlBackslashEscape")
NPP_PREF_BOOL(converterInsertSpace, setConverterInsertSpace, @"converterInsertSpace")
NPP_PREF_BOOL(converterUppercase, setConverterUppercase, @"converterUppercase")
NPP_PREF_INT(converterHexPerLine, setConverterHexPerLine, @"converterHexPerLine")
NPP_PREF_BOOL(spellCheckEnabled, setSpellCheckEnabled, @"spellCheckEnabled")
NPP_PREF_OBJ(spellCheckLanguage, setSpellCheckLanguage, NSString, @"spellCheckLanguage")
NPP_PREF_OBJ(languageIndent, setLanguageIndent, NSDictionary, @"languageIndent")
NPP_PREF_BOOL(backspaceUnindents, setBackspaceUnindents, @"backspaceUnindents")
NPP_PREF_BOOL(statusBarHidden, setStatusBarHidden, @"statusBarHidden")
NPP_PREF_BOOL(smoothFont, setSmoothFont, @"smoothFont")
NPP_PREF_BOOL(selectedTextCustomForeground, setSelectedTextCustomForeground, @"selectedTextCustomForeground")
NPP_PREF_BOOL(multiEditing, setMultiEditing, @"multiEditing")
NPP_PREF_BOOL(preventC0Typing, setPreventC0Typing, @"preventC0Typing")
NPP_PREF_BOOL(foldCommandsToggle, setFoldCommandsToggle, @"foldCommandsToggle")
NPP_PREF_BOOL(eolPlainText, setEolPlainText, @"eolPlainText")
NPP_PREF_BOOL(eolCustomColour, setEolCustomColour, @"eolCustomColour")
NPP_PREF_BOOL(npcShow, setNpcShow, @"npcShow")
NPP_PREF_BOOL(ccUniEolShow, setCcUniEolShow, @"ccUniEolShow")
NPP_PREF_BOOL(npcCodepoint, setNpcCodepoint, @"npcCodepoint")
NPP_PREF_BOOL(npcCustomColour, setNpcCustomColour, @"npcCustomColour")
NPP_PREF_BOOL(npcIncludeCcUniEol, setNpcIncludeCcUniEol, @"npcIncludeCcUniEol")
NPP_PREF_BOOL(lineNumberShow, setLineNumberShow, @"lineNumberShow")
NPP_PREF_BOOL(lineNumberDynamicWidth, setLineNumberDynamicWidth, @"lineNumberDynamicWidth")
NPP_PREF_BOOL(changeHistoryMargin, setChangeHistoryMargin, @"changeHistoryMargin")
NPP_PREF_BOOL(changeHistoryText, setChangeHistoryText, @"changeHistoryText")
NPP_PREF_BOOL(highlightMatchingTags, setHighlightMatchingTags, @"highlightMatchingTags")
NPP_PREF_BOOL(highlightTagAttributes, setHighlightTagAttributes, @"highlightTagAttributes")
NPP_PREF_BOOL(highlightNonHtmlZone, setHighlightNonHtmlZone, @"highlightNonHtmlZone")
NPP_PREF_BOOL(smartHighlightUseFindSettings, setSmartHighlightUseFindSettings, @"smartHighlightUseFindSettings")
NPP_PREF_BOOL(smartHighlightOtherView, setSmartHighlightOtherView, @"smartHighlightOtherView")
NPP_PREF_BOOL(printFormFeedPageBreak, setPrintFormFeedPageBreak, @"printFormFeedPageBreak")
NPP_PREF_BOOL(findDialogStaysOpen, setFindDialogStaysOpen, @"findDialogStaysOpen")
NPP_PREF_BOOL(confirmReplaceAllOpenDocs, setConfirmReplaceAllOpenDocs, @"confirmReplaceAllOpenDocs")
NPP_PREF_BOOL(fillDirectoryFromActiveDocument, setFillDirectoryFromActiveDocument, @"fillDirectoryFromActiveDocument")
NPP_PREF_BOOL(findMatchCase, setFindMatchCase, @"findMatchCase")
NPP_PREF_BOOL(findWholeWord, setFindWholeWord, @"findWholeWord")
NPP_PREF_BOOL(findWrap, setFindWrap, @"findWrap")
NPP_PREF_INT(inSelectionThreshold, setInSelectionThreshold, @"inSelectionThreshold")
NPP_PREF_INT(fillFindWhatThreshold, setFillFindWhatThreshold, @"fillFindWhatThreshold")
NPP_PREF_INT(findMode, setFindMode, @"findMode")
NPP_PREF_BOOL(toolbarFilledIcons, setToolbarFilledIcons, @"toolbarFilledIcons")
NPP_PREF_INT(toolbarIconColour, setToolbarIconColour, @"toolbarIconColour")
NPP_PREF_OBJ(toolbarIconCustomColour, setToolbarIconCustomColour, NSString, @"toolbarIconCustomColour")
NPP_PREF_BOOL(toolbarColorizeComplete, setToolbarColorizeComplete, @"toolbarColorizeComplete")
NPP_PREF_BOOL(tabDrawActiveBar, setTabDrawActiveBar, @"tabDrawActiveBar")
NPP_PREF_BOOL(tabColourInactive, setTabColourInactive, @"tabColourInactive")
NPP_PREF_BOOL(tabReduced, setTabReduced, @"tabReduced")
NPP_PREF_INT(tabMaxLabelLength, setTabMaxLabelLength, @"tabMaxLabelLength")
NPP_PREF_OBJ(panelStateKeep, setPanelStateKeep, NSDictionary, @"panelStateKeep")
NPP_PREF_INT(distractionFreeDivPart, setDistractionFreeDivPart, @"distractionFreeDivPart")
NPP_PREF_BOOL(openAnsiAsUtf8, setOpenAnsiAsUtf8, @"openAnsiAsUtf8")
NPP_PREF_OBJ(dockLayout, setDockLayout, NSDictionary, @"dockLayout")
NPP_PREF_OBJ(localizationFile, setLocalizationFile, NSString, @"localizationFile")
NPP_PREF_INT(autoUpdateMode, setAutoUpdateMode, @"autoUpdateMode")
NPP_PREF_INT(updateIntervalDays, setUpdateIntervalDays, @"updateIntervalDays")
NPP_PREF_OBJ(nextUpdateDate, setNextUpdateDate, NSString, @"nextUpdateDate")
NPP_PREF_OBJ(updateRepository, setUpdateRepository, NSString, @"updateRepository")
NPP_PREF_OBJ(customDateFormat, setCustomDateFormat, NSString, @"customDateFormat")
NPP_PREF_INT(foldMarginStyle, setFoldMarginStyle, @"foldMarginStyle")
NPP_PREF_OBJ(shortcutOverrides, setShortcutOverrides, NSDictionary, @"shortcutOverrides")
NPP_PREF_OBJ(contextMenuCommands, setContextMenuCommands, NSArray, @"contextMenuCommands")
NPP_PREF_INT(fontSize, setFontSize, @"fontSize")
NPP_PREF_INT(tabWidth, setTabWidth, @"tabWidth")
NPP_PREF_INT(defaultEOL, setDefaultEOL, @"defaultEOL")
NPP_PREF_INT(appearanceMode, setAppearanceMode, @"appearanceMode")
NPP_PREF_INT(toolbarDisplayMode, setToolbarDisplayMode, @"toolbarDisplayMode")
NPP_PREF_INT(toolbarIconSize, setToolbarIconSize, @"toolbarIconSize")
NPP_PREF_INT(backupMode, setBackupMode, @"backupMode")
NPP_PREF_INT(autosaveInterval, setAutosaveInterval, @"autosaveInterval")
NPP_PREF_INT(printColourMode, setPrintColourMode, @"printColourMode")
NPP_PREF_INT(printHeaderFontSize, setPrintHeaderFontSize, @"printHeaderFontSize")
NPP_PREF_INT(largeFileThresholdMB, setLargeFileThresholdMB, @"largeFileThresholdMB")
NPP_PREF_INT(multiInstanceMode, setMultiInstanceMode, @"multiInstanceMode")
NPP_PREF_INT(autoCompleteSource, setAutoCompleteSource, @"autoCompleteSource")
NPP_PREF_INT(autoCompleteThreshold, setAutoCompleteThreshold, @"autoCompleteThreshold")
NPP_PREF_INT(recentFilesMax, setRecentFilesMax, @"recentFilesMax")
NPP_PREF_INT(recentFilesMaxLength, setRecentFilesMaxLength, @"recentFilesMaxLength")
NPP_PREF_INT(defaultDirectoryMode, setDefaultDirectoryMode, @"defaultDirectoryMode")
NPP_PREF_INT(jsonIndent, setJsonIndent, @"jsonIndent")
NPP_PREF_BOOL(useSpaces, setUseSpaces, @"useSpaces")
NPP_PREF_BOOL(wordWrap, setWordWrap, @"wordWrap")
NPP_PREF_BOOL(showWhitespace, setShowWhitespace, @"showWhitespace")
NPP_PREF_BOOL(showIndentGuides, setShowIndentGuides, @"showIndentGuides")
NPP_PREF_BOOL(showEOL, setShowEOL, @"showEOL")
NPP_PREF_BOOL(showWrapSymbol, setShowWrapSymbol, @"showWrapSymbol")
NPP_PREF_BOOL(restoreSession, setRestoreSession, @"restoreSession")
NPP_PREF_BOOL(detectLanguageFromContent, setDetectLanguageFromContent, @"detectLanguageFromContent")
NPP_PREF_BOOL(showToolbar, setShowToolbar, @"showToolbar")
NPP_PREF_BOOL(autosaveEnabled, setAutosaveEnabled, @"autosaveEnabled")
NPP_PREF_BOOL(fileAutoDetection, setFileAutoDetection, @"fileAutoDetection")
NPP_PREF_BOOL(autoDetectCharacterEncoding, setAutoDetectCharacterEncoding, @"autoDetectCharacterEncoding")
NPP_PREF_BOOL(fileAutoDetectionSilent, setFileAutoDetectionSilent, @"fileAutoDetectionSilent")
NPP_PREF_BOOL(fileAutoDetectionScrollToEnd, setFileAutoDetectionScrollToEnd, @"fileAutoDetectionScrollToEnd")
NPP_PREF_BOOL(printLineNumbers, setPrintLineNumbers, @"printLineNumbers")
NPP_PREF_BOOL(printHeaderBold, setPrintHeaderBold, @"printHeaderBold")
NPP_PREF_BOOL(printHeaderItalic, setPrintHeaderItalic, @"printHeaderItalic")
NPP_PREF_BOOL(largeFileRestrictionEnabled, setLargeFileRestrictionEnabled, @"largeFileRestrictionEnabled")
NPP_PREF_BOOL(largeFileDeactivateWordWrap, setLargeFileDeactivateWordWrap, @"largeFileDeactivateWordWrap")
NPP_PREF_BOOL(largeFileAllowAutoCompletion, setLargeFileAllowAutoCompletion, @"largeFileAllowAutoCompletion")
NPP_PREF_BOOL(largeFileAllowSmartHighlighting, setLargeFileAllowSmartHighlighting, @"largeFileAllowSmartHighlighting")
NPP_PREF_BOOL(largeFileAllowBraceMatch, setLargeFileAllowBraceMatch, @"largeFileAllowBraceMatch")
NPP_PREF_BOOL(largeFileAllowClickableLinks, setLargeFileAllowClickableLinks, @"largeFileAllowClickableLinks")
NPP_PREF_BOOL(suppressHugeFileWarning, setSuppressHugeFileWarning, @"suppressHugeFileWarning")
NPP_PREF_BOOL(linksEnabled, setLinksEnabled, @"linksEnabled")
NPP_PREF_BOOL(linksNoUnderline, setLinksNoUnderline, @"linksNoUnderline")
NPP_PREF_BOOL(linksFullBox, setLinksFullBox, @"linksFullBox")
NPP_PREF_BOOL(braceMatchEnabled, setBraceMatchEnabled, @"braceMatchEnabled")
NPP_PREF_BOOL(smartHighlightEnabled, setSmartHighlightEnabled, @"smartHighlightEnabled")
NPP_PREF_BOOL(customWordCharsEnabled, setCustomWordCharsEnabled, @"customWordCharsEnabled")
NPP_PREF_BOOL(delimiterMultiline, setDelimiterMultiline, @"delimiterMultiline")
NPP_PREF_BOOL(reverseDateTimeOrder, setReverseDateTimeOrder, @"reverseDateTimeOrder")
NPP_PREF_BOOL(rememberPanelState, setRememberPanelState, @"rememberPanelState")
NPP_PREF_BOOL(autoCompleteOnInput, setAutoCompleteOnInput, @"autoCompleteOnInput")
NPP_PREF_BOOL(autoCompleteBriefList, setAutoCompleteBriefList, @"autoCompleteBriefList")
NPP_PREF_BOOL(autoCompleteIgnoreNumbers, setAutoCompleteIgnoreNumbers, @"autoCompleteIgnoreNumbers")
NPP_PREF_BOOL(autoCompleteUseTab, setAutoCompleteUseTab, @"autoCompleteUseTab")
NPP_PREF_BOOL(functionHintOnInput, setFunctionHintOnInput, @"functionHintOnInput")
NPP_PREF_BOOL(autoInsertParenthesis, setAutoInsertParenthesis, @"autoInsertParenthesis")
NPP_PREF_BOOL(autoInsertBracket, setAutoInsertBracket, @"autoInsertBracket")
NPP_PREF_BOOL(autoInsertBrace, setAutoInsertBrace, @"autoInsertBrace")
NPP_PREF_BOOL(autoInsertSingleQuote, setAutoInsertSingleQuote, @"autoInsertSingleQuote")
NPP_PREF_BOOL(autoInsertDoubleQuote, setAutoInsertDoubleQuote, @"autoInsertDoubleQuote")
NPP_PREF_BOOL(autoInsertCloseTag, setAutoInsertCloseTag, @"autoInsertCloseTag")
NPP_PREF_BOOL(openNewDocumentAtStartup, setOpenNewDocumentAtStartup, @"openNewDocumentAtStartup")
NPP_PREF_BOOL(untitledFromFirstLine, setUntitledFromFirstLine, @"untitledFromFirstLine")
NPP_PREF_BOOL(hideTabBar, setHideTabBar, @"hideTabBar")
NPP_PREF_BOOL(tabDoubleClickCloses, setTabDoubleClickCloses, @"tabDoubleClickCloses")
NPP_PREF_BOOL(exitOnClosingLastTab, setExitOnClosingLastTab, @"exitOnClosingLastTab")
NPP_PREF_BOOL(tabShowCloseButton, setTabShowCloseButton, @"tabShowCloseButton")
NPP_PREF_BOOL(tabPinFeatureEnabled, setTabPinFeatureEnabled, @"tabPinFeatureEnabled")
NPP_PREF_BOOL(tabCloseButtonOnInactive, setTabCloseButtonOnInactive, @"tabCloseButtonOnInactive")
NPP_PREF_BOOL(tabBarLocked, setTabBarLocked, @"tabBarLocked")
NPP_PREF_BOOL(tabBarVertical, setTabBarVertical, @"tabBarVertical")
NPP_PREF_BOOL(tabBarMultiLine, setTabBarMultiLine, @"tabBarMultiLine")
NPP_PREF_BOOL(recentFilesShowFullPath, setRecentFilesShowFullPath, @"recentFilesShowFullPath")
NPP_PREF_BOOL(findFillWithSelection, setFindFillWithSelection, @"findFillWithSelection")
NPP_PREF_BOOL(findSelectWordUnderCaret, setFindSelectWordUnderCaret, @"findSelectWordUnderCaret")
NPP_PREF_BOOL(replaceStaysOnOccurrence, setReplaceStaysOnOccurrence, @"replaceStaysOnOccurrence")
NPP_PREF_BOOL(confirmReplaceAll, setConfirmReplaceAll, @"confirmReplaceAll")
NPP_PREF_BOOL(smartHighlightMatchCase, setSmartHighlightMatchCase, @"smartHighlightMatchCase")
NPP_PREF_BOOL(smartHighlightWholeWord, setSmartHighlightWholeWord, @"smartHighlightWholeWord")
NPP_PREF_BOOL(compareIgnoreCase, setCompareIgnoreCase, @"compareIgnoreCase")
NPP_PREF_BOOL(compareIgnoreSpaces, setCompareIgnoreSpaces, @"compareIgnoreSpaces")
NPP_PREF_BOOL(compareIgnoreEmptyLines, setCompareIgnoreEmptyLines, @"compareIgnoreEmptyLines")
NPP_PREF_BOOL(compareDetectMoves, setCompareDetectMoves, @"compareDetectMoves")
NPP_PREF_BOOL(compareCharDiffs, setCompareCharDiffs, @"compareCharDiffs")

#define NPP_PREF_DOUBLE(getter, setter, key)                                      \
- (double)getter { return [[NSUserDefaults standardUserDefaults] doubleForKey:Key(key)]; } \
- (void)setter:(double)value {                                                    \
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:Key(key)];       \
}

NPP_PREF_DOUBLE(printMarginLeft, setPrintMarginLeft, @"printMarginLeft")
NPP_PREF_DOUBLE(printMarginRight, setPrintMarginRight, @"printMarginRight")
NPP_PREF_DOUBLE(printMarginTop, setPrintMarginTop, @"printMarginTop")
NPP_PREF_DOUBLE(printMarginBottom, setPrintMarginBottom, @"printMarginBottom")

- (BOOL)systemIsDark {
    NSString *match = [NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSString *)effectiveThemeName {
    BOOL dark = self.appearanceMode == 2 || (self.appearanceMode == 0 && [self systemIsDark]);
    // A user language made for dark mode is chosen by extension in dark mode.
    [LanguageCatalog sharedCatalog].darkMode = dark;
    return dark ? (self.darkThemeName ?: @"DarkModeDefault") : (self.lightThemeName ?: @"Default");
}

- (void)setStyleOverride:(NSDictionary *)attributes
             forLanguage:(NSString *)language styleID:(int)styleID {
    NSMutableDictionary *all = [self.styleOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%d", language, styleID];
    if (attributes.count) all[key] = attributes; else [all removeObjectForKey:key];
    self.styleOverrides = all;
}

- (NSDictionary *)styleOverrideForLanguage:(NSString *)language styleID:(int)styleID {
    id stored = self.styleOverrides[[NSString stringWithFormat:@"%@/%d", language, styleID]];
    if ([stored isKindOfClass:[NSDictionary class]]) return stored;
    // Settings written by the foreground-only version were a bare hex string.
    if ([stored isKindOfClass:[NSString class]]) return @{@"fg": stored};
    return nil;
}

+ (NSString *)dateFormatFromWindowsPicture:(NSString *)picture {
    // GetDateFormat / GetTimeFormat pictures mostly read the same; these do not.
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, n = picture.length;
    while (i < n) {
        unichar c = [picture characterAtIndex:i];
        if (c == '\'') {                                    // quoted text passes through
            NSRange close = [picture rangeOfString:@"'" options:0 range:NSMakeRange(i + 1, n - i - 1)];
            NSUInteger end = close.location == NSNotFound ? n : NSMaxRange(close);
            [out appendString:[picture substringWithRange:NSMakeRange(i, end - i)]];
            i = end;
            continue;
        }
        NSUInteger run = 1;
        while (i + run < n && [picture characterAtIndex:i + run] == c) run++;
        NSString *piece = [picture substringWithRange:NSMakeRange(i, run)];
        if (c == 't') piece = @"a";                         // tt / t: AM or PM
        else if (c == 'd' && run >= 3) piece = run == 3 ? @"EEE" : @"EEEE";
        else if (c == 'g') piece = @"G";
        [out appendString:piece];
        i += run;
    }
    return out;
}

- (BOOL)keepsPanelState:(NSString *)panel {
    NSNumber *keep = self.panelStateKeep[panel];
    return keep ? keep.boolValue : YES;
}

- (NSInteger)tabWidthForLanguage:(NSString *)language {
    NSDictionary *own = language ? self.languageIndent[language] : nil;
    return [own[@"size"] integerValue] > 0 ? [own[@"size"] integerValue] : MAX(1, self.tabWidth);
}

- (BOOL)useSpacesForLanguage:(NSString *)language {
    NSDictionary *own = language ? self.languageIndent[language] : nil;
    return own[@"spaces"] ? [own[@"spaces"] boolValue] : self.useSpaces;
}

- (NSString *)searchEngineTemplate {
    switch (self.searchEngine) {
        case 0: return @"https://duckduckgo.com/?q=%@";
        case 2: return @"https://www.bing.com/search?q=%@";
        case 3: return @"https://search.yahoo.com/search?q=%@";
        case 4: {
            // Upstream writes the words as $(CURRENT_WORD).
            NSString *custom = [self.searchEngineCustom stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
            custom = [custom stringByReplacingOccurrencesOfString:@"$(CURRENT_WORD)" withString:@"%@"];
            if ([custom rangeOfString:@"%@"].location != NSNotFound) return custom;
            break;
        }
        default: break;
    }
    return @"https://www.google.com/search?q=%@";
}

- (void)setShortcutOverride:(NSString *)spec forCommand:(NSString *)title {
    NSMutableDictionary *all = [self.shortcutOverrides mutableCopy] ?: [NSMutableDictionary dictionary];
    if (spec.length) all[title] = spec; else [all removeObjectForKey:title];
    self.shortcutOverrides = all;
}

- (void)applyToEditor:(EditorController *)editor {
    // Light or Dark chosen in Preferences is the whole interface's, not only the
    // editor theme's (NppDarkMode::setDarkMode dresses menus, tabs and dialogs
    // too); following the system leaves the appearance to it. Set first, so
    // systemIsDark reads the system again once "follow" is back.
    NSAppearanceName chrome = self.appearanceMode == 1 ? NSAppearanceNameAqua
                            : self.appearanceMode == 2 ? NSAppearanceNameDarkAqua : nil;
    if (!(NSApp.appearance == nil && chrome == nil) && ![NSApp.appearance.name isEqualToString:chrome]) {
        NSApp.appearance = chrome ? [NSAppearance appearanceNamed:chrome] : nil;
    }
    // The theme decides the colours, so it is loaded before the styles are set.
    NSString *wanted = [self effectiveThemeName];
    if (![[StyleCatalog sharedCatalog].themeName isEqualToString:wanted]) {
        [StyleCatalog loadThemeNamed:wanted];
        [editor applyLanguage];
    }
    ScintillaView *sci = editor.mainSci;
    [sci setStringProperty:SCI_STYLESETFONT parameter:STYLE_DEFAULT value:NppAvailableFontName(self.fontName)];
    [sci message:SCI_STYLESETSIZE wParam:STYLE_DEFAULT lParam:self.fontSize];
    [editor applyDocumentSettings];
    [sci message:SCI_SETWRAPMODE wParam:(uptr_t)(self.wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE) lParam:0];
    [editor applySymbolsToView:sci];
    if (editor.secondarySci) [editor applySymbolsToView:editor.secondarySci];
    [editor refreshChrome];
    // The agent interface listens while MISC. says so, and not otherwise.
    [NppAgentServer shared].editor = editor;
    if (self.agentServer) [[NppAgentServer shared] start]; else [[NppAgentServer shared] stop];
    [editor gitRefreshMarkers];
}

- (void)reset {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [[d dictionaryRepresentation] allKeys]) {
        if ([key hasPrefix:kDefaultsPrefix]) [d removeObjectForKey:key];
    }
}

@end

#pragma mark - Editor side

void NppE2ECountBeep(BOOL muted);   // E2EHooks.mm: counts for the end-to-end suite, nothing otherwise

NSString *NppAvailableFontName(NSString *name) {
    static NSMutableDictionary<NSString *, NSString *> *resolved;
    static NSString *monospaced;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        resolved = [NSMutableDictionary dictionary];
        monospaced = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular].fontName;
    });
    if (!name.length) return monospaced;
    NSString *known = resolved[name];
    if (known) return known;
    // A face name (Menlo, Courier New) or a family the font manager lists.
    BOOL installed = [NSFont fontWithName:name size:12] != nil ||
                     [[NSFontManager sharedFontManager] availableMembersOfFontFamily:name].count > 0;
    NSString *use = installed ? name : monospaced;
    resolved[name] = use;
    return use;
}

void NppBeep(void) {
    NppE2ECountBeep([NppPreferences shared].muteSounds);
    if (![NppPreferences shared].muteSounds) NSBeep();
}

@implementation EditorController (SettingsCommands)

static NSString *gSettingsDirectoryForThisLaunch;

+ (void)setSettingsDirectoryForThisLaunch:(NSString *)directory {
    gSettingsDirectoryForThisLaunch = [directory copy];
}

BOOL NppSettingsDirectoryOverridden(void) { return gSettingsDirectoryForThisLaunch.length > 0; }

- (NSString *)supportDirectory {
    // -settingsDir= on the command line, for this launch only; then the
    // preference; then the default.
    NSString *override = gSettingsDirectoryForThisLaunch.length
        ? gSettingsDirectoryForThisLaunch : [NppPreferences shared].settingsDirectory;
    NSString *dir = override.length
        ? override
        : self.defaultSessionPath.stringByDeletingLastPathComponent;
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:nil error:NULL];
    return dir;
}

- (NSString *)userDefinedLanguagePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"userDefineLang.xml"];
}

- (NSUInteger)importFiles:(NSArray<NSString *> *)paths intoSubdirectory:(NSString *)subdir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:NULL];

    NSUInteger copied = 0;
    for (NSString *src in paths) {
        NSString *target = [dest stringByAppendingPathComponent:src.lastPathComponent];
        [fm removeItemAtPath:target error:NULL];      // importing again replaces
        if ([fm copyItemAtPath:src toPath:target error:NULL]) copied++;
    }
    return copied;
}

- (NSArray<NSString *> *)importedFilesIn:(NSString *)subdir {
    NSString *dir = [[self supportDirectory] stringByAppendingPathComponent:subdir];
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    return [names sortedArrayUsingSelector:@selector(compare:)] ?: @[];
}

/// Writes the language in the same shape Notepad++ uses for userDefineLang.xml,
/// so the file is recognisable to anyone who has seen the Windows one.
static NSString *XMLEscaped(NSString *text) {
    NSMutableString *out = [(text ?: @"") mutableCopy];
    [out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
    [out replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, out.length)];
    return out;
}

- (BOOL)defineUserLanguageNamed:(NSString *)name
                     extensions:(NSString *)extensions
                       keywords:(NSString *)keywords
                    commentLine:(NSString *)commentLine {
    if (!name.length) return NO;
    NSString *xml = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
        @"<NotepadPlus>\n"
        @"    <UserLang name=\"%@\" ext=\"%@\" udlVersion=\"2.1\">\n"
        @"        <Settings>\n"
        @"            <Global caseIgnored=\"no\" />\n"
        @"        </Settings>\n"
        @"        <KeywordLists>\n"
        @"            <Keywords name=\"Comments\">%@</Keywords>\n"
        @"            <Keywords name=\"Keywords1\">%@</Keywords>\n"
        @"        </KeywordLists>\n"
        @"    </UserLang>\n"
        @"</NotepadPlus>\n",
        XMLEscaped(name), XMLEscaped(extensions), XMLEscaped(commentLine), XMLEscaped(keywords)];

    if (![xml writeToFile:[self userDefinedLanguagePath] atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL]) return NO;

    // Read back the way every user language is, and applied to the document.
    [[LanguageCatalog sharedCatalog] reloadUserLanguagesFromDirectory:[self supportDirectory]];
    // Shown on the document in front, as the Windows dialog previews it, but
    // not as a choice the user made: a rename still re-detects the language.
    [self setLanguageNamed:name];
    return YES;
}

- (NSDictionary *)userDefinedLanguage {
    NSString *xml = [NSString stringWithContentsOfFile:[self userDefinedLanguagePath]
                                              encoding:NSUTF8StringEncoding error:NULL];
    if (!xml.length) return nil;
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"<UserLang name=\"([^\"]*)\" ext=\"([^\"]*)\""
                             options:0 error:&err];
    NSTextCheckingResult *m = [re firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    if (!m) return nil;
    return @{@"name": [xml substringWithRange:[m rangeAtIndex:1]],
             @"ext":  [xml substringWithRange:[m rangeAtIndex:2]]};
}

@end
