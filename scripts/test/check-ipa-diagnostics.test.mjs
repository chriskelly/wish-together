import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  ENVIRONMENT_MARKER_PREFIX,
  missingMarkers,
  requiredMarkers,
} from '../check-ipa-diagnostics.mjs';

const CLI = fileURLToPath(new URL('../check-ipa-diagnostics.mjs', import.meta.url));
const DART_SOURCE = fileURLToPath(
  new URL('../../lib/core/logging/sentry_startup.dart', import.meta.url),
);
const DSN = 'https://key@o1.ingest.sentry.io/2';

function runCli(args) {
  return spawnSync(process.execPath, [CLI, ...args], { encoding: 'utf8' });
}

function withBundle(contents, run) {
  const directory = mkdtempSync(join(tmpdir(), 'ipa-diagnostics-'));
  try {
    const bundle = join(directory, 'App');
    writeFileSync(bundle, contents);
    return run(bundle);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('requires the DSN and the environment marker', () => {
  assert.deepEqual(requiredMarkers(DSN, 'testflight'), [
    DSN,
    `${ENVIRONMENT_MARKER_PREFIX}testflight`,
  ]);
});

test('requires only the DSN when no environment is given', () => {
  assert.deepEqual(requiredMarkers(DSN, undefined), [DSN]);
});

test('refuses an empty DSN', () => {
  assert.throws(() => requiredMarkers('  ', 'testflight'), /SENTRY_DSN/);
});

test('refuses a blank environment', () => {
  assert.throws(() => requiredMarkers(DSN, ' '), /environment/);
});

test('reports a marker that differs by one leading space', () => {
  const bundle = Buffer.from(`${ENVIRONMENT_MARKER_PREFIX} testflight`);

  assert.deepEqual(missingMarkers(bundle, [`${ENVIRONMENT_MARKER_PREFIX}testflight`]), [
    `${ENVIRONMENT_MARKER_PREFIX}testflight`,
  ]);
});

test('exits 0 when the binary embeds both markers', () => {
  const result = withBundle(`${DSN}\n${ENVIRONMENT_MARKER_PREFIX}testflight`, (bundle) =>
    runCli([bundle, DSN, 'testflight']),
  );

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /2 Sentry marker/);
});

test('exits 1 and names the missing marker', () => {
  const result = withBundle(DSN, (bundle) => runCli([bundle, DSN, 'testflight']));

  assert.equal(result.status, 1);
  assert.match(result.stderr, /wishtogether-sentry-environment=testflight/);
});

test('exits 0 for the DSN-only App Store path', () => {
  const result = withBundle(DSN, (bundle) => runCli([bundle, DSN]));

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /1 Sentry marker/);
});

test('exits 1 when the binary does not exist', () => {
  const result = runCli(['/nonexistent/App', DSN, 'testflight']);

  assert.equal(result.status, 1);
  assert.match(result.stderr, /cannot read the bundle/);
});

test('the marker constants match what the app emits', () => {
  const source = readFileSync(DART_SOURCE, 'utf8').replace(/\s+/g, ' ');

  assert.ok(
    source.includes(
      `const String sentryEnvironmentStampPrefix = '${ENVIRONMENT_MARKER_PREFIX}';`,
    ),
  );

  // The stamp must stay one compile-time literal made from the prefix and the
  // environment, or the lane greps for a value the binary cannot contain.
  // Either interpolation spelling is fine; only the composition matters.
  const stamp =
    /const String sentryEnvironmentStamp = ([^;]+);/.exec(source)?.[1] ?? '';
  assert.ok(stamp.includes('sentryEnvironmentStampPrefix'));
  assert.ok(stamp.includes('wtSentryEnvironment'));
});
