import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('names the active scenario in the accessibility tree', (
    tester,
  ) async {
    // ARRANGE: the whole dev app, not the strip on its own. The name has to
    // survive the app shell: a labelled node painted beside the navigator is
    // dropped from the semantics tree, which is how the strip used to be
    // unreadable.
    final scenarioId = defaultFixture.id;
    final expected = 'Dev session · scenario: $scenarioId';
    final handle = tester.ensureSemantics();

    // ACT
    await tester.pumpWidget(await buildDevAppForScenario(scenarioId));
    // Let the pages' first snapshots land, as a browser would.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // ASSERT: exactly one node carries the name. Two would read the scenario
    // twice to a screen reader.
    expect(find.semantics.byLabel(expected), findsOne);

    handle.dispose();
  });
}
