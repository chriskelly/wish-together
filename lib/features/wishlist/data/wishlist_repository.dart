import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class WishlistRepository extends FirebaseRepository<Wishlist> {
  WishlistRepository({super.firestore}) : super(Wishlist.collectionName);

  @override
  Wishlist fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Wishlist.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(Wishlist wishlist) {
    return wishlist.toMap();
  }

  ItemRepository items(String wishlistId) {
    return ItemRepository(wishlistId, firestore: instance);
  }

  Future<void> addItemToWishlist(String wishlistId, Item item) {
    return items(wishlistId).add(item);
  }

  Future<void> updateItemInWishlist(String wishlistId, Item item) {
    // The item needs an ID to be updated correctly.
    if (item.id == null) {
      throw ArgumentError('Item must have an ID to be updated.');
    }
    return items(wishlistId).update(item.id!, item);
  }

  Future<void> removeWishlistFromGroup(
    String wishlistId,
    String groupId,
  ) async {
    final wishlist = await get(wishlistId);
    final updatedGroups = List<String>.from(wishlist.sharedWithGroups)
      ..remove(groupId);
    await update(
      wishlistId,
      wishlist.copyWith(sharedWithGroups: updatedGroups),
    );
  }

  /// The wishlists owned by [ownerId].
  Future<List<Wishlist>> listOwnedBy(String ownerId) async {
    final snapshot = await instance
        .collection(collectionPath)
        .where('ownerId', isEqualTo: ownerId)
        .get();
    return snapshot.docs.map((doc) => fromFirestore(doc)).toList();
  }

  /// Deletes the wishlist and every item in its `items` sub-collection.
  ///
  /// Firestore does not remove a sub-collection when its parent document is
  /// deleted, so the items go first (in batches), then the wishlist itself.
  Future<void> deleteWithItems(String wishlistId) async {
    final itemRepository = items(wishlistId);
    final snapshot = await itemRepository.instance
        .collection(itemRepository.collectionPath)
        .get();
    for (var start = 0; start < snapshot.docs.length; start += _batchLimit) {
      final batch = instance.batch();
      for (final doc in snapshot.docs.skip(start).take(_batchLimit)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await delete(wishlistId);
  }

  /// The largest number of deletes Firestore accepts in one batch.
  static const int _batchLimit = 500;
}
