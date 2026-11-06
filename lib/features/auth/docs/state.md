# Auth state and pages

Scope: the session the app shell depends on, the `users/{uid}` document, and the
read lifecycles of the home and profile pages. Read before touching
`AuthSession`, a profile use case, or a page that streams the signed-in user.

## Types

- `AuthSession` — the narrow, Firebase-free view of the signed-in identity that the app shell
  depends on: `currentUserId` / `currentUserEmail` / `currentUserPhoneNumber`, `providerIds`,
  `uidChanges` (a `Stream<String?>` of uids, not Firebase users), `signOut()`,
  `supportsAccountDeletion`, and `supportsSignOut`. The router, the signed-in pages and the use
  cases resolve this type; sign-in, re-authentication and account deletion are deliberately not
  on it, so an implementation that never touches Firebase can stand in for the production one.
  `supportsSignOut` is what keeps the home page's logout control honest: signing out routes to
  the login page, which resolves the production service, so a session without one reports
  `false` and the control is not rendered at all.
- `UserRepository extends FirebaseRepository<User>` — collection `users`.
  `getOrCreateUser(uid, {email, displayName, phoneNumber})` returns the existing document
  or creates one. `streamUsersFromIds(ids)` feeds the group members list.
- `User` — `id`, `displayName`, `email`, `phoneNumber`; `copyWith` / `toMap` / `fromMap`.
  `hasDisplayName` (the user name has content once trimmed) is what "onboarded" means, and
  `isNonBlankName(value)` is the one blank check the form validator and `hasDisplayName` share.
- `LoadUserProfileUseCase` — returns the signed-in user's document, or `null` if signed out.
- `SaveUserProfileUseCase` — trims the name, rejects a blank one with `ArgumentError` before
  any read or write, stores the trimmed value, and for a first-time user creates their default
  `"<displayName>'s Wishlist"`.

## Invariants

- The `users/{uid}` document id **is** the Firebase Auth uid.
- Onboarding is router-driven: a user with no display name — null, empty, or whitespace-only —
  cannot reach home until they save a name on `ProfilePage`.
- The default wishlist is created only on the first save (when the prior name had no content
  once trimmed), so it is not duplicated on later profile edits. A document that already holds a
  whitespace-only name — only reachable from outside the app, since Save trims and the router
  creates the document with no name — therefore counts as a first save and gets a default
  wishlist of its own.
- **`ProfilePage` offers a non-saving exit to an existing user, and none to a new one.** The
  `PrimaryAppBar`'s back arrow is gated by `shouldShowProfileBackButton`, which applies the same
  rule the router uses for onboarding — no display name, null/empty/whitespace-only alike — and
  is offered only for a **loaded** profile (`ProfileLoadState.loaded`), so the arrow is never
  offered where the redirect would only send the user back, and never on the strength of a read
  that has not succeeded.
  It navigates with `context.go(profileExitTarget(redirectTo))` — the rule Save also uses, so
  the two exits cannot disagree — never `pop`, because `/profile` is a top-level route and both
  Home → Profile and a web deep link arrive with a one-deep stack. `profileExitTarget` falls
  back to home for an absent, blank, or self-referential (`/profile` in any spelling: trailing
  slash or query string included) `redirect_to`
  and otherwise forwards the value it was handed, trimmed (an invitation arrives as a path,
  `/join?group=123`; the value is still untrusted query input). The bar also sets
  `automaticallyImplyLeading: false` so a future `push` cannot put an automatic arrow on the
  onboarding state; `ProfilePage` supplies the arrow itself through `leading`, which is why the
  two states stay a decision the page makes rather than one the bar infers.
- **A profile read that throws or finds no document shows an error with Retry.**
  `ProfilePage` models its single read as `ProfileLoadState` (`loading`, `loaded`, `failed`).
  A throw from `LoadUserProfileUseCase` — which deliberately propagates rather than swallowing —
  and a `null` result both become `failed`, which renders a message plus a **Try again** action
  and nothing else: no form, no Save, no delete-account section, no back arrow. Retry returns to
  `loading` and re-reads, ignoring a second tap while one is in flight; a success renders the
  form normally. Retries are unlimited and always user-initiated (no automatic retry or
  backoff), because a cap would turn a recoverable page into a dead end. The AppBar title is
  `Profile` while loading or failed, since only a loaded profile knows whether the user is new.
  Two consequences are accepted, not oversights: a read that never *completes* still spins,
  because nothing on this path has a timeout (the router's own `getOrCreateUser` read is
  equally unbounded), and account deletion — which lives in the form — is unreachable while the
  read fails. Sign out lives only on `HomePage`, so an account whose read never succeeds has no
  in-app way to sign out or switch account either. The page recovers on the first read that
  succeeds.
- **Home-page reads belong to the signed-in session, and end before it does.**
  `_HomePageState` starts its three reads — the user document, the wishlists query and the groups
  query, all keyed by the uid it reads at that moment — through `_subscribeDataStreams()`, and
  `build()` renders from state without touching a repository. `_cancelDataStreams()` cancels all
  three; the logout button calls it immediately before awaiting `AuthService.signOut()`,
  `dispose()` calls it as a safety net, and every start is preceded by a cancel so a second
  lifecycle cannot leak the first. The ordering is the point:
  a home listener that outlives the credential makes Firestore re-issue its reads unauthenticated,
  which the rules deny — the sign-out bug this page used to have. The cancel is a Dart
  subscription cancel, and that is the mechanism: each stream turns it into its own listener
  removal inside the same call (for queries, cancelling the snapshot `EventChannel` subscription,
  which sends the platform's cancel), so the detach is issued before the credential is cleared.
  The returned futures are deliberately not awaited: the detach is already issued, so awaiting
  would only add a microtask. A page built with no uid subscribes to nothing, so a rebuild cannot
  read or throw.
  A sign-out that *fails* is handled by what the session looks like afterwards: still live, the
  page reports the failure and then restarts its reads; already cleared, it starts nothing and
  drops the session, so the page shows only its loading state. The failure is reported as an
  `error` event with code `sign-out-failed`; it is retryable, so it tracks a user retrying rather
  than a crash loop. One sign-out runs at a time — a tap while one is in flight is ignored, and the
  button is served again once it settles — and a sign-out that never settles leaves the page
  without its reads until it does, because nothing on this path has a timeout. A read that errors
  is not final — the same subscription delivers later, and a value clears the error — but nothing
  re-subscribes on a rebuild any more, so a user-document read that never succeeds leaves the error
  screen with a relaunch (a page reload on web) as its only exit. Sign out lives on this page
  today; if it ever gains a second call site, that teardown belongs with whatever owns the session,
  not with one page.

## How it is tested

- `test/features/auth/application/` — `LoadUserProfileUseCase` and
  `SaveUserProfileUseCase` with `mocktail` mocks registered in `getIt` (including the
  "new user gets a default wishlist" and "signed-out throws" cases).
- `test/features/auth/data/user_repository_test.dart` — `streamUsersFromIds` against
  `FakeFirebaseFirestore`.
- `test/features/auth/presentation/home_page_test.dart` — the home page's read lifecycle against
  mocked repositories and broadcast stream controllers: every read is cancelled *before*
  `AuthService.signOut()` runs; no read is issued after sign-out, even for a late snapshot and a
  rebuild; a page built with no signed-in user reads nothing, renders the spinner and survives a
  rebuild; the three reads start together and a rebuild adds none; a failed sign-out with a live
  session restarts the reads and clears the previous error; a tap during a sign-out is ignored
  and served again once it settles, and a failed sign-out leaves no extra listener behind; a
  failed sign-out that cleared the session starts nothing and shows only the loading state; a
  sign-out cancels its reads before the session is cleared; a list error clears when data arrives;
  a failed or empty profile read shows the error screen; the confirmed wishlist delete calls
  `deleteWithItems` rather than the document-only `delete`, cancelling calls neither, and a
  failed cascade shows the error snackbar instead of the success one.
- `test/features/auth/presentation/profile_page_test.dart` — the profile page's exits:
  `shouldShowProfileBackButton` (a new user, a still-loading profile, and a failed read get no
  arrow; a loaded existing user does), `profilePageTitle` (onboarding and edit titles only once
  loaded), and `profileExitTarget` (a `redirect_to` destination — including an invitation path
  — is returned unchanged, with `/` as the fallback for absent, blank, or self-referential
  values). The same helper drives Save's exit. It also drives the page itself against a mocked
  `LoadUserProfileUseCase` in `getIt` for the load states: a throw shows the error with no back
  arrow, Save or delete section; a `null` result shows the same error; a successful Retry
  renders the form (with an arrow for an existing user, without one for a nameless user); a
  failed Retry keeps Retry available; a double tap starts one read; a Retry in flight shows the
  spinner; and a read that fails after the page is disposed raises nothing. One case pushes the
  page onto a navigator, where an implicit leading arrow would be allowed, and asserts a new user
  still gets none.
- `test/core/router_test.dart` covers the auth redirect matrix.
