# Auth — Agent Guide

Authentication, first-run onboarding, and the pages that frame the signed-in app (home and
profile). Phone OTP, Google, Sign in with Apple, sign-out, and in-app account deletion.

## Rules

- **`users/{uid}` is a public document.** Every signed-in user can read it, so never add a
  private field; rules cannot restrict fields on read.
- The `users/{uid}` document id **is** the Firebase Auth uid.
- `AuthSession` is the narrow shell-facing type. Sign-in, re-authentication and deletion stay
  off it, so a Firebase-free implementation can stand in for the real service.
- Account deletion runs its Firestore cascade **before** `deleteAccount()`, because those writes
  need a live session; every step is idempotent so a retry restarts the flow.
- `HomePage` is a `ConsumerWidget`; its three uid-keyed reads are gated by
  `homeReadsEnabledProvider`, and `HomeSignOut` closes that gate before `AuthSession.signOut()`,
  so no read outlives the credential. Its rows are `HomeWishlistRow` and `HomeGroupRow`; the
  page imports no `service_locator.dart`.
- A `users/{uid}` read that throws or finds nothing shows an error with Retry — never an empty
  form, and never a silent fallback.

## Reference

- Sign-in and deletion mechanics → `docs/flows.md`
- Session, profile document, page read lifecycles → `docs/state.md`
- Onboarding, deletion order, provider revocation → `docs/invariants.md`
- Hosts, Apple capability, per-provider validation → `docs/platform.md`
