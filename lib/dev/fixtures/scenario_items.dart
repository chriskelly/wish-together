import 'package:cloud_firestore/cloud_firestore.dart';

/// The fields of one item document, without the optional fields it does not set.
///
/// Fixtures are Firestore-shaped rather than domain models, so this returns the
/// stored form: optional fields are absent rather than null, which is how an
/// item document looks when the app never wrote those keys.
///
/// A claim is one entry in the `claims` map: `{uid: Timestamp}`. The claim
/// limit is always written, because every item the app creates carries one;
/// `1` is the single-claim default and `0` means unlimited.
Map<String, dynamic> devItemFields(
  String name, {
  String? description,
  String? url,
  Map<String, Timestamp> claims = const {},
  int claimLimit = 1,
}) {
  return <String, dynamic>{
    'name': name,
    if (description != null) 'description': description,
    if (url != null) 'url': url,
    'claims': claims,
    'claimLimit': claimLimit,
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
