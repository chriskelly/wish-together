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

  Future<DocumentReference> addWishlist(Wishlist wishlist) {
    return _db.collection('wishlists').add(wishlist.toFirestore());
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
}
