# Auth — Overview

Authentication, first-run onboarding, and the pages that frame the signed-in app (home and
profile).

## Responsibility

- Phone OTP, Google sign-in, and Sign in with Apple; and sign-out.
- The `users/{uid}` profile document.
- Enforcing a display name before the rest of the app is reachable.

## Layout

| Layer | Files |
| ----- | ----- |
| `domain/` | `user.dart` |
| `data/` | `auth_service.dart`, `user_repository.dart`, `google_sign_in_stub.dart`, `phone_auth_error.dart`, `apple_auth_error.dart` |
| `application/` | `load_user_profile_use_case.dart`, `save_user_profile_use_case.dart` |
| `presentation/` | `login_page.dart`, `verification_page.dart`, `profile_page.dart`, `home_page.dart` |

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
  `appleCredentialFetcher` constructor arguments so the flows are unit-testable.
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
- The default wishlist is created only on the first save (when the prior `displayName`
  was empty), so it is not duplicated on later profile edits.
- `google_sign_in_stub.dart` is a compile-time stub that `login_page.dart` falls back to on
  non-web platforms so its `web_only.renderButton()` reference still compiles there; the real
  web button comes from `google_sign_in_web`. `AuthService` always imports the real
  `google_sign_in` package, on native and web alike.
- The Sign in with Apple button is rendered **only on iOS** (`!kIsWeb &&
  defaultTargetPlatform == TargetPlatform.iOS`); web and Android show nothing. This satisfies
  App Store guideline 4.8 on the iOS app without pulling in the Apple Service ID / web flow.

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
  silent-on-cancel case.
- `test/core/router_test.dart` covers the auth redirect matrix.
