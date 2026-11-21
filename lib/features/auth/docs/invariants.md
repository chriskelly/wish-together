# Auth invariants

Scope: the non-obvious rules that keep sign-in, onboarding and deletion correct.
Read before changing the login page's layout, the deletion cascade, or a
provider revocation.

- **The login title is the hero's, not a paragraph.** `LoginPage` opens with the same full-bleed
  `BrandHero` Home uses, and authors the title as `'Welcome to\nWishTogether'`. Each line is
  scaled down to the width instead of wrapping, so "WishTogether" shrinks rather than breaking
  mid-word on a 320 px phone or at a 2.0 text scale. The hero is pinned, so it cannot shrink: it
  is dropped whenever the keyboard is up, because on a short landscape viewport it would push the
  form past the bottom; in portrait that only costs the form its breathing room. The scroll
  area's minimum height comes from the space left under the hero, not from the screen height.
  With the hero gone the page has to cover what the hero provided: it takes the top safe-area
  inset itself and sets the status-bar icon style for the canvas, which is the one reason the
  page carries an `AnnotatedRegion` when the hero already has one. `login_page_test` pins the
  320 px / 2.0-scale case (both lines whole, the wider one scaled) and the keyboard case (no
  overflow, form below the status bar, no hero).
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
- Deleting an account revokes a linked Google grant (`_googleSignIn.disconnect()`, not
  merely `signOut()`), so the provider-side access is dropped as well as the local
  session. The link is read before the auth user is deleted, because a phone or Apple
  re-authentication does not prove the account has no Google link. The revocation is
  best-effort under a bound: the account is already gone, and a hung third-party SDK
  must not leave the deletion unfinished.
- **Google Sign-In is initialized once.** v7's singleton allows one `initialize()`, and
  web throws on a second. `AuthService` memoizes the future per plugin instance (tests
  and the live dev session build the service repeatedly) and subscribes to the web
  event stream once per instance. A pending or failed initialization owns no Google
  session, so sign-out skips Google rather than waiting for it.
- **Google credentials carry only an idToken.** v7 separates authentication from
  authorization; the app requests no scopes and never builds a credential with an
  access token.
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
