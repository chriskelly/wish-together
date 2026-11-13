import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';

/// One group on the home page.
///
/// The row owns its card, its tap and the owner-only delete flow; [userId] is
/// passed in so the page watches the session once for all rows.
class HomeGroupRow extends ConsumerWidget {
  const HomeGroupRow({super.key, required this.group, required this.userId});

  final Group group;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = group.ownerId == userId;
    return BrandCard(
      child: ListTile(
        title: Text(group.name),
        trailing: isOwner
            ? ListItemActions(
                onDelete: () => _confirmDelete(context, ref),
                deleteTooltip: 'Delete Group',
              )
            : null,
        onTap: () => context.goNamed(
          GroupDetailsPage.routeName,
          pathParameters: {'id': group.id!},
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // The row can leave the list before the write is acknowledged, so the
    // messenger and the repository are captured before the dialog.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(groupRepositoryProvider);
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Confirm Deletion',
      content: 'Are you sure you want to delete this group?',
      confirmText: 'Delete',
    );
    if (confirmed != true) return;

    try {
      await repository.delete(group.id!);
      messenger.showSnackBar(const SnackBar(content: Text('Group deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
