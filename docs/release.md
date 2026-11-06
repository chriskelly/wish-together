# Release and versioning

Scope: how a TestFlight or App Store build gets its number, its marketing
version, and its What's New text. Read before a release, a version bump, or a PR
that changes something a user sees.

## Build numbers

Build numbers are resolved from App Store Connect (highest already uploaded + 1), raised to
the workflow run number when that is higher, and falling back to it if App Store Connect cannot
be read — so the TestFlight and App Store lanes cannot collide.

## A released marketing version closes its TestFlight train

Once a version is approved and released, App Store Connect refuses any further build on it:
`CFBundleShortVersionString [1.0.0] must contain a higher version than the previously
approved version [1.0.0]` (90062) and `Invalid Pre-Release Train … is closed for new build
submissions` (90186). Since every same-repo PR uploads a TestFlight build, **bump `version:`
in `pubspec.yaml` on `master` immediately after a release**, and rebase (or label `no-deploy`)
any PR still on the closed version — its iOS build otherwise fails on the upload, not on the
code. The App Store lane is unaffected by this: it takes the marketing version from the tag or
dispatch input, which is why a release tag must match the bumped `pubspec.yaml`.

## A TestFlight upload never needs a version bump of its own

`testflight_marketing_version` (`Fastfile`) reads App Store Connect's highest version and,
when the branch's `pubspec.yaml` is not above it, uploads the build under the next patch — the
repository is untouched, so a PR on a released version still builds. If App Store Connect
cannot be read the committed version is used, with a warning. The App Store lane does the
opposite and **refuses a tag that is not above the latest App Store version** before it builds
(`validate_release_version!`), because there the version is the release identity and must be
bumped deliberately.

## Release notes (App Store What's New)

`fastlane/metadata/en-US/release_notes.txt` is the "What's New in This Version" text, and it
is uploaded by the release lane (`skip_metadata: false`; only this file exists in the metadata
directory, so nothing else in the live listing is touched). The directory locale must match the
app record's primary language — English (U.S.), so `en-US`.

- **Every pull request with a customer-facing change adds one short line to that file.** Write
  it for the person who installed the app, not for the team: what changed, in plain words, no
  emoji (App Store metadata has choked on them before), no issue numbers, no jargon. Keep the
  whole file under Apple's 4,000-character limit; a release is usually two to five bullets.
- **Every release writes its own notes.** The release lane calls `validate_release_notes!`
  before it builds, and fails on a missing, empty or oversized file — so a release cannot be
  submitted with stale or absent notes, and the failure costs seconds instead of a signed
  archive.
- **The file is cleared after a successful release.**
  `.github/workflows/clear-release-notes.yml` runs on `workflow_run` success for *App Store
  Release*, truncates the file on `master` and pushes with `[skip ci]`. Pull before you branch
  after a release, or the clearing commit shows up as a surprise in your diff.
- If a release is submitted and then rejected, the notes are already in App Store Connect; edit
  them there. Re-running the release needs a non-empty file again.
