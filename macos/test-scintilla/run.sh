#!/bin/bash
# Runs Scintilla's own Python tests on macOS.
#
# They are written against the direct-call interface, which is the same on every
# platform; only their harness is Windows. XiteWin.py here stands in for it, so
# the test files themselves are used exactly as they ship -- they are copied in
# at run time and removed again, never edited.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCI="$(cd "$HERE/../.." && pwd)/scintilla"
cd "$HERE" || exit 1

if [ ! -f libscintillahost.dylib ] || [ ScintillaHost.mm -nt libscintillahost.dylib ]; then
    echo "==> собираю хост"
    clang++ -std=c++17 -DNDEBUG -DSCI_LEXER -O2 -fPIC -fobjc-arc \
        -I"$SCI/include" -I"$SCI/src" -I"$SCI/cocoa" -I"$HERE/../../lexilla/include" \
        -dynamiclib ScintillaHost.mm \
        "$HERE/../build/libscintilla-cocoa.a" "$HERE/../../lexilla/bin/liblexilla.a" \
        -framework Cocoa -framework QuartzCore -o libscintillahost.dylib || exit 1
fi

cp "$SCI/test/simpleTests.py" "$SCI/test/performanceTests.py" .
trap 'rm -f "$HERE/simpleTests.py" "$HERE/performanceTests.py"' EXIT

status=0
echo "==> simpleTests"
python3 simpleTests.py 2>&1 | grep -vE 'cursor is invalid' | tail -12 || status=1
echo "==> performanceTests"
python3 performanceTests.py 2>&1 | grep -vE 'cursor is invalid' | tail -14 || status=1
exit $status
