import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/fixtures/dev_fixture.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/group/data/group_repository.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

/// Harness-contract tests: every repository operation a signed-in page issues,
/// run against `FakeFirebaseFirestore` through the real repositories.
///
/// The fake is what a dev session reads and writes, so a query it cannot serve
/// would make a screenshot lie. Each test below names the page that makes the
/// call, and the seeding goes through [seedDevFirestore], the same loop a dev
/// session uses — so the fixture format and the operation are exercised
/// together.
///
/// Two things are pinned elsewhere on purpose:
///
/// - the paged cascade in `WishlistRepository.deleteWithItems` (the 501-item
///   case), in `test/features/wishlist/data/wishlist_repository_test.dart`;
/// - the divergence list an agent reads before trusting a fake-mode success, in
///   `lib/dev/OVERVIEW.md`.
///
/// The last group pins behaviour where the fake *differs* from Firestore. Those
/// tests are not assertions that the fake is right: they fail loudly if a
/// dependency upgrade changes the gap, so the divergence list cannot quietly go
/// stale.
const String viewerUid = 'dev-u1';
const String otherUid = 'dev-u2';

/// Seeds a store exactly the way a dev session does.
Future<FakeFirebaseFirestore> seededStore(
  Map<String, Map<String, dynamic>> documents,
) async {
  final firestore = FakeFirebaseFirestore();
  await seedDevFirestore(
    firestore,
    DevFixture(id: 'parity', viewerUid: viewerUid, documents: documents),
  );
  return firestore;
}

void main() {
  group('reads a page issues', () {
    test('home lists the wishlists the viewer owns', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/mine': <String, dynamic>{
          'name': 'Mine',
          'ownerId': viewerUid,
          'sharedWithGroups': <String>[],
        },
        'wishlists/theirs': <String, dynamic>{
          'name': 'Theirs',
          'ownerId': otherUid,
          'sharedWithGroups': <String>[],
        },
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT: the exact query shape `home_page.dart` subscribes to.
      final wishlists = await repository
          .streamWhere('ownerId', isEqualTo: viewerUid)
          .first;

      // ASSERT
      expect(wishlists.map((wishlist) => wishlist.name), <String>['Mine']);
    });

    test('home lists the groups the viewer belongs to', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'groups/ours': <String, dynamic>{
          'name': 'Ours',
          'ownerId': otherUid,
          'members': <String>[viewerUid, otherUid],
        },
        'groups/not-ours': <String, dynamic>{
          'name': 'Not ours',
          'ownerId': otherUid,
          'members': <String>[otherUid],
        },
      });
      final repository = GroupRepository(firestore: firestore);

      // ACT
      final groups = await repository
          .streamWhere('members', arrayContains: viewerUid)
          .first;

      // ASSERT
      expect(groups.map((group) => group.name), <String>['Ours']);
    });

    test('group details lists the members named in the group', () async {
      // ARRANGE: the page reads the group, then the users its members array
      // names, which is the only `documentId whereIn` in the app.
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'users/$viewerUid': <String, dynamic>{'displayName': 'Ana Dev'},
        'users/$otherUid': <String, dynamic>{'displayName': 'Ben Dev'},
        'users/dev-u3': <String, dynamic>{'displayName': 'Cleo Dev'},
        'groups/g1': <String, dynamic>{
          'name': 'Family',
          'ownerId': viewerUid,
          'members': <String>[viewerUid, otherUid, 'dev-u3'],
        },
      });
      final groupRepository = GroupRepository(firestore: firestore);
      final userRepository = UserRepository(firestore: firestore);
      final group = await groupRepository.streamOne('g1').first;

      // ACT
      final members = await userRepository
          .streamUsersFromIds(group.members)
          .first;

      // ASSERT
      expect(
        members.map((user) => user.displayName),
        unorderedEquals(<String>['Ana Dev', 'Ben Dev', 'Cleo Dev']),
      );
    });

    test('group details lists the wishlists shared with the group', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/shared': <String, dynamic>{
          'name': 'Shared',
          'ownerId': otherUid,
          'sharedWithGroups': <String>['g1'],
        },
        'wishlists/private': <String, dynamic>{
          'name': 'Private',
          'ownerId': otherUid,
          'sharedWithGroups': <String>[],
        },
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT
      final shared = await repository
          .streamWhere('sharedWithGroups', arrayContains: 'g1')
          .first;

      // ASSERT
      expect(shared.map((wishlist) => wishlist.name), <String>['Shared']);
    });

    test('a wishlist detail page streams only its own items', () async {
      // ARRANGE: two wishlists, one item each, in the nested collection.
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/l1/items/i1': <String, dynamic>{'name': 'Board game'},
        'wishlists/l2/items/i2': <String, dynamic>{'name': 'Cookbook'},
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT
      final items = await repository.items('l1').streamAll().first;

      // ASSERT: the sub-collection path is what scopes the read.
      expect(items.map((item) => item.name), <String>['Board game']);
    });

    test('account deletion reads the same rows in one shot', () async {
      // ARRANGE: `listWhere` is the one-shot counterpart the delete-account
      // use case needs, because it cannot wait on a stream.
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/mine': <String, dynamic>{
          'name': 'Mine',
          'ownerId': viewerUid,
          'sharedWithGroups': <String>[],
        },
        'wishlists/theirs': <String, dynamic>{
          'name': 'Theirs',
          'ownerId': otherUid,
          'sharedWithGroups': <String>[],
        },
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT
      final owned = await repository.listOwnedBy(viewerUid);

      // ASSERT
      expect(owned.map((wishlist) => wishlist.name), <String>['Mine']);
    });

    test('a write reaches a stream that is already open', () async {
      // ARRANGE: the page is subscribed before the write happens, which is what
      // makes a create or claim appear without a reload.
      final firestore = await seededStore(<String, Map<String, dynamic>>{});
      final repository = WishlistRepository(firestore: firestore);
      final emissions = <List<Wishlist>>[];
      final subscription = repository
          .streamWhere('ownerId', isEqualTo: viewerUid)
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      // ACT
      await repository.add(Wishlist(name: 'Created', ownerId: viewerUid));
      await pumpEventQueue();

      // ASSERT
      expect(
        emissions.last.map((wishlist) => wishlist.name),
        contains('Created'),
      );
    });
  });

  group('writes a page issues', () {
    test('joining a group appends the member once', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'groups/g1': <String, dynamic>{
          'name': 'Family',
          'ownerId': otherUid,
          'members': <String>[otherUid],
        },
      });
      final repository = GroupRepository(firestore: firestore);

      // ACT: `FieldValue.arrayUnion`, twice, as a double tap would.
      await repository.joinGroup('g1', viewerUid);
      await repository.joinGroup('g1', viewerUid);

      // ASSERT
      final group = await repository.streamOne('g1').first;
      expect(group.members, <String>[otherUid, viewerUid]);
    });

    test('leaving a group removes only the caller', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'groups/g1': <String, dynamic>{
          'name': 'Family',
          'ownerId': otherUid,
          'members': <String>[viewerUid, otherUid, 'dev-u3'],
        },
      });
      final repository = GroupRepository(firestore: firestore);

      // ACT
      await repository.leaveGroup('g1', viewerUid);

      // ASSERT
      final group = await repository.streamOne('g1').first;
      expect(group.members, <String>[otherUid, 'dev-u3']);
    });

    test('claiming an item stores a timestamp the model reads back', () async {
      // ARRANGE
      final claimedAt = DateTime.utc(2026, 10, 1);
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/l1/items/i1': <String, dynamic>{'name': 'Board game'},
      });
      final items = WishlistRepository(firestore: firestore).items('l1');

      // ACT: the claim use case writes the whole model through `update`.
      await items.update(
        'i1',
        Item(
          id: 'i1',
          name: 'Board game',
          claimedBy: viewerUid,
          claimedAt: claimedAt,
        ),
      );

      // ASSERT: the field is a Firestore Timestamp on disk and a DateTime in
      // the model, which is the conversion `ItemRepository` owns.
      final stored = await firestore.doc('wishlists/l1/items/i1').get();
      expect(stored.data()!['claimedAt'], isA<Timestamp>());
      final item = await items.streamOne('i1').first;
      expect(item.claimedBy, viewerUid);
      expect(item.claimedAt!.toUtc(), claimedAt);
    });

    test('unclaiming an item sets both claim fields to null', () async {
      // ARRANGE: a claimed item.
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/l1/items/i1': <String, dynamic>{
          'name': 'Board game',
          'claimedBy': viewerUid,
          'claimedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 1)),
        },
      });
      final items = WishlistRepository(firestore: firestore).items('l1');

      // ACT
      await items.unclaim('i1');

      // ASSERT: both fields exist and are null. `firestore.rules` accepts an
      // unclaimed item only when the pair is absent together, so a partial
      // update would be denied in production.
      final stored = await firestore.doc('wishlists/l1/items/i1').get();
      expect(stored.data()!.containsKey('claimedBy'), isTrue);
      expect(stored.data()!['claimedBy'], isNull);
      expect(stored.data()!.containsKey('claimedAt'), isTrue);
      expect(stored.data()!['claimedAt'], isNull);
      final item = await items.streamOne('i1').first;
      expect(item.claimedBy, isNull);
      expect(item.claimedAt, isNull);
    });

    test('deleting an item removes it from the nested collection', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/l1/items/i1': <String, dynamic>{'name': 'Board game'},
        'wishlists/l1/items/i2': <String, dynamic>{'name': 'Wool scarf'},
      });
      final items = WishlistRepository(firestore: firestore).items('l1');

      // ACT
      await items.delete('i1');

      // ASSERT: only the named item is gone.
      expect(await items.streamAll().first, hasLength(1));
      expect(
        (await firestore.doc('wishlists/l1/items/i1').get()).exists,
        isFalse,
      );
    });

    test('sharing a wishlist adds the group to its list', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/l1': <String, dynamic>{
          'name': 'Birthday list',
          'ownerId': viewerUid,
          'sharedWithGroups': <String>[],
        },
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT: the share use case reads the wishlist, appends the group id and
      // writes the whole model back.
      final wishlist = await repository.get('l1');
      await repository.update(
        'l1',
        wishlist.copyWith(sharedWithGroups: <String>['g1']),
      );

      // ASSERT
      final shared = await repository
          .streamWhere('sharedWithGroups', arrayContains: 'g1')
          .first;
      expect(shared.map((w) => w.id), <String>['l1']);
    });
  });

  group('where the fake differs from Firestore', () {
    test(
      'a missing document fails the read instead of yielding a model',
      () async {
        // ARRANGE: no wishlist at this id, which is what a stale deep link asks
        // for. `fromFirestore` casts a null snapshot, so the page's "not found"
        // state arrives as an error rather than a null model.
        final firestore = await seededStore(<String, Map<String, dynamic>>{});
        final repository = WishlistRepository(firestore: firestore);

        // ACT & ASSERT
        await expectLater(
          repository.streamOne('missing'),
          emitsError(isA<TypeError>()),
        );
      },
    );

    test('updating a missing document fails not-found', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{});
      final repository = WishlistRepository(firestore: firestore);

      // ACT & ASSERT: the fake reports the same code Firestore does, so a
      // write to a deleted document does not silently create one.
      await expectLater(
        repository.updateData('missing', <String, dynamic>{'name': 'Ghost'}),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );
    });

    test('a server timestamp is resolved at write time by the client clock', () async {
      // ARRANGE
      final firestore = await seededStore(<String, Map<String, dynamic>>{});

      // ACT
      await firestore.doc('probe/one').set(<String, dynamic>{
        'at': FieldValue.serverTimestamp(),
      });

      // ASSERT: already a Timestamp, never the sentinel. Firestore resolves it
      // on the server and shows a pending estimate first, so a scenario cannot
      // model the pending state or a server clock that differs from this one.
      final stored = await firestore.doc('probe/one').get();
      expect(stored.data()!['at'], isA<Timestamp>());
    });

    test('a batch commit applies its earlier tasks when a later one fails', () async {
      // ARRANGE: one real document, then a batch that writes it and then a
      // document that does not exist.
      final firestore = await seededStore(<String, Map<String, dynamic>>{});
      await firestore.doc('probe/kept').set(<String, dynamic>{'n': 1});
      final batch = firestore.batch()
        ..update(firestore.doc('probe/kept'), <String, dynamic>{'n': 2})
        ..update(firestore.doc('probe/missing'), <String, dynamic>{'n': 3});

      // ACT
      await expectLater(batch.commit(), throwsA(isA<FirebaseException>()));

      // ASSERT: task by task, so the first write survived. Firestore would roll
      // the whole batch back, which is why a fake-mode success cannot prove a
      // multi-document write is atomic.
      final kept = await firestore.doc('probe/kept').get();
      expect(kept.data()!['n'], 2);
    });

    test('reads a group of thirty members in one query', () async {
      // ARRANGE: the largest `whereIn` Firestore accepts.
      final members = List<String>.generate(30, (index) => 'member-$index');
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        for (final uid in members)
          'users/$uid': <String, dynamic>{'displayName': uid},
      });
      final repository = UserRepository(firestore: firestore);

      // ACT
      final users = await repository.streamUsersFromIds(members).first;

      // ASSERT
      expect(users, hasLength(30));
    });

    test(
      'rejects a thirty-one value whereIn once it evaluates a document',
      () async {
        // ARRANGE: `UserRepository.streamUsersFromIds` sends the whole member
        // list as one `whereIn`, and neither backend chunks it. The unrelated
        // user document is what makes the fake evaluate the predicate.
        final members = List<String>.generate(31, (index) => 'member-$index');
        final firestore = await seededStore(<String, Map<String, dynamic>>{
          'users/bystander': <String, dynamic>{'displayName': 'Bystander'},
        });
        final repository = UserRepository(firestore: firestore);

        // ACT & ASSERT: a group this large fails the members read on both
        // backends, so it is a limit of the app, not of the fake.
        await expectLater(
          repository.streamUsersFromIds(members),
          emitsError(isA<ArgumentError>()),
        );
      },
    );

    test(
      'accepts a thirty-one value whereIn when it evaluates no document',
      () async {
        // ARRANGE: the same over-limit query, against an empty collection.
        final members = List<String>.generate(31, (index) => 'member-$index');
        final firestore = await seededStore(<String, Map<String, dynamic>>{});
        final repository = UserRepository(firestore: firestore);

        // ACT & ASSERT: no error, an empty list. The fake enforces the 30-value
        // cap inside its per-document predicate, so an over-limit query that
        // matches nothing looks fine here and is rejected by Firestore. A
        // scenario cannot be trusted to surface this limit.
        expect(await repository.streamUsersFromIds(members).first, isEmpty);
      },
    );

    test('a malformed document fails the list read', () async {
      // ARRANGE: `sharedWithGroups` is a string, so `Wishlist.fromMap` throws
      // while projecting the snapshot.
      final firestore = await seededStore(<String, Map<String, dynamic>>{
        'wishlists/broken': <String, dynamic>{
          'name': 'Broken',
          'ownerId': viewerUid,
          'sharedWithGroups': 'not-a-list',
        },
      });
      final repository = WishlistRepository(firestore: firestore);

      // ACT & ASSERT: the list renderer shows its error state instead of an
      // empty list, which is what makes a bad fixture visible.
      await expectLater(
        repository.streamWhere('ownerId', isEqualTo: viewerUid),
        emitsError(isA<TypeError>()),
      );
    });
  });
}
