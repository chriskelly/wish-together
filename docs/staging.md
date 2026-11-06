# Staging environment

Scope: what the staging site is, how it deploys, the one-time setup it needs,
and the demo dataset. Read before a staging dispatch, a rules rehearsal, or
seeding demo data.

`https://wish-together-staging.web.app` is a persistent pre-merge environment where
**real phone and Google sign-in work** (once the one-time allowlisting below is done). It
exists because per-PR preview channels are short-lived, so CI cannot allowlist them without
a wildcard (`https://*.web.app/*`) on the public browser API key; widening that key is an
open security decision that needs review, not a convenience. **CI never allowlists a
preview host.** An operator may allowlist ONE preview host locally and temporarily via
`.agents/skills/preview-auth/`, then revert. Staging is the one stable, authorized host.

Staging is a **second site in the production Firebase project** (`wish-together-project`).
It shares the production **Auth** — a staging sign-in is a real Auth account — but its
Firestore reads and writes go to the named **`staging`** database, not `(default)`. That
database is the **rules + data rehearsal target**: a candidate `firestore.rules` is
deployed there and exercised with seeded, real-shaped data while production is untouched.

## Deploying

- `.github/workflows/deploy-staging.yml` — manual (`workflow_dispatch`). Actions →
  **Deploy staging** → *Run workflow*, choose a ref (branch, tag, or SHA). It builds web,
  deploys the candidate rules to the `staging` database, verifies the deploy, then publishes
  that ref to the `wish-together-staging` site. Each run **overwrites** both, so only the
  latest dispatch matters. A cancelled run can leave new rules with the previous bundle
  (rules are published first).
- It deploys from `firebase.staging.json`, which names the `"site":
  "wish-together-staging"` Hosting config **and** `firestore.database = "staging"`. It never
  uses `firebase.json`, which keeps its single untargeted `(default)` config, so live
  (`master` → `firebase deploy --only hosting`) and the PR preview channels are unchanged.
  Hosting `headers` are duplicated in both files; change them together.
- The build reads the database id from that same file and passes
  `--dart-define=WT_FIRESTORE_DATABASE=<id>`. An **empty** define means production, so live,
  preview channels, and iOS builds are unaffected; only the staging dispatch sets it. The
  workflow fails unless the id is a named database (never `(default)`) and `rules` is
  `firestore.rules`; it also fails unless `build/web/main.dart.js` embeds the
  `wishtogether-firestore-target=<id>` marker emitted by `lib/core/firestore_target.dart` (the bare
  database id is not unique — Flutter's own code contains "staging").
- The rules deploy is `firebase deploy --only firestore:rules --config firebase.staging.json`.
  Afterwards the workflow **verifies** that the staging release source matches
  `firestore.rules` (guards against firebase-tools #9910 silently skipping an upload) and that
  the production release id did not change; either mismatch fails the run. The run summary
  records both rulesets. The staging database has **no composite indexes** today; if the app
  gains one, update all of these together: `firebase.staging.json` (`indexes`), the
  `scripts/staging-config.mjs` allowlist, the artifact upload, and the deploy `--only` target
  (`firestore:indexes`); the service account then needs `datastore.indexes.*`.
- **Config allowlist:** `firebase.staging.json` is candidate data, and `firebase deploy`
  executes `predeploy`/`postdeploy` hooks. The deploy job validates the downloaded config
  against a strict allowlist (`hosting`: `site`, `public`, `ignore`, `rewrites`, `headers`,
  `appAssociation` — required to be `NONE`; `firestore`: `database`, `rules`) and rejects
  every other key, so a candidate branch cannot run shell in the credential-holding job.
  Branches created before `appAssociation` became required must be rebased before a staging
  dispatch.
- **Trust model:** the deploy runs as two jobs. `build` has no secrets and runs the candidate
  code; `deploy` has the service account but runs **no candidate code** — it downloads the
  built artifacts, checks out the verification tooling from the workflow's own commit into
  `.verify`, and re-validates `firebase.staging.json` immediately before deploying it. Dispatch
  from `master` with `ref=<branch>` so the tooling itself is trusted; dispatching a branch runs
  that branch's workflow code with the credentials (the run warns when it is not `master`).
- **Pre-merge dispatch of this workflow or its scripts:** until a change to
  `.github/workflows/deploy-staging.yml`, to `scripts/staging-config.mjs`, or to any script the
  deploy runs (for example the `appAssociation` key the validator checks) is on `master`,
  dispatch that branch from **"Use workflow from" = the branch** *and* `ref=<branch>`; the
  dispatch runs master's copy of those steps, so an unknown config key fails closed and a new
  step is simply not exercised. Normal branches keep the documented `master` + `ref=<branch>`
  mode.
- Rules still reach production only through `.github/workflows/ci-rules.yml`
  (`docs/authorization.md`). Staging is the pre-merge rehearsal, not that path.
- `firebase.json` **must not** learn about the `staging` database: production rules/indexes
  are published from it, and adding a second database there would make
  `firebase deploy --only firestore:rules` ambiguous. The staging database lives only in
  `firebase.staging.json`.

## One-time setup

The database:

```bash
gcloud firestore databases create --database=staging --location=nam5 \
  --edition=standard --type=firestore-native --project wish-together-project
```

Billing is required for named databases and is already enabled here. A named-database rules
deploy also reads project metadata (`firebase.projects.get`) to attach the ruleset; if the
service account 403s there, grant that permission too.

The site must exist (`firebase hosting:sites:create wish-together-staging`, or Console →
Hosting → Add site). `firebase.staging.json` names it explicitly, so no `.firebaserc` target
is involved. Then allowlist the staging host, with the **exact** host (no wildcard), in each:

1. Firebase Console → **Authentication → Settings → Authorized domains** →
   `wish-together-staging.web.app`
2. Google Cloud Console → **APIs & Services → Credentials → the browser API key →
   Application restrictions → HTTP referrers** → `https://wish-together-staging.web.app/*`
3. Google Cloud Console → **Credentials → the web OAuth 2.0 client → Authorized JavaScript
   origins** → `https://wish-together-staging.web.app` (needed for Google sign-in)

## Shared production services

- **Shared Auth caveat:** the test account is a real account in the production Auth project.
  Never use a family member's account, and never exercise in-app **account deletion** on
  staging with a real account — it deletes the production Auth user. Use a throwaway test
  account.
- **App Check:** the staging host shares the production project's App Check registration.
  Enforcement is currently off; if it is enabled later, the staging host and its reCAPTCHA
  key must be registered first (the same prerequisite as the allowlisting above).
- **Remote Config:** also shared with production. A production `min_supported_build` above the
  staged build makes the staging site show the blocking force-update screen.

## Demo data

`scripts/seed-demo.mjs` writes a fictional, multi-family dataset (10 people, 3 overlapping
groups, 11 wishlists, 86 items, marked claims) for screenshots and manual testing. It
defaults to the named **`staging`** Firestore database; pass `--database "(default)"` to
write to production. It needs an Admin service-account JSON via
`GOOGLE_APPLICATION_CREDENTIALS`, refuses to run without `--yes`, refuses a credentials file
from another project, and only ever touches `demo-` document ids. Only the `--viewer-uid`
account needs real authentication; the other people are plain `users/{uid}` documents, which
works because every signed-in user can read every user document and every wishlist (see
`docs/authorization.md`). Run it with `--clean-only` when done — while the data exists, any
signed-in user can read it.

```bash
cd scripts && npm ci
GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
  npm run seed:demo -- --yes --database staging --viewer-uid <test-uid>
GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
  npm run seed:demo -- --yes --clean-only --database staging
```

Seed after a staging deploy, and use a **dedicated test account** (see Shared Auth above).
