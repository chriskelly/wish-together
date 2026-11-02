import 'package:cloud_firestore/cloud_firestore.dart';

/// The fields of one item document, without the optional fields it does not set.
///
/// Fixtures are Firestore-shaped rather than domain models, so this returns the
/// stored form: optional fields are absent rather than null, which is how an
/// item document looks when the app never wrote those keys.
///
/// A claim carries both [claimedBy] and [claimedAt]. `ItemRepository` casts the
/// stored `claimedAt` to a `Timestamp`, so [claimedAt] has to be one; an
/// ISO-8601 string throws when the repository reads the item back.
Map<String, dynamic> devItemFields(
  String name, {
  String? description,
  String? url,
  String? claimedBy,
  Timestamp? claimedAt,
}) {
  assert(
    (claimedBy == null) == (claimedAt == null),
    'an item is claimed by a uid with a Timestamp, or unclaimed with neither',
  );
  return <String, dynamic>{
    'name': name,
    if (description != null) 'description': description,
    if (url != null) 'url': url,
    if (claimedBy != null) 'claimedBy': claimedBy,
    if (claimedAt != null) 'claimedAt': claimedAt,
  };
}

/// Builds [count] item documents under [wishlistId], keyed by full path.
///
/// [id] and [fields] receive a zero-based index, so the caller decides both the
/// ids it wants to read in a URL or a log and what each item carries. Use it
/// when the data is the point of the scenario (fifty rows, a long list) rather
/// than a handful of hand-written documents.
///
/// A map literal would silently keep the last of two identical paths, so the
/// ids are checked as the map is built: a generator that repeats an id is a
/// fixture with fewer items than it asked for, not a duplicate.
Map<String, Map<String, dynamic>> devItems({
  required String wishlistId,
  required int count,
  required String Function(int index) id,
  required Map<String, dynamic> Function(int index) fields,
}) {
  final documents = <String, Map<String, dynamic>>{};
  for (var index = 0; index < count; index++) {
    final itemId = id(index);
    final path = 'wishlists/$wishlistId/items/$itemId';
    assert(
      !documents.containsKey(path),
      'devItems generated the id "$itemId" twice under $wishlistId',
    );
    documents[path] = fields(index);
  }
  return documents;
}
