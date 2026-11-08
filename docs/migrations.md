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
- A document with `claimLimit` but no `claims` map is new-shape: it gains an
  empty `claims` map and keeps its limit; only a missing or invalid limit
  becomes `1`.
- A claimed uid without a usable `claimedAt` is repaired with the run time.
- An item with a claims map is not re-claimed. A missing or invalid
  `claimLimit` and leftover legacy keys are the only things written for it
  (counted as planned, not skipped), so a rerun converges on those. An invalid
  claim timestamp, or more claims than a valid limit, is left for `--verify` to
  report and must be fixed by hand.
  A map with several claims but no integer limit stops the run, because no safe
  limit can be guessed.
- A non-null, non-map `claims` value stops the run and names the document; no
  later run could repair it. For a document without a claims map, a `claimedBy`
  that is neither null nor a non-empty string also stops the run.
- Writes are 400-document batches committed in order. The first failed batch
  stops the run and reports how many items were written before it.

The new UI does not display claim dates, so a repaired timestamp is not
user-visible. Until the new web build is deployed and any open tab reloads, the
old web build reads the deleted `claimedBy` as unclaimed: it shows migrated
claimed items as available, and a claim from it fails. Old iOS builds read the
same deleted fields and behave the same way until users update; the
minimum-build gate nudges them.

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
failed batch, a key that cannot authenticate, or any other failure after the
guards; `2` usage, or credentials that are missing, unreadable, from the wrong
project or not a service-account key. A run that scans zero items also exits 1:
it has checked nothing, so check the target.

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
outage. Record the pre-freeze ruleset id for the audit trail; every deploy mints
a new id, so a restore is verified by content, not by that id:

```sh
cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
  npm run rules:release -- show --database "(default)"   # or staging
```

Deploy the freeze as an uncommitted edit to `firestore.rules`; run these from
the repository root:

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
  npm run rules:release -- check --database "(default)" \
  --source ../firestore.rules   # or --database staging
```

The freeze is a local edit, not a commit. Once the upload is confirmed, run
`git checkout -- firestore.rules` so the next deploy cannot republish it; the
deployed freeze is unaffected.

CI publishes `master`'s rules whenever a push touches `firestore.rules`,
`firebase.json`, `rules_tests/` or the rules workflow, and the web build
publishes on merge. Hold every other merge until the final rules are live: an
unrelated push touching those paths republishes master's rules and lifts the
freeze. Merging the rules-and-data change and the UI change is the deploy: hold
them until `--verify` is clean and merge inside the freeze window. The rules job
and the web job are independent; wait for both before the smoke test.

## Staging rehearsal

1. Seed from a commit before the claims changes (the seeder then writes the
   legacy shape), or import a legacy export. Once the claims change lands, the
   seeder writes the new shape and the dry run would plan nothing. Deploy the staging freeze (above),
   take the export, and require a non-zero plan.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary; stop if it exits non-zero. Then run the
   full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and
   `--verify`.
6. Discard the local freeze edit, redeploy the previous staging rules, and
   reseed staging:

   ```sh
   # repository root, before the claims rules merge
   git fetch && git show origin/master:firestore.rules > firestore.rules \
     && test -s firestore.rules \
     && firebase deploy --only firestore:rules \
       --config firebase.staging.json --project wish-together-project
   (cd scripts && npm run seed:demo -- --yes --viewer-uid <staging-test-uid> \
     --database staging)
   ```

   The seeder needs `--yes` and a uid; `docs/staging.md` says to use the
   dedicated test account. This restores the pre-claims rules only before the
   claims merge; afterwards `origin/master` holds the claims rules. Staging then
   holds claims-shaped data, and a claim from the old app under the old rules
   would be written in the legacy shape and dropped by the next migration.

## Production order

Run the `npm run` commands from `scripts/`, with
`GOOGLE_APPLICATION_CREDENTIALS` exported once for the window. The iOS app is
live, so the release window includes an App Store build.

1. Rehearse on `staging`, including the restore, and verify the counts.
2. Submit the claims-aware build from the head of the final UI change (which
   contains the data change; the merge keeps the tree identical), then
   immediately switch Version Release to "Manually release this version" in App
   Store Connect: the `app_store_release` lane requests automatic release. After
   submitting, do not push to either claims branch.
   Confirm it shows "Pending Developer Release" before continuing. Do not
   release it until later in this window.
3. Record the prior ruleset id, then deploy the production freeze (above).
4. Export production to the backup bucket, with `--database="(default)"`, and
   record the exact `gs://` path for the rollback. The bucket must exist before
   the window, and your account needs `storage.objects.create` on it.
5. Run the dry run against production and read the counts:
   `npm run migrate:claims -- --database "(default)"`.
6. Run the canary, stop if it exits non-zero (a planning or batch failure
   commits nothing; a canary that succeeded is safe to rerun), then the full
   migration:

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
   release iOS, and reject or remove the pending App Store version.

8. From a clean tree, merge the rules-and-data change and the UI change; CI
   deploys the final rules and the web build. Point the local file at the merged
   rules and confirm the content is live:

   ```sh
   cd "$(git rev-parse --show-toplevel)"
   git fetch && git show origin/master:firestore.rules > firestore.rules \
     && test -s firestore.rules
   cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
     npm run rules:release -- check --database "(default)" --source ../firestore.rules
   ```

   If the rules job fails, the freeze stays live: fix and push before releasing
   iOS. If the web job fails, the old
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

Before the merge (the freeze is live): import the export, reject or remove the
pending App Store version, then restore and deploy the pre-freeze rules:

```sh
cd "$(git rev-parse --show-toplevel)"
git fetch && git show origin/master:firestore.rules > firestore.rules \
  && test -s firestore.rules \
  && firebase deploy --only firestore:rules --project wish-together-project
```

Master still holds the pre-freeze rules because rules merges are held. Or copy
the pre-freeze version from the Firebase console's Firestore rules history and
publish it (the console publishes to the production `(default)` database only).
Verify the content:

```sh
cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
  npm run rules:release -- check --database "(default)" --source ../firestore.rules
```
Nothing has shipped yet, so the old app still reads the legacy fields.

After the merge (the final rules and web are live, whether or not iOS has
shipped):

1. Re-apply the freeze to the current `firestore.rules` (deny every item write
   and the wishlist delete, including the claims update branch) and deploy it.
2. Import the export.
3. Roll Hosting back in the Firebase console's release history to the last
   release published before the claims changes merged.
4. Restore the pre-freeze rules from the commit before the rules change merged
   and deploy them, then verify the content:

   ```sh
   cd "$(git rev-parse --show-toplevel)"
   git show <pre-freeze-commit>:firestore.rules > firestore.rules \
     && test -s firestore.rules \
     && firebase deploy --only firestore:rules --project wish-together-project
   cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
     npm run rules:release -- check --database "(default)" --source ../firestore.rules
   ```

   The `test -s` stops an empty file reaching production if `git show` fails.
   This overwrites the local freeze edit; the file route is the only one that
   can be verified by content. Revert both claims merges (the rules/data change
   and the UI change), or block every merge to `master`, because the web job
   deploys on any push and would otherwise republish the claims-aware UI under
   the restored rules.
5. Restore the previous `min_supported_build`, `update_url` and `update_message`
   values if they were changed (publish Remote Config).
6. If the App Store version is still pending, reject or remove it. If it is
   already live, an updated client can only be repaired by a build that writes
   the legacy pair, or by rolling forward: redeploy the claims rules and re-run
   the migration. A raised `min_supported_build` cannot rescue a client that
   already updated.
