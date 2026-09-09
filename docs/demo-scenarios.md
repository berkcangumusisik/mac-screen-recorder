# Demo scenarios

## What already ships

The three images in the README are generated, not hand-made. They render
Snaplet's real views and renderers over a synthetic desktop drawn by the test
itself, so they contain no personal content and anyone can reproduce them:

```bash
xcodebuild -project Snaplet.xcodeproj -scheme Snaplet \
  -destination 'platform=macOS,arch=arm64' \
  test -only-testing:SnapletTests/DocumentationScreenshotTests
cp /tmp/snaplet-docs/*.png docs/images/
```

The scheme runs tests with `-AppleLanguages (en)`, so the interface in those
images is English whatever language the machine is set to.

What they cover: the selection overlay with the loupe and colour readout, the
editor with annotations and a redaction, and the Studio presentation preset.

## Still to record

A moving demo of the app in use cannot be generated — it needs a machine with
Screen & System Audio Recording permission and a clean desktop. The shots worth
taking are written down below.

Record these on a clean desktop, at 1× or 2×, with a neutral wallpaper and no
personal content on screen. Check every frame before committing anything.

## Still images for the README

1. **The editor window in full** — the generated image shows the canvas only.
   A real screenshot would also show the tool palette on the left and the
   inspector on the right.
   Suggested file: `docs/images/editor-window.png`

2. **Recording in progress** — the menu-bar timer and the floating control,
   captured from a second Mac or a second display so the control is genuinely on
   screen rather than composited.
   Suggested file: `docs/images/recording.png`

3. **Sensitive-text suggestions** — the editor's Text tab after scanning a
   screenshot containing an obviously fake email address and API key, with the
   suggestions listed and one already redacted. Use invented values such as
   `ada@example.com` and `sk_test_0000000000000000`.
   Suggested file: `docs/images/sensitive-text.png`

4. **History** — a populated history window with a mix of images and videos and
   a search term matching recognised text.
   Suggested file: `docs/images/history.png`

## Short demo recording (about 45 seconds, no audio)

A single take, no cuts, so it is obviously not staged:

1. (0:00) Menu bar only. Press ⌃⌥⌘A.
2. (0:03) Drag a selection over a window; let the loupe and the dimensions show.
3. (0:06) Release. The preview panel appears without the front app losing focus
   — click into that app and keep typing to prove it.
4. (0:12) Click **Edit** in the preview.
5. (0:15) Add an arrow, two step markers and a redaction over something that
   looks like a key.
6. (0:25) Switch to the Style tab, turn styling on, pick Studio, type a title.
7. (0:35) Export, then show the exported file in Finder at full size.
8. (0:42) End on the menu bar again.

Export as MP4, then produce a GIF from the same clip using Snaplet's own GIF
export at 12 FPS and 640 px — that also serves as a check that GIF export works.

Suggested files: `docs/media/demo.mp4` and `docs/media/demo.gif`.

## Before committing anything

- No real email addresses, tokens, file paths, account names or computer names.
- No third-party product's interface presented as if it were part of Snaplet.
- Redact with the **redaction** tool, not blur or pixelate.
- Keep the GIF under a couple of megabytes so the README stays quick to load.
- Add the images to the README and `README.tr.md` in the same pull request.
