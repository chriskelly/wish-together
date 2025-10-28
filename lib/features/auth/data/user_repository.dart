import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/core/data/firebase_repository.dart';
import 'package:myapp/features/auth/domain/user.dart';

class UserRepository extends FirebaseRepository<User> {
  UserRepository() : super('users');

  @override
  User fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return User.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(User user) {
    return user.toMap();
  }
}
