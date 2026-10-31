import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

/// Deletes the signed-in user's account and the data that belongs to them.
///
/// Runs as a best-effort client-side cascade, in the only order that works:
/// the caller re-authenticates first (Firebase requires a recent login), then
/// the Firestore writes happen while the session is still live, and the auth
/// account is deleted last. Every step is safe to repeat, so a failed run can
/// simply be retried after re-authenticating again.
///
/// What it does:
/// - deletes the user's own wishlists and their items;
/// - hands an owned group to its first remaining member, or deletes the group
///   when the user was its last member;
/// - removes the user from the groups they do not own;
/// - deletes the `users/{uid}` profile document;
/// - deletes the auth account.
///
/// What it deliberately leaves alone: claims on items in other people's
/// wishlists. A claimed item stays claimed, so a deleted account cannot cause
/// the same gift to be bought twice. Nothing outside the user's own documents
/// and groups is written.
///
/// A server-side cascade (a Cloud Function) could delete the sub-collections
/// and the auth account atomically; this one is a sequence of client writes, so
/// a mid-way failure leaves a partially-deleted account that a rerun finishes.
class DeleteAccountUseCase {
  Future<void> execute() async {
    // The identity comes from the session; deleting the auth account is a
    // production-only capability, so it is taken from the service itself.
    final session = getIt<AuthSession>();
    final authService = getIt<AuthService>();
    final userRepository = getIt<UserRepository>();
    final wishlistRepository = getIt<WishlistRepository>();
    final groupRepository = getIt<GroupRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    // The user's own wishlists, with their items.
    final ownedWishlists = await wishlistRepository.listOwnedBy(userId);
    for (final wishlist in ownedWishlists) {
      await wishlistRepository.deleteWithItems(wishlist.id!);
    }

    // Groups: hand over (or delete) the ones the user owns, leave the rest.
    final ownedGroups = await groupRepository.listOwnedBy(userId);
    final memberGroups = await groupRepository.listForMember(userId);
    final ownedGroupIds = ownedGroups.map((group) => group.id).toSet();

    for (final group in ownedGroups) {
      final remainingMembers = group.members
          .where((member) => member != userId)
          .toList();
      if (remainingMembers.isEmpty) {
        await groupRepository.delete(group.id!);
      } else {
        await groupRepository.transferOwnership(
          group.id!,
          remainingMembers.first,
          remainingMembers,
        );
      }
    }

    for (final group in memberGroups) {
      if (ownedGroupIds.contains(group.id)) {
        continue;
      }
      await groupRepository.leaveGroup(group.id!, userId);
    }

    await userRepository.delete(userId);

    // The auth account goes last: the writes above need the session, and
    // nothing after this step needs an authenticated user.
    await authService.deleteAccount();
  }
}
