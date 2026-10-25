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
final RegExp _digitGroups = RegExp(r'^[0-9]+(?:[.-][0-9]+)+$');
final RegExp _dottedLowercaseName = RegExp(r'^[a-z.]+$');

/// A bare token at or above this length is uid/document-id shaped.
///
/// Firebase uids are 28 characters and Firestore auto-ids are 20; both are
/// alphanumeric, so a separator-free token that long cannot be a real code.
const int _maxBareCodeLength = 16;

/// A dotted value at or below this length can be name-shaped.
const int _maxDottedNameLength = 40;

/// Keeps a code only when it is shaped like one.
///
/// Codes are the structured identifiers Firebase and the platforms already
/// return (`permission-denied`, `ERROR_OPERATION_NOT_SUPPORTED`). This is a
/// **shape gate for a structured field, not a general PII classifier**, and it
/// is defence in depth behind the typed events. It drops values shaped like the
/// secrets §S3 names plus the two the contract check found:
///
/// - a bare all-digit value, or digit groups joined by `-`/`.` — phone-shaped;
/// - a bare alphanumeric token of 16+ characters — uid- or document-id-shaped;
/// - a dotted lowercase value up to 40 characters — name-shaped (`jane.doe`).
///
/// A message with spaces or an email cannot pass the character set. A name
/// without a dot, or a phone number in an unusual format, can still pass: the
/// caller must pass a real code, and the wire key is `error_code`, not free
/// text.
/// Reads a structured `code` from an error and keeps it only if it passes
/// [redactCode].
///
/// Shared by `AppLog.error` and the seams that build a typed event from a
/// caught error, so the structural read and its gate cannot drift apart.
String? readErrorCode(Object error) {
  try {
    final dynamic candidate = error;
    final Object? code = candidate.code;
    return code is String ? redactCode(code) : null;
  } catch (_) {
    return null;
  }
}

String? redactCode(String? code) {
  if (code == null ||
      !_codeShape.hasMatch(code) ||
      _digitsOnly.hasMatch(code) ||
      _digitGroups.hasMatch(code)) {
    return null;
  }
  if (code.length <= _maxDottedNameLength &&
      code.contains('.') &&
      _dottedLowercaseName.hasMatch(code)) {
    return null;
  }
  final isBareToken = !_codeSeparator.hasMatch(code);
  if (isBareToken && code.length >= _maxBareCodeLength) {
    return null;
  }
  return code;
}
