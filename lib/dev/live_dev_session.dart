import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:wishtogether/core/firestore_target.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/dev_error_screen.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/firebase_options.dart';
import 'package:wishtogether/main.dart';

/// Starts Firebase for a live session.
typedef DevFirebaseInitializer = Future<void> Function();

/// Signs in with a custom token.
typedef DevCustomTokenSignIn = Future<void> Function(String token);

/// Opens the Firestore instance for one database id.
typedef DevFirestoreFactory = FirebaseFirestore Function(String databaseId);

/// Builds a live session: real Firebase, a real sign-in, and real Firestore
/// pointed at [LiveDevLaunch.databaseId].
///
/// Nothing here chooses the database: [resolveDevLaunch] already refused every
/// value that could mean production, so this only has to use what it was given.
/// It also decides only one capability: [liveDevSession] installs a session that
/// hides account deletion unless the build asked for it.
///
/// The collaborators are injectable so the failure paths can be tested without
/// a Firebase project. Production never imports this file.
Future<Widget> buildLiveDevApp(
  LiveDevLaunch launch, {
  DevFirebaseInitializer initializeFirebase = initializeLiveDevFirebase,
  DevCustomTokenSignIn signIn = signInWithLiveDevToken,
  DevFirestoreFactory createFirestore = createLiveDevFirestore,
  AuthSession Function()? createSession,
}) async {
  try {
    await initializeFirebase();
  } catch (error) {
    return buildLiveStartFailureApp(error);
  }

  try {
    await signIn(launch.token);
  } catch (error) {
    return buildLiveSignInFailureApp(launch, error);
  }

  // App Check is deliberately not activated: this is a local debug tool, and
  // activating a provider it has no registration for would only add a failure.
  final firestore = createFirestore(launch.databaseId);

  // The shell gets a real session — the real uid stream, the real providers and
  // a real sign-out — with the one capability a dev session must not offer
  // removed: deleting the account. See [liveDevSession].
  final installedSession = liveDevSession(launch, createSession: createSession);
  setupServiceLocator(
    firestore: firestore,
    appLog: buildDevLog(),
    authSession: installedSession,
  );
  final session = getIt<AuthSession>();

  return WishTogetherApp(
    router: createRouter(session),
    pageFrame: (pages) => DevSessionFrame.live(
      launch.databaseId,
      ignoredScenario: launch.ignoredScenario,
      pages: pages,
    ),
  );
}

/// The live session with the danger zone removed.
///
/// It is a real [AuthService], so the locator registers it as one: `AuthService`
/// still resolves (the sign-in and verification screens build, and sign-out
/// works) and only the profile page's account-deletion section disappears.
///
/// Deletion is the one thing a dev session must not offer: the cascade
/// re-authenticates against the real provider and then deletes a real Auth user,
/// and the Auth project is shared with production.
class LiveDevAuthService extends AuthService {
  LiveDevAuthService({
    super.auth,
    super.isWeb,
    super.appleCredentialFetcher,
    super.googleSignIn,
  });

  @override
  bool get supportsAccountDeletion => false;
}

/// The session a live launch installs.
///
/// Null means "let the locator build the production `AuthService`", which is the
/// only shape that offers in-app account deletion, so it is used only when the
/// build set `WT_DEV_ALLOW_ACCOUNT_DELETION=true`.
///
/// [createSession] is the single seam for tests: they pass a session that needs
/// no Firebase, both to pump the composition and to exercise this branch.
AuthSession? liveDevSession(
  LiveDevLaunch launch, {
  AuthSession Function()? createSession,
}) {
  if (launch.allowAccountDeletion) {
    return null;
  }
  return (createSession ?? LiveDevAuthService.new)();
}

/// Boots a live session in the browser.
Future<void> runLiveDevSession(LiveDevLaunch launch) async {
  prepareDevBrowser();
  runApp(await buildLiveDevApp(launch));
}

/// The page shown when Firebase itself could not start.
Widget buildLiveStartFailureApp(Object error) => buildDevPageApp(
  DevFailureScreen(
    label: devNotStartedLabel,
    headline: 'Live dev mode could not start Firebase',
    details: <String>[
      'Firebase.initializeApp failed with ${error.runtimeType}.',
      'Check that this build carries the web Firebase options for '
          'wish-together-project.',
    ],
  ),
);

/// The page shown when the token was rejected.
///
/// A rejected token is the ordinary end of a live session — they last about an
/// hour — so the page names the command that mints the next one instead of
/// surfacing an SDK error nobody can act on. The other cause of the same
/// failure is an origin the project API key does not allow, which is why the
/// port is named too.
Widget buildLiveSignInFailureApp(LiveDevLaunch launch, Object error) =>
    buildDevPageApp(
      DevFailureScreen(
        label: devNotStartedLabel,
        headline: 'Live dev mode could not sign in',
        details: liveSignInFailureDetails(
          databaseId: launch.databaseId,
          code: error is FirebaseAuthException ? error.code : null,
          errorType: '${error.runtimeType}',
        ),
      ),
    );

/// The lines a rejected sign-in produces.
///
/// Split from the page so the text is testable without constructing an SDK
/// exception: this text is the whole fix a reader gets.
List<String> liveSignInFailureDetails({
  required String databaseId,
  required String? code,
  required String errorType,
}) => <String>[
  if (code != null)
    'Firebase rejected the token ($code).'
  else
    'Firebase sign-in failed with $errorType.',
  'A token is rejected once it has expired (they last about an hour), and also '
      'when this page is not an origin the project API key allows.',
  'Mint a new one and restart: cd scripts && npm run dev:token -- '
      '--uid <uid> --database $databaseId',
  'If a fresh token fails the same way, check the port: live mode signs in on '
      '--web-port=$devLiveWebPort. '
      '.agents/skills/preview-auth/scripts/preview-auth.sh list shows the '
      'origins the key allows.',
];

/// The production Firebase startup, without the update gate.
///
/// `lib/main.dart`'s own startup also runs the update gate and activates App
/// Check; a live session needs neither, so it composes the two steps it does
/// need rather than reusing that function.
Future<void> initializeLiveDevFirebase() =>
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

/// Signs in with the token the mint script printed.
Future<void> signInWithLiveDevToken(String token) async {
  await FirebaseAuth.instance.signInWithCustomToken(token);
}

/// The Firestore instance for [databaseId].
///
/// The id is already known to be a named database; `createFirestoreInstance`
/// resolves it again so there is one place that maps an id to an instance.
FirebaseFirestore createLiveDevFirestore(String databaseId) =>
    createFirestoreInstance(override: databaseId);
