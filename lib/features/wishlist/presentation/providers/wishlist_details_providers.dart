import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';
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

/// The clock the details page uses to classify old claims. Tests override it
/// with a fixed time so their claim fixtures never drift into stale.
final wishlistNowProvider = Provider<DateTime>(
  (_) => DateTime.now(),
  isAutoDispose: true,
);

/// The old claims on [wishlistId], derived from the item stream the page
/// already watches. Empty while the items are loading or failed, so the banner
/// never sits above an error.
final staleClaimsPlanProvider = Provider.family<StaleClaimsPlan, String>((
  ref,
  wishlistId,
) {
  final itemsAsync = ref.watch(wishlistItemsProvider(wishlistId));
  final items = itemsAsync.hasError ? null : itemsAsync.value;
  if (items == null) return StaleClaimsPlan.empty;
  return StaleClaimsPlan.fromItems(items, now: ref.watch(wishlistNowProvider));
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

/// The command state: the item action that is running, the bulk clear, or
/// neither.
///
/// It has no `==` because the only watcher selects a record of booleans; the
/// notifier reads the state to serialise actions.
class ItemActionState {
  const ItemActionState({this.busyItemId, this.isBulk = false});

  /// The item whose action is running, or null when no item action is running.
  final String? busyItemId;

  /// True while the wishlist-wide stale-claim clear is running.
  final bool isBulk;

  bool get isBusy => busyItemId != null || isBulk;
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
    ItemActionState(busyItemId: itemId),
    () => ref.read(claimItemUseCaseProvider).execute(wishlistId, itemId),
  );

  Future<bool> unclaim(String itemId) => _run(
    ItemActionState(busyItemId: itemId),
    () => ref.read(unclaimItemUseCaseProvider).execute(wishlistId, itemId),
  );

  Future<bool> delete(String itemId) => _run(
    ItemActionState(busyItemId: itemId),
    () => ref.read(itemRepositoryProvider(wishlistId)).delete(itemId),
  );

  Future<bool> clearStaleClaims(StaleClaimsPlan plan) => _run(
    const ItemActionState(isBulk: true),
    () => ref.read(clearStaleClaimsUseCaseProvider).execute(wishlistId, plan),
  );

  Future<bool> _run(
    ItemActionState running,
    Future<void> Function() action,
  ) async {
    if (state.isBusy) {
      return false;
    }

    // A plain read opens and closes a temporary listener. Without this link an
    // auto-disposed notifier would be gone by the next frame, and a second tap
    // would see a fresh, idle notifier and run the action again.
    final link = ref.keepAlive();
    state = running;
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
