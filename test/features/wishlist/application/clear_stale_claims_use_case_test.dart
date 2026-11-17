import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/clear_stale_claims_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';

import '../../../core/logging/recording_sink.dart';

class MockAuthSession extends Mock implements AuthSession {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  const wishlistId = 'wishlist123';
  const userId = 'user123';
  const plan = StaleClaimsPlan({
    'item-1': {'uid-1'},
    'item-2': {'uid-2'},
    'item-3': {'uid-3'},
  });

  group('ClearStaleClaimsUseCase', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClearStaleClaimsUseCase clearStaleClaimsUseCase;

    setUpAll(() {
      registerFallbackValue(<String>{});
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
      clearStaleClaimsUseCase = ClearStaleClaimsUseCase();
    });

    tearDown(getIt.reset);

    test("removes every planned item's claims", () async {
      // Arrange
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      ).thenAnswer((_) async {});

      // Act
      await clearStaleClaimsUseCase.execute(wishlistId, plan);

      // Assert
      for (final entry in plan.byItem.entries) {
        final uids =
            verify(
                  () => mockItemRepository.removeClaims(
                    entry.key,
                    uids: captureAny(named: 'uids'),
                  ),
                ).captured.single
                as Set<String>;
        expect(uids, entry.value);
      }
    });

    test(
      'throws a signed-out failure and writes nothing when nobody is signed in',
      () async {
        // Arrange
        when(() => mockAuthSession.currentUserId).thenReturn(null);

        // Act & Assert
        await expectLater(
          clearStaleClaimsUseCase.execute(wishlistId, plan),
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
          () =>
              mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
        );
      },
    );

    test(
      'stops at the first failed write and throws its classified failure',
      () async {
        // Arrange
        when(() => mockAuthSession.currentUserId).thenReturn(userId);
        when(
          () =>
              mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
        ).thenAnswer((invocation) {
          if (invocation.positionalArguments.first == 'item-2') {
            throw const CodedError('permission-denied');
          }
          return Future<void>.value();
        });

        // Act & Assert
        await expectLater(
          clearStaleClaimsUseCase.execute(wishlistId, plan),
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
        verifyNever(
          () => mockItemRepository.removeClaims(
            'item-3',
            uids: any(named: 'uids'),
          ),
        );
      },
    );

    test("keeps the write's stack trace on the ClaimFailure", () async {
      // Arrange
      const String marker = 'original-failure-site';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      ).thenAnswer((invocation) {
        if (invocation.positionalArguments.first == 'item-2') {
          return Error.throwWithStackTrace(
            const CodedError('permission-denied'),
            StackTrace.fromString(marker),
          );
        }
        return Future<void>.value();
      });

      // Act
      StackTrace? caught;
      try {
        await clearStaleClaimsUseCase.execute(wishlistId, plan);
      } catch (_, stackTrace) {
        caught = stackTrace;
      }

      // Assert
      expect(caught, isNotNull);
      expect(caught.toString(), contains(marker));
    });
  });

  group('ClearStaleClaimsUseCase diagnostics', () {
    late MockAuthSession mockAuthSession;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClearStaleClaimsUseCase clearStaleClaimsUseCase;
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
      clearStaleClaimsUseCase = ClearStaleClaimsUseCase();
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
    });

    tearDown(getIt.reset);

    test('reports started then completed', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      ).thenAnswer((_) async {});

      await clearStaleClaimsUseCase.execute(wishlistId, plan);

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test('reports denied when nobody is signed in', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(null);

      await expectLater(
        clearStaleClaimsUseCase.execute(wishlistId, plan),
        throwsA(isA<ClaimFailure>()),
      );

      final event = sink.eventsOf<ClaimActionEvent>().single;
      expect(event.phase, ClaimPhase.denied);
      expect(event.code, unauthenticatedCode);
      verifyNever(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      );
    });

    test('reports denied with the error code on a failed write', () async {
      const code = 'permission-denied';
      when(() => mockAuthSession.currentUserId).thenReturn(userId);
      when(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      ).thenAnswer((invocation) {
        if (invocation.positionalArguments.first == 'item-2') {
          throw const CodedError(code);
        }
        return Future<void>.value();
      });

      await expectLater(
        clearStaleClaimsUseCase.execute(wishlistId, plan),
        throwsA(isA<ClaimFailure>()),
      );

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.denied,
      ]);
      expect(sink.eventsOf<ClaimActionEvent>().last.code, code);
    });

    test('returns without writing or logging for an empty plan', () async {
      when(() => mockAuthSession.currentUserId).thenReturn(userId);

      await clearStaleClaimsUseCase.execute(
        wishlistId,
        const StaleClaimsPlan({}),
      );

      expect(phasesOf(sink), isEmpty);
      verifyNever(
        () => mockItemRepository.removeClaims(any(), uids: any(named: 'uids')),
      );
    });
  });
}
