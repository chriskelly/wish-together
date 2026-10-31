import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/application/join_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';

class MockAuthService extends Mock implements AuthService {}

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('JoinGroupUseCase', () {
    late MockAuthService mockAuthService;
    late MockGroupRepository mockGroupRepository;
    late JoinGroupUseCase joinGroupUseCase;

    setUp(() {
      getIt.reset();
      mockAuthService = MockAuthService();
      mockGroupRepository = MockGroupRepository();
      getIt.registerSingleton<AuthSession>(mockAuthService);
      getIt.registerSingleton<GroupRepository>(mockGroupRepository);
      joinGroupUseCase = JoinGroupUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should join group with current user', () async {
      // Arrange
      const groupId = 'group123';
      const userId = 'user123';

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.joinGroup(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await joinGroupUseCase.execute(groupId);

      // Assert
      verify(() => mockGroupRepository.joinGroup(groupId, userId)).called(1);
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthService.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => joinGroupUseCase.execute('group123'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockGroupRepository.joinGroup(any(), any()));
    });

    test('should propagate exceptions from GroupRepository', () async {
      // Arrange
      const groupId = 'group123';
      const userId = 'user123';
      final exception = Exception('Failed to join group');
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.joinGroup(any(), any()))
          .thenThrow(exception);

      // Act & Assert
      expect(() => joinGroupUseCase.execute(groupId), throwsException);
    });
  });
}
