import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';

class MockClaimItemUseCase extends Mock implements ClaimItemUseCase {}

class MockUnclaimItemUseCase extends Mock implements UnclaimItemUseCase {}

void main() {
  const wishlistId = 'wishlist-1';
  const itemId = 'item-1';

  late MockClaimItemUseCase claimItemUseCase;
  late MockUnclaimItemUseCase unclaimItemUseCase;

  setUp(() {
    claimItemUseCase = MockClaimItemUseCase();
    unclaimItemUseCase = MockUnclaimItemUseCase();
  });

  ProviderContainer containerWith({
    ClaimItemUseCase? claim,
    UnclaimItemUseCase? unclaim,
  }) {
    return ProviderContainer.test(
      retry: disableAutomaticRetry,
      overrides: [
        if (claim != null) claimItemUseCaseProvider.overrideWithValue(claim),
        if (unclaim != null)
          unclaimItemUseCaseProvider.overrideWithValue(unclaim),
      ],
    );
  }

  /// Keeps an auto-disposed provider alive for the test body.
  void listen<T>(ProviderContainer container, ProviderListenable<T> provider) {
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
  }

  group('spoiler toggle', () {
    test('starts spoiler-free and flips on toggle', () {
      final container = containerWith();
      listen(container, wishlistSpoilerFreeProvider(wishlistId));

      expect(container.read(wishlistSpoilerFreeProvider(wishlistId)), isTrue);

      container.read(wishlistSpoilerFreeProvider(wishlistId).notifier).toggle();
      expect(container.read(wishlistSpoilerFreeProvider(wishlistId)), isFalse);

      container.read(wishlistSpoilerFreeProvider(wishlistId).notifier).toggle();
      expect(container.read(wishlistSpoilerFreeProvider(wishlistId)), isTrue);
    });
  });

  group('item actions', () {
    test('claim runs the use case, reports busy and clears it', () async {
      final completer = Completer<void>();
      when(() => claimItemUseCase.execute(wishlistId, itemId))
          .thenAnswer((_) => completer.future);
      final container = containerWith(claim: claimItemUseCase);
      listen(container, wishlistItemActionsProvider(wishlistId));

      final running = container
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .claim(itemId);
      expect(
        container.read(wishlistItemActionsProvider(wishlistId)).busyItemId,
        itemId,
      );

      completer.complete();
      expect(await running, isTrue);
      expect(
        container.read(wishlistItemActionsProvider(wishlistId)).busyItemId,
        isNull,
      );
      verify(() => claimItemUseCase.execute(wishlistId, itemId)).called(1);
    });

    test('claim rethrows a ClaimFailure and clears busy', () async {
      when(() => claimItemUseCase.execute(wishlistId, itemId))
          .thenThrow(const ClaimFailure(ClaimFailureReason.fullyClaimed));
      final container = containerWith(claim: claimItemUseCase);
      listen(container, wishlistItemActionsProvider(wishlistId));

      await expectLater(
        container
            .read(wishlistItemActionsProvider(wishlistId).notifier)
            .claim(itemId),
        throwsA(isA<ClaimFailure>()),
      );
      expect(
        container.read(wishlistItemActionsProvider(wishlistId)).busyItemId,
        isNull,
      );
    });

    test('unclaim runs the unclaim use case', () async {
      when(() => unclaimItemUseCase.execute(wishlistId, itemId))
          .thenAnswer((_) async {});
      final container = containerWith(unclaim: unclaimItemUseCase);
      listen(container, wishlistItemActionsProvider(wishlistId));

      final ran = await container
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .unclaim(itemId);

      expect(ran, isTrue);
      verify(() => unclaimItemUseCase.execute(wishlistId, itemId)).called(1);
    });
  });
}
