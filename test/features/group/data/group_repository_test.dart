import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';

void main() {
  group('GroupRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late GroupRepository groupRepository;

    const String groupsCollection = 'groups';
    const String testGroupId = 'test_group';
    const String testUserId = 'test_user';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore: fakeFirestore);
    });

    test('joinGroup should add a user to the group members list', () async {
      // ARRANGE: Create a group document without any members.
      await fakeFirestore.collection(groupsCollection).doc(testGroupId).set({
        'name': 'Test Group',
        'members': [],
      });

      // ACT: Call the method to join the group.
      await groupRepository.joinGroup(testGroupId, testUserId);

      // ASSERT: Verify that the user was added to the members list.
      final doc = await fakeFirestore
          .collection(groupsCollection)
          .doc(testGroupId)
          .get();
      final members = doc.data()?['members'] as List<dynamic>?;

      expect(members, isNotNull, reason: 'Members list should not be null.');
      expect(
        members,
        contains(testUserId),
        reason: 'The user should be in the members list.',
      );
    });

    test(
      'leaveGroup should remove a user from the group members list',
      () async {
        // ARRANGE: Create a group with the user already in the members list.
        await fakeFirestore.collection(groupsCollection).doc(testGroupId).set({
          'name': 'Test Group',
          'members': [testUserId, 'another_user'], // Add the user to the group.
        });

        // ACT: Call the method to leave the group.
        await groupRepository.leaveGroup(testGroupId, testUserId);

        // ASSERT: Verify that the user has been removed.
        final doc = await fakeFirestore
            .collection(groupsCollection)
            .doc(testGroupId)
            .get();
        final members = doc.data()?['members'] as List<dynamic>?;

        expect(
          members,
          isNotNull,
          reason: 'Members list should not be null after leaving.',
        );
        expect(
          members,
          isNot(contains(testUserId)),
          reason: 'The user should no longer be in the group.',
        );
        expect(
          members,
          contains('another_user'),
          reason: 'The other member should still be in the group.',
        );
      },
    );
  });
}
