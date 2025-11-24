import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock implements DocumentReference {}

void main() {
  group('SaveUserProfileUseCase', () {
    late MockAuthService mockAuthService;
    late MockUserRepository mockUserRepository;
    late MockWishlistRepository mockWishlistRepository;
    late SaveUserProfileUseCase saveUserProfileUseCase;

    setUpAll(() {
      registerFallbackValue(Wishlist(name: 'test', ownerId: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockAuthService = MockAuthService();
      mockUserRepository = MockUserRepository();
      mockWishlistRepository = MockWishlistRepository();
      getIt.registerSingleton<AuthService>(mockAuthService);
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      saveUserProfileUseCase = SaveUserProfileUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should update user display name', () async {
      // Arrange
      const userId = 'user123';
      const displayName = 'John Doe';
      final existingUser = User(id: userId, displayName: 'Old Name');

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(
        () => mockUserRepository.get(userId),
      ).thenAnswer((_) async => existingUser);
      when(
        () => mockUserRepository.updateData(any(), any()),
      ).thenAnswer((_) async => {});

      // Act
      await saveUserProfileUseCase.execute(displayName);

      // Assert
      verify(
        () =>
            mockUserRepository.updateData(userId, {'displayName': displayName}),
      ).called(1);
    });

    test('should create default wishlist for new user', () async {
      // Arrange
      const userId = 'user123';
      const displayName = 'John Doe';
      final existingUser = User(id: userId, displayName: null);
      final mockDocRef = MockDocumentReference();

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(
        () => mockUserRepository.get(userId),
      ).thenAnswer((_) async => existingUser);
      when(
        () => mockUserRepository.updateData(any(), any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockWishlistRepository.add(any()),
      ).thenAnswer((_) async => mockDocRef);

      // Act
      await saveUserProfileUseCase.execute(displayName);

      // Assert
      final captured = verify(
        () => mockWishlistRepository.add(captureAny()),
      ).captured;
      expect(captured.length, 1);
      final wishlist = captured[0] as Wishlist;
      expect(wishlist.name, "$displayName's Wishlist");
      expect(wishlist.ownerId, userId);
    });

    test('should not create default wishlist for existing user', () async {
      // Arrange
      const userId = 'user123';
      const displayName = 'John Doe';
      final existingUser = User(id: userId, displayName: 'Old Name');

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(
        () => mockUserRepository.get(userId),
      ).thenAnswer((_) async => existingUser);
      when(
        () => mockUserRepository.updateData(any(), any()),
      ).thenAnswer((_) async => {});

      // Act
      await saveUserProfileUseCase.execute(displayName);

      // Assert
      verify(
        () =>
            mockUserRepository.updateData(userId, {'displayName': displayName}),
      ).called(1);
      verifyNever(() => mockWishlistRepository.add(any()));
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthService.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => saveUserProfileUseCase.execute('John Doe'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockUserRepository.updateData(any(), any()));
    });

    test('should propagate exceptions from UserRepository', () async {
      // Arrange
      const userId = 'user123';
      final exception = Exception('Failed to update user');
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(
        () => mockUserRepository.get(userId),
      ).thenAnswer((_) async => User(id: userId));
      when(
        () => mockUserRepository.updateData(any(), any()),
      ).thenThrow(exception);

      // Act & Assert
      expect(() => saveUserProfileUseCase.execute('John Doe'), throwsException);
    });
  });
}
