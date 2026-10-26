import '../service_locator.dart';
import 'app_event.dart';
import 'app_log.dart';
import 'log_sink.dart';
import 'sentry_sink.dart';
import 'sentry_startup.dart';
import 'session_context.dart';

/// The registered [AppLog], or null when diagnostics are not wired.
///
/// Every call site uses this instead of `getIt<AppLog>()`: unit and widget
/// tests reset the locator and register only the collaborators they need, and
/// diagnostics must never throw on a locator miss.
AppLog? get appLogOrNull =>
    getIt.isRegistered<AppLog>() ? getIt<AppLog>() : null;

/// The §4.2 auth outcome of a transition, or null when the provider is outside
/// the vocabulary.
///
/// Firebase can link several providers onto one account, so the last matching
/// entry wins: provider data is ordered by link time, not by last use. The
/// outcome therefore names a provider on the account, not necessarily the one
/// used for this sign-in.
AuthOutcome? authOutcomeFor({
  required bool signedIn,
  required List<String> providerIds,
}) {
  if (!signedIn) {
    return AuthOutcome.signedOut;
  }
  for (final id in providerIds.reversed) {
    switch (id) {
      case 'phone':
        return AuthOutcome.phone;
      case 'google.com':
        return AuthOutcome.google;
      case 'apple.com':
        return AuthOutcome.apple;
    }
  }
  return null;
}

/// One launch's diagnostics.
class LaunchDiagnostics {
  const LaunchDiagnostics({required this.log, this.sentrySink});

  final AppLog log;

  /// Present only when Sentry is initialised.
  final SentrySink? sentrySink;
}

/// Builds the session, the facade and its sinks.
///
/// [sentryTransport] is supplied by `main.dart` only when a DSN is configured,
/// so an empty DSN produces a `ConsoleSink`-only log and no Sentry dependency
/// at runtime.
LaunchDiagnostics createLaunchDiagnostics({
  required BuildIdentity identity,
  required bool consoleEnabled,
  SentryTransport? sentryTransport,
}) {
  final session = SessionContext.create(
    build: identity.build,
    platform: identity.platform,
  );
  final sentrySink = sentryTransport == null
      ? null
      : SentrySink(sentryTransport);
  final log = AppLog(
    session: session,
    sinks: <LogSink>[
      ConsoleSink(enabled: consoleEnabled),
      if (sentrySink != null) sentrySink,
    ],
  );
  return LaunchDiagnostics(log: log, sentrySink: sentrySink);
}
