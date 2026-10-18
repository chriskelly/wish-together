import 'package:cloud_firestore/cloud_firestore.dart';

abstract class FirebaseRepository<T> {
  late final FirebaseFirestore instance;
  final String collectionPath;

  FirebaseRepository(this.collectionPath, {FirebaseFirestore? firestore}) {
    instance = firestore ?? FirebaseFirestore.instance;
  }

  Stream<List<T>> streamAll() {
    return instance
        .collection(collectionPath)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) => fromFirestore(doc)).toList(),
        );
  }

  /// Builds the query behind [streamWhere] and [listWhere].
  ///
  /// Single source for the query shape and the model projection, so a one-shot
  /// caller cannot silently diverge from a streaming one.
  Query<Map<String, dynamic>> _query(
    String field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? arrayContainsAny,
    List<Object?>? whereIn,
    List<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return instance
        .collection(collectionPath)
        .where(
          field,
          isEqualTo: isEqualTo,
          isNotEqualTo: isNotEqualTo,
          isLessThan: isLessThan,
          isLessThanOrEqualTo: isLessThanOrEqualTo,
          isGreaterThan: isGreaterThan,
          isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
          arrayContains: arrayContains,
          arrayContainsAny: arrayContainsAny,
          whereIn: whereIn,
          whereNotIn: whereNotIn,
          isNull: isNull,
        );
  }

  Stream<List<T>> streamWhere(
    String field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? arrayContainsAny,
    List<Object?>? whereIn,
    List<Object?>? whereNotIn,
    bool? isNull,
  }) {
    return _query(
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    ).snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => fromFirestore(doc)).toList(),
    );
  }

  /// The one-shot counterpart to [streamWhere], for callers that need the
  /// current matches and cannot wait on a stream.
  Future<List<T>> listWhere(
    String field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? arrayContainsAny,
    List<Object?>? whereIn,
    List<Object?>? whereNotIn,
    bool? isNull,
  }) async {
    final snapshot = await _query(
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      arrayContains: arrayContains,
      arrayContainsAny: arrayContainsAny,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
      isNull: isNull,
    ).get();
    return snapshot.docs.map((doc) => fromFirestore(doc)).toList();
  }

  Stream<T> streamOne(String id) {
    return instance
        .collection(collectionPath)
        .doc(id)
        .snapshots()
        .map((doc) => fromFirestore(doc));
  }

  Future<T> get(String id) async {
    final doc = await instance.collection(collectionPath).doc(id).get();
    return fromFirestore(doc);
  }

  Future<DocumentReference> add(T data) {
    return instance.collection(collectionPath).add(toFirestore(data));
  }

  Future<void> update(String id, T data) {
    return instance
        .collection(collectionPath)
        .doc(id)
        .update(toFirestore(data));
  }

  Future<void> updateData(String id, Map<String, dynamic> data) {
    return instance.collection(collectionPath).doc(id).update(data);
  }

  Future<void> delete(String id) {
    return instance.collection(collectionPath).doc(id).delete();
  }

  T fromFirestore(DocumentSnapshot doc);
  Map<String, dynamic> toFirestore(T data);
}
