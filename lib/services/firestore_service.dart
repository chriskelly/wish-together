import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import '../models/user.dart';
import '../models/wishlist.dart';
import '../models/group.dart';
import '../models/item.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // User methods
  Future<AppUser?> getUser(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();
    if (doc.exists) {
      return AppUser.fromFirestore(doc);
    }
    return null;
  }

  Future<void> createUser(auth.User user, String displayName) async {
    final appUser = AppUser(
      id: user.uid,
      displayName: displayName,
      phoneNumber: user.phoneNumber,
    );

    final defaultWishlist = Wishlist(
      name: "$displayName's Wishlist",
      ownerId: user.uid,
    );

    final batch = _db.batch();

    // Create the user document
    batch.set(_db.collection('users').doc(user.uid), appUser.toJson());

    // Create the default wishlist
    final wishlistRef = _db.collection('wishlists').doc();
    batch.set(wishlistRef, defaultWishlist.toFirestore());

    await batch.commit();
  }

  Future<void> updateUser(String userId, {String? displayName}) async {
    final Map<String, dynamic> data = {};
    if (displayName != null) {
      data['displayName'] = displayName;
    }

    if (data.isNotEmpty) {
      return _db.collection('users').doc(userId).update(data);
    }
  }

  // Wishlist methods
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
    if (wishlist.id == null) {
      throw ArgumentError("Wishlist ID cannot be null when updating.");
    }
    return _db
        .collection('wishlists')
        .doc(wishlist.id)
        .update(wishlist.toFirestore());
  }

  Future<void> deleteWishlist(String wishlistId) async {
    final wishlistRef = _db.collection('wishlists').doc(wishlistId);

    final itemsSnapshot = await wishlistRef.collection('items').get();

    if (itemsSnapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in itemsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    await wishlistRef.delete();
  }

  // Group methods
  Stream<List<Group>> getUserGroups(String userId) {
    return _db
        .collection('groups')
        .where('members', arrayContains: userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Group.fromFirestore(doc)).toList());
  }

  Future<DocumentReference> createGroup(String name, String ownerId) {
    return _db.collection('groups').add({
      'name': name,
      'ownerId': ownerId,
      'members': [ownerId], // The owner is the first member.
    });
  }

   Future<void> updateGroup(Group group) {
    return _db
        .collection('groups')
        .doc(group.id)
        .update(group.toFirestore());
  }

  Future<void> deleteGroup(String groupId) {
    return _db.collection('groups').doc(groupId).delete();
  }


  Stream<Group?> getGroup(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .map((doc) => doc.exists ? Group.fromFirestore(doc) : null);
  }

  Future<Group?> getGroupFuture(String groupId) async {
    final doc = await _db.collection('groups').doc(groupId).get();
    return doc.exists ? Group.fromFirestore(doc) : null;
  }

  Future<void> joinGroup(String groupId, String userId) {
    return _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([userId])
    });
  }

  Future<void> leaveGroup(String groupId, String userId) {
    return _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([userId])
    });
  }

  Stream<List<AppUser>> getGroupMembers(String groupId) {
    return getGroup(groupId).asyncMap((group) async {
      if (group == null || group.members.isEmpty) {
        return [];
      }
      final usersSnapshot = await _db
          .collection('users')
          .where(FieldPath.documentId, whereIn: group.members)
          .get();
      return usersSnapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList();
    });
  }

    Future<void> shareWishlistWithGroup(String wishlistId, String groupId) {
    return _db.collection('wishlists').doc(wishlistId).update({
      'sharedWithGroups': FieldValue.arrayUnion([groupId])
    });
  }

  Future<void> unshareWishlistFromGroup(String wishlistId, String groupId) {
    return _db.collection('wishlists').doc(wishlistId).update({
      'sharedWithGroups': FieldValue.arrayRemove([groupId])
    });
  }

  Stream<List<Wishlist>> getSharedWishlistsForGroup(String groupId) {
    return _db
        .collection('wishlists')
        .where('sharedWithGroups', arrayContains: groupId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Wishlist.fromFirestore(doc))
            .toList());
  }


  // Item methods
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
    if (item.id == null) {
      throw ArgumentError("Item ID cannot be null when updating.");
    }
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

  Future<void> claimItem(String wishlistId, String itemId, String userId) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .doc(itemId)
        .update({
      'claimedBy': userId,
      'claimedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unclaimItem(String wishlistId, String itemId) {
    return _db
        .collection('wishlists')
        .doc(wishlistId)
        .collection('items')
        .doc(itemId)
        .update({
      'claimedBy': null,
      'claimedAt': null,
    });
  }
}
