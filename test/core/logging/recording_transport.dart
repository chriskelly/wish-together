import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wishtogether/core/logging/sentry_sink.dart';
import 'package:wishtogether/core/logging/session_context.dart';

/// A [SentryTransport] that keeps every call, for assertions.
class RecordingTransport implements SentryTransport {
  final List<Breadcrumb> breadcrumbs = <Breadcrumb>[];
  final List<({SentryEvent event, StackTrace? stackTrace})> events =
      <({SentryEvent event, StackTrace? stackTrace})>[];
  final List<SessionContext> scopes = <SessionContext>[];
  int flushes = 0;

  @override
  void addBreadcrumb(Breadcrumb breadcrumb) => breadcrumbs.add(breadcrumb);

  @override
  void applyScope(SessionContext session) => scopes.add(session);

  @override
  void captureEvent(SentryEvent event, {StackTrace? stackTrace}) =>
      events.add((event: event, stackTrace: stackTrace));

  @override
  Future<void> flush() async => flushes++;
}
