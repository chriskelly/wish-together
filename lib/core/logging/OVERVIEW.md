# Logging — Overview

The app's only reporting seam: typed events in, allowlisted records out. It is pure Dart
(no Firebase, no Sentry, no network) so the privacy rules are unit-testable with a fake sink.

## Responsibility

- Define the closed event vocabulary (§4.2) as typed Dart classes.
- Derive and carry the launch identifiers: `session_id`, `support_code`, `user_ref`, build.
- Enforce the breadcrumb allowlist (§4.3) before a record reaches any sink.
- Hand records to `LogSink` implementations. `ConsoleSink` prints in debug; S2 adds
  `SentrySink`. Sinks own the side effects.

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `AppLog` | `app_log.dart` | The seam: `event`, `error`, `routeChanged`, `setUserRef`, `flush`, `breadcrumbs`. |
| `LogSink` / `ConsoleSink` | `log_sink.dart` | Sink interface and the debug-only `debugPrint` implementation. |
| `LogRecord` | `log_record.dart` | One event plus the session snapshot; `toMap()` is the only serialisation boundary. |
| `AppEvent` | `app_event.dart` | Sealed vocabulary: session start/end, auth, Firestore, route, update gate, App Check, claim, error. |
| `SessionContext` | `session_context.dart` | Immutable identifiers of one launch, plus the pure id helpers. |
| `logRecordKeys`, `redactRoute`, `redactCollection`, `redactCode` | `redaction.dart` | The §4.3 allowlist and the redactions every record passes through. |

## Invariants

- **Nothing here throws.** A sink that throws, or an error object whose `toString()` throws,
  cannot change the caller's decision. `AppLog.flush` is the only method that returns a
  future, and it swallows sink failures too.
- **A raw uid never reaches the wire.** `AppLog.setUserRef(rawUid)` hashes immediately and
  stores only the 12-hex `user_ref`; `null` or a blank uid clears it. `SessionContext.withUserRef`
  and `LogRecord.toMap` also drop any `user_ref` that is not 12 lowercase hex characters, so a
  hand-built context cannot leak a uid either.
- **No message text, ever.** `AppLog.error` records `runtimeTypeName`, a code and the stack.
  It never reads the exception's message and never calls `toString()` on it.
- **Serialised keys come only from `logRecordKeys`.** Routes pass `redactRoute` (a segment is
  kept only when it is in `logRouteLiterals`, so ids *and* unlisted areas become `:id`, and the
  query/fragment is dropped). Callers pass a router location or pattern, never a
  `GoRouterState.name`: a bare name is not a path segment and is masked. Collections pass
  `redactCollection` (anything outside the four names becomes `other`), and every
  code/reason/provider/result passes `redactCode`.
- **`redactCode` is a shape gate for a structured field, not a general PII classifier.** It
  drops a bare all-digit value or digit groups joined by `-`/`.` (phone-shaped), a bare 16+
  character alphanumeric token (uid- or document-id-shaped), and a dotted lowercase value up to
  40 characters (name-shaped, `jane.doe`). A message with spaces or an email cannot pass the
  character set, but a name without a dot or an unusual phone format can still pass: the caller
  must still pass a real code, and this wire key is `error_code`, not free text.
- **S2's Firestore seam passes the collection name constant** (`items`, `wishlists`, …), never
  `FirebaseRepository.collectionPath`: the item repository's path is `wishlists/<id>/items`,
  which the allowlist masks as `other`.
- **`clean` belongs only to `sessionEnd`;** `min`/`running`/`reason` only to `updateGate`.
  The wire-key contract is in the epic spec §4.2.
- **Breadcrumbs are capped at 30** (`maxBreadcrumbs`), oldest dropped, and errors are not
  breadcrumbs.
- **`SessionContext` is immutable.** `AppLog` replaces it on auth/route changes; each
  `LogRecord` carries the snapshot from when it was emitted.
- **`ConsoleSink(enabled: …)` takes the debug gate as an argument** (the composition root
  passes `kDebugMode`), so the branch is testable in a VM test. Release builds pass `false`.
- No barrel file: import the concrete path (`package:wishtogether/core/logging/app_log.dart`).

## Data flow

The composition root (S2) creates one `SessionContext.create(...)` per launch and an `AppLog`
with its sinks. Presentation, application and data code call `AppLog`; the log builds a
`LogRecord` from the event and the current session, appends non-error records to the
breadcrumb ring, and calls `sink.add(record)` on each sink. `LogRecord.toMap()` is what a sink
serialises: S2's Sentry sink uses it for tags/breadcrumbs and S2's `beforeSend` reuses
`logRecordKeys` as its scrubber. A sink that needs the trail reads `AppLog.breadcrumbs`.

## How it is tested

`test/core/logging/` mirrors the files; no `getIt`, no Firebase, literals bound to `const`
variables.

- `session_context_test.dart` — Crockford encoding (known vectors), support-code alphabet and
  length, `user_ref` shape/stability/uniqueness, build resolution, route redaction.
- `redaction_test.dart` — route patterns and masks, collection mask, code shape rejection.
- `log_record_test.dart` — every event's name/fields, allowlisted keys, code dropping,
  `user_ref` absent when signed out, stack outside the map.
- `app_log_test.dart` — fan-out to sinks, error message never captured, uid never emitted,
  route redaction, 30-breadcrumb cap, sink/`toString` failures swallowed, `flush`.
- `log_sink_test.dart` — `ConsoleSink` prints when enabled and is silent when disabled.
