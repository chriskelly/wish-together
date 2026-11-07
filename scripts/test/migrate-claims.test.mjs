import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import {
  PROJECT_ID,
  main,
  parseArgs,
  planItem,
  runClaims,
  verifyItem,
} from '../migrate-claims.mjs';

const SCRIPT = fileURLToPath(new URL('../migrate-claims.mjs', import.meta.url));

function run(args, env = {}) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, ...env },
  });
}

function credentialsFile(t, fields) {
  const dir = mkdtempSync(join(tmpdir(), 'wt-claims-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'service-account.json');
  writeFileSync(path, JSON.stringify(fields));
  return path;
}

function fakeLog() {
  const lines = [];
  return {
    lines,
    log: (line) => lines.push(line),
    error: (line) => lines.push(`error: ${line}`),
    warn: (line) => lines.push(`warn: ${line}`),
  };
}

function fakeDoc(path, data) {
  return { ref: { path }, data: () => data };
}

/// A Firestore stand-in: one collection group snapshot and recorded batches.
function fakeDb(documents, { failCommit = 0 } = {}) {
  const batches = [];
  let commits = 0;
  return {
    batches,
    collectionGroup(name) {
      assert.equal(name, 'items');
      return { get: async () => ({ docs: documents }) };
    },
    batch() {
      const ops = [];
      batches.push(ops);
      return {
        update(ref, fields) {
          ops.push({ path: ref.path, fields });
        },
        async commit() {
          commits += 1;
          if (commits === failCommit) {
            throw new Error('commit exploded');
          }
        },
      };
    },
  };
}

/// [count] legacy, unclaimed item documents.
function documents(count) {
  return Array.from({ length: count }, (_, index) =>
    fakeDoc(`wishlists/w1/items/i${String(index).padStart(3, '0')}`, {
      name: `Item ${index}`,
      claimedBy: null,
      claimedAt: null,
    }),
  );
}

function deps(db) {
  const log = fakeLog();
  return {
    log,
    env: {},
    credentials: () => ({ project_id: PROJECT_ID }),
    openDb: () => db,
  };
}

// --- CLI guards -----------------------------------------------------------

test('--help prints the usage and exits zero', () => {
  const result = run(['--help']);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Usage: npm run migrate:claims/);
});

test('--print-target resolves the default, production and a named database', () => {
  const staging = run(['--print-target']);
  const production = run(['--print-target', '--database', '(default)']);
  const named = run(['--print-target', '--database=staging-2']);

  assert.equal(staging.stdout.trim(), 'staging');
  assert.equal(production.stdout.trim(), '(default)');
  assert.equal(named.stdout.trim(), 'staging-2');
});

test('an invalid database id exits 2', () => {
  const result = run(['--print-target', '--database=bad/id']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Invalid --database/);
});

test('an unknown flag exits 2', () => {
  const result = run(['--wat']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Unknown option --wat/);
});

test('a flag used as a value is a missing value', () => {
  const result = run(['--database', '--yes']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /--database needs a value/);
});

test('a missing credentials variable is named', () => {
  const result = run(['--limit', '1']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Set GOOGLE_APPLICATION_CREDENTIALS/);
});

test("a credentials file from another project is refused, naming both", (t) => {
  const path = credentialsFile(t, {
    project_id: 'some-other-project',
    client_email: 'x@example.com',
  });

  const result = run(['--limit', '1'], {
    GOOGLE_APPLICATION_CREDENTIALS: path,
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /some-other-project/);
  assert.match(result.stderr, new RegExp(PROJECT_ID));
});

test('--limit, --yes and --print-target are refused with --verify', () => {
  const limited = run(['--verify', '--limit', '10']);
  const apply = run(['--verify', '--yes']);
  const target = run(['--verify', '--print-target']);

  assert.equal(limited.status, 2);
  assert.match(limited.stderr, /--limit cannot be combined with --verify/);
  assert.equal(apply.status, 2);
  assert.match(apply.stderr, /--yes cannot be combined with --verify/);
  assert.equal(target.status, 2);
  assert.match(target.stderr, /--print-target cannot be combined with --verify/);
});

test('a production run without --yes is a read-only dry run', async () => {
  const db = fakeDb(documents(1));
  const injected = deps(db);

  const code = await main(
    ['--database', '(default)', '--limit', '1'],
    injected,
  );

  assert.equal(code, 0);
  assert.deepEqual(db.batches, []);
  assert.ok(injected.log.lines.some((line) => /warn: .*PRODUCTION/.test(line)));
});

test('a production verify is allowed and warns', async () => {
  const db = fakeDb([
    fakeDoc('wishlists/w1/items/a', {
      claims: {},
      claimLimit: 1,
    }),
  ]);
  const injected = deps(db);

  const code = await main(
    ['--database', '(default)', '--verify'],
    injected,
  );

  assert.equal(code, 0);
  assert.ok(injected.log.lines.some((line) => /warn: .*PRODUCTION/.test(line)));
});

test('a credentials file that is not a service-account key is refused', (t) => {
  const path = credentialsFile(t, { project_id: PROJECT_ID });

  const result = run(['--limit', '1'], {
    GOOGLE_APPLICATION_CREDENTIALS: path,
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /service-account key/);
});

test('a credentials file with the wrong type is refused', (t) => {
  const path = credentialsFile(t, {
    type: 'authorized_user',
    project_id: PROJECT_ID,
    private_key: 'key',
    client_email: 'x@example.com',
  });

  const result = run(['--limit', '1'], {
    GOOGLE_APPLICATION_CREDENTIALS: path,
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, /service-account key/);
});

// --- parseArgs ------------------------------------------------------------

test('parseArgs defaults to a staging dry run', () => {
  assert.deepEqual(parseArgs([]), {
    databaseId: 'staging',
    yes: false,
    verify: false,
    printTarget: false,
    help: false,
    limit: null,
  });
});

test('parseArgs accepts a positive limit and refuses anything else', () => {
  assert.equal(parseArgs(['--limit', '3']).limit, 3);
  for (const bad of ['0', '-1', '1.5', 'abc']) {
    assert.throws(() => parseArgs([`--limit=${bad}`]), /Invalid --limit/);
  }
});

// --- planItem -------------------------------------------------------------

test('a claimed legacy item becomes one claim with the same timestamp', () => {
  const claimedAt = Timestamp.fromDate(new Date('2026-01-02T03:04:05Z'));

  const plan = planItem({ claimedBy: 'uid-1', claimedAt });

  assert.deepEqual(Object.keys(plan.claims), ['uid-1']);
  assert.ok(plan.claims['uid-1'].isEqual(claimedAt));
  assert.equal(plan.claimLimit, 1);
  assert.ok(plan.claimedBy.isEqual(FieldValue.delete()));
  assert.ok(plan.claimedAt.isEqual(FieldValue.delete()));
});

test('an unclaimed legacy item becomes an empty claims map', () => {
  for (const data of [{ claimedBy: null, claimedAt: null }, {}]) {
    const plan = planItem(data);

    assert.deepEqual(plan.claims, {});
    assert.equal(plan.claimLimit, 1);
    assert.ok(plan.claimedBy.isEqual(FieldValue.delete()));
    assert.ok(plan.claimedAt.isEqual(FieldValue.delete()));
  }
});

test('an already migrated item is skipped', () => {
  assert.equal(planItem({ claims: { 'uid-1': Timestamp.now() }, claimLimit: 1 }), null);
  assert.equal(planItem({ claims: {}, claimLimit: 1 }), null);
});

test('a single-claim map without a limit gets one, so a rerun converges', () => {
  assert.deepEqual(planItem({ claims: {} }), { claimLimit: 1 });
  assert.deepEqual(
    Object.keys(planItem({ claims: {}, claimedBy: null })),
    ['claimLimit', 'claimedBy'],
  );
});

test('a multi-claim map without a numeric limit stops the run', () => {
  const claims = { a: Timestamp.now(), b: Timestamp.now() };

  for (const claimLimit of [undefined, null, '1']) {
    assert.throws(
      () => planItem({ claims, claimLimit }),
      /claims map has several claims but needs an integer claimLimit/,
    );
  }
});

test('a single-claim map with an invalid limit is repaired', () => {
  for (const claimLimit of [null, '1', 1.5, -1]) {
    assert.deepEqual(
      planItem({ claims: { a: Timestamp.now() }, claimLimit }),
      { claimLimit: 1 },
    );
  }
});

test('an already migrated item with leftover legacy keys is only cleaned up', () => {
  const plan = planItem({
    claims: {},
    claimLimit: 1,
    claimedBy: null,
    claimedAt: null,
  });

  assert.deepEqual(Object.keys(plan), ['claimedBy', 'claimedAt']);
  assert.ok(plan.claimedBy.isEqual(FieldValue.delete()));
  assert.ok(plan.claimedAt.isEqual(FieldValue.delete()));
});

test('a non-map claims value stops the run instead of being skipped', () => {
  assert.throws(() => planItem({ claims: 'nope' }), /claims is not a map/);
  assert.throws(() => planItem({ claims: 42 }), /claims is not a map/);
  assert.throws(() => planItem({ claims: Timestamp.now() }), /claims is not a map/);
  assert.throws(() => planItem({ claims: [Timestamp.now()] }), /claims is not a map/);
});

test('a claimedBy that is not a non-empty string stops the run', () => {
  assert.throws(() => planItem({ claimedBy: 123 }), /claimedBy is not a string/);
  assert.throws(() => planItem({ claimedBy: {} }), /claimedBy is not a string/);
  assert.throws(() => planItem({ claimedBy: '' }), /claimedBy is not a string/);
});

test('a missing or wrong-typed claim timestamp is repaired with the run time', () => {
  const now = Timestamp.fromDate(new Date('2026-06-07T08:09:10Z'));

  for (const claimedAt of [undefined, '2026-01-01']) {
    const plan = planItem({ claimedBy: 'uid-1', claimedAt }, now);

    assert.ok(plan.claims['uid-1'].isEqual(now));
  }
});

// --- verifyItem -----------------------------------------------------------

test('a migrated item has no problems', () => {
  assert.deepEqual(verifyItem({ claims: {}, claimLimit: 1 }), []);
});

test('verifyItem names every malformed field', () => {
  assert.deepEqual(verifyItem({ claimLimit: 1 }), ['missing claims map']);
  assert.deepEqual(verifyItem({ claims: 'nope', claimLimit: 1 }), [
    'claims is not a map',
  ]);
  assert.deepEqual(verifyItem({ claims: {} }), ['missing claimLimit']);
  assert.deepEqual(verifyItem({ claims: {}, claimLimit: -1 }), [
    'invalid claimLimit -1',
  ]);
  assert.deepEqual(verifyItem({ claims: {}, claimLimit: 1.5 }), [
    'invalid claimLimit 1.5',
  ]);
  assert.deepEqual(
    verifyItem({
      claims: { a: Timestamp.now(), b: Timestamp.now() },
      claimLimit: 1,
    }),
    ['claims exceed claimLimit 1'],
  );
  assert.deepEqual(verifyItem({ claims: { 'uid-1': 'yesterday' }, claimLimit: 1 }), [
    'invalid claim timestamp for uid-1',
  ]);
  assert.deepEqual(
    verifyItem({ claims: {}, claimLimit: 1, claimedBy: null, claimedAt: null }),
    ['leftover claimedBy', 'leftover claimedAt'],
  );
});

// --- runClaims ------------------------------------------------------------

test('a dry run reports counts and writes nothing', async () => {
  const db = fakeDb([
    fakeDoc('wishlists/w1/items/a', { claimedBy: null }),
    fakeDoc('wishlists/w1/items/b', { claims: {}, claimLimit: 1 }),
  ]);

  const result = await runClaims({ db, mode: 'dry-run', log: fakeLog() });

  assert.equal(result.scanned, 2);
  assert.equal(result.planned, 1);
  assert.equal(result.skipped, 1);
  assert.equal(result.written, 0);
  assert.deepEqual(db.batches, []);
});

test('apply writes only planned items in batches of 400', async () => {
  const migrated = fakeDoc('wishlists/w1/items/migrated', {
    claims: {},
    claimLimit: 1,
  });
  const db = fakeDb([migrated, ...documents(401)]);
  const log = fakeLog();

  const result = await runClaims({ db, mode: 'apply', log });

  assert.equal(result.scanned, 402);
  assert.equal(result.skipped, 1);
  assert.equal(result.planned, 401);
  assert.equal(result.written, 401);
  assert.deepEqual(
    db.batches.map((ops) => ops.length),
    [400, 1],
  );
  assert.equal(
    db.batches.flat().some((op) => op.path === migrated.ref.path),
    false,
  );
});

test('apply writes the migrated fields', async () => {
  const db = fakeDb([
    fakeDoc('wishlists/w1/items/a', { claimedBy: 'uid-1' }),
  ]);

  await runClaims({ db, mode: 'apply', log: fakeLog() });

  const [op] = db.batches.flat();
  assert.equal(op.path, 'wishlists/w1/items/a');
  assert.deepEqual(Object.keys(op.fields.claims), ['uid-1']);
  assert.equal(op.fields.claimLimit, 1);
  assert.ok(op.fields.claimedBy.isEqual(FieldValue.delete()));
  assert.ok(op.fields.claimedAt.isEqual(FieldValue.delete()));
});

test('a malformed claims value stops the run with its document path', async () => {
  const db = fakeDb([fakeDoc('wishlists/w1/items/a', { claims: 'nope' })]);

  await assert.rejects(
    runClaims({ db, mode: 'dry-run', log: fakeLog() }),
    /wishlists\/w1\/items\/a: claims is not a map/,
  );
  assert.deepEqual(db.batches, []);
});

test('--yes through the CLI writes', async () => {
  const db = fakeDb([fakeDoc('wishlists/w1/items/a', { claimedBy: 'uid-1' })]);

  assert.equal(await main(['--yes'], deps(db)), 0);
  assert.equal(db.batches.flat()[0].fields.claimLimit, 1);
});

test('a failed batch through the CLI exits 1', async () => {
  const db = fakeDb([fakeDoc('wishlists/w1/items/b', { claimedBy: null })], {
    failCommit: 1,
  });

  assert.equal(await main(['--yes'], deps(db)), 1);
});

test('--limit stops after N scanned documents', async () => {
  const db = fakeDb(documents(5));

  const result = await runClaims({ db, mode: 'dry-run', limit: 2, log: fakeLog() });

  assert.equal(result.scanned, 2);
  assert.equal(result.planned, 2);
});

test('a rerun skips already migrated items', async () => {
  const db = fakeDb([
    fakeDoc('wishlists/w1/items/a', { claims: {}, claimLimit: 1 }),
    fakeDoc('wishlists/w1/items/b', { claimedBy: 'uid-1' }),
  ]);

  const result = await runClaims({ db, mode: 'apply', log: fakeLog() });

  assert.equal(result.skipped, 1);
  assert.equal(result.written, 1);
  assert.equal(db.batches.flat()[0].path, 'wishlists/w1/items/b');
});

test('a failed batch stops the run and reports the counts so far', async () => {
  const db = fakeDb(documents(401), { failCommit: 2 });
  const log = fakeLog();

  const result = await runClaims({ db, mode: 'apply', log });

  assert.equal(result.written, 400);
  assert.equal(result.failed, true);
  assert.ok(log.lines.some((line) => /Batch failed after 400 of 401/.test(line)));
});

test('verify collects path-prefixed problems', async () => {
  const db = fakeDb([
    fakeDoc('wishlists/w1/items/a', { claims: {}, claimLimit: 1 }),
    fakeDoc('wishlists/w1/items/b', { claimLimit: 1 }),
  ]);

  const result = await runClaims({ db, mode: 'verify', log: fakeLog() });

  assert.deepEqual(result.problems, ['wishlists/w1/items/b: missing claims map']);
});

test('a verify with no problems exits zero and with problems exits one', async () => {
  const clean = deps(
    fakeDb([fakeDoc('wishlists/w1/items/a', { claims: {}, claimLimit: 1 })]),
  );
  const broken = deps(fakeDb([fakeDoc('wishlists/w1/items/b', { claimLimit: 1 })]));

  assert.equal(await main(['--verify'], clean), 0);
  assert.equal(await main(['--verify'], broken), 1);
});

test('a verify that scans zero items fails', async () => {
  assert.equal(await main(['--verify'], deps(fakeDb([]))), 1);
});

test('a limited apply writes at most the limit', async () => {
  const db = fakeDb(documents(5));

  assert.equal(await main(['--yes', '--limit', '2'], deps(db)), 0);
  assert.equal(db.batches.flat().length, 2);
});

test('a malformed document through the CLI exits 1', async () => {
  const db = fakeDb([fakeDoc('wishlists/w1/items/a', { claims: 'nope' })]);

  assert.equal(await main(['--yes'], deps(db)), 1);
  assert.deepEqual(db.batches, []);
});
