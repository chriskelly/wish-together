import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class GroupRepository extends FirebaseRepository<Group> {
  GroupRepository({FirebaseFirestore? firestore})
    : super(Group.collectionName, firestore: firestore);

  @override
  Group fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Group.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(Group group) {
    return group.toMap();
  }

  Future<void> joinGroup(String groupId, String userId) {
    return updateData(groupId, {
      'members': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> leaveGroup(String groupId, String userId) {
    return updateData(groupId, {
      'members': FieldValue.arrayRemove([userId]),
    });
  }
}
