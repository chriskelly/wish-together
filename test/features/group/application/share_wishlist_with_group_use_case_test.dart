import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/group/application/share_wishlist_with_group_use_case.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

void main() {
  group('ShareWishlistWithGroupUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late ShareWishlistWithGroupUseCase shareWishlistWithGroupUseCase;

    setUpAll(() {
      registerFallbackValue(Wishlist(name: 'test', ownerId: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      shareWishlistWithGroupUseCase = ShareWishlistWithGroupUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should add group to wishlist sharedWithGroups', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const groupId = 'group123';
      final wishlist = Wishlist(
        id: wishlistId,
        name: 'My Wishlist',
        ownerId: 'owner123',
        sharedWithGroups: [],
      );

      when(() => mockWishlistRepository.get(wishlistId))
          .thenAnswer((_) async => wishlist);
      when(() => mockWishlistRepository.update(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await shareWishlistWithGroupUseCase.execute(wishlistId, groupId);

      // Assert
      verify(() => mockWishlistRepository.get(wishlistId)).called(1);
      final captured = verify(() => mockWishlistRepository.update(
        wishlistId,
        captureAny(),
      )).captured;
      expect(captured.length, 1);
      final updatedWishlist = captured[0] as Wishlist;
      expect(updatedWishlist.sharedWithGroups, contains(groupId));
    });

    test('should not duplicate group if already shared', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const groupId = 'group123';
      final wishlist = Wishlist(
        id: wishlistId,
        name: 'My Wishlist',
        ownerId: 'owner123',
        sharedWithGroups: [groupId],
      );

      when(() => mockWishlistRepository.get(wishlistId))
          .thenAnswer((_) async => wishlist);
      when(() => mockWishlistRepository.update(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await shareWishlistWithGroupUseCase.execute(wishlistId, groupId);

      // Assert
      final captured = verify(() => mockWishlistRepository.update(
        wishlistId,
        captureAny(),
      )).captured;
      expect(captured.length, 1);
      final updatedWishlist = captured[0] as Wishlist;
      // Should still only have one instance
      expect(updatedWishlist.sharedWithGroups.where((id) => id == groupId).length, 1);
    });

    test('should propagate exceptions from WishlistRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const groupId = 'group123';
      final exception = Exception('Failed to share wishlist');
      when(() => mockWishlistRepository.get(wishlistId)).thenThrow(exception);

      // Act & Assert
      expect(
        () => shareWishlistWithGroupUseCase.execute(wishlistId, groupId),
        throwsException,
      );
    });
  });
}

