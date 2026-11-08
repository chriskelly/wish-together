import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class UpdateItemUseCase {
  Future<void> execute(
    String wishlistId,
    Item item, {
    String? name,
    String? description,
    String? url,
    int? claimLimit,
  }) async {
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);

    final updatedItem = item.copyWith(
      name: name,
      description: description,
      url: url,
      claimLimit: claimLimit,
    );
    // Field-scoped: an owner's edit must never rewrite the claims map.
    await itemRepository.updateContent(
      item.id!,
      name: updatedItem.name,
      description: updatedItem.description,
      url: updatedItem.url,
      claimLimit: updatedItem.claimLimit,
    );
  }
}
