import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/wishlist/data/item_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class WishlistRepository extends FirebaseRepository<Wishlist> {
  WishlistRepository({FirebaseFirestore? firestore})
    : super(Wishlist.collectionName, firestore: firestore);

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
}
