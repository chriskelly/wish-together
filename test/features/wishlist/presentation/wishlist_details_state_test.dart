import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
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

/// An item read the server has confirmed, unless a test says otherwise.
ListSnapshot<Item> _items(List<Item> items, {bool isFromCache = false}) =>
    ListSnapshot(items: items, isFromCache: isFromCache);

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

  /// Pumps the page past the unavailable panel's 800 ms grace.
  Future<void> pumpPastGrace(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
  }

  /// The item read's in-flight spinner, matched by its screen-reader label.
  final loadingItems = find.byWidgetPredicate(
    (widget) =>
        widget is CircularProgressIndicator &&
        widget.semanticsLabel == 'Loading wishlist items',
  );

  group('one subscription per page lifetime', () {
    late int wishlistCalls;
    late int itemCalls;
    late int wishlistListens;
    late int wishlistCancels;
    late int itemListens;
    late int itemCancels;
    late StreamController<Wishlist> wishlistUpdates;
    late StreamController<ListSnapshot<Item>> itemUpdates;

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
      itemUpdates = StreamController<ListSnapshot<Item>>.broadcast(
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
        return _seeded(_items([item]), itemUpdates.stream);
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
        itemUpdates.add(_items([item.copyWith(name: 'Updated lamp')]));
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
        .thenAnswer((_) => Stream.value(_items([item])));

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
        .thenAnswer((_) => Stream.value(_items([item])));
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
        .thenAnswer((_) => Stream.value(_items(const <Item>[])));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('This wishlist has no items yet.'), findsOneWidget);
  });

  testWidgets('shows the unavailable state for a cache-only empty read', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));
      when(() => itemRepository.streamAll()).thenAnswer(
        (_) => Stream.value(_items(const <Item>[], isFromCache: true)),
      );

      await tester.pumpWidget(app());
      await pumpPastGrace(tester);

      expect(find.text('Could not load the items.'), findsOneWidget);
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      expect(find.text('This wishlist has no items yet.'), findsNothing);

      final liveRegion = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      );
      expect(liveRegion, findsOneWidget);
      final node = tester.getSemantics(liveRegion);
      expect(node.label, contains('Could not load the items.'));
      expect(node.label, contains('Check your connection and try again.'));
      expect(node.label, isNot(contains('Try again')));
      expect(
        node.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
        reason: 'a screen reader must announce the failed load',
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('Try again re-subscribes and shows progress while it runs', (
    tester,
  ) async {
    final retry = StreamController<ListSnapshot<Item>>.broadcast();
    addTearDown(retry.close);
    var itemCalls = 0;
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer((_) {
      itemCalls++;
      if (itemCalls == 1) {
        return Stream.value(_items(const <Item>[], isFromCache: true));
      }
      return retry.stream;
    });

    await tester.pumpWidget(app());
    await pumpPastGrace(tester);
    expect(find.text('Try again'), findsOneWidget);
    expect(itemCalls, 1);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(itemCalls, 2);
    expect(find.text('Try again'), findsNothing);
    expect(loadingItems, findsOneWidget);

    // The retry's first snapshot is cache-only, as it is on a fresh listen.
    // The fresh grace window keeps the panel back until the server replies.
    retry.add(_items(const <Item>[], isFromCache: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Could not load the items.'), findsNothing);
    expect(find.text('Try again'), findsNothing);

    retry.add(_items(const <Item>[], isFromCache: false));
    await tester.pump();
    await tester.pump();

    expect(find.text('This wishlist has no items yet.'), findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(itemCalls, 2);
  });

  testWidgets('does not flash the panel when a retry resolves from cache', (
    tester,
  ) async {
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer(
      (_) => Stream.value(_items(const <Item>[], isFromCache: true)),
    );

    await tester.pumpWidget(app());
    await pumpPastGrace(tester);
    expect(find.text('Could not load the items.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(find.text('Could not load the items.'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(loadingItems, findsOneWidget);

    await pumpPastGrace(tester);
    expect(find.text('Could not load the items.'), findsOneWidget);
  });

  testWidgets('restarts the grace when a retry cache snapshot arrives late', (
    tester,
  ) async {
    final retry = StreamController<ListSnapshot<Item>>.broadcast();
    addTearDown(retry.close);
    var itemCalls = 0;
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer((_) {
      itemCalls++;
      if (itemCalls == 1) {
        return Stream.value(_items(const <Item>[], isFromCache: true));
      }
      return retry.stream;
    });

    await tester.pumpWidget(app());
    await pumpPastGrace(tester);
    await tester.tap(find.text('Try again'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 900));
    expect(loadingItems, findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);

    retry.add(_items(const <Item>[], isFromCache: true));
    await tester.pump();
    await tester.pump();
    expect(loadingItems, findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(find.text('Could not load the items.'), findsOneWidget);
  });

  testWidgets('shows the list error when a retry fails', (tester) async {
    var itemCalls = 0;
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer((_) {
      itemCalls++;
      if (itemCalls == 1) {
        return Stream.value(_items(const <Item>[], isFromCache: true));
      }
      return Stream.error(StateError('items failed'));
    });

    await tester.pumpWidget(app());
    await pumpPastGrace(tester);
    expect(find.text('Could not load the items.'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // The generic list error is the page's pre-existing item-error UI; a
    // retry-capable error panel is a follow-up.
    expect(find.textContaining('An error occurred'), findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('shows cache-only rows instead of the unavailable state', (
    tester,
  ) async {
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => Stream.value(_items([item], isFromCache: true)));

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);
  });

  testWidgets('keeps the empty message after cached rows become empty', (
    tester,
  ) async {
    final items = StreamController<ListSnapshot<Item>>.broadcast();
    addTearDown(items.close);
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer((_) => items.stream);

    await tester.pumpWidget(app());
    await tester.pump();
    items.add(_items([item], isFromCache: true));
    await tester.pump();
    await tester.pump();
    expect(find.text('Desk lamp'), findsOneWidget);

    // The owner deletes the last row while offline: the local delete is the
    // user's own state, not a failed read.
    items.add(_items(const <Item>[], isFromCache: true));
    await tester.pump();
    await tester.pump();

    expect(find.text('This wishlist has no items yet.'), findsOneWidget);
    expect(find.text('Could not load the items.'), findsNothing);
  });

  testWidgets(
    'replaces the unavailable state when the server confirms the read',
    (tester) async {
      final items = StreamController<ListSnapshot<Item>>.broadcast();
      addTearDown(items.close);
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));
      when(() => itemRepository.streamAll()).thenAnswer((_) => items.stream);

      await tester.pumpWidget(app());
      await tester.pump();
      items.add(_items(const <Item>[], isFromCache: true));
      await pumpPastGrace(tester);
      expect(find.text('Could not load the items.'), findsOneWidget);

      items.add(_items(const <Item>[], isFromCache: false));
      await tester.pump();
      await tester.pump();

      expect(find.text('This wishlist has no items yet.'), findsOneWidget);
      expect(find.text('Could not load the items.'), findsNothing);
    },
  );

  testWidgets(
    'does not flash the panel when the server confirms in the grace',
    (tester) async {
      final items = StreamController<ListSnapshot<Item>>.broadcast();
      addTearDown(items.close);
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));
      when(() => itemRepository.streamAll()).thenAnswer((_) => items.stream);

      await tester.pumpWidget(app());
      await tester.pump();
      items.add(_items(const <Item>[], isFromCache: true));
      await tester.pump();
      await tester.pump();
      expect(find.text('Could not load the items.'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      items.add(_items(const <Item>[], isFromCache: false));
      await tester.pump();
      await tester.pump();

      expect(find.text('This wishlist has no items yet.'), findsOneWidget);
      expect(find.text('Could not load the items.'), findsNothing);
    },
  );

  testWidgets(
    'waits out the grace window before showing the unavailable state',
    (tester) async {
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));
      when(() => itemRepository.streamAll()).thenAnswer(
        (_) => Stream.value(_items(const <Item>[], isFromCache: true)),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Could not load the items.'), findsNothing);
      expect(loadingItems, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Could not load the items.'), findsOneWidget);
    },
  );

  testWidgets('cancels the grace timer when the page leaves', (tester) async {
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(wishlist));
    when(() => itemRepository.streamAll()).thenAnswer(
      (_) => Stream.value(_items(const <Item>[], isFromCache: true)),
    );

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
    await tester.pump();
    await tester.pump();
    expect(
      loadingItems,
      findsOneWidget,
      reason: 'the grace timer must be pending before the page leaves',
    );

    setHostState(() => showPage = false);
    await tester.pump();

    // The test binding reports a timer still pending after the tree is
    // disposed, so a missing dispose cancel fails here.
  });

  testWidgets('deletes an item after confirmation', (tester) async {
    final items = StreamController<ListSnapshot<Item>>.broadcast();
    addTearDown(items.close);
    final ack = Completer<void>();
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(ownerWishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => _seeded(_items([item]), items.stream));
    when(() => itemRepository.delete(item.id!)).thenAnswer((_) async {
      // The listener removes the row before the backend acknowledges the write.
      items.add(_items(const <Item>[]));
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
    final items = StreamController<ListSnapshot<Item>>.broadcast();
    addTearDown(items.close);
    final ack = Completer<void>();
    when(() => wishlistRepository.streamOne(wishlistId))
        .thenAnswer((_) => Stream.value(ownerWishlist));
    when(() => itemRepository.streamAll())
        .thenAnswer((_) => _seeded(_items([item]), items.stream));
    when(() => itemRepository.delete(item.id!)).thenAnswer((_) async {
      items.add(_items(const <Item>[]));
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
          .thenAnswer((_) => Stream.value(_items(const <Item>[])));

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
          .thenAnswer((_) => Stream.value(_items(const <Item>[])));

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
