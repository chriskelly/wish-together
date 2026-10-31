import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockAuthService extends Mock implements AuthService {}

/// A session that is not the production service, which is what the seam exists
/// for.
class MockAuthSession extends Mock implements AuthSession {}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('every repository reads and writes the build Firestore instance', () {
    final firestore = MockFirebaseFirestore();

    setupServiceLocator(firestore: firestore);

    expect(getIt<WishlistRepository>().instance, same(firestore));
    expect(
      getIt<WishlistRepository>().items('wishlist-id').instance,
      same(firestore),
    );
    expect(getIt<GroupRepository>().instance, same(firestore));
    expect(getIt<UserRepository>().instance, same(firestore));
  });

  test('the session and the auth service are one instance', () {
    final firestore = MockFirebaseFirestore();
    final authService = MockAuthService();

    setupServiceLocator(firestore: firestore, authSession: authService);

    expect(getIt<AuthSession>(), same(authService));
    expect(getIt<AuthService>(), same(authService));
  });

  test('the production branch builds one service and serves both types', () {
    final firestore = MockFirebaseFirestore();
    final authService = MockAuthService();
    var builds = 0;

    // No session supplied: the locator builds the service, and both types must
    // resolve to that one object. A second build would mean two identities.
    setupServiceLocator(
      firestore: firestore,
      createAuthService: () {
        builds++;
        return authService;
      },
    );

    expect(getIt<AuthSession>(), same(authService));
    expect(getIt<AuthService>(), same(authService));
    expect(builds, 1);
  });

  test('a supplied session is what the signed-in shell resolves', () {
    final firestore = MockFirebaseFirestore();
    final session = MockAuthSession();

    // The mock stands in, so resolving the session needs no Firebase.
    setupServiceLocator(firestore: firestore, authSession: session);

    expect(getIt<AuthSession>(), same(session));
  });

  test('a session without the production service cannot resolve one', () {
    final firestore = MockFirebaseFirestore();

    setupServiceLocator(firestore: firestore, authSession: MockAuthSession());

    expect(() => getIt<AuthService>(), throwsStateError);
  });
}
