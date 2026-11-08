import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class UnclaimItemUseCase {
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

    final itemRepository = wishlistRepository.items(wishlistId);
    log?.event(const ClaimActionEvent(phase: ClaimPhase.started));
    try {
      await itemRepository.unclaim(itemId, claimedBy: userId);
    } catch (error) {
      log?.event(
        ClaimActionEvent(phase: ClaimPhase.denied, code: readErrorCode(error)),
      );
      rethrow;
    }
    log?.event(const ClaimActionEvent(phase: ClaimPhase.completed));
  }
}
