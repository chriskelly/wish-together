import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/application/create_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockGroupRepository extends Mock implements GroupRepository {}

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock implements DocumentReference {}

void main() {
  group('CreateGroupUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockGroupRepository mockGroupRepository;
    late CreateGroupUseCase createGroupUseCase;

    setUpAll(() {
      registerFallbackValue(Group(name: 'test', ownerId: 'test', members: []));
    });

    setUp(() {
      getIt.reset();
      mockAuthSession = MockAuthSession();
      mockGroupRepository = MockGroupRepository();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<GroupRepository>(mockGroupRepository);
      createGroupUseCase = CreateGroupUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should create group with current user as owner and member', () async {
      // Arrange
      const userId = 'user123';
      const groupName = 'My Group';
      final mockDocRef = MockDocumentReference();

      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.add(any()))
          .thenAnswer((_) async => mockDocRef);

      // Act
      await createGroupUseCase.execute(groupName);

      // Assert
      final captured = verify(() => mockGroupRepository.add(captureAny()))
          .captured;
      expect(captured.length, 1);
      final group = captured[0] as Group;
      expect(group.name, groupName);
      expect(group.ownerId, userId);
      expect(group.members, contains(userId));
      expect(group.members.length, 1);
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => createGroupUseCase.execute('My Group'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockGroupRepository.add(any()));
    });

    test('should propagate exceptions from GroupRepository', () async {
      // Arrange
      const userId = 'user123';
      final exception = Exception('Failed to create group');
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockGroupRepository.add(any())).thenThrow(exception);

      // Act & Assert
      expect(() => createGroupUseCase.execute('My Group'), throwsException);
    });
  });
}
