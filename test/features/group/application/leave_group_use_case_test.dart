import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/application/leave_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('LeaveGroupUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockGroupRepository mockGroupRepository;
    late LeaveGroupUseCase leaveGroupUseCase;

    setUp(() {
      getIt.reset();
      mockAuthSession = MockAuthSession();
      mockGroupRepository = MockGroupRepository();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<GroupRepository>(mockGroupRepository);
      leaveGroupUseCase = LeaveGroupUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should leave group with current user', () async {
      // Arrange
      const groupId = 'group123';
      const userId = 'user123';

      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.leaveGroup(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await leaveGroupUseCase.execute(groupId);

      // Assert
      verify(() => mockGroupRepository.leaveGroup(groupId, userId)).called(1);
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => leaveGroupUseCase.execute('group123'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockGroupRepository.leaveGroup(any(), any()));
    });

    test('should propagate exceptions from GroupRepository', () async {
      // Arrange
      const groupId = 'group123';
      const userId = 'user123';
      final exception = Exception('Failed to leave group');
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.leaveGroup(any(), any()))
          .thenThrow(exception);

      // Act & Assert
      expect(() => leaveGroupUseCase.execute(groupId), throwsException);
    });
  });
}
