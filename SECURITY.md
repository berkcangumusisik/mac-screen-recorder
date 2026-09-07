# Security Policy

## Supported versions

Snaplet is pre-1.0. Only the latest commit on `main` is supported. There are no
maintained release branches yet.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue.

Use GitHub's private vulnerability reporting on this repository:
<https://github.com/berkcangumusisik/mac-screen-recorder/security/advisories/new>

If that page is not available to you, open a public issue that says only that
you have a security report and asks for a private channel — no details — and a
maintainer will follow up.

> **Maintainer note:** if you want a security email address listed here, add it
> to this section. This file deliberately does not invent one.

Please include:

- What the issue is and what an attacker could achieve.
- The macOS version, Snaplet commit and whether the build was ad hoc signed.
- Steps to reproduce, and a proof of concept if you have one.

You should get an acknowledgement within about a week. Please give a reasonable
window for a fix before publishing.

## What is in scope

Snaplet handles data that is sensitive by nature — screen contents, audio,
camera frames and recognised text. Reports in these areas are especially
welcome:

- Captured content, recognised text or file paths reaching a log, a crash
  report, or anywhere outside the app.
- Any outbound network request. Snaplet is supposed to make none at all; a
  single one is a bug worth reporting.
- Content that should have been hidden surviving into an exported file — for
  example a redaction that does not cover every frame it should.
- Snaplet's own overlays or windows appearing in a capture that should not
  contain them.
- Files written outside the configured output folder, temporary directory and
  application support directory, or temporary files that are not cleaned up.
- Anything that widens the permissions Snaplet asks for, or uses a granted
  permission for something the user did not ask for.

## What is not a vulnerability

- **Blur and pixelate are not irreversible.** They are visual effects, and
  Snaplet says so in the interface. Use redaction, which draws an opaque block,
  for anything that matters. A report that a blurred region can be partly
  reconstructed is expected behaviour, not a vulnerability.
- **The sensitive-text suggestions are not exhaustive.** They match patterns
  over text that Vision managed to read. Missed matches are a quality issue —
  open a normal issue with an example.
- macOS asking for permission again after a rebuild. Ad hoc signatures change
  between builds; this is how TCC works.
- Ad hoc signed builds warning on other machines. See
  [docs/signing-and-notarization.md](docs/signing-and-notarization.md).
