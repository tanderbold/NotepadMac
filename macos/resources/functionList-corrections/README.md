# Corrections to the Notepad++ function-list parsers

These files are in exactly the format of `PowerEditor/installer/functionList`,
and are loaded after it. A parser here replaces the upstream one with the same
`id`.

Nothing is here for the sake of being different. Each file corrects a parser
that does not find declarations it plainly should, and each says at the top what
it changes and what the original did. A language whose upstream parser is
correct has no file here.
