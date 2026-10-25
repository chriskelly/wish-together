# Logging — Overview

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
| `logRecordKeys`, `redactRoute`, `redactCollection`, `redactCode` | `redaction.dart` | The §4.3 allowlist and the redactions every record passes through. |
| `SentrySink` / `SentryTransport` | `sentry_sink.dart` | One breadcrumb per record; errors and warnings are also events. The transport isolates the SDK statics so the mapping is testable. |
| `sentryLevelFor`, `shouldCapture`, `scrubEvent`, `scrubBreadcrumb` | `sentry_policy.dart` | The §4.2 level mapping and the second line of defence behind the typed façade. |
| `SentryStartup`, `BuildIdentity`, `readBuildIdentity` | `sentry_startup.dart` | The §4.5 option values as pure data, plus the web/iOS build identity. |
| `appLogOrNull`, `errorCodeOf`, `authOutcomeFor`, `createLaunchDiagnostics` | `diagnostics.dart` | Null-safe accessor and the pure helpers the seams share. |
| `RouteChangeRecorder` | `../router.dart` | Records one `routeChanged` per router location change. |
| `SupportCodeTile` | `../../common/widgets/support_code_tile.dart` | The six-character code with a copy action. |

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
- **A collection is reported by name, never by path.** A nested path
  (`wishlists/<id>/items`) contains a document id, which is a capability under
  `firestore.rules`; the allowlist masks anything outside the four names as `other`.
- **`clean` belongs only to `sessionEnd`;** `min`/`running`/`reason` only to `updateGate`.
  The wire-key contract is in the epic spec §4.2.
- **Breadcrumbs are capped at 30** (`maxBreadcrumbs`), oldest dropped, and errors are not
  breadcrumbs.
- **`SessionContext` is immutable.** `AppLog` replaces it on auth/route changes; each
  `LogRecord` carries the snapshot from when it was emitted.
- **`ConsoleSink(enabled: …)` takes the debug gate as an argument** (the composition root
  passes `kDebugMode`), so the branch is testable in a VM test. Release builds pass `false`.
- **Every record is a Sentry breadcrumb; only the diagnostic families are events.**
  `ErrorEvent` → `error`; `FirestoreErrorEvent`, a failed `AuthStateEvent` and an
  `UpdateGateEvent` with `result: failedOpen` → `warning`; everything else → `info`, breadcrumb
  only. Capturing every info record would spend the free error quota on route changes, while a
  warning is queryable on demand — a gate that silently fails open is exactly what an agent
  needs to find afterwards.
- **`beforeBreadcrumb` keeps only category `applog`.** An SDK breadcrumb (an HTTP URL, a
  lifecycle event) cannot carry an id or free text into the store. `beforeSend` drops an event
  whose tags or extra carry a key outside `logRecordKeys`, nulls the request, reduces the user
  to a validated `SentryUser(id:)`, strips every exception's `value`, and keeps a message only
  when the event carries this app's `event` tag — a zone or native error has no such tag, so its
  `toString()` never ships. That last part matters on **web**: `sentry_flutter`
  runs the app runner inside its own `runZonedGuarded` there, materialises an uncaught error's
  `toString()` into `exceptions[].value` before `beforeSend`, and Flutter web never routes those
  errors to `PlatformDispatcher.onError` — so the scrubber is the only thing between a
  `FirebaseAuthException` message and the store.
- **The scope is written from the record's own session**, not from a second writer: the auth
  listener calls `setUserRef` and then emits an `AuthStateEvent`, so both the `user_ref` tag and
  `SentryUser` follow on sign-in and clear on sign-out. The six tag names come from
  `scopeTagsFor`; `user_ref` is *removed* when signed out, not left behind, so one account's
  signed-out activity cannot be attributed to it.
- **`sessionEnd` is not emitted.** No app-level lifecycle observer exists, and a `detached`
  callback cannot reliably await a flush on web or iOS. Sentry's own session tracking covers
  session health; a startup only emits `sessionStart` (with the real build, platform and route).
- **An empty `WT_SENTRY_DSN` means Sentry is never initialised** — not merely disabled: no SDK,
  no native handler, no network. `ConsoleSink` still reports in debug.
- **`WT_SENTRY_ENVIRONMENT` overrides the environment**; `staging` also omits `release`/`dist`,
  because the pre-merge deploy uploads no symbols. The staging deploy workflow passes it.
- **Sentry's own handlers are the only global error handlers.** `SentryFlutter.init` installs
  `FlutterErrorIntegration` and `PlatformDispatcher.onError` (on web, its own
  `runZonedGuarded`), so the app does not install a second pair; `beforeSend` is what keeps the
  raw exception text off the wire.
- **The support code is reachable signed out.** It is on Profile for a signed-in user and on
  the login page for the failed-OTP case, because the router sends a signed-out user to
  `/login` and Profile is unreachable there.

## Data flow

`main.dart` installs the path strategy and the deep-link service, then either runs the startup
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

- `session_context_test.dart` — Crockford encoding (known vectors), support-code alphabet and
  length, `user_ref` shape/stability/uniqueness, build resolution, route redaction.
- `redaction_test.dart` — route patterns and masks, collection mask, code shape rejection.
- `log_record_test.dart` — every event's name/fields, allowlisted keys, code dropping,
  `user_ref` absent when signed out, stack outside the map.
- `app_log_test.dart` — fan-out to sinks, error message never captured, uid never emitted,
  route redaction, 30-breadcrumb cap, sink/`toString` failures swallowed, `flush`.
- `log_sink_test.dart` — `ConsoleSink` prints when enabled and is silent when disabled.
- `sentry_startup_test.dart` — empty/whitespace DSN disables; environment and staging rules;
  release/dist naming; the §4.5 option values; iOS build read and fallback.
- `sentry_policy_test.dart` — level mapping (including a `failedOpen` gate), capture split,
  the exact §4.5 scope-tag names, allowlisted breadcrumb/event data, exception-value and
  message scrubbing, and every drop rule.
- `sentry_sink_test.dart` — breadcrumb vs event, stack passthrough, one scope write per session
  change, sign-out clears the user, transport failures swallowed.
- `diagnostics_test.dart` — Sentry sink present only with a transport, structural code read,
  provider mapping.
- `route_literals_test.dart` — every page route constant is in `logRouteLiterals` (gap 5).
