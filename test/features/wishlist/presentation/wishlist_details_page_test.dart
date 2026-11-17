import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/common/widgets/status_pill.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/core/theme.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/clear_stale_claims_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';
import 'package:wishtogether/features/wishlist/presentation/stale_claims_banner.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_details_page.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_item_row.dart';

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockItemRepository extends Mock implements ItemRepository {}

class MockClaimItemUseCase extends Mock implements ClaimItemUseCase {}

class MockUnclaimItemUseCase extends Mock implements UnclaimItemUseCase {}

class MockClearStaleClaimsUseCase extends Mock
    implements ClearStaleClaimsUseCase {}

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
    final fixedNow = DateTime.utc(2026, 11, 16, 12);
    final staleClaimAt = fixedNow.subtract(const Duration(days: 200));
    final recentClaimAt = fixedNow.subtract(const Duration(days: 30));

    late MockWishlistRepository wishlistRepository;
    late MockItemRepository itemRepository;
    late MockClaimItemUseCase claimItemUseCase;
    late MockUnclaimItemUseCase unclaimItemUseCase;
    late MockClearStaleClaimsUseCase clearStaleClaimsUseCase;
    late MockAuthSession authSession;

    setUpAll(() {
      registerFallbackValue(StaleClaimsPlan.empty);
    });

    setUp(() {
      wishlistRepository = MockWishlistRepository();
      when(() => wishlistRepository.streamOne(wishlistId))
          .thenAnswer((_) => Stream.value(wishlist));

      itemRepository = MockItemRepository();

      authSession = MockAuthSession();
      when(() => authSession.currentUserId).thenReturn(viewerId);

      claimItemUseCase = MockClaimItemUseCase();
      unclaimItemUseCase = MockUnclaimItemUseCase();
      clearStaleClaimsUseCase = MockClearStaleClaimsUseCase();
      when(() => clearStaleClaimsUseCase.execute(any(), any()))
          .thenAnswer((_) async {});
    });

    /// Pumps the page for an item stream that has already emitted [items].
    Future<void> pumpPage(
      WidgetTester tester,
      List<Item> items, {
      ThemeData? theme,
      bool asOwner = false,
      DateTime? now,
      Stream<List<Item>>? itemStream,
    }) async {
      if (asOwner) {
        when(
          () => wishlistRepository.streamOne(wishlistId),
        ).thenAnswer((_) => Stream.value(wishlist.copyWith(ownerId: viewerId)));
      }
      when(() => itemRepository.streamAll())
          .thenAnswer((_) => itemStream ?? Stream.value(items));

      await tester.pumpWidget(
        ProviderScope(
          retry: disableAutomaticRetry,
          overrides: [
            wishlistRepositoryProvider.overrideWithValue(wishlistRepository),
            itemRepositoryProvider(wishlistId)
                .overrideWithValue(itemRepository),
            authSessionProvider.overrideWithValue(authSession),
            claimItemUseCaseProvider.overrideWithValue(claimItemUseCase),
            unclaimItemUseCaseProvider.overrideWithValue(unclaimItemUseCase),
            clearStaleClaimsUseCaseProvider.overrideWithValue(
              clearStaleClaimsUseCase,
            ),
            wishlistNowProvider.overrideWithValue(now ?? fixedNow),
          ],
          child: MaterialApp(
            theme: theme ?? lightTheme,
            home: const WishlistDetailsPage(wishlistId: wishlistId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Pins a phone-sized viewport, with an optional system text scale and
    /// bottom safe-area inset. The tear-downs restore the view metrics and the
    /// text scale.
    void useViewport(
      WidgetTester tester,
      Size size, {
      double textScale = 1.0,
      double bottomInset = 0,
    }) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      if (bottomInset > 0) {
        final padding = FakeViewPadding(bottom: bottomInset);
        tester.view.padding = padding;
        tester.view.viewPadding = padding;
      }
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    /// A 320 px phone at 1.3 text scale: the narrowest layout the review
    /// requires the claim rows to fit.
    void useNarrowPhone(WidgetTester tester) =>
        useViewport(tester, const Size(320, 640), textScale: 1.3);

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

    /// The card's content sits 16 px inside its edge.
    void expectRightAligned(WidgetTester tester, Finder finder) {
      final card = tester.getRect(
        find.descendant(
          of: find.byType(BrandCard),
          matching: find.byType(Card),
        ),
      );
      expect(tester.getRect(finder).right, closeTo(card.right - 16, 1.5));
    }

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
            claims: <String, DateTime>{viewerId: DateTime.utc(2026, 11, 1)},
            claimLimit: 1,
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

    testWidgets('explains a signed-out unclaim instead of printing the error', (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claims: <String, DateTime>{viewerId: DateTime.utc(2026, 11, 1)},
          claimLimit: 1,
        ),
      ]);
      when(() => unclaimItemUseCase.execute(wishlistId, 'item-1')).thenThrow(
        const ClaimFailure(
          ClaimFailureReason.signedOut,
          code: unauthenticatedCode,
        ),
      );

      await tester.tap(find.text('Unclaim'));
      await tester.pumpAndSettle();

      expect(find.text('Please sign in again to claim items.'), findsOneWidget);
      expect(find.textContaining('ClaimFailure'), findsNothing);
    });

    testWidgets('shows the full-item copy when a claim is refused', (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(id: 'item-1', name: itemName, claimLimit: 1),
      ]);
      when(() => claimItemUseCase.execute(wishlistId, 'item-1'))
          .thenThrow(const ClaimFailure(ClaimFailureReason.fullyClaimed));

      await tester.tap(find.text('Claim'));
      await tester.pumpAndSettle();

      expect(find.text('This item is no longer available.'), findsOneWidget);
      expect(find.textContaining('ClaimFailure'), findsNothing);
    });

    testWidgets('shows a full single-claim item as Unavailable', (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claims: <String, DateTime>{otherReaderId: DateTime.utc(2026, 11, 1)},
          claimLimit: 1,
        ),
      ]);

      expect(find.text('Unavailable'), findsOneWidget);
      expect(toneOf(tester, 'Unavailable'), StatusPillTone.neutral);
      // Only the claimer may clear a claim, so offering either action here
      // would surface a denial for a tap the viewer cannot win.
      expect(find.text('Claim'), findsNothing);
      expect(find.text('Unclaim'), findsNothing);
      // A single-claim row never carries a count.
      expect(find.textContaining('of 1 claimed'), findsNothing);
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
                claims: <String, DateTime>{
                  claimedBy: DateTime.utc(2026, 11, 1),
                },
                claimLimit: 1,
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
                claims: <String, DateTime>{
                  claimedBy: DateTime.utc(2026, 11, 1),
                },
                claimLimit: 1,
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
                claims: <String, DateTime>{
                  claimedBy: DateTime.utc(2026, 11, 1),
                },
                claimLimit: 1,
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
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
            },
            claimLimit: 1,
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

      testWidgets('leaves a partially claimed multi-claim card available', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: itemName,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
            },
            claimLimit: 3,
          ),
        ]);

        final scheme = lightTheme.colorScheme;
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerLow);
        expect(titleOf(tester, itemName).style?.color, scheme.onSurface);
        expect(
          titleOf(tester, itemName).style?.decoration,
          isNot(TextDecoration.lineThrough),
        );
        expect(find.text('Claim'), findsOneWidget);
        expect(find.text('1 of 3 claimed'), findsOneWidget);
        expect(find.byType(StatusPill), findsNothing);
      });

      testWidgets('uses the dark palette for a claimed reader item', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: itemName,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
            },
            claimLimit: 1,
          ),
        ], theme: darkTheme);

        final scheme = darkTheme.colorScheme;
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerHighest);
        expect(titleOf(tester, itemName).style?.color, scheme.onSurfaceVariant);
      });

      testWidgets('renders a claimed card at 320 px without overflowing', (
        tester,
      ) async {
        useNarrowPhone(tester);

        const longName = 'A very long claimed item name that must wrap cleanly';
        await pumpPage(tester, [
          Item(
            id: claimedItemId,
            name: longName,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
            },
            claimLimit: 1,
          ),
        ]);

        expect(tester.takeException(), isNull);
      });
    });

    group('owner claim limit and status', () {
      Future<void> reveal(WidgetTester tester) async {
        await tester.tap(find.byTooltip('Show claimed status'));
        await tester.pumpAndSettle();
      }

      testWidgets('shows the unlimited limit while spoiler-free', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 0),
        ], asOwner: true);

        expect(find.text('Unlimited claims'), findsOneWidget);
        expect(find.text('No claims yet'), findsNothing);
      });

      testWidgets('shows the single limit while spoiler-free', (tester) async {
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 1),
        ], asOwner: true);

        expect(find.text('1 person can claim'), findsOneWidget);
      });

      testWidgets('shows the finite limit while spoiler-free', (tester) async {
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 3),
        ], asOwner: true);

        expect(find.text('3 people can claim'), findsOneWidget);
      });

      testWidgets('shows No claims yet for an unlimited item with no claims', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 0),
        ], asOwner: true);

        await reveal(tester);

        expect(find.text('No claims yet'), findsOneWidget);
      });

      testWidgets('shows the unlimited claim count when revealed', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 0,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
              'third-reader-uid': DateTime.utc(2026, 11, 2),
            },
          ),
        ], asOwner: true);

        await reveal(tester);

        expect(find.text('2 claimed'), findsOneWidget);
      });

      testWidgets(
        'shows No claims yet for a finite multi item with no claims',
        (tester) async {
          await pumpPage(tester, [
            Item(id: 'item-1', name: itemName, claimLimit: 3),
          ], asOwner: true);

          await reveal(tester);

          expect(find.text('No claims yet'), findsOneWidget);
        },
      );

      testWidgets('shows the finite multi claim count when revealed', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 3,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
              'third-reader-uid': DateTime.utc(2026, 11, 2),
            },
          ),
        ], asOwner: true);

        await reveal(tester);

        expect(find.text('2 of 3 claimed'), findsOneWidget);
      });

      testWidgets(
        'shows Available for an unclaimed single item when revealed',
        (tester) async {
          await pumpPage(tester, [
            Item(id: 'item-1', name: itemName, claimLimit: 1),
          ], asOwner: true);

          await reveal(tester);

          expect(find.text('Available'), findsOneWidget);
        },
      );
    });

    group('reader multi-claim rows', () {
      testWidgets('shows a full multi item as Unavailable without a count', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 2,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
              'third-reader-uid': DateTime.utc(2026, 11, 2),
            },
          ),
        ]);

        final scheme = lightTheme.colorScheme;
        expect(find.text('Unavailable'), findsOneWidget);
        expect(find.textContaining('of 2 claimed'), findsNothing);
        expect(find.text('Claim'), findsNothing);
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerHighest);
        expect(
          titleOf(tester, itemName).style?.decoration,
          TextDecoration.lineThrough,
        );
        expectRightAligned(tester, find.byType(StatusPill));
      });

      testWidgets("shows the viewer's multi claim count beside Unclaim", (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 4,
            claims: <String, DateTime>{
              viewerId: DateTime.utc(2026, 11, 1),
              otherReaderId: DateTime.utc(2026, 11, 2),
            },
          ),
        ]);

        final scheme = lightTheme.colorScheme;
        expect(find.text('2 of 4 claimed'), findsOneWidget);
        expect(toneOf(tester, 'You claimed this!'), StatusPillTone.accent);
        expect(find.text('Unclaim'), findsOneWidget);
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerHighest);
        expect(
          titleOf(tester, itemName).style?.decoration,
          TextDecoration.lineThrough,
        );
      });

      testWidgets('keeps Unclaim on a full item the viewer claimed', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 2,
            claims: <String, DateTime>{
              viewerId: DateTime.utc(2026, 11, 1),
              otherReaderId: DateTime.utc(2026, 11, 2),
            },
          ),
        ]);

        final scheme = lightTheme.colorScheme;
        expect(find.text('2 of 2 claimed'), findsOneWidget);
        expect(toneOf(tester, 'You claimed this!'), StatusPillTone.accent);
        expect(find.text('Unclaim'), findsOneWidget);
        expect(find.text('Unavailable'), findsNothing);
        expect(cardOf(tester, itemName).color, scheme.surfaceContainerHighest);
        expect(
          titleOf(tester, itemName).style?.decoration,
          TextDecoration.lineThrough,
        );
      });

      testWidgets('shows an unlimited claim count beside Claim', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 0,
            claims: <String, DateTime>{
              otherReaderId: DateTime.utc(2026, 11, 1),
              'third-reader-uid': DateTime.utc(2026, 11, 2),
              'fourth-reader-uid': DateTime.utc(2026, 11, 3),
            },
          ),
        ]);

        expect(find.text('3 claimed'), findsOneWidget);
        expect(find.text('Claim'), findsOneWidget);
        expect(find.byType(StatusPill), findsNothing);
      });

      testWidgets('shows No claims yet for an unlimited item with no claims', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 0),
        ]);

        expect(find.text('No claims yet'), findsOneWidget);
        expect(find.text('Claim'), findsOneWidget);
      });

      testWidgets('fits the widest claim row at a raised text scale', (
        tester,
      ) async {
        useNarrowPhone(tester);

        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claimLimit: 4,
            claims: <String, DateTime>{
              viewerId: DateTime.utc(2026, 11, 1),
              otherReaderId: DateTime.utc(2026, 11, 2),
            },
          ),
        ]);

        expect(tester.takeException(), isNull);
        expect(find.text('2 of 4 claimed'), findsOneWidget);
        expect(find.text('You claimed this!'), findsOneWidget);
        expect(find.text('Unclaim'), findsOneWidget);
        expectRightAligned(
          tester,
          find
              .ancestor(
                of: find.text('You claimed this!'),
                matching: find.byType(Wrap),
              )
              .first,
        );
      });

      testWidgets(
        'fits a partial multi count and Claim at a raised text scale',
        (tester) async {
          useNarrowPhone(tester);

          await pumpPage(tester, [
            Item(
              id: 'item-1',
              name: itemName,
              claimLimit: 3,
              claims: <String, DateTime>{
                otherReaderId: DateTime.utc(2026, 11, 1),
              },
            ),
          ]);

          expect(tester.takeException(), isNull);
          expect(find.text('1 of 3 claimed'), findsOneWidget);
          expect(find.text('Claim'), findsOneWidget);
          expectRightAligned(
            tester,
            find
                .ancestor(of: find.text('Claim'), matching: find.byType(Wrap))
                .first,
          );
        },
      );

      testWidgets('fits the owner limit label at a raised text scale', (
        tester,
      ) async {
        useNarrowPhone(tester);

        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName, claimLimit: 0),
        ], asOwner: true);

        expect(tester.takeException(), isNull);
        expect(find.text('Unlimited claims'), findsOneWidget);
      });
    });

    testWidgets("does not restyle the owner's card when claims are revealed", (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claims: <String, DateTime>{otherReaderId: DateTime.utc(2026, 11, 1)},
          claimLimit: 1,
        ),
      ], asOwner: true);

      await tester.tap(find.byTooltip('Show claimed status'));
      await tester.pumpAndSettle();

      expect(find.text('Claimed'), findsOneWidget);
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

    testWidgets("does not restyle the owner's card in the spoiler-free view", (
      tester,
    ) async {
      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claims: <String, DateTime>{otherReaderId: DateTime.utc(2026, 11, 1)},
          claimLimit: 1,
        ),
      ], asOwner: true);

      expect(find.text('Claimed'), findsNothing);
      expect(find.text('Available'), findsNothing);
      expect(find.text('1 person can claim'), findsOneWidget);
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
      useNarrowPhone(tester);

      await pumpPage(tester, [
        Item(
          id: 'item-1',
          name: itemName,
          claims: <String, DateTime>{viewerId: DateTime.utc(2026, 11, 1)},
          claimLimit: 1,
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

    group('FAB clearance', () {
      /// A standard iPhone: 393 x 852 with a 34 px home-indicator inset. The
      /// inset matters because the Scaffold body runs to the physical bottom
      /// while the add button sits above the safe area.
      void usePhone(WidgetTester tester) =>
          useViewport(tester, const Size(393, 852), bottomInset: 34);

      /// Leaves the item list at its end, where the last row rests against the
      /// bottom padding. Fails rather than silently passing if the list is too
      /// short to scroll.
      Future<void> scrollToEnd(WidgetTester tester) async {
        final scrollable = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'the end-of-list case needs a list that scrolls',
        );
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
      }

      /// Six rows are enough to need scrolling on this phone; the last row is
      /// the one the add button used to cover.
      List<Item> scrollingItems() => [
        for (var index = 0; index < 6; index++)
          Item(id: 'item-$index', name: 'Item $index'),
      ];
      const lastItemName = 'Item 5';

      /// The delete action of the row named [name], not merely the last button
      /// in the tree: a row that did not build must not stand in for the last.
      Finder deleteButtonOf(String name) => find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(WishlistItemRow),
        ),
        matching: find.widgetWithIcon(IconButton, Icons.delete_outline),
      );

      void expectClearOfTheAddButton(WidgetTester tester, Finder deleteButton) {
        final deleteRect = tester.getRect(deleteButton);
        final fabRect = tester.getRect(find.byType(FloatingActionButton));

        expect(
          deleteRect.overlaps(fabRect),
          isFalse,
          reason:
              'the add button $fabRect covers the delete button $deleteRect',
        );
      }

      testWidgets(
        "keeps the last row's delete button clear of the add button at the "
        'end of a list that scrolls',
        (tester) async {
          usePhone(tester);
          await pumpPage(tester, scrollingItems(), asOwner: true);

          await scrollToEnd(tester);

          expectClearOfTheAddButton(tester, deleteButtonOf(lastItemName));
        },
      );

      testWidgets(
        "keeps the last row's delete button clear of the add button at the "
        '320 px review size',
        (tester) async {
          useViewport(
            tester,
            const Size(320, 640),
            textScale: 1.3,
            bottomInset: 34,
          );
          await pumpPage(tester, scrollingItems(), asOwner: true);

          // At this width the wrapped status label lifts the action row, so
          // this case guards the narrow layout; the phone case above is the
          // one that reproduces the overlap.
          await scrollToEnd(tester);

          expectClearOfTheAddButton(tester, deleteButtonOf(lastItemName));
        },
      );

      testWidgets("leaves a single-row list clear of the add button", (
        tester,
      ) async {
        usePhone(tester);
        await pumpPage(tester, [
          Item(id: 'item-1', name: itemName),
        ], asOwner: true);

        // The row sits near the top, so this cannot reproduce the overlap;
        // it pins the ticket's short-list edge case.
        expectClearOfTheAddButton(tester, deleteButtonOf(itemName));
      });

      testWidgets('opens the delete confirmation from the last row', (
        tester,
      ) async {
        usePhone(tester);
        await pumpPage(tester, scrollingItems(), asOwner: true);
        await scrollToEnd(tester);

        final deleteButton = deleteButtonOf(lastItemName);
        expect(
          deleteButton.hitTestable(),
          findsOneWidget,
          reason: 'the add button must not take the delete button taps',
        );
        await tester.tap(deleteButton);
        await tester.pumpAndSettle();

        expect(find.text('Delete Item?'), findsOneWidget);
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

    group('stale claims banner', () {
      Item staleItem() => Item(
        id: 'item-1',
        name: itemName,
        claims: {'old-reader': staleClaimAt},
      );

      Finder bannerButton() => find.descendant(
        of: find.byType(StaleClaimsBanner),
        matching: find.byType(TextButton),
      );

      Finder dialogConfirm() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Clear old claims'),
      );

      Future<void> confirmClear(WidgetTester tester) async {
        await tester.tap(bannerButton());
        await tester.pumpAndSettle();
        await tester.tap(dialogConfirm());
        await tester.pumpAndSettle();
      }

      testWidgets(
        'shows the old-claims banner to the owner in the default spoiler-free view',
        (tester) async {
          await pumpPage(tester, [staleItem()], asOwner: true);

          expect(
            find.text('You have claim(s) older than 6 months.'),
            findsOneWidget,
          );
          expect(find.text('Clear old claims'), findsOneWidget);
          expect(bannerButton(), findsOneWidget);
          expect(find.text('1 person can claim'), findsOneWidget);
          expect(find.text('Claimed'), findsNothing);
        },
      );

      testWidgets('hides the old-claims banner from a reader', (tester) async {
        await pumpPage(tester, [staleItem()]);

        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsNothing,
        );
        expect(bannerButton(), findsNothing);
      });

      testWidgets('hides the old-claims banner when every claim is recent', (
        tester,
      ) async {
        await pumpPage(tester, [
          Item(
            id: 'item-1',
            name: itemName,
            claims: {'recent-reader': recentClaimAt},
          ),
        ], asOwner: true);

        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsNothing,
        );
      });

      testWidgets('shows the banner when the owner reveals claims', (
        tester,
      ) async {
        await pumpPage(tester, [staleItem()], asOwner: true);

        await tester.tap(find.byTooltip('Show claimed status'));
        await tester.pumpAndSettle();

        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsOneWidget,
        );
        expect(bannerButton(), findsOneWidget);
        expect(find.text('Claimed'), findsOneWidget);
      });

      testWidgets('uses the injected clock to decide staleness', (
        tester,
      ) async {
        final claimAt = fixedNow.subtract(const Duration(days: 100));
        final item = Item(
          id: 'item-1',
          name: itemName,
          claims: {'reader': claimAt},
        );

        await pumpPage(tester, [item], asOwner: true);
        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsNothing,
        );

        await pumpPage(
          tester,
          [item],
          asOwner: true,
          now: fixedNow.add(const Duration(days: 100)),
        );
        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsOneWidget,
        );
      });

      testWidgets(
        'hides the old-claims banner when the item stream is in error',
        (tester) async {
          final items = StreamController<List<Item>>();
          addTearDown(items.close);
          items.add([staleItem()]);

          await pumpPage(
            tester,
            const [],
            asOwner: true,
            itemStream: items.stream,
          );
          items.addError(Exception('the item read failed'));
          await tester.pumpAndSettle();

          expect(
            find.text('You have claim(s) older than 6 months.'),
            findsNothing,
          );
          expect(find.textContaining('An error occurred'), findsOneWidget);
        },
      );

      testWidgets(
        'the old-claims banner fits a 320 px phone at 1.3 text scale',
        (tester) async {
          useNarrowPhone(tester);
          await pumpPage(tester, [staleItem()], asOwner: true);

          expect(
            find.text('You have claim(s) older than 6 months.'),
            findsOneWidget,
          );
          expect(bannerButton(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'clearing old claims asks for confirmation and passes the plan',
        (tester) async {
          await pumpPage(tester, [staleItem()], asOwner: true);

          await tester.tap(bannerButton());
          await tester.pumpAndSettle();

          expect(find.text('Clear old claims?'), findsOneWidget);
          expect(
            find.text(
              'This removes any item claims older than 6 months. '
              "Claims made in the last 6 months are kept. This can't be undone.",
            ),
            findsOneWidget,
          );

          await tester.tap(dialogConfirm());
          await tester.pumpAndSettle();

          final captured =
              verify(
                    () => clearStaleClaimsUseCase.execute(
                      wishlistId,
                      captureAny(),
                    ),
                  ).captured.single
                  as StaleClaimsPlan;
          expect(captured.byItem, {
            'item-1': {'old-reader'},
          });
          expect(find.text('Old claims cleared.'), findsOneWidget);
        },
      );

      testWidgets('cancelling the confirmation leaves the claims alone', (
        tester,
      ) async {
        await pumpPage(tester, [staleItem()], asOwner: true);

        await tester.tap(bannerButton());
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();

        verifyNever(() => clearStaleClaimsUseCase.execute(any(), any()));
      });

      testWidgets('shows the partial copy when a write fails', (tester) async {
        when(() => clearStaleClaimsUseCase.execute(any(), any())).thenThrow(
          const ClaimFailure(
            ClaimFailureReason.accessDenied,
            code: 'permission-denied',
          ),
        );
        await pumpPage(tester, [staleItem()], asOwner: true);

        await confirmClear(tester);

        expect(
          find.text(
            "Not all old claims were cleared. You don't have permission to "
            'clear these claims.',
          ),
          findsOneWidget,
        );
        expect(find.text('Old claims cleared.'), findsNothing);
        expect(tester.widget<TextButton>(bannerButton()).onPressed, isNotNull);

        await confirmClear(tester);
        verify(() => clearStaleClaimsUseCase.execute(any(), any())).called(2);
      });

      testWidgets(
        'shows the generic partial copy when the use case throws unexpectedly',
        (tester) async {
          when(() => clearStaleClaimsUseCase.execute(any(), any()))
              .thenThrow(Exception('boom'));
          await pumpPage(tester, [staleItem()], asOwner: true);

          await confirmClear(tester);

          expect(
            find.text('Not all old claims were cleared. Please try again.'),
            findsOneWidget,
          );
          expect(find.textContaining('boom'), findsNothing);
        },
      );

      testWidgets('disables the clear button while the action runs', (
        tester,
      ) async {
        final pending = Completer<void>();
        when(() => clearStaleClaimsUseCase.execute(any(), any()))
            .thenAnswer((_) => pending.future);
        await pumpPage(tester, [staleItem()], asOwner: true);

        await tester.tap(bannerButton());
        await tester.pumpAndSettle();
        await tester.tap(dialogConfirm());
        await tester.pump();

        expect(find.byType(ButtonLoadingIndicator), findsOneWidget);
        expect(tester.widget<TextButton>(bannerButton()).onPressed, isNull);

        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('Old claims cleared.'), findsOneWidget);
      });

      testWidgets('blocks row actions while the bulk clear runs', (
        tester,
      ) async {
        final pending = Completer<void>();
        when(() => clearStaleClaimsUseCase.execute(any(), any()))
            .thenAnswer((_) => pending.future);
        await pumpPage(tester, [staleItem()], asOwner: true);

        await tester.tap(bannerButton());
        await tester.pumpAndSettle();
        await tester.tap(dialogConfirm());
        await tester.pump();

        await tester.tap(find.byTooltip('Delete'), warnIfMissed: false);
        await tester.pump();
        expect(find.text('Delete Item?'), findsNothing);

        pending.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('keeps the success snackbar after the banner unmounts', (
        tester,
      ) async {
        final pending = Completer<void>();
        when(() => clearStaleClaimsUseCase.execute(any(), any()))
            .thenAnswer((_) => pending.future);
        final items = StreamController<List<Item>>();
        addTearDown(items.close);
        items.add([staleItem()]);

        await pumpPage(
          tester,
          const [],
          asOwner: true,
          itemStream: items.stream,
        );

        await tester.tap(bannerButton());
        await tester.pumpAndSettle();
        await tester.tap(dialogConfirm());
        await tester.pump();

        items.add([Item(id: 'item-1', name: itemName)]);
        await tester.pump();
        expect(
          find.text('You have claim(s) older than 6 months.'),
          findsNothing,
        );

        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('Old claims cleared.'), findsOneWidget);
      });
    });
  });
}
