import 'package:google_sign_in/google_sign_in.dart';

/// The neutral message a dismissed Google account picker produces.
const String googleSignInCancelledMessage = 'Sign-in cancelled';

/// The GIS credential-response error strings that mean the user backed out.
///
/// `google_sign_in_web` wraps every credential-response error string in a
/// `GoogleSignInException` with [GoogleSignInExceptionCode.unknownError] and
/// the raw string as its description. A denied or closed popup arrives as
/// `access_denied` or `popup_closed_by_user`.
const Set<String> _webCancellationDescriptions = <String>{
  'access_denied',
  'popup_closed_by_user',
};

/// Whether [error] means the user backed out of a Google prompt.
///
/// v7 throws [GoogleSignInExceptionCode.canceled] on a dismissed native
/// picker; the web GIS button reports the description strings above instead.
/// A cancellation is a breadcrumb, not an auth failure.
bool isGoogleSignInCancellation(Object error) {
  if (error is! GoogleSignInException) {
    return false;
  }
  if (error.code == GoogleSignInExceptionCode.canceled) {
    return true;
  }
  return error.code == GoogleSignInExceptionCode.unknownError &&
      _webCancellationDescriptions.contains(error.description?.trim());
}

final RegExp _uppercase = RegExp('[A-Z]');

/// The reportable code for a Google failure.
///
/// The enum name is camelCase, and the diagnostics shape gate drops a
/// separator-free token at uid length (`clientConfigurationError`), so each
/// capital becomes a kebab separator: `client-configuration-error`.
String googleSignInFailureCode(GoogleSignInException error) => error.code.name
    .replaceAllMapped(_uppercase, (match) => '-${match[0]!.toLowerCase()}');
