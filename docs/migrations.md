# Migrating Firestore data

One-off admin scripts in `scripts/` change stored data outside the app. They run
with a service account, bypass security rules, and are not covered by unit tests
at the data boundary, so the runbook below is part of the change.

Use a one-off script when:

- the change is a single, well-understood rewrite of existing documents;
- it is idempotent, so a failed run can simply be run again;
- the rollback is a `gcloud firestore import` of an export taken just before.

Revisit a shared migration kit only when several migrations need the same
pagination, backup or restore machinery. The claims migration is deliberately
one script; the background and the rejected kit are in
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
- A claimed uid without a `claimedAt` is repaired with the run time; the date is
  stored but never displayed.
- An item that already has a `claims` map is skipped, so the run is idempotent
  and a rerun after a partial failure writes only the remainder.
- Writes go in batches of 400, committed in order. The first failed batch stops
  the run and the script prints how many items were written before it.

Run it with `cd scripts` in the shell (the npm script lives there):

```sh
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  npm run migrate:claims -- --database staging
```

| Flag | Effect |
| --- | --- |
| none | Dry run: prints counts and the first ten paths, writes nothing |
| `--yes` | Performs the migration |
| `--verify` | Reads again; prints `path: problem` and exits 1 on any |
| `--limit <n>` | Stops after n items, for a canary |
| `--database <id>` | A named database, or `"(default)"` (default `staging`) |
| `--print-target` | Prints the resolved database and exits |
| `--help` | Prints the usage |

Exit codes: `0` success, `1` verification problems or a failed batch, `2` usage,
target or credential refusal.

## Export before any write

Take a full export first; it is the rollback path. `--database` is required for
a named database, and `(default)` is the production database.

```sh
gcloud firestore export "gs://<backup-bucket>/claims-$(date +%Y%m%dT%H%M%S)" \
  --database=staging
```

Rollback is an import. It restores the entire database as it was at export time,
so stop the app's writes first (the freeze below) and expect to redeploy the
matching rules and build.

```sh
gcloud firestore import "gs://<backup-bucket>/claims-<timestamp>" \
  --database=staging
```

## Freeze

Deploy temporary rules that deny item creates, updates and deletes, and wishlist
deletes. Reads stay available. Without the freeze an old client can write the
legacy fields after its item was migrated, and an item created or deleted during
the run is missed or aborts a batch.

The freeze is a few minutes of "claims are read-only", not an outage. Record the
previous ruleset id before deploying it so the rollback can redeploy it.

## Staging rehearsal

1. Seed demo data on `staging`, deploy the freeze, and take the export.
2. Run the dry run and read the counts.
3. Run `--limit 10 --yes` as a canary, then the full `--yes`.
4. Run `--verify`; zero problems, or stop and investigate.
5. Run the import once to prove the rollback, then repeat the migration and
   `--verify`.
6. Redeploy the previous staging rules.

## Production order

1. Rehearse on `staging`, including the restore.
2. Deploy the freeze to production; record the prior ruleset id.
3. Export production to the backup bucket.
4. Run the canary, then the full migration with `--database "(default)" --yes`.
5. Run `--verify`; stop on any problem.
6. Deploy the final rules, then the web build.
7. Smoke test: a reader claims, unclaims, a full item shows unavailable, and the
   owner edits an item without dropping a claim.
8. Keep the export for a few days, then delete it.

Rollback while frozen: import the export, then redeploy the previous rules.
Rollback after the release: import the export and redeploy the previous rules
and hosting release.
