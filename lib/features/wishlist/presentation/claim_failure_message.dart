import 'package:wishtogether/features/wishlist/application/claim_failure.dart';

/// The offline copy, shared with the owner's reset action.
const String offlineFailureMessage =
    "Couldn't reach the server. Check your connection and try again.";

/// The missing-item copy, shared with the owner's reset action.
const String itemMissingFailureMessage = 'This item no longer exists.';

/// A short, user-facing message for a failed claim.
///
/// Takes the thrown object rather than a reason so the page never has to
/// classify an error itself: anything that is not a [ClaimFailure] is
/// unexpected and gets the generic message, never the exception text.
String claimFailureMessage(Object error) {
  final reason = error is ClaimFailure
      ? error.reason
      : ClaimFailureReason.unknown;
  return switch (reason) {
    ClaimFailureReason.accessDenied =>
      "This item can't be claimed right now. It may already be claimed, or the "
          'wishlist may no longer be shared with you.',
    ClaimFailureReason.offline => offlineFailureMessage,
    ClaimFailureReason.itemMissing => itemMissingFailureMessage,
    ClaimFailureReason.signedOut => 'Please sign in again to claim items.',
    ClaimFailureReason.fullyClaimed => 'This item is no longer available.',
    ClaimFailureReason.unknown => "Couldn't claim this item. Please try again.",
  };
}
