import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class UpdateWishlistUseCase {
  Future<void> execute(Wishlist wishlist, String newName) async {
    final wishlistRepository = getIt<WishlistRepository>();

    final updatedWishlist = wishlist.copyWith(name: newName);
    await wishlistRepository.update(wishlist.id!, updatedWishlist);
  }
}
