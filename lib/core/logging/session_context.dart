import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'redaction.dart';

/// Build identity supplied at compile time.
///
/// Web builds pass the commit SHA; iOS passes its `CFBundleVersion` to
/// [SessionContext.create] instead. Empty means a local or test run.
const String wtBuildId = String.fromEnvironment('WT_BUILD_ID');

/// Build identity used when the build passes none.
const String devBuildId = 'dev';

/// Crockford base32: 32 symbols, with no `I`, `L`, `O` or `U`.
const String crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Bytes in a session id (128 bits).
const int sessionIdByteCount = 16;

/// Symbols in the user-facing support code.
const int supportCodeLength = 6;

/// Resolves the launch build identity, falling back to [devBuildId].
String resolveBuildId(String raw) {
  final build = raw.trim();
  return build.isEmpty ? devBuildId : build;
}

/// Encodes [bytes] as Crockford base32, most significant bit first.
///
/// Sixteen bytes always produce 26 symbols; the final symbol is padded with
/// zero bits, as base32 requires.
String sessionIdFromBytes(List<int> bytes) {
  final buffer = StringBuffer();
  var accumulator = 0;
  var bits = 0;
  for (final byte in bytes) {
    // Keep only the bits that can still reach an output symbol.
    accumulator = ((accumulator << 8) | (byte & 0xff)) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buffer.write(crockfordAlphabet[(accumulator >> bits) & 31]);
    }
  }
  if (bits > 0) {
    buffer.write(crockfordAlphabet[(accumulator << (5 - bits)) & 31]);
  }
  return buffer.toString();
}

/// The part of the session id a user reads out loud (§4.4).
String supportCodeFor(String sessionId) =>
    sessionId.substring(0, min(supportCodeLength, sessionId.length));

/// The §4.4 `user_ref`: the first 12 hex characters of `sha256(uid)`.
///
/// The uid itself is never stored or reported; see `AppLog.setUserRef`.
String userRefForUid(String uid) =>
    sha256.convert(utf8.encode(uid)).toString().substring(0, 12);

final RegExp _userRefShape = RegExp(r'^[0-9a-f]{12}$');

/// Whether [value] has the shape of a derived §4.4 user reference.
bool isUserRef(String value) => _userRefShape.hasMatch(value);

/// The identifiers of one app launch.
///
/// Immutable: `AppLog` replaces the context when the route or the signed-in
/// user changes, so a record always carries the values that were current when
/// it was emitted. Read `AppLog.session` (or the snapshot on a `LogRecord`)
/// instead of caching this object across a change.
class SessionContext {
  const SessionContext({
    required this.sessionId,
    required this.supportCode,
    required this.build,
    required this.platform,
    this.userRef,
    this.route = '/',
  });

  /// Creates the per-launch context with a fresh random [sessionId].
  ///
  /// [random] is injectable so the generated id is reproducible in tests.
  factory SessionContext.create({
    String? build,
    required String platform,
    String route = '/',
    Random? random,
  }) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(
      sessionIdByteCount,
      (_) => source.nextInt(256),
    );
    final sessionId = sessionIdFromBytes(bytes);
    return SessionContext(
      sessionId: sessionId,
      supportCode: supportCodeFor(sessionId),
      build: resolveBuildId(build ?? wtBuildId),
      platform: platform,
      route: redactRoute(route),
    );
  }

  /// 16 random bytes as 26 Crockford base32 symbols; not persisted.
  final String sessionId;

  /// The first six symbols of [sessionId]: what a user reads out.
  final String supportCode;

  /// `sha256(uid)` truncated to 12 hex characters, or null when signed out.
  final String? userRef;

  /// iOS `CFBundleVersion`, or the web `WT_BUILD_ID`.
  final String build;

  /// `web`, `ios`, or whatever the platform integration reports.
  final String platform;

  /// The current route *pattern*; ids never appear here.
  final String route;

  /// Replaces the user reference.
  ///
  /// A value that is not shaped like a derived reference is dropped silently
  /// (not asserted), so a raw uid passed here by mistake is never stored and
  /// diagnostics cannot change the app's behaviour. `AppLog.setUserRef` is the
  /// intended entry point; it derives the reference first.
  SessionContext withUserRef(String? userRef) => SessionContext(
    sessionId: sessionId,
    supportCode: supportCode,
    build: build,
    platform: platform,
    userRef: userRef != null && isUserRef(userRef) ? userRef : null,
    route: route,
  );

  SessionContext withRoute(String route) => SessionContext(
    sessionId: sessionId,
    supportCode: supportCode,
    build: build,
    platform: platform,
    userRef: userRef,
    route: redactRoute(route),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionContext &&
          other.sessionId == sessionId &&
          other.supportCode == supportCode &&
          other.userRef == userRef &&
          other.build == build &&
          other.platform == platform &&
          other.route == route;

  @override
  int get hashCode =>
      Object.hash(sessionId, supportCode, userRef, build, platform, route);
}
