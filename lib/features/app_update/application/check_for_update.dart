import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
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
  } catch (_) {
    appLogOrNull?.event(
      const UpdateGateEvent(
        result: UpdateGateResult.failedOpen,
        reason: 'unexpected-failure',
      ),
    );
    return const UpdateDecision.allowed();
  }
}
