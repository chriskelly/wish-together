# Auth flows

Scope: how a user signs in with phone, Google or Apple, how the profile is
saved, and how account deletion runs. Read before changing a provider, a sign-in
page, or the deletion cascade. Paths are relative to `lib/features/auth/`, then
to the repository root.

## Responsibility

- Phone OTP, Google sign-in, and Sign in with Apple; and sign-out.
- In-app account deletion: re-authentication for the current provider, the
  data cascade, and deleting the auth account.
- The `users/{uid}` profile document.
- Enforcing a display name before the rest of the app is reachable.

## Layout

The area is split into `domain/`, `data/`, `application/` and
`presentation/`. List the current files with
`find lib/features/auth -name '*.dart' | sort`.

## Sign-in and deletion types

- `AuthService implements AuthSession` — wraps `FirebaseAuth`, `GoogleSignIn`, and
  `SignInWithApple`. Adds `googleSignIn`, `isWeb`, the sign-in and
  re-authentication flows, `signInProvider()` and `deleteAccount()`.
  `supportsAccountDeletion` is `true`. Google sign-in is completed by
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
  outcome with no code (a breadcrumb, not an auth-failure event). Provider-SDK
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
  dialog), then the use case. `ProfilePage` renders it only when the session reports
  `supportsAccountDeletion`, so a session that cannot delete an account does not offer the
  control at all. The section itself keeps `AuthService`, because the
  re-authentication flows it drives are not part of the session.
- `phoneAuthErrorMessage(...)` — maps a phone `FirebaseAuthException` to a short user-facing
  message, including the "domain not authorized" case.
- `normalizeUsPhoneNumber(...)` / `isCompleteSmsCode(...)` — the phone pages' input
  rules: ten digits with optional separators (no country code) become E.164, and
  only a six-digit code enables Verify.
- `appleAuthErrorMessage(...)` — maps an Apple sign-in failure (Apple-sheet exceptions or a
  Firebase `FirebaseAuthException`) to a short user-facing message. Returns `null` when the
  user canceled the Apple sheet, so the UI stays silent.

## Sign-in flow

Logged out: `LoginPage` requests an SMS code through `AuthService.startPhoneVerification`,
which branches once on `kIsWeb` and completes when the platform has reported an outcome.
The Send button stays disabled until that future completes: the raw `verifyPhoneNumber`
future returns as soon as the request is handed to the platform, so a guard tied to it
re-enabled Send while the SMS was still on its way, and each extra tap sent another code and
opened another code page. A platform that never reports fails with a `TimeoutException`
**and** an `authState` record (`code: 'timeout'`), and the page tells the user to try again.

The number is normalised on the device first: `LoginPage` accepts ten digits with spaces,
dashes, dots or parentheses and rejects anything else — a country code, an eleventh digit or
a letter — with a message, before any request reaches Firebase. `VerificationPage` keeps
Verify disabled until the code is six digits, submits it trimmed, and ignores a second tap
while a confirmation is in flight.

- **Web:** `AuthService.startWebPhoneSignIn` calls `FirebaseAuth.signInWithPhoneNumber`
  (the documented web API, which manages the reCAPTCHA challenge) and returns a verification
  id. `LoginPage` navigates to `VerificationPage` with that id as `extra` (carrying
  `redirect_to` forward). `VerificationPage` calls `AuthService.confirmPhoneCode`, which
  confirms the stashed `ConfirmationResult` with the SMS code.
- **Native:** `AuthService.verifyPhoneNumber` reports progress through callbacks, which
  `startPhoneVerification` turns into a `PhoneVerification`. A sent code navigates to
  `VerificationPage`; an auto-verified credential signs the user in directly;
  `confirmPhoneCode` builds a `PhoneAuthProvider` credential and signs in with it.

`VerificationPage` is pushed on top of `LoginPage`, so its `PrimaryAppBar` keeps the
implied back action that returns to the number the user typed, still in the field. The
push is imperative, so the web address bar keeps showing `/login` while the code page is
up, and a reload returns to login — the page was never reloadable anyway, since it needs
the verification id passed as route `extra`. Leaving the page discards a pending web
sign-in, and a successful confirmation drops it too, so neither can be reused; a
rejected code keeps it so the user can retry. The page also shows the session's support
code: a wrong or expired code is an auth failure the user may have to report, and it is
the one screen where that failure is most likely.

On iOS, the Apple button (from `sign_in_with_apple`) calls `AuthService.signInWithApple`, which
exchanges the Apple identity token for a Firebase session. Email lands on the Firebase user
via the identity token and flows into the profile document through the router; Apple only
returns the name/email on the *first* sign-in, and this flow does not persist the name (the
onboarding page still collects a display name).

On web, the Google button is rendered by `google_sign_in_web` and `AuthService` handles the
credential. Either path triggers the router redirect: no name → `/profile`, otherwise
`redirect_to` or `/`.

## Deleting an account

Deleting an account starts on `ProfilePage` — reachable for any signed-in user, including one
who has not chosen a display name yet — and never touches the router's redirect rules:
`DeleteAccountSection` confirms, re-authenticates for the session's provider, runs
`DeleteAccountUseCase`, and returns to `/login`. Because `user.delete()` clears the Firebase
session, `AuthListenable` drops the signed-in state at the same moment; the
`context.go('/login')` matches what the redirect would do anyway.

## How it is tested

- `test/features/auth/data/auth_service_test.dart` — the phone-auth platform split with
  mocked `FirebaseAuth` / `ConfirmationResult` (web uses `signInWithPhoneNumber` + `confirm`;
  native uses `signInWithCredential`), plus `signInWithApple` with an injected
  `AppleCredentialFetcher` (credential exchange, the SHA-256 nonce relationship, the missing
  identity token, and error propagation). It also covers `deleteAccount` (delete then revoke the
  Google grant, the signed-out no-op, and a failed revocation still counting as success), every
  re-authentication path (native Google credential, web Google popup, Apple credential, phone
  code, platform-verified phone credential), `startPhoneVerification` (instant verification,
  code sent, auto-retrieval timeout, failure, double-fire, timeout, and the web path),
  `signInProvider`, and `providerIds`.
- `test/features/auth/data/phone_auth_error_test.dart` — the phone error-code → message mapper.
- `test/features/auth/data/phone_input_test.dart` — the phone input rules: accepted
  separators, rejection of a country code, an eleventh digit and non-digits, and the
  six-digit SMS-code shape.
- `test/features/auth/data/apple_auth_error_test.dart` — the Apple error mapper, including the
  silent-on-cancel case and every handled Firebase code.
- `test/features/auth/data/reauth_provider_test.dart` — the provider-preference truth
  table, including the token-over-linked-providers preference and Apple being skipped
  on web.
- `test/features/auth/data/delete_account_error_test.dart` — the deletion error mapper,
  including the silent-on-cancel cases.
- `test/features/auth/application/delete_account_use_case_test.dart` — the deletion
  cascade: owned wishlists deleted with their items, an owned group handed over or
  deleted, non-owned memberships removed, the profile document deleted, the auth
  account deleted **last**, the unauthenticated throw, and "a failed cascade never
  deletes the auth account".
- `test/features/auth/presentation/verification_page_test.dart` — the code page's support code
  (visible on arrival and after a failed confirmation), Verify staying disabled until six
  digits, a second tap ignored while a confirmation is in flight and the retry path reopening
  when it fails, the "sign-in expired" message when the page outlives the web sign-in, and the
  pending sign-in being discarded when the page closes.
- `test/features/auth/presentation/login_page_test.dart` — the phone flow leaving the code page
  on top of login through the real router, with a back action that returns to login and keeps
  the typed number; rejecting a malformed number before the service; sending formatted input as
  E.164; a second Send tap before the platform reports being ignored, Send re-enabling after a
  failure, and the timeout message.
