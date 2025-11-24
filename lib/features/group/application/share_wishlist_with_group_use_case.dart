import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class ShareWishlistWithGroupUseCase {
  Future<void> execute(String wishlistId, String groupId) async {
    final wishlistRepository = getIt<WishlistRepository>();

    final wishlist = await wishlistRepository.get(wishlistId);
    final updatedSharedGroups = List<String>.from(wishlist.sharedWithGroups);
    if (!updatedSharedGroups.contains(groupId)) {
      updatedSharedGroups.add(groupId);
    }
    final updatedWishlist = wishlist.copyWith(
      sharedWithGroups: updatedSharedGroups,
    );
    await wishlistRepository.update(wishlistId, updatedWishlist);
  }
}
