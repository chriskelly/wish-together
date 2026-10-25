import 'package:sentry_flutter/sentry_flutter.dart';

import 'log_record.dart';
import 'log_sink.dart';
import 'sentry_policy.dart';
import 'session_context.dart';

/// The Sentry calls the sink needs.
///
/// An interface, not a static reference, so the mapping can be asserted in a VM
/// test without an SDK transport.
abstract class SentryTransport {
  /// Writes the six scope tags and the derived user reference.
  void applyScope(SessionContext session);

  /// Adds one breadcrumb.
  void addBreadcrumb(Breadcrumb breadcrumb);

  /// Captures one event; [stackTrace] travels separately from the event.
  void captureEvent(SentryEvent event, {StackTrace? stackTrace});

  /// Delivers everything buffered.
  Future<void> flush();
}

/// The production transport, backed by the `sentry_flutter` statics.
///
/// Breadcrumbs live in the SDK's scope and travel with the next event, and
/// `captureEvent` is already queued internally, so [flush] has nothing to
/// drain (the SDK has no static `flush` in v10).
class LiveSentryTransport implements SentryTransport {
  LiveSentryTransport();

  @override
  void applyScope(SessionContext session) {
    final tags = scopeTagsFor(session);
    Sentry.configureScope((scope) {
      for (final entry in tags.entries) {
        scope.setTag(entry.key, entry.value);
      }
      if (!tags.containsKey('user_ref')) {
        scope.removeTag('user_ref');
      }
      final userRef = tags['user_ref'];
      scope.setUser(userRef == null ? null : SentryUser(id: userRef));
    });
  }

  @override
  void addBreadcrumb(Breadcrumb breadcrumb) {
    Sentry.addBreadcrumb(breadcrumb);
  }

  @override
  void captureEvent(SentryEvent event, {StackTrace? stackTrace}) {
    Sentry.captureEvent(event, stackTrace: stackTrace);
  }

  @override
  Future<void> flush() async {}
}

/// Reports the facade's records to Sentry.
///
/// Every record is a breadcrumb; the error and warning families are also
/// events (see [shouldCapture]). The scope is written from the record's own
/// session snapshot, so `setUserRef` reaches Sentry without the facade having
/// to notify sinks.
class SentrySink implements LogSink {
  SentrySink(this._transport);

  final SentryTransport _transport;

  /// The session the scope was last written from.
  SessionContext? _applied;

  @override
  void add(LogRecord record) {
    try {
      if (!_sameSession(_applied, record.session)) {
        _transport.applyScope(record.session);
        _applied = record.session;
      }
      final fields = record.toMap();
      _transport.addBreadcrumb(sentryBreadcrumbFor(record, fields));
      if (shouldCapture(record)) {
        _transport.captureEvent(
          sentryEventFor(record, fields),
          stackTrace: record.stackTrace,
        );
      }
    } catch (_) {
      // A sink must never change the caller's decision.
    }
  }

  @override
  Future<void> flush() async {
    try {
      await _transport.flush();
    } catch (_) {
      // A sink must never change the caller's decision.
    }
  }

  static bool _sameSession(SessionContext? previous, SessionContext next) {
    if (previous == null) {
      return false;
    }
    return previous.sessionId == next.sessionId &&
        previous.userRef == next.userRef &&
        previous.build == next.build &&
        previous.platform == next.platform &&
        previous.route == next.route;
  }
}
