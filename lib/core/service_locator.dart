import 'package:get_it/get_it.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // Services
  getIt.registerLazySingleton<AuthService>(() => AuthService());
  getIt.registerLazySingleton<UserRepository>(() => UserRepository());
  getIt.registerLazySingleton<WishlistRepository>(() => WishlistRepository());
  getIt.registerLazySingleton<GroupRepository>(() => GroupRepository());

  // Use Cases
  getIt.registerLazySingleton<LoadUserProfileUseCase>(
    () => LoadUserProfileUseCase(),
  );
  getIt.registerLazySingleton<SaveUserProfileUseCase>(
    () => SaveUserProfileUseCase(),
  );
}
