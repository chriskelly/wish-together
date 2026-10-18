import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
// Always use the real `google_sign_in` package on the platforms it supports:
// native (iOS/Android) and web. On web the plugin shares
// `GoogleSignInPlatform.instance` with `google_sign_in_web`'s rendered button,
// so subscribing to `onCurrentUserChanged` here completes the Firebase
// credential exchange on both web and native. The compile-time stub returns
// `null` from `signIn()`, which silently no-ops the native Google button in
// `login_page.dart`.
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';

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

/// The `FirebaseAuthException` code raised when the user dismisses a
/// re-authentication prompt.
///
/// The delete-account flow treats a dismissal as "nothing happened" — the
/// error mapper returns `null`, so the UI stays silent.
const String reauthCancelledCode = 'reauth-cancelled';

/// The `FirebaseAuthException` code raised by the re-authentication helpers when
/// there is no signed-in user to re-authenticate.
const String _noCurrentUserCode = 'no-current-user';

class AuthService {
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

  /// The pending web phone sign-in, set by [startWebPhoneSignIn] and consumed by
  /// [confirmPhoneCode]. Web only.
  ConfirmationResult? _webConfirmation;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
       _googleSignIn =
           googleSignIn ??
           GoogleSignIn(
             // On iOS the plugin reads the iOS OAuth client (CLIENT_ID) from the
             // bundled GoogleService-Info.plist. Passing the web client id here
             // would not match the reversed-client-ID URL scheme configured in
             // Info.plist.
             clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                 ? null
                 : clientId,
           ),
       _fetchAppleCredential =
           appleCredentialFetcher ?? SignInWithApple.getAppleIDCredential {
    // Listen to Google Sign-In user changes
    _googleSignIn.onCurrentUserChanged.listen((
      GoogleSignInAccount? account,
    ) async {
      if (account != null) {
        // User is signed in with Google, now authenticate with Firebase
        try {
          final GoogleSignInAuthentication googleAuth =
              await account.authentication;
          final AuthCredential credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          // Only sign in with Firebase if not already signed in
          if (_auth.currentUser == null) {
            await _auth.signInWithCredential(credential);
          }
        } catch (e) {
          debugPrint("Error during Firebase authentication: $e");
          // If Firebase auth fails, sign out of Google to allow for a clean retry
          await _googleSignIn.signOut();
        }
      }
    });
  }

  // Sign out from both Firebase and Google
  Future<void> signOut() async {
    debugPrint("signed-out");
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Expose the GoogleSignIn instance for the UI to use
  GoogleSignIn get googleSignIn => _googleSignIn;

  String? get currentUserId => _auth.currentUser?.uid;

  String? get currentUserEmail => _auth.currentUser?.email;

  String? get currentUserPhoneNumber => _auth.currentUser?.phoneNumber;

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(PhoneAuthCredential) verificationCompleted,
    required Function(FirebaseAuthException) verificationFailed,
    required Function(String, int?) codeSent,
    required Function(String) codeAutoRetrievalTimeout,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  Future<UserCredential> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    return await _auth.signInWithCredential(credential);
  }

  /// Starts a phone sign-in on the web platform.
  ///
  /// Web uses the documented `signInWithPhoneNumber` API, which manages the
  /// reCAPTCHA challenge and returns a [ConfirmationResult]. The result is kept
  /// so [confirmPhoneCode] can finish the flow with the SMS code. Returns the
  /// verification id to route to the code-entry page.
  Future<String> startWebPhoneSignIn(String phoneNumber) async {
    final confirmationResult = await _auth.signInWithPhoneNumber(phoneNumber);
    _webConfirmation = confirmationResult;
    return confirmationResult.verificationId;
  }

  /// Finishes a phone sign-in with the SMS code sent to the user.
  ///
  /// On web the stashed [ConfirmationResult] is confirmed; on native a
  /// [PhoneAuthProvider] credential is built from the verification id and code.
  Future<UserCredential> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (_isWeb) {
      final confirmationResult = _webConfirmation;
      if (confirmationResult == null) {
        throw StateError(
          'No web phone sign-in in progress. Call startWebPhoneSignIn first.',
        );
      }
      return confirmationResult.confirm(smsCode);
    }
    return _auth.signInWithCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
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
    return _auth.signInWithCredential(await _freshAppleCredential());
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
  List<String> get providerIds =>
      _auth.currentUser?.providerData.map((info) => info.providerId).toList() ??
      const <String>[];

  /// Re-authenticates the current user with Google.
  ///
  /// Web uses the SDK's popup, which manages the Google OAuth flow itself. On
  /// native platforms a fresh Google credential is exchanged, because Firebase
  /// requires a recent login before sensitive operations such as deleting an
  /// account.
  Future<void> reauthenticateWithGoogle() async {
    final user = _requireCurrentUser();
    if (_isWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
      return;
    }

    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw FirebaseAuthException(
        code: reauthCancelledCode,
        message: 'The Google account picker was dismissed.',
      );
    }
    final googleAuth = await account.authentication;
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      ),
    );
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
    // Start the clock before calling the platform: a method channel that never
    // returns must not defeat the bound.
    final verification = result.future.timeout(timeout);
    // The callbacks can fire before the caller awaits the future. Mark it as
    // observed now, so a failure is not *also* reported as an unhandled async
    // error; the caller's await still sees it.
    verification.ignore();

    // Deliberately not awaited: the timeout above has to cover the platform call
    // itself, so its error is forwarded into the completer instead.
    unawaited(
      verifyPhoneNumber(
        phoneNumber: phoneNumber,
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

  /// Deletes the signed-in user's account, then revokes the Google grant.
  ///
  /// Requires a recent login: `User.delete()` throws `requires-recent-login`
  /// otherwise, which the caller resolves by re-authenticating first. Does
  /// nothing when nobody is signed in — the delete-account use case requires a
  /// session long before it gets here.
  ///
  /// The Google grant is revoked with `disconnect()`, not merely signed out:
  /// deleting an account must also drop the app's access to the provider
  /// account, and `disconnect()` stops the account listener from trying to
  /// re-establish a session for the deleted account at the same time.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    await user.delete();
    try {
      await _googleSignIn.disconnect();
    } catch (error) {
      // The account is already gone, so a failed revocation must not be
      // reported as a failed deletion — but it must not vanish either: it is
      // the only signal that the Google grant is still active.
      debugPrint('Google revocation failed after account deletion: $error');
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
