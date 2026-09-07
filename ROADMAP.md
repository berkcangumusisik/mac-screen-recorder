# Roadmap

What is done, what is next, and what is deliberately out of scope. Nothing here
is a promise with a date.

## Shipped in 0.1.0

See [CHANGELOG.md](CHANGELOG.md) for the full list. In short: instant capture,
a non-destructive screenshot editor, share-ready styling, screen recording with
audio and a webcam overlay, light video editing with MP4 and GIF export,
on-device text recognition with sensitive-region suggestions, a local history,
and a local bug-report flow — in English and Turkish.

## Next

Roughly in order of how much they would improve daily use.

- **An app icon.** The menu-bar item currently uses an SF Symbol.
- **Screenshots and a demo recording for the README.** The scenarios are already
  written down in [docs/demo-scenarios.md](docs/demo-scenarios.md); they need a
  machine with screen-recording permission.
- **Measure capture latency on real hardware.** `shortcut→overlay` and
  `selection→clipboard` are instrumented in the app but not yet published,
  because they have not been measured on a range of displays. See
  [docs/performance.md](docs/performance.md).
- **Selection across multiple displays.** Today a selection stays within the
  display where the drag started.
- **Pause and resume while recording.**
- **Inline text editing on the editor canvas.** Text and callout content is
  currently edited in the inspector.
- **Zoom and pan in the screenshot editor** beyond the current fit / 50% / 100%
  / 200% steps.
- **Adopt the Swift 6 language mode.** The code already uses structured
  concurrency and actor isolation, but the targets build in Swift 5 mode with
  minimal concurrency checking.
- **Verify Intel support.** The project builds for x86_64; nothing has been
  tested there, so the README makes no claim.
- **More export formats** — HEIC for stills, and a look at HEVC for recordings.

## Considered, not committed

- Automatic object tracking and automatic cinematic zoom. Both are easy to do
  badly; zoom emphases are placed by hand for now.
- Scrolling capture.
- A shareable link or any hosted component. This would mean a server, and
  Snaplet's promise is that nothing leaves the Mac.
- Publishing a GitHub issue directly from the bug-report form. It would need an
  account connection and token storage; exporting Markdown and media keeps the
  app offline.

## Out of scope

- Accounts, subscriptions, ads, watermarks and telemetry.
- A full timeline video editor. Snaplet is for short product demos.
- Cloud OCR, cloud AI or any remote processing.
- Presenting blur or pixelate as a security guarantee, or the sensitive-text
  suggestions as exhaustive.
