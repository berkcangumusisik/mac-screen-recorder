# Performance

Snaplet publishes only numbers that were actually measured, and always says on
what. Nothing here is an estimate.

## How the numbers were produced

Two sources:

1. **Repeatable measurements in the test suite.**
   `SnapletTests/PerformanceMeasurementTests.swift` renders, recognises and
   exports real data and appends each result to `/tmp/snaplet-perf.txt`:

   ```bash
   rm -f /tmp/snaplet-perf.txt
   xcodebuild -project Snaplet.xcodeproj -scheme Snaplet \
     -destination 'platform=macOS' \
     test -only-testing:SnapletTests/PerformanceMeasurementTests
   cat /tmp/snaplet-perf.txt
   ```

   These tests assert correctness, never speed, so a slow machine cannot fail
   the build.

2. **Live measurements inside the app.** Snaplet times the two paths that
   matter most for the capture experience and shows them under
   *Snaplet menu › Keyboard Shortcuts… › Session measurements*:

   - `shortcut→overlay` — from the hot key firing to the selection overlay
     being on screen (this includes taking the pre-capture display snapshot).
   - `selection→clipboard` — from releasing the mouse to the image being on
     the clipboard.

   These need Screen & System Audio Recording permission and a real display, so
   they cannot run in CI. Use the **Copy** button in that panel to get a plain
   text report.

## Measured results

Machine: Apple M5 Pro, 24 GB, macOS 26.6.2, Xcode 26.6.
Build: **Debug** configuration (the test bundle needs `ENABLE_TESTABILITY`).
Release timings for the same work are expected to be equal or better, because
the heavy lifting happens in Core Graphics, Core Image, Vision and
AVFoundation rather than in Snaplet's own Swift code.

| Operation | Samples | Median | Min | Max |
| --- | --- | --- | --- | --- |
| 3840×2160 screenshot: 8 annotations rendered + PNG encoded | 5 | 39.3 ms | 38.9 ms | 118.0 ms |
| 3840×2160 screenshot: full presentation styling (gradient, frame, shadow, 16:9) | 5 | 100.2 ms | 99.6 ms | 102.7 ms |
| 1920×1080 screenshot with 20 lines of text: Vision recognition | 3 | 228.0 ms | 222.7 ms | 484.6 ms |
| 5 s 1280×720 clip exported to MP4 with a redaction and a zoom | 1 | 367.2 ms | — | — |

The `max` column is the first, cold run in each case.

**Not measured yet, so not claimed:** capture latency on a real display
(`shortcut→overlay`, `selection→clipboard`), sustained recording throughput,
memory use during long recordings, and Intel Mac performance. If you measure
any of these, open a pull request with the numbers and the machine.

## Design choices that affect these paths

- Area selection captures the display **once**, before the overlay appears, and
  then crops that image. Confirming a selection therefore involves no second
  capture, which is why `selection→clipboard` is dominated by PNG encoding.
- Recording streams to disk through `AVAssetWriter`; frames are never
  accumulated in memory.
- Video preview and export share one Core Image composition. The styled
  background, shadow, window frame and caption are rendered once into a static
  plate, so per-frame work is limited to the frame itself.
- Snaplet holds no capture stream while idle and runs no polling timers outside
  an active recording.
