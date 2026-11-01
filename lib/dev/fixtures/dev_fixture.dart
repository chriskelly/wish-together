import 'package:cloud_firestore/cloud_firestore.dart';

/// One dev session's identity and data.
class DevFixture {
  const DevFixture({
    required this.id,
    required this.viewerUid,
    required this.documents,
  });

  /// The scenario id: the registry key, and what the dev banner names.
  final String id;

  /// The uid the dev session reports as signed in.
  final String viewerUid;

  /// Firestore documents, keyed by full document path.
  final Map<String, Map<String, dynamic>> documents;
}

/// Writes every document in [fixture] into [firestore].
///
/// Each key is a full document path, so a document id is exactly the id a URL
/// names, and a nested item path (`wishlists/<id>/items/<id>`) needs no special
/// case. A malformed path fails here, at composition time, rather than as an
/// empty screen.
Future<void> seedDevFirestore(
  FirebaseFirestore firestore,
  DevFixture fixture,
) async {
  for (final entry in fixture.documents.entries) {
    await firestore.doc(entry.key).set(entry.value);
  }
}
