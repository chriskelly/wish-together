import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';
import 'package:wishtogether/core/firestore_target.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/features/app_update/data/app_update_service.dart';
import 'package:wishtogether/features/auth/application/delete_account_use_case.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/application/create_group_use_case.dart';
import 'package:wishtogether/features/group/application/join_group_use_case.dart';
import 'package:wishtogether/features/group/application/leave_group_use_case.dart';
import 'package:wishtogether/features/group/application/share_wishlist_with_group_use_case.dart';
import 'package:wishtogether/features/group/application/update_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/application/claim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/create_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/application/unclaim_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

final getIt = GetIt.instance;

/// Registers the app's services.
///
/// [firestore] and [authSession] are composition seams: production passes
/// neither and the locator builds them, while a caller that has its own — a
/// test, or any session that must not touch Firebase — supplies it.
///
/// [createAuthService] builds the production service when no session is
/// supplied. Tests pass one because the real constructor needs Firebase.
///
/// A supplied session that is not an [AuthService] leaves the sign-in,
/// verification and account-deletion screens unbuildable: resolving
/// [AuthService] throws rather than constructing a second identity.
void setupServiceLocator({
  FirebaseFirestore? firestore,
  AppLog? appLog,
  AuthSession? authSession,
  AuthService Function() createAuthService = AuthService.new,
}) {
  // Diagnostics are optional: tests register only the collaborators they need,
  // and every call site goes through `appLogOrNull`.
  if (appLog != null) {
    getIt.registerSingleton<AppLog>(appLog);
  }

  // Services
  getIt.registerLazySingleton<FirebaseFirestore>(
    () => firestore ?? createFirestoreInstance(),
  );
  // Auth: one instance answers both the narrow session the signed-in shell
  // resolves and the concrete service the sign-in and deletion flows resolve.
  // A supplied session that is not the production service cannot answer those
  // flows, so resolving it is an error rather than a silent second identity.
  getIt.registerLazySingleton<AuthService>(
    () => switch (authSession) {
      null => createAuthService(),
      final AuthService service => service,
      _ => throw StateError(
        'AuthService was resolved for a session that is not one: sign-in, '
        're-authentication and account deletion need the production service.',
      ),
    },
  );
  getIt.registerLazySingleton<AuthSession>(
    () => authSession ?? getIt<AuthService>(),
  );
  getIt.registerLazySingleton<AppUpdateService>(() => AppUpdateService());
  getIt.registerLazySingleton<UserRepository>(
    () => UserRepository(firestore: getIt<FirebaseFirestore>()),
  );
  getIt.registerLazySingleton<WishlistRepository>(
    () => WishlistRepository(firestore: getIt<FirebaseFirestore>()),
  );
  getIt.registerLazySingleton<GroupRepository>(
    () => GroupRepository(firestore: getIt<FirebaseFirestore>()),
  );

  // Auth Use Cases
  getIt.registerLazySingleton<LoadUserProfileUseCase>(
    () => LoadUserProfileUseCase(),
  );
  getIt.registerLazySingleton<SaveUserProfileUseCase>(
    () => SaveUserProfileUseCase(),
  );
  getIt.registerLazySingleton<DeleteAccountUseCase>(
    () => DeleteAccountUseCase(),
  );

  // Group Use Cases
  getIt.registerLazySingleton<CreateGroupUseCase>(() => CreateGroupUseCase());
  getIt.registerLazySingleton<JoinGroupUseCase>(() => JoinGroupUseCase());
  getIt.registerLazySingleton<LeaveGroupUseCase>(() => LeaveGroupUseCase());
  getIt.registerLazySingleton<UpdateGroupUseCase>(() => UpdateGroupUseCase());
  getIt.registerLazySingleton<ShareWishlistWithGroupUseCase>(
    () => ShareWishlistWithGroupUseCase(),
  );

  // Wishlist Use Cases
  getIt.registerLazySingleton<CreateWishlistUseCase>(
    () => CreateWishlistUseCase(),
  );
  getIt.registerLazySingleton<UpdateWishlistUseCase>(
    () => UpdateWishlistUseCase(),
  );
  getIt.registerLazySingleton<CreateItemUseCase>(() => CreateItemUseCase());
  getIt.registerLazySingleton<UpdateItemUseCase>(() => UpdateItemUseCase());
  getIt.registerLazySingleton<ClaimItemUseCase>(() => ClaimItemUseCase());
  getIt.registerLazySingleton<UnclaimItemUseCase>(() => UnclaimItemUseCase());
}
