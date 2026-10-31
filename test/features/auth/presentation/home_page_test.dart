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

  final user = User(id: uid, displayName: displayName);
  final wishlist = Wishlist(id: 'w1', name: wishlistName, ownerId: uid);
  final group = Group(id: 'g1', name: groupName, ownerId: uid, members: [uid]);

  setUp(() async {
    await getIt.reset();
    authService = MockAuthService();
    userRepository = MockUserRepository();
    wishlistRepository = MockWishlistRepository();
    groupRepository = MockGroupRepository();
    // Broadcast: the pre-change code resubscribes per rebuild, and a
    // single-subscription stream would fail structurally instead of logically.
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
      listenersAtSignOut.addAll([
        userStream.hasListener,
        wishlistStream.hasListener,
        groupStream.hasListener,
      ]);
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
  /// A `StatefulBuilder` returning the same `const HomePage()` would be a
  /// no-op: `Element.updateChild` short-circuits an identical widget, so the
  /// page would never rebuild and the assertions below would pass against the
  /// broken code.
  Future<void> forcePageRebuild(WidgetTester tester) async {
    tester.element(find.byType(HomePage)).markNeedsBuild();
    await tester.pump();
  }

  /// Loads the page in production order: the user document first, then the two
  /// lists.
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
    await forcePageRebuild(tester);

    // Assert
    expect((userReads, wishlistReads, groupReads), (0, 0, 0));
    expect(tester.takeException(), isNull);
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
