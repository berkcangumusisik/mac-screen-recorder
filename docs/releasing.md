# Cutting a release

A release is a git tag. Everything else — the version stamped into the app, the
disk image, the notes and the GitHub release — follows from it.

## The short version

```bash
./scripts/set-version.sh 0.2.0     # update CHANGELOG.md in the same commit
git commit -am "Release 0.2.0"
git tag v0.2.0
git push origin main --tags
```

Pushing the tag runs `.github/workflows/release.yml`, which stamps the version
from the tag, runs the tests, builds a disk image and publishes it as a GitHub
release people can download.

## What the workflow does

1. Reads the version from the tag (`v0.2.0` → `0.2.0`) and stamps it into the
   project with `scripts/set-version.sh`, using the run number as the build
   number. The tag, the download and the About pane cannot disagree.
2. Runs the full test suite. A failing test stops the release.
3. Builds `dist/Snaplet-<version>.dmg` with `scripts/build-dmg.sh`.
4. Signs and notarises it **if** the repository has the secrets below.
5. Writes install notes that state plainly whether the build is notarised.
6. Attaches the disk image to the release.

## Making the download actually open on other Macs

Without an Apple Developer account the disk image still builds and still works,
but macOS refuses it on first launch and the release notes tell people to
right-click and choose **Open** — Apple's own per-app override. That is honest
and it works, but it is friction, and some people will not trust it.

To remove that step you need a paid **Apple Developer Program** membership and
these repository secrets:

| Secret | What it is |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | Your *Developer ID Application* certificate exported as `.p12`, base64 encoded |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password you set when exporting it |
| `DEVELOPMENT_TEAM` | Your 10-character Team ID |
| `NOTARY_APPLE_ID` | The Apple ID used for notarisation |
| `NOTARY_PASSWORD` | An app-specific password for that Apple ID |

Export the certificate like this:

```bash
# In Keychain Access, export the Developer ID Application certificate as
# certificate.p12, then:
base64 -i certificate.p12 | pbcopy
```

With those set, the same tag push produces a notarised image that opens with a
double-click, and the install notes say so.

None of these secrets are needed to build, test or run Snaplet from source.

## Building a disk image locally

```bash
./scripts/build-dmg.sh                                   # ad hoc, this Mac only
SIGN_IDENTITY="Snaplet Dev" ./scripts/build-dmg.sh       # self-signed, this Mac only
SIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
  DEVELOPMENT_TEAM=TEAMID ./scripts/build-dmg.sh         # distributable, then notarise
```

The script prints a warning whenever the result is not distributable, and
[docs/signing-and-notarization.md](signing-and-notarization.md) has the
notarisation commands.

## Version numbers

Snaplet follows [Semantic Versioning](https://semver.org). Pre-1.0, breaking
changes go in the minor position.

`scripts/set-version.sh` writes `MARKETING_VERSION` (what people see) and
`CURRENT_PROJECT_VERSION` (the build number) into the Xcode project. Run it
locally before tagging so the committed project matches the tag.
