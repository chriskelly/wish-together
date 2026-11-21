# Auth platform prerequisites

Scope: the Firebase and Apple configuration each sign-in method needs, and the
compile-time stubs that keep one codebase building on every platform. Read
before enabling a provider or testing auth on a deployed host.

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

The Sign in with Apple button is rendered **only on iOS** — `LoginPage` gates it
with the pure `shouldShowAppleSignInButton(isWeb:, platform:)` predicate, which web
(where `defaultTargetPlatform` is the browser's OS) and Android both fail. This satisfies
App Store guideline 4.8 on the iOS app without pulling in the Apple Service ID / web flow.
`test/features/auth/presentation/login_page_test.dart` pins that platform-gate truth table (iOS
shows; web, Android, macOS hide).

`lib/features/auth/data/google_sign_in_stub.dart` is a compile-time stub that supplies only
`renderButton()`, so `login_page.dart`'s `web_only.renderButton()` reference compiles on
non-web platforms; the real web button comes from `google_sign_in_web`. `AuthService` always
imports the real `google_sign_in` package.

On web, `GoogleSignIn.instance.initialize(clientId: ...)` must complete before the GIS button
renders; `LoginPage` starts it when the page opens. `web/index.html`'s
`google-signin-client_id` meta tag is the fallback client id, and a failed or timed-out
initialization replaces the button with a message offering a reload or phone sign-in (a
second initialize is not allowed). On iOS the client id stays null in Dart:
`google_sign_in_ios` reads the bundled
`GoogleService-Info.plist`, whose reversed client id is the URL scheme in `Info.plist`.
Android passes the web client id as `serverClientId` so Firebase receives an idToken.

Account deletion re-authenticates for real, so it cannot be exercised on a preview channel:
validate it on the **staging** site (or live) with a throwaway account for each provider
(Google, Apple, phone).
