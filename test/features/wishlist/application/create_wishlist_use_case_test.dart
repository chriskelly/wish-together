import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/create_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock implements DocumentReference {}

void main() {
  group('CreateWishlistUseCase', () {
    late MockAuthService mockAuthService;
    late MockWishlistRepository mockWishlistRepository;
    late CreateWishlistUseCase createWishlistUseCase;

    setUpAll(() {
      registerFallbackValue(Wishlist(name: 'test', ownerId: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockAuthService = MockAuthService();
      mockWishlistRepository = MockWishlistRepository();
      getIt.registerSingleton<AuthService>(mockAuthService);
      getIt.registerSingleton<AuthSession>(mockAuthService);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      createWishlistUseCase = CreateWishlistUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should create wishlist with current user as owner', () async {
      // Arrange
      const userId = 'user123';
      const wishlistName = 'My Wishlist';
      final mockDocRef = MockDocumentReference();

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockWishlistRepository.add(any()))
          .thenAnswer((_) async => mockDocRef);

      // Act
      await createWishlistUseCase.execute(wishlistName);

      // Assert
      final captured = verify(() => mockWishlistRepository.add(captureAny()))
          .captured;
      expect(captured.length, 1);
      final wishlist = captured[0] as Wishlist;
      expect(wishlist.name, wishlistName);
      expect(wishlist.ownerId, userId);
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      when(() => mockAuthService.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => createWishlistUseCase.execute('My Wishlist'),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockWishlistRepository.add(any()));
    });

    test('should propagate exceptions from WishlistRepository', () async {
      // Arrange
      const userId = 'user123';
      final exception = Exception('Failed to create wishlist');
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockWishlistRepository.add(any())).thenThrow(exception);

      // Act & Assert
      expect(
        () => createWishlistUseCase.execute('My Wishlist'),
        throwsException,
      );
    });
  });
}
