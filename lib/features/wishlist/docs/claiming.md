# Wishlists and claiming

Scope: wishlist and item models, the spoiler-free claim flow, and the rules that
gate a claim. Read before touching `lib/features/wishlist/` or how a claim is
written. Paths are relative to `lib/features/wishlist/`, then to the repository
root.

## Responsibility

- Create, rename, and delete wishlists.
- Add, edit, and delete items within a wishlist.
- Claim and unclaim items, with one claim per person and an optional limit.
- Hide claimed status from the wishlist owner by default ("spoiler-free").

## Layout

The area is split into `domain/`, `data/`, `application/` and
`presentation/`. List the current files with
`find lib/features/wishlist -name '*.dart' | sort`.

## Key types

- `Wishlist` — `id`, `name`, `ownerId`, `sharedWithGroups: List<String>`; collection
  `wishlists`.
- `Item` — `id`, `name`, `description`, `url`, `claims: Map<String, DateTime>`, and
  `claimLimit: int`. Lives in the `wishlists/{wishlistId}/items` sub-collection; `items` is
  **not** a top-level collection. A claim maps a uid to when that person claimed; one key per
  person, and the time is never displayed. `claimLimit` is `1` for the classic single claim,
  `0` for unlimited, and `n > 1` for n claimants; a document without it reads as `1`.
  `claimCount`, `isUnlimited`, `hasClaimRoom`, and `isClaimedBy(uid)` derive everything else.
- `StaleClaimsPlan` (`domain/stale_claims.dart`) — `byItem: Map<String, Set<String>>`, built by
  `fromItems(items, now:)`; a claim is stale when it is strictly older than `staleClaimAge`
  (183 days). `staleClaimAgeLabel` is the matching `6 months` copy used by the banner and its
  confirmation.
- `WishlistRepository extends FirebaseRepository<Wishlist>` — `items(wishlistId)` returns
  an `ItemRepository` bound to the sub-collection (reusing the same Firestore instance),
  plus `addItemToWishlist`, `updateItemInWishlist`, `removeWishlistFromGroup`,
  `listOwnedBy(ownerId)` (a one-shot query, for callers that cannot wait on a stream), and
  `deleteWithItems(wishlistId)` (deletes every item, in batches, then the wishlist).
- `ItemRepository extends FirebaseRepository<Item>` — path `wishlists/{wishlistId}/items`;
  converts each claims value between a Firestore `Timestamp` and a `DateTime` (the map crosses
  `Item.toMap`/`fromMap` as ISO-8601 strings, like the old claim date).
  - `claim(itemId, claimedBy:)` always runs a transaction: it reads the item, treats a repeat
    claim by the same uid as an idempotent success, rejects a full finite item with
    `ClaimLimitReachedException`, and otherwise writes only `claims.<uid>`. A missing item is a
    `not-found` failure.
  - `unclaim(itemId, claimedBy:)` deletes only that key by delegating to
    `removeClaims(itemId, uids: {claimedBy})`.
  - `removeClaims(itemId, {required Set<String> uids})` deletes only the named keys in one
    write, leaving every other claimant untouched. A reset is the special case that deletes the
    whole `claims` field.
  - `resetClaims(itemId)` deletes the whole `claims` field in one write. It
    leaves content and the limit alone. A claim a reader commits after the
    reset survives, because the reset deletes the map rather than blocking
    future claims; offline, the write queues as the reader's unclaim does.
  - `updateContent(itemId, name:, description:, url:, claimLimit:)` writes those four fields
    and never `claims`; `WishlistRepository.updateItemInWishlist` delegates to it.
- `ClaimLimitReachedException` lives in `domain/` so data and application can name the same
  condition.
- Use cases: create/update wishlist; `CreateItemUseCase` and `UpdateItemUseCase` carry
  `claimLimit` (`UpdateItemUseCase` keeps the item's existing limit when none is given);
  `ClaimItemUseCase` claims for the current uid; `UnclaimItemUseCase` resolves the current uid
  and throws a signed-out `ClaimFailure` when there is none; `ResetClaimsUseCase` does the same
  signed-out guard and then clears every claim on an item; `ClearStaleClaimsUseCase` removes the
  old keys in a `StaleClaimsPlan`, stops at the first failed write, and throws that
  `ClaimFailure` with the write's stack trace. It returns without logging for an empty plan.
  The claim, unclaim, reset and clear use cases report a `claimAction` phase (`started`,
  `completed`, or `denied` with the error code); `ClaimItemUseCase` throws a `ClaimFailure` whose
  reason is one of `accessDenied`, `offline`, `itemMissing`, `signedOut`, `fullyClaimed` or
  `unknown`, preserving the write's stack trace. `presentation/claim_failure_message.dart` turns
  the thrown object into copy, so the claim and unclaim paths never print the exception; the item
  form maps reset failures the same way, and the banner maps clear failures with
  `clearStaleClaimsFailureMessage`.

## Invariants

- `ItemRepository` is bound to `wishlists/{wishlistId}/items`; `WishlistRepository.items(id)` is
  the only way pages reach it, so an item query always carries its parent.
- `deleteWithItems` reads up to 500 items at a time, batch-deletes each page through the
  `ItemRepository` reporting helpers, and deletes the wishlist once a page comes back empty. A
  write landing after that empty read and before the parent delete is not covered; only a
  server-side cascade could close that window. A failed page read or commit reports
  `firestoreError` instead of failing silently.
- An `Item` must have an id before it can be updated;
  `WishlistRepository.updateItemInWishlist` throws `ArgumentError` otherwise.
- Claim times are stored as Firestore `Timestamp`s but modeled as `DateTime`s; the conversion
  lives only in `ItemRepository`, so both the model and `fake_cloud_firestore` agree. A claim
  value that is not a Timestamp is dropped on read rather than failing the whole list; the
  migration's `--verify` reports such a document.
- An owner's content edit is field-scoped: it writes `name`, `description`, `url` and
  `claimLimit`, never `claims`, so it cannot drop a claim. A separate claim removal deletes any
  subset of claim keys in one write; the rules accept it only when no key is added and no existing
  value changes, so it can remove claims but cannot add or rewrite one. A malformed stored
  `claims` value can only be cleared to empty. The item form's stepper sets a limit of 1–99 or
  unlimited (0, shown as `∞`); on edit its minimum is `max(1, claimCount)`, so a limit cannot be
  lowered below the people who already claimed. A pre-existing finite limit above 99 is kept and
  cannot be lowered. A successful reset clears the page's claim count, so the minimum drops to 1
  without leaving the form.
- Both forms save from the app bar's check mark (`Save changes` on an edit, `Save item` on a
  create), enabled while the form differs from the values it last saved (or opened with) and no
  save is in flight; tapping it is still the explicit action. Leaving either form with unsaved
  content — back arrow, system back or the browser's back button — asks Save, Discard or Keep
  editing, and a save is never attempted silently. System back reaches `PopScope`; a web back
  can arrive as a `popRoute` first and then as a route replacement, and the replacement path
  reaches go_router's `onExit` without touching `PopScope`, so both routes carry a guard (the
  edit route in `EditItemRouteArgs.leaveGuard`, the create route in its own `ItemFormLeaveGuard`)
  that asks the same question. Whichever path arrives first asks, and the dialog guard keeps the
  other from stacking. The iOS swipe-back gesture is disabled while the change is unsaved
  instead of opening the prompt, so the app-bar arrow is the way out there; a create whose write
  is in flight may leave, so its swipe is not blocked. A browser reload or tab close is the one
  exit that still drops the form; it is not intercepted, because guarding it would need draft
  persistence. An edit does not autofocus the name field, so the keyboard
  does not cover the form before the owner has chosen what to change; creating still does. A
  failed save stays on the form as a banner with the classified copy and a retry, and the typed
  values are kept; an edit write still unacknowledged after ten seconds is reported as
  unconfirmed rather than spinning forever, and the banner's Retry (or the check mark) issues it
  again. A router redirect caused by the session ending or changing is never held by the prompt,
  because the form cannot save into a different session. A create is one shot: its check mark
  and fields stay locked until the write resolves, so a queued create cannot be submitted twice
  or edited into a state the write does not contain. The owner may leave while that write is in
  flight; it can still land after they go, and the list stream then shows the item. If it
  instead fails after they leave, that failure is silent: the page is gone and no retry is
  offered.
- Owner-only UI: the add-item FAB, item edit/delete actions, wishlist edit, and the spoiler
  toggle appear only when `wishlist.ownerId == currentUserId`.
- `WishlistDetailsPage` starts spoiler-free (`SpoilerFree.build()` returns true). Spoiler-free
  shows the configured limit (`Unlimited claims`, `1 person can claim`, `N people can claim`)
  instead of claim status; the revealed view shows `Available`/`Claimed` for a single-claim item,
  `No claims yet`/`N claimed` for unlimited, and `No claims yet`/`N of M claimed` for a finite
  multi item, never a date. A reader always sees the state: their own claim as an accent "You
  claimed this!" pill beside Unclaim, with a count for multi or unlimited items; a count before
  Claim while room remains; or a neutral `Unavailable` pill when full. Single-claim rows never
  show a count.
- A reader's card is muted and struck only when the viewer claimed the item or no room remains;
  a partially claimed item stays normal. The owner's card is never muted.
- The owner's details page also shows `StaleClaimsBanner` when any claim is older than
  `staleClaimAge`, in the default spoiler-free view as well as the revealed one. The banner names
  no item, no claimant and no count; every item row keeps the configured limit until the owner
  reveals status. It is the one aggregate exception to the spoiler-free default. Its confirmation
  removes only the planned old keys, keeps claims newer than the cutoff, and keeps the banner on a
  partial failure. A reader never sees it.
- The cutoff is evaluated on the device against the stored claim times, and the plan is a
  snapshot: a wrong clock or a claim refreshed after the tap can misclassify a claim. The rules
  allow the owner to remove any subset, so the six-month policy is a UI contract, not a security
  boundary.
- Another reader cannot take over a claim or remove someone else's key. There is no separate
  claim document. The rule itself is in `docs/authorization.md`.
- The rules enforce the cap on every write, but the check is not serialisable: two hostile
  clients can both see the last slot and overshoot by one. The client transaction closes that
  for cooperating clients. A transaction needs connectivity, so an offline claim fails with the
  `offline` copy instead of being queued; unclaim is a direct field delete and still queues.
- Item reads are gated on the parent wishlist (rule in `docs/authorization.md`). A non-owner
  opening a never-shared wishlist therefore gets a permission error from the items query
  instead of an empty list, and `WishlistDetailsPage` shows its error state rather than the
  items.

## Data flow

`HomePage` streams the user's wishlists with `streamWhere('ownerId', isEqualTo: uid)`.
`WishlistDetailsPage` watches `wishlistProvider(id)` and `wishlistItemsProvider(id)`, computes
`isOwner` from `currentUserIdProvider`, and runs claim/unclaim/delete through `ItemActions`; the
spoiler toggle is `SpoilerFree`. For the owner it also watches `staleClaimsPlanProvider(id)`,
which derives from the same item stream and `wishlistNowProvider`, and renders
`StaleClaimsBanner` above the list when the plan is non-empty. The banner's clear calls
`ItemActions.clearStaleClaims`, so it shares the page-wide busy guard: its button is disabled
while any page action runs, and its spinner means the bulk clear itself is running. Each item card
is a `WishlistItemRow`. The owner's `ItemFormPage` carries the reset-claims action, which calls
`ResetClaimsUseCase`, keeps the form open and shows `Claims reset.` so a pending edit survives. A
wishlist shared with a group appears in that group's details page because of
`sharedWithGroups`.

## How it is tested

- `test/features/wishlist/domain/` — `Item` helpers, the empty-claims default, an invalid or
  missing limit reading as `1`, the map round-trip, and dropping an unparseable claim value; the
  stale-claim plan's 183-day boundary, mixed ages, future dates, a later clock, and an item
  without an id.
- `test/features/wishlist/application/` — the use cases with `mocktail` mocks registered in
  `getIt`: create/update carry `claimLimit`, update is field-scoped, unclaim passes the uid and
  fails signed out, reset clears the item, fails signed out and classifies a denied write, claim
  rejects a full item as `fullyClaimed`, clear removes every planned item's keys, fails signed
  out, stops at the first failed write with its stack trace, and returns without logging for an
  empty plan, and `ClaimFailure.from` maps the exception before any Firestore code.
- `test/features/wishlist/data/` — `WishlistRepository` (sub-collection wiring, the
  field-scoped item update preserving a stored claim, the no-id `ArgumentError`,
  `deleteWithItems`) and `ItemRepository` against `FakeFirebaseFirestore`: claims `Timestamp`
  round-trip, a repeat claim keeping one key, the cap rejecting without a write, unlimited
  items, unclaim removing only the caller's key by delegating to `removeClaims`, `removeClaims`
  deleting only the named keys, `resetClaims` clearing every key, and `updateContent` preserving
  `claims`. The fake transaction has no isolation or rollback, so the true concurrency behaviour
  is proven by the rules tests and the staging smoke test, not here.
- `test/features/wishlist/presentation/` — `claimFailureMessage` and
  `clearStaleClaimsFailureMessage` copy; `item_form_page_test` pins the stepper's create, edit,
  unlimited and save behaviour, the reset action always showing on an edit, its confirmation, its
  pending state, and its failure copies, both forms' check-mark enablement and autofocus
  behaviour, the create leave guard, its locked fields while the write is in flight, the leave
  dialog from both `PopScope` and the browser's route replacement (keep editing, discard and
  save on both paths; an invalid save from the back dialog), a failure banner that survives a
  focus change but clears on a text edit, the failed/offline/unconfirmed save banner and its
  retry, a rapid edit sequence, edits kept when typed during an in-flight save, a create that
  cannot be submitted twice, and a reset that stays on the form and refreshes the stepper
  minimum;
  `wishlist_details_page_test` pins the reader's own and other claims, the unclaimed case, the
  multi/unlimited counts, `Unavailable`, the owner's spoiler-free limit labels and revealed
  status, the row fitting a 320 px phone at 1.3 text scale, the signed-out unclaim copy, the
  owner's card never being restyled in either spoiler mode, and the banner's owner-only presence,
  copy, confirmation, success/partial snackbars, retry, busy state, error suppression, and
  snackbar surviving the banner's unmount.
- `test/features/wishlist/presentation/providers/` — `ProviderContainer` transitions with no
  widgets: the spoiler toggle flips, claim succeeds and fails (rethrow plus busy cleared),
  unclaim runs its use case, and the bulk clear reports its marker, runs the clear use case, and
  serialises with claim and delete in both directions.
- `test/features/wishlist/presentation/wishlist_details_state_test.dart` — the subscription
  regression (no re-listen after a toggle, a page rebuild, a text-scale change, an item emission
  or a wishlist emission; a cancel on leave; one new listen on re-entry), the double-tap claim
  guard (one call and one snackbar), the empty list, the delete flow, and the wishlist/item error
  branches.
- `rules_tests/` — own-key-only adds and removes, the cap, unlimited items, the owner's
  field-scoped edit and limit invariant, an owner removing any subset of claims, additions and
  rewrites refused, an absent map allowing a no-op removal, a malformed map repaired by clearing
  it, a reset combined with a content edit refused, create validation, a legacy document being
  write-denied, and an item created without a claims map still being claimable.
