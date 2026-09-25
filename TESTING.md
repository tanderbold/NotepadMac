# Help test NotepadMac

NotepadMac follows Notepad++ on Windows closely, and about 2,500 automated checks run on every
change - but nothing replaces people using it on their own files. If you use Notepad++ on
Windows, or used to, you are exactly who can tell where the Mac version differs.

## Install

`brew install --cask tanderbold/tap/notepadmac`, or the `.dmg` from
[Releases](https://github.com/tanderbold/NotepadMac/releases). Your settings live in
`~/Library/Application Support/NotepadMac/`; to start clean, quit NotepadMac and move that
folder away.

## What is most useful to try

**Coming from Windows**
- Copy your Windows settings folder's `session.xml`, `shortcuts.xml`, `contextMenu.xml`,
  `userDefineLangs/` and themes into `~/Library/Application Support/NotepadMac/`. Do your User
  Defined Languages colour the same? Do your macros and shortcuts work? Does the session open?
- Do the things your hands do without thinking: the shortcuts you use most, column editing,
  macros, Find in Files with your usual regular expressions, Replace with `$1`.

**Your real files**
- The languages you work in: colouring, folding, the Function List, auto-completion.
- Files in other encodings (Windows-1251, Shift-JIS, UTF-16), Windows line endings, very large
  files, very long lines, logs you follow with View > Monitoring (tail -f).
- Text pasted into an empty tab or a file without an extension: is its language worked out?

**The Mac side**
- Two views side by side, docked and floating panels, a second screen, full screen, dark mode.
- The interface in your language (Preferences > General > Localization): anything cut off,
  wrongly translated or left in English? The texts only the Mac version has are machine
  translations - corrections from native speakers are especially welcome.
- The built-in plugins: Compare, Git, JSON, XML, FTP, NppExec scripting, Markdown Preview.
- `nppmac` from the Terminal (Tools > Install Command Line Tool), and an AI agent over MCP if you use one.

## Reporting what you find

Open an [issue](https://github.com/tanderbold/NotepadMac/issues/new/choose) - the form asks for
the version and the steps. The most useful reports say what Notepad++ on Windows does in the
same case, and come with a small made-up file that shows it (never a file with anything private
in it). Questions and ideas go to [Discussions](https://github.com/tanderbold/NotepadMac/discussions).
Please do not take Mac problems to the Notepad++ project: they did not make this port.

If NotepadMac crashes, macOS keeps a report in `~/Library/Logs/DiagnosticReports`
(`NotepadMac-*.ips`); attaching it helps a lot.
