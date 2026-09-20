#!/bin/bash
# Packages the built NotepadMac.app into a disk image for people without a
# toolchain. Signing and notarization happen when the credentials are there
# and are skipped, with a message, when they are not:
#
#   NPPMAC_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#       signs with the hardened runtime instead of ad hoc
#   NPPMAC_NOTARY_PROFILE=<keychain profile made by `xcrun notarytool store-credentials`>
#       submits the image to Apple, waits, and staples the ticket
#
#   ./macos/package.sh          after ./macos/build.sh
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

if [ -n "${NPPMAC_SIGN_IDENTITY:-}" ]; then
    echo "==> Signing as $NPPMAC_SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp \
             --sign "$NPPMAC_SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "==> Ad hoc signature (set NPPMAC_SIGN_IDENTITY to sign for distribution)"
    codesign --force --deep --sign - "$APP"
fi

echo "==> $DMG"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NotepadMac $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${NPPMAC_SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$NPPMAC_SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NPPMAC_NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NPPMAC_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
    echo "==> Not notarized (set NPPMAC_NOTARY_PROFILE to notarize)"
fi
echo "Done: $DMG"
