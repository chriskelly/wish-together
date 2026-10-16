import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:wishtogether/features/auth/data/google_sign_in_stub.dart'
    if (dart.library.html) 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  /// The web OAuth client id. Used by the web build and as the server client id.
  static String clientId =
      "1063002805065-eobumao8o4tk4s54ea41jogjvls62pu5.apps.googleusercontent.com";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // On iOS the plugin reads the iOS OAuth client (CLIENT_ID) from the bundled
    // GoogleService-Info.plist. Passing the web client id here would not match
    // the reversed-client-ID URL scheme configured in Info.plist.
    clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? null
        : clientId,
  );

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  AuthService() {
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
}
