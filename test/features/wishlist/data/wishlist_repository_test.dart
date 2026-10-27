import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/app_log.dart';
import 'package:wishtogether/core/logging/log_sink.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

import '../../../core/logging/recording_sink.dart';

/// Fails before any Firestore call, to pin the item page read's guard.
class ThrowingFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    throw StateError('read failed');
  }
}

class MockWriteBatch extends Mock implements WriteBatch {}

/// Serves a batch whose commit fails, after the page read succeeds.
class CommitFailingFirestore extends FakeFirebaseFirestore {
  CommitFailingFirestore(this.batchToReturn);

  final WriteBatch batchToReturn;

  @override
  WriteBatch batch() => batchToReturn;
}

void main() {
  group('WishlistRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late WishlistRepository wishlistRepository;

    const String testWishlistId = 'test_wishlist';
    final String itemsCollectionPath =
        '${Wishlist.collectionName}/$testWishlistId/${Item.collectionName}';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      wishlistRepository = WishlistRepository(firestore: fakeFirestore);
    });

    test(
      'items method should return a correctly configured ItemRepository',
      () {
        // ACT: Get the ItemRepository for a specific wishlist.
        final itemRepository = wishlistRepository.items(testWishlistId);

        // ASSERT: Verify that the repository is pointing to the correct collection path.
        expect(itemRepository.collectionPath, equals(itemsCollectionPath));
      },
    );

    test(
      'addItemToWishlist should add an item to the correct sub-collection',
      () async {
        // ARRANGE: Create a new item to be added.
        final itemToAdd = Item(name: 'New Test Item');

        // ACT: Add the item to the wishlist.
        await wishlistRepository.addItemToWishlist(testWishlistId, itemToAdd);

        // ASSERT: Check that the item now exists in the sub-collection.
        final snapshot = await fakeFirestore
            .collection(itemsCollectionPath)
            .get();
        expect(
          snapshot.docs.length,
          1,
          reason: 'There should be one item in the sub-collection.',
        );
        expect(snapshot.docs.first.data()['name'], equals(itemToAdd.name));
      },
    );

    test(
      'updateItemInWishlist should update an item in the sub-collection',
      () async {
        // ARRANGE: Add an initial item to the sub-collection.
        final initialItem = Item(name: 'Initial Item Name');
        final docRef = await fakeFirestore
            .collection(itemsCollectionPath)
            .add(
              wishlistRepository.items(testWishlistId).toFirestore(initialItem),
            );

        // Create an updated version of the item with a new name.
        final updatedItem = Item(id: docRef.id, name: 'Updated Item Name');

        // ACT: Update the item in the wishlist.
        await wishlistRepository.updateItemInWishlist(
          testWishlistId,
          updatedItem,
        );

        // ASSERT: Verify that the item's name has been updated in Firestore.
        final doc = await fakeFirestore
            .collection(itemsCollectionPath)
            .doc(docRef.id)
            .get();
        expect(doc.data()?['name'], equals(updatedItem.name));
      },
    );

    test(
      'updateItemInWishlist should throw an error if the item has no ID',
      () {
        // ARRANGE: Create an item without an ID.
        final itemWithoutId = Item(name: 'Item without ID');

        // ACT & ASSERT: Expect an ArgumentError to be thrown.
        expect(
          () => wishlistRepository.updateItemInWishlist(
            testWishlistId,
            itemWithoutId,
          ),
          throwsArgumentError,
          reason: 'An ArgumentError should be thrown when updating an item without an ID.',
        );
      },
    );

    test('removeWishlistFromGroup should remove the group ID from the sharedWithGroups list', () async {
      // ARRANGE: Create a wishlist that is shared with two groups.
      const wishlistId = 'wishlist-to-remove-from';
      const groupIdToRemove = 'group-to-remove';
      const otherGroupId = 'other-group';
      final initialWishlist = Wishlist(
        id: wishlistId,
        ownerId: 'owner-id',
        name: 'My Wishlist',
        sharedWithGroups: [groupIdToRemove, otherGroupId],
      );

      // Add the wishlist to the fake Firestore instance.
      await fakeFirestore
          .collection(Wishlist.collectionName)
          .doc(wishlistId)
          .set(wishlistRepository.toFirestore(initialWishlist));

      // ACT: Call the method to remove the wishlist from the specified group.
      await wishlistRepository.removeWishlistFromGroup(
        wishlistId,
        groupIdToRemove,
      );

      // ASSERT: Verify that the group ID has been removed from the document.
      final doc = await fakeFirestore
          .collection(Wishlist.collectionName)
          .doc(wishlistId)
          .get();
      final updatedWishlist = wishlistRepository.fromFirestore(doc);

      expect(
        updatedWishlist.sharedWithGroups,
        isNot(contains(groupIdToRemove)),
      );
      expect(updatedWishlist.sharedWithGroups, contains(otherGroupId));
      expect(updatedWishlist.sharedWithGroups.length, 1);
    });

    test(
      'listOwnedBy returns only the wishlists whose owner matches',
      () async {
        // ARRANGE: two wishlists for the owner, one for somebody else.
        const ownerId = 'owner';
        const otherOwnerId = 'other-owner';
        final wishlists = fakeFirestore.collection(Wishlist.collectionName);
        await wishlists
            .doc('mine-1')
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: 'mine-1', name: 'Mine 1', ownerId: ownerId),
              ),
            );
        await wishlists
            .doc('mine-2')
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: 'mine-2', name: 'Mine 2', ownerId: ownerId),
              ),
            );
        await wishlists
            .doc('theirs')
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: 'theirs', name: 'Theirs', ownerId: otherOwnerId),
              ),
            );

        // ACT
        final owned = await wishlistRepository.listOwnedBy(ownerId);

        // ASSERT
        expect(
          owned.map((wishlist) => wishlist.id),
          unorderedEquals(['mine-1', 'mine-2']),
        );
      },
    );

    test('deleteWithItems removes the wishlist and every item in its sub-collection', () async {
      // ARRANGE: a wishlist with two items.
      final wishlists = fakeFirestore.collection(Wishlist.collectionName);
      await wishlists
          .doc(testWishlistId)
          .set(
            wishlistRepository.toFirestore(
              Wishlist(id: testWishlistId, name: 'Doomed', ownerId: 'owner'),
            ),
          );
      final items = fakeFirestore.collection(itemsCollectionPath);
      await items.doc('item-1').set({'name': 'Item 1'});
      await items.doc('item-2').set({'name': 'Item 2'});

      // ACT
      await wishlistRepository.deleteWithItems(testWishlistId);

      // ASSERT
      expect((await wishlists.doc(testWishlistId).get()).exists, isFalse);
      expect((await items.get()).docs, isEmpty);
    });

    test(
      'deleteWithItems removes every item when they span more than one batch',
      () async {
        // ARRANGE: more items than a single Firestore batch can delete (500).
        const itemCount = 501;
        final wishlists = fakeFirestore.collection(Wishlist.collectionName);
        await wishlists
            .doc(testWishlistId)
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: testWishlistId, name: 'Big', ownerId: 'owner'),
              ),
            );
        final items = fakeFirestore.collection(itemsCollectionPath);
        // Seeded in two batches because Firestore caps a batch at 500 writes.
        for (var start = 0; start < itemCount; start += 500) {
          final batch = fakeFirestore.batch();
          for (var i = start; i < itemCount && i < start + 500; i++) {
            batch.set(items.doc('item-$i'), {'name': 'Item $i'});
          }
          await batch.commit();
        }

        // ACT
        await wishlistRepository.deleteWithItems(testWishlistId);

        // ASSERT
        expect((await items.get()).docs, isEmpty);
        expect((await wishlists.doc(testWishlistId).get()).exists, isFalse);
      },
    );

    test(
      'deleteWithItems leaves another wishlist and its items untouched',
      () async {
        // ARRANGE: a doomed wishlist and a survivor, each with an item.
        const survivorId = 'survivor';
        final wishlists = fakeFirestore.collection(Wishlist.collectionName);
        await wishlists
            .doc(testWishlistId)
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: testWishlistId, name: 'Doomed', ownerId: 'owner'),
              ),
            );
        await wishlists
            .doc(survivorId)
            .set(
              wishlistRepository.toFirestore(
                Wishlist(id: survivorId, name: 'Survivor', ownerId: 'owner'),
              ),
            );
        await fakeFirestore
            .collection(itemsCollectionPath)
            .doc('doomed-item')
            .set({'name': 'Doomed item'});
        final survivorItems = fakeFirestore.collection(
          '${Wishlist.collectionName}/$survivorId/${Item.collectionName}',
        );
        await survivorItems.doc('survivor-item').set({'name': 'Survivor item'});

        // ACT
        await wishlistRepository.deleteWithItems(testWishlistId);

        // ASSERT
        expect((await wishlists.doc(survivorId).get()).exists, isTrue);
        expect((await survivorItems.get()).docs.length, 1);
      },
    );
  });

  group('WishlistRepository diagnostics', () {
    const String wishlistId = 'doomed';
    final String itemsPath =
        '${Wishlist.collectionName}/$wishlistId/${Item.collectionName}';
    late RecordingSink sink;

    setUp(() {
      sink = RecordingSink();
      getIt.registerSingleton<AppLog>(
        AppLog(session: testSession, sinks: <LogSink>[sink]),
      );
      addTearDown(getIt.reset);
    });

    test('reports a failed item page read', () async {
      // Arrange
      final repository = WishlistRepository(firestore: ThrowingFirestore());

      // Act & Assert
      await expectLater(
        repository.deleteWithItems(wishlistId),
        throwsA(isA<StateError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.list);
      expect(event.collection, Item.collectionName);
    });

    test('reports a failed item batch commit', () async {
      // Arrange: one item, so the cascade reaches the delete batch.
      final batch = MockWriteBatch();
      final firestore = CommitFailingFirestore(batch);
      await firestore.collection(itemsPath).doc('item-1').set(<String, dynamic>{
        'name': 'Doomed item',
      });
      when(() => batch.commit()).thenThrow(StateError('commit failed'));
      final repository = WishlistRepository(firestore: firestore);

      // Act & Assert
      await expectLater(
        repository.deleteWithItems(wishlistId),
        throwsA(isA<StateError>()),
      );

      final event = sink.eventsOf<FirestoreErrorEvent>().single;
      expect(event.op, FirestoreOp.write);
      expect(event.collection, Item.collectionName);
    });
  });
}
