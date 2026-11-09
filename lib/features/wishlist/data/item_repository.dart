import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:wishtogether/core/data/firebase_repository.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/features/wishlist/domain/claim_limit_reached_exception.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class ItemRepository extends FirebaseRepository<Item> {
  ItemRepository(String wishlistId, {super.firestore})
    : super('${Wishlist.collectionName}/$wishlistId/${Item.collectionName}');

  @override
  Item fromFirestore(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
    // Firestore returns claim times as Timestamps. Convert each one here, at
    // the boundary; the model keeps DateTimes. A value that is not a Timestamp
    // is passed through so `Item.fromMap` can drop it without failing the
    // whole read.
    final rawClaims = data['claims'];
    if (rawClaims is Map) {
      data['claims'] = <String, dynamic>{
        for (final entry in rawClaims.entries)
          if (entry.key is String)
            entry.key as String: entry.value is Timestamp
                ? (entry.value as Timestamp).toDate().toUtc().toIso8601String()
                : entry.value,
      };
    }
    return Item.fromMap(data, doc.id);
  }

  @override
  Map<String, dynamic> toFirestore(Item item) {
    final map = item.toMap();
    // `Item.toMap` carries claim times as ISO-8601 strings; Firestore stores
    // them as Timestamps.
    final claims = map['claims'];
    if (claims is Map) {
      map['claims'] = <String, dynamic>{
        for (final entry in claims.entries)
          entry.key as String: Timestamp.fromDate(
            DateTime.parse(entry.value as String),
          ),
      };
    }
    return map;
  }

  /// Removes only [claimedBy]'s claim, leaving other claimants untouched.
  Future<void> unclaim(String itemId, {required String claimedBy}) {
    return updateData(itemId, {'claims.$claimedBy': FieldValue.delete()});
  }

  /// Claims [itemId] for [claimedBy], touching no other field.
  ///
  /// A transaction keeps the cap honest: two readers racing for the last slot
  /// cannot both commit, and the same uid claiming twice is an idempotent
  /// success that keeps its original timestamp. Unlimited items skip the cap
  /// check, not the transaction. A missing item is reported as `not-found`, and
  /// a full item as [ClaimLimitReachedException]; neither is a Firestore error.
  Future<void> claim(String itemId, {required String claimedBy}) async {
    final doc = instance.collection(collectionPath).doc(itemId);
    final full = await reportingFuture(
      FirestoreOp.claim,
      () => instance.runTransaction<bool>((transaction) async {
        final snapshot = await transaction.get(doc);
        if (!snapshot.exists) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
        }
        final current = fromFirestore(snapshot);
        if (current.isClaimedBy(claimedBy)) {
          return false;
        }
        if (!current.hasClaimRoom) {
          return true;
        }
        transaction.update(doc, {'claims.$claimedBy': Timestamp.now()});
        return false;
      }),
    );
    if (full) {
      throw const ClaimLimitReachedException();
    }
  }

  /// Writes the owner-editable fields and never the claims map.
  Future<void> updateContent(
    String itemId, {
    required String name,
    String? description,
    String? url,
    required int claimLimit,
  }) {
    return updateData(itemId, {
      'name': name,
      'description': description,
      'url': url,
      'claimLimit': claimLimit,
    });
  }
}
