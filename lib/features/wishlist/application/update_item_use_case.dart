import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class UpdateItemUseCase {
  /// Writes the owner-editable content of [item].
  ///
  /// [description] and [url] are required so every caller states its intent:
  /// null removes the value, because the item form sends null for a box the
  /// owner cleared. [name] and [claimLimit] fall back to the stored item when
  /// omitted.
  Future<void> execute(
    String wishlistId,
    Item item, {
    String? name,
    required String? description,
    required String? url,
    int? claimLimit,
  }) async {
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);

    // Field-scoped: an owner's edit must never rewrite the claims map.
    await itemRepository.updateContent(
      item.id!,
      name: name ?? item.name,
      description: description,
      url: url,
      claimLimit: claimLimit ?? item.claimLimit,
    );
  }
}
