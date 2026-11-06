# Fake mode

Scope: running the in-memory backend, authoring a fixture, and what the fake
Firestore actually serves. Read before adding a scenario or reporting that a
screen "works" from a dev session. Paths are relative to `lib/dev/` unless they
start with `lib/` or `test/`.

## Running it

`tool/dev.sh` is the one command per backend; the agent-facing recipe — commands, scenario
URLs, interaction and screenshot recipes — is `.agents/skills/dev-session/SKILL.md`.

```sh
# the in-memory fixture: no credentials, no network. Prints the URL it serves.
tool/dev.sh
tool/dev.sh family /wishlist/fam-l1

# the theme gallery: primitives and component states no scenario reaches
tool/dev.sh --entrypoint lib/dev/gallery_main.dart
```

The runner serves fake mode headless on port 47923 (move it with `--port`); `--chrome` opens
the same URL in Chrome instead. The raw command, when the runner is unavailable:

```sh
flutter run -t lib/dev/dev_main.dart -d chrome
```

| Input | Effect |
| ----- | ------ |
| the page path | the route, e.g. `/wishlist/dev-l1` |
| `?scenario=<id>` | the fixture, read once at startup |
| `--dart-define=WT_DEV_SCENARIO=<id>` | the fixture when the URL names none |
| `--dart-define=WT_DEV_BACKEND=` | unset or `fake` for the in-memory backend; `live` for the real one; anything else is a page naming both |

An unknown scenario id renders a page naming the ids that exist rather than leaving a blank tab:
an agent must never silently see the wrong data.

The scenario query is **not** preserved by in-app navigation — go_router rewrites the location and
drops it. Open the scenario URL directly, or reload on it, rather than clicking around and then
reloading.

## Authoring a scenario

A committed scenario is one Dart module plus one registry line.

1. Create `lib/dev/fixtures/<name>_scenario.dart` with a top-level `final DevFixture`. Its `id`
   is what `?scenario=` names, and the registry uses that id as its key, so the URL, the banner
   and the registry cannot disagree. The `viewerUid` needs a `users/<uid>` document with a
   non-empty `displayName`; without one every route redirects to onboarding.
2. Write the documents as Firestore-shaped maps keyed by full path. `devItemFields` writes one
   item; `devItems` generates N under a wishlist in one call, with ids you choose. A claim needs
   both `claimedBy` and a `Timestamp` `claimedAt`: `ItemRepository` casts that field, so an
   ISO-8601 string throws when the item is read back.
3. Register it in `fixtures/registry.dart` — one import, one map entry.
4. `flutter test test/dev/dev_fixture_test.dart` sweeps every registered scenario: every document
   parses through its model, each id names one document, the viewer has a display name, and every
   owner, member, shared group, parent wishlist and claimer refers to a document the scenario
   seeds. It also holds the sharing convention: this library shares a list only with groups whose
   members include its owner, so ordinary screens show ordinary data.
   `test/dev/scenario_library_test.dart` pins the documented ids and the property the scenario
   exists to provide (a count, a claim spread, a probe length); add to it when that property
   changes, not for the literal contents. Add one mount test in
   `test/dev/scenario_urls_test.dart` for the scenario's **Open** URL: that handle is what an
   agent copies, so it is the one thing the data tests cannot prove.
5. Add a row to the Layout table, the scenarios table and the document-ids table in
   `docs/scenarios.md`.

Keep the data plausible and self-consistent: a group's owner is one of its members, a list is
shared only with groups that exist and that the owner belongs to, and a claim names a person in
the scenario. Use fixed timestamps; a fixture must not read the clock, or a screenshot and a test
drift apart.

## One-off scenarios

A one-off is a private fixture in its own entrypoint under `lib/dev/scenarios/local/`, which is
gitignored. It cannot live in the registry: Dart needs a compile-time import, and a tracked file
that imports a missing one breaks a fresh clone. Nothing imports the entrypoint, so the directory
being absent is a clean tree.

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

The path is the route, the same as the committed entrypoint, and the banner names the fixture's
`id`. `flutter analyze` checks the file; `flutter test` never compiles it. A change to a one-off
costs a restart, not a reload. To vary a scenario that already exists, import it instead of
rebuilding it (`import .../family_scenario.dart;` then `runDevSession(familyFixture)`).

## What the fake serves

Every Firestore operation a signed-in page issues is served by `FakeFirebaseFirestore`, so a
form, claim, share, leave or delete runs the real use case, the real repository and the real
widget. `test/dev/fake_parity_test.dart` pins one test per operation, and its header names the
page behind each one:

| Page | Operation |
| ---- | --------- |
| router, profile | `users/{uid}` read by id, create when missing, `updateData` for one field |
| home | `users` by id (stream); `wishlists` where `ownerId == uid`; `groups` where `members` contains uid; deleting a wishlist pages its `items` and batch-deletes them before the wishlist document (pinned in `test/features/wishlist/data/wishlist_repository_test.dart`) |
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
