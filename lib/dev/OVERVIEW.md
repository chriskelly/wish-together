# Dev — Overview

A development entrypoint that boots the app **signed in**, on the real widgets, against one of
two backends: an in-memory Firestore seeded from a Dart fixture (the default), or real Firebase
Auth and real Firestore on a **named** database (live). It exists so an agent (or the user) can
see, drive and screenshot any signed-in screen without a deployment, and can check real rules
and queries when that is what matters.

## Responsibility

- Compose the production app shell over the chosen backend, through the same `setupServiceLocator`
  seams production uses.
- Choose the backend from compile-time defines, and the fixture and route from the page URL, so a
  screenshot is a URL.
- Mark the build visibly, so a screenshot cannot be mistaken for the real app — and mark live data
  differently from a fixture.

Not in scope: a production-visible debug menu, screenshot tooling, a token server, refresh-token
handling, or any affordance reachable from `lib/main.dart`.

## Layout

| File | Role |
| ---- | ---- |
| `dev_main.dart` | The committed entrypoint: resolves the launch and dispatches to the fake, live or refusal path. |
| `dev_config.dart` | Define names, the bundle marker literal, and the pure resolution rules (`resolveDevLaunch`, `resolveScenarioId`). |
| `dev_session.dart` | `DevAuthSession implements AuthSession`: the fake session's identity, no Firebase. |
| `live_dev_session.dart` | The live backend: `Firebase.initializeApp`, custom-token sign-in, real Firestore on a named database, and the pages for a sign-in that cannot happen. |
| `dev_banner.dart` | `DevSessionFrame`: the strip above every page plus the one accessibility node naming what is on screen. Three tones: fixture, live data, not started. |
| `dev_error_screen.dart` | `DevFailureScreen` (headline + details + one semantics node) and the unknown-scenario page built on it. |
| `run_dev_session.dart` | `buildDevApp(fixture)` / `buildDevAppForScenario(id)`, the `runDevSession*` entrypoint helpers, `buildRefusedDevApp`, and the browser preparation both backends share. |
| `fixtures/dev_fixture.dart` | `DevFixture` and the seeding loop. |
| `fixtures/registry.dart` | Scenario id → fixture, with a loud failure for an unknown id. |
| `fixtures/default_scenario.dart` | The scenario shown when nothing else is asked for. |

## Running it

```sh
# the in-memory fixture: no credentials, no network
flutter run -t lib/dev/dev_main.dart -d chrome

# real Auth and real Firestore, on a named database only
flutter run -t lib/dev/dev_main.dart -d chrome --web-port=59922 \
  --dart-define=WT_DEV_BACKEND=live \
  --dart-define=WT_FIRESTORE_DATABASE=staging \
  --dart-define=WT_DEV_TOKEN=<token from `npm run dev:token`>
```

| Input | Effect |
| ----- | ------ |
| the page path | the route, e.g. `/wishlist/dev-l1` |
| `?scenario=<id>` | the fixture, read once at startup. Meaningless in live mode: ignored, and the banner says so |
| `--dart-define=WT_DEV_SCENARIO=<id>` | the fixture when the URL names none (fake only) |
| `--dart-define=WT_DEV_BACKEND=` | unset or `fake` for the in-memory backend; `live` for the real one; anything else is a page naming both |
| `--dart-define=WT_FIRESTORE_DATABASE=<id>` | live only: the named database. Empty means production and is refused, as is `(default)` |
| `--dart-define=WT_DEV_TOKEN=<token>` | live only: the custom token from `npm run dev:token` |
| `--web-port=59922` | live only: the port the project's API key allows (see Live mode) |

An unknown scenario id renders a page naming the ids that exist rather than leaving a blank tab:
an agent must never silently see the wrong data. Every launch that cannot run — unknown backend,
refused database, missing or rejected token — is a page naming the fix for the same reason.

The scenario query is **not** preserved by in-app navigation — go_router rewrites the location and
drops it. Open the scenario URL directly, or reload on it, rather than clicking around and then
reloading.

A one-off fixture is its own entrypoint, three lines, kept out of git under
`lib/dev/scenarios/local/`:

```dart
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

void main() => runDevSession(myFixture);
```

## Live mode

Live mode signs in for real, so it is the check for everything the fake cannot enforce: security
rules, composite indexes, server timestamps, cross-client real-time fan-out, and the shape of real
data. It is also the only mode that runs the real `AuthService` — the uid stream, the providers,
sign-out and account deletion are production's own.

Mint a token (the same service account `seed-demo` uses):

```sh
cd scripts && npm ci
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  npm run dev:token -- --uid <uid> --database staging
```

It prints the token and the whole `flutter run` line — one line, with the port pinned. The uid needs
no Auth account: the first sign-in creates one. Seed what it should see with the same uid, and
remove it afterwards:

```sh
GOOGLE_APPLICATION_CREDENTIALS=... npm run seed:demo -- --yes --database staging --viewer-uid <uid>
GOOGLE_APPLICATION_CREDENTIALS=... npm run seed:demo -- --yes --clean-only --database staging
```

**It cannot reach production.** The launch is resolved before Firebase is touched, and each
refusal is its own page:

| Refusal page | Cause |
| ------------ | ----- |
| `Live dev mode needs a named database` | `WT_FIRESTORE_DATABASE` is unset or blank, which means the production database |
| `Live dev mode refuses the production database` | `WT_FIRESTORE_DATABASE="(default)"` |
| `WT_FIRESTORE_DATABASE="<value>" is not a database id` | malformed id (lowercase, 4–63 characters, starts with a letter) |
| `Live dev mode needs a token` | `WT_DEV_TOKEN` is unset or blank |
| `WT_DEV_BACKEND="<value>" is not a backend this build can run` | anything other than `fake` or `live` |
| `Live dev mode could not sign in` | the token expired or was rejected, or the page's origin is not one the project API key allows; names `npm run dev:token` and the port |
| `Live dev mode could not start Firebase` | `initializeApp` failed |

A token lasts about an hour. `--dart-define` is compile-time, so a fresh token means stopping the
app and running the line again — a hot restart keeps the old one.

**The port is not free choice.** The project's browser API key restricts HTTP referrers, and the
only localhost entry it allows is `http://localhost:59922/*`, so live sign-in works on
`--web-port=59922` and no other. Any other port fails at sign-in with an API-key error, which the
failure page names. `.agents/skills/preview-auth/scripts/preview-auth.sh list` prints the allowed
referrers. Two concurrent sessions (the only way to see cross-client behaviour) would need a second
port added to that key, which is an operator change, not something this harness does.

**Use a synthetic uid.** Account deletion really runs: it deletes the uid's staging documents and
the Auth user. Auth is shared with production, so that account must never be a real one.

App Check is not activated by this path, the update gate is not part of it (so a production
`min_supported_build` cannot block a live session), and Sentry is not initialised.

**Which rules apply.** Live mode runs against whatever ruleset is currently deployed to the named
database. `npm run rules:release -- show --database staging` prints it; dispatch the staging deploy
to rehearse a candidate ruleset first.

## What the fake shows, and what it cannot

The fake accepts writes, so forms, claims, shares, leaves and deletes run the real use case,
the real repository and the real widget. A reload re-seeds it, so a broken experiment costs a
reload rather than a rebuild.

It cannot show: rules enforcement, composite-index errors, server timestamps, cross-client
real-time fan-out, platform plugins (share, external links, sign-in sheets), or the auth
screens. A success here is a success of the widgets and the query composition, not a promise
that production would accept the same write. Live mode is the check for the first four.

## Boundaries

- `lib/main.dart` never imports anything under `lib/dev/`, and no production bundle contains
  the fake store: `test/dev/no_dev_in_production_test.dart` walks the import graph.
- The banner's key carries `devBundleMarker` (`wishtogether-dev-session`), the literal a CI
  bundle guard searches the compiled production bundle for. Every dev page carries it, including
  the failure pages.
- Fake mode never calls `Firebase.initializeApp` and never touches a real Firebase singleton, so
  there is no project, no credential and no network. `live_dev_session.dart` is the one file
  allowed to do so, and the boundary test names exactly that file (and fails if it is renamed
  without updating the list).
- In fake mode the shell resolves `AuthSession` only. `AuthService` is registered but throws when
  resolved, so the sign-in, verification and deletion screens are unbuildable there; the home page
  hides its sign-out control and the profile page hides the danger zone rather than offering
  controls that cannot work. Live mode has the real service, so both controls are present and real.
- `setupServiceLocator` is single-shot: a second call in one process throws. A reload is a new
  process, which is why a dev scenario never needs a reset.
