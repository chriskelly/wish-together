# CI and signing

Scope: the workflows that gate a PR, deploy the web app, and sign iOS builds, with the
secrets and pinned versions they use. Read before changing one of those workflows, a
secret, or a lane.

## Web

`.github/workflows/ci-web.yml` runs on every PR — format gate
(`dart format --output=none --set-exit-if-changed .`), `flutter analyze`,
`flutter test --coverage`, `flutter build web` — then deploys a Firebase Hosting **preview
channel** (`pr-<number>`, commented on the PR). Pushes to `master` run the same checks and
**deploy live** to `https://wishtogether.gift`. `.github/workflows/ci-web-cleanup.yml`
deletes the preview channel when the PR closes. Both authenticate with the
`FIREBASE_SERVICE_ACCOUNT` repository secret (a service-account JSON) via
`google-github-actions/auth`; `.github/workflows/ci-web.yml` additionally pins the Flutter version, and both
pin firebase-tools. Coverage is uploaded as the `coverage-lcov` artifact and is **report-only**
(no threshold). Preview deploys are skipped for pull requests from forks and Dependabot,
which do not receive repository secrets. `.github/workflows/lint.yml` separately runs
actionlint, the dev-script tests and the Fastlane gates.

## iOS

All on `macos-26` runners with the same pinned Flutter version:

- `.github/workflows/ci-ios.yml` — the only PR-triggered iOS check: `flutter test` +
  `flutter build ios --simulator` (compile gate, no signing).
- `.github/workflows/testflight-release.yml` — chained after **iOS CI** succeeds on a PR
  (`workflow_run`, so it never shows up as a permanently-Skipped check) and uploads an
  internal TestFlight build. **Opt out** per PR by adding the `no-deploy` label. It comments
  the build number on the PR.
- `.github/workflows/app-store-release.yml` — on a `v*` tag or manual dispatch, uploads and
  submits for App Store review. Screenshots are uploaded by hand to the editable version first
  and the lane passes `skip_screenshots: true`, so it never touches them; see
  `.agents/skills/appstore-screenshots/`.
- `.github/workflows/clear-release-notes.yml` — runs when *App Store Release* succeeds; the
  only workflow that commits, and it pushes with `[skip ci]` (see `docs/release.md`).

## Signing and secrets

Signing uses fastlane [`match`](https://docs.fastlane.tools/actions/match/) against the
private certificate repo `chriskelly/ios-match-certs`; uploads use an App Store Connect API
key. Secrets: `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_PRIVATE_KEY`,
`APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`,
`APP_STORE_CONNECT_API_KEY_CONTENT` (base64 of the `.p8`), and `SENTRY_AUTH_TOKEN` for the dSYM
upload, which also reads the `SENTRY_DSN` variable (see `docs/diagnostics.md`).
`fastlane/` holds the `Appfile`, `Matchfile`, and the `Fastfile` lanes (`testflight_release`,
`app_store_release`); the same workflows pin Ruby `3.3`. The release lanes run
`flutter build ipa` and switch the project to manual signing with the match profile.
`aps-environment` is `production` in `Runner.entitlements` (Release/Profile, used by
TestFlight) and `development` in `Runner-Debug.entitlements` (Debug).

Security posture: `.github/workflows/testflight-release.yml` runs the *PR's*
`fastlane/Fastfile` and app code with the `match` signing key, App Store Connect API key
and Sentry auth token in the environment. It is restricted to same-repo pull requests
and the `no-deploy` label opts a PR out — but anyone who can push a branch reaches those
secrets' effects. Add a GitHub `environment` with required reviewers if that needs a
human gate.

## One-time local setup

On a Mac with Xcode: `bundle install`, then `bundle exec fastlane match appstore` to create
or renew the signing assets in the cert repo (add a read-only deploy key to the cert repo and
set `MATCH_GIT_PRIVATE_KEY`). Before the first `app-store-release`, the App Store Connect
listing (description, screenshots, privacy) must be complete — precheck validates the live
listing, not the PR. The lane creates or updates the editable App Store version for the tag;
the listing itself is maintained in App Store Connect **except for What's New**, which lives
in git (see `docs/release.md`).

Running the lanes locally does not need Bundler: this repo's lockfile pins bundler 2.4.20,
which may be absent for a newer Ruby — `fastlane match appstore` (without `bundle exec`)
works with a globally installed fastlane. If fastlane reports an invalid Apple session,
delete the stale cookie at `~/.fastlane/spaceship/<apple-id>/cookie` and log in again.
