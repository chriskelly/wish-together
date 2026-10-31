import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  group('LoadUserProfileUseCase', () {
    late MockAuthService mockAuthService;
    late MockUserRepository mockUserRepository;
    late LoadUserProfileUseCase loadUserProfileUseCase;

    setUp(() {
      getIt.reset();
      mockAuthService = MockAuthService();
      mockUserRepository = MockUserRepository();
      getIt.registerSingleton<AuthSession>(mockAuthService);
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      loadUserProfileUseCase = LoadUserProfileUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should return user when user is authenticated', () async {
      // Arrange
      const userId = 'user123';
      final user = User(
        id: userId,
        displayName: 'Test User',
        email: 'test@example.com',
      );

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockUserRepository.get(userId)).thenAnswer((_) async => user);

      // Act
      final result = await loadUserProfileUseCase.execute();

      // Assert
      expect(result, isNotNull);
      expect(result?.id, userId);
      expect(result?.displayName, 'Test User');
      verify(() => mockUserRepository.get(userId)).called(1);
    });

    test('should return null when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthService.currentUserId).thenReturn(null);

      // Act
      final result = await loadUserProfileUseCase.execute();

      // Assert
      expect(result, isNull);
      verifyNever(() => mockUserRepository.get(any()));
    });

    test('should propagate exceptions from UserRepository', () async {
      // Arrange
      const userId = 'user123';
      final exception = Exception('Failed to load user');
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockUserRepository.get(userId)).thenThrow(exception);

      // Act & Assert
      expect(() => loadUserProfileUseCase.execute(), throwsException);
    });
  });
}
