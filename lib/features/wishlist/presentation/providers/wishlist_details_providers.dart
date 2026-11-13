import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// The wishlist and its items are reads: each stream is created once while the
/// page is mounted and disposed when it leaves, so a widget rebuild cannot
/// re-subscribe or refetch. The explicit Try again invalidates the item read;
/// that is the one deliberate exception.
final wishlistProvider = StreamProvider.family<Wishlist, String>(
  (ref, wishlistId) =>
      ref.watch(wishlistRepositoryProvider).streamOne(wishlistId),
  isAutoDispose: true,
);

/// The item read's presentation state, derived from the repository's
/// `ListSnapshot`.
///
/// Keeping it here lets the page depend on this provider rather than the data
/// layer. [hasCredibleData] records whether this subscription has seen a
/// server-confirmed snapshot or a non-empty local one; only an empty read with
/// no such history is a failed read.
class WishlistItems {
  const WishlistItems({required this.items, required this.hasCredibleData});

  final List<Item> items;
  final bool hasCredibleData;

  /// True when the list is empty and this subscription has no server-confirmed
  /// or non-empty local read.
  bool get isUnconfirmedEmpty => items.isEmpty && !hasCredibleData;
}

final wishlistItemsProvider = StreamProvider.family<WishlistItems, String>((
  ref,
  wishlistId,
) {
  // Per subscription: a retry starts a fresh listener and must not inherit
  // credibility from the read it replaced.
  var hasCredibleData = false;
  final repository = ref.watch(itemRepositoryProvider(wishlistId));
  return repository.streamAll().map((snapshot) {
    hasCredibleData =
        hasCredibleData || !snapshot.isFromCache || snapshot.items.isNotEmpty;
    return WishlistItems(
      items: snapshot.items,
      hasCredibleData: hasCredibleData,
    );
  });
}, isAutoDispose: true);

/// The owner's spoiler-free toggle. It starts on, so a fresh visit hides claim
/// status until the owner asks to reveal it.
final wishlistSpoilerFreeProvider =
    NotifierProvider.family<SpoilerFree, bool, String>(
      (_) => SpoilerFree(),
      isAutoDispose: true,
    );

class SpoilerFree extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

/// The mutating actions, serialised page-wide.
final wishlistItemActionsProvider =
    NotifierProvider.family<ItemActions, ItemActionState, String>(
      ItemActions.new,
      isAutoDispose: true,
    );

/// The command state: [busyItemId] while an action runs, null otherwise.
///
/// It has no `==` because nothing watches it; the notifier reads it only to
/// serialise actions.
class ItemActionState {
  const ItemActionState({this.busyItemId});

  /// The item whose action is running, or null when nothing is in flight.
  final String? busyItemId;
}

class ItemActions extends Notifier<ItemActionState> {
  ItemActions(this.wishlistId);

  final String wishlistId;

  @override
  ItemActionState build() => const ItemActionState();

  /// Claims [itemId] for the signed-in user.
  ///
  /// Returns false when another action is already running, so the caller can
  /// avoid a second success message. Failures propagate unchanged.
  Future<bool> claim(String itemId) => _run(
    itemId,
    () => ref.read(claimItemUseCaseProvider).execute(wishlistId, itemId),
  );

  Future<bool> unclaim(String itemId) => _run(
    itemId,
    () => ref.read(unclaimItemUseCaseProvider).execute(wishlistId, itemId),
  );

  Future<bool> delete(String itemId) => _run(
    itemId,
    () => ref.read(itemRepositoryProvider(wishlistId)).delete(itemId),
  );

  Future<bool> _run(String itemId, Future<void> Function() action) async {
    if (state.busyItemId != null) {
      return false;
    }

    // A plain read opens and closes a temporary listener. Without this link an
    // auto-disposed notifier would be gone by the next frame, and a second tap
    // would see a fresh, idle notifier and run the action again.
    final link = ref.keepAlive();
    state = ItemActionState(busyItemId: itemId);
    try {
      await action();
      return true;
    } finally {
      if (ref.mounted) {
        state = const ItemActionState();
      }
      link.close();
    }
  }
}
