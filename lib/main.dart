import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show
        debugPrint,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        kReleaseMode,
        TargetPlatform,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/core/deep_links.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/logging/sentry_sink.dart';
import 'package:wishtogether/core/logging/sentry_startup.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/app_update/application/check_for_update.dart';
import 'package:wishtogether/features/app_update/application/retry_update_gate.dart';
import 'package:wishtogether/features/app_update/data/app_update_service.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';
import 'package:wishtogether/features/app_update/domain/update_url.dart';
import 'package:wishtogether/features/app_update/presentation/update_required_page.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';

import 'firebase_options.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Installed before any plugin runs, so a Universal Link queued during startup
  // is kept and web routes are real paths before Sentry sees them.
  usePathUrlStrategy();
  _deepLinks = DeepLinkService();

  // No DSN means Sentry is never initialised: no SDK, no native handler, no
  // network. The app then runs exactly the startup it ran before Sentry.
  if (!sentryDsnConfigured(wtSentryDsn)) {
    await _startUp();
    return;
  }

  final identity = await SentryStartup.readIdentity();
  final startup = SentryStartup.fromEnvironment(
    identity: identity,
    releaseMode: kReleaseMode,
  );
  var appRunnerStarted = false;
  try {
    await SentryFlutter.init(
      startup.configure,
      appRunner: () async {
        appRunnerStarted = true;
        await _startUp(identity: identity, sentryEnabled: true);
      },
    );
  } catch (error, stackTrace) {
    // A malformed or rotated DSN must not leave the user on a blank screen.
    if (!appRunnerStarted) {
      await _startUp(identity: identity);
    } else {
      // The app runner had already begun; a real startup failure must stay
      // visible instead of turning into a silent blank screen.
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

/// The startup without Sentry, plus the diagnostics that are inert without a
/// DSN.
Future<void> _startUp({
  BuildIdentity? identity,
  bool sentryEnabled = false,
}) async {
  // Started before Firebase so the iOS package-info call overlaps its init.
  final identityFuture = identity == null
      ? SentryStartup.readIdentity()
      : Future<BuildIdentity>.value(identity);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final launchIdentity = await identityFuture;

  final diagnostics = createLaunchDiagnostics(
    identity: launchIdentity,
    consoleEnabled: kDebugMode,
    sentryTransport: sentryEnabled ? LiveSentryTransport() : null,
  );
  setupServiceLocator(appLog: diagnostics.log);

  await _activateAppCheck();

  // The update gate runs at startup, after Firebase is ready. It fails open:
  // only an explicit minimum from Remote Config can block the app.
  final updateDecision = await _checkForUpdate();
  if (updateDecision.isBlocked) {
    runApp(
      UpdateRequiredApp(
        message: updateDecision.message,
        onUpdate: _updateLauncher(updateDecision.updateUrl),
        onCheckAgain: _checkForUpdateAgain,
      ),
    );
    return;
  }

  _startApp();
}

/// Runs the gate, treating any unexpected failure as "do not block".
Future<UpdateDecision> _checkForUpdate() =>
    checkForUpdate(() => getIt<AppUpdateService>().check());

bool _appStarted = false;
late final DeepLinkService _deepLinks;

void _startApp() {
  if (_appStarted) {
    return;
  }
  startApp(links: _deepLinks, auth: getIt<AuthService>(), mount: runApp);
  _appStarted = true;
}

/// Composition step shared with the startup test: apply a queued link to the
/// router, mount the app, then forward warm links.
@visibleForTesting
void startApp({
  required DeepLinkService links,
  required AuthService auth,
  required void Function(WishTogetherApp app) mount,
}) {
  final initialLocation = links.takePendingLocation();
  final log = appLogOrNull;
  if (log != null) {
    // Seed the session route before anything else is reported, so an event on a
    // deep-link cold start carries the page the user actually opened.
    // routeChanged redacts the location; the event then reports the pattern
    // the session actually holds.
    log.routeChanged(initialLocation ?? '/');
    log.event(
      SessionStartEvent(
        build: log.session.build,
        platform: log.session.platform,
        route: log.session.route,
      ),
    );
  }

  final router = createRouter(auth, initialLocation: initialLocation);
  mount(WishTogetherApp(router: router));
  links.attach((location) => router.go(location));
}

/// Re-runs the gate and, when it is conclusively satisfied, replaces the
/// blocker with the app.
///
/// A retry that merely fails open must not unlock a confirmed block: offline
/// users could otherwise tap through the gate.
Future<bool> _checkForUpdateAgain() {
  return retryUpdateGate(check: _checkForUpdate, start: _startApp);
}

/// Builds the blocking screen's update action, or null when no usable URL is
/// configured (which disables the button).
///
/// Returns whether the store opened, so the screen can show a fallback message
/// when it did not.
Future<bool> Function()? _updateLauncher(String updateUrl) {
  final uri = parseUpdateUrl(updateUrl);
  if (uri == null) {
    return null;
  }
  return () async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        debugPrint('App update gate: could not open $uri');
      }
      return opened;
    } catch (error) {
      debugPrint('App update gate: could not open $uri: $error');
      return false;
    }
  };
}

/// Activates App Check on iOS using the DeviceCheck provider.
///
/// Web and Android are intentionally left untouched here: web auth is handled
/// elsewhere, and Android is out of scope for this cycle.
Future<void> _activateAppCheck() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  await FirebaseAppCheck.instance.activate(
    providerApple: const AppleDeviceCheckProvider(),
  );
}

class WishTogetherApp extends StatelessWidget {
  final GoRouter router;

  const WishTogetherApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: router,
      title: 'WishTogether',
      // The DEBUG ribbon is noise in screenshots and demos. It only ever
      // renders in debug builds, so this has no effect on release.
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
