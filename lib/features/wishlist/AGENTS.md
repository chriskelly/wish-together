# Wishlist — Agent Guide

Wishlists and their items, plus the spoiler-free gift-claiming behaviour that is the heart of
the product.

## Rules

- Items live only in the `wishlists/{id}/items` sub-collection; never query items globally.
- Deleting a wishlist goes through `deleteWithItems`, because Firestore does not remove a
  sub-collection with its parent.
- A claim writes only the caller's own key in `claims`, and never the rest of the item. An
  owner's edit writes content and `claimLimit` only, never `claims`.
- A finite claim limit never drops below the item's current claim count; the item form's
  minimum on edit is `max(1, claimCount)`.
- The owner's details page hides claimed status by default and shows the configured limit
  instead; a reader of a shared list always sees the state. Single-claim rows never show a
  count; multi and unlimited rows show the count summary while room remains, and a full reader
  row shows `Unavailable` with no count.

## Reference

- Models, repositories, claim states, the rules that gate a claim → `docs/claiming.md`
