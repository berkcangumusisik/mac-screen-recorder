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

# Automatic signing insists on a development team the moment a real identity is
# named, which a self-signed certificate does not have. Naming an identity means
# the choice is already made, so sign manually.
if [ "$SIGN_IDENTITY" = "-" ]; then
  CODE_SIGN_STYLE="Automatic"
  INJECT_BASE_ENTITLEMENTS="YES"
else
  CODE_SIGN_STYLE="Manual"
  # Xcode otherwise injects com.apple.security.get-task-allow, which lets a
  # debugger attach to the release build and makes notarisation reject it.
  INJECT_BASE_ENTITLEMENTS="NO"
fi
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
  CODE_SIGN_STYLE="$CODE_SIGN_STYLE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS="$INJECT_BASE_ENTITLEMENTS" \
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

# Leave exactly one Snaplet.app behind. Two bundles with the same identifier
# confuse Launch Services, which would then happily open the intermediate copy
# that the next build deletes out from under the running app.
rm -rf "$BUILD_DIR"

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

An ad hoc signature is derived from the binary, so it changes on every build,
and macOS ties Screen & System Audio Recording to the signature. Expect to grant
that permission again after each rebuild. Signing with a stable self-signed
certificate avoids this while developing — see the "Keeping permissions across
rebuilds" section of docs/signing-and-notarization.md.
NOTE
fi
