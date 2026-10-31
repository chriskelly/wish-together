import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class CreateGroupUseCase {
  Future<void> execute(String name) async {
    final session = getIt<AuthSession>();
    final groupRepository = getIt<GroupRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
      throw Exception('User is not authenticated');
    }

    await groupRepository.add(
      Group(name: name, ownerId: userId, members: [userId]),
    );
  }
}
