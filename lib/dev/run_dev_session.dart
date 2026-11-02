import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/dev_failure_screen.dart';
import 'package:wishtogether/dev/dev_session.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/main.dart';

/// Builds the app a dev session runs: a seeded in-memory store, the locator
/// wired to it, and the production app widget around the shared router.
///
/// Nothing here resolves a Firebase plugin: the repositories take the fake
/// through the locator's `firestore:` seam and the shell takes [DevAuthSession]
/// through `authSession:`. There is no `initializeApp`, so no project, no
/// credentials and no network.
///
/// Split from [runDevSession] so a test can pump the same composition instead
/// of starting a process.
Future<WishTogetherApp> buildDevApp(DevFixture fixture) async {
  final firestore = FakeFirebaseFirestore();
  await seedDevFirestore(firestore, fixture);

  // No initialLocation: on web the browser path is the route, and go_router
  // ignores the parameter whenever the path is not `/`.
  return composeDevApp(
    firestore: firestore,
    authSession: DevAuthSession(fixture.viewerUid),
    frame: (pages) => DevSessionFrame.scenario(fixture.id, pages: pages),
  );
}

/// Builds the shell both dev backends run: the locator over [firestore], the
/// router over the session that locator resolves, and [frame] around the pages.
///
/// The router always takes the session from the locator rather than from the
/// parameter. That is what makes the two backends differ only in what they
/// register — a live launch passes null and gets the production service — and
/// what lets a test replace the session without replacing the router.
WishTogetherApp composeDevApp({
  required FirebaseFirestore firestore,
  required AuthSession? authSession,
  required Widget Function(Widget pages) frame,
}) {
  setupServiceLocator(
    firestore: firestore,
    appLog: buildDevLog(),
    authSession: authSession,
  );
  return WishTogetherApp(
    router: createRouter(getIt<AuthSession>()),
    pageFrame: frame,
  );
}

/// The app for the scenario [scenarioId], or the page that names the ids that
/// do exist.
///
/// [fixtureForScenario] throws rather than falling back to `default`, which is
/// right for a caller that can read the error: an agent must never be shown
/// another scenario's data without knowing. A browser entrypoint cannot let
/// that throw stand, though — it lands before `runApp`, so the tab is blank and
/// the only trace is a console error nobody may be listening to.
Future<Widget> buildDevAppForScenario(String scenarioId) async {
  final DevFixture fixture;
  try {
    fixture = fixtureForScenario(scenarioId);
  } on StateError {
    return buildUnknownScenarioApp(scenarioId);
  }
  return buildDevApp(fixture);
}

/// The log a dev session reports through.
///
/// A console sink, always enabled: route changes, repository failures and
/// feature-seam events are the second thing an agent reads when a click appears
/// to do nothing. The production startup enables the same sink only in debug
/// builds; dev is always a debug build.
AppLog buildDevLog() => AppLog(
  session: SessionContext.create(
    platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
  ),
  sinks: <LogSink>[ConsoleSink(enabled: true)],
);

/// Boots the app for [fixture].
///
/// This is the whole entrypoint of a one-off scenario: parse nothing, pass a
/// fixture, mount. Committed scenarios go through `dev_main.dart` instead,
/// which adds the URL and define resolution.
Future<void> runDevSession(DevFixture fixture) async {
  prepareDevBrowser();
  runApp(await buildDevApp(fixture));
}

/// Boots the scenario [scenarioId] names, from the page URL.
///
/// An unknown id is something an agent types, so it gets a page that says so
/// and lists the ids that work instead of the blank tab a failure before
/// `runApp` leaves behind.
Future<void> runDevSessionFor(String scenarioId) async {
  prepareDevBrowser();
  runApp(await buildDevAppForScenario(scenarioId));
}

/// Boots the page for a launch that cannot run.
///
/// Same browser preparation as a working session: a refusal must be a page that
/// can be read and addressed, not a process that died before painting.
Future<void> runRefusedDevSession(RefusedDevLaunch refusal) async {
  prepareDevBrowser();
  runApp(buildRefusedDevApp(refusal));
}

/// Everything a dev session needs from the browser before it mounts.
///
/// Every dev page calls this first, whichever path asked for it: a page that
/// cannot be read, or whose widgets a driver cannot address, is not a page. It
/// runs before Firebase as well as after, because the failure it prevents is a
/// tab that never paints rather than a request that fails.
void prepareDevBrowser() {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web builds its accessibility DOM on demand. Without semantics on,
  // the page holds a placeholder and a text-only agent has nothing to address
  // widgets by.
  retainDevSemantics();
  // Real paths, so the browser pathname is the initial route.
  usePathUrlStrategy();
}

/// The semantics handle, kept for the life of the process.
SemanticsHandle? _semanticsHandle;

/// Turns the semantics tree on, and keeps it on.
///
/// `ensureSemantics()` returns a handle that the caller has to hold: dropping
/// it releases the semantics tree again, which would quietly take the
/// accessibility DOM away mid-session. The first call stores that handle here
/// and returns it; a later call returns the same one, so the handle count stays
/// at one no matter how often the bootstrap runs.
SemanticsHandle retainDevSemantics() =>
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
