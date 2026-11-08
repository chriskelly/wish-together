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

    const wishlistId = 'wishlist123';
    const itemId = 'item123';

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      updateItemUseCase = UpdateItemUseCase();
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(
        () => mockItemRepository.updateContent(
          any(),
          name: any(named: 'name'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          claimLimit: any(named: 'claimLimit'),
        ),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      getIt.reset();
    });

    test('writes the edited content field-scoped', () async {
      // Arrange
      final existingItem = Item(
        id: itemId,
        name: 'Old Name',
        description: 'Old description',
        url: 'https://old.com',
        claimLimit: 1,
      );

      // Act
      await updateItemUseCase.execute(
        wishlistId,
        existingItem,
        name: 'Updated Item Name',
        description: 'Updated description',
        url: 'https://updated.com',
      );

      // Assert
      verify(
        () => mockItemRepository.updateContent(
          itemId,
          name: 'Updated Item Name',
          description: 'Updated description',
          url: 'https://updated.com',
          claimLimit: 1,
        ),
      ).called(1);
      verifyNever(() => mockItemRepository.update(any(), any()));
    });

    test('keeps the existing limit when none is given', () async {
      // Arrange: an unlimited item must not be silently downgraded to 1.
      final unlimitedItem = Item(id: itemId, name: 'Old Name', claimLimit: 0);

      // Act
      await updateItemUseCase.execute(wishlistId, unlimitedItem, name: 'New');

      // Assert
      verify(
        () => mockItemRepository.updateContent(
          itemId,
          name: 'New',
          description: null,
          url: null,
          claimLimit: 0,
        ),
      ).called(1);
    });

    test('passes an explicit claim limit', () async {
      // Arrange
      final item = Item(id: itemId, name: 'Old Name', claimLimit: 1);

      // Act
      await updateItemUseCase.execute(wishlistId, item, claimLimit: 5);

      // Assert
      verify(
        () => mockItemRepository.updateContent(
          itemId,
          name: 'Old Name',
          description: null,
          url: null,
          claimLimit: 5,
        ),
      ).called(1);
    });

    test('keeps the existing description and url when they are omitted', () async {
      // Arrange
      final item = Item(
        id: itemId,
        name: 'Old Name',
        description: 'Old description',
        url: 'https://old.com',
      );

      // Act
      await updateItemUseCase.execute(wishlistId, item, name: 'New Name');

      // Assert
      verify(
        () => mockItemRepository.updateContent(
          itemId,
          name: 'New Name',
          description: 'Old description',
          url: 'https://old.com',
          claimLimit: 1,
        ),
      ).called(1);
    });

    test('propagates exceptions from ItemRepository', () async {
      // Arrange
      final item = Item(id: itemId, name: 'Old Name');
      final exception = Exception('Failed to update item');
      when(
        () => mockItemRepository.updateContent(
          any(),
          name: any(named: 'name'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          claimLimit: any(named: 'claimLimit'),
        ),
      ).thenThrow(exception);

      // Act & Assert
      expect(
        () => updateItemUseCase.execute(wishlistId, item, name: 'New Name'),
        throwsA(same(exception)),
      );
    });
  });
}
