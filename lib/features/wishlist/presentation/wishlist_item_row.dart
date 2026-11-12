import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// One item card on the wishlist details page.
///
/// The row owns its rendering and its claim/unclaim/delete side effects; the
/// page owns the streams, the app bar and navigation. `userId` and the owner and
/// spoiler flags are inputs so the page watches each provider once.
class WishlistItemRow extends ConsumerWidget {
  const WishlistItemRow({
    super.key,
    required this.wishlistId,
    required this.item,
    required this.isOwner,
    required this.isSpoilerFree,
    required this.userId,
  });

  final String wishlistId;
  final Item item;
  final bool isOwner;
  final bool isSpoilerFree;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // An owner's card never carries the claimed treatment; the spoiler toggle
    // only controls the status text. A reader always sees claims, so the card
    // itself carries the state.
    final applyClaimedTreatment =
        !isOwner && (item.isClaimedBy(userId) || !item.hasClaimRoom);
    final claimedColor = applyClaimedTreatment ? scheme.onSurfaceVariant : null;

    final cardBody = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One area per card lets a drag select across the name, link and
          // description. The action row stays outside it, so its buttons keep
          // their own long-press behaviour.
          SelectionArea(
            child: _buildItemText(context, claimedColor: claimedColor),
          ),
          _buildItemActions(context, ref),
        ],
      ),
    );

    return BrandCard(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      backgroundColor: applyClaimedTreatment
          ? scheme.surfaceContainerHighest
          : null,
      child: cardBody,
    );
  }

  Widget _buildItemText(BuildContext context, {required Color? claimedColor}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemNameAndUrl(context, claimedColor: claimedColor),
          (item.description != null && item.description!.isNotEmpty)
              ? _buildItemDescription(context, claimedTextColor: claimedColor)
              : (item.url != null && item.url!.isNotEmpty)
              ? const SizedBox(height: 16) // Space between url and actions
              : const SizedBox.shrink(),
        ],
      );

  Widget _buildItemNameAndUrl(
    BuildContext context, {
    required Color? claimedColor,
  }) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: claimedColor,
      decoration: claimedColor == null ? null : TextDecoration.lineThrough,
      decorationColor: claimedColor,
    );

    // The Row first allocates the fixed 8px spacing.
    // The Flexible URL takes half the space if there is a url.
    // The Expanded name takes all space if there is no url.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(item.name, style: titleStyle)),
          if (item.url != null && item.url!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => _launchURL(context, item.url!),
                  child: Text(
                    item.url!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemDescription(
    BuildContext context, {
    required Color? claimedTextColor,
  }) {
    final style = claimedTextColor == null
        ? null
        : Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: claimedTextColor);
    return Text(item.description!, style: style);
  }

  Widget _buildItemActions(BuildContext context, WidgetRef ref) {
    if (isOwner) {
      return _buildOwnerActions(context, ref);
    }

    if (item.isClaimedBy(userId)) {
      return _buildUserClaimedView(context, ref);
    }

    if (!item.hasClaimRoom) {
      return _buildUnavailablePill();
    }

    return _buildClaimButton(context, ref);
  }

  Widget _buildOwnerActions(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _buildOwnerStatus(context)),
      ListItemActions(
        onEdit: () {
          context.pushNamed(
            ItemFormPage.editRouteName,
            pathParameters: {'id': wishlistId, 'itemId': item.id!},
            extra: EditItemRouteArgs(item),
          );
        },
        onDelete: () => _deleteItem(context, ref, item.id!),
      ),
    ],
  );

  Widget _buildOwnerStatus(BuildContext context) => isSpoilerFree
      ? _buildClaimLimitText(context)
      : _buildClaimedStatus(context);

  TextStyle _mutedTextStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _buildClaimLimitText(BuildContext context) =>
      Text(_claimLimitLabel(), style: _mutedTextStyle(context));

  String _claimLimitLabel() {
    if (item.isUnlimited) {
      return 'Unlimited claims';
    }
    if (item.claimLimit == 1) {
      return '1 person can claim';
    }
    return '${item.claimLimit} people can claim';
  }

  /// The claim count copy, shared by the owner's revealed view and the reader
  /// rows so the two can never drift.
  String _claimSummary() {
    if (item.isUnlimited) {
      return item.claimCount == 0
          ? 'No claims yet'
          : '${item.claimCount} claimed';
    }
    if (item.claimCount == 0) {
      return 'No claims yet';
    }
    return '${item.claimCount} of ${item.claimLimit} claimed';
  }

  /// A single-claim item never shows a count; multi and unlimited items do.
  String? _readerClaimSummary() =>
      item.claimLimit == 1 ? null : _claimSummary();

  Widget _buildClaimedStatus(BuildContext context) {
    final italic = _mutedTextStyle(context)
        .copyWith(fontStyle: FontStyle.italic);
    if (item.claimLimit != 1) {
      return Text(_claimSummary(), style: italic);
    }
    if (item.claimCount > 0) {
      return Text('Claimed', style: italic);
    }
    return Text(
      'Available',
      style: _mutedTextStyle(context).copyWith(fontWeight: FontWeight.bold),
    );
  }

  // A Wrap, not a Row: when the count, pill and action do not fit side by side
  // the action moves to the next run instead of the row overflowing. The pill
  // keeps its natural width there, so its label breaks between words rather
  // than inside one.
  Widget _claimActionRow(
    BuildContext context, {
    String? summary,
    required List<Widget> trailing,
  }) => Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (summary != null) Text(summary, style: _mutedTextStyle(context)),
        ...trailing,
      ],
    ),
  );

  Widget _buildUserClaimedView(BuildContext context, WidgetRef ref) =>
      _claimActionRow(
        context,
        summary: _readerClaimSummary(),
        trailing: [
          const StatusPill(
            label: 'You claimed this!',
            tone: StatusPillTone.accent,
          ),
          TextButton(
            onPressed: () => _unclaimItem(context, ref),
            child: const Text('Unclaim'),
          ),
        ],
      );

  Widget _buildUnavailablePill() => const Align(
    alignment: Alignment.centerRight,
    child: StatusPill(label: 'Unavailable', tone: StatusPillTone.neutral),
  );

  Widget _buildClaimButton(BuildContext context, WidgetRef ref) =>
      _claimActionRow(
        context,
        summary: _readerClaimSummary(),
        trailing: [
          ElevatedButton(
            onPressed: () => _claimItem(context, ref),
            child: const Text('Claim'),
          ),
        ],
      );

  Future<void> _launchURL(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        _showSnackBar(context, 'Could not launch $url');
      }
    }
  }

  Future<void> _claimItem(BuildContext context, WidgetRef ref) => _runAction(
    context,
    () => ref
        .read(wishlistItemActionsProvider(wishlistId).notifier)
        .claim(item.id!),
    success: 'Item claimed!',
    failure: claimFailureMessage,
    onError: (error, stackTrace) {
      if (error is! ClaimFailure) {
        // No repository seam saw this one, so it would otherwise leave no
        // trail; a classified failure is already reported by the write itself.
        appLogOrNull?.error(error, stackTrace);
      }
    },
  );

  Future<void> _unclaimItem(BuildContext context, WidgetRef ref) => _runAction(
    context,
    () => ref
        .read(wishlistItemActionsProvider(wishlistId).notifier)
        .unclaim(item.id!),
    success: 'Item unclaimed.',
    failure: (error) => error is ClaimFailure
        ? claimFailureMessage(error)
        : "Couldn't unclaim this item. Please try again.",
  );

  Future<void> _deleteItem(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    // The delete removes this row before the backend acknowledges it; the
    // app-level messenger outlives the row, so the copy still lands.
    final messenger = ScaffoldMessenger.of(context);
    final bool? confirm = await _showDeleteDialog(context);
    if (confirm != true || !context.mounted) {
      return;
    }
    await _runAction(
      context,
      () => ref
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .delete(itemId),
      success: 'Item deleted.',
      failure: (error) => 'Failed to delete item: $error',
      messenger: messenger,
    );
  }

  /// Runs one command, shows its success copy only when it actually ran, and
  /// maps a failure. [onError] sees every failure before the snackbar, so the
  /// claim path can report an unclassified error without changing the copy.
  Future<void> _runAction(
    BuildContext context,
    Future<bool> Function() action, {
    required String success,
    required String Function(Object error) failure,
    void Function(Object error, StackTrace stackTrace)? onError,
    ScaffoldMessengerState? messenger,
  }) async {
    try {
      final ran = await action();
      if (!ran || (messenger == null && !context.mounted)) {
        return;
      }
      _showSnackBar(context, success, messenger: messenger);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      if (messenger == null && !context.mounted) {
        return;
      }
      _showSnackBar(context, failure(error), messenger: messenger);
    }
  }

  Future<bool?> _showDeleteDialog(BuildContext context) =>
      showConfirmationDialog(
        context: context,
        title: 'Delete Item?',
        content: 'Are you sure you want to delete this item? This action cannot be undone.',
        confirmText: 'Delete',
      );

  void _showSnackBar(
    BuildContext context,
    String message, {
    ScaffoldMessengerState? messenger,
  }) {
    if (messenger != null) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
