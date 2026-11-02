import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/dev_session.dart';
import 'package:wishtogether/dev/live_dev_session.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

/// A live launch the tests can hand around without a Firebase project.
LiveDevLaunch liveLaunch({String? ignoredScenario}) => LiveDevLaunch(
  databaseId: 'staging',
  token: 'header.payload.signature',
  ignoredScenario: ignoredScenario,
);

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('devLiveLabel', () {
    test('names the database the data came from', () {
      // ASSERT: a screenshot of staging data must never read as a fixture.
      expect(
        devLiveLabel('staging'),
        'Dev session · live data · database: staging',
      );
    });

    test('says a requested scenario was ignored', () {
      // ACT
      final label = devLiveLabel('staging', ignoredScenario: 'large');

      // ASSERT: the request is visible, so the missing fixture is explained.
      expect(
        label,
        'Dev session · live data · database: staging · '
        'scenario "large" ignored',
      );
    });

    test('a blank ignored scenario adds nothing', () {
      // ACT
      final label = devLiveLabel('staging', ignoredScenario: '   ');

      // ASSERT
      expect(label, 'Dev session · live data · database: staging');
    });
  });

  testWidgets('a refused launch is a page that names the fix', (tester) async {
    // ARRANGE
    const refusal = RefusedDevLaunch(
      headline: 'Live dev mode needs a token',
      details: <String>[
        'WT_DEV_TOKEN is empty.',
        'npm run dev:token prints a fresh one.',
      ],
    );
    final handle = tester.ensureSemantics();

    // ACT
    await tester.pumpWidget(buildRefusedDevApp(refusal));

    // ASSERT: the reader sees the reason and the fix, a driver reads the same
    // words, and the page still carries the dev marker.
    expect(find.text(refusal.headline), findsOneWidget);
    expect(find.text(refusal.details.first), findsOneWidget);
    final node = find.semantics
        .byLabel(RegExp('WT_DEV_TOKEN'))
        .evaluate()
        .single;
    expect(node.label, contains('npm run dev:token'));
    expect(find.byKey(const ValueKey<String>(devBundleMarker)), findsOneWidget);

    handle.dispose();
  });

  testWidgets('a rejected token names the command that mints the next one', (
    tester,
  ) async {
    // ARRANGE: a sign-in that fails the way an expired token does.
    final app = await buildLiveDevApp(
      liveLaunch(),
      initializeFirebase: () async {},
      signIn: (token) async => throw StateError('rejected'),
    );

    // ACT
    await tester.pumpWidget(app);

    // ASSERT
    expect(find.text('Live dev mode could not sign in'), findsOneWidget);
    expect(find.textContaining('npm run dev:token'), findsOneWidget);
    expect(find.textContaining('--database staging'), findsOneWidget);
  });

  testWidgets('a Firebase that cannot start says so instead of going blank', (
    tester,
  ) async {
    // ARRANGE
    final app = await buildLiveDevApp(
      liveLaunch(),
      initializeFirebase: () async => throw StateError('no options'),
    );

    // ACT
    await tester.pumpWidget(app);

    // ASSERT
    expect(find.text('Live dev mode could not start Firebase'), findsOneWidget);
    expect(find.textContaining('StateError'), findsOneWidget);
  });

  testWidgets('a live session marks real data, never a scenario', (
    tester,
  ) async {
    // ARRANGE: every Firebase seam is a no-op or an in-memory store, so the
    // composition can be pumped without a project. The session is injected for
    // the same reason; a real launch leaves it out and gets AuthService.
    final handle = tester.ensureSemantics();
    final app = await buildLiveDevApp(
      liveLaunch(ignoredScenario: 'large'),
      initializeFirebase: () async {},
      signIn: (token) async {},
      createFirestore: (databaseId) => FakeFirebaseFirestore(),
      authSession: const DevAuthSession('dev-live-1'),
    );

    // ACT
    await tester.pumpWidget(app);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ASSERT: the strip says real data from a named database, and that the
    // scenario in the URL was ignored rather than applied.
    expect(
      find.textContaining('live data · database: staging'),
      findsOneWidget,
    );
    expect(find.textContaining('scenario "large" ignored'), findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp('live data · database: staging')),
      findsOne,
    );
    expect(find.byKey(const ValueKey<String>(devBundleMarker)), findsOneWidget);
    expect(tester.takeException(), isNull);

    handle.dispose();
  });

  test('the sign-in failure text names the code, the command and the port', () {
    // ACT
    final text = liveSignInFailureDetails(
      databaseId: 'staging',
      code: 'invalid-custom-token',
      errorType: 'FirebaseAuthException',
    ).join(' ');

    // ASSERT: the three things a reader needs to get unstuck.
    expect(text, contains('invalid-custom-token'));
    expect(text, contains('npm run dev:token'));
    expect(text, contains('staging'));
    expect(text, contains('$devLiveWebPort'));
  });

  test('the mint script pins the port the browser API key allows', () {
    // The app tells a reader which port to use and the script prints the
    // command. Read the *declaration*, not the file text: the literal also
    // appears in the script's comments, so a text search would keep passing
    // after the constant itself was changed.
    final script = File('scripts/dev-token.mjs').readAsStringSync();
    final declared = RegExp(
      r'^export const DEFAULT_WEB_PORT = (\d+);$',
      multiLine: true,
    ).firstMatch(script);

    // ASSERT
    expect(
      declared,
      isNotNull,
      reason: 'scripts/dev-token.mjs must declare DEFAULT_WEB_PORT',
    );
    expect(int.parse(declared!.group(1)!), devLiveWebPort);
    // The number is an operational fact, not a preference: it is the only
    // localhost referrer the project's browser API key allows. Changing it means
    // changing the key first.
    expect(devLiveWebPort, 59922);
  });
}
