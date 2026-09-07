# Contributing to Snaplet

Thanks for taking the time. This document is short on ceremony and specific
about the things that actually cause problems in a capture app.

## Getting set up

```bash
git clone https://github.com/berkcangumusisik/mac-screen-recorder.git
cd mac-screen-recorder
open Snaplet.xcodeproj      # Xcode 26 or later, macOS 15 or later
./scripts/run-tests.sh
```

There are no package dependencies to fetch. Snaplet uses Apple frameworks only,
and that is a deliberate constraint — a new third-party dependency needs a
reason in the pull request and a compatible licence.

The Xcode project uses filesystem-synchronised groups, so adding a `.swift` file
under `Snaplet/` or `SnapletTests/` is enough; the project file does not need to
be edited and should rarely appear in a diff.

## Where things live

See the architecture section of the [README](README.md#architecture). Two rules
matter more than the rest:

1. **Coordinate conversions belong in `ScreenGeometry`.** If you find yourself
   writing `primaryHeight - y` or multiplying by a backing scale factor
   somewhere else, move it.
2. **Preview and export must share a renderer.** `AnnotationRenderer` for
   images, `VideoFrameRenderer` for video. Do not add a second drawing path for
   the on-screen preview: that is how previews start lying.

## Tests

Run the suite before opening a pull request:

```bash
./scripts/run-tests.sh
```

Aim tests at the places where mistakes are expensive:

- **Coordinate conversions** — multi-display layouts, negative origins,
  non-integer scale factors, clamping.
- **Recording state** — transitions that must be rejected, not just the happy
  path.
- **Time ranges** — inclusive bounds, ramps, clamping, trims.
- **Censored output** — render and read the pixels back. `RedactionOutputTests`
  and `VideoRedactionCoverageTests` show the pattern; a redaction that stops
  covering under crop, rotation, zoom or styling is a serious bug.
- **File integrity** — a written file must be readable and have the expected
  duration or dimensions.

Tests must not depend on screen-recording permission, a real display, a camera
or a microphone. `SnapletTests/TestSupport.swift` can generate images and write
a real short MP4, which covers most of what the media paths need.

`PerformanceMeasurementTests` asserts correctness, never speed, and appends
timings to `/tmp/snaplet-perf.txt`. Keep it that way so a slow machine cannot
fail the build.

## Manual checks

Some things genuinely cannot be automated here. If your change touches capture,
recording or permissions, say in the pull request which of these you ran:

- Capture an area, a window and a full screen on a Retina display.
- Repeat the same on a second display, including one placed left of or below the
  primary one.
- Deny screen recording permission, then grant it, without restarting.
- Record with system audio, with the microphone, and with both.
- Record with the webcam overlay and confirm it is in the exported file.
- Unplug a display, and let the Mac sleep, while recording.
- Quit while recording and check that the partial file plays.

## User-facing strings

Every string a person can read goes through `String(localized:)`. After adding
or changing one:

```bash
./scripts/sync-strings.sh
```

This extracts the strings into `Snaplet/Resources/Localizable.xcstrings` and
fills in the Turkish column from `scripts/turkish_strings.py`. The script exits
non-zero and lists anything it could not translate, so add the Turkish text
there in the same pull request. English is the source language.

## Privacy rules that are not negotiable

- No network requests. No analytics, no crash reporting, no update checks.
- Never log captured pixels, recognised text, window titles or file paths.
- Never add the computer name, account name or a file path to anything the user
  might share.
- Do not describe blur or pixelate as irreversible, and do not describe the
  sensitive-text suggestions as complete.
- Do not present an unimplemented feature as working — no disabled buttons
  standing in for a plan.

## Style

Match the surrounding code. Beyond that:

- `@MainActor` for anything touching AppKit or SwiftUI; explicit queues for
  ScreenCaptureKit and AVFoundation callbacks.
- Comments explain *why*, not *what*. Most of the file should not need any.
- Errors go through `SnapletError` and `ErrorPresenter`, not raw `NSAlert`.

## Pull requests

- One topic per pull request.
- Fill in the template: what changed, why, how it was tested, and which manual
  checks you ran.
- Update `CHANGELOG.md` under *Unreleased*.
- If you changed behaviour the README describes, update the README — and
  `README.tr.md` with it.

## Code of Conduct

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
