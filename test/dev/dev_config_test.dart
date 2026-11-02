import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/dev_notice_screen.dart';

/// The text a refusal becomes, through the same function the page uses.
///
/// Composing it here instead would let these tests assert words the page never
/// renders.
String refusalText(RefusedDevLaunch launch) =>
    noticeSemanticsLabel(launch.headline, launch.details);

/// Asserts a launch has type [T] and returns it, so a failure names what came
/// back instead of only what was wanted.
T launchOf<T extends DevLaunch>(DevLaunch launch) {
  expect(launch, isA<T>(), reason: 'expected $T, got ${launch.runtimeType}');
  return launch as T;
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
      final refusal = launchOf<RefusedDevLaunch>(launch);
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
      final text = refusalText(launchOf<RefusedDevLaunch>(launch));
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
      expect(
        refusalText(launchOf<RefusedDevLaunch>(launch)),
        contains('WT_FIRESTORE_DATABASE'),
      );
    });

    test('the default database is refused as production', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: '(default)',
        tokenDefine: 'a-token',
      );

      // ASSERT
      final text = refusalText(launchOf<RefusedDevLaunch>(launch));
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
      expect(
        refusalText(launchOf<RefusedDevLaunch>(launch)),
        contains(malformed),
      );
    });

    test('a too-short database id is refused too', () {
      // ACT
      final launch = resolveDevLaunch(
        backendDefine: liveDevBackend,
        databaseDefine: 'abc',
        tokenDefine: 'a-token',
      );

      // ASSERT
      expect(refusalText(launchOf<RefusedDevLaunch>(launch)), contains('abc'));
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
      final text = refusalText(launchOf<RefusedDevLaunch>(launch));
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
      final text = refusalText(launchOf<RefusedDevLaunch>(launch));
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
      expect(
        refusalText(launchOf<RefusedDevLaunch>(launch)),
        contains('WT_DEV_TOKEN'),
      );
    });

    test('a valid launch carries the database and the trimmed token', () {
      // ARRANGE
      const database = 'staging';
      const token = '  header.payload.signature  ';

      // ACT
      final launch = launchOf<LiveDevLaunch>(
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
      final launch = launchOf<LiveDevLaunch>(
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
      final launch = launchOf<LiveDevLaunch>(
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

  group('resolveDevLaunch — the account-deletion opt-in', () {
    DevLaunch withFlag(String raw) => resolveDevLaunch(
      backendDefine: liveDevBackend,
      databaseDefine: 'staging',
      tokenDefine: 'a-token',
      allowAccountDeletionDefine: raw,
    );

    test('is off when the build says nothing', () {
      // ACT
      final launch = launchOf<LiveDevLaunch>(withFlag(''));

      // ASSERT: deleting a real Auth user must be asked for, never defaulted.
      expect(launch.allowAccountDeletion, isFalse);
    });

    test('is off when explicitly false', () {
      // ACT
      final launch = launchOf<LiveDevLaunch>(withFlag('false'));

      // ASSERT
      expect(launch.allowAccountDeletion, isFalse);
    });

    test('is on for true', () {
      // ACT
      final launch = launchOf<LiveDevLaunch>(withFlag('true'));

      // ASSERT
      expect(launch.allowAccountDeletion, isTrue);
    });

    test('a value that is neither is refused, naming the accepted ones', () {
      // ARRANGE
      const malformed = 'yes';

      // ACT
      final text = refusalText(launchOf<RefusedDevLaunch>(withFlag(malformed)));

      // ASSERT: a typo must not silently mean "off".
      expect(text, contains(malformed));
      expect(text, contains('"true"'));
      expect(text, contains('Accepted values'));
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

  test('a live build with no database define refuses', () {
    // ARRANGE: nothing but the backend, as a real `flutter run` would arrive
    // with no WT_FIRESTORE_DATABASE. The default argument is the compile-time
    // define, so this pins the wiring, not only the guard.
    // ACT
    final launch = resolveDevLaunch(backendDefine: liveDevBackend);

    // ASSERT: an empty define means production, so it must never start.
    expect(launch, isA<RefusedDevLaunch>());
  });

  test('a live build with no token define refuses', () {
    // ACT
    final launch = resolveDevLaunch(
      backendDefine: liveDevBackend,
      databaseDefine: 'staging',
    );

    // ASSERT
    expect(launch, isA<RefusedDevLaunch>());
  });

  test('the live backend is named live', () {
    // The value the documented commands and the guard both name; changing it
    // silently breaks every one of them.
    expect(liveDevBackend, 'live');
  });
}
