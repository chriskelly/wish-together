import 'app_event.dart';
import 'log_record.dart';
import 'log_sink.dart';
import 'redaction.dart';
import 'session_context.dart';

/// How many recent events [AppLog.breadcrumbs] keeps.
const int maxBreadcrumbs = 30;

/// The only reporting seam application code calls.
///
/// Fire-and-forget by contract: no caller has to await anything, nothing here
/// throws, and a failing sink is swallowed. Diagnostics must never change the
/// decision (`app_update_service.dart`'s "fail open" precedent).
///
/// The log is pure Dart; sinks own the side effects. That is what makes the
/// privacy rules (`redaction.dart`) testable without Firebase or Sentry.
class AppLog {
  factory AppLog({
    required SessionContext session,
    required List<LogSink> sinks,
  }) => AppLog._(session, List<LogSink>.unmodifiable(sinks));

  AppLog._(this._session, this._sinks);

  final List<LogSink> _sinks;
  final List<LogRecord> _breadcrumbs = <LogRecord>[];
  SessionContext _session;

  /// The identifiers of this launch.
  ///
  /// Replaced, not mutated, when the route or the signed-in user changes, so
  /// call it again after a change rather than caching the object.
  SessionContext get session => _session;

  /// The most recent events, newest last, capped at [maxBreadcrumbs].
  ///
  /// Errors are not breadcrumbs; they are the headline. Sinks that need the
  /// trail (S2's Sentry scope) read it here.
  List<LogRecord> get breadcrumbs => List<LogRecord>.unmodifiable(_breadcrumbs);

  /// Reports one typed event.
  void event(AppEvent event) {
    final record = LogRecord(event: event, session: _session);
    if (event is! ErrorEvent) {
      _breadcrumbs.add(record);
      if (_breadcrumbs.length > maxBreadcrumbs) {
        _breadcrumbs.removeAt(0);
      }
    }
    for (final sink in _sinks) {
      try {
        sink.add(record);
      } catch (_) {
        // Diagnostics must never change the decision.
      }
    }
  }

  /// Reports a navigation, keeping only the route pattern.
  ///
  /// [pattern] is a resolved location or a pattern produced by the router
  /// (`/wishlist/:id`, `/join`), never a `GoRouterState.name` such as
  /// `wishlistDetails`: redaction keeps only path segments in
  /// `logRouteLiterals`, so a bare name is masked as `:id`.
  void routeChanged(String pattern) {
    _session = _session.withRoute(pattern);
    event(RouteChangedEvent(route: _session.route));
  }

  /// Takes the RAW uid and stores only its §4.4 reference.
  ///
  /// Hashing at this boundary is what guarantees a uid cannot be stored on
  /// [session] or reach a sink. `null` (or a blank uid) clears the reference,
  /// which is the sign-out transition.
  void setUserRef(String? uid) {
    final trimmed = uid?.trim();
    final userRef = (trimmed == null || trimmed.isEmpty)
        ? null
        : userRefForUid(trimmed);
    _session = _session.withUserRef(userRef);
  }

  /// Reports an error without its message text.
  ///
  /// Only the runtime type, a code and the stack are kept. The exception's
  /// message is the channel that used to leak phone numbers and field values,
  /// so it is never read — not even `toString()`, which may throw.
  void error(Object error, StackTrace? stackTrace, {String? code}) {
    event(
      ErrorEvent(
        runtimeTypeName: error.runtimeType.toString(),
        code: _codeFor(error, code),
        stackTrace: stackTrace,
        route: _session.route,
      ),
    );
  }

  /// Gives every sink the chance to deliver what it buffered.
  ///
  /// Safe to call on shutdown; it never throws, even if a sink does.
  Future<void> flush() async {
    for (final sink in _sinks) {
      try {
        await sink.flush();
      } catch (_) {
        // Diagnostics must never change the decision.
      }
    }
  }

  /// Prefers the caller's code, then the error's own code.
  ///
  /// A candidate that the redaction gate would drop is skipped, so a malformed
  /// explicit code does not hide the structured one carried by the error. The
  /// error's `code` is read only when the explicit one cannot be used.
  static String? _codeFor(Object error, String? explicit) {
    final gated = explicit == null ? null : redactCode(explicit);
    return gated ?? readErrorCode(error);
  }
}
