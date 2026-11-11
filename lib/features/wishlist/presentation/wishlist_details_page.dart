import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';
import 'package:url_launcher/url_launcher.dart';

typedef _ClaimedText = ({Color color, bool strikeThrough});

class WishlistDetailsPage extends ConsumerWidget {
  static const String routeName = 'wishlistDetails';
  static const String route = '/wishlist/:id';

  final String wishlistId;

  const WishlistDetailsPage({super.key, required this.wishlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlistAsync = ref.watch(wishlistProvider(wishlistId));
    // AsyncValue.value keeps the previous value during an error. The old
    // StreamBuilder cleared data on error, so check the error first.
    if (wishlistAsync.hasError) {
      return _notFoundScaffold();
    }
    final wishlist = wishlistAsync.value;
    if (wishlist == null) {
      return wishlistAsync.isLoading ? _loadingScaffold() : _notFoundScaffold();
    }

    final userId = ref.watch(currentUserIdProvider);
    final isOwner = wishlist.ownerId == userId;
    final isSpoilerFree = ref.watch(wishlistSpoilerFreeProvider(wishlistId));
    final itemsAsync = ref.watch(wishlistItemsProvider(wishlistId));

    return Scaffold(
      appBar: _buildAppBar(context, ref, wishlist, isOwner, isSpoilerFree),
      body: ListContentBuilder<Item>(
        items: itemsAsync.value,
        error: itemsAsync.error,
        entityWidgetBuilder: (context, item) => _buildItemCard(
          context,
          ref,
          item,
          isOwner: isOwner,
          isSpoilerFree: isSpoilerFree,
          userId: userId,
        ),
        emptyMessage: 'This wishlist has no items yet.',
        listPadding: const EdgeInsets.only(bottom: 48),
      ),
      floatingActionButton: _buildFloatingActionButton(context, isOwner),
    );
  }

  Widget _loadingScaffold() => Scaffold(
    appBar: AppBar(title: const Text('Loading...')),
    body: const Center(child: CircularProgressIndicator()),
  );

  Widget _notFoundScaffold() => Scaffold(
    appBar: AppBar(title: const Text('Wishlist Not Found')),
    body: const Center(child: Text('Wishlist Not Found')),
  );

  PrimaryAppBar _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    Wishlist wishlist,
    bool isOwner,
    bool isSpoilerFree,
  ) => PrimaryAppBar(
    title: wishlist.name,
    actions: [
      if (isOwner)
        Row(
          children: [
            _buildSpoilerToggleButton(ref, isSpoilerFree),
            _buildEditButton(context, wishlist),
          ],
        ),
    ],
  );

  Widget _buildSpoilerToggleButton(WidgetRef ref, bool isSpoilerFree) =>
      IconButton(
        icon: Icon(isSpoilerFree ? Icons.visibility_off : Icons.visibility),
        onPressed: () =>
            ref.read(wishlistSpoilerFreeProvider(wishlistId).notifier).toggle(),
        tooltip: isSpoilerFree ? 'Show claimed status' : 'Hide claimed status',
      );

  Widget _buildEditButton(BuildContext context, Wishlist wishlist) =>
      IconButton(
        icon: const Icon(Icons.edit),
        onPressed: () {
          context.pushNamed(
            WishlistFormPage.editRouteName,
            pathParameters: {'id': wishlist.id!},
            extra: wishlist,
          );
        },
        tooltip: 'Edit Wishlist',
      );

  Widget _buildItemCard(
    BuildContext context,
    WidgetRef ref,
    Item item, {
    required bool isOwner,
    required bool isSpoilerFree,
    required String? userId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // An owner's card never carries the claimed treatment; the spoiler toggle
    // only controls the status text. A reader always sees claims, so the card
    // itself carries the state.
    final applyClaimedTreatment =
        !isOwner && (item.isClaimedBy(userId) || !item.hasClaimRoom);
    final claimedText = applyClaimedTreatment
        ? (color: scheme.onSurfaceVariant, strikeThrough: true)
        : null;

    final cardBody = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One area per card lets a drag select across the name, link and
          // description. The action row stays outside it, so its buttons keep
          // their own long-press behaviour.
          SelectionArea(
            child: _buildItemText(context, item, claimedText: claimedText),
          ),
          _buildItemActions(
            context,
            ref,
            item,
            isOwner: isOwner,
            isSpoilerFree: isSpoilerFree,
            userId: userId,
          ),
        ],
      ),
    );

    return BrandCard(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      backgroundColor: applyClaimedTreatment
          ? scheme.surfaceContainerHighest
          : null,
      child: cardBody,
    );
  }

  Widget _buildItemText(
    BuildContext context,
    Item item, {
    required _ClaimedText? claimedText,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildItemNameAndUrl(context, item, claimedText: claimedText),
      (item.description != null && item.description!.isNotEmpty)
          ? _buildItemDescription(
              context,
              item,
              claimedTextColor: claimedText?.color,
            )
          : (item.url != null && item.url!.isNotEmpty)
          ? const SizedBox(height: 16) // Space between url and actions
          : const SizedBox.shrink(),
    ],
  );

  Widget _buildItemNameAndUrl(
    BuildContext context,
    Item item, {
    required _ClaimedText? claimedText,
  }) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: claimedText?.color,
      decoration: (claimedText?.strikeThrough ?? false)
          ? TextDecoration.lineThrough
          : null,
      decorationColor: claimedText?.color,
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
    BuildContext context,
    Item item, {
    required Color? claimedTextColor,
  }) {
    final style = claimedTextColor == null
        ? null
        : Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: claimedTextColor);
    return Text(item.description!, style: style);
  }

  Widget _buildItemActions(
    BuildContext context,
    WidgetRef ref,
    Item item, {
    required bool isOwner,
    required bool isSpoilerFree,
    required String? userId,
  }) {
    if (isOwner) {
      return _buildOwnerActions(
        context,
        ref,
        item,
        isSpoilerFree: isSpoilerFree,
      );
    }

    if (item.isClaimedBy(userId)) {
      return _buildUserClaimedView(context, ref, item);
    }

    if (!item.hasClaimRoom) {
      return _buildUnavailablePill();
    }

    return _buildClaimButton(context, ref, item);
  }

  Widget _buildOwnerActions(
    BuildContext context,
    WidgetRef ref,
    Item item, {
    required bool isSpoilerFree,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _buildOwnerStatus(context, item, isSpoilerFree: isSpoilerFree),
      ),
      ListItemActions(
        onEdit: () {
          context.pushNamed(
            ItemFormPage.editRouteName,
            pathParameters: {'id': wishlistId, 'itemId': item.id!},
            extra: item,
          );
        },
        onDelete: () => _deleteItem(context, ref, item.id!),
      ),
    ],
  );

  Widget _buildOwnerStatus(
    BuildContext context,
    Item item, {
    required bool isSpoilerFree,
  }) => isSpoilerFree
      ? _buildClaimLimitText(context, item)
      : _buildClaimedStatus(context, item);

  TextStyle _mutedTextStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _buildClaimLimitText(BuildContext context, Item item) =>
      Text(_claimLimitLabel(item), style: _mutedTextStyle(context));

  String _claimLimitLabel(Item item) {
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
  String _claimSummary(Item item) {
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
  String? _readerClaimSummary(Item item) =>
      item.claimLimit == 1 ? null : _claimSummary(item);

  Widget _buildClaimedStatus(BuildContext context, Item item) {
    final italic = _mutedTextStyle(context)
        .copyWith(fontStyle: FontStyle.italic);
    if (item.claimLimit != 1) {
      return Text(_claimSummary(item), style: italic);
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

  Widget _buildUserClaimedView(
    BuildContext context,
    WidgetRef ref,
    Item item,
  ) => _claimActionRow(
    context,
    summary: _readerClaimSummary(item),
    trailing: [
      const StatusPill(label: 'You claimed this!', tone: StatusPillTone.accent),
      TextButton(
        onPressed: () => _unclaimItem(context, ref, item),
        child: const Text('Unclaim'),
      ),
    ],
  );

  Widget _buildUnavailablePill() => const Align(
    alignment: Alignment.centerRight,
    child: StatusPill(label: 'Unavailable', tone: StatusPillTone.neutral),
  );

  Widget _buildClaimButton(BuildContext context, WidgetRef ref, Item item) =>
      _claimActionRow(
        context,
        summary: _readerClaimSummary(item),
        trailing: [
          ElevatedButton(
            onPressed: () => _claimItem(context, ref, item),
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
        _showErrorSnackbar(context, 'Could not launch $url');
      }
    }
  }

  Future<void> _claimItem(
    BuildContext context,
    WidgetRef ref,
    Item item,
  ) async {
    try {
      final ran = await ref
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .claim(item.id!);
      if (!ran || !context.mounted) {
        return;
      }
      _showSuccessSnackbar(context, 'Item claimed!');
    } catch (error, stackTrace) {
      if (error is! ClaimFailure) {
        // No repository seam saw this one, so it would otherwise leave no
        // trail; a classified failure is already reported by the write itself.
        appLogOrNull?.error(error, stackTrace);
      }
      if (!context.mounted) {
        return;
      }
      _showErrorSnackbar(context, claimFailureMessage(error));
    }
  }

  Future<void> _unclaimItem(
    BuildContext context,
    WidgetRef ref,
    Item item,
  ) async {
    try {
      final ran = await ref
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .unclaim(item.id!);
      if (!ran || !context.mounted) {
        return;
      }
      _showSuccessSnackbar(context, 'Item unclaimed.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _showErrorSnackbar(
        context,
        error is ClaimFailure
            ? claimFailureMessage(error)
            : "Couldn't unclaim this item. Please try again.",
      );
    }
  }

  Future<void> _deleteItem(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    final bool? confirm = await _showDeleteDialog(context);
    if (confirm != true || !context.mounted) {
      return;
    }

    try {
      final ran = await ref
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .delete(itemId);
      if (!ran || !context.mounted) {
        return;
      }
      _showSuccessSnackbar(context, 'Item deleted.');
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      _showErrorSnackbar(context, 'Failed to delete item: $e');
    }
  }

  Future<bool?> _showDeleteDialog(BuildContext context) =>
      showConfirmationDialog(
        context: context,
        title: 'Delete Item?',
        content: 'Are you sure you want to delete this item? This action cannot be undone.',
        confirmText: 'Delete',
      );

  void _showSuccessSnackbar(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _showErrorSnackbar(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Widget _buildFloatingActionButton(BuildContext context, bool isOwner) {
    if (!isOwner) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton(
      onPressed: () => context.pushNamed(
        ItemFormPage.createRouteName,
        pathParameters: {'id': wishlistId},
      ),
      tooltip: 'Add item',
      child: const Icon(Icons.add),
    );
  }
}
