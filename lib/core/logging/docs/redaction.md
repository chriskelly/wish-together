# Redaction and the allowlist

Scope: what may reach Sentry, the shape gates every field passes through, and
the two SDK callbacks that re-check the record. Read before adding a wire key or
an event field.

## The allowlist

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
  `firestore.rules`; the allowlist masks anything outside the four names as `other`. Callers pass
  the collection name constant, never `FirebaseRepository.collectionPath`.

## The SDK callbacks

- **`beforeBreadcrumb` keeps only category `applog` and no message or one from the closed
  vocabulary.** An SDK breadcrumb (an HTTP URL, a lifecycle event), or one whose message is free
  text, cannot carry an id or a phone number into the store. `beforeSend` drops an event whose
  tags or extra carry a key outside `logRecordKeys` — except the SDK's two constant provenance
  tags (`event.origin`, `event.environment`), which `LoadContextsIntegration` adds to every
  native event before `beforeSend` (without that exemption every Dart event on iOS would be
  dropped). The exemption is by key only: the values stay the SDK's `flutter`/`dart` constants,
  and no app code writes those keys — do not put user data there. `beforeSend` also nulls
  `fingerprint`, `logger` and `serverName`, which a native scope can copy across and which this
  app never sets. It rebuilds `contexts` to an allowlist
  (`os.name`, `os.version`, `app.version`, `app.build`) — which drops the device name and
  Flutter's `flutter_error_details`, whose `informationCollector` text can quote a typed name or
  a text span — nulls the request, **the SDK transaction and culprit** (on web the enricher
  defaults `transaction` to `window.location.pathname`, which under the path URL strategy is a
  document id), reduces the user to a validated `SentryUser(id:)`, strips every exception's
  `value`, and keeps a message only when the event carries this app's `event` tag —
  a Dart error captured outside the sink has no such tag, so its materialised `toString()` is
  dropped. That last part matters on **web**: `sentry_flutter` runs the app runner inside its
  own `runZonedGuarded` there, materialises an uncaught error's `toString()` into
  `exceptions[].value` before `beforeSend`, and Flutter web never routes those errors to
  `PlatformDispatcher.onError`.
- **The scrubber's reach is Dart-only, and must not be described otherwise.** `beforeSend` does
  not see a native iOS crash (the Cocoa SDK's path), and on web the SDK's JS client installs
  `globalHandlers` with its own `beforeSend`, so a JS-level uncaught error posted by the JS
  client does not pass through `scrubEvent`. iOS also emits native lifecycle and HTTP breadcrumbs
  (`enableAutoNativeBreadcrumbs` and `recordHttpBreadcrumbs` default on);
  `LoadContextsIntegration` merges them into a Dart event through `beforeBreadcrumb` — where the
  category/message allowlist drops them — but the native-crash envelope bypasses both callbacks.
  On those paths the protections are `sendDefaultPii: false` and the absence of any PII-bearing
  custom key; check the native breadcrumbs on the manual iOS run before relying on the
  guarantee. Its policy text must not claim the scrubber covers every crash.

## How it is tested

- `test/core/logging/redaction_test.dart` — route patterns and masks, collection mask, code shape rejection, and
  the shared `readErrorCode` reader.
- `test/core/logging/sentry_policy_test.dart` — level mapping (including a `failedOpen` gate), capture split,
  the exact scope-tag names, allowlisted breadcrumb/event data, exception-value and
  message scrubbing, and every drop rule.
- `test/core/logging/sentry_scrub_end_to_end_test.dart` — a real `SentryClient`/`beforeSend` round trip: the
  serialised envelope carries no phone number, document id, uid, device name or typed name.
