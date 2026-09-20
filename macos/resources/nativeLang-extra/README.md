# nativeLang-extra

Translations of what the macOS port says and Windows Notepad++ does not: the
JSON, Compare, XML, FTP and NppExec menus, the port's own settings, the
update check, its messages. `english.xml` is the list of those texts; every
other file translates them for the nativeLang file of the same name in
`PowerEditor/installer/nativeLang`, and is loaded together with it.

    <Item english="Show Console" text="Показать консоль"/>

- `english` is the text exactly as the port has it. Do not change it.
- `text` is what is shown. An `Item` that is left out stays English, which is
  better than a guess.
- Keep a trailing `…`, the `<…>` of `<temporary script>`, and names as they
  are: NotepadMac, Notepad++, NppExec, JSON, XML, DTD, XPath, XSL, FTP, Finder, Cmd.
- Use the words the language's own nativeLang file already uses (its words
  for Compare, Folder, Bookmark, Match case and so on).

`python3 macos/check_nativelang_extra.py [file …]` checks the files.
