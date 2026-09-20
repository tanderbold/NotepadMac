# Upstream sources in this repository

`PowerEditor/`, `scintilla/`, `lexilla/`, `boostregex/` and `LICENSE` are a snapshot of
[Notepad++](https://github.com/notepad-plus-plus/notepad-plus-plus), copyright Don Ho and the
Notepad++ contributors (Scintilla and Lexilla: Neil Hodgson and contributors), under their
licences, unchanged except where noted below.

| Snapshot | Notepad++ v8.9.8 + 14 commits (upstream commit `2f50e44ff`, 2026-09-08) |
|---|---|

They are here because the Mac application is built from Scintilla and Lexilla, reads Notepad++'s
data files (languages, styles, themes, function lists, translations) and is written against
`PowerEditor/src` as its specification. Upstream's own README, Windows build instructions, CI
configuration and release key are left out: they describe and sign the Windows version.

Changed from upstream: `lexilla/lexers/LexUser.cxx`, the one file that kept Lexilla from building
on macOS - `#include <windows.h>` is now inside `#ifdef _WIN32` (nothing in the file needs it), and
the MSVC-only `_itoa()` is replaced by `snprintf()` at its ten call sites, byte for byte the same result.

To move to a newer Notepad++: replace these folders with the new release's, re-apply the
`LexUser.cxx` fixes if upstream has not taken them, rerun the generators (`macos/gen_*`), run the
suite, and record the new snapshot here - as one commit titled `upstream: Notepad++ vX.Y.Z`.
