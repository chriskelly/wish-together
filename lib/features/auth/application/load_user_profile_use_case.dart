import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

class LoadUserProfileUseCase {
  Future<User?> execute() async {
    final authService = getIt<AuthService>();
    final userRepository = getIt<UserRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      return null;
    }
    return await userRepository.get(userId);
  }
}
