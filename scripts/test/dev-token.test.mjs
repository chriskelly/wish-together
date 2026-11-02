import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  DEFAULT_DATABASE_ID,
  DEFAULT_WEB_PORT,
  ENTRYPOINT,
  devRunCommand,
  parseArgs,
  validateDatabaseId,
  validateUid,
  validateWebPort,
} from '../dev-token.mjs';

const SCRIPT = fileURLToPath(new URL('../dev-token.mjs', import.meta.url));
const PROJECT_ID = 'wish-together-project';

/// Runs the CLI with a clean environment, so a developer's own credentials can
/// never change what a test sees.
function run(args, env = {}) {
  return spawnSync(process.execPath, [SCRIPT, ...args], {
    encoding: 'utf8',
    env: { PATH: process.env.PATH, ...env },
  });
}

/// A credentials file for [projectId], in a directory removed after the test.
function credentialsFile(t, projectId) {
  const dir = mkdtempSync(join(tmpdir(), 'wt-dev-token-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'service-account.json');
  writeFileSync(
    path,
    JSON.stringify({ project_id: projectId, client_email: 'x@example.com' }),
  );
  return path;
}

test('--help prints the usage and exits zero', () => {
  const result = run(['--help']);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Usage: npm run dev:token/);
});

test('a run without --uid names the missing flag', () => {
  const result = run([]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Missing --uid/);
});

test('a flag used as a value is a missing value, not a uid', () => {
  const result = run(['--uid', '--database', 'staging']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /--uid needs a value/);
});

test('an unknown option is refused instead of ignored', () => {
  const result = run(['--wat']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Unknown option --wat/);
});

test('a uid with whitespace is refused rather than trimmed', () => {
  const result = run(['--uid', 'dev live 1']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /whitespace/);
});

test('a uid longer than Firebase accepts is refused', () => {
  const result = run(['--uid', 'u'.repeat(129)]);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /128/);
});

test('the production database is refused, naming what to use instead', () => {
  const result = run(['--uid', 'dev-live-1', '--database', '(default)']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /production/);
  assert.match(result.stderr, new RegExp(DEFAULT_DATABASE_ID));
});

test('a malformed database id is refused', () => {
  const result = run(['--uid', 'dev-live-1', '--database', 'bad/id']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Invalid --database/);
});

test('a port outside the valid range is refused', () => {
  for (const port of ['0', 'abc', '70000']) {
    const result = run(['--uid', 'dev-live-1', '--web-port', port]);

    assert.equal(result.status, 2, port);
    assert.match(result.stderr, /Invalid --web-port/);
  }
});

test('the equals form is accepted', () => {
  // ARRANGE / ACT: parsing succeeds, so the run gets as far as the credentials.
  const result = run(['--uid=dev-live-1', '--database=staging']);

  // ASSERT
  assert.equal(result.status, 2);
  assert.match(result.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
  assert.doesNotMatch(result.stderr, /Unknown option/);
});

test('a missing credentials variable is named', () => {
  const result = run(['--uid', 'dev-live-1']);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /GOOGLE_APPLICATION_CREDENTIALS/);
});

test("a credentials file from another project is refused, naming both", (t) => {
  const other = 'some-other-project';
  const path = credentialsFile(t, other);

  const result = run(['--uid', 'dev-live-1'], {
    GOOGLE_APPLICATION_CREDENTIALS: path,
  });

  assert.equal(result.status, 2);
  assert.match(result.stderr, new RegExp(other));
  assert.match(result.stderr, new RegExp(PROJECT_ID));
});

test('the printed command carries every define the app reads', () => {
  // ARRANGE
  const token = 'header.payload.signature';

  // ACT
  const command = devRunCommand({
    databaseId: 'staging',
    token,
    webPort: DEFAULT_WEB_PORT,
  });

  // ASSERT: one line, the pinned port, and the three defines.
  assert.doesNotMatch(command, /\n/);
  assert.ok(command.startsWith('flutter run '), command);
  assert.match(command, new RegExp(`-t ${ENTRYPOINT}`));
  assert.match(command, new RegExp(`--web-port=${DEFAULT_WEB_PORT}`));
  assert.match(command, /--dart-define=WT_DEV_BACKEND=live/);
  assert.match(command, /--dart-define=WT_FIRESTORE_DATABASE=staging/);
  assert.match(command, new RegExp(`--dart-define=WT_DEV_TOKEN=${token}`));
});

test('parseArgs defaults to the staging database and the pinned port', () => {
  assert.deepEqual(parseArgs(['--uid', 'dev-live-1']), {
    uid: 'dev-live-1',
    databaseId: DEFAULT_DATABASE_ID,
    webPort: DEFAULT_WEB_PORT,
    help: false,
  });
});

test('validateUid trims surrounding whitespace', () => {
  assert.equal(validateUid('  dev-live-1 '), 'dev-live-1');
});

test('validateDatabaseId accepts a named database and refuses production', () => {
  assert.equal(validateDatabaseId('staging'), 'staging');
  assert.throws(() => validateDatabaseId('(default)'), /production/);
  assert.throws(() => validateDatabaseId('abc'), /Invalid --database/);
});

test('validateWebPort returns a number', () => {
  assert.equal(validateWebPort('59922'), 59922);
  assert.throws(() => validateWebPort('http'), /Invalid --web-port/);
});
