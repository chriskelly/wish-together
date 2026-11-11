import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// The wishlist and its items are reads: each stream is created once while the
/// page is mounted and disposed when it leaves, so a widget rebuild cannot
/// re-subscribe or refetch.
final wishlistProvider = StreamProvider.family<Wishlist, String>(
  (ref, wishlistId) =>
      ref.watch(wishlistRepositoryProvider).streamOne(wishlistId),
  isAutoDispose: true,
);

final wishlistItemsProvider = StreamProvider.family<List<Item>, String>(
  (ref, wishlistId) =>
      ref.watch(itemRepositoryProvider(wishlistId)).streamAll(),
  isAutoDispose: true,
);

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

/// Only [busyItemId] is read today; a later in-flight field should give this
/// class `==` so a watcher is not rebuilt for an equal state.
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
