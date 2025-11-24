import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class SaveUserProfileUseCase {
  Future<void> execute(String displayName) async {
    final authService = getIt<AuthService>();
    final userRepository = getIt<UserRepository>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    // Get current user to check if they're new
    final currentUser = await userRepository.get(userId);
    final isNewUser =
        currentUser.displayName == null || currentUser.displayName!.isEmpty;

    // Update display name
    await userRepository.updateData(userId, {'displayName': displayName});

    // Create default wishlist for new users
    if (isNewUser) {
      await wishlistRepository.add(
        Wishlist(name: "$displayName's Wishlist", ownerId: userId),
      );
    }
  }
}
