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
  `currentUserId` / `currentUserEmail` / `currentUserPhoneNumber`, `verifyPhoneNumber(...)`,
  `signInWithPhoneCredential(...)`, `signOut()`, and the underlying `googleSignIn`
  instance. Google sign-in is completed by subscribing to
  `_googleSignIn.onCurrentUserChanged` and exchanging the account for a Firebase
  `GoogleAuthProvider` credential.
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
- `google_sign_in_stub.dart` is a compile-time stub (via conditional import) that keeps
  `AuthService` compiling off-web and in the test runner; the real web button comes from
  `google_sign_in_web`.

## Data flow

Logged out: `LoginPage` calls `AuthService.verifyPhoneNumber`; the `codeSent` callback
navigates to `VerificationPage` with the `verificationId` as `extra` (carrying `redirect_to`
forward). The code is exchanged via `signInWithPhoneCredential`. On web, the Google button
is rendered by `google_sign_in_web` and `AuthService` handles the credential. Either path
triggers the router redirect: no name → `/profile`, otherwise `redirect_to` or `/`.

## How it is tested

- `test/features/auth/application/` — `LoadUserProfileUseCase` and
  `SaveUserProfileUseCase` with `mocktail` mocks registered in `getIt` (including the
  "new user gets a default wishlist" and "signed-out throws" cases).
- `test/features/auth/data/user_repository_test.dart` — `streamUsersFromIds` against
  `FakeFirebaseFirestore`.
- `test/core/router_test.dart` covers the auth redirect matrix.
- `AuthService` itself (Firebase calls) has no unit tests.
