---
name: appstore-screenshots
description: Capture, verify and upload the six iPhone screenshots for the App Store listing from the real app on an iOS simulator, signed in against the staging Firestore database. Use when replacing the listing screenshots, refreshing them after a redesign, adding a localised set, or recovering an upload rejected with "File dimensions are invalid".
---

# App Store screenshots

The listing shows six captures of the real app, signed in as a fictional viewer
against the **staging** Firestore database, with a clean 9:41 status bar and no
dev banner. The last two are a pair — the same wishlist with claim status shown
and hidden — because spoiler-free claiming is the product's difference.

No PNG and no entrypoint is committed. `capture.sh` builds a private entrypoint
that signs in with a dev token, points Firestore at `staging` and mounts the
production app shell on one route; the simulator supplies the device frame and
status bar that a browser capture cannot.

This skill contains:

| File | Purpose |
| --- | --- |
| `capture.sh` | build one route's entrypoint, launch it, capture one PNG, strip alpha |
| `appstore_shots.dart` | entrypoint template, copied to `lib/dev/scenarios/local/` (gitignored) |
| `verify.sh` | dimensions, alpha, OCR content and palette gate |
| `ocr.swift` | macOS Vision OCR, used by `verify.sh` |
| `colors.swift` | dominant colours, used by `verify.sh` |
| `bbox.swift` | locate a text element's row in a capture (it does not find icons) |

## Check the required size before capturing

Apple's required iPhone slot is **iPhone with Dynamic Island (medium display)**:
**1206 × 2622** portrait, or 1179 × 2556. It changed in October 2026. A Pro Max
capture (1320 × 2868) is valid only in the separate, **optional** large-display
slot; the required slot rejects it.

Read the live spec before capturing — the numbers above were verified on
2026-11-05 and Apple changes them:
<https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications>

A wrong size is not caught until upload. App Store Connect answers "File
dimensions are invalid." and links to that page with no detail about which rule
failed. Two habits prevent it:

- **Capture on a medium device** — iPhone 16 Pro or 17 Pro — so the PNG is the
  upload size natively. Capturing on a Pro Max writes 1320 × 2868 and needs a
  downscale.
- **Screenshots must have no alpha.** Simulator PNGs are RGBA even though they
  look opaque. `capture.sh` flattens with `-pix_fmt rgb24`; App Store Connect
  rejects transparency outright.

## Pipeline

```
  scripts/seed-demo.mjs ──► staging Firestore (demo- ids)
  scripts/dev-token.mjs ──► token for the synthetic viewer (about an hour)

  capture.sh ──► build entrypoint (one build per route)
             ──► simctl install / launch / screenshot
             ──► strip alpha, warn if the size is not 1206x2622
             ──► PNG in $TMPDIR/appstore-shots, outside the repository

  verify.sh  ──► dimensions, alpha, OCR strings, palette

  App Store Connect ──► create the version, add the six in order
  release action ─────► build, upload, submit (it never touches screenshots)
```

## 1. Prepare staging

The seed targets the **named `staging` database**; never `(default)`, which is
production. The token identifies a uid, not a database — the entrypoint is what
points Firestore at `staging`. The staging database shares production Auth, so
use a synthetic uid, never a real account, and never exercise in-app account
deletion with it.

```sh
npm --prefix scripts ci

# Seed the demo cast. The viewer uid is synthetic; the first custom-token
# sign-in creates that Auth user.
GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
  npm --prefix scripts run seed:demo -- --yes --database staging \
  --viewer-uid appstore-screenshots --viewer-name Shawn

# Mint a token (about an hour). The script prints a token plus a paste-ready
# command; keep only the JWT line, never the last line of its output.
GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
  npm --prefix scripts run --silent dev:token -- \
    --uid appstore-screenshots --database staging \
  | grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' \
  | head -1 > /tmp/wt-token
```

The seed writes only `demo-` document ids, and one cast backs every screen.
Remove it when the captures are done:

```sh
GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
  npm --prefix scripts run seed:demo -- --yes --clean-only --database staging
```

## 2. Boot the simulator

A medium device, light appearance. The status bar override is what removes the
real clock and battery from the listing:

```sh
xcrun simctl boot "iPhone 16 Pro"          # or boot it in DeviceHub
xcrun simctl ui booted appearance light
xcrun simctl status_bar booted override \
  --time "9:41" --dataNetwork wifi --wifiBars 3 \
  --cellularBars 4 --batteryState charged --batteryLevel 100
```

`capture.sh` uses the booted device when exactly one is booted; with several it
stops and asks for `WT_UDID` rather than guessing, because a Pro Max writes the
wrong size.

## 3. Capture the six

Every capture is one build (the route is a compile-time `--dart-define`), so
expect a few minutes per screen. Run from the repository root; PNGs land in
`$TMPDIR/appstore-shots` (override with `WT_OUT_DIR`), never in the working
tree:

```sh
WT_TOKEN_FILE=/tmp/wt-token .agents/skills/appstore-screenshots/capture.sh \
  01-the-carters /group/demo-group-family
```

| File | Route | State |
| --- | --- | --- |
| `01-the-carters.png` | `/group/demo-group-family` | group, shared wishlists and members |
| `02-the-knowles-family.png` | `/group/demo-group-knowles` | a group the viewer joined, not owns |
| `03-home.png` | `/` | both home sections |
| `04-sasha-birthday.png` | `/wishlist/demo-wishlist-sasha-birthday` | the viewer's claim on `Perfume: oud`; scroll to it |
| `05-shawns-birthday.png` | `/wishlist/demo-wishlist-viewer-birthday` | claim status **shown** (`Available`, `2 of 3 claimed` on the multi-claim overcoat) |
| `06-shawns-birthday-spoiler-free.png` | `/wishlist/demo-wishlist-viewer-birthday` | the default load, claim status **hidden** |

`WishlistDetailsPage` starts spoiler-free, so `06` needs no extra flag. `05` is
one tap on the app bar's claim-status action, synthesized as a real pointer event
by the entrypoint rather than a GUI click:

```sh
WT_TOKEN_FILE=/tmp/wt-token \
WT_EXTRA_DEFINES="--dart-define=WT_SHOT_TAP=330,91" \
  .agents/skills/appstore-screenshots/capture.sh \
  05-shawns-birthday /wishlist/demo-wishlist-viewer-birthday 14
```

The claim-status action is the first of the two end-aligned app-bar icons, so
its centre is about `width - 72` logical points: **330** on the 402-point medium
device, not the 368 that belonged to the 440-point Pro Max. Tapping the second
icon opens the edit form instead, and the capture then fails `verify.sh` with
`ocr MISS: 2 of 3 claimed`. `bbox.swift` finds *text*, not icons — it gives the
title's row (y ≈ 91) but you still have to place the x from the device width.
`WT_SHOT_SCROLL=<logical px>` scrolls the page the same way; `04` uses whatever
value puts the claimed row on screen, around 480 in the current design.

## 4. Verify before uploading

```sh
.agents/skills/appstore-screenshots/verify.sh "${WT_OUT_DIR:-${TMPDIR:-/tmp}/appstore-shots}"
```

It fails on:

- a missing file, an extra capture left from an earlier run, or a set that is not
  the six in the table above;
- dimensions other than 1206 × 2622, or any alpha channel;
- an OCR string a screen must show, or one it must not (`Dev session`,
  `Exception`, `Something went wrong`, `Retry`);
- `06` containing `Available`, `Claimed` or `2 of 3 claimed`, or `05` and `06` being identical;
- a dominant colour that is neither the cream canvas nor the item-card surface,
  or the old blue (`#2196F3` / `#1976D2`) returning.

The palette check guards the current design; adjust its colours when the palette
changes rather than deleting it.

## 5. Upload

1. In App Store Connect, create the version (or open the editable draft) and add
   the six files **in table order**. A new version starts with the previous
   version's screenshots, so replace all six rather than assuming they carried
   over.
2. Then release. The App Store lane passes `skip_screenshots: true`, so it
   neither uploads nor deletes screenshots — create the version first, because
   the lane submits immediately and a later run would not add them. An editable
   draft is allowed to be the version being released.
3. The lane takes What's New from `fastlane/metadata/en-US/release_notes.txt`,
   clears that file on success, and resolves the build number from App Store
   Connect. See `docs/release.md`.

## Traps

- **Tokens last about an hour.** A capture that lands on the login page is an
  expired token, not a sign-out bug. `capture.sh` rejects a token file with no
  JWT-shaped line.
- **App Check is not active in the entrypoint.** Captures rely on enforcement
  being off for the staging host. If enforcement is turned on, every screen
  becomes a permission-denied error rather than a data problem.
- **The web dev session is not a listing capture.** It shows a `Dev session`
  label, has no device status bar, and its colours differ. Use the simulator.
- **A localised set repeats the whole pipeline per language.** Screenshots are
  per locale and per display type; the English set does not cover another
  locale's App Store page.
- **The entrypoint is a template, not shipped code.** If `setupServiceLocator`
  or `WishTogetherApp` changes signature, update the copy in the skill so the
  next capture compiles; nothing in `lib/` imports it.
