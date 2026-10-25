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
  platform-aware so callers do not branch. `signInWithApple()` fetches the Apple ID credential
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
  a credential the platform verified itself on Android), `isWeb`, and
  `deleteAccount()`.
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
  read fails. The page recovers on the first read that succeeds.
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

Logged out: `LoginPage` requests an SMS code; the flow branches once on `kIsWeb`.
- **Web:** `AuthService.startWebPhoneSignIn` calls `FirebaseAuth.signInWithPhoneNumber`
  (the documented web API, which manages the reCAPTCHA challenge) and returns a verification
  id. `LoginPage` navigates to `VerificationPage` with that id as `extra` (carrying
  `redirect_to` forward). `VerificationPage` calls `AuthService.confirmPhoneCode`, which
  confirms the stashed `ConfirmationResult` with the SMS code.
- **Native:** `AuthService.verifyPhoneNumber` reports progress through callbacks; the
  `codeSent` callback navigates to `VerificationPage`, and `confirmPhoneCode` builds a
  `PhoneAuthProvider` credential and signs in with it.

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
  `shouldShowAppleSignInButton` platform-gate truth table (iOS shows; web, Android, macOS hide).
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
  spinner; and a read that completes after the page is disposed raises nothing.
- `test/core/router_test.dart` covers the auth redirect matrix.
