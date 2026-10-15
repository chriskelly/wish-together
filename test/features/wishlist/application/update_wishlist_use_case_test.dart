import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/update_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

void main() {
  group('UpdateWishlistUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late UpdateWishlistUseCase updateWishlistUseCase;

    setUpAll(() {
      registerFallbackValue(Wishlist(name: 'test', ownerId: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      updateWishlistUseCase = UpdateWishlistUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should update wishlist name', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const newName = 'Updated Wishlist Name';
      final existingWishlist = Wishlist(
        id: wishlistId,
        name: 'Old Name',
        ownerId: 'owner123',
      );

      when(() => mockWishlistRepository.update(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await updateWishlistUseCase.execute(existingWishlist, newName);

      // Assert
      verify(
        () => mockWishlistRepository.update(
          wishlistId,
          any(
            that: predicate<Wishlist>(
              (wishlist) =>
                  wishlist.name == newName && wishlist.id == wishlistId,
            ),
          ),
        ),
      ).called(1);
    });

    test('should propagate exceptions from WishlistRepository', () async {
      // Arrange
      final wishlist = Wishlist(
        id: 'wishlist123',
        name: 'Old Name',
        ownerId: 'owner123',
      );
      final exception = Exception('Failed to update wishlist');
      when(() => mockWishlistRepository.update(any(), any()))
          .thenThrow(exception);

      // Act & Assert
      expect(
        () => updateWishlistUseCase.execute(wishlist, 'New Name'),
        throwsException,
      );
    });
  });
}
