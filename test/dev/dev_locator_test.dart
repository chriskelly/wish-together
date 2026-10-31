import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/dev/dev_session.dart';
import 'package:wishtogether/dev/fixtures/default_scenario.dart';
import 'package:wishtogether/dev/run_dev_session.dart';
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

void main() {
  /// One probe per type `setupServiceLocator` registers.
  ///
  /// `isRegistered` rather than a resolve: resolving the production auth service
  /// is an error for a dev session by design, and a resolving guard would fail
  /// for that reason instead of reporting drift.
  final Map<String, bool Function()> probes = <String, bool Function()>{
    'AppLog': () => getIt.isRegistered<AppLog>(),
    'FirebaseFirestore': () => getIt.isRegistered<FirebaseFirestore>(),
    'AuthService': () => getIt.isRegistered<AuthService>(),
    'AuthSession': () => getIt.isRegistered<AuthSession>(),
    'AppUpdateService': () => getIt.isRegistered<AppUpdateService>(),
    'UserRepository': () => getIt.isRegistered<UserRepository>(),
    'WishlistRepository': () => getIt.isRegistered<WishlistRepository>(),
    'GroupRepository': () => getIt.isRegistered<GroupRepository>(),
    'LoadUserProfileUseCase': () =>
        getIt.isRegistered<LoadUserProfileUseCase>(),
    'SaveUserProfileUseCase': () =>
        getIt.isRegistered<SaveUserProfileUseCase>(),
    'DeleteAccountUseCase': () => getIt.isRegistered<DeleteAccountUseCase>(),
    'CreateGroupUseCase': () => getIt.isRegistered<CreateGroupUseCase>(),
    'JoinGroupUseCase': () => getIt.isRegistered<JoinGroupUseCase>(),
    'LeaveGroupUseCase': () => getIt.isRegistered<LeaveGroupUseCase>(),
    'UpdateGroupUseCase': () => getIt.isRegistered<UpdateGroupUseCase>(),
    'ShareWishlistWithGroupUseCase': () =>
        getIt.isRegistered<ShareWishlistWithGroupUseCase>(),
    'CreateWishlistUseCase': () => getIt.isRegistered<CreateWishlistUseCase>(),
    'UpdateWishlistUseCase': () => getIt.isRegistered<UpdateWishlistUseCase>(),
    'CreateItemUseCase': () => getIt.isRegistered<CreateItemUseCase>(),
    'UpdateItemUseCase': () => getIt.isRegistered<UpdateItemUseCase>(),
    'ClaimItemUseCase': () => getIt.isRegistered<ClaimItemUseCase>(),
    'UnclaimItemUseCase': () => getIt.isRegistered<UnclaimItemUseCase>(),
  };

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('the dev locator registers every type the production one does', () async {
    // ARRANGE: read what the locator registers from its own source, so a new
    // service fails this test instead of going missing from every dev session.
    final source = File('lib/core/service_locator.dart').readAsStringSync();
    final registered = RegExp(r'getIt\.register\w*<([A-Za-z0-9_]+)>')
        .allMatches(source)
        .map((match) => match.group(1)!)
        .toSet();

    // ACT
    await buildDevApp(defaultFixture);

    // ASSERT
    expect(
      registered,
      isNotEmpty,
      reason:
          'the scan must actually find the locator registrations; an empty '
          'scan would prove nothing',
    );
    expect(
      probes.keys,
      containsAll(registered),
      reason:
          'setupServiceLocator gained a registration: add it to '
          'probes so the dev session is checked for it too',
    );
    for (final entry in probes.entries) {
      expect(
        entry.value(),
        isTrue,
        reason: '${entry.key} is not registered in a dev session',
      );
    }
  });

  test('the dev session is the shell identity, and only that', () async {
    // ACT
    await buildDevApp(defaultFixture);

    // ASSERT
    expect(getIt<AuthSession>(), isA<DevAuthSession>());
    expect(getIt<AuthSession>().currentUserId, defaultFixture.viewerUid);
  });

  test(
    'the production auth service cannot be resolved in a dev session',
    () async {
      // ARRANGE
      await buildDevApp(defaultFixture);

      // ACT & ASSERT: sign-in, verification and deletion are unbuildable here,
      // which is what makes a hidden sign-out control the right answer.
      expect(() => getIt<AuthService>(), throwsStateError);
    },
  );
}
