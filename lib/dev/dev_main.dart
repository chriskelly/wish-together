import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/live_dev_session.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

/// The committed development entrypoint.
///
/// Boots the app signed in, on the real widgets, against one of two backends:
///
/// ```sh
/// # the in-memory fixture (default), no credentials, no network
/// flutter run -t lib/dev/dev_main.dart -d chrome
///
/// # real Firebase Auth and real Firestore, on a named database only
/// flutter run -t lib/dev/dev_main.dart -d chrome --web-port=59922 \
///   --dart-define=WT_DEV_BACKEND=live \
///   --dart-define=WT_FIRESTORE_DATABASE=staging \
///   --dart-define=WT_DEV_TOKEN=<token from `npm run dev:token`>
/// ```
///
/// The path is the route, so any signed-in screen is a URL:
///
/// ```text
/// http://localhost:PORT/wishlist/dev-l1?scenario=default
/// ```
///
/// `?scenario=` picks the fixture and means nothing in live mode, where the
/// data is real: the banner says so rather than showing staging data under a
/// scenario name.
///
/// Every launch that cannot run is a page naming the fix — a bad scenario id, an
/// unknown backend, a live launch without a named database or token, or a
/// rejected token. A blank tab would hide the one thing a reader needs.
Future<void> main() async {
  final launch = resolveDevLaunch(
    urlScenario: Uri.base.queryParameters[devScenarioParam],
  );
  switch (launch) {
    case FakeDevLaunch(:final scenarioId):
      await runDevSessionFor(scenarioId);
    case LiveDevLaunch():
      await runLiveDevSession(launch);
    case RefusedDevLaunch():
      await runRefusedDevSession(launch);
  }
}
