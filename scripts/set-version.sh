#!/usr/bin/env bash
#
# Sets the version Snaplet reports and names its builds after.
#
#   ./scripts/set-version.sh 0.2.0        # marketing version, build stays
#   ./scripts/set-version.sh 0.2.0 14     # marketing version and build number
#
# Release builds run this from the git tag, so the download, the About pane and
# the tag can never disagree.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
BUILD="${2:-}"

if [ -z "$VERSION" ]; then
  echo "usage: $0 <marketing-version> [build-number]" >&2
  echo "current: $(grep -m1 'MARKETING_VERSION' Snaplet.xcodeproj/project.pbxproj | sed 's/.*= //; s/;//')" >&2
  exit 1
fi

if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "\"$VERSION\" is not a version number like 1.2.3" >&2
  exit 1
fi

PBXPROJ=Snaplet.xcodeproj/project.pbxproj
/usr/bin/sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
if [ -n "$BUILD" ]; then
  /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$PBXPROJ"
fi

echo "MARKETING_VERSION    = $(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= //; s/;//')"
echo "CURRENT_PROJECT_VERSION = $(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= //; s/;//')"
