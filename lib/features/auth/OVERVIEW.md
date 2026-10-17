# Auth — Overview

Authentication, first-run onboarding, and the pages that frame the signed-in app (home and
profile).

## Responsibility

- Phone OTP and Google sign-in, and sign-out.
- The `users/{uid}` profile document.
- Enforcing a display name before the rest of the app is reachable.

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `user.dart` |
| `data/` | `auth_service.dart`, `user_repository.dart`, `google_sign_in_stub.dart` |
| `application/` | `load_user_profile_use_case.dart`, `save_user_profile_use_case.dart` |
| `presentation/` | `login_page.dart`, `verification_page.dart`, `profile_page.dart`, `home_page.dart` |

## Key types

- `AuthService` — wraps `FirebaseAuth` and `GoogleSignIn`. Exposes `authStateChanges`,
  `currentUserId` / `currentUserEmail` / `currentUserPhoneNumber`, `signOut()`, and the
  underlying `googleSignIn` instance. Google sign-in is completed by subscribing to
  `_googleSignIn.onCurrentUserChanged` and exchanging the account for a Firebase
  `GoogleAuthProvider` credential. Phone auth is **split by platform**: web uses
  `startWebPhoneSignIn(...)` (which calls `FirebaseAuth.signInWithPhoneNumber` and keeps the
  returned `ConfirmationResult`) and `confirmPhoneCode(...)` (which confirms it); native uses
  `verifyPhoneNumber(...)` plus `signInWithPhoneCredential(...)`. `confirmPhoneCode(...)` is
  platform-aware so callers do not branch. `AuthService` takes optional `auth` / `isWeb`
  constructor arguments so the split is unit-testable.
- `phoneAuthErrorMessage(...)` — maps a `FirebaseAuthException` to a short user-facing
  message, including the "domain not authorized" case.
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
- The default wishlist is created only on the first save (when the prior `displayName`
  was empty), so it is not duplicated on later profile edits.
- `google_sign_in_stub.dart` is a compile-time stub that `login_page.dart` falls back to on
  non-web platforms so its `web_only.renderButton()` reference still compiles there; the real
  web button comes from `google_sign_in_web`. `AuthService` always imports the real
  `google_sign_in` package, on native and web alike.

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

On web, the Google button is rendered by `google_sign_in_web` and `AuthService` handles the
credential. Either path triggers the router redirect: no name → `/profile`, otherwise
`redirect_to` or `/`.

## Platform prerequisites

Web phone auth requires the app's host to be listed in **Firebase Auth → Settings →
Authorized domains** — the reCAPTCHA check fails with `unauthorized-domain` otherwise.
Preview-channel hosts and `localhost` are separate cases: preview hosts are not covered by a
wildcard, and Firebase does not allow `localhost` as a host for real phone auth (local testing
is limited to test numbers).

## How it is tested

- `test/features/auth/application/` — `LoadUserProfileUseCase` and
  `SaveUserProfileUseCase` with `mocktail` mocks registered in `getIt` (including the
  "new user gets a default wishlist" and "signed-out throws" cases).
- `test/features/auth/data/user_repository_test.dart` — `streamUsersFromIds` against
  `FakeFirebaseFirestore`.
- `test/features/auth/data/auth_service_test.dart` — the phone-auth platform split with
  mocked `FirebaseAuth` / `ConfirmationResult` (web uses `signInWithPhoneNumber` + `confirm`;
  native uses `signInWithCredential`).
- `test/features/auth/data/phone_auth_error_test.dart` — the error-code → message mapper.
- `test/core/router_test.dart` covers the auth redirect matrix.
