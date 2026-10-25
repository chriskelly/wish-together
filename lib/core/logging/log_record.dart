import 'app_event.dart';
import 'redaction.dart';
import 'session_context.dart';

/// One report: the typed event plus the launch identifiers current when it was
/// emitted.
///
/// [toMap] is the only serialisation boundary. Its keys are drawn from
/// [logRecordKeys] and its values are already redacted, so a sink never has to
/// decide what is safe.
class LogRecord {
  const LogRecord({required this.event, required this.session});

  final AppEvent event;
  final SessionContext session;

  /// The stack trace, when this record reports an error.
  ///
  /// Kept out of [toMap] because a sink attaches a stack natively (Sentry's
  /// `captureException` takes it separately); the map is for tags and
  /// breadcrumb data only.
  StackTrace? get stackTrace => switch (event) {
    ErrorEvent(stackTrace: final trace) => trace,
    _ => null,
  };

  /// The wire form used by every sink and by S2's scrubber.
  ///
  /// The session route and `user_ref` are gated here as well, so a
  /// hand-built `SessionContext` cannot put an id path or a raw uid on the
  /// wire.
  Map<String, Object?> toMap() {
    final userRef = session.userRef;
    final map = <String, Object?>{
      'event': _eventName(event),
      'session_id': session.sessionId,
      'support_code': session.supportCode,
      'build': session.build,
      'platform': session.platform,
      'route': redactRoute(session.route),
      if (userRef != null && isUserRef(userRef)) 'user_ref': userRef,
    };

    switch (event) {
      case SessionStartEvent(:final build, :final platform, :final route):
        map['build'] = build;
        map['platform'] = platform;
        map['route'] = redactRoute(route);
      case SessionEndEvent(
        :final build,
        :final platform,
        :final route,
        :final clean,
      ):
        map['build'] = build;
        map['platform'] = platform;
        map['route'] = redactRoute(route);
        map['clean'] = clean;
      case AuthStateEvent(:final outcome, :final code):
        map['outcome'] = outcome.name;
        _putCode(map, code);
      case FirestoreErrorEvent(:final op, :final collection, :final code):
        map['op'] = op.name;
        map['collection'] = redactCollection(collection);
        _putCode(map, code);
      case RouteChangedEvent(:final route):
        map['route'] = redactRoute(route);
      case UpdateGateEvent(
        :final result,
        :final min,
        :final running,
        :final reason,
      ):
        map['result'] = result.name;
        if (min != null) map['min'] = min;
        if (running != null) map['running'] = running;
        _putCode(map, reason, key: 'reason');
      case AppCheckEvent(:final result, :final provider):
        _putCode(map, result, key: 'result');
        _putCode(map, provider, key: 'provider');
      case ClaimActionEvent(:final phase, :final code):
        map['phase'] = phase.name;
        _putCode(map, code);
      case ErrorEvent(:final runtimeTypeName, :final code, :final route):
        map['error_type'] = runtimeTypeName;
        map['route'] = redactRoute(route);
        _putCode(map, code);
    }

    return map;
  }

  static void _putCode(
    Map<String, Object?> map,
    String? value, {
    String key = 'error_code',
  }) {
    final redacted = redactCode(value);
    if (redacted != null) {
      map[key] = redacted;
    }
  }
}

String _eventName(AppEvent event) => switch (event) {
  SessionStartEvent() => 'sessionStart',
  SessionEndEvent() => 'sessionEnd',
  AuthStateEvent() => 'authState',
  FirestoreErrorEvent() => 'firestoreError',
  RouteChangedEvent() => 'routeChanged',
  UpdateGateEvent() => 'updateGate',
  AppCheckEvent() => 'appCheck',
  ClaimActionEvent() => 'claimAction',
  ErrorEvent() => 'error',
};
