/// The §4.3 allowlist, enforced inside the façade.
///
/// `AppLog` serialises only these keys, and S2's `beforeSend`/`beforeBreadcrumb`
/// reuse this set instead of restating it, so one list governs both ends.
const Set<String> logRecordKeys = <String>{
  'event',
  'session_id',
  'support_code',
  'user_ref',
  'build',
  'platform',
  'route',
  'outcome',
  'op',
  'collection',
  'error_code',
  'result',
  'min',
  'running',
  'reason',
  'phase',
  'provider',
  'error_type',
  'clean',
};

/// Collection names the app may report.
///
/// A collection *path* can carry a document id (`wishlists/<id>/items`), and
/// document ids are capabilities under `firestore.rules`, so anything outside
/// this set is reported as [unknownCollection].
const Set<String> logCollectionNames = <String>{
  'wishlists',
  'items',
  'groups',
  'users',
};

/// Wire value for a collection that is not allowlisted.
const String unknownCollection = 'other';

/// Path segments that are route literals rather than ids.
///
/// Keep in sync with the page `route` constants; a segment that is missing here
/// is masked as `:id`, which is safe but less useful.
const Set<String> logRouteLiterals = <String>{
  'login',
  'verify',
  'profile',
  'join',
  'create-wishlist',
  'create-group',
  'wishlist',
  'group',
  'add-item',
  'item',
  'edit',
};

/// Collapses a location into a route pattern: ids become `:id`, and the query
/// and fragment are dropped.
///
/// A resolved location such as `/wishlist/abc123?tab=1` therefore reports
/// `/wishlist/:id`, and `/join?group=abc123` reports `/join`. Every segment is
/// kept only when it is in [logRouteLiterals]; anything else — including an
/// unlisted area — is masked (`/settings/dark` reports `/:id/:id`, and a bare
/// id path reports `/:id`). The literal set is the guard, not the caller's
/// promise.
String redactRoute(String route) {
  final path = route.split('?').first.split('#').first;
  final segments = path
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return '/';
  }
  final pattern = segments.map(
    (segment) => logRouteLiterals.contains(segment) ? segment : ':id',
  );
  return '/${pattern.join('/')}';
}

/// Keeps an allowlisted collection name and masks everything else.
String redactCollection(String collection) =>
    logCollectionNames.contains(collection) ? collection : unknownCollection;

final RegExp _codeShape = RegExp(r'^[A-Za-z0-9._-]{1,64}$');
final RegExp _codeSeparator = RegExp(r'[-_.]');
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

/// A bare token at or above this length is uid/document-id shaped.
///
/// Firebase uids are 28 characters and Firestore auto-ids are 20; both are
/// alphanumeric, so a separator-free token that long cannot be a real code.
const int _maxBareCodeLength = 16;

/// Keeps a code only when it is shaped like one.
///
/// Codes are the structured identifiers Firebase and the platforms already
/// return (`permission-denied`, `ERROR_OPERATION_NOT_SUPPORTED`). The gate is a
/// shape check, not a value allowlist, and it is defence in depth behind the
/// typed events, so it also drops values shaped like the two secrets §S3 names:
///
/// - a bare all-digit value is shaped like a phone number;
/// - a bare alphanumeric token of 16+ characters is shaped like a Firebase uid
///   or a Firestore document id.
///
/// A message, an email or a display name cannot pass the character set, so a
/// careless `code:` cannot become the leak channel that `$error` used to be.
String? redactCode(String? code) {
  if (code == null ||
      !_codeShape.hasMatch(code) ||
      _digitsOnly.hasMatch(code)) {
    return null;
  }
  final isBareToken = !_codeSeparator.hasMatch(code);
  if (isBareToken && code.length >= _maxBareCodeLength) {
    return null;
  }
  return code;
}
