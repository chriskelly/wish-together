import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// The Firestore database id used when no build-time target is set.
const String defaultFirestoreDatabaseId = '(default)';

/// Build-time Firestore database selector.
///
/// Empty (the default) means production. The staging deploy sets
/// `--dart-define=WT_FIRESTORE_DATABASE=<id>`, reading the id from
/// `firebase.staging.json` so the build and the rules deploy cannot diverge.
const String firestoreDatabaseIdOverride = String.fromEnvironment(
  'WT_FIRESTORE_DATABASE',
);

/// A distinctive marker emitted into the compiled bundle so the staging deploy
/// can prove the build flag reached the artifact. Flutter's own code contains
/// the word "staging", so the database id alone is not a usable marker.
const String firestoreTargetStampPrefix = 'wishtogether-firestore-target=';
const String firestoreTargetStamp =
    '$firestoreTargetStampPrefix$firestoreDatabaseIdOverride';

/// A Firestore database id must be a plain lowercase id (the same shape the
/// staging deploy guard accepts), never a resource path.
final RegExp _namedDatabaseId = RegExp(r'^[a-z][a-z0-9-]{3,62}$');

/// Resolves the Firestore database id for the current build.
///
/// Empty or whitespace means the default database. A malformed id throws
/// instead of silently falling back to production.
String resolveFirestoreDatabaseId(String override) {
  final id = override.trim();
  if (id.isEmpty) {
    return defaultFirestoreDatabaseId;
  }
  if (id != defaultFirestoreDatabaseId && !_namedDatabaseId.hasMatch(id)) {
    throw ArgumentError.value(
      override,
      'WT_FIRESTORE_DATABASE',
      'Invalid Firestore database id ($firestoreTargetStamp)',
    );
  }
  return id;
}

/// Chooses the Firestore instance for a given build target.
///
/// Split from [createFirestoreInstance] so the production-vs-named branch can
/// be tested without initializing Firebase.
FirebaseFirestore selectFirestoreInstance({
  required String override,
  required FirebaseFirestore? defaultInstance,
  required FirebaseFirestore Function(String databaseId) namedInstance,
}) {
  final databaseId = resolveFirestoreDatabaseId(override);
  if (databaseId == defaultFirestoreDatabaseId) {
    // Resolved lazily: a staging build must not need the default instance.
    return defaultInstance ?? FirebaseFirestore.instance;
  }
  return namedInstance(databaseId);
}

/// Creates the single [FirebaseFirestore] instance for this app.
///
/// Repositories receive this through the service locator, so every read and
/// write follows the build's target database.
FirebaseFirestore createFirestoreInstance({
  String override = firestoreDatabaseIdOverride,
  FirebaseFirestore? defaultInstance,
  FirebaseFirestore Function(String databaseId)? namedInstance,
}) {
  return selectFirestoreInstance(
    override: override,
    defaultInstance: defaultInstance,
    namedInstance:
        namedInstance ??
        (databaseId) => FirebaseFirestore.instanceFor(
          app: Firebase.app(),
          databaseId: databaseId,
        ),
  );
}
