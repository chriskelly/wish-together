import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

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
  });
}
