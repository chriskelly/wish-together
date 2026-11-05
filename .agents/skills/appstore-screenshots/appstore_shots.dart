// App Store screenshot entrypoint — the template committed with this skill.
//
// `capture.sh` copies it to `lib/dev/scenarios/local/appstore_shots.dart`, which
// is gitignored: nothing in lib/ imports it, and a fresh clone must compile
// without it. Edit the copy rather than this template when a capture needs a
// change, then bring the change back here.
//
// Signs in with a dev token minted for a synthetic uid against the named
// staging database, then mounts the production app shell on one route.
//
// Two compile-time inputs drive the screen into the state to photograph, so a
// capture needs no Simulator GUI:
//
//   WT_SHOT_SCROLL=<logical px>   scroll the page down that far
//   WT_SHOT_TAP=<x>,<y>           tap that logical point (e.g. the app bar's
//                                 claim-status toggle)
//
// Both dispatch real pointer events, so the UI reaches the state a person
// would; nothing here fakes a widget.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/firebase_options.dart';
import 'package:wishtogether/main.dart';

const String shotRoute = String.fromEnvironment(
  'WT_SHOT_ROUTE',
  defaultValue: '/',
);
const String shotSignedOut = String.fromEnvironment('WT_SHOT_SIGNED_OUT');
const String devToken = String.fromEnvironment('WT_DEV_TOKEN');
const int shotScroll = int.fromEnvironment('WT_SHOT_SCROLL');
const String shotTap = String.fromEnvironment('WT_SHOT_TAP');

/// Long enough for sign-in, the user document and the list's first snapshot.
const Duration settleBeforeAction = Duration(seconds: 7);
const Duration settleAfterAction = Duration(seconds: 2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (shotSignedOut != 'true') {
    await FirebaseAuth.instance.signInWithCustomToken(devToken);
  }
  final firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    // Hardcoded on purpose: a listing capture must never read production, even
    // if the surrounding shell defines something else.
    databaseId: 'staging',
  );
  // Null authSession lets the locator build the production AuthService over the
  // signed-in FirebaseAuth instance.
  setupServiceLocator(firestore: firestore, authSession: null);
  runApp(
    WishTogetherApp(
      router: createRouter(getIt<AuthSession>(), initialLocation: shotRoute),
    ),
  );
  unawaited(_driveIfAsked());
}

Future<void> _driveIfAsked() async {
  if (shotScroll == 0 && shotTap.isEmpty) return;
  await Future<void>.delayed(settleBeforeAction);
  final binding = GestureBinding.instance;
  if (shotScroll != 0) {
    // A pointer signal is what a trackpad or wheel sends; Scrollable applies it
    // exactly like a drag, without a gesture arena to time.
    const centre = Offset(220, 620);
    binding.handlePointerEvent(
      PointerScrollEvent(
        position: centre,
        scrollDelta: Offset(0, shotScroll.toDouble()),
      ),
    );
  }
  if (shotTap.isNotEmpty) {
    final parts = shotTap.split(',');
    final point = Offset(double.parse(parts[0]), double.parse(parts[1]));
    const pointer = 4711;
    binding.handlePointerEvent(
      PointerDownEvent(
        pointer: pointer,
        position: point,
        kind: PointerDeviceKind.touch,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    binding.handlePointerEvent(
      PointerUpEvent(
        pointer: pointer,
        position: point,
        kind: PointerDeviceKind.touch,
      ),
    );
  }
  await Future<void>.delayed(settleAfterAction);
}
