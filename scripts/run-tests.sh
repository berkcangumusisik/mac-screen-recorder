#!/usr/bin/env bash
# Builds Snaplet and runs the full test suite, filtering the system log noise
# that macOS emits around test hosts.
set -uo pipefail

cd "$(dirname "$0")/.."

LOG=$(mktemp -t snaplet-tests)
trap 'rm -f "$LOG"' EXIT

xcodebuild \
  -project Snaplet.xcodeproj \
  -scheme Snaplet \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  test >"$LOG" 2>&1
STATUS=$?

grep -vE '\[Connection\]|linkd\.autoShortcut' "$LOG" \
  | grep -E 'error:|XCTAssert|Test Case .* failed|Executed .* tests|\*\* TEST' \
  || true

if [ $STATUS -ne 0 ]; then
  echo
  echo "Tests failed. Full log:"
  echo "  $LOG"
  cp "$LOG" ./snaplet-test.log
  echo "  copied to ./snaplet-test.log"
fi

exit $STATUS
