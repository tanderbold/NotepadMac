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
open macos/build/NotepadMac.app
bash macos/package.sh                        # .dmg; signs/notarises when NPPMAC_SIGN_IDENTITY / NPPMAC_NOTARY_PROFILE are set
```

- Every `.mm` in `macos/app/` is compiled; there is no file list to update.
  C sources of `macos/third_party/argon2` are compiled by their own block in `build.sh`.
- Linked: Cocoa, QuartzCore, Security, libcurl, libxml2, zlib; libpcre2 is loaded at run time.
- The suite is `macos/app/Tests.mm` (one function, `NppMacRunTests`), run inside the real
  application with `NPPMAC_TEST=1`. A check is `Check(@"IDM_… or Area (what)", @"what must hold", condition)`.
  `macos/implemented.txt` lists upstream command ids the suite must cover (a meta-test reads it).
- Screenshots without a display server: `NPPMAC_SNAPSHOT=/path/out.png` plus optionally
  `NPPMAC_SNAPSHOT_PANEL=find:<tab>|prefs:<page>|style|mapper|about|debug|tools:<digest|files|bcrypt|scrypt|argon2|pbkdf2|base|unbase|password|http[:<address>]>`.
  A setting can be overridden for one run without touching the user's defaults:
  `… NotepadMac -NppMac.localizationFile russian.xml`. Look at the PNG: it is how layout and
  cut-off text are verified.
- CI: `.github/workflows/macos.yml` (macos-14): universal build, suite, package; the `.dmg`
  is an artifact. **The runner has empty NSUserDefaults** - a test must set every preference it
  depends on and restore it afterwards. To reproduce locally: `defaults export org.notepad-plus-plus.mac backup.plist`,
  `defaults delete org.notepad-plus-plus.mac`, run the suite, then `defaults import` the backup. Never
  leave the user's preferences changed, and do not do this while the user has the app open.

### Release packaging (signing and notarization)

`macos/package.sh` ships a copy of the app without the `test-*.py` servers, signed
inside out (a single `codesign` call: the bundle has exactly one code object) with
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
2. **Every change comes with tests** in `Tests.mm`, against published vectors or a real local
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
| Editing commands | `EditCommands.mm`, `AdvancedEditCommands.mm`, `TypingCommands.mm`, `EncodingCommands.mm`, `CharsetDetection.mm`, `TagMatch.mm` |
| Panels and docking | `DockingManager.mm`, `NppPanel.mm`, `DocumentListPanel.mm`, `FunctionListPanel.mm`, `FunctionListCatalog.mm`, `ProjectPanel.mm`, `WorkspacePanel.mm`, `AuxPanels.mm` |
| Preferences, shortcuts, context menu | `SettingsCommands.mm` (NPP_PREF_* macros, defaults), `SettingsPanels.mm`, `ShortcutMapper.mm`, `ContextMenuFile.mm` |
| Localisation | `Localization.mm` (upstream `nativeLang/*.xml` by command id and by English text; the port's own texts from `resources/nativeLang-extra/`) |
| Plugin stand-ins | `JsonCommands.mm`, `CompareCommands.mm`, `XmlCommands.mm`, `FtpClient.mm`/`FtpCommands.mm`, `ScriptCommands.mm` (NppExec), `RunCommands.mm` |
| Tools menu | `ToolsCommands.mm` (digests, macros, window list), `CryptoTools.mm` (bcrypt, scrypt, Argon2 wrapper, PBKDF2, SHA-3, Base58/32, passwords), `HttpRequest.mm` (request, curl import/export, libcurl), `ToolsWindows.mm` (the windows, Auto Layout) |
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
    name; `.tex` as LaTeX or TeX by its head). At most 120 files per project per language. The
    train/held-out split is by project folder (Rosetta: by task).
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
- Current numbers (held-out, first choice right): whole files 92.3%, 40 lines 90.9%, 20 lines 89.4%,
  10 lines 86.7%, 5 lines 81.8%, quoting 61.3%.
