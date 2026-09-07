## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- What problem does this solve? -->

## How it was tested

- [ ] `./scripts/run-tests.sh` passes
- [ ] New or updated tests cover the change

<!-- If this touches capture, recording or permissions, say which manual checks
     you ran. CONTRIBUTING.md has the list. -->

Manual checks run:

## Checklist

- [ ] User-facing strings go through `String(localized:)` and
      `./scripts/sync-strings.sh` has been run, with Turkish filled in
- [ ] No new network calls, analytics or crash reporting
- [ ] Nothing sensitive is logged (pixels, recognised text, window titles, paths)
- [ ] No new third-party dependency, or the pull request explains why one is
      needed and which licence it uses
- [ ] `CHANGELOG.md` updated under *Unreleased*
- [ ] README and `README.tr.md` updated if documented behaviour changed
- [ ] Nothing is presented as working that is not implemented
