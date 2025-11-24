import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class CreateItemUseCase {
  Future<void> execute(
    String wishlistId,
    String name, {
    String? description,
    String? url,
  }) async {
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);

    final newItem = Item(name: name, description: description, url: url);
    await itemRepository.add(newItem);
  }
}
