import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class ClaimItemUseCase {
  Future<void> execute(String wishlistId, Item item) async {
    final authService = getIt<AuthService>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    final itemRepository = wishlistRepository.items(wishlistId);
    final updatedItem = item.copyWith(
      claimedBy: userId,
      claimedAt: DateTime.now(),
    );
    await itemRepository.update(item.id!, updatedItem);
  }
}
