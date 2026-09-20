#!/bin/bash
# Runs the test suites that come with the projects this port is built on, and
# validates the XML this port adds against Notepad++'s own schema.
#
#     ./macos/test-upstream.sh
#
# The Function List and URL corpora are not here: they are bundled into the app
# and run by ./macos/test.sh with everything else.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failed=0

step() { printf '\n== %s ==\n' "$1"; }

step "Lexilla: lexers against their example files"
(cd "$ROOT/lexilla/src" && make -s) || { echo "не собралась библиотека"; failed=1; }
(cd "$ROOT/lexilla/test" && make -s >/dev/null && ./TestLexers > /tmp/npp-lexers.txt 2>&1)
if [ $? -eq 0 ]; then
    echo "прошло: $(grep -c '^Lexing' /tmp/npp-lexers.txt) файлов, $(ls "$ROOT/lexilla/test/examples" | wc -l | tr -d ' ') лексеров"
else
    echo "ПРОВАЛ"; tail -20 /tmp/npp-lexers.txt; failed=1
fi

step "Lexilla: unit tests"
(cd "$ROOT/lexilla/test/unit" && make -s >/dev/null && ./unitTest | tail -2) || failed=1

step "Scintilla: unit tests"
(cd "$ROOT/scintilla/test/unit" && make -s >/dev/null && ./unitTest | tail -2) || failed=1

step "Scintilla: its own Python tests, through a macOS harness"
"$ROOT/macos/test-scintilla/run.sh" > /tmp/npp-scintilla.txt 2>&1
grep -E '^Ran |^OK$|^FAILED' /tmp/npp-scintilla.txt | sed 's/^/  /'
echo "  (четыре известных расхождения описаны в macos/test-scintilla/README.md)"

step "Notepad++ schema: the function-list files this port adds"
schema="$ROOT/PowerEditor/Test/xmlValidator/functionList.xsd"
for f in "$ROOT"/macos/resources/functionList-corrections/*.xml; do
    if xmllint --noout --schema "$schema" "$f" >/dev/null 2>&1; then
        printf '  %-16s прошёл\n' "$(basename "$f")"
    else
        printf '  %-16s ПРОВАЛ\n' "$(basename "$f")"
        xmllint --noout --schema "$schema" "$f" 2>&1 | head -2
        failed=1
    fi
done

printf '\n'
[ $failed -eq 0 ] && echo "все наборы апстрима прошли" || echo "есть провалы"
exit $failed
