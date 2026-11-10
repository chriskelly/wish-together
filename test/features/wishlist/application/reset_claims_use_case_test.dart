import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/reset_claims_use_case.dart';
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

  group('ResetClaimsUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ResetClaimsUseCase resetClaimsUseCase;

    setUp(() {
      getIt.reset();
      mockAuthSession = MockAuthSession();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<AuthSession>(mockAuthSession);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      resetClaimsUseCase = ResetClaimsUseCase();
    });

    tearDown(getIt.reset);

    test('resets claims through the bound item repository', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.resetClaims(itemId))
          .thenAnswer((_) async {});

      // Act
      await resetClaimsUseCase.execute(wishlistId, itemId);

      // Assert
      verify(() => mockItemRepository.resetClaims(itemId)).called(1);
    });

    test(
      'throws a signed-out failure and writes nothing when nobody is signed in',
      () async {
        // Arrange
        when(() => mockAuthSession.currentUserId).thenReturn(null);

        // Act & Assert
        await expectLater(
          resetClaimsUseCase.execute(wishlistId, itemId),
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
        verifyNever(() => mockItemRepository.resetClaims(any()));
      },
    );

    test('classifies a failed write and propagates it', () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.resetClaims(itemId))
          .thenThrow(const CodedError('permission-denied'));

      // Act & Assert
      await expectLater(
        resetClaimsUseCase.execute(wishlistId, itemId),
        throwsA(
          isA<ClaimFailure>()
              .having(
                (failure) => failure.reason,
                'reason',
                ClaimFailureReason.accessDenied,
              )
              .having((failure) => failure.code, 'code', 'permission-denied'),
        ),
      );
    });

    test("keeps the write's stack trace on the ClaimFailure", () async {
      // Arrange
      const String marker = 'original-failure-site';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.resetClaims(itemId)).thenAnswer(
        (_) => Error.throwWithStackTrace(
          const CodedError('permission-denied'),
          StackTrace.fromString(marker),
        ),
      );

      // Act
      StackTrace? caught;
      try {
        await resetClaimsUseCase.execute(wishlistId, itemId);
      } catch (_, stackTrace) {
        caught = stackTrace;
      }

      // Assert
      expect(caught, isNotNull);
      expect(caught.toString(), contains(marker));
    });
  });

  group('ResetClaimsUseCase diagnostics', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ResetClaimsUseCase resetClaimsUseCase;
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
      resetClaimsUseCase = ResetClaimsUseCase();
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
    });

    tearDown(getIt.reset);

    test('reports started then completed', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.resetClaims(itemId))
          .thenAnswer((_) async {});

      await resetClaimsUseCase.execute(wishlistId, itemId);

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test('reports denied when nobody is signed in', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      await expectLater(
        resetClaimsUseCase.execute(wishlistId, itemId),
        throwsA(isA<ClaimFailure>()),
      );

      final event = sink.eventsOf<ClaimActionEvent>().single;
      expect(event.phase, ClaimPhase.denied);
      expect(event.code, unauthenticatedCode);
      verifyNever(() => mockItemRepository.resetClaims(any()));
    });

    test(
      'reports denied with the error code and rethrows on a failed write',
      () async {
        const code = 'permission-denied';
        when(() => mockAuthSession.currentUserId).thenReturn(userId);
        when(() => mockItemRepository.resetClaims(itemId))
            .thenThrow(const CodedError(code));

        await expectLater(
          resetClaimsUseCase.execute(wishlistId, itemId),
          throwsA(isA<ClaimFailure>()),
        );

        expect(phasesOf(sink), <ClaimPhase>[
          ClaimPhase.started,
          ClaimPhase.denied,
        ]);
        expect(sink.eventsOf<ClaimActionEvent>().last.code, code);
      },
    );
  });
}
