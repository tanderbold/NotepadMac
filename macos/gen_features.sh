#!/bin/bash
# Regenerate macos/FEATURES.md: every Notepad++ menu command, with what the
# macOS build implements so far. The command list is parsed from the Windows
# menu resource, so it cannot drift from upstream.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/macos/gen_features.py" "$ROOT"
