import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/delete_account_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockGroupRepository extends Mock implements GroupRepository {}

void main() {
  group('DeleteAccountUseCase', () {
    const userId = 'user-deleting';

    late MockAuthService authService;
    late MockUserRepository userRepository;
    late MockWishlistRepository wishlistRepository;
    late MockGroupRepository groupRepository;
    late DeleteAccountUseCase useCase;

    setUpAll(() {
      registerFallbackValue(<String>[]);
    });

    setUp(() {
      getIt.reset();
      authService = MockAuthService();
      userRepository = MockUserRepository();
      wishlistRepository = MockWishlistRepository();
      groupRepository = MockGroupRepository();
      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<AuthSession>(authService);
      getIt.registerSingleton<UserRepository>(userRepository);
      getIt.registerSingleton<WishlistRepository>(wishlistRepository);
      getIt.registerSingleton<GroupRepository>(groupRepository);
      useCase = DeleteAccountUseCase();

      when(() => authService.currentUserId).thenReturn(userId);
      // Default: the user owns nothing and belongs to nothing.
      when(() => wishlistRepository.listOwnedBy(userId))
          .thenAnswer((_) async => []);
      when(() => groupRepository.listOwnedBy(userId))
          .thenAnswer((_) async => []);
      when(() => groupRepository.listForMember(userId))
          .thenAnswer((_) async => []);
      when(() => userRepository.delete(userId)).thenAnswer((_) async {});
      when(() => authService.deleteAccount()).thenAnswer((_) async {});
    });

    tearDown(() {
      getIt.reset();
    });

    test('deletes every owned wishlist together with its items', () async {
      // ARRANGE: the user owns two wishlists.
      when(() => wishlistRepository.listOwnedBy(userId)).thenAnswer(
        (_) async => [
          Wishlist(id: 'w1', name: 'One', ownerId: userId),
          Wishlist(id: 'w2', name: 'Two', ownerId: userId),
        ],
      );
      when(() => wishlistRepository.deleteWithItems('w1'))
          .thenAnswer((_) async {});
      when(() => wishlistRepository.deleteWithItems('w2'))
          .thenAnswer((_) async {});

      // ACT
      await useCase.execute();

      // ASSERT
      verify(() => wishlistRepository.deleteWithItems('w1')).called(1);
      verify(() => wishlistRepository.deleteWithItems('w2')).called(1);
    });

    test(
      'hands an owned group with other members to the first remaining member',
      () async {
        // ARRANGE: the user owns a group with two other members.
        when(() => groupRepository.listOwnedBy(userId)).thenAnswer(
          (_) async => [
            Group(
              id: 'family',
              name: 'Family',
              ownerId: userId,
              members: [userId, 'aunt', 'uncle'],
            ),
          ],
        );
        when(() => groupRepository.transferOwnership(any(), any(), any()))
            .thenAnswer((_) async {});

        // ACT
        await useCase.execute();

        // ASSERT
        final captured = verify(
          () => groupRepository.transferOwnership(
            'family',
            captureAny(),
            captureAny(),
          ),
        ).captured;
        expect(captured[0], 'aunt');
        expect(captured[1], ['aunt', 'uncle']);
        verifyNever(() => groupRepository.delete('family'));
      },
    );

    test('deletes an owned group when the user is its only member', () async {
      // ARRANGE: the user is the only member of the group.
      when(() => groupRepository.listOwnedBy(userId)).thenAnswer(
        (_) async => [
          Group(id: 'solo', name: 'Solo', ownerId: userId, members: [userId]),
        ],
      );
      when(() => groupRepository.delete('solo')).thenAnswer((_) async {});

      // ACT
      await useCase.execute();

      // ASSERT
      verify(() => groupRepository.delete('solo')).called(1);
      verifyNever(() => groupRepository.transferOwnership(any(), any(), any()));
    });

    test('removes the user from groups they do not own', () async {
      // ARRANGE: the user is a member of somebody else's group.
      when(() => groupRepository.listForMember(userId)).thenAnswer(
        (_) async => [
          Group(
            id: 'friends',
            name: 'Friends',
            ownerId: 'friend',
            members: ['friend', userId],
          ),
        ],
      );
      when(() => groupRepository.leaveGroup(any(), any()))
          .thenAnswer((_) async {});

      // ACT
      await useCase.execute();

      // ASSERT
      verify(() => groupRepository.leaveGroup('friends', userId)).called(1);
    });

    test('does not leave a group the user owns', () async {
      // ARRANGE: a group the user owns and is a member of.
      final ownedGroup = Group(
        id: 'mine',
        name: 'Mine',
        ownerId: userId,
        members: [userId, 'friend'],
      );
      when(() => groupRepository.listOwnedBy(userId))
          .thenAnswer((_) async => [ownedGroup]);
      when(() => groupRepository.listForMember(userId))
          .thenAnswer((_) async => [ownedGroup]);
      when(() => groupRepository.transferOwnership(any(), any(), any()))
          .thenAnswer((_) async {});

      // ACT
      await useCase.execute();

      // ASSERT
      verifyNever(() => groupRepository.leaveGroup(any(), any()));
    });

    test('deletes the user profile document', () async {
      // ACT
      await useCase.execute();

      // ASSERT
      verify(() => userRepository.delete(userId)).called(1);
    });

    test('deletes the auth account only after the data cascade', () async {
      // ARRANGE: the user owns one wishlist.
      when(() => wishlistRepository.listOwnedBy(userId)).thenAnswer(
        (_) async => [Wishlist(id: 'w1', name: 'One', ownerId: userId)],
      );
      when(() => wishlistRepository.deleteWithItems('w1'))
          .thenAnswer((_) async {});

      // ACT
      await useCase.execute();

      // ASSERT
      verifyInOrder([
        () => wishlistRepository.deleteWithItems('w1'),
        () => userRepository.delete(userId),
        () => authService.deleteAccount(),
      ]);
    });

    test('throws and touches nothing when no user is signed in', () async {
      // ARRANGE
      when(() => authService.currentUserId).thenReturn(null);

      // ACT & ASSERT
      await expectLater(useCase.execute(), throwsA(isA<Exception>()));
      verifyNever(() => wishlistRepository.listOwnedBy(any()));
      verifyNever(() => groupRepository.listForMember(any()));
      verifyNever(() => userRepository.delete(any()));
      verifyNever(() => authService.deleteAccount());
    });

    test('does not delete the auth account when the cascade fails', () async {
      // ARRANGE: deleting the user's wishlist fails.
      when(() => wishlistRepository.listOwnedBy(userId)).thenAnswer(
        (_) async => [Wishlist(id: 'w1', name: 'One', ownerId: userId)],
      );
      when(() => wishlistRepository.deleteWithItems('w1'))
          .thenThrow(Exception('firestore unavailable'));

      // ACT & ASSERT
      await expectLater(useCase.execute(), throwsA(isA<Exception>()));
      verifyNever(() => authService.deleteAccount());
      verifyNever(() => userRepository.delete(any()));
    });
  });
}
