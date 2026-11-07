# Migrating Firestore data

One-off admin scripts in `scripts/` change stored data outside the app. They run
with a service account, bypass security rules, and their tests use a fake
Firestore, so the runbook below is part of the change.

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
- A claimed uid without a usable `claimedAt` is repaired with the run time.
- An item with a claims map is not re-claimed. A missing `claimLimit` or
  leftover legacy keys are the only things written for it (counted as planned,
  not skipped), so a rerun converges. A map with several claims but no limit
  stops the run, because no safe limit can be guessed.
- A non-null, non-map `claims` value, or a `claimedBy` that is not a non-empty
  string, stops the run and names the document; no later run could repair it.
- Writes are 400-document batches committed in order. The first failed batch
  stops the run and reports how many items were written before it.

The new UI does not display claim dates, so a repaired timestamp is not
user-visible. Until the new web build is deployed and any open tab reloads, the
old build reads the deleted `claimedBy` as unclaimed: it shows migrated claimed
items as available, and a claim from it fails.

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

Deploy temporary rules that deny item creates, updates and deletes, and wishlist
deletes; reads stay available. Without the freeze an old client can write the
legacy fields after its item was migrated, an item created during the run is
missed, and a deleted item aborts a batch.

The freeze is a few minutes of item creates, edits and claims being refused,
not an outage. Record the previous ruleset id so the rollback can redeploy it.
Deploy it as an uncommitted edit to `firestore.rules`:

```sh
# staging
firebase deploy --only firestore:rules --config firebase.staging.json \
  --project wish-together-project

# production
firebase deploy --only firestore:rules --project wish-together-project
```

CI publishes `master`'s rules whenever a push touches `firestore.rules`,
`firebase.json`, `rules_tests/` or the rules workflow, and the web build
publishes on merge. Merging the rules/app PRs (PR 2 onward) is therefore the
deploy: hold them until `--verify` is clean and merge inside the freeze window.

## Staging rehearsal

1. Seed demo data on `staging`, deploy the staging freeze (above), and take the
   export.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary; stop if it exits non-zero. Then run the
   full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and
   `--verify`.
6. Redeploy the previous staging rules and reseed staging: it now holds
   claims-shaped data, and a later claim from the old app under the old rules
   would be written in the legacy shape and dropped by the next migration.

## Production order

The iOS app is live, so the release window includes an App Store build.

1. Rehearse on `staging`, including the restore, and verify the counts.
2. Confirm the claims-aware build is approved and set to manual release in App
   Store Connect. Do not release it until the data and rules are in place.
3. Deploy the production freeze (above); record the prior ruleset id.
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

8. Merge the claims PRs; CI deploys the final rules and the web build. Confirm
   the rules release id. If the rules job fails, the freeze stays live: fix and
   push before releasing iOS.
9. Smoke test on web: a reader claims, unclaims, a full item shows unavailable,
   and the owner edits an item without dropping a claim.
10. Release the iOS build in the same window.
11. Only after the build is available in the App Store, set
    `min_supported_build` and publish Remote Config with the App Store
    `update_url`; confirm a build below the minimum shows the update screen on
    its next launch.
12. Keep the export for a few days, then delete it.

The minimum-build gate is iOS-only, runs at startup only, fails open (no
network, no Remote Config value, or an older gate means no prompt), and can be
bypassed. The rules are the enforcement; the gate only helps people update. An
already-open web tab is not gated and must reload for the new build.

## Rollback

While frozen: import the export, then `git fetch && git checkout origin/master --
firestore.rules` (master still holds the pre-freeze rules because rules merges
are held) and deploy it, or restore the recorded ruleset id in the console. Nothing has shipped yet, so
the old app still reads the legacy fields.

After the release: import the export, restore the recorded pre-freeze ruleset id
in the console, redeploy the previous hosting release, and restore the previous
`min_supported_build` value (publish Remote Config) so the older build can read
the legacy fields. Once the claims-aware iOS build is live, a data rollback
needs a follow-up build, so release iOS only after `--verify` is clean.
