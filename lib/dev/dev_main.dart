import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

/// The committed development entrypoint.
///
/// Boots the app signed in, on the real widgets, against an in-memory store:
///
/// ```sh
/// flutter run -t lib/dev/dev_main.dart -d chrome
/// ```
///
/// The path is the route and `?scenario=<id>` picks the fixture, so any
/// signed-in screen is a URL:
///
/// ```text
/// http://localhost:PORT/wishlist/dev-l1?scenario=default
/// ```
///
/// A `?scenario=` this build does not have is still a page: it names the ids
/// that work instead of leaving the tab blank.
Future<void> main() async {
  // Only the fake backend exists: this stops the launch rather than rendering
  // an empty session when someone asks for one that needs Firebase.
  requireFakeBackend(devBackendDefine);
  await runDevSessionFor(scenarioIdFor(Uri.base));
}
