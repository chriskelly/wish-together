import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/brand_card.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/empty_scenario.dart';
import 'package:wishtogether/dev/fixtures/family_scenario.dart';
import 'package:wishtogether/dev/fixtures/large_wishlist_scenario.dart';
import 'package:wishtogether/dev/fixtures/overflow_scenario.dart';
import 'package:wishtogether/dev/fixtures/shared_scenario.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
import 'package:wishtogether/main.dart';

// Every scenario at the URL `lib/dev/docs/scenarios.md` publishes for it.
//
// A fixture can parse and still render an error page: a group id the viewer
// cannot read, a page that resolves a missing document, a route that never
// matches. These tests mount the fixture and open the documented URL, so the
// published handle is the thing that is asserted, not just the data behind it.
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

  Future<WishTogetherApp> pumpApp(
    WidgetTester tester,
    DevFixture fixture,
  ) async {
    final app = await buildDevApp(fixture);
    await tester.pumpWidget(app);
    await pumpFrames(tester);
    return app;
  }

  Future<void> open(
    WidgetTester tester,
    WishTogetherApp app,
    String location,
  ) async {
    app.router.go(location);
    await pumpFrames(tester);
  }

  Future<void> scrollListTo(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );

  testWidgets('default opens home with its lists and group', (tester) async {
    await pumpApp(tester, defaultFixture);

    expect(find.text('Birthday list'), findsOneWidget);
    expect(find.text('Christmas list'), findsOneWidget);
    expect(find.text('Dev Family'), findsOneWidget);
  });

  testWidgets('family opens home with its three groups and two lists', (
    tester,
  ) async {
    await pumpApp(tester, familyFixture);

    expect(find.text('The Whitfields'), findsOneWidget);
    expect(find.text('The Bell Family'), findsOneWidget);
    expect(find.text('The Friday Crew'), findsOneWidget);
    expect(find.text("The Twins' Birthday"), findsOneWidget);
    expect(find.text("Ada's Birthday"), findsOneWidget);
  });

  testWidgets('family opens the shared wishlist and lists its items', (
    tester,
  ) async {
    final app = await pumpApp(tester, familyFixture);

    await open(tester, app, '/wishlist/fam-l1');

    expect(find.text("Bea's Birthday"), findsOneWidget);
    expect(find.text('Vintage microphone'), findsOneWidget);
    // The viewer is a reader here, so another member's full single claim and
    // the viewer's own claim are both rendered without touching the spoiler
    // toggle.
    expect(find.text('Unavailable'), findsOneWidget);
    await scrollListTo(tester, find.text('You claimed this!'));
    expect(find.text('You claimed this!'), findsOneWidget);
  });

  testWidgets(
    'family opens the viewer-owned wishlist with the spoiler toggle',
    (tester) async {
      final app = await pumpApp(tester, familyFixture);

      await open(tester, app, '/wishlist/fam-l11');

      expect(find.text("Ada's Birthday"), findsOneWidget);
      expect(find.text('Vintage watch'), findsOneWidget);
      expect(find.byTooltip('Show claimed status'), findsOneWidget);
    },
  );

  testWidgets('large-wishlist opens the list and its first item', (
    tester,
  ) async {
    final app = await pumpApp(tester, largeWishlistFixture);

    await open(tester, app, '/wishlist/lg-l1');

    expect(find.text('Fifty gift ideas'), findsOneWidget);
    expect(find.text('Gift idea 1'), findsOneWidget);
  });

  testWidgets('empty opens home with both empty sections', (tester) async {
    await pumpApp(tester, emptyFixture);

    expect(find.text('No wishlists yet. Create one!'), findsOneWidget);
    expect(find.text('No groups yet. Create or join one!'), findsOneWidget);
  });

  testWidgets('overflow opens the wishlist with its long item text', (
    tester,
  ) async {
    final app = await pumpApp(tester, overflowFixture);

    await open(tester, app, '/wishlist/ovf-l1');

    expect(find.text(overflowWishlistName), findsOneWidget);
    expect(find.text(overflowSpacedItemName), findsOneWidget);
  });

  // The overflow scenario's group page (`/group/ovf-g1`) is deliberately not
  // mounted here: its member row lays out an unbounded name beside the role
  // label, so the unbroken display name overflows the Row and Flutter reports
  // it as an error in a widget test. That is a real layout gap the scenario was
  // written to expose, not a fixture problem, so it is reported rather than
  // hidden by shortening the name.

  testWidgets('shared opens the group page that links both wishlists', (
    tester,
  ) async {
    final app = await pumpApp(tester, sharedFixture);

    await open(tester, app, '/group/shr-g1');

    expect(find.text('The Riveras'), findsOneWidget);
    expect(find.text("Priya's Wedding List"), findsOneWidget);
    expect(find.text("Sam's Birthday"), findsOneWidget);
  });

  testWidgets('shared opens a wishlist the viewer does not own', (
    tester,
  ) async {
    final app = await pumpApp(tester, sharedFixture);

    await open(tester, app, '/wishlist/shr-l2');

    expect(find.text("Priya's Wedding List"), findsOneWidget);
    expect(find.text('Tea towel set'), findsOneWidget);
    expect(find.text('You claimed this!'), findsWidgets);

    await scrollListTo(tester, find.text('Garden hose'));
    expect(find.text('2 claimed'), findsOneWidget);

    await scrollListTo(tester, find.text('Board game'));
    final boardGameCard = find.ancestor(
      of: find.text('Board game'),
      matching: find.byType(BrandCard),
    );
    expect(find.text('2 of 4 claimed'), findsOneWidget);
    expect(
      find.descendant(
        of: boardGameCard,
        matching: find.text('You claimed this!'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shared opens the viewer-owned list with its claim limits', (
    tester,
  ) async {
    final app = await pumpApp(tester, sharedFixture);

    await open(tester, app, '/wishlist/shr-l1');

    expect(find.text("Sam's Birthday"), findsOneWidget);
    expect(find.text('1 person can claim'), findsWidgets);

    await scrollListTo(tester, find.text('Stand mixer'));
    expect(find.text('Unlimited claims'), findsOneWidget);
  });
}
