# Reporting pipeline

Scope: the typed event vocabulary, the facade, and which records reach Sentry as
events. Read before adding an event, a sink, or a caller of `AppLog`. Paths are
relative to `lib/core/logging/` unless they start with `lib/`, `test/` or
`package:`.

The app's only reporting seam: typed events in, allowlisted records out. The facade is pure
Dart (no Firebase, no network) so the privacy rules are unit-testable with a fake sink; the
Sentry sink, its policy and the startup wiring are the files that know about the SDK.

## Responsibility

- Define the closed event vocabulary (§4.2) as typed Dart classes.
- Derive and carry the launch identifiers: `session_id`, `support_code`, `user_ref`, build.
- Enforce the breadcrumb allowlist (§4.3) before a record reaches any sink.
- Hand records to `LogSink` implementations. `ConsoleSink` prints in debug; `SentrySink`
  forwards to Sentry. Sinks own the side effects.
- Own the Sentry configuration (§4.5) and the null-safe accessor the rest of the app reports
  through.

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `AppLog` | `app_log.dart` | The seam: `event`, `error`, `routeChanged`, `setUserRef`, `flush`, `breadcrumbs`. |
| `LogSink` / `ConsoleSink` | `log_sink.dart` | Sink interface and the debug-only `debugPrint` implementation. |
| `LogRecord` | `log_record.dart` | One event plus the session snapshot; `toMap()` is the only serialisation boundary. |
| `AppEvent` | `app_event.dart` | Sealed vocabulary: session start/end, auth, Firestore, route, update gate, App Check, claim, error. |
| `SessionContext` | `session_context.dart` | Immutable identifiers of one launch, plus the pure id helpers. |
| `logRecordKeys`, `redactRoute`, `redactCollection`, `redactCode`, `readErrorCode` | `redaction.dart` | The §4.3 allowlist and the redactions every record passes through (see `docs/redaction.md`). |
| `SentrySink` / `SentryTransport` | `sentry_sink.dart` | One breadcrumb per record; errors and warnings are also events. The transport isolates the SDK statics so the mapping is testable. |
| `sentryLevelFor`, `shouldCapture`, `scrubEvent`, `scrubBreadcrumb` | `sentry_policy.dart` | The §4.2 level mapping and the second line of defence (see `docs/redaction.md`). |
| `SentryStartup`, `BuildIdentity`, `readBuildIdentity` | `sentry_startup.dart` | The §4.5 option values as pure data, plus the web/iOS build identity. |
| `appLogOrNull`, `authOutcomeFor`, `createLaunchDiagnostics` | `diagnostics.dart` | Null-safe accessor, the auth-outcome mapping and the launch composition. |
| `RouteChangeRecorder` | `../router.dart` | Records one `routeChanged` per router location change. |
| `SupportCodeTile` | `../../common/widgets/support_code_tile.dart` | The six-character code with a copy action. |

## Invariants

- **Nothing here throws.** A sink that throws, or an error object whose `toString()` throws,
  cannot change the caller's decision. `AppLog.flush` is the only method that returns a
  future, and it swallows sink failures too.
- **`clean` belongs only to `sessionEnd`;** `min`/`running`/`reason` only to `updateGate`.
  The wire-key contract is in the epic spec §4.2.
- **The facade's breadcrumb ring and Sentry's breadcrumb buffer are separate 30s.**
  `AppLog.maxBreadcrumbs` caps the in-memory ring that `AppLog.breadcrumbs` exposes (oldest
  dropped, errors excluded); the Sentry option `maxBreadcrumbs: 30` caps the SDK scope. The
  Sentry trail is built by `SentrySink` from every record, so the ring is no longer its source.
- **`SessionContext` is immutable.** `AppLog` replaces it on auth/route changes; each
  `LogRecord` carries the snapshot from when it was emitted.
- **`ConsoleSink(enabled: …)` takes the debug gate as an argument** (the composition root
  passes `kDebugMode`), so the branch is testable in a VM test. Release builds pass `false`.
- No barrel file: import the concrete path (`package:wishtogether/core/logging/app_log.dart`).
- **No direct `debugPrint`/`debugPrintStack` in `lib/` except `log_sink.dart`.**
  `test/no_debug_print_test.dart` scans every `lib/**/*.dart` and exempts only the console
  sink's two calls. The Profile page's former `debugPrintStack` now reports
  `profile-load-failed` through `AppLog`.
- **Every record is a Sentry breadcrumb; only the diagnostic families are events.**
  `ErrorEvent` → `error`; `FirestoreErrorEvent`, a failed `AuthStateEvent` and an
  `UpdateGateEvent` with `result: failedOpen` → `warning`; everything else → `info`, breadcrumb
  only. Capturing every info record would spend the free error quota on route changes, while a
  warning is queryable on demand — a gate that silently fails open is exactly what an agent
  needs to find afterwards.
- **The scope is written from the record's own session**, not from a second writer: the auth
  listener calls `setUserRef` and then emits an `AuthStateEvent`, so both the `user_ref` tag and
  `SentryUser` follow on sign-in and clear on sign-out. The six tag names come from
  `scopeTagsFor`; `user_ref` is *removed* when signed out, not left behind, so one account's
  signed-out activity cannot be attributed to it.

## Data flow

`lib/main.dart` installs the path strategy and the deep-link service, then either runs the startup
directly (empty DSN) or calls `SentryFlutter.init` with `appRunner` bound to the same startup.
The startup creates one `SessionContext.create(...)` per launch and an `AppLog` with
`ConsoleSink` and, when a DSN exists, `SentrySink`, and registers it in the locator. `startApp`
seeds the session route from the pending deep link and emits `sessionStart`;
`RouteChangeRecorder` reports later location changes, and the auth listener reports the
transition. `LogRecord.toMap()` is what a sink serialises, `SentrySink` maps it to a breadcrumb
(and an event for errors/warnings), and Sentry's `beforeSend`/`beforeBreadcrumb` re-check the
allowlist.

## How it is tested

`test/core/logging/` mirrors the files; no Firebase, literals bound to `const` variables,
`getIt` only where the seam requires it and always `await getIt.reset()` first.

- `test/core/logging/session_context_test.dart` — Crockford encoding (known vectors), support-code alphabet and
  length, `user_ref` shape/stability/uniqueness, build resolution, route redaction.
- `test/core/logging/log_record_test.dart` — every event's name/fields, allowlisted keys, code dropping,
  `user_ref` absent when signed out, stack outside the map.
- `test/core/logging/app_log_test.dart` — fan-out to sinks, error message never captured, uid never emitted,
  route redaction, 30-breadcrumb cap, sink/`toString` failures swallowed, `flush`.
- `test/core/logging/log_sink_test.dart` — `ConsoleSink` prints when enabled and is silent when disabled.
- `test/core/logging/route_literals_test.dart` — every page route constant is in `logRouteLiterals` (gap 5).
