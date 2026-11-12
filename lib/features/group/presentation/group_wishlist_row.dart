import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/presentation/providers/group_details_providers.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';

/// One wishlist shared into the group.
///
/// The row owns its card, its owner subtitle and the remove action; the page
/// owns the reads and the section. [userId] is the viewer, passed in so the
/// page watches the session once for all rows.
class GroupWishlistRow extends ConsumerWidget {
  const GroupWishlistRow({
    super.key,
    required this.groupId,
    required this.wishlist,
    required this.userId,
  });

  final String groupId;
  final Wishlist wishlist;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = wishlist.ownerId == userId;
    final ownerAsync = ref.watch(wishlistOwnerProvider(wishlist.ownerId));

    return BrandCard(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        title: Text(wishlist.name),
        // Its own semantics node, so the row's accessible name is exactly the
        // wishlist name. Without it the tile merges title and subtitle into one
        // label ("<name>\nOwned by <person>"), and a selector written against
        // the name breaks whenever the owner changes.
        subtitle: Semantics(
          container: true,
          child: Text(_ownerLabel(ownerAsync, isOwner)),
        ),
        onTap: () => context.pushNamed(
          WishlistDetailsPage.routeName,
          pathParameters: {'id': wishlist.id!},
        ),
        trailing: isOwner
            ? ListItemActions(
                onDelete: () => _confirmRemove(context, ref),
                deleteIcon: Icons.remove_circle_outline,
                deleteTooltip: 'Remove from group',
              )
            : null,
      ),
    );
  }

  /// The owner line, keeping the three states the page showed before the
  /// migration: waiting, a resolved owner, and a missing or failed profile.
  String _ownerLabel(AsyncValue<User> ownerAsync, bool isOwner) {
    if (ownerAsync.hasError) {
      return 'by an unknown user';
    }
    final owner = ownerAsync.value;
    if (owner == null) {
      return 'Loading...';
    }
    return isOwner ? 'Owned by you' : 'Owned by ${owner.displayName}';
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    // This row can leave the list before the write is acknowledged, so the
    // messenger and the repository are captured now: a `ref.read` after the
    // await would throw once the row is unmounted, and the remove would be
    // lost.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(wishlistRepositoryProvider);
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Remove Wishlist?',
      content:
          'Are you sure you want to remove "${wishlist.name}" from this group?',
      confirmText: 'Remove',
    );
    if (confirmed != true) return;

    try {
      await repository.removeWishlistFromGroup(wishlist.id!, groupId);
      messenger.showSnackBar(
        const SnackBar(content: Text('Wishlist removed from group.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to remove wishlist: $e')),
      );
    }
  }
}
