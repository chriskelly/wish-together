import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { parseSentryDsn } from '../sentry-identity.mjs';

const CLI = fileURLToPath(new URL('../sentry-identity.mjs', import.meta.url));

// Shape of a current SaaS DSN: the key is public, the host carries the numeric
// organisation id, and the path is the numeric project id.
const DSN = 'https://0123456789abcdef0123456789abcdef@o4512313775882240.ingest.us.sentry.io/4512313818611712';
const ORG_ID = '4512313775882240';
const PROJECT_ID = '4512313818611712';

function runCli(dsn) {
  const env = { PATH: process.env.PATH };
  if (dsn !== undefined) env.SENTRY_DSN = dsn;
  return spawnSync(process.execPath, [CLI], { encoding: 'utf8', env });
}

test('reads the numeric organisation and project ids from the DSN', () => {
  assert.deepEqual(parseSentryDsn(DSN), {
    orgId: ORG_ID,
    projectId: PROJECT_ID,
  });
});

test('reads a DSN hosted in another region', () => {
  const euDsn = DSN.replace('ingest.us.', 'ingest.de.');

  assert.deepEqual(parseSentryDsn(euDsn), {
    orgId: ORG_ID,
    projectId: PROJECT_ID,
  });
});

test('tolerates surrounding whitespace', () => {
  assert.deepEqual(parseSentryDsn(`  ${DSN}\n`), {
    orgId: ORG_ID,
    projectId: PROJECT_ID,
  });
});

test('rejects an old DSN that carries no organisation id', () => {
  const dsn = 'https://0123456789abcdef0123456789abcdef@sentry.io/4512313818611712';

  assert.throws(() => parseSentryDsn(dsn), /organisation id/);
});

test('rejects a self-hosted DSN, whose host is not an organisation host', () => {
  const dsn = 'https://0123456789abcdef0123456789abcdef@sentry.example.com/42';

  assert.throws(() => parseSentryDsn(dsn), /organisation id/);
});

test('rejects a DSN whose project id is not numeric', () => {
  const dsn = DSN.replace(PROJECT_ID, 'wishtogether');

  assert.throws(() => parseSentryDsn(dsn), /organisation id/);
});

test('rejects an empty DSN', () => {
  assert.throws(() => parseSentryDsn('   '), /SENTRY_DSN is empty/);
});

test('the command prints the two values GitHub Actions can export', () => {
  const result = runCli(DSN);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `SENTRY_ORG=${ORG_ID}\nSENTRY_PROJECT=${PROJECT_ID}\n`);
});

test('the command fails, naming the variable, when the DSN is absent', () => {
  const result = runCli();

  assert.equal(result.status, 1);
  assert.equal(result.stdout, '', 'a failed run must not write to $GITHUB_ENV');
  assert.match(result.stderr, /SENTRY_DSN/);
});

test('the command rejects a DSN passed as an argument', () => {
  const result = spawnSync(process.execPath, [CLI, DSN], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH },
  });

  assert.equal(result.status, 2);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /usage/);
});

test('still runs when invoked through a symlink to the script', (t) => {
  // A symlinked entry point must not be mistaken for a module import, which
  // would exit 0 having parsed nothing.
  const dir = mkdtempSync(join(tmpdir(), 'sentry-identity-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const link = join(dir, 'identity.mjs');
  symlinkSync(CLI, link);

  const result = spawnSync(process.execPath, [link], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, SENTRY_DSN: DSN },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `SENTRY_ORG=${ORG_ID}\nSENTRY_PROJECT=${PROJECT_ID}\n`);
});
