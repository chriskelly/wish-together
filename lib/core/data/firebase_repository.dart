import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show protected;
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/core/logging/redaction.dart';

/// The allowlisted collection name behind a collection path.
///
/// A nested path (`wishlists/<id>/items`) carries a document id, which is a
/// capability under `firestore.rules`; only the last segment may be reported,
/// and `redactCollection` masks it if it is not allowlisted.
String _collectionNameFromPath(String path) {
  final segments = path.split('/').where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? '' : segments.last;
}

abstract class FirebaseRepository<T> {
  late final FirebaseFirestore instance;
  final String collectionPath;

  /// The collection *name* reported at the diagnostics seam.
  ///
  /// Never pass [collectionPath] to an event: the item repository's path is
  /// `wishlists/<id>/items`, which would leak an id.
  final String collectionName;

  FirebaseRepository(this.collectionPath, {FirebaseFirestore? firestore})
    : collectionName = _collectionNameFromPath(collectionPath) {
    instance = firestore ?? FirebaseFirestore.instance;
  }

  /// Reports one failure at the seam, without changing the outcome.
  void _report(FirestoreOp op, Object error) {
    appLogOrNull?.event(
      FirestoreErrorEvent(
        op: op,
        collection: collectionName,
        code: readErrorCode(error),
      ),
    );
  }

  /// Runs one Firestore call, reports a failure, and rethrows it unchanged.
  ///
  /// Protected rather than library-private so an override that cannot use a
  /// base method (a different query shape, a batch commit) still reports at
  /// this one seam instead of bypassing it. Report through the repository that
  /// owns the collection: a subclass reading another repository's sub-collection
  /// passes that repository as the receiver, because [collectionName] is
  /// per instance.
  @protected
  Future<R> reportingFuture<R>(
    FirestoreOp op,
    Future<R> Function() body,
  ) async {
    try {
      return await body();
    } catch (error) {
      _report(op, error);
      rethrow;
    }
  }

  /// Reports a stream error and forwards it to the caller.
  ///
  /// `Stream.handleError` cannot be used here: a callback that returns normally
  /// makes the stream *forget* the error, and the list renderers —
  /// `StreamListBuilder` and `ListContentBuilder` — show their error UI from it.
  /// This transformer reports and re-emits.
  @protected
  Stream<R> reportingStream<R>(Stream<R> source, FirestoreOp op) {
    return source.transform(
      StreamTransformer<R, R>.fromHandlers(
        handleError: (Object error, StackTrace stackTrace, EventSink<R> sink) {
          _report(op, error);
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  Stream<List<T>> streamAll() {
    return reportingStream(
      instance
          .collection(collectionPath)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map((doc) => fromFirestore(doc)).toList(),
          ),
      FirestoreOp.list,
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
    return reportingStream(
      _query(
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
      ),
      FirestoreOp.list,
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
    return reportingFuture(FirestoreOp.list, () async {
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
    });
  }

  Stream<T> streamOne(String id) {
    return reportingStream(
      instance
          .collection(collectionPath)
          .doc(id)
          .snapshots()
          .map((doc) => fromFirestore(doc)),
      FirestoreOp.get,
    );
  }

  Future<T> get(String id) => reportingFuture(FirestoreOp.get, () async {
    final doc = await instance.collection(collectionPath).doc(id).get();
    return fromFirestore(doc);
  });

  Future<DocumentReference> add(T data) => reportingFuture(
    FirestoreOp.write,
    () => instance.collection(collectionPath).add(toFirestore(data)),
  );

  Future<void> update(String id, T data) => reportingFuture(
    FirestoreOp.write,
    () => instance.collection(collectionPath).doc(id).update(toFirestore(data)),
  );

  Future<void> updateData(String id, Map<String, dynamic> data) =>
      reportingFuture(
        FirestoreOp.write,
        () => instance.collection(collectionPath).doc(id).update(data),
      );

  Future<void> delete(String id) => reportingFuture(
    FirestoreOp.write,
    () => instance.collection(collectionPath).doc(id).delete(),
  );

  T fromFirestore(DocumentSnapshot doc);
  Map<String, dynamic> toFirestore(T data);
}
