# Dev limits and accessibility

Scope: what a fake-mode success does not prove, the naming conventions that keep
a screen drivable by a text-only agent, and the boundaries that keep dev code
out of production. Read before reporting "works" from a dev session. Paths are
relative to `lib/dev/`, then to the repository root.

## Divergences: what a fake-mode success does not prove

The fake-dependent items are pinned by a test in `test/dev/fake_parity_test.dart`, green under the `fake_cloud_firestore` that
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
7. **Platform plugins are inert.** Share, external-URL launch and sign-in sheets either no-op
   or depend on the browser. Everything up to the plugin call can be verified; the call itself
   cannot.
8. **Auth transitions are not modelled.** One fixed signed-in identity: no sign-in, no
   sign-out, no account deletion, and no auth screens. The group details page no longer
   force-unwraps the uid — a signed-out session drops the owner controls, Leave and the Share
   button, and its share dialog lists nothing without querying — but a scenario cannot exercise
   that branch because the fake always has an identity. Its widget test covers it.
9. **Nothing persists.** The store lives in the process; a reload re-seeds it, and there is no
   offline or cache behaviour to observe (`metadata.isFromCache` and
   `metadata.hasPendingWrites` are always false). The wishlist details page's
   "couldn't load" panel therefore needs a live session, not a fake scenario; its widget
   tests cover the panel with a mocked repository.
10. **A transaction is not isolated.** The fake's `runTransaction` runs the handler once against
    the current data, with no retry and no rollback, and applies its `update` without awaiting it,
    so do not rely on write ordering. A fake-mode claim proves the widget and the query shape, not
    the cap under concurrency; the rules tests and the staging smoke test own that.

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

- `test/dev/no_dev_in_production_test.dart` starts at `lib/main.dart`, follows every import and
  export, and fails if the graph reaches `lib/dev/` or `package:fake_cloud_firestore/`.
- The banner's key carries `devBundleMarker` (`wishtogether-dev-session`), the literal a CI
  bundle guard searches the compiled production bundle for. Every dev page carries it, the
  failure pages included.
- The second test in that file scans every `.dart` file under `lib/dev/` for
  `Firebase.initializeApp(...)` and the `FirebaseApp`, `FirebaseAuth`, `FirebaseFirestore`,
  `FirebaseAppCheck` and `FirebaseRemoteConfig` singletons, exempts exactly `live_dev_session.dart`,
  and asserts that path exists, so a rename fails the test instead of silently widening the
  exception. So a fake session has no project, no credential and no network. Because the
  entrypoint imports the live file, a dev build links the Firebase Auth and Firestore web plugins —
  registration only; the fake branch never initialises them, so nothing is contacted.
- In fake mode the shell resolves `AuthSession` only. `AuthService` is registered but throws when
  resolved, so the sign-in, verification and deletion screens are unbuildable there; the home page
  hides its sign-out control and the profile page hides the danger zone rather than offering
  controls that cannot work. A live session has the real service, so sign-out is live and the
  danger zone is behind the opt-in.
- `setupServiceLocator` is single-shot: a second call in one process throws. A reload is a new
  process, which is why a dev scenario never needs a reset.
