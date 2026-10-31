import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class ItemRepository extends FirebaseRepository<Item> {
  ItemRepository(String wishlistId, {super.firestore})
    : super('${Wishlist.collectionName}/$wishlistId/${Item.collectionName}');

  @override
  Item fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    // Handle Firestore Timestamps, which can be returned by the database.
    // The testing library, in particular, may return these.
    final claimedAtTimestamp = data['claimedAt'] as Timestamp?;
    if (claimedAtTimestamp != null) {
      data['claimedAt'] = claimedAtTimestamp.toDate().toIso8601String();
    }
    return Item.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(Item item) {
    final map = item.toMap();
    // The `claimedAt` field is stored as an ISO 8601 string in the Item model.
    // It needs to be converted to a Firestore Timestamp before being saved.
    if (map['claimedAt'] != null) {
      map['claimedAt'] = Timestamp.fromDate(DateTime.parse(map['claimedAt']));
    }
    return map;
  }

  Future<void> unclaim(String itemId) {
    return updateData(itemId, {'claimedBy': null, 'claimedAt': null});
  }

  /// Claims [itemId] for [claimedBy], touching no other field.
  ///
  /// A reader's copy of the item can be stale, or can lack an optional field
  /// that the stored document already has, and the rules only allow a reader to
  /// change the claim pair. Writing both in one update keeps the write valid
  /// whatever else the owner changed meanwhile.
  Future<void> claim(String itemId, {required String claimedBy}) {
    return updateData(itemId, {
      'claimedBy': claimedBy,
      'claimedAt': Timestamp.now(),
    });
  }
}
