import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';

class JoinGroupUseCase {
  Future<void> execute(String groupId) async {
    final session = getIt<AuthSession>();
    final groupRepository = getIt<GroupRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    await groupRepository.joinGroup(groupId, userId);
  }
}
