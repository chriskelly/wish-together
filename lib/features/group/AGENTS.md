# Group — Agent Guide

Groups are how users share wishlists with family and friends: a named set of members identified
by Firebase Auth uid, with wishlists shared *into* the group.

## Rules

- Membership is a `members` array of uids mutated with atomic array operations — there is no
  membership sub-collection.
- A group always has an owner, and the owner is always a member.
- Sharing writes the **group id into the wishlist's** `sharedWithGroups`, never the group
  document, and is idempotent.

## Reference

- Create/rename/join/leave, the invitation link, and membership rules → `docs/groups.md`
