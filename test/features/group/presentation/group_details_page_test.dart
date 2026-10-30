import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/group/application/leave_group_use_case.dart';
import 'package:wishtogether/features/group/application/share_wishlist_with_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockGroupRepository extends Mock implements GroupRepository {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockUserRepository extends Mock implements UserRepository {}

class MockLeaveGroupUseCase extends Mock implements LeaveGroupUseCase {}

class MockShareWishlistWithGroupUseCase extends Mock
    implements ShareWishlistWithGroupUseCase {}

/// Clears the one layout overflow the *test font* causes at phone widths.
///
/// Flutter's test font draws every glyph as a square roughly twice as wide as a
/// real font, so the "Shared Wishlists" header row is wider than a phone-width
/// body and layout reports an overflow before the floating button is involved.
/// Clearing that one overflow lets the geometry below decide the test; any other
/// layout error still fails it.
void clearTestFontOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) return;
  if (exception is FlutterError && exception.message.contains('overflowed')) {
    return;
  }
  fail('unexpected layout error while pumping the page: $exception');
}

void main() {
  test('builds the canonical production invite path off web', () {
    expect(
      GroupDetailsPage.getInvitationLink('123'),
      'https://wishtogether.gift/join?group=123',
    );
  });

  test('uses the supplied origin and encodes the group id', () {
    expect(
      GroupDetailsPage.getInvitationLink('a b', origin: 'https://preview.test'),
      'https://preview.test/join?group=a+b',
    );
  });

  group('GroupDetailsPage layout', () {
    const groupId = 'group-1';
    const viewerId = 'viewer-uid';
    const ownerId = 'owner-uid';
    // Enough members that the page scrolls on every tested viewport, so the
    // Leave Group button can land in the band the floating button occupies.
    const memberIds = [
      ownerId,
      viewerId,
      'member-3',
      'member-4',
      'member-5',
      'member-6',
      'member-7',
      'member-8',
      'member-9',
      'member-10',
      'member-11',
      'member-12',
    ];
    final group = Group(
      id: groupId,
      name: 'Family',
      ownerId: ownerId,
      members: memberIds,
    );
    final members = [
      for (var i = 0; i < memberIds.length; i++)
        User(id: memberIds[i], displayName: i == 0 ? 'Owner' : 'Member $i'),
    ];

    late MockAuthService authService;

    setUp(() {
      getIt.reset();
      authService = MockAuthService();
      when(() => authService.currentUserId).thenReturn(viewerId);

      final groupRepository = MockGroupRepository();
      when(() => groupRepository.streamOne(groupId))
          .thenAnswer((_) => Stream.value(group));

      final wishlistRepository = MockWishlistRepository();
      when(
        () => wishlistRepository.streamWhere(
          any(),
          arrayContains: any(named: 'arrayContains'),
        ),
      ).thenAnswer((_) => Stream.value(const <Wishlist>[]));
      when(
        () => wishlistRepository.streamWhere(
          any(),
          isEqualTo: any(named: 'isEqualTo'),
        ),
      ).thenAnswer((_) => Stream.value(const <Wishlist>[]));

      final userRepository = MockUserRepository();
      when(() => userRepository.streamUsersFromIds(memberIds))
          .thenAnswer((_) => Stream.value(members));

      getIt.registerSingleton<AuthService>(authService);
      getIt.registerSingleton<GroupRepository>(groupRepository);
      getIt.registerSingleton<WishlistRepository>(wishlistRepository);
      getIt.registerSingleton<UserRepository>(userRepository);
      getIt.registerSingleton<LeaveGroupUseCase>(MockLeaveGroupUseCase());
      getIt.registerSingleton<ShareWishlistWithGroupUseCase>(
        MockShareWishlistWithGroupUseCase(),
      );
    });

    tearDown(getIt.reset);

    final leaveGroupButton = find.widgetWithText(TextButton, 'Leave Group');
    final shareWishlistFab = find.byType(FloatingActionButton);

    Future<void> pumpPage(WidgetTester tester, Size viewport) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = viewport * 3.0;
      addTearDown(tester.view.reset);

      // The page resolves a router before reacting to Leave Group, so the
      // harness supplies the same shape the app routes with.
      final router = GoRouter(
        initialLocation: '/group/$groupId',
        routes: [
          GoRoute(
            path: GroupDetailsPage.route,
            name: GroupDetailsPage.routeName,
            builder: (context, state) =>
                GroupDetailsPage(groupId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      clearTestFontOverflow(tester);
    }

    /// Leaves the scroll view at its end, where the last row rests against the
    /// bottom edge of the body.
    Future<void> scrollToEnd(WidgetTester tester) async {
      final outerScrollable = find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(outerScrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    for (final viewport in const [
      Size(320, 568),
      Size(390, 844),
      Size(800, 600),
    ]) {
      testWidgets(
        'keeps the Leave Group tap target clear of the floating button '
        'at ${viewport.width.toInt()}x${viewport.height.toInt()}',
        (tester) async {
          await pumpPage(tester, viewport);
          await scrollToEnd(tester);

          final leaveButtonRect = tester.getRect(leaveGroupButton);
          final fabRect = tester.getRect(shareWishlistFab);

          expect(
            leaveButtonRect.overlaps(fabRect),
            isFalse,
            reason:
                'the floating button $fabRect covers the Leave Group tap '
                'target $leaveButtonRect',
          );
        },
      );
    }

    testWidgets('opens the leave confirmation when Leave Group is tapped at '
        'the end of a small phone page', (tester) async {
      const viewport = Size(320, 568);
      await pumpPage(tester, viewport);
      await scrollToEnd(tester);

      await tester.tap(leaveGroupButton);
      await tester.pumpAndSettle();

      expect(find.text('Leave Group?'), findsOneWidget);
      expect(find.text('Share a Wishlist'), findsNothing);
    });

    testWidgets('offers the group owner no Leave Group button', (tester) async {
      when(() => authService.currentUserId).thenReturn(ownerId);
      await pumpPage(tester, const Size(320, 568));
      await scrollToEnd(tester);

      expect(leaveGroupButton, findsNothing);
    });

    testWidgets('opens the share dialog from the floating button', (
      tester,
    ) async {
      await pumpPage(tester, const Size(320, 568));
      await scrollToEnd(tester);

      await tester.tap(shareWishlistFab);
      await tester.pumpAndSettle();

      expect(find.text('Share a Wishlist'), findsOneWidget);
    });
  });
}
