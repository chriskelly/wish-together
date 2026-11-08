import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

import '../../../core/logging/recording_sink.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  const wishlistId = 'wishlist123';
  const itemId = 'item123';
  const userId = 'user123';

  group('UnclaimItemUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UnclaimItemUseCase unclaimItemUseCase;

    setUp(() {
      getIt.reset();
      mockAuthSession = MockAuthSession();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      unclaimItemUseCase = UnclaimItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('unclaims the item for the current user', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.unclaim(itemId, claimedBy: userId))
          .thenAnswer((_) async {});

      // Act
      await unclaimItemUseCase.execute(wishlistId, itemId);

      // Assert
      verify(() => mockItemRepository.unclaim(itemId, claimedBy: userId))
          .called(1);
    });

    test('throws a signed-out failure and writes nothing when nobody is signed in',
        () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      // Act & Assert
      await expectLater(
        unclaimItemUseCase.execute(wishlistId, itemId),
        throwsA(
          isA<ClaimFailure>()
              .having(
                (failure) => failure.reason,
                'reason',
                ClaimFailureReason.signedOut,
              )
              .having((failure) => failure.code, 'code', unauthenticatedCode),
        ),
      );
      verifyNever(
        () => mockItemRepository.unclaim(
          any(),
          claimedBy: any(named: 'claimedBy'),
        ),
      );
    });

    test('propagates exceptions from ItemRepository', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      final exception = Exception('Failed to unclaim item');
      when(() => mockItemRepository.unclaim(itemId, claimedBy: userId))
          .thenThrow(exception);

      // Act & Assert
      expect(
        () => unclaimItemUseCase.execute(wishlistId, itemId),
        throwsA(same(exception)),
      );
    });
  });

  group('UnclaimItemUseCase diagnostics', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UnclaimItemUseCase unclaimItemUseCase;
    late RecordingSink sink;

    setUp(() async {
      await getIt.reset();
      mockAuthSession = MockAuthSession();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      sink = RecordingSink();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      unclaimItemUseCase = UnclaimItemUseCase();
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
    });

    tearDown(getIt.reset);

    test('reports started then completed', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.unclaim(itemId, claimedBy: userId))
          .thenAnswer((_) async {});

      await unclaimItemUseCase.execute(wishlistId, itemId);

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test('reports denied when nobody is signed in', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      await expectLater(
        unclaimItemUseCase.execute(wishlistId, itemId),
        throwsA(isA<ClaimFailure>()),
      );

      final event = sink.eventsOf<ClaimActionEvent>().single;
      expect(event.phase, ClaimPhase.denied);
      expect(event.code, unauthenticatedCode);
      verifyNever(
        () => mockItemRepository.unclaim(
          any(),
          claimedBy: any(named: 'claimedBy'),
        ),
      );
    });

    test('reports denied with the error code and rethrows on a failed write',
        () async {
      const code = 'permission-denied';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.unclaim(itemId, claimedBy: userId))
          .thenThrow(const CodedError(code));

      await expectLater(
        unclaimItemUseCase.execute(wishlistId, itemId),
        throwsA(isA<CodedError>()),
      );

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.denied,
      ]);
      expect(sink.eventsOf<ClaimActionEvent>().last.code, code);
    });
  });
}
