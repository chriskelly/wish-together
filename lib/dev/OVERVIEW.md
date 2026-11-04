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
| `dev_banner.dart` | `DevSessionFrame`: the strip above every page plus the one accessibility node naming what is on screen. Tones: `scenario`, `live`, `starting`, `refused`. |
| `dev_notice_screen.dart` | `DevNoticeScreen` (headline + details + one semantics node), the shared page theme, and the pages for an unknown scenario, a refused launch and a launch still starting. |
| `theme_gallery.dart` | `ThemeGallery`: every primitive and the component states no scenario reaches (dialog, snackbar, chip tones, pills, form fields, empty state), following the platform brightness. |
| `gallery_main.dart` | The gallery's own entrypoint; nothing in `lib/main.dart` imports it. |
| `run_dev_session.dart` | The fake composition (`buildDevApp(fixture)`, `buildDevAppForScenario(id)`), `composeDevApp` — the shell both backends run — the `runDevSession*` entrypoint helpers, and the browser preparation. |
| `fixtures/dev_fixture.dart` | `DevFixture` and the seeding loop. |
| `fixtures/registry.dart` | Scenario id → fixture, with a loud failure for an unknown id. |
| `fixtures/default_scenario.dart` | The scenario shown when nothing else is asked for. |
| `fixtures/scenario_items.dart` | `devItems` (N generated items in one call) and `devItemFields` (one item document). |
| `fixtures/family_scenario.dart` | The multi-family dataset: ten people, three groups, eleven wishlists. |
| `fixtures/large_wishlist_scenario.dart` | Fifty items in one wishlist. |
| `fixtures/empty_scenario.dart` | A signed-in account with no lists and no groups. |
| `fixtures/overflow_scenario.dart` | Long text in every place a layout can hold it. |
| `fixtures/shared_scenario.dart` | A group-shared wishlist with other members' claims. |

## Running it

`tool/dev.sh` is the one command per backend. The agent-facing guide — commands, scenario
URLs, interaction and screenshot recipes, and the limits of the fake — is
`.agents/skills/dev-session/SKILL.md`.

```sh
# the in-memory fixture: no credentials, no network. Prints the URL it serves.
tool/dev.sh
tool/dev.sh family /wishlist/fam-l1

# real Auth and real Firestore, on a named database only
GOOGLE_APPLICATION_CREDENTIALS=... tool/dev.sh live --uid <uid> --database staging

# the theme gallery: primitives and component states no scenario reaches
tool/dev.sh --entrypoint lib/dev/gallery_main.dart
```

The runner serves fake mode headless on port 47923 (move it with `--port`); `--chrome` opens
the same URL in Chrome instead. For live mode it mints the token itself and pins port 59922.
The raw commands, when the runner is unavailable:

```sh
flutter run -t lib/dev/dev_main.dart -d chrome

flutter run -t lib/dev/dev_main.dart -d chrome --web-port=59922 \
  --dart-define=WT_DEV_BACKEND=live \
  --dart-define=WT_FIRESTORE_DATABASE=staging \
  --dart-define=WT_DEV_TOKEN=<token from `cd scripts && npm run dev:token`>
```

| Input | Effect |
| ----- | ------ |
| the page path | the route, e.g. `/wishlist/dev-l1` |
| `?scenario=<id>` | the fixture, read once at startup. Meaningless in live mode: ignored, and the banner says so |
| `--dart-define=WT_DEV_SCENARIO=<id>` | the fixture when the URL names none (fake only) |
| `--dart-define=WT_DEV_BACKEND=` | unset or `fake` for the in-memory backend; `live` for the real one; anything else is a page naming both |
| `--dart-define=WT_FIRESTORE_DATABASE=<id>` | live only: the named database. Empty means production and is refused, as is `(default)` |
| `--dart-define=WT_DEV_TOKEN=<token>` | live only: the custom token from `cd scripts && npm run dev:token` |
| `--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true` | live only: offers account deletion, which is otherwise hidden |
| `--web-port=59922` | live only: the port the project's API key allows (see Live mode) |

An unknown scenario id renders a page naming the ids that exist rather than leaving a blank tab:
an agent must never silently see the wrong data. Every launch that cannot run — unknown backend,
refused database, missing or rejected token — is a page naming the fix for the same reason.

The scenario query is **not** preserved by in-app navigation — go_router rewrites the location and
drops it. Open the scenario URL directly, or reload on it, rather than clicking around and then
reloading.

A one-off fixture is its own entrypoint kept out of git under
`lib/dev/scenarios/local/`; see [One-off scenarios](#one-off-scenarios) for the
template and the command.

## Scenarios

Six datasets are registered. Every URL below is the page **plus**
`?scenario=<id>`: the query is what selects the fixture, and it is read only at
startup.

| Id | What it shows | Open |
| -- | ------------- | ---- |
| `default` | Two wishlists the viewer owns, one shared list owned by somebody else, one group, one claimed item. | `/` |
| `family` | Ten people, three overlapping groups, eleven wishlists, eighty-six items, claims on owned and on shared lists. The shape of `seed-demo.mjs` with an invented cast and renamed items. | `/` |
| `large-wishlist` | Fifty items in one list, generated, for scrolling and performance. | `/wishlist/lg-l1` |
| `empty` | A signed-in account with no wishlists and no groups. | `/` |
| `overflow` | Long display, group and wishlist names, an unbroken item name, a long link and a long description. | `/wishlist/ovf-l1` |
| `shared` | A group the viewer belongs to, a wishlist another member shared with it, and claims by that member and by the viewer. | `/group/shr-g1` or `/wishlist/shr-l2` |

The overflow scenario's group page (`/group/ovf-g1`) is worth opening too: its
member row overflows when the name is unbroken, which is the layout gap the
scenario exists to expose. It is not part of the automated URL suite for that
reason; the member row is the code that needs the fix, not the fixture.

The document ids each scenario exposes:

| Scenario | Ids |
| -------- | --- |
| `default` | users `dev-u1`–`dev-u3`, group `dev-g1`, wishlists `dev-l1`–`dev-l3`, items `dev-i1`–`dev-i7` |
| `family` | users `fam-u1`–`fam-u10`, groups `fam-g1`–`fam-g3`, wishlists `fam-l1`–`fam-l11`, items `fam-i01`–`fam-i86` |
| `large-wishlist` | user `lg-u1`, wishlist `lg-l1`, items `lg-i01`–`lg-i50` |
| `empty` | user `emp-u1`, and nothing else |
| `overflow` | users `ovf-u1`–`ovf-u3`, group `ovf-g1`, wishlists `ovf-l1`–`ovf-l2`, items `ovf-i1`–`ovf-i5` |
| `shared` | users `shr-u1`–`shr-u4`, group `shr-g1`, wishlists `shr-l1`–`shr-l2`, items `shr-i1`–`shr-i6` |

Worth opening directly:

- `/wishlist/fam-l1?scenario=family` is Bea's list, shared with two of the
  viewer's groups. The viewer is a reader, so its claims are visible.
- `/wishlist/fam-l11?scenario=family` is the viewer's own list with claims on it,
  so the spoiler toggle has something to hide and reveal.
- `/wishlist/shr-l2?scenario=shared` is another member's list; `shr-i5` is claimed
  by a third member and `shr-i6` by the viewer, so both claimed renderings are on
  one screen.
- `/wishlist/ovf-l1?scenario=overflow` holds the long-name, long-link and
  long-description probes.

A fixture cannot store spoiler mode: it is a per-view toggle on the wishlist
details page, on by default for the owner and absent for a reader. To see an
owned list's claims, press **Show claimed status**; to see claims without
pressing anything, open a list the viewer does not own.

The names and the relationships behind each id are in that scenario's module;
the tables above are only the handles an agent needs to write a URL.

## Authoring a scenario

A committed scenario is one Dart module plus one registry line.

1. Create `lib/dev/fixtures/<name>_scenario.dart` with a top-level `final
   DevFixture`. Its `id` is what `?scenario=` names, and the registry uses that
   id as its key, so the URL, the banner and the registry cannot disagree. The
   `viewerUid` needs a `users/<uid>` document with a non-empty `displayName`;
   without one every route redirects to onboarding.
2. Write the documents as Firestore-shaped maps keyed by full path.
   `devItemFields` writes one item; `devItems` generates N under a wishlist in
   one call, with ids you choose. A claim needs both `claimedBy` and a
   `Timestamp` `claimedAt`: `ItemRepository` casts that field, so an ISO-8601
   string throws when the item is read back.
3. Register it in `fixtures/registry.dart` — one import, one map entry.
4. `flutter test test/dev/dev_fixture_test.dart` sweeps every registered
   scenario: every document parses through its model, each id names one
   document, the viewer has a display name, and every owner, member, shared
   group, parent wishlist and claimer refers to a document the scenario seeds.
   It also holds the sharing convention: this library shares a list only with
   groups whose members include its owner, so ordinary screens show ordinary
   data. `test/dev/scenario_library_test.dart` pins the
   documented ids and the property the scenario exists to provide (a count, a
   claim spread, a probe length); add to it when that property changes, not for
   the literal contents. Add one mount test in
   `test/dev/scenario_urls_test.dart` for the scenario's **Open** URL: that
   handle is what an agent copies, so it is the one thing the data tests cannot
   prove.
5. Add a row to the Layout table, the scenarios table and the document-ids
   table above.

Keep the data plausible and self-consistent: a group's owner is one of its
members, a list is shared only with groups that exist and that the owner belongs
to, and a claim names a person in the scenario. Use fixed timestamps; a fixture
must not read the clock, or a screenshot and a test drift apart.

## One-off scenarios

A one-off is a private fixture in its own entrypoint under
`lib/dev/scenarios/local/`, which is gitignored. It cannot live in the registry:
Dart needs a compile-time import, and a tracked file that imports a missing one
breaks a fresh clone. Nothing imports the entrypoint, so the directory being
absent is a clean tree.

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
flutter run -t lib/dev/scenarios/local/mine.dart -d chrome
```

The path is the route, the same as the committed entrypoint, and the banner
names the fixture's `id`. `flutter analyze` checks the file; `flutter test` never
compiles it. A change to a one-off costs a restart, not a reload.

To vary a scenario that already exists, import it instead of rebuilding it:

```dart
import 'package:wishtogether/dev/fixtures/family_scenario.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

void main() => runDevSession(familyFixture);
```

## Live mode

Live mode signs in for real, so it is the check for everything the fake cannot enforce: security
rules, composite indexes, server timestamps, cross-client real-time fan-out, and the shape of real
data. It is also the only mode that runs the real `AuthService` — the uid stream, the providers and
sign-out are production's own. Account deletion does not: see below.

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
refusal is its own page. They are decided in one fixed order: the backend first, then the database
(empty, then production, then a malformed id), then the token, then the account-deletion flag. The
first failure in that order is the page a reader gets, so a bad backend is reported as a bad backend
even when the database is wrong too.

| Refusal page | Cause |
| ------------ | ----- |
| `WT_DEV_BACKEND="<value>" is not a backend this build can run` | anything other than `fake` or `live`; checked first |
| `Live dev mode needs a named database` | `WT_FIRESTORE_DATABASE` is unset or blank, which means the production database |
| `Live dev mode refuses the production database` | `WT_FIRESTORE_DATABASE="(default)"` |
| `WT_FIRESTORE_DATABASE="<value>" is not a database id` | malformed id (lowercase, 4–63 characters, starts with a letter) |
| `Live dev mode needs a token` | `WT_DEV_TOKEN` is unset or blank |
| `WT_DEV_ALLOW_ACCOUNT_DELETION="<value>" is not a flag value` | anything other than `true`, `false` or unset; the value is trimmed first, so `" true "` enables deletion |
| `Live dev mode could not sign in` | the token expired or was rejected, or the page's origin is not one the project API key allows; names `npm run dev:token` and the port |
| `Live dev mode could not start` | `initializeApp`, or the session built on it, failed |

A token lasts about an hour. `--dart-define` is compile-time, so a fresh token means stopping the
app and running the line again — a hot restart keeps the old one.

While the token is exchanged the page is a notice (`Live dev mode is signing in`, on the `starting`
strip), so the window before the session exists is never a blank tab. It is replaced by the app, or
by the reason the sign-in failed.

**The port is not free choice.** The project's browser API key restricts HTTP referrers, and the
only localhost entry it allows is `http://localhost:59922/*`, so live sign-in works on
`--web-port=59922` and no other. Any other port fails at sign-in with an API-key error, which the
failure page names. `.agents/skills/preview-auth/scripts/preview-auth.sh list` prints the allowed
referrers. Two concurrent sessions (the only way to see cross-client behaviour) would need a second
port added to that key, which is an operator change, not something this harness does.

**Account deletion is off unless the build asks for it.** The live session is a real `AuthService`
with one capability removed, so the profile page has no danger zone: the cascade re-authenticates
against the real provider and then deletes a real Auth user, and this Auth project is shared with
production. To exercise that flow on purpose, add `--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true`
— and only ever with a synthetic uid, because the account it deletes is the one it signed in as.

**Sign-out really signs out.** The home page's Logout control ends the session and returns to the
login page, which builds here (the real `AuthService` is registered) but cannot sign back in from
localhost, because no OAuth origin is allowlisted for it. Getting back into a live session means a
new token and a restart.

App Check is not activated by this path, the update gate is not part of it (so a production
`min_supported_build` cannot block a live session), and Sentry is not initialised.

**Which rules apply.** Live mode runs against whatever ruleset is currently deployed to the named
database. `npm run rules:release -- show --database staging` prints it; dispatch the staging deploy
to rehearse a candidate ruleset first.

## What the fake serves

Every Firestore operation a signed-in page issues is served by `FakeFirebaseFirestore`, so a
form, claim, share, leave or delete runs the real use case, the real repository and the real
widget. `test/dev/fake_parity_test.dart` pins one test per operation, and its header names the
page behind each one:

| Page | Operation |
| ---- | --------- |
| router, profile | `users/{uid}` read by id, create when missing, `updateData` for one field |
| home | `users` by id (stream); `wishlists` where `ownerId == uid`; `groups` where `members` contains uid |
| wishlist details | `wishlists/{id}` stream; `wishlists/{id}/items` stream, add, update, delete |
| item claim and unclaim | item `update` carrying a `Timestamp`; `updateData` clearing `claimedBy` and `claimedAt` together |
| group details | `users` by `documentId whereIn`; `wishlists` where `sharedWithGroups` contains the group; `groups` `updateData` with `arrayUnion` / `arrayRemove` |
| account deletion (not offered in dev) | one-shot `listWhere` reads; the paged batch delete in `WishlistRepository.deleteWithItems` |

A write reaches a stream that is already open, which is what makes a create or a claim appear
without a reload. A reload re-seeds, so a broken experiment costs a reload rather than a
rebuild.

Two behaviours match Firestore rather than diverging from it, and are worth knowing because
they shape what a page shows: a document read of a path that does not exist emits a snapshot
with `exists == false`, and `fromFirestore` throws on the null data, so a page's "not found"
state arrives through its error path instead of as a null model; an `update` on a missing
document fails `not-found`.

## Divergences: what a fake-mode success does not prove

Read this before reporting "works" from a dev session. The fake-dependent items are pinned by a
test in `test/dev/fake_parity_test.dart`, green under the `fake_cloud_firestore` that
`pubspec.lock` pins, so a dependency upgrade that changes the gap fails loudly. The others
cannot be exercised in one process, or are app behaviour the harness reproduces faithfully.

1. **Rules are not enforced.** No document is denied; any write the app composes succeeds. A
   write the real `firestore.rules` would reject is indistinguishable from a working one here.
2. **No composite-index errors.** The fake answers any query it understands, so a query that
   would need an index in production passes here. Today every app query is single-field or
   `array-contains`, so none needs one — a property of the current queries, not a guarantee the
   fake gives.
3. **`FieldValue.serverTimestamp()` is resolved at write time by the client clock.** The stored
   value is already a `Timestamp`; Firestore resolves it on the server and shows a pending
   estimate first. A scenario cannot model the pending state, nor a server clock that differs
   from this machine's.
4. **A batch commit is sequential, not atomic.** `MockWriteBatch.commit` applies each task in
   order; when a later task fails, the earlier ones stay applied. Firestore rolls the whole
   batch back, so a fake-mode success cannot prove a multi-document write is atomic.
5. **One client.** There is no cross-client fan-out: "does the other parent see this
   immediately" needs two real sessions.
6. **The 30-value `whereIn` cap is enforced per document.** Firestore rejects an over-limit
   query whatever the data; the fake throws only once it evaluates a document, and returns an
   empty list when the collection is empty. `UserRepository.streamUsersFromIds` does not chunk,
   so a group with 31 or more members fails the members read on both backends — a limit of the
   app that a sparse fixture can hide.
7. **Deleting a wishlist does not cascade.** The home page deletes the wishlist document only
   (`home_page.dart:321`); `deleteWithItems`, which pages through the items first, is reached
   only from account deletion. A dev session therefore shows the wishlist gone while its item
   documents remain, exactly as production does today. The app-side gap is tracked in #102; the
   fake neither hides nor fixes it.
8. **Platform plugins are inert.** Share, external-URL launch and sign-in sheets either no-op
   or depend on the browser. Everything up to the plugin call can be verified; the call itself
   cannot.
9. **Auth transitions are not modelled.** One fixed signed-in identity: no sign-in, no
   sign-out, no account deletion, and no auth screens. `group_details_page.dart` force-unwraps
   `currentUserId`, so a signed-out session would throw rather than degrade.
10. **Nothing persists.** The store lives in the process; a reload re-seeds it, and there is no
    offline or cache behaviour to observe (`metadata.hasPendingWrites` is always false).

A fake-mode success is a success of the widgets and the query composition, not a promise that
production accepts the same write.

## Accessible names

A control with no accessible name is one a text-only agent cannot address and a screen reader
cannot announce. The conventions, so a new screen stays drivable:

- Icon-only controls carry a `tooltip` (`'Add item'`, `'Edit'`, `'Delete Wishlist'`, …). On web
  the engine folds the tooltip into the DOM label; the mobile screen readers announce it. A
  bare `IconButton` or `FloatingActionButton` with no tooltip is a gap.
- A `ListTile` merges its title and subtitle into one label. Where both must be addressable
  separately, wrap the subtitle in `Semantics(container: true, …)`: the row keeps the title as
  its name and the subtitle becomes its own node.
- Select by exact label rather than by substring: `find.semantics.byLabel` matches the whole
  label, and `find.text` matches the whole string.
- `test/dev/dev_flows_test.dart` asserts the two names the field test found missing, and
  `test/dev/dev_banner_test.dart` asserts the scenario name reaches the tree.

## Boundaries

- `lib/main.dart` never imports anything under `lib/dev/`, and no production bundle contains
  the fake store: `test/dev/no_dev_in_production_test.dart` walks the import graph.
- The banner's key carries `devBundleMarker` (`wishtogether-dev-session`), the literal a CI
  bundle guard searches the compiled production bundle for. Every dev page carries it, the
  failure pages included.
- Fake mode never calls `Firebase.initializeApp` and never touches a real Firebase singleton, so
  there is no project, no credential and no network. `live_dev_session.dart` is the one file
  allowed to do so; the boundary test names exactly that file, and fails if it is renamed without
  updating the list. Because the entrypoint imports that file, a dev build does link the Firebase
  Auth and Firestore web plugins — registration only; the fake branch never initialises them, so
  nothing is contacted.
- In fake mode the shell resolves `AuthSession` only. `AuthService` is registered but throws when
  resolved, so the sign-in, verification and deletion screens are unbuildable there; the home page
  hides its sign-out control and the profile page hides the danger zone rather than offering
  controls that cannot work. A live session has the real service, so sign-out is live and the
  danger zone is behind the opt-in.
- `setupServiceLocator` is single-shot: a second call in one process throws. A reload is a new
  process, which is why a dev scenario never needs a reset.
