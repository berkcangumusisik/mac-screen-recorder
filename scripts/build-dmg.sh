#!/usr/bin/env bash
#
# Packages Snaplet.app into a disk image people can download, open and drag into
# Applications.
#
#   ./scripts/build-dmg.sh                       # ad hoc signed, this Mac only
#   SIGN_IDENTITY="Developer ID Application: …" \
#   DEVELOPMENT_TEAM=TEAMID ./scripts/build-dmg.sh
#
# Read the warning this prints at the end before sending the result to anyone.
set -euo pipefail

cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST_DIR="$(pwd)/dist"
APP="$DIST_DIR/Snaplet.app"

# Build unless a matching app is already sitting in dist/.
if [ ! -d "$APP" ] || [ "${REBUILD:-1}" = "1" ]; then
  SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/build-release.sh
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$DIST_DIR/Snaplet-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

echo "Staging disk image contents…"
cp -R "$APP" "$STAGING/Snaplet.app"
# The Applications symlink is what makes "drag to install" obvious.
ln -s /Applications "$STAGING/Applications"

# Give the mounted volume the app's own icon rather than the generic disk.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
fi

rm -f "$DMG"
echo "Creating $DMG…"
hdiutil create \
  -volname "Snaplet" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -quiet \
  "$DMG"

if [ "$SIGN_IDENTITY" != "-" ]; then
  echo "Signing the disk image…"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi

SIZE=$(du -h "$DMG" | cut -f1)
echo
echo "Built Snaplet $VERSION ($BUILD_NUMBER)"
echo "  dmg:    $DMG"
echo "  size:   $SIZE"
echo "  sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "Authority|Signature" | sed 's/^/  app: /'
echo

if [ "$SIGN_IDENTITY" = "-" ] || ! codesign --display --verbose=2 "$APP" 2>&1 | grep -q "Authority=Developer ID"; then
  cat <<'WARNING'
⚠️  This disk image will NOT open on anyone else's Mac.

Gatekeeper refuses apps that are not signed with a Developer ID *and* notarised
by Apple. What you have here is fine for your own machine and for a colleague
who is willing to bypass the warning deliberately, but it is not a download
link you can put in a README.

To make a distributable one you need a paid Apple Developer account:

  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  DEVELOPMENT_TEAM=TEAMID ./scripts/build-dmg.sh
  xcrun notarytool submit dist/Snaplet-<version>.dmg \
    --keychain-profile snaplet-notary --wait
  xcrun stapler staple dist/Snaplet-<version>.dmg

Full steps: docs/signing-and-notarization.md
Do not tell users to disable Gatekeeper instead.
WARNING
fi
