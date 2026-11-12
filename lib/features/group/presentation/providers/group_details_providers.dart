import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// The group document, owned by the page for as long as it is open.
final groupProvider = StreamProvider.family<Group, String>(
  (ref, groupId) => ref.watch(groupRepositoryProvider).streamOne(groupId),
  isAutoDispose: true,
);

/// The wishlists whose `sharedWithGroups` contains the group id.
final groupSharedWishlistsProvider =
    StreamProvider.family<List<Wishlist>, String>(
      (ref, groupId) => ref
          .watch(wishlistRepositoryProvider)
          .streamWhere('sharedWithGroups', arrayContains: groupId),
      isAutoDispose: true,
    );

/// The member users, resolved from the group's `members` array.
///
/// It waits for the group read and then follows the member documents, so a
/// group emission (for example a membership change) re-reads the users without
/// the page rebuilding a query.
final groupMembersProvider = StreamProvider.family<List<User>, String>((
  ref,
  groupId,
) async* {
  final group = await ref.watch(groupProvider(groupId).future);
  yield* ref.watch(userRepositoryProvider).streamUsersFromIds(group.members);
}, isAutoDispose: true);

/// One owner profile, read once and shared by every row that names that owner.
///
/// A point read, not a stream: the row never reads the user repository itself,
/// so a rebuild cannot refetch the owner.
final wishlistOwnerProvider = FutureProvider.family<User, String>(
  (ref, ownerId) => ref.watch(userRepositoryProvider).get(ownerId),
  isAutoDispose: true,
);

/// The signed-in user's wishlists, for the share dialog.
///
/// Keyed by the session rather than an id the dialog has to carry; a signed-out
/// session gets an empty list instead of a query, so the dialog has no null to
/// unwrap.
final myWishlistsProvider = StreamProvider<List<Wishlist>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    return Stream<List<Wishlist>>.value(const []);
  }
  return ref
      .watch(wishlistRepositoryProvider)
      .streamWhere('ownerId', isEqualTo: userId);
}, isAutoDispose: true);
