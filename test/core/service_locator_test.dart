import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// A session that never touches Firebase, standing in for the dev entrypoint's.
class FakeSession implements AuthSession {
  @override
  String? get currentUserId => 'fake-uid';

  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserPhoneNumber => null;

  @override
  List<String> get providerIds => const <String>[];

  @override
  Stream<String?> get uidChanges => const Stream<String?>.empty();

  @override
  Future<void> signOut() async {}

  @override
  bool get supportsAccountDeletion => false;
}

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
    final authService = AuthService(auth: MockFirebaseAuth(), isWeb: true);

    setupServiceLocator(firestore: firestore, authSession: authService);

    expect(getIt<AuthSession>(), same(authService));
    expect(getIt<AuthService>(), same(authService));
  });

  test('a supplied session is what the signed-in shell resolves', () {
    final firestore = MockFirebaseFirestore();
    final session = FakeSession();

    setupServiceLocator(firestore: firestore, authSession: session);

    expect(getIt<AuthSession>(), same(session));
  });
}
