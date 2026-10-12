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
| `application/` | `create_wishlist_use_case.dart`, `update_wishlist_use_case.dart`, `create_item_use_case.dart`, `update_item_use_case.dart`, `claim_item_use_case.dart`, `unclaim_item_use_case.dart` |
| `presentation/` | `wishlist_form_page.dart`, `wishlist_details_page.dart`, `item_form_page.dart` |

## Key types

- `Wishlist` — `id`, `name`, `ownerId`, `sharedWithGroups: List<String>`; collection
  `wishlists`.
- `Item` — `id`, `name`, `description`, `url`, `claimedBy` (uid or null),
  `claimedAt: DateTime?`. Lives in the `wishlists/{wishlistId}/items` sub-collection;
  `items` is **not** a top-level collection.
- `WishlistRepository extends FirebaseRepository<Wishlist>` — `items(wishlistId)` returns
  an `ItemRepository` bound to the sub-collection (reusing the same Firestore instance),
  plus `addItemToWishlist`, `updateItemInWishlist`, and `removeWishlistFromGroup`.
- `ItemRepository extends FirebaseRepository<Item>` — path
  `wishlists/{wishlistId}/items`; converts `claimedAt` between an ISO-8601 string (model)
  and a Firestore `Timestamp` (storage); `unclaim(itemId)` nulls `claimedBy` and
  `claimedAt` in one update.
- Use cases: create/update wishlist; create/update item; `ClaimItemUseCase` (sets
  `claimedBy` to the current uid and `claimedAt` to now); `UnclaimItemUseCase`.

## Invariants

- Items are always scoped to a wishlist sub-collection; never query items globally.
- An `Item` must have an id before it can be updated;
  `WishlistRepository.updateItemInWishlist` throws `ArgumentError` otherwise.
- `claimedAt` is stored as a Firestore `Timestamp` but modeled as a `DateTime`; the
  conversion lives only in `ItemRepository`, so both the model and
  `fake_cloud_firestore` agree.
- Owner-only UI: the add-item FAB, item edit/delete actions, wishlist edit, and the spoiler
  toggle appear only when `wishlist.ownerId == currentUserId`.
- Spoiler-free: the owner's details page defaults `_isSpoilerFree = true` and hides claimed
  status until toggled. Non-owners always see the true status and can claim/unclaim.
- Claiming is last-write-wins on the item document; there is no separate claim document.

## Data flow

`HomePage` streams the user's wishlists with `streamWhere('ownerId', isEqualTo: uid)`.
`WishlistDetailsPage` streams the wishlist and its items, computes `isOwner` from the
current uid, and calls the claim/unclaim use cases from the item card actions. A wishlist
shared with a group appears in that group's details page because of
`sharedWithGroups`.

## How it is tested

- `test/features/wishlist/application/` — the six use cases with `mocktail` mocks
  registered in `getIt` (claim records uid + non-null timestamp, unauthenticated throw,
  exception propagation).
- `test/features/wishlist/data/` — `WishlistRepository` (sub-collection wiring, item
  update, the no-id `ArgumentError`, remove-from-group) and `ItemRepository`
  (`claimedAt` `Timestamp` round-trip and `unclaim` nulling) against
  `FakeFirebaseFirestore`.
- The wishlist pages have no widget tests.
