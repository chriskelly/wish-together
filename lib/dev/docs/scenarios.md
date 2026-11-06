# Dev scenarios

Scope: what a dev session is, the files that make it, and the six registered
scenarios with the document ids each exposes. Read before opening a screen
locally or adding a scenario. Paths are relative to `lib/dev/`, then to the
repository root.

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

## The six scenarios

Every URL below is the page **plus** `?scenario=<id>`: the query is what selects the fixture,
and it is read only at startup.

| Id | What it shows | Open |
| -- | ------------- | ---- |
| `default` | Two wishlists the viewer owns, one shared list owned by somebody else, one group, one claimed item. | `/` |
| `family` | Ten people, three overlapping groups, eleven wishlists, eighty-six items, claims on owned and on shared lists. The shape of `scripts/seed-demo.mjs` with an invented cast and renamed items. | `/` |
| `large-wishlist` | Fifty items in one list, generated, for scrolling and performance. | `/wishlist/lg-l1` |
| `empty` | A signed-in account with no wishlists and no groups. | `/` |
| `overflow` | Long display, group and wishlist names, an unbroken item name, a long link and a long description. | `/wishlist/ovf-l1` |
| `shared` | A group the viewer belongs to, a wishlist another member shared with it, and claims by that member and by the viewer. | `/group/shr-g1` or `/wishlist/shr-l2` |

The overflow scenario's group page (`/group/ovf-g1`) is worth opening too: its member row
overflows when the name is unbroken, which is the layout gap the scenario exists to expose. It
is not part of the automated URL suite for that reason; the member row is the code that needs
the fix, not the fixture.

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

- `/wishlist/fam-l1?scenario=family` is Bea's list, shared with two of the viewer's groups. The
  viewer is a reader, so its claims are visible.
- `/wishlist/fam-l11?scenario=family` is the viewer's own list with claims on it, so the spoiler
  toggle has something to hide and reveal.
- `/wishlist/shr-l2?scenario=shared` is another member's list; `shr-i5` is claimed by a third
  member and `shr-i6` by the viewer, so both claimed renderings are on one screen.
- `/wishlist/ovf-l1?scenario=overflow` holds the long-name, long-link and long-description probes.

A fixture cannot store spoiler mode: it is a per-view toggle on the wishlist details page, on by
default for the owner and absent for a reader. To see an owned list's claims, press **Show claimed
status**; to see claims without pressing anything, open a list the viewer does not own.

The names and the relationships behind each id are in that scenario's module; the tables above
are only the handles an agent needs to write a URL.
