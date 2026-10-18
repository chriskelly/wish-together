import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/group/domain/group.dart';

void main() {
  group('GroupRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late GroupRepository groupRepository;

    const String testGroupId = 'test_group';
    const String testUserId = 'test_user';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      groupRepository = GroupRepository(firestore: fakeFirestore);
    });

    test('joinGroup should add a user to the group members list', () async {
      // ARRANGE: Create a group document without any members.
      await fakeFirestore.collection(Group.collectionName).doc(testGroupId).set(
        {'name': 'Test Group', 'members': []},
      );

      // ACT: Call the method to join the group.
      await groupRepository.joinGroup(testGroupId, testUserId);

      // ASSERT: Verify that the user was added to the members list.
      final doc = await fakeFirestore
          .collection(Group.collectionName)
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
        await fakeFirestore
            .collection(Group.collectionName)
            .doc(testGroupId)
            .set({
              'name': 'Test Group',
              'members': [
                testUserId,
                'another_user',
              ], // Add the user to the group.
            });

        // ACT: Call the method to leave the group.
        await groupRepository.leaveGroup(testGroupId, testUserId);

        // ASSERT: Verify that the user has been removed.
        final doc = await fakeFirestore
            .collection(Group.collectionName)
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

    test('listForMember returns the groups that contain the member', () async {
      // ARRANGE: one group the user belongs to, one they do not.
      final groups = fakeFirestore.collection(Group.collectionName);
      await groups.doc('member-of').set({
        'name': 'Member Of',
        'ownerId': 'someone',
        'members': ['someone', testUserId],
      });
      await groups.doc('not-member-of').set({
        'name': 'Not Member Of',
        'ownerId': 'someone-else',
        'members': ['someone-else'],
      });

      // ACT
      final found = await groupRepository.listForMember(testUserId);

      // ASSERT
      expect(found.map((group) => group.id), ['member-of']);
    });

    test('listOwnedBy returns only the groups the user owns', () async {
      // ARRANGE: one owned group, one group the user does not own.
      final groups = fakeFirestore.collection(Group.collectionName);
      await groups.doc('owned').set({
        'name': 'Owned',
        'ownerId': testUserId,
        'members': [testUserId],
      });
      await groups.doc('joined').set({
        'name': 'Joined',
        'ownerId': 'someone-else',
        'members': ['someone-else', testUserId],
      });

      // ACT
      final owned = await groupRepository.listOwnedBy(testUserId);

      // ASSERT
      expect(owned.map((group) => group.id), ['owned']);
    });

    test('transferOwnership hands the group to the new owner and records the remaining members', () async {
      // ARRANGE: a group owned by the departing user, with one other member.
      const newOwnerId = 'stayer';
      await fakeFirestore.collection(Group.collectionName).doc(testGroupId).set(
        {
          'name': 'Test Group',
          'ownerId': testUserId,
          'members': [testUserId, newOwnerId],
        },
      );

      // ACT
      await groupRepository.transferOwnership(testGroupId, newOwnerId, [
        newOwnerId,
      ]);

      // ASSERT
      final data =
          (await fakeFirestore
                  .collection(Group.collectionName)
                  .doc(testGroupId)
                  .get())
              .data();
      expect(data?['ownerId'], newOwnerId);
      expect(data?['members'], [newOwnerId]);
    });
  });
}
