/// The closed vocabulary of things the app reports (§4.2).
///
/// Every event is a typed class with typed fields; there is deliberately no
/// free-form `String message` on the privacy-sensitive path. `sealed` means a
/// new event cannot be added without updating `LogRecord.toMap` and the
/// allowlist in `redaction.dart`.
sealed class AppEvent {
  const AppEvent();
}

/// How a sign-in attempt ended.
enum AuthOutcome { signedOut, phone, google, apple }

/// The Firestore operation that failed.
enum FirestoreOp { get, list, write, claim }

/// The update gate's decision.
enum UpdateGateResult { allowed, blocked, failedOpen }

/// Where a claim attempt stopped.
enum ClaimPhase { started, completed, denied }

/// The app started. The route is the one it actually opened on.
class SessionStartEvent extends AppEvent {
  const SessionStartEvent({
    required this.build,
    required this.platform,
    required this.route,
  });

  final String build;
  final String platform;
  final String route;
}

/// The app stopped; [clean] distinguishes a normal exit from a crash path.
class SessionEndEvent extends AppEvent {
  const SessionEndEvent({
    required this.build,
    required this.platform,
    required this.route,
    required this.clean,
  });

  final String build;
  final String platform;
  final String route;
  final bool clean;
}

/// A sign-in state change. [code] carries the failure code, never the
/// identifier the user typed.
class AuthStateEvent extends AppEvent {
  const AuthStateEvent({required this.outcome, this.code});

  final AuthOutcome outcome;
  final String? code;
}

/// A Firestore failure at the repository seam.
///
/// [collection] must be one of the allowlisted names; `LogRecord` masks
/// anything else, because a collection path can contain a document id.
class FirestoreErrorEvent extends AppEvent {
  const FirestoreErrorEvent({
    required this.op,
    required this.collection,
    this.code,
  });

  final FirestoreOp op;
  final String collection;
  final String? code;
}

/// Navigation happened. [route] is a pattern, never a resolved id path.
class RouteChangedEvent extends AppEvent {
  const RouteChangedEvent({required this.route});

  final String route;
}

/// The update gate decided. [min] and [running] are the integer builds, and
/// [reason] is a code such as `build-unreadable`, `remote-config-unavailable`,
/// `missing-update-url`, `min-not-integer`, `check-failed`,
/// `unexpected-failure`, `debug-bypass` or `gate-not-applicable`.
class UpdateGateEvent extends AppEvent {
  const UpdateGateEvent({
    required this.result,
    this.min,
    this.running,
    this.reason,
  });

  final UpdateGateResult result;
  final int? min;
  final int? running;
  final String? reason;
}

/// App Check activation ended. [provider] is iOS-only today.
class AppCheckEvent extends AppEvent {
  const AppCheckEvent({required this.result, this.provider});

  final String result;
  final String? provider;
}

/// A claim attempt. [code] is the failure code when one applies.
class ClaimActionEvent extends AppEvent {
  const ClaimActionEvent({required this.phase, this.code});

  final ClaimPhase phase;
  final String? code;
}

/// An error, reduced to what is safe to report.
///
/// The exception's message text is deliberately not a field: `AppLog.error`
/// never reads it, because it is the channel that used to leak phone numbers
/// and field values. [runtimeTypeName] is a class name, never instance data.
class ErrorEvent extends AppEvent {
  const ErrorEvent({
    required this.runtimeTypeName,
    this.code,
    this.stackTrace,
    required this.route,
  });

  final String runtimeTypeName;
  final String? code;
  final StackTrace? stackTrace;
  final String route;
}
