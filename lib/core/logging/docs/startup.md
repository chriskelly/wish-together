# Sentry startup

Scope: when Sentry initialises, which environment and identity a build reports,
and which handlers own uncaught errors. Read before changing a `WT_SENTRY_*`
define or `lib/core/logging/sentry_startup.dart`.

## Invariants

- **`sessionEnd` is not emitted.** No app-level lifecycle observer exists, and a `detached`
  callback cannot reliably await a flush on web or iOS. Sentry's own session tracking covers
  session health; a startup only emits `sessionStart` (with the real build, platform and route).
- **An empty `WT_SENTRY_DSN` means Sentry is never initialised** — not merely disabled: no SDK,
  no native handler, no network. Consequently no global handlers are installed either, so
  uncaught framework errors go to the console only; that is the accepted dev/test/CI behaviour.
  Startup is equivalent to pre-Sentry with two documented differences: on iOS one
  `PackageInfo` read still runs (it supplies the build identity), and `ConsoleSink` prints the
  launch and route records in debug.
- **`WT_SENTRY_ENVIRONMENT` overrides the environment**; `staging` also omits `release`/`dist`,
  because the pre-merge deploy uploads no symbols. `configure` removes the SDK's
  `LoadReleaseIntegration` for staging, since that integration would otherwise fill both from
  `PackageInfo`. `.github/workflows/ci-web.yml` passes `preview` for a preview channel and `production` for the live
  site; `.github/workflows/deploy-staging.yml` passes `staging`.
- **Sentry's own handlers are the only global error handlers.** `SentryFlutter.init` installs
  `FlutterErrorIntegration` and `PlatformDispatcher.onError` (on web, its own
  `runZonedGuarded`), so the app does not install a second pair; `beforeSend` is what keeps the
  raw exception text off the wire.
- **The support code is reachable signed out.** It is on Profile for a signed-in user and on
  the login page for the failed-OTP case, because the router sends a signed-out user to
  `/login` and Profile is unreachable there.

## Build identity

The web identity is the commit SHA, mirrored literally from `releaseNameFor` and `distNameFor`
in `lib/core/logging/sentry_startup.dart` by `.github/workflows/ci-web.yml`; iOS reports `wishtogether@<CFBundleVersion>` with the
archive build as its dist. The full build/environment table and the source-map upload rules are
in `docs/diagnostics.md`.

## How it is tested

- `test/core/logging/sentry_startup_test.dart` — empty/whitespace DSN disables; environment and staging rules;
  release/dist naming; the Sentry option values; iOS build read and fallback.
- `test/core/logging/sentry_sink_test.dart` — breadcrumb vs event, stack passthrough, one scope write per session
  change, sign-out clears the user, transport failures swallowed.
- `test/core/logging/diagnostics_test.dart` — Sentry sink present only with a transport, provider mapping.
