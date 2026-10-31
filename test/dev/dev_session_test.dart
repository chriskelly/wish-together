import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
import 'package:wishtogether/main.dart';

/// A scenario the test invents, to prove a one-off fixture needs nothing but
/// data.
DevFixture adHocFixture() => DevFixture(
  id: 'ad-hoc',
  viewerUid: 'zoe',
  documents: <String, Map<String, dynamic>>{
    'users/zoe': <String, dynamic>{'displayName': 'Zoe Ad Hoc'},
    'wishlists/zoe-l1': <String, dynamic>{
      'name': 'Garden plans',
      'ownerId': 'zoe',
      'sharedWithGroups': <String>[],
    },
  },
);

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  /// Pumps a fixed number of frames so asynchronous stream emissions land.
  ///
  /// `pumpAndSettle` cannot be used here: the pages show a progress indicator
  /// while their first snapshot is in flight, and its animation never settles.
  /// The frame count is deterministic — `pump` advances a fake clock — so this
  /// is not a timing budget; a page that needed more frames would be a
  /// behaviour change the assertions catch.
  Future<void> pumpFrames(WidgetTester tester, {int frames = 12}) async {
    for (var frame = 0; frame < frames; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Builds the dev app and pumps it.
  Future<WishTogetherApp> pumpDevApp(
    WidgetTester tester, {
    DevFixture? fixture,
  }) async {
    final app = await buildDevApp(fixture ?? defaultFixture);
    await tester.pumpWidget(app);
    await pumpFrames(tester);
    return app;
  }

  testWidgets('opens signed in on the seeded home page', (tester) async {
    // ACT
    await pumpDevApp(tester);

    // ASSERT: the two wishlists the viewer owns, and no login page.
    expect(find.text('Birthday list'), findsOneWidget);
    expect(find.text('Christmas list'), findsOneWidget);
    expect(find.text('Dev Family'), findsOneWidget);
    expect(find.textContaining('Welcome, Ana Dev'), findsOneWidget);
  });

  testWidgets('marks the build and names the scenario it is showing', (
    tester,
  ) async {
    // ACT
    await pumpDevApp(tester);

    // ASSERT: a screenshot of this page can never be read as the real app.
    expect(find.byType(DevBanner), findsOneWidget);
    expect(
      find.textContaining('scenario: ${defaultFixture.id}'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>(devBundleMarker)),
      findsOneWidget,
      reason: 'the key carries the literal a CI bundle guard greps for',
    );
  });

  testWidgets('offers no sign-out control and keeps its data on screen', (
    tester,
  ) async {
    // ACT
    await pumpDevApp(tester);

    // ASSERT: no sign-out control at all, and the page still holds the data it
    // loaded after settling.
    expect(find.byTooltip('Logout'), findsNothing);
    expect(find.byTooltip('Profile'), findsOneWidget);
    expect(find.text('Birthday list'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides account deletion on the profile page', (tester) async {
    // ARRANGE
    final app = await pumpDevApp(tester);

    // ACT
    app.router.go('/profile');
    await pumpFrames(tester);

    // ASSERT: the page rendered, without the danger zone.
    expect(find.text('Update your profile information.'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
  });

  testWidgets('builds every signed-in screen without the production auth '
      'service', (tester) async {
    // ARRANGE
    final app = await pumpDevApp(tester);

    // ACT & ASSERT: home -> wishlist -> group -> profile. A StateError from
    // resolving AuthService would surface on exactly one of these.
    await tester.tap(find.text('Birthday list'));
    await pumpFrames(tester);
    expect(find.text('Board game'), findsOneWidget);

    app.router.go('/');
    await pumpFrames(tester);
    await tester.tap(find.text('Dev Family'));
    await pumpFrames(tester);
    expect(find.text('Dev Family'), findsWidgets);

    app.router.go('/');
    await pumpFrames(tester);
    await tester.tap(find.byTooltip('Profile'));
    await pumpFrames(tester);
    expect(find.text('Update your profile information.'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('creates a wishlist through the form and lists it', (
    tester,
  ) async {
    // ARRANGE
    const created = 'Weekend trip';
    await pumpDevApp(tester);

    // ACT: the real form, use case, repository and widget against the fake.
    await tester.tap(find.byTooltip('Add new wishlist'));
    await pumpFrames(tester);
    await tester.enterText(find.byType(TextFormField), created);
    await tester.tap(find.text('Save Wishlist'));
    await pumpFrames(tester);

    // ASSERT: the write is visible in the list the home page reads back.
    expect(find.text(created), findsOneWidget);
  });

  testWidgets('claims an item on a shared wishlist and renders the claim', (
    tester,
  ) async {
    // ARRANGE: the third wishlist belongs to somebody else and is shared with
    // the viewer's group, which is what makes an item claimable.
    final app = await pumpDevApp(tester);

    // ACT
    app.router.go('/wishlist/dev-l3');
    await pumpFrames(tester);
    await tester.tap(find.text('Claim'));
    await pumpFrames(tester);

    // ASSERT
    expect(find.text('You claimed this!'), findsOneWidget);
  });

  testWidgets('shows a page its own missing-document state', (tester) async {
    // ARRANGE: a route the fixture has no data for.
    final app = await pumpDevApp(tester);

    // ACT
    app.router.go('/wishlist/not-in-the-fixture');
    await pumpFrames(tester);

    // ASSERT: the page's own handling, not a harness crash.
    expect(find.text('Wishlist Not Found'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders a fixture it is handed without a registry entry', (
    tester,
  ) async {
    // ACT
    await pumpDevApp(tester, fixture: adHocFixture());

    // ASSERT: a one-off entrypoint is data only.
    expect(find.text('Garden plans'), findsOneWidget);
    expect(find.textContaining('Welcome, Zoe Ad Hoc'), findsOneWidget);
    expect(find.textContaining('scenario: ad-hoc'), findsOneWidget);
  });

  testWidgets('sends a viewer with no profile document to onboarding', (
    tester,
  ) async {
    // ARRANGE: the router creates the missing users/{uid} document, which has
    // no display name yet.
    final fixture = DevFixture(
      id: 'no-profile',
      viewerUid: 'newcomer',
      documents: <String, Map<String, dynamic>>{
        'wishlists/nothing-yet': <String, dynamic>{
          'name': 'Not mine',
          'ownerId': 'someone-else',
          'sharedWithGroups': <String>[],
        },
      },
    );

    // ACT
    await pumpDevApp(tester, fixture: fixture);

    // ASSERT: onboarding, not a crash.
    expect(
      find.text('Welcome! Please enter your name to continue.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports route changes to the console', (tester) async {
    // ARRANGE: capture what the console sink would print. The override has to
    // be undone before the test body returns: the binding fails a test that
    // leaves a foundation debug variable changed.
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        printed.add(message);
      }
    };

    try {
      await pumpDevApp(tester);

      // ACT: a navigation is what produces a route change.
      await tester.tap(find.text('Birthday list'));
      await pumpFrames(tester);

      // ASSERT: the agent's second feedback channel is wired up.
      expect(
        printed.where((line) => line.contains('routeChanged')),
        isNotEmpty,
        reason: 'the console sink must report navigation in a dev session',
      );
    } finally {
      debugPrint = original;
    }
  });
}
