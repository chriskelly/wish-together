# Migrating Firestore data

One-off admin scripts in `scripts/` change stored data outside the app. They run
with a service account and bypass security rules; their tests use a fake
Firestore, so this runbook carries the operational checks.

Use a one-off script when the change is a single rewrite, it is idempotent, and
an export taken just before is a sufficient rollback. Revisit a shared kit only
when several migrations need the same pagination or backup machinery; the
background and rejected alternatives are in
[issue #143](https://github.com/chriskelly/wish-together/issues/143).

## The claims migration

Before, on every document in the `items` collection group:

```js
{ name, description, url, claimedBy: 'uid-1', claimedAt: Timestamp }
```

After:

```js
{ name, description, url, claims: { 'uid-1': Timestamp }, claimLimit: 1 }
```

- `claimedBy`/`claimedAt` are deleted, not written as `null`.
- A document with `claimLimit` but no `claims` map is new-shape and keeps its
  limit; only a missing or invalid limit becomes `1`.
- A claimed uid without a usable `claimedAt` is repaired with the run time.
- An item with a claims map is not re-claimed. A missing or invalid
  `claimLimit` and leftover legacy keys are the only things written for it
  (counted as planned, not skipped), so a rerun converges on those. An invalid
  claim timestamp is left for `--verify` to report and must be fixed by hand.
  A map with several claims but no integer limit stops the run, because no safe
  limit can be guessed.
- A non-null, non-map `claims` value, or a `claimedBy` that is not a non-empty
  string, stops the run and names the document; no later run could repair it.
- Writes are 400-document batches committed in order. The first failed batch
  stops the run and reports how many items were written before it.

The new UI does not display claim dates, so a repaired timestamp is not
user-visible. Until the new web build is deployed and any open tab reloads, the
old web and iOS builds read the deleted `claimedBy` as unclaimed: they show
migrated claimed items as available, and a claim from them fails.

Run the script from `scripts/`:

```sh
cd scripts && npm ci
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  npm run migrate:claims -- --database staging
```

| Flag | Effect |
| --- | --- |
| none | Dry run: prints counts and the first ten planned paths, writes nothing |
| `--yes` | Performs the migration |
| `--verify` | Reads again; prints `path: problem` and exits 1 on any |
| `--limit <n>` | Stops after n scanned items, for a canary |
| `--database <id>` | Named database or `(default)`; the script defaults to `staging` |
| `--print-target` | Prints the resolved database and exits |
| `--help` | Prints the usage |

Exit codes: `0` success; `1` verification problems, a malformed document, a
failed batch or any other run failure; `2` usage, target or credential refusal.
A verify that scans zero items also exits 1: it has checked nothing, so check
the target.

The `items` collection-group query is the one sanctioned exception to the
wishlist area rule against global item reads. Client code must still never query
items across wishlists; this script runs with a service account and never ships.

## Export before any write

Take a full export first; it is the rollback path. Both commands take
`--project`; without `--database` gcloud targets the production `(default)`, so
name the target explicitly.

```sh
gcloud firestore export "gs://<backup-bucket>/claims-<database>-$(date +%Y%m%dT%H%M%S)" \
  --project=wish-together-project --database="<database>"
```

Rollback is an import. It overwrites the exported documents with their export
content and discards every write after the export, including claims, but it does
**not** delete documents created later. Stop the app's writes first (the freeze
below) and expect to redeploy the matching rules and build.

```sh
gcloud firestore import "gs://<backup-bucket>/claims-<database>-<timestamp>" \
  --project=wish-together-project --database="<database>"
```

## Freeze

Deploy temporary rules that set the wishlist `allow delete` and the nested item
`allow create`, `allow update` and `allow delete` to `if false`, leaving reads
as they are. Firestore has no deny rule: adding one beside an existing allow
changes nothing. Without the freeze an old client can write the legacy fields
after its item was migrated, an item created during the run is missed, and a
deleted item aborts a batch.

The freeze lasts from here until the rules job publishes after the merge,
typically 20-40 minutes: item creates, edits and claims are refused, not an
outage. Record the previous ruleset id with the rules-release script so the
rollback can redeploy it:

```sh
ACCESS_TOKEN=$(gcloud auth print-access-token) \
  npm run rules:release -- show --database "(default)"   # or staging
```

Deploy the freeze as an uncommitted edit to `firestore.rules`:

```sh
# staging
firebase deploy --only firestore:rules --config firebase.staging.json \
  --project wish-together-project

# production
firebase deploy --only firestore:rules --project wish-together-project
```

After the deploy, confirm the upload landed (firebase-tools can skip it):

```sh
cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
  npm run rules:release -- check --database "(default)" --source ../firestore.rules
```

The freeze is a local edit, not a commit. Once the upload is confirmed, run
`git checkout -- firestore.rules` so the next deploy cannot republish it; the
deployed freeze is unaffected.

CI publishes `master`'s rules whenever a push touches `firestore.rules`,
`firebase.json`, `rules_tests/` or the rules workflow, and the web build
publishes on merge. Merging the rules/app PRs (PR 2 onward) is therefore the
deploy: hold them until `--verify` is clean and merge inside the freeze window.
The rules job and the web job are independent; wait for both before the smoke
test.

## Staging rehearsal

1. Seed demo data on `staging`, deploy the staging freeze (above), and take the
   export.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary; stop if it exits non-zero. Then run the
   full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and
   `--verify`.
6. Discard the local freeze edit (`git checkout -- firestore.rules`), redeploy
   the previous staging rules, and reseed staging: it now holds claims-shaped
   data, and a later claim from the old app under the old rules would be written
   in the legacy shape and dropped by the next migration.

## Production order

The iOS app is live, so the release window includes an App Store build.

1. Rehearse on `staging`, including the restore, and verify the counts.
2. Submit the claims-aware build for the exact commit that step 8 merges, then
   immediately switch Version Release to "Manually release this version" in App
   Store Connect: the `app_store_release` lane requests automatic release.
   Confirm it shows "Pending Developer Release" before continuing. Do not
   release it until later in this window.
3. Deploy the production freeze (above) and record the prior ruleset id.
4. Export production to the backup bucket, with `--database="(default)"`.
5. Run the dry run against production and read the counts:
   `npm run migrate:claims -- --database "(default)"`.
6. Run the canary, stop if it exits non-zero, then the full migration:

   ```sh
   npm run migrate:claims -- --database "(default)" --limit 10 --yes
   npm run migrate:claims -- --database "(default)" --yes
   ```

7. Run `--verify` against production; stop on any problem:

   ```sh
   npm run migrate:claims -- --database "(default)" --verify
   ```

   If it is not clean, import the export, restore the pre-freeze rules (see
   Rollback, before the merge), and stop: do not deploy the final rules or
   release iOS.

8. From a clean tree, merge the claims PRs; CI deploys the final rules and the
   web build. Confirm the rules release id. If the rules job fails, the freeze
   stays live: fix and push before releasing iOS. If the web job fails, the old
   web build stays served under the new rules: re-run it before the smoke test.
9. Smoke test on web: a reader claims, unclaims, a full item shows unavailable,
   and the owner edits an item without dropping a claim.
10. Release the iOS build in the same window.
11. Note the current Remote Config values, then set `min_supported_build`,
    `update_url` and `update_message` only after the build is available in the
    App Store. Confirm a build below the minimum shows the update screen on its
    next launch.
12. Keep the export for a few days, then delete it.

The minimum-build gate is iOS-only, runs at startup only, fails open (no
network, no Remote Config value, or an older gate means no prompt), and can be
bypassed. The rules are the enforcement; the gate only helps people update. An
already-open web tab is not gated and must reload for the new build.

## Rollback

Before the merge (the freeze is live): import the export, then
`git fetch && git checkout origin/master -- firestore.rules` (master still holds
the pre-freeze rules because rules merges are held) and deploy it, or restore
the recorded pre-freeze ruleset id in the console. Nothing has shipped yet, so
the old app still reads the legacy fields.

After the merge (the final rules and web are live, whether or not iOS has
shipped): import the export, restore the recorded pre-freeze ruleset id in the
console, redeploy the previous hosting release, and restore the previous
`min_supported_build` value if it was raised (publish Remote Config). The git
checkout now restores the claims rules, so do not use it here. Once the
claims-aware iOS build is live, a data rollback needs a follow-up build, so
release iOS only after `--verify` is clean.
