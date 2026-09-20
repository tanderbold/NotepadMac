#!/bin/bash
# Regenerate macos/app/LangMap.h from Notepad++'s own language table.
#
# Source of truth: ScintillaEditView::_langNameInfoArray in
# PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp, which maps each
# Notepad++ language name to the Lexilla lexer ID it uses on Windows, plus the
# Language-menu command id (IDM_LANG_*) derived from the LangType enum and
# confirmed against the Windows menu resource.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/macos/gen_langmap.py" "$ROOT"
