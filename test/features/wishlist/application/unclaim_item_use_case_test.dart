import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

import '../../../core/logging/recording_sink.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

void main() {
  group('UnclaimItemUseCase', () {
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UnclaimItemUseCase unclaimItemUseCase;

    setUp(() {
      getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      getIt.registerSingleton<WishlistRepository>(mockWishlistRepository);
      unclaimItemUseCase = UnclaimItemUseCase();
    });

    tearDown(() {
      getIt.reset();
    });

    test('should unclaim item', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.unclaim(itemId))
          .thenAnswer((_) async => {});

      // Act
      await unclaimItemUseCase.execute(wishlistId, itemId);

      // Assert
      verify(() => mockItemRepository.unclaim(itemId)).called(1);
    });

    test('should propagate exceptions from ItemRepository', () async {
      // Arrange
      const wishlistId = 'wishlist123';
      const itemId = 'item123';
      final exception = Exception('Failed to unclaim item');

      when(() => mockWishlistRepository.items(wishlistId))
          .thenReturn(mockItemRepository);
      when(() => mockItemRepository.unclaim(itemId)).thenThrow(exception);

      // Act & Assert
      expect(
        () => unclaimItemUseCase.execute(wishlistId, itemId),
        throwsException,
      );
    });
  });

  group('UnclaimItemUseCase diagnostics', () {
    late MockWishlistRepository mockWishlistRepository;
    late MockItemRepository mockItemRepository;
    late UnclaimItemUseCase unclaimItemUseCase;
    late RecordingSink sink;

    const String wishlistId = 'wishlist123';
    const String itemId = 'item123';

    setUp(() async {
      await getIt.reset();
      mockWishlistRepository = MockWishlistRepository();
      mockItemRepository = MockItemRepository();
      sink = RecordingSink();
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
      when(() => mockItemRepository.unclaim(itemId)).thenAnswer((_) async {});

      await unclaimItemUseCase.execute(wishlistId, itemId);

      expect(phasesOf(sink), <ClaimPhase>[
        ClaimPhase.started,
        ClaimPhase.completed,
      ]);
    });

    test(
      'reports denied with the error code and rethrows on a failed write',
      () async {
        const code = 'permission-denied';
        when(() => mockItemRepository.unclaim(itemId))
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
      },
    );
  });
}
