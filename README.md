# Snaplet

**Capture instantly. Explain clearly. Share beautifully.**

Snaplet is an open-source macOS capture tool that lives in the menu bar. Take a
screenshot or record your screen, mark it up, hide what should not be shared,
and produce something worth posting — all in one app, all on your Mac.

- No account, no subscription, no ads, no watermark.
- No telemetry and no server. Snaplet makes no network requests.
- MIT licensed.

> **The name is provisional.** "Snaplet" has not been checked for trademark or
> App Store conflicts. Rename the product and the bundle identifier before
> publishing anything under it.

---

## Contents

- [What works today](#what-works-today)
- [Requirements](#requirements)
- [Build from source](#build-from-source)
- [Permissions](#permissions)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Where your data goes](#where-your-data-goes)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [Known limitations](#known-limitations)
- [License](#license)

---

## What works today

Every item below is implemented and reachable in the app.

### Instant capture

- Menu-bar app with no dock icon and no window until you need one.
- Configurable global shortcuts for area, window, full-screen, repeat-last-area,
  start/stop recording, copy-text-on-screen and edit-clipboard-image.
- Selection overlay with crosshair, dimming, live pixel dimensions and a pixel
  loupe. ⇧ constrains to a square, ⌥ draws from the centre, Space moves the
  selection, Esc cancels.
- The overlay draws a snapshot taken *before* it appeared, so Snaplet's own
  overlay, preview panel and recording control can never appear in a capture.
- Retina and mixed-scale displays are handled; a selection stays within one
  display in this version.
- Repeating the last area re-checks that the display is still connected and that
  the rectangle is still inside it.
- Captures go to the clipboard immediately. Writing a file is optional.
- A small preview panel appears without stealing focus: edit, save, reveal in
  Finder, or drag the file straight into another app.

### Screenshot editor

Non-destructive: the source image is never modified. Crop, rotation and every
annotation are stored separately and applied when you export.

- Crop and rotate.
- Arrow, line, rectangle, ellipse, freehand, highlighter.
- Text, callout bubbles, auto-numbered step markers, magnifier.
- Blur, pixelate and opaque redaction.
- Colour, thickness and font size; select, move, resize, nudge and delete;
  undo/redo.
- Export to PNG or JPEG with a quality setting.

Redaction draws an opaque block and is the recommended way to hide something.
Blur and pixelate are presented as visual effects, not as a security guarantee.
Export always rasterises: the exported file contains one flat image, and the
original pixels under a redaction are not written into it. This is covered by
tests that read the exported pixels back.

### Share-ready styling

- Solid, gradient or image backgrounds, or none at all.
- Padding, corner radius and shadow.
- A neutral window frame of Snaplet's own design.
- Title and short description.
- Original, 1:1, 16:9, 9:16 and 4:3 output; live preview and pixel dimensions.
- Five starting presets — Clean, Midnight, Studio, Docs, Social — plus your own
  saved presets.

### Screen recording

- Record the full screen, a window or a selected area.
- System audio and microphone toggle independently. With both on they are mixed
  into a single track on a shared clock, rather than written as two tracks a
  player might ignore.
- Pointer visibility, click highlighting, 30 or 60 FPS, original resolution or a
  1080p/1440p/4K limit (never upscaled), optional countdown.
- MP4 (H.264) output written straight to disk as it is captured.
- Menu-bar timer, a movable floating control, and stopping from the shortcut.
- Optional round or rounded-rectangle webcam overlay, composited into the
  encoded frames rather than only shown on screen.
- Recordings are flushed in two-second fragments, so an interrupted session
  still leaves a playable file. Snaplet only reports success after the file is
  finalised.

### Light video editing

- Trim start and end, scrub the preview, save any frame as an image.
- Presentation styling and aspect ratio for the output.
- Zoom emphases over a time range with an eased ramp.
- Text and opaque redaction boxes over a time range.
- MP4 export, and GIF export for a short selection with duration, frame-rate and
  width limits.
- Progress and immediate cancellation.

Preview and export run through the same composition, so what you see playing is
what gets written.

### Bug report flow

- A local form: title, steps to reproduce, expected, actual.
- Numbered markers from the editor can seed the steps list.
- Environment lines are opt-in and shown in full before you share them. Snaplet
  never adds your computer name, account name or file paths.
- Output as Markdown on the clipboard, or an export folder containing
  `report.md` and copies of the media.

Snaplet does not connect to GitHub. The report says plainly that the media has
not been uploaded and must be attached to the issue by you.

### Text recognition

- Copy the text in a selected area straight to the clipboard with a shortcut.
- Read a screenshot's text in the editor and copy selected lines.
- Search your history by recognised text.
- Suggestions for possibly sensitive regions — email addresses, key-shaped
  strings, tokens, IP addresses, long numbers — which you approve before
  anything is hidden.

Recognition uses Apple's Vision framework on this Mac, off the main thread.
There is no cloud AI, no API key and no remote OCR service. The suggestions are
pattern matching over recognised text: they will miss things and they will flag
harmless ones.

### History and settings

- Local history with image/video filters, thumbnails, favourites and search over
  file names and recognised text.
- Reopen an item in the editor, reveal it in Finder, remove it from the history,
  or move the file to the Trash — the difference between the last two is stated
  in the interface.
- Metadata lives in a small SwiftData store; media files stay in your output
  folder and are never copied into the database.
- Settings for shortcuts, output folder, clipboard and auto-save behaviour,
  image format, default style, recording quality and audio, webcam overlay,
  theme, language, open-at-login, and clearing the history and text index.
- Snaplet never deletes your capture files on its own.

---

## Requirements

- macOS 15 or later.
- Xcode 26 or later to build from source.
- Apple silicon is the development and test target. The project builds for
  Intel, but Snaplet has not been tested on an Intel Mac, so no claim is made
  about it.

## Build from source

```bash
git clone https://github.com/berkcangumusisik/mac-screen-recorder.git
cd mac-screen-recorder
open Snaplet.xcodeproj
```

Select the **Snaplet** scheme and run. From the command line:

```bash
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet -configuration Debug -destination 'platform=macOS' build
```

Run the tests:

```bash
./scripts/run-tests.sh
```

Build a Release `.app` and a zip into `dist/`:

```bash
./scripts/build-release.sh
```

The app icon is generated from source rather than checked in as artwork, so it
can be reviewed and adjusted like any other file. Re-render it after changing
`scripts/make-app-icon.swift`:

```bash
swift scripts/make-app-icon.swift
```

It writes every size into `Snaplet/Resources/Assets.xcassets/AppIcon.appiconset`
plus a 1024 px preview at `build/icon-preview.png`. The 16 and 32 pixel sizes
are drawn with their own bolder geometry, because downsampling the full artwork
turns it into a smudge at those sizes. The menu-bar item deliberately keeps an
SF Symbol so it follows the system's template-image behaviour in light and dark.

The default build signs ad hoc (`CODE_SIGN_IDENTITY = "-"`), which is enough to
run Snaplet on the Mac that built it. Distributing to other machines needs
signing and notarisation — see [docs/signing-and-notarization.md](docs/signing-and-notarization.md).

## Permissions

Snaplet asks for a permission only when you first use the feature that needs it.

| Permission | Needed for | When it is asked |
| --- | --- | --- |
| Screen & System Audio Recording | Every screenshot and recording | The first capture |
| Microphone | Narration in a recording | The first recording with "Record microphone" on |
| Camera | The webcam overlay | The first recording with the overlay on |

Nothing else is requested. Snaplet does not need Accessibility permission: its
global shortcuts use Carbon hot keys, which the system delivers only for the
exact combinations Snaplet registered. Snaplet never observes general keyboard
input. Click highlighting is drawn by the system's capture pipeline and needs no
extra permission.

If you deny a permission, Snaplet says what is missing and offers to open the
right System Settings pane. Granting it later works without restarting.

Because a Debug build is signed ad hoc, macOS may ask again after a rebuild
changes the signature.

## Keyboard shortcuts

Defaults use ⌃⌥⌘ so they do not collide with the built-in macOS screenshot
shortcuts (⇧⌘3/4/5/6). All of them can be changed in Settings › Shortcuts, and
any that the system refuses is reported there.

| Action | Default |
| --- | --- |
| Capture area | ⌃⌥⌘A |
| Capture window | ⌃⌥⌘W |
| Capture full screen | ⌃⌥⌘F |
| Repeat last area | ⌃⌥⌘R |
| Start / stop recording | ⌃⌥⌘V |
| Copy text on screen | ⌃⌥⌘T |
| Edit clipboard image | ⌃⌥⌘E |

While selecting: ⇧ square, ⌥ from centre, Space to move, Esc to cancel.
In the editor, single keys switch tools (V, C, A, L, R, O, D, H, T, B, S, M, U,
P, X) and ⌘Z / ⇧⌘Z undo and redo.

## Where your data goes

Every capture, edit, recognition pass and export happens on your Mac:

- Screenshots and recordings are produced by ScreenCaptureKit and written to
  your chosen output folder (default `~/Pictures/Snaplet`).
- Editing is in-memory; exports are written with ImageIO and AVFoundation.
- Text recognition uses Apple's Vision framework locally.
- History metadata is stored in `~/Library/Application Support/Snaplet`, with
  thumbnails as small JPEG files beside it. Media is referenced by path, never
  copied in.
- Preferences live in the app's `UserDefaults`.

Snaplet contains no analytics SDK, no crash reporter and no networking code. Its
only dependencies are Apple frameworks; there are no third-party packages, so
there is nothing else to audit.

Logging is deliberately narrow: Snaplet logs lifecycle and error information
only. Captured pixels, recognised text, window titles and file paths are never
written to the log.

## Architecture

```
Snaplet/
  App/           Composition root, menu bar, main menu, app delegate
  Core/          Errors, logging, coordinate conversion, image export, temp files, metrics
  Permissions/   Screen, microphone and camera permission state
  Hotkeys/       Shortcut model, Carbon registration, key-code translation
  Capture/       ScreenCaptureKit stills, selection overlay, capture coordinator
  Editor/        Non-destructive document, annotations, renderer, canvas, inspectors
  Presentation/  Style presets and the share-ready renderer
  Recording/     Configuration, state machine, writer, audio mixer, webcam, compositor
  VideoEditor/   Edit model, frame renderer, composition builder, exporter, UI
  OCR/           Vision recognition and sensitive-pattern suggestions
  Library/       SwiftData history store and window
  BugReport/     Report model and form
  Settings/      Preferences, store, settings UI, shortcut recorder
  UI/            Preview panel, error presentation, help window
```

Three ideas hold it together:

1. **One coordinate authority.** `ScreenGeometry` is the only place that
   converts between AppKit points, Core Graphics display points and image
   pixels. Every capture path goes through it, and it is covered by tests
   including negative-origin and secondary-display layouts.
2. **One renderer per medium.** Screenshots have `AnnotationRenderer`; video has
   `VideoFrameRenderer`. The editor preview and the exporter call the same code,
   so a preview cannot drift from what is written.
3. **Explicit lifecycles.** Recording has a real state machine
   (`RecordingState`) whose transitions are validated and tested; exports are
   cancellable jobs; streams, observers and tasks are torn down on the paths
   that create them.

Handled edge cases: permission denied and later granted, rapid repeated hot-key
presses, starting a recording while one is running, the target window closing,
a display being unplugged, sleep, a full disk, export cancellation, and quitting
with a recording in progress (the partial file is finalised and kept).

Measured performance numbers and how to reproduce them are in
[docs/performance.md](docs/performance.md).

## Contributing

Bug reports and pull requests are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md), which covers the layout, the test
conventions and what a change needs before review. Everyone taking part is
expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Security issues: see [SECURITY.md](SECURITY.md).

## Known limitations

- A selection cannot span two displays; it stays within the display where the
  drag started.
- Recording cannot be paused and resumed. Stopping finalises the file.
- There is no automatic object tracking and no automatic cinematic zoom; zoom
  emphases are placed by hand.
- Video editing is deliberately small: trim, styling, zoom, text and redaction.
  It is not a timeline editor and has no multi-clip support.
- GIF export is capped at 30 seconds, 15 FPS and 800 px wide.
- Sensitive-text suggestions only see what Vision could read, and match on
  shape. Treat them as a prompt to look, not as a guarantee.
- Blur and pixelate are visual effects. Use redaction for anything that matters.
- Snaplet has not been tested on an Intel Mac.
- The Turkish translation ships complete for the current strings; new strings
  need `./scripts/sync-strings.sh` before release.
- No screenshots or demo video are included, because they would have to be
  produced on a machine with screen-recording permission. The scenarios to
  record are written down in [docs/demo-scenarios.md](docs/demo-scenarios.md).

Planned work is in [ROADMAP.md](ROADMAP.md).

## License

MIT — see [LICENSE](LICENSE).
