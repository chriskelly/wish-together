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

| Layer | Files |
| ----- | ----- |
| `domain/` | `domain/wishlist.dart`, `domain/item.dart`, `domain/claim_limit_reached_exception.dart` |
| `data/` | `data/wishlist_repository.dart`, `data/item_repository.dart` |
| `application/` | `application/create_wishlist_use_case.dart`, `application/update_wishlist_use_case.dart`, `application/create_item_use_case.dart`, `application/update_item_use_case.dart`, `application/claim_item_use_case.dart`, `application/claim_failure.dart`, `application/unclaim_item_use_case.dart` |
| `presentation/` | `presentation/wishlist_form_page.dart`, `presentation/wishlist_details_page.dart`, `presentation/claim_failure_message.dart`, `presentation/item_form_page.dart` |

## Key types

- `Wishlist` — `id`, `name`, `ownerId`, `sharedWithGroups: List<String>`; collection
  `wishlists`.
- `Item` — `id`, `name`, `description`, `url`, `claims: Map<String, DateTime>`, and
  `claimLimit: int`. Lives in the `wishlists/{wishlistId}/items` sub-collection; `items` is
  **not** a top-level collection. A claim maps a uid to when that person claimed; one key per
  person, and the time is never displayed. `claimLimit` is `1` for the classic single claim,
  `0` for unlimited, and `n > 1` for n claimants; a document without it reads as `1`.
  `claimCount`, `isUnlimited`, `hasClaimRoom`, and `isClaimedBy(uid)` derive everything else.
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
  - `unclaim(itemId, claimedBy:)` deletes only that key.
  - `updateContent(itemId, name:, description:, url:, claimLimit:)` writes those four fields
    and never `claims`; `WishlistRepository.updateItemInWishlist` delegates to it.
- `ClaimLimitReachedException` lives in `domain/` so data and application can name the same
  condition.
- Use cases: create/update wishlist; `CreateItemUseCase` and `UpdateItemUseCase` carry
  `claimLimit` (`UpdateItemUseCase` keeps the item's existing limit when none is given);
  `ClaimItemUseCase` claims for the current uid; `UnclaimItemUseCase` resolves the current uid
  and throws a signed-out `ClaimFailure` when there is none.
  The claim use cases report a `claimAction` phase (`started`, `completed`, or `denied` with
  the error code); `ClaimItemUseCase` throws a `ClaimFailure` whose reason is one of
  `accessDenied`, `offline`, `itemMissing`, `signedOut`, `fullyClaimed` or `unknown`,
  preserving the write's stack trace. `presentation/claim_failure_message.dart` turns the
  thrown object into copy, so the claim and unclaim paths never print the exception.

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
  `claimLimit`, never `claims`, so it cannot drop a claim. The item form passes the existing
  limit; there is no limit control in the UI yet.
- Owner-only UI: the add-item FAB, item edit/delete actions, wishlist edit, and the spoiler
  toggle appear only when `wishlist.ownerId == currentUserId`.
- `WishlistDetailsPage` defaults `_isSpoilerFree` to true for the owner's controls. Spoiler-free
  shows no claim status; the revealed view shows `Claimed` or `Available`, never a date. A
  reader always sees the state: their own claim as an accent "You claimed this!" pill beside
  Unclaim, another person's claim as a neutral `Claimed` pill, or Claim while there is room.
- A reader's card is muted and struck only when the viewer claimed the item or no room remains;
  a partially claimed item stays normal. The owner's card is never muted.
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
`WishlistDetailsPage` streams the wishlist and its items, computes `isOwner` from the
current uid, and calls the claim/unclaim use cases from the item card actions. A wishlist
shared with a group appears in that group's details page because of
`sharedWithGroups`.

## How it is tested

- `test/features/wishlist/domain/` — `Item` helpers, the empty-claims default, an invalid or
  missing limit reading as `1`, the map round-trip, and dropping an unparseable claim value.
- `test/features/wishlist/application/` — the use cases with `mocktail` mocks registered in
  `getIt`: create/update carry `claimLimit`, update is field-scoped, unclaim passes the uid and
  fails signed out, claim rejects a full item as `fullyClaimed`, and `ClaimFailure.from` maps
  the exception before any Firestore code.
- `test/features/wishlist/data/` — `WishlistRepository` (sub-collection wiring, the
  field-scoped item update preserving a stored claim, the no-id `ArgumentError`,
  `deleteWithItems`) and `ItemRepository` against `FakeFirebaseFirestore`: claims `Timestamp`
  round-trip, a repeat claim keeping one key, the cap rejecting without a write, unlimited
  items, unclaim removing only the caller's key, and `updateContent` preserving `claims`. The
  fake transaction has no isolation or rollback, so the true concurrency behaviour is proven by
  the rules tests and the staging smoke test, not here.
- `test/features/wishlist/presentation/` — `claimFailureMessage` copy (including a full item);
  `wishlist_details_page_test` pins the reader's own and other claims, the unclaimed case, the
  row fitting a 320 px phone at 1.3 text scale, the signed-out unclaim copy, and the owner's
  card never being restyled in either spoiler mode.
- `rules_tests/` — own-key-only adds and removes, the cap, unlimited items, the owner's
  field-scoped edit and limit invariant, create validation, a legacy document being write-denied,
  and an item created without a claims map still being claimable.
