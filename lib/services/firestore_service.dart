import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/wishlist.dart';
import '../models/group.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  Stream<List<Wishlist>> getUserWishlists(String userId) {
    return _db
        .collection('wishlists')
        .where('ownerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Wishlist.fromFirestore(doc))
            .toList());
  }

  Future<Wishlist?> getWishlist(String wishlistId) async {
    final doc = await _db.collection('wishlists').doc(wishlistId).get();
    if (doc.exists) {
      return Wishlist.fromFirestore(doc);
    }
    return null;
  }

  Future<DocumentReference> addWishlist(Wishlist wishlist) {
    return _db.collection('wishlists').add(wishlist.toFirestore());
  }

  Future<void> updateWishlist(Wishlist wishlist) {
    return _db
        .collection('wishlists')
        .doc(wishlist.id)
        .update(wishlist.toFirestore());
  }

  Future<void> deleteWishlist(String wishlistId) async {
    final wishlistRef = _db.collection('wishlists').doc(wishlistId);

    // Get all items in the wishlist to delete them in a batch
    final itemsSnapshot = await wishlistRef.collection('items').get();

    if (itemsSnapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in itemsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // After deleting all items, delete the wishlist itself
    await wishlistRef.delete();
  }

  Stream<List<Group>> getUserGroups(String userId) {
    return _db
        .collection('groups')
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Group.fromFirestore(doc)).toList());
  }

  Stream<List<Item>> getWishlistItems(String wishlistId) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Item.fromFirestore(doc)).toList());
  }

  Future<DocumentReference> addItemToWishlist(String wishlistId, Item item) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .add(item.toFirestore());
  }

  Future<void> updateItemInWishlist(String wishlistId, Item item) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .doc(item.id)
        .update(item.toFirestore());
  }

  Future<void> deleteItemFromWishlist(String wishlistId, String itemId) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .doc(itemId)
        .delete();
  }
}
