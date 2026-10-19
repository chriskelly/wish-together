import 'package:flutter/foundation.dart' show debugPrint;
import 'package:wishtogether/features/app_update/domain/update_decision.dart';

/// Runs the gate, treating any unexpected failure as an inconclusive allowance.
///
/// This is the composition-root safety net: `AppUpdateService.check` already
/// fails open, but resolving the service or a future collaborator could still
/// throw. A throw must never block startup or unlock a retry.
Future<UpdateDecision> checkForUpdate(
  Future<UpdateDecision> Function() check,
) async {
  try {
    return await check();
  } catch (error) {
    debugPrint('App update gate: unexpected failure, failing open: $error');
    return const UpdateDecision.allowed();
  }
}
