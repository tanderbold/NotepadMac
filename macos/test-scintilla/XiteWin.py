# -*- coding: utf-8 -*-
"""Stands in for Scintilla's own XiteWin so its tests can run on macOS.

Scintilla's simpleTests.py and performanceTests.py are written against the
direct-call interface, fn(ptr, msg, wparam, lparam), which is the same
everywhere. Only the harness around it is Windows: XiteWin creates a window with
the Win32 API and asks it for that pointer.

This module gets the same pointer from a Scintilla living in an off-screen
Cocoa window, inside libscintillahost.dylib, and presents the interface the
tests expect. The tests themselves are used unchanged.
"""

import ctypes
import os
import sys

from ctypes import c_char_p, c_int, c_ssize_t, c_void_p

HERE = os.path.dirname(os.path.abspath(__file__))
SCINTILLA = os.path.normpath(os.path.join(HERE, "..", "..", "scintilla"))
LEXILLA = os.path.normpath(os.path.join(HERE, "..", "..", "lexilla"))

sys.path.insert(0, os.path.join(SCINTILLA, "test"))
sys.path.insert(0, os.path.join(SCINTILLA, "scripts"))

import Face
import ScintillaCallable

# Lexilla is linked into the host, so the lexer tests can run.
lexillaAvailable = True
scintillaIncludesLexers = False

_host = ctypes.CDLL(os.path.join(HERE, "libscintillahost.dylib"))
_host.NppTestScintillaCreate.restype = c_void_p
_host.NppTestScintillaDirectFunction.argtypes = [c_void_p]
_host.NppTestScintillaDirectFunction.restype = c_void_p
_host.NppTestScintillaDirectPointer.argtypes = [c_void_p]
_host.NppTestScintillaDirectPointer.restype = c_void_p
_host.NppTestCreateLexer.argtypes = [c_char_p]
_host.NppTestCreateLexer.restype = c_void_p

class XiteFrame:
    def __init__(self):
        instance = _host.NppTestScintillaCreate()
        face = Face.Face()
        face.ReadFromFile(os.path.join(SCINTILLA, "include", "Scintilla.iface"))
        # The lexer constants live in Lexilla's own interface file, and the
        # tests expect both sets to be present.
        lexFace = Face.Face()
        lexFace.ReadFromFile(os.path.join(LEXILLA, "include", "LexicalStyles.iface"))
        face.features.update(lexFace.features)
        self.face = face

        # ScintillaCallable wraps the address itself, so it is handed the plain
        # integer -- wrapping it here as well makes a pointer out of a pointer.
        function = _host.NppTestScintillaDirectFunction(instance)
        pointer = c_char_p(_host.NppTestScintillaDirectPointer(instance))
        self.ed = ScintillaCallable.ScintillaCallable(face, function, pointer)

    def ChooseLexer(self, lexer):
        """Sets the lexer by name. The tests pass the name as bytes, which is
        what Lexilla's loader takes."""
        if isinstance(lexer, str):
            lexer = lexer.encode("utf-8")
        self.ed.SetILexer(0, _host.NppTestCreateLexer(lexer))

    def DoEvents(self):
        _host.NppTestDoEvents()


xiteFrame = XiteFrame()


def main(test):
    """The tests call this with their own module name to run themselves."""
    import importlib
    import unittest

    module = sys.modules.get("__main__")
    if module is None or not getattr(module, "__file__", "").endswith(test + ".py"):
        module = importlib.import_module(test)

    runner = unittest.TextTestRunner(verbosity=1)
    result = runner.run(unittest.defaultTestLoader.loadTestsFromModule(module))
    if not result.wasSuccessful():
        sys.exit(1)
    return {}
