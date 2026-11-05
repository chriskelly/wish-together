import 'package:flutter/material.dart';
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
    Future<void> pumpPage(WidgetTester tester, List<Item> items) async {
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => Stream.value(items));

      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: const WishlistDetailsPage(wishlistId: wishlistId),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The margin the page gives every item row.
    const itemMargin = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);

    StatusPillTone toneOf(WidgetTester tester, String label) =>
        tester.widget<StatusPill>(find.widgetWithText(StatusPill, label)).tone;

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

        final row = find.ancestor(of: pill, matching: find.byType(Row)).first;
        final unclaim = find.descendant(
          of: row,
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
      expect(find.text('You claimed this!'), findsOneWidget);
      expect(find.text('Unclaim'), findsOneWidget);
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
