import 'package:wishtogether/features/app_update/domain/update_decision.dart';

/// Re-checks the gate and starts the app only when the result is conclusive.
///
/// Returns whether [start] was called. A retry that merely fails open must not
/// replace a confirmed block: otherwise an offline user could tap through the
/// gate.
Future<bool> retryUpdateGate({
  required Future<UpdateDecision> Function() check,
  required void Function() start,
}) async {
  final decision = await check();
  if (!canStartFromRetry(decision)) {
    return false;
  }
  start();
  return true;
}
