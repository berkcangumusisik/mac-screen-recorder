# Changelog

All notable changes to Snaplet are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- App icon, generated from source by `scripts/make-app-icon.swift` and rendered
  into an asset catalogue at every size macOS asks for. The 16 and 32 pixel
  variants use their own bolder geometry, because downsampling the full artwork
  is illegible at that scale.
- An accent colour in the asset catalogue, matching the icon and the Studio
  presentation preset.
- A log line recording whether the system actually placed the status item. It is
  the app's only permanent surface, and macOS hides items when the menu bar runs
  out of room, so a missing one was otherwise silent.
- **Pin to screen.** Captures can float above every window, from the preview
  panel or the editor, with copy and drag-out, and a menu-bar item to close them
  all. Pinned shots are excluded from later captures like the rest of Snaplet's
  windows.
- **Colour picker.** Pressing C while selecting copies the hex value under the
  pointer; the loupe shows it live. Reads a single pixel out of the display
  snapshot rather than holding an uncompressed copy of a 5K display.
- **Pause and resume while recording**, from the floating control or the menu
  bar. Samples are dropped while paused and everything after is shifted back by
  the pause length, so the file has no dead air and no frozen frame. One frame
  of spacing is kept at the resume point so the first frame back is not dropped
  by the monotonic-timeline guard.
- Localisation fit tests measure translated labels against the widths they are
  drawn into, in every shipped language, so a translation that no longer fits
  fails the build instead of silently truncating.
- Development-only interface snapshots: `InterfaceSnapshotTests` renders the
  floating surfaces to PNGs in light and dark so layout can be reviewed without
  launching the app. A control case records that `ImageRenderer` cannot draw a
  `Menu` offscreen, so the placeholder it leaves is not mistaken for a bug.
- **Captions are edited on the canvas.** Double-clicking a text or callout
  annotation, or pressing Return with one selected, opens a live text view over
  it, so the caption is typed where it will actually appear. The inspector field
  still works.
- **Zoom and pan in the screenshot editor.** ⌘+ / ⌘− step through zoom levels,
  ⌘0 fits and ⌘1 shows actual size; the trackpad pinch and ⌥ with the scroll
  wheel zoom continuously, while a plain scroll pans. Stepping out of "fit"
  continues from the size on screen rather than jumping.
- **Capture latency is now measured** on real hardware and published in
  `docs/performance.md`: 56 ms median from the hot key to the selection overlay
  with two displays, and 11 ms from releasing a 600×400 pt selection to the
  image being on the clipboard, both in a Release build.
- **Selections can cross displays.** The drag is tracked in global coordinates
  rather than inside the display it started on, and the result is stitched from
  every display it touches, rendered at the sharpest scale involved so a Retina
  half is not downscaled to match a 1× monitor. Regions no display covers stay
  transparent instead of being filled in. Recording areas still stay on one
  display, because a capture stream is bound to one.
- **Open an image or a video to edit**, from the menu bar, the application menu
  (⌘O) or by dropping a file on the Dock icon. The video editor previously had
  no entry point except the preview panel, which dismisses itself, and the
  history — so an existing recording could not be opened for editing at all.
- **Self-timer.** An optional 3, 5 or 10 second delay that runs after you choose
  what to capture, so menus and hover states can be opened first. Area captures
  re-read the display after the wait rather than cropping the older snapshot.

### Fixed

- Recording could stop working entirely until the app was relaunched. Cancelling
  the area or window picker, or the countdown, tried to move the presenter from
  `.preparing` or `.countingDown` straight to `.idle`; neither transition was
  legal, so it was rejected and the presenter never returned to `.idle`. Every
  later start request was then silently ignored.
- Snaplet kept asking for Screen & System Audio Recording after the permission
  had been granted. `CGPreflightScreenCaptureAccess` answers from a value cached
  per process, so it keeps saying no while the app is running; the permission is
  now confirmed against ScreenCaptureKit before anything is reported.
- Write failures reported only "the operation could not be completed". They now
  carry the domain, the code and any underlying error.
- Capture callbacks could still be in flight when finishing began, where
  appending to `AVAssetWriter` is undefined.
- Adding any new preference reset every existing setting. The synthesised
  decoder throws `keyNotFound` for keys a stored blob does not contain, so a
  blob written by an older build failed to decode and fell back to defaults
  wholesale. Decoding is now written by hand, field by field.
- `build-release.sh` left a second `Snaplet.app` in `build/`, which Launch
  Services would happily open and the next build would delete out from under the
  running app.

- Recording failed roughly two times in five, a few seconds in, with
  `AVFoundationErrorDomain -11800` / `NSOSStatusErrorDomain -16341`, losing the
  whole capture. The cause was writing fragmented `.mp4` output: the failure
  always landed shortly after the first movie fragment was flushed. Fragments
  are gone and the same conditions now pass every time.

### Changed

- The recording control was redesigned around the new pause button: a pulsing
  status dot that turns amber while paused, a monospaced timer, and separate
  pause and stop buttons with their own VoiceOver labels.
- Layouts are sized from measured text rather than fixed widths or a
  character-count guess, because Turkish labels run longer than their English
  originals and were being clipped. The recording control, the capture preview
  panel and the selection overlay's labels now take their size from the text
  they actually draw.
- The style inspector's background type is a menu instead of a segmented
  control: four labels did not fit the inspector in any language, and segments
  truncate without complaining.
- The settings window is wider by default, leaving the tab bar room in longer
  languages.
- The About pane shows the real app icon instead of a stand-in symbol, and its
  content is centred rather than crowded against the top.
- The settings window is resizable, so larger accessibility text sizes are not
  clipped.
- The capture preview panel now leads with Edit as the emphasised action, groups
  Save, Show in Finder and Pin beside it at equal weight, and frames the
  thumbnail so a wide capture no longer floats in empty grey.
- Permission guidance now covers the case where Snaplet is already listed and
  switched on, which is what an ad hoc rebuild produces.
- Recordings no longer use movie fragments, so an outright crash mid-recording
  now loses the file. Quitting Snaplet normally still finalises and keeps it.
- Write failures name the track, the frame count and the sample format, so a
  report says what the writer was actually handed.
- New live capture integration tests drive a real `SCStream` through the real
  writer for every capture target. They need Screen & System Audio Recording for
  the test host and skip themselves without it, so CI is unaffected.
- 176 tests, up from 111.

## [0.1.0] — 2026-09-07

First working version. Not tagged or released; the app builds and runs from
source.

### Added

**Capture**
- Menu-bar application with no dock icon and no window until one is needed.
- Configurable global shortcuts for area, window, full-screen, repeat-last-area,
  start/stop recording, copy-text-on-screen and edit-clipboard-image, registered
  as Carbon hot keys so no Accessibility permission is required.
- Selection overlay per display with dimming, live pixel dimensions and a pixel
  loupe; ⇧ constrains to a square, ⌥ draws from the centre, Space moves the
  selection, Esc cancels.
- The overlay renders a snapshot taken before it appeared, so Snaplet's own
  windows can never be captured, and confirming a selection needs no second
  capture.
- Window picking, full-screen capture of the display under the pointer, and
  repeat-last-area with display and bounds re-validation.
- Clipboard-first delivery, optional automatic file saving, and a preview panel
  that does not take focus, with edit, save, reveal and drag-out.

**Editor**
- Non-destructive document: immutable source image with separate crop, rotation
  and annotation state, and undo/redo.
- Arrow, line, rectangle, ellipse, freehand, highlighter, text, callout,
  auto-numbered step markers, magnifier, blur, pixelate and opaque redaction.
- Colour, thickness and font size; selection, move, resize, arrow-key nudge and
  delete.
- PNG and JPEG export with a quality setting; export rasterises so hidden
  content is not carried into the file.

**Presentation**
- Solid, gradient, image or no background; padding, corner radius and shadow; a
  neutral window frame; title and description; original, 1:1, 16:9, 9:16 and 4:3
  output.
- Clean, Midnight, Studio, Docs and Social presets, plus user-saved presets.

**Recording**
- Full-screen, window and area recording through ScreenCaptureKit, written to
  MP4 (H.264) as it is captured.
- Independent system-audio and microphone capture, mixed into one track on a
  shared clock when both are on.
- Pointer visibility, click highlighting, 30/60 FPS, resolution limits that
  never upscale, and an optional countdown.
- Menu-bar timer, movable floating control and shortcut stop.
- Optional circular or rounded-rectangle webcam overlay composited into the
  encoded frames.
- Explicit recording state machine, and handling for permission denial, an
  unplugged display, sleep, a closed target window, a full disk and quitting
  mid-recording.

**Video editing**
- Trim, scrub, frame extraction, presentation styling, eased zoom emphases and
  time-ranged text and redaction overlays.
- MP4 export via AVAssetReader/AVAssetWriter with real progress and immediate
  cancellation; GIF export with duration, frame-rate and width limits.
- Preview and export share one Core Image composition.

**Text recognition**
- On-device Vision recognition, off the main thread, with no network access.
- Copy text from a selected area, read a screenshot's text in the editor and
  copy selected lines.
- Suggestions for possibly sensitive regions, applied only after approval.

**History and settings**
- SwiftData history of metadata only, with thumbnails on disk, search over file
  names and recognised text, favourites, filters, and a clear separation between
  removing a record and trashing a file.
- Settings for shortcuts, output folder, clipboard and auto-save, image format,
  default style, recording quality and audio, webcam overlay, theme, language,
  open-at-login, and clearing the history and text index.

**Bug reports**
- Local Markdown report with opt-in environment lines, an export folder
  containing the media, and no automatic device, account or path information.

**Project**
- English and Turkish interfaces through a String Catalog.
- Full keyboard access, VoiceOver labels, and light and dark support.
- 111 unit and integration tests at the time of that entry, including censored-output pixel checks for
  both images and video.
- GitHub Actions workflow that builds and tests on a macOS runner.
- Release build and packaging scripts.
