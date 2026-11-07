# Wishlists and claiming

Scope: wishlist and item models, the spoiler-free claim flow, and the rules that
gate a claim. Read before touching `lib/features/wishlist/` or how a claim is
written. Paths are relative to `lib/features/wishlist/`, then to the repository
root.

## Responsibility

- Create, rename, and delete wishlists.
- Add, edit, and delete items within a wishlist.
- Claim and unclaim items.
- Hide claimed status from the wishlist owner by default ("spoiler-free").

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `domain/wishlist.dart`, `domain/item.dart` |
| `data/` | `data/wishlist_repository.dart`, `data/item_repository.dart` |
| `application/` | `application/create_wishlist_use_case.dart`, `application/update_wishlist_use_case.dart`, `application/create_item_use_case.dart`, `application/update_item_use_case.dart`, `application/claim_item_use_case.dart`, `application/claim_failure.dart`, `application/unclaim_item_use_case.dart` |
| `presentation/` | `presentation/wishlist_form_page.dart`, `presentation/wishlist_details_page.dart`, `presentation/claim_failure_message.dart`, `presentation/item_form_page.dart` |

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
  `claimedAt` in one update. `claim(itemId, claimedBy:)` sends a two-field update
  (`claimedBy` and `claimedAt: Timestamp.now()`) without reading the item first, so a stale copy
  or a document missing an optional field cannot make the write invalid.
- Use cases: create/update wishlist; create/update item; `ClaimItemUseCase` (takes the
  item id and claims it for the current uid; `ItemRepository.claim` stamps `claimedAt`);
  `UnclaimItemUseCase`.
  The claim use cases report a `claimAction` phase (`started`, `completed`, or `denied` with
  the error code); `ClaimItemUseCase` throws a `ClaimFailure` whose reason is one of
  `accessDenied`, `offline`, `itemMissing`, `signedOut` or `unknown`, preserving the
  write's stack trace. `presentation/claim_failure_message.dart` turns the thrown object into copy, so
  the claim path never prints the exception.

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
- `claimedAt` is stored as a Firestore `Timestamp` but modeled as a `DateTime`; the
  conversion lives only in `ItemRepository`, so both the model and
  `fake_cloud_firestore` agree.
- Owner-only UI: the add-item FAB, item edit/delete actions, wishlist edit, and the spoiler
  toggle appear only when `wishlist.ownerId == currentUserId`.
- `WishlistDetailsPage` defaults `_isSpoilerFree` to true for the owner's controls, while a reader's
  item row goes straight to `_buildClaimedPill` or `_buildUserClaimedView`, so claimed status needs
  no toggle. A reader can claim any unclaimed item or unclaim their own; the rules deny claim
  writes when the wishlist is not currently shared with any group.
- A reader's claimed item card is muted: the fill steps to `surfaceContainerHighest`, a 4px
  edge marks it (brass for the viewer's own claim, muted ink for another member's), the title
  and description use `onSurfaceVariant`, and the title is struck through. The edge is
  decorative; the existing claim pill and the strike carry the state. The owner's view never
  applies this treatment; the spoiler toggle changes only whether the claimed-date text is
  shown.
- Another reader cannot take a claim over, and the wishlist owner is not bound by the rule.
  There is no separate claim document. The rule itself is in `docs/authorization.md`.
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
  a thrown object that is not a `ClaimFailure`; `wishlist_details_page_test` pins the two
  reader claim states (`StatusPill` accent beside Unclaim, neutral for someone else's), the
  unclaimed case, the reader's muted and struck-through claimed card in light and dark, the
  owner's card staying unmarked in both spoiler modes, each item row's `BrandCard` at the
  page's margin, the owner-only bar controls, and the claim row fitting a 320 px phone at 1.3
  text scale.
- `rules_tests/` — a whole-map claim carrying stale content is denied, documenting the
  denial the pair-only write avoids; the rules themselves are unchanged.
