import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(new URL('../seed-demo.mjs', import.meta.url));

function run(...args) {
  return spawnSync(process.execPath, [SCRIPT, ...args], { encoding: 'utf8' });
}

test('refuses to run without --yes and names the default target', () => {
  const result = run();

  assert.equal(result.status, 2);
  assert.match(result.stderr, /without --yes/);
  assert.match(result.stderr, /"staging"/);
});

test('accepts the --database=id form and validates it', () => {
  const result = run('--yes', '--database=bad/id', '--viewer-uid', 'test-uid');

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Invalid --database/);
});

test('prints the resolved target without needing --yes', () => {
  const result = run('--print-target');

  assert.equal(result.status, 0);
  assert.equal(result.stdout.trim(), 'staging');
});

test('prints an explicit override, including the equals form', () => {
  const explicit = run('--print-target', '--database', '(default)');
  const equals = run('--print-target', '--database=staging-2');

  assert.equal(explicit.stdout.trim(), '(default)');
  assert.equal(equals.stdout.trim(), 'staging-2');
});

test('treats a following flag as a missing viewer uid', () => {
  const result = run(
    '--yes',
    '--database',
    'staging',
    '--viewer-uid',
    '--viewer-name',
    'Sasha',
  );

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Missing --viewer-uid/);
});

test('rejects a database id the app guard would reject', () => {
  for (const bad of ['abc', 'Staging']) {
    const result = run('--print-target', `--database=${bad}`);

    assert.equal(result.status, 2);
    assert.match(result.stderr, /Invalid --database/);
  }
});

test('rejects an unknown option instead of ignoring it', () => {
  const result = run('--yes', '--wat');

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Unknown option --wat/);
});

test('requires a viewer uid before touching credentials', () => {
  const result = run('--yes', '--database', 'staging');

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Missing --viewer-uid/);
});
