# Scintilla's own tests, on macOS

`scintilla/test/simpleTests.py` and `performanceTests.py` say in their README that
they run on Windows only. That is true of their harness, not of the tests: they
drive Scintilla through the direct-call interface, `fn(ptr, message, wParam,
lParam)`, which is the same everywhere. What is Windows is `XiteWin.py`, which
makes a window with the Win32 API and asks it for that pointer.

`XiteWin.py` here provides the same interface from a Scintilla living in an
off-screen Cocoa window, inside `libscintillahost.dylib`. The test files are used
exactly as they ship -- `run.sh` copies them in and removes them afterwards.

    ./macos/test-scintilla/run.sh

250 tests run. Four do not pass, and none of them is a fault in this port:

  - `testLineEnds` passes on its own and fails in a full run. The tests share one
    Scintilla and `setUp` does not put the end-of-line mode back, so it inherits
    whatever the test before it left. On Windows this goes unnoticed, because the
    value it inherits is the one the test expects there.

  - `testLineScroll` expects the horizontal offset to be an exact multiple of the
    character width. The default font here is 6.6 points wide, so scrolling eight
    characters gives 52.8 and the offset, being an integer, is 53.

  - `testCopySeparator` and `testMultipleCopy` fail on their own as well. They
    are right to: `SCI_SETCOPYSEPARATOR` does nothing in this Scintilla.
    Editor.cxx picks `pdoc->EOLString()` whenever there is more than one
    selection and the separator only when there is one -- and with one selection
    nothing is ever appended, so the separator is unreachable. Nothing in this
    port uses it, and Notepad++ carries the same Scintilla, so it is left alone
    and written down here.

The nine performance tests all pass.
