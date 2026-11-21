import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
// The service imports the real package on every platform: native flows call
// `authenticate()`, and on web the plugin shares `GoogleSignIn.instance` with
// `google_sign_in_web`'s rendered button, whose `authenticationEvents` this
// service exchanges for Firebase credentials. The compile-time stub in
// `google_sign_in_stub.dart` only supplies `renderButton` on non-web builds.
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/google_auth_error.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';

/// Fetches an Apple ID credential.
///
/// Injectable because the production implementation — the static
/// `SignInWithApple.getAppleIDCredential` — cannot be mocked directly, so
/// [AuthService.signInWithApple] would otherwise be untestable.
typedef AppleCredentialFetcher =
    Future<AuthorizationCredentialAppleID> Function({
      required List<AppleIDAuthorizationScopes> scopes,
      String? nonce,
    });

/// One initialization future per Google Sign-In plugin instance.
///
/// v7 allows `initialize()` exactly once per process, and web throws a
/// `StateError` on a second call. `AuthService` is rebuilt by tests and the
/// live dev session, so the future is keyed by the plugin instance:
/// production's singleton is initialized exactly once, while a test's fresh
/// mock gets its own.
final Expando<Future<void>> _googleSignInInitializations =
    Expando<Future<void>>('Google Sign-In initialization');

/// One web `authenticationEvents` subscription per plugin instance.
///
/// The stream is broadcast, so two listeners would exchange one sign-in twice.
/// The first service to prepare an instance owns its events; production has
/// exactly one service.
final Expando<StreamSubscription<GoogleSignInAuthenticationEvent>>
_googleSignInWebEvents =
    Expando<StreamSubscription<GoogleSignInAuthenticationEvent>>(
      'Google Sign-In web events',
    );

/// The `FirebaseAuthException` code raised when the user dismisses a
/// re-authentication prompt.
///
/// The delete-account flow treats a dismissal as "nothing happened" — the
/// error mapper returns `null`, so the UI stays silent.
const String reauthCancelledCode = 'reauth-cancelled';

/// The `FirebaseAuthException` code raised by the re-authentication helpers when
/// there is no signed-in user to re-authenticate.
const String _noCurrentUserCode = 'no-current-user';

/// The Firebase code that means the user backed out of the web phone prompt
/// without becoming an auth failure.
///
/// Google's v7 cancellations are recognised by [isGoogleSignInCancellation];
/// the delete flow's popup codes are mapped by `delete_account_error.dart`.
const String _webPhoneCancellationCode = 'web-context-canceled';

/// The production [AuthSession]: Firebase Auth, Google Sign-In and Sign in with
/// Apple, plus the sign-in, re-authentication and deletion flows that need them.
class AuthService implements AuthSession {
  /// The web OAuth client id. Used by the web build and as the server client id.
  static String clientId =
      "1063002805065-eobumao8o4tk4s54ea41jogjvls62pu5.apps.googleusercontent.com";

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  /// Whether the app is running on the web platform. Injectable for tests.
  final bool _isWeb;

  /// Fetches the Apple ID credential. Injectable for tests; defaults to the
  /// real [SignInWithApple.getAppleIDCredential].
  final AppleCredentialFetcher _fetchAppleCredential;

  /// The pending web phone sign-in: set by [startWebPhoneSignIn], cleared by a
  /// successful [confirmPhoneCode] and by [discardPendingPhoneSignIn]. Web only.
  ConfirmationResult? _webConfirmation;

  /// This service's memoized [prepareGoogleSignIn] future.
  Future<void>? _googleSignInReady;

  /// Whether initialization completed. A pending or failed initialize owns no
  /// Google session, so sign-out and deletion must not wait for it.
  bool _googleSignInInitialized = false;

  /// The signed-in user's id on every auth transition, and `null` on sign-out.
  @override
  Stream<String?> get uidChanges =>
      _auth.authStateChanges().map((user) => user?.uid);

  /// [auth], [isWeb], [appleCredentialFetcher] and [googleSignIn] are injectable
  /// so the platform-specific sign-in and re-authentication flows can be unit
  /// tested; production callers use the defaults.
  AuthService({
    FirebaseAuth? auth,
    bool? isWeb,
    AppleCredentialFetcher? appleCredentialFetcher,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _isWeb = isWeb ?? kIsWeb,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _fetchAppleCredential =
           appleCredentialFetcher ?? SignInWithApple.getAppleIDCredential;

  /// Initializes the Google Sign-In singleton for this process.
  ///
  /// Web's rendered button stays in its "Getting ready" state until this
  /// completes, so the login page starts it when it opens. Native flows await
  /// it before their first SDK call. The future is memoized per service, and
  /// the plugin call is memoized per plugin instance: v7 allows one
  /// `initialize()`, and web throws on a second.
  Future<void> prepareGoogleSignIn() =>
      _googleSignInReady ??= _initializeGoogleSignIn();

  Future<void> _initializeGoogleSignIn() async {
    if (_isWeb) {
      _googleSignInWebEvents[_googleSignIn] ??= _googleSignIn
          .authenticationEvents
          .listen(
            _handleWebAuthenticationEvent,
            onError: _handleWebAuthenticationError,
          );
    }
    await (_googleSignInInitializations[_googleSignIn] ??=
        _initializeGoogleSignInOnce());
    _googleSignInInitialized = true;
  }

  Future<void> _initializeGoogleSignInOnce() async {
    try {
      // Web needs its OAuth client id. iOS reads the iOS client from the
      // bundled GoogleService-Info.plist when none is passed, and its reversed
      // client id is the URL scheme in Info.plist. Android's v7 plugin takes no
      // clientId and needs the web client as the server client id so Firebase
      // receives an idToken.
      await _googleSignIn.initialize(
        clientId: _isWeb ? clientId : null,
        serverClientId:
            !_isWeb && defaultTargetPlatform == TargetPlatform.android
            ? clientId
            : null,
      );
    } catch (error, stackTrace) {
      // One record for the process: a second service reuses this future.
      appLogOrNull?.error(
        error,
        stackTrace,
        code: 'google-sign-in-init-failed',
      );
      rethrow;
    }
  }

  /// Signs in with Google on a platform where the app owns the button.
  ///
  /// Web is excluded: the GIS SDK requires its own rendered button, and
  /// [prepareGoogleSignIn]'s event listener handles that flow. A call here on
  /// web is a programming error and throws `uiUnavailable`.
  Future<UserCredential> signInWithGoogle() async {
    if (_isWeb) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.uiUnavailable,
        description: 'Web sign-in uses the rendered Google button.',
      );
    }
    GoogleSignInAccount? account;
    try {
      await prepareGoogleSignIn();
      account = await _googleSignIn.authenticate();
      return await _auth.signInWithCredential(_googleCredential(account));
    } catch (error) {
      // A failed initialization already recorded one process error in the
      // shared initializer; this attempt still reports its own one warning.
      _reportAuthFailure(AuthOutcome.google, error);
      if (account != null) {
        await _signOutOfGoogleQuietly();
      }
      rethrow;
    }
  }

  void _handleWebAuthenticationEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      unawaited(_signInWithWebAccount(event.user));
    }
  }

  Future<void> _signInWithWebAccount(GoogleSignInAccount account) async {
    if (_auth.currentUser != null) {
      return;
    }
    try {
      await _auth.signInWithCredential(_googleCredential(account));
    } catch (error) {
      _reportAuthFailure(AuthOutcome.google, error);
      await _signOutOfGoogleQuietly();
    }
  }

  void _handleWebAuthenticationError(Object error, StackTrace stackTrace) {
    _reportAuthFailure(AuthOutcome.google, error);
  }

  /// The Firebase credential for an authenticated Google account.
  ///
  /// v7 separates authentication from authorization: authentication yields
  /// only an idToken, which is all Firebase needs.
  OAuthCredential _googleCredential(GoogleSignInAccount account) {
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Google returned no ID token.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Signs out of Google without letting a failure reach the caller.
  ///
  /// Used to drop a session whose Firebase exchange failed (so a retry starts
  /// clean) and by sign-out, where a Google failure must not keep the Firebase
  /// credential alive.
  Future<void> _signOutOfGoogleQuietly() async {
    try {
      await _googleSignIn.signOut();
    } catch (error, stackTrace) {
      appLogOrNull?.error(error, stackTrace, code: 'google-sign-out-failed');
    }
  }

  // Sign out from both Firebase and Google.
  //
  // The sign-out transition is reported by the router's auth listener (it is
  // the only app-wide subscription); a Google sign-out failure is the one thing
  // logged here. A pending or failed Google initialization owns no session, so
  // it is skipped rather than awaited.
  @override
  Future<void> signOut() async {
    if (_googleSignInInitialized) {
      await _signOutOfGoogleQuietly();
    }
    await _auth.signOut();
  }

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  String? get currentUserEmail => _auth.currentUser?.email;

  @override
  String? get currentUserPhoneNumber => _auth.currentUser?.phoneNumber;

  /// In-app deletion re-authenticates against the real provider and deletes the
  /// real auth account, so the production session always offers it.
  @override
  bool get supportsAccountDeletion => true;

  /// Production has a sign-in flow to return to, and signs out for real.
  @override
  bool get supportsSignOut => true;

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) verificationCompleted,
    required Function(FirebaseAuthException) verificationFailed,
    required Function(String, int?) codeSent,
    required Function(String) codeAutoRetrievalTimeout,
    bool Function()? claimFailureReport,
  }) async {
    // The plugin can report the same failure through both the callback and the
    // returned future; count it once for the auth-failure alert. A caller that
    // reports failures of its own — the timeout guard in
    // [startPhoneVerification] — passes [claimFailureReport] so the attempt is
    // counted once overall, not once per path.
    final localOnce = _FailureOnce();
    final claim = claimFailureReport ?? localOnce.claim;
    void reportFailure(Object error) {
      if (!claim()) {
        return;
      }
      _reportAuthFailure(AuthOutcome.phone, error);
    }

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: verificationCompleted,
        verificationFailed: (error) {
          reportFailure(error);
          verificationFailed(error);
        },
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      );
    } catch (error) {
      reportFailure(error);
      rethrow;
    }
  }

  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      return await _auth.signInWithCredential(credential);
    } catch (error) {
      _reportAuthFailure(AuthOutcome.phone, error);
      rethrow;
    }
  }

  /// Starts a phone sign-in on the web platform.
  ///
  /// Web uses the documented `signInWithPhoneNumber` API, which manages the
  /// reCAPTCHA challenge and returns a [ConfirmationResult]. The result is kept
  /// so [confirmPhoneCode] can finish the flow with the SMS code. Returns the
  /// verification id to route to the code-entry page.
  Future<String> startWebPhoneSignIn(String phoneNumber) async {
    try {
      final confirmationResult = await _auth.signInWithPhoneNumber(phoneNumber);
      _webConfirmation = confirmationResult;
      return confirmationResult.verificationId;
    } catch (error) {
      _reportAuthFailure(AuthOutcome.phone, error);
      rethrow;
    }
  }

  /// Finishes a phone sign-in with the SMS code sent to the user.
  ///
  /// On web the stashed [ConfirmationResult] is confirmed; it is dropped once
  /// that succeeds, because a confirmed sign-in has no pending step left, while
  /// a rejected code keeps it so the user can retry. On native a
  /// [PhoneAuthProvider] credential is built from the verification id and code.
  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      if (_isWeb) {
        final confirmationResult = _webConfirmation;
        if (confirmationResult == null) {
          throw StateError(
            'No web phone sign-in in progress. Call startWebPhoneSignIn first.',
          );
        }
        final credential = await confirmationResult.confirm(smsCode);
        _webConfirmation = null;
        return credential;
      }
      return await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
        ),
      );
    } catch (error) {
      _reportAuthFailure(AuthOutcome.phone, error);
      rethrow;
    }
  }

  /// Drops a web phone sign-in the user abandoned before entering the code.
  ///
  /// Native keeps no pending state, so this is a no-op there.
  void discardPendingPhoneSignIn() {
    _webConfirmation = null;
  }

  /// Signs in with Apple and exchanges the credential for a Firebase session.
  ///
  /// Does not check the platform: `SignInWithApple.getAppleIDCredential` throws
  /// where Sign in with Apple is unavailable (web/Android without web auth
  /// options), so callers must gate this by platform.
  ///
  /// A per-attempt nonce guards against replay: Apple receives the SHA-256 of
  /// the raw nonce (which it embeds in the identity token), and Firebase
  /// receives the raw nonce to compare against that claim.
  Future<UserCredential> signInWithApple() async {
    try {
      return await _auth.signInWithCredential(await _freshAppleCredential());
    } catch (error) {
      _reportAuthFailure(AuthOutcome.apple, error);
      rethrow;
    }
  }

  /// The provider that issued the current ID token (`google.com`, `apple.com`
  /// or `phone`), or `null` when nobody is signed in.
  ///
  /// Firebase can link several providers onto one account (same-email Google +
  /// Apple), so the account's provider list cannot say which one this session
  /// used — only the token can.
  Future<String?> signInProvider() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    final idTokenResult = await user.getIdTokenResult();
    return idTokenResult.signInProvider;
  }

  /// The provider ids linked to the signed-in account.
  @override
  List<String> get providerIds =>
      _auth.currentUser?.providerData.map((info) => info.providerId).toList() ??
      const <String>[];

  /// Re-authenticates the current user with Google.
  ///
  /// Web uses the SDK's popup, which manages the Google OAuth flow itself. On
  /// native platforms a fresh Google credential is exchanged, because Firebase
  /// requires a recent login before sensitive operations such as deleting an
  /// account. A dismissed picker keeps the delete flow's silent
  /// [reauthCancelledCode].
  Future<void> reauthenticateWithGoogle() async {
    final user = _requireCurrentUser();
    if (_isWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }

    try {
      await prepareGoogleSignIn();
      final account = await _googleSignIn.authenticate();
      await user.reauthenticateWithCredential(_googleCredential(account));
    } on GoogleSignInException catch (error) {
      if (isGoogleSignInCancellation(error)) {
        throw FirebaseAuthException(
          code: reauthCancelledCode,
          message: 'The Google account picker was dismissed.',
        );
      }
      _reportAuthFailure(AuthOutcome.google, error);
      rethrow;
    }
  }

  /// Re-authenticates the current user with Apple.
  ///
  /// Like [signInWithApple], this requires a per-attempt nonce; unlike it, the
  /// fresh credential re-authenticates the existing session rather than
  /// creating a new one.
  Future<void> reauthenticateWithApple() async {
    final user = _requireCurrentUser();
    await user.reauthenticateWithCredential(await _freshAppleCredential());
  }

  /// Re-authenticates the current user with a fresh SMS code.
  ///
  /// The verification id comes from the usual phone flow ([verifyPhoneNumber]
  /// on native, [startWebPhoneSignIn] on web); only the code's credential is
  /// consumed here.
  Future<void> reauthenticateWithPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final user = _requireCurrentUser();
    await user.reauthenticateWithCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
  }

  /// Re-authenticates the current user with a credential the platform verified
  /// itself (Android instant verification).
  Future<void> reauthenticateWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final user = _requireCurrentUser();
    await user.reauthenticateWithCredential(credential);
  }

  /// Whether the app is running on web, per the injectable [isWeb] value.
  bool get isWeb => _isWeb;

  /// Starts a phone verification for [phoneNumber].
  ///
  /// Native reports progress through callbacks, and the platform may verify the
  /// device on its own (Android instant verification, which sends no SMS) — so
  /// the outcome says which route to take rather than assuming a code was sent.
  /// [timeout] bounds that callback wait so a platform that never reports cannot
  /// hang the caller.
  ///
  /// The web path is the SDK's reCAPTCHA challenge, which is interactive and is
  /// deliberately not capped: a user solving a challenge must not be timed out.
  Future<PhoneVerification> startPhoneVerification(
    String phoneNumber, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (_isWeb) {
      return PhoneVerificationCodeSent(await startWebPhoneSignIn(phoneNumber));
    }

    final result = Completer<PhoneVerification>();
    // One failure per attempt, shared by the timeout guard and the platform
    // callbacks: a platform that times out and then reports the same failure
    // must not produce two auth-failure events.
    final failureOnce = _FailureOnce();
    // Start the clock before calling the platform: a method channel that never
    // returns must not defeat the bound.
    final verification = _boundedVerification(
      result.future,
      timeout,
      failureOnce,
    );
    // The callbacks can fire before the caller awaits the future. Mark it as
    // observed now, so a failure is not *also* reported as an unhandled async
    // error; the caller's await still sees it.
    verification.ignore();

    // Deliberately not awaited: the timeout above has to cover the platform call
    // itself, so its error is forwarded into the completer instead.
    unawaited(
      verifyPhoneNumber(
        phoneNumber: phoneNumber,
        claimFailureReport: failureOnce.claim,
        verificationCompleted: (credential) {
          if (!result.isCompleted) {
            result.complete(PhoneVerificationAutoVerified(credential));
          }
        },
        verificationFailed: (error) {
          if (!result.isCompleted) {
            result.completeError(error);
          }
        },
        codeSent: (verificationId, resendToken) {
          if (!result.isCompleted) {
            result.complete(PhoneVerificationCodeSent(verificationId));
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          // Auto-retrieval gave up, but the code route is still open.
          if (!result.isCompleted) {
            result.complete(PhoneVerificationCodeSent(verificationId));
          }
        },
      ).then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!result.isCompleted) {
            result.completeError(error, stackTrace);
          }
        },
      ),
    );

    return verification;
  }

  /// Bounds the wait for a platform callback and reports a timeout.
  ///
  /// A timeout is neither the platform's `verificationFailed` nor an error from
  /// `verifyPhoneNumber`, so before this guard a hung verification produced no
  /// record at all — on the primary iOS path. It is its own failure, with its
  /// own code, and it is counted once.
  Future<PhoneVerification> _boundedVerification(
    Future<PhoneVerification> verification,
    Duration timeout,
    _FailureOnce failureOnce,
  ) async {
    try {
      return await verification.timeout(timeout);
    } on TimeoutException {
      // The platform may still report its own failure after the bound fired;
      // [failureOnce] keeps the attempt to a single event.
      if (failureOnce.claim()) {
        appLogOrNull?.event(
          const AuthStateEvent(outcome: AuthOutcome.phone, code: 'timeout'),
        );
      }
      rethrow;
    }
  }

  /// Deletes the signed-in user's account, then revokes a linked Google grant.
  ///
  /// Requires a recent login: `User.delete()` throws `requires-recent-login`
  /// otherwise, which the caller resolves by re-authenticating first. Does
  /// nothing when nobody is signed in — the delete-account use case requires a
  /// session long before it gets here.
  ///
  /// The Google grant is revoked with `disconnect()`, not merely signed out:
  /// deleting an account must also drop the app's access to the provider
  /// account. The link is read before the delete because a phone or Apple
  /// re-authentication does not prove the account has no Google link. v7 keeps
  /// no restored Google session, so the attempt is bounded and best-effort: a
  /// pending third-party SDK must never block a deletion that already
  /// happened. [googleRevokeTimeout] bounds the prepare and disconnect pair.
  Future<void> deleteAccount({
    Duration googleRevokeTimeout = const Duration(seconds: 5),
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    final googleLinked = providerIds.contains('google.com');
    await user.delete();
    if (!googleLinked) {
      return;
    }
    try {
      await prepareGoogleSignIn()
          .then((_) => _googleSignIn.disconnect())
          .timeout(googleRevokeTimeout);
    } catch (error, stackTrace) {
      // The account is already gone, so a failed revocation must not be
      // reported as a failed deletion — but it must not vanish either: it is
      // the only signal that the Google grant is still active.
      appLogOrNull?.error(error, stackTrace, code: 'google-revoke-failed');
    }
  }

  /// Builds a fresh Apple credential for a new session or a re-authentication.
  ///
  /// Apple receives the SHA-256 of the raw nonce (which it embeds in the
  /// identity token), and Firebase receives the raw nonce to compare against
  /// that claim.
  Future<OAuthCredential> _freshAppleCredential() async {
    final rawNonce = generateNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await _fetchAppleCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: appleMissingIdTokenCode,
        message: 'Apple did not return an identity token.',
      );
    }

    return OAuthProvider('apple.com').credential(
      idToken: idToken,
      // Apple's authorization code goes in `accessToken`: Firebase expects it
      // here for the native iOS exchange.
      accessToken: appleCredential.authorizationCode,
      rawNonce: rawNonce,
    );
  }

  /// Reports a failed sign-in attempt with its provider and structured code.
  ///
  /// The identifier the user typed is never passed: only the code, which is
  /// what the auth-failure alert counts. A cancellation is a breadcrumb, not an
  /// auth-failure event.
  void _reportAuthFailure(AuthOutcome outcome, Object error) {
    appLogOrNull?.event(
      AuthStateEvent(outcome: outcome, code: _authFailureCode(error)),
    );
  }

  /// The reportable code for a failure, or null when the user backed out.
  String? _authFailureCode(Object error) {
    if (isGoogleSignInCancellation(error)) {
      return null;
    }
    if (error is GoogleSignInException) {
      return redactCode(googleSignInFailureCode(error));
    }
    final code = readErrorCode(error);
    return code == _webPhoneCancellationCode ? null : code;
  }

  /// The signed-in user, or a [FirebaseAuthException] when there is none.
  User _requireCurrentUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: _noCurrentUserCode,
        message: 'No user is signed in.',
      );
    }
    return user;
  }
}

/// A one-shot claim, so one auth attempt reports at most one failure.
class _FailureOnce {
  bool _claimed = false;

  bool claim() {
    if (_claimed) {
      return false;
    }
    _claimed = true;
    return true;
  }
}
