# Notepad++ for macOS

A native macOS port of Notepad++: the same
editing engine (Scintilla), the same syntax highlighting (Lexilla), the same
language, colour, theme, function-list and translation files as the Windows
version - in a Cocoa application that runs on Apple silicon and Intel Macs.
No Wine, no emulation, no Windows code.

![NotepadMac editing an Objective-C++ source file: syntax highlighting, line numbers and code folding, dark theme](docs/screenshot-editor.png)

> An independent, unofficial port. It is not made, released or supported by the
> Notepad++ project: **questions, bug reports and requests about the Mac version
> belong in the Issues and Discussions of this repository**, not upstream's
> forum, site or e-mail. Releases of the Mac version are made and signed here.
> Same licence as Notepad++: GPL.

## What you get

**All 579 commands of the Windows menus** are implemented (the list is generated
from the Windows menu resource, see [macos/FEATURES.md](macos/FEATURES.md)), and they behave
the way they do on Windows - the port is written against Notepad++'s own sources.

**Editing**
- Tabs, two views side by side (move or clone a document to the other view), drag and pin tabs, tab colours.
- Multi-selection and column mode, Column Editor, Begin/End Select, line operations (sort seven ways, remove duplicates, join, split, move), case conversions, trim and tab/space conversion, comment toggling, date/time insertion.
- Auto-completion of words, functions and paths with parameter hints; auto-close of brackets, quotes and HTML tags; smart highlighting; brace and XML-tag matching.
- Bookmarks with line operations, five mark styles, Change History, code folding, hidden lines.
- Macros: record, play, run many times, save with a shortcut - including menu commands and searches, in the Windows `shortcuts.xml` format.
- Clipboard History, Character Panel, paste as HTML / RTF / binary.

**Languages**
- Syntax highlighting and folding for about 90 languages, from Notepad++'s own `langs.model.xml` and `stylers.model.xml`; all upstream themes; the Style Configurator.
- User Defined Languages: the full editor, and UDL files from Windows work as they are.
- Function List for every language upstream has a parser for (run with PCRE2, as written), Document Map, Document List, Folder as Workspace, Project panels - dockable, floatable, remembered.
- **The language of a text is worked out from its contents** when its name says nothing - a file without an extension, a snippet pasted into an empty tab - by a small model trained on real code, which offers one language or a short list.

**Search**
- Find, Replace, Find in Files, Find in Projects, Mark, incremental search, with Notepad++'s regular-expression syntax (Boost), the results panel with folding and navigation, search-result colours.

**Files and encodings**
- UTF-8/16 with and without BOM, ANSI, all 46 of Notepad++'s character sets as "Encode in" and "Convert to", encoding detection, EOL conversion.
- Sessions, periodic backup and snapshot of unsaved documents, file-change monitoring (tail -f), large-file handling, read-only, print.
- `session.xml`, `shortcuts.xml`, `contextMenu.xml`, UDL and theme files are read and written in the Windows formats, so a settings folder can be carried over.

**Tools**
- **Hashes**: MD5, SHA-1, SHA-256, SHA-512 as upstream, plus SHA-224, SHA-384, SHA3-256, SHA3-512, BLAKE2b, CRC-32 and an optional HMAC key; **bcrypt, scrypt, Argon2 and PBKDF2** with their settings, salts, and a verifier. Each: of a text (or each line), of files, of the selection into the clipboard.
- **Base**: Base64 (and URL-safe), Base58 (and Base58Check), Base32 - from text or bytes in hexadecimal, and back to both.
- **Password Generator**: length, character sets, look-alikes excluded, entropy shown, drawn from the system's secure random generator without bias; optionally the hash of each password.
- **HTTP Request**: method, address, parameters, headers, body, Basic authentication, redirects, timeout; the answer's status, headers and body (JSON laid out), opened as a document if wanted; **Paste curl Command** and **Copy as curl**.

**Built in instead of plugins** (Windows plugins are Windows binaries and cannot load)
- JSON: format, compact, sort keys, validate, tree.
- Compare: two files side by side with differences marked and navigation.
- XML tools: pretty print, linearize, validate (DTD/XSD), XPath, XSLT.
- FTP/FTPS client panel.
- NppExec-compatible scripting: a console, scripts, variables, its commands.
- MIME Tools: Base64 (all seven variants of the plugin), Quoted-printable, URL encoding, SAML decode.

**Plugins of your own**: native plugins load from the plugins folder the way they do
on Windows — a small C interface, Scintilla messages and all. See
[macos/plugin-sdk](macos/plugin-sdk/README.md).

**Interface**
- The interface in any of Notepad++'s ~90 translations, chosen in Preferences; what only the Mac version says is translated too.
- Preferences with Notepad++'s pages and wording, Shortcut Mapper (menu, macro, run and Scintilla commands, conflicts shown), editable context menu, toolbar with upstream's icon sets, dark mode.
- Mac conventions where Windows ones make no sense: Finder and Terminal for Explorer and cmd, the Trash for the Recycle Bin, ⌘ shortcuts.

## Differences from the Windows version

- **Windows plugins (`.dll`) do not run** and cannot: they are Windows binaries. The most used
  ones are built in instead (JSON, Compare, XML tools, FTP, NppExec scripting, MIME Tools), and
  native Mac plugins can be written against [macos/plugin-sdk](macos/plugin-sdk/README.md);
  Plugins Admin is absent.
- Mac conventions replace Windows ones: Finder and Terminal instead of Explorer and cmd, the Trash
  instead of the Recycle Bin, the system menu bar and dark appearance, ⌘ shortcuts.
- Settings that only make sense on Windows are left out (tray icon, DirectWrite modes, hiding the
  menu bar, custom dark-mode tones).
- Docked panels can be moved between four sides, tabbed and floated, but not nested as freely as on Windows.
- Texts that only the Mac version has are translated by machine and not yet reviewed by native speakers.

## Install

With [Homebrew](https://brew.sh):

```
brew install --cask tanderbold/tap/notepadmac
```

Or download the `.dmg` from this repository's **Releases** page (or, for the very latest
build, from the newest successful run of the *macOS* workflow: Actions tab → run →
Artifacts), open it and drag **NotepadMac** to Applications.
Requires macOS 11 or later; one build runs on Apple silicon and Intel.

Releases are signed and notarised. Builds taken straight from CI are not, so for those,
the first time: right-click the app → **Open** → **Open** (or System Settings → Privacy &
Security → *Open Anyway*).

Settings live in `~/Library/Application Support/NotepadMac/` and in the
`org.notepad-plus-plus.mac` preferences domain.

## Build it yourself

Only Apple's Command Line Tools are needed (`xcode-select --install`) - no Xcode
project, no Homebrew packages.

```
git clone <this repository> NotepadMac && cd NotepadMac
bash macos/build.sh                          # universal app in macos/build/NotepadMac.app
NPPMAC_ARCH=native bash macos/build.sh       # this Mac's architecture only, about twice as fast
bash macos/test.sh                           # the test suite (runs inside the real application)
bash macos/package.sh                        # macos/build/*.dmg
open macos/build/NotepadMac.app
```

To sign and notarise a release, set `NPPMAC_SIGN_IDENTITY="Developer ID Application: … (TEAMID)"`
and `NPPMAC_NOTARY_PROFILE=<profile made with xcrun notarytool store-credentials>` before
`package.sh`.

## How it is made

- Upstream's `scintilla/` and `lexilla/` are compiled unchanged (one portability fix in `LexUser.cxx`);
  `PowerEditor/` is not compiled at all - it is the specification the Mac code is written against,
  and the source of the data files and generated tables.
- The Mac application is about 40,000 lines of Objective-C++ in `macos/app/`.
- A suite of almost 800 checks runs inside the real application on every push (GitHub Actions,
  macOS runner): every menu command, file formats against files written on Windows, encodings,
  regular expressions, cryptography against published vectors, the HTTP and FTP clients against
  local servers, the interface in another language with no text cut off.
- [AGENTS.md](AGENTS.md) is the technical briefing - how to build, test and find one's way in
  the code, and how the language-detection model is trained. It is written for AI coding agents
  and reads just as well for people.

## Questions, bugs, contributing

Use this repository's **Issues** for bugs and requests and **Discussions** for questions.
Please do not take problems with the Mac version to the Notepad++ project - they did not
make it and cannot fix it.

Bug reports with a file or steps that show a difference from Windows Notepad++ are the most
useful kind. Translations of the Mac-only texts are machine-made and need native speakers:
see `macos/resources/nativeLang-extra/README.md`. Code changes come with a test in
`macos/app/Tests.mm` and keep `bash macos/test.sh` at `0 failed`.

## Credits and licence

This port stands on other people's work, used under their licences and gratefully acknowledged:
Notepad++ by Don Ho and its contributors (GPL) - the design, the data files, the translations and
the behaviour this application follows; Scintilla and Lexilla by Neil Hodgson and contributors;
uchardet; the Argon2 reference implementation (CC0). "Notepad++" is the name of the original
Windows application; the Mac application is called NotepadMac. Everything in `macos/` is
licensed under the GPL, like Notepad++ itself (see `LICENSE`).

`PowerEditor/`, `scintilla/`, `lexilla/` and `boostregex/` are a snapshot of upstream Notepad++,
kept as the sources the application is built from and the reference it is written against;
[UPSTREAM.md](UPSTREAM.md) says which version and what was changed.
