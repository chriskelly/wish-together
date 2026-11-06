# Dev scenarios

Scope: what a dev session is, how its files fit together, and the six scenarios
it can open. Read before opening a screen locally or adding a scenario. Paths
are relative to `lib/dev/`, then to the repository root.

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

`dev_main.dart` resolves the launch and dispatches to the fake, live or refusal path; the
compile-time defines and the pure launch rules live in `dev_config.dart`. `run_dev_session.dart`
builds the fake composition and `live_dev_session.dart` the live backend, both through
`composeDevApp`; the banner, notice screens and theme gallery sit beside them, and the gallery
covers the primitives and component states no scenario reaches.

Fixtures live under `fixtures/`: `fixtures/dev_fixture.dart` owns `DevFixture` and the seeding
loop, `fixtures/registry.dart` maps a scenario id to its fixture, and one module per scenario
builds the documents. To see the current files, run `ls lib/dev lib/dev/fixtures`; to see the
registered ids, read `fixtures/registry.dart`.

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

The document ids follow the scenario's short prefix — `dev`, `fam`, `lg`, `emp`, `ovf`, `shr` —
then a kind letter (`u` user, `g` group, `l` wishlist, `i` item) and a number. Hand-written item
ids count from `1` (`dev-i1`, `shr-i6`); the generated sets in `family` and `large-wishlist`
zero-pad to two digits (`fam-i01`). Each scenario's module builds its own ids and holds the names
and relationships; `test/dev/scenario_library_test.dart` pins the exact set. Read either to find
one, and use the scenario table above for start URLs.

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
