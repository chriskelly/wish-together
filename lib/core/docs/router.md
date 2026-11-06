# Router

Scope: the `go_router` graph, the redirect contract that gates onboarding, and
the URL allowlist behind Universal Links. Read before adding a route or changing
a redirect. Paths are relative to `lib/core/`, then to the repository root.

`createRouter` builds a `GoRouter` whose `refreshListenable` re-evaluates on auth changes
and whose `redirect` delegates to the pure function `handleRedirect(uriString, AuthSession,
{UserRepository?})`. Keeping the logic in `handleRedirect` is what makes it unit-testable.
`AuthListenable` is the only app-wide auth subscription: on every transition it calls
`AppLog.setUserRef(uid)` and emits an `AuthStateEvent` (including `signedOut`), tolerating a
missing `AppLog` so tests can build a router with only a `UserRepository`. It listens to the
session's `uidChanges` (ids, not Firebase users) and reads `providerIds` from the session at
the moment of the change, because the stream cannot carry the provider list.
`RouteChangeRecorder` listens to the router's own route-information notifier, because
`GoRouter.observers` sees only Navigator push/pop and would miss `go()`, redirects and deep
links. It records one `routeChanged` per *pattern* change, seeded with the initial location, so
startup and redirect re-entry are not double-logged; two ids on the same route are one record by
design. The value is the *requested* location (go_router leaves the notifier at the pre-redirect
URI), so a signed-out `/wishlist/abc` records `/wishlist/:id` before the router shows login.
`createRouter` takes an optional `userRepository`, defaulting to
`getIt<UserRepository>()`; `lib/main.dart` relies on that default, while tests and alternative
composition roots may inject one. It also takes an optional `initialLocation` (a path such
as `/join?group=123`), which is how an iOS Universal Link starts the router.
`handleRedirect`'s fallback is for direct callers and tests.

## Invariants

- A logged-out user is redirected to `/login`, preserving the original destination in the
  `redirect_to` query parameter. `/login` and `/verify` never redirect while logged out.
- A logged-in user whose `User.hasDisplayName` is false — no display name, or one with no
  content once trimmed — is redirected to `/profile` (also preserving `redirect_to`), so
  onboarding completes before any other page renders.
- A logged-in user on `/login` is sent to `redirect_to` or `/`.
- Every redirect for a logged-in user calls `UserRepository.getOrCreateUser`, so the
  `users/{uid}` document is created lazily on first navigation.
- Web routes are **real paths** (`usePathUrlStrategy`): `/join?group=…`, `/group/<id>`,
  `/wishlist/<id>`. The router receives in-app locations (path + query) only; hash URLs are
  not supported (`docs/deep-links.md`).
- `redirect_to` is forwarded verbatim as a location; it is never normalized from a fragment
  or an absolute URL.

## How it is tested

- `test/core/router_test.dart` drives `handleRedirect` across the logged-out /
  logged-in-without-name / logged-in-with-name matrix, including join-link redirects, with
  a mocked `AuthSession` and `UserRepository`; it also pins the `getIt<UserRepository>()`
  fallback.
- `test/core/app_urls_test.dart` pins the Universal-Link mapping: https/host/path allowlist,
  query encoding, and the debug-vs-release host sets.
- `test/core/deep_links_test.dart` pins the startup queue and warm-link forwarding, including
  the no-replay rule.
- `test/core/deep_link_config_test.dart` pins the AASA content, both hosting AASA settings,
  the entitlements split, and the disabled engine handler.
