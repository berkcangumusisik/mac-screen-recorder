#!/usr/bin/env bash
# Extracts localizable strings from the source into Snaplet/Resources/Localizable.xcstrings
# and then fills in the Turkish column.
#
# Run this after adding or changing any user-facing string.
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED=$(mktemp -d)
trap 'rm -rf "$DERIVED"' EXIT

echo "Building to extract strings…"
xcodebuild -project Snaplet.xcodeproj \
           -scheme Snaplet \
           -configuration Debug \
           -destination 'platform=macOS' \
           -derivedDataPath "$DERIVED" \
           build >/dev/null

ARGS=()
while IFS= read -r file; do
  ARGS+=(--stringsdata "$file")
done < <(find "$DERIVED/Build/Intermediates.noindex/Snaplet.build/Debug/Snaplet.build" -name '*.stringsdata')

if [ ${#ARGS[@]} -eq 0 ]; then
  echo "No .stringsdata files were produced." >&2
  exit 1
fi

xcrun xcstringstool sync Snaplet/Resources/Localizable.xcstrings "${ARGS[@]}"
echo "Filling Turkish translations…"
python3 scripts/turkish_strings.py
