/// The outcome of the minimum-build check.
///
/// [isBlocked] is true only when the running build is known to be below the
/// configured minimum. Every uncertain case fails open; see [evaluateUpdate].
class UpdateDecision {
  const UpdateDecision._({
    required this.isBlocked,
    required this.isConclusive,
    required this.message,
    required this.updateUrl,
  });

  /// The gate is inert: nothing is shown and the app starts normally.
  ///
  /// [isConclusive] is false when this allowance came from failing open (for
  /// example an unreachable server) rather than from a completed check.
  const UpdateDecision.allowed({this.isConclusive = true})
    : isBlocked = false,
      message = '',
      updateUrl = '';

  /// The running build is below the minimum and must be replaced.
  const UpdateDecision.blocked({
    required String message,
    required String updateUrl,
  }) : this._(
         isBlocked: true,
         isConclusive: true,
         message: message,
         updateUrl: updateUrl,
       );

  final bool isBlocked;

  /// Whether the result is based on a completed check. An allowed but
  /// inconclusive result means "could not determine", not "confirmed current".
  final bool isConclusive;

  final String message;
  final String updateUrl;
}

/// The message shown when Remote Config does not provide one.
const String defaultUpdateMessage =
    'A newer version of WishTogether is required to keep using the app. '
    'Please update to continue.';

/// Decides whether the running build must be blocked.
///
/// Fails open in every uncertain case:
/// - [bypass] (debug build or maintainer override) never blocks.
/// - A non-positive [minSupportedBuild] is the kill switch, so the gate is
///   inert until a maintainer deliberately raises it.
/// - An unknown [runningBuild] never blocks: the gate must not lock a user out
///   because a platform failed to report its build number.
/// - An inconclusive check (for example a failed fetch) is allowed but marked
///   inconclusive so a retry cannot downgrade a confirmed block.
UpdateDecision evaluateUpdate({
  required int? runningBuild,
  required int minSupportedBuild,
  required String message,
  required String updateUrl,
  required bool bypass,
  required bool conclusive,
}) {
  if (bypass) {
    return const UpdateDecision.allowed();
  }
  if (minSupportedBuild <= 0) {
    return UpdateDecision.allowed(isConclusive: conclusive);
  }
  if (runningBuild == null) {
    return const UpdateDecision.allowed(isConclusive: false);
  }
  if (runningBuild >= minSupportedBuild) {
    return UpdateDecision.allowed(isConclusive: conclusive);
  }
  return UpdateDecision.blocked(
    message: message.isEmpty ? defaultUpdateMessage : message,
    updateUrl: updateUrl,
  );
}

/// Whether a retry result may replace the blocking screen.
///
/// Fail-open is a startup policy for users who were never confirmed stale. A
/// confirmed block must not be downgraded by a retry that merely failed open
/// (offline, timeout, unreadable build number).
bool canStartFromRetry(UpdateDecision decision) =>
    !decision.isBlocked && decision.isConclusive;
