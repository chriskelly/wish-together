---
name: preview-auth
description: Enable real phone and Google sign-in on ONE Firebase Hosting preview channel (or the staging site) by allowlisting its exact host in the three Firebase lists, and remove it again afterwards. Local, human-invoked, using the operator's own credentials. Use when a preview URL needs real auth (phone OTP or Google) for manual validation, or when tearing that access back down.
---

# Preview auth

Make **one** preview host work for real sign-in — phone OTP and Google — then
undo it. This is the local answer to the "previews are UI-only" rule: preview
channels cannot be allowlisted in CI without widening a shared public API key, so
the operator does it here, by hand, for a single host.

> **This mutates production Firebase config** (Auth authorized domains and the
> browser API key's HTTP referrers). It is a **local, human-invoked** action.
> **Never run it in CI**, never commit its output, and never add a wildcard
> referrer. Use the staging site (`docs`/`AGENTS.md` → "Staging environment")
> when you want a persistent, always-authorized host instead.

## The three lists

Real sign-in on a non-live host needs all three; each is independent, and the
mechanism (`hosting:channel:deploy`) only auto-fills the first.

| # | List | Where | Automated here? |
|---|------|-------|-----------------|
| 1 | **Auth → Authorized domains** | Firebase project, Identity Toolkit admin config | Yes (usually already set by the channel deploy) |
| 2 | **Browser API key → HTTP referrers** | Google Cloud API Keys API | Yes (exact host, no wildcard) |
| 3 | **Google OAuth web client → Authorized JavaScript origins** | Google Cloud Console | **No** — no public API; the script prints the exact steps |

## Prerequisites

- Run from the repo root (the script reads the web `apiKey` from
  `lib/firebase_options.dart`).
- `curl`, `jq`, and an authenticated `gcloud` (`gcloud auth login`) whose account
  can update the project's API key (`apikeys.keys.update`) and Auth config
  (`firebaseauth.configs.update`). If a call returns 403, you lack that role.
- The preview host from `firebase hosting:channel:list --json` (or the URL that
  `ci-web.yml` commented on the PR), e.g.
  `wish-together-project--pr-12-abcde.web.app`.

## Usage

```sh
scripts=.agents/skills/preview-auth/scripts/preview-auth.sh

# 1. See the current state of lists 1 and 2 (read-only).
"$scripts" list

# 2. Dry run: print the exact change and write a backup. Writes nothing else.
"$scripts" add wish-together-project--pr-12-abcde.web.app

# 3. Apply it, then do the Google step the script prints (list 3).
"$scripts" add wish-together-project--pr-12-abcde.web.app --apply

# 4. Afterwards, remove the host again (reversible).
"$scripts" remove wish-together-project--pr-12-abcde.web.app --apply
```

The script preserves `apiTargets` and **every** existing referrer, adds or
removes only the exact `https://<host>/*` entry, sends the key's `etag` so a
concurrent change fails closed, and backs the old key JSON up to
`$PREVIEW_AUTH_BACKUP_DIR` (default `~/.cache/wishtogether-preview-auth`). Read
the backup before retrying if a PATCH fails.

## Validating the preview

- **Flutter web renders to a canvas.** Enable the semantics tree (for example
  `SemanticsBinding.instance.ensureSemantics()` in a debug build) so Playwright
  can address widgets by label instead of pixel coordinates.
- **Automation cannot pass phone auth by itself.** Google serves a **visible
  reCAPTCHA** to automated browsers, and a scripted click cannot complete it.
  Either use `appVerificationDisabledForTesting` + a console **test phone
  number** (an app-code change, for debug builds only), or plan **one human
  pass** on the real path — that pass is the last mile.
- Phone numbers for testing: Firebase Console → **Authentication → Sign-in
  method → Phone → Phone numbers for testing** (bypasses SMS, fixed code).
- Once list 3 is set, Google sign-in completes in a normal browser.

## Scope

This is for **one-off, reversible** preview validation. The persistent staging
site and its committed workflow are separate. The browser-key referrer *scope*
decision (a broad `https://*.web.app/*`) is deliberately **not** taken here — no
wildcard — and remains a PR 8 security call.
