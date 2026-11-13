import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/list_content_builder.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_item_row.dart';

class WishlistDetailsPage extends ConsumerWidget {
  static const String routeName = 'wishlistDetails';
  static const String route = '/wishlist/:id';

  final String wishlistId;

  const WishlistDetailsPage({super.key, required this.wishlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the toggle before the loading/error returns so the owner's choice
    // survives an error frame rather than being disposed with the page body.
    final isSpoilerFree = ref.watch(wishlistSpoilerFreeProvider(wishlistId));
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
    final itemsAsync = ref.watch(wishlistItemsProvider(wishlistId));

    return Scaffold(
      appBar: _buildAppBar(context, ref, wishlist, isOwner, isSpoilerFree),
      body: ListContentBuilder<Item>(
        items: itemsAsync.value,
        error: itemsAsync.error,
        entityWidgetBuilder: (context, item) => WishlistItemRow(
          key: ValueKey(item.id),
          wishlistId: wishlistId,
          item: item,
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

  Widget _buildFloatingActionButton(BuildContext context, bool isOwner) {
    if (!isOwner) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton(
      onPressed: () => context.pushNamed(
        ItemFormPage.createRouteName,
        pathParameters: {'id': wishlistId},
        extra: CreateItemRouteArgs(),
      ),
      tooltip: 'Add item',
      child: const Icon(Icons.add),
    );
  }
}
