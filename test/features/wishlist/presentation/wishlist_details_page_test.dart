import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/core/theme.dart';
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

void main() {
  group('WishlistDetailsPage item rows', () {
    const wishlistId = 'wishlist-1';
    const viewerId = 'viewer-uid';
    const ownerId = 'owner-uid';
    const otherReaderId = 'other-reader-uid';
    const itemName = 'Desk lamp';
    final wishlist = Wishlist(
      id: wishlistId,
      name: 'Birthday list',
      ownerId: ownerId,
      sharedWithGroups: const ['group-1'],
    );

    late MockWishlistRepository wishlistRepository;
    late MockItemRepository itemRepository;

    setUp(() {
      getIt.reset();

      wishlistRepository = MockWishlistRepository();
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));

      itemRepository = MockItemRepository();
      when(() => wishlistRepository.items(wishlistId))
          .thenReturn(itemRepository);

      final authSession = MockAuthSession();
      when(() => authSession.currentUserId).thenReturn(viewerId);

      getIt.registerSingleton<WishlistRepository>(wishlistRepository);
      getIt.registerSingleton<AuthSession>(authSession);
      getIt.registerSingleton<ClaimItemUseCase>(MockClaimItemUseCase());
      getIt.registerSingleton<UnclaimItemUseCase>(MockUnclaimItemUseCase());
    });

    tearDown(getIt.reset);

    /// Pumps the page for an item stream that has already emitted [items].
    Future<void> pumpPage(
      WidgetTester tester,
      List<Item> items, {
      ThemeData? theme,
      bool asOwner = false,
    }) async {
      if (asOwner) {
        when(
          () => wishlistRepository.streamOne(wishlistId),
        ).thenAnswer((_) => Stream.value(wishlist.copyWith(ownerId: viewerId)));
      }
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => Stream.value(items));

      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? lightTheme,
          home: const WishlistDetailsPage(wishlistId: wishlistId),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The margin the page gives every item row.
    const itemMargin = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);

    /// The Material card that carries the item row's fill.
    Card cardOf(WidgetTester tester, String name) => tester.widget<Card>(
      find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(BrandCard),
        ),
        matching: find.byType(Card),
      ),
    );

    Text titleOf(WidgetTester tester, String name) =>
        tester.widget<Text>(find.text(name));

    StatusPillTone toneOf(WidgetTester tester, String label) =>
        tester.widget<StatusPill>(find.widgetWithText(StatusPill, label)).tone;

    /// Records the platform channel so a copy can be asserted.
    ///
    /// The page also emits system-chrome calls, so look the clipboard write up
    /// by name instead of taking the first or last call.
    List<MethodCall> recordPlatformCalls() {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return calls;
    }

    String? copiedText(List<MethodCall> calls) {
      for (final call in calls) {
        if (call.method == 'Clipboard.setData') {
          return (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
      }
      return null;
    }

    /// Long-presses [finder], then taps the toolbar's Copy action.
    Future<void> selectAndCopy(WidgetTester tester, Finder finder) async {
      await tester.longPress(finder);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      "shows the viewer's own claim as an accent pill beside Unclaim",
      (tester) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimedBy: viewerId,
            claimedAt: DateTime.utc(2026, 11, 1),
          ),
        ]);

        final pill = find.widgetWithText(StatusPill, 'You claimed this!');
        expect(pill, findsOneWidget);
        expect(toneOf(tester, 'You claimed this!'), StatusPillTone.accent);

        final wrap = find.ancestor(of: pill, matching: find.byType(Wrap)).first;
        final unclaim = find.descendant(
          of: wrap,
          matching: find.text('Unclaim'),
        );
        expect(unclaim, findsOneWidget);
        expect(
          tester.getRect(pill).right,
          lessThan(tester.getRect(unclaim).left),
          reason: 'the pill sits before the action it belongs to',
        );
      },
    );

    testWidgets("shows another reader's claim as a neutral pill", (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claimedBy: otherReaderId,
          claimedAt: DateTime.utc(2026, 11, 1),
        ),
      ]);

      expect(find.text('Claimed'), findsOneWidget);
      expect(toneOf(tester, 'Claimed'), StatusPillTone.neutral);
      // Only the claimer may clear a claim, so offering either action here
      // would surface a denial for a tap the viewer cannot win.
      expect(find.text('Claim'), findsNothing);
      expect(find.text('Unclaim'), findsNothing);
    });

    testWidgets('leaves an unclaimed item claimable', (tester) async {
      await pumpPage(tester, [Item(id: 'item-1', name: itemName)]);

      expect(find.text('Claim'), findsOneWidget);
      expect(find.byType(StatusPill), findsNothing);
    });

    group('claimed card treatment for readers', () {
      const claimedItemId = 'item-1';

      for (final (claimer, claimedBy) in <(String, String)>[
        ('another member', otherReaderId),
        ('the viewer', viewerId),
      ]) {
        testWidgets(
          "mutes a claimed item's card fill for a reader when $claimer claimed it",
          (tester) async {
            await pumpPage(tester, [
              Item(
                id: claimedItemId,
                name: itemName,
                claimedBy: claimedBy,
                claimedAt: DateTime.utc(2026, 11, 1),
              ),
            ]);

            expect(
              cardOf(tester, itemName).color,
              lightTheme.colorScheme.surfaceContainerHighest,
            );
          },
        );

        testWidgets(
          "mutes and strikes a claimed item's title for a reader when $claimer claimed it",
          (tester) async {
            await pumpPage(tester, [
              Item(
                id: claimedItemId,
                name: itemName,
                claimedBy: claimedBy,
                claimedAt: DateTime.utc(2026, 11, 1),
              ),
            ]);

            final scheme = lightTheme.colorScheme;
            expect(
              titleOf(tester, itemName).style?.color,
              scheme.onSurfaceVariant,
            );
            expect(
              titleOf(tester, itemName).style?.decoration,
              TextDecoration.lineThrough,
            );
          },
        );

        testWidgets(
          "mutes a claimed item's description for a reader when $claimer claimed it",
          (tester) async {
            const description = 'Handmade ceramic mug';
            await pumpPage(tester, [
              Item(
                id: claimedItemId,
                name: itemName,
                description: description,
                claimedBy: claimedBy,
                claimedAt: DateTime.utc(2026, 11, 1),
              ),
            ]);

            expect(
              tester.widget<Text>(find.text(description)).style?.color,
              lightTheme.colorScheme.onSurfaceVariant,
            );
          },
        );
      }

      testWidgets("leaves an unclaimed item's description un-muted", (
        tester,
      ) async {
        const description = 'Handmade ceramic mug';
        await pumpPage(tester, [
          Item(id: claimedItemId, name: itemName, description: description),
        ]);

        expect(tester.widget<Text>(find.text(description)).style, isNull);
      });

      testWidgets("leaves the owner's description un-muted", (tester) async {
        const description = 'Handmade ceramic mug';
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: itemName,
            description: description,
            claimedBy: otherReaderId,
            claimedAt: DateTime.utc(2026, 11, 1),
          ),
        ], asOwner: true);

        expect(tester.widget<Text>(find.text(description)).style, isNull);
      });

      testWidgets("leaves a reader's unclaimed item unchanged", (tester) async {
        await pumpPage(tester, [Item(id: claimedItemId, name: itemName)]);

        final scheme = lightTheme.colorScheme;
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerLow);
        expect(titleOf(tester, itemName).style?.color, scheme.onSurface);
        expect(
          titleOf(tester, itemName).style?.decoration,
          isNot(TextDecoration.lineThrough),
        );
        expect(find.text('Claim'), findsOneWidget);
      });

      testWidgets('uses the dark palette for a claimed reader item', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: itemName,
            claimedBy: otherReaderId,
            claimedAt: DateTime.utc(2026, 11, 1),
          ),
        ], theme: darkTheme);

        final scheme = darkTheme.colorScheme;
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerHighest);
        expect(titleOf(tester, itemName).style?.color, scheme.onSurfaceVariant);
      });

      testWidgets('renders a claimed card at 320 px without overflowing', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        const longName = 'A very long claimed item name that must wrap cleanly';
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: longName,
            claimedBy: otherReaderId,
            claimedAt: DateTime.utc(2026, 11, 1),
          ),
        ]);

        expect(tester.takeException(), isNull);
      });
    });

    testWidgets("does not restyle the owner's card when claims are revealed", (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claimedBy: otherReaderId,
          claimedAt: DateTime.utc(2026, 11, 1),
        ),
      ], asOwner: true);

      await tester.tap(find.byTooltip('Show claimed status'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Claimed on'), findsOneWidget);
      expect(
        cardOf(tester, itemName).color,
        lightTheme.colorScheme.surfaceContainerLow,
      );
      expect(
        titleOf(tester, itemName).style?.color,
        lightTheme.colorScheme.onSurface,
      );
      expect(
        titleOf(tester, itemName).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );
    });

    testWidgets("does not restyle the owner's card in the spoiler-free view", (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claimedBy: otherReaderId,
          claimedAt: DateTime.utc(2026, 11, 1),
        ),
      ], asOwner: true);

      expect(find.textContaining('Claimed on'), findsNothing);
      expect(
        cardOf(tester, itemName).color,
        lightTheme.colorScheme.surfaceContainerLow,
      );
      expect(
        titleOf(tester, itemName).style?.color,
        lightTheme.colorScheme.onSurface,
      );
      expect(
        titleOf(tester, itemName).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );
    });

    testWidgets('keeps the claim row inside the card at a raised text scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claimedBy: viewerId,
          claimedAt: DateTime.utc(2026, 11, 1),
        ),
      ]);

      expect(
        tester.takeException(),
        isNull,
        reason:
            'the pill and Unclaim must fit a 320 px phone at 1.3 text scale',
      );

      // Overflow is not the only way the label can leave the card: the card
      // clips, so a clipped-but-not-overflowing row would still pass the check
      // above. Bound against the clipping Card, not BrandCard's outer padding,
      // which reserves room for the shadow.
      final pill = find.byType(StatusPill);
      final card = find.descendant(
        of: find.byType(BrandCard),
        matching: find.byType(Card),
      );
      expect(pill, findsOneWidget);
      expect(
        tester.getRect(pill).left,
        greaterThanOrEqualTo(tester.getRect(card).left),
      );
      expect(
        tester.getRect(pill).right,
        lessThanOrEqualTo(tester.getRect(card).right),
      );

      // The shape that makes the fit possible: the action moves below the pill
      // instead of squeezing it, so the label never has to break inside a word.
      final unclaim = find.widgetWithText(TextButton, 'Unclaim');
      expect(
        tester.getRect(unclaim).top,
        greaterThanOrEqualTo(tester.getRect(pill).bottom),
        reason: 'Unclaim should drop below the pill, not squeeze its label',
      );
      expect(find.text('You claimed this!'), findsOneWidget);
    });

    testWidgets('gives the wishlist owner edit and spoiler controls', (
      tester,
    ) async {
      when(
        () => wishlistRepository.streamOne(wishlistId),
      ).thenAnswer((_) => Stream.value(wishlist.copyWith(ownerId: viewerId)));
      await pumpPage(tester, [Item(id: 'item-1', name: itemName)]);

      expect(find.byTooltip('Edit Wishlist'), findsOneWidget);
      expect(find.byTooltip('Show claimed status'), findsOneWidget);
    });

    testWidgets('gives a reader no owner controls in the bar', (tester) async {
      await pumpPage(tester, [Item(id: 'item-1', name: itemName)]);

      expect(find.byTooltip('Edit Wishlist'), findsNothing);
      expect(find.byTooltip('Show claimed status'), findsNothing);
    });

    group('item text selection', () {
      const selectableName = 'Lantern';
      const description = 'Handmade ceramic mug';
      const url = 'https://example.com';

      testWidgets('copies an item name with a long press', (tester) async {
        final calls = recordPlatformCalls();
        await pumpPage(tester, [Item(id: 'item-1', name: selectableName)]);

        await selectAndCopy(tester, find.text(selectableName));

        expect(copiedText(calls), selectableName);
      });

      testWidgets('copies text from the item description', (tester) async {
        final calls = recordPlatformCalls();
        await pumpPage(tester, [
          Item(id: 'item-1', name: selectableName, description: description),
        ]);

        await selectAndCopy(tester, find.text(description));

        final copied = copiedText(calls);
        expect(copied?.trim(), isNotEmpty);
        expect(description, contains(copied!));
      });

      testWidgets('copies text from the item link', (tester) async {
        final calls = recordPlatformCalls();
        await pumpPage(tester, [
          Item(id: 'item-1', name: selectableName, url: url),
        ]);

        await selectAndCopy(tester, find.text(url));

        final copied = copiedText(calls);
        expect(copied?.trim(), isNotEmpty);
        expect(url, contains(copied!));
      });

      testWidgets('selects across the name, link and description at once', (
        tester,
      ) async {
        final calls = recordPlatformCalls();
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: selectableName,
            url: url,
            description: description,
          ),
        ]);

        // Press the first glyph: the name sits in an Expanded, so the
        // paragraph's centre is blank space past the text.
        final nameRect = tester.getRect(find.text(selectableName));
        final gesture = await tester.startGesture(
          nameRect.topLeft + Offset(4, nameRect.height / 2),
        );
        await tester.pump(kLongPressTimeout + kPressTimeout);
        await gesture.moveTo(tester.getCenter(find.text(description)));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(
          find.text('Copy'),
          findsOneWidget,
          reason: 'dragging from the name to the description should select',
        );
        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();

        final copied = copiedText(calls);
        expect(copied, contains(selectableName));
        expect(copied, contains(url));
        expect(copied, contains(description.split(' ').first));
      });

      testWidgets('keeps the claim action out of the selection area', (
        tester,
      ) async {
        final calls = recordPlatformCalls();
        await pumpPage(tester, [Item(id: 'item-1', name: selectableName)]);

        await tester.longPress(find.text('Claim'));
        await tester.pumpAndSettle();

        expect(
          find.ancestor(
            of: find.text('Claim'),
            matching: find.byType(SelectionArea),
          ),
          findsNothing,
        );
        expect(find.text('Copy'), findsNothing);
        expect(copiedText(calls), isNull);
      });

      testWidgets('still scrolls the item list', (tester) async {
        await pumpPage(tester, [
          for (var index = 0; index < 30; index++)
            Item(id: 'item-$index', name: 'Item $index'),
        ]);
        final scrollable = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final before = tester
            .state<ScrollableState>(scrollable)
            .position
            .pixels;

        await tester.drag(find.text('Item 2'), const Offset(0, -300));
        await tester.pumpAndSettle();

        final after = tester.state<ScrollableState>(scrollable).position.pixels;
        expect(after, greaterThan(before));
      });
    });

    testWidgets('renders every item inside a BrandCard at the page margin', (
      tester,
    ) async {
      const secondItemName = 'Floor lamp';
      await pumpPage(tester, [
        Item(id: 'item-1', name: itemName),
        Item(id: 'item-2', name: secondItemName),
      ]);

      for (final name in [itemName, secondItemName]) {
        final card = find.ancestor(
          of: find.text(name),
          matching: find.byType(BrandCard),
        );

        expect(card, findsOneWidget);
        expect(tester.widget<BrandCard>(card).margin, itemMargin);
      }
    });
  });
}
