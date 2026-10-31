# Auth — Overview

Authentication, first-run onboarding, and the pages that frame the signed-in app (home and
profile).

## Responsibility

- Phone OTP, Google sign-in, and Sign in with Apple; and sign-out.
- In-app account deletion: re-authentication for the current provider, the
  data cascade, and deleting the auth account.
- The `users/{uid}` profile document.
- Enforcing a display name before the rest of the app is reachable.

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `user.dart` |
| `data/` | `auth_service.dart`, `user_repository.dart`, `google_sign_in_stub.dart`, `phone_auth_error.dart`, `apple_auth_error.dart`, `reauth_provider.dart`, `delete_account_error.dart`, `phone_verification.dart` |
| `application/` | `load_user_profile_use_case.dart`, `save_user_profile_use_case.dart`, `delete_account_use_case.dart` |
| `presentation/` | `login_page.dart`, `verification_page.dart`, `profile_page.dart`, `delete_account_section.dart`, `home_page.dart` |

## Key types

- `AuthService` — wraps `FirebaseAuth`, `GoogleSignIn`, and `SignInWithApple`. Exposes
  `authStateChanges`, `currentUserId` / `currentUserEmail` / `currentUserPhoneNumber`,
  `signOut()`, and the underlying `googleSignIn` instance. Google sign-in is completed by
  subscribing to `_googleSignIn.onCurrentUserChanged` and exchanging the account for a
  Firebase `GoogleAuthProvider` credential. Phone auth is **split by platform**: web uses
  `startWebPhoneSignIn(...)` (which calls `FirebaseAuth.signInWithPhoneNumber` and keeps the
  returned `ConfirmationResult`) and `confirmPhoneCode(...)` (which confirms it); native uses
  `verifyPhoneNumber(...)` plus `signInWithPhoneCredential(...)`. `confirmPhoneCode(...)` is
  platform-aware so callers do not branch. `discardPendingPhoneSignIn()` drops a web
  sign-in the user abandoned before entering the code, so a later confirmation cannot reuse
  it; it is a no-op on native, which keeps no pending state. `signInWithApple()` fetches the
  Apple ID credential
  (via the injectable `AppleCredentialFetcher`, defaulting to the static
  `SignInWithApple.getAppleIDCredential`) and exchanges it for a Firebase session through an
  `apple.com` OAuth credential. `AuthService` takes optional `auth` / `isWeb` /
  `appleCredentialFetcher` / `googleSignIn` constructor arguments so the flows are
  unit-testable. For account deletion it also exposes `signInProvider()` (the
  provider that issued the current ID token, which is the only place the
  *session's* provider is recorded once Firebase has linked several providers to
  one account), `providerIds` (the account's linked providers),
  `reauthenticateWithGoogle()` / `reauthenticateWithApple()` /
  `reauthenticateWithPhoneCode(...)` / `reauthenticateWithPhoneCredential(...)`,
  `startPhoneVerification(...)` (returns a `PhoneVerification`: a sent SMS code, or
  a credential the platform verified itself on Android; a native verification that
  never reports a callback is bounded by its `timeout` — 60 s by default,
  injectable — and reports an `authState` failure with `code: 'timeout'`), `isWeb`, and
  `deleteAccount()`. Failed sign-ins report an `authState` event with the provider
  outcome and the structured error code; the identifier the user typed and the
  exception message are never reported. A user cancelling a prompt reports the
  outcome with no code (a breadcrumb, not an S4 auth-failure event). Provider-SDK
  errors whose `code` is not a string (Apple authorization errors, some Google
  sign-in errors) also stay breadcrumbs; only `FirebaseAuthException` codes reach
  the auth-failure event family.
- `reauthCancelledCode` — the `FirebaseAuthException` code the re-authentication
  helpers throw when the user dismisses a prompt; `deleteAccountErrorMessage`
  turns it into silence rather than an error.
- `preferredReauthProvider(...)` / `ReauthProvider` — pure helper that picks the
  confirmation flow for a session: the token's provider first, then the account's
  linked providers in a fixed `phone → Google → Apple` order, skipping Apple on
  web.
- `deleteAccountErrorMessage(...)` — maps a deletion or re-authentication failure
  to a short user-facing message, and `null` when the user simply backed out.
- `DeleteAccountUseCase` — deletes the signed-in user's account. Requires a
  recent login, so the UI re-authenticates first. Deletes the user's wishlists
  and their items, hands over (or deletes) the groups they own, leaves the groups
  they do not own, deletes `users/{uid}`, then deletes the auth account last.
- `DeleteAccountSection` — the profile page's danger zone: confirm dialog,
  provider-appropriate re-authentication (Google/Apple prompt or an SMS-code
  dialog), then the use case.
- `phoneAuthErrorMessage(...)` — maps a phone `FirebaseAuthException` to a short user-facing
  message, including the "domain not authorized" case.
- `appleAuthErrorMessage(...)` — maps an Apple sign-in failure (Apple-sheet exceptions or a
  Firebase `FirebaseAuthException`) to a short user-facing message. Returns `null` when the
  user canceled the Apple sheet, so the UI stays silent.
- `UserRepository extends FirebaseRepository<User>` — collection `users`.
  `getOrCreateUser(uid, {email, displayName, phoneNumber})` returns the existing document
  or creates one. `streamUsersFromIds(ids)` feeds the group members list.
- `User` — `id`, `displayName`, `email`, `phoneNumber`; `copyWith` / `toMap` / `fromMap`.
- `LoadUserProfileUseCase` — returns the signed-in user's document, or `null` if signed out.
- `SaveUserProfileUseCase` — sets `displayName` and, for a first-time user, creates their
  default `"<displayName>'s Wishlist"`.

## Invariants

- The `users/{uid}` document id **is** the Firebase Auth uid.
- Onboarding is router-driven: a user with an empty `displayName` cannot reach home until
  they save a name on `ProfilePage`.
- **`ProfilePage` offers a non-saving exit to an existing user, and none to a new one.** The
  AppBar's back arrow is gated by `shouldShowProfileBackButton`, which applies the same rule the
  router uses for onboarding — an empty `displayName` — and is offered only for a **loaded**
  profile (`ProfileLoadState.loaded`), so the arrow is never offered where the redirect would
  only send the user back, and never on the strength of a read that has not succeeded.
  It navigates with `context.go(profileExitTarget(redirectTo))` — the rule Save also uses, so
  the two exits cannot disagree — never `pop`, because `/profile` is a top-level route and both
  Home → Profile and a web deep link arrive with a one-deep stack. `profileExitTarget` falls
  back to home for an absent, blank, or self-referential (`/profile` in any spelling: trailing
  slash or query string included) `redirect_to`
  and otherwise forwards the value it was handed, trimmed (an invitation arrives as a path,
  `/join?group=123`; the value is still untrusted query input). The AppBar also sets
  `automaticallyImplyLeading: false` so a future `push` cannot put an automatic arrow on the
  onboarding state.
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
  three; the logout button calls it **before** awaiting `AuthService.signOut()`, `dispose()` calls
  it again as a safety net, and every start is preceded by a cancel so a second lifecycle cannot
  leak the first. The ordering is the point: a home listener that outlives the credential makes
  Firestore re-issue its reads unauthenticated, which the rules deny — the sign-out bug this page
  used to have. A page built with no uid subscribes to nothing, so a rebuild cannot read or throw.
  A sign-out that *fails* is handled by what the session looks like afterwards: still live, the
  page reports the failure and then restarts its reads; already cleared, it starts nothing and
  drops the session, so the page shows only its loading state and the dead session's data is never
  rendered. One sign-out runs at a time — a tap
  while one is in flight is ignored, and the button is served again once it settles — and a
  sign-out that never settles leaves the page without its reads until it does, because nothing on
  this path has a timeout. A read that errors is not final — the same subscription delivers later,
  and a value clears the error — but nothing re-subscribes on a rebuild any more, so a user-document
  read that never succeeds leaves the error screen with a relaunch (a page reload on web) as its
  only exit.
  The cancellation guarantee is at the Dart subscription level, which is where the SDK's read is
  issued from. Sign out lives on this page today; if it ever gains a second call site, or the
  `AuthService` API is redesigned (#61), that teardown belongs with the session owner instead.
- The default wishlist is created only on the first save (when the prior `displayName`
  was empty), so it is not duplicated on later profile edits.
- `google_sign_in_stub.dart` is a compile-time stub that `login_page.dart` falls back to on
  non-web platforms so its `web_only.renderButton()` reference still compiles there; the real
  web button comes from `google_sign_in_web`. `AuthService` always imports the real
  `google_sign_in` package, on native and web alike.
- The Sign in with Apple button is rendered **only on iOS** — `LoginPage` gates it
  with the pure `shouldShowAppleSignInButton(isWeb:, platform:)` predicate, which web
  (where `defaultTargetPlatform` is the browser's OS) and Android both fail. This satisfies
  App Store guideline 4.8 on the iOS app without pulling in the Apple Service ID / web flow.
- **Account deletion order is load-bearing.** The Firestore cascade runs *before*
  `deleteAccount()`, because Firestore writes need a live session; the auth
  account is deleted last. The caller re-authenticates first
  (`User.delete()` throws `requires-recent-login` otherwise). Every step is
  idempotent, so a failed run is retried by starting the flow again.
- **Deletion leaves other people's data alone.** Claims on items in other
  users' wishlists are *not* cleared — a claimed item stays claimed so a gift is
  never bought twice — and nothing outside the user's own documents and their
  groups' membership arrays is written. A group the user owned passes to its
  first remaining member (one atomic `ownerId` + `members` update); a group is
  deleted only when the user was its last member.
- Deleting an account revokes the Google grant (`_googleSignIn.disconnect()`, not
  merely `signOut()`), so the provider-side access is dropped as well as the local
  session, and the `onCurrentUserChanged` listener cannot re-establish a session for
  the deleted account.
- **Sign in with Apple is only manually revoked.** Programmatic revocation needs the
  Apple refresh token (or authorization code) plus a client secret signed with the
  Apple private key — both server-side. The authorization code is available during
  sign-in and re-authentication, but is deliberately not retained because no server
  endpoint exists to consume it yet. So when the account has an `apple.com` link, the
  flow ends with TN3194's fallback: the user is told to remove the app under
  Settings → Apple ID → Sign in with Apple. Programmatic revocation needs the
  authorization code and the user identifier kept at sign-in (or captured from the
  re-authentication step), plus a Cloud Function; until then App Store submission
  relies on the manual step. TN3194's third step — handling the credential-revoked
  notification — is a no-op for this client: `user.delete()` has already left it
  unauthenticated and no Apple refresh token is stored.

## Data flow

Logged out: `LoginPage` requests an SMS code through `AuthService.startPhoneVerification`,
which branches once on `kIsWeb` and completes when the platform has reported an outcome.
The Send button stays disabled until that future completes: the raw `verifyPhoneNumber`
future returns as soon as the request is handed to the platform, so a guard tied to it
re-enabled Send while the SMS was still on its way, and each extra tap sent another code and
opened another code page. A platform that never reports fails with a `TimeoutException`
**and** an `authState` record (`code: 'timeout'`), and the page tells the user to try again.
- **Web:** `AuthService.startWebPhoneSignIn` calls `FirebaseAuth.signInWithPhoneNumber`
  (the documented web API, which manages the reCAPTCHA challenge) and returns a verification
  id. `LoginPage` navigates to `VerificationPage` with that id as `extra` (carrying
  `redirect_to` forward). `VerificationPage` calls `AuthService.confirmPhoneCode`, which
  confirms the stashed `ConfirmationResult` with the SMS code.
- **Native:** `AuthService.verifyPhoneNumber` reports progress through callbacks, which
  `startPhoneVerification` turns into a `PhoneVerification`. A sent code navigates to
  `VerificationPage`; an auto-verified credential signs the user in directly;
  `confirmPhoneCode` builds a `PhoneAuthProvider` credential and signs in with it.

`VerificationPage` is pushed on top of `LoginPage`, so the AppBar's back action returns to the
number the user typed, still in the field. It used to replace the login page in the stack: on web
the browser's Back still reached login, but a freshly built one with the number gone, and the app
itself offered no in-app way out. Because the push is imperative the web address bar keeps
showing `/login` while the code page is up, and a reload returns to login — the page was never
reloadable anyway, since it needs the verification id passed as route `extra`. Leaving the page
discards a pending web sign-in, and a successful confirmation drops it too, so neither can be
reused; a rejected code keeps it so the user can retry. The page also shows the session's
support code: a wrong or expired code is an auth failure the user may have to report, and it is
the one screen where that failure is most likely.

On iOS, the Apple button (from `sign_in_with_apple`) calls `AuthService.signInWithApple`, which
exchanges the Apple identity token for a Firebase session. Email lands on the Firebase user
via the identity token and flows into the profile document through the router; Apple only
returns the name/email on the *first* sign-in, and this flow does not persist the name (the
onboarding page still collects a display name).

On web, the Google button is rendered by `google_sign_in_web` and `AuthService` handles the
credential. Either path triggers the router redirect: no name → `/profile`, otherwise
`redirect_to` or `/`.

Deleting an account starts on `ProfilePage` — reachable for any signed-in user, including one
who has not chosen a display name yet — and never touches the router's redirect rules:
`DeleteAccountSection` confirms, re-authenticates for the session's provider, runs
`DeleteAccountUseCase`, and returns to `/login`. Because `user.delete()` clears the Firebase
session, `AuthListenable` drops the signed-in state at the same moment; the
`context.go('/login')` matches what the redirect would do anyway.

## Platform prerequisites

Web phone auth requires the app's host to be listed in **Firebase Auth → Settings →
Authorized domains** — the reCAPTCHA check fails with `unauthorized-domain` otherwise.
Preview-channel hosts and `localhost` are separate cases: preview hosts are not covered by a
wildcard, and Firebase does not allow `localhost` as a host for real phone auth (local testing
is limited to test numbers).

Sign in with Apple requires the **Apple** provider enabled in **Firebase Auth** and the App ID
to have the **Sign in with Apple** capability in the Apple Developer portal. The capability is
already declared in `ios/Runner/Runner.entitlements` and `ios/Runner/Runner-Debug.entitlements`
(`com.apple.developer.applesignin`). The native iOS flow needs no Services ID or authorization
callback URL — those are only for the OAuth code flow (web/Android).

Account deletion re-authenticates for real, so it cannot be exercised on a preview channel:
validate it on the **staging** site (or live) with a throwaway account for each provider
(Google, Apple, phone).

## How it is tested

- `test/features/auth/application/` — `LoadUserProfileUseCase` and
  `SaveUserProfileUseCase` with `mocktail` mocks registered in `getIt` (including the
  "new user gets a default wishlist" and "signed-out throws" cases).
- `test/features/auth/data/user_repository_test.dart` — `streamUsersFromIds` against
  `FakeFirebaseFirestore`.
- `test/features/auth/data/auth_service_test.dart` — the phone-auth platform split with
  mocked `FirebaseAuth` / `ConfirmationResult` (web uses `signInWithPhoneNumber` + `confirm`;
  native uses `signInWithCredential`), plus `signInWithApple` with an injected
  `AppleCredentialFetcher` (credential exchange, the SHA-256 nonce relationship, the missing
  identity token, and error propagation).
- `test/features/auth/data/phone_auth_error_test.dart` — the phone error-code → message mapper.
- `test/features/auth/data/apple_auth_error_test.dart` — the Apple error mapper, including the
  silent-on-cancel case and every handled Firebase code.
- `test/features/auth/application/delete_account_use_case_test.dart` — the deletion
  cascade: owned wishlists deleted with their items, an owned group handed over or
  deleted, non-owned memberships removed, the profile document deleted, the auth
  account deleted **last**, the unauthenticated throw, and "a failed cascade never
  deletes the auth account".
- `test/features/auth/data/auth_service_test.dart` — as above, plus `deleteAccount`
  (delete then revoke the Google grant, the signed-out no-op, and a failed revocation
  still counting as success), every re-authentication path (native Google credential,
  web Google popup, Apple credential, phone code, platform-verified phone credential),
  `startPhoneVerification` (instant verification, code sent, auto-retrieval timeout,
  failure, double-fire, timeout, and the web path), `signInProvider`, and
  `providerIds`.
- `test/features/auth/data/reauth_provider_test.dart` — the provider-preference truth
  table, including the token-over-linked-providers preference and Apple being skipped
  on web.
- `test/features/auth/data/delete_account_error_test.dart` — the deletion error mapper,
  including the silent-on-cancel cases.
- `test/features/auth/presentation/login_page_test.dart` — the
  `shouldShowAppleSignInButton` platform-gate truth table (iOS shows; web, Android, macOS hide);
  the phone flow leaving the code page on top of login through the real router, with a back
  action that returns to login and keeps the typed number; a second Send tap before the
  platform reports being ignored, Send re-enabling after a failure, and the timeout message.
- `test/features/auth/presentation/home_page_test.dart` — the home page's read lifecycle against
  mocked repositories and broadcast stream controllers: every read is cancelled *before*
  `AuthService.signOut()` runs; no read is issued after sign-out, even for a late snapshot and a
  rebuild; a page built with no signed-in user reads nothing, renders the spinner and survives a
  rebuild; the three reads start together and a rebuild adds none; a failed sign-out with a live
  session restarts the reads and clears the previous error; a tap during a sign-out is ignored
  and served again once it settles, and a failed sign-out leaves no extra listener behind; a
  failed sign-out that cleared the session starts nothing and shows only the loading state; a
  list error clears when data arrives; and a failed or empty profile read shows the error screen.
- `test/features/auth/presentation/verification_page_test.dart` — the code page's support code
  (visible on arrival and after a failed confirmation), the "sign-in expired" message when the
  page outlives the web sign-in, and the pending sign-in being discarded when the page closes.
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
  spinner; and a read that fails after the page is disposed raises nothing.
- `test/core/router_test.dart` covers the auth redirect matrix.
