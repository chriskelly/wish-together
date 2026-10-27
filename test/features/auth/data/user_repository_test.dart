import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

import '../../../core/logging/recording_sink.dart';

/// Fails before any Firestore call, to pin the open path's guard.
class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    throw StateError('read failed');
  }
}

/// Fails while mapping, which is what a malformed member document does.
class ThrowingUserRepository extends UserRepository {
  ThrowingUserRepository({super.firestore});

  @override
  User fromFirestore(DocumentSnapshot doc) => throw TypeError();
}

/// Fails while building the create payload, which the write guard covers.
class UnwritableUserRepository extends UserRepository {
  UnwritableUserRepository({super.firestore});

  @override
  Map<String, dynamic> toFirestore(User user) =>
      throw StateError('write failed');
}

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
            .collection(User.collectionName)
            .doc(user1.id)
            .set(user1.toMap());
        await fakeFirestore
            .collection(User.collectionName)
            .doc(user2.id)
            .set(user2.toMap());
        await fakeFirestore
            .collection(User.collectionName)
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

  group('UserRepository diagnostics', () {
    const String uid = 'user1';
    late RecordingSink sink;

    setUp(() {
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      addTearDown(getIt.reset);
    });

    test('reports a failed profile read', () async {
      // Arrange
      final repository = UserRepository(firestore: ThrowingFirestore());

      // Act & Assert
      await expectLater(
        repository.getOrCreateUser(uid),
        throwsA(isA<StateError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.get);
      expect(event.collection, User.collectionName);
    });

    test('reports a failed profile create', () async {
      // Arrange: the read finds nothing, so the create write runs and fails
      // while building its payload.
      final repository = UnwritableUserRepository(
        firestore: FakeFirebaseFirestore(),
      );

      // Act & Assert
      await expectLater(
        repository.getOrCreateUser(uid, displayName: 'Alice'),
        throwsA(isA<StateError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.write);
      expect(event.collection, User.collectionName);
    });

    test('reports and forwards a failed member stream', () async {
      // Arrange: a member document the model cannot read.
      final firestore = FakeFirebaseFirestore();
      await firestore.collection(User.collectionName).doc(uid).set(
        <String, dynamic>{'displayName': null},
      );
      final repository = ThrowingUserRepository(firestore: firestore);

      // Act
      final stream = repository.streamUsersFromIds(<String>[uid]);

      // Assert: the listener still receives the error, not only the sink.
      await expectLater(stream, emitsError(isA<TypeError>()));

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.list);
      expect(event.collection, User.collectionName);
    });
  });
}
