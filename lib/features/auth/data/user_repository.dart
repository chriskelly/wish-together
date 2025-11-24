import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';

class UserRepository extends FirebaseRepository<User> {
  UserRepository({FirebaseFirestore? firestore})
    : super(User.collectionName, firestore: firestore);

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
    final doc = await instance.collection(collectionPath).doc(uid).get();
    if (doc.exists) {
      return fromFirestore(doc);
    } else {
      final newUser = User(
        email: email,
        displayName: displayName,
        phoneNumber: phoneNumber,
      );
      await instance
          .collection(collectionPath)
          .doc(uid)
          .set(toFirestore(newUser));
      final confirmedUser = await get(uid);
      return confirmedUser;
    }
  }

  Stream<List<User>> streamUsersFromIds(List<String> userIds) {
    if (userIds.isEmpty) {
      return Stream.value([]);
    }
    return instance
        .collection(collectionPath)
        .where(FieldPath.documentId, whereIn: userIds)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) => fromFirestore(doc)).toList(),
        );
  }
}
