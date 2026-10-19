/// The outcome of the minimum-build check.
///
/// [isBlocked] is true only when the running build is known to be below the
/// configured minimum. Every uncertain case fails open; see [evaluateUpdate].
class UpdateDecision {
  const UpdateDecision._({
    required this.isBlocked,
    required this.message,
    required this.updateUrl,
  });

  /// The gate is inert: nothing is shown and the app starts normally.
  const UpdateDecision.allowed()
    : this._(isBlocked: false, message: '', updateUrl: '');

  /// The running build is below the minimum and must be replaced.
  const UpdateDecision.blocked({
    required String message,
    required String updateUrl,
  }) : this._(isBlocked: true, message: message, updateUrl: updateUrl);

  final bool isBlocked;
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
UpdateDecision evaluateUpdate({
  required int? runningBuild,
  required int minSupportedBuild,
  required String message,
  required String updateUrl,
  required bool bypass,
}) {
  if (bypass) {
    return const UpdateDecision.allowed();
  }
  if (minSupportedBuild <= 0) {
    return const UpdateDecision.allowed();
  }
  if (runningBuild == null || runningBuild >= minSupportedBuild) {
    return const UpdateDecision.allowed();
  }
  return UpdateDecision.blocked(
    message: message.isEmpty ? defaultUpdateMessage : message,
    updateUrl: updateUrl,
  );
}
