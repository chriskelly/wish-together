import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

/// Re-checks the gate and starts the app only when the result is conclusive.
///
/// Returns whether [start] was called. A retry that merely fails open must not
/// replace a confirmed block: otherwise an offline user could tap through the
/// gate. A throw from either callback is treated as "not started".
Future<bool> retryUpdateGate({
  required Future<UpdateDecision> Function() check,
  required void Function() start,
}) async {
  try {
    final decision = await check();
    if (!canStartFromRetry(decision)) {
      return false;
    }
    start();
    return true;
  } catch (error, stackTrace) {
    // The gate did not fail open: the confirmed block stays. This is the retry
    // itself throwing, so it is an error with a stack.
    appLogOrNull?.error(error, stackTrace, code: 'retry-failed');
    return false;
  }
}
