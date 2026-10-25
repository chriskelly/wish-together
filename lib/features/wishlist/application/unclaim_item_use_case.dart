import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class UnclaimItemUseCase {
  Future<void> execute(String wishlistId, String itemId) async {
    final log = appLogOrNull;
    final wishlistRepository = getIt<WishlistRepository>();
    final itemRepository = wishlistRepository.items(wishlistId);

    log?.event(const ClaimActionEvent(phase: ClaimPhase.started));
    try {
      await itemRepository.unclaim(itemId);
    } catch (error) {
      log?.event(
        ClaimActionEvent(phase: ClaimPhase.denied, code: errorCodeOf(error)),
      );
      rethrow;
    }
    log?.event(const ClaimActionEvent(phase: ClaimPhase.completed));
  }
}
