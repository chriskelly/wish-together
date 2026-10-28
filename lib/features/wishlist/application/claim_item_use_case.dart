import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/logging/redaction.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

class ClaimItemUseCase {
  Future<void> execute(String wishlistId, Item item) async {
    final log = appLogOrNull;
    final authService = getIt<AuthService>();
    final wishlistRepository = getIt<WishlistRepository>();

    final userId = authService.currentUserId;
    if (userId == null) {
      log?.event(
        const ClaimActionEvent(
          phase: ClaimPhase.denied,
          code: 'unauthenticated',
        ),
      );
      throw Exception('User is not authenticated');
    }

    log?.event(const ClaimActionEvent(phase: ClaimPhase.started));
    final itemRepository = wishlistRepository.items(wishlistId);
    final updatedItem = item.copyWith(
      claimedBy: userId,
      claimedAt: DateTime.now(),
    );
    try {
      await itemRepository.update(item.id!, updatedItem);
    } catch (error) {
      log?.event(
        ClaimActionEvent(phase: ClaimPhase.denied, code: readErrorCode(error)),
      );
      rethrow;
    }
    log?.event(const ClaimActionEvent(phase: ClaimPhase.completed));
  }
}
