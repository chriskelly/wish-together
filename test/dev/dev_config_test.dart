import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/dev_config.dart';

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

  group('requireFakeBackend', () {
    test('accepts the fake backend and the default', () {
      // ACT & ASSERT
      expect(() => requireFakeBackend(''), returnsNormally);
      expect(() => requireFakeBackend(fakeDevBackend), returnsNormally);
    });

    test('refuses live mode until it is implemented', () {
      // ARRANGE
      const requested = 'live';

      // ACT & ASSERT
      expect(
        () => requireFakeBackend(requested),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains(requested), contains(fakeDevBackend)),
          ),
        ),
      );
    });

    test('refuses an unknown backend by name', () {
      // ARRANGE
      const requested = 'carrier-pigeon';

      // ACT & ASSERT
      expect(
        () => requireFakeBackend(requested),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(requested),
          ),
        ),
      );
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
