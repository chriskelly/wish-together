# Core architecture

Scope: what `lib/core/` is responsible for, its key types, and the startup order
that wires them. Read before adding a shared type or changing `lib/main.dart`.
Paths are relative to `lib/core/`, then to the repository root.

## Responsibility

- Base data access (`FirebaseRepository<T>`) — see `docs/data-access.md`.
- Navigation and the auth/onboarding redirect contract (`router.dart`) — see `docs/router.md`.
- Dependency wiring (`service_locator.dart`).
- App theming (`theme.dart`) — see `docs/design-system.md`.
- The reporting façade (`logging/`) — typed events, identifier derivation, and the
  breadcrumb allowlist; see `logging/AGENTS.md`.

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `FirebaseRepository<T>` | `data/firebase_repository.dart` | Abstract base for feature repositories. |
| `resolveFirestoreDatabaseId` / `createFirestoreInstance` | `firestore_target.dart` | Build-time Firestore database selection (`WT_FIRESTORE_DATABASE`). |
| `createRouter(AuthSession, {UserRepository?, String? initialLocation})` / `handleRedirect(...)` | `router.dart` | The `go_router` graph and the redirect contract. |
| `RouteChangeRecorder` / `AuthListenable` | `router.dart` | The two instrumentation seams: one `routeChanged` per location change, and the auth transition that owns `AppLog.setUserRef`. |
| `AppLog` / `LogSink` / `SessionContext` / `AppEvent` / `LogRecord` | `logging/` | The typed reporting seam (the facade is pure Dart; only the Sentry files know the SDK) and its vocabulary. |
| `appOrigin` / `locationFromUniversalLink(...)` | `app_urls.dart` | Canonical URL and the allowlisted Universal-Link → location mapping. |
| `DeepLinkService` | `deep_links.dart` | iOS link delivery (`app_links`) with a startup queue and a warm-link callback. |
| `setupServiceLocator({firestore, appLog, authSession})` / `getIt` | `service_locator.dart` | Registers the log (eagerly, when supplied), repositories and use cases. `firestore` and `authSession` are composition seams: production passes neither, a caller with its own supplies it. A supplied session that is not an `AuthService` makes `getIt<AuthService>()` throw, so the sign-in, verification and deletion screens are unbuildable for it. |
| `PackageInfoLoader` | `platform_info.dart` | The injectable `PackageInfo.fromPlatform` seam shared by the update gate and the build-identity read. |
| `BrandPalette` / `BrandGeometry` / `buildTextTheme` | `design_tokens.dart` | Brand values, geometry and the type scale. |
| `lightTheme`, `darkTheme` | `theme.dart` | Material 3 themes built from `BrandPalette`; the only theme entry points. |

## Data flow

`lib/main.dart` installs the path URL strategy and constructs `DeepLinkService` before
Firebase, so an iOS link received while startup is still working is queued. It then reads the
build identity: with a DSN the Sentry wrapper reads it before `SentryFlutter.init`; without one,
`_startUp` starts the read and initializes Firebase concurrently (the iOS package-info call
overlaps init) and awaits it afterwards. It builds the launch diagnostics (`SessionContext`,
`AppLog`, `ConsoleSink`, and `SentrySink` when a DSN is configured), registers the log in the
locator, activates App Check, and asks `AppUpdateService`
whether the running build is still supported. If it is, `_startApp` takes the queued link (if
any), seeds the session route and emits `sessionStart`, mounts
`createRouter(getIt<AuthSession>(), initialLocation: …)` via `MaterialApp.router`, and attaches
the router for warm links; if not, the blocking `UpdateRequiredApp` is mounted and the router is
never created. `SentryFlutter.init` wraps that same startup only when `WT_SENTRY_DSN` is set.
Pages read dependencies from `getIt` and repositories from the locator; nothing constructs a
repository inline.

## How it is tested

`test/core/service_locator_test.dart` pins that every repository (including the item
sub-repository) receives the one build Firestore instance.
