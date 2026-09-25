# Notepad++ for macOS — notes for coding agents

This repository is a native macOS port of Notepad++. Our code is under `macos/`.
`PowerEditor/`, `scintilla/`, `lexilla/` and `boostregex/` are a snapshot of upstream Notepad++
(`UPSTREAM.md` says which) and are the **reference**, not something to edit (one exception:
`lexilla/lexers/LexUser.cxx`, two portability fixes). Human-facing description: `README.md`.
The port is released and supported from this repository: never point users at upstream's site,
forum or e-mail - README, About and the Help menu lead here. `macos/FEATURES.md` is the generated
menu-command coverage.

The maintainers' internal working documents (audit, plan, engineering notes, to-do lists) are
deliberately **not published**; they live beside the clone in `../workdocs/`. Keep them current
there, and never add such documents to the repository.

## What it is

`NotepadMac.app`: Objective-C++ / Cocoa over the same Scintilla and Lexilla that
Windows Notepad++ uses, reading Notepad++'s own data files (`langs.model.xml`,
`stylers.model.xml`, themes, `functionList/*.xml`, `nativeLang/*.xml`,
`shortcuts.xml`, `session.xml`, `contextMenu.xml`) instead of re-describing them.
No Xcode project, no package manager: `macos/build.sh` compiles with the Command
Line Tools. Bundle id `org.notepad-plus-plus.mac`, minimum macOS 11, universal
(arm64 + x86_64). Licence: GPL, as upstream.

## Build, test, run

```
NPPMAC_ARCH=native bash macos/build.sh      # host architecture only; incremental (seconds after one edit)
bash macos/build.sh                          # universal, what CI and releases use
bash macos/test.sh                           # builds if needed, runs the suite, checks nativeLang-extra
NPPMAC_TEST=1 macos/build/NotepadMac.app/Contents/MacOS/NotepadMac > log 2>&1   # the suite alone; last line "N passed, M failed"
NPPMAC_TEST=1 NPPMAC_TEST_ONLY=Git,Agent macos/build/NotepadMac.app/Contents/MacOS/NotepadMac   # only the sections whose heading has one of the words: while working on an area
open macos/build/NotepadMac.app
bash macos/package.sh                        # .dmg; signs/notarises when NPPMAC_SIGN_IDENTITY / NPPMAC_NOTARY_PROFILE are set
```

- Every `.mm` in `macos/app/` is compiled; there is no file list to update.
  C sources of `macos/third_party/argon2` are compiled by their own block in `build.sh`, as is
  the ComparePlus engine (`macos/third_party/compareplus`, C++20, with the shims beside it).
- Linked: Cocoa, QuartzCore, Security, WebKit, Vision, CoreImage, libcurl, libxml2, zlib; libpcre2 is loaded at run time.
- The suite is run inside the real application with `NPPMAC_TEST=1`. `macos/app/Tests.mm` is the
  driver (`NppMacRunTests`: the shared helpers, the counters, the coverage meta-test, the summary);
  the sections live by area in `macos/app/Tests<Area>.mm` (beside it: `build.sh` compiles
  `macos/app/*.mm` only) - `TestsFiles`, `TestsEditing`,
  `TestsSearch`, `TestsView`, `TestsLanguages`, `TestsTools`, `TestsSettings`, `TestsPlugins`,
  `TestsGit`, `TestsAgent` - each a function `NppTests…(app, ed, sci)` declared in
  `TestSupport.h` (with the helpers) and called by the driver in the suite's order. Where an
  area's sections are not together in that order, its file has one function per run of them;
  a new section goes into its area's function, or a new function called at its place in the driver. While working on one area run only its sections
  (`NPPMAC_TEST_ONLY=Git,Agent`, matched against the `== … ==` headings); the whole suite,
  coverage meta-test included, runs before every commit and must end `0 failed`. A check is `Check(@"IDM_… or Area (what)", @"what must hold", condition)`.
  `macos/implemented.txt` lists upstream command ids the suite must cover (a meta-test reads it).
- Screenshots without a display server: `NPPMAC_SNAPSHOT=/path/out.png` plus optionally
  `NPPMAC_SNAPSHOT_PANEL=find:<tab>|prefs:<page>|style|mapper|about|debug|tools:<digest|files|bcrypt|scrypt|argon2|pbkdf2|base|unbase|password|converter|http[:<address>]>`.
  A setting can be overridden for one run without touching the user's defaults:
  `… NotepadMac -NppMac.localizationFile russian.xml`. Look at the PNG: it is how layout and
  cut-off text are verified. The pictures in `docs/screenshots/` are whole windows on a made-up
  project, taken by `../npp-tests/tools/shots.py` (English interface, no personal paths).
- CI: `.github/workflows/macos.yml` (macos-14): universal build, suite, package; the `.dmg`
  is an artifact. **The runner has empty NSUserDefaults** - a test must set every preference it
  depends on and restore it afterwards. To reproduce locally: `defaults export org.notepad-plus-plus.mac backup.plist`,
  `defaults delete org.notepad-plus-plus.mac`, run the suite, then `defaults import` the backup. Never
  leave the user's preferences changed, and do not do this while the user has the app open.
  Its screen is small (about 1024x768, smaller than the 1000x780 window): a check that moves or resizes
  windows must hold there too.

### Release packaging (signing and notarization)

`macos/package.sh` ships a copy of the app without the `test-*.py` servers, signed
inside out (the nested `Contents/Helpers/nppmac` first, then the bundle) with
the hardened runtime and no entitlements - `libpcre2` is dlopen'ed from `/usr/lib`,
which the hardened runtime allows for system libraries, and the child processes
(Run, NppExec) are ordinary fork/exec. The app is notarized first, as a zip, so its
own stapled ticket lets a copy dragged out of the image open on an offline Mac;
the image is then signed, notarized and stapled itself. Set-up, once per machine:

- a "Developer ID Application" certificate (Xcode → Settings → Accounts →
  Manage Certificates → "+");
- `xcrun notarytool store-credentials <profile> --apple-id … --team-id …`;
- let codesign use the signing key without a per-signature dialog, or a signing
  run started from tooling hangs forever on a keychain prompt it cannot show
  (and a dismissed prompt fails with `errSecInternalComponent`):
  `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db`

Both that `security` call and `store-credentials` ask for passwords; type them in
a real terminal window - hidden input relayed through other tooling arrives
mangled and fails with 401 / "passphrase is not correct".

## How work is done here

1. **Windows Notepad++ is the specification.** Before implementing or fixing anything, read how
   upstream does it (`PowerEditor/src/...`) and match it: wording, defaults, order of menu items,
   file formats, edge cases. Say in a comment which upstream function a piece follows
   (`// setXmlLexer`, `// HashFromTextDlg::generateHashPerLine`). Where macOS needs something else
   (Finder for Explorer, Trash for Recycle Bin), say so at the site.
2. **Every change comes with tests** in the area's `Tests<Area>.mm`, against published vectors or a real local
   server where that applies (`test-ftp-server.py`, `test-http-server.py`), and with a check in
   another language when it has UI. Run the whole suite; it must end `0 failed`.
3. **Docs move with the code**: this file for design decisions and numbers, `README.md` when what a user
   gets changes (features, differences from Windows), `../workdocs/` for the internal audit and engineering record, `implemented.txt` / `FEATURES.md` (generated by
   `gen_features.sh`) for menu commands.
4. One commit per piece of work, message `macos: <what is now true>` with a body explaining why.
   Push to `origin main`, then watch the "macOS" workflow to green
   (`gh run watch <id> --exit-status`).
5. Report honestly. If something is not done, not verified, or got worse, say it, with numbers.
   No hand-written special cases to make one example pass (see the language model below).
6. Do not wait on long fixed sleeps; poll for the condition (`until grep -q 'passed,' log; do sleep 2; done`).

Code style: match the surrounding file - plain-English comments that say *why*, Objective-C++
with blocks and small static helpers, categories on `EditorController` per area
(`EditorController (ToolsCommands)`), no new dependencies without a strong reason. Property names
must not begin with `copy`/`new`/`init` (ARC ownership rules) and must not be called `count`.
`NSTextView.string` is the live backing store - copy it before comparing later.

## Map of `macos/app`

| Area | Files |
|---|---|
| Application, menus, actions, snapshot mode, self-test | `AppDelegate.mm`, `main.mm`, `CommandIDs.h` (generated), `MacroableCommands.h` (generated) |
| Documents, tabs, views, session, lexer set-up, themes | `EditorController.mm`, `TabBarView.mm`, `Toolbar.mm`, `EditorLook.mm`, `ViewCommands.mm`, `BehaviourCommands.mm`, `BackupAndPrint.mm` |
| Languages, styles, UDL | `LanguageCatalog.mm`, `LangMap.h` (generated), `StyleCatalog.mm`, `StyleConfigurator.mm`, `UserLanguages.mm`, `UserLanguageDialog.mm`, `ApiCatalog.mm` (auto-completion) |
| Language from contents | `LanguageDetection.mm` (declarations only: shebang, `<?xml`, modeline, JSON), `LanguageModel.mm` (the trained model) |
| Search | `FindCommands.mm`, `SearchCommands.mm`, `NppRegex.mm` (Boost-syntax regex over ICU/PCRE2), `BoostFormat.mm` |
| Editing commands | `EditCommands.mm`, `AdvancedEditCommands.mm`, `TypingCommands.mm`, `EncodingCommands.mm`, `CharsetDetection.mm`, `TagMatch.mm`, `NumberSet.mm`, `Formula.mm` + `NumberSetCommands.mm` (the context menu's sum/average/min/max/count and sort of a selected set of numbers; Edit > Calculate, Cmd+=, a formula's value after its `=`, selected or at the caret; Edit > Selected Numbers mirrors the context submenu for shortcuts and `run_command`; user reference `docs/numbers.html`; Foundation-only parsing, NSDecimalNumber arithmetic, functions in double) |
| Panels and docking | `DockingManager.mm`, `NppPanel.mm`, `DocumentListPanel.mm`, `FunctionListPanel.mm`, `FunctionListCatalog.mm`, `ProjectPanel.mm`, `WorkspacePanel.mm`, `AuxPanels.mm` |
| Preferences, shortcuts, context menu | `SettingsCommands.mm` (NPP_PREF_* macros, defaults), `SettingsPanels.mm`, `ShortcutMapper.mm`, `ContextMenuFile.mm` |
| Localisation | `Localization.mm` (upstream `nativeLang/*.xml` by command id and by English text; the port's own texts from `resources/nativeLang-extra/`) |
| Plugin stand-ins | `JsonCommands.mm`, `CompareCommands.mm` (ComparePlus's engine from `macos/third_party/compareplus` over the two panes; see below), `XmlCommands.mm`, `FtpClient.mm`/`FtpCommands.mm`, `ScriptCommands.mm` (NppExec), `RunCommands.mm`, `MimeCommands.mm` (MIME Tools), `ConverterCommands.mm` + the Conversion Panel in `ToolsWindows.mm`, `ExportCommands.mm` (NppExport), `SpellCheck.mm` (DSpellCheck by way of NSSpellChecker; indicator 17 - 8-16 are taken by mark styles, find mark, links and tag match), `MarkdownPanel.mm` (MarkdownViewer++: cmark from `macos/third_party/cmark` + a GFM-table pre-pass, shown in a WKWebView with JavaScript off) |
| Third-party plugins | `PluginHost.mm` (dlopen, the send() bridge, NPPM/NPPN subset); the public C interface and sample live in `macos/plugin-sdk/`. Release signing needs `macos/entitlements.plist` (library validation off) or the hardened runtime refuses the dylibs |
| Tools menu | `ToolsCommands.mm` (digests, macros, window list), `CryptoTools.mm` (bcrypt, scrypt, Argon2 wrapper, PBKDF2, SHA-3, Base58/32, passwords), `HttpRequest.mm` (request, curl import/export, libcurl), `ToolsWindows.mm` (the windows, Auto Layout) |
| Mac extras | `ImageCommands.mm` (OCR paste, QR both ways - Vision + Core Image), `macos/cli/nppmac.m` (the command line tool, built into Contents/Helpers and heard over a distributed notification; `nppmac mcp` is the stdio bridge to the agent socket) |
| Agent interface (MCP) | `AgentServer.mm`: the Unix socket, the JSON-RPC/MCP methods and the 21 tools; see below |
| Git | `GitCommands.mm`: `NppGit` (runs the `git` executable; status, branches, HEAD contents), the margin markers against HEAD, the status-bar branch, the Git panel, the Commit window; see below |
| Help | `InfoWindows.mm`, `UpdateChecker.mm` |

Generators (`macos/gen_*.py|sh`) rebuild headers and resources from upstream sources; rerun them
after merging upstream rather than editing their output.

### Lexer set-up (easy to get wrong)

`-[EditorController applyLanguage]` must give each lexer what `ScintillaEditView.cpp` gives it:
properties per family (`fold.html`, `fold.hypertext.comment`, `fold.preprocessor`,
`lexer.cpp.track.preprocessor=0`, backquoted strings, JSON escapes...) and the word lists under the
numbers the *lexer* reads, which for the C family, Objective-C, Tcl, TypeScript, XML and the
hypertext family are not Notepad++'s `LANG_INDEX_*` numbers. HTML, PHP, ASP and JSP are all the
`hypertext` lexer with HTML + embedded JavaScript + PHP + ASP words and styles.

### Compare (ComparePlus's engine)

`macos/third_party/compareplus/Engine` and `Icons` are the plugin's own files, unchanged
(commit 6611373); `shim/` stands in for Win32 (UTF-8 to `wchar_t` and back, lower-casing),
Boost.Regex (the standard library's), the progress dialog (a cancel flag), Notepad++'s
settings and helpers, and `CallScintilla`, which reaches the two panes through Scintilla's
direct function: `BindViews` in `CompareCommands.mm` sets the pointers, MAIN_VIEW is the
document in front, SUB_VIEW the second pane with the other text. The engine writes its
marks straight into the panes: whole-line backgrounds on markers 0/2/3/4, symbols 10-19 in
margin 5, the changed characters under indicator 18, all on numbers the port has free
(`shim/NppHelpers.h`). Scintilla draws a background marker in the text only when some
margin's mask has its bit, so margin 1's mask carries them. Alignment is the plugin's:
blank annotations (`alignPanes`, from `alignDiffs`) put each difference at the same height
in both panes. What is the port's own around it: the other text in the second pane with the
document's language and theme, the bar, Escape, the comparison re-run 0.4 s after typing
(`compareRefreshNow`, the view kept where it was), and the revert arrow (marker 9) beside
each run of the port's own line diff (`diffBetween`, which the git margin and the agent use
too). Not carried over: selection compare, find unique, the nav bar, patches, visual
filters. `NPPMAC_SNAPSHOT_COMPARE=<file>` snapshots the sample compared with that file.

### End-to-end hooks (`E2EHooks.mm`)

A separate black-box suite ([NotepadMac-tests](https://github.com/tanderbold/NotepadMac-tests), checked out
beside this one as `../npp-tests`) drives a copy of the
built application under its own bundle id over the agent socket. With `NPPMAC_E2E=1`, and
only then, the agent server registers `e2e_*` tools (Scintilla messages, menu state, windows
and their controls, clicks and keys through AppKit's own routing, snapshots (`screen=true`: the window
as the window server composites it, which the app may take of itself without the Screen Recording
permission), preferences,
a private clipboard), NSAlert and open/save panels take queued answers, NSWorkspace opens
and printing are logged instead of performed, and requests are served in the run loop's
common modes so a modal can be driven from a second connection. `nppmac` talks to the
application it ships in (its bundle id + `.cli`), so the copy never reaches the user's
instance. Without the variable nothing of this exists; keep it that way.

### Agent interface (MCP)

`AgentServer.mm` is the application speaking MCP itself: JSON-RPC 2.0, one message per line,
over a Unix socket (`~/Library/Application Support/NotepadMac/agent.sock`, 0600; the suite and
tools point elsewhere with `NPPMAC_AGENT_SOCKET`, kept short - a socket path has 104 bytes).
`nppmac mcp` is nothing but a pipe between an agent's stdio and that socket, so any MCP client
works and the protocol lives in one place. Listening follows the MISC. preference `agentServer`
(off by default) through `-[NppPreferences applyToEditor:]`; `applicationWillTerminate:` removes
the socket file.

- Every message is handled on the main thread (`handleMessage:`), so tools run where the editor
  lives; the connection's thread waits. A tool is a block registered in `registerTools` with its
  JSON schema; `callTool:arguments:error:` is what the suite calls.
- Reading a document that is not in front goes through a hidden `ScintillaView` given the
  document's pointer (`readDocument:using:`): text, styling and lexer belong to the Scintilla
  document, so the tab in front is not touched. Changing one goes through the front view
  (`withDocumentInFront:do:`), which is what keeps `modified`, bookmarks and folds, and the tab
  and the recent order are put back, as `forEachOpenDocument:` does for a search.
- Lines and columns in the protocol are one-based, columns in characters (`SCI_POSITIONAFTER`
  walks UTF-8); answers carry byte positions too. Text in one answer stops at a million
  characters with `truncated`.
- Tools reuse the engines as they are: `FindCommands` (its `regexFor:`/`rangesOfMatches:` are
  declared privately in `AgentServer.mm`), `LanguageModel`, `FunctionListCatalog`,
  `CompareCommands`, `NppCharsetDetection`, `ImageCommands`, `NSSpellChecker`. Adding a tool means
  one `addTool:` call, a check in the suite's "Agent interface" section, and a row in README's table.
- Refused to agents: `IDM_FILE_EXIT`, `IDM_FILE_DELETE`; closing a modified document without
  `discard_changes`; saving a document that has no file (that is a Save As panel, the user's).

### Git

`GitCommands.mm` drives the `git` executable (`NppGit executable`: the Command Line Tools' or
Xcode's, found through `xcode-select -p` so that a Mac without the tools never gets Apple's
install dialog from `/usr/bin/git`; else Homebrew's) - never a library, so what the editor shows
is what `git status` says. Every call sets `GIT_TERMINAL_PROMPT=0`: git fails rather than hangs
on a prompt no one can see. Quick calls (status, show, rev-parse) run synchronously on the main
thread; fetch, pull and push stream into the NppExec console from a thread.

- Repository roots are cached per folder (`repositoryRootForPath:`), forgotten when the app comes
  to front, on Refresh and after fetch/pull/push. The document's path relative to the root is
  worked out with symlinks resolved on both sides: git reports `/private/var/...`, the editor may
  hold `/var/...`.
- Margin markers 6-8 in margin 4 (`SCI_SETMARGINS` is 5 for that) mark added, changed and removed
  lines against HEAD's text - fetched once per HEAD commit per document - diffed with Compare's
  Myers implementation over the text as it is now, 0.6 s after typing stops (not for texts over
  2 MB); on open, save, activation and after every git command at once. MISC. has the switch.
- Bookmarks, folds and the modified flag are the front view's, so the panel's commands work on
  paths and the editor reloads an open document that `discard` set back. Destructive commands ask
  (`gitAsk:`); the suite sets `gitAnswersWithoutAsking`.
- The panel's buttons are an `NppButtonFlow` that wraps, and its narrow columns are as wide as
  their headings, because a panel is narrow and some languages' words are long; `relocalize`
  is called from `applyLocalization`. The suite opens the commit window and the panel in every
  language that translates the Git texts and checks nothing is cut.
- The suite (`== Git ==`) makes its own repository in the temporary folder: `git init`, an
  identity set in the repository's config, commits, a bare repository to push to.

### Localisation

Interface text is written in English in code and translated at display: menu commands by upstream
command id, everything else by its English text (`NppL(@"…")`, `NppLMessage` for `$STR_REPLACE$` /
`$INT_REPLACE$`). Text upstream already has is reused; text only the port has goes into
`macos/resources/nativeLang-extra/english.xml` (the master) and is translated in the ~90 sibling
files, which must use the vocabulary of the language's own `nativeLang` file; an item a translator
is unsure of is **left out** (stays English), never guessed. `python3 macos/check_nativelang_extra.py`
validates them. A literal `|` in a label is read as `Group|Field` - avoid it. New windows are laid
out with Auto Layout so translated text cannot be cut; the suite checks that in Russian.
The translations are model-made and unreviewed by native speakers (said so in `README.md`).

## The language model (working out a language from a text)

Used when a file's name says nothing (no extension, text pasted into an empty document). Two
layers only: what the text declares outright, then the trained model. **There are no hand-written
marks or keyword rules, by decision**: when a snippet is misread, the fix is training data or
features, measured on held-out files - never a rule for that snippet. If the model still gets a
case wrong, report it; do not special-case it.

- Model: one independent logistic judgement per language (91), so a text two languages could have
  written is offered as a short list. Features are 64-bit keys computed identically in
  `train-language-model.py` and `LanguageModel.mm`: byte n-grams (2,3,4), words, first word of a
  line, line shape, pairs of neighbouring words. File format v5 (`NPPLANG\x05`) carries the weights
  (int8 per class with a scale), idf, and the fitted rule: scale, level to be offered, level to be
  applied alone (below it the best three are offered). Changing a feature means changing both files
  and retraining; the suite checks the app and the trainer agree.
- Corpora (not in the repository, ~4 GB, kept beside the clone as `../linguist`, `../rosetta`, `../repos`):
  - `git clone --depth 1 https://github.com/github-linguist/linguist.git`
  - `git clone --depth 1 https://github.com/acmeism/RosettaCodeData.git rosetta`
  - `python3 macos/fetch-language-corpus.py ../repos` - shallow clones of ~90 well-known projects, plus,
    for languages no well-known project is written in (INI, registry, KiXtart, COBOL...), files found
    by extension through GitHub code search (needs `gh` logged in; rate-limited, about an hour).
  - also read: Lexilla's lexer examples, the function-list corpus, this repository, written samples
    in `macos/resources/language-samples/<language>/`, generated Intel HEX / S-record / Tektronix.
  - Files are labelled by extension as Notepad++ would open them (`Makefile`, `CMakeLists.txt` by
    name; `.tex` as LaTeX or TeX by its head; Linguist's "JSON with Comments" as JSON5, the lexer
    Notepad++ has for it). A file labelled JSON that is not JSON (a `tsconfig.json` with comments or
    trailing commas) is left out: it taught the model that JSON has comments. At most 120 files per
    project per language. The train/held-out split is by project folder (Rosetta: by task), hashed
    on the path inside the repository for files of the checkout, so a worktree trains the same
    model; the written samples are always learnt from, never held back.
- Train (needs `numpy`, about four minutes):
  `python3 macos/train-language-model.py --linguist ../linguist --rosetta ../rosetta --repos ../repos --report > train.log`
  It writes `macos/resources/language-model.bin` and prints, on held-out files, accuracy by fragment
  length, by source, the confusions, and a "quoting" row (a piece of one language with a block of
  another set into it - the known weakness; measured, deliberately not trained on: it bought 2 points
  there and cost many confident answers elsewhere).
  Try a model on files: `python3 macos/train-language-model.py --model macos/resources/language-model.bin --try file…`
- After retraining: rebuild, run the suite (`IDM_LANG_DETECT …` checks, among them "a file of each
  language": at least 36 of the 41 corpus files offered their own language), update the table and
  numbers below, commit the `.bin` with the script.
- Current numbers (held-out, first choice right): whole files 92.6%, 40 lines 90.8%, 20 lines 89.4%,
  10 lines 86.4%, 5 lines 81.7%, quoting 61.5%. JSON5/JSONC files (34 held out) 79%, JSON 98%.
  A list is offered for 18% of whole files, 34% of 10-line pieces. The rule's measure is flat near
  its best (rules 0.002 apart differed twofold in how often they ask), so of the rules within
  `NPP_FIT_TOLERANCE` of the best the trainer takes the one that asks least.
