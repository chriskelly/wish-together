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
| `dev_banner.dart` | `DevSessionFrame`: the strip above every page plus the one accessibility node naming the active scenario. |
| `dev_error_screen.dart` | The page shown for a scenario id that does not exist, naming the ids that do. |
| `run_dev_session.dart` | `buildDevApp(fixture)` and `buildDevAppForScenario(id)` (composition, used by tests), the `runDevSession*` entrypoint helpers, and `buildUnknownScenarioApp`. |
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

An unknown scenario id renders a page naming the ids that exist rather than leaving a blank tab:
an agent must never silently see the wrong data.

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

## What the fake serves

Every Firestore operation a signed-in page issues is served by `FakeFirebaseFirestore`, so a
form, claim, share, leave or delete runs the real use case, the real repository and the real
widget. `test/dev/fake_parity_test.dart` pins one test per operation, and its header names the
page behind each one:

| Page | Operation |
| ---- | --------- |
| router, profile | `users/{uid}` read, create, update |
| home | `users` by document id; `wishlists` where `ownerId == uid`; `groups` where `members` contains uid |
| wishlist details | `wishlists/{id}` stream; `wishlists/{id}/items` stream, add, update, delete |
| item claim and unclaim | item `update` carrying a `Timestamp`; `updateData` clearing `claimedBy` and `claimedAt` together |
| group details | `users` by `documentId whereIn`; `wishlists` where `sharedWithGroups` contains the group; `groups` `updateData` with `arrayUnion` / `arrayRemove` |
| account deletion (not offered in dev) | one-shot `listWhere` reads; the paged batch delete in `WishlistRepository.deleteWithItems` |

A write reaches a stream that is already open, which is what makes a create or a claim appear
without a reload. A reload re-seeds, so a broken experiment costs a reload rather than a
rebuild.

## Divergences: what a fake-mode success does not prove

Read this before reporting "works" from a dev session. Each item is either pinned by a test in
`test/dev/fake_parity_test.dart`, so a dependency upgrade that changes it fails loudly, or
listed here because one process cannot model it.

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
7. **A missing document is an error, not a null model.** A document read of a path that does
   not exist emits a snapshot with `exists == false`, and the repositories' `fromFirestore`
   throws on the null data, so a page's "not found" state arrives through its error path. An
   `update` on a missing document fails `not-found`, as it does in production.
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
  bundle guard searches the compiled production bundle for.
- Fake mode never calls `Firebase.initializeApp` and never touches a real Firebase singleton, so
  there is no project, no credential and no network.
- The shell resolves `AuthSession` only. `AuthService` is registered but throws when resolved, so
  the sign-in, verification and deletion screens are unbuildable here; the home page hides its
  sign-out control and the profile page hides the danger zone rather than offering controls that
  cannot work.
- `setupServiceLocator` is single-shot: a second call in one process throws. A reload is a new
  process, which is why a dev scenario never needs a reset.
