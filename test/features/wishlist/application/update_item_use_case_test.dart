import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  group('UpdateItemUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UpdateItemUseCase updateItemUseCase;

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      updateItemUseCase = UpdateItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should update item', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';
      const newName = 'Updated Item Name';
      const newDescription = 'Updated description';
      const newUrl = 'https://updated.com';
      final existingItem = Item(
        id: itemId,
        name: 'Old Name',
        description: 'Old description',
        url: 'https://old.com',
      );

      when(
        () => mockWishlistRepository.items(wishlistId),
      ).thenReturn(mockItemRepository);
      when(
        () => mockItemRepository.update(any(), any()),
      ).thenAnswer((_) async => {});

      // Act
      await updateItemUseCase.execute(
        wishlistId,
        existingItem,
        name: newName,
        description: newDescription,
        url: newUrl,
      );

      // Assert
      verify(
        () => mockItemRepository.update(
          itemId,
          any(
            that: predicate<Item>(
              (item) =>
                  item.name == newName &&
                  item.description == newDescription &&
                  item.url == newUrl &&
                  item.id == itemId,
            ),
          ),
        ),
      ).called(1);
    });

    test('should propagate exceptions from ItemRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      final item = Item(id: 'item123', name: 'Old Name');
      final exception = Exception('Failed to update item');
      when(
        () => mockWishlistRepository.items(wishlistId),
      ).thenReturn(mockItemRepository);
      when(() => mockItemRepository.update(any(), any())).thenThrow(exception);

      // Act & Assert
      expect(
        () => updateItemUseCase.execute(wishlistId, item, name: 'New Name'),
        throwsException,
      );
    });
  });
}
