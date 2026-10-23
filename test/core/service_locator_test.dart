import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

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
}
