#!/bin/bash
# Build NotepadMac.app on macOS: Lexilla + Scintilla core + Scintilla/Cocoa,
# then the editor itself, bundled with Notepad++'s own language and style data.
#
# Requires only Xcode Command Line Tools (no full Xcode, no Qt).
#
#   ./macos/build.sh              universal (arm64 + x86_64)
#   NPPMAC_ARCH=native ./macos/build.sh   host architecture only, ~2x faster
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCI="$ROOT/scintilla"
LEX="$ROOT/lexilla"
SRC="$ROOT/macos/app"
OUT="$ROOT/macos/build"

if [ "${NPPMAC_ARCH:-universal}" = "native" ]; then
    ARCHS=()
else
    ARCHS=(-arch arm64 -arch x86_64)
fi

CXXFLAGS=(-std=c++17 -DNDEBUG -DSCI_LEXER -O2 -fPIC -Wno-deprecated-declarations ${ARCHS[@]+"${ARCHS[@]}"})
INCLUDES=(-I"$SCI/include" -I"$SCI/src" -I"$SCI/cocoa" -I"$LEX/include" -I"$SRC" -I"$ROOT/macos/third_party/compareplus/shim" -I"$ROOT/macos/third_party/compareplus/Engine"
          -I"$ROOT/PowerEditor/src/uchardet"
          -I"$ROOT/macos/third_party/argon2"
          -I"$ROOT/macos/third_party/cmark"
          -I"$(xcrun --show-sdk-path)/usr/include/libxml2")

# Objects built for one set of architectures must not serve another, so the
# object directory is named after it. Headers are not tracked: after editing
# one under scintilla/, remove macos/build/obj-* to rebuild.
OBJ="$OUT/obj-${NPPMAC_ARCH:-universal}"
mkdir -p "$OBJ"

echo "==> Lexilla"
make -C "$LEX/src" -j"$(sysctl -n hw.ncpu)" >/dev/null

echo "==> Scintilla core"
for f in "$SCI"/src/*.cxx; do
    o="$OBJ/$(basename "${f%.cxx}").o"
    # Scintilla does not change from one build of the editor to the next.
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && continue
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -c "$f" -o "$o"
done

echo "==> Scintilla Cocoa layer"
for f in PlatCocoa ScintillaCocoa ScintillaView InfoBar; do
    o="$OBJ/$f.o"
    [ "$o" -nt "$SCI/cocoa/$f.mm" ] && [ "$o" -nt "$0" ] && continue
    clang++ "${CXXFLAGS[@]}" "${INCLUDES[@]}" -fobjc-arc -c "$SCI/cocoa/$f.mm" -o "$o"
done

echo "==> uchardet"
UCHARDET="$ROOT/PowerEditor/src/uchardet"
UCOBJ="$OUT/uchardet-${NPPMAC_ARCH:-universal}"
mkdir -p "$UCOBJ"
for f in "$UCHARDET"/*.cpp; do
    o="$UCOBJ/$(basename "${f%.cpp}").o"
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && continue
    clang++ -std=c++17 -DNDEBUG -O2 -fPIC -w ${ARCHS[@]+"${ARCHS[@]}"} -I "$UCHARDET" -c "$f" -o "$o"
done

# Argon2's reference implementation (macos/third_party/argon2, CC0), for
# Tools > Hashes. Lanes are worked through one after another: the answer is the
# same, and a hash made from a dialog has no need of threads.
ARGON2="$ROOT/macos/third_party/argon2"
A2OBJ="$OUT/argon2obj-${NPPMAC_ARCH:-universal}"
mkdir -p "$A2OBJ"
for f in "$ARGON2"/*.c "$ARGON2"/blake2/*.c; do
    o="$A2OBJ/$(basename "${f%.c}").o"
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && continue
    clang -std=c99 -DNDEBUG -DARGON2_NO_THREADS -O2 -w ${ARCHS[@]+"${ARCHS[@]}"} -I "$ARGON2" -c "$f" -o "$o"
done

# cmark, CommonMark's reference implementation (macos/third_party/cmark,
# BSD-2; 0.31.2), renders Markdown for the preview panel.
CMARK="$ROOT/macos/third_party/cmark"
CMOBJ="$OUT/cmarkobj-${NPPMAC_ARCH:-universal}"
mkdir -p "$CMOBJ"
for f in "$CMARK"/*.c; do
    o="$CMOBJ/$(basename "${f%.c}").o"
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && continue
    clang -std=c99 -DNDEBUG -O2 -w ${ARCHS[@]+"${ARCHS[@]}"} -I "$CMARK" -c "$f" -o "$o"
done

# ComparePlus's engine (macos/third_party/compareplus, GPL): the diff
# algorithms, moved lines, sub-line differences and alignment behind Compare,
# with the shims that stand in for Win32, Boost.Regex and Notepad++. C++20,
# as the engine is written.
CPLUS="$ROOT/macos/third_party/compareplus"
CPOBJ="$OUT/compareplusobj-${NPPMAC_ARCH:-universal}"
mkdir -p "$CPOBJ"
for f in "$CPLUS"/Engine/Engine.cpp "$CPLUS"/shim/NppHelpers.cpp; do
    o="$CPOBJ/$(basename "${f%.cpp}").o"
    [ "$o" -nt "$f" ] && [ "$o" -nt "$0" ] && [ "$o" -nt "$CPLUS/shim/NppHelpers.h" ] && continue
    clang++ -std=c++20 -DNDEBUG -O2 -fPIC -w ${ARCHS[@]+"${ARCHS[@]}"} -I "$CPLUS/shim" -I "$CPLUS/Engine" -I "$SCI/include" -c "$f" -o "$o"
done

echo "==> libscintilla-cocoa.a"
libtool -static -o "$OUT/libscintilla-cocoa.a" "$OBJ"/*.o 2>/dev/null

echo "==> NotepadMac"
# Objects per architecture set; a source is recompiled only when it, or a
# header it includes (as clang recorded in its .d file), is newer than its
# object, or the build script itself changed. Every .mm in macos/app is part
# of the application: there is no list to forget a new file in.
APPOBJ="$OUT/appobj-${NPPMAC_ARCH:-universal}"
mkdir -p "$APPOBJ"
SOURCES=()
for f in "$SRC"/*.mm; do SOURCES+=("$(basename "${f%.mm}")"); done

needs_build() {
    local name="$1" o="$APPOBJ/$1.o" d="$APPOBJ/$1.d"
    [ -f "$o" ] && [ -f "$d" ] || return 0
    [ "$0" -nt "$o" ] && return 0
    local dep
    for dep in $(sed -e 's/^[^:]*://' -e 's/\\$//' "$d"); do
        [ -e "$dep" ] || return 0
        [ "$dep" -nt "$o" ] && return 0
    done
    return 1
}

STALE=()
for f in "${SOURCES[@]}"; do needs_build "$f" && STALE+=("$f"); done
# Objects of sources that no longer exist are dropped, so they are not linked.
for o in "$APPOBJ"/*.o; do
    [ -e "$o" ] || continue
    [ -f "$SRC/$(basename "${o%.o}").mm" ] || rm -f "$o" "${o%.o}.d"
done
echo "    ${#STALE[@]} of ${#SOURCES[@]} sources to compile"
if [ ${#STALE[@]} -gt 0 ]; then
    export CXXFLAGS_STR="${CXXFLAGS[*]}" INCLUDES_STR="${INCLUDES[*]}" SRC APPOBJ
    printf '%s\n' "${STALE[@]}" | xargs -P "$(sysctl -n hw.ncpu)" -I{} sh -c '
        clang++ $CXXFLAGS_STR $INCLUDES_STR -fobjc-arc -MMD -MF "$APPOBJ/{}.d" \
            -c "$SRC/{}.mm" -o "$APPOBJ/{}.o" || { rm -f "$APPOBJ/{}.o"; exit 255; }'
fi
clang++ -std=c++17 -fobjc-arc -O2 ${ARCHS[@]+"${ARCHS[@]}"} "$APPOBJ"/*.o "$UCOBJ"/*.o "$A2OBJ"/*.o "$CMOBJ"/*.o "$CPOBJ"/*.o \
    "$OUT/libscintilla-cocoa.a" "$LEX/bin/liblexilla.a" \
    -framework Cocoa -framework QuartzCore -framework Security -framework WebKit -framework Vision -framework CoreImage -lcurl -lxml2 -lz \
    -o "$OUT/NotepadMac"

echo "==> NotepadMac.app"
APP="$OUT/NotepadMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/NotepadMac" "$APP/Contents/MacOS/NotepadMac"
cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
# The versions Debug Info reports, as upstream's About box has them.
NPP_VERSION=$(sed -n 's/.*define NOTEPAD_PLUS_VERSION L"Notepad++ v\([0-9.]*\)".*/\1/p' "$ROOT/PowerEditor/src/resource.h")
for pair in "NppUpstreamVersion:$NPP_VERSION" "NppScintillaVersion:$(cat "$SCI/version.txt")" \
            "NppLexillaVersion:$(cat "$LEX/version.txt")" "NppBuildTime:$(LC_ALL=C date '+%b %e %Y - %H:%M:%S')"; do
    /usr/libexec/PlistBuddy -c "Add :${pair%%:*} string '${pair#*:}'" "$APP/Contents/Info.plist" >/dev/null
done
# The application icon: the Windows icon on a Mac tile with a ⌘ badge (macos/make_icon.m makes it).
cp "$ROOT/macos/resources/AppIcon.icns" "$APP/Contents/Resources/"
# The About box's chameleon, light and dark, as upstream's resources have it.
cp "$ROOT/PowerEditor/src/icons/standard/about/chameleon.ico" "$APP/Contents/Resources/chameleon.ico"
cp "$ROOT/PowerEditor/src/icons/dark/about/chameleon.ico" "$APP/Contents/Resources/chameleon_dm.ico"
# Notepad++'s own language and colour definitions, read at runtime.
cp "$ROOT/PowerEditor/src/langs.model.xml"   "$APP/Contents/Resources/"
cp "$ROOT/PowerEditor/src/stylers.model.xml" "$APP/Contents/Resources/"
# read back by the coverage meta-test in the built-in suite
cp "$ROOT/macos/implemented.txt"            "$APP/Contents/Resources/"
cp "$ROOT/macos/resources/encoding-reference.txt" "$APP/Contents/Resources/"
# Upstream's default context menu (gen_context_menu.py), which a new settings folder starts with.
cp "$ROOT/macos/resources/contextMenu.xml" "$APP/Contents/Resources/"
# The trained language model, fitted offline by macos/train-language-model.py.
cp "$ROOT/macos/resources/language-model.bin"    "$APP/Contents/Resources/"
# The FTP tests need a server to talk to; this one exists only for them.
cp "$ROOT/macos/test-ftp-server.py"         "$APP/Contents/Resources/"
cp "$ROOT/macos/test-http-server.py"        "$APP/Contents/Resources/"
# Notepad++'s own colour themes; the Style Configurator and Preferences list these.
mkdir -p "$APP/Contents/Resources/themes"
cp "$ROOT"/PowerEditor/installer/themes/*.xml "$APP/Contents/Resources/themes/"
# Notepad++'s own function-list parsers, read by the Function List panel.
mkdir -p "$APP/Contents/Resources/toolbar/light" "$APP/Contents/Resources/toolbar/dark"
cp "$ROOT"/macos/resources/toolbar/order.txt        "$APP/Contents/Resources/toolbar/"
cp "$ROOT"/macos/resources/toolbar/light/*.png      "$APP/Contents/Resources/toolbar/light/"
cp "$ROOT"/macos/resources/toolbar/dark/*.png       "$APP/Contents/Resources/toolbar/dark/"
for set in light-filled dark-filled; do
    mkdir -p "$APP/Contents/Resources/toolbar/$set"
    cp "$ROOT"/macos/resources/toolbar/$set/*.png "$APP/Contents/Resources/toolbar/$set/"
done

# The user languages Notepad++ ships (Markdown, light and dark).
mkdir -p "$APP/Contents/Resources/userDefineLangs"
cp "$ROOT"/PowerEditor/bin/userDefineLangs/*.xml "$APP/Contents/Resources/userDefineLangs/"
# Notepad++'s translations, read by Localization.mm.
mkdir -p "$APP/Contents/Resources/nativeLang"
cp "$ROOT"/PowerEditor/installer/nativeLang/*.xml "$APP/Contents/Resources/nativeLang/"
# What the port says and Windows does not, in the languages someone has written it in.
mkdir -p "$APP/Contents/Resources/nativeLang-extra"
cp "$ROOT"/macos/resources/nativeLang-extra/*.xml "$APP/Contents/Resources/nativeLang-extra/" 2>/dev/null || true

mkdir -p "$APP/Contents/Resources/APIs"
cp "$ROOT"/PowerEditor/installer/APIs/*.xml "$APP/Contents/Resources/APIs/"

mkdir -p "$APP/Contents/Resources/functionList"
cp "$ROOT"/PowerEditor/installer/functionList/*.xml "$APP/Contents/Resources/functionList/"

mkdir -p "$APP/Contents/Resources/urlCorpus"
cp "$ROOT"/macos/resources/url-corpus/* "$APP/Contents/Resources/urlCorpus/"

mkdir -p "$APP/Contents/Resources/functionListCorpus"
cp -R "$ROOT"/macos/resources/functionList-corpus/* "$APP/Contents/Resources/functionListCorpus/"

mkdir -p "$APP/Contents/Resources/functionListCorrections"
cp "$ROOT"/macos/resources/functionList-corrections/*.xml "$APP/Contents/Resources/functionListCorrections/"
# The command-line tool, into Contents/Helpers as editors keep theirs.
mkdir -p "$APP/Contents/Helpers"
clang -fobjc-arc -O2 ${ARCHS[@]+"${ARCHS[@]}"} -framework Cocoa \
    "$ROOT/macos/cli/nppmac.m" -o "$APP/Contents/Helpers/nppmac"
# Nested code first, then the bundle: inside out, without the deprecated --deep.
codesign --force --sign - "$APP/Contents/Helpers/nppmac" 2>/dev/null
codesign --force --sign - "$APP" 2>/dev/null

echo
echo "Built: $APP"
echo "Run:   open $APP"
echo "Test:  NPPMAC_TEST=1 $APP/Contents/MacOS/NotepadMac"
