import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

class LoadUserProfileUseCase {
  Future<User?> execute() async {
    final session = getIt<AuthSession>();
    final userRepository = getIt<UserRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
      return null;
    }
    return await userRepository.get(userId);
  }
}
