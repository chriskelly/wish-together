import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';

/// The scenarios this build can show, keyed by the id the URL names.
///
/// A new committed scenario is one entry here; the fixture's own [DevFixture.id]
/// is the key, so the URL, the banner and the registry cannot disagree.
final Map<String, DevFixture> devScenarios = <String, DevFixture>{
  defaultFixture.id: defaultFixture,
};

/// The fixture for [id], or a failure that names what is available.
///
/// An unknown id must not fall back to the default: an agent would then see the
/// wrong data and never know it.
DevFixture fixtureForScenario(String id) {
  final fixture = devScenarios[id];
  if (fixture != null) {
    return fixture;
  }
  throw StateError(
    'Unknown dev scenario "$id". Available scenarios: '
    '${devScenarios.keys.join(', ')}.',
  );
}
