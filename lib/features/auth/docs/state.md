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

- `AuthSession.currentUserId` is the Firebase Auth uid (`AuthService` returns
  `_auth.currentUser?.uid`), and the router, profile use cases and account deletion pass it to
  `UserRepository`, which reads and writes `users/<uid>`; the rules compare the path segment with
  `request.auth.uid`.
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
  `HomePage` is a `ConsumerWidget`. Its three reads — the user document, the user's wishlists and
  the user's groups — are `homeUserProvider`, `homeWishlistsProvider` and
  `homeGroupsProvider`, uid-keyed auto-disposed `StreamProvider`s that start together on the
  first build and are created once per page lifetime; a rebuild (including a text-scale change)
  or a delete dialog creates none. `HomeSignOut.signOut()` owns the teardown: it closes
  `homeReadsEnabledProvider` before awaiting `AuthSession.signOut()`. Riverpod cancels each
  stream subscription synchronously when the gate closes, so the detach is issued before the
  credential is cleared — a listener that outlived the credential made Firestore re-issue its
  reads unauthenticated, the #81 sign-out bug. A successful sign-out leaves the gate closed; the
  router takes the page away. A failed sign-out with a live session opens the gate again, which
  starts exactly one new subscription per read and clears the old errors; one that cleared the
  session first leaves the gate closed and the page on its loading state. One sign-out runs at a
  time — a tap while one is in flight is ignored — and the failure is reported as an `error`
  event with code `sign-out-failed`; a sign-out that never settles leaves the page without its
  reads until it does, because nothing on this path has a timeout. A page built with no uid
  watches nothing and shows the spinner.
- **A gated read is data, not loading.** A closed gate emits `null` (the user) or an empty list,
  so the page checks the gate before interpreting a null user as an error. While a session is
  readable but its data is not, the page shows a loading scaffold with the profile and sign-out
  actions still reachable — a first load, a sign-out in flight, and a restart after a failed
  sign-out all use it; only a page with no uid is the bare spinner. After a failed sign-out the
  reads reload from scratch rather than keeping the old values, so the page shows loading until
  the first snapshot.
- **An ended profile stream is an error, not an endless spinner.** `homeUserProvider` wraps the
  repository stream so a stream that completes without a value emits `null`; a `null` user with
  no read in flight renders the error screen. An error outranks the value `AsyncValue` retains,
  and an error followed by done stays an error (the wrapper never turns a failure into the
  empty fallback). A read that never *completes* still spins, because nothing on this path has a
  timeout.

## How it is tested

- `test/features/auth/application/` — `LoadUserProfileUseCase` and
  `SaveUserProfileUseCase` with `mocktail` mocks registered in `getIt` (including the
  "new user gets a default wishlist" and "signed-out throws" cases).
- `test/features/auth/data/user_repository_test.dart` — `streamUsersFromIds` against
  `FakeFirebaseFirestore`.
- `test/features/auth/presentation/home_page_test.dart` — the home page's reads, sign-out and
  delete flows against mocked repositories in a `ProviderScope`: no read is issued after
  sign-out, even for a late snapshot and a rebuild; a page built with no signed-in user reads
  nothing, renders the spinner and survives a rebuild; the three reads start together and a
  rebuild, text-scale change or delete dialog adds none; the page shows its loading state
  during a sign-out and after a failed restart while keeping the profile and sign-out
  controls; a failed sign-out with a live session restarts the reads, clears the previous
  error and leaves no extra listener behind; a tap during a sign-out is ignored and served
  again once it settles; a failed sign-out that cleared the session starts nothing and shows
  only the loading state; a list error clears when data arrives; a failed or empty profile
  read shows the error screen, including a failure after data; a fresh page after a successful
  sign-out reads again; the confirmed wishlist delete calls `deleteWithItems` rather than the
  document-only `delete`, the group owner's delete calls `delete`, a member gets no delete,
  cancelling calls neither, and a failed cascade shows the error snackbar instead of the
  success one.
- `test/features/auth/presentation/home_state_test.dart` — the provider transitions without
  widgets: the read gate cancels all three streams before the credential clears (reversing the
  two calls fails it), an error followed by done stays an error instead of becoming the empty
  fallback, a value followed by done keeps that value, and a failed sign-out after the page left
  re-reads the gate instead of touching the disposed one.
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
