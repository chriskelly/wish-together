import 'dart:async';

import 'package:flutter/material.dart';

// This is a stub for `google_sign_in`'s `renderButton`. `login_page.dart` falls
// back to it on non-web platforms so its `web_only.renderButton()` reference
// still compiles there; the web build resolves `web_only` to `google_sign_in_web`.
// `AuthService` uses the real `google_sign_in` package on every platform.

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
