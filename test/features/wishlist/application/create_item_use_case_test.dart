import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock implements DocumentReference {}

void main() {
  group('CreateItemUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late CreateItemUseCase createItemUseCase;

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      createItemUseCase = CreateItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should create item in wishlist', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemName = 'New Item';
      const itemDescription = 'Item description';
      const itemUrl = 'https://example.com';
      final mockDocRef = MockDocumentReference();

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.add(any()))
          .thenAnswer((_) async => mockDocRef);

      // Act
      await createItemUseCase.execute(
        wishlistId,
        itemName,
        description: itemDescription,
        url: itemUrl,
      );

      // Assert
      final captured = verify(() => mockItemRepository.add(captureAny()))
          .captured;
      expect(captured.length, 1);
      final item = captured[0] as Item;
      expect(item.name, itemName);
      expect(item.description, itemDescription);
      expect(item.url, itemUrl);
    });

    test('should create item with only name', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemName = 'New Item';
      final mockDocRef = MockDocumentReference();

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.add(any()))
          .thenAnswer((_) async => mockDocRef);

      // Act
      await createItemUseCase.execute(wishlistId, itemName);

      // Assert
      final captured = verify(() => mockItemRepository.add(captureAny()))
          .captured;
      expect(captured.length, 1);
      final item = captured[0] as Item;
      expect(item.name, itemName);
      expect(item.description, isNull);
      expect(item.url, isNull);
    });

    test('should propagate exceptions from ItemRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      final exception = Exception('Failed to create item');
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.add(any())).thenThrow(exception);

      // Act & Assert
      expect(
        () => createItemUseCase.execute(wishlistId, 'New Item'),
        throwsException,
      );
    });
  });
}
