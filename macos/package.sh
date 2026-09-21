#!/bin/bash
# Packages the built NotepadMac.app into a disk image for people without a
# toolchain. Signing and notarization happen when the credentials are there
# and are skipped, with a message, when they are not:
#
#   NPPMAC_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#       signs with the hardened runtime instead of ad hoc
#   NPPMAC_NOTARY_PROFILE=<keychain profile made by `xcrun notarytool store-credentials`>
#       submits the app and the image to Apple, waits, and staples both
#
#   ./macos/package.sh          after ./macos/build.sh
#
# The app that ships is a copy: the test servers (test-*.py, used only by the
# NPPMAC_TEST=1 suite) are removed from it, and it is signed inside out - the
# bundle has exactly one code object (no frameworks, no helpers), so that is a
# single codesign call on the app; --deep is deprecated and not needed. The
# app in macos/build/ keeps its scripts so the suite and CI still run.
# Notarizing the app itself (as a zip) lets the ticket be stapled to it, so a
# copy dragged out of the image opens on a Mac that is offline.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/macos/build"
APP="$OUT/NotepadMac.app"
[ -d "$APP" ] || { echo "No $APP; run macos/build.sh first." >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/NotepadMac-$VERSION.dmg"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/NotepadMac")
echo "==> NotepadMac $VERSION ($ARCHS)"
case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) ;;
    *) echo "    note: not universal; build without NPPMAC_ARCH=native for a release" ;; esac

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
SHIP="$STAGE/NotepadMac.app"
rm -f "$SHIP/Contents/Resources/"test-*.py   # test-suite servers, not for users

if [ -n "${NPPMAC_SIGN_IDENTITY:-}" ]; then
    echo "==> Signing as $NPPMAC_SIGN_IDENTITY"
    codesign --force --options runtime --timestamp \
             --sign "$NPPMAC_SIGN_IDENTITY" "$SHIP"
else
    echo "==> Ad hoc signature (set NPPMAC_SIGN_IDENTITY to sign for distribution)"
    codesign --force --sign - "$SHIP"
fi
codesign --verify --strict --verbose=2 "$SHIP"

if [ -n "${NPPMAC_NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing the app"
    ZIP="$STAGE/NotepadMac.zip"
    ditto -c -k --keepParent "$SHIP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NPPMAC_NOTARY_PROFILE" --wait
    rm -f "$ZIP"                                 # the zip is only a notarization envelope
    xcrun stapler staple "$SHIP"
    spctl --assess --type exec --verbose "$SHIP"
fi

echo "==> $DMG"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NotepadMac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${NPPMAC_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$NPPMAC_SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NPPMAC_NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing the image"
    xcrun notarytool submit "$DMG" --keychain-profile "$NPPMAC_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
    echo "==> Not notarized (set NPPMAC_NOTARY_PROFILE to notarize)"
fi
echo "Done: $DMG"
