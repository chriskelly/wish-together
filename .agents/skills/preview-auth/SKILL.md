---
name: preview-auth
description: Enable real phone and Google sign-in on ONE Firebase Hosting preview channel (or the staging site) by allowlisting its exact host in the three Firebase lists, and remove it again afterwards. Local, human-invoked, using the operator's own credentials. Use when a preview URL needs real auth (phone OTP or Google) for manual validation, or when tearing that access back down.
---

# Preview auth

Make **one** preview host work for real sign-in — phone OTP and Google — then
undo it. CI never allowlists a preview host; an operator may do it here, locally,
for one host at a time, and revert afterwards. The persistent, always-authorized
host is the staging site (see `AGENTS.md` → "Staging environment").

> **This mutates production Firebase config** for the project in `.firebaserc`
> (Auth authorized domains and the browser API key's HTTP referrers). It is a
> **local, human-invoked** action. **Never run it in CI**, never commit its
> output, and never add a wildcard referrer.

The script only accepts hosts of this project (`<project>--<channel>-<id>.web.app`
or `wish-together-staging.web.app`), refuses to remove the live or staging host,
refuses to create a referrer restriction on an unrestricted key, and refuses to
write an empty referrer list — each of those would cause a production outage for
a "safe" helper.

## The three lists

Real sign-in on a non-live host needs all three; each is independent, and the
mechanism (`hosting:channel:deploy`) only auto-fills the first. **The script
automates lists 1 and 2; list 3 has no public API, so it prints the exact manual
steps.**

| # | List | Where | Handled here? |
|---|------|-------|---------------|
| 1 | **Auth → Authorized domains** | Firebase project, Identity Toolkit admin config | Automated (usually already set by the channel deploy) |
| 2 | **Browser API key → HTTP referrers** | Google Cloud API Keys API | Automated (exact host, no wildcard) |
| 3 | **Google OAuth web client → Authorized JavaScript origins** | Google Cloud Console | **Manual** — the script prints the add/remove steps |

## Prerequisites

- Run from anywhere inside the repo (the script finds the repo root and reads the
  web `apiKey` from `lib/firebase_options.dart`).
- `curl`, `jq`, and an authenticated `gcloud` (`gcloud auth login`) whose account
  can update the project's API key (`apikeys.keys.update`) and Auth config
  (`firebaseauth.configs.update`), and use the project as a quota project
  (`serviceusage.services.use` — Owner/Editor have it). If a call returns 403, you
  lack one of those. The script sends `x-goog-user-project` on the Identity
  Toolkit calls (which require it for user credentials).
- The preview host from `firebase hosting:channel:list --json` (or the URL that
  `ci-web.yml` commented on the PR) — **copy the exact host**, e.g.
  `wish-together-project--pr-12-abcde.web.app`.

## Usage

```sh
scripts=.agents/skills/preview-auth/scripts/preview-auth.sh

# 1. See the current state of lists 1 and 2 (read-only).
"$scripts" list

# 2. Dry run: print the exact change. Firebase is not modified.
"$scripts" add wish-together-project--pr-12-abcde.web.app

# 3. Apply it, then do the Google step (list 3) the script prints.
"$scripts" add wish-together-project--pr-12-abcde.web.app --apply

# 4. Afterwards, remove the host again (lists 1 and 2), and delete the Google
#    origin the removal step prints (list 3).
"$scripts" remove wish-together-project--pr-12-abcde.web.app --apply
```

The script preserves `apiTargets` and **every** existing referrer, changes only
the exact `https://<host>/*` entry (no wildcard, no reordering), sends the key's
`etag` so a concurrent change fails closed, skips the API call when nothing would
change, and backs the current key JSON up (on `--apply`) to
`$PREVIEW_AUTH_BACKUP_DIR` (default `~/.cache/wishtogether-preview-auth`). If a
PATCH fails, read the backup and the printed revert command before retrying.

The pure logic (set math, the host guard, and URL construction) is covered by
`scripts/preview-auth.test.sh` — stubbed `curl`/`gcloud`, no network:

```sh
bash .agents/skills/preview-auth/scripts/preview-auth.test.sh
```

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

This is for **one-off, reversible** preview validation, per host. The persistent
staging site and its committed workflow are separate. The broad
`https://*.web.app/*` referrer — which would cover every preview but widens a
public key — is deliberately **not** used here; widening the browser key is a
security decision that needs review, not a convenience.
