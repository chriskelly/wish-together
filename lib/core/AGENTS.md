# Core — Agent Guide

Shared infrastructure and the composition roots that wire the app together. Nothing here is a
feature; features import from `core/`.

## Rules

- A brand value is written only in `design_tokens.dart`; `theme.dart` turns those values into
  `lightTheme` and `darkTheme`. A brand change edits tokens, never `ThemeData`.
- Repositories are constructed only by `setupServiceLocator`. Never build one inline, and never
  fall back to `FirebaseFirestore.instance` in app code.
- `router.dart` and `service_locator.dart` are composition roots: they may import feature pages,
  repositories and use cases deliberately.
- Every Firestore operation goes through a repository's reporting wrapper, so a failure reports
  and then behaves exactly as before.
- A getIt dependency reaches presentation only through a bridge provider in `lib/core/providers.dart`;
  no page imports `service_locator.dart`.
- One `ProviderScope` is created in `WishTogetherApp.build` around `MaterialApp.router`, with
  `retry: disableAutomaticRetry`. Every test scope and `ProviderContainer` uses the same policy.

## Reference

- What core is, key types, startup flow → `docs/architecture.md`
- Screen state, the getIt bridge, retry and test patterns → `docs/state.md`
- `FirebaseRepository<T>`, database selection, data invariants → `docs/data-access.md`
- Colours, type, primitives → `docs/design-system.md`
- Router, redirect contract, link mapping → `docs/router.md`
- The reporting pipeline → `logging/AGENTS.md`
