import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';

/// Removes the old claims the owner's cleanup selected, one item at a time.
///
/// It stops at the first failed write and throws the classified failure, so
/// the caller keeps the banner for a retry. For a signed-in caller, an empty
/// plan returns without logging; a signed-out caller still gets the signed-out
/// failure.
class ClearStaleClaimsUseCase {
  Future<void> execute(String wishlistId, StaleClaimsPlan plan) async {
    final log = appLogOrNull;
    final session = getIt<AuthSession>();

    if (session.currentUserId == null) {
      log?.event(
        const ClaimActionEvent(
          phase: ClaimPhase.denied,
          code: unauthenticatedCode,
        ),
      );
      throw const ClaimFailure(
        ClaimFailureReason.signedOut,
        code: unauthenticatedCode,
      );
    }

    if (plan.isEmpty) {
      return;
    }

    log?.event(const ClaimActionEvent(phase: ClaimPhase.started));
    final itemRepository = getIt<WishlistRepository>().items(wishlistId);
    for (final entry in plan.byItem.entries) {
      try {
        await itemRepository.removeClaims(entry.key, uids: entry.value);
      } catch (error, stackTrace) {
        final failure = ClaimFailure.from(error);
        log?.event(
          ClaimActionEvent(phase: ClaimPhase.denied, code: failure.code),
        );
        Error.throwWithStackTrace(failure, stackTrace);
      }
    }
    log?.event(const ClaimActionEvent(phase: ClaimPhase.completed));
  }
}
