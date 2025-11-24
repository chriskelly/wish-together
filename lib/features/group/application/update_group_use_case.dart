import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class UpdateGroupUseCase {
  Future<void> execute(Group group, String newName) async {
    final groupRepository = getIt<GroupRepository>();

    final updatedGroup = group.copyWith(name: newName);
    await groupRepository.update(group.id!, updatedGroup);
  }
}
