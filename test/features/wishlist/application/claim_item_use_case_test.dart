import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

import '../../../core/logging/recording_sink.dart';
import '../../../core/logging/wire_absence.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  const String wishlistId = 'wishlist123';
  const String itemId = 'item123';
  const String userId = 'user123';

  group('ClaimItemUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClaimItemUseCase claimItemUseCase;

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockAuthSession = MockAuthSession();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      claimItemUseCase = ClaimItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('claims the item for the current user', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .thenAnswer((_) async {});

      // Act
      await claimItemUseCase.execute(wishlistId, itemId);

      // Assert
      verify(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .called(1);
      verifyNever(() => mockItemRepository.update(any(), any()));
    });

    test('throws a signed-out failure when nobody is signed in', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      // Act & Assert
      await expectLater(
        claimItemUseCase.execute(wishlistId, itemId),
        throwsA(
          isA<ClaimFailure>().having(
            (failure) => failure.reason,
            'reason',
            ClaimFailureReason.signedOut,
          ),
        ),
      );
      verifyNever(
        () =>
            mockItemRepository.claim(any(), claimedBy: any(named: 'claimedBy')),
      );
    });

    test('throws a ClaimFailure carrying the reason and code', () async {
      // Arrange
      const String code = 'permission-denied';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .thenThrow(const CodedError(code));

      // Act & Assert
      await expectLater(
        claimItemUseCase.execute(wishlistId, itemId),
        throwsA(
          isA<ClaimFailure>()
              .having(
                (failure) => failure.reason,
                'reason',
                ClaimFailureReason.accessDenied,
              )
              .having((failure) => failure.code, 'code', code),
        ),
      );
    });

    test("keeps the write's stack trace on the ClaimFailure", () async {
      // Arrange
      const String marker = 'original-failure-site';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .thenAnswer(
            (_) => Error.throwWithStackTrace(
              const CodedError('permission-denied'),
              StackTrace.fromString(marker),
            ),
          );

      // Act
      StackTrace? caught;
      try {
        await claimItemUseCase.execute(wishlistId, itemId);
      } catch (_, stackTrace) {
        caught = stackTrace;
      }

      // Assert
      expect(caught, isNotNull);
      expect(caught.toString(), contains(marker));
    });
  });

  group('ClaimItemUseCase diagnostics', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClaimItemUseCase claimItemUseCase;
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
      claimItemUseCase = ClaimItemUseCase();
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
    });

    tearDown(getIt.reset);

    test('reports started then completed', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .thenAnswer((_) async {});

      // Act
      await claimItemUseCase.execute(wishlistId, itemId);

      // Assert
      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test('reports denied when nobody is signed in', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      // Act
      await expectLater(
        claimItemUseCase.execute(wishlistId, itemId),
        throwsA(isA<ClaimFailure>()),
      );

      // Assert
      final event = sink.eventsOf<ClaimActionEvent>().single;
      expect(event.phase, ClaimPhase.denied);
      expect(event.code, unauthenticatedCode);
      verifyNever(
        () =>
            mockItemRepository.claim(any(), claimedBy: any(named: 'claimedBy')),
      );
    });

    test(
      'reports denied with the error code and rethrows a ClaimFailure',
      () async {
        // Arrange
        const code = 'permission-denied';
        when(() => mockAuthSession.currentUserId).thenReturn(userId);
        when(() => mockItemRepository.claim(itemId, claimedBy: userId))
            .thenThrow(const CodedError(code));

        // Act
        await expectLater(
          claimItemUseCase.execute(wishlistId, itemId),
          throwsA(isA<ClaimFailure>()),
        );

        // Assert
        expect(phasesOf(sink), <ClaimPhase>[
          ClaimPhase.started,
          ClaimPhase.denied,
        ]);
        expect(sink.eventsOf<ClaimActionEvent>().last.code, code);
        expect(sink.eventsOf<ErrorEvent>(), isEmpty);
      },
    );

    test('a claim carries no item id or sensitive value', () async {
      // Arrange
      const phoneNumber = '+15555550123';
      const updateMessageToken = 'MAINTENANCE-WINDOW-42';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.claim(itemId, claimedBy: userId))
          .thenAnswer((_) async {});

      // Act
      await claimItemUseCase.execute(wishlistId, itemId);

      // Assert
      expectNoSensitiveValues(sink.records, <String>[
        phoneNumber,
        itemId,
        updateMessageToken,
      ]);
    });
  });
}
