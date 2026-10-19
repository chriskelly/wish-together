import 'package:wishtogether/features/app_update/domain/update_url.dart';

/// The outcome of the minimum-build check.
///
/// [isBlocked] is true only when the running build is known to be below the
/// configured minimum. Every uncertain case fails open; see [evaluateUpdate].
class UpdateDecision {
  const UpdateDecision._({
    required this.isBlocked,
    required this.isConclusive,
    required this.blockedForMissingUpdateUrl,
    required this.message,
    required this.updateUrl,
  });

  /// The gate is inert: nothing is shown and the app starts normally.
  ///
  /// [isConclusive] defaults to false as a fail-safe: a caller that forgets to
  /// state that a check completed must not be able to unlock a retry. A
  /// completed check that could not produce an actionable result is also
  /// inconclusive.
  const UpdateDecision.allowed({
    this.isConclusive = false,
    this.blockedForMissingUpdateUrl = false,
  }) : isBlocked = false,
       message = '',
       updateUrl = '';

  /// The running build is below the minimum and must be replaced.
  const UpdateDecision.blocked({
    required String message,
    required String updateUrl,
  }) : this._(
         isBlocked: true,
         isConclusive: true,
         blockedForMissingUpdateUrl: false,
         message: message,
         updateUrl: updateUrl,
       );

  final bool isBlocked;

  /// Whether the result may be treated as a completed check for retry
  /// purposes. An allowed but inconclusive result means "could not determine",
  /// not "confirmed current". A completed check that cannot offer an
  /// actionable block (for example a block with no usable update URL) is also
  /// marked inconclusive.
  final bool isConclusive;

  /// True when the policy would have blocked but no usable update URL was
  /// configured, so the decision failed open instead. Used only for logging.
  final bool blockedForMissingUpdateUrl;

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
/// - An inconclusive check is allowed but marked inconclusive, so a retry
///   cannot downgrade a confirmed block.
/// - A non-positive [minSupportedBuild] is the kill switch, so the gate is
///   inert until a maintainer deliberately raises it.
/// - An unknown [runningBuild] never blocks: the gate must not lock a user out
///   because a platform failed to report its build number.
/// - A block is only produced when [updateUrl] is a usable store URL; a block
///   with no action would be a dead end.
UpdateDecision evaluateUpdate({
  required int? runningBuild,
  required int minSupportedBuild,
  required String message,
  required String updateUrl,
  required bool bypass,
  required bool conclusive,
}) {
  if (bypass) {
    return const UpdateDecision.allowed(isConclusive: true);
  }
  if (!conclusive) {
    return const UpdateDecision.allowed();
  }
  if (minSupportedBuild <= 0) {
    return const UpdateDecision.allowed(isConclusive: true);
  }
  if (runningBuild == null) {
    return const UpdateDecision.allowed();
  }
  if (runningBuild >= minSupportedBuild) {
    return const UpdateDecision.allowed(isConclusive: true);
  }
  if (parseUpdateUrl(updateUrl) == null) {
    return const UpdateDecision.allowed(blockedForMissingUpdateUrl: true);
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
