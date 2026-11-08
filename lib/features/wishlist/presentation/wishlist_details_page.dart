import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

typedef _ClaimedText = ({Color color, bool strikeThrough});

class WishlistDetailsPage extends StatefulWidget {
  static const String routeName = 'wishlistDetails';
  static const String route = '/wishlist/:id';

  final String wishlistId;

  const WishlistDetailsPage({super.key, required this.wishlistId});

  @override
  State<WishlistDetailsPage> createState() => _WishlistDetailsPageState();
}

class _WishlistDetailsPageState extends State<WishlistDetailsPage> {
  final WishlistRepository _wishlistRepository = getIt<WishlistRepository>();
  final ClaimItemUseCase _claimItemUseCase = getIt<ClaimItemUseCase>();
  final UnclaimItemUseCase _unclaimItemUseCase = getIt<UnclaimItemUseCase>();
  late final ItemRepository _itemRepository;
  late final String? _currentUserId;
  bool _isSpoilerFree = true; // Default to spoiler-free for the owner

  @override
  void initState() {
    super.initState();
    _itemRepository = _wishlistRepository.items(widget.wishlistId);
    _currentUserId = getIt<AuthSession>().currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Wishlist>(
      stream: _wishlistRepository.streamOne(widget.wishlistId),
      builder: (context, wishlistSnapshot) {
        if (wishlistSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Loading...')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!wishlistSnapshot.hasData || wishlistSnapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Wishlist Not Found')),
            body: const Center(child: Text('Wishlist Not Found')),
          );
        }
        final wishlist = wishlistSnapshot.data!;
        final isOwner = wishlist.ownerId == _currentUserId;

        return Scaffold(
          appBar: _buildAppBar(wishlist, isOwner),
          body: StreamListBuilder<Item>(
            stream: _itemRepository.streamAll(),
            entityWidgetBuilder: (context, item) =>
                _buildItemCard(item, context, wishlist, isOwner),
            emptyMessage: 'This wishlist has no items yet.',
            listPadding: const EdgeInsets.only(bottom: 48),
          ),
          floatingActionButton: _buildFloatingActionButton(wishlist, isOwner),
        );
      },
    );
  }

  PrimaryAppBar _buildAppBar(Wishlist wishlist, bool isOwner) => PrimaryAppBar(
    title: wishlist.name,
    actions: [
      if (isOwner)
        Row(
          children: [_buildSpoilerToggleButton(), _buildEditButton(wishlist)],
        ),
    ],
  );

  Widget _buildSpoilerToggleButton() => IconButton(
    icon: Icon(_isSpoilerFree ? Icons.visibility_off : Icons.visibility),
    onPressed: () {
      setState(() {
        _isSpoilerFree = !_isSpoilerFree;
      });
    },
    tooltip: _isSpoilerFree ? 'Show claimed status' : 'Hide claimed status',
  );

  Widget _buildEditButton(Wishlist wishlist) => IconButton(
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
    Item item,
    BuildContext context,
    Wishlist wishlist,
    bool isOwner,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // The owner's view never changes: the spoiler toggle controls the status
    // text there. A reader always sees claims, so the card itself carries the
    // state.
    final applyClaimedTreatment =
        !isOwner &&
        (item.isClaimedBy(_currentUserId) || !item.hasClaimRoom);
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
          SelectionArea(child: _buildItemText(item, claimedText: claimedText)),
          _buildItemActions(item, isOwner, context),
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

  Widget _buildItemText(Item item, {required _ClaimedText? claimedText}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemNameAndUrl(item, claimedText: claimedText),
          (item.description != null && item.description!.isNotEmpty)
              ? _buildItemDescription(
                  item,
                  claimedTextColor: claimedText?.color,
                )
              : (item.url != null && item.url!.isNotEmpty)
              ? const SizedBox(height: 16) // Space between url and actions
              : const SizedBox.shrink(),
        ],
      );

  Widget _buildItemNameAndUrl(Item item, {required _ClaimedText? claimedText}) {
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
                  onTap: () => _launchURL(item.url!),
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

  Widget _buildItemDescription(Item item, {required Color? claimedTextColor}) {
    final style = claimedTextColor == null
        ? null
        : Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: claimedTextColor);
    return Text(item.description!, style: style);
  }

  Widget _buildItemActions(Item item, bool isOwner, BuildContext context) {
    final bool viewerClaimed = item.isClaimedBy(_currentUserId);

    if (isOwner) {
      return _buildOwnerActions(item);
    }

    if (viewerClaimed) {
      return _buildUserClaimedView(item);
    }

    if (!item.hasClaimRoom) {
      return _buildClaimedPill();
    }

    return _buildClaimButton(item);
  }

  Widget _buildOwnerActions(Item item) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _buildClaimedStatus(item),
      ListItemActions(
        onEdit: () {
          context.pushNamed(
            ItemFormPage.editRouteName,
            pathParameters: {'id': widget.wishlistId, 'itemId': item.id!},
            extra: item,
          );
        },
        onDelete: () => _deleteItem(item.id!),
      ),
    ],
  );

  Widget _buildClaimedStatus(Item item) {
    if (_isSpoilerFree) {
      return const Spacer();
    }
    final scheme = Theme.of(context).colorScheme;
    if (item.claimCount > 0) {
      return Text(
        'Claimed',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Text(
      'Available',
      style: TextStyle(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // A Wrap, not a Row: when the pill and its action do not fit side by side the
  // action moves to the next run instead of the row overflowing. The pill keeps
  // its natural width there, so its label breaks between words rather than
  // inside one.
  Widget _buildUserClaimedView(Item item) => Align(
    alignment: Alignment.centerRight,
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        const StatusPill(
          label: 'You claimed this!',
          tone: StatusPillTone.accent,
        ),
        TextButton(
          onPressed: () => _unclaimItem(item),
          child: const Text('Unclaim'),
        ),
      ],
    ),
  );

  Widget _buildClaimedPill() => const Align(
    alignment: Alignment.centerRight,
    child: StatusPill(label: 'Claimed', tone: StatusPillTone.neutral),
  );

  Widget _buildClaimButton(Item item) => Align(
    alignment: Alignment.centerRight,
    child: ElevatedButton(
      onPressed: () => _claimItem(item),
      child: const Text('Claim'),
    ),
  );

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        _showErrorSnackbar('Could not launch $url');
      }
    }
  }

  Future<void> _claimItem(Item item) async {
    try {
      await _claimItemUseCase.execute(widget.wishlistId, item.id!);
      if (mounted) {
        _showSuccessSnackbar('Item claimed!');
      }
    } catch (error, stackTrace) {
      if (error is! ClaimFailure) {
        // No repository seam saw this one, so it would otherwise leave no
        // trail; a classified failure is already reported by the write itself.
        appLogOrNull?.error(error, stackTrace);
      }
      if (mounted) {
        _showErrorSnackbar(claimFailureMessage(error));
      }
    }
  }

  Future<void> _unclaimItem(Item item) async {
    try {
      await _unclaimItemUseCase.execute(widget.wishlistId, item.id!);
      if (mounted) {
        _showSuccessSnackbar('Item unclaimed.');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to unclaim item: $e');
      }
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final bool? confirm = await _showDeleteDialog();
    if (confirm != true) return;

    try {
      await _itemRepository.delete(itemId);
      if (mounted) {
        _showSuccessSnackbar('Item deleted.');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to delete item: $e');
      }
    }
  }

  Future<bool?> _showDeleteDialog() => showConfirmationDialog(
    context: context,
    title: 'Delete Item?',
    content: 'Are you sure you want to delete this item? This action cannot be undone.',
    confirmText: 'Delete',
  );

  void _showSuccessSnackbar(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _showErrorSnackbar(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Widget _buildFloatingActionButton(Wishlist wishlist, bool isOwner) {
    if (!isOwner) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton(
      onPressed: () => context.pushNamed(
        ItemFormPage.createRouteName,
        pathParameters: {'id': widget.wishlistId},
      ),
      tooltip: 'Add item',
      child: const Icon(Icons.add),
    );
  }
}
