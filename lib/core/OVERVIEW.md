# Core — Overview

Shared infrastructure and the composition roots that wire the app together. Nothing here
is a feature; features import from `core/`.

## Responsibility

- Base data access (`FirebaseRepository<T>`).
- Navigation and the auth/onboarding redirect contract (`router.dart`).
- Dependency wiring (`service_locator.dart`).
- App theming (`theme.dart`).
- The reporting façade (`logging/`) — typed events, identifier derivation, and the
  breadcrumb allowlist; see `logging/OVERVIEW.md`.

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `FirebaseRepository<T>` | `data/firebase_repository.dart` | Abstract base for feature repositories. |
| `resolveFirestoreDatabaseId` / `createFirestoreInstance` | `firestore_target.dart` | Build-time Firestore database selection (`WT_FIRESTORE_DATABASE`). |
| `createRouter(AuthService, {UserRepository?, String? initialLocation})` / `handleRedirect(...)` | `router.dart` | The `go_router` graph and the redirect contract. |
| `RouteChangeRecorder` / `AuthListenable` | `router.dart` | The two instrumentation seams: one `routeChanged` per location change, and the auth transition that owns `AppLog.setUserRef`. |
| `AppLog` / `LogSink` / `SessionContext` / `AppEvent` / `LogRecord` | `logging/` | The typed reporting seam (the facade is pure Dart; only the Sentry files know the SDK), its vocabulary, and the §4.3 allowlist (`logging/OVERVIEW.md`). |
| `appOrigin` / `locationFromUniversalLink(...)` | `app_urls.dart` | Canonical URL and the allowlisted Universal-Link → location mapping. |
| `DeepLinkService` | `deep_links.dart` | iOS link delivery (`app_links`) with a startup queue and a warm-link callback. |
| `setupServiceLocator()` / `getIt` | `service_locator.dart` | Registers the log (eagerly, when supplied), repositories and use cases. |
| `PackageInfoLoader` | `platform_info.dart` | The injectable `PackageInfo.fromPlatform` seam shared by the update gate and the build-identity read. |
| `lightTheme`, `darkTheme`, `appTextTheme` | `theme.dart` | Material 3 theme from a blue seed color (`google_fonts`). |

### `FirebaseRepository<T>`

Holds a `FirebaseFirestore instance` (injectable via the `firestore:` constructor argument
for tests), a `collectionPath` and its `collectionName` (the path's last segment).
Provides generic `streamAll`, `streamWhere(...)`, `streamOne`, `get`, `add`, `update`,
`updateData`, and `delete`. Subclasses implement `fromFirestore(DocumentSnapshot)` and
`toFirestore(T)`.

Every failed operation reports a `FirestoreErrorEvent` at this one seam, tagged with the
`collectionName` and the structured code, and then behaves exactly as before: a future
`rethrow`s the original error and a stream re-emits it through a transformer (not
`Stream.handleError`, which would make the stream forget the error and break
the list renderers' error UI — `StreamListBuilder`, `ListContentBuilder`).
Diagnostics never change the outcome. The guard covers the
model mapping too, so a `fromFirestore`/`toFirestore` `TypeError` is reported as a
`firestoreError` with no code — a client bug, not a backend code.

An override that cannot use a base method (a different query shape, a batch commit) must
call the **protected** `reportingFuture` / `reportingStream` instead of going to Firestore
directly. Deleting one of those wrappers is a silent failure — it was the violation that
made group-member loading (`streamUsersFromIds`) fail with no record at all. Report through
the repository that owns the collection, so `collectionName` names the right one:
`deleteWithItems` reports its item page read and batch commit through the `ItemRepository`.

In the running app the instance comes from `getIt<FirebaseFirestore>()`, created by
`createFirestoreInstance()`: `FirebaseFirestore.instance` when the build passes no
`WT_FIRESTORE_DATABASE`, otherwise `instanceFor(databaseId: ...)`. Tests inject a fake
directly and never construct the production instance.
**Direct construction still falls back to `FirebaseFirestore.instance`**; never do that in
app code — repositories are only constructed by `setupServiceLocator`.

### `router.dart`

`createRouter` builds a `GoRouter` whose `refreshListenable` re-evaluates on auth changes
and whose `redirect` delegates to the pure function `handleRedirect(uriString, AuthService,
{UserRepository?})`. Keeping the logic in `handleRedirect` is what makes it unit-testable.
`AuthListenable` is the only app-wide auth subscription: on every transition it calls
`AppLog.setUserRef(uid)` and emits an `AuthStateEvent` (including `signedOut`), tolerating a
missing `AppLog` so tests can build a router with only a `UserRepository`.
`RouteChangeRecorder` listens to the router's own route-information notifier, because
`GoRouter.observers` sees only Navigator push/pop and would miss `go()`, redirects and deep
links. It records one `routeChanged` per *pattern* change, seeded with the initial location, so
startup and redirect re-entry are not double-logged; two ids on the same route are one record by
design. The value is the *requested* location (go_router leaves the notifier at the pre-redirect
URI), so a signed-out `/wishlist/abc` records `/wishlist/:id` before the router shows login.
`createRouter` takes an optional `userRepository`, defaulting to
`getIt<UserRepository>()`; `main.dart` relies on that default, while tests and alternative
composition roots may inject one. It also takes an optional `initialLocation` (a path such
as `/join?group=123`), which is how an iOS Universal Link starts the router.
`handleRedirect`'s fallback is for direct callers and tests.

## Invariants

- `FirebaseRepository.instance` is `late final`, assigned once in the constructor.
- `FirebaseRepository.collectionName` is what a diagnostics event reports; the path never is,
  because a nested path (`wishlists/<id>/items`) contains a document id.
- A logged-out user is redirected to `/login`, preserving the original destination in the
  `redirect_to` query parameter. `/login` and `/verify` never redirect while logged out.
- A logged-in user with no `displayName` is redirected to `/profile` (also preserving
  `redirect_to`), so onboarding completes before any other page renders.
- A logged-in user on `/login` is sent to `redirect_to` or `/`.
- Every redirect for a logged-in user calls `UserRepository.getOrCreateUser`, so the
  `users/{uid}` document is created lazily on first navigation.
- All repositories share the single `getIt<FirebaseFirestore>()` instance; a build that sets
  `WT_FIRESTORE_DATABASE` reaches exactly that database and no other.
- Web routes are **real paths** (`usePathUrlStrategy`): `/join?group=…`, `/group/<id>`,
  `/wishlist/<id>`. The router receives in-app locations (path + query) only; hash URLs
  (`/#/…`) are not supported and land on `/`.
- `redirect_to` is forwarded verbatim as a location; it is never normalized from a fragment
  or an absolute URL.

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
`createRouter(getIt<AuthService>(), initialLocation: …)` via `MaterialApp.router`, and attaches
the router for warm links; if not, the blocking `UpdateRequiredApp` is mounted and the router is
never created. `SentryFlutter.init` wraps that same startup only when `WT_SENTRY_DSN` is set.
Pages read dependencies from `getIt` and repositories from the locator; nothing constructs a
repository inline.

## How it is tested

- `test/core/data/firebase_repository_test.dart` exercises the generic CRUD and stream
  methods against `FakeFirebaseFirestore` using a throwaway `TestModelRepository`.
- `test/core/router_test.dart` drives `handleRedirect` across the logged-out /
  logged-in-without-name / logged-in-with-name matrix, including join-link redirects, with
  a mocked `AuthService` and `UserRepository`; it also pins the `getIt<UserRepository>()`
  fallback.
- `test/core/firestore_target_test.dart` pins the database-id resolution: absent/blank means
  `(default)`, a named id is kept, and a malformed id throws instead of falling back to
  production. It also pins the define→stamp coupling and the default-vs-named instance
  selection; the staging workflow asserts the compiled bundle.
- `test/core/service_locator_test.dart` pins that every repository (including the item
  sub-repository) receives the one build Firestore instance.
- `test/core/app_urls_test.dart` pins the Universal-Link mapping: https/host/path allowlist,
  query encoding, and the debug-vs-release host sets.
- `test/core/deep_links_test.dart` pins the startup queue and warm-link forwarding, including
  the no-replay rule.
- `test/core/deep_link_config_test.dart` pins the AASA content, both hosting AASA settings,
  the entitlements split, and the disabled engine handler.
- `test/core/logging/` pins the reporting façade with fake sinks: the Crockford session id and
  support code, `user_ref` hashing, route/collection/code redaction, the allowlisted wire keys,
  the 30-record breadcrumb cap, error-message suppression, and `ConsoleSink`'s injected gate.
