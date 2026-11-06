# Deep links (Universal Links)

Scope: how an iOS Universal Link reaches a route, and the web files and
entitlements that must agree with it. Read before changing a link path, the AASA
file, or a hosting config.

The app receives iOS Universal Links through `app_links`, not Flutter's built-in handler
(`FlutterDeepLinkingEnabled` is **false** in `Info.plist`; two handlers would navigate
twice).

- The canonical URL is `<origin>/join?group=<id>` (plus `/group/<id>` and `/wishlist/<id>`).
  Web uses `usePathUrlStrategy()`, so routes are real paths. Legacy `/#/…` hash links are
  **not** supported and land on `/`.
- `web/.well-known/apple-app-site-association` is deployed as a static file and lists only
  those three paths. Both `firebase.json` and `firebase.staging.json` set
  `"appAssociation": "NONE"` (otherwise Hosting generates a `/*` file) and serve the AASA
  with `Content-Type: application/json`. The static file wins over the `**` rewrite; do not
  add an AASA rewrite, and keep the hosting `headers` blocks in sync.
- `app_links` captures the URL at scene connection, so a link received while Firebase, App
  Check, or the update gate is still running is queued. `lib/core/deep_links.dart` hands the
  queued location to `createRouter(initialLocation:)` and later links to `go_router`.
  `lib/core/app_urls.dart` is the pure allowlist: https only, our hosts only, the three AASA
  paths only.
- **Entitlements:** `Runner.entitlements` (Release/Profile/TestFlight) carries
  `applinks:wishtogether.gift`; `Runner-Debug.entitlements` carries
  `applinks:wish-together-staging.web.app` only. A release build must never authorize the
  staging host.
- **Signing:** the App ID needs the Associated Domains capability, and the distribution
  `match` profile must be regenerated (`fastlane match appstore --force`) after the
  entitlement is added, or the TestFlight lane fails signing. This is a human step, like
  Sign in with Apple.
- **Device testing:** iOS debug builds cannot cold-launch standalone (they need Xcode), and
  `app_links` also cancels registration when it is not attached to the debugger. A debug
  build therefore validates **warm** links only; cold start is validated with a Release or
  TestFlight build after the narrow production AASA is live.
- Apple's AASA CDN caches the file; first-time verification can take hours. Simulators do not
  open Universal Links, and typing the URL in Safari opens the website by design.
