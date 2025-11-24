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
  }) async {
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);

    final updatedItem = item.copyWith(
      name: name,
      description: description,
      url: url,
    );
    await itemRepository.update(item.id!, updatedItem);
  }
}
