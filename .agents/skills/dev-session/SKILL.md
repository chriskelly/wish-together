---
name: dev-session
description: Boot WishTogether signed in on the real widgets from an in-memory Dart fixture (no credentials) or against a named Firestore database with a real token, then drive and screenshot any signed-in screen. Use when you need to see, click through, or screenshot the app without deploying, check a screen's layout, reproduce a UI bug, or exercise real rules and queries against staging.
---

# Dev session

The dev session boots the real app shell **signed in**, without a deployment. It
exists so an agent can reach a signed-in screen, press its controls and read the
result, instead of reasoning about widgets from source alone.

There are two backends:

- **fake** (default) — an in-memory Firestore seeded from a Dart fixture. No
  credentials, no network, and a reload restores a known state.
- **live** — real Firebase Auth and real Firestore on a **named** database. It
  is the check for security rules, composite indexes, server timestamps,
  cross-client fan-out and the shape of real data.

Live mode refuses the production database. Neither backend is reachable from the
production app.

## Commands

```sh
# fake: headless, prints the URL it serves
tool/dev.sh
tool/dev.sh family                       # a committed scenario
tool/dev.sh large-wishlist /wishlist/lg-l1

# fake: a private entrypoint kept out of git
tool/dev.sh --entrypoint lib/dev/scenarios/local/mine.dart /wishlist/mine-l1

# live: real Auth + real Firestore, on the staging database
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  tool/dev.sh live --uid <synthetic-uid> --database staging
```

| Command | Effect |
| ------- | ------ |
| `tool/dev.sh [scenario] [path]` | fake, headless on port 47923. `path` is the route to start on (`/` by default); a lone path is the route |
| `tool/dev.sh live [path] --uid <uid>` | live on the named database (default `staging`), always port 59922 |
| `--chrome` | launch Chrome at the printed URL instead of serving headless |
| `--port <port>` | fake only, except the pinned 59922 in live: move the fake port off 47923 |
| `--entrypoint <file> [path]` | fake only: run a one-off entrypoint instead of the committed one |
| `--allow-account-deletion` | live only: offer account deletion. It deletes a real Auth account; only with a synthetic uid |
| `-- <args>` | append arguments to the `flutter run` command |

The runner prints the exact URL it serves (including the scenario query, when
there is one) before the server starts. Open that URL; do not guess a port. It
fails with a readable line for an unknown scenario id, a missing live uid or
credentials, a missing `scripts/node_modules`, or the production database.

Raw equivalents, if the runner is unavailable:

```sh
flutter run -t lib/dev/dev_main.dart -d chrome
flutter run -t lib/dev/dev_main.dart -d chrome --web-port=59922 \
  --dart-define=WT_DEV_BACKEND=live \
  --dart-define=WT_FIRESTORE_DATABASE=staging \
  --dart-define=WT_DEV_TOKEN=<token from `cd scripts && npm run dev:token`>
```

## Scenarios

The query **is** the scenario: every URL below is the page plus
`?scenario=<id>`. It is read once at startup.

The runner starts at `/` unless you give it the page too: `tool/dev.sh
large-wishlist /wishlist/lg-l1` selects the scenario and the page, while
`tool/dev.sh /wishlist/dev-l1` keeps the default scenario and starts on that
page. The table's URL is also what you open by hand.

| Id | Start URL | What it shows | Document ids |
| -- | --------- | ------------- | ------------ |
| `default` | `/` | Two wishlists the viewer owns, one shared list owned by somebody else, one group, one claimed item. | users `dev-u1`–`dev-u3`, group `dev-g1`, lists `dev-l1`–`dev-l3`, items `dev-i1`–`dev-i7` |
| `family` | `/` | Ten people, three overlapping groups, eleven lists, eighty-six items, claims on owned and shared lists — the `seed-demo` shape with an invented cast. | users `fam-u1`–`fam-u10`, groups `fam-g1`–`fam-g3`, lists `fam-l1`–`fam-l11`, items `fam-i01`–`fam-i86` |
| `large-wishlist` | `/wishlist/lg-l1` | Fifty generated items in one list, for scrolling and performance. | user `lg-u1`, list `lg-l1`, items `lg-i01`–`lg-i50` |
| `empty` | `/` | A signed-in account with no lists and no groups. | user `emp-u1` only |
| `overflow` | `/wishlist/ovf-l1` | Long names, an unbroken item name, a long link and description. | users `ovf-u1`–`ovf-u3`, group `ovf-g1`, lists `ovf-l1`–`ovf-l2`, items `ovf-i1`–`ovf-i5` |
| `shared` | `/group/shr-g1` or `/wishlist/shr-l2` | A group-shared list and claims by another member and by the viewer. | users `shr-u1`–`shr-u4`, group `shr-g1`, lists `shr-l1`–`shr-l2`, items `shr-i1`–`shr-i6` |

Useful deep links:

- `/wishlist/fam-l1?scenario=family` — a list the viewer reads; another member's
  claim is visible without pressing anything.
- `/wishlist/fam-l11?scenario=family` — the viewer's own list; press **Show
  claimed status** to reveal claims (spoiler mode is a per-view toggle, and a
  fixture cannot store it).
- `/wishlist/shr-l2?scenario=shared` — another member's list; `shr-i5` is claimed
  by a third member and `shr-i6` by the viewer.

`lib/dev/OVERVIEW.md` has the same tables next to the fixtures.

## Drive it as a text-only agent

The entrypoint turns Flutter's accessibility tree on
(`SemanticsBinding.instance.ensureSemantics()`), so widgets are addressable by
role and label. Do not click pixel coordinates.

1. **Open the scenario URL directly** in the browser pane. The query is the
   entry point, not a setting: in-app navigation drops it, so reloading after
   clicking around falls back to the default scenario.
2. **Read the rendered page** as an accessibility snapshot or text, and address
   widgets by role and label (`button "Add item"`, `text field "Item Name"`). Select
   by exact label where you can; some names are composite (a tile's title and
   subtitle merge), so match those by substring. A control with no accessible
   name cannot be pressed — that is a product accessibility gap, not a reason to
   fall back to coordinates.
3. **Act** — press, type, scroll.
4. **Read the rendered result again** (snapshot or screenshot). This is the
   primary answer to "did it work".
5. **Read the browser console.** The dev entrypoint installs a console `AppLog`
   sink: `routeChanged`, `firestoreError` and `authState` records land there. An
   interaction that appears to do nothing leaves a trace.
6. **Read the address.** `go`-reached pages (home, wishlist details, group
   details) move it; imperatively pushed screens do not.

Example loop: open `/wishlist/dev-l1?scenario=default`, press the **Add item**
button, type a name, press **Save Item**, then read the item in the rendered list
and the `routeChanged` / repository records in the console.

## Screenshot recipe

- Run `tool/dev.sh <scenario>` and open the printed URL in the browser pane.
- Screenshot the pane to a file. The session frame carries the label `Dev
  session · scenario: <id>` (or `Dev session · live data · database: <id>`), and
  the strip at the top of every page shows the same text, so the image states
  which data it shows and cannot be mistaken for the production app.
- With a Superset browser pane, the open, screenshot and console verbs are in the
  `superset-browser` skill; another harness's pane has equivalents.
- Prefer a `go`-reached page (home, wishlist details, group details) for a
  screenshot that its address reproduces. A pushed form (create/edit) is not
  URL-addressable: capture it from the current state and note the route from the
  console instead.

## Author a scenario

A **committed** scenario is one Dart module plus one registry line:

1. Create `lib/dev/fixtures/<name>_scenario.dart` with a top-level
   `final DevFixture`. Its `id` is what `?scenario=` names. Give the
   `viewerUid` a `users/<uid>` document with a non-empty `displayName`, or every
   route redirects to onboarding.
2. Write documents as Firestore-shaped maps keyed by full path. Use `devItems`
   for N generated items and `devItemFields` for one. A claim needs both
   `claimedBy` and a `Timestamp` `claimedAt`; an ISO-8601 string throws when the
   item is read back.
3. Add one import and one map entry in `lib/dev/fixtures/registry.dart`.
4. Run `flutter test test/dev/dev_fixture_test.dart test/dev/scenario_library_test.dart`
   and add a mount test in `test/dev/scenario_urls_test.dart` for its start URL.
5. Add rows to the layout, scenarios and document-id tables in
   `lib/dev/OVERVIEW.md`, and to the scenario table in this skill.

A **private** scenario is a gitignored entrypoint, unreferenced by anything
else, so a fresh clone compiles without it:

```dart
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

final DevFixture myFixture = DevFixture(
  id: 'mine',
  viewerUid: 'dev-u1',
  documents: <String, Map<String, dynamic>>{
    'users/dev-u1': <String, dynamic>{'displayName': 'Ana Dev'},
  },
);

void main() => runDevSession(myFixture);
```

```sh
tool/dev.sh --entrypoint lib/dev/scenarios/local/mine.dart
```

It lives under `lib/dev/scenarios/local/` (gitignored). `flutter analyze` checks
it; `flutter test` never compiles it. Changing it costs a restart, not a reload.

## Limits: what a fake-mode success does not prove

Read this before reporting "works". The full divergence list is in
`lib/dev/OVERVIEW.md`.

- **Rules and composite indexes are not enforced.** A write production would
  deny succeeds here; a query that needs an index passes. Live mode is the check.
- **Batch commits apply sequentially, not atomically.** A later failure leaves
  earlier writes applied.
- **One client.** No cross-client fan-out and no server clock. "Does the other
  parent see this immediately" needs live mode and two sessions.
- **Platform plugins are inert.** Share, external-URL launch and sign-in sheets
  no-op or depend on the browser. Everything up to the plugin call is verifiable.
- **Auth screens are unreachable.** The session is always signed in: no sign-in,
  no sign-out, no account deletion in fake mode. Auth work needs real sign-in.
- **Pushed screens have no URL.** Create/edit forms keep the address of the page
  underneath, and a reload returns there. Only `go`-reached pages are
  address-reproducible.
- **The scenario is an entry URL.** It is read once; in-app navigation drops the
  query. Open the scenario URL rather than navigating and reloading.
- **A deep-linked start emits no `routeChanged`** until the next navigation, so
  the rendered page, not the console, answers "where am I".
- **Live mode needs port 59922.** The project's browser API key allows that one
  localhost origin; every other port fails at sign-in. The runner pins it.

## Pitfalls

- **Reload re-seeds the fixture** (and loses your changes). That is the reset
  button; it is also why an experiment costs a reload rather than a rebuild.
- A committed scenario switches by **reload**; editing a one-off entrypoint needs
  a **restart**.
- A live token lasts **about an hour** and arrives through `--dart-define`, which
  is compile-time: a fresh token means stopping the app and running the command
  again. A hot restart keeps the old one.
- **Account deletion is off in live mode** unless the build opts in with
  `--allow-account-deletion`. It re-authenticates and deletes a real Auth user,
  and staging shares production Auth: use a synthetic uid, never a real account.
- Signing out of a live session cannot sign back in from localhost; mint a new
  token and restart.
- Live data is whatever the named database currently holds: seed with
  `cd scripts && npm run seed:demo` and remove it with `--clean-only` when you
  are done.
