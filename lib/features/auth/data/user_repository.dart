import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

class UserRepository extends FirebaseRepository<User> {
  UserRepository({super.firestore}) : super(User.collectionName);

  @override
  User fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return User.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(User user) {
    return user.toMap();
  }

  Future<User> getOrCreateUser(
    String uid, {
    String? email,
    String? displayName,
    String? phoneNumber,
  }) async {
    // Both raw calls go through the base seam: this override bypasses `get`
    // and `add`, and an unguarded read here fails completely silently.
    final existing = await reportingFuture(FirestoreOp.get, () async {
      final doc = await instance.collection(collectionPath).doc(uid).get();
      return doc.exists ? fromFirestore(doc) : null;
    });
    if (existing != null) {
      return existing;
    }

    final newUser = User(
      email: email,
      displayName: displayName,
      phoneNumber: phoneNumber,
    );
    await reportingFuture(
      FirestoreOp.write,
      () => instance
          .collection(collectionPath)
          .doc(uid)
          .set(toFirestore(newUser)),
    );
    return get(uid);
  }

  Stream<List<User>> streamUsersFromIds(List<String> userIds) {
    if (userIds.isEmpty) {
      return Stream.value([]);
    }
    return reportingStream(
      instance
          .collection(collectionPath)
          .where(FieldPath.documentId, whereIn: userIds)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map((doc) => fromFirestore(doc)).toList(),
          ),
      FirestoreOp.list,
    );
  }
}
