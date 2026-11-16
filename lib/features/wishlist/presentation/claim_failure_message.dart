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

/// The owner's partial-clear copy. The prefix is fixed so every reason reads as
/// a partial outcome rather than a failed single action.
String clearStaleClaimsFailureMessage(Object error) {
  final reason = ClaimFailure.from(error).reason;
  final detail = switch (reason) {
    ClaimFailureReason.signedOut => 'Please sign in again to clear old claims.',
    ClaimFailureReason.offline => offlineFailureMessage,
    ClaimFailureReason.accessDenied =>
      "You don't have permission to clear these claims.",
    ClaimFailureReason.itemMissing =>
      'One of these items no longer exists. Refresh and try again.',
    ClaimFailureReason.fullyClaimed ||
    ClaimFailureReason.unknown => 'Please try again.',
  };
  return 'Not all old claims were cleared. $detail';
}
