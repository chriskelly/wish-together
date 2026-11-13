import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';

/// One wishlist on the home page.
///
/// The row owns its card, its tap and the delete flow; the page owns the reads
/// and the section.
class HomeWishlistRow extends ConsumerWidget {
  const HomeWishlistRow({super.key, required this.wishlist});

  final Wishlist wishlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) => BrandCard(
    child: ListTile(
      title: Text(wishlist.name),
      trailing: ListItemActions(
        onDelete: () => _confirmDelete(context, ref),
        deleteTooltip: 'Delete Wishlist',
      ),
      onTap: () => context.goNamed(
        WishlistDetailsPage.routeName,
        pathParameters: {'id': wishlist.id!},
      ),
    ),
  );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // The row can leave the list before the write is acknowledged, so the
    // messenger and the repository are captured before the dialog.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(wishlistRepositoryProvider);
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Deletion',
      content: 'Are you sure you want to delete this wishlist?',
      confirmText: 'Delete',
    );
    if (confirmed != true) return;

    try {
      // Purges the items first: Firestore keeps a sub-collection when its
      // parent document is deleted.
      await repository.deleteWithItems(wishlist.id!);
      messenger.showSnackBar(
        const SnackBar(content: Text('Wishlist deleted.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
