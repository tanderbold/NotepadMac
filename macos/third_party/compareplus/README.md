# ComparePlus engine

`Engine/` and `Icons/` are taken unchanged from [ComparePlus](https://github.com/pnedev/comparePlus)
(commit 6611373, GPL v3, copyright Jean-Sebastien Leroy and Pavel Nedev - see LICENSE.txt):
the diff algorithms (Myers, histogram, mixed), the detection of moved lines and blocks,
the sub-line (word and character) differences, the alignment information, and the
margin symbols. NotepadMac's Compare is built on them, so what it shows is what the
plugin shows on Windows.

`shim/` is what stands in for the plugin's surroundings on macOS: the few Win32 calls the
engine makes (wide-string conversion, lower-casing, the message box), the progress dialog
(a cancel flag), Boost.Regex (the standard library's regex), Notepad++'s settings and helpers,
and `CallScintilla`, which reaches the two panes through Scintilla's direct-call function.
The engine is compiled as C++20 by `macos/build.sh`.
