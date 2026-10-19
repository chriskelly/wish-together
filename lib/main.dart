import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/core/service_locator.dart';
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

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _activateAppCheck();
  setupServiceLocator();

  // The update gate runs once at startup, after Firebase is ready. It fails
  // open: only an explicit minimum from Remote Config can block the app.
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
Future<UpdateDecision> _checkForUpdate() async {
  try {
    return await getIt<AppUpdateService>().check();
  } catch (error) {
    debugPrint('App update gate: unexpected failure, failing open: $error');
    return const UpdateDecision.allowed();
  }
}

bool _appStarted = false;

void _startApp() {
  if (_appStarted) {
    return;
  }
  _appStarted = true;
  final authService = getIt<AuthService>();
  runApp(WishTogetherApp(router: createRouter(authService)));
}

/// Re-runs the gate and, when it is conclusively satisfied, replaces the
/// blocker with the app.
///
/// A retry that merely fails open must not unlock a confirmed block: offline
/// users could otherwise tap through the gate.
Future<void> _checkForUpdateAgain() async {
  final decision = await _checkForUpdate();
  if (canStartFromRetry(decision)) {
    _startApp();
  }
}

/// Builds the blocking screen's update action, or null when no usable URL is
/// configured (which disables the button).
VoidCallback? _updateLauncher(String updateUrl) {
  final uri = parseUpdateUrl(updateUrl);
  if (uri == null) {
    return null;
  }
  return () {
    unawaited(() async {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened) {
          debugPrint('App update gate: could not open $uri');
        }
      } catch (error) {
        debugPrint('App update gate: could not open $uri: $error');
      }
    }());
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
