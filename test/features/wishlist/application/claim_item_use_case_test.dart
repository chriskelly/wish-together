import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

import '../../../core/logging/recording_sink.dart';
import '../../../core/logging/wire_absence.dart';

class MockAuthService extends Mock implements AuthService {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  group('ClaimItemUseCase', () {
    late MockAuthService mockAuthService;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClaimItemUseCase claimItemUseCase;

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() {
      getIt.reset();
      mockAuthService = MockAuthService();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<AuthService>(mockAuthService);
      getIt.registerSingleton<AuthSession>(mockAuthService);
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      claimItemUseCase = ClaimItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should claim item with current user and timestamp', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';
      const userId = 'user123';
      final item = Item(id: itemId, name: 'Test Item');

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.update(any(), any()))
          .thenAnswer((_) async => {});

      // Act
      await claimItemUseCase.execute(wishlistId, item);

      // Assert
      final captured = verify(
        () => mockItemRepository.update(itemId, captureAny()),
      ).captured;
      expect(captured.length, 1);
      final updatedItem = captured[0] as Item;
      expect(updatedItem.claimedBy, userId);
      expect(updatedItem.claimedAt, isNotNull);
    });

    test('should throw exception when user is not authenticated', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      final item = Item(id: 'item123', name: 'Test Item');

      when(() => mockAuthService.currentUserId).thenReturn(null);

      // Act & Assert
      expect(
        () => claimItemUseCase.execute(wishlistId, item),
        throwsA(isA<Exception>()),
      );
      verifyNever(() => mockItemRepository.update(any(), any()));
    });

    test('should propagate exceptions from ItemRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const userId = 'user123';
      final item = Item(id: 'item123', name: 'Test Item');
      final exception = Exception('Failed to claim item');

      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.update(any(), any())).thenThrow(exception);

      // Act & Assert
      expect(() => claimItemUseCase.execute(wishlistId, item), throwsException);
    });
  });

  group('ClaimItemUseCase diagnostics', () {
    late MockAuthService mockAuthService;
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late ClaimItemUseCase claimItemUseCase;
    late RecordingSink sink;

    const String wishlistId = 'wishlist123';
    const String itemId = 'item123';
    const String userId = 'user123';

    setUpAll(() {
      registerFallbackValue(Item(name: 'test'));
    });

    setUp(() async {
      await getIt.reset();
      mockAuthService = MockAuthService();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      sink = RecordingSink();
      getIt.registerSingleton<AuthService>(mockAuthService);
      getIt.registerSingleton<AuthSession>(mockAuthService);
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
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.update(any(), any()))
          .thenAnswer((_) async {});

      await claimItemUseCase.execute(
        wishlistId,
        Item(id: itemId, name: 'Test Item'),
      );

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test('reports denied when nobody is signed in', () async {
      when(() => mockAuthService.currentUserId).thenReturn(null);

      await expectLater(
        claimItemUseCase.execute(
          wishlistId,
          Item(id: itemId, name: 'Test Item'),
        ),
        throwsA(isA<Exception>()),
      );

      final event = sink.eventsOf<ClaimActionEvent>().single;
      expect(event.phase, ClaimPhase.denied);
      expect(event.code, 'unauthenticated');
      verifyNever(() => mockItemRepository.update(any(), any()));
    });

    test(
      'reports denied with the error code and rethrows on a failed write',
      () async {
        const code = 'permission-denied';
        when(() => mockAuthService.currentUserId).thenReturn(userId);
        when(() => mockItemRepository.update(any(), any()))
            .thenThrow(const CodedError(code));

        await expectLater(
          claimItemUseCase.execute(
            wishlistId,
            Item(id: itemId, name: 'Test Item'),
          ),
          throwsA(isA<CodedError>()),
        );

        expect(phasesOf(sink), <ClaimPhase>[
          ClaimPhase.started,
          ClaimPhase.denied,
        ]);
        expect(sink.eventsOf<ClaimActionEvent>().last.code, code);
      },
    );

    test('a claim carries no item id or sensitive value', () async {
      // Arrange
      const phoneNumber = '+15555550123';
      const updateMessageToken = 'MAINTENANCE-WINDOW-42';
      when(() => mockAuthService.currentUserId).thenReturn(userId);
      when(() => mockItemRepository.update(any(), any()))
          .thenAnswer((_) async {});

      // Act
      await claimItemUseCase.execute(
        wishlistId,
        Item(id: itemId, name: 'Test Item'),
      );

      // Assert
      expectNoSensitiveValues(sink.records, <String>[
        phoneNumber,
        itemId,
        updateMessageToken,
      ]);
    });
  });
}
