import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:wishtogether/features/auth/data/google_sign_in_stub.dart'
    if (dart.library.html) 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static String clientId =
      "1063002805065-eobumao8o4tk4s54ea41jogjvls62pu5.apps.googleusercontent.com";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(clientId: clientId);

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

    // Trigger silent sign-in on web to check for existing sessions
    if (_auth.currentUser == null) {
      _googleSignIn.signInSilently();
    }
  }

  // Sign out from both Firebase and Google
  Future<void> signOut() async {
    debugPrint("signed-out");
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  // Expose the GoogleSignIn instance for the UI to use
  GoogleSignIn get googleSignIn => _googleSignIn;

  User? get currentUser => _auth.currentUser;
}
