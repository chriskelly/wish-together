import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/brand_hero.dart';
import 'package:wishtogether/core/providers.dart';
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
const String wishlistDeletedMessage = 'Wishlist deleted.';
const String groupDeletedMessage = 'Group deleted.';
const String lateWishlistName = 'Late arrival';
const String lateGroupName = 'Late group';

void main() {
  late MockAuthService authService;
  late MockUserRepository userRepository;
  late MockWishlistRepository wishlistRepository;
  late MockGroupRepository groupRepository;
  late StreamController<User> userStream;
  late StreamController<List<Wishlist>> wishlistStream;
  late StreamController<List<Group>> groupStream;
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

  List<Override> homeOverrides() => [
    authSessionProvider.overrideWithValue(authService),
    userRepositoryProvider.overrideWithValue(userRepository),
    wishlistRepositoryProvider.overrideWithValue(wishlistRepository),
    groupRepositoryProvider.overrideWithValue(groupRepository),
  ];

  setUp(() {
    authService = MockAuthService();
    userRepository = MockUserRepository();
    wishlistRepository = MockWishlistRepository();
    groupRepository = MockGroupRepository();
    // Broadcast, so the same controller can be listened to again after a
    // restart and `hasListener` stays a usable assertion.
    userStream = StreamController<User>.broadcast();
    wishlistStream = StreamController<List<Wishlist>>.broadcast();
    groupStream = StreamController<List<Group>>.broadcast();
    signedIn = true;
    userReads = 0;
    wishlistReads = 0;
    groupReads = 0;

    when(() => authService.currentUserId)
        .thenAnswer((_) => signedIn ? uid : null);
    when(() => authService.supportsSignOut).thenReturn(true);
    when(() => authService.signOut()).thenAnswer((_) async {
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
  });

  tearDown(() async {
    await userStream.close();
    await wishlistStream.close();
    await groupStream.close();
  });

  Future<void> pumpHome(WidgetTester tester) => tester.pumpWidget(
    ProviderScope(
      retry: disableAutomaticRetry,
      overrides: homeOverrides(),
      child: const MaterialApp(home: HomePage()),
    ),
  );

  /// Rebuilds the page the way the router does: the element is dirtied and a
  /// frame runs, so `HomePage.build` executes again.
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

  testWidgets('offers no sign-out control when the session cannot sign out', (
    tester,
  ) async {
    // Arrange: a session that reports it has no sign-out behind it.
    when(() => authService.supportsSignOut).thenReturn(false);

    // Act
    await loadSignedInHome(tester);

    // Assert: the page renders its data, but offers no sign-out control.
    expect(find.text(wishlistName), findsOneWidget);
    expect(find.byTooltip('Logout'), findsNothing);
    expect(find.byTooltip('Profile'), findsOneWidget);
  });

  testWidgets('cancels every home read before the session is cleared', (
    tester,
  ) async {
    // Arrange: the session records whether each read still has a listener at
    // the moment the credential is cleared.
    final listenersAtSignOut = <bool>[];
    when(() => authService.signOut()).thenAnswer((_) async {
      listenersAtSignOut.addAll(listenerState());
      signedIn = false;
    });
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

  testWidgets('drops a snapshot that arrives after sign-out', (tester) async {
    // Arrange
    await loadSignedInHome(tester);
    final readsBefore = (userReads, wishlistReads, groupReads);
    final lateWishlist = Wishlist(
      id: 'w2',
      name: lateWishlistName,
      ownerId: uid,
    );
    final lateGroup = Group(
      id: 'g2',
      name: lateGroupName,
      ownerId: uid,
      members: [uid],
    );

    // Act
    await tester.tap(find.byTooltip('Logout'));
    // The detach is synchronous: assert it before the page's next frame, where
    // autoDispose alone would remove the listeners anyway.
    expect(listenerState(), everyElement(isFalse));
    await tester.pump();
    wishlistStream.add([lateWishlist]);
    groupStream.add([lateGroup]);
    await forcePageRebuild(tester);

    // Assert: the cancel left no listener to receive the late values, the gate
    // hides them anyway, and the rebuild issues no new read.
    expect(find.text(lateWishlistName), findsNothing);
    expect(find.text(lateGroupName), findsNothing);
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
    expect(find.byTooltip('Logout'), findsNothing);

    // Act
    await forcePageRebuild(tester);

    // Assert
    expect((userReads, wishlistReads, groupReads), (0, 0, 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('restarts its reads and clears the previous errors on failure', (
    tester,
  ) async {
    // Arrange: a failed list read, so the restart has an error to clear.
    await loadSignedInHome(tester);
    final listError = Exception('offline');
    final groupsError = Exception('groups offline');
    wishlistStream.addError(listError);
    groupStream.addError(groupsError);
    await tester.pump();
    expect(find.text('An error occurred: $listError'), findsOneWidget);
    expect(find.text('An error occurred: $groupsError'), findsOneWidget);

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
    expect(find.text('An error occurred: $groupsError'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(wishlistName), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('serves another attempt after a failed sign-out', (tester) async {
    // Arrange
    await loadSignedInHome(tester);
    var signOutCalls = 0;
    when(() => authService.signOut()).thenAnswer((_) async {
      signOutCalls++;
      throw Exception('network');
    });
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();
    await tester.pump();

    // Act: the in-flight guard was reset by the failed attempt, and the
    // loading state kept the control reachable.
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert
    expect(signOutCalls, 2);
  });

  testWidgets('leaves no extra listener behind after a failed sign-out', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    when(() => authService.signOut()).thenAnswer((_) async {
      throw Exception('network');
    });
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();
    await tester.pump();
    expect(listenerState(), everyElement(isTrue));

    // Act: a successful sign-out cancels every listener. A duplicate listener
    // left behind by the restart would keep `hasListener` true.
    when(() => authService.signOut()).thenAnswer((_) async {
      signedIn = false;
    });
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert
    expect(listenerState(), everyElement(isFalse));
  });

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

  testWidgets('shows the loading state while a sign-out is in flight', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    final pending = Completer<void>();
    when(() => authService.signOut()).thenAnswer((_) => pending.future);

    // Act
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Assert: the reads are detached and the page says so, but the controls
    // that a failed attempt must offer stay reachable.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(wishlistName), findsNothing);
    expect(find.byTooltip('Logout'), findsOneWidget);
    expect(find.byTooltip('Profile'), findsOneWidget);

    pending.complete();
    await tester.pump();
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

  testWidgets('shows the error screen when the profile read fails after data', (
    tester,
  ) async {
    // Arrange: the page rendered a user before the read failed.
    await loadSignedInHome(tester);
    expect(find.text(wishlistName), findsOneWidget);

    // Act
    userStream.addError(Exception('offline'));
    await tester.pump();

    // Assert: an error outranks the value AsyncValue retained, as it always
    // has, so no stale home data sits under the failure.
    expect(find.text(userLoadFailedMessage), findsOneWidget);
    expect(find.text(wishlistName), findsNothing);
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
    'keeps one subscription per read across rebuilds, text scale and dialogs',
    (tester) async {
      // Wide enough that a 1.5 text scale does not overflow the square test
      // font in a section header.
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(1400, 900) * 3.0;
      addTearDown(tester.view.reset);

      late StateSetter setHostState;
      var pageBuilds = 0;
      await tester.pumpWidget(
        ProviderScope(
          retry: disableAutomaticRetry,
          overrides: homeOverrides(),
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                // Register a MediaQuery dependency so a text-scale change
                // rebuilds this host, and build a fresh page so its own build
                // runs rather than being skipped as an identical widget.
                MediaQuery.textScalerOf(context);
                pageBuilds++;
                return HomePage();
              },
            ),
          ),
        ),
      );

      // The reads start from the uid, not from the user document.
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));
      // A signed-in load offers the actions while it waits; only a page with no
      // session is a bare spinner.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byTooltip('Logout'), findsOneWidget);
      userStream.add(user);
      wishlistStream.add([wishlist]);
      groupStream.add([group]);
      await tester.pump();
      expect(pageBuilds, 1);
      expect(find.byType(BrandHero), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Welcome,'), findsOneWidget);
      expect(find.text('$displayName!'), findsOneWidget);
      expect(find.text(wishlistName), findsOneWidget);
      expect(find.text(groupName), findsOneWidget);

      // Act: a host rebuild.
      setHostState(() {});
      await tester.pumpAndSettle();
      expect(pageBuilds, 2);
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));

      // Act: a text-scale change.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(pageBuilds, 3);
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));

      // Act: a delete dialog opened and cancelled.
      await tester.tap(find.byTooltip('Delete Wishlist'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Deletion'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Assert
      expect((userReads, wishlistReads, groupReads), (1, 1, 1));
    },
  );

  testWidgets('starts its reads again for a new home lifetime', (tester) async {
    // Arrange: a host that can take the page out and put it back under the
    // same ProviderScope.
    late StateSetter setHostState;
    var showHome = true;
    await tester.pumpWidget(
      ProviderScope(
        retry: disableAutomaticRetry,
        overrides: homeOverrides(),
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return showHome ? HomePage() : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    userStream.add(user);
    wishlistStream.add([wishlist]);
    groupStream.add([group]);
    await tester.pump();
    expect((userReads, wishlistReads, groupReads), (1, 1, 1));

    // Act: a successful sign-out closes the gate for this lifetime.
    when(() => authService.signOut()).thenAnswer((_) async {
      signedIn = false;
    });
    await tester.tap(find.byTooltip('Logout'));
    await tester.pump();

    // Act: leave home and come back with a live session. The gate is
    // auto-disposed with the page, so the new lifetime must read again.
    setHostState(() => showHome = false);
    await tester.pump(const Duration(milliseconds: 10));
    signedIn = true;
    setHostState(() => showHome = true);
    await tester.pump();
    await tester.pump();

    // Assert
    expect((userReads, wishlistReads, groupReads), (2, 2, 2));
  });

  testWidgets('deletes a wishlist together with its items', (tester) async {
    // Arrange: the cascade is the operation the confirmed delete must use.
    when(() => wishlistRepository.deleteWithItems(wishlist.id!))
        .thenAnswer((_) async {});
    await loadSignedInHome(tester);

    // Act: confirm the deletion dialog.
    await tester.tap(find.byTooltip('Delete Wishlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Assert: the items are purged with the wishlist, and the document-only
    // delete is not used.
    verify(() => wishlistRepository.deleteWithItems(wishlist.id!)).called(1);
    verifyNever(() => wishlistRepository.delete(wishlist.id!));
    expect(find.text(wishlistDeletedMessage), findsOneWidget);
  });

  testWidgets('leaves the wishlist alone when the deletion is cancelled', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);

    // Act: back out of the confirmation dialog.
    await tester.tap(find.byTooltip('Delete Wishlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Assert: neither delete path ran, and no snackbar claims otherwise.
    verifyNever(() => wishlistRepository.deleteWithItems(wishlist.id!));
    verifyNever(() => wishlistRepository.delete(wishlist.id!));
    expect(find.text(wishlistDeletedMessage), findsNothing);
  });

  testWidgets('reports a failed cascade instead of claiming the delete', (
    tester,
  ) async {
    // Arrange: the item purge fails, so no wishlist document is removed and
    // the user must not be told the wishlist was deleted.
    final failure = Exception('items offline');
    when(() => wishlistRepository.deleteWithItems(wishlist.id!))
        .thenAnswer((_) => Future<void>.error(failure));
    await loadSignedInHome(tester);

    // Act
    await tester.tap(find.byTooltip('Delete Wishlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('Error: $failure'), findsOneWidget);
    expect(find.text(wishlistDeletedMessage), findsNothing);
  });

  testWidgets('offers the owner a group delete and calls delete', (
    tester,
  ) async {
    // Arrange
    when(() => groupRepository.delete(group.id!)).thenAnswer((_) async {});
    await loadSignedInHome(tester);

    // Act
    await tester.tap(find.byTooltip('Delete Group'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Assert
    verify(() => groupRepository.delete(group.id!)).called(1);
    expect(find.text(groupDeletedMessage), findsOneWidget);
  });

  testWidgets('offers no group delete to a member who is not the owner', (
    tester,
  ) async {
    // Arrange
    await loadSignedInHome(tester);
    final otherGroup = Group(
      id: 'g2',
      name: 'Book club',
      ownerId: 'someone-else',
      members: [uid],
    );

    // Act
    groupStream.add([otherGroup]);
    await tester.pump();

    // Assert
    expect(find.text('Book club'), findsOneWidget);
    expect(find.byTooltip('Delete Group'), findsNothing);
  });

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
