# Logging — Agent Guide

The app's only reporting seam: typed events in, allowlisted records out. The facade is pure
Dart; only the Sentry files know the SDK.

## Rules

- **Nothing here throws.** A sink failure cannot change the caller's decision.
- **No raw uid and no message text ever reaches the wire.** Hash the uid; record an exception's
  type, code and stack, never its message.
- Serialised keys come only from `logRecordKeys`; routes, collections, codes, reasons, providers
  and results pass their `redact*` helper first.
- There is no barrel file: import the concrete path.
- No `debugPrint`/`debugPrintStack` in `lib/` except the two calls in `log_sink.dart`.

## Reference

- Responsibility, key types, event split, startup flow → `docs/pipeline.md`
- The allowlist, the redactions, and `beforeSend`/`beforeBreadcrumb` → `docs/redaction.md`
- DSN gate, environments, build identity, handlers → `docs/startup.md`
