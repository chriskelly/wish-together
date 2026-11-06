# Wishlist — Agent Guide

Wishlists and their items, plus the spoiler-free gift-claiming behaviour that is the heart of
the product.

## Rules

- Items live only in the `wishlists/{id}/items` sub-collection; never query items globally.
- Deleting a wishlist goes through `deleteWithItems`, because Firestore does not remove a
  sub-collection with its parent.
- A claim writes only `claimedBy` and `claimedAt`, as a pair, and never the rest of the item.
- The owner's details page hides claimed status by default; a reader of a shared list always
  sees it.

## Reference

- Models, repositories, claim states, the rules that gate a claim → `docs/claiming.md`
