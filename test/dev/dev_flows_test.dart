import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/main.dart';

/// The signed-in flows, driven through the dev app: the real widgets, use
/// cases and repositories, with only the store in memory.
///
/// Each test asserts the state change the interaction is supposed to cause, not
/// only that the screen rendered. That is the property a dev session exists for:
/// an agent presses the button, then reads what happened.
void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  /// Pumps a fixed number of frames so asynchronous stream emissions land.
  ///
  /// `pumpAndSettle` cannot be used: the pages show a progress indicator while
  /// their first snapshot is in flight, and its animation never settles.
  Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Builds the dev app for [fixture] and pumps it.
  Future<WishTogetherApp> pumpApp(
    WidgetTester tester, {
    DevFixture? fixture,
  }) async {
    final app = await buildDevApp(fixture ?? defaultFixture);
    await tester.pumpWidget(app);
    await pumpFrames(tester);
    return app;
  }

  /// Navigates the mounted app and lets the destination load.
  Future<void> go(
    WidgetTester tester,
    WishTogetherApp app,
    String location,
  ) async {
    app.router.go(location);
    await pumpFrames(tester);
  }

  /// A fixture whose group belongs to somebody else, so the viewer may leave it.
  DevFixture groupOwnedByAnother() => DevFixture(
    id: 'leave-group',
    viewerUid: 'dev-u1',
    documents: <String, Map<String, dynamic>>{
      'users/dev-u1': <String, dynamic>{'displayName': 'Ana Dev'},
      'users/dev-u2': <String, dynamic>{'displayName': 'Ben Dev'},
      'groups/dev-g2': <String, dynamic>{
        'name': 'Book club',
        'ownerId': 'dev-u2',
        'members': <String>['dev-u1', 'dev-u2'],
      },
    },
  );

  /// A fixture with a wishlist whose fields cannot be projected, to make a read
  /// fail the way a bad fixture would.
  DevFixture unreadableWishlist() => DevFixture(
    id: 'unreadable',
    viewerUid: 'dev-u1',
    documents: <String, Map<String, dynamic>>{
      'users/dev-u1': <String, dynamic>{'displayName': 'Ana Dev'},
      'wishlists/broken': <String, dynamic>{
        'name': 'Broken',
        'ownerId': 'dev-u1',
        'sharedWithGroups': 'not-a-list',
      },
    },
  );

  /// A fixture with an invitation the viewer has not accepted yet.
  DevFixture openInvitation() => DevFixture(
    id: 'invitation',
    viewerUid: 'dev-u1',
    documents: <String, Map<String, dynamic>>{
      'users/dev-u1': <String, dynamic>{'displayName': 'Ana Dev'},
      'users/dev-u2': <String, dynamic>{'displayName': 'Ben Dev'},
      'groups/dev-g3': <String, dynamic>{
        'name': 'Neighbours',
        'ownerId': 'dev-u2',
        'members': <String>['dev-u2'],
      },
    },
  );

  testWidgets('adds an item and shows it in the wishlist', (tester) async {
    // ARRANGE
    const added = 'Wool socks';
    final app = await pumpApp(tester);
    await go(tester, app, '/wishlist/dev-l1');

    // ACT: the FAB, the real form, the use case and the repository.
    await tester.tap(find.byTooltip('Add item'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextFormField).first, added);
    await tester.tap(find.text('Save Item'));
    await pumpFrames(tester);

    // ASSERT: the new item is rendered, and the seeded ones are still there.
    expect(find.text(added), findsOneWidget);
    expect(find.text('Board game'), findsOneWidget);
  });

  testWidgets('edits an item and shows the new name', (tester) async {
    // ARRANGE: one seeded item, addressed by the name its card renders.
    const renamed = 'Espresso grinder';
    final app = await pumpApp(tester);
    await go(tester, app, '/wishlist/dev-l1');
    final card = find.ancestor(
      of: find.text('Coffee grinder'),
      matching: find.byType(Card),
    );

    // ACT
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Edit')),
    );
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextFormField).first, renamed);
    await tester.tap(find.text('Update Item'));
    await pumpFrames(tester);

    // ASSERT
    expect(find.text(renamed), findsOneWidget);
    expect(find.text('Coffee grinder'), findsNothing);
  });

  testWidgets('claims an item and unclaims it again', (tester) async {
    // ARRANGE: a wishlist somebody else owns, shared with the viewer's group,
    // which is the only way an item is claimable.
    final app = await pumpApp(tester);
    await go(tester, app, '/wishlist/dev-l3');

    // ACT
    await tester.tap(find.text('Claim'));
    await pumpFrames(tester);

    // ASSERT: the claim is rendered for the reader who made it.
    expect(find.text('You claimed this!'), findsOneWidget);

    // ACT
    await tester.tap(find.text('Unclaim'));
    await pumpFrames(tester);

    // ASSERT: both fields are cleared, so the item is claimable again.
    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('You claimed this!'), findsNothing);
  });

  testWidgets('deletes a wishlist and removes it from home', (tester) async {
    // ARRANGE
    await pumpApp(tester);
    final tile = find.ancestor(
      of: find.text('Birthday list'),
      matching: find.byType(Card),
    );

    // ACT: the tile's own delete action, then the confirmation.
    await tester.tap(
      find.descendant(of: tile, matching: find.byTooltip('Delete Wishlist')),
    );
    await pumpFrames(tester);
    await tester.tap(find.text('Delete'));
    await pumpFrames(tester);

    // ASSERT: only the deleted wishlist is gone.
    expect(find.text('Birthday list'), findsNothing);
    expect(find.text('Christmas list'), findsOneWidget);
  });

  testWidgets('creates a group and shows it on home', (tester) async {
    // ARRANGE
    const created = 'Neighbours';
    await pumpApp(tester);

    // ACT
    await tester.tap(find.byTooltip('Add new group'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextFormField).first, created);
    await tester.tap(find.text('Create Group'));
    await pumpFrames(tester);

    // ASSERT
    expect(find.text(created), findsOneWidget);
    expect(find.text('Dev Family'), findsOneWidget);
  });

  testWidgets('shares a wishlist and shows it under the group', (tester) async {
    // ARRANGE: the viewer owns "Christmas list" and has not shared it with the
    // group, so the dialog offers exactly that one.
    final app = await pumpApp(tester);
    await go(tester, app, '/group/dev-g1');

    // ACT
    await tester.tap(find.text('Share Wishlist'));
    await pumpFrames(tester);
    expect(find.text('Share a Wishlist'), findsOneWidget);
    await tester.tap(find.text('Christmas list'));
    await pumpFrames(tester);

    // ASSERT: the group's shared list reads the write back.
    expect(find.widgetWithText(ListTile, 'Christmas list'), findsOneWidget);
    expect(find.text('Owned by you'), findsNWidgets(2));
  });

  testWidgets('leaves a group and removes it from home', (tester) async {
    // ARRANGE: a group somebody else owns, so Leave Group is offered.
    final app = await pumpApp(tester, fixture: groupOwnedByAnother());
    expect(find.text('Book club'), findsOneWidget);
    await go(tester, app, '/group/dev-g2');

    // ACT
    await tester.tap(find.text('Leave Group'));
    await pumpFrames(tester);
    await tester.tap(find.text('Leave'));
    await pumpFrames(tester);

    // ASSERT: back on home, with the group gone from the list.
    expect(find.text('Book club'), findsNothing);
    expect(find.text('No groups yet. Create or join one!'), findsOneWidget);
  });

  testWidgets('joins a group from an invitation link', (tester) async {
    // ARRANGE: a group the viewer is not a member of yet.
    final app = await pumpApp(tester, fixture: openInvitation());
    await go(tester, app, '/join?group=dev-g3');
    expect(find.text("You've been invited to join"), findsOneWidget);

    // ACT
    await tester.tap(find.text('Join Group'));
    await pumpFrames(tester);

    // ASSERT: the group page opens as a member — the viewer may leave, which
    // only a member is offered.
    expect(find.text('Neighbours'), findsWidgets);
    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.text('Ana Dev'), findsOneWidget);
  });

  testWidgets('renders home loading, then the seeded data', (tester) async {
    // ARRANGE: the locator on the fake, without the router, so the page's own
    // lifecycle is what is under test.
    await buildDevApp(defaultFixture);

    // ACT: the first frame, before any snapshot has landed.
    await tester.pumpWidget(const MaterialApp(home: HomePage()));

    // ASSERT
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // ACT
    await pumpFrames(tester);

    // ASSERT: the fake served all three reads.
    expect(find.textContaining('Welcome, Ana Dev'), findsOneWidget);
    expect(find.text('Birthday list'), findsOneWidget);
  });

  testWidgets('renders a read error when a document cannot be projected', (
    tester,
  ) async {
    // ARRANGE
    await buildDevApp(unreadableWishlist());

    // ACT
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await pumpFrames(tester);

    // ASSERT: the wishlist section reports the failure instead of rendering an
    // empty list, which is what makes a bad fixture visible.
    expect(find.textContaining('An error occurred'), findsOneWidget);
    expect(find.textContaining('Welcome, Ana Dev'), findsOneWidget);
  });

  group('accessible names', () {
    testWidgets('the add-item button is named', (tester) async {
      // ARRANGE
      final app = await pumpApp(tester);

      // ACT
      await go(tester, app, '/wishlist/dev-l1');

      // ASSERT: the field test found this control with an empty name, so an
      // agent could see it but not address it. The name is the tooltip: the web
      // engine folds a node's tooltip into its DOM label, and the mobile screen
      // readers announce it the same way. Every other icon-only control in the
      // app is named this way, so this one follows the convention.
      expect(
        find.semantics.byPredicate((node) => node.tooltip == 'Add item'),
        findsOne,
      );
    });

    testWidgets('a shared wishlist row names its title and owner separately', (
      tester,
    ) async {
      // ARRANGE
      final app = await pumpApp(tester);

      // ACT
      await go(tester, app, '/group/dev-g1');

      // ASSERT: the title is exactly the wishlist name, and the owner is its
      // own node, so a selector does not break when the seed data changes.
      expect(find.semantics.byLabel("Ben's list"), findsOne);
      expect(find.semantics.byLabel('Owned by Ben Dev'), findsOne);
      expect(
        find.semantics.byLabel("Ben's list\nOwned by Ben Dev"),
        findsNothing,
      );
    });
  });
}
