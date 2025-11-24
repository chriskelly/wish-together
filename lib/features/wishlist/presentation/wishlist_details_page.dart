import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/list_item_actions.dart';
import 'package:wishtogether/common/widgets/stream_list_builder.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';

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
    _currentUserId = getIt<AuthService>().currentUserId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: StreamListBuilder<Item>(
        stream: _itemRepository.streamAll(),
        entityWidgetBuilder: (context, item) => _buildItemCard(item, context),
        emptyMessage: 'This wishlist has no items yet.',
        listPadding: const EdgeInsets.only(bottom: 48),
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  AppBar _buildAppBar() =>
      AppBar(title: _buildAppBarTitle(), actions: [_buildAppBarActions()]);

  Widget _buildAppBarTitle() => FutureBuilder<Wishlist?>(
    future: _wishlistRepository.get(widget.wishlistId),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Text('Loading...');
      }
      if (!snapshot.hasData || snapshot.data == null) {
        return const Text('Wishlist Not Found');
      }
      return Text(
        snapshot.data!.name,
        style: Theme.of(context).textTheme.headlineSmall,
      );
    },
  );

  Widget _buildAppBarActions() => FutureBuilder<Wishlist?>(
    future: _wishlistRepository.get(widget.wishlistId),
    builder: (context, snapshot) {
      if (!snapshot.hasData ||
          _currentUserId == null ||
          snapshot.data == null) {
        return const SizedBox.shrink();
      }
      final wishlist = snapshot.data!;
      if (wishlist.ownerId == _currentUserId) {
        return Row(
          children: [_buildSpoilerToggleButton(), _buildEditButton(wishlist)],
        );
      }
      return const SizedBox.shrink();
    },
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

  Widget _buildItemCard(Item item, BuildContext context) {
    return FutureBuilder<Wishlist?>(
      future: _wishlistRepository.get(widget.wishlistId),
      builder: (context, wishlistSnapshot) {
        if (!wishlistSnapshot.hasData) return const SizedBox.shrink();
        final isOwner = wishlistSnapshot.data!.ownerId == _currentUserId;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildItemNameAndUrl(item),
                (item.description != null && item.description!.isNotEmpty)
                    ? _buildItemDescription(item)
                    : (item.url != null && item.url!.isNotEmpty)
                    ? const SizedBox(
                        height: 16,
                      ) // Ensure there's space between url and actions
                    : const SizedBox.shrink(),
                _buildItemActions(item, isOwner, context),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemNameAndUrl(Item item) {
    // The Row first allocates the fixed 8px spacing.
    // The Flexible URL takes half the space if there is a url.
    // The Expanded name takes all space if there is no url.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              item.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (item.url != null && item.url!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => _launchURL(item.url!),
                  child: Text(
                    item.url!,
                    style: const TextStyle(
                      color: Colors.blue,
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

  Widget _buildItemDescription(Item item) => Text(item.description!);

  Widget _buildItemActions(Item item, bool isOwner, BuildContext context) {
    final bool isClaimed = item.claimedBy != null;
    final bool claimedByCurrentUser = item.claimedBy == _currentUserId;

    if (isOwner) {
      return _buildOwnerActions(item, isClaimed);
    }

    if (isClaimed) {
      if (claimedByCurrentUser) {
        return _buildUserClaimedView(item);
      }
      return _buildClaimedChip();
    }

    return _buildClaimButton(item);
  }

  Widget _buildOwnerActions(Item item, bool isClaimed) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _buildClaimedStatus(item, isClaimed),
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

  Widget _buildClaimedStatus(Item item, bool isClaimed) {
    if (_isSpoilerFree) {
      return const Spacer();
    }
    if (isClaimed) {
      return Text(
        'Claimed on ${DateFormat.yMMMd().format(item.claimedAt!)}',
        style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
      );
    }
    return const Text(
      'Available',
      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildUserClaimedView(Item item) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      const Text(
        'You claimed this!',
        style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () => _unclaimItem(item),
        child: const Text('Unclaim'),
      ),
    ],
  );

  Widget _buildClaimedChip() => const Align(
    alignment: Alignment.centerRight,
    child: Chip(label: Text('Claimed'), backgroundColor: Colors.grey),
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
      await _claimItemUseCase.execute(widget.wishlistId, item);
      if (mounted) {
        _showSuccessSnackbar('Item claimed!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to claim item: $e');
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

  void _showSuccessSnackbar(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _showErrorSnackbar(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Widget _buildFloatingActionButton() => FutureBuilder<Wishlist?>(
    future: _wishlistRepository.get(widget.wishlistId),
    builder: (context, snapshot) {
      if (!snapshot.hasData || _currentUserId == null) {
        return const SizedBox.shrink();
      }
      if (snapshot.data!.ownerId == _currentUserId) {
        return FloatingActionButton(
          onPressed: () => context.pushNamed(
            ItemFormPage.createRouteName,
            pathParameters: {'id': widget.wishlistId},
          ),
          child: const Icon(Icons.add),
        );
      }
      return const SizedBox.shrink();
    },
  );
}
