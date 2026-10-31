import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockWishlistRepository extends Mock implements WishlistRepository {}

class MockGroupRepository extends Mock implements GroupRepository {}

const String uid = 'user-1';
const String displayName = 'Grace';
const String wishlistName = 'Beach trip';
const String groupName = 'Family';
const String signOutFailedMessage = 'Could not sign out. Please try again.';
const String userLoadFailedMessage = 'Could not load user profile.';
const String emptyWishlistsMessage = 'No wishlists yet. Create one!';

void main() {
  late MockAuthService authService;
  late MockUserRepository userRepository;
  late MockWishlistRepository wishlistRepository;
  late MockGroupRepository groupRepository;
  late StreamController<User> userStream;
  late StreamController<List<Wishlist>> wishlistStream;
  late StreamController<List<Group>> groupStream;
  late List<bool> listenersAtSignOut;
  late bool signedIn;
  late int userReads;
  late int wishlistReads;
  late int groupReads;

  /// Whether each of the page's three reads currently has a listener.
  List<bool> listenerState() => [
    userStream.hasListener,
    wishlistStream.hasListener,
    groupStream.hasListener,
  ];

  final user = User(id: uid, displayName: displayName);
  final wishlist = Wishlist(id: 'w1', name: wishlistName, ownerId: uid);
  final group = Group(id: 'g1', name: groupName, ownerId: uid, members: [uid]);

  setUp(() async {
    await getIt.reset();
    authService = MockAuthService();
    userRepository = MockUserRepository();
    wishlistRepository = MockWishlistRepository();
    groupRepository = MockGroupRepository();
    // Broadcast, so the same controller can be listened to again after a
    // restart and `hasListener` stays a usable assertion.
    userStream = StreamController<User>.broadcast();
    wishlistStream = StreamController<List<Wishlist>>.broadcast();
    groupStream = StreamController<List<Group>>.broadcast();
    listenersAtSignOut = <bool>[];
    signedIn = true;
    userReads = 0;
    wishlistReads = 0;
    groupReads = 0;

    when(() => authService.currentUserId)
        .thenAnswer((_) => signedIn ? uid : null);
    when(() => authService.signOut()).thenAnswer((_) async {
      listenersAtSignOut.addAll(listenerState());
      signedIn = false;
    });
    when(() => userRepository.streamOne(uid)).thenAnswer((_) {
      userReads++;
      return userStream.stream;
    });
    when(() => wishlistRepository.streamWhere('ownerId', isEqualTo: uid))
        .thenAnswer((_) {
          wishlistReads++;
          return wishlistStream.stream;
        });
    when(() => groupRepository.streamWhere('members', arrayContains: uid))
        .thenAnswer((_) {
          groupReads++;
          return groupStream.stream;
        });

    getIt.registerSingleton<AuthService>(authService);
    getIt.registerSingleton<UserRepository>(userRepository);
    getIt.registerSingleton<WishlistRepository>(wishlistRepository);
    getIt.registerSingleton<GroupRepository>(groupRepository);
  });

  tearDown(() async {
    await userStream.close();
    await wishlistStream.close();
    await groupStream.close();
    await getIt.reset();
  });

  Future<void> pumpHome(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: HomePage()));

  /// Rebuilds the page the way the router does: the element is dirtied and a
  /// frame runs, so `_HomePageState.build` executes again.
  ///
  /// Dirtying the element is what makes the rebuild real: `Element.updateChild`
  /// short-circuits an identical widget, so a parent that rebuilds with the
  /// same `const HomePage()` would leave `build()` unrun and the "no read on
  /// rebuild" assertions would prove nothing.
  Future<void> forcePageRebuild(WidgetTester tester) async {
    tester.element(find.byType(HomePage)).markNeedsBuild();
    await tester.pump();
  }

  /// Loads the page with all three reads filled: the user document first,
  /// then the two lists (the reads themselves start together when the page is
  /// created).
  Future<void> loadSignedInHome(WidgetTester tester) async {
    await pumpHome(tester);
    userStream.add(user);
    await tester.pump();
    wishlistStream.add([wishlist]);
    groupStream.add([group]);
    await tester.pump();
  }

  testWidgets('cancels every home read before the session is cleared', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    expect((userReads, wishlistReads, groupReads), (1, 1, 1));
    expect(listenerState(), everyElement(isTrue));

    // Act
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert
    expect(listenersAtSignOut, hasLength(3));
    expect(listenersAtSignOut, everyElement(isFalse));
  });

  testWidgets('issues no read after sign-out, even for a late snapshot', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();
    final readsBefore = (userReads, wishlistReads, groupReads);

    // Act
    wishlistStream.add([wishlist]);
    groupStream.add([group]);
    await forcePageRebuild(tester);

    // Assert
    expect((userReads, wishlistReads, groupReads), readsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reads nothing and survives a rebuild with no signed-in user', (
    tester,
  ) async {
    // Arrange
    signedIn = false;

    // Act
    await pumpHome(tester);
    await tester.pump();

    // Assert: nothing to read, no crash, and the loading state is what shows.
    expect((userReads, wishlistReads, groupReads), (0, 0, 0));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Act
    await forcePageRebuild(tester);

    // Assert
    expect((userReads, wishlistReads, groupReads), (0, 0, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('restarts its reads and clears the previous error on failure', (
    tester,
  ) async {
    // Arrange: a failed list read, so the restart has an error to clear.
    await loadSignedInHome(tester);
    final listError = Exception('offline');
    wishlistStream.addError(listError);
    await tester.pump();
    expect(find.text('An error occurred: $listError'), findsOneWidget);

    when(() => authService.signOut()).thenAnswer((_) async {
      throw Exception('network');
    });
    final readsBefore = (userReads, wishlistReads, groupReads);

    // Act
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();
    await tester.pump();

    // Assert: the session is still live, so the page must not be left inert.
    expect(userReads, readsBefore.$1 + 1);
    expect(wishlistReads, readsBefore.$2 + 1);
    expect(groupReads, readsBefore.$3 + 1);
    expect(listenerState(), everyElement(isTrue));
    expect(find.text(signOutFailedMessage), findsOneWidget);
    expect(find.text('An error occurred: $listError'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'serves another attempt and leaves no extra listener on failure',
    (tester) async {
      // Arrange
      await loadSignedInHome(tester);
      var signOutCalls = 0;
      when(() => authService.signOut()).thenAnswer((_) async {
        signOutCalls++;
        throw Exception('network');
      });

      // Act
      await tester.tap(find.byTooltip('Logout'));
      await tester.pump();
      await tester.pump();

      // Assert: the in-flight guard was reset by the failed attempt.
      await tester.tap(find.byTooltip('Logout'));
      await tester.pump();
      expect(signOutCalls, 2);

      // Act: a successful sign-out cancels every listener. A duplicate listener
      // left behind by the restart would keep `hasListener` true.
      when(() => authService.signOut()).thenAnswer((_) async {
        signedIn = false;
      });
      await tester.tap(find.byTooltip('Logout'));
      await tester.pump();

      // Assert
      expect(listenerState(), everyElement(isFalse));
    },
  );

  testWidgets(
    'drops the dead session when sign-out cleared it before failing',
    (tester) async {
      // Arrange
      await loadSignedInHome(tester);
      when(() => authService.signOut()).thenAnswer((_) async {
        signedIn = false;
        throw Exception('network');
      });
      final readsBefore = (userReads, wishlistReads, groupReads);

      // Act
      await tester.tap(find.byTooltip('Logout'));
      await tester.pump();
      await tester.pump();

      // Assert: no restart against a session that is already gone, and no claim
      // that the user is still signed in.
      expect((userReads, wishlistReads, groupReads), readsBefore);
      expect(listenerState(), everyElement(isFalse));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(signOutFailedMessage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ignores a second tap while sign-out is in flight', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    final pending = Completer<void>();
    var signOutCalls = 0;
    when(() => authService.signOut()).thenAnswer((_) {
      signOutCalls++;
      return pending.future;
    });

    // Act: both taps land before the first sign-out completes.
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert
    expect(signOutCalls, 1);

    // Act: a tap after the first one finishes is served again.
    pending.complete();
    await tester.pump();
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert
    expect(signOutCalls, 2);
  });

  testWidgets('shows the empty placeholder when a list stream ends empty', (
    tester,
  ) async {
    // Arrange
    when(() => wishlistRepository.streamWhere('ownerId', isEqualTo: uid))
        .thenAnswer((_) => Stream<List<Wishlist>>.empty());

    // Act
    await pumpHome(tester);
    userStream.add(user);
    await tester.pump();

    // Assert: the wishlist section settles on its placeholder. The group
    // section is still waiting, so the page itself keeps its spinner.
    expect(find.text(emptyWishlistsMessage), findsOneWidget);
  });

  testWidgets('shows the error screen when the profile read fails', (
    tester,
  ) async {
    // Arrange
    await pumpHome(tester);

    // Act
    userStream.addError(Exception('offline'));
    await tester.pump();

    // Assert
    expect(find.text(userLoadFailedMessage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the error screen when the profile stream ends empty', (
    tester,
  ) async {
    // Arrange: a profile stream that completes without ever emitting. Awaiting
    // `StreamController.close()` inside a widget test hangs (the done event
    // needs the real event loop), so the stream is stubbed directly.
    when(() => userRepository.streamOne(uid))
        .thenAnswer((_) => Stream<User>.empty());

    // Act
    await pumpHome(tester);
    await tester.pump();

    // Assert
    expect(find.text(userLoadFailedMessage), findsOneWidget);
  });

  testWidgets(
    'subscribes to all three reads at once and never re-reads on rebuild',
    (tester) async {
      // Arrange: the reads start from the uid, not from the user document.
      await pumpHome(tester);
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));

      userStream.add(user);
      wishlistStream.add([wishlist]);
      groupStream.add([group]);
      await tester.pump();
      expect(find.text('Welcome, $displayName!'), findsOneWidget);
      expect(find.text(wishlistName), findsOneWidget);
      expect(find.text(groupName), findsOneWidget);

      // Act
      await forcePageRebuild(tester);

      // Assert
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));
    },
  );

  testWidgets('clears a list error when data arrives', (tester) async {
    // Arrange
    await pumpHome(tester);
    userStream.add(user);
    await tester.pump();
    final error = Exception('offline');
    wishlistStream.addError(error);
    await tester.pump();
    expect(find.text('An error occurred: $error'), findsOneWidget);

    // Act
    wishlistStream.add([wishlist]);
    groupStream.add([group]);
    await tester.pump();

    // Assert
    expect(find.text('An error occurred: $error'), findsNothing);
    expect(find.text(wishlistName), findsOneWidget);
  });
}
