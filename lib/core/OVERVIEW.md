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
| `createRouter(AuthService, {UserRepository?})` / `handleRedirect(...)` | `router.dart` | The `go_router` graph and the redirect contract. |
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
composition roots may inject one. `handleRedirect`'s fallback is for direct callers and tests.

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
- Web hash URLs are normalized: the route may arrive in the URI fragment, not the path.

## Data flow

`lib/main.dart` initializes Firebase, activates App Check, runs
`setupServiceLocator()`, then asks `AppUpdateService` whether the running build
is still supported. If it is, `createRouter(getIt<AuthService>())` is mounted
via `MaterialApp.router`; if not, the blocking `UpdateRequiredApp` is mounted
and the router is never created. Pages read dependencies from `getIt` and
repositories from the locator; nothing constructs a repository inline.

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
