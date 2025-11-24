import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class UnclaimItemUseCase {
  Future<void> execute(String wishlistId, String itemId) async {
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);
    await itemRepository.unclaim(itemId);
  }
}
