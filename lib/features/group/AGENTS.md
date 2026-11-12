# Group — Agent Guide

Groups are how users share wishlists with family and friends: a named set of members identified
by Firebase Auth uid, with wishlists shared *into* the group.

## Rules

- Membership is a `members` array of uids mutated with atomic array operations — there is no
  membership sub-collection.
- A group always has an owner, and the owner is always a member.
- Sharing writes the **group id into the wishlist's** `sharedWithGroups`, never the group
  document, and is idempotent.
- `GroupDetailsPage` is a `ConsumerWidget`. Its shared-wishlist rows are `GroupWishlistRow`
  (card, owner line, remove action) and its member rows are `GroupMemberRow`; the page keeps
  the group and member reads, the app bar, the share and leave dialogs, and navigation.
  Providers live in `presentation/providers/group_details_providers.dart`; the page imports
  no `service_locator.dart`.

## Reference

- Create/rename/join/leave, the invitation link, membership rules, and the provider shapes
  → `docs/groups.md`
