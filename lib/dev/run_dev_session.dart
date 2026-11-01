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
import 'package:wishtogether/core/theme.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_error_screen.dart';
import 'package:wishtogether/dev/dev_session.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';
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

  final session = DevAuthSession(fixture.viewerUid);
  setupServiceLocator(
    firestore: firestore,
    appLog: buildDevLog(),
    authSession: session,
  );

  // No initialLocation: on web the browser path is the route, and go_router
  // ignores the parameter whenever the path is not `/`.
  return WishTogetherApp(
    router: createRouter(session),
    pageFrame: (pages) => DevSessionFrame(scenarioId: fixture.id, pages: pages),
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

/// The page shown for a scenario id the registry does not have.
Widget buildUnknownScenarioApp(String requestedScenario) => MaterialApp(
  title: 'WishTogether dev session',
  debugShowCheckedModeBanner: false,
  theme: lightTheme,
  darkTheme: darkTheme,
  themeMode: ThemeMode.system,
  home: DevErrorScreen(
    requestedScenario: requestedScenario,
    availableScenarios: devScenarios.keys.toList(),
  ),
);

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
  _prepareBrowser();
  runApp(await buildDevApp(fixture));
}

/// Boots the scenario [scenarioId] names, from the page URL.
///
/// An unknown id is something an agent types, so it gets a page that says so
/// and lists the ids that work instead of the blank tab a failure before
/// `runApp` leaves behind.
Future<void> runDevSessionFor(String scenarioId) async {
  _prepareBrowser();
  runApp(await buildDevAppForScenario(scenarioId));
}

/// Everything a dev session needs from the browser before it mounts.
///
/// Both the scenario and the error page run this: a wrong id must still be a
/// page that can be read, not a process that died before painting.
void _prepareBrowser() {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web builds its accessibility DOM on demand. Without semantics on,
  // the page holds a placeholder and a text-only agent has nothing to address
  // widgets by.
  _retainSemantics();
  // Real paths, so the browser pathname is the initial route.
  usePathUrlStrategy();
}

/// The semantics handle, kept for the life of the process.
///
/// `ensureSemantics()` returns a handle that the caller has to hold: dropping
/// it releases the semantics tree again, which would quietly take the
/// accessibility DOM away mid-session.
SemanticsHandle? _semanticsHandle;

void _retainSemantics() {
  _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
}
