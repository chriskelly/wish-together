import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/features/wishlist/domain/claim_limit_reached_exception.dart';

/// The failure code used both for a missing signed-in user and for a write
/// Firestore rejects as unauthenticated, so the two paths classify the same.
const String unauthenticatedCode = 'unauthenticated';

/// Why a claim did not happen, in terms the UI can act on.
enum ClaimFailureReason {
  accessDenied,
  offline,
  itemMissing,
  signedOut,
  fullyClaimed,
  unknown,
}

/// A claim that was not completed.
///
/// The reason is a closed value so the page can choose copy without knowing
/// Firestore error codes, and [code] is the redacted code when there was one.
/// The caller reattaches the write's stack trace when it rethrows, so the trace
/// is not carried here.
class ClaimFailure implements Exception {
  const ClaimFailure(this.reason, {this.code});

  /// Classifies [error] by its redacted structured code.
  factory ClaimFailure.from(Object error) {
    if (error is ClaimFailure) {
      return error;
    }
    // The repository raises this for a full item; it has no Firestore code, and
    // the code table would map it to `unknown`.
    if (error is ClaimLimitReachedException) {
      return const ClaimFailure(ClaimFailureReason.fullyClaimed);
    }
    final code = readErrorCode(error);
    return ClaimFailure(_reasonForCode(code), code: code);
  }

  final ClaimFailureReason reason;
  final String? code;

  @override
  String toString() => 'ClaimFailure($reason, code: $code)';
}

ClaimFailureReason _reasonForCode(String? code) => switch (code) {
  'permission-denied' => ClaimFailureReason.accessDenied,
  'unavailable' => ClaimFailureReason.offline,
  'not-found' => ClaimFailureReason.itemMissing,
  unauthenticatedCode => ClaimFailureReason.signedOut,
  _ => ClaimFailureReason.unknown,
};
