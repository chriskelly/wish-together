import 'dart:async';

import 'package:flutter/material.dart';

// This is a stub implementation of the google_sign_in package. It provides
// the necessary classes and methods for the AuthService to compile and run in a
// non-web environment (like the test runner) without causing platform errors.

/// A stub for the `GoogleSignInAuthentication` class.
/// It provides fake token values.
class GoogleSignInAuthentication {
  String? get accessToken => 'fake_access_token';
  String? get idToken => 'fake_id_token';
}

/// A stub for the `GoogleSignInAccount` class.
/// It provides a fake `authentication` getter.
class GoogleSignInAccount {
  Future<GoogleSignInAuthentication> get authentication async =>
      GoogleSignInAuthentication();
}

/// A stub for the main `GoogleSignIn` class.
class GoogleSignIn {
  // The constructor in the real package accepts a clientId. We need to have a
  // matching constructor signature here for the conditional import to work.
  GoogleSignIn({String? clientId});

  /// Returns a stream that never emits, simulating that there is no user logged in.
  Stream<GoogleSignInAccount?> get onCurrentUserChanged => Stream.value(null);

  /// Returns a Future that completes with null, simulating a failed silent sign-in.
  Future<GoogleSignInAccount?> signInSilently({
    bool suppressErrors = true,
    bool reAuthenticate = false,
  }) async => null;

  /// Returns a Future that completes with null.
  Future<GoogleSignInAccount?> signOut() async => null;

  /// Returns a Future that completes with null, simulating a canceled sign-in.
  Future<GoogleSignInAccount?> signIn() async => null;
}

// Stub for the renderButton function from google_sign_in_web
Widget renderButton() => const SizedBox.shrink();
