# Migrating Firestore data

One-off admin scripts in `scripts/` change stored data outside the app. They run
with a service account and bypass security rules; their tests use a fake
Firestore, so the operational checks live in `docs/migration-runbook.md`.

Use a one-off script when the change is a single rewrite, it is idempotent, and
an export taken just before is a sufficient rollback. Revisit a shared kit only
when several migrations need the same pagination or backup machinery; the
background and rejected alternatives are in
[issue #143](https://github.com/chriskelly/wish-together/issues/143).

This doc covers why a migration exists, the claims document shape, the script's
flags and exit codes, and the one sanctioned global item read.

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
- A document with `claimLimit` but no `claims` map is new-shape: it keeps its
  limit and gains a `claims` map, holding one key when `claimedBy` is set and
  empty otherwise. Only a missing or invalid limit becomes `1`.
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
same deleted fields and behave the same way until users update; the runbook's
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
