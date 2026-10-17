import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

const String _genericMessage =
    'Sign in with Apple failed. Please try again, or use Google sign-in instead.';

/// Maps an Apple sign-in failure to a short, user-facing message.
///
/// Returns `null` when no message should be shown — the user simply backed out
/// of the Apple sheet. Mirrors the phone-auth mapper: Firebase's raw server
/// strings stay away from the user, and the cases we can act on get their own
/// wording.
String? appleAuthErrorMessage(Object error) {
  if (error is SignInWithAppleAuthorizationException) {
    // Canceling the sheet is a normal action, not an error worth surfacing.
    if (error.code == AuthorizationErrorCode.canceled) {
      return null;
    }
    return _genericMessage;
  }

  if (error is SignInWithAppleNotSupportedException) {
    return 'Sign in with Apple is not available on this device.';
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'An account already exists for this email. Sign in the way you '
            'used before.';
      case 'operation-not-allowed':
        return 'Sign in with Apple is not enabled for this app yet. Please '
            'use Google sign-in.';
      case 'credential-already-in-use':
        return 'This Apple ID is already linked to another account.';
      case 'missing-apple-id-token':
        return 'Apple did not return a sign-in token. Please try again.';
      case 'network-request-failed':
        return 'Network problem. Check your connection and try again.';
      default:
        return _genericMessage;
    }
  }

  return _genericMessage;
}
