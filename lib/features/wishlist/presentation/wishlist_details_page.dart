import 'dart:async';

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
    final itemState = itemsAsync.value;

    return Scaffold(
      appBar: _buildAppBar(context, ref, wishlist, isOwner, isSpoilerFree),
      body: ListContentBuilder<Item>(
        items: itemState?.items,
        error: itemsAsync.error,
        emptyWidget: itemState?.isUnconfirmedEmpty == true
            ? _ItemsUnavailable(
                isLoading: itemsAsync.isLoading,
                onRetry: () =>
                    ref.invalidate(wishlistItemsProvider(wishlistId)),
              )
            : null,
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

/// The item read's "couldn't load" state: an empty list the server has not
/// confirmed.
///
/// A cache-only snapshot can also be the first frame of an online read, before
/// the server answers. The failure is held back for [_gracePeriod], so a quick
/// online reply does not flash it; a cache-only read that persists means the
/// server has not confirmed the empty result.
///
/// A retry starts a fresh grace window on the tap and again when the reload
/// resolves, so neither a fast nor a slow first cache-only snapshot flashes
/// the panel before the server replies.
class _ItemsUnavailable extends StatefulWidget {
  const _ItemsUnavailable({required this.isLoading, required this.onRetry});

  /// True while the read is in flight. This is `itemsAsync.isLoading`, not
  /// Riverpod's `isReloading`/`isRefreshing`: the panel must hide for an
  /// invalidate as well as a dependency rebuild.
  final bool isLoading;

  final VoidCallback onRetry;

  @override
  State<_ItemsUnavailable> createState() => _ItemsUnavailableState();
}

class _ItemsUnavailableState extends State<_ItemsUnavailable> {
  static const _gracePeriod = Duration(milliseconds: 800);

  Timer? _timer;
  bool _showFailure = false;

  @override
  void initState() {
    super.initState();
    _startGrace();
  }

  @override
  void didUpdateWidget(covariant _ItemsUnavailable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading != oldWidget.isLoading) {
      _startGrace();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startGrace() {
    _timer?.cancel();
    _showFailure = false;
    _timer = Timer(_gracePeriod, () {
      if (mounted) {
        setState(() => _showFailure = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showFailure || widget.isLoading) {
      return Semantics(
        liveRegion: true,
        container: true,
        child: const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading wishlist items',
          ),
        ),
      );
    }
    return _failurePanel(context);
  }

  Widget _failurePanel(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Could not load the items.',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Check your connection and try again.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(_startGrace);
                    widget.onRetry();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
