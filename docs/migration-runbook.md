# Firestore migration runbook

One-off Firestore migration runbook; script contract and claims shape: `docs/migrations.md`.

## Freeze

Deploy temporary rules setting the wishlist `allow delete` and the nested item `allow create`, `allow update`
and `allow delete` to `if false`; reads stay as they are. Firestore has no deny rule, so adding one beside an
allow changes nothing. Without the freeze an old client can write legacy fields after its item was migrated,
an item created during the run is missed, and a deleted item aborts a batch.

It lasts until the rules job publishes after the merge, typically 20-40 minutes: item creates, edits and
claims are refused, not an outage. Record the pre-freeze ruleset id for the audit trail; every deploy mints a
new id, so a restore is verified by content, not by that id:

```sh
cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
  npm run rules:release -- show --database "(default)"   # or staging
```

Deploy the freeze as an uncommitted edit to `firestore.rules`; run these from the repository root after
leaving `scripts/`:

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

The freeze is a local edit, not a commit. Once the upload is confirmed, run `git checkout -- firestore.rules`
so the next deploy cannot republish it; the deployed freeze is unaffected.

CI publishes `master`'s rules on pushes touching `firestore.rules`, `firebase.json`, `rules_tests/` or the
rules workflow, and the web build on merge. Hold every other merge until the final rules are live: an
unrelated push there republishes master's rules and lifts the freeze. Merge rules-and-data first, then the UI
change stacked on its branch, both in the same window; merging rules-and-data is the deploy, so hold that
merge until `--verify` is clean. The App Store review wait is not frozen; the freeze covers only the
migration and verify window. The rules job and the web job are independent; wait for both before the smoke
test.

## Export and rollback import

With the freeze in place, take a full export; it is the rollback path. An export taken before the freeze can
be outrun by writes, which a restore would drop. Both commands take `--project`; name `--database`, because
without it gcloud targets production `(default)`.

```sh
gcloud firestore export "gs://<backup-bucket>/claims-<database>-$(date +%Y%m%dT%H%M%S)" \
  --project=wish-together-project --database="<database>"
```

Rollback is an import: it overwrites the exported documents with their export content and discards every
write after the export, including claims, but does **not** delete documents created later. The freeze stops
the app's writes; expect to redeploy the matching rules and build.

```sh
gcloud firestore import "gs://<backup-bucket>/claims-<database>-<timestamp>" \
  --project=wish-together-project --database="<database>"
```

## Staging rehearsal

1. Seed from a pre-claims commit (the seeder then writes the legacy shape) or import a legacy export; after
   the claims change the seeder writes the new shape and the dry run would plan nothing. Deploy the staging
   freeze (above), take the export, and require a non-zero plan.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary; stop if it exits non-zero. Then run the full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and `--verify`.
6. Discard the local freeze edit, redeploy the previous staging rules, and reseed staging:

   ```sh
   # repository root, before the claims rules merge
   git fetch && git show origin/master:firestore.rules > firestore.rules \
     && test -s firestore.rules \
     && firebase deploy --only firestore:rules \
       --config firebase.staging.json --project wish-together-project
   (cd scripts && npm run seed:demo -- --yes --viewer-uid <staging-test-uid> \
     --database staging)
   ```

   The seeder needs `--yes` and a uid; use the dedicated test account from `docs/staging.md`. This restores
   the pre-claims rules only before the claims merge; afterwards `origin/master` holds the claims rules.
   Staging then holds claims-shaped data, and an old app's claim under the old rules is legacy-shaped and
   dropped by the next migration.

## Production order

Run the `npm run` commands from `scripts/` with `GOOGLE_APPLICATION_CREDENTIALS` exported once. The iOS app
is live, so the window includes an App Store build.

1. Rehearse on `staging`, including the restore, and verify the counts.
2. Submit the claims-aware build from the final claims code as it will be merged, then immediately switch
   Version Release to "Manually release this version" in App Store Connect: the `app_store_release` lane
   requests automatic release. Do not push to either claims branch afterwards. Confirm "Pending Developer
   Release" before continuing; do not release it until later in this window.
3. Record the prior ruleset id, then deploy the production freeze (above).
4. Export production to the backup bucket, with `--database="(default)"`, and record the exact `gs://` path
   for the rollback. The bucket must exist before the window, and your account needs `storage.objects.create`
   on it.
5. Run the dry run (`npm run migrate:claims -- --database "(default)"`) and read the counts, then the canary
   (stop if it exits non-zero: a failed plan or batch commits nothing, and a successful canary is safe to
   rerun) and the full migration:

   ```sh
   npm run migrate:claims -- --database "(default)" --limit 10 --yes
   npm run migrate:claims -- --database "(default)" --yes
   ```

6. Run `--verify` against production; stop on any problem:

   ```sh
   npm run migrate:claims -- --database "(default)" --verify
   ```

   If it is not clean, import the export, restore the pre-freeze rules (see Rollback, before the merge), and
   stop: do not deploy the final rules or release iOS, and reject or remove the pending App Store version.

7. From a clean tree, merge rules-and-data first, then the UI change stacked on its branch; CI deploys the
   final rules and the web build. Point the local file at the merged rules and confirm the content is live:

   ```sh
   cd "$(git rev-parse --show-toplevel)"
   git fetch && git show origin/master:firestore.rules > firestore.rules \
     && test -s firestore.rules
   cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
     npm run rules:release -- check --database "(default)" --source ../firestore.rules
   ```

   If the rules job fails, the freeze stays live: fix and push before releasing iOS. If the web job fails,
   the old web build stays served under the new rules: re-run it before the smoke test.
8. Smoke test on web: a reader claims, unclaims, a full item shows unavailable, and the owner edits an item
   without dropping a claim.
9. Release the iOS build in the same window.
10. Note the current Remote Config values, then set `min_supported_build`, `update_url` and `update_message`
    only once the build is available in the App Store. Confirm a below-minimum build shows the update screen
    on its next launch. Keep the export for a few days, then delete it.

**Minimum-build gate.** Step 10 sets the values. The gate is iOS-only, runs at startup only, fails open (no
network, no Remote Config value, or an older gate means no prompt), and can be bypassed. The rules enforce;
the gate only helps people update. An already-open web tab is not gated and must reload for the new build.

## Rollback

Before the merge (the freeze is live): import the export, reject or remove the pending App Store version,
then restore and deploy the pre-freeze rules:

```sh
cd "$(git rev-parse --show-toplevel)"
git fetch && git show origin/master:firestore.rules > firestore.rules \
  && test -s firestore.rules \
  && firebase deploy --only firestore:rules --project wish-together-project
```

Master still holds the pre-freeze rules because rules merges are held. Alternatively, copy the pre-freeze
version from the console's rules history and publish it; the console publishes to production `(default)`
only. Verify the content as in Freeze. Nothing has shipped, so the old app still reads the legacy fields.

After the merge (the final rules and web are live, whether or not iOS has shipped):

1. Re-apply the freeze to the current `firestore.rules` (deny every item write and the wishlist delete,
   including the claims update branch) and deploy it.
2. Import the export.
3. Roll Hosting back in the Firebase console's release history to the last release published before the
   claims changes merged.
4. Restore the pre-freeze rules from the commit before the rules change merged and deploy them, then verify
   the content as in Freeze:

   ```sh
   cd "$(git rev-parse --show-toplevel)"
   git show <pre-freeze-commit>:firestore.rules > firestore.rules \
     && test -s firestore.rules \
     && firebase deploy --only firestore:rules --project wish-together-project
   cd scripts && ACCESS_TOKEN=$(gcloud auth print-access-token) \
     npm run rules:release -- check --database "(default)" --source ../firestore.rules
   ```

   The `test -s` stops an empty file reaching production if `git show` fails. This overwrites the local
   freeze edit; only the file route is verifiable by content. Revert both claims merges (rules/data and UI),
   or block every merge to `master`: the web job deploys on any push and would republish the claims-aware UI
   under the restored rules.
5. Restore the previous `min_supported_build`, `update_url` and `update_message` values if they were changed
   (publish Remote Config).
6. If the App Store version is still pending, reject or remove it. If it is live, an updated client needs a
   build that writes the legacy pair, or a roll-forward: redeploy the claims rules and re-run the migration.
   A raised `min_supported_build` cannot rescue it.

