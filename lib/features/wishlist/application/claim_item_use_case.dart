import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class ClaimItemUseCase {
  Future<void> execute(String wishlistId, String itemId) async {
    final log = appLogOrNull;
    final session = getIt<AuthSession>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = session.currentUserId;
    if (userId == null) {
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
      await itemRepository.claim(itemId, claimedBy: userId);
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
