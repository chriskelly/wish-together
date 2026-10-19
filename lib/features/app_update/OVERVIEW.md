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
| `evaluateUpdate(...)` / `UpdateDecision` | `domain/update_decision.dart` | Pure decision: given the running and minimum builds, blocked or not. |
| `AppUpdateService` | `data/app_update_service.dart` | Remote Config + `PackageInfo`; injectable; fails open. |
| `UpdateRequiredPage` / `UpdateRequiredApp` | `presentation/update_required_page.dart` | The blocking screen and the `MaterialApp` that hosts it. |

## Remote Config keys

| Key | Type | Default | Meaning |
| --- | ---- | ------- | ------- |
| `min_supported_build` | int | `0` | Minimum iOS build (`CFBundleVersion`). `0` leaves the gate inert. |
| `update_message` | string | code default | Message shown on the blocking screen. |
| `update_url` | string | empty | App Store URL opened by "Update now". The button is disabled while empty. |

## Behaviour

- **Kill switch:** the default minimum is `0`, so the gate does nothing until a
  maintainer deliberately raises the key.
- **Fail open:** a Remote Config fetch that throws or exceeds the 3-second
  timeout is treated as "no minimum". A missing or unparseable build number
  also never blocks.
- **No web build gate:** the web build number is not comparable with the iOS
  `CFBundleVersion`, so the service refuses to gate anywhere but iOS. Web gets
  cache-busting headers instead (`firebase.json` / `firebase.staging.json`), but
  a warm service-worker cache can still run an old bundle until the page is
  reloaded.
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
   `min_supported_build` to that integer, and set `update_url` to the App Store
   listing. Adjust `update_message` if needed.
4. Publish the changes.
5. Verify on a device: a build below the minimum shows the blocking screen; a
   build at or above it starts normally.
6. Roll back by setting `min_supported_build` to `0` and publishing again.

A Remote Config outage leaves the app usable. That is deliberate: a network
failure must never lock a user out.
