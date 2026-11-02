import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/dev_config.dart';

/// The readable text of a refusal: what a reader sees and what a driver reads
/// out of the page's one semantics node.
String refusalText(RefusedDevLaunch launch) =>
    '${launch.headline} ${launch.details.join(' ')}';

/// Asserts a launch is live and returns it, so a failure names what came back.
LiveDevLaunch liveLaunchOf(DevLaunch launch) {
  expect(
    launch,
    isA<LiveDevLaunch>(),
    reason: 'expected a live launch, got ${launch.runtimeType}',
  );
  return launch as LiveDevLaunch;
}

/// Asserts a launch was refused and returns it.
RefusedDevLaunch refusalOf(DevLaunch launch) {
  expect(
    launch,
    isA<RefusedDevLaunch>(),
    reason: 'expected a refusal, got ${launch.runtimeType}',
  );
  return launch as RefusedDevLaunch;
}

void main() {
  group('resolveScenarioId', () {
    const fromDefine = 'family';

    test('the URL scenario wins over the compiled default', () {
      // ARRANGE / ACT
      final id = resolveScenarioId(
        urlScenario: 'large',
        defineScenario: fromDefine,
      );

      // ASSERT
      expect(id, 'large');
    });

    test('the compiled default is used when the URL names none', () {
      // ARRANGE / ACT
      final id = resolveScenarioId(
        urlScenario: null,
        defineScenario: fromDefine,
      );

      // ASSERT
      expect(id, fromDefine);
    });

    test('the default scenario is used when neither source names one', () {
      // ARRANGE / ACT
      final id = resolveScenarioId(urlScenario: null, defineScenario: '');

      // ASSERT
      expect(id, defaultScenarioId);
    });

    test('a blank URL scenario falls back to the compiled default', () {
      // The page is still addressable with "?scenario=" left behind by a tool,
      // and an empty id is not a scenario anyone asked for.
      const blank = '   ';

      // ACT
      final id = resolveScenarioId(urlScenario: blank, defineScenario: '');

      // ASSERT
      expect(id, defaultScenarioId);
    });
  });

  group('resolveDevLaunch — which backend runs', () {
    test('an unset backend is the fake one', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: '',
        urlScenario: null,
        defineScenario: '',
      );

      // ASSERT: fake is the default, so design iteration needs no credentials.
      expect(launch, isA<FakeDevLaunch>());
      expect((launch as FakeDevLaunch).scenarioId, defaultScenarioId);
    });

    test('the fake backend is the fake one', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: fakeDevBackend,
        urlScenario: null,
        defineScenario: '',
      );

      // ASSERT
      expect(launch, isA<FakeDevLaunch>());
    });

    test('the URL scenario reaches the fake launch', () {
      // ARRANGE
      const requested = 'large-wishlist';

      // ACT
      final launch = resolveDevLaunch(
        backendDefine: fakeDevBackend,
        urlScenario: requested,
        defineScenario: 'family',
      );

      // ASSERT: the URL still wins over the compiled default.
      expect((launch as FakeDevLaunch).scenarioId, requested);
    });

    test('the live backend is accepted', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: 'staging',
        tokenDefine: 'a-token',
      );

      // ASSERT
      expect(launch, isA<LiveDevLaunch>());
    });

    test('an unknown backend is refused, naming it and both valid ones', () {
      // ARRANGE
      const requested = 'carrier-pigeon';

      // ACT
      final launch = resolveDevLaunch(backendDefine: requested);

      // ASSERT: an agent must not be left guessing which values work.
      final refusal = refusalOf(launch);
      final text = refusalText(refusal);
      expect(text, contains(requested));
      expect(text, contains(fakeDevBackend));
      expect(text, contains(liveDevBackend));
    });
  });

  group('resolveDevLaunch — live refuses to touch production', () {
    test('a missing database define is refused with the mint command', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: '',
        tokenDefine: 'a-token',
      );

      // ASSERT: empty means the production database, so it must not start.
      final text = refusalText(refusalOf(launch));
      expect(text, contains('WT_FIRESTORE_DATABASE'));
      expect(text, contains('npm run dev:token'));
    });

    test('a blank database define is refused, not trimmed into production', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: '   ',
        tokenDefine: 'a-token',
      );

      // ASSERT
      expect(refusalText(refusalOf(launch)), contains('WT_FIRESTORE_DATABASE'));
    });

    test('the default database is refused as production', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: '(default)',
        tokenDefine: 'a-token',
      );

      // ASSERT
      final text = refusalText(refusalOf(launch));
      expect(text, contains('(default)'));
      expect(text, contains('production'));
    });

    test('a malformed database id is refused and named', () {
      // ARRANGE
      const malformed = 'Staging';

      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: malformed,
        tokenDefine: 'a-token',
      );

      // ASSERT
      expect(refusalText(refusalOf(launch)), contains(malformed));
    });

    test('a too-short database id is refused too', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: 'abc',
        tokenDefine: 'a-token',
      );

      // ASSERT
      expect(refusalText(refusalOf(launch)), contains('abc'));
    });

    test('the database is checked before the token', () {
      // ACT: nothing is set at all.
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: '',
        tokenDefine: '',
      );

      // ASSERT: the safety-critical input is the one named first, so a reader
      // fixes the guard that matters rather than the token.
      final text = refusalText(refusalOf(launch));
      expect(text, contains('WT_FIRESTORE_DATABASE'));
      expect(text, isNot(contains('WT_DEV_TOKEN')));
    });
  });

  group('resolveDevLaunch — the live token', () {
    test('a missing token is refused with the mint command', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: 'staging',
        tokenDefine: '',
      );

      // ASSERT
      final text = refusalText(refusalOf(launch));
      expect(text, contains('WT_DEV_TOKEN'));
      expect(text, contains('npm run dev:token'));
    });

    test('a blank token is refused, not sent to Firebase', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: 'staging',
        tokenDefine: '  ',
      );

      // ASSERT
      expect(refusalText(refusalOf(launch)), contains('WT_DEV_TOKEN'));
    });

    test('a valid launch carries the database and the trimmed token', () {
      // ARRANGE
      const database = 'staging';
      const token = '  header.payload.signature  ';

      // ACT
      final launch = liveLaunchOf(
        resolveDevLaunch(
          backendDefine: liveDevBackend,
          databaseDefine: ' $database ',
          tokenDefine: token,
        ),
      );

      // ASSERT
      expect(launch.databaseId, database);
      expect(launch.token, token.trim());
    });

    test('a URL scenario is recorded as ignored, never applied', () {
      // ARRANGE: the same URL an agent uses for fake mode.
      const requested = 'large-wishlist';

      // ACT
      final launch = liveLaunchOf(
        resolveDevLaunch(
          backendDefine: liveDevBackend,
          databaseDefine: 'staging',
          tokenDefine: 'a-token',
          urlScenario: requested,
          defineScenario: 'family',
        ),
      );

      // ASSERT: live data has no scenario, and the banner has to say so rather
      // than let staging data be read as a fixture.
      expect(launch.ignoredScenario, requested);
    });

    test('no URL scenario means nothing to report as ignored', () {
      // ACT
      final launch = liveLaunchOf(
        resolveDevLaunch(
          backendDefine: liveDevBackend,
          databaseDefine: 'staging',
          tokenDefine: 'a-token',
          urlScenario: null,
          defineScenario: 'family',
        ),
      );

      // ASSERT: the compiled scenario default is a fake-mode input, so it is
      // not something a live session has to announce.
      expect(launch.ignoredScenario, isNull);
    });
  });

  test('the bundle marker keeps the literal the CI guard greps', () {
    // A dev build carries this string; a production build must never contain
    // it. Changing it silently would leave the guard searching for a marker
    // that no longer exists.
    expect(devBundleMarker, 'wishtogether-dev-session');
  });

  test('the scenario query parameter is named scenario', () {
    expect(devScenarioParam, 'scenario');
  });

  test('the live backend is named live', () {
    // T5 documents this value; changing it silently breaks every command.
    expect(liveDevBackend, 'live');
  });

  test('a build without the define reports no token', () {
    // The guard treats an empty value as "no token", so an unset define must
    // arrive as the empty string rather than as a null or a placeholder.
    expect(devTokenDefine, isEmpty);
  });

  group('scenarioIdFor', () {
    test('reads the scenario from the page URL', () {
      // ARRANGE
      final uri = Uri.parse('/wishlist/dev-l1?scenario=large-wishlist');

      // ACT
      final id = scenarioIdFor(uri, defineScenario: 'family');

      // ASSERT: the URL is what an agent typed, so it wins.
      expect(id, 'large-wishlist');
    });

    test('falls back to the compiled default when the URL names none', () {
      // ARRANGE
      final uri = Uri.parse('/wishlist/dev-l1');

      // ACT
      final id = scenarioIdFor(uri, defineScenario: 'family');

      // ASSERT
      expect(id, 'family');
    });
  });
}
