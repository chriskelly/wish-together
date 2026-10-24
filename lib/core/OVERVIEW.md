# Core — Overview

Shared infrastructure and the composition roots that wire the app together. Nothing here
is a feature; features import from `core/`.

## Responsibility

- Base data access (`FirebaseRepository<T>`).
- Navigation and the auth/onboarding redirect contract (`router.dart`).
- Dependency wiring (`service_locator.dart`).
- App theming (`theme.dart`).

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `FirebaseRepository<T>` | `data/firebase_repository.dart` | Abstract base for feature repositories. |
| `resolveFirestoreDatabaseId` / `createFirestoreInstance` | `firestore_target.dart` | Build-time Firestore database selection (`WT_FIRESTORE_DATABASE`). |
| `createRouter(AuthService, {UserRepository?, String? initialLocation})` / `handleRedirect(...)` | `router.dart` | The `go_router` graph and the redirect contract. |
| `appOrigin` / `locationFromUniversalLink(...)` | `app_urls.dart` | Canonical URL and the allowlisted Universal-Link → location mapping. |
| `DeepLinkService` | `deep_links.dart` | iOS link delivery (`app_links`) with a startup queue and a warm-link callback. |
| `setupServiceLocator()` / `getIt` | `service_locator.dart` | Registers repositories and use cases as lazy singletons. |
| `lightTheme`, `darkTheme`, `appTextTheme` | `theme.dart` | Material 3 theme from a blue seed color (`google_fonts`). |

### `FirebaseRepository<T>`

Holds a `FirebaseFirestore instance` (injectable via the `firestore:` constructor argument
for tests) and a `collectionPath`. Provides generic
`streamAll`, `streamWhere(...)`, `streamOne`, `get`, `add`, `update`, `updateData`, and
`delete`. Subclasses implement `fromFirestore(DocumentSnapshot)` and `toFirestore(T)`.

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
`createRouter` takes an optional `userRepository`, defaulting to
`getIt<UserRepository>()`; `main.dart` relies on that default, while tests and alternative
composition roots may inject one. It also takes an optional `initialLocation` (a path such
as `/join?group=123`), which is how an iOS Universal Link starts the router.
`handleRedirect`'s fallback is for direct callers and tests.

## Invariants

- `FirebaseRepository.instance` is `late final`, assigned once in the constructor.
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
Firebase, so an iOS link received while startup is still working is queued. It then
initializes Firebase, activates App Check, runs `setupServiceLocator()`, and asks
`AppUpdateService` whether the running build is still supported. If it is, `_startApp` takes
the queued link (if any), mounts `createRouter(getIt<AuthService>(), initialLocation: …)` via
`MaterialApp.router`, and attaches the router for warm links; if not, the blocking
`UpdateRequiredApp` is mounted and the router is never created. Pages read dependencies from
`getIt` and repositories from the locator; nothing constructs a repository inline.

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
