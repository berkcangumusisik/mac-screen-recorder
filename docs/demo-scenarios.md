# Demo scenarios

No screenshots or demo video ship with this repository. Producing them requires
a machine with Screen & System Audio Recording permission granted to a build of
Snaplet, so rather than inventing images, the shots worth taking are written
down here.

Record these on a clean desktop, at 1× or 2×, with a neutral wallpaper and no
personal content on screen. Check every frame before committing anything.

## Still images for the README

1. **The selection overlay** — ⌃⌥⌘A over a text-heavy window, mid-drag, with the
   pixel dimensions and the loupe visible. This is the shot that explains the
   overlay in one frame.
   Suggested file: `docs/images/selection-overlay.png`

2. **The editor with annotations** — an arrow, two numbered step markers, a
   callout and a redaction over a settings pane. Shows the tool palette on the
   left and the inspector on the right.
   Suggested file: `docs/images/editor.png`

3. **Share-ready styling** — the same screenshot with the Studio preset: gradient
   background, window frame, 16:9, a short title. Before and after, side by
   side, is more convincing than the result alone.
   Suggested file: `docs/images/styling.png`

4. **Recording in progress** — the menu-bar timer and the floating control,
   captured from a second Mac or a second display so the control is genuinely on
   screen rather than composited.
   Suggested file: `docs/images/recording.png`

5. **Sensitive-text suggestions** — the editor's Text tab after scanning a
   screenshot containing an obviously fake email address and API key, with the
   suggestions listed and one already redacted. Use invented values such as
   `ada@example.com` and `sk_test_0000000000000000`.
   Suggested file: `docs/images/sensitive-text.png`

6. **History** — a populated history window with a mix of images and videos and
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
