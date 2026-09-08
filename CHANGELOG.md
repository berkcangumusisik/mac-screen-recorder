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
- `build-release.sh` left a second `Snaplet.app` in `build/`, which Launch
  Services would happily open and the next build would delete out from under the
  running app.

### Changed

- Permission guidance now covers the case where Snaplet is already listed and
  switched on, which is what an ad hoc rebuild produces.
- 122 tests, up from 111.

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
  MP4 (H.264) as it is captured, with two-second movie fragments so an
  interrupted session still leaves a playable file.
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
