# Wishlist — Agent Guide

Wishlists and their items, plus the spoiler-free gift-claiming behaviour that is the heart of
the product.

## Rules

- Items live only in the `wishlists/{id}/items` sub-collection; never query items globally.
- Deleting a wishlist goes through `deleteWithItems`, because Firestore does not remove a
  sub-collection with its parent.
- A claim writes only the caller's own key in `claims`, and never the rest of the item. An
  owner's content edit writes content and `claimLimit` only, never `claims`; a separate reset
  deletes every claim in one write, and the rules accept it only when the map ends empty.
- A finite claim limit never drops below the item's current claim count; the item form's
  minimum on edit is `max(1, claimCount)`. A successful reset lowers that minimum to 1 in place
  and keeps the form (and any pending edit) open.
- Both forms save from the app-bar check mark, and leaving either with unsaved content asks
  Save / Discard / Keep editing from both `PopScope` and the route's `onExit`. Any new way out of
  those pages must go through the same question, except a router redirect caused by the session
  ending or changing, which always wins. A create may leave while its one-shot write is in
  flight; that write can still land and the item then appears in the list.
- The owner's details page hides claimed status by default and shows the configured limit
  instead; a reader of a shared list always sees the state. Single-claim rows never show a
  count; multi and unlimited rows show the count summary while room remains, and a full reader
  row shows `Unavailable` with no count.
- `WishlistDetailsPage` is a `ConsumerWidget`; its item rows are `WishlistItemRow`, which owns
  the card rendering and the claim/unclaim/delete side effects. The page keeps the reads, the
  app bar and navigation. Row rendering and claim copy are covered by
  `wishlist_details_page_test.dart`; the delete flow, the busy guard and the stream lifetime by
  `wishlist_details_state_test.dart`.
- `wishlistItemsProvider` derives its state from the snapshot metadata. A cache-only empty
  read is a failed read only when the subscription has never seen server-confirmed data or a
  non-empty local list: the page then shows the cloud-off panel with Try again after an
  800 ms grace, so a quick online reply does not flash it. Once any credible read has arrived
  in that subscription, a later cache-only empty (for example, deleting the last item offline)
  keeps the empty message; a fresh page load starts a new subscription and its own
  credibility. Known false positives: an owner who creates a wishlist offline and opens it,
  deletes the last item and reopens the page, or has only a pending local write in an
  otherwise unknown cache, sees the panel until the server confirms. Cache-only rows render
  unchanged.

## Reference

- Models, repositories, claim states, the rules that gate a claim → `docs/claiming.md`
- The provider pattern, retry policy and test shapes → `../core/docs/state.md`
