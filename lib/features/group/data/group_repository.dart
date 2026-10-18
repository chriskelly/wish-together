import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

class GroupRepository extends FirebaseRepository<Group> {
  GroupRepository({super.firestore}) : super(Group.collectionName);

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

  /// The groups whose `members` array contains [userId].
  Future<List<Group>> listForMember(String userId) async {
    final snapshot = await instance
        .collection(collectionPath)
        .where('members', arrayContains: userId)
        .get();
    return snapshot.docs.map((doc) => fromFirestore(doc)).toList();
  }

  /// The groups owned by [ownerId].
  Future<List<Group>> listOwnedBy(String ownerId) async {
    final snapshot = await instance
        .collection(collectionPath)
        .where('ownerId', isEqualTo: ownerId)
        .get();
    return snapshot.docs.map((doc) => fromFirestore(doc)).toList();
  }

  /// Moves a group to [newOwnerId] and records the [remainingMembers].
  ///
  /// A single atomic update: the group never exists without an owner, and a
  /// security rule can require both fields to change together.
  Future<void> transferOwnership(
    String groupId,
    String newOwnerId,
    List<String> remainingMembers,
  ) {
    return updateData(groupId, {
      'ownerId': newOwnerId,
      'members': remainingMembers,
    });
  }
}
