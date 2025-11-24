import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/group/application/update_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('UpdateGroupUseCase', () {
    late MockGroupRepository mockGroupRepository;
    late UpdateGroupUseCase updateGroupUseCase;

    setUpAll(() {
      registerFallbackValue(Group(name: 'test', ownerId: 'test', members: []));
    });

    setUp(() {
      getIt.reset();
      mockGroupRepository = MockGroupRepository();
      getIt.registerSingleton<GroupRepository>(mockGroupRepository);
      updateGroupUseCase = UpdateGroupUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should update group name', () async {
      // Arrange
      const groupId = 'group123';
      const newName = 'Updated Group Name';
      final existingGroup = Group(
        id: groupId,
        name: 'Old Name',
        ownerId: 'owner123',
        members: ['owner123'],
      );

      when(() => mockGroupRepository.update(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await updateGroupUseCase.execute(existingGroup, newName);

      // Assert
      verify(() => mockGroupRepository.update(
        groupId,
        any(that: predicate<Group>(
          (group) => group.name == newName && group.id == groupId,
        )),
      )).called(1);
    });

    test('should propagate exceptions from GroupRepository', () async {
      // Arrange
      final group = Group(
        id: 'group123',
        name: 'Old Name',
        ownerId: 'owner123',
        members: ['owner123'],
      );
      final exception = Exception('Failed to update group');
      when(() => mockGroupRepository.update(any(), any())).thenThrow(exception);

      // Act & Assert
      expect(
        () => updateGroupUseCase.execute(group, 'New Name'),
        throwsException,
      );
    });
  });
}

