import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  group('ItemRepository', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ItemRepository itemRepository;

    const String testWishlistId = 'test_wishlist';
    final String itemsCollectionPath =
        '${Wishlist.collectionName}/$testWishlistId/${Item.collectionName}';

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      itemRepository = ItemRepository(testWishlistId, firestore: fakeFirestore);
    });

    test('toFirestore should convert claimedAt from DateTime to Timestamp', () {
      // ARRANGE: Create an item with a claimedAt date as a DateTime object.
      final item = Item(
        id: 'test_item',
        name: 'Test Item',
        claimedAt: DateTime.now(),
      );

      // ACT: Convert the item to a Firestore map.
      final firestoreMap = itemRepository.toFirestore(item);

      // ASSERT: Verify that the claimedAt field is a Firestore Timestamp.
      expect(
        firestoreMap['claimedAt'],
        isA<Timestamp>(),
        reason:
            'The claimedAt field should be converted to a Firestore Timestamp.',
      );
    });

    test(
      'fromFirestore should convert claimedAt from Timestamp to DateTime',
      () async {
        // ARRANGE: Create a Firestore document with a Timestamp for the claimedAt field.
        final docRef = await fakeFirestore.collection(itemsCollectionPath).add({
          'name': 'Test Item From Firestore',
          'claimedAt': Timestamp.now(),
        });

        // ACT: Retrieve the document and use fromFirestore to parse it.
        final doc = await docRef.get();
        final item = itemRepository.fromFirestore(doc);

        // ASSERT: Verify that the claimedAt field in the Item object is a DateTime.
        expect(
          item.claimedAt,
          isA<DateTime>(),
          reason:
              'The claimedAt field should be parsed into a DateTime object.',
        );
      },
    );

    test(
      'toFirestore and fromFirestore should correctly handle a null claimedAt',
      () async {
        // ARRANGE: Create an item with a null claimedAt.
        final itemWithNullClaimedAt = Item(
          id: 'test_item_null',
          name: 'Test Item',
          claimedAt: null,
        );

        // ACT (toFirestore): Convert the item to a Firestore map.
        final firestoreMap = itemRepository.toFirestore(itemWithNullClaimedAt);

        // ASSERT (toFirestore): Check that the claimedAt field is null in the map.
        expect(
          firestoreMap['claimedAt'],
          isNull,
          reason:
              'A null claimedAt in the model should result in a null value in the Firestore map.',
        );

        // ARRANGE (fromFirestore): Add the map to the fake Firestore instance.
        final docRef = await fakeFirestore
            .collection(itemsCollectionPath)
            .add(firestoreMap);

        // ACT (fromFirestore): Retrieve the document and parse it.
        final doc = await docRef.get();
        final retrievedItem = itemRepository.fromFirestore(doc);

        // ASSERT (fromFirestore): Check that the claimedAt field is still null in the final Item object.
        expect(
          retrievedItem.claimedAt,
          isNull,
          reason:
              'A null claimedAt in Firestore should result in a null value in the Item model.',
        );
      },
    );

    test('unclaim should set claimedBy and claimedAt to null', () async {
      // ARRANGE: Create a claimed item and add it to the database with a specific ID.
      final claimedItem = Item(
        id: 'claimed_item',
        name: 'Claimed Item',
        claimedBy: 'user123',
        claimedAt: DateTime.now(),
      );
      // Use the fake firestore instance directly to set up the test data.
      await fakeFirestore
          .collection(itemsCollectionPath)
          .doc(claimedItem.id)
          .set(itemRepository.toFirestore(claimedItem));

      // ACT: Call the unclaim method.
      await itemRepository.unclaim(claimedItem.id!);

      // ASSERT: Retrieve the item and verify it's unclaimed.
      final updatedItemDoc = await fakeFirestore
          .collection(itemsCollectionPath)
          .doc(claimedItem.id)
          .get();
      final updatedItem = itemRepository.fromFirestore(updatedItemDoc);

      expect(
        updatedItem.claimedBy,
        isNull,
        reason: 'claimedBy should be null after unclaiming.',
      );
      expect(
        updatedItem.claimedAt,
        isNull,
        reason: 'claimedAt should be null after unclaiming.',
      );
      expect(
        updatedItem.name,
        claimedItem.name,
        reason: 'Other fields should not be changed.',
      );
    });
  });
}
