import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/core/data/firebase_repository.dart';
import 'package:myapp/features/wishlist/domain/item.dart';

class ItemRepository extends FirebaseRepository<Item> {
  ItemRepository(String wishlistId) : super('wishlists/$wishlistId/items');

  @override
  Item fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final claimedAtTimestamp = data['claimedAt'] as Timestamp?;
    data['claimedAt'] = claimedAtTimestamp?.toDate();
    return Item.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(Item item) {
    return item.toMap();
  }
}
