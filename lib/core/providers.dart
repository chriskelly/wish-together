import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

/// There is no automatic retry: re-entering the screen is the retry.
///
/// Riverpod 3's default retries a non-`Error` failure ten times over about 38
/// seconds, which would re-subscribe Firestore streams and amplify the
/// repository's per-error diagnostics. Passed to the root `ProviderScope` and to
/// every test scope and container.
Duration? disableAutomaticRetry(int retryCount, Object error) => null;

/// These providers are the temporary bridge over getIt. Presentation reads a
/// collaborator here, never from `service_locator.dart`; constructor injection
/// replaces the bridge feature by feature.
final authSessionProvider = Provider<AuthSession>(
  (ref) => getIt<AuthSession>(),
);

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => getIt<WishlistRepository>(),
);

/// Derives the sub-repository for [wishlistId]; it does not resolve it from getIt.
final itemRepositoryProvider = Provider.family<ItemRepository, String>(
  (ref, wishlistId) => ref.watch(wishlistRepositoryProvider).items(wishlistId),
  isAutoDispose: true,
);

final claimItemUseCaseProvider = Provider<ClaimItemUseCase>(
  (ref) => getIt<ClaimItemUseCase>(),
);

final unclaimItemUseCaseProvider = Provider<UnclaimItemUseCase>(
  (ref) => getIt<UnclaimItemUseCase>(),
);

/// The signed-in uid, re-read when the last screen watching it leaves.
///
/// One snapshot per page lifetime, not a stream: sign-out navigates away and is
/// the router's concern. The reactive identity is `AuthSession.uidChanges`.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authSessionProvider).currentUserId,
  isAutoDispose: true,
);
