# Group — Overview

Groups are how users share wishlists with family and friends. A group is a named set of
members identified by Firebase Auth uid; wishlists are shared *into* a group.

## Responsibility

- Create, rename, join, and leave groups.
- Group membership.
- Invitation links.
- Sharing and un-sharing wishlists into a group.

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `group.dart` |
| `data/` | `group_repository.dart` |
| `application/` | `create_group_use_case.dart`, `join_group_use_case.dart`, `leave_group_use_case.dart`, `update_group_use_case.dart`, `share_wishlist_with_group_use_case.dart` |
| `presentation/` | `group_form_page.dart`, `group_details_page.dart`, `join_group_page.dart` |

## Key types

- `Group` — `id`, `name`, `ownerId`, `members: List<String>` (uids); collection `groups`.
- `GroupRepository extends FirebaseRepository<Group>` — `joinGroup(groupId, userId)`
  (`FieldValue.arrayUnion`) and `leaveGroup(groupId, userId)` (`FieldValue.arrayRemove`),
  plus `listForMember(userId)` / `listOwnedBy(ownerId)` (one-shot queries for callers
  that cannot wait on a stream) and `transferOwnership(groupId, newOwnerId,
  remainingMembers)` (one atomic update of `ownerId` and `members`).
- Use cases: `CreateGroupUseCase` (owner is also the first member),
  `JoinGroupUseCase`, `LeaveGroupUseCase`, `UpdateGroupUseCase` (rename),
  `ShareWishlistWithGroupUseCase`.
- `GroupDetailsPage.getInvitationLink(groupId, {String? origin})` builds the invite URL.
- `JoinGroupPage` handles the invite deep link.

## Invariants

- Membership is a `members` array of uids, mutated with atomic array operations — there is
  no membership sub-collection.
- A group is never left without an owner. Account deletion hands an owned group to
  its first remaining member with a single `transferOwnership` update (`ownerId` and
  `members` change together, so a request that is still the old owner passes any
  owner-only rule); only a group whose last member is leaving is deleted.
- A group's owner is always a member; the creator is added as a member at creation.
- Only the owner sees the edit and copy-invite actions; non-owners see the Leave action.
- Sharing a wishlist writes the **group id into the wishlist's** `sharedWithGroups` array,
  not the group document. It is idempotent: an already-shared group is skipped.
- The group's "Shared Wishlists" list is the set of wishlists whose `sharedWithGroups`
  `arrayContains` the group id; a wishlist is removed by its owner.
- The invite format is `<origin>/join?group=<groupId>` — a real path, not a hash URL. Web
  uses the current origin; native uses `https://wishtogether.gift`. On iOS the URL is a
  Universal Link (`app_links`); the router receives the location `/join?group=<groupId>` and
  preserves it as `redirect_to` through login, verification, and profile, so an invited,
  not-yet-onboarded user still lands on the join page. Legacy `/#/join?…` links are not
  supported and land on `/`.

## Data flow

`HomePage` streams the user's groups with `streamWhere('members', arrayContains: uid)`.
`GroupDetailsPage` streams the group, streams member `User` documents via
`UserRepository.streamUsersFromIds(group.members)`, and streams shared wishlists via
`streamWhere('sharedWithGroups', arrayContains: groupId)`. Joining uses the current uid
from `AuthSession`; no uid is passed in from the UI.

## How it is tested

- `test/features/group/application/` — all five use cases with `mocktail` mocks registered
  in `getIt` (owner-as-member, unauthenticated throw, exception propagation, and the
  idempotent share case).
- `test/features/group/data/group_repository_test.dart` — join/leave array operations
  plus `listForMember`, `listOwnedBy`, and `transferOwnership` (both fields, and the
  departing member gone) against `FakeFirebaseFirestore`.
- `test/core/router_test.dart` covers the invite-link redirect matrix.
- `test/features/group/presentation/group_details_page_test.dart` pins the invite URL
  (canonical origin off web, supplied origin, encoded id) and the page's layout: at a
  phone width, scrolled to the end, the Leave Group tap target does not intersect the
  Share Wishlist button, tapping Leave Group opens the leave confirmation, an owner sees
  no Leave Group button, and the floating button opens the share dialog.
- No other widget tests cover the group pages.
