import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

class MockClaimItemUseCase extends Mock implements ClaimItemUseCase {}

class MockUnclaimItemUseCase extends Mock implements UnclaimItemUseCase {}

class MockAuthSession extends Mock implements AuthSession {}

/// Yields [initial] on every listen, then follows [updates].
///
/// A broadcast controller alone would drop an event added before the provider
/// subscribes; this keeps the first emission deterministic.
Stream<T> _seeded<T>(T initial, Stream<T> updates) async* {
  yield initial;
  yield* updates;
}

void main() {
  const wishlistId = 'wishlist-1';
  const viewerId = 'viewer-uid';
  const ownerId = 'owner-uid';
  final wishlist = Wishlist(
    id: wishlistId,
    name: 'Birthday list',
    ownerId: ownerId,
    sharedWithGroups: const ['group-1'],
  );
  final ownerWishlist = wishlist.copyWith(ownerId: viewerId);
  final item = Item(id: 'item-1', name: 'Desk lamp');

  late MockWishlistRepository wishlistRepository;
  late MockItemRepository itemRepository;
  late MockClaimItemUseCase claimItemUseCase;
  late MockUnclaimItemUseCase unclaimItemUseCase;
  late MockAuthSession authSession;

  setUp(() {
    wishlistRepository = MockWishlistRepository();
    itemRepository = MockItemRepository();
    claimItemUseCase = MockClaimItemUseCase();
    unclaimItemUseCase = MockUnclaimItemUseCase();
    authSession = MockAuthSession();
    when(() => authSession.currentUserId).thenReturn(viewerId);
  });

  /// The page under a scope whose bridges are replaced by the mocks.
  Widget app({Widget Function()? frame}) {
    return ProviderScope(
      retry: disableAutomaticRetry,
      overrides: [
        wishlistRepositoryProvider.overrideWithValue(wishlistRepository),
        itemRepositoryProvider(wishlistId).overrideWithValue(itemRepository),
        authSessionProvider.overrideWithValue(authSession),
        claimItemUseCaseProvider.overrideWithValue(claimItemUseCase),
        unclaimItemUseCaseProvider.overrideWithValue(unclaimItemUseCase),
      ],
      child: MaterialApp(
        home: frame?.call() ?? WishlistDetailsPage(wishlistId: wishlistId),
      ),
    );
  }

  group('one subscription per page lifetime', () {
    late int wishlistCalls;
    late int itemCalls;
    late int wishlistListens;
    late int wishlistCancels;
    late int itemListens;
    late int itemCancels;
    late StreamController<Wishlist> wishlistUpdates;
    late StreamController<List<Item>> itemUpdates;

    setUp(() {
      wishlistCalls = 0;
      itemCalls = 0;
      wishlistListens = 0;
      wishlistCancels = 0;
      itemListens = 0;
      itemCancels = 0;

      wishlistUpdates = StreamController<Wishlist>.broadcast(
        onListen: () => wishlistListens++,
        onCancel: () => wishlistCancels++,
      );
      itemUpdates = StreamController<List<Item>>.broadcast(
        onListen: () => itemListens++,
        onCancel: () => itemCancels++,
      );
      addTearDown(wishlistUpdates.close);
      addTearDown(itemUpdates.close);

      when(() => wishlistRepository.streamOne(wishlistId)).thenAnswer((_) {
        wishlistCalls++;
        return _seeded(ownerWishlist, wishlistUpdates.stream);
      });
      when(() => itemRepository.streamAll()).thenAnswer((_) {
        itemCalls++;
        return _seeded([item], itemUpdates.stream);
      });
    });

    testWidgets(
      'reuses the wishlist and item streams across rebuilds and re-entry',
      (tester) async {
        late StateSetter setHostState;
        var pageBuilds = 0;
        var showPage = true;
        await tester.pumpWidget(
          app(
            frame: () => StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                // Register a MediaQuery dependency so a text-scale change
                // rebuilds this host, and build a fresh page so the page's own
                // build runs rather than being skipped as an identical widget.
                MediaQuery.textScalerOf(context);
                pageBuilds++;
                return showPage
                    ? WishlistDetailsPage(wishlistId: wishlistId)
                    : const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(pageBuilds, 1);
        expect(wishlistCalls, 1);
        expect(itemCalls, 1);
        expect(wishlistListens, 1);
        expect(itemListens, 1);

        // The defect: a spoiler toggle used to rebuild the page and resubscribe.
        await tester.tap(find.byTooltip('Show claimed status'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Hide claimed status'), findsOneWidget);
        expect(wishlistCalls, 1);
        expect(itemCalls, 1);

        // A real page rebuild, not only a descendant text relayout.
        setHostState(() {});
        await tester.pumpAndSettle();
        expect(pageBuilds, 2);
        expect(wishlistCalls, 1);
        expect(itemCalls, 1);

        // A text-scale change rebuilds the host and therefore the page.
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(pageBuilds, 3);
        expect(wishlistCalls, 1);
        expect(itemCalls, 1);

        // An item emission updates the list without a new subscription.
        itemUpdates.add([item.copyWith(name: 'Updated lamp')]);
        await tester.pumpAndSettle();
        expect(find.text('Updated lamp'), findsOneWidget);
        expect(wishlistCalls, 1);
        expect(itemCalls, 1);
        expect(wishlistListens, 1);
        expect(itemListens, 1);

        // The old page rebuilt the item StreamBuilder when the wishlist
        // snapshot changed; the item stream must stay subscribed.
        wishlistUpdates.add(ownerWishlist.copyWith(name: 'Renamed'));
        await tester.pumpAndSettle();
        expect(find.text('Renamed'), findsOneWidget);
        expect(itemCalls, 1);
        expect(itemListens, 1);

        // Leaving the page disposes both subscriptions; the scope stays alive.
        setHostState(() => showPage = false);
        await tester.pumpAndSettle();
        expect(wishlistCancels, 1);
        expect(itemCancels, 1);

        // Re-entering starts one new subscription per stream.
        setHostState(() => showPage = true);
        await tester.pumpAndSettle();
        expect(wishlistCalls, 2);
        expect(itemCalls, 2);
        expect(wishlistListens, 2);
        expect(itemListens, 2);
      },
    );
  });

  testWidgets('a second claim tap while the first is running does nothing', (
    tester,
  ) async {
    final completer = Completer<void>();
    when(() => claimItemUseCase.execute(wishlistId, item.id!))
        .thenAnswer((_) => completer.future);
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => Stream.value([item]));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Claim'));
    await tester.pump();
    await tester.tap(find.text('Claim'));
    await tester.pump();

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.text('Item claimed!'), findsOneWidget);
    verify(() => claimItemUseCase.execute(wishlistId, item.id!)).called(1);

    // A queued second snackbar would still be visible after the first expires.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Item claimed!'), findsNothing);
  });

  testWidgets('re-reads the signed-in uid for a new page lifetime', (
    tester,
  ) async {
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => Stream.value([item]));
    when(() => authSession.currentUserId).thenReturn(ownerId);

    var showPage = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      app(
        frame: () => StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return showPage
                ? const WishlistDetailsPage(wishlistId: wishlistId)
                : const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit Wishlist'), findsOneWidget);

    setHostState(() => showPage = false);
    await tester.pumpAndSettle();

    when(() => authSession.currentUserId).thenReturn(viewerId);
    setHostState(() => showPage = true);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit Wishlist'), findsNothing);
    expect(find.text('Claim'), findsOneWidget);
  });

  testWidgets('shows the empty message for an empty item list', (tester) async {
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => Stream.value(const <Item>[]));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('This wishlist has no items yet.'), findsOneWidget);
  });

  testWidgets('deletes an item after confirmation', (tester) async {
    final items = StreamController<List<Item>>.broadcast();
    addTearDown(items.close);
    final ack = Completer<void>();
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(ownerWishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => _seeded([item], items.stream));
    when(() => itemRepository.delete(item.id!)).thenAnswer((_) async {
      // The listener removes the row before the backend acknowledges the write.
      items.add(const <Item>[]);
      await ack.future;
    });

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Item?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    verifyNever(() => itemRepository.delete(item.id!));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Desk lamp'),
      findsNothing,
      reason: 'the row must be gone before the write is acknowledged',
    );
    expect(find.text('Item deleted.'), findsNothing);

    ack.complete();
    await tester.pumpAndSettle();

    verify(() => itemRepository.delete(item.id!)).called(1);
    expect(find.text('Item deleted.'), findsOneWidget);
  });

  testWidgets('shows the failure copy after a rejected delete', (tester) async {
    final items = StreamController<List<Item>>.broadcast();
    addTearDown(items.close);
    final ack = Completer<void>();
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(ownerWishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => _seeded([item], items.stream));
    when(() => itemRepository.delete(item.id!)).thenAnswer((_) async {
      items.add(const <Item>[]);
      await ack.future;
      throw StateError('denied');
    });

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Desk lamp'), findsNothing);

    ack.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Failed to delete item'), findsOneWidget);
  });

  group('error branches', () {
    testWidgets('shows Not Found when the wishlist read fails at once', (
      tester,
    ) async {
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.error(StateError('missing')));
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => Stream.value(const <Item>[]));

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('Wishlist Not Found'), findsWidgets);
    });

    testWidgets('shows Not Found when the wishlist fails after data', (
      tester,
    ) async {
      final controller = StreamController<Wishlist>();
      addTearDown(controller.close);
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => controller.stream);
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => Stream.value(const <Item>[]));

      await tester.pumpWidget(app());
      controller.add(wishlist);
      await tester.pumpAndSettle();
      expect(find.text('Birthday list'), findsOneWidget);

      controller.addError(StateError('boom'));
      await tester.pumpAndSettle();

      expect(find.text('Wishlist Not Found'), findsWidgets);
    });

    testWidgets('shows the list error when the item read fails', (
      tester,
    ) async {
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => Stream.error(StateError('items failed')));

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.textContaining('An error occurred'), findsOneWidget);
    });
  });
}
