import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class SaveUserProfileUseCase {
  Future<void> execute(String displayName) async {
    final session = getIt<AuthSession>();
    final userRepository = getIt<UserRepository>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    // A name is its trimmed value. A blank one is not a name, and storing it
    // would leave the router treating this user as not onboarded.
    final name = displayName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(displayName, 'displayName', 'is blank');
    }

    // Get current user to check if they're new
    final currentUser = await userRepository.get(userId);
    final isNewUser = !currentUser.hasDisplayName;

    // Update display name
    await userRepository.updateData(userId, {'displayName': name});

    // Create default wishlist for new users
    if (isNewUser) {
      await wishlistRepository.add(
        Wishlist(name: "$name's Wishlist", ownerId: userId),
      );
    }
  }
}
