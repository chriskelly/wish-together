# Groups and invitations

Scope: group membership, the invite link, and sharing a wishlist into a group.
Read before touching `lib/features/group/` or the `/join` route. Paths are
relative to `lib/features/group/` unless they start with `lib/` or `test/`.

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
| `domain/` | `domain/group.dart` |
| `data/` | `data/group_repository.dart` |
| `application/` | `application/create_group_use_case.dart`, `application/join_group_use_case.dart`, `application/leave_group_use_case.dart`, `application/update_group_use_case.dart`, `application/share_wishlist_with_group_use_case.dart` |
| `presentation/` | `presentation/group_form_page.dart`, `presentation/group_details_page.dart`, `presentation/join_group_page.dart` |

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
  not-yet-onboarded user still lands on the join page. Legacy hash links are not
  supported (`docs/deep-links.md`).
- Accepting an invite for a group the viewer already belongs to goes straight to that
  group's details page. The navigation is reported as a replacement, so on web the invite
  entry is replaced rather than stacked and Back does not return to `/join`. There is no
  "already a member" page; the group fetch, not the home list, decides membership.
- The join route is keyed by its path, not its query string, so a second invite link in the
  same session updates the page in place. The page re-reads the group when `groupId`
  changes, so the name and the membership decision always describe the link just followed.
  A rebuild that keeps the same group id does not re-read; leaving the page and returning,
  or reloading, reads again. Distinguishing a failed read from a missing group, and
  offering a retry, is a separate change.

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
  no Leave Group button, and the floating button opens the share dialog. The bar carries
  the invite and edit controls for the owner only. A shared wishlist renders inside a
  `BrandCard` at the page's row margin (the inner `Card` is pinned by
  `test/common/widgets/brand_card_test.dart`). A long unbroken member name truncates with
  an ellipsis before the Owner/Member label, a name that fits is not truncated, and only
  the owner's row is labelled Owner.
- `test/features/group/presentation/join_group_page_test.dart` drives the real `/join` route
  through a `GoRouter` and pins the invite outcomes: an existing member lands on
  `/group/<id>` with no tap, no interstitial and no `/join` left in the router's matches,
  and the engine is told to replace the browser entry (recorded from the navigation
  channel); a non-member sees the invitation; a failed group fetch shows "This invitation is
  no longer valid." and stays on `/join`; the loading state holds while the fetch is
  pending; a second invite link re-reads the new group; a rebuild reads the group only once;
  and Join Group still joins and lands on the group. The page also renders the invitation
  when no session is present, which is defensive: the router normally sends a signed-out
  visitor to login first.
- These two are the only widget tests that cover the group pages.
