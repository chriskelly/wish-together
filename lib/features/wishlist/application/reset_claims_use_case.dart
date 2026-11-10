import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

/// Clears every claim on an item, for the wishlist's owner.
///
/// The rules are the boundary that keeps this owner-only; the signed-out guard
/// here only converts a missing session into the existing signed-out failure.
class ResetClaimsUseCase {
  Future<void> execute(String wishlistId, String itemId) async {
    final log = appLogOrNull;
    final session = getIt<AuthSession>();
    final wishlistRepository = getIt<WishlistRepository>();

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

    log?.event(const ClaimActionEvent(phase: ClaimPhase.started));
    final itemRepository = wishlistRepository.items(wishlistId);
    try {
      await itemRepository.resetClaims(itemId);
    } catch (error, stackTrace) {
      final failure = ClaimFailure.from(error);
      log?.event(
        ClaimActionEvent(phase: ClaimPhase.denied, code: failure.code),
      );
      Error.throwWithStackTrace(failure, stackTrace);
    }
    log?.event(const ClaimActionEvent(phase: ClaimPhase.completed));
  }
}
