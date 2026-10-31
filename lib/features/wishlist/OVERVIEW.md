# Wishlist — Overview

Wishlists and their items, plus the spoiler-free gift-claiming behavior that is the heart
of the product.

## Responsibility

- Create, rename, and delete wishlists.
- Add, edit, and delete items within a wishlist.
- Claim and unclaim items.
- Hide claimed status from the wishlist owner by default ("spoiler-free").

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `wishlist.dart`, `item.dart` |
| `data/` | `wishlist_repository.dart`, `item_repository.dart` |
| `application/` | `create_wishlist_use_case.dart`, `update_wishlist_use_case.dart`, `create_item_use_case.dart`, `update_item_use_case.dart`, `claim_item_use_case.dart`, `claim_failure.dart`, `unclaim_item_use_case.dart` |
| `presentation/` | `wishlist_form_page.dart`, `wishlist_details_page.dart`, `claim_failure_message.dart`, `item_form_page.dart` |

## Key types

- `Wishlist` — `id`, `name`, `ownerId`, `sharedWithGroups: List<String>`; collection
  `wishlists`.
- `Item` — `id`, `name`, `description`, `url`, `claimedBy` (uid or null),
  `claimedAt: DateTime?`. Lives in the `wishlists/{wishlistId}/items` sub-collection;
  `items` is **not** a top-level collection.
- `WishlistRepository extends FirebaseRepository<Wishlist>` — `items(wishlistId)` returns
  an `ItemRepository` bound to the sub-collection (reusing the same Firestore instance),
  plus `addItemToWishlist`, `updateItemInWishlist`, `removeWishlistFromGroup`,
  `listOwnedBy(ownerId)` (a one-shot query, for callers that cannot wait on a stream), and
  `deleteWithItems(wishlistId)` (deletes every item, in batches, then the wishlist).
- `ItemRepository extends FirebaseRepository<Item>` — path
  `wishlists/{wishlistId}/items`; converts `claimedAt` between an ISO-8601 string (model)
  and a Firestore `Timestamp` (storage); `unclaim(itemId)` nulls `claimedBy` and
  `claimedAt` in one update, and `claim(itemId, claimedBy:)` writes only that pair, with
  `Timestamp.now()` as the timestamp. A claim never writes the rest of the item, so a
  reader's stale copy or a document missing an optional field cannot make the write
  invalid.
- Use cases: create/update wishlist; create/update item; `ClaimItemUseCase` (takes the
  item id and claims it for the current uid; `ItemRepository.claim` stamps `claimedAt`);
  `UnclaimItemUseCase`.
  The claim use cases report a `claimAction` phase (`started`, `completed`, or `denied` with
  the error code); `ClaimItemUseCase` throws a `ClaimFailure` whose reason is one of
  `accessDenied`, `offline`, `itemMissing`, `signedOut` or `unknown`, preserving the
  write's stack trace. `claim_failure_message.dart` turns the thrown object into copy, so
  the claim path never prints the exception.

## Invariants

- Items are always scoped to a wishlist sub-collection; never query items globally.
- Deleting a wishlist goes through `deleteWithItems`, because Firestore does not
  remove a sub-collection when its parent document is deleted. It pages through
  the items first, then deletes the wishlist; a write landing inside that window
  is not covered (only a server-side cascade could close it). Its page read and
  batch commit go through the `ItemRepository`'s protected reporting helpers, so
  a failed cascade reports `firestoreError` records instead of failing silently.
- An `Item` must have an id before it can be updated;
  `WishlistRepository.updateItemInWishlist` throws `ArgumentError` otherwise.
- `claimedAt` is stored as a Firestore `Timestamp` but modeled as a `DateTime`; the
  conversion lives only in `ItemRepository`, so both the model and
  `fake_cloud_firestore` agree.
- Owner-only UI: the add-item FAB, item edit/delete actions, wishlist edit, and the spoiler
  toggle appear only when `wishlist.ownerId == currentUserId`.
- Spoiler-free: the owner's details page defaults `_isSpoilerFree = true` and hides claimed
  status until toggled. A reader of a shared wishlist always sees the true status and can
  claim any unclaimed item, or unclaim one they claimed themselves; the rules deny claim
  writes when the wishlist has never been shared and deny taking over another reader's
  claim.
- Another reader cannot take a claim over: the current claimer must unclaim first
  (`claimedBy` and `claimedAt` back to null), or the rules deny the write. The wishlist
  owner is not bound by this and can still edit or clear a claim. There is no separate
  claim document.
- Item reads are gated on the parent wishlist: its owner can always read the items, while
  everyone else can read them only once the wishlist has been shared with a group. A
  non-owner opening a never-shared wishlist therefore gets a permission error from the
  items query instead of an empty list, and `WishlistDetailsPage` shows its error state
  rather than the items.

## Data flow

`HomePage` streams the user's wishlists with `streamWhere('ownerId', isEqualTo: uid)`.
`WishlistDetailsPage` streams the wishlist and its items, computes `isOwner` from the
current uid, and calls the claim/unclaim use cases from the item card actions. A wishlist
shared with a group appears in that group's details page because of
`sharedWithGroups`.

## How it is tested

- `test/features/wishlist/application/` — the six use cases with `mocktail` mocks
  registered in `getIt` (claim calls `claim` with the uid and never `update`, a failed
  write throws a `ClaimFailure` with its stack trace, unauthenticated throw) and
  `ClaimFailure.from`'s code-to-reason table.
- `test/features/wishlist/data/` — `WishlistRepository` (sub-collection wiring, item
  update, the no-id `ArgumentError`, remove-from-group, `listOwnedBy`, and
  `deleteWithItems` removing the items *and* the wishlist without touching a sibling)
  and `ItemRepository` (`claimedAt` `Timestamp` round-trip, `unclaim` nulling, and `claim`
  leaving stored content — including an absent optional field — untouched) against
  `FakeFirebaseFirestore`. The field-scope repository test and the use case's
  `verifyNever(update)` together guard the regression.
- `test/features/wishlist/presentation/` — `claimFailureMessage` copy and its fallback for
  a thrown object that is not a `ClaimFailure`; the pages themselves have no widget tests.
- `rules_tests/` — a whole-map claim carrying stale content is denied, documenting the
  denial the pair-only write avoids; the rules themselves are unchanged.
