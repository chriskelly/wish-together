import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

void main() {
  group('UserRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late UserRepository userRepository;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      userRepository = UserRepository(firestore: fakeFirestore);
    });

    test(
      'streamUsersFromIds should return a stream of users for the given IDs',
      () async {
        // 1. Setup: Create and add users to the fake database
        final user1 = User(id: 'user1', displayName: 'Alice');
        final user2 = User(id: 'user2', displayName: 'Bob');
        final user3 = User(
          id: 'user3',
          displayName: 'Charlie',
        ); // This user won't be queried

        await fakeFirestore
            .collection('users')
            .doc(user1.id)
            .set(user1.toMap());
        await fakeFirestore
            .collection('users')
            .doc(user2.id)
            .set(user2.toMap());
        await fakeFirestore
            .collection('users')
            .doc(user3.id)
            .set(user3.toMap());

        final userIds = ['user1', 'user2'];

        // 2. Act: Call the method to get the stream
        final stream = userRepository.streamUsersFromIds(userIds);

        // 3. Assert: Check if the stream emits the correct list of users
        expect(
          stream,
          emitsInOrder([
            (List<User> users) {
              expect(users.length, 2);
              expect(
                users.any((u) => u.id == 'user1' && u.displayName == 'Alice'),
                isTrue,
              );
              expect(
                users.any((u) => u.id == 'user2' && u.displayName == 'Bob'),
                isTrue,
              );
              return true; // Return true if all checks pass
            },
          ]),
        );
      },
    );

    test(
      'streamUsersFromIds should return an empty stream if ID list is empty',
      () async {
        // 1. Setup: No users needed, just an empty list
        final userIds = <String>[];

        // 2. Act: Call the method with an empty list
        final stream = userRepository.streamUsersFromIds(userIds);

        // 3. Assert: Expect the stream to emit an empty list
        expect(stream, emitsInOrder([[]]));
      },
    );
  });
}
