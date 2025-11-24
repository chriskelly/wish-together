import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';

class LeaveGroupUseCase {
  Future<void> execute(String groupId) async {
    final authService = getIt<AuthService>();
    final groupRepository = getIt<GroupRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    await groupRepository.leaveGroup(groupId, userId);
  }
}
