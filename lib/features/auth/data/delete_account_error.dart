import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:wishtogether/features/auth/data/apple_auth_error.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';

const String _genericMessage =
    'Could not delete your account. Please try again.';

/// A short, user-facing message for a failed account deletion or
/// re-authentication, or `null` when nothing should be shown.
///
/// Returns `null` when the user simply backed out of a prompt: dismissing the
/// Google account picker, closing the web popup, or cancelling the Apple sheet
/// is a normal action, not an error worth surfacing.
String? deleteAccountErrorMessage(Object error) {
  if (error is SignInWithAppleAuthorizationException ||
      error is SignInWithAppleNotSupportedException) {
    return appleAuthErrorMessage(error);
  }

  if (error is FirebaseAuthException) {
    switch (error.code) {
      case reauthCancelledCode:
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return null;
      case 'requires-recent-login':
        return 'For your security we need you to confirm your identity again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network problem. Check your connection and try again.';
      default:
        return _genericMessage;
    }
  }

  return _genericMessage;
}
