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
- An item with a claims map is skipped; if it still carries the legacy keys, the
  run deletes only those, so a rerun converges.
- A `claims` value that is not a map stops the run and names the document,
  because no later run could repair it.
- Writes are 400-document batches committed in order. The first failed batch
  stops the run and reports how many items were written before it.

The new UI does not display claim dates; the current web build shows
`Claimed on <date>` until replaced, so a repaired timestamp can be visible
briefly.

Run the script from `scripts/`:

```sh
cd scripts && npm ci
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  npm run migrate:claims -- --database staging
```

| Flag | Effect |
| --- | --- |
| none | Dry run: prints counts and the first ten paths, writes nothing |
| `--yes` | Performs the migration |
| `--verify` | Reads again; prints `path: problem` and exits 1 on any |
| `--limit <n>` | Stops after n scanned items, for a canary |
| `--database <id>` | Named database or `(default)`; the script defaults to `staging` |
| `--print-target` | Prints the resolved database and exits |
| `--help` | Prints the usage |

Exit codes: `0` success, `1` verification problems or a failed batch, `2` usage,
target or credential refusal.

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

The freeze is a few minutes of "claims are read-only", not an outage. Record the
previous ruleset id so the rollback can redeploy it.

## Staging rehearsal

1. Seed demo data on `staging`, deploy the freeze, and take the export.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary, then the full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and
   `--verify`.
6. Redeploy the previous staging rules.

## Production order

The iOS app is live, so the release window includes an App Store build.

1. Rehearse on `staging`, including the restore, and verify the counts.
2. In App Store Connect, set the approved claims-aware build to manual release.
   Do not submit it until the data and rules are in place.
3. Deploy the freeze to production; record the prior ruleset id.
4. Export production to the backup bucket.
5. Run the canary, then the full migration with
   `--database "(default)" --yes`.
6. Run `--verify` against production; stop on any problem:
   `npm run migrate:claims -- --database "(default)" --verify`.
7. Deploy the final rules, then the web build.
8. Release the iOS build in the same window.
9. Only after the build is available in the App Store, set
   `min_supported_build` and publish Remote Config with the App Store
   `update_url`.
10. Smoke test: a reader claims, unclaims, a full item shows unavailable, and the
    owner edits an item without dropping a claim.
11. Keep the export for a few days, then delete it.

The minimum-build gate is iOS-only, runs at startup only, fails open (no
network, no Remote Config value, or an older gate means no prompt), and can be
bypassed. The rules are the enforcement; the gate only helps people update. An
already-open web tab is not gated and must reload for the new build.

## Rollback

While frozen: import the export, then redeploy the previous rules. Nothing has
shipped yet, so the old app still reads the legacy fields.

After the release: import the export, redeploy the previous rules and hosting
release. Once the claims-aware iOS build is live, a data rollback needs a
follow-up build, so release iOS only after `--verify` is clean.
