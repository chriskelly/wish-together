# App update — Overview

The startup gate that can force an outdated client onto a newer build. When it
blocks, the normal app is never mounted: the blocking screen is its own
`MaterialApp`, outside the router.

## Responsibility

- Read `min_supported_build` from Firebase Remote Config at startup.
- Compare it with the running iOS build number (`CFBundleVersion`).
- Mount a blocking screen instead of the app when the running build is below
  the minimum.

It is a **policy nudge, not a security control**. A modified client can bypass
it. Its job is to keep a client that no longer understands a server contract
from breaking quietly.

## Key types

| Type | File | What it is |
| ---- | ---- | ---------- |
| `evaluateUpdate(...)` / `UpdateDecision` / `canStartFromRetry` | `domain/update_decision.dart` | Pure policy: given the running and minimum builds, blocked or not, and whether the answer is conclusive. |
| `parseUpdateUrl(...)` | `domain/update_url.dart` | Pure allowlist for store URLs (`https` / `itms-apps`, non-empty host). |
| `AppUpdateService` | `data/app_update_service.dart` | Remote Config + `PackageInfo`; injectable; fails open; bounds the whole check. |
| `UpdateRequiredPage` / `UpdateRequiredApp` | `presentation/update_required_page.dart` | The blocking screen (scrollable, so a long message cannot hide the action) and the `MaterialApp` that hosts it. |

## Remote Config keys

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `min_supported_build` | int | `0` | Minimum iOS build (`CFBundleVersion`). `0` leaves the gate inert. |
| `update_message` | string | code default | Message shown on the blocking screen. |
| `update_url` | string | empty | Store URL for "Update now". Must be `https` or `itms-apps` on `apps.apple.com` or `itunes.apple.com`. |

## Behaviour

- **Kill switch:** the default minimum is `0`, so the gate does nothing until a
  maintainer deliberately raises the key.
- **Fail open:** a Remote Config fetch that throws or exceeds the 3-second
  timeout is treated as "no minimum". A missing or unparseable build number
  also never blocks. The update check itself is bounded (5 seconds) so a hung
  plugin cannot stop the first frame; Firebase initialization and App Check
  activation run before it and are not part of that bound.
- **A confirmed block stays blocked:** "Check again" may only replace the
  blocker with the app when the retry is both allowed *and* conclusive. A retry
  that merely fails open (offline, timeout) must not let a stale user through.
  The screen disables the retry while it is in flight and says "Still not
  available" when it did not help.
- **No dead-end blocks:** the gate refuses to block when `update_url` is empty
  or is not a usable Apple App Store URL, and logs why. Set `update_url` before
  raising the minimum. If the store still cannot be opened on the device, the
  screen shows manual instructions instead of failing silently.
- **No web build gate:** the web build number is not comparable with the iOS
  `CFBundleVersion`, so the service refuses to gate anywhere but iOS. Web gets
  a `Cache-Control: no-cache` rule on `**` (revalidation, covering SPA deep
  links; unchanged files still return 304), but a warm service-worker cache can
  still run an old bundle until the page is reloaded.
- **Maintainer bypass:** debug builds always bypass. A release build can bypass
  with `--dart-define=WT_DISABLE_UPDATE_GATE=true`. Neither is reachable from
  the UI. To exercise the blocking screen locally, run a release build (or the
  widget test) rather than `flutter run`.

## Runbook — raising the minimum

1. Decide the lowest iOS build that speaks the new server contract. It is the
   App Store Connect / TestFlight build number, **not** the pubspec `+N`.
2. Confirm that build is actually available to users (App Store release is
   live, or the TestFlight group can update).
3. In Firebase Console → Remote Config for `wish-together-project`, set
   `min_supported_build` to that integer, set `update_url` to the App Store
   listing (`https://apps.apple.com/app/id…`), and adjust `update_message` if
   needed. A block is refused unless `update_url` is a usable Apple App Store
   URL.
4. Publish the changes.
5. Verify on a device: a build below the minimum shows the blocking screen; a
   build at or above it starts normally.
6. Roll back by setting `min_supported_build` to `0` and publishing again.
   Clients already on the blocking screen recover on their next successful
   check (the "Check again" button).

A Remote Config outage never blocks a user who was not already confirmed stale;
a user already on the blocking screen stays blocked until a check succeeds.
That is deliberate: a network failure must never lock a new user out.
