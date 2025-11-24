import 'package:get_it/get_it.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/application/create_group_use_case.dart';
import 'package:wishtogether/features/group/application/join_group_use_case.dart';
import 'package:wishtogether/features/group/application/leave_group_use_case.dart';
import 'package:wishtogether/features/group/application/share_wishlist_with_group_use_case.dart';
import 'package:wishtogether/features/group/application/update_group_use_case.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Services
  getIt.registerLazySingleton<AuthService>(() => AuthService());
  getIt.registerLazySingleton<UserRepository>(() => UserRepository());
  getIt.registerLazySingleton<WishlistRepository>(() => WishlistRepository());
  getIt.registerLazySingleton<GroupRepository>(() => GroupRepository());

  // Auth Use Cases
  getIt.registerLazySingleton<LoadUserProfileUseCase>(
    () => LoadUserProfileUseCase(),
  );
  getIt.registerLazySingleton<SaveUserProfileUseCase>(
    () => SaveUserProfileUseCase(),
  );

  // Group Use Cases
  getIt.registerLazySingleton<CreateGroupUseCase>(() => CreateGroupUseCase());
  getIt.registerLazySingleton<JoinGroupUseCase>(() => JoinGroupUseCase());
  getIt.registerLazySingleton<LeaveGroupUseCase>(() => LeaveGroupUseCase());
  getIt.registerLazySingleton<UpdateGroupUseCase>(() => UpdateGroupUseCase());
  getIt.registerLazySingleton<ShareWishlistWithGroupUseCase>(
    () => ShareWishlistWithGroupUseCase(),
  );
}
