import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
import 'package:wishtogether/main.dart';

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('an unknown scenario renders a page naming the ids that exist', (
    tester,
  ) async {
    // ARRANGE: an id nobody registered, typed into ?scenario=.
    const requested = 'no-such-scenario';
    final handle = tester.ensureSemantics();

    // ACT
    await tester.pumpWidget(await buildDevAppForScenario(requested));

    // ASSERT: what a reader sees and what a driver addresses by label are the
    // same facts, including the id that would have worked.
    expect(find.text('Unknown scenario "$requested"'), findsOneWidget);
    expect(
      find.text('Available scenarios: ${devScenarios.keys.join(', ')}'),
      findsOneWidget,
    );
    final node = find.semantics
        .byLabel(RegExp('Available scenarios'))
        .evaluate()
        .single;
    expect(node.label, contains(requested));
    for (final available in devScenarios.keys) {
      expect(node.label, contains(available));
    }
    // The page is still visibly a dev page, so it still carries the marker.
    expect(find.byKey(const ValueKey<String>(devBundleMarker)), findsOneWidget);

    handle.dispose();
  });

  test(
    'a known scenario builds the session instead of the error page',
    () async {
      // ACT
      final app = await buildDevAppForScenario(defaultFixture.id);

      // ASSERT: the catch is for the registry's refusal only, not for every
      // failure to build a session.
      expect(app, isA<WishTogetherApp>());
    },
  );
}
