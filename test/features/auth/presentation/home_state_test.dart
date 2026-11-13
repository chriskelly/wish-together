import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/providers.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/providers/home_providers.dart';
import 'package:wishtogether/features/auth/presentation/providers/home_sign_out_provider.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockGroupRepository extends Mock implements GroupRepository {}

const String uid = 'user-1';

void main() {
  late MockAuthService authService;
  late MockUserRepository userRepository;
  late MockWishlistRepository wishlistRepository;
  late MockGroupRepository groupRepository;
  late StreamController<User> userStream;
  late StreamController<List<Wishlist>> wishlistStream;
  late StreamController<List<Group>> groupStream;
  late bool signedIn;

  List<Override> homeOverrides() => [
    authSessionProvider.overrideWithValue(authService),
    userRepositoryProvider.overrideWithValue(userRepository),
    wishlistRepositoryProvider.overrideWithValue(wishlistRepository),
    groupRepositoryProvider.overrideWithValue(groupRepository),
  ];

  ProviderContainer container() => ProviderContainer.test(
    retry: disableAutomaticRetry,
    overrides: homeOverrides(),
  );

  /// Keeps an auto-disposed provider alive for the test body.
  void listen<T>(ProviderContainer container, ProviderListenable<T> provider) {
    final subscription = container.listen(
      provider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
  }

  setUp(() {
    authService = MockAuthService();
    userRepository = MockUserRepository();
    wishlistRepository = MockWishlistRepository();
    groupRepository = MockGroupRepository();
    userStream = StreamController<User>.broadcast();
    wishlistStream = StreamController<List<Wishlist>>.broadcast();
    groupStream = StreamController<List<Group>>.broadcast();
    signedIn = true;

    when(() => authService.currentUserId)
        .thenAnswer((_) => signedIn ? uid : null);
    when(() => authService.supportsSignOut).thenReturn(true);
    when(() => authService.signOut()).thenAnswer((_) async {
      signedIn = false;
    });
    when(() => userRepository.streamOne(uid))
        .thenAnswer((_) => userStream.stream);
    when(() => wishlistRepository.streamWhere('ownerId', isEqualTo: uid))
        .thenAnswer((_) => wishlistStream.stream);
    when(() => groupRepository.streamWhere('members', arrayContains: uid))
        .thenAnswer((_) => groupStream.stream);
  });

  tearDown(() async {
    await userStream.close();
    await wishlistStream.close();
    await groupStream.close();
  });

  test('cancels every read before the credential clears', () async {
    // Arrange: the session records whether each read still has a listener at
    // the moment the credential is cleared.
    final listenersAtSignOut = <bool>[];
    when(() => authService.signOut()).thenAnswer((_) async {
      listenersAtSignOut.addAll([
        userStream.hasListener,
        wishlistStream.hasListener,
        groupStream.hasListener,
      ]);
      signedIn = false;
    });
    final subject = container();
    listen(subject, homeUserProvider(uid));
    listen(subject, homeWishlistsProvider(uid));
    listen(subject, homeGroupsProvider(uid));
    expect([
      userStream.hasListener,
      wishlistStream.hasListener,
      groupStream.hasListener,
    ], everyElement(isTrue));

    // Act
    final result = await subject.read(homeSignOutProvider.notifier).signOut();

    // Assert: closing the gate cancels the three subscriptions before
    // `signOut()`; reversing the two statements makes this list all true.
    expect(result, HomeSignOutResult.signedOut);
    expect(listenersAtSignOut, hasLength(3));
    expect(listenersAtSignOut, everyElement(isFalse));
  });

  test(
    'keeps an error that ends a stream instead of the empty fallback',
    () async {
      // Arrange: the profile read errors, then closes. The fallback must not
      // turn the failure into "no user document".
      final controller = StreamController<User>();
      when(() => userRepository.streamOne(uid))
          .thenAnswer((_) => controller.stream);
      final subject = container();
      listen(subject, homeUserProvider(uid));

      // Act
      controller.addError(Exception('offline'));
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      // Assert
      final value = subject.read(homeUserProvider(uid));
      expect(value.hasError, isTrue);
      expect(value.hasValue, isFalse);
    },
  );

  test(
    'keeps a value that ended the stream instead of the empty fallback',
    () async {
      // Arrange
      final controller = StreamController<User>();
      when(() => userRepository.streamOne(uid))
          .thenAnswer((_) => controller.stream);
      final subject = container();
      listen(subject, homeUserProvider(uid));

      // Act
      final user = User(id: uid, displayName: 'Grace');
      controller.add(user);
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      // Assert
      final value = subject.read(homeUserProvider(uid));
      expect(value.value, user);
      expect(value.hasError, isFalse);
    },
  );

  test(
    'a failed sign-out after the page left does not touch a disposed gate',
    () async {
      // Arrange: the page is the gate's only listener.
      final pending = Completer<void>();
      when(() => authService.signOut()).thenAnswer((_) => pending.future);
      final subject = container();
      final gate = subject.listen(
        homeReadsEnabledProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final running = subject.read(homeSignOutProvider.notifier).signOut();

      // Act: the page leaves while the credential call is in flight, then the
      // call fails with the session still live.
      gate.close();
      await subject.pump();
      pending.completeError(Exception('network'));

      // Assert: the command re-reads the gate instead of reopening the disposed
      // notifier, and reports the live-session failure.
      expect(await running, HomeSignOutResult.failedSessionLive);
    },
  );
}
