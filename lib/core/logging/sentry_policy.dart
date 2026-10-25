import 'package:sentry_flutter/sentry_flutter.dart';

import 'app_event.dart';
import 'log_record.dart';
import 'redaction.dart';
import 'session_context.dart';

/// Category on every breadcrumb this app adds.
///
/// `beforeBreadcrumb` keeps only this category, so an SDK breadcrumb (an HTTP
/// URL, a lifecycle event) cannot carry an id or a free-text message into the
/// store.
const String sentryBreadcrumbCategory = 'applog';

/// The keys contributing to an event's message, in a fixed order.
///
/// Every value comes from the closed vocabulary and is already redacted by
/// `LogRecord.toMap`, so the sentence can be grouped on but cannot leak.
const List<String> _messageKeys = <String>[
  'event',
  'outcome',
  'op',
  'collection',
  'phase',
  'error_type',
  'result',
  'reason',
  'provider',
  'error_code',
];

/// The §4.2 level of a record.
SentryLevel sentryLevelFor(LogRecord record) => switch (record.event) {
  ErrorEvent() => SentryLevel.error,
  FirestoreErrorEvent() => SentryLevel.warning,
  AuthStateEvent(:final code) when code != null => SentryLevel.warning,
  UpdateGateEvent(result: UpdateGateResult.failedOpen) => SentryLevel.warning,
  _ => SentryLevel.info,
};

/// The six scope tags of §4.5.
///
/// `user_ref` is absent when signed out, which is what makes
/// `LiveSentryTransport` remove the tag instead of leaving the previous
/// account's reference attached to signed-out events.
Map<String, String> scopeTagsFor(SessionContext session) => <String, String>{
  'support_code': session.supportCode,
  'session_id': session.sessionId,
  'build': session.build,
  'platform': session.platform,
  'route': session.route,
  if (session.userRef != null) 'user_ref': session.userRef!,
};

/// Whether a record is also a Sentry event, not only a breadcrumb.
///
/// Info records stay breadcrumbs: one event per navigation would exhaust the
/// error quota without adding signal. The warning families are events because
/// the tag-metric alerts filter on their `error_code`.
bool shouldCapture(LogRecord record) =>
    sentryLevelFor(record) != SentryLevel.info;

/// A deterministic, allowlisted summary used as the Sentry message.
String _messageFrom(Map<String, Object?> map) => _messageKeys
    .map((key) => map[key])
    .whereType<Object>()
    .map((value) => '$value')
    .join(' ');

/// The breadcrumb form of a record: event name plus allowlisted data.
///
/// [fields] is the record's already-built map when one caller needs both the
/// breadcrumb and the event; it is copied because the event still needs the
/// `event` key as provenance.
Breadcrumb sentryBreadcrumbFor(
  LogRecord record, [
  Map<String, Object?>? fields,
]) {
  final data = <String, dynamic>{...(fields ?? record.toMap())};
  final event = data.remove('event');
  return Breadcrumb(
    category: sentryBreadcrumbCategory,
    message: event == null ? null : '$event',
    data: data,
    level: sentryLevelFor(record),
  );
}

/// The event form of a record: message, level and allowlisted tags.
SentryEvent sentryEventFor(LogRecord record, [Map<String, Object?>? fields]) {
  final map = fields ?? record.toMap();
  final tags = <String, String>{
    for (final entry in map.entries)
      if (entry.value != null) entry.key: '${entry.value}',
  };
  return SentryEvent(
    level: sentryLevelFor(record),
    message: SentryMessage(_messageFrom(map)),
    tags: tags,
  );
}

/// Drops anything that is not an allowlisted report.
///
/// The sink never builds an unsafe event; this is the second line of defence
/// behind it, and the one that also covers events the SDK captured on its own.
SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  final tags = event.tags;
  if (tags != null && !tags.keys.every(logRecordKeys.contains)) {
    return null;
  }
  // ignore: deprecated_member_use
  final extra = event.extra;
  if (extra != null && !extra.keys.every(logRecordKeys.contains)) {
    return null;
  }
  // Flutter's error-details context carries the informationCollector output:
  // free diagnostic text that can quote a controller value (the typed name) or
  // a text span. It is not a §4.3 field, so it never ships.
  event.contexts.remove('flutter_error_details');
  // A request carries the endpoint and, on some platforms, an IP.
  event.request = null;
  // The SDK materialises an exception's `toString()` into `value` before this
  // callback runs (on web it owns `runZonedGuarded`), so the message text has
  // to be stripped here. Type, mechanism and frames survive. The rebuild also
  // drops nested causes and `unknown`: that loss is deliberate, not a bug —
  // do not "restore" it by copying `value` back.
  final exceptions = event.exceptions;
  if (exceptions != null) {
    event.exceptions = [
      for (final exception in exceptions)
        SentryException(
          type: exception.type,
          value: null,
          module: exception.module,
          stackTrace: exception.stackTrace,
          mechanism: exception.mechanism,
          threadId: exception.threadId,
        ),
    ];
  }
  // Only an event this app built carries the `event` tag, so a foreign message
  // (a zone error, a native crash) is dropped instead of shipping its text.
  final message = event.message?.formatted;
  if (message != null && !(event.tags?.containsKey('event') ?? false)) {
    event.message = null;
  }
  final user = event.user;
  if (user != null) {
    final id = user.id;
    event.user = id != null && isUserRef(id) ? SentryUser(id: id) : null;
  }
  final breadcrumbs = event.breadcrumbs;
  if (breadcrumbs != null) {
    event.breadcrumbs = breadcrumbs.where(_isAllowedBreadcrumb).toList();
  }
  return event;
}

/// Keeps only this app's allowlisted breadcrumbs.
Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb, Hint hint) =>
    breadcrumb != null && _isAllowedBreadcrumb(breadcrumb) ? breadcrumb : null;

bool _isAllowedBreadcrumb(Breadcrumb breadcrumb) {
  if (breadcrumb.category != sentryBreadcrumbCategory) {
    return false;
  }
  final data = breadcrumb.data;
  return data == null || data.keys.every(logRecordKeys.contains);
}
