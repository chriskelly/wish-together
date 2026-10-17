import 'package:firebase_auth/firebase_auth.dart';

const String _genericMessage =
    'Phone sign-in failed. Please try again, or use Google sign-in instead.';

/// Maps a phone-auth failure to a short, user-facing message.
///
/// Keeps Firebase's raw server strings (`CAPTCHA_CHECK_FAILED : Hostname match
/// not found`, etc.) away from the user, and points at the fix where we can.
String phoneAuthErrorMessage(FirebaseAuthException exception) {
  switch (exception.code) {
    case 'invalid-phone-number':
      return "That phone number doesn't look right. Check it and try again.";
    case 'too-many-requests':
      return 'Too many attempts. Please wait a few minutes and try again.';
    case 'invalid-verification-code':
      return "That code isn't right. Check the SMS code and try again.";
    case 'code-expired':
      return 'That code has expired. Request a new one and try again.';
    case 'invalid-app-credential':
    case 'captcha-check-failed':
      return 'We could not verify this browser. Refresh the page and try again.';
    case 'quota-exceeded':
    case 'billing-not-enabled':
      return 'Phone sign-in is temporarily unavailable. Please try again later, '
          'or use Google sign-in.';
    case 'operation-not-allowed':
      return 'Phone sign-in is not enabled for this app. Please use Google '
          'sign-in.';
    case 'network-request-failed':
      return 'Network problem. Check your connection and try again.';
    // Both surface when the page's domain is not allowed to run reCAPTCHA.
    case 'unauthorized-domain':
    case 'missing-client-identifier':
      return 'This domain is not authorized for phone sign-in. Add it to '
          'Firebase Auth \u2192 Authorized domains and try again.';
    default:
      return _genericMessage;
  }
}
