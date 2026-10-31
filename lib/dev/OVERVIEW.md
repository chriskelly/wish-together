# Dev — Overview

A development entrypoint that boots the app **signed in**, on the real widgets, against an
in-memory Firestore seeded from a Dart fixture. It exists so an agent (or the user) can see,
drive and screenshot any signed-in screen without a credential, a deployment or a real sign-in.

## Responsibility

- Compose the production app shell over a fake backend, through the same `setupServiceLocator`
  seams production uses.
- Choose a scenario and a route from the page URL, so a screenshot is a URL.
- Mark the build visibly, so a screenshot cannot be mistaken for the real app.

Not in scope: a production-visible debug menu, screenshot tooling, or any affordance reachable
from `lib/main.dart`.

## Layout

| File | Role |
| ---- | ---- |
| `dev_main.dart` | The committed entrypoint: reads the URL and the defines, resolves a fixture, boots. |
| `dev_config.dart` | Define names, the bundle marker literal, and the pure resolution rules. |
| `dev_session.dart` | `DevAuthSession implements AuthSession`: the session's identity, no Firebase. |
| `dev_banner.dart` | The strip above every page naming the active scenario. |
| `run_dev_session.dart` | `buildDevApp(fixture)` (composition, used by tests) and `runDevSession(fixture)` (the one-off entrypoint helper). |
| `fixtures/dev_fixture.dart` | `DevFixture` and the seeding loop. |
| `fixtures/registry.dart` | Scenario id → fixture, with a loud failure for an unknown id. |
| `fixtures/default_scenario.dart` | The scenario shown when nothing else is asked for. |

## Running it

```sh
flutter run -t lib/dev/dev_main.dart -d chrome
```

| Input | Effect |
| ----- | ------ |
| the page path | the route, e.g. `/wishlist/dev-l1` |
| `?scenario=<id>` | the fixture, read once at startup |
| `--dart-define=WT_DEV_SCENARIO=<id>` | the fixture when the URL names none |
| neither | the `default` scenario |
| `--dart-define=WT_DEV_BACKEND=fake` | the in-memory backend; anything else stops the launch |

An unknown scenario id fails the launch and lists the available ids: an agent must never
silently see the wrong data.

The query is **not** preserved by in-app navigation — go_router rewrites the location and drops
it. Open the scenario URL directly, or reload on it, rather than clicking around and then
reloading.

A one-off fixture is its own entrypoint, three lines, kept out of git under
`lib/dev/scenarios/local/`:

```dart
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

void main() => runDevSession(myFixture);
```

## What the fake shows, and what it cannot

The fake accepts writes, so forms, claims, shares, leaves and deletes run the real use case,
the real repository and the real widget. A reload re-seeds it, so a broken experiment costs a
reload rather than a rebuild.

It cannot show: rules enforcement, composite-index errors, server timestamps, cross-client
real-time fan-out, platform plugins (share, external links, sign-in sheets), or the auth
screens. A success here is a success of the widgets and the query composition, not a promise
that production would accept the same write.

## Boundaries

- `lib/main.dart` never imports anything under `lib/dev/`, and no production bundle contains
  the fake store: `test/dev/no_dev_in_production_test.dart` walks the import graph.
- The banner's key carries `devBundleMarker` (`wishtogether-dev-session`), the literal a CI
  bundle guard searches the compiled production bundle for.
- Fake mode never calls `Firebase.initializeApp` and never touches a real Firebase singleton, so
  there is no project, no credential and no network.
- The shell resolves `AuthSession` only. `AuthService` is registered but throws when resolved, so
  the sign-in, verification and deletion screens are unbuildable here; the home page hides its
  sign-out control and the profile page hides the danger zone rather than offering controls that
  cannot work.
- `setupServiceLocator` is single-shot: a second call in one process throws. A reload is a new
  process, which is why a dev scenario never needs a reset.
