import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  group('UnclaimItemUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UnclaimItemUseCase unclaimItemUseCase;

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      unclaimItemUseCase = UnclaimItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should unclaim item', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.unclaim(itemId))
          .thenAnswer((_) async => {});

      // Act
      await unclaimItemUseCase.execute(wishlistId, itemId);

      // Assert
      verify(() => mockItemRepository.unclaim(itemId)).called(1);
    });

    test('should propagate exceptions from ItemRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';
      final exception = Exception('Failed to unclaim item');

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.unclaim(itemId)).thenThrow(exception);

      // Act & Assert
      expect(
        () => unclaimItemUseCase.execute(wishlistId, itemId),
        throwsException,
      );
    });
  });
}
