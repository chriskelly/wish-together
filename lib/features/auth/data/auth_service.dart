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

Future<AuthorizationCredentialAppleID> _getAppleIDCredential({
  required List<AppleIDAuthorizationScopes> scopes,
  String? nonce,
}) => SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);

class AuthService {
  /// The web OAuth client id. Used by the web build and as the server client id.
  static String clientId =
      "1063002805065-eobumao8o4tk4s54ea41jogjvls62pu5.apps.googleusercontent.com";

  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // On iOS the plugin reads the iOS OAuth client (CLIENT_ID) from the bundled
    // GoogleService-Info.plist. Passing the web client id here would not match
    // the reversed-client-ID URL scheme configured in Info.plist.
    clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? null
        : clientId,
  );

  /// Whether the app is running on the web platform. Injectable for tests.
  final bool _isWeb;

  /// Fetches the Apple ID credential. Injectable for tests; defaults to the
  /// real [SignInWithApple.getAppleIDCredential].
  final AppleCredentialFetcher _fetchAppleCredential;

  /// The pending web phone sign-in, set by [startWebPhoneSignIn] and consumed by
  /// [confirmPhoneCode]. Web only.
  ConfirmationResult? _webConfirmation;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// [auth], [isWeb] and [appleCredentialFetcher] are injectable so the
  /// platform-specific sign-in flows can be unit tested; production callers use
  /// the defaults.
  AuthService({
    FirebaseAuth? auth,
    bool? isWeb,
    AppleCredentialFetcher? appleCredentialFetcher,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _isWeb = isWeb ?? kIsWeb,
       _fetchAppleCredential = appleCredentialFetcher ?? _getAppleIDCredential {
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

  /// Signs in with Apple on Apple platforms.
  ///
  /// Fetches the Apple ID credential, then exchanges it for a Firebase session
  /// via an `apple.com` OAuth credential. Callers gate the button by platform;
  /// this method itself is platform-agnostic.
  ///
  /// A per-attempt nonce guards against replay: Apple receives the SHA-256 of
  /// the raw nonce (which it embeds in the identity token), and Firebase
  /// receives the raw nonce to compare against that claim.
  Future<UserCredential> signInWithApple() async {
    final rawNonce = generateNonce();
    final nonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final appleCredential = await _fetchAppleCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-apple-id-token',
        message: 'Apple did not return an identity token.',
      );
    }

    return _auth.signInWithCredential(
      OAuthProvider('apple.com').credential(
        idToken: idToken,
        accessToken: appleCredential.authorizationCode,
        rawNonce: rawNonce,
      ),
    );
  }
}
