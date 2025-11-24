import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class CreateWishlistUseCase {
  Future<void> execute(String name) async {
    final authService = getIt<AuthService>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    await wishlistRepository.add(Wishlist(name: name, ownerId: userId));
  }
}
