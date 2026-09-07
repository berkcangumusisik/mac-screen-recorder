#!/usr/bin/env bash
# Builds a Release Snaplet.app and packages it into dist/.
#
# By default the app is signed ad hoc, which is enough to run it on this Mac.
# To sign with a Developer ID instead:
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   DEVELOPMENT_TEAM=TEAMID ./scripts/build-release.sh
#
# Notarisation is a separate step; see docs/signing-and-notarization.md.
set -euo pipefail

cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
BUILD_DIR="$(pwd)/build/release"
DIST_DIR="$(pwd)/dist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Building Release…"
xcodebuild \
  -project Snaplet.xcodeproj \
  -scheme Snaplet \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  build

APP="$BUILD_DIR/Build/Products/Release/Snaplet.app"
if [ ! -d "$APP" ]; then
  echo "Build finished but $APP is missing." >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
ZIP="$DIST_DIR/Snaplet-$VERSION-$BUILD_NUMBER.zip"

rm -rf "$DIST_DIR/Snaplet.app" "$ZIP"
cp -R "$APP" "$DIST_DIR/Snaplet.app"

echo "Packaging…"
# ditto keeps the bundle's symlinks and extended attributes intact.
ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/Snaplet.app" "$ZIP"

echo
echo "Built Snaplet $VERSION ($BUILD_NUMBER)"
echo "  app: $DIST_DIR/Snaplet.app"
echo "  zip: $ZIP"
echo "  sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Signature:"
codesign --display --verbose=2 "$DIST_DIR/Snaplet.app" 2>&1 | sed 's/^/  /'
echo
if [ "$SIGN_IDENTITY" = "-" ]; then
  cat <<'NOTE'
This build is signed ad hoc. It runs on this Mac, but other machines will refuse
it until it is signed with a Developer ID and notarised. Do not tell users to
turn Gatekeeper off — see docs/signing-and-notarization.md.
NOTE
fi
