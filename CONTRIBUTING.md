# Contributing to the macOS port

This repository is the macOS port of Notepad++ (see `README.md`). Changes to the Windows version
belong upstream, in the Notepad++ project, not here.

- **Bugs and requests**: this repository's Issues. The most useful report shows a difference from
  Windows Notepad++: the file or the steps, what Windows does, what the Mac version does.
- **Questions**: this repository's Discussions.
- **Translations** of the texts only the Mac version has are machine-made and need native speakers:
  `macos/resources/nativeLang-extra/README.md` says how; `python3 macos/check_nativelang_extra.py` checks a file.
- **Code**: read `AGENTS.md` (it is written for coding agents, and is just as true for people): Windows
  Notepad++'s source is the specification, every change comes with a test in `macos/app/Tests.mm`,
  and `bash macos/test.sh` must end with `0 failed`. One commit per piece of work, titled
  `macos: <what is now true>`.
