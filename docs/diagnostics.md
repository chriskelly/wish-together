# Diagnostics (Sentry)

Scope: what the app reports, how to debug a report, the project settings the
privacy policy depends on, and which build reports under which environment. Read
before touching `lib/core/logging/`, a diagnostics workflow step, or the privacy
policy.

Crashes, failures and a short trail of steps are reported to **Sentry** (Functional Software,
Inc., United States), once a DSN is configured. `web/privacy.html` is the user-facing
disclosure; this file is the operator view. The policy names **categories** of data, not
features or event names — keep it that way, so shipping a screen does not require a policy
edit.

Nothing is reported without a DSN. `WT_SENTRY_DSN` is empty in local runs, in the test
suite and in the checks that do not deploy (`.github/workflows/ci-ios.yml`, fork and
Dependabot PRs), so Sentry is not initialised there at all (no SDK, no handlers, no
network); a debug run reports only to the console. Builds that are deployed or shipped
do carry one — see Builds, environments and source maps.

## What is never reported by the app

Names, emails, phone numbers, raw uids, document ids, wishlist/group/item titles, descriptions,
links, claim ownership, screenshots, replays and Remote Config message text. Document ids are
capabilities under `firestore.rules`, which is why they never reach the wire at all.
`lib/core/logging/redaction.dart` is the allowlist and
`lib/core/logging/docs/redaction.md` explains the mechanism, including which record becomes an
event. Platform-captured crashes can carry their own context instead — see Known blind spots.

## Debugging a report

Load the **`sentry-triage`** skill (`.agents/skills/sentry-triage/`): the support-code query,
the two endpoints' quirks, how to read tags and breadcrumbs, and the checklist for "nothing
arrived".

One invariant belongs here rather than in the skill: `beforeSend` fails **closed**. An event
with a tag or `extra` key outside the allowlist is dropped, not scrubbed, so a new SDK
integration can erase real errors in silence. That is why an empty search needs the checklist
before it means anything.

## Alerting

The app emits four things worth alerting on, plus site uptime. **Which rules exist, their
thresholds and who is notified are operator preferences.** They change without touching this
repository, nothing here can verify them, and a table of console steps would rot faster than it
would help — configure them in the Sentry console, not in this file.

- `event:error` — failures. Sentry groups them, so a crash loop counts once.
- `event:authState` — sign-in failures only: a cancellation carries no code and never becomes an
  event, so every `authState` event that reaches Sentry is a genuine failure.
- `event:firestoreError` with `error_code:permission-denied` — a rules regression. Legitimate
  volume is near zero, so a single denial after a rules deploy is worth knowing about.
- `event:updateGate` with `reason:*` — the gate could not run; see
  `lib/features/app_update/docs/app-update.md`.
- Site uptime for `https://wishtogether.gift/` — independent of the app, and the only signal
  that survives a crash loop exhausting the event quota.

**One rule is not a preference:** scope every alert and every saved search to
`environment:production`. Preview channels and the staging dispatch report to this same project
and must never page anyone.

Nothing checks that any rule exists. Read this section as what is *possible*, not what is
*configured*.

## Project settings the privacy policy depends on

Not code, and not preferences: `web/privacy.html` makes claims that these settings must keep
true. Check them under **Settings**, organization and project.

- **Data region**: United States, which is what the policy discloses. An EU organization would
  make that wording wrong.
- **Retention**: 30 days, the Developer plan's retention, which is what the policy promises. Do
  not promise longer without changing the policy.
- **IP storage**: "Prevent Storing of IP Addresses" must be **on**. `sendDefaultPii: false` only
  stops the SDK attaching `user.ip_address`; the server enriches the event from the request
  anyway. It was off until the only event then in the project was found carrying
  `user.ip_address` and `user.geo`; it is now **on**, verified with a fresh event that carried
  neither. Re-check it before shipping a build that reports, or the policy's IP sentence is
  false.
- **App Privacy answers** (App Store Connect, not a file): `Diagnostics → Crash Data` **Yes**,
  `Diagnostics → Other Diagnostic Data` **Yes**, linked to the user, not tracking, not
  advertising. `Identifiers → Device ID` is **Yes** for every iOS user while auto session
  tracking stays on, because the session record always carries the installation id (blind spot
  3). The answers are submitted; keep them in step if an upload ever adds a data category.

## Builds, environments and source maps

Every build this repository deploys or ships carries a DSN, so it reports. The DSN is the
repository variable `SENTRY_DSN`: it is public by design (it ships inside the web bundle and
the app, and only names where events go), which is why it is not a secret. `SENTRY_AUTH_TOKEN`
is a secret and authorises the upload.

| Build | `environment` | `release` / `dist` | Symbols |
| ----- | ------------- | ------------------ | ------- |
| push to `master` (live site) | `production` | `wishtogether@<sha>` / `web-<sha>` | source maps uploaded and served |
| same-repo PR preview channel | `preview` | `wishtogether@<sha>` / `web-<sha>` | source maps uploaded and served |
| fork or Dependabot PR | none — no DSN | — | — |
| staging dispatch | `staging` | none (deliberate) | none (no release to attach them to) |
| TestFlight / App Store | `production` (derived from the release build) | `wishtogether@<CFBundleVersion>` / `ios-<build>` | dSYMs uploaded, untagged |
| local, test, iOS CI | none — no DSN | — | — |

- The web identity is the commit SHA: `.github/workflows/ci-web.yml` compiles with `--dart-define=WT_BUILD_ID=<sha>`
  and uses the same value for `SENTRY_RELEASE` and `SENTRY_DIST`, so the uploaded artifact
  bundle matches the release the app reports. `releaseNameFor` and `distNameFor` in
  `lib/core/logging/sentry_startup.dart` are the formatters; the workflow mirrors them
  literally.
- The upload runs `sentry_dart_plugin` — a dev dependency, configured by the `sentry:` block in
  `pubspec.yaml`, invoked explicitly after the build — and a failed upload fails the run. A
  deployed build without its symbols reports unreadable stack traces, which is worse than not
  deploying. The `sentry:` block deliberately sets no release or dist: CI passes them through
  the environment.
- Source maps are a build artefact, not source text: a real build's map lists 1,221 SDK, engine
  and package paths and embeds no sources (`sourcesContent` is absent), so it reveals nothing
  the public repository does not already show. It is uploaded for symbolication and then
  **served with the deploy**, because stripping it would mean maintaining a script and a test
  to save 3.2 MB that no browser fetches unless devtools is open. The check that matters is
  before the upload: the workflow fails when `main.dart.js` or its map is missing, so a Flutter
  upgrade that stops emitting maps cannot silently leave events unsymbolicated.
- **Not yet guarded: the environment define itself.** Both bundle guards assert the DSN and the
  build id, and the staging guard asserts the Firestore target, but nothing proves the bundle
  was compiled with `WT_SENTRY_ENVIRONMENT`. Delete that define and the build reports
  `environment=production` while every guard still passes — a preview would page the operator.
  The fix is a unique compile-time marker emitted from app code (as
  `wishtogether-firestore-target` does) and grepped by both guards; until then, keep the define
  in the same edit as the DSN.
- The numeric organisation and project ids are parsed from the DSN by
  `scripts/sentry-identity.mjs`, so the repository stores no Sentry slug. That parser expects a
  current-format SaaS DSN (`https://<key>@o<org>.ingest.<region>.sentry.io/<project>`); a legacy
  or self-hosted DSN cannot supply an organisation id and fails the run instead of uploading to
  the wrong place. `sentry-cli` prefers the organisation embedded in `SENTRY_AUTH_TOKEN`;
  because the token carries the **slug** and `SENTRY_ORG` carries the **numeric id** from the
  DSN, the two strings differ and the override warning is logged on every upload. They name the
  same organisation, so the warning is expected. Keep the token and the DSN from the same
  organisation: a token minted for a different one overrides the parsed id, and the upload then
  fails on a project id that does not exist there rather than landing somewhere wrong.
- iOS builds are not obfuscated, so there is no Dart symbol map. The plugin uploads the dSYMs
  in the Xcode archive, which symbolicate native frames and crash reports, and creates and
  finalises the release record `wishtogether@<CFBundleVersion>`; the upload itself is untagged,
  because Sentry pairs symbols with events by debug id. The lane refuses to ship when the
  archive holds no dSYM: the plugin uploads what it finds and would otherwise succeed having
  uploaded nothing. `ios-<build>` is the dist the app reports, not a tag on the upload.
- Staging carries no release and no dist on purpose: it uploads no symbols, so an
  identity would name a build Sentry cannot symbolicate. `.github/workflows/ci-
  web.yml` treats a fork or Dependabot PR as untrusted — a fork by head repository,
  Dependabot by PR author — so such a build compiles without diagnostics and deploys
  nothing. A same-repo run whose variable is missing fails rather than deploying a
  silent bundle.

## Known blind spots

1. **Native crash paths.** A native iOS crash envelope, and the platform's own lifecycle and
   network records that travel with it, never pass through `beforeSend` — the Cocoa SDK builds
   that envelope outside Dart. `sendDefaultPii: false` and the absence of PII-bearing custom
   keys are the protection there.
2. **JavaScript-level uncaught errors on web.** `sentry_flutter`'s JS client installs its own
   global handlers and its own `beforeSend`, and this app's breadcrumb filter is not bridged to
   it, so a browser-captured crash carries that client's context — which can include the page
   address, and under the path URL strategy a page address contains a wishlist or group id —
   and the exception's own message text. The privacy policy says so in plain language; do not
   "fix" it by claiming the scrubber covers every crash.
3. **The native session record bypasses `beforeSend` (iOS).** `enableAutoSessionTracking` is on
   and is forwarded to the Cocoa SDK, which emits session envelopes outside Dart — at least one
   per launch, and two when a return from the background ends the previous session (the
   interval is 30 s). Each carries a run id, a distinct id, start time, state and an error
   count, and the record written when a session ends also carries an end timestamp and
   duration. There is no `version` field: the app version travels as the release name
   (`wishtogether@<build>`, i.e. the build number) plus the environment. The distinct id is a
   random installation id stored in a file in the app's cache directory: the same on every
   launch unless the app is reinstalled or iOS purges that cache, unchanged by signing in, and
   the account hash never appears in a session envelope. No screen or content data is involved,
   but nothing in `lib/core/logging/` filters it. On web the path is inert today:
   `sentry_flutter` starts web sessions only from a `SentryNavigatorObserver`, which this app
   does not install; adding one would produce per-navigation sessions with a different field
   set. Turning the option off would remove the iOS path and the installation id, but that is a
   code change, not a documentation one.
4. **The update gate reports one decision per launch.** Read `failedOpen` as "the gate did not
   decide"; the record and its reasons are in `lib/features/app_update/docs/app-update.md`.
