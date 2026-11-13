import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';

class MockClaimItemUseCase extends Mock implements ClaimItemUseCase {}

class MockUnclaimItemUseCase extends Mock implements UnclaimItemUseCase {}

class MockItemRepository extends Mock implements ItemRepository {}

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

  group('item read state', () {
    final item = Item(id: itemId, name: 'Desk lamp');

    ListSnapshot<Item> snapshot(
      List<Item> items, {
      required bool isFromCache,
    }) => ListSnapshot(items: items, isFromCache: isFromCache);

    /// Listens for item-read states; the subscription closes with the test.
    List<WishlistItems> listenItems(ProviderContainer container) {
      final states = <WishlistItems>[];
      final subscription = container.listen(wishlistItemsProvider(wishlistId), (
        _,
        next,
      ) {
        if (next.hasValue) states.add(next.requireValue);
      }, fireImmediately: true);
      addTearDown(subscription.close);
      return states;
    }

    Future<List<WishlistItems>> itemsFrom(
      Stream<ListSnapshot<Item>> snapshots,
    ) async {
      final repository = MockItemRepository();
      when(() => repository.streamAll()).thenAnswer((_) => snapshots);
      final container = ProviderContainer.test(
        retry: disableAutomaticRetry,
        overrides: [
          itemRepositoryProvider(wishlistId).overrideWithValue(repository),
        ],
      );
      final states = listenItems(container);
      await container.read(wishlistItemsProvider(wishlistId).future);
      await pumpEventQueue();
      return states;
    }

    test('carries the rows', () async {
      final states = await itemsFrom(
        Stream.value(snapshot(<Item>[item], isFromCache: true)),
      );

      expect(states.last.items, <Item>[item]);
      expect(states.last.isUnconfirmedEmpty, isFalse);
    });

    test('a lone cache-only empty read is unconfirmed empty', () async {
      final states = await itemsFrom(
        Stream.value(snapshot(const <Item>[], isFromCache: true)),
      );

      expect(states.single.isUnconfirmedEmpty, isTrue);
    });

    test('a server-confirmed empty read is not unconfirmed', () async {
      final states = await itemsFrom(
        Stream.value(snapshot(const <Item>[], isFromCache: false)),
      );

      expect(states.single.isUnconfirmedEmpty, isFalse);
    });

    test('cached rows make a later cache-only empty read credible', () async {
      final states = await itemsFrom(
        Stream.fromIterable([
          snapshot(<Item>[item], isFromCache: true),
          snapshot(const <Item>[], isFromCache: true),
        ]),
      );

      expect(states.last.items, isEmpty);
      expect(states.last.isUnconfirmedEmpty, isFalse);
    });

    test(
      'a server-confirmed empty read keeps a later cache-only empty credible',
      () async {
        final states = await itemsFrom(
          Stream.fromIterable([
            snapshot(const <Item>[], isFromCache: false),
            snapshot(const <Item>[], isFromCache: true),
          ]),
        );

        expect(states.last.isUnconfirmedEmpty, isFalse);
      },
    );

    test('a retry does not inherit credibility', () async {
      final first = StreamController<ListSnapshot<Item>>.broadcast();
      final second = StreamController<ListSnapshot<Item>>.broadcast();
      addTearDown(first.close);
      addTearDown(second.close);
      var calls = 0;
      final repository = MockItemRepository();
      when(() => repository.streamAll()).thenAnswer((_) {
        calls++;
        return calls == 1 ? first.stream : second.stream;
      });
      final container = ProviderContainer.test(
        retry: disableAutomaticRetry,
        overrides: [
          itemRepositoryProvider(wishlistId).overrideWithValue(repository),
        ],
      );
      final states = listenItems(container);

      first.add(snapshot(<Item>[item], isFromCache: true));
      await pumpEventQueue();
      expect(states.last.isUnconfirmedEmpty, isFalse);

      container.invalidate(wishlistItemsProvider(wishlistId));
      await pumpEventQueue();
      second.add(snapshot(const <Item>[], isFromCache: true));
      await pumpEventQueue();

      expect(states.last.isUnconfirmedEmpty, isTrue);
    });
  });

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
